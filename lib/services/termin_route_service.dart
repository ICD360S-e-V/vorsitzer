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

    // Filter out journeys that have already departed. EFA/HAFAS arrive-by
    // search returns multiple options — some may be trains/buses that already
    // left. Tolerance of 1 minute (imminent departures still shown).
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(minutes: 1));
    final futureJourneys = journeys.where((j) => j.depTime.isAfter(cutoff)).toList();
    _log.info(
      'TerminRoute: ${journeys.length} raw → ${futureJourneys.length} future (now=${now.hour}:${now.minute.toString().padLeft(2, "0")})',
      tag: 'TERMIN_ROUTE',
    );
    if (futureJourneys.isEmpty) {
      return TerminRouteResult.error(TerminRouteError.tooLate);
    }
    final selected = futureJourneys;

    return TerminRouteResult.success(TerminRoute(
      primary: selected.first,
      alternatives: selected.skip(1).toList(),
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
  /// Results are re-ranked with a strict city filter so entries far from
  /// the queried city (like "Jobcenter Tirschenreuth" for a "Jobcenter Ulm"
  /// query) never win, even when EFA has no proper match locally.
  ///
  /// If ranking drops all results because no entry mentions the queried city,
  /// we fall back to a city-only search — targeting the city centre so the
  /// user at least gets a plausible arrival station (city Hbf / centre) rather
  /// than a same-name POI 300 km away.
  Future<List<TransitLocation>> _resolveFirstNonEmpty(List<String> candidates) async {
    for (final q in candidates) {
      _log.info('TerminRoute: trying candidate="$q"', tag: 'TERMIN_ROUTE');
      final r = await _transitService.searchLocations(q);
      if (r.isEmpty) continue;

      final cityHint = _extractCityHint(q);
      final ranked = _rankByQueryMatch(r, q);

      // If the strict city filter should have applied but nothing survived,
      // fall back to searching for the city's Hauptbahnhof — that resolves
      // to a real, well-known stop instead of a same-name POI elsewhere.
      if (cityHint != null && cityHint.length >= 3) {
        final anyMatchesCity = ranked.any((l) => l.name.toLowerCase().contains(cityHint));
        if (!anyMatchesCity) {
          for (final variant in ['$cityHint Hbf', '$cityHint Hauptbahnhof', '$cityHint Bahnhof']) {
            _log.info('TerminRoute: no city match — trying "$variant"', tag: 'TERMIN_ROUTE');
            final r = await _transitService.searchLocations(variant);
            // Keep only results that actually contain the target city
            final cityStops = r.where((l) => l.name.toLowerCase().contains(cityHint)).toList();
            if (cityStops.isNotEmpty) {
              _log.info('TerminRoute: fallback "$variant" → top="${cityStops.first.name}"', tag: 'TERMIN_ROUTE');
              return cityStops;
            }
          }
        }
      }

      _log.info(
        'TerminRoute: candidate="$q" → ${r.length} raw, top after rank="${ranked.first.name}" (${ranked.first.type})',
        tag: 'TERMIN_ROUTE',
      );
      return ranked;
    }
    _log.info('TerminRoute: all ${candidates.length} candidates returned empty', tag: 'TERMIN_ROUTE');
    return [];
  }

  /// Extract the target city name from a query. Mirrors the logic in
  /// [_rankByQueryMatch] so filter + fallback stay consistent.
  String? _extractCityHint(String query) {
    final plzCity = RegExp(r'\b\d{5}\s+([A-Za-zÄÖÜäöüß][\w\-]+)').firstMatch(query);
    if (plzCity != null) return plzCity.group(1)!.toLowerCase();
    if (query.contains(',')) {
      final tail = query.split(',').last.trim();
      return tail.replaceAll(RegExp(r'^\d{5}\s*'), '').toLowerCase();
    }
    final tokens = query.split(RegExp(r'\s+')).where((t) => t.length >= 3).toList();
    if (tokens.length >= 2) {
      final last = tokens.last;
      if (RegExp(r'^[A-ZÄÖÜ]').hasMatch(last)) return last.toLowerCase();
    }
    return null;
  }

  /// Score-sort results by how well their name matches the query.
  /// Two-pass:
  ///   1. STRICT filter — if a city hint (from PLZ+city or last capitalized
  ///      word) is present, drop results whose name doesn't contain it.
  ///      This kills the classic "Jobcenter Ulm" → Tirschenreuth trap
  ///      (a Jobcenter in Bavaria, 300km away).
  ///   2. Rank remaining results by keyword + PLZ + type matches.
  /// Falls back to unfiltered when strict filter empties (e.g. rural queries).
  List<TransitLocation> _rankByQueryMatch(List<TransitLocation> results, String query) {
    final lower = query.toLowerCase();
    final words = lower
        .split(RegExp(r'[\s,;/\.]+'))
        .where((w) => w.length >= 3 && !RegExp(r'^\d{1,2}$').hasMatch(w))
        .toList();
    final plz = RegExp(r'\b(\d{5})\b').firstMatch(query)?.group(1);

    // Extract "city hint" — the town whose transit network should be searched.
    // Preference order:
    //   1. After a PLZ:                "Neue Straße 100, 89073 Ulm" → "ulm"
    //   2. After the last comma:       "Praxis Meyer, Neu-Ulm"      → "neu-ulm"
    //   3. Last capitalized word ≥3ch: "Jobcenter Ulm"              → "ulm"
    String? cityHint;
    final plzCity = RegExp(r'\b\d{5}\s+([A-Za-zÄÖÜäöüß][\w\-]+)').firstMatch(query);
    if (plzCity != null) {
      cityHint = plzCity.group(1)!.toLowerCase();
    } else if (query.contains(',')) {
      cityHint = query.split(',').last.trim().toLowerCase();
      // Drop any trailing PLZ if present
      cityHint = cityHint.replaceAll(RegExp(r'^\d{5}\s*'), '');
    } else {
      // Fallback: last capitalized ≥3 chars word
      final tokens = query.split(RegExp(r'\s+')).where((t) => t.length >= 3).toList();
      if (tokens.length >= 2) {
        final last = tokens.last;
        if (RegExp(r'^[A-ZÄÖÜ]').hasMatch(last)) {
          cityHint = last.toLowerCase();
        }
      }
    }

    // STRICT city-based filter
    List<TransitLocation> base = results;
    if (cityHint != null && cityHint.length >= 3) {
      final hint = cityHint;
      final filtered = results.where((r) {
        final name = r.name.toLowerCase();
        return name.contains(hint);
      }).toList();
      if (filtered.isNotEmpty) {
        base = filtered;
      } else {
        // No hit for city — probably a Behörde name unknown to EFA. Keep going
        // with all results but log so we can diagnose why nothing matched.
        // No log helper visible here; the caller already logs the candidate.
      }
    }

    int score(TransitLocation l) {
      final name = l.name.toLowerCase();
      int s = 0;
      for (final w in words) {
        if (name.contains(w)) s += 20;
      }
      if (plz != null && name.contains(plz)) s += 30;
      if (cityHint != null && name.contains(cityHint)) s += 50; // strong city boost
      switch (l.type) {
        case 'stop': s += 12; break;
        case 'singlehouse': s += 10; break;
        case 'poi': s += 5; break;
        case 'street': s += 3; break;
      }
      return s;
    }

    final sorted = List<TransitLocation>.from(base);
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
  /// Alle passenden Verbindungen sind bereits abgefahren
  tooLate,
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
      case TerminRouteError.tooLate:
        return 'Alle Verbindungen sind bereits abgefahren. Termin liegt zu nah — jetzt aufbrechen und rennen!';
      case null:
        return '';
    }
  }
}
