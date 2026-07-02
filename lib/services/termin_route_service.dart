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

    // 2. Resolve both addresses to transit locations.
    // Verein adresse is multi-line in DB (Vereinsname / c-o / Straße / PLZ Ort);
    // we try multiple query variants until one returns a hit.
    _log.info('TerminRoute: verein raw=${_shortForLog(vereinAdresse)}', tag: 'TERMIN_ROUTE');
    _log.info('TerminRoute: termin.location="${termin.location}"', tag: 'TERMIN_ROUTE');
    final vereinCandidates = _addressCandidates(vereinAdresse);
    _log.info('TerminRoute: verein candidates=$vereinCandidates', tag: 'TERMIN_ROUTE');

    // Same multi-candidate strategy for termin.location — user may enter
    // "Jobcenter Ulm" (nume+oras), "Adenauerplatz 15" (str+nr), or full address.
    final terminCandidates = _addressCandidates(termin.location);
    _log.info('TerminRoute: termin candidates=$terminCandidates', tag: 'TERMIN_ROUTE');

    final List<TransitLocation> fromResults;
    final List<TransitLocation> toResults;
    try {
      final both = await Future.wait([
        _resolveFirstNonEmpty(vereinCandidates),
        _resolveFirstNonEmpty(terminCandidates),
      ]);
      fromResults = both[0];
      toResults = both[1];
    } catch (e) {
      _log.error('TerminRoute: address resolution failed: $e', tag: 'TERMIN_ROUTE');
      return TerminRouteResult.error(TerminRouteError.resolutionFailed);
    }
    _log.info('TerminRoute: from=${fromResults.length} results, to=${toResults.length} results', tag: 'TERMIN_ROUTE');
    final results = [fromResults, toResults];

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

  /// Returns candidate query strings for a raw address, ordered from most
  /// specific to most general. `searchLocations` gets tried on each until one
  /// returns results.
  ///
  /// Handles multiple input shapes:
  ///   • Multi-line Verein-Adresse: "ICD360S e.V.\nc/o Ionut\nElsa-Brandstrom-str. 13\n89231 Neu-Ulm"
  ///   • Single-line address: "Adenauerplatz 15, 89073 Ulm"
  ///   • Just Behörde name: "Jobcenter Ulm"
  ///   • Comma / semicolon / <br> separated
  List<String> _addressCandidates(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return [];
    // Normalize separators — treat <br>, ;, newlines the same way
    final normalized = t
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(';', '\n');
    final lines = normalized
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    // Filter out lines that are clearly non-address:
    //  - "c/o …" forwarding
    //  - lines with a legal-form suffix (e.V., GmbH, AG) as sole content
    final cleanLines = lines.where((l) {
      if (RegExp(r'^c[/ ]?o[\.\s]', caseSensitive: false).hasMatch(l)) return false;
      // Vereinsname / company name: contains "e.V." or "GmbH" and no digit
      if (RegExp(r'(e\.?\s?v\.?|gmbh|ag\b|kg\b|ohg)', caseSensitive: false).hasMatch(l) &&
          !RegExp(r'\d').hasMatch(l)) {
        return false;
      }
      return true;
    }).toList();

    final candidates = <String>[];

    // 1. If we have street+city format (2+ lines), join them.
    if (cleanLines.length >= 2) {
      candidates.add('${cleanLines[cleanLines.length - 2]}, ${cleanLines.last}');
    }

    // 2. Original raw text — EFA sometimes handles multi-line surprisingly well.
    if (!candidates.contains(t)) candidates.add(t);

    // 3. Last line only (typically PLZ + Ort)
    if (cleanLines.isNotEmpty && !candidates.contains(cleanLines.last)) {
      candidates.add(cleanLines.last);
    }

    // 4. Line with a house number (contains digit) — usually the street line
    for (final line in cleanLines) {
      if (RegExp(r'\d').hasMatch(line) && !candidates.contains(line)) {
        candidates.add(line);
        break;
      }
    }

    // 5. Extract city from PLZ line: "89231 Neu-Ulm" → "Neu-Ulm"
    final plzMatch = RegExp(r'\b(\d{5})\s+(.+)$').firstMatch(cleanLines.isEmpty ? '' : cleanLines.last);
    if (plzMatch != null) {
      final city = plzMatch.group(2)!.trim();
      if (!candidates.contains(city)) candidates.add(city);
    }

    return candidates;
  }

  /// Truncate a possibly-multiline string for log output.
  String _shortForLog(String s) {
    final oneLine = s.replaceAll(RegExp(r'\r?\n'), ' | ');
    return oneLine.length > 80 ? '${oneLine.substring(0, 80)}…' : oneLine;
  }

  /// Try each candidate address until one returns non-empty results.
  /// Results are re-ranked so entries whose name matches query keywords rise
  /// to the top — the raw autocomplete order is often globally alphabetical,
  /// so "Adenauerplatz 15, 89073 Ulm" would otherwise return Berlin's
  /// Adenauerplatz as top hit.
  Future<List<TransitLocation>> _resolveFirstNonEmpty(List<String> candidates) async {
    for (final q in candidates) {
      _log.info('TerminRoute: trying candidate="$q"', tag: 'TERMIN_ROUTE');
      final r = await _transitService.searchLocations(q);
      if (r.isNotEmpty) {
        final ranked = _rankByQueryMatch(r, q);
        _log.info(
          'TerminRoute: candidate="$q" → ${r.length} raw, top after rank="${ranked.first.name}" (${ranked.first.type})',
          tag: 'TERMIN_ROUTE',
        );
        return ranked;
      }
    }
    _log.info('TerminRoute: all ${candidates.length} candidates returned empty', tag: 'TERMIN_ROUTE');
    return [];
  }

  /// Score-sort results by how well their name matches the query.
  /// A query "Adenauerplatz 15, 89073 Ulm" boosts entries whose name contains
  /// "adenauerplatz" AND "ulm" — so Ulm's beats Berlin's.
  List<TransitLocation> _rankByQueryMatch(List<TransitLocation> results, String query) {
    final words = query
        .toLowerCase()
        .split(RegExp(r'[\s,;/\.]+'))
        .where((w) => w.length >= 3 && !RegExp(r'^\d{1,2}$').hasMatch(w))
        .toList();
    // PLZ digits (5) get their own strong weight
    final plz = RegExp(r'\b(\d{5})\b').firstMatch(query)?.group(1);

    int score(TransitLocation l) {
      final name = l.name.toLowerCase();
      int s = 0;
      for (final w in words) {
        if (name.contains(w)) s += 20;
      }
      if (plz != null && name.contains(plz)) s += 30;
      // Type preferences
      switch (l.type) {
        case 'stop': s += 12; break;
        case 'singlehouse': s += 10; break;
        case 'poi': s += 5; break;
        case 'street': s += 3; break;
      }
      return s;
    }

    final sorted = List<TransitLocation>.from(results);
    sorted.sort((a, b) => score(b).compareTo(score(a)));
    return sorted;
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
