import 'dart:async';
import 'api_service.dart';
import 'logger_service.dart';

final _log = LoggerService();

/// Heartbeat Service — hält `users.last_seen` frisch, damit Mitglieder sehen,
/// ob der Vorsitz gerade erreichbar ist.
///
/// ⚠️ DIESER TAKT HÄNGT AN EINER ZAHL AUF DEM SERVER.
/// `api/chat/support_status.php` entscheidet mit `ONLINE_FENSTER_SEKUNDEN`,
/// ab wann jemand als offline gilt. Das Fenster muss GRÖSSER sein als dieser
/// Takt, sonst flackert die Anzeige.
///
/// Bis zum 03.09.2026 passte das nicht zusammen: hier standen 60 Sekunden,
/// dort 30 — der Vorsitz galt also die halbe Zeit als offline, obwohl die App
/// lief. Live nachgemessen an dem Tag: `seconds_since_active: 32`, also genau
/// dieser Fall. Kein Fehler meldete sich; es sah nur nach „gerade weg" aus.
///
/// Jetzt 120 s hier gegen 180 s dort. Das halbiert nebenbei die Anfragen von
/// 1.440 auf 720 am Tag — jede weckt das Funkmodul, das danach rund
/// 17 Sekunden in erhöhtem Zustand bleibt (Android, „The radio state
/// machine"). Wer den Takt ändert, ändert das Serverfenster mit.
class HeartbeatService {
  static const Duration _interval = Duration(seconds: 120);

  /// Nur für den Regressionstest, der diesen Wert gegen das Online-Fenster
  /// des Servers hält. Der Takt selbst bleibt privat.
  static int get taktSekunden => _interval.inSeconds;

  Timer? _timer;
  String? _currentMitgliedernummer;
  ApiService? _apiService;
  bool _isActive = false;

  // Singleton
  static final HeartbeatService _instance = HeartbeatService._internal();
  factory HeartbeatService(ApiService apiService) {
    _instance._apiService = apiService;
    return _instance;
  }
  HeartbeatService._internal();

  /// Start heartbeat updates
  void start(String mitgliedernummer) {
    _log.info('Heartbeat: Starting for $mitgliedernummer', tag: 'HEARTBEAT');
    _currentMitgliedernummer = mitgliedernummer;
    _isActive = true;

    // Cancel existing timer
    _timer?.cancel();

    // Start periodic heartbeat
    _timer = Timer.periodic(_interval, (_) => _sendHeartbeat());

    // Send initial heartbeat immediately
    _sendHeartbeat();
  }

  /// Stop heartbeat updates
  void stop() {
    _log.info('Heartbeat: Stopping', tag: 'HEARTBEAT');
    _timer?.cancel();
    _timer = null;
    _isActive = false;
    _currentMitgliedernummer = null;
  }

  /// Send heartbeat to server
  Future<void> _sendHeartbeat() async {
    if (!_isActive || _currentMitgliedernummer == null || _apiService == null) {
      return;
    }

    try {
      final result = await _apiService!.sendHeartbeat(_currentMitgliedernummer!);

      if (result['success'] == true) {
        _log.debug('Heartbeat: Sent successfully for $_currentMitgliedernummer', tag: 'HEARTBEAT');
      } else {
        _log.warning('Heartbeat: Failed - ${result['message']}', tag: 'HEARTBEAT');
      }
    } catch (e) {
      // Silently fail - don't interrupt app for heartbeat failures
      _log.error('Heartbeat: Error sending - $e', tag: 'HEARTBEAT');
    }
  }

  /// Check if heartbeat is active
  bool get isActive => _isActive;

  /// Dispose service
  void dispose() {
    stop();
  }
}
