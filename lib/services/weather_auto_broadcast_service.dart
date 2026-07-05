import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';
import 'api_service.dart';
import 'logger_service.dart';

final _log = LoggerService();

/// Small in-memory log entry of an auto-broadcast the service actually made,
/// or a decision-not-to-make. Useful for the read-only status view later.
class AutoBroadcastLogEntry {
  final DateTime at;
  final String userMitgliedernummer;
  final String userName;
  final String alertEvent;
  final String alertSeverity;
  final bool sent;
  final String? failureReason;

  const AutoBroadcastLogEntry({
    required this.at,
    required this.userMitgliedernummer,
    required this.userName,
    required this.alertEvent,
    required this.alertSeverity,
    required this.sent,
    this.failureReason,
  });
}

/// Fully-automated Vorsitzer tool: pro Mitglied-Adresse werden DWD-Warnungen
/// von Bright Sky abgefragt; bei einer NEUEN Warnung mit Severity ≥ `moderate`
/// wird automatisch ein Chat-Full-Screen-Alert an genau die betroffenen
/// Mitglieder verschickt. Kein Klick nötig.
///
/// Anti-Spam-Schutz:
///   • Dedup pro (Warn-Hash, Mitglied-ID, Kalendertag) — persistent in
///     SharedPreferences, überlebt App-Neustarts
///   • Nur Severity moderate/severe/extreme werden verschickt; leichte
///     Warnungen bleiben stumm damit niemand alle drei Wochen mit einer
///     Nebel-Meldung geweckt wird
///   • Timer läuft alle 6 Stunden — DWD-Warnungen ändern sich selten schneller
///     als das, und häufigere Sweeps würden nur unnötig Handy-Akku und
///     API-Kontingent kosten. Zusätzlich manuelles refreshNow() für den
///     Vorsitzer, falls er sofort einen Sweep triggern will
class WeatherAutoBroadcastService {
  WeatherAutoBroadcastService._();
  static final instance = WeatherAutoBroadcastService._();

  Timer? _timer;
  ApiService? _apiService;
  List<User> _users = const [];
  String _adminMitgliedernummer = '';
  bool _running = false;

  // Rolling in-memory log — up to 200 entries so the status UI stays useful
  // without eating memory across a long-lived Vorsitzer session.
  final List<AutoBroadcastLogEntry> _logs = [];
  List<AutoBroadcastLogEntry> get log => List.unmodifiable(_logs.reversed);

  // Cache: user location key → (lat, lon). Populated lazily.
  final Map<String, (double, double)> _geoCache = {};

  static const _spKeyGeocodePrefix = 'auto_broadcast_geo_v1_';
  static const _spKeyDedupPrefix = 'auto_broadcast_sent_v1_';

  void start({
    required ApiService apiService,
    required List<User> users,
    required String adminMitgliedernummer,
  }) {
    _apiService = apiService;
    _users = users;
    _adminMitgliedernummer = adminMitgliedernummer;
    if (_timer != null) return; // already running
    _timer = Timer.periodic(const Duration(hours: 6), (_) => _sweep());
    // First sweep 30 seconds after start so we don't hammer the API in the
    // exact same second as everything else the dashboard is loading.
    Timer(const Duration(seconds: 30), _sweep);
    _log.info('WeatherAutoBroadcast: started (${users.length} users)',
        tag: 'AUTO_BROADCAST');
  }

  void updateUsers(List<User> users) {
    _users = users;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Manuell einen Sweep starten (z.B. wenn Vorsitzer nach neuen Daten
  /// direkt broadcasten will, ohne die 30-Min-Grenze abzuwarten).
  Future<void> refreshNow() async {
    if (!_running) await _sweep();
  }

  Future<void> _sweep() async {
    if (_running) return;
    final api = _apiService;
    if (api == null || _users.isEmpty) return;
    _running = true;
    int newAlerts = 0, sent = 0, failed = 0;
    try {
      // Group users by location so 30 Members in Ulm cost exactly one API call.
      final byLoc = <String, List<User>>{};
      for (final u in _users) {
        if (u.status != 'aktiv' && u.status != 'active') continue;
        final key = _locKey(u);
        if (key == null) continue;
        byLoc.putIfAbsent(key, () => []).add(u);
      }

      for (final entry in byLoc.entries) {
        final coords = await _geocode(entry.key);
        if (coords == null) continue;
        final alerts = await _fetchAlerts(coords.$1, coords.$2);
        if (alerts.isEmpty) continue;
        for (final alert in alerts) {
          final severity = (alert['severity'] as String? ?? 'minor');
          // Only moderate+ — leichte Warnungen erzeugen sonst permanent Push
          if (severity == 'minor') continue;
          final headline = (alert['headline_de'] ?? alert['headline'] ?? '') as String;
          final event = (alert['event_de'] ?? alert['event'] ?? '') as String;
          if (headline.isEmpty) continue;
          final alertHash = _hashAlert(headline, event, severity);
          for (final u in entry.value) {
            newAlerts++;
            final ok = await _maybeSend(u, alertHash, headline, event, severity);
            if (ok == null) continue; // dedup skipped
            if (ok) { sent++; } else { failed++; }
          }
        }
      }
      _log.info(
        'WeatherAutoBroadcast: sweep done — '
        '$newAlerts alerts scanned, $sent sent, $failed failed',
        tag: 'AUTO_BROADCAST',
      );
    } catch (e, st) {
      _log.error('WeatherAutoBroadcast: sweep crashed: $e\n$st',
          tag: 'AUTO_BROADCAST');
    } finally {
      _running = false;
    }
  }

  /// Returns null when the send was deduped (already handled today),
  /// true when it went through, false when the send API failed.
  Future<bool?> _maybeSend(
    User user,
    String alertHash,
    String headline,
    String event,
    String severity,
  ) async {
    final api = _apiService;
    if (api == null) return false;
    final sp = await SharedPreferences.getInstance();
    final ymd = _ymd(DateTime.now());
    final key = '$_spKeyDedupPrefix${alertHash}_${user.id}_$ymd';
    if (sp.getBool(key) == true) return null; // already sent today

    final severityLabel = switch (severity) {
      'extreme' => 'AKUT',
      'severe' => 'Schwer',
      'moderate' => 'Mäßig',
      _ => 'Leicht',
    };
    final message =
        '⚠️ Wetter-Warnung an deiner Adresse\n\n'
        '$event ($severityLabel)\n'
        '$headline\n\n'
        'Bitte auf Wettermeldungen achten und bei Bedarf Termine verschieben. '
        'Melde dich, wenn du Hilfe brauchst.\n\n'
        '— ICD360S e.V.';
    try {
      final start = await api.adminStartChat(
        _adminMitgliedernummer, user.mitgliedernummer);
      if (start['success'] != true) {
        _logEntry(user, event, severity, false,
            reason: 'adminStart: ${start['message']}');
        return false;
      }
      final convId = start['conversation_id'] as int?;
      if (convId == null) {
        _logEntry(user, event, severity, false, reason: 'no conversation_id');
        return false;
      }
      final send = await api.sendChatMessage(
        convId, _adminMitgliedernummer, message,
        urgent: true, skipTranslation: false,
      );
      if (send['success'] == true) {
        await sp.setBool(key, true);
        _logEntry(user, event, severity, true);
        return true;
      } else {
        _logEntry(user, event, severity, false, reason: '${send['message']}');
        return false;
      }
    } catch (e) {
      _logEntry(user, event, severity, false, reason: '$e');
      return false;
    }
  }

  void _logEntry(User u, String event, String severity, bool sent,
      {String? reason}) {
    _logs.add(AutoBroadcastLogEntry(
      at: DateTime.now(),
      userMitgliedernummer: u.mitgliedernummer,
      userName: u.name,
      alertEvent: event,
      alertSeverity: severity,
      sent: sent,
      failureReason: reason,
    ));
    if (_logs.length > 200) _logs.removeAt(0);
  }

  String? _locKey(User u) {
    final ort = (u.ort ?? '').trim();
    if (ort.isEmpty) return null;
    final plz = (u.plz ?? '').trim();
    return plz.isEmpty ? ort : '$plz $ort';
  }

  Future<(double, double)?> _geocode(String key) async {
    if (_geoCache.containsKey(key)) return _geoCache[key];
    final sp = await SharedPreferences.getInstance();
    final cached = sp.getString('$_spKeyGeocodePrefix$key');
    if (cached != null) {
      final parts = cached.split(',');
      if (parts.length == 2) {
        final lat = double.tryParse(parts[0]);
        final lon = double.tryParse(parts[1]);
        if (lat != null && lon != null) {
          _geoCache[key] = (lat, lon);
          return (lat, lon);
        }
      }
    }
    try {
      final r = await http.get(Uri.parse(
        'https://geocoding-api.open-meteo.com/v1/search'
        '?name=${Uri.encodeComponent(key)}&count=1&language=de&format=json',
      )).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return null;
      final data = jsonDecode(r.body);
      final results = data['results'] as List?;
      if (results == null || results.isEmpty) return null;
      final lat = (results[0]['latitude'] as num).toDouble();
      final lon = (results[0]['longitude'] as num).toDouble();
      await sp.setString('$_spKeyGeocodePrefix$key', '$lat,$lon');
      _geoCache[key] = (lat, lon);
      return (lat, lon);
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchAlerts(double lat, double lon) async {
    try {
      final r = await http.get(Uri.parse(
        'https://api.brightsky.dev/alerts?lat=$lat&lon=$lon',
      )).timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return const [];
      final data = jsonDecode(r.body);
      final list = (data['alerts'] as List?) ?? const [];
      final now = DateTime.now();
      return list.cast<Map<String, dynamic>>().where((a) {
        final expires = a['expires'] != null
            ? DateTime.tryParse(a['expires'])
            : null;
        return expires == null || expires.isAfter(now);
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Stable hash so the same DWD alert deduplicates even after a re-fetch.
  String _hashAlert(String headline, String event, String severity) {
    final b = utf8.encode('$event|$severity|$headline');
    return sha256.convert(b).toString().substring(0, 12);
  }

  String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
