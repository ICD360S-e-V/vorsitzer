import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import 'notification_service.dart';
import 'http_client_factory.dart';
import 'logger_service.dart';
import 'device_key_service.dart';

final _log = LoggerService();

/// Ticket Notification Service - Polls for new ticket notifications every 10 seconds
class TicketNotificationService {
  static final TicketNotificationService _instance = TicketNotificationService._internal();
  factory TicketNotificationService() => _instance;
  TicketNotificationService._internal() {
    _httpClient = IOClient(HttpClientFactory.createPinnedHttpClient());
  }

  Timer? _pollTimer;
  bool _isPolling = false;
  String? _mitgliedernummer;
  final NotificationService _notificationService = NotificationService();
  late final http.Client _httpClient;

  static const Duration _pollInterval = Duration(seconds: 60);
  static const String _apiUrl = 'https://icd360sev.icd360s.de/api/tickets/poll_notifications.php';
  static const String _ermaessigungPollUrl = 'https://icd360sev.icd360s.de/api/admin/ermaessigung_poll.php';
  int _lastErmaessigungCount = 0;

  /// Start polling for ticket notifications
  Future<void> start(String mitgliedernummer) async {
    if (_isPolling) {
      _log.warning('TicketNotificationService läuft bereits', tag: 'TICKET_NOTIF');
      return;
    }

    _mitgliedernummer = mitgliedernummer;
    _isPolling = true;

    // Erstes Poll sofort
    await _pollNotifications();

    // Dann alle 10 Sekunden
    _pollTimer = Timer.periodic(_pollInterval, (_) async {
      await _pollNotifications();
    });

    _log.info('TicketNotificationService gestartet (alle ${_pollInterval.inSeconds}s)', tag: 'TICKET_NOTIF');
  }

  /// Stop polling for ticket notifications
  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _isPolling = false;
    _mitgliedernummer = null;
    _log.info('TicketNotificationService gestoppt', tag: 'TICKET_NOTIF');
  }

  /// Poll for new ticket notifications
  Future<void> _pollNotifications() async {
    if (_mitgliedernummer == null) {
      _log.warning('Keine Mitgliedernummer - Poll übersprungen', tag: 'TICKET_NOTIF');
      return;
    }

    try {
      final deviceKey = DeviceKeyService().deviceKey;

      // Skip poll if device key not yet initialized
      if (deviceKey == null || deviceKey.isEmpty) {
        _log.debug('Device Key noch nicht initialisiert (key=${deviceKey ?? "null"}) - Poll übersprungen', tag: 'TICKET_NOTIF');
        return;
      }

      _log.debug('Polling mit Device Key: ${deviceKey.substring(0, 10)}...', tag: 'TICKET_NOTIF');

      final response = await _httpClient.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'X-Device-Key': deviceKey,  // CORRECT: Use X-Device-Key, not X-API-Key!
          'User-Agent': 'ICD360S-Vorsitzer-Windows/1.0',
        },
        body: jsonEncode({
          'mitgliedernummer': _mitgliedernummer,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _log.debug('Poll response: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}', tag: 'TICKET_NOTIF');

        if (data['success'] == true) {
          // Handle both response formats: with/without 'data' wrapper
          final dataField = data['data'];
          final notifications = (dataField != null
              ? dataField['notifications']
              : data['notifications']) as List<dynamic>? ?? [];
          final count = (dataField != null
              ? dataField['count']
              : data['count']) as int? ?? 0;

          _log.info('Poll erfolgreich: $count Benachrichtigung(en)', tag: 'TICKET_NOTIF');

          if (count > 0) {
            // Zeige Windows Notification für jede neue Benachrichtigung
            for (var notification in notifications) {
              await _showNotification(notification);
            }
          }
        } else {
          _log.warning('Poll fehlgeschlagen: ${data['message']}', tag: 'TICKET_NOTIF');
        }
      } else {
        _log.warning('Poll HTTP ${response.statusCode}: ${response.body}', tag: 'TICKET_NOTIF');
      }
    } catch (e) {
      _log.error('Poll-Fehler: $e', tag: 'TICKET_NOTIF');
    }

    // Also poll for Ermäßigungsanträge
    await _pollErmaessigung();
  }

  /// Poll for pending Ermäßigungsanträge
  Future<void> _pollErmaessigung() async {
    try {
      final deviceKey = DeviceKeyService().deviceKey;
      if (deviceKey == null || deviceKey.isEmpty) return;

      final response = await _httpClient.post(
        Uri.parse(_ermaessigungPollUrl),
        headers: {
          'Content-Type': 'application/json',
          'X-Device-Key': deviceKey,
          'User-Agent': 'ICD360S-Vorsitzer-Windows/1.0',
        },
        body: jsonEncode({
          'mitgliedernummer': _mitgliedernummer,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final count = data['count'] as int? ?? 0;
          final antraege = data['antraege'] as List<dynamic>? ?? [];

          // Only notify when count increases (new submissions)
          if (count > _lastErmaessigungCount && _lastErmaessigungCount >= 0) {
            final newCount = count - _lastErmaessigungCount;
            if (_lastErmaessigungCount > 0) {
              // Show notification for new submissions
              for (var i = 0; i < newCount && i < antraege.length; i++) {
                final antrag = antraege[i] as Map<String, dynamic>;
                final memberName = antrag['member_name'] ?? 'Unbekannt';
                final typ = antrag['antrag_typ'] ?? 'sonstiges';
                await _notificationService.show(
                  title: 'Neuer Ermäßigungsantrag',
                  body: '$memberName hat einen Ermäßigungsantrag ($typ) eingereicht.',
                  duration: const Duration(seconds: 8),
                );
              }
            }
          }
          _lastErmaessigungCount = count;
        }
      }
    } catch (e) {
      _log.error('Ermäßigung-Poll-Fehler: $e', tag: 'TICKET_NOTIF');
    }
  }

  /// Show Windows notification for a ticket notification
  Future<void> _showNotification(Map<String, dynamic> notification) async {
    try {
      final notificationType = notification['notification_type'] as String? ?? 'unknown';
      final title = notification['title'] as String? ?? 'Neue Benachrichtigung';
      final message = notification['message'] as String? ?? '';
      final ticketSubject = notification['ticket_subject'] as String? ?? '';
      final senderName = notification['sender_name'] as String? ?? 'Unbekannt';
      final ticketId = notification['ticket_id'] as int? ?? 0;

      String body = message;

      // Formatiere Nachricht basierend auf Typ
      if (notificationType == 'ticket_created') {
        body = '$senderName hat ein neues Ticket erstellt:\n"$ticketSubject"';
      } else if (notificationType == 'comment_added') {
        body = '$senderName hat auf Ticket #$ticketId geantwortet:\n"$ticketSubject"';
      }

      await _notificationService.show(
        title: title,
        body: body,
        duration: const Duration(seconds: 8),
      );

      _log.info('Notification angezeigt: "$title" - Ticket #$ticketId', tag: 'TICKET_NOTIF');
    } catch (e) {
      _log.error('Fehler beim Anzeigen der Benachrichtigung: $e', tag: 'TICKET_NOTIF');
    }
  }

  /// Check if service is currently polling
  bool get isPolling => _isPolling;

  /// Get current mitgliedernummer
  String? get mitgliedernummer => _mitgliedernummer;
}
