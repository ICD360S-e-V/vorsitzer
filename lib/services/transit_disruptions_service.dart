import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'http_client_factory.dart';
import 'logger_service.dart';

/// Active disruption fetched from a public transit feed.
class TransitDisruption {
  final String id;
  final String headline;
  final String? text;
  final DateTime? validFrom;
  final DateTime? validUntil;
  /// "HIGH" / "MEDIUM" / "LOW" — from bahn.de priority; heuristic if missing.
  final String priority;
  /// Comma-separated list of affected products or lines, e.g. "S1, IC 2013".
  final String? affected;

  const TransitDisruption({
    required this.id,
    required this.headline,
    this.text,
    this.validFrom,
    this.validUntil,
    this.priority = 'MEDIUM',
    this.affected,
  });

  bool get isHigh => priority.toUpperCase() == 'HIGH';
}

/// Fetches active traffic disruptions from bahn.de's public
/// `reiseloesung/verkehrsmeldungen` endpoint and exposes them as a badge
/// count + list. Refresh runs every 15 minutes; single-shot fetches are
/// cached for 5 minutes to avoid dashboard spam.
class TransitDisruptionsService extends ChangeNotifier {
  static final TransitDisruptionsService _instance = TransitDisruptionsService._();
  factory TransitDisruptionsService() => _instance;
  TransitDisruptionsService._();

  static const _url = 'https://www.bahn.de/web/api/reiseloesung/verkehrsmeldungen';
  static const _refresh = Duration(minutes: 15);
  static const _cacheTtl = Duration(minutes: 5);

  final _log = LoggerService();
  final http.Client _client = IOClient(HttpClientFactory.createDefaultHttpClient());

  List<TransitDisruption> _disruptions = [];
  DateTime? _lastFetch;
  Timer? _timer;

  /// When non-empty, only disruptions whose headline+text+affected mention
  /// one of these tokens (lowercased substring match) are counted / shown.
  /// Tokens come from user's Stufe-1-Adresse (city, bundesland), current GPS
  /// city, and active transit provider name.
  ///
  /// Empty set → national mode: everything is shown (fallback while profile
  /// still loading).
  final Set<String> _regionTokens = {};

  /// When true, the region filter is bypassed and every active nationwide
  /// disruption is surfaced. Persisted separately by UI code.
  bool _bypassRegionFilter = false;
  bool get bypassRegionFilter => _bypassRegionFilter;
  set bypassRegionFilter(bool v) {
    if (v == _bypassRegionFilter) return;
    _bypassRegionFilter = v;
    notifyListeners();
  }

  /// Replace the region-token set. Called by dashboard once user profile
  /// (Verifizierung Stufe 1 = strasse/plz/ort/bundesland from user_details.php)
  /// AND GPS reverse-geocode are both resolved.
  ///
  /// Tokens shorter than 4 chars are dropped — a token like "ding" would
  /// match "bindung" / "verbindung" / "erledigung" as substring and let
  /// most nationwide disruption spam through the filter.
  void setRegionTokens(Iterable<String> tokens) {
    final normalized = tokens
        .map((t) => t.trim().toLowerCase())
        .where((t) => t.length >= 4)
        .toSet();
    if (setEquals(normalized, _regionTokens)) return;
    _regionTokens
      ..clear()
      ..addAll(normalized);
    _log.info('Disruptions: region tokens set to ${_regionTokens.join(", ")}', tag: 'DISRUPT');
    notifyListeners();
  }

  /// Full nationwide list (unfiltered) — used by "Auch bundesweit anzeigen".
  List<TransitDisruption> get allDisruptions => List.unmodifiable(_disruptions);
  int get allCount => _disruptions.length;

  /// Filtered, ranked list (region-relevant first if filter active).
  List<TransitDisruption> get disruptions {
    if (_bypassRegionFilter || _regionTokens.isEmpty) {
      return List.unmodifiable(_disruptions);
    }
    return List.unmodifiable(_disruptions.where(_matchesRegion));
  }

  int get count => disruptions.length;
  int get highPriorityCount => disruptions.where((d) => d.isHigh).length;
  DateTime? get lastFetch => _lastFetch;

  /// Return the currently active disruptions that explicitly mention a line
  /// like "S1", "IC 2013", "Bus 5", "RE 4". Word-boundary substring match
  /// against headline + text + affected. Used by the Verbindung tab to
  /// mark journey cards whose actual line has an active disruption.
  ///
  /// Match is greedy — a disruption that mentions "S1 und S2" surfaces for
  /// both "S1" and "S2" queries.
  List<TransitDisruption> disruptionsMentioning(String line) {
    final needle = line.trim().toLowerCase();
    if (needle.length < 2) return const [];
    return _disruptions.where((d) {
      final hay = '${d.headline} ${d.text ?? ""} ${d.affected ?? ""}'.toLowerCase();
      final idx = hay.indexOf(needle);
      if (idx < 0) return false;
      final startOk = idx == 0 || !_isAlphanumeric(hay.codeUnitAt(idx - 1));
      final endIdx = idx + needle.length;
      final endOk = endIdx >= hay.length || !_isAlphanumeric(hay.codeUnitAt(endIdx));
      return startOk && endOk;
    }).toList();
  }

  bool _isAlphanumeric(int c) {
    return (c >= 0x30 && c <= 0x39) || _isLetter(c);
  }

  /// Word-boundary substring match. Prevents "Ulm" from matching
  /// "Neumünster", "Baden" from matching "Wiesbaden", etc. Boundary
  /// characters are ASCII non-letters (space, punctuation, digits, hyphen).
  bool _matchesRegion(TransitDisruption d) {
    final hay = '${d.headline} ${d.text ?? ""} ${d.affected ?? ""}'.toLowerCase();
    for (final t in _regionTokens) {
      final idx = hay.indexOf(t);
      if (idx < 0) continue;
      // Word start: at index 0 or previous char is non-letter.
      final startOk = idx == 0 || !_isLetter(hay.codeUnitAt(idx - 1));
      // Word end: at end of string or next char is non-letter.
      final endIdx = idx + t.length;
      final endOk = endIdx >= hay.length || !_isLetter(hay.codeUnitAt(endIdx));
      if (startOk && endOk) return true;
    }
    return false;
  }

  /// True for ASCII letters + common German umlauts (ä ö ü ß).
  bool _isLetter(int c) {
    if (c >= 0x61 && c <= 0x7A) return true; // a-z
    if (c >= 0x41 && c <= 0x5A) return true; // A-Z
    return c == 0xE4 || c == 0xF6 || c == 0xFC || c == 0xDF ||
           c == 0xC4 || c == 0xD6 || c == 0xDC;
  }

  /// Kick off periodic fetching. Idempotent — safe to call from dashboard init.
  void start() {
    if (_timer != null) return;
    fetch();
    _timer = Timer.periodic(_refresh, (_) => fetch());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> fetch({bool force = false}) async {
    if (!force && _lastFetch != null && DateTime.now().difference(_lastFetch!) < _cacheTtl) {
      return;
    }
    try {
      final resp = await _client.get(
        Uri.parse(_url),
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'ICD360S-eV-App/1.0',
        },
      ).timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) {
        _log.debug('Disruptions: HTTP ${resp.statusCode}', tag: 'DISRUPT');
        return;
      }
      final data = jsonDecode(resp.body);
      // The endpoint returns { verkehrsmeldungen: [...] } — each entry has
      // a headline, texts, validity window, priority, affected line list.
      final list = (data is Map ? data['verkehrsmeldungen'] : null) as List? ?? [];
      final parsed = list
          .map<TransitDisruption?>((raw) => _parse(raw as Map<String, dynamic>))
          .whereType<TransitDisruption>()
          .toList();
      _disruptions = parsed;
      _lastFetch = DateTime.now();
      _log.info('Disruptions: fetched ${parsed.length} active', tag: 'DISRUPT');
      notifyListeners();
    } catch (e) {
      _log.debug('Disruptions: fetch failed: $e', tag: 'DISRUPT');
    }
  }

  TransitDisruption? _parse(Map<String, dynamic> raw) {
    try {
      final id = (raw['id'] ?? raw['himId'])?.toString();
      final headline = (raw['ueberschrift'] ?? raw['headline'] ?? raw['text'])?.toString();
      if (id == null || headline == null || headline.isEmpty) return null;

      final text = (raw['text'] ?? raw['ausfuehrlicherText'])?.toString();
      final validFrom = _parseDate(raw['gueltigAb'] ?? raw['validFrom']);
      final validUntil = _parseDate(raw['gueltigBis'] ?? raw['validUntil']);

      // Only surface disruptions that are currently valid.
      final now = DateTime.now();
      if (validFrom != null && validFrom.isAfter(now)) return null;
      if (validUntil != null && validUntil.isBefore(now)) return null;

      final prio = (raw['prioritaet'] ?? raw['priority'])?.toString().toUpperCase() ?? 'MEDIUM';

      String? affected;
      final produkte = raw['produkte'] ?? raw['products'];
      if (produkte is List && produkte.isNotEmpty) {
        affected = produkte.take(5).map((p) => p.toString()).join(', ');
      }

      return TransitDisruption(
        id: id, headline: headline, text: text,
        validFrom: validFrom, validUntil: validUntil,
        priority: prio, affected: affected,
      );
    } catch (_) {
      return null;
    }
  }

  static DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    try {
      return DateTime.tryParse(raw.toString());
    } catch (_) {
      return null;
    }
  }
}
