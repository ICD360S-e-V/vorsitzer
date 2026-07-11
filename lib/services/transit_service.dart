import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'logger_service.dart';
import 'http_client_factory.dart';
import 'transit_offline_cache.dart';

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

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'distance': distance,
        'platform': platform,
      };
  factory TransitStop.fromJson(Map<String, dynamic> j) => TransitStop(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        distance: (j['distance'] as num?)?.toInt() ?? 0,
        platform: j['platform'] as String?,
      );
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
  // Fields required for stop-sequence lookup ("where does this bus go?").
  // Not always present — some HAFAS variants omit them, in which case the
  // sequence dialog degrades to just "from → destination".
  final String? stopID;    // ID of the boarding stop (where the user is)
  final String? destID;    // ID of the line's final stop (for EFA trip search)
  final String? tripID;    // HAFAS-style trip ID (for transport.rest /trips)
  /// True when the operator has flagged this departure as cancelled
  /// (HAFAS `stbStop.dCncl == true`, EFA `pointCancelled != null`).
  /// UI shows an "Ausgefallen" badge and lines through the time.
  final bool isCancelled;

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
    this.stopID,
    this.destID,
    this.tripID,
    this.isCancelled = false,
  });

  Map<String, dynamic> toJson() => {
        'line': line,
        'direction': direction,
        'plannedTime': plannedTime.toIso8601String(),
        'realtimeTime': realtimeTime?.toIso8601String(),
        'delay': delay,
        'platform': platform,
        'productType': productType,
        'operator': operator,
        'stopName': stopName,
        'stopID': stopID,
        'destID': destID,
        'tripID': tripID,
        'isCancelled': isCancelled,
      };

  factory Departure.fromJson(Map<String, dynamic> j) => Departure(
        line: j['line'] as String? ?? '',
        direction: j['direction'] as String? ?? '',
        plannedTime: DateTime.tryParse(j['plannedTime'] as String? ?? '') ?? DateTime.now(),
        realtimeTime: (j['realtimeTime'] is String) ? DateTime.tryParse(j['realtimeTime'] as String) : null,
        delay: (j['delay'] as num?)?.toInt() ?? 0,
        platform: j['platform'] as String?,
        productType: j['productType'] as String? ?? 'bus',
        operator: j['operator'] as String? ?? '',
        isCancelled: j['isCancelled'] as bool? ?? false,
        stopName: j['stopName'] as String? ?? '',
        stopID: j['stopID'] as String?,
        destID: j['destID'] as String?,
        tripID: j['tripID'] as String?,
      );

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

/// A single stop on a vehicle's route — returned by `fetchTripStops` and
/// rendered as a vertical timeline in the "Wo fährt der Bus hin?" dialog.
///
/// The user's current stop is flagged so the UI can highlight it with a
/// coloured "here" marker.
class TripStop {
  final String name;
  final String stopID;
  final DateTime plannedTime;
  final DateTime? realtimeTime;
  final int delay;      // minutes
  final bool isCurrent; // true = this is where the user is boarding
  final String? platform;
  final double? lat;
  final double? lon;

  TripStop({
    required this.name,
    required this.stopID,
    required this.plannedTime,
    this.realtimeTime,
    this.delay = 0,
    this.isCurrent = false,
    this.platform,
    this.lat,
    this.lon,
  });

  String get timeString {
    final t = realtimeTime ?? plannedTime;
    return '${t.hour}:${t.minute.toString().padLeft(2, '0')}';
  }
}

/// The full drawable route of one leg: stops + the polyline path between them.
/// Used by the "Karte" tab in the trip-sequence dialog to render on OSM.
class TripRoute {
  final List<TripStop> stops;
  /// Path polyline as (lat, lon) pairs — from EFA's `leg.path`
  /// (space-separated "lon,lat" tokens) or HAFAS `polyG`. Empty if not
  /// provided by the backend; UI falls back to straight lines between pins.
  final List<(double, double)> path;

  TripRoute({required this.stops, required this.path});
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
  /// True dacă operatorul permite explicit Fahrradmitnahme pe această tură.
  /// Sursa: HAFAS `jny.isPresale`? sau — mai des — heuristic pe productType
  /// (RE/RB/S-Bahn/Regional permit, MEX/ICE/IC nu). null când nu știm.
  final bool? fahrradmitnahme;

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
    this.fahrradmitnahme,
  });

  /// Heuristic-based reply când server-ul nu spune explicit. RE/RB/S-Bahn/
  /// Tram/U-Bahn/Regional permit bicicletă gratis. ICE/IC/EC cere Reservierung.
  /// Bus – uneori doar Faltrad, deci = null (unknown).
  bool get bikeAllowedHeuristic {
    if (isWalk) return true;
    if (fahrradmitnahme != null) return fahrradmitnahme!;
    switch (productType) {
      case 'suburban':
      case 'regional':
      case 'tram':
      case 'subway':
        return true;
      case 'train':
        // Regional-Zug OK, ICE/IC/EC nu.
        final l = line.toUpperCase();
        if (l.startsWith('ICE') || l.startsWith('IC ') || l.startsWith('EC ')) return false;
        return true;
      default:
        return false;
    }
  }

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

class _CachedTripStops {
  final List<TripStop> stops;
  final List<(double, double)> path;
  final DateTime at;
  _CachedTripStops(this.stops, this.at, {this.path = const []});
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

/// Whether a Journey is likely to work for a wheelchair / stroller user
/// based on the DB FaSta elevator status at each transfer stop.
///
/// - `unknown`: no facility data for any checked stop (all bus stops,
///   or DB doesn't cover these stations) — don't punish, show as "?".
/// - `barrierFree`: every station we could check has working elevators.
/// - `brokenElevator`: at least one station has an INACTIVE elevator.
enum JourneyAccessibilityStatus { unknown, barrierFree, brokenElevator }

class JourneyAccessibility {
  final JourneyAccessibilityStatus status;
  /// Station names with an inactive elevator, in order.
  final List<String> brokenAt;
  /// Station names for which we successfully got facility data.
  final List<String> checked;

  const JourneyAccessibility({
    required this.status,
    this.brokenAt = const [],
    this.checked = const [],
  });

  static const unknown = JourneyAccessibility(status: JourneyAccessibilityStatus.unknown);

  String get germanLabel {
    switch (status) {
      case JourneyAccessibilityStatus.barrierFree:
        return 'Barrierefrei';
      case JourneyAccessibilityStatus.brokenElevator:
        return brokenAt.isEmpty
            ? 'Aufzug defekt'
            : 'Aufzug defekt: ${brokenAt.join(", ")}';
      case JourneyAccessibilityStatus.unknown:
        return 'Barrierefreiheit unbekannt';
    }
  }
}

/// A full journey option (departure → destination) with all legs
class Journey {
  final List<JourneyLeg> legs;
  final DateTime depTime;
  final DateTime arrTime;

  Journey({required this.legs, required this.depTime, required this.arrTime});

  /// Number of vehicle-to-vehicle transfers on this journey. Zero for
  /// direct connections OR walking-only routes (bahn.de sometimes returns
  /// pure Fußweg journeys under 500m — those aren't "transfers" either).
  /// Clamped at 0 so UI never renders "-1 ×".
  int get transfers {
    final vehicleLegs = legs.where((l) => !l.isWalk).length;
    return vehicleLegs > 0 ? vehicleLegs - 1 : 0;
  }
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
  // Added 2026-07: 8 providers verified live via agent research
  vms, vmt, vvw, vmv, vrt, vrs, wtp, vos,
  // Added 2026-07-09: DEFAS Bayern (state-wide EFA — covers Würzburg,
  // Regensburg, Passau, Landshut, Bayreuth, Kempten, Rosenheim), plus
  // AVV Augsburg (a distinct Verbund from AVV Aachen), plus VVV Vogtland.
  defasBayern, avvAugsburg, vve,
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
  /// Optional mic+mac request-signing salt (UTF-8 string). When set, every
  /// HAFAS POST body is signed with MD5(body) → `mic` and
  /// MD5(hex(mic) || salt) → `mac`, both appended as URL query params.
  /// Sources: public-transport/hafas-client `p/<name>/base.js` — see
  /// _hafasRequestUrl for the exact algorithm.
  final String? hafasSalt;

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
    this.hafasSalt,
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
    // Public AID from hafas-client repo (`p/saarfahrplan/base.js`). Env var
    // via `HAFAS_AID` --dart-define still overrides at build time (see
    // `_resolveAid`), so existing signed builds keep working; new builds
    // don't need the secret anymore.
    hafasAid: '51XfsVqgbdA6oXzHrx75jhlocRg6Xe',
    hafasClientType: 'AND', hafasVer: '1.40',
    // Bounding box widened to include Saarbrücken metro area's cross-border
    // stops (Forbach FR, Luxembourg City, Trier). Saarland-proper is
    // 49.09-49.65 / 6.30-7.405 — the extra padding catches through-services
    // that terminate outside Saarland proper.
    minLat: 48.95, maxLat: 49.85, minLon: 6.05, maxLon: 7.50,
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
    // mic+mac signing OBLIGATORIU — salt UTF-8 din hafas-client p/vbn/base.js.
    hafasSalt: 'SP31mBufSyCLmNxp',
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

  // ── Added 2026-07: 8 providers verified live via agent research ─────

  TransitProviderConfig(
    type: TransitProviderType.vms, api: TransitApiType.efa,
    name: 'VMS', displayName: 'VMS (Verkehrsverbund Mittelsachsen)',
    baseUrl: 'https://efa.vvo-online.de/VMSSL3',
    minLat: 50.10, maxLat: 51.05, minLon: 12.10, maxLon: 13.55,
  ),
  TransitProviderConfig(
    type: TransitProviderType.vmt, api: TransitApiType.hafas,
    name: 'VMT', displayName: 'VMT (Verkehrsverbund Mittelthüringen)',
    // Endpoint mutat 2026 la hafas.cloud SaaS + AID nou + ver 1.78 +
    // mic+mac signing OBLIGATORIU (else AUTH fail). Salt UTF-8 din
    // hafas-client p/vmt/base.js.
    baseUrl: 'https://vmt.eks-prod-euc1.hafas.cloud/bin/mgate.exe',
    hafasAid: 'web-vmt-qdr6c6y8s4cvfmfw',
    hafasClientId: 'HAFAS', hafasClientName: 'webapp',
    hafasClientType: 'WEB', hafasVer: '1.78',
    hafasSalt: '7x8d3n2a5m1b3c6z',
    minLat: 50.37, maxLat: 51.12, minLon: 10.16, maxLon: 12.17,
  ),
  TransitProviderConfig(
    type: TransitProviderType.vvw, api: TransitApiType.hafas,
    name: 'VVW', displayName: 'VVW / RSAG (Verkehrsverbund Warnow)',
    baseUrl: 'https://fahrplan.rsag-online.de/bin/mgate.exe',
    hafasAid: 'tF5JTs25rzUhGrrl',
    hafasClientId: 'RSAG', hafasClientName: 'webapp',
    hafasClientType: 'WEB', hafasVer: '1.42', hafasExt: 'VBN.2',
    // RSAG folosește backend-ul VBN → reuse VBN salt când primim AUTH.
    hafasSalt: 'SP31mBufSyCLmNxp',
    minLat: 53.63, maxLat: 54.27, minLon: 11.50, maxLon: 12.82,
  ),
  TransitProviderConfig(
    // NVBW/bwegt EFA install (nvbw3L path)
    type: TransitProviderType.vmv, api: TransitApiType.efa,
    name: 'VMV', displayName: 'VMV (Mecklenburg-Vorpommern)',
    baseUrl: 'https://www.efa-bw.de/nvbw3L',
    minLat: 53.05, maxLat: 54.92, minLon: 10.51, maxLon: 14.42,
  ),
  TransitProviderConfig(
    type: TransitProviderType.vrt, api: TransitApiType.efa,
    name: 'VRT', displayName: 'VRT (Verkehrsverbund Region Trier)',
    baseUrl: 'https://www.vrt-info.de/fahrplanauskunft',
    minLat: 49.53, maxLat: 50.39, minLon: 6.13, maxLon: 7.26,
  ),
  TransitProviderConfig(
    // KVB HAFAS backend serves Köln/Bonn + Rhein-Sieg-Kreis
    type: TransitProviderType.vrs, api: TransitApiType.hafas,
    name: 'VRS', displayName: 'VRS (Rhein-Sieg via KVB)',
    baseUrl: 'https://auskunft.kvb.koeln/gate',
    hafasAid: 'Rt6foY5zcTTRXMQs',
    hafasClientId: 'HAFAS', hafasClientVersion: '10008', hafasClientName: 'webapp',
    hafasClientType: 'WEB', hafasVer: '1.78',
    minLat: 50.5, maxLat: 51.2, minLon: 6.4, maxLon: 7.7,
  ),
  TransitProviderConfig(
    type: TransitProviderType.wtp, api: TransitApiType.efa,
    name: 'WestfalenTarif', displayName: 'WestfalenTarif (Münster/Bielefeld/Paderborn)',
    baseUrl: 'https://westfalenfahrplan.de/std3',
    minLat: 50.7, maxLat: 52.6, minLon: 6.6, maxLon: 9.5,
  ),
  TransitProviderConfig(
    type: TransitProviderType.vos, api: TransitApiType.hafas,
    name: 'VOS', displayName: 'VOS (Verkehrsgemeinschaft Osnabrück)',
    baseUrl: 'https://fahrplan.vos.info/bin/mgate.exe',
    hafasAid: 'PnYowCQP7Tp1V',
    hafasClientId: 'SWO', hafasClientName: 'webapp',
    hafasClientType: 'WEB', hafasVer: '1.24',
    minLat: 52.10, maxLat: 52.65, minLon: 7.60, maxLon: 8.55,
  ),

  // ── Added 2026-07-09: 3 providers verified live via curl ─────────────
  //
  // DEFAS Bayern (Datenaustausch-Format der ÖPNV-Systeme in Bayern) —
  // Bayernweiter EFA-Aggregator, deckt Würzburg (VVM), Regensburg (RVV),
  // Passau, Landshut, Bayreuth, Kempten, Rosenheim ab. Überschneidet sich
  // mit MVV (München) und VGN (Nürnberg): dort gewinnt der jeweilige
  // Verbund via city-list-Match. DEFAS greift wo weder MVV noch VGN passt.
  TransitProviderConfig(
    type: TransitProviderType.defasBayern, api: TransitApiType.efa,
    name: 'DEFAS-Bayern',
    displayName: 'DEFAS Bayern (Bayernweit — Würzburg, Regensburg, Passau …)',
    baseUrl: 'https://mobile.defas-fgi.de/beg',
    minLat: 47.27, maxLat: 50.57, minLon: 8.98, maxLon: 13.84,
  ),
  // AVV Augsburg — distinct from AVV Aachen (already listed as `avv`).
  // EFA classic endpoint, no auth.
  TransitProviderConfig(
    type: TransitProviderType.avvAugsburg, api: TransitApiType.efa,
    name: 'AVV-Augsburg',
    displayName: 'AVV Augsburg (Augsburger Verkehrs- und Tarifverbund)',
    baseUrl: 'https://fahrtauskunft.avv-augsburg.de/efa',
    // Stadt Augsburg + Landkreise Augsburg, Aichach-Friedberg, Dillingen.
    // Narrower than DEFAS Bayern so it wins for Augsburg proper via
    // nearest-centre in the geometry pass.
    minLat: 48.15, maxLat: 48.75, minLon: 10.30, maxLon: 11.15,
  ),
  // VVV Vogtland — small Verkehrsverbund, Plauen/Zwickau/Reichenbach corner.
  TransitProviderConfig(
    type: TransitProviderType.vve, api: TransitApiType.efa,
    name: 'VVV',
    displayName: 'VVV (Verkehrsverbund Vogtland — Plauen, Zwickau, Reichenbach)',
    baseUrl: 'https://vogtlandauskunft.de/std',
    minLat: 50.29, maxLat: 50.75, minLon: 11.86, maxLon: 12.65,
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

  // ════════════════════════════════════════════════════════════════
  // MEMBER HOME REGION — extras din Verifizierung Stufe 1
  // (ort/plz/bundesland al userului logat). Folosit ca fallback când
  // GPS-ul e off + pentru filtrarea providerilor la autocomplete →
  // interogăm doar cei relevanți geografic, nu toți 23.
  //
  // Prioritate rezolvare provider:
  //   1) GPS activat + fix precis → activeProvider = detected
  //   2) GPS off + Stufe-1 setat → activeProvider = derived from
  //      _memberHomeOrt / _memberHomePlz / _memberHomeBundesland
  //   3) Nimic → fallback la toți providerii (autocomplete lent)
  // ════════════════════════════════════════════════════════════════
  String? _memberHomeOrt;
  String? _memberHomePlz;
  String? _memberHomeBundesland;

  /// Setează adresa Verifizierung Stufe 1 al membrului logat.
  /// Called de dashboard când `_users` conține detaliile.
  /// null-values dezactivează câmpul respectiv.
  void setMemberHomeRegion({String? ort, String? plz, String? bundesland}) {
    _memberHomeOrt = ort?.trim().toLowerCase();
    _memberHomePlz = plz?.trim();
    _memberHomeBundesland = bundesland?.trim().toLowerCase();
    _log.info('Transit: home region set ort=$_memberHomeOrt plz=$_memberHomePlz '
        'bundesland=$_memberHomeBundesland', tag: 'TRANSIT');
    // BUG FIX 2026-07-11: NU mai auto-declanșa `_detectProviderFromMemberHome`.
    // Dashboard apelează asta ÎNAINTE ca GPS-ul să răspundă → Stufe-1 setează
    // coords la Ulm (Neu-Ulm home) chiar dacă userul e fizic în Saarbrücken.
    // Trigger-ul e făcut acum EXCLUSIV din `start()` cand GPS eșuează.
  }

  /// Detectează activeProvider din Verifizierung Stufe 1 (ort/plz/bundesland).
  /// Folosit când GPS-ul e off / lipsește. Setează _latitude/_longitude la
  /// centrul provider-ului găsit ca fallback pentru fetchDepartures.
  void _detectProviderFromMemberHome() {
    final ort = _memberHomeOrt;
    final plz = _memberHomePlz;
    final bl = _memberHomeBundesland;
    if (ort == null && plz == null && bl == null) return;

    // BUG FIX 2026-07-11: nu suprascrie coords GPS dacă sunt deja setate.
    // User poate fi fizic în Saarbrücken cu adresa Stufe-1 în Neu-Ulm →
    // păstrăm GPS coords reale, doar setăm provider dacă lipsește.
    final gpsAlreadySet = _useGps && _latitude != null && _longitude != null;

    // Match după city set — cea mai reliable metodă (~450 orașe mapate).
    for (final entry in _providerCities.entries) {
      for (final city in entry.value) {
        final cLow = city.toLowerCase();
        if (ort != null && (cLow == ort || cLow.contains(ort) || ort.contains(cLow))) {
          final p = _providers.firstWhere((x) => x.type == entry.key);
          activeProvider = p;
          if (!gpsAlreadySet) {
            // Center la mijloc bounding box.
            _latitude = (p.minLat + p.maxLat) / 2;
            _longitude = (p.minLon + p.maxLon) / 2;
            gpsCity = ort;
          }
          _log.info('Transit: provider ${p.name} matched from Stufe-1 ort=$ort '
              '${gpsAlreadySet ? "(GPS coords kept)" : "(coords set to center)"}',
              tag: 'TRANSIT');
          return;
        }
      }
    }
    // PLZ prefix fallback: primele 2 cifre indică region (ex. 66xxx=Saarland).
    // Map soft: PLZ 60-65 → RMV, 66 → saarVV, 89 → DING, 10-14 → VBB, etc.
    if (plz != null && plz.length >= 2) {
      final prefix = plz.substring(0, 2);
      TransitProviderType? guess;
      switch (prefix) {
        case '01': case '02': guess = TransitProviderType.vvo; break;   // Dresden
        case '04': guess = TransitProviderType.insa; break;              // Leipzig
        case '06': case '07': case '08': case '09':
          guess = TransitProviderType.insa; break;                       // Sachsen-Anhalt
        case '10': case '11': case '12': case '13': case '14':
          guess = TransitProviderType.vbb; break;                        // Berlin/Brandenburg
        case '15': case '16': case '17': case '18': case '19':
          guess = TransitProviderType.vbb; break;                        // Brandenburg/MV
        case '20': case '21': case '22':
          guess = TransitProviderType.vbn; break;                        // Hamburg-adjacent
        case '23': case '24': case '25':
          guess = TransitProviderType.nahsh; break;                      // Schleswig-Holstein
        case '26': case '27': case '28': case '29':
          guess = TransitProviderType.vbn; break;                        // Bremen/Niedersachsen
        case '30': case '31': case '32': case '33': case '37': case '38':
          guess = TransitProviderType.vbn; break;                        // Hannover/Braunschweig
        case '34': case '35': case '36':
          guess = TransitProviderType.nvv; break;                        // Nordhessen
        case '40': case '41': case '42': case '43': case '44': case '45': case '46': case '47':
          guess = TransitProviderType.vrr; break;                        // Rhein-Ruhr
        case '48': case '49':
          guess = TransitProviderType.wtp; break;                        // Westfalen
        case '50': case '51': case '53':
          guess = TransitProviderType.vrs; break;                        // Köln/Bonn
        case '52':
          guess = TransitProviderType.avv; break;                        // Aachen
        case '55': case '56': case '57':
          guess = TransitProviderType.rmv; break;                        // Rhein-Main/RLP
        case '58': case '59':
          guess = TransitProviderType.vrr; break;                        // Ruhr
        case '60': case '61': case '63': case '64': case '65':
          guess = TransitProviderType.rmv; break;                        // Frankfurt/RMV
        case '66':
          guess = TransitProviderType.saarvv; break;                     // Saarland
        case '67': case '68': case '69':
          guess = TransitProviderType.vrn; break;                        // Rhein-Neckar
        case '70': case '71': case '72': case '73': case '74':
          guess = TransitProviderType.vvs; break;                        // Stuttgart
        case '75': case '76':
          guess = TransitProviderType.kvv; break;                        // Karlsruhe
        case '77': case '78': case '79':
          guess = TransitProviderType.naldo; break;                      // Tübingen/Reutlingen
        case '80': case '81': case '82': case '83': case '84': case '85':
          guess = TransitProviderType.mvv; break;                        // München
        case '86':
          guess = TransitProviderType.avvAugsburg; break;                // Augsburg
        case '87': case '88':
          guess = TransitProviderType.defasBayern; break;                // Kempten/Rosenheim
        case '89':
          guess = TransitProviderType.ding; break;                       // Ulm
        case '90': case '91': case '92':
          guess = TransitProviderType.vgn; break;                        // Nürnberg
        case '93': case '94': case '95':
          guess = TransitProviderType.defasBayern; break;                // Regensburg/Passau
        case '96': case '97':
          guess = TransitProviderType.vgn; break;                        // Bamberg/Würzburg
        case '98': case '99':
          guess = TransitProviderType.vmt; break;                        // Thüringen
      }
      if (guess != null) {
        try {
          final p = _providers.firstWhere((x) => x.type == guess);
          activeProvider = p;
          if (!gpsAlreadySet) {
            _latitude = (p.minLat + p.maxLat) / 2;
            _longitude = (p.minLon + p.maxLon) / 2;
          }
          _log.info('Transit: provider ${p.name} matched from Stufe-1 PLZ=$plz '
              '(prefix $prefix) ${gpsAlreadySet ? "(GPS coords kept)" : ""}',
              tag: 'TRANSIT');
          return;
        } catch (_) {}
      }
    }
    _log.debug('Transit: could not match provider from Stufe-1 '
        'ort=$ort plz=$plz bundesland=$bl', tag: 'TRANSIT');
  }

  /// Returnează providerii relevanți pentru membrul curent (Stufe-1 + GPS).
  /// Reduce lista de la 23 la 3-6 candidați → autocomplete 3× mai rapid +
  /// zero AUTH-spam de la provideri nerelevanți.
  ///
  /// Include:
  ///   • activeProvider (dacă e setat)
  ///   • provideri ale căror bounding-box include coords GPS (dacă avem GPS)
  ///   • provideri ale căror city-list overlaps cu ort-ul membrului
  ///
  /// Dacă nu găsim niciun match → returnăm toată lista (fallback fail-open).
  List<TransitProviderConfig> _relevantProviders() {
    final relevant = <TransitProviderConfig>{};
    if (activeProvider != null) relevant.add(activeProvider!);

    // GPS-based: bounding box hit.
    final lat = _latitude;
    final lon = _longitude;
    if (lat != null && lon != null) {
      for (final p in _providers) {
        if (p.containsCoord(lat, lon)) relevant.add(p);
      }
    }

    // Stufe-1 based: match după ort în city list.
    final ort = _memberHomeOrt;
    if (ort != null && ort.isNotEmpty) {
      for (final entry in _providerCities.entries) {
        for (final city in entry.value) {
          if (city.toLowerCase().contains(ort) || ort.contains(city.toLowerCase())) {
            try {
              final p = _providers.firstWhere((x) => x.type == entry.key);
              relevant.add(p);
              break;
            } catch (_) {}
          }
        }
      }
    }

    if (relevant.isEmpty) return _providers; // fallback fail-open
    return relevant.toList();
  }

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
    } else if (_memberHomeOrt != null || _memberHomePlz != null) {
      // GPS denied/unavailable → derive provider din Verifizierung Stufe 1.
      _detectProviderFromMemberHome();
      if (activeProvider == null) {
        _log.info('Transit: No provider derivable from Stufe-1, skipping', tag: 'TRANSIT');
        return;
      }
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

    // Detect provider based on coordinates.
    // BUG FIX 2026-07-11: dacă GPS-ul a răspuns cu succes, REDETECTEAZĂ mereu
    // provider-ul pe baza coords real GPS — nu ține activeProvider setat
    // greșit din Stufe-1 override (user poate fi fizic în alt oraș decât
    // adresa Verifizierung Stufe 1).
    if (_useGps) {
      _detectProvider(); // GPS = truth, ignore Stufe-1 preset
    } else if (activeProvider == null) {
      _detectProvider();
    }

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

  /// True while the coarse (100m-filter, dashboard) stream is paused because
  /// a fine-grained consumer (trip map, Ausstieg-Alarm) is active. Prevents
  /// running two Geolocator streams in parallel = ~2× battery drain.
  bool _coarseTrackingPaused = false;
  int _fineConsumerCount = 0;

  /// Called by TripMapView on initState. If it's the first fine consumer,
  /// suspends the coarse tracker until [resumeCoarseTracking] balances it.
  void pauseCoarseTracking() {
    _fineConsumerCount++;
    if (_fineConsumerCount == 1 && _positionSub != null) {
      _coarseTrackingPaused = true;
      _positionSub?.cancel();
      _positionSub = null;
      _log.debug('Transit: coarse tracking paused (fine consumer active)', tag: 'TRANSIT');
    }
  }

  /// Called by TripMapView on dispose. Restarts the coarse stream when the
  /// last fine consumer leaves.
  void resumeCoarseTracking() {
    if (_fineConsumerCount > 0) _fineConsumerCount--;
    if (_fineConsumerCount == 0 && _coarseTrackingPaused && _useGps) {
      _coarseTrackingPaused = false;
      _startPositionStream();
      _log.debug('Transit: coarse tracking resumed', tag: 'TRANSIT');
    }
  }

  /// Map of provider → set of city/Landkreis names it serves.
  /// Compiled from each Verkehrsverbund's official coverage page (Wikipedia
  /// tarifgebiet lists + Verbund-Websites), covering all cities with ≥20k
  /// residents plus all Landkreise/Kreise. ~450 entries total.
  ///
  /// All names lowercased; matching is substring both ways so "Neu-Ulm"
  /// matches "neu-ulm" and vice versa.
  ///
  /// **Uncovered German regions** (no provider implemented yet, trip search
  /// falls through to bahn.de):
  ///  • Hamburg → HVV (uses GeoFox/GTI protocol, needs separate parser)
  ///  • Chemnitz → VMS
  ///  • Erfurt/Jena/Weimar/Gera → VMT
  ///  • Leipzig/Halle-region → MDV
  ///  • Freiburg → RVF
  ///  • Trier → VRT
  ///  • Konstanz → VHB
  ///  • Rostock → VVW
  ///  • Schwerin → VMV (no classic Verbund)
  ///  • Koblenz → VRM
  ///  • Hannover → GVH
  ///  • Braunschweig/Wolfsburg → VRB
  ///  • Göttingen → VSN
  ///  • Köln/Bonn → VRS
  ///  • Münster/Bielefeld/Paderborn → WestfalenTarif
  static const Map<TransitProviderType, Set<String>> _providerCities = {
    TransitProviderType.ding: {
      'ulm', 'neu-ulm', 'senden', 'ehingen', 'biberach an der riß', 'biberach',
      'laupheim', 'illertissen', 'vöhringen', 'weißenhorn', 'riedlingen',
      'blaubeuren', 'laichingen', 'langenau', 'blaustein', 'munderkingen',
      'erbach', 'dietenheim', 'landkreis alb-donau-kreis', 'alb-donau-kreis',
      'landkreis biberach', 'landkreis neu-ulm',
    },
    TransitProviderType.mvv: {
      'münchen', 'munich', 'landshut', 'rosenheim', 'freising', 'dachau',
      'germering', 'fürstenfeldbruck', 'erding', 'unterschleißheim', 'olching',
      'puchheim', 'garching bei münchen', 'garching', 'starnberg',
      'wolfratshausen', 'bad tölz', 'ebersberg', 'miesbach', 'mühldorf am inn',
      'landsberg am lech', 'weilheim in oberbayern', 'weilheim',
      'garmisch-partenkirchen', 'poing', 'karlsfeld', 'oberhaching',
      'unterhaching', 'ottobrunn', 'gräfelfing', 'planegg', 'taufkirchen',
      'landkreis bad tölz-wolfratshausen', 'landkreis dachau',
      'landkreis ebersberg', 'landkreis erding', 'landkreis freising',
      'landkreis fürstenfeldbruck', 'landkreis garmisch-partenkirchen',
      'landkreis landsberg am lech', 'landkreis landshut', 'landkreis miesbach',
      'landkreis mühldorf am inn', 'landkreis münchen', 'landkreis rosenheim',
      'landkreis starnberg', 'landkreis weilheim-schongau',
    },
    TransitProviderType.vvs: {
      'stuttgart', 'esslingen am neckar', 'esslingen', 'ludwigsburg',
      'sindelfingen', 'böblingen', 'leonberg', 'waiblingen', 'fellbach',
      'göppingen', 'filderstadt', 'kirchheim unter teck', 'kirchheim',
      'leinfelden-echterdingen', 'nürtingen', 'ostfildern', 'schorndorf',
      'bietigheim-bissingen', 'backnang', 'herrenberg', 'kornwestheim',
      'winnenden', 'vaihingen an der enz', 'weinstadt',
      'geislingen an der steige', 'remseck am neckar', 'ditzingen',
      'eislingen/fils', 'metzingen', 'plochingen', 'marbach am neckar',
      'landkreis böblingen', 'landkreis esslingen', 'landkreis ludwigsburg',
      'rems-murr-kreis', 'landkreis göppingen',
    },
    TransitProviderType.kvv: {
      'karlsruhe', 'pforzheim', 'baden-baden', 'landau in der pfalz',
      'landau', 'rastatt', 'bruchsal', 'ettlingen', 'gaggenau', 'bühl',
      'bretten', 'mühlacker', 'stutensee', 'waghäusel', 'rheinstetten',
      'germersheim', 'philippsburg', 'landkreis karlsruhe',
      'landkreis rastatt', 'landkreis germersheim',
      'landkreis südliche weinstraße', 'enzkreis',
    },
    TransitProviderType.naldo: {
      'tübingen', 'reutlingen', 'albstadt', 'rottenburg am neckar',
      'rottenburg', 'balingen', 'metzingen', 'mössingen', 'hechingen',
      'sigmaringen', 'bad saulgau', 'bad urach', 'münsingen', 'meßstetten',
      'mengen', 'pfullendorf', 'gammertingen', 'landkreis reutlingen',
      'landkreis tübingen', 'landkreis sigmaringen', 'zollernalbkreis',
    },
    TransitProviderType.vrn: {
      'mannheim', 'heidelberg', 'ludwigshafen am rhein', 'ludwigshafen',
      'kaiserslautern', 'worms', 'neustadt an der weinstraße', 'neustadt',
      'speyer', 'frankenthal', 'landau in der pfalz', 'pirmasens',
      'zweibrücken', 'weinheim', 'sinsheim', 'schwetzingen', 'walldorf',
      'wiesloch', 'bad dürkheim', 'grünstadt', 'edenkoben', 'deidesheim',
      'rhein-neckar-kreis', 'landkreis rhein-neckar-kreis',
      'neckar-odenwald-kreis', 'main-tauber-kreis', 'landkreis bergstraße',
      'landkreis alzey-worms', 'landkreis bad dürkheim', 'donnersbergkreis',
      'landkreis germersheim', 'landkreis kaiserslautern', 'landkreis kusel',
      'rhein-pfalz-kreis', 'landkreis südliche weinstraße',
      'landkreis südwestpfalz',
    },
    TransitProviderType.vgn: {
      'nürnberg', 'nurnberg', 'fürth', 'erlangen', 'schwabach', 'ansbach',
      'bamberg', 'bayreuth', 'coburg', 'hof', 'amberg',
      'weiden in der oberpfalz', 'weiden', 'forchheim', 'hersbruck',
      'altdorf bei nürnberg', 'zirndorf', 'oberasbach', 'feucht',
      'herzogenaurach', 'landkreis nürnberger land', 'nürnberger land',
      'landkreis fürth', 'landkreis roth', 'landkreis erlangen-höchstadt',
      'landkreis forchheim', 'landkreis ansbach', 'landkreis bamberg',
      'landkreis bayreuth', 'landkreis coburg', 'landkreis hof',
      'landkreis amberg-sulzbach', 'landkreis neumarkt in der oberpfalz',
      'landkreis neustadt an der aisch-bad windsheim',
      'landkreis neustadt an der waldnaab', 'landkreis kitzingen',
      'landkreis haßberge', 'landkreis kronach', 'landkreis kulmbach',
      'landkreis lichtenfels', 'landkreis tirschenreuth',
      'landkreis weißenburg-gunzenhausen',
      'landkreis wunsiedel im fichtelgebirge', 'landkreis donau-ries',
    },
    TransitProviderType.avv: {
      'aachen', 'eschweiler', 'stolberg', 'alsdorf', 'herzogenrath',
      'würselen', 'baesweiler', 'monschau', 'düren', 'jülich', 'erkelenz',
      'heinsberg', 'hückelhoven', 'geilenkirchen', 'wegberg',
      'übach-palenberg', 'roetgen', 'städteregion aachen', 'kreis düren',
      'kreis heinsberg',
    },
    TransitProviderType.vrr: {
      'düsseldorf', 'duisburg', 'essen', 'dortmund', 'bochum', 'wuppertal',
      'mönchengladbach', 'krefeld', 'oberhausen', 'hagen',
      'mülheim an der ruhr', 'mülheim', 'solingen', 'herne', 'remscheid',
      'gelsenkirchen', 'bottrop', 'neuss', 'ratingen', 'velbert',
      'recklinghausen', 'marl', 'dorsten', 'gladbeck', 'castrop-rauxel',
      'herten', 'datteln', 'haltern am see', 'oer-erkenschwick', 'witten',
      'hattingen', 'ennepetal', 'gevelsberg', 'schwelm', 'wetter (ruhr)',
      'sprockhövel', 'herdecke', 'moers', 'dinslaken', 'wesel', 'kleve',
      'geldern', 'goch', 'emmerich am rhein', 'kevelaer', 'viersen',
      'willich', 'nettetal', 'kempen', 'tönisvorst', 'dormagen',
      'grevenbroich', 'meerbusch', 'kaarst', 'korschenbroich',
      'langenfeld (rheinland)', 'langenfeld', 'hilden', 'erkrath',
      'monheim am rhein', 'monheim', 'mettmann', 'haan', 'heiligenhaus',
      'ruhr', 'rhein-ruhr', 'ennepe-ruhr-kreis', 'kreis kleve',
      'kreis mettmann', 'kreis recklinghausen', 'rhein-kreis neuss',
      'kreis viersen', 'kreis wesel',
    },
    TransitProviderType.vvo: {
      'dresden', 'hoyerswerda', 'pirna', 'meißen', 'freital', 'radebeul',
      'riesa', 'radeberg', 'großenhain', 'kamenz', 'dippoldiswalde',
      'sebnitz', 'bischofswerda', 'coswig', 'bautzen',
      'sächsische schweiz', 'landkreis bautzen', 'landkreis meißen',
      'landkreis sächsische schweiz-osterzgebirge',
    },
    TransitProviderType.saarvv: {
      'saarland', 'saarbrücken', 'saarbrucken', 'saarbrueckn',
      'neunkirchen', 'homburg', 'völklingen', 'voelklingen',
      'st. ingbert', 'st ingbert', 'sankt ingbert',
      'saarlouis', 'saar louis',
      'st. wendel', 'st wendel', 'sankt wendel',
      'dillingen', 'dillingen/saar',
      'merzig', 'blieskastel', 'sulzbach', 'sulzbach/saar',
      'püttlingen', 'puettlingen',
      'regionalverband saarbrücken', 'stadtverband saarbrücken',
      'landkreis merzig-wadern', 'kreis merzig-wadern',
      'landkreis neunkirchen', 'kreis neunkirchen',
      'landkreis saarlouis', 'kreis saarlouis',
      'saarpfalz-kreis', 'saarpfalzkreis',
      'landkreis st. wendel', 'kreis st. wendel',
      // Small towns often geocoded from bus stops
      'friedrichsthal', 'quierschied', 'riegelsberg', 'heusweiler',
      'kleinblittersdorf', 'grossrosseln', 'großrosseln', 'wadgassen',
      'ensdorf', 'schwalbach', 'bous', 'überherrn', 'ueberherrn',
      'losheim', 'weiskirchen', 'perl', 'mettlach', 'beckingen',
      'wadern', 'lebach', 'schmelz', 'nalbach', 'nonnweiler',
      'nohfelden', 'tholey', 'freisen', 'namborn', 'oberthal', 'marpingen',
      'illingen', 'ottweiler', 'eppelborn', 'spiesen-elversberg',
      'bexbach', 'kirkel', 'mandelbachtal', 'gersheim',
    },
    TransitProviderType.nvv: {
      'kassel', 'bad hersfeld', 'baunatal', 'korbach', 'eschwege',
      'frankenberg (eder)', 'frankenberg', 'schwalmstadt', 'bad wildungen',
      'bad arolsen', 'fritzlar', 'homberg (efze)', 'homberg', 'melsungen',
      'witzenhausen', 'hofgeismar', 'rotenburg an der fulda', 'rotenburg',
      'bebra', 'hessisch lichtenau', 'wolfhagen', 'vellmar', 'lohfelden',
      'niestetal', 'landkreis kassel', 'landkreis hersfeld-rotenburg',
      'landkreis waldeck-frankenberg', 'schwalm-eder-kreis',
      'werra-meißner-kreis',
    },
    TransitProviderType.rmv: {
      'frankfurt am main', 'frankfurt', 'wiesbaden', 'darmstadt',
      'offenbach am main', 'offenbach', 'hanau', 'fulda', 'gießen',
      'marburg', 'wetzlar', 'bad homburg vor der höhe', 'bad homburg',
      'rüsselsheim am main', 'rüsselsheim', 'limburg an der lahn',
      'limburg', 'aschaffenburg', 'oberursel', 'kronberg', 'königstein',
      'dreieich', 'langen', 'hofheim am taunus', 'hofheim', 'eschborn',
      'bad vilbel', 'bad soden', 'bad nauheim', 'bensheim',
      // VRM Rhein-Mosel (Koblenz) served by RMV HAFAS backend
      'koblenz', 'neuwied', 'andernach', 'mayen', 'bad ems',
      'landkreis mayen-koblenz', 'landkreis neuwied', 'landkreis cochem-zell',
      'westerwaldkreis', 'rhein-lahn-kreis', 'rhein-hunsrück-kreis',
      // Original RMV
      'landkreis darmstadt-dieburg', 'landkreis fulda', 'landkreis gießen',
      'landkreis groß-gerau', 'hochtaunuskreis', 'lahn-dill-kreis',
      'landkreis limburg-weilburg', 'main-kinzig-kreis', 'main-taunus-kreis',
      'landkreis marburg-biedenkopf', 'odenwaldkreis', 'landkreis offenbach',
      'rheingau-taunus-kreis', 'vogelsbergkreis', 'wetteraukreis',
    },
    TransitProviderType.nahsh: {
      'schleswig-holstein', 'kiel', 'lübeck', 'flensburg', 'norderstedt',
      'neumünster', 'elmshorn', 'pinneberg', 'wedel', 'ahrensburg',
      'geesthacht', 'itzehoe', 'rendsburg', 'reinbek', 'henstedt-ulzburg',
      'schleswig', 'bad oldesloe', 'husum', 'kaltenkirchen', 'quickborn',
      'heide', 'eckernförde', 'glückstadt', 'brunsbüttel', 'eutin',
      'plön', 'preetz', 'ratzeburg', 'mölln', 'kreis dithmarschen',
      'kreis herzogtum lauenburg', 'kreis nordfriesland', 'kreis ostholstein',
      'kreis pinneberg', 'kreis plön', 'kreis rendsburg-eckernförde',
      'kreis schleswig-flensburg', 'kreis segeberg', 'kreis steinburg',
      'kreis stormarn',
    },
    TransitProviderType.insa: {
      'sachsen-anhalt', 'magdeburg', 'halle (saale)', 'halle',
      'dessau-roßlau', 'dessau', 'stendal', 'weißenfels', 'halberstadt',
      'bitterfeld-wolfen', 'bitterfeld', 'merseburg', 'wernigerode',
      'naumburg (saale)', 'naumburg', 'bernburg (saale)', 'bernburg',
      'schönebeck (elbe)', 'schönebeck', 'zeitz', 'sangerhausen',
      'zerbst/anhalt', 'zerbst', 'aschersleben', 'staßfurt', 'quedlinburg',
      'haldensleben', 'oschersleben', 'thale', 'wittenberg',
      // MDV — Mitteldeutscher Verkehrsverbund is served by INSA/NASA HAFAS
      'leipzig', 'landkreis leipzig', 'landkreis nordsachsen', 'grimma',
      'delitzsch', 'wurzen', 'markkleeberg', 'borna', 'schkeuditz', 'oschatz',
      // Original INSA
      'altmarkkreis salzwedel', 'salzwedel',
      'landkreis anhalt-bitterfeld', 'landkreis börde', 'burgenlandkreis',
      'landkreis harz', 'landkreis jerichower land',
      'landkreis mansfeld-südharz', 'saalekreis', 'salzlandkreis',
      'landkreis stendal', 'landkreis wittenberg',
    },
    TransitProviderType.vbn: {
      'bremen', 'bremerhaven', 'oldenburg', 'delmenhorst',
      'wilhelmshaven', 'cuxhaven', 'nordenham', 'vechta', 'diepholz',
      'aurich', 'emden', 'leer', 'papenburg', 'jever', 'varel',
      // GVH (Hannover) & VRB (Braunschweig/Wolfsburg) served by VBN HAFAS
      'hannover', 'garbsen', 'langenhagen', 'laatzen', 'hemmingen',
      'ronnenberg', 'seelze', 'burgdorf', 'lehrte', 'wunstorf',
      'landkreis hannover', 'region hannover',
      'braunschweig', 'wolfsburg', 'salzgitter', 'peine', 'gifhorn',
      'wolfenbüttel', 'goslar', 'landkreis peine', 'landkreis gifhorn',
      'landkreis wolfenbüttel', 'landkreis helmstedt', 'landkreis goslar',
      'landkreis northeim',
      // Original VBN Landkreise
      'landkreis ammerland', 'landkreis diepholz', 'landkreis oldenburg',
      'landkreis osterholz', 'landkreis verden', 'landkreis wesermarsch',
      'landkreis cuxhaven', 'landkreis nienburg',
      'landkreis rotenburg (wümme)', 'landkreis rotenburg',
    },
    TransitProviderType.vbb: {
      'berlin', 'brandenburg', 'potsdam', 'cottbus',
      'brandenburg an der havel', 'frankfurt (oder)', 'frankfurt/oder',
      'oranienburg', 'falkensee', 'bernau bei berlin', 'bernau',
      'eberswalde', 'königs wusterhausen', 'schwedt/oder', 'schwedt',
      'fürstenwalde/spree', 'fürstenwalde', 'neuruppin', 'ludwigsfelde',
      'strausberg', 'teltow', 'werder (havel)', 'hohen neuendorf',
      'hennigsdorf', 'eisenhüttenstadt', 'rathenow', 'senftenberg',
      'landkreis barnim', 'landkreis dahme-spreewald',
      'landkreis elbe-elster', 'landkreis havelland',
      'landkreis märkisch-oderland', 'landkreis oberhavel',
      'landkreis oberspreewald-lausitz', 'landkreis oder-spree',
      'landkreis ostprignitz-ruppin', 'landkreis potsdam-mittelmark',
      'landkreis prignitz', 'landkreis spree-neiße',
      'landkreis teltow-fläming', 'landkreis uckermark',
    },

    // ── 8 newly-added providers (verified live 2026-07) ──

    TransitProviderType.vms: {
      'chemnitz', 'zwickau', 'plauen', 'freiberg', 'mittweida',
      'annaberg-buchholz', 'aue', 'schwarzenberg', 'stollberg', 'werdau',
      'crimmitschau', 'reichenbach im vogtland', 'oelsnitz',
      'landkreis mittelsachsen', 'landkreis zwickau', 'erzgebirgskreis',
      'vogtlandkreis',
    },
    TransitProviderType.vmt: {
      'erfurt', 'jena', 'weimar', 'gera', 'eisenach', 'gotha', 'mühlhausen',
      'nordhausen', 'suhl', 'meiningen', 'arnstadt', 'apolda', 'sonneberg',
      'saalfeld', 'ilmenau', 'greiz', 'altenburg', 'sömmerda', 'bad langensalza',
      'schmalkalden', 'rudolstadt', 'landkreis gotha', 'landkreis nordhausen',
      'landkreis eichsfeld', 'landkreis kyffhäuserkreis', 'kyffhäuserkreis',
      'landkreis sömmerda', 'landkreis weimarer land', 'landkreis saale-holzland',
      'landkreis saale-orla-kreis', 'landkreis saalfeld-rudolstadt',
      'landkreis ilm-kreis', 'ilm-kreis', 'landkreis unstrut-hainich-kreis',
      'unstrut-hainich-kreis', 'landkreis wartburgkreis', 'wartburgkreis',
      'landkreis schmalkalden-meiningen', 'landkreis hildburghausen',
      'landkreis sonneberg', 'landkreis greiz', 'landkreis altenburger land',
      'altenburger land', 'thüringen',
    },
    TransitProviderType.vvw: {
      'rostock', 'bad doberan', 'ribnitz-damgarten', 'graal-müritz',
      'kühlungsborn', 'warnemünde', 'güstrow', 'teterow',
      'landkreis rostock', 'landkreis bad doberan',
    },
    TransitProviderType.vmv: {
      'schwerin', 'wismar', 'greifswald', 'stralsund', 'neubrandenburg',
      'neustrelitz', 'waren (müritz)', 'waren', 'parchim', 'ludwigslust',
      'anklam', 'demmin', 'bergen auf rügen', 'bergen', 'ueckermünde',
      'pasewalk', 'malchin', 'landkreis nordwestmecklenburg',
      'landkreis ludwigslust-parchim', 'landkreis mecklenburgische seenplatte',
      'landkreis vorpommern-greifswald', 'landkreis vorpommern-rügen',
      'mecklenburg-vorpommern',
    },
    TransitProviderType.vrt: {
      'trier', 'bitburg', 'wittlich', 'daun', 'prüm', 'saarburg',
      'hermeskeil', 'gerolstein', 'landkreis trier-saarburg',
      'eifelkreis bitburg-prüm', 'landkreis bernkastel-wittlich',
      'landkreis vulkaneifel',
    },
    TransitProviderType.vrs: {
      // Rhein-Sieg — Köln/Bonn agglomeration + Bergisch Land
      'köln', 'koeln', 'bonn', 'leverkusen', 'rösrath', 'bergisch gladbach',
      'siegburg', 'sankt augustin', 'troisdorf', 'hennef', 'lohmar',
      'niederkassel', 'wesseling', 'brühl', 'hürth', 'frechen', 'pulheim',
      'bergheim', 'kerpen', 'erftstadt', 'euskirchen', 'mechernich',
      'schleiden', 'rhein-sieg-kreis', 'rhein-erft-kreis',
      'rheinisch-bergischer kreis', 'oberbergischer kreis',
      'kreis euskirchen',
    },
    TransitProviderType.wtp: {
      // WestfalenTarif — Nordrhein-Westfalen east + Münsterland
      'münster', 'muenster', 'bielefeld', 'paderborn', 'gütersloh',
      'minden', 'detmold', 'lippstadt', 'lüdenscheid', 'iserlohn',
      'siegen', 'arnsberg', 'hamm', 'unna', 'soest', 'coesfeld',
      'ahlen', 'rheine', 'gronau', 'ibbenbüren', 'warendorf', 'beckum',
      'oelde', 'bad salzuflen', 'herford', 'löhne', 'bünde',
      'landkreis borken', 'landkreis coesfeld', 'landkreis steinfurt',
      'landkreis warendorf', 'landkreis gütersloh', 'landkreis herford',
      'landkreis lippe', 'landkreis minden-lübbecke', 'landkreis höxter',
      'landkreis paderborn', 'kreis soest', 'hochsauerlandkreis',
      'märkischer kreis', 'landkreis olpe', 'landkreis siegen-wittgenstein',
      'kreis unna', 'westfalen',
    },
    TransitProviderType.vos: {
      'osnabrück', 'osnabrueck', 'melle', 'georgsmarienhütte', 'bramsche',
      'quakenbrück', 'bad iburg', 'dissen', 'wallenhorst',
      'landkreis osnabrück',
    },
    // DEFAS Bayern — state-wide aggregator, NOT for München (MVV wins) or
    // Nürnberg-Fürth-Erlangen (VGN wins). List only Bavarian cities not
    // covered by MVV/VGN city lists.
    TransitProviderType.defasBayern: {
      // Franken (excl. Nürnberg region)
      'würzburg', 'wuerzburg', 'schweinfurt', 'aschaffenburg', 'bad kissingen',
      'kitzingen', 'lohr am main', 'miltenberg', 'hassfurt', 'haßfurt',
      'bad neustadt', 'bad neustadt an der saale',
      'landkreis würzburg', 'landkreis schweinfurt', 'landkreis aschaffenburg',
      'landkreis bad kissingen', 'landkreis kitzingen', 'landkreis miltenberg',
      'landkreis haßberge', 'landkreis rhön-grabfeld',
      // Oberpfalz
      'regensburg', 'weiden', 'weiden i.d.opf.', 'amberg', 'neumarkt',
      'schwandorf', 'cham', 'tirschenreuth',
      'landkreis regensburg', 'landkreis cham', 'landkreis schwandorf',
      'landkreis neumarkt in der oberpfalz', 'landkreis amberg-sulzbach',
      // Niederbayern
      'passau', 'landshut', 'deggendorf', 'straubing', 'kelheim', 'landau',
      'landkreis passau', 'landkreis landshut', 'landkreis deggendorf',
      'landkreis straubing-bogen', 'landkreis kelheim',
      'landkreis rottal-inn', 'landkreis freyung-grafenau',
      'landkreis regen', 'landkreis dingolfing-landau',
      // Oberfranken
      'bayreuth', 'bamberg', 'coburg', 'kulmbach', 'hof', 'kronach',
      'lichtenfels', 'forchheim',
      'landkreis bayreuth', 'landkreis bamberg', 'landkreis coburg',
      'landkreis hof', 'landkreis kulmbach', 'landkreis kronach',
      'landkreis lichtenfels', 'landkreis wunsiedel',
      // Schwaben (excl. Augsburg = own AVV Augsburg provider)
      'kempten', 'memmingen', 'kaufbeuren', 'lindau', 'sonthofen',
      'füssen', 'fuessen', 'oberstdorf', 'bad wörishofen',
      'landkreis oberallgäu', 'landkreis unterallgäu', 'landkreis ostallgäu',
      'landkreis lindau', 'landkreis günzburg', 'landkreis dillingen an der donau',
      // Oberbayern south (not MVV)
      'rosenheim', 'traunstein', 'berchtesgaden', 'bad reichenhall',
      'garmisch-partenkirchen', 'mühldorf', 'muehldorf', 'burghausen',
      'weilheim', 'bad tölz',
      'landkreis rosenheim', 'landkreis traunstein', 'landkreis mühldorf am inn',
      'landkreis berchtesgadener land', 'landkreis altötting',
      'landkreis garmisch-partenkirchen', 'landkreis weilheim-schongau',
      'landkreis bad tölz-wolfratshausen', 'landkreis miesbach',
      'landkreis eichstätt', 'ingolstadt', 'landkreis ingolstadt',
    },
    // AVV Augsburg — city + surrounding Landkreise
    TransitProviderType.avvAugsburg: {
      'augsburg', 'friedberg', 'aichach', 'meitingen', 'gersthofen',
      'königsbrunn', 'koenigsbrunn', 'stadtbergen', 'bobingen',
      'neusäß', 'neusaess', 'schwabmünchen', 'schwabmuenchen',
      'landkreis augsburg', 'landkreis aichach-friedberg',
      'landkreis dillingen', 'dillingen an der donau',
    },
    // VVV Vogtland
    TransitProviderType.vve: {
      'plauen', 'zwickau', 'reichenbach', 'auerbach', 'oelsnitz', 'klingenthal',
      'markneukirchen', 'falkenstein', 'rodewisch', 'treuen',
      'vogtlandkreis', 'landkreis vogtland',
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

    // Step 1: city name match — 3 passes to avoid false substring matches
    //   Pass 1: EXACT match (city == catalog entry) — strongest, wins first
    //   Pass 2: WORD-BOUNDARY match (catalog entry is a whole token in city
    //           name, or vice versa) — catches "Bergisch Gladbach" via "bonn"
    //           without letting "Neubrandenburg" false-match "brandenburg"
    //   Pass 3: fall through to bounding-box geometry
    if (gpsCity != null && gpsCity!.isNotEmpty) {
      final cityLower = gpsCity!.toLowerCase();
      final cityTokens = cityLower.split(RegExp(r'[\s,\-()/]+')).where((t) => t.isNotEmpty).toSet();

      // Pass 1 — exact match on whole gpsCity string
      for (final p in _providers) {
        final cities = _providerCities[p.type];
        if (cities == null) continue;
        if (cities.contains(cityLower)) {
          activeProvider = p;
          _log.info('Transit: gpsCity "$gpsCity" EXACT match ${p.name}', tag: 'TRANSIT');
          return;
        }
      }

      // Pass 2 — word-boundary. A catalog entry counts as a token match if
      // every one of its own tokens appears in the city's token set (so
      // "münster" doesn't match "neumünster", and "gera" doesn't match
      // "landkreis groß-gerau").
      for (final p in _providers) {
        final cities = _providerCities[p.type];
        if (cities == null) continue;
        for (final c in cities) {
          final catTokens = c.split(RegExp(r'[\s,\-()/]+')).where((t) => t.isNotEmpty).toList();
          if (catTokens.isEmpty) continue;
          if (catTokens.every(cityTokens.contains)) {
            activeProvider = p;
            _log.info('Transit: gpsCity "$gpsCity" TOKEN match ${p.name} (via "$c")', tag: 'TRANSIT');
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

      // NOTE: apeluri la bahn.de (v6.db.transport.rest) NU se fac in main
      // flow — sunt on-demand, doar cand UI-ul deschide tab-ul Bhf via
      // `fetchBhfNearby()`. Restul tab-urilor (Bus/Tram/S-Bhf/U-Bhf)
      // folosesc EXCLUSIV provider-ul local activ (DING/MVV/HAFAS) →
      // zero trafic la bahn.de pentru scenarii bus/tram-only.
    } catch (e) {
      _log.error('Transit: Fetch failed: $e', tag: 'TRANSIT');
    }

    isLoading = false;
    onDeparturesUpdate?.call(departures);

    // Persist the successful snapshot for offline fallback. Best-effort;
    // failure to write is silent (SharedPreferences errors shouldn't
    // affect the current fetch flow).
    if (departures.isNotEmpty || nearbyStops.isNotEmpty) {
      TransitOfflineCache.save(
        stops: nearbyStops,
        departures: departures,
        city: gpsCity ?? city,
      );
    }
  }

  /// Best-effort offline fallback: if the current in-memory departures list
  /// is empty AND we have a persisted snapshot, populate from cache and
  /// return the snapshot for freshness-banner rendering. Returns null if
  /// no snapshot exists or if live data is already present.
  Future<TransitOfflineSnapshot?> loadOfflineSnapshotIfEmpty() async {
    if (departures.isNotEmpty || nearbyStops.isNotEmpty) return null;
    final snap = await TransitOfflineCache.load();
    if (snap == null) return null;
    nearbyStops = snap.stops;
    departures = snap.departures;
    if (snap.city.isNotEmpty && gpsCity == null) gpsCity = snap.city;
    onDeparturesUpdate?.call(departures);
    return snap;
  }

  /// Timestamp ultimului fetch DB rail (bahn.de). 60s TTL — evită refetch
  /// când userul switch-uie între Bhf tab și alt tab și înapoi rapid.
  DateTime? _lastBhfFetch;
  static const _bhfFetchTtl = Duration(seconds: 60);
  /// True dacă ULTIMUL fetch a eșuat (toate mirror-urile DB au picat).
  /// Folosit de UI ca să distingă "no rail stops in area" (rural) vs.
  /// "API down" (vremelnic).
  bool bhfLastFetchFailed = false;

  /// PUBLIC — găsește cele mai apropiate 3 gări DB (bahn.de) pe GPS user +
  /// adaugă departures ICE/IC/RE/RB/S-Bahn la lista globală. Apelat DOAR
  /// din UI când userul deschide tab-ul Bhf → restul tab-urilor folosesc
  /// exclusiv provider-ul local (fără trafic bahn.de).
  ///
  /// Endpoint: `v6.db.transport.rest/stops/nearby?latitude=X&longitude=Y
  ///           &results=10&distance=30000`
  ///
  /// Filtru pe products: keep doar stații cu min. una din {nationalExpress,
  /// national, regionalExp, regional, suburban} — evită POI-uri gen "H+M
  /// Passage" care apar în răspuns dar nu-s stații reale.
  ///
  /// Idempotent: cache 60s + dedup pe (line, dir, time, stop). Reapelarea
  /// în TTL e no-op instant.
  Future<void> fetchBhfNearby({bool force = false}) async {
    if (!force && _lastBhfFetch != null &&
        DateTime.now().difference(_lastBhfFetch!) < _bhfFetchTtl) {
      return;
    }
    if (_latitude == null || _longitude == null) return;
    // Ordine încercare — bahn.de PRIMARY (upstream oficial DB), apoi
    // mirrors community pentru redundanță. Cazuri:
    // - bahn.de merge → cel mai reliable (server DB oficial)
    // - bahn.de rate-limitat sau UA-blocked → v6.db.transport.rest
    // - v6 down → db.transport.rest / v5.db.transport.rest
    //
    // Fiecare endpoint returnează format diferit → parseri specializați.
    List<Map>? rail;
    String? usedSource;

    // 1) bahn.de PRIMARY
    try {
      rail = await _fetchNearbyStopsBahnDe();
      if (rail != null) {
        usedSource = 'bahn.de';
      }
    } catch (e) {
      _log.debug('Transit: bahn.de primary failed: $e', tag: 'TRANSIT');
    }

    // 2) Fallback la mirrors community v6.db.transport.rest & co.
    if (rail == null) {
      const dbMirrors = [
        'https://v6.db.transport.rest',
        'https://db.transport.rest',
        'https://v5.db.transport.rest',
      ];
      for (final mirror in dbMirrors) {
        for (int attempt = 0; attempt < 2; attempt++) {
          try {
            final uri = Uri.parse('$mirror/stops/nearby'
                '?latitude=${_latitude!.toStringAsFixed(6)}'
                '&longitude=${_longitude!.toStringAsFixed(6)}'
                '&results=10&distance=30000'
                '&subStops=false&entrances=false&linesOfStops=false');
            final resp = await _client.get(uri, headers: _restHeaders)
                .timeout(const Duration(seconds: 15));
            if (resp.statusCode == 200) {
              final parsed = jsonDecode(_decodeUtf8(resp));
              if (parsed is List) {
                rail = _parseRestNearbyRail(parsed);
                usedSource = mirror;
                break;
              }
            } else if (resp.statusCode == 503 || resp.statusCode == 502 || resp.statusCode == 429) {
              _log.debug('Transit: $mirror returned ${resp.statusCode} — retry', tag: 'TRANSIT');
              await Future.delayed(const Duration(seconds: 1));
              continue;
            }
            break;
          } catch (e) {
            _log.debug('Transit: $mirror attempt $attempt failed: $e', tag: 'TRANSIT');
          }
        }
        if (rail != null) break;
      }
    }
    if (rail == null || rail.isEmpty) {
      _log.info('Transit: toate sursele DB rail sunt down — no Bahnhof data', tag: 'TRANSIT');
      bhfLastFetchFailed = true;
      _lastBhfFetch = DateTime.now();
      onDeparturesUpdate?.call(departures);
      return;
    }
    bhfLastFetchFailed = false;
    _log.info('Transit: DB nearby via $usedSource (${rail.length} stații)', tag: 'TRANSIT');
    try {
      // Sortare după distanță crescătoare + limit 3
      rail.sort((a, b) {
        final da = (a['distance'] as num?)?.toInt() ?? 999999;
        final db = (b['distance'] as num?)?.toInt() ?? 999999;
        return da.compareTo(db);
      });
      final top3 = rail.take(3).toList();

      // Adaugă în nearbyStops (dacă nu-s deja acolo)
      final seenNames = nearbyStops.map((s) => s.name.toLowerCase()).toSet();
      final railStops = <TransitStop>[];
      for (final s in top3) {
        final name = s['name']?.toString() ?? '';
        final id = s['id']?.toString() ?? '';
        final dist = (s['distance'] as num?)?.toInt() ?? 0;
        if (name.isEmpty || id.isEmpty) continue;
        if (seenNames.contains(name.toLowerCase())) continue;
        final stop = TransitStop(id: id, name: name, distance: dist);
        railStops.add(stop);
        nearbyStops.add(stop);
      }

      // Fetch departures for each în paralel + adaugă la global list
      if (railStops.isEmpty) {
        _log.info('Transit: DB nearby stații deja în nearbyStops', tag: 'TRANSIT');
        return;
      }
      _log.info('Transit: DB nearby adaugă ${railStops.length} gări noi', tag: 'TRANSIT');
      // Trece stationId (EVA) direct → evită resolve lookup + folosim
      // bahn.de official pentru departures (nu doar community proxy).
      // BUG FIX 2026-07-11: auto-refresh Hbf/Bhf arata mereu trenurile vechi.
      // 2 cauze:
      //   1. `fetchDbDepartures` avea cache intern 60s care ignora `force`
      //   2. `fetchBhfNearby` facea DEDUP pe (line, dir, plannedTime) →
      //      trenurile cu acelasi plannedTime dar realtime updated erau
      //      skipped. Deci departures vechi ramaneau in lista.
      //
      // Fix: la force=true, invalidez cache DB PER stop + REPLACE (nu dedup)
      // toate departures existente cu stopName in railStops (rail only, nu
      // afectam bus/tram locale).
      if (force) {
        for (final s in railStops) {
          _dbDeparturesCache.remove(s.name);
          _dbDeparturesCache.remove(s.id);
        }
      }
      final railStopNames = railStops.map((s) => s.name).toSet();
      // REPLACE — sterg vechile departures pentru stopurile rail
      // pe care le refreshuim acum.
      departures.removeWhere((d) => railStopNames.contains(d.stopName));
      final futures = railStops
          .map((s) => fetchDbDepartures(s.name, stationId: s.id))
          .toList();
      final results = await Future.wait(futures);

      // Now ADD fresh (fara dedup — lista deja fara vechi).
      for (int i = 0; i < railStops.length; i++) {
        final stopName = railStops[i].name;
        for (final dbDep in results[i]) {
          if (dbDep.productType == 'bus') continue; // strict rail-only
          departures.add(Departure(
            line: dbDep.line,
            direction: dbDep.direction,
            plannedTime: dbDep.plannedTime,
            realtimeTime: dbDep.realtimeTime,
            delay: dbDep.delay,
            platform: dbDep.platform,
            productType: dbDep.productType,
            operator: dbDep.operator,
            stopName: stopName,
            stopID: dbDep.stopID,
            tripID: dbDep.tripID,
          ));
        }
      }
      // Re-sort
      departures.sort((a, b) {
        final ta = a.realtimeTime ?? a.plannedTime;
        final tb = b.realtimeTime ?? b.plannedTime;
        return ta.compareTo(tb);
      });
      // Re-sort nearbyStops after adding rail stops (nearby DB stations
      // may be closer than EFA-returned bus stops — restore distance order)
      nearbyStops.sort((a, b) => a.distance.compareTo(b.distance));
      _lastBhfFetch = DateTime.now();
      onDeparturesUpdate?.call(departures);
    } catch (e) {
      _log.debug('Transit: fetchBhfNearby failed: $e', tag: 'TRANSIT');
    }
  }

  /// Query DB Navigator app backend pentru găsirea stațiilor rail pe GPS.
  /// POST + JSON body — evită problemele de URL-encoding din dbweb (422).
  ///
  /// Format request (din `db-vendo-client/p/dbnav/nearby-req.js`):
  /// ```json
  /// {
  ///   "area": {"coordinates":{"longitude":X,"latitude":Y}, "radius": 30000},
  ///   "maxResults": 10,
  ///   "products": ["ALL"]
  /// }
  /// ```
  /// Response: array de `{haltId, haltName, produktGattungen:[...], entfernung}`.
  ///
  /// Returnează normalized list `{id, name, distance}` sau null la eroare.
  Future<List<Map>?> _fetchNearbyStopsBahnDe() async {
    try {
      final body = jsonEncode({
        'area': {
          'coordinates': {
            'longitude': _longitude,
            'latitude': _latitude,
          },
          // dbnav MAX supported = 10000m (verificat direct din
          // db-vendo-client `p/dbnav/nearby-req.js:6`:
          //   `if (opt.distance > 10000) throw new Error(...)`)
          // Peste 10000 → HTTP 400. Pentru zone rurale > 10km, fetchul cade
          // pe fallback v6.db.transport.rest.
          'radius': 10000,
        },
        // maxResults marit la 30 — bahn.de sortează după distanță; deja am
        // filtrare server-side pe products = doar rail, deci top 30 = 30 gări
        // (cu suficient pentru user rural unde gara e departe).
        'maxResults': 30,
        // ═══ CRITICAL: filter server-side DOAR rail products ═══
        //
        // Bug anterior (v6.59.33+35): trimiteam BUSSE + STRASSENBAHN + UBAHN
        // in lista → bahn.de returna zeci de bus/tram stops sortate by
        // distance. Saarbrücken Hbf (real 1-2 km) era in top 30 dar dupa 10+
        // bus stops → nu ajungea in primele 10 pe care le luam.
        //
        // Fix: trimit DOAR rail codes → bahn.de răspunde DOAR gări.
        'products': [
          'HOCHGESCHWINDIGKEITSZUEGE',       // ICE
          'INTERCITYUNDEUROCITYZUEGE',       // IC/EC
          'INTERREGIOUNDSCHNELLZUEGE',       // IR/RE
          'NAHVERKEHRSONSTIGEZUEGE',         // RB
          'SBAHNEN',                          // S-Bahn
        ],
      });
      final uri = Uri.parse('$_dbNavBase/mob/location/nearby');
      final resp = await _client.post(uri,
          headers: {
            'Content-Type': _dbNavNearbyContentType,
            'Accept': _dbNavNearbyContentType,
            'X-Correlation-ID': _dbNavCorrelationId(),
          },
          body: body,
      ).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 429 || resp.statusCode == 403) {
        _log.debug('Transit: dbnav nearby rate-limited (${resp.statusCode})', tag: 'TRANSIT');
        return null;
      }
      if (resp.statusCode != 200) {
        _log.debug('Transit: dbnav nearby returned ${resp.statusCode}', tag: 'TRANSIT');
        return null;
      }
      final respBody = _decodeUtf8(resp);
      if (respBody.trimLeft().startsWith('<')) {
        _log.debug('Transit: dbnav returned HTML (WAF block)', tag: 'TRANSIT');
        return null;
      }
      final data = jsonDecode(respBody);
      // Response poate fi list direct SAU obiect wrapping (variants văzute):
      // - direct list (parseLocation itera pe res.map)
      // - `{haltestellen: [...]}` sau `{stops: [...]}` sau `{items: [...]}`
      final List list;
      if (data is List) {
        list = data;
      } else if (data is Map) {
        // Try MANY key variants
        final candidate = data['haltestellen'] ?? data['nearbyStops'] ??
                          data['stops'] ?? data['items'] ?? data['result'] ??
                          data['res'] ?? data['orte'] ?? data['locations'];
        if (candidate is List) {
          list = candidate;
        } else {
          _log.debug('Transit: dbnav response Map keys=${data.keys.toList()}',
              tag: 'TRANSIT');
          return null;
        }
      } else {
        return null;
      }
      _log.debug('Transit: dbnav nearby raw list len=${list.length}', tag: 'TRANSIT');
      if (list.isEmpty) return [];
      // Log primul item pentru debugging schema.
      if (list.isNotEmpty && list[0] is Map) {
        final first = list[0] as Map;
        _log.debug('Transit: dbnav first item keys=${first.keys.toList()}',
            tag: 'TRANSIT');
        _log.info('Transit: dbnav first FULL DUMP name=${first['name']} '
            'locType=${first['locationType']} products=${first['products']} '
            'evaNr=${first['evaNr']}', tag: 'TRANSIT');
      }
      final rail = <Map>[];
      int rejectedNoRail = 0;
      for (final s in list) {
        if (s is! Map) continue;
        final id = (s['id'] ?? s['extId'] ?? s['evaNr'] ?? s['evaNumber'] ??
                    s['evaNo'] ?? s['bahnhofsId'] ?? s['haltId'] ?? s['lid'] ?? '').toString();
        final name = (s['name'] ?? s['haltName'] ?? s['bezeichnung'] ?? '').toString();
        if (id.isEmpty || name.isEmpty) continue;
        final typ = (s['type'] ?? s['typ'] ?? 'ST').toString().toUpperCase();
        if (typ == 'ADR' || typ == 'POI') continue;

        // ═══ FILTER rail-only STRICT ═══
        //
        // Din log v6.59.33 dovada bug:
        //   name=Cottbuser Platz Malstatt, Saarbrücken
        //   locType=ST evaNr=839433 products=[BUSSE, STRASSENBAHN]
        //
        // Deci EVA number există CHIAR și pentru bus/tram stops (nu-i marker
        // valid pentru rail). Nu ne bazăm nici pe locationType (toate sunt 'ST').
        //
        // Doar filtru pe `products` cu match EXACT pe rail codes dbnav.
        //
        // dbnav rail codes:
        // - HOCHGESCHWINDIGKEITSZUEGE (ICE)
        // - INTERCITYUNDEUROCITYZUEGE (IC/EC)
        // - INTERREGIOUNDSCHNELLZUEGE (IR/RE)
        // - NAHVERKEHRSONSTIGEZUEGE (RB)
        // - SBAHNEN (S-Bahn)
        //
        // NON-rail (respingem):
        // - BUSSE (bus)
        // - STRASSENBAHN (tram)
        // - UBAHN (metro)
        // - SCHIFFE (ship)
        // - ANRUFPFLICHTIGEVERKEHRE (on-demand)
        bool hasRail = false;
        final products = s['products'];
        if (products is Map) {
          hasRail = (products['nationalExpress'] == true) ||
                    (products['national'] == true) ||
                    (products['regionalExpress'] == true) ||
                    (products['regionalExp'] == true) ||
                    (products['regional'] == true) ||
                    (products['suburban'] == true);
        } else if (products is List) {
          hasRail = products.any((p) {
            final code = p.toString().toUpperCase();
            // Match STRICT — dbnav rail codes + legacy short codes.
            return code == 'HOCHGESCHWINDIGKEITSZUEGE' ||
                   code == 'INTERCITYUNDEUROCITYZUEGE' ||
                   code == 'INTERREGIOUNDSCHNELLZUEGE' ||
                   code == 'NAHVERKEHRSONSTIGEZUEGE' ||
                   code == 'SBAHNEN' ||
                   // Legacy short codes (from vendo/dbweb sau alte responses)
                   code == 'ICE' || code == 'IC' || code == 'EC' ||
                   code == 'EC_IC' || code == 'IR' || code == 'REGIONAL' ||
                   code == 'SBAHN' ||
                   // Match .contains pe cuvinte unambiguos rail:
                   // HOCH, INTERCITY, INTERREGIO, NAHVERKEHR
                   // (NU 'BAHN' care prinde STRASSENBAHN!)
                   code.contains('HOCH') || code.contains('INTERCITY') ||
                   code.contains('INTERREGIO') || code.contains('NAHVERKEHR');
          });
        }
        if (!hasRail) {
          rejectedNoRail++;
          continue;
        }
        rail.add({
          'id': id,
          'name': name,
          'distance': ((s['distance'] ?? s['entfernung'] ?? s['dist'] ?? 0) as num).toInt(),
        });
      }
      _log.info('Transit: dbnav nearby → ${rail.length} RAIL stops '
          '(${list.length} raw, $rejectedNoRail bus-only rejected)', tag: 'TRANSIT');
      return rail;
    } catch (e) {
      _log.debug('Transit: dbnav nearby exception: $e', tag: 'TRANSIT');
      return null;
    }
  }

  /// Parse v6.db.transport.rest `/stops/nearby` response → normalized rail list
  /// (același format cu bahn.de parser pentru procesare unificată).
  List<Map>? _parseRestNearbyRail(List data) {
    final rail = <Map>[];
    for (final s in data) {
      if (s is! Map) continue;
      final products = s['products'];
      if (products is! Map) continue;
      final hasRail = (products['nationalExpress'] == true) ||
          (products['national'] == true) ||
          (products['regionalExp'] == true) ||
          (products['regional'] == true) ||
          (products['suburban'] == true);
      if (!hasRail) continue;
      rail.add({
        'id': s['id']?.toString() ?? '',
        'name': s['name']?.toString() ?? '',
        'distance': (s['distance'] as num?)?.toInt() ?? 0,
      });
    }
    return rail;
  }

  /// For every visible stop whose name matches a mainline station pattern,
  /// fetch DB (HAFAS via transport.rest) departures in parallel and merge them.
  ///
  /// Match is strict: token-boundary on "Hbf" / "Hauptbahnhof", or the name
  /// STARTS with "Bahnhof <Ort>". This avoids false positives like
  /// "Klinikum am Bahnhof" or "Am Bahnhof 12" which are bus stops, not
  /// railway stations, and don't need DB augmentation.
  Future<void> _augmentWithDbRailDepartures() async {
    if (nearbyStops.isEmpty) return;
    final railwayStops = nearbyStops.where(_isMainlineStation).toList();
    if (railwayStops.isEmpty) return;

    _log.info('Transit: augmenting ${railwayStops.length} railway stops with DB data', tag: 'TRANSIT');
    // Helper isolated so the strict match logic is shared and testable.
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

  /// Strict token-boundary match for mainline stations. Positives:
  /// "Ulm Hbf", "München Hauptbahnhof", "Bahnhof Neu-Ulm",
  /// "Neu-Ulm Bahnhof", "Senden Bahnhof", "Illertissen Bahnhof".
  /// Negatives (bus stops / addresses):
  /// "Bahnhofstraße", "Bahnhofsplatz", "Am Bahnhof 12" (address with number).
  ///
  /// Design: permissive pentru "X Bahnhof" — false-positives sunt inofensive
  /// (dacă DB /locations nu găsește potrivire → 0 rail departures adăugate).
  /// User in Neu-Ulm nu vedea trenurile pentru că regex-ul precedent rata
  /// pattern-ul "X Bahnhof" (doar "X Hbf" era detectat).
  static final RegExp _stationRe = RegExp(
    // 1) hbf / hauptbahnhof / bahnhof cu word-boundary la ambele capete
    // 2) ^bahnhof <token> (start cu "Bahnhof X")
    r'(^|\s)(hbf|hauptbahnhof|bahnhof)($|\s)|^bahnhof\s+\S',
    caseSensitive: false,
  );
  bool _isMainlineStation(TransitStop s) {
    final n = s.name.toLowerCase();
    // Străzi / piețe cu prefix "bahnhof" — filtrare guard.
    if (n.contains('bahnhofstr') || n.contains('bahnhofspl') ||
        n.contains('bahnhofsvor') || n.contains('bahnhofsvi')) return false;
    // Adrese numerotate: "Am Bahnhof 12" / "Bahnhof 3" — au număr după bahnhof.
    if (RegExp(r'bahnhof\s+\d').hasMatch(n)) return false;
    return _stationRe.hasMatch(n);
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
            stopID: dep['stopID']?.toString(),
            destID: servingLine['destID']?.toString(),
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

  Map<String, dynamic> _hafasRequest(List<Map<String, dynamic>> svcReqL,
      {TransitProviderConfig? providerOverride}) {
    // Prefer explicit override → activeProvider fallback. Cross-provider
    // trip searches pass their own provider (LocMatch pe fp/tp) — without
    // this override, client-config leaked from activeProvider era buggy.
    final p = providerOverride ?? activeProvider;
    final client = <String, dynamic>{
      'type': p?.hafasClientType ?? 'AND',
      'id': p?.hafasClientId ?? 'ZPS-SAAR',
      'name': p?.hafasClientName ?? 'Saarfahrplan',
    };
    // client.v serialization is picky per backend:
    //   - Android/iPhone HAFAS backends (saarVV, VBB, NAH.SH, ...) expect a
    //     numeric `"v":1000070`. If we send `"v":"1000070"` the server accepts
    //     the auth but silently returns zero results for LocGeoPos.
    //   - WEB clients (RMV) omit v entirely.
    // We try int-parse first and fall back to the string.
    final ver = p?.hafasClientVersion ?? '1000070';
    if (ver.isNotEmpty && p?.hafasClientType != 'WEB') {
      final intVer = int.tryParse(ver);
      client['v'] = intVer ?? ver;
    } else {
      final wv = p?.hafasClientVersion;
      if (wv != null) {
        final intVer = int.tryParse(wv);
        client['v'] = intVer ?? wv;
      }
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

  /// Build the final POST URL, appending mic+mac signature query params
  /// dacă providerul are `hafasSalt`.
  ///
  /// Algoritm (după `public-transport/hafas-client lib/request.js`):
  ///   1. mic = MD5(body_bytes)                    → hex string
  ///   2. mac = MD5(hex(mic) || salt_utf8_bytes)   → hex string
  ///   3. URL = baseUrl?mic=<hex>&mac=<hex>
  ///
  /// Provideri care NU au salt → returnează baseUrl neschimbat.
  String _hafasSignedUrl(TransitProviderConfig? p, String body) {
    final base = p?.baseUrl ?? _hafasEndpoint;
    final salt = p?.hafasSalt;
    if (salt == null || salt.isEmpty) return base;
    final bodyBytes = utf8.encode(body);
    final micDigest = md5.convert(bodyBytes);
    final micHex = micDigest.toString(); // lowercase hex
    // Concatenăm hex(mic) + salt (raw UTF-8 bytes), apoi MD5.
    final macInput = utf8.encode(micHex) + utf8.encode(salt);
    final macDigest = md5.convert(macInput);
    final macHex = macDigest.toString();
    // Append la URL. Base poate deja să conțină '?' — improbabil pentru mgate.
    final sep = base.contains('?') ? '&' : '?';
    return '$base${sep}mic=$micHex&mac=$macHex';
  }

  /// Convenience: build request map, JSON-serialize, sign URL — returns
  /// both pentru un singur call site care POST-ează.
  ({String url, String body}) _buildSignedHafasCall(
      TransitProviderConfig? p, List<Map<String, dynamic>> svcReqL) {
    final reqMap = _hafasRequest(svcReqL, providerOverride: p);
    final body = jsonEncode(reqMap);
    final url = _hafasSignedUrl(p, body);
    return (url: url, body: body);
  }

  /// Fetch departures via HAFAS mgate.exe (saarVV)
  /// Two-step: 1) find nearby stops  2) get departures for each
  Future<void> _fetchHafasDepartures() async {
    // Circuit-breaker: skip complet dacă providerul e blacklist-uit.
    final activeP = activeProvider;
    if (activeP != null && _isHafasBlacklisted(activeP.type)) {
      _log.debug('Transit [${activeP.name}]: skipped — blacklisted', tag: 'TRANSIT');
      return;
    }
    // Step 1: Find nearby stops via LocGeoPos.
    // Expanded 2026-07 la 30km / 20 max stops pentru a suporta sub-tab-uri
    // per productType (Bus, Tram, S-Bhf, U-Bhf, Bhf). Distanța 30km e
    // suficientă pentru mediu rural — Bhf/Tram pot fi la 15-25 km. Chiar
    // dacă rezultatul e mai departe, arătăm cele mai apropiate 3 per tip.
    final nearbyCall = _buildSignedHafasCall(activeP, [
      {
        'meth': 'LocGeoPos',
        'req': {
          'ring': {
            'cCrd': {
              'x': (_longitude! * 1000000).round(),
              'y': (_latitude! * 1000000).round(),
            },
            'maxDist': 30000,
          },
          'getPOIs': false,
          'getStops': true,
        },
      },
    ]);

    final nearbyResponse = await _client.post(
      Uri.parse(nearbyCall.url),
      headers: {'Content-Type': 'application/json'},
      body: nearbyCall.body,
    ).timeout(const Duration(seconds: 15));

    if (nearbyResponse.statusCode != 200) {
      _log.error('Transit [saarVV]: LocGeoPos returned ${nearbyResponse.statusCode}', tag: 'TRANSIT');
      return;
    }

    final nearbyData = jsonDecode(_decodeUtf8(nearbyResponse));
    // Root-level AUTH check (activeP may be null pre-detection).
    final rootErr = nearbyData['err']?.toString();
    if (rootErr == 'AUTH' && activeP != null) {
      _markHafasAuthFail(activeP, '${nearbyData['errTxt'] ?? 'AUTH'}');
      return;
    }
    final nearbyRes = nearbyData['svcResL'];
    if (nearbyRes == null || nearbyRes is! List || nearbyRes.isEmpty) {
      final providerName = activeP?.name ?? 'HAFAS';
      _log.error('Transit [$providerName]: Empty LocGeoPos response', tag: 'TRANSIT');
      return;
    }

    final locRes = nearbyRes[0]['res'];
    if (locRes == null) {
      // Check for error
      final err = nearbyRes[0]['err']?.toString();
      final providerName = activeP?.name ?? 'HAFAS';
      if (err == 'AUTH' && activeP != null) {
        _markHafasAuthFail(activeP, '${nearbyRes[0]['errTxt'] ?? 'AUTH'}');
      } else {
        _log.error('Transit [$providerName]: LocGeoPos error: $err', tag: 'TRANSIT');
      }
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

      // Max 20 closest stops — suficient pentru filtrare per productType
      // (Bus/Tram/Bhf/S/U) în UI. Sortare stabilă crescător după distanță.
      if (nearbyStops.length >= 20) break;
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

    final depCall = _buildSignedHafasCall(activeP, stbRequests);
    final depResponse = await _client.post(
      Uri.parse(depCall.url),
      headers: {'Content-Type': 'application/json'},
      body: depCall.body,
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

      // Common locations list (referenced by stbStop.locX)
      final commonLocL = common['locL'] as List? ?? [];

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

          // Cancellation flag — saarVV/VBB/RMV all use `dCncl:true` on the
          // stbStop when the service is dropped. Show it as a distinct state,
          // NOT as "Plan" (which implies the vehicle will still come).
          final isCancelled = stbStop['dCncl'] == true;

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

            // Product type: prefer prodCtx.catOut (Bus/Tram/S/RE/RB/ICE/…)
            // which is reliable across all HAFAS backends. saarVV in particular
            // uses non-standard `cls` values (cls=8 for RE/RB, cls=64+catOut="S"
            // for Saarbahn light-rail, cls=128 for regular buses), so a `cls`-
            // only switch mis-classifies tram as bus and regional as S-Bahn.
            // Fall back to `cls` only when catOut is absent.
            productType = _hafasProductType(prod);
          }

          // Direction
          final direction = jny['dirTxt']?.toString() ?? '';

          // Resolve stop/trip identifiers for trip-sequence lookup.
          //   - stopID:  extId of the boarding stop from common.locL[stbStop.locX]
          //   - tripID:  jny.jid — unique per journey, feeds JourneyDetails method
          //              which returns the full stop sequence without needing destID
          //   - destID:  intentionally null for HAFAS — resolved via JourneyDetails
          String? boardStopId;
          final locX = stbStop['locX'];
          if (locX is int && locX >= 0 && locX < commonLocL.length) {
            final loc = commonLocL[locX];
            if (loc is Map) {
              boardStopId = (loc['extId'] ?? loc['lid'])?.toString();
            }
          }
          final tripJid = jny['jid']?.toString();

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
            isCancelled: isCancelled,
            stopID: boardStopId,
            tripID: tripJid,
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

  /// Map a HAFAS prodL entry to our internal productType string.
  ///
  /// Uses a two-step lookup:
  ///   1. `prodCtx.catOutL` (long name — always the most reliable when
  ///      present, e.g. "Saarbahn" instead of the ambiguous "S", or
  ///      "Straßenbahn" instead of catOut="STR").
  ///   2. Fall back to `catOutS` / `catOut` / `catCode`.
  ///   3. Last resort: numeric `cls` bitmask (varies per backend).
  ///
  /// Notable pitfalls this handles:
  ///   - saarVV emits catOut="S" for Saarbahn light-rail (which is really a
  ///     tram), but catOutL="Saarbahn" makes the distinction clear.
  ///   - saarVV cls=64 covers *both* Saarbahn and buses (with catOutL="Bus"),
  ///     and cls=128 also covers buses — cls alone is useless there.
  static String _hafasProductType(Map prod) {
    final ctx = prod['prodCtx'];
    String catLong = '';
    String cat = '';
    if (ctx is Map) {
      catLong = (ctx['catOutL'] ?? '').toString().trim().toUpperCase();
      cat = (ctx['catOutS'] ?? ctx['catOut'] ?? ctx['catCode'] ?? '').toString().trim().toUpperCase();
    }
    // Long-name check first — catches operator-specific brand names.
    if (catLong.isNotEmpty) {
      if (catLong.contains('SAARBAHN') || catLong.contains('STRASSENBAHN') ||
          catLong.contains('STRAßENBAHN') || catLong.contains('TRAM')) {
        return 'tram';
      }
      if (catLong.contains('S-BAHN') || catLong.contains('SBAHN')) return 'suburban';
      if (catLong.contains('U-BAHN') || catLong.contains('UBAHN')) return 'subway';
      if (catLong == 'BUS' || catLong.endsWith(' BUS') || catLong.startsWith('BUS ')) return 'bus';
      if (catLong.contains('FÄHRE') || catLong.contains('SCHIFF') || catLong.contains('FERRY')) return 'ferry';
    }
    if (cat.isNotEmpty) {
      switch (cat) {
        case 'ICE':
        case 'IC':
        case 'EC':
        case 'EN':
        case 'NJ':
        case 'TGV':
        case 'RJ':
        case 'ECE':
        case 'IR':
        case 'FLX':
          return 'train';
        // IRE = Interregio-Express — REGIONAL service (D-Ticket eligible),
        // nu Fernverkehr! Was misclassified pre-2026-07.
        case 'IRE':
        case 'RE':
        case 'RB':
        case 'RS':
        case 'MEX':
        case 'ALX':
        case 'BRB':
        case 'HLB':
        case 'HKX':
        case 'NBE':
        case 'NWB':
        case 'ODEG':
        case 'ERB':
        case 'MRB':
        case 'VIAS':
        case 'ENO':
          return 'regional';
        case 'S':
        case 'S-BAHN':
        case 'SBAHN':
          return 'suburban';
        case 'U':
        case 'U-BAHN':
        case 'UBAHN':
        case 'M':
          return 'subway';
        case 'TRAM':
        case 'STR':
        case 'STRAB':
        case 'T':
          return 'tram';
        case 'BUS':
        case 'SEV':
        case 'RUF':
        case 'AST':
        case 'ALT':
          return 'bus';
        case 'F':
        case 'FÄHRE':
        case 'SCH':
        case 'SCHIFF':
          return 'ferry';
      }
    }
    // Fallback to cls (best-effort — standard HAFAS mapping)
    final cls = prod['cls'] as int? ?? 0;
    if (cls == 1 || cls == 2) return 'train';
    if (cls == 4 || cls == 8) return 'regional';
    if (cls == 16) return 'suburban';
    if (cls == 256) return 'subway';
    if (cls == 512) return 'tram';
    if (cls == 32) return 'bus';
    if (cls == 64) return 'ferry';
    return 'bus';
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

  /// **Deutsche Bahn Navigator mobile app backend** — POST + JSON, cel mai
  /// stabil endpoint public DB. Folosit de aplicația oficială DB Navigator.
  ///
  /// De ce dbnav în loc de int.bahn.de dbweb:
  /// - dbweb URL-encoding `products[]=X` producea 422 pe device (verificat)
  /// - dbnav POST + JSON body → nu are probleme cu URL encoding
  /// - Backend oficial DB Navigator = uptime real
  ///
  /// Endpoint-uri (din `db-vendo-client/p/dbnav/`):
  /// - `POST /mob/location/nearby` → stații pe GPS
  /// - `POST /mob/bahnhofstafel/abfahrt` → live departures
  ///
  /// Headers necesare:
  /// - `X-Correlation-ID` (32 hex + `_` + 32 hex, gen la fiecare request)
  /// - `Content-Type: application/x.db.vendo.mob.location.v3+json` (nearby)
  /// - `Content-Type: application/x.db.vendo.mob.bahnhofstafeln.v2+json` (dep)
  static const _dbNavBase = 'https://app.services-bahn.de';
  static const _dbNavNearbyContentType = 'application/x.db.vendo.mob.location.v3+json';
  static const _dbNavBoardContentType = 'application/x.db.vendo.mob.bahnhofstafeln.v2+json';

  /// Generate X-Correlation-ID pentru fiecare request dbnav.
  /// Format: 32 hex chars + '_' + 32 hex chars.
  String _dbNavCorrelationId() {
    final rnd = math.Random();
    String hex32() =>
        List.generate(32, (_) => rnd.nextInt(16).toRadixString(16)).join();
    return '${hex32()}_${hex32()}';
  }

  /// Legacy int.bahn.de (dbweb) constants — păstrate pentru fallback + docs.
  /// NU e folosit după 2026-07-11 (params `[]` producea 422).
  static const _bahnDeBase = 'https://int.bahn.de/web/api/reiseloesung';
  static const _bahnDeHeaders = {
    'Accept': 'application/json',
    'Accept-Language': 'de-DE,de;q=0.9',
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
  };

  // ════════════════════════════════════════════════════════════════
  // HAFAS AUTH CIRCUIT-BREAKER — mulți provideri au migrat la request
  // signing (MIC/MAC HMAC-SHA1); AID-ul singur nu mai e suficient și
  // returnează `err=AUTH HCI Core: Authorization fail`. Pentru evitare
  // spam-ului în server-side logs + latency degeaba la fiecare autocomplete
  // keystroke, blacklist providerul 6h după primul AUTH fail. Auto-recover
  // la expiry pentru cazul restaurării AID.
  // ════════════════════════════════════════════════════════════════
  final Map<TransitProviderType, DateTime> _hafasAuthBlacklist = {};
  final Map<TransitProviderType, DateTime> _hafasLastLoggedError = {};
  static const _hafasBlacklistTtl = Duration(hours: 6);
  static const _hafasLogCooldown = Duration(minutes: 5);

  /// True dacă acest provider e blacklist-uit — skip request-ul.
  bool _isHafasBlacklisted(TransitProviderType t) {
    final until = _hafasAuthBlacklist[t];
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      _hafasAuthBlacklist.remove(t);
      return false;
    }
    return true;
  }

  /// Înregistrează AUTH fail — blacklist 6h + suprima log-uri viitoare.
  void _markHafasAuthFail(TransitProviderConfig p, String rootErr) {
    final now = DateTime.now();
    _hafasAuthBlacklist[p.type] = now.add(_hafasBlacklistTtl);
    final lastLog = _hafasLastLoggedError[p.type];
    // Log doar o dată la 5 min per provider ca să nu spamăm server-side.
    if (lastLog == null || now.difference(lastLog) > _hafasLogCooldown) {
      _hafasLastLoggedError[p.type] = now;
      _log.error('Transit [${p.name}]: HAFAS auth fail ($rootErr) — '
          'blacklisted for 6h', tag: 'TRANSIT');
    }
  }
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
  ///
  /// Try order: bahn.de official → v6.db.transport.rest fallback.
  Future<List<Departure>> fetchDbDepartures(String stationName, {String? stationId}) async {
    final cacheKey = stationId ?? stationName;
    final cached = _dbDeparturesCache[cacheKey];
    if (cached != null && DateTime.now().difference(cached.at) < const Duration(seconds: 60)) {
      return cached.departures;
    }
    // Try bahn.de PRIMARY (folosim direct stationId ca ortExtId dacă avem EVA).
    if (stationId != null && stationId.isNotEmpty) {
      final viaBahnDe = await _fetchDeparturesBahnDe(stationId, stationName);
      if (viaBahnDe != null) {
        _dbDeparturesCache[cacheKey] = _CachedDepartures(viaBahnDe, DateTime.now());
        return viaBahnDe;
      }
    }
    // Fallback la v6.db.transport.rest — resolve name → id → departures.
    final id = stationId ?? await _resolveDbStopId(stationName);
    if (id == null) {
      _dbDeparturesCache[cacheKey] = _CachedDepartures([], DateTime.now());
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
        // .toLocal() — same timezone fix ca la _fetchDeparturesBahnDe.
        final plannedRaw = DateTime.tryParse(d['plannedWhen']?.toString() ?? '');
        final actualRaw = DateTime.tryParse(d['when']?.toString() ?? '');
        if (plannedRaw == null) continue;
        final planned = plannedRaw.toLocal();
        final actual = actualRaw?.toLocal();
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

  /// dbnav (DB Navigator app) live departures via POST + JSON.
  /// `stationId` = EVA (7 cifre, ex. "8000201" Ulm Hbf).
  /// Returnează null la eroare (fallback la v6.db.transport.rest).
  ///
  /// Request format (din `db-vendo-client/p/dbnav/station-board-req.js`):
  /// ```
  /// POST /mob/bahnhofstafel/abfahrt
  /// body: {
  ///   anfragezeit: "HH:mm",
  ///   datum: "yyyy-MM-dd",
  ///   ursprungsBahnhofId: EVA,
  ///   verkehrsmittel: ["ALL"]
  /// }
  /// ```
  Future<List<Departure>?> _fetchDeparturesBahnDe(String stationId, String stationName) async {
    try {
      final now = DateTime.now();
      final datum = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      final zeit = '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}';
      final body = jsonEncode({
        'anfragezeit': zeit,
        'datum': datum,
        'ursprungsBahnhofId': stationId,
        'verkehrsmittel': [
          'HOCHGESCHWINDIGKEITSZUEGE',
          'INTERCITYUNDEUROCITYZUEGE',
          'INTERREGIOUNDSCHNELLZUEGE',
          'NAHVERKEHRSONSTIGEZUEGE',
          'SBAHNEN',
          'UBAHN',
          'STRASSENBAHN',
          'BUSSE',
          'SCHIFFE',
          'ANRUFPFLICHTIGEVERKEHRE',
        ],
      });
      final uri = Uri.parse('$_dbNavBase/mob/bahnhofstafel/abfahrt');
      final resp = await _client.post(uri,
          headers: {
            'Content-Type': _dbNavBoardContentType,
            'Accept': _dbNavBoardContentType,
            'X-Correlation-ID': _dbNavCorrelationId(),
          },
          body: body,
      ).timeout(const Duration(seconds: 12));
      if (resp.statusCode == 429 || resp.statusCode == 403) {
        _log.debug('Transit: dbnav abfahrt rate-limited ${resp.statusCode}', tag: 'TRANSIT');
        return null;
      }
      if (resp.statusCode != 200) {
        _log.debug('Transit: dbnav abfahrt returned ${resp.statusCode}', tag: 'TRANSIT');
        return null;
      }
      final respBody = _decodeUtf8(resp);
      if (respBody.trimLeft().startsWith('<')) return null; // WAF HTML
      final data = jsonDecode(respBody);
      if (data is! Map) return null;
      // DEBUG: log top-level keys pentru schema discovery.
      _log.info('Transit: dbnav abfahrt $stationName top-level keys=${data.keys.toList()}',
          tag: 'TRANSIT');
      // dbnav response schema variates:
      final entries = data['bahnhofstafelAbfahrtPositionen'] ??
                       data['entries'] ??
                       data['abfahrten'] ??
                       data['positionen'] ??
                       data['results'] ??
                       data['bahnhofstafel'] ??
                       data['items'] ??
                       data['data'];
      if (entries is! List) {
        _log.info('Transit: dbnav abfahrt entries NOT a list — data body starts: '
            '${respBody.substring(0, respBody.length > 400 ? 400 : respBody.length)}',
            tag: 'TRANSIT');
        return null;
      }
      _log.info('Transit: dbnav abfahrt entries.length=${entries.length}',
          tag: 'TRANSIT');
      if (entries.isNotEmpty && entries[0] is Map) {
        _log.info('Transit: dbnav abfahrt first entry keys=${(entries[0] as Map).keys.toList()}',
            tag: 'TRANSIT');
      }
      final out = <Departure>[];
      for (final e in entries) {
        if (e is! Map) continue;
        // Câmpuri EXACTE (din test/fixtures/dbnav-departures.json):
        // - abgangsDatum    → planned ISO 8601 datetime
        // - ezAbgangsDatum  → realtime ISO 8601 datetime
        // - mitteltext      → "RB 82" (line + number)
        // - kurztext        → "RB" (product short code)
        // - richtung        → direction
        // - gleis           → platform
        // - produktGattung  → "ICE", "IC", "RB", "RE", "SBAHN", "RUF", ...
        final zeitIso = e['abgangsDatum']?.toString() ??
                        e['zeit']?.toString() ?? ''; // fallback
        final echtzeitIso = e['ezAbgangsDatum']?.toString() ??
                            e['echtzeit']?.toString();
        // BUG FIX 2026-07-11 timezone: bahn.de returnează "15:05:00+01:00"
        // (Europe/Berlin). `DateTime.tryParse` pentru string cu offset creează
        // un DateTime în UTC (`isUtc == true`). UI folosea `dep.plannedTime.hour`
        // direct → afișa ora UTC (13:05) în loc de local (15:05).
        //
        // `.toLocal()` convertește la timezone-ul device-ului (Berlin CEST/CET).
        final plannedRaw = DateTime.tryParse(zeitIso);
        if (plannedRaw == null) continue;
        final planned = plannedRaw.toLocal();
        final realtimeRaw = echtzeitIso == null ? null : DateTime.tryParse(echtzeitIso);
        final realtime = realtimeRaw?.toLocal();
        final delay = realtime != null ? realtime.difference(planned).inMinutes : 0;
        // produktGattung acum returneaza SHORT codes: "ICE", "IC", "RB", "RE",
        // "SBAHN", "UBAHN", "STRASSENBAHN", "BUS", "RUF", "ANRUFPFLICHTIGEVERKEHRE"
        final produktGattung = (e['produktGattung'] ?? e['gattung'] ?? '')
            .toString().toUpperCase();
        String productType;
        switch (produktGattung) {
          case 'ICE':
          case 'EC': case 'IC': case 'EC_IC':
          case 'IR':
            productType = 'train';
            break;
          case 'RE': case 'RB': case 'IRE': case 'MEX': case 'REGIONAL':
          case 'ALX': case 'BRB': case 'HLB': case 'ODEG': case 'ERB':
            productType = 'regional';
            break;
          case 'S': case 'SBAHN': case 'S-BAHN':
            productType = 'suburban';
            break;
          case 'U': case 'UBAHN': case 'U-BAHN':
            productType = 'subway';
            break;
          case 'STR': case 'TRAM': case 'STRAB': case 'STRASSENBAHN':
            productType = 'tram';
            break;
          case 'BUS': case 'BUSSE':
            productType = 'bus';
            break;
          case 'RUF': case 'AST': case 'ALT': case 'ANRUFPFLICHTIGEVERKEHRE':
            productType = 'bus'; // Ruftaxi = bus category
            break;
          default:
            productType = 'regional';
        }
        // Line name: prefer mitteltext ("RB 82") over kurztext ("RB").
        final lineName = (e['mitteltext'] ?? e['kurztext'] ?? '?').toString();
        // tripID = zuglaufId → folosit pentru trip-sequence dialog (click pe
        // departure = vezi stațiile trenului + Ausstieg-Alarm).
        // stopID = evaNr din abfrageOrt → boarding stop pentru isCurrent flag.
        final zuglaufId = e['zuglaufId']?.toString();
        final abfrageOrt = e['abfrageOrt'];
        final boardStopId = (abfrageOrt is Map)
            ? (abfrageOrt['evaNr'] ?? abfrageOrt['stationId'])?.toString()
            : null;
        out.add(Departure(
          line: lineName,
          direction: (e['richtung'] ?? e['ziel'] ?? '').toString(),
          plannedTime: planned,
          realtimeTime: realtime,
          delay: delay < 0 ? 0 : delay,
          platform: e['gleis']?.toString(),
          productType: productType,
          operator: '',
          stopName: stationName,
          isCancelled: e['ausfall'] == true || e['cancelled'] == true,
          stopID: boardStopId,
          tripID: zuglaufId,
        ));
      }
      _log.info('Transit: bahn.de $stationName → ${out.length} departures', tag: 'TRANSIT');
      return out;
    } catch (e) {
      _log.debug('Transit: bahn.de abfahrten exception: $e', tag: 'TRANSIT');
      return null;
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

    // 1) PRIMARY: bahnhof.de scrape — no auth, cel mai fresh (60s CDN cache).
    // Format URL: https://www.bahnhof.de/{slug}/aufzuege
    // (ex: "Saarbrücken Hbf" → "saarbruecken-hbf")
    try {
      final fromBahnhofDe = await _fetchElevatorsFromBahnhofDe(stationName);
      if (fromBahnhofDe.isNotEmpty) {
        _log.info('Transit: ${fromBahnhofDe.length} facilities @ "$stationName" via bahnhof.de',
            tag: 'TRANSIT');
        _facilitiesCache[stationName] = _CachedFacilities(fromBahnhofDe, DateTime.now());
        return fromBahnhofDe;
      }
    } catch (e) {
      _log.debug('Transit: bahnhof.de scrape failed: $e', tag: 'TRANSIT');
    }

    // 2) FALLBACK: v6.db.transport.rest — deja poate fi down/503.
    final id = await _resolveDbStopId(stationName);
    if (id == null) {
      _facilitiesCache[stationName] = _CachedFacilities([], DateTime.now());
      return [];
    }
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

  /// Fetches elevator status from `bahnhof.de/{slug}/aufzuege`.
  ///
  /// Format URL cu slug derivat din numele stației (transformă umlaut-uri
  /// și înlocuiește spații cu `-`). URL exemplu:
  ///   Saarbrücken Hbf → https://www.bahnhof.de/saarbruecken-hbf/aufzuege
  ///
  /// Pagina e Next.js SSR — datele sunt embedded în `self.__next_f.push()`
  /// chunks din HTML. Header `RSC: 1` returnează doar payload-ul RSC
  /// (~108 KB) în loc de HTML complet (~150 KB).
  ///
  /// Response conține `"elevators":[{...}]` cu:
  /// - `state.type`: ACTIVE / INACTIVE / UNKNOWN
  /// - `state.explanation`: text descriptiv
  /// - `description`: "zu Gleis 3-4"
  /// - `type`: ELEVATOR / ESCALATOR
  Future<List<StationFacility>> _fetchElevatorsFromBahnhofDe(String stationName) async {
    final slug = _bahnhofDeSlug(stationName);
    if (slug.isEmpty) return [];
    final uri = Uri.parse('https://www.bahnhof.de/$slug/aufzuege');
    final resp = await _client.get(uri, headers: {
      'RSC': '1',
      'Accept': 'text/x-component,*/*',
      'Accept-Language': 'de-DE,de;q=0.9',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
    }).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      _log.debug('Transit: bahnhof.de $slug returned ${resp.statusCode}', tag: 'TRANSIT');
      return [];
    }
    final body = _decodeUtf8(resp);
    // Extrag JSON `"elevators":[...]` din stream. Poate apărea multiple ori
    // (o dată per RSC chunk); folosim un match cu paranteze balansate.
    final match = RegExp(r'"elevators"\s*:\s*(\[)').firstMatch(body);
    if (match == null) return [];
    final startIdx = match.end - 1; // includem '['
    // Traversez și cont paranteze until match.
    int depth = 0;
    int endIdx = -1;
    bool inStr = false;
    bool escape = false;
    for (int i = startIdx; i < body.length; i++) {
      final c = body[i];
      if (inStr) {
        if (escape) { escape = false; }
        else if (c == r'\') { escape = true; }
        else if (c == '"') { inStr = false; }
        continue;
      }
      if (c == '"') { inStr = true; continue; }
      if (c == '[') depth++;
      else if (c == ']') {
        depth--;
        if (depth == 0) { endIdx = i; break; }
      }
    }
    if (endIdx < 0) return [];
    final arrJson = body.substring(startIdx, endIdx + 1);
    // Unescape RSC-stream (\" → ", \\ → \, \n → newline)
    final unescaped = arrJson
        .replaceAll(r'\"', '"')
        .replaceAll(r'\\', r'\')
        .replaceAll(r'\n', '\n');
    List<dynamic> elevators;
    try {
      elevators = jsonDecode(unescaped) as List;
    } catch (_) {
      try {
        elevators = jsonDecode(arrJson) as List; // fallback fără unescape
      } catch (e) {
        _log.debug('Transit: bahnhof.de JSON parse failed: $e', tag: 'TRANSIT');
        return [];
      }
    }
    final result = <StationFacility>[];
    for (final e in elevators) {
      if (e is! Map) continue;
      final stateRaw = e['state'];
      String state = 'UNKNOWN';
      String? reason;
      if (stateRaw is Map) {
        state = (stateRaw['type'] ?? 'UNKNOWN').toString().toUpperCase();
        reason = stateRaw['explanation']?.toString();
      } else if (stateRaw is String) {
        state = stateRaw.toUpperCase();
      }
      final type = (e['type'] ?? 'ELEVATOR').toString().toUpperCase();
      final desc = (e['description'] ?? '').toString();
      result.add(StationFacility(
        description: desc.isEmpty ? (type == 'ESCALATOR' ? 'Fahrtreppe' : 'Aufzug') : desc,
        type: type,
        status: state,
        reason: reason,
      ));
    }
    return result;
  }

  /// Transformă numele stației într-un slug URL-safe pentru bahnhof.de.
  /// Reguli:
  ///   - lowercase
  ///   - ä→ae, ö→oe, ü→ue, ß→ss
  ///   - remove accente (é→e, à→a)
  ///   - spații și caractere non-alfanumerice → `-`
  ///   - trim leading/trailing `-`
  ///
  /// Exemple:
  ///   "Berlin Hbf" → "berlin-hbf"
  ///   "München Hauptbahnhof" → "muenchen-hauptbahnhof"
  ///   "Saarbrücken Hbf" → "saarbruecken-hbf"
  ///   "Frankfurt(M) Hbf" → "frankfurt-m-hbf"
  static String _bahnhofDeSlug(String name) {
    if (name.trim().isEmpty) return '';
    var s = name.toLowerCase().trim();
    // Umlaut + ß
    s = s
        .replaceAll('ä', 'ae')
        .replaceAll('ö', 'oe')
        .replaceAll('ü', 'ue')
        .replaceAll('ß', 'ss');
    // Accente comune (best-effort, dev acoperă și cazuri rare gen "Château")
    const accents = {
      'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'å': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
      'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u',
      'ç': 'c', 'ñ': 'n',
    };
    for (final entry in accents.entries) {
      s = s.replaceAll(entry.key, entry.value);
    }
    // Spații + non-alfanumeric → dash. Colapsez multi-dashes.
    s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    s = s.replaceAll(RegExp(r'-+'), '-');
    s = s.replaceAll(RegExp(r'^-|-$'), '');
    return s;
  }

  /// Check whether a Journey is likely usable for a wheelchair user by
  /// querying DB FaSta elevator status at every vehicle-leg endpoint.
  ///
  /// Walking legs are skipped (no ÖPNV = no facilities to check).
  /// Stops without DB coverage (pure bus stops) contribute nothing —
  /// if none of the checked stops have data, status stays `unknown`.
  ///
  /// All fetches run in parallel; individual results are already cached
  /// 5min by `fetchFacilities` so multiple journeys sharing a station
  /// hit the cache.
  Future<JourneyAccessibility> checkJourneyAccessibility(Journey j) async {
    final stops = <String>{};
    for (final leg in j.legs) {
      if (leg.isWalk) continue;
      if (leg.fromName.isNotEmpty) stops.add(leg.fromName);
      if (leg.toName.isNotEmpty) stops.add(leg.toName);
    }
    if (stops.isEmpty) return JourneyAccessibility.unknown;

    final results = await Future.wait(stops.map((s) async {
      try {
        return MapEntry(s, await fetchFacilities(s));
      } catch (_) {
        return MapEntry(s, const <StationFacility>[]);
      }
    }));

    final checked = <String>[];
    final broken = <String>[];
    for (final e in results) {
      final elevators = e.value.where((f) => f.isElevator).toList();
      if (elevators.isEmpty) continue; // no data → don't count
      checked.add(e.key);
      if (elevators.any((f) => f.isBroken)) broken.add(e.key);
    }

    if (checked.isEmpty) return JourneyAccessibility.unknown;
    if (broken.isNotEmpty) {
      return JourneyAccessibility(
        status: JourneyAccessibilityStatus.brokenElevator,
        brokenAt: broken, checked: checked,
      );
    }
    return JourneyAccessibility(
      status: JourneyAccessibilityStatus.barrierFree,
      checked: checked,
    );
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
  // TRIP STOP SEQUENCE — "Wo fährt der Bus hin?"
  // ══════════════════════════════════════════════════════════════

  final _tripStopsCache = <String, _CachedTripStops>{};

  /// Fetch the full stop sequence for one departure — every station between
  /// the user's boarding stop and the line's final stop, with planned +
  /// realtime times. Used by the "Wo fährt der Bus hin?" dialog.
  ///
  /// Strategy: run `XSLT_TRIP_REQUEST2` (EFA) or HAFAS TripSearch between
  /// the boarding stop and the line's `destID`. The first returned leg is
  /// this line's route; its `stopSeq` / `stopL` yields every intermediate
  /// station.
  ///
  /// Cached 60 seconds per (stopID, destID, line) so re-opening the dialog
  /// doesn't hammer the API.
  Future<List<TripStop>> fetchTripStops(Departure dep) async {
    final route = await fetchTripRoute(dep);
    return route.stops;
  }

  /// Same as [fetchTripStops] but returns [TripRoute] with polyline for the map.
  ///
  /// Accepts either:
  ///   - EFA: `stopID` + `destID` (both required, used with XSLT_TRIP_REQUEST2)
  ///   - HAFAS: `tripID` alone (JourneyDetails method, most reliable)
  ///   - HAFAS: `stopID` + `destID` (TripSearch fallback if no tripID)
  Future<TripRoute> fetchTripRoute(Departure dep) async {
    final empty = TripRoute(stops: const [], path: const []);
    final fromId = dep.stopID;
    final toId = dep.destID;
    final tripId = dep.tripID;
    final hasTrip = tripId != null && tripId.isNotEmpty;
    final hasFromTo = fromId != null && fromId.isNotEmpty && toId != null && toId.isNotEmpty;
    if (!hasTrip && !hasFromTo) {
      _log.info('Transit: fetchTripRoute skipped — no tripID and no stopID/destID', tag: 'TRANSIT');
      return empty;
    }
    // Cache key varies by which lookup path we're taking.
    final cacheKey = hasTrip
        ? 'jid|$tripId|${dep.line}'
        : '$fromId|$toId|${dep.line}|${dep.plannedTime.toIso8601String()}';
    final cached = _tripStopsCache[cacheKey];
    if (cached != null && DateTime.now().difference(cached.at) < const Duration(seconds: 60)) {
      return TripRoute(stops: cached.stops, path: cached.path);
    }

    TripRoute route = empty;
    try {
      // Bahn.de tripID starts with "2|#" (dbnav format).
      // Use dbnav /fahrt/{zuglaufId} endpoint (works for ICE/IC/RE/RB).
      final isDbNavTrip = hasTrip && (tripId.startsWith('2|') || tripId.contains('#VN#'));
      if (isDbNavTrip) {
        route = await _dbnavTripRoute(dep);
      } else {
        final provider = activeProvider;
        if (provider == null) return empty;
        if (provider.api == TransitApiType.efa) {
          // EFA still requires stopID + destID.
          if (hasFromTo) route = await _efaTripRoute(provider, dep);
        } else {
          // HAFAS: _hafasTripRoute internally prefers JourneyDetails via jid,
          // then falls back to TripSearch (which needs destID).
          route = await _hafasTripRoute(provider, dep);
        }
      }
    } catch (e) {
      _log.error('Transit: fetchTripRoute failed for line ${dep.line}: $e', tag: 'TRANSIT');
    }
    _tripStopsCache[cacheKey] = _CachedTripStops(route.stops, DateTime.now(), path: route.path);
    _log.info('Transit: fetchTripRoute line ${dep.line} → ${route.stops.length} stops, ${route.path.length} path points', tag: 'TRANSIT');
    return route;
  }

  /// bahn.de dbnav `/fahrt/{zuglaufId}` — returnează trip stops complete
  /// pentru un tren specific. Folosit când click pe ICE/IC/RE/RB in Hbf/Bhf
  /// tab pentru a vedea "unde merge trenul + Ausstieg-Alarm".
  ///
  /// Response schema (din `test/fixtures/dbnav-trip.json`):
  /// - `halte: [{abgangsDatum, ort:{name,evaNr,position:{lat,lon}}, gleis}]`
  /// - `polylineGroup.polylineDesc[].coordinates: [{longitude, latitude}]`
  Future<TripRoute> _dbnavTripRoute(Departure dep) async {
    final empty = TripRoute(stops: const [], path: const []);
    final tripId = dep.tripID;
    if (tripId == null || tripId.isEmpty) return empty;
    try {
      final encoded = Uri.encodeComponent(tripId);
      final uri = Uri.parse('$_dbNavBase/mob/zuglauf/$encoded');
      final resp = await _client.get(uri, headers: {
        'Accept': 'application/x.db.vendo.mob.zuglauf.v2+json',
        'X-Correlation-ID': _dbNavCorrelationId(),
      }).timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) {
        _log.debug('Transit: dbnav zuglauf returned ${resp.statusCode}', tag: 'TRANSIT');
        return empty;
      }
      final data = jsonDecode(_decodeUtf8(resp));
      if (data is! Map) return empty;
      final halte = data['halte'];
      if (halte is! List) return empty;
      final stops = <TripStop>[];
      final currentStopId = dep.stopID;
      for (final h in halte) {
        if (h is! Map) continue;
        final abg = h['abgangsDatum']?.toString() ?? h['ankunftsDatum']?.toString();
        if (abg == null) continue;
        // .toLocal() — convert UTC-tagged ISO string la timezone-ul device
        // (Berlin CEST/CET) — same fix ca la _fetchDeparturesBahnDe.
        final plannedRaw = DateTime.tryParse(abg);
        if (plannedRaw == null) continue;
        final planned = plannedRaw.toLocal();
        final ezAbg = h['ezAbgangsDatum']?.toString() ??
                      h['ezAnkunftsDatum']?.toString();
        final rtRaw = ezAbg == null ? null : DateTime.tryParse(ezAbg);
        final rt = rtRaw?.toLocal();
        final ort = h['ort'];
        String name = '';
        String stopId = '';
        double? lat, lon;
        if (ort is Map) {
          name = ort['name']?.toString() ?? '';
          stopId = (ort['evaNr'] ?? ort['stationId'] ?? '').toString();
          final pos = ort['position'];
          if (pos is Map) {
            lat = (pos['latitude'] as num?)?.toDouble();
            lon = (pos['longitude'] as num?)?.toDouble();
          }
        }
        if (name.isEmpty) continue;
        final delay = rt != null ? rt.difference(planned).inMinutes : 0;
        stops.add(TripStop(
          name: name,
          stopID: stopId,
          plannedTime: planned,
          realtimeTime: rt,
          delay: delay > 0 ? delay : 0,
          isCurrent: stopId == currentStopId,
          platform: h['gleis']?.toString(),
          lat: lat,
          lon: lon,
        ));
      }
      // Parse polyline coords
      final path = <(double, double)>[];
      final polyGroup = data['polylineGroup'];
      if (polyGroup is Map) {
        final polyDescs = polyGroup['polylineDesc'];
        if (polyDescs is List) {
          for (final pd in polyDescs) {
            if (pd is! Map) continue;
            final coords = pd['coordinates'];
            if (coords is! List) continue;
            for (final c in coords) {
              if (c is! Map) continue;
              final lat = (c['latitude'] as num?)?.toDouble();
              final lon = (c['longitude'] as num?)?.toDouble();
              if (lat != null && lon != null) path.add((lat, lon));
            }
          }
        }
      }
      _log.info('Transit: dbnav trip ${dep.line} → ${stops.length} stops, ${path.length} path points',
          tag: 'TRANSIT');
      return TripRoute(stops: stops, path: path);
    } catch (e) {
      _log.debug('Transit: dbnav trip exception: $e', tag: 'TRANSIT');
      return empty;
    }
  }

  Future<TripRoute> _efaTripRoute(TransitProviderConfig p, Departure dep) async {
    final when = dep.realtimeTime ?? dep.plannedTime;
    final dateStr = '${when.year}${when.month.toString().padLeft(2, '0')}${when.day.toString().padLeft(2, '0')}';
    final timeStr = '${when.hour.toString().padLeft(2, '0')}${when.minute.toString().padLeft(2, '0')}';
    final uri = Uri.parse(
      '${p.baseUrl}/XSLT_TRIP_REQUEST2'
      '?outputFormat=JSON&locationServerActive=1&useRealtime=1&calcNumberOfTrips=1'
      '&type_origin=stop&name_origin=${Uri.encodeComponent(dep.stopID!)}'
      '&type_destination=stop&name_destination=${Uri.encodeComponent(dep.destID!)}'
      '&itdDate=$dateStr&itdTime=$timeStr'
      '&coordOutputFormat=WGS84[dd.ddddd]',
    );
    final resp = await _client.get(uri).timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) return TripRoute(stops: const [], path: const []);
    final data = jsonDecode(_decodeUtf8(resp));
    // DING returns `trips` as {trip: [...]} or {trip: {...}}; MVV returns a bare list.
    dynamic tripsRoot = data['trips'];
    dynamic firstTrip;
    if (tripsRoot is List && tripsRoot.isNotEmpty) {
      firstTrip = tripsRoot.first;
    } else if (tripsRoot is Map) {
      final t = tripsRoot['trip'];
      firstTrip = t is List ? (t.isNotEmpty ? t.first : null) : t;
    }
    if (firstTrip is! Map) return TripRoute(stops: const [], path: const []);
    final legs = firstTrip['legs'] as List? ?? [];
    // Find the leg matching this line (skip walks)
    for (final leg in legs) {
      final mode = leg['mode'] as Map? ?? {};
      if (mode['type']?.toString() == '100' || mode['type']?.toString() == '99') continue;
      final lineNum = mode['number']?.toString() ?? mode['symbol']?.toString() ?? '';
      if (lineNum != dep.line && !lineNum.contains(dep.line)) continue;
      final seqRaw = leg['stopSeq'];
      final seq = seqRaw is List ? seqRaw : (seqRaw is Map ? (seqRaw['stop'] as List? ?? []) : []);
      final stops = _parseEfaStopSequence(seq, dep.stopID!);
      // Parse polyline "lon,lat lon,lat …" (space-separated tokens).
      final pathStr = leg['path']?.toString() ?? '';
      final path = <(double, double)>[];
      for (final token in pathStr.split(' ')) {
        final xy = token.split(',');
        if (xy.length != 2) continue;
        final lon = double.tryParse(xy[0]);
        final lat = double.tryParse(xy[1]);
        if (lon == null || lat == null) continue;
        path.add((lat, lon));
      }
      return TripRoute(stops: stops, path: path);
    }
    return TripRoute(stops: const [], path: const []);
  }

  List<TripStop> _parseEfaStopSequence(List seq, String currentStopId) {
    final out = <TripStop>[];
    for (final s in seq) {
      if (s is! Map) continue;
      final name = s['name']?.toString() ?? '';
      final ref = s['ref'] is Map ? s['ref'] as Map : {};
      final id = ref['id']?.toString() ?? s['stopID']?.toString() ?? '';
      if (name.isEmpty) continue;
      final dt = s['dateTime'];
      final planned = _parseEfaTripDateTime(dt) ?? _parseEfaDateTime(dt is Map ? Map<String, dynamic>.from(dt) : {});
      if (planned == null) continue;
      DateTime? rt;
      if (dt is Map && (dt['rtDate'] != null || dt['rtTime'] != null)) {
        rt = _parseEfaTripDateTime({
          'date': dt['rtDate'] ?? dt['date'],
          'time': dt['rtTime'] ?? dt['time'],
        });
      }
      final delayMin = (rt != null) ? rt.difference(planned).inMinutes : 0;
      // Parse coords "lon,lat" (EFA convention).
      double? lat, lon;
      final coordsStr = ref['coords']?.toString();
      if (coordsStr != null) {
        final xy = coordsStr.split(',');
        if (xy.length == 2) {
          lon = double.tryParse(xy[0]);
          lat = double.tryParse(xy[1]);
        }
      }
      out.add(TripStop(
        name: name,
        stopID: id,
        plannedTime: planned,
        realtimeTime: rt,
        delay: delayMin > 0 ? delayMin : 0,
        isCurrent: id == currentStopId,
        platform: _cleanEfaPlatform(s['platform']),
        lat: lat,
        lon: lon,
      ));
    }
    return out;
  }

  /// Fetch the passing-stop list for a single HAFAS journey identified by
  /// `dep.tripID` (jid). Returns 20+ TripStop entries with planned+realtime
  /// times, lat/lon coords, platforms — everything the trip-sequence UI
  /// needs, without requiring a destination hint (unlike TripSearch which
  /// needs `depLocL` + `arrLocL`).
  Future<TripRoute> _hafasJourneyDetails(TransitProviderConfig p, Departure dep) async {
    final empty = TripRoute(stops: const [], path: const []);
    final jid = dep.tripID;
    if (jid == null || jid.isEmpty) return empty;
    final call = _buildSignedHafasCall(p, [
      {
        'meth': 'JourneyDetails',
        'req': {
          'jid': jid,
          'getPasslist': true,
          'getPolyline': true, // optional — include drawable path if backend has it
        },
      },
    ]);
    try {
      final resp = await _client.post(Uri.parse(call.url),
          headers: {'Content-Type': 'application/json'},
          body: call.body).timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return empty;
      final data = jsonDecode(_decodeUtf8(resp));
      final res = data['svcResL']?[0];
      if (res == null || res['err'] != 'OK') return empty;
      final r = res['res'];
      if (r is! Map) return empty;
      final common = r['common'] ?? {};
      final locL = common['locL'] as List? ?? [];
      final journey = r['journey'] ?? {};
      final stopL = journey['stopL'] as List? ?? [];
      // Fall back to today when the response omits the date field.
      final date = journey['date']?.toString() ?? dep.plannedTime.toIso8601String().substring(0, 10).replaceAll('-', '');

      final out = <TripStop>[];
      final path = <(double, double)>[];
      for (final s in stopL) {
        if (s is! Map) continue;
        final locX = s['locX'] as int? ?? -1;
        if (locX < 0 || locX >= locL.length) continue;
        final loc = locL[locX] as Map;
        final name = loc['name']?.toString() ?? '';
        if (name.isEmpty) continue;
        final id = (loc['extId'] ?? loc['lid'])?.toString() ?? '';

        // Prefer dep time (dTimeS), fall back to arr time (aTimeS) at terminus.
        final planned = _parseHafasDateTime(date, (s['dTimeS'] ?? s['aTimeS'] ?? '').toString());
        if (planned == null) continue;
        final rtStr = (s['dTimeR'] ?? s['aTimeR'] ?? '').toString();
        final rt = rtStr.isNotEmpty ? _parseHafasDateTime(date, rtStr) : null;
        final delayMin = (rt != null) ? rt.difference(planned).inMinutes : 0;

        // HAFAS coord: crd.x = lon*1e6, crd.y = lat*1e6
        double? lat, lon;
        final crd = loc['crd'];
        if (crd is Map) {
          final x = crd['x']; final y = crd['y'];
          if (x is num) lon = x / 1000000;
          if (y is num) lat = y / 1000000;
        }
        if (lat != null && lon != null) path.add((lat, lon));

        out.add(TripStop(
          name: name,
          stopID: id,
          plannedTime: planned,
          realtimeTime: rt,
          delay: delayMin > 0 ? delayMin : 0,
          isCurrent: id == dep.stopID,
          platform: (s['dPlatfR'] ?? s['aPlatfR'] ?? s['dPlatfS'] ?? s['aPlatfS'])?.toString(),
          lat: lat,
          lon: lon,
        ));
      }
      return TripRoute(stops: out, path: path);
    } catch (e) {
      _log.debug('Transit: JourneyDetails failed: $e', tag: 'TRANSIT');
      return empty;
    }
  }

  Future<TripRoute> _hafasTripRoute(TransitProviderConfig p, Departure dep) async {
    // Prefer JourneyDetails when we have the jid — it returns the exact
    // vehicle's stop sequence without needing a destination hint. This is
    // what mainstream apps like DB Navigator use for the "stops" list.
    if (dep.tripID != null && dep.tripID!.isNotEmpty) {
      final byJid = await _hafasJourneyDetails(p, dep);
      if (byJid.stops.isNotEmpty) return byJid;
    }
    final when = dep.realtimeTime ?? dep.plannedTime;
    final dateStr = '${when.year}${when.month.toString().padLeft(2, '0')}${when.day.toString().padLeft(2, '0')}';
    final timeStr = '${when.hour.toString().padLeft(2, '0')}${when.minute.toString().padLeft(2, '0')}00';
    // TripSearch fallback — only reachable if both endpoints are known.
    if (dep.destID == null || dep.destID!.isEmpty) {
      return TripRoute(stops: const [], path: const []);
    }
    final call = _buildSignedHafasCall(p, [
      {
        'meth': 'TripSearch',
        'req': {
          'depLocL': [{'lid': dep.stopID}],
          'arrLocL': [{'lid': dep.destID}],
          'outDate': dateStr,
          'outTime': timeStr,
          'numF': 1,
          'getPasslist': true, // include intermediate stops
          'outFrwd': true,
        },
      },
    ]);
    final resp = await _client.post(Uri.parse(call.url),
        headers: {'Content-Type': 'application/json'},
        body: call.body).timeout(const Duration(seconds: 12));
    final empty = TripRoute(stops: const [], path: const []);
    if (resp.statusCode != 200) return empty;
    final data = jsonDecode(_decodeUtf8(resp));
    if (data['err']?.toString() != null && data['err'] != 'OK') return empty;
    final svc = data['svcResL']?[0]?['res'];
    if (svc is! Map) return empty;
    final common = svc['common'] ?? {};
    final locL = common['locL'] as List? ?? [];
    final conL = svc['outConL'] as List? ?? [];
    if (conL.isEmpty) return empty;
    final firstCon = conL.first;
    final date = firstCon['date']?.toString() ?? dateStr;
    final secL = firstCon['secL'] as List? ?? [];
    for (final sec in secL) {
      if (sec['type']?.toString() != 'JNY') continue;
      final jny = sec['jny'] ?? {};
      final stopL = jny['stopL'] as List? ?? [];
      final out = <TripStop>[];
      final path = <(double, double)>[];
      for (final s in stopL) {
        if (s is! Map) continue;
        final locX = s['locX'] as int? ?? -1;
        if (locX < 0 || locX >= locL.length) continue;
        final loc = locL[locX] as Map;
        final name = loc['name']?.toString() ?? '';
        final id = loc['lid']?.toString() ?? loc['extId']?.toString() ?? '';
        if (name.isEmpty) continue;
        final planned = _parseHafasDateTime(date, (s['dTimeS'] ?? s['aTimeS'] ?? '').toString());
        if (planned == null) continue;
        final rtStr = (s['dTimeR'] ?? s['aTimeR'] ?? '').toString();
        final rt = rtStr.isNotEmpty ? _parseHafasDateTime(date, rtStr) : null;
        final delayMin = (rt != null) ? rt.difference(planned).inMinutes : 0;
        // HAFAS coord: `crd.x = lon*1e6`, `crd.y = lat*1e6`.
        double? lat, lon;
        final crd = loc['crd'];
        if (crd is Map) {
          final x = crd['x']; final y = crd['y'];
          if (x is num) lon = x / 1000000;
          if (y is num) lat = y / 1000000;
        }
        if (lat != null && lon != null) path.add((lat, lon));
        out.add(TripStop(
          name: name,
          stopID: id,
          plannedTime: planned,
          realtimeTime: rt,
          delay: delayMin > 0 ? delayMin : 0,
          isCurrent: id == dep.stopID,
          platform: s['dPlatfR']?.toString() ?? s['dPlatfS']?.toString(),
          lat: lat,
          lon: lon,
        ));
      }
      return TripRoute(stops: out, path: path);
    }
    return empty;
  }

  // ══════════════════════════════════════════════════════════════
  // TRIP SEARCH — "Verbindung suchen" tab
  // ══════════════════════════════════════════════════════════════

  /// Autocomplete stops / addresses / POIs matching [query].
  ///
  /// 2026-07-11 SIMPLIFICARE: foloseste DOAR bahn.de `orte` endpoint
  /// (typ=ALL). Acopera intreaga Germania si returneaza:
  ///   - Stații ("A=1@O=Ulm Hbf@...")  → tip 'stop'
  ///   - Adrese ("A=2@O=Ulm, Königstraße 15@...")  → tip 'address'
  ///   - POI-uri (spitale, școli etc.)  → tip 'poi'
  ///
  /// bahn.de accepta atat adrese cat si statii ca `abfahrtsHalt`/
  /// `ankunftsHalt` in trip search → foloseste walk automat de la adresa
  /// la statia cea mai apropiata. Deci autocomplete pe adresa e suficient
  /// pentru un flow complet "casa mea → destinatie".
  Future<List<TransitLocation>> searchLocations(String query) async {
    if (query.trim().length < 2) return [];
    try {
      final results = await _bahnLocationSearch(query);
      // Sort: stops (A=1) first, apoi adrese (A=2), apoi POI (A=4).
      final stops = <TransitLocation>[];
      final addresses = <TransitLocation>[];
      final others = <TransitLocation>[];
      for (final loc in results) {
        if (loc.id.startsWith('A=1@')) {
          stops.add(loc);
        } else if (loc.id.startsWith('A=2@')) {
          addresses.add(loc);
        } else {
          others.add(loc);
        }
      }
      return [...stops, ...addresses, ...others].take(15).toList();
    } catch (e) {
      _log.debug('Transit: bahn.de search failed: $e', tag: 'TRANSIT');
      return [];
    }
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
    /// When true, filter results to only journeys covered by the 49€
    /// Deutschlandticket. bahn.de gets the native flag; EFA/HAFAS results
    /// are stripped client-side (drop journeys containing ICE/IC/EC/IR legs).
    bool onlyDeutschlandTicket = false,
    /// Case-insensitive line names to exclude from results — e.g. {"S1"}.
    /// Used by "Alternative suchen" when the primary journey's line is hit
    /// by an active HIM disruption. Any Journey whose vehicle-leg `line`
    /// (trim + lowercase) matches an entry is dropped.
    Set<String>? excludedLines,
  }) async {
    final arriveBy = arrivalTime != null;
    final when = arrivalTime ?? departureTime ?? DateTime.now();
    List<Journey> results = [];

    // 2026-07-11 SIMPLIFICARE: Verbindung suchen foloseste DOAR bahn.de.
    // Motive:
    //   1. bahn.de acopera intreaga Germania (nu doar 1 provider regional)
    //   2. bahn.de suporta flag nativ `nurDeutschlandTicketVerbindungen`
    //   3. bahn.de suporta ADRESE (typ=ADRESSE) — nu doar stații — cu walk
    //      automat de la adresa exacta la statia cea mai apropiata
    //   4. HAFAS/EFA local returna line-uri fara prefix ("619" pt ICE 619)
    //      care corupea D-Ticket filter (aparea ca autobuz)
    //   5. Cross-provider HAFAS raram functioneaza (AUTH blocked)
    //
    // Daca bahn.de pica sau nu gaseste nimic → results ramane gol.
    try {
      // Daca from.id / to.id vin din bahn.de search (cel mai des cazul),
      // folosim direct trip search. Daca vin din alt provider (name-only),
      // apelam name-based search care re-rezolva prin bahn.de LocSearch.
      final fromFromBahn = from.id.startsWith('A=') && from.id.contains('@L=');
      final toFromBahn = to.id.startsWith('A=') && to.id.contains('@L=');
      if (fromFromBahn && toFromBahn) {
        results = await _bahnTripSearch(
          from, to, when,
          arriveBy: arriveBy,
          onlyDeutschlandTicket: onlyDeutschlandTicket,
        );
      } else {
        results = await _bahnTripSearchByName(
          from.name, to.name, when,
          arriveBy: arriveBy,
          onlyDeutschlandTicket: onlyDeutschlandTicket,
        );
      }
    } catch (e) {
      _log.error('Transit: bahn.de trip search failed: $e', tag: 'TRANSIT');
    }

    // Filter journeys din trecut — bahn.de + HAFAS uneori returnează
    // conexiuni deja plecate (special când user cere trip search fără
    // `when` param sau când server-ul are ceas-drift).
    // Elimin journeys ai căror dep < now - 5min.
    if (results.isNotEmpty) {
      final now = DateTime.now();
      final cutoff = now.subtract(const Duration(minutes: 5));
      final before = results.length;
      results = results.where((j) => j.depTime.isAfter(cutoff)).toList();
      // Sort by depTime crescator pentru afisare corectă.
      results.sort((a, b) => a.depTime.compareTo(b.depTime));
      if (results.length < before) {
        _log.info('Transit: filtrat ${before - results.length} journeys '
            'din trecut, ${results.length} rămase', tag: 'TRANSIT');
      }
    }

    // Client-side D-Ticket filter for local provider results.
    //
    // FALLBACK 2026-07-11: dacă filter STRICT respinge TOATE journeys
    // (ex. Saarbrücken → Ulm real are DOAR variante cu ICE via Mannheim
    // — nu există journey Nahverkehr pur), returnăm originale în loc de
    // "Keine Verbindung". UI-ul afișează badge Fernverkehr per journey +
    // costul estimat (deja implementat via `_FareBadge` in JourneyCard).
    if (onlyDeutschlandTicket && results.isNotEmpty) {
      final before = results.length;
      final filtered = results.where(_isDeutschlandTicketOnly).toList();
      if (filtered.isEmpty && before > 0) {
        _log.info('Transit: D-Ticket filter respins toate $before journeys '
            '— return originale (contin ICE — user vede badge Fernverkehr)',
            tag: 'TRANSIT');
        // NU aplicăm filter — returnăm originalele.
      } else {
        results = filtered;
        _log.info('Transit: D-Ticket filter kept ${results.length}/$before journeys',
            tag: 'TRANSIT');
      }
    }

    // Alternative-line filter (client-side): drop journeys that use any of
    // the excluded line names. Case-insensitive exact-match on leg.line.
    if (excludedLines != null && excludedLines.isNotEmpty && results.isNotEmpty) {
      final excl = excludedLines.map((s) => s.trim().toLowerCase()).toSet();
      final before = results.length;
      results = results.where((j) => !j.legs.any(
        (l) => !l.isWalk && excl.contains(l.line.trim().toLowerCase()),
      )).toList();
      _log.info('Transit: excluded lines filter kept ${results.length}/$before journeys', tag: 'TRANSIT');
    }

    return results;
  }

  /// Journey qualifies for the 49€ Deutschlandticket. Walking legs always OK.
  ///
  /// Approach: WHITELIST by productType (most reliable) + line-prefix BLACKLIST
  /// pentru cazul când productType e ambiguu ('train' poate fi Regional-IRE
  /// sau Fernverkehr-ICE).
  ///
  /// D-Ticket ACCEPTĂ (Nahverkehr):
  ///   productType: regional, suburban, subway, tram, bus, ferry, walk
  ///   Prefixes: RE, RB, RS, RJX (regional), IRE, MEX, ALX, BRB, HLB, HKX,
  ///             NBE, NWB, ENO, ODEG, VIAS, VBG, ERB, MRB, WFB, WEG,
  ///             erixx, metronom, vlexx, meridian, BOB, agilis, eurobahn,
  ///             Abellio, DB Regio, Chiemgau, Cantus, Trilex, TLX,
  ///             S (S-Bahn), U (U-Bahn), STR, T (Tram), M (München-Tram)
  ///
  /// D-Ticket RESPINGE (Fernverkehr):
  ///   productType: train (ICE/IC/EC/IR)
  ///   Prefixes: ICE, IC, EC, IR, TGV, RJ, NJ, ECE, EN, WESTbahn, Thalys,
  ///             FLX (FlixTrain), CNL, EIC, TER
  ///
  /// EXCEPȚII (IC-Linien acceptate ca Nahverkehr conform DB 2024+):
  ///   - IC 61: Bebra ↔ Erfurt ↔ Chemnitz (Sachsen, Thüringen, Hessen)
  ///   - IC 62: Aachen ↔ Kassel (NRW/Hessen segment specific)
  ///   - IC 68: Berlin ↔ Cottbus (Brandenburg)
  ///   Aceste linii cu numărul concret sunt acceptate — verificate pe leg.line.
  ///
  /// Case-insensitive, strips leading/trailing whitespace înainte de check.
  static const _dTicketAllowedProductTypes = <String>{
    'regional', 'suburban', 'subway', 'tram', 'bus', 'ferry', 'walk',
  };

  /// IC-Linien speciale care sunt integrate în tarife locale (D-Ticket OK).
  /// Actualizat 2026 din bahn.de/service/nahverkehrsfreigabe.
  ///
  /// Kanonische Liste 2026:
  /// • Dresden ↔ Freiberg ↔ Chemnitz (alle IC — cover via number match)
  /// • Dortmund ↔ Iserlohn-Letmathe ↔ Dillenburg (IC 2222-2226, 2320,
  ///   2323-2327)
  /// • Bremen ↔ Emden Außenhafen / Norddeich Mole (alle IC)
  /// • Rostock ↔ Stralsund (alle IC)
  /// • Erfurt ↔ Weimar ↔ Jena ↔ Gera (alle IC — ex "IC 61")
  /// • Stuttgart ↔ Singen ↔ Konstanz (Gäubahn, alle IC)
  /// • Westerland (Sylt) ↔ Niebüll (IC 2075, doar Mo-Fr)
  ///
  /// Wegfall ab 2025-12-14 (VBB-cancel):
  /// • Berlin ↔ Elsterwerda (IC) — NU mai e valabil
  /// • Berlin ↔ Prenzlau (IC/ICE) — NU mai e valabil
  /// • Potsdam ↔ Cottbus (IC) — NU mai e valabil
  static const _dTicketIcLines = <String>{
    // Cu spațiu
    'IC 2222', 'IC 2223', 'IC 2224', 'IC 2225', 'IC 2226',
    'IC 2320', 'IC 2323', 'IC 2324', 'IC 2325', 'IC 2326', 'IC 2327',
    'IC 2075',
    // Fără spațiu
    'IC2222', 'IC2223', 'IC2224', 'IC2225', 'IC2226',
    'IC2320', 'IC2323', 'IC2324', 'IC2325', 'IC2326', 'IC2327',
    'IC2075',
  };

  /// Prefixes stricte Fernverkehr — respinge chiar dacă productType e ambiguu.
  /// Ordonat descrescător după lungime pentru a nu matcha prefix scurt când
  /// există unul mai lung ("ECE" înainte de "EC", "ICE" înainte de "IC").
  static const _fernverkehrPrefixes = <String>[
    'ICE', 'ECE', 'ECX', 'THALYS', 'FLIXT',
    'IC', 'EC', 'IR', 'TGV', 'RJ', 'NJ', 'EN', 'FLX', 'CNL', 'EIC', 'TER',
  ];

  /// True dacă `line` este marcat ca Fernverkehr (nu D-Ticket).
  bool _lineIsFernverkehr(String line) {
    final l = line.trim().toUpperCase();
    if (l.isEmpty) return false;
    for (final prefix in _fernverkehrPrefixes) {
      if (l == prefix) return true;
      // Prefix urmat de spațiu, cifră sau `-` (ICE100, ICE 100, ICE-T, IC-1)
      if (l.length > prefix.length && l.startsWith(prefix)) {
        final next = l[prefix.length];
        if (next == ' ' || next == '-' || next == '.' || (next.codeUnitAt(0) >= 0x30 && next.codeUnitAt(0) <= 0x39)) {
          // Extra check: exception pentru IC 61/62/68.
          if (prefix == 'IC') {
            // Extract IC number (până la primul non-digit după prefix).
            final m = RegExp(r'^IC\s?(\d+)').firstMatch(l);
            if (m != null) {
              final key = 'IC ${m.group(1)}';
              if (_dTicketIcLines.contains(key) || _dTicketIcLines.contains('IC${m.group(1)}')) {
                return false; // IC 61/62/68 → NU e Fernverkehr, e Nahverkehr!
              }
            }
          }
          return true;
        }
      }
    }
    return false;
  }

  /// Public wrapper pentru unit tests. Rulează același filter ca cel din
  /// `searchJourneys(onlyDeutschlandTicket: true)`.
  bool isJourneyDTicketCompatible(Journey j) => _isDeutschlandTicketOnly(j);

  bool _isDeutschlandTicketOnly(Journey j) {
    // Din server logs v6.59.52: bahn.de returneaza `productType='bus'` pentru
    // TOATE legs (incl. ICE cu line="9557", "1015"). Deci `productType` e
    // total unreliable — filtram STRICT pe line NAME cu whitelist.
    //
    // Regula noua STRICTA:
    // 1. Line prefix Nahverkehr (RE, RB, S, U, MEX, IRE, ...) → ACCEPT
    // 2. IC number in Nahverkehrsfreigabe list (IC 2222 etc.) → ACCEPT
    // 3. Brand name Nahverkehr (metronom, erixx, ...) → ACCEPT
    // 4. Everything else (INCL. line = doar cifre gen "9557") → REJECT
    const knownNahverkehrPrefixes = [
      'RE', 'RB', 'RS', 'RJX', 'IRE', 'MEX', 'ALX', 'BRB', 'HLB', 'HKX',
      'NBE', 'NWB', 'ENO', 'ODEG', 'VIAS', 'VBG', 'ERB', 'MRB', 'WFB',
      'WEG', 'ERX', 'TLX', 'ABR', 'RTB', 'BOB', 'CAN', 'DPN', 'FEG',
      'FLB', 'HZL', 'MEG', 'NEB', 'OPB', 'OSB', 'PRE', 'SBB', 'SBS',
      'STB', 'SWE', 'UBB', 'VEC', 'VEN', 'WBA', 'DLB', 'DAB', 'AVG',
      'BSB', 'BLB', 'ESB',
      // Nahverkehr specific short codes
      'S', 'U', 'STR', 'TRAM', 'M',
      // Ersatzverkehr / bus înlocuitor
      'SEV', 'BUS', 'EV',
    ];
    const brandNames = ['METRONOM', 'ERIXX', 'MERIDIAN', 'AGILIS', 'EUROBAHN',
      'ABELLIO', 'CANTUS', 'TRILEX', 'VLEXX', 'BAYERISCHE OBERLANDBAHN',
      'CHIEMGAU', 'ALLGÄU', 'BAYERN', 'ILMEBAHN', 'HANSEATISCHE',
    ];

    for (final leg in j.legs) {
      if (leg.isWalk) continue;
      final pt = leg.productType.toLowerCase();
      final line = leg.line.trim();

      _log.info('Transit: D-Ticket examine line="$line" pt="$pt" '
          'from="${leg.fromName}" to="${leg.toName}"', tag: 'TRANSIT');

      // Bus productType clar valid (pentru bus stops locale — Bus 12 etc.)
      // TREBUIE să distingem: bus real vs. ICE mislabel ca 'bus'.
      // Doar accept 'bus'/'tram'/'ferry'/'walk' cand line NU e doar cifre.
      // (ICE apare cu line="9557" fara prefix.)

      // ═══ STEP 1: LINE FERNVERKEHR PREFIX → REJECT ═══
      if (_lineIsFernverkehr(line)) {
        _log.info('Transit: D-Ticket REJECT "$line" (Fernverkehr prefix)',
            tag: 'TRANSIT');
        return false;
      }

      // ═══ STEP 1b: IC Nahverkehrsfreigabe → ACCEPT DIRECT ═══
      // IC 2222, IC 2075 etc. — sunt IC dar Nahverkehr acceptate D-Ticket.
      // `_lineIsFernverkehr` returnează false pentru astea (excepție), dar
      // restul filter le-ar respinge la Step 5. Accept explicit aici.
      {
        final icMatch = RegExp(r'^IC\s?(\d+)').firstMatch(line.toUpperCase());
        if (icMatch != null) {
          final num = icMatch.group(1)!;
          if (_dTicketIcLines.contains('IC $num') ||
              _dTicketIcLines.contains('IC$num')) {
            continue; // ACCEPT — IC Nahverkehrsfreigabe
          }
        }
      }

      // ═══ STEP 2: LINE = DOAR CIFRE → REJECT ═══
      // ICE/IC de la bahn.de trip search vin cu line="9557", "1015", "619"
      // (kurzText fără prefix). Nahverkehr are ALWAYS un prefix ("S3", "RB70").
      if (RegExp(r'^\d+$').hasMatch(line)) {
        _log.info('Transit: D-Ticket REJECT "$line" (only digits — likely ICE)',
            tag: 'TRANSIT');
        return false;
      }

      // ═══ STEP 3: LINE Nahverkehr prefix / brand → ACCEPT ═══
      final l = line.toUpperCase();
      bool isNah = false;
      for (final p in knownNahverkehrPrefixes) {
        if (l == p || l.startsWith('$p ') || l.startsWith('$p-') ||
            (l.length > p.length && l.startsWith(p) &&
             l.codeUnitAt(p.length) >= 0x30 && l.codeUnitAt(p.length) <= 0x39)) {
          isNah = true;
          break;
        }
      }
      if (!isNah) {
        for (final b in brandNames) {
          if (l.contains(b)) { isNah = true; break; }
        }
      }
      if (isNah) continue;

      // ═══ STEP 4: Safe passthrough pentru productType clar Nahverkehr ═══
      // Cazul rar cand line e text ("Fußweg", "Umstieg") — accept dacă
      // productType e clar walk/tram/subway/ferry (dar NU bus — bus vine
      // cu productType=bus si pentru ICE).
      if (pt == 'walk' || pt == 'tram' || pt == 'subway' || pt == 'suburban' ||
          pt == 'ferry' || pt == 'regional') {
        continue;
      }

      _log.info('Transit: D-Ticket REJECT "$line" pt="$pt" '
          '(not Nahverkehr pattern)', tag: 'TRANSIT');
      return false;
    }
    return true;
  }

  /// bahn.de journey search that resolves location names to bahn.de IDs first.
  Future<List<Journey>> _bahnTripSearchByName(
    String fromName, String toName, DateTime when,
    {bool arriveBy = false, bool onlyDeutschlandTicket = false}
  ) async {
    // Bahn.de e sensibil la format: "Saarbrücken, Hauptbahnhof" (HAFAS-style
    // cu virgulă) nu găsește potrivire — dar "Saarbrücken Hbf" da. Încercăm
    // 3 variante în ordinea:
    //   1) numele original (dacă vine deja curat de la un autocomplete bahn.de)
    //   2) fără virgulă, "Hauptbahnhof" → "Hbf" (bahn.de idiom)
    //   3) doar prima parte înaintea virgulei ("Saarbrücken")
    final fromVariants = _bahnNameVariants(fromName);
    final toVariants = _bahnNameVariants(toName);

    List<TransitLocation> fromResults = [];
    for (final v in fromVariants) {
      fromResults = await _bahnLocationSearch(v);
      if (fromResults.isNotEmpty) {
        _log.debug('Transit: bahn.de resolved "$fromName" via variant "$v"', tag: 'TRANSIT');
        break;
      }
    }
    if (fromResults.isEmpty) {
      _log.info('Transit: bahn.de could not resolve fromName="$fromName" '
          '(tried ${fromVariants.length} variants)', tag: 'TRANSIT');
      return [];
    }
    List<TransitLocation> toResults = [];
    for (final v in toVariants) {
      toResults = await _bahnLocationSearch(v);
      if (toResults.isNotEmpty) {
        _log.debug('Transit: bahn.de resolved "$toName" via variant "$v"', tag: 'TRANSIT');
        break;
      }
    }
    if (toResults.isEmpty) {
      _log.info('Transit: bahn.de could not resolve toName="$toName" '
          '(tried ${toVariants.length} variants)', tag: 'TRANSIT');
      return [];
    }
    return _bahnTripSearch(
      fromResults.first, toResults.first, when,
      arriveBy: arriveBy,
      onlyDeutschlandTicket: onlyDeutschlandTicket,
    );
  }

  /// Generate de-duped list of query variants pentru bahn.de LocSearch.
  /// bahn.de acceptă formatare "Nume Hbf" dar respinge "Nume, Hauptbahnhof"
  /// și e sensibil la accente. Încercăm câteva forme comune.
  List<String> _bahnNameVariants(String raw) {
    final variants = <String>[];
    void add(String s) {
      final t = s.trim();
      if (t.isEmpty || variants.contains(t)) return;
      variants.add(t);
    }
    add(raw);
    // Idiom "Hauptbahnhof" → "Hbf".
    add(raw.replaceAll('Hauptbahnhof', 'Hbf').replaceAll('hauptbahnhof', 'Hbf'));
    // Strip virgulă și tot spațiu dublu.
    add(raw.replaceAll(',', ' ').replaceAll(RegExp(r'\s+'), ' '));
    // Combinație: virgulă + Hbf.
    add(raw.replaceAll(',', ' ').replaceAll('Hauptbahnhof', 'Hbf')
        .replaceAll(RegExp(r'\s+'), ' '));
    // Doar prima parte înainte de virgulă ("Saarbrücken, Rathaus" → "Saarbrücken").
    final commaIdx = raw.indexOf(',');
    if (commaIdx > 0) add(raw.substring(0, commaIdx));
    return variants;
  }

  // ── EFA trip/location endpoints ────────────────────────────────

  Future<List<TransitLocation>> _efaLocationSearch(TransitProviderConfig p, String q) async {
    // EFA circuit-breaker: skip dacă providerul e blacklist-uit
    // (endpoint mutat, întorc HTML în loc de JSON etc.).
    if (_isHafasBlacklisted(p.type)) return [];
    final uri = Uri.parse(
      '${p.baseUrl}/XSLT_STOPFINDER_REQUEST'
      '?outputFormat=JSON&locationServerActive=1&type_sf=any&anyObjFilter_sf=126'
      '&name_sf=${Uri.encodeComponent(q)}',
    );
    final response = await _client.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return [];
    final body = _decodeUtf8(response);
    // Sanity check — dacă EFA returnează HTML (endpoint mutat, redirect la
    // landing page), blacklist providerul ca să nu spamăm log + latency.
    final trim = body.trimLeft();
    if (trim.startsWith('<') || trim.toLowerCase().startsWith('<!doctype')) {
      _markHafasAuthFail(p, 'EFA returns HTML — endpoint moved/broken');
      return [];
    }
    final data = jsonDecode(body);
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
    // Skip immediately dacă providerul e blacklist-uit (evită request + log spam).
    if (_isHafasBlacklisted(p.type)) return [];
    final call = _buildSignedHafasCall(p, [
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
      Uri.parse(call.url),
      headers: {'Content-Type': 'application/json'},
      body: call.body,
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return [];
    final data = jsonDecode(_decodeUtf8(response));
    // HAFAS reports auth failures at root level, not in svcResL — check both
    final rootErr = data['err']?.toString();
    if (rootErr != null && rootErr != 'OK') {
      if (rootErr == 'AUTH') {
        _markHafasAuthFail(p, '${data['errTxt'] ?? rootErr}');
      } else {
        _log.error('Transit [${p.name}]: HAFAS root err=$rootErr '
            '${data['errTxt'] ?? ''}', tag: 'TRANSIT');
      }
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
    if (_isHafasBlacklisted(p.type)) return [];
    final dateStr = '${when.year}${when.month.toString().padLeft(2, '0')}${when.day.toString().padLeft(2, '0')}';
    final timeStr = '${when.hour.toString().padLeft(2, '0')}${when.minute.toString().padLeft(2, '0')}00';
    final call = _buildSignedHafasCall(p, [
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
      Uri.parse(call.url),
      headers: {'Content-Type': 'application/json'},
      body: call.body,
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) return [];
    final data = jsonDecode(_decodeUtf8(response));
    return _parseHafasTripResponse(data, providerHint: p);
  }

  List<Journey> _parseHafasTripResponse(Map<String, dynamic> data,
      {TransitProviderConfig? providerHint}) {
    final rootErr = data['err']?.toString();
    if (rootErr != null && rootErr != 'OK') {
      if (rootErr == 'AUTH' && providerHint != null) {
        _markHafasAuthFail(providerHint, '${data['errTxt'] ?? rootErr}');
      } else {
        _log.error('Transit: HAFAS trip root err=$rootErr '
            '${data['errTxt'] ?? ''}', tag: 'TRANSIT');
      }
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
              // Same catOut-preferred mapping as StationBoard parsing — fixes
              // saarVV mislabeling of Saarbahn as bus and RE/RB as S-Bahn.
              productType = _hafasProductType(prod);
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
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
    }).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return [];
    final data = jsonDecode(_decodeUtf8(response));
    if (data is! List) return [];
    return data.map<TransitLocation?>((e) {
      final name = e['name']?.toString() ?? '';
      final id = e['id']?.toString() ?? e['extId']?.toString() ?? '';
      if (name.isEmpty || id.isEmpty) return null;
      // Extract type from A=N prefix in id:
      //   A=1 = station/stop
      //   A=2 = address (street + number)
      //   A=4 = POI
      String? type = e['typ']?.toString();
      if (type == null || type.isEmpty) {
        if (id.startsWith('A=1@')) {
          type = 'stop';
        } else if (id.startsWith('A=2@')) {
          type = 'address';
        } else if (id.startsWith('A=4@')) {
          type = 'poi';
        }
      }
      return TransitLocation(
        id: id, name: name, type: type,
        lat: (e['lat'] as num?)?.toDouble(),
        lon: (e['lon'] as num?)?.toDouble(),
      );
    }).whereType<TransitLocation>().toList();
  }

  Future<List<Journey>> _bahnTripSearch(
    TransitLocation from, TransitLocation to, DateTime when,
    {bool arriveBy = false, bool onlyDeutschlandTicket = false}
  ) async {
    // 2026-07-11: MIGRATED from `bahn.de/web/api/reiseloesung/verbindungen`
    // (dbweb) to `app.services-bahn.de/mob/angebote/fahrplan` (dbnav) —
    // dbweb returned `verkehrsmittel.kurzText = "9557"` for ICE trains
    // (line number only, no "ICE" prefix), which broke the D-Ticket filter
    // (a line "9557" looks like a bus number). dbnav returns `mitteltext =
    // "ICE 617"` on every leg — proper HAFAS "product + line" label.
    //
    // Fallback: dacă dbnav fahrplan pică (rare, 400/500), încercăm dbweb.
    final direct = await _dbnavTripSearch(
      from, to, when,
      arriveBy: arriveBy,
      onlyDeutschlandTicket: onlyDeutschlandTicket,
    );
    if (direct.isNotEmpty) return direct;
    return _dbwebTripSearchLegacy(
      from, to, when,
      arriveBy: arriveBy,
      onlyDeutschlandTicket: onlyDeutschlandTicket,
    );
  }

  /// dbnav backend — `POST /mob/angebote/fahrplan` cu Content-Type
  /// `application/x.db.vendo.mob.verbindungssuche.v9+json`. Returnează
  /// `verbindungen[].verbindungsAbschnitte[].mitteltext` = "ICE 617"
  /// (prefix + line), care alimentează corect D-Ticket filter.
  Future<List<Journey>> _dbnavTripSearch(
    TransitLocation from, TransitLocation to, DateTime when,
    {bool arriveBy = false, bool onlyDeutschlandTicket = false}
  ) async {
    final uri = Uri.parse('$_dbNavBase/mob/angebote/fahrplan');
    // dbnav așteaptă ISO local FĂRĂ offset ("2026-07-11T08:00:00").
    String twoDigit(int n) => n.toString().padLeft(2, '0');
    final local = when.toLocal();
    final isoNoTz = '${local.year}-${twoDigit(local.month)}-${twoDigit(local.day)}'
        'T${twoDigit(local.hour)}:${twoDigit(local.minute)}:${twoDigit(local.second)}';

    // D-Ticket only → limit produs list la Nahverkehr. Numele dbnav diferă
    // de cele dbweb: enum "verkehrsmittel" (nu "produktgattungen").
    // https://github.com/public-transport/db-vendo-client/blob/main/p/dbnav/journeys-req.js
    final verkehrsmittel = onlyDeutschlandTicket
        ? const ['NAHVERKEHRSONSTIGEZUEGE','SBAHNEN','UBAHN','STRASSENBAHN','BUSSE','SCHIFFE','ANRUFPFLICHTIGEVERKEHRE']
        : const ['ALL'];

    final body = jsonEncode({
      'autonomeReservierung': false,
      'einstiegsTypList': ['STANDARD'],
      'klasse': 'KLASSE_2',
      'reisendenProfil': {
        'reisende': [{
          'typ': 'ERWACHSENER',
          'alter': [],
          'anzahl': 1,
          'ermaessigungen': [
            {'art': 'KEINE_ERMAESSIGUNG', 'klasse': 'KLASSENLOS'}
          ],
        }],
      },
      'reservierungsKontingenteVorhanden': false,
      'fahrverguenstigungen': [],
      'nurDeutschlandTicketVerbindungen': onlyDeutschlandTicket,
      'reiseHin': {
        'wunsch': {
          'abgangsLocationId': from.id,
          'zielLocationId': to.id,
          'zeitWunsch': {
            'reiseDatum': isoNoTz,
            'zeitPunktArt': arriveBy ? 'ANKUNFT' : 'ABFAHRT',
          },
          'verkehrsmittel': verkehrsmittel,
          'maxUmstiege': 3,
          'minUmstiegsdauer': 0,
        },
      },
    });

    try {
      final response = await _client.post(
        uri,
        headers: {
          'Content-Type': 'application/x.db.vendo.mob.verbindungssuche.v9+json',
          'Accept': 'application/x.db.vendo.mob.verbindungssuche.v9+json',
          'X-Correlation-ID': _dbNavCorrelationId(),
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
        },
        body: body,
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        _log.info('Transit: dbnav fahrplan HTTP ${response.statusCode}, '
            'falling back to dbweb', tag: 'TRANSIT');
        return [];
      }
      final data = jsonDecode(_decodeUtf8(response));
      final verb = (data['verbindungen'] as List?) ?? [];
      return verb
          .map<Journey?>(_parseDbnavConnection)
          .whereType<Journey>()
          .take(4)
          .toList();
    } catch (e) {
      _log.info('Transit: dbnav fahrplan error: $e', tag: 'TRANSIT');
      return [];
    }
  }

  /// Legacy dbweb parser — folosit ca fallback dacă dbnav pică. Bug-ul e
  /// că `kurzText` = "9557" (fără prefix ICE), dar cu `name` primim uneori
  /// "ICE 9557" — dacă chiar cade la dbweb măcar avem ceva.
  Future<List<Journey>> _dbwebTripSearchLegacy(
    TransitLocation from, TransitLocation to, DateTime when,
    {bool arriveBy = false, bool onlyDeutschlandTicket = false}
  ) async {
    final iso = when.toIso8601String();
    final uri = Uri.parse('https://www.bahn.de/web/api/reiseloesung/verbindungen');
    final produkte = onlyDeutschlandTicket
        ? const ['REGIONAL','SBAHN','BUS','SCHIFF','UBAHN','TRAM','ANRUFPFLICHTIG']
        : const ['ICE','EC_IC','IR','REGIONAL','SBAHN','BUS','SCHIFF','UBAHN','TRAM','ANRUFPFLICHTIG'];
    final body = jsonEncode({
      'abfahrtsHalt': from.id,
      'ankunftsHalt': to.id,
      'anfrageZeitpunkt': iso,
      'ankunftSuche': arriveBy ? 'ANKUNFT' : 'ABFAHRT',
      'klasse': 'KLASSE_2',
      'produktgattungen': produkte,
      'reisende': [{'typ':'ERWACHSENER','ermaessigungen':[{'art':'KEINE_ERMAESSIGUNG','klasse':'KLASSENLOS'}],'alter':[],'anzahl':1}],
      'schnelleVerbindungen': true,
      'sitzplatzOnly': false,
      'bikeCarriage': false,
      'reservierungsKontingenteVorhanden': false,
      'nurDeutschlandTicketVerbindungen': onlyDeutschlandTicket,
    });
    final response = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
            'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
      },
      body: body,
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) return [];
    final data = jsonDecode(_decodeUtf8(response));
    final verb = data['verbindungen'] as List? ?? [];
    return verb.map<Journey?>(_parseBahnConnection).whereType<Journey>().take(4).toList();
  }

  /// Parse un `verbindung` din răspunsul dbnav `/mob/angebote/fahrplan`.
  /// Cheia principală: `verbindungsAbschnitte[].mitteltext` = "ICE 617"
  /// (product + line number cu prefix — exact ce cere D-Ticket filter).
  Journey? _parseDbnavConnection(dynamic conn) {
    try {
      final segments = conn['verbindungsAbschnitte'] as List? ?? [];
      if (segments.isEmpty) return null;
      final legs = <JourneyLeg>[];
      for (final seg in segments) {
        final typ = seg['typ']?.toString().toUpperCase() ?? '';
        final isWalk = typ == 'FUSSWEG' || typ == 'WALK' || typ == 'TRANSFER';
        // dbnav timestamps: `abfahrtsZeitpunkt` sau `abgangsDatum`, ISO cu offset.
        final depIso = seg['abfahrtsZeitpunkt']?.toString()
            ?? seg['abgangsDatum']?.toString();
        final arrIso = seg['ankunftsZeitpunkt']?.toString()
            ?? seg['ankunftsDatum']?.toString();
        if (depIso == null || arrIso == null) continue;
        final depDT = DateTime.tryParse(depIso)?.toLocal();
        final arrDT = DateTime.tryParse(arrIso)?.toLocal();
        if (depDT == null || arrDT == null) continue;

        // mitteltext = "ICE 617" / "RB 82" / "S 3" — canonical HAFAS label.
        // kurztext = "ICE" / "RB" / "S" (product only)
        // langtext = "ICE 617 (12345)" (adaugă numărul de tren)
        final mitteltext = seg['mitteltext']?.toString().trim();
        final kurztext = seg['kurztext']?.toString().trim();
        final line = isWalk
            ? 'Fußweg'
            : (mitteltext?.isNotEmpty == true
                ? mitteltext!
                : (kurztext?.isNotEmpty == true ? kurztext! : '?'));

        // Product mapping via kurztext (product code) — mai fiabil decât enum.
        final k = (kurztext ?? '').toUpperCase();
        String productType;
        if (isWalk) {
          productType = 'walk';
        } else if (k == 'ICE' || k == 'ECE') {
          productType = 'train';
        } else if (k == 'IC' || k == 'EC' || k == 'IR' || k == 'FLX'
            || k == 'RJ' || k == 'RJX' || k == 'NJ' || k == 'EN' || k == 'TGV') {
          productType = 'train';
        } else if (k == 'RE' || k == 'RB' || k == 'IRE' || k == 'MEX'
            || k == 'RS' || k == 'RJ' || k.startsWith('R')) {
          productType = 'regional';
        } else if (k == 'S' || k.startsWith('S')) {
          productType = 'suburban';
        } else if (k == 'U' || k.startsWith('U')) {
          productType = 'subway';
        } else if (k == 'STR' || k == 'TRAM' || k == 'M') {
          productType = 'tram';
        } else if (k == 'BUS' || k == 'SEV' || k == 'EV') {
          productType = 'bus';
        } else if (k == 'FÄHRE' || k == 'FAEHRE' || k == 'F') {
          productType = 'ferry';
        } else {
          productType = 'bus';
        }

        legs.add(JourneyLeg(
          line: line,
          direction: seg['richtung']?.toString()
              ?? seg['verkehrsmittel']?['richtung']?.toString()
              ?? '',
          fromName: seg['abgangsOrt']?['name']?.toString()
              ?? seg['abfahrtsOrt']?.toString()
              ?? '',
          toName: seg['ankunftsOrt']?['name']?.toString()
              ?? seg['ankunftsOrt']?.toString()
              ?? '',
          depTime: depDT,
          arrTime: arrDT,
          fromPlatform: seg['abgangsGleis']?.toString()
              ?? seg['abfahrtsGleis']?.toString(),
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

  Journey? _parseBahnConnection(dynamic conn) {
    try {
      final segments = conn['verbindungsAbschnitte'] as List? ?? [];
      if (segments.isEmpty) return null;
      final legs = <JourneyLeg>[];
      for (final seg in segments) {
        final vk = seg['verkehrsmittel'] as Map?;
        // 2026-07-11 FIX: `typ` e in verkehrsmittel, NU la top-level.
        // WALK legs: vk.typ='WALK', vk.name='Fußweg', fara produktGattung.
        // PT legs:   vk.typ='PUBLICTRANSPORT', vk.produktGattung='TRAM' etc.
        final vkTyp = vk?['typ']?.toString() ?? '';
        final isWalk = vkTyp == 'WALK' || vkTyp == 'FUSSWEG'
            || (vk?['name']?.toString() == 'Fußweg');
        final depIso = seg['abfahrtsZeitpunkt']?.toString();
        final arrIso = seg['ankunftsZeitpunkt']?.toString();
        if (depIso == null || arrIso == null) continue;
        final depDT = DateTime.tryParse(depIso);
        final arrDT = DateTime.tryParse(arrIso);
        if (depDT == null || arrDT == null) continue;

        final gattung = vk?['produktGattung']?.toString() ?? '';
        String productType;
        if (isWalk) {
          productType = 'walk';
        } else {
          switch (gattung) {
            case 'ICE': case 'EC_IC': case 'IR': productType = 'train'; break;
            case 'REGIONAL': productType = 'regional'; break;
            case 'SBAHN': productType = 'suburban'; break;
            case 'UBAHN': productType = 'subway'; break;
            case 'TRAM': productType = 'tram'; break;
            case 'SCHIFF': productType = 'ferry'; break;
            default: productType = 'bus';
          }
        }

        // 2026-07-11 FIX: bahn.de returneaza `name = "4140"` (numar tren) si
        // `kurzText = "RE"` (product only). `langText = "RE1 (4140)"` are
        // line-ul CORECT (RE1, RB70, ICE 619 etc.). Preluam din langText fara
        // sufix `(4140)`. Fallback pe name + kurzText combo daca langText gol.
        String extractLine() {
          if (isWalk) return 'Fußweg';
          final vk = seg['verkehrsmittel'];
          if (vk is! Map) return '?';
          final langText = vk['langText']?.toString().trim() ?? '';
          if (langText.isNotEmpty) {
            // "RE1 (4140)" → "RE1", "ICE 619 (12345)" → "ICE 619"
            final parenIdx = langText.indexOf(' (');
            return parenIdx > 0 ? langText.substring(0, parenIdx) : langText;
          }
          final mittelText = vk['mittelText']?.toString().trim() ?? '';
          if (mittelText.isNotEmpty) return mittelText;
          // Combine kurzText + name daca name e doar cifre: "RE" + "4140" = "RE 4140"
          final kurz = vk['kurzText']?.toString().trim() ?? '';
          final nm = vk['name']?.toString().trim() ?? '';
          if (kurz.isNotEmpty && nm.isNotEmpty && RegExp(r'^\d+$').hasMatch(nm)) {
            return '$kurz $nm';
          }
          return nm.isNotEmpty ? nm : (kurz.isNotEmpty ? kurz : '?');
        }

        legs.add(JourneyLeg(
          line: extractLine(),
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
