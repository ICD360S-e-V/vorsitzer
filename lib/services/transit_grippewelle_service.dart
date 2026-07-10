import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'http_client_factory.dart';
import 'logger_service.dart';

/// Nivele risc pentru boli respiratorii circulante (Grippe/COVID/RSV).
enum GrippewelleLevel { low, moderate, high, veryHigh }

/// Service care surfacează dacă e in-curse grippewelle regional. Sursă
/// primară: RKI ARE Wochenbericht (WEB scraping soft — endpoint public).
/// Fallback: SharedPreferences-cached last-known-level (păstrat 7 zile).
///
/// Design: nu se pornește single-shot la boot ca să nu spam-eze RKI de la
/// mii de instanțe. Se pornește doar când user-ul deschide OpnvDialog și
/// cache-ul e vechi (>24h).
class TransitGrippewelleService extends ChangeNotifier {
  static final TransitGrippewelleService _instance = TransitGrippewelleService._();
  factory TransitGrippewelleService() => _instance;
  TransitGrippewelleService._();

  static const _kPrefsLevelKey = 'opnv.grippewelle.level';
  static const _kPrefsFetchedKey = 'opnv.grippewelle.fetched_at';
  static const _kPrefsWeekKey = 'opnv.grippewelle.kw';
  // RKI ARE Wochenbericht JSON — endpoint public (dacă schimbă schema,
  // fallback la default = low fără eroare vizibilă).
  static const _url =
      'https://influenza.rki.de/Wochenbericht.aspx?format=json';

  final _log = LoggerService();
  final http.Client _client = IOClient(HttpClientFactory.createDefaultHttpClient());

  GrippewelleLevel _level = GrippewelleLevel.low;
  DateTime? _fetchedAt;
  int? _kalenderwoche;

  GrippewelleLevel get level => _level;
  int? get kalenderwoche => _kalenderwoche;
  DateTime? get fetchedAt => _fetchedAt;

  bool get shouldWarn =>
      _level == GrippewelleLevel.high || _level == GrippewelleLevel.veryHigh;

  String get germanLabel {
    switch (_level) {
      case GrippewelleLevel.low:      return 'Geringe Aktivität';
      case GrippewelleLevel.moderate: return 'Moderate Aktivität';
      case GrippewelleLevel.high:     return 'Erhöhte Aktivität';
      case GrippewelleLevel.veryHigh: return 'Starke Grippewelle';
    }
  }

  /// One-shot fetch dacă cache-ul e >24h vechi.
  Future<void> refreshIfStale() async {
    await _loadFromPrefs();
    if (_fetchedAt != null &&
        DateTime.now().difference(_fetchedAt!).inHours < 24) {
      return;
    }
    await _fetchFromRki();
  }

  Future<void> _loadFromPrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_kPrefsLevelKey);
      if (raw != null) {
        _level = GrippewelleLevel.values.firstWhere(
          (v) => v.name == raw,
          orElse: () => GrippewelleLevel.low,
        );
      }
      final ts = sp.getString(_kPrefsFetchedKey);
      if (ts != null) _fetchedAt = DateTime.tryParse(ts);
      _kalenderwoche = sp.getInt(_kPrefsWeekKey);
    } catch (_) {}
  }

  Future<void> _fetchFromRki() async {
    try {
      final resp = await _client.get(
        Uri.parse(_url),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return;
      // RKI-ul returnează un raport săptămânal. Parseăm intensitate.
      final body = resp.body;
      // Fallback simplu: cautăm keywords în răspuns.
      GrippewelleLevel derived = GrippewelleLevel.low;
      final lower = body.toLowerCase();
      if (lower.contains('sehr hoch') || lower.contains('sehr starke')) {
        derived = GrippewelleLevel.veryHigh;
      } else if (lower.contains('hoch') || lower.contains('starke')) {
        derived = GrippewelleLevel.high;
      } else if (lower.contains('moderat')) {
        derived = GrippewelleLevel.moderate;
      }
      // Extract Kalenderwoche (KW XX).
      final kwMatch = RegExp(r'KW\s*(\d{1,2})', caseSensitive: false).firstMatch(body);
      if (kwMatch != null) {
        _kalenderwoche = int.tryParse(kwMatch.group(1)!);
      }
      _level = derived;
      _fetchedAt = DateTime.now();
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_kPrefsLevelKey, _level.name);
      await sp.setString(_kPrefsFetchedKey, _fetchedAt!.toIso8601String());
      if (_kalenderwoche != null) {
        await sp.setInt(_kPrefsWeekKey, _kalenderwoche!);
      }
      _log.info('Grippewelle: fetched RKI status ${_level.name} '
          '(KW ${_kalenderwoche ?? "?"})', tag: 'GRIPPE');
      notifyListeners();
    } catch (e) {
      _log.debug('Grippewelle: RKI fetch failed: $e', tag: 'GRIPPE');
    }
  }

  /// Wrapper JSON de decodare — extras separat pentru testabilitate.
  static Map<String, dynamic>? tryDecode(String body) {
    try {
      final j = jsonDecode(body);
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null;
    }
  }
}
