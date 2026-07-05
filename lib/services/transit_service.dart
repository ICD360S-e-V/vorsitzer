import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'logger_service.dart';
import 'http_client_factory.dart';

final _log = LoggerService();

/// A single nearby transit stop
class TransitStop {
  final String id;
  final String name;
  final int distance; // meters
  final String? platform;

  TransitStop({
    required this.id,
    required this.name,
    required this.distance,
    this.platform,
  });
}

/// A single departure from a stop
class Departure {
  final String line;
  final String direction;
  final DateTime plannedTime;
  final DateTime? realtimeTime;
  final int delay; // minutes
  final String? platform;
  final String productType; // bus, tram, train, etc.
  final String operator;
  final String stopName;

  Departure({
    required this.line,
    required this.direction,
    required this.plannedTime,
    this.realtimeTime,
    required this.delay,
    this.platform,
    required this.productType,
    required this.operator,
    required this.stopName,
  });

  /// Minutes until departure (from now, using realtime if available)
  int get minutesUntil {
    final departureTime = realtimeTime ?? plannedTime;
    return departureTime.difference(DateTime.now()).inMinutes;
  }

  /// Icon for product type
  String get icon {
    switch (productType) {
      case 'tram':
        return '🚊';
      case 'subway':
        return '🚇';
      case 'train':
      case 'regional':
        return '🚆';
      case 'suburban':
        return '🚈';
      default:
        return '🚌';
    }
  }

  /// Formatted departure time
  String get timeString {
    final t = realtimeTime ?? plannedTime;
    return '${t.hour}:${t.minute.toString().padLeft(2, '0')}';
  }
}

// ══════════════════════════════════════════════════════════════
// Trip search models — used by "Verbindung suchen" tab
// ══════════════════════════════════════════════════════════════

/// A location (stop, city, POI) returned by autocomplete
class TransitLocation {
  final String id;
  final String name;
  final String? type; // "stop", "locality", "poi"
  final double? lat;
  final double? lon;
  /// Which provider found this location — needed so `searchJourneys` uses the
  /// same one instead of `activeProvider` (server IP may be in a different region).
  final TransitProviderConfig? sourceProvider;

  TransitLocation({
    required this.id,
    required this.name,
    this.type,
    this.lat,
    this.lon,
    this.sourceProvider,
  });
}

/// A single leg of a journey (one vehicle segment or a walk)
class JourneyLeg {
  final String line;         // "S3", "134", "IC 2013", "Fußweg"
  final String direction;    // final destination shown on vehicle
  final String fromName;
  final String toName;
  final DateTime depTime;
  final DateTime arrTime;
  final int depDelay;
  final int arrDelay;
  final String? fromPlatform;
  final String? toPlatform;
  final String productType;  // bus, tram, train, suburban, walk
  final bool isWalk;

  JourneyLeg({
    required this.line,
    required this.direction,
    required this.fromName,
    required this.toName,
    required this.depTime,
    required this.arrTime,
    this.depDelay = 0,
    this.arrDelay = 0,
    this.fromPlatform,
    this.toPlatform,
    required this.productType,
    this.isWalk = false,
  });

  String get icon {
    if (isWalk) return '🚶';
    switch (productType) {
      case 'tram': return '🚊';
      case 'train':
      case 'regional': return '🚆';
      case 'suburban': return '🚈';
      default: return '🚌';
    }
  }
}

class _CachedFacilities {
  final List<StationFacility> facilities;
  final DateTime at;
  _CachedFacilities(this.facilities, this.at);
}

class _CachedDepartures {
  final List<Departure> departures;
  final DateTime at;
  _CachedDepartures(this.departures, this.at);
}

/// A station facility — elevator (Aufzug) or escalator (Fahrtreppe) with
/// live operational status. Sourced from `v6.db.transport.rest`, which
/// wraps DB's FaSta (Facility Status) service.
class StationFacility {
  final String description;   // "Aufzug zu Gleis 3-4"
  final String type;          // "ELEVATOR" | "ESCALATOR"
  final String status;        // "ACTIVE" | "INACTIVE" | "UNKNOWN"
  final String? reason;       // "Wartung", "Defekt", ... — optional

  StationFacility({
    required this.description,
    required this.type,
    required this.status,
    this.reason,
  });

  bool get isElevator => type == 'ELEVATOR' || type.toLowerCase().contains('aufzug');
  bool get isEscalator => type == 'ESCALATOR' || type.toLowerCase().contains('fahrtreppe');
  bool get isWorking => status == 'ACTIVE';
  bool get isBroken => status == 'INACTIVE';

  String get icon => isElevator ? '🛗' : (isEscalator ? '↕️' : '⚙️');
}

/// A full journey option (departure → destination) with all legs
class Journey {
  final List<JourneyLeg> legs;
  final DateTime depTime;
  final DateTime arrTime;

  Journey({required this.legs, required this.depTime, required this.arrTime});

  int get transfers => legs.where((l) => !l.isWalk).length - 1;
  Duration get duration => arrTime.difference(depTime);
}

/// Where the last position fix came from — used for UI transparency
/// (green dot = precise GNSS, orange = coarse cell/Wi-Fi, red = IP-only).
enum LocationSource {
  none,
  gnss,              // raw GNSS chip via LocationManager (best)
  fusedLocation,     // Google Play Services (Wi-Fi + cell + GNSS)
  cached,            // getLastKnownPosition
  ipFallback,        // ipapi.co (city-level ~5-20km)
  cityGeocode,       // geocoded from `city` fallback
}

// ══════════════════════════════════════════════════════════════
// Transit Providers — auto-detected by GPS coordinates
// ══════════════════════════════════════════════════════════════

enum TransitApiType { efa, hafas }

enum TransitProviderType {
  ding, mvv, vvs, vrn, vrr, kvv, vvo, vgn, naldo,
  saarvv, vbb, nvv, rmv, nahsh, insa, vbn, avv,
}

class TransitProviderConfig {
  final TransitProviderType type;
  final TransitApiType api;
  final String name;        // short name
  final String displayName; // shown in UI footer
  final String baseUrl;     // EFA base or HAFAS mgate endpoint
  final double minLat, maxLat, minLon, maxLon; // bounding box
  // HAFAS-only — public config extracted from official apps (hafas-client community)
  final String? hafasAid;
  final String? hafasClientId;
  final String? hafasClientVersion;   // may be null for WEB clients (e.g. RMV)
  final String? hafasClientName;
  final String hafasClientType;       // "AND" (Android), "IPH" (iPhone), "WEB"
  final String hafasVer;              // protocol version ("1.30", "1.40", "1.42", "1.44")
  final String? hafasExt;             // optional ext field (e.g. "RMV.1")

  const TransitProviderConfig({
    required this.type,
    required this.api,
    required this.name,
    required this.displayName,
    required this.baseUrl,
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
    this.hafasAid,
    this.hafasClientId,
    this.hafasClientVersion,
    this.hafasClientName,
    this.hafasClientType = 'AND',
    this.hafasVer = '1.40',
    this.hafasExt,
  });

  bool containsCoord(double lat, double lon) {
    return lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon;
  }
}

/// All supported transit providers with geographic bounding boxes.
/// Order matters — more specific (smaller) boxes come first so overlapping
/// regions resolve to the tighter provider (e.g. Stuttgart → VVS, not RMV).
/// HAFAS AIDs are public tokens extracted from official mobile apps.
const _providers = [
  // ── EFA (MENTZ) — no auth required ─────────────────────────────
  TransitProviderConfig(
    type: TransitProviderType.ding, api: TransitApiType.efa,
    name: 'DING', displayName: 'DING (Donau-Iller-Nahverkehrsverbund)',
    baseUrl: 'https://ding.eu/mobile',
    minLat: 47.8, maxLat: 48.8, minLon: 9.3, maxLon: 10.5,
  ),
  TransitProviderConfig(
    type: TransitProviderType.mvv, api: TransitApiType.efa,
    name: 'MVV', displayName: 'MVV (Münchner Verkehrs- und Tarifverbund)',
    baseUrl: 'https://efa.mvv-muenchen.de/ng',
    minLat: 47.5, maxLat: 48.6, minLon: 10.8, maxLon: 12.5,
  ),
  TransitProviderConfig(
    type: TransitProviderType.vvs, api: TransitApiType.efa,
    name: 'VVS', displayName: 'VVS (Verkehrs- und Tarifverbund Stuttgart)',
    baseUrl: 'https://www3.vvs.de/mngvvs',
    minLat: 48.5, maxLat: 49.2, minLon: 8.8, maxLon: 10.0,
  ),
  TransitProviderConfig(
    type: TransitProviderType.kvv, api: TransitApiType.efa,
    name: 'KVV', displayName: 'KVV (Karlsruher Verkehrsverbund)',
    baseUrl: 'https://projekte.kvv-efa.de/sl3-alone',
    minLat: 48.8, maxLat: 49.3, minLon: 8.2, maxLon: 8.7,
  ),
  TransitProviderConfig(
    // naldo shares statewide Baden-Württemberg EFA (Mentz)
    type: TransitProviderType.naldo, api: TransitApiType.efa,
    name: 'naldo', displayName: 'naldo (Verkehrsverbund Neckar-Alb-Donau via efa-bw)',
    baseUrl: 'https://www.efa-bw.de/nvbw',
    minLat: 47.9, maxLat: 48.6, minLon: 8.7, maxLon: 9.6,
  ),
  TransitProviderConfig(
    type: TransitProviderType.vrn, api: TransitApiType.efa,
    name: 'VRN', displayName: 'VRN (Verkehrsverbund Rhein-Neckar)',
    baseUrl: 'https://www.vrn.de/mngvrn',
    minLat: 49.0, maxLat: 49.9, minLon: 8.0, maxLon: 9.4,
  ),
  TransitProviderConfig(
    type: TransitProviderType.vgn, api: TransitApiType.efa,
    name: 'VGN', displayName: 'VGN (Verkehrsverbund Großraum Nürnberg)',
    baseUrl: 'https://efa.vgn.de/vgnExt_oeffi',
    minLat: 49.0, maxLat: 50.3, minLon: 10.5, maxLon: 12.0,
  ),
  TransitProviderConfig(
    type: TransitProviderType.vrr, api: TransitApiType.efa,
    name: 'VRR', displayName: 'VRR (Verkehrsverbund Rhein-Ruhr)',
    baseUrl: 'https://efa.vrr.de/vrr',
    minLat: 51.0, maxLat: 51.8, minLon: 6.4, maxLon: 7.7,
  ),
  TransitProviderConfig(
    type: TransitProviderType.vvo, api: TransitApiType.efa,
    name: 'VVO', displayName: 'VVO (Verkehrsverbund Oberelbe Dresden)',
    baseUrl: 'https://efa.vvo-online.de/std3',
    minLat: 50.5, maxLat: 51.4, minLon: 13.2, maxLon: 14.3,
  ),

  // ── HAFAS (HaCon) — public AIDs from official apps ─────────────
  TransitProviderConfig(
    type: TransitProviderType.saarvv, api: TransitApiType.hafas,
    name: 'saarVV', displayName: 'saarVV (Saarländischer Verkehrsverbund)',
    baseUrl: 'https://saarfahrplan.de/bin/mgate.exe',
    hafasClientId: 'ZPS-SAAR', hafasClientVersion: '1000070', hafasClientName: 'Saarfahrplan',
    // saarVV AID injected via --dart-define at build time (see _resolveAid)
    minLat: 49.0, maxLat: 49.7, minLon: 6.3, maxLon: 7.5,
  ),
  TransitProviderConfig(
    type: TransitProviderType.nvv, api: TransitApiType.hafas,
    name: 'NVV', displayName: 'NVV (Nordhessischer Verkehrsverbund)',
    baseUrl: 'https://auskunft.nvv.de/auskunft/bin/app/mgate.exe',
    hafasAid: 'Kt8eNOH7qjVeSxNA',
    hafasClientId: 'NVV', hafasClientVersion: '5000300', hafasClientName: 'NVV Mobil',
    minLat: 50.6, maxLat: 51.6, minLon: 8.5, maxLon: 10.4,
  ),
  TransitProviderConfig(
    type: TransitProviderType.rmv, api: TransitApiType.hafas,
    name: 'RMV', displayName: 'RMV (Rhein-Main-Verkehrsverbund)',
    baseUrl: 'https://www.rmv.de/auskunft/bin/jp/mgate.exe',
    hafasAid: 'x0k4ZR33ICN9CWmj',
    hafasClientId: 'RMV', hafasClientName: 'webapp',
    hafasClientType: 'WEB', hafasVer: '1.44', hafasExt: 'RMV.1',
    minLat: 49.5, maxLat: 51.6, minLon: 7.8, maxLon: 10.2,
  ),
  TransitProviderConfig(
    type: TransitProviderType.nahsh, api: TransitApiType.hafas,
    name: 'NAH.SH', displayName: 'NAH.SH (Nahverkehr Schleswig-Holstein)',
    baseUrl: 'https://nahsh.hafas.cloud/gate',
    hafasAid: 'r0Ot9FLFNAFxijLW',
    hafasClientId: 'NAHSH', hafasClientVersion: '3000700', hafasClientName: 'NAHSHPROD',
    hafasClientType: 'IPH', hafasVer: '1.30',
    minLat: 53.3, maxLat: 55.1, minLon: 8.4, maxLon: 11.3,
  ),
  TransitProviderConfig(
    type: TransitProviderType.insa, api: TransitApiType.hafas,
    name: 'INSA', displayName: 'INSA / NASA (Sachsen-Anhalt)',
    baseUrl: 'https://reiseauskunft.insa.de/bin/mgate.exe',
    hafasAid: 'nasa-apps',
    hafasClientId: 'NASA', hafasClientVersion: '4000200', hafasClientName: 'nasaPROD',
    hafasClientType: 'IPH', hafasVer: '1.44',
    minLat: 50.9, maxLat: 53.1, minLon: 10.5, maxLon: 13.2,
  ),
  TransitProviderConfig(
    type: TransitProviderType.vbn, api: TransitApiType.hafas,
    name: 'VBN', displayName: 'VBN (Verkehrsverbund Bremen/Niedersachsen)',
    baseUrl: 'https://fahrplaner.vbn.de/bin/mgate.exe',
    hafasAid: 'kaoxIXLn03zCr2KR',
    hafasClientId: 'VBN', hafasClientVersion: '6000000', hafasClientName: 'vbn',
    hafasClientType: 'IPH', hafasVer: '1.42',
    minLat: 52.0, maxLat: 54.0, minLon: 7.0, maxLon: 11.0,
  ),
  TransitProviderConfig(
    // AVV Aachen uses HAFAS, not EFA (per transport-apis registry)
    type: TransitProviderType.avv, api: TransitApiType.hafas,
    name: 'AVV', displayName: 'AVV (Aachener Verkehrsverbund)',
    baseUrl: 'https://auskunft.avv.de/bin/mgate.exe',
    hafasAid: '4vV1AcH3N511icH',
    hafasClientId: 'AVV_AACHEN', hafasClientVersion: '14000200', hafasClientName: 'AVV_AACHEN',
    minLat: 50.6, maxLat: 51.0, minLon: 5.9, maxLon: 6.5,
  ),
  TransitProviderConfig(
    type: TransitProviderType.vbb, api: TransitApiType.hafas,
    name: 'VBB', displayName: 'VBB (Verkehrsverbund Berlin-Brandenburg)',
    baseUrl: 'https://fahrinfo.vbb.de/bin/mgate.exe',
    hafasAid: 'hafas-vbb-webapp',
    hafasClientId: 'VBB', hafasClientVersion: '10000', hafasClientName: 'VBB',
    minLat: 51.3, maxLat: 53.6, minLon: 11.2, maxLon: 14.8,
  ),
];

/// Transit service with multi-provider support.
/// Singleton — shared between dashboard (departures + dialog) and
/// terminverwaltung (route calculation for termin cards).
///
/// Providers auto-detected by GPS coordinates. GPS uses a layered strategy:
/// cached fix → high-accuracy single shot (8s) → medium (4s) → IP fallback →
/// continuous `getPositionStream` with 100m distanceFilter.
class TransitService {
  static final TransitService _instance = TransitService._internal();
  factory TransitService() => _instance;
  TransitService._internal();

  Timer? _refreshTimer;
  StreamSubscription<Position>? _positionSub;
  double? _latitude;
  double? _longitude;
  String city = '';
  bool _useGps = false;

  List<TransitStop> nearbyStops = [];
  List<Departure> departures = [];
  bool isLoading = false;
  String? locationError;

  /// Accuracy (meters) of the last GPS/IP fix. null = unknown.
  /// < 50m: excellent GNSS fix
  /// 50-200m: good FusedLocation (Wi-Fi + cell + GNSS)
  /// 200-500m: acceptable but coarse
  /// > 500m: cell-tower or IP fallback — bus stops within 1km won't be found
  double? lastAccuracy;

  /// Where the last position came from — for UI transparency.
  LocationSource lastSource = LocationSource.none;

  /// Current coordinates (for sharing with weather service)
  double? get latitude => _latitude;
  double? get longitude => _longitude;

  /// Currently active provider (detected from GPS)
  TransitProviderConfig? activeProvider;

  // Callbacks
  void Function(List<Departure>)? onDeparturesUpdate;
  /// Called when GPS location changes significantly (new city)
  void Function(double lat, double lon, String city)? onLocationChanged;

  final http.Client _client = IOClient(HttpClientFactory.createDefaultHttpClient());

  /// Actual city name from GPS reverse geocoding
  String? gpsCity;

  /// Start transit monitoring — tries GPS first, falls back to city geocoding
  Future<void> start(String cityName) async {
    city = cityName;

    // Try GPS location first
    final gpsSuccess = await _getGpsLocation();
    if (gpsSuccess) {
      _useGps = true;
      _log.info('Transit: Using GPS location ($_latitude, $_longitude)', tag: 'TRANSIT');
      // Reverse geocode to get actual city name
      await _reverseGeocode();
    } else if (cityName.isNotEmpty) {
      // Fallback: geocode city name
      final geocodeSuccess = await _geocodeCity(city);
      if (!geocodeSuccess) {
        _log.error('Transit: Could not determine location', tag: 'TRANSIT');
        return;
      }
      _log.info('Transit: Using city geocode "$city" ($_latitude, $_longitude)', tag: 'TRANSIT');
    } else {
      _log.info('Transit: No location available, skipping', tag: 'TRANSIT');
      return;
    }

    // Detect provider based on coordinates
    _detectProvider();

    // Initial fetch
    await fetchDepartures();

    // Continuous stream: fires when user moves >=100m (idiomatic for transit app)
    if (_useGps) _startPositionStream();

    // Periodic departure refresh every 60s (GPS handled by stream)
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      await fetchDepartures();
    });
  }

  void _startPositionStream() {
    _positionSub?.cancel();
    final settings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 100,
            forceLocationManager: false, // keep FusedLocationProvider (Wi-Fi/cell)
            intervalDuration: const Duration(seconds: 15),
          )
        : Platform.isIOS || Platform.isMacOS
            ? AppleSettings(
                accuracy: LocationAccuracy.high,
                distanceFilter: 100,
                activityType: ActivityType.otherNavigation,
                pauseLocationUpdatesAutomatically: true,
              )
            : const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 100);

    _positionSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) async {
        final oldLat = _latitude;
        final oldLon = _longitude;
        _latitude = pos.latitude;
        _longitude = pos.longitude;
        _log.debug('Transit: Stream update = $_latitude, $_longitude', tag: 'TRANSIT');
        if (oldLat != null && oldLon != null) {
          final dist = _distanceKm(oldLat, oldLon, _latitude!, _longitude!);
          if (dist > 2.0) {
            _log.info('Transit: Moved ${dist.toStringAsFixed(1)}km, re-geocoding', tag: 'TRANSIT');
            await _reverseGeocode();
            _detectProvider();
            onLocationChanged?.call(_latitude!, _longitude!, gpsCity ?? city);
          }
        }
        await fetchDepartures();
      },
      onError: (e) {
        _log.debug('Transit: Position stream error: $e', tag: 'TRANSIT');
      },
    );
  }

  void stop() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _positionSub?.cancel();
    _positionSub = null;
    _log.info('Transit: Stopped', tag: 'TRANSIT');
  }

  /// Map of provider → set of city/Landkreis names it serves.
  /// Compiled from each Verkehrsverbund's official coverage page — used as
  /// the primary match signal before falling back to bounding-box geometry.
  /// All names lowercased; matching is substring both ways so "Neu-Ulm"
  /// still matches "neu-ulm" and vice versa.
  static const Map<TransitProviderType, Set<String>> _providerCities = {
    TransitProviderType.ding: {
      'ulm', 'neu-ulm', 'ehingen', 'blaubeuren', 'laichingen', 'illertissen',
      'vöhringen', 'senden', 'weißenhorn', 'riedlingen', 'biberach',
      'alb-donau-kreis', 'landkreis neu-ulm', 'landkreis biberach',
    },
    TransitProviderType.mvv: {
      'münchen', 'munich', 'freising', 'erding', 'ebersberg', 'dachau',
      'fürstenfeldbruck', 'starnberg', 'wolfratshausen', 'bad tölz', 'miesbach',
      'garmisch-partenkirchen',
    },
    TransitProviderType.vvs: {
      'stuttgart', 'ludwigsburg', 'böblingen', 'sindelfingen', 'esslingen',
      'nürtingen', 'göppingen', 'waiblingen', 'kirchheim unter teck',
      'rems-murr-kreis', 'landkreis göppingen',
    },
    TransitProviderType.kvv: {
      'karlsruhe', 'bruchsal', 'ettlingen', 'rastatt', 'baden-baden', 'bretten',
      'enzkreis', 'landkreis karlsruhe',
    },
    TransitProviderType.naldo: {
      'tübingen', 'reutlingen', 'rottenburg', 'balingen', 'sigmaringen',
      'metzingen', 'zollernalbkreis', 'landkreis tübingen',
    },
    TransitProviderType.vrn: {
      'mannheim', 'heidelberg', 'ludwigshafen', 'speyer', 'frankenthal',
      'weinheim', 'sinsheim', 'neustadt', 'rhein-neckar-kreis',
      'rhein-pfalz-kreis', 'bergstraße',
    },
    TransitProviderType.vgn: {
      'nürnberg', 'nurnberg', 'fürth', 'erlangen', 'bamberg', 'ansbach',
      'schwabach', 'forchheim', 'nürnberger land', 'roth',
    },
    TransitProviderType.avv: {
      'aachen', 'düren', 'heinsberg', 'erkelenz', 'alsdorf', 'herzogenrath',
      'stolberg', 'eschweiler',
    },
    TransitProviderType.vrr: {
      'essen', 'duisburg', 'dortmund', 'düsseldorf', 'wuppertal', 'bochum',
      'gelsenkirchen', 'oberhausen', 'krefeld', 'mönchengladbach', 'hagen',
      'solingen', 'neuss', 'mülheim', 'remscheid', 'moers', 'bottrop',
      'recklinghausen', 'herne', 'ruhr', 'rhein-ruhr',
    },
    TransitProviderType.vvo: {
      'dresden', 'meißen', 'radebeul', 'freital', 'pirna', 'kamenz',
      'bautzen', 'sächsische schweiz',
    },
    TransitProviderType.saarvv: {
      'saarland', 'saarbrücken', 'saarbrucken', 'neunkirchen', 'völklingen',
      'homburg', 'st. wendel', 'merzig', 'saarlouis', 'blieskastel',
      'dillingen', 'sulzbach',
    },
    TransitProviderType.nvv: {
      'kassel', 'fulda', 'bad hersfeld', 'marburg', 'wolfhagen', 'rotenburg',
      'werra-meißner', 'waldeck-frankenberg', 'hersfeld-rotenburg',
      'schwalm-eder',
    },
    TransitProviderType.rmv: {
      'frankfurt am main', 'frankfurt', 'wiesbaden', 'mainz', 'offenbach',
      'darmstadt', 'hanau', 'bad homburg', 'aschaffenburg', 'limburg',
      'rüsselsheim', 'gießen', 'wetzlar',
    },
    TransitProviderType.nahsh: {
      'schleswig-holstein', 'kiel', 'lübeck', 'flensburg', 'neumünster',
      'norderstedt', 'elmshorn', 'pinneberg', 'itzehoe', 'rendsburg',
      'heide', 'husum',
    },
    TransitProviderType.insa: {
      'sachsen-anhalt', 'magdeburg', 'halle', 'dessau', 'wittenberg',
      'bernburg', 'naumburg', 'wernigerode', 'merseburg', 'bitterfeld',
      'stendal', 'salzwedel',
    },
    TransitProviderType.vbn: {
      'bremen', 'bremerhaven', 'osnabrück', 'oldenburg', 'wilhelmshaven',
      'cuxhaven', 'delmenhorst', 'nordenham', 'vechta', 'diepholz',
    },
    TransitProviderType.vbb: {
      'berlin', 'brandenburg', 'potsdam', 'cottbus', 'frankfurt (oder)',
      'frankfurt/oder', 'eberswalde', 'oranienburg', 'bernau', 'strausberg',
      'königs wusterhausen', 'ludwigsfelde', 'falkensee',
    },
  };

  /// Detect which transit provider best matches the current location.
  ///
  /// Three-step:
  ///   1. **City name match** — if reverse geocode gave us `gpsCity`, look it
  ///      up in the per-provider city catalog. Most accurate signal — knows
  ///      that Göppingen belongs to VVS even though it's inside DING's box.
  ///   2. **Bounding-box + nearest centre** — if no name match, use geometry.
  ///      Overlapping boxes resolved by nearest bounding-box centre so DING
  ///      no longer wins by list order.
  ///   3. **Nearest-centre-under-150 km fallback** — for uncovered cities
  ///      like Rostock or Chemnitz. Beyond 150 km, leave `activeProvider` null
  ///      and trip search falls through to bahn.de.
  void _detectProvider() {
    if (_latitude == null || _longitude == null) return;
    final lat = _latitude!;
    final lon = _longitude!;

    // Step 1: city name match
    if (gpsCity != null && gpsCity!.isNotEmpty) {
      final cityLower = gpsCity!.toLowerCase();
      for (final p in _providers) {
        final cities = _providerCities[p.type];
        if (cities == null) continue;
        for (final c in cities) {
          if (cityLower.contains(c) || c.contains(cityLower)) {
            activeProvider = p;
            _log.info('Transit: gpsCity "$gpsCity" matches ${p.name} (via "$c")', tag: 'TRANSIT');
            return;
          }
        }
      }
      _log.info('Transit: gpsCity "$gpsCity" not in any provider catalog, using geometry', tag: 'TRANSIT');
    }

    double centerDistKm(TransitProviderConfig p) {
      final cLat = (p.minLat + p.maxLat) / 2;
      final cLon = (p.minLon + p.maxLon) / 2;
      return _distanceKm(lat, lon, cLat, cLon);
    }

    // Step 2: containing providers, pick nearest centre
    final containing = _providers.where((p) => p.containsCoord(lat, lon)).toList();
    if (containing.isNotEmpty) {
      containing.sort((a, b) => centerDistKm(a).compareTo(centerDistKm(b)));
      activeProvider = containing.first;
      _log.info(
        'Transit: Provider ${activeProvider!.name} '
        '(bounding-box match, ${containing.length} candidate${containing.length > 1 ? "s" : ""})',
        tag: 'TRANSIT',
      );
      return;
    }

    // Step 3: no box contains — nearest centre within 150 km
    final sorted = List<TransitProviderConfig>.from(_providers)
      ..sort((a, b) => centerDistKm(a).compareTo(centerDistKm(b)));
    final nearest = sorted.first;
    final distKm = centerDistKm(nearest);
    if (distKm < 150) {
      activeProvider = nearest;
      _log.info(
        'Transit: nearest provider ${nearest.name} (${distKm.toStringAsFixed(0)} km) for ($lat, $lon)',
        tag: 'TRANSIT',
      );
      return;
    }

    activeProvider = null;
    _log.info(
      'Transit: ${distKm.toStringAsFixed(0)} km from nearest provider — bahn.de fallback',
      tag: 'TRANSIT',
    );
  }

  /// Force UTF-8 decoding of HTTP body regardless of `Content-Type` header.
  /// EFA (DING/MVV/VVS/...) returns `text/html` without a charset declaration,
  /// so `response.body` defaults to latin-1 → German umlauts appear as `Ã¶`,
  /// `Ã¤`, `ÃŸ`. All EFA/HAFAS/bahn.de responses are actually UTF-8.
  String _decodeUtf8(http.Response r) => utf8.decode(r.bodyBytes, allowMalformed: true);

  /// Get current GPS position — layered strategy:
  ///   1. Cached last-known (instant, 0ms)
  ///   2. Fresh high-accuracy fix (8s max) — parallel with IP fallback
  ///   3. Fresh medium-accuracy fix (4s max)
  ///   4. IP-based geolocation via ipapi.co (city-level, works when no GNSS)
  ///   5. Previous known position
  Future<bool> _getGpsLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      _log.info('Transit: GPS permission = $permission', tag: 'TRANSIT');

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _log.info('Transit: Location permission denied → IP fallback', tag: 'TRANSIT');
          return await _ipGeolocate();
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _log.info('Transit: Location permission denied forever → IP fallback', tag: 'TRANSIT');
        return await _ipGeolocate();
      }

      // Strategy 1: instant cached fix (best seed while fresh acquisition runs)
      Position? cached;
      try {
        cached = await Geolocator.getLastKnownPosition();
        if (cached != null) {
          _latitude = cached.latitude;
          _longitude = cached.longitude;
          _log.info('Transit: Cached GPS = $_latitude, $_longitude', tag: 'TRANSIT');
        }
      } catch (_) {}

      // Strategy 2: FusedLocationProvider high accuracy (Wi-Fi + cell + GNSS).
      // Longer timeout (15s) — first GNSS fix can take 10-20s from cold start.
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: Platform.isAndroid
              ? AndroidSettings(
                  accuracy: LocationAccuracy.high,
                  forceLocationManager: false, // FusedLocationProvider
                )
              : Platform.isIOS || Platform.isMacOS
                  ? AppleSettings(accuracy: LocationAccuracy.high)
                  : const LocationSettings(accuracy: LocationAccuracy.high),
        ).timeout(const Duration(seconds: 15));
        _log.info('Transit: FusedLocation high = ${position.latitude}, ${position.longitude} (accuracy ${position.accuracy.toStringAsFixed(0)}m)', tag: 'TRANSIT');
        // Accept only tight fixes (< 100m) — the whole point is finding bus
        // stops within walking distance. A 500m fix means we can't distinguish
        // which side of a block the user is on.
        // 300m is the useful cutoff — EFA returns correct nearby stops up to
        // ~300m offset (verified live). Below 100m = perfect, 100-300m still
        // resolves the right stops just at fractional distance.
        if (position.accuracy < 300) {
          _latitude = position.latitude;
          _longitude = position.longitude;
          lastAccuracy = position.accuracy;
          lastSource = LocationSource.fusedLocation;
          locationError = null;
          return true;
        }
        _log.info('Transit: high fix too coarse (${position.accuracy.toStringAsFixed(0)}m) — trying raw GNSS', tag: 'TRANSIT');
        // Keep this fix as tentative — better than nothing if raw GNSS fails.
        _latitude = position.latitude;
        _longitude = position.longitude;
        lastAccuracy = position.accuracy;
        lastSource = LocationSource.fusedLocation;
      } catch (e) {
        _log.debug('Transit: High accuracy failed/timeout: $e', tag: 'TRANSIT');
      }

      // Strategy 2b (Android only): force raw LocationManager / GNSS chip.
      // Bypasses Google Play Services — some tablets (Samsung especially) get
      // stuck on cell-tower fix when FusedLocation is used. Raw GNSS is slower
      // to lock but gives real GPS coordinates.
      if (Platform.isAndroid) {
        try {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: AndroidSettings(
              accuracy: LocationAccuracy.best,
              forceLocationManager: true, // raw LocationManager (GNSS)
            ),
          ).timeout(const Duration(seconds: 20));
          _log.info('Transit: Raw GNSS = ${position.latitude}, ${position.longitude} (accuracy ${position.accuracy.toStringAsFixed(0)}m)', tag: 'TRANSIT');
          if (position.accuracy < 300) {
            _latitude = position.latitude;
            _longitude = position.longitude;
            lastAccuracy = position.accuracy;
            lastSource = LocationSource.gnss;
            locationError = null;
            return true;
          }
        } catch (e) {
          _log.debug('Transit: Raw GNSS failed/timeout: $e', tag: 'TRANSIT');
        }
      }

      // Strategy 3: medium accuracy — quicker to lock, wider tolerance
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: Platform.isAndroid
              ? AndroidSettings(accuracy: LocationAccuracy.medium, forceLocationManager: false)
              : const LocationSettings(accuracy: LocationAccuracy.medium),
        ).timeout(const Duration(seconds: 5));
        _latitude = position.latitude;
        _longitude = position.longitude;
        locationError = null;
        lastAccuracy = position.accuracy;
        lastSource = LocationSource.fusedLocation;
        _log.info('Transit: Fresh GPS (medium) = $_latitude, $_longitude (accuracy ${position.accuracy.toStringAsFixed(0)}m)', tag: 'TRANSIT');
        return true;
      } catch (e) {
        _log.debug('Transit: Medium accuracy failed: $e', tag: 'TRANSIT');
      }

      // Strategy 4: if we have any cached (even stale) fix, use it
      if (cached != null && cached.latitude != 0.0) {
        locationError = null;
        lastAccuracy = cached.accuracy;
        lastSource = LocationSource.cached;
        _log.info('Transit: Using stale cached fix', tag: 'TRANSIT');
        return true;
      }

      // Strategy 5: keep tentative coarse fix if we got one from Strategy 2
      if (_latitude != null && _longitude != null) {
        _log.info('Transit: Using coarse fix from strategy 2 = $_latitude, $_longitude', tag: 'TRANSIT');
        return true;
      }

      // Strategy 6: IP fallback — city-level, LAST resort
      if (await _ipGeolocate()) return true;

      // Strategy 6: keep last known
      if (_latitude != null && _longitude != null) {
        _log.info('Transit: Keeping previous position = $_latitude, $_longitude', tag: 'TRANSIT');
        return true;
      }

      locationError = 'Standort nicht verfügbar';
      return false;
    } catch (e) {
      _log.error('Transit: GPS strategy crashed: $e', tag: 'TRANSIT');
      if (_latitude != null && _longitude != null) return true;
      return await _ipGeolocate();
    }
  }

  /// IP-based geolocation fallback via ipapi.co (HTTPS, no key, ~1000/day).
  /// City-level accuracy (5–20 km) — enough to pick a default provider/station.
  /// Essential on Linux Flatpak (GeoClue2 sandbox), Windows without GNSS, macOS.
  Future<bool> _ipGeolocate() async {
    try {
      final response = await _client.get(
        Uri.parse('https://ipapi.co/json/'),
        headers: {'Accept': 'application/json', 'User-Agent': 'ICD360S-eV-App/1.0'},
      ).timeout(const Duration(seconds: 3));
      if (response.statusCode != 200) return false;
      final data = jsonDecode(_decodeUtf8(response));
      final lat = (data['latitude'] as num?)?.toDouble();
      final lon = (data['longitude'] as num?)?.toDouble();
      final ipCity = data['city']?.toString();
      if (lat == null || lon == null) return false;
      _latitude = lat;
      _longitude = lon;
      if (ipCity != null && ipCity.isNotEmpty) gpsCity = ipCity;
      locationError = null;
      lastAccuracy = 10000; // ~10 km typical for IP geolocation
      lastSource = LocationSource.ipFallback;
      _log.info('Transit: IP geolocation → $lat, $lon ($ipCity)', tag: 'TRANSIT');
      return true;
    } catch (e) {
      _log.debug('Transit: IP geolocation failed: $e', tag: 'TRANSIT');
      return false;
    }
  }

  /// Haversine distance in km between two GPS points
  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0; // Earth radius in km
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// Reverse geocode GPS coordinates → city name (Nominatim / OpenStreetMap)
  Future<void> _reverseGeocode() async {
    if (_latitude == null || _longitude == null) return;
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=$_latitude&lon=$_longitude&format=json&accept-language=de',
      );
      final response = await _client.get(uri, headers: {
        'User-Agent': 'ICD360S-eV-App/1.0',
      }).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(_decodeUtf8(response));
        final address = data['address'];
        if (address != null) {
          final name = address['city'] ?? address['town'] ?? address['village'] ?? address['municipality'];
          if (name != null) {
            gpsCity = name.toString();
            _log.info('Transit: Reverse geocoded → $gpsCity', tag: 'TRANSIT');
          }
        }
      }
    } catch (e) {
      _log.error('Transit: Reverse geocode failed: $e', tag: 'TRANSIT');
    }
  }

  /// Geocode city name to lat/lon (fallback)
  Future<bool> _geocodeCity(String city) async {
    try {
      final uri = Uri.parse(
        'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(city)}&count=1&language=de&format=json',
      );
      final response = await _client.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(_decodeUtf8(response));
        final results = data['results'] as List?;
        if (results != null && results.isNotEmpty) {
          _latitude = (results[0]['latitude'] as num).toDouble();
          _longitude = (results[0]['longitude'] as num).toDouble();
          return true;
        }
      }
      return false;
    } catch (e) {
      _log.error('Transit: Geocoding failed: $e', tag: 'TRANSIT');
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // FETCH DEPARTURES — dispatches to correct provider
  // ══════════════════════════════════════════════════════════════

  /// Fetch departures using the detected provider
  Future<void> fetchDepartures() async {
    if (_latitude == null || _longitude == null) return;

    isLoading = true;

    try {
      final provider = activeProvider;
      if (provider == null) {
        // Uncovered region — no local provider knows this coord. Skip local
        // fetch; the Verbindungssuche tab still works via bahn.de fallback.
        _log.info('Transit: fetchDepartures skipped — no local provider active', tag: 'TRANSIT');
        nearbyStops = [];
        departures = [];
      } else if (provider.api == TransitApiType.hafas) {
        await _fetchHafasDepartures();
      } else {
        await _fetchEfaDepartures(baseUrl: '${provider.baseUrl}/XSLT_DM_REQUEST');
      }

      // If any of the nearby stops is a mainline station (name contains
      // "Hbf"/"Hauptbahnhof"/"Bahnhof"), the local EFA/HAFAS provider likely
      // has only its buses+trams for that stop — no DB long-distance trains.
      // Merge in DB departures from transport.rest so the user sees ICE/IC/RE/RB.
      await _augmentWithDbRailDepartures();
    } catch (e) {
      _log.error('Transit: Fetch failed: $e', tag: 'TRANSIT');
    }

    isLoading = false;
    onDeparturesUpdate?.call(departures);
  }

  /// For every visible stop whose name matches a mainline station pattern,
  /// fetch DB (HAFAS via transport.rest) departures in parallel and merge them.
  Future<void> _augmentWithDbRailDepartures() async {
    if (nearbyStops.isEmpty) return;
    final railwayStops = nearbyStops.where((s) {
      final n = s.name.toLowerCase();
      return n.contains('hbf') || n.contains('hauptbahnhof') || n.contains('bahnhof');
    }).toList();
    if (railwayStops.isEmpty) return;

    _log.info('Transit: augmenting ${railwayStops.length} railway stops with DB data', tag: 'TRANSIT');
    final futures = railwayStops.map((s) => fetchDbDepartures(s.name)).toList();
    final results = await Future.wait(futures);

    // De-dup by (line, direction, plannedTime, stopName) so we don't stack the
    // same tram twice when EFA + DB both report it.
    final seen = <String>{};
    for (final d in departures) {
      seen.add('${d.line}|${d.direction}|${d.plannedTime.toIso8601String()}|${d.stopName}');
    }
    for (int i = 0; i < railwayStops.length; i++) {
      final stopName = railwayStops[i].name;
      for (final dbDep in results[i]) {
        // Keep DB's rail entries only — DB feeds also carry buses that EFA
        // already reported. This avoids duplicates and clutters.
        if (dbDep.productType == 'bus') continue;
        // Rewrite stopName to match the local EFA one (short form)
        final dep = Departure(
          line: dbDep.line,
          direction: dbDep.direction,
          plannedTime: dbDep.plannedTime,
          realtimeTime: dbDep.realtimeTime,
          delay: dbDep.delay,
          platform: dbDep.platform,
          productType: dbDep.productType,
          operator: dbDep.operator,
          stopName: stopName,
        );
        final key = '${dep.line}|${dep.direction}|${dep.plannedTime.toIso8601String()}|$stopName';
        if (seen.contains(key)) continue;
        seen.add(key);
        departures.add(dep);
      }
    }

    // Re-sort by time (may include new rail entries)
    departures.sort((a, b) {
      final ta = a.realtimeTime ?? a.plannedTime;
      final tb = b.realtimeTime ?? b.plannedTime;
      return ta.compareTo(tb);
    });
  }

  /// Fetch departures for a specific stop by name (EFA only)
  Future<void> fetchDeparturesForStop(String stopName) async {
    isLoading = true;

    try {
      final provider = activeProvider ?? _providers.first;
      if (provider.api != TransitApiType.efa) return;
      final baseUrl = '${provider.baseUrl}/XSLT_DM_REQUEST';

      final uri = Uri.parse(
        '$baseUrl'
        '?outputFormat=JSON'
        '&type_dm=stop'
        '&name_dm=${Uri.encodeComponent(stopName)}'
        '&mode=direct'
        '&useRealtime=1'
        '&locationServerActive=1'
        '&limit=30',
      );

      final response = await _client.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(_decodeUtf8(response));
        _parseEfaResponse(data);
      }
    } catch (e) {
      _log.error('Transit: Stop fetch failed: $e', tag: 'TRANSIT');
    }

    isLoading = false;
    onDeparturesUpdate?.call(departures);
  }

  /// The closest stop name (for default filter in UI)
  String? closestStopName;

  // ══════════════════════════════════════════════════════════════
  // EFA PROVIDER — used by DING (Ulm) and MVV (München)
  // ══════════════════════════════════════════════════════════════

  Future<void> _fetchEfaDepartures({required String baseUrl}) async {
    final coordStr = '${_longitude!.toStringAsFixed(6)}:${_latitude!.toStringAsFixed(6)}:WGS84';
    final uri = Uri.parse(
      '$baseUrl'
      '?outputFormat=JSON'
      '&coordOutputFormat=WGS84[dd.ddddd]'
      '&type_dm=coord'
      '&name_dm=$coordStr'
      '&mode=direct'
      '&useRealtime=1'
      '&locationServerActive=1'
      '&limit=30',
    );

    final response = await _client.get(uri).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = jsonDecode(_decodeUtf8(response));
      _parseEfaResponse(data);
      _log.debug('Transit [${activeProvider?.name}]: ${departures.length} departures from ${nearbyStops.length} stops', tag: 'TRANSIT');
    } else {
      _log.error('Transit [${activeProvider?.name}]: API returned ${response.statusCode}', tag: 'TRANSIT');
    }
  }

  /// Parse the EFA JSON response (DING + MVV share the same format)
  void _parseEfaResponse(Map<String, dynamic> data) {
    // Parse assigned stops (sorted by distance).
    // DING returns them under `itdOdvAssignedStops` (with the `itdOdv` prefix).
    // A few EFA installs use plain `assignedStops` — try both.
    nearbyStops = [];
    final dm = data['dm'];
    if (dm is Map) {
      final assignedStops = dm['itdOdvAssignedStops'] ?? dm['assignedStops'];
      if (assignedStops is List) {
        for (final s in assignedStops) {
          nearbyStops.add(TransitStop(
            id: s['stopID']?.toString() ?? '',
            name: s['name']?.toString() ?? '',
            distance: int.tryParse(s['distance']?.toString() ?? '0') ?? 0,
            platform: s['platform']?.toString(),
          ));
        }
        nearbyStops.sort((a, b) => a.distance.compareTo(b.distance));
      }
    }

    // Fallback: if the assignedStops list was empty/missing, derive stops
    // from the departure list. Every departure has `stopID` + `stopName`;
    // we can't know the distance but we surface unique stops so the UI
    // shows something instead of "Keine Haltestellen".
    if (nearbyStops.isEmpty) {
      final seen = <String>{};
      final departureList = data['departureList'];
      if (departureList is List) {
        for (final dep in departureList) {
          if (dep is! Map) continue;
          final id = dep['stopID']?.toString() ?? '';
          final name = dep['stopName']?.toString() ?? '';
          if (id.isEmpty || name.isEmpty) continue;
          if (seen.contains(id)) continue;
          seen.add(id);
          nearbyStops.add(TransitStop(id: id, name: name, distance: 0));
        }
      }
      _log.info('Transit: assignedStops empty → derived ${nearbyStops.length} stops from departureList', tag: 'TRANSIT');
    }

    // Consider 5 nearest stops as candidates so we can prune the empty ones
    // and land on the 3 nearest ACTIVE stops. Match by stopID — the stopName
    // in `itdOdvAssignedStops` is just "Rathaus", but departureList shows
    // "Ulm Rathaus" (with city prefix), so name comparison filters everything
    // out. IDs are stable across both structures.
    final allowedStopIds = <String>{};
    final idToNiceName = <String, String>{};
    for (int i = 0; i < nearbyStops.length && i < 5; i++) {
      allowedStopIds.add(nearbyStops[i].id);
      idToNiceName[nearbyStops[i].id] = nearbyStops[i].name;
    }
    closestStopName = nearbyStops.isNotEmpty ? nearbyStops.first.name : null;

    // Parse departures — only from nearest stops
    departures = [];
    final departureList = data['departureList'];
    if (departureList is List) {
      for (final dep in departureList) {
        try {
          final servingLine = dep['servingLine'] ?? {};
          final dateTime = dep['dateTime'] ?? {};
          final realDateTime = dep['realDateTime'];

          final depStopId = dep['stopID']?.toString() ?? '';
          final depStopName = dep['stopName']?.toString() ?? '';
          // Prefer the short name from nearbyStops ("Rathaus") over the full
          // "Ulm Rathaus" so the UI groups by clean stop labels.
          final stopName = idToNiceName[depStopId] ?? depStopName;

          // Filter: only keep departures from nearest stops (by ID)
          if (allowedStopIds.isNotEmpty && !allowedStopIds.contains(depStopId)) continue;

          final planned = _parseEfaDateTime(dateTime);
          if (planned == null) continue;

          DateTime? realtime;
          if (realDateTime != null) {
            realtime = _parseEfaDateTime(realDateTime);
          }

          final delayStr = dep['servingLine']?['delay']?.toString() ?? '0';
          final delay = int.tryParse(delayStr) ?? 0;

          // Determine product type (EFA motType codes):
          //  0 = train (ICE/IC), 1 = S-Bahn, 2 = U-Bahn, 3 = Stadtbahn/light rail,
          //  4 = Tram, 5 = Stadtbus, 6 = Regionalbus, 7 = Schnellbus,
          //  8 = Seilbahn, 9 = Schiff, 10 = AST, 11 = other
          final motType = servingLine['motType']?.toString() ?? '';
          String productType;
          switch (motType) {
            case '0':
              productType = 'train';
              break;
            case '1':
              productType = 'suburban';
              break;
            case '2':
              productType = 'subway'; // U-Bahn
              break;
            case '3': // Stadtbahn / light rail (Karlsruhe, Stuttgart)
            case '4':
              productType = 'tram';
              break;
            default:
              productType = 'bus';
          }

          final platform = dep['platform']?.toString();

          departures.add(Departure(
            line: servingLine['number']?.toString() ?? servingLine['symbol']?.toString() ?? '?',
            direction: servingLine['direction']?.toString() ?? '',
            plannedTime: planned,
            realtimeTime: realtime,
            delay: delay,
            platform: (platform != null && platform.isNotEmpty && platform != 'null') ? platform : null,
            productType: productType,
            operator: servingLine['operator']?['publicName']?.toString() ?? '',
            stopName: stopName,
          ));
        } catch (e) {
          // Skip malformed entries
        }
      }

      // Sort by departure time
      departures.sort((a, b) {
        final timeA = a.realtimeTime ?? a.plannedTime;
        final timeB = b.realtimeTime ?? b.plannedTime;
        return timeA.compareTo(timeB);
      });
    }

    // Prune nearbyStops to top-3 ACTIVE stops. Two considerations:
    //   • silent bus stops (0 deps) shouldn't push tram/subway off the list
    //   • trams/subways/S-Bahn get preferential ranking — they run through
    //     the city and are usually farther apart, so a tram stop at 400m is
    //     often more useful than a 3rd bus stop at 300m.
    // We boost tram/subway/S-Bahn stops by giving them 30% distance discount.
    final stopIdToDeps = <String, List<Departure>>{};
    for (final d in departures) {
      final id = _stopIdForName(d.stopName) ?? d.stopName;
      stopIdToDeps.putIfAbsent(id, () => []).add(d);
    }

    double effectiveDistance(TransitStop s) {
      final deps = stopIdToDeps[s.id] ?? stopIdToDeps[s.name] ?? [];
      final hasRail = deps.any((d) =>
          d.productType == 'tram' ||
          d.productType == 'subway' ||
          d.productType == 'suburban' ||
          d.productType == 'train');
      return hasRail ? s.distance * 0.7 : s.distance.toDouble();
    }

    final activeStops = nearbyStops
        .where((s) => stopIdToDeps.containsKey(s.id) || stopIdToDeps.containsKey(s.name))
        .toList()
      ..sort((a, b) => effectiveDistance(a).compareTo(effectiveDistance(b)));

    if (activeStops.isNotEmpty) {
      final top3 = activeStops.take(3).toList()..sort((a, b) => a.distance.compareTo(b.distance));
      nearbyStops = top3;
      closestStopName = nearbyStops.first.name;
    }
  }

  /// Reverse-lookup: departure.stopName ("Rathaus" — already prettified above)
  /// → matching nearbyStop.id, so the pruning above can match either the
  /// cleaned name or the stopID.
  String? _stopIdForName(String stopName) {
    for (final s in nearbyStops) {
      if (s.name == stopName) return s.id;
    }
    return null;
  }

  /// Parse EFA departure monitor dateTime → DateTime.
  /// Format: `{year, month, day, hour, minute}` (integer strings).
  DateTime? _parseEfaDateTime(Map<String, dynamic> dt) {
    try {
      final year = int.tryParse(dt['year']?.toString() ?? '');
      final month = int.tryParse(dt['month']?.toString() ?? '');
      final day = int.tryParse(dt['day']?.toString() ?? '');
      final hour = int.tryParse(dt['hour']?.toString() ?? '');
      final minute = int.tryParse(dt['minute']?.toString() ?? '');
      if (year == null || month == null || day == null || hour == null || minute == null) return null;
      return DateTime(year, month, day, hour, minute);
    } catch (e) {
      return null;
    }
  }

  /// Clean EFA platform value — filters out "None"/"null"/empty literals.
  String? _cleanEfaPlatform(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString();
    if (s.isEmpty || s == 'None' || s == 'null' || s == '0') return null;
    return s;
  }

  /// Parse EFA TRIP response dateTime → DateTime.
  /// Format: `{date: "DD.MM.YYYY", time: "HH:MM", rtDate?, rtTime?}`.
  /// Prefers `rtDate`/`rtTime` (realtime) when present.
  DateTime? _parseEfaTripDateTime(dynamic dt) {
    if (dt is! Map) return null;
    try {
      final date = (dt['rtDate'] ?? dt['date'])?.toString();
      final time = (dt['rtTime'] ?? dt['time'])?.toString();
      if (date == null || time == null) return null;
      // date: "01.07.2026" (DD.MM.YYYY)
      final dParts = date.split('.');
      if (dParts.length != 3) return null;
      final day = int.tryParse(dParts[0]);
      final month = int.tryParse(dParts[1]);
      final year = int.tryParse(dParts[2]);
      // time: "17:10" (HH:MM) — sometimes "17:10:00"
      final tParts = time.split(':');
      if (tParts.length < 2) return null;
      final hour = int.tryParse(tParts[0]);
      final minute = int.tryParse(tParts[1]);
      if (year == null || month == null || day == null || hour == null || minute == null) return null;
      return DateTime(year, month, day, hour, minute);
    } catch (_) {
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // HAFAS PROVIDER — used by saarVV (Saarland)
  // ══════════════════════════════════════════════════════════════

  /// Fallback HAFAS endpoint (used only when `activeProvider` is null).
  static const _hafasEndpoint = 'https://saarfahrplan.de/bin/mgate.exe';
  /// saarVV AID from build-time env (kept for backward compat with existing builds).
  static const _saarvvAidFromEnv = String.fromEnvironment('HAFAS_AID', defaultValue: '');

  /// Resolve HAFAS AID for the active provider:
  ///   - saarVV: env var override (build-time) OR fall through
  ///   - other providers: config's `hafasAid`
  String _resolveAid(TransitProviderConfig? p) {
    if (p?.type == TransitProviderType.saarvv && _saarvvAidFromEnv.isNotEmpty) {
      return _saarvvAidFromEnv;
    }
    return p?.hafasAid ?? '';
  }

  Map<String, dynamic> _hafasRequest(List<Map<String, dynamic>> svcReqL) {
    final p = activeProvider;
    final client = <String, dynamic>{
      'type': p?.hafasClientType ?? 'AND',
      'id': p?.hafasClientId ?? 'ZPS-SAAR',
      'name': p?.hafasClientName ?? 'Saarfahrplan',
    };
    // client.v is optional (WEB clients like RMV don't send it)
    final ver = p?.hafasClientVersion ?? '1000070';
    if (ver.isNotEmpty && p?.hafasClientType != 'WEB') {
      client['v'] = ver;
    } else if (p?.hafasClientVersion != null) {
      client['v'] = p!.hafasClientVersion;
    }
    final req = <String, dynamic>{
      'ver': p?.hafasVer ?? '1.40',
      'lang': 'de',
      'auth': {'type': 'AID', 'aid': _resolveAid(p)},
      'client': client,
      'svcReqL': svcReqL,
    };
    if (p?.hafasExt != null) req['ext'] = p!.hafasExt;
    return req;
  }

  /// Fetch departures via HAFAS mgate.exe (saarVV)
  /// Two-step: 1) find nearby stops  2) get departures for each
  Future<void> _fetchHafasDepartures() async {
    // Step 1: Find nearby stops via LocGeoPos
    final nearbyRequest = _hafasRequest([
      {
        'meth': 'LocGeoPos',
        'req': {
          'ring': {
            'cCrd': {
              'x': (_longitude! * 1000000).round(),
              'y': (_latitude! * 1000000).round(),
            },
            'maxDist': 1000,
          },
          'getPOIs': false,
          'getStops': true,
        },
      },
    ]);

    final nearbyResponse = await _client.post(
      Uri.parse(activeProvider?.baseUrl ?? _hafasEndpoint),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(nearbyRequest),
    ).timeout(const Duration(seconds: 15));

    if (nearbyResponse.statusCode != 200) {
      _log.error('Transit [saarVV]: LocGeoPos returned ${nearbyResponse.statusCode}', tag: 'TRANSIT');
      return;
    }

    final nearbyData = jsonDecode(_decodeUtf8(nearbyResponse));
    final nearbyRes = nearbyData['svcResL'];
    if (nearbyRes == null || nearbyRes is! List || nearbyRes.isEmpty) {
      _log.error('Transit [saarVV]: Empty LocGeoPos response', tag: 'TRANSIT');
      return;
    }

    final locRes = nearbyRes[0]['res'];
    if (locRes == null) {
      // Check for error
      final err = nearbyRes[0]['err'];
      _log.error('Transit [saarVV]: LocGeoPos error: $err', tag: 'TRANSIT');
      return;
    }

    final locList = locRes['locL'] as List? ?? [];

    // Parse nearby stops
    nearbyStops = [];
    final stopIds = <String>[];
    final stopLids = <String>[];

    for (final loc in locList) {
      if (loc['type'] != 'S') continue; // only stops
      final name = loc['name']?.toString() ?? '';
      final lid = loc['lid']?.toString() ?? '';
      final dist = loc['dist'] as int? ?? 0;
      final extId = loc['extId']?.toString() ?? '';

      nearbyStops.add(TransitStop(
        id: extId.isNotEmpty ? extId : lid,
        name: name,
        distance: dist,
      ));
      stopIds.add(extId.isNotEmpty ? extId : lid);
      stopLids.add(lid);

      // Max 3 closest stops
      if (nearbyStops.length >= 3) break;
    }

    nearbyStops.sort((a, b) => a.distance.compareTo(b.distance));
    closestStopName = nearbyStops.isNotEmpty ? nearbyStops.first.name : null;

    if (stopLids.isEmpty) {
      _log.info('Transit [saarVV]: No nearby stops found', tag: 'TRANSIT');
      departures = [];
      return;
    }

    // Step 2: Get departures for each nearby stop
    final now = DateTime.now();
    final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final timeStr = '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}00';

    final stbRequests = stopLids.map((lid) => {
      'meth': 'StationBoard',
      'req': {
        'type': 'DEP',
        'stbLoc': {'lid': lid},
        'maxJny': 15,
        'date': dateStr,
        'time': timeStr,
      },
    }).toList();

    final depRequest = _hafasRequest(stbRequests);
    final depResponse = await _client.post(
      Uri.parse(activeProvider?.baseUrl ?? _hafasEndpoint),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(depRequest),
    ).timeout(const Duration(seconds: 15));

    if (depResponse.statusCode != 200) {
      _log.error('Transit [saarVV]: StationBoard returned ${depResponse.statusCode}', tag: 'TRANSIT');
      return;
    }

    final depData = jsonDecode(_decodeUtf8(depResponse));
    final depResL = depData['svcResL'] as List? ?? [];

    departures = [];

    for (int svcIdx = 0; svcIdx < depResL.length; svcIdx++) {
      final svc = depResL[svcIdx];
      if (svc['meth'] != 'StationBoard') continue;

      final res = svc['res'];
      if (res == null) continue;

      final stopName = svcIdx < nearbyStops.length ? nearbyStops[svcIdx].name : '';

      // Common products list (referenced by index from jnyL)
      final common = res['common'] ?? {};
      final prodL = common['prodL'] as List? ?? [];

      final jnyL = res['jnyL'] as List? ?? [];

      for (final jny in jnyL) {
        try {
          final stbStop = jny['stbStop'] ?? {};
          final date = jny['date']?.toString() ?? dateStr;

          // Parse scheduled time
          final dTimeS = stbStop['dTimeS']?.toString();
          if (dTimeS == null || dTimeS.length < 4) continue;
          final planned = _parseHafasDateTime(date, dTimeS);
          if (planned == null) continue;

          // Parse realtime time
          DateTime? realtime;
          final dTimeR = stbStop['dTimeR']?.toString();
          if (dTimeR != null && dTimeR.length >= 4) {
            realtime = _parseHafasDateTime(date, dTimeR);
          }

          // Calculate delay
          int delay = 0;
          if (realtime != null) {
            delay = realtime.difference(planned).inMinutes;
            if (delay < 0) delay = 0;
          }

          // Platform
          final dPlatfS = stbStop['dPlatfS']?.toString();
          final dPlatfR = stbStop['dPlatfR']?.toString();
          final platform = dPlatfR ?? dPlatfS;

          // Product info (line name, type)
          final prodIdx = jny['prodX'] as int? ?? (jny['prodL'] is List && (jny['prodL'] as List).isNotEmpty ? (jny['prodL'] as List)[0]['prodX'] ?? 0 : 0);
          String lineName = '?';
          String productType = 'bus';
          String operatorName = '';

          if (prodIdx < prodL.length) {
            final prod = prodL[prodIdx];
            lineName = prod['name']?.toString().trim() ?? '?';
            // Extract short line number from name (e.g. "Bus 101" → "101")
            final nameStr = prod['name']?.toString() ?? '';
            final lineMatch = RegExp(r'(\d+\w*)$').firstMatch(nameStr.trim());
            if (lineMatch != null) {
              lineName = lineMatch.group(1)!;
            }
            operatorName = prod['oprX'] != null ? '' : '';

            // Product class → type
            final cls = prod['cls'] as int? ?? 0;
            if (cls == 1 || cls == 2) {
              productType = 'train'; // ICE, IC
            } else if (cls == 4) {
              productType = 'regional'; // RE, RB
            } else if (cls == 8) {
              productType = 'suburban'; // S-Bahn
            } else if (cls == 16) {
              productType = 'tram'; // Tram
            } else {
              productType = 'bus';
            }
          }

          // Direction
          final direction = jny['dirTxt']?.toString() ?? '';

          departures.add(Departure(
            line: lineName,
            direction: direction,
            plannedTime: planned,
            realtimeTime: realtime,
            delay: delay,
            platform: (platform != null && platform.isNotEmpty) ? platform : null,
            productType: productType,
            operator: operatorName,
            stopName: stopName,
          ));
        } catch (e) {
          // Skip malformed entries
        }
      }
    }

    // Sort all departures by time
    departures.sort((a, b) {
      final timeA = a.realtimeTime ?? a.plannedTime;
      final timeB = b.realtimeTime ?? b.plannedTime;
      return timeA.compareTo(timeB);
    });

    _log.debug('Transit [saarVV]: ${departures.length} departures from ${nearbyStops.length} stops', tag: 'TRANSIT');
  }

  /// Parse HAFAS date+time strings → DateTime
  /// date: "20260301", time: "143500" or "1435"
  DateTime? _parseHafasDateTime(String date, String time) {
    try {
      if (date.length < 8) return null;
      final year = int.parse(date.substring(0, 4));
      final month = int.parse(date.substring(4, 6));
      final day = int.parse(date.substring(6, 8));

      // Time can be "HHMMSS" or "HHMM" — also handle day overflow (e.g. "250000" = next day 01:00)
      int hour = int.parse(time.substring(0, 2));
      final minute = int.parse(time.substring(2, 4));

      var dt = DateTime(year, month, day, 0, minute);
      if (hour >= 24) {
        dt = dt.add(Duration(hours: hour));
      } else {
        dt = DateTime(year, month, day, hour, minute);
      }
      return dt;
    } catch (e) {
      return null;
    }
  }

  /// Force refresh (also updates GPS if available)
  Future<void> refresh() async {
    if (_useGps) await _getGpsLocation();
    _detectProvider(); // re-detect in case position changed significantly
    await fetchDepartures();
  }

  /// Force a fresh GNSS chip fix — bypasses cache and Play Services.
  /// Triggered by "GPS erneuern" button in Echtzeit tab when the user sees
  /// only city-level results. On Android hits raw LocationManager with
  /// `LocationAccuracy.best`; up to 30s to acquire a satellite fix.
  Future<bool> forceGnssRefresh() async {
    _log.info('Transit: forceGnssRefresh triggered', tag: 'TRANSIT');
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: Platform.isAndroid
            ? AndroidSettings(
                accuracy: LocationAccuracy.best,
                forceLocationManager: true,
              )
            : Platform.isIOS || Platform.isMacOS
                ? AppleSettings(accuracy: LocationAccuracy.bestForNavigation)
                : const LocationSettings(accuracy: LocationAccuracy.bestForNavigation),
      ).timeout(const Duration(seconds: 30));
      _latitude = position.latitude;
      _longitude = position.longitude;
      lastAccuracy = position.accuracy;
      lastSource = Platform.isAndroid ? LocationSource.gnss : LocationSource.fusedLocation;
      locationError = null;
      _log.info('Transit: forceGnssRefresh got ${position.accuracy.toStringAsFixed(0)}m fix', tag: 'TRANSIT');
      await _reverseGeocode();
      _detectProvider();
      await fetchDepartures();
      return true;
    } catch (e) {
      _log.error('Transit: forceGnssRefresh failed: $e', tag: 'TRANSIT');
      locationError = 'GPS-Chip antwortet nicht — draußen mit freier Sicht zum Himmel versuchen';
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // STATION FACILITIES — live elevator + escalator status via db-rest
  // ══════════════════════════════════════════════════════════════

  /// In-memory cache for facility lookups (5 min TTL).
  /// Facility state doesn't change often; cache saves API round-trips when
  /// user reopens the same stop dialog.
  final _facilitiesCache = <String, _CachedFacilities>{};

  final _dbStopIdCache = <String, String?>{};   // stationName → DB stop ID
  final _dbDeparturesCache = <String, _CachedDepartures>{};

  static const _restBase = 'https://v6.db.transport.rest';
  static const _restHeaders = {
    'Accept': 'application/json',
    'User-Agent': 'ICD360S-eV-App/1.0',
  };

  /// Resolve a station name to a DB (HAFAS) stop ID via transport.rest.
  /// Cached — the mapping is stable across days.
  Future<String?> _resolveDbStopId(String stationName) async {
    if (_dbStopIdCache.containsKey(stationName)) return _dbStopIdCache[stationName];
    // Try `/locations?query=X&results=1&addresses=false&poi=false`
    try {
      final uri = Uri.parse(
        '$_restBase/locations?query=${Uri.encodeQueryComponent(stationName)}&results=1&addresses=false&poi=false',
      );
      final resp = await _client.get(uri, headers: _restHeaders).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final data = jsonDecode(_decodeUtf8(resp));
        if (data is List && data.isNotEmpty) {
          final first = data.first;
          if (first is Map) {
            final id = first['id']?.toString();
            _log.info('Transit: DB stop resolve "$stationName" → id=$id (${first['name']})', tag: 'TRANSIT');
            _dbStopIdCache[stationName] = id;
            return id;
          }
        }
      }
    } catch (e) {
      _log.debug('Transit: DB stop resolve failed for "$stationName": $e', tag: 'TRANSIT');
    }
    _dbStopIdCache[stationName] = null;
    return null;
  }

  /// Fetch live DB long-distance/regional/S-Bahn departures for a station
  /// (ICE, IC, EC, RE, RB, S). Complements EFA which typically only has local
  /// buses + trams. Cached 60s.
  Future<List<Departure>> fetchDbDepartures(String stationName) async {
    final cached = _dbDeparturesCache[stationName];
    if (cached != null && DateTime.now().difference(cached.at) < const Duration(seconds: 60)) {
      return cached.departures;
    }
    final id = await _resolveDbStopId(stationName);
    if (id == null) {
      _dbDeparturesCache[stationName] = _CachedDepartures([], DateTime.now());
      return [];
    }
    try {
      final uri = Uri.parse('$_restBase/stops/$id/departures?duration=60&results=10');
      final resp = await _client.get(uri, headers: _restHeaders).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) {
        _log.debug('Transit: DB departures returned ${resp.statusCode} for $stationName', tag: 'TRANSIT');
        _dbDeparturesCache[stationName] = _CachedDepartures([], DateTime.now());
        return [];
      }
      final data = jsonDecode(_decodeUtf8(resp));
      // Response shape: { departures: [...] } (v6) or bare list (v5)
      final list = data is Map ? (data['departures'] as List? ?? []) : (data as List? ?? []);
      final out = <Departure>[];
      for (final d in list) {
        if (d is! Map) continue;
        final planned = DateTime.tryParse(d['plannedWhen']?.toString() ?? '');
        final actual = DateTime.tryParse(d['when']?.toString() ?? '');
        if (planned == null) continue;
        final line = d['line'] as Map? ?? {};
        final product = (line['product'] ?? line['productName'] ?? '').toString().toLowerCase();
        String pt;
        if (product.contains('nationalexpress') || product.contains('national') || product.contains('ice')) {
          pt = 'train';
        } else if (product.contains('regional') || product.contains('regionalexp')) {
          pt = 'regional';
        } else if (product.contains('suburban') || product.contains('sbahn')) {
          pt = 'suburban';
        } else if (product.contains('subway') || product.contains('ubahn')) {
          pt = 'subway';
        } else if (product.contains('tram')) {
          pt = 'tram';
        } else {
          pt = 'bus';
        }
        final delay = (d['delay'] as num?) != null ? ((d['delay'] as num).toInt() ~/ 60) : 0;
        out.add(Departure(
          line: line['name']?.toString() ?? line['id']?.toString() ?? '?',
          direction: d['direction']?.toString() ?? d['destination']?['name']?.toString() ?? '',
          plannedTime: planned,
          realtimeTime: actual,
          delay: delay,
          platform: d['platform']?.toString() ?? d['plannedPlatform']?.toString(),
          productType: pt,
          operator: (d['line'] as Map?)?['operator']?['name']?.toString() ?? '',
          stopName: stationName,
        ));
      }
      _log.info('Transit: DB $stationName → ${out.length} rail departures', tag: 'TRANSIT');
      _dbDeparturesCache[stationName] = _CachedDepartures(out, DateTime.now());
      return out;
    } catch (e) {
      _log.error('Transit: fetchDbDepartures failed for "$stationName": $e', tag: 'TRANSIT');
      _dbDeparturesCache[stationName] = _CachedDepartures([], DateTime.now());
      return [];
    }
  }

  /// Fetch live status of elevators + escalators at [stationName].
  /// Uses `v6.db.transport.rest` `/stops/{id}` which embeds a `facilities` map
  /// keyed by facility ID. No auth key required. Returns empty list if the
  /// stop is not a DB railway station.
  Future<List<StationFacility>> fetchFacilities(String stationName) async {
    final cached = _facilitiesCache[stationName];
    if (cached != null && DateTime.now().difference(cached.at) < const Duration(minutes: 5)) {
      return cached.facilities;
    }

    // Try to resolve to a DB stop ID via /locations.
    final id = await _resolveDbStopId(stationName);
    if (id == null) {
      _facilitiesCache[stationName] = _CachedFacilities([], DateTime.now());
      return [];
    }

    // Try both endpoints (schema varies between deployments):
    //   /stops/{id}  — usually has facilities under `.facilities`
    //   /stations/{id} — legacy STADA endpoint (some ILU codes only)
    for (final url in [
      '$_restBase/stops/$id',
      '$_restBase/stations/$id',
    ]) {
      try {
        final resp = await _client.get(Uri.parse(url), headers: _restHeaders).timeout(const Duration(seconds: 8));
        if (resp.statusCode != 200) continue;
        final data = jsonDecode(_decodeUtf8(resp));
        final result = _parseFacilities(data);
        if (result.isNotEmpty) {
          _log.info('Transit: ${result.length} facilities @ "$stationName" via $url', tag: 'TRANSIT');
          _facilitiesCache[stationName] = _CachedFacilities(result, DateTime.now());
          return result;
        }
      } catch (e) {
        _log.debug('Transit: facility fetch $url failed: $e', tag: 'TRANSIT');
      }
    }
    _log.info('Transit: no facilities data for "$stationName"', tag: 'TRANSIT');
    _facilitiesCache[stationName] = _CachedFacilities([], DateTime.now());
    return [];
  }

  List<StationFacility> _parseFacilities(dynamic data) {
    if (data is! Map) return [];
    // v6.db.transport.rest shape: `facilities` is a Map<id, { title, state, ... }>
    // Older wrappers used a List. Handle both.
    final raw = data['facilities'] ?? data['aufzuege'] ?? data['elevators'];
    Iterable<dynamic> entries;
    if (raw is Map) {
      entries = raw.values;
    } else if (raw is List) {
      entries = raw;
    } else {
      return [];
    }

    final out = <StationFacility>[];
    for (final f in entries) {
      if (f is! Map) continue;
      final desc = (f['description'] ?? f['title'] ?? f['name'] ?? f['label'] ?? '').toString();
      final rawType = (f['type'] ?? f['facilityType'] ?? '').toString().toUpperCase();
      // Guess type from description when field is missing
      String type;
      if (rawType.contains('ESCAL') || rawType.contains('FAHRTREPPE')) {
        type = 'ESCALATOR';
      } else if (rawType.contains('ELEVATOR') || rawType.contains('AUFZUG') || rawType.contains('LIFT')) {
        type = 'ELEVATOR';
      } else {
        final descLower = desc.toLowerCase();
        if (descLower.contains('fahrtreppe') || descLower.contains('rolltreppe') || descLower.contains('escalator')) {
          type = 'ESCALATOR';
        } else {
          type = 'ELEVATOR';
        }
      }
      // Normalize status (FaSta uses ACTIVE/INACTIVE/UNKNOWN; some clients use in_service/out_of_service)
      final rawStatus = (f['state'] ?? f['status'] ?? f['operationalStatus'] ?? 'UNKNOWN').toString().toUpperCase();
      String status;
      if (rawStatus == 'ACTIVE' || rawStatus == 'IN_SERVICE' || rawStatus == 'AVAILABLE' || rawStatus == 'BETRIEB') {
        status = 'ACTIVE';
      } else if (rawStatus == 'INACTIVE' || rawStatus == 'OUT_OF_SERVICE' || rawStatus == 'DEFECT' || rawStatus == 'STOERUNG') {
        status = 'INACTIVE';
      } else {
        status = 'UNKNOWN';
      }
      if (desc.isEmpty) continue;
      out.add(StationFacility(
        description: desc,
        type: type,
        status: status,
        reason: f['stateExplanation']?.toString() ?? f['reason']?.toString() ?? f['ausfallgrund']?.toString(),
      ));
    }
    return out;
  }

  // ══════════════════════════════════════════════════════════════
  // TRIP SEARCH — "Verbindung suchen" tab
  // ══════════════════════════════════════════════════════════════

  /// Autocomplete stops/localities matching [query].
  /// Searches ALL EFA + HAFAS providers + bahn.de in parallel — the server may be in
  /// a region (e.g. Limburg → RMV) that doesn't cover the queried city
  /// (e.g. Neu-Ulm → DING). Merges + deduplicates by name.
  /// Each result carries `sourceProvider` so `searchJourneys` uses the right one.
  Future<List<TransitLocation>> searchLocations(String query) async {
    if (query.trim().length < 2) return [];

    // Fire all providers + bahn.de in parallel. Individual failures → empty list.
    final futures = <Future<List<TransitLocation>>>[];
    for (final p in _providers) {
      final search = p.api == TransitApiType.efa
          ? _efaLocationSearch(p, query)
          : _hafasLocationSearch(p, query);
      futures.add(
        search
            .then((list) => list.map((l) => TransitLocation(
                  id: l.id, name: l.name, type: l.type, lat: l.lat, lon: l.lon,
                  sourceProvider: p,
                )).toList())
            .catchError((e) {
              _log.debug('Transit: ${p.name} search failed: $e', tag: 'TRANSIT');
              return <TransitLocation>[];
            }),
      );
    }
    futures.add(
      _bahnLocationSearch(query).catchError((e) {
        _log.debug('Transit: bahn.de search failed: $e', tag: 'TRANSIT');
        return <TransitLocation>[];
      }),
    );

    final allResults = await Future.wait(futures);

    // Merge + deduplicate by (name, id). Prioritize stops over cities/streets.
    final seen = <String>{};
    final stops = <TransitLocation>[];
    final others = <TransitLocation>[];
    for (final list in allResults) {
      for (final loc in list) {
        final key = '${loc.name.toLowerCase()}|${loc.id}';
        if (seen.contains(key)) continue;
        seen.add(key);
        if (loc.type == 'stop') {
          stops.add(loc);
        } else {
          others.add(loc);
        }
      }
    }
    // Stops first (bus/tram/train stations), then localities/streets/POIs.
    return [...stops, ...others].take(20).toList();
  }

  /// Search journeys between two locations.
  /// Uses [from.sourceProvider] and [to.sourceProvider] to pick the right
  /// backend — NOT `activeProvider` (which reflects the server's GPS position,
  /// not the location the user is asking about).
  ///
  /// Time semantics:
  ///   - `arrivalTime` set → arrive-by search (for "must be at Behörde by 13:45").
  ///     Backend maps to EFA `itdTripDateTimeDepArr=arr` / HAFAS `outFrwd=false`
  ///     / bahn.de `ankunftSuche=ANKUNFT`.
  ///   - `departureTime` set (or default now) → depart-at search.
  Future<List<Journey>> searchJourneys({
    required TransitLocation from,
    required TransitLocation to,
    DateTime? departureTime,
    DateTime? arrivalTime,
  }) async {
    final arriveBy = arrivalTime != null;
    final when = arrivalTime ?? departureTime ?? DateTime.now();
    List<Journey> results = [];

    final fp = from.sourceProvider;
    final tp = to.sourceProvider;
    final sameProvider = fp != null && tp != null && fp.type == tp.type;

    if (sameProvider) {
      try {
        if (fp.api == TransitApiType.efa) {
          results = await _efaTripSearch(fp, from, to, when, arriveBy: arriveBy);
        } else {
          results = await _hafasTripSearch(fp, from, to, when, arriveBy: arriveBy);
        }
      } catch (e) {
        _log.error('Transit: ${fp.name} trip search failed: $e', tag: 'TRANSIT');
      }
    }

    // Fallback (or intercity) → bahn.de HAFAS (Germany-wide).
    if (results.isEmpty) {
      try {
        results = await _bahnTripSearchByName(from.name, to.name, when, arriveBy: arriveBy);
      } catch (e) {
        _log.error('Transit: bahn.de trip search failed: $e', tag: 'TRANSIT');
      }
    }

    return results;
  }

  /// bahn.de journey search that resolves location names to bahn.de IDs first.
  Future<List<Journey>> _bahnTripSearchByName(String fromName, String toName, DateTime when, {bool arriveBy = false}) async {
    final results = await Future.wait([
      _bahnLocationSearch(fromName),
      _bahnLocationSearch(toName),
    ]);
    if (results[0].isEmpty || results[1].isEmpty) return [];
    return _bahnTripSearch(results[0].first, results[1].first, when, arriveBy: arriveBy);
  }

  // ── EFA trip/location endpoints ────────────────────────────────

  Future<List<TransitLocation>> _efaLocationSearch(TransitProviderConfig p, String q) async {
    final uri = Uri.parse(
      '${p.baseUrl}/XSLT_STOPFINDER_REQUEST'
      '?outputFormat=JSON&locationServerActive=1&type_sf=any&anyObjFilter_sf=126'
      '&name_sf=${Uri.encodeComponent(q)}',
    );
    final response = await _client.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return [];
    final data = jsonDecode(_decodeUtf8(response));
    final points = data['stopFinder']?['points'];
    List raw;
    if (points is List) {
      raw = points;
    } else if (points is Map && points['point'] is List) {
      raw = points['point'];
    } else if (points is Map && points['point'] is Map) {
      raw = [points['point']];
    } else {
      return [];
    }
    return raw.map<TransitLocation?>((e) {
      final ref = e['ref'] ?? {};
      final refId = ref['id']?.toString() ?? '';
      final stateless = e['stateless']?.toString() ?? '';
      final anyType = e['anyType']?.toString() ?? '';
      // For "stop" the short refId works. For "singlehouse"/"poi"/"address"
      // refId is generic (whole street), stateless carries the house number
      // (`streetID:XXX:13:...`) — required for trip search to hit the exact address.
      final id = anyType == 'stop'
          ? (refId.isNotEmpty ? refId : stateless)
          : (stateless.isNotEmpty ? stateless : refId);
      final name = e['name']?.toString() ?? e['object']?.toString() ?? '';
      if (id.isEmpty || name.isEmpty) return null;
      final coords = ref['coords']?.toString().split(',');
      double? lat, lon;
      if (coords != null && coords.length == 2) {
        lon = double.tryParse(coords[0]);
        lat = double.tryParse(coords[1]);
      }
      return TransitLocation(
        id: id, name: name, type: anyType, lat: lat, lon: lon,
      );
    }).whereType<TransitLocation>().toList();
  }

  Future<List<Journey>> _efaTripSearch(
    TransitProviderConfig p, TransitLocation from, TransitLocation to, DateTime when, {
    bool arriveBy = false,
  }) async {
    final dateStr = '${when.year}${when.month.toString().padLeft(2, '0')}${when.day.toString().padLeft(2, '0')}';
    final timeStr = '${when.hour.toString().padLeft(2, '0')}${when.minute.toString().padLeft(2, '0')}';
    final uri = Uri.parse(
      '${p.baseUrl}/XSLT_TRIP_REQUEST2'
      '?outputFormat=JSON&locationServerActive=1&useRealtime=1&calcNumberOfTrips=4'
      '&type_origin=any&name_origin=${Uri.encodeComponent(from.id)}'
      '&type_destination=any&name_destination=${Uri.encodeComponent(to.id)}'
      '&itdDate=$dateStr&itdTime=$timeStr'
      '&itdTripDateTimeDepArr=${arriveBy ? "arr" : "dep"}',
    );
    final response = await _client.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) return [];
    final data = jsonDecode(_decodeUtf8(response));
    final trips = data['trips'];
    if (trips is! List) return [];
    return trips.map<Journey?>(_parseEfaTrip).whereType<Journey>().toList();
  }

  Journey? _parseEfaTrip(dynamic trip) {
    try {
      final legsRaw = trip['legs'];
      if (legsRaw is! List || legsRaw.isEmpty) return null;
      final legs = <JourneyLeg>[];
      for (final leg in legsRaw) {
        final points = leg['points'] as List? ?? [];
        if (points.length < 2) continue;
        final depPoint = points.first;
        final arrPoint = points.last;
        // Trip response uses DIFFERENT dateTime format than departure monitor:
        //   DM:   {year, month, day, hour, minute}   (integers as strings)
        //   Trip: {date: "01.07.2026", time: "17:10", rtDate, rtTime}
        // Try trip parser first, fall back to DM parser.
        final depDT = _parseEfaTripDateTime(depPoint['dateTime']) ?? _parseEfaDateTime(depPoint['dateTime'] ?? {});
        final arrDT = _parseEfaTripDateTime(arrPoint['dateTime']) ?? _parseEfaDateTime(arrPoint['dateTime'] ?? {});
        if (depDT == null || arrDT == null) continue;

        final mode = leg['mode'] ?? {};
        final motType = mode['type']?.toString() ?? '';
        final isWalk = motType == '100' || motType == '99' || (mode['name']?.toString().toLowerCase().contains('fuß') ?? false);
        String productType;
        switch (motType) {
          case '0': productType = 'train'; break;
          case '1': productType = 'suburban'; break;
          case '4': productType = 'tram'; break;
          case '100': case '99': productType = 'walk'; break;
          default: productType = 'bus';
        }

        legs.add(JourneyLeg(
          line: isWalk ? 'Fußweg' : (mode['number']?.toString() ?? mode['symbol']?.toString() ?? '?'),
          direction: mode['destination']?.toString() ?? '',
          fromName: depPoint['name']?.toString() ?? '',
          toName: arrPoint['name']?.toString() ?? '',
          depTime: depDT,
          arrTime: arrDT,
          fromPlatform: _cleanEfaPlatform(depPoint['platform']),
          toPlatform: _cleanEfaPlatform(arrPoint['platform']),
          productType: productType,
          isWalk: isWalk,
        ));
      }
      if (legs.isEmpty) return null;
      return Journey(legs: legs, depTime: legs.first.depTime, arrTime: legs.last.arrTime);
    } catch (e) {
      return null;
    }
  }

  // ── HAFAS trip/location endpoints ──────────────────────────────

  Future<List<TransitLocation>> _hafasLocationSearch(TransitProviderConfig p, String q) async {
    final req = _hafasRequest([
      {
        'meth': 'LocMatch',
        'req': {
          'input': {
            'field': 'S',
            'loc': {'name': q, 'type': 'ALL'},
            'maxLoc': 15,
          },
        },
      },
    ]);
    final response = await _client.post(
      Uri.parse(p.baseUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(req),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return [];
    final data = jsonDecode(_decodeUtf8(response));
    // HAFAS reports auth failures at root level, not in svcResL — check both
    final rootErr = data['err']?.toString();
    if (rootErr != null && rootErr != 'OK') {
      _log.error('Transit [${p.name}]: HAFAS root err=$rootErr ${data['errTxt'] ?? ''}', tag: 'TRANSIT');
      return [];
    }
    final match = data['svcResL']?[0]?['res']?['match']?['locL'] as List? ?? [];
    return match.map<TransitLocation?>((loc) {
      final name = loc['name']?.toString() ?? '';
      final lid = loc['lid']?.toString() ?? '';
      if (name.isEmpty || lid.isEmpty) return null;
      final crd = loc['crd'];
      double? lat, lon;
      if (crd is Map) {
        final x = crd['x']; final y = crd['y'];
        if (x is num) lon = x / 1000000;
        if (y is num) lat = y / 1000000;
      }
      return TransitLocation(id: lid, name: name, type: loc['type']?.toString(), lat: lat, lon: lon);
    }).whereType<TransitLocation>().toList();
  }

  Future<List<Journey>> _hafasTripSearch(
    TransitProviderConfig p, TransitLocation from, TransitLocation to, DateTime when, {
    bool arriveBy = false,
  }) async {
    final dateStr = '${when.year}${when.month.toString().padLeft(2, '0')}${when.day.toString().padLeft(2, '0')}';
    final timeStr = '${when.hour.toString().padLeft(2, '0')}${when.minute.toString().padLeft(2, '0')}00';
    final req = _hafasRequest([
      {
        'meth': 'TripSearch',
        'req': {
          'depLocL': [{'lid': from.id}],
          'arrLocL': [{'lid': to.id}],
          'outDate': dateStr,
          'outTime': timeStr,
          'numF': 4,
          'outFrwd': !arriveBy, // true = depart-at, false = arrive-by
        },
      },
    ]);
    final response = await _client.post(
      Uri.parse(p.baseUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(req),
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) return [];
    final data = jsonDecode(_decodeUtf8(response));
    return _parseHafasTripResponse(data);
  }

  List<Journey> _parseHafasTripResponse(Map<String, dynamic> data) {
    final rootErr = data['err']?.toString();
    if (rootErr != null && rootErr != 'OK') {
      _log.error('Transit: HAFAS trip root err=$rootErr ${data['errTxt'] ?? ''}', tag: 'TRANSIT');
      return [];
    }
    final svc = data['svcResL']?[0]?['res'];
    if (svc == null) return [];
    final common = svc['common'] ?? {};
    final locL = common['locL'] as List? ?? [];
    final prodL = common['prodL'] as List? ?? [];
    final outConL = svc['outConL'] as List? ?? [];

    final journeys = <Journey>[];
    for (final con in outConL) {
      try {
        final date = con['date']?.toString() ?? '';
        final secL = con['secL'] as List? ?? [];
        final legs = <JourneyLeg>[];
        for (final sec in secL) {
          final type = sec['type']?.toString() ?? '';
          final isWalk = type == 'WALK' || type == 'TRSF';
          final dep = sec['dep'] ?? {};
          final arr = sec['arr'] ?? {};
          final depDT = _parseHafasDateTime(date, dep['dTimeR']?.toString() ?? dep['dTimeS']?.toString() ?? '');
          final arrDT = _parseHafasDateTime(date, arr['aTimeR']?.toString() ?? arr['aTimeS']?.toString() ?? '');
          if (depDT == null || arrDT == null) continue;

          final depLocIdx = dep['locX'] as int? ?? 0;
          final arrLocIdx = arr['locX'] as int? ?? 0;
          final fromName = depLocIdx < locL.length ? (locL[depLocIdx]['name']?.toString() ?? '') : '';
          final toName = arrLocIdx < locL.length ? (locL[arrLocIdx]['name']?.toString() ?? '') : '';

          String line = 'Fußweg';
          String direction = '';
          String productType = 'walk';
          if (!isWalk) {
            final jny = sec['jny'] ?? {};
            direction = jny['dirTxt']?.toString() ?? '';
            final prodX = jny['prodX'] as int?;
            if (prodX != null && prodX < prodL.length) {
              final prod = prodL[prodX];
              final nameStr = prod['name']?.toString().trim() ?? '?';
              final m = RegExp(r'([A-Z]*\s?\d+\w*)$').firstMatch(nameStr);
              line = m?.group(1)?.trim() ?? nameStr;
              final cls = prod['cls'] as int? ?? 0;
              if (cls == 1 || cls == 2) {
                productType = 'train';
              } else if (cls == 4) {
                productType = 'regional';
              } else if (cls == 8) {
                productType = 'suburban';
              } else if (cls == 16) {
                productType = 'tram';
              } else {
                productType = 'bus';
              }
            }
          }

          legs.add(JourneyLeg(
            line: line,
            direction: direction,
            fromName: fromName,
            toName: toName,
            depTime: depDT,
            arrTime: arrDT,
            fromPlatform: dep['dPlatfR']?.toString() ?? dep['dPlatfS']?.toString(),
            toPlatform: arr['aPlatfR']?.toString() ?? arr['aPlatfS']?.toString(),
            productType: productType,
            isWalk: isWalk,
          ));
        }
        if (legs.isEmpty) continue;
        journeys.add(Journey(legs: legs, depTime: legs.first.depTime, arrTime: legs.last.arrTime));
      } catch (_) {}
    }
    return journeys;
  }

  // ── bahn.de fallback (Germany-wide, no auth) ───────────────────

  Future<List<TransitLocation>> _bahnLocationSearch(String q) async {
    final uri = Uri.parse(
      'https://www.bahn.de/web/api/reiseloesung/orte'
      '?suchbegriff=${Uri.encodeComponent(q)}&typ=ALL&limit=15',
    );
    final response = await _client.get(uri, headers: {
      'Accept': 'application/json',
      'User-Agent': 'Mozilla/5.0 (Linux; Android 13) ICD360S-eV-App/1.0',
    }).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return [];
    final data = jsonDecode(_decodeUtf8(response));
    if (data is! List) return [];
    return data.map<TransitLocation?>((e) {
      final name = e['name']?.toString() ?? '';
      final id = e['id']?.toString() ?? e['extId']?.toString() ?? '';
      if (name.isEmpty || id.isEmpty) return null;
      return TransitLocation(
        id: id, name: name, type: e['typ']?.toString(),
        lat: (e['lat'] as num?)?.toDouble(),
        lon: (e['lon'] as num?)?.toDouble(),
      );
    }).whereType<TransitLocation>().toList();
  }

  Future<List<Journey>> _bahnTripSearch(TransitLocation from, TransitLocation to, DateTime when, {bool arriveBy = false}) async {
    final iso = when.toIso8601String();
    final uri = Uri.parse('https://www.bahn.de/web/api/reiseloesung/verbindungen');
    final body = jsonEncode({
      'abfahrtsHalt': from.id,
      'ankunftsHalt': to.id,
      'anfrageZeitpunkt': iso,
      'ankunftSuche': arriveBy ? 'ANKUNFT' : 'ABFAHRT',
      'klasse': 'KLASSE_2',
      'produktgattungen': ['ICE','EC_IC','IR','REGIONAL','SBAHN','BUS','SCHIFF','UBAHN','TRAM','ANRUFPFLICHTIG'],
      'reisende': [{'typ':'ERWACHSENER','ermaessigungen':[{'art':'KEINE_ERMAESSIGUNG','klasse':'KLASSENLOS'}],'alter':[],'anzahl':1}],
      'schnelleVerbindungen': true,
      'sitzplatzOnly': false,
      'bikeCarriage': false,
      'reservierungsKontingenteVorhanden': false,
      'nurDeutschlandTicketVerbindungen': false,
    });
    final response = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': 'Mozilla/5.0 (Linux; Android 13) ICD360S-eV-App/1.0',
      },
      body: body,
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) return [];
    final data = jsonDecode(_decodeUtf8(response));
    final verb = data['verbindungen'] as List? ?? [];
    return verb.map<Journey?>(_parseBahnConnection).whereType<Journey>().take(4).toList();
  }

  Journey? _parseBahnConnection(dynamic conn) {
    try {
      final segments = conn['verbindungsAbschnitte'] as List? ?? [];
      if (segments.isEmpty) return null;
      final legs = <JourneyLeg>[];
      for (final seg in segments) {
        final typ = seg['typ']?.toString() ?? '';
        final isWalk = typ == 'WALK' || typ == 'FUSSWEG';
        final depIso = seg['abfahrtsZeitpunkt']?.toString();
        final arrIso = seg['ankunftsZeitpunkt']?.toString();
        if (depIso == null || arrIso == null) continue;
        final depDT = DateTime.tryParse(depIso);
        final arrDT = DateTime.tryParse(arrIso);
        if (depDT == null || arrDT == null) continue;

        final gattung = seg['verkehrsmittel']?['produktGattung']?.toString() ?? '';
        String productType;
        switch (gattung) {
          case 'ICE': case 'EC_IC': case 'IR': productType = 'train'; break;
          case 'REGIONAL': productType = 'regional'; break;
          case 'SBAHN': productType = 'suburban'; break;
          case 'TRAM': case 'UBAHN': productType = 'tram'; break;
          case 'WALK': case 'FUSSWEG': productType = 'walk'; break;
          default: productType = 'bus';
        }

        legs.add(JourneyLeg(
          line: isWalk ? 'Fußweg' : (seg['verkehrsmittel']?['name']?.toString() ?? seg['verkehrsmittel']?['kurzText']?.toString() ?? '?'),
          direction: seg['verkehrsmittel']?['richtung']?.toString() ?? '',
          fromName: seg['abfahrtsOrt']?.toString() ?? '',
          toName: seg['ankunftsOrt']?.toString() ?? '',
          depTime: depDT,
          arrTime: arrDT,
          fromPlatform: seg['abfahrtsGleis']?.toString(),
          toPlatform: seg['ankunftsGleis']?.toString(),
          productType: productType,
          isWalk: isWalk,
        ));
      }
      if (legs.isEmpty) return null;
      return Journey(legs: legs, depTime: legs.first.depTime, arrTime: legs.last.arrTime);
    } catch (_) {
      return null;
    }
  }
}
