import 'dart:async';
import 'api_service.dart';
import 'transit_service.dart';
import 'termin_service.dart';
import 'logger_service.dart';

final _log = LoggerService();

/// Result of a Termin → route calculation.
class TerminRoute {
  final Journey primary;
  final List<Journey> alternatives;
  final TransitLocation from;
  final TransitLocation to;
  final DateTime targetArrival;
  final int bufferMinutes;

  TerminRoute({
    required this.primary,
    required this.alternatives,
    required this.from,
    required this.to,
    required this.targetArrival,
    required this.bufferMinutes,
  });

  /// All journeys (primary + alternatives) sorted by departure time.
  List<Journey> get all => [primary, ...alternatives];

  /// How many minutes before termin the user arrives (positive = early).
  int minutesBeforeTermin(DateTime terminDate) =>
      terminDate.difference(primary.arrTime).inMinutes;
}

/// Orchestrates route calculation for a Termin:
///   Verein-Adresse → Behörde/Praxis-Adresse from termin.location
///
/// The service auto-resolves both addresses to nearest stops via the transit
/// backends (EFA/HAFAS/bahn.de) and runs an arrive-by search targeting
/// `terminDate − bufferMinutes` (default 15 min buffer).
class TerminRouteService {
  final ApiService _apiService;
  final TransitService _transitService;

  TerminRouteService(this._apiService, this._transitService);

  /// In-memory cache for Verein address (5 min TTL). Rarely changes; avoids
  /// hitting `getVereineinstellungen` on every termin card expansion.
  String? _cachedVereinAdresse;
  DateTime? _cachedAt;
  static const _cacheTtl = Duration(minutes: 5);

  /// Fetch Verein address (cached) or return null if unavailable / empty.
  Future<String?> _getVereinAdresse() async {
    if (_cachedVereinAdresse != null &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < _cacheTtl) {
      return _cachedVereinAdresse;
    }
    try {
      final result = await _apiService.getVereineinstellungen();
      if (result['success'] == true && result['data'] != null) {
        final adresse = (result['data']['adresse'] ?? '').toString().trim();
        if (adresse.isNotEmpty) {
          _cachedVereinAdresse = adresse;
          _cachedAt = DateTime.now();
          return adresse;
        }
      }
    } catch (e) {
      _log.error('TerminRoute: getVereineinstellungen failed: $e', tag: 'TERMIN_ROUTE');
    }
    return null;
  }

  /// Calculate the ÖPNV route Verein → termin.location.
  /// Returns null if any step fails (missing Verein adresse, unresolvable
  /// termin.location, no journeys found).
  ///
  /// [bufferMinutes] — arrive this many minutes before termin start
  /// (default 15). Used to compute the arrive-by time passed to the backends.
  Future<TerminRouteResult> calculateRoute(
    Termin termin, {
    int bufferMinutes = 15,
  }) async {
    // 1. Verein address
    final vereinAdresse = await _getVereinAdresse();
    if (vereinAdresse == null) {
      return TerminRouteResult.error(TerminRouteError.vereinAdresseMissing);
    }
    if (termin.location.trim().isEmpty) {
      return TerminRouteResult.error(TerminRouteError.terminLocationMissing);
    }

    // 2. Resolve both addresses to transit locations in parallel.
    // Verein adresse is multi-line in DB (Vereinsname / c-o / Straße / PLZ Ort);
    // we strip lines that would confuse the geocoder.
    final cleanVerein = _cleanAddress(vereinAdresse);
    final List<List<TransitLocation>> results;
    try {
      results = await Future.wait([
        _transitService.searchLocations(cleanVerein),
        _transitService.searchLocations(termin.location),
      ]);
    } catch (e) {
      _log.error('TerminRoute: address resolution failed: $e', tag: 'TERMIN_ROUTE');
      return TerminRouteResult.error(TerminRouteError.resolutionFailed);
    }

    if (results[0].isEmpty) {
      return TerminRouteResult.error(TerminRouteError.vereinAdresseUnresolvable);
    }
    if (results[1].isEmpty) {
      return TerminRouteResult.error(TerminRouteError.terminLocationUnresolvable);
    }

    final from = results[0].first;
    final to = results[1].first;

    // 3. Search journeys with arrive-by = terminDate − buffer.
    final targetArrival = termin.terminDate.subtract(Duration(minutes: bufferMinutes));
    List<Journey> journeys;
    try {
      journeys = await _transitService.searchJourneys(
        from: from,
        to: to,
        arrivalTime: targetArrival,
      );
    } catch (e) {
      _log.error('TerminRoute: searchJourneys failed: $e', tag: 'TERMIN_ROUTE');
      return TerminRouteResult.error(TerminRouteError.searchFailed);
    }

    if (journeys.isEmpty) {
      return TerminRouteResult.error(TerminRouteError.noJourneysFound);
    }

    return TerminRouteResult.success(TerminRoute(
      primary: journeys.first,
      alternatives: journeys.skip(1).toList(),
      from: from,
      to: to,
      targetArrival: targetArrival,
      bufferMinutes: bufferMinutes,
    ));
  }

  /// Force-invalidate the Verein address cache (e.g. after admin updates).
  void invalidateCache() {
    _cachedVereinAdresse = null;
    _cachedAt = null;
  }

  /// Clean a multi-line German address for geocoder consumption.
  ///
  /// The `vereineinstellungen.adresse` field is stored as a formatted block:
  ///   ICD360S e.V.
  ///   c/o Ionut-Claudiu Duinea
  ///   Elsa-Brandstrom-str. 13
  ///   89231 Neu-Ulm
  ///
  /// EFA/HAFAS geocoders expect a single line "Straße + Nr, PLZ Ort".
  /// We drop the Vereinsname and "c/o …" lines and rejoin the rest.
  String _cleanAddress(String raw) {
    final lines = raw
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .where((l) => !RegExp(r'^c[/ ]?o[\.\s]', caseSensitive: false).hasMatch(l))
        .toList();
    if (lines.isEmpty) return raw.trim();
    // Prefer the last two lines (street + PLZ Ort). If only one line contains
    // a number (street with house number), keep only lines that look like
    // address components (contain digits or look like a postal-city line).
    if (lines.length >= 2) {
      return '${lines[lines.length - 2]}, ${lines.last}';
    }
    return lines.first;
  }
}

/// Discrete error states for route calculation — used to render actionable UI.
enum TerminRouteError {
  /// Verein-Adresse leer / nicht konfiguriert
  vereinAdresseMissing,
  /// termin.location leer
  terminLocationMissing,
  /// Vereins-Adresse kann nicht in eine Haltestelle aufgelöst werden
  vereinAdresseUnresolvable,
  /// termin.location kann nicht aufgelöst werden (z.B. "Praxis Dr. Müller" ohne Straße)
  terminLocationUnresolvable,
  /// Netzwerk/API-Fehler bei Adressauflösung
  resolutionFailed,
  /// Netzwerk/API-Fehler bei Verbindungssuche
  searchFailed,
  /// Kein Weg gefunden (zu weit? falscher Tag?)
  noJourneysFound,
}

/// Discriminated union — either a route or an error.
class TerminRouteResult {
  final TerminRoute? route;
  final TerminRouteError? error;

  const TerminRouteResult._({this.route, this.error});
  factory TerminRouteResult.success(TerminRoute route) => TerminRouteResult._(route: route);
  factory TerminRouteResult.error(TerminRouteError err) => TerminRouteResult._(error: err);

  bool get isSuccess => route != null;

  String get germanMessage {
    switch (error) {
      case TerminRouteError.vereinAdresseMissing:
        return 'Vereins-Adresse nicht in den Einstellungen konfiguriert.';
      case TerminRouteError.terminLocationMissing:
        return 'Keine Adresse für den Termin angegeben.';
      case TerminRouteError.vereinAdresseUnresolvable:
        return 'Vereins-Adresse konnte nicht in eine Haltestelle umgewandelt werden.';
      case TerminRouteError.terminLocationUnresolvable:
        return 'Adresse des Termins konnte nicht gefunden werden. Manuell in ÖPNV suchen.';
      case TerminRouteError.resolutionFailed:
      case TerminRouteError.searchFailed:
        return 'Netzwerkfehler bei der Routenberechnung. Bitte erneut versuchen.';
      case TerminRouteError.noJourneysFound:
        return 'Keine ÖPNV-Verbindung gefunden. Möglicherweise zu weit oder außerhalb der Fahrzeiten.';
      case null:
        return '';
    }
  }
}
