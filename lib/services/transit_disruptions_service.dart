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

  List<TransitDisruption> get disruptions => List.unmodifiable(_disruptions);
  int get count => _disruptions.length;
  int get highPriorityCount => _disruptions.where((d) => d.isHigh).length;
  DateTime? get lastFetch => _lastFetch;

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
