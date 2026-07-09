import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
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
    baseUrl: 'https://vmt.hafas.de/bin/ticketing/mgate.exe',
    hafasAid: 't2h7u1e6r4i8n3g7e0n',
    hafasClientId: 'HAFAS', hafasClientVersion: '2040100', hafasClientName: 'VMT',
    hafasClientType: 'IPH', hafasVer: '1.18',
    minLat: 50.37, maxLat: 51.12, minLon: 10.16, maxLon: 12.17,
  ),
  TransitProviderConfig(
    type: TransitProviderType.vvw, api: TransitApiType.hafas,
    name: 'VVW', displayName: 'VVW / RSAG (Verkehrsverbund Warnow)',
    baseUrl: 'https://fahrplan.rsag-online.de/bin/mgate.exe',
    hafasAid: 'tF5JTs25rzUhGrrl',
    hafasClientId: 'RSAG', hafasClientName: 'webapp',
    hafasClientType: 'WEB', hafasVer: '1.24', hafasExt: 'VBN.2',
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
  /// "Ulm Hbf", "München Hauptbahnhof", "Bahnhof Neu-Ulm".
  /// Negatives (bus stops): "Klinikum am Bahnhof", "Am Bahnhof 12", "Bahnhofstraße".
  static final RegExp _stationRe = RegExp(
    r'(^|\s)(hbf|hauptbahnhof)(\s|$)|^bahnhof\s+\S',
    caseSensitive: false,
  );
  bool _isMainlineStation(TransitStop s) {
    final n = s.name.toLowerCase();
    // "bahnhofstraße"/"bahnhofsplatz" etc. must not match.
    if (n.contains('bahnhofstr') || n.contains('bahnhofspl')) return false;
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

  Map<String, dynamic> _hafasRequest(List<Map<String, dynamic>> svcReqL) {
    final p = activeProvider;
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
    } else if (p?.hafasClientVersion != null) {
      final intVer = int.tryParse(p!.hafasClientVersion);
      client['v'] = intVer ?? p.hafasClientVersion;
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
  Future<TripRoute> fetchTripRoute(Departure dep) async {
    final empty = TripRoute(stops: const [], path: const []);
    final fromId = dep.stopID;
    final toId = dep.destID;
    if (fromId == null || fromId.isEmpty || toId == null || toId.isEmpty) {
      _log.info('Transit: fetchTripRoute skipped — missing stopID/destID', tag: 'TRANSIT');
      return empty;
    }
    final cacheKey = '$fromId|$toId|${dep.line}|${dep.plannedTime.toIso8601String()}';
    final cached = _tripStopsCache[cacheKey];
    if (cached != null && DateTime.now().difference(cached.at) < const Duration(seconds: 60)) {
      return TripRoute(stops: cached.stops, path: cached.path);
    }

    final provider = activeProvider;
    if (provider == null) return empty;
    TripRoute route = empty;
    try {
      if (provider.api == TransitApiType.efa) {
        route = await _efaTripRoute(provider, dep);
      } else {
        route = await _hafasTripRoute(provider, dep);
      }
    } catch (e) {
      _log.error('Transit: fetchTripRoute failed for line ${dep.line}: $e', tag: 'TRANSIT');
    }
    _tripStopsCache[cacheKey] = _CachedTripStops(route.stops, DateTime.now(), path: route.path);
    _log.info('Transit: fetchTripRoute line ${dep.line} → ${route.stops.length} stops, ${route.path.length} path points', tag: 'TRANSIT');
    return route;
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

  Future<TripRoute> _hafasTripRoute(TransitProviderConfig p, Departure dep) async {
    final when = dep.realtimeTime ?? dep.plannedTime;
    final dateStr = '${when.year}${when.month.toString().padLeft(2, '0')}${when.day.toString().padLeft(2, '0')}';
    final timeStr = '${when.hour.toString().padLeft(2, '0')}${when.minute.toString().padLeft(2, '0')}00';
    final req = _hafasRequest([
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
    final resp = await _client.post(Uri.parse(p.baseUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(req)).timeout(const Duration(seconds: 12));
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
        results = await _bahnTripSearchByName(
          from.name, to.name, when,
          arriveBy: arriveBy,
          onlyDeutschlandTicket: onlyDeutschlandTicket,
        );
      } catch (e) {
        _log.error('Transit: bahn.de trip search failed: $e', tag: 'TRANSIT');
      }
    }

    // Client-side D-Ticket filter for local provider results (EFA/HAFAS
    // don't support the flag server-side). Some EFA services return REs
    // that cross tariff zones without D-Ticket coverage, and many HAFAS
    // regional endpoints happily surface IC/EC. Filter journeys whose
    // legs include known non-D-Ticket product categories.
    if (onlyDeutschlandTicket && results.isNotEmpty) {
      final before = results.length;
      results = results.where(_isDeutschlandTicketOnly).toList();
      _log.info('Transit: D-Ticket filter kept ${results.length}/$before journeys', tag: 'TRANSIT');
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

  /// Journey qualifies for the 49€ Deutschlandticket iff none of its
  /// vehicle legs is a long-distance product. Walking legs are always OK.
  ///
  /// Non-D-Ticket products: ICE, IC, EC, IR, TGV, RJ, ECE, NJ (Nightjet),
  /// TER, plus generic 'long_distance'. Product-type strings vary between
  /// EFA and HAFAS so we check both the `productType` field and the `line`
  /// prefix (case-insensitive).
  static final RegExp _nonDTicketLineRe = RegExp(
    r'^(ice|ic|ec|ir|tgv|rj|ecx|ece|nj|en|thalys|flixt|flx)\b',
    caseSensitive: false,
  );
  bool _isDeutschlandTicketOnly(Journey j) {
    for (final leg in j.legs) {
      if (leg.isWalk) continue;
      final pt = leg.productType.toLowerCase();
      if (pt == 'long_distance' || pt == 'nationalexpress' || pt == 'national' ||
          pt == 'ice' || pt == 'ic' || pt == 'ec' || pt == 'ir') {
        return false;
      }
      if (_nonDTicketLineRe.hasMatch(leg.line.trim())) return false;
    }
    return true;
  }

  /// bahn.de journey search that resolves location names to bahn.de IDs first.
  Future<List<Journey>> _bahnTripSearchByName(
    String fromName, String toName, DateTime when,
    {bool arriveBy = false, bool onlyDeutschlandTicket = false}
  ) async {
    final results = await Future.wait([
      _bahnLocationSearch(fromName),
      _bahnLocationSearch(toName),
    ]);
    if (results[0].isEmpty || results[1].isEmpty) return [];
    return _bahnTripSearch(
      results[0].first, results[1].first, when,
      arriveBy: arriveBy,
      onlyDeutschlandTicket: onlyDeutschlandTicket,
    );
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

  Future<List<Journey>> _bahnTripSearch(
    TransitLocation from, TransitLocation to, DateTime when,
    {bool arriveBy = false, bool onlyDeutschlandTicket = false}
  ) async {
    final iso = when.toIso8601String();
    final uri = Uri.parse('https://www.bahn.de/web/api/reiseloesung/verbindungen');
    // When onlyDeutschlandTicket is on, ICE/EC/IC/IR are stripped from the
    // product list AND the D-Ticket-only flag is set — bahn.de then only
    // returns Nahverkehr (Regional, S-Bahn, Bus, U-Bahn, Tram, Fähre).
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
