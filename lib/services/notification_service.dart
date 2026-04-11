import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'logger_service.dart';
import 'tray_service.dart';
import 'platform_service.dart';

final _log = LoggerService();

/// Cross-Platform Notification Service
/// Uses flutter_local_notifications for all platforms:
/// - Windows: Toast notifications
/// - macOS: Notification Center
/// - Linux: libnotify
/// - Android: System notifications
/// - iOS: Local notifications
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  // Global key for navigator (kept for compatibility)
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  // Track if admin chat dialog is currently open
  static bool _isChatDialogOpen = false;

  bool _isInitialized = false;

  // Flutter Local Notifications plugin instance
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  // macOS native notification channel
  static final MethodChannel _macOSChannel =
      MethodChannel('de.icd360sev.vorsitzer/notifications');

  // Stream for notification click events (payload string)
  final StreamController<String> _clickController = StreamController<String>.broadcast();
  Stream<String> get onNotificationClicked => _clickController.stream;

  // Notification channel for Android
  static const String _channelId = 'icd360sev_vorsitzer_channel';
  static const String _channelName = 'ICD360S e.V Benachrichtigungen';
  static const String _channelDescription =
      'Benachrichtigungen für Chat, Anrufe und Updates';

  /// Chat-Dialog-Status setzen (von AdminChatDialog aufrufen)
  static void setChatDialogOpen(bool isOpen) {
    _isChatDialogOpen = isOpen;
    _log.debug('Chat-Dialog geöffnet: $isOpen', tag: 'NOTIF');

    // Beim Öffnen des Chats: Ungelesen-Zähler und Blinken zurücksetzen
    if (isOpen && PlatformService.isDesktop) {
      TrayService().clearUnread();
      TrayService().stopFlashing();
    }
  }

  /// Check if chat dialog is currently open
  static bool get isChatDialogOpen => _isChatDialogOpen;

  /// Initialize the notification service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Platform-specific initialization settings
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const linuxSettings =
          LinuxInitializationSettings(defaultActionName: 'Öffnen');

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
        linux: linuxSettings,
      );

      await _notifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // Create notification channel for Android
      if (Platform.isAndroid) {
        await _createAndroidNotificationChannel();
      }

      // Request permissions on iOS/macOS
      if (Platform.isIOS || Platform.isMacOS) {
        await _requestDarwinPermissions();
      }

      // Listen for notification click events from native macOS
      if (Platform.isMacOS) {
        _macOSChannel.setMethodCallHandler((call) async {
          if (call.method == 'onNotificationClicked') {
            final payload = call.arguments as String? ?? '';
            _log.info('macOS notification clicked, payload: $payload', tag: 'NOTIF');
            _clickController.add(payload);
          }
        });
      }

      _isInitialized = true;
      _log.info(
          'NotificationService initialisiert (${PlatformService.platformName})',
          tag: 'NOTIF');
    } catch (e) {
      _log.error('NotificationService Initialisierung fehlgeschlagen: $e',
          tag: 'NOTIF');
    }
  }

  /// Create Android notification channel
  Future<void> _createAndroidNotificationChannel() async {
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// Request notification permissions on iOS/macOS
  Future<void> _requestDarwinPermissions() async {
    if (Platform.isIOS) {
      await _notifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    } else if (Platform.isMacOS) {
      await _notifications
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    }
  }

  /// Gestionează click pe notificare
  /// Payload format: 'type:data' (ex: 'chat:123', 'call:456', 'update:1.0.5')
  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    _log.debug('Notificare apăsată: $payload', tag: 'NOTIF');

    if (payload == null || payload.isEmpty) return;

    // Parsează payload-ul (format: 'type:data')
    final parts = payload.split(':');
    final type = parts.isNotEmpty ? parts[0] : '';
    final data = parts.length > 1 ? parts[1] : '';

    // Acțiuni bazate pe tip
    switch (type) {
      case 'chat':
        // Deschide chat-ul - gestionat de UI (AdminChatDialog)
        _log.info('Navigare la conversație: $data', tag: 'NOTIF');
        break;
      case 'call':
        // Apel incoming - gestionat de VoiceCallService
        _log.info('Navigare la apel: $data', tag: 'NOTIF');
        break;
      case 'update':
        // Update disponibil - gestionat de UpdateService
        _log.info('Navigare la update: v$data', tag: 'NOTIF');
        break;
      case 'connection':
      case 'error':
      case 'success':
      case 'test':
        // Notificări informative - fără navigare
        _log.debug('Notificare informativă: $type', tag: 'NOTIF');
        break;
      default:
        _log.warning('Tip notificare necunoscut: $type', tag: 'NOTIF');
    }
  }

  /// Get platform-specific notification details
  NotificationDetails _getNotificationDetails({
    String? payload,
    bool playSound = true,
  }) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        playSound: playSound,
        enableVibration: true,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: playSound,
      ),
      macOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: playSound,
      ),
      linux: const LinuxNotificationDetails(),
    );
  }

  /// Show a native notification on all platforms
  Future<void> show({
    required String title,
    required String body,
    Duration duration = const Duration(seconds: 5),
    Color? backgroundColor,
    IconData? icon,
    VoidCallback? onTap,
    String? payload,
  }) async {
    try {
      if (Platform.isMacOS) {
        // macOS: use native UNUserNotificationCenter via MethodChannel
        await _showMacOSNotification(title, body, payload: payload);
      } else {
        // All other platforms: use flutter_local_notifications
        final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        await _notifications.show(
          id: id,
          title: title,
          body: body,
          notificationDetails: _getNotificationDetails(payload: payload),
          payload: payload,
        );
      }

      _log.info('Notification angezeigt: "$title" - $body', tag: 'NOTIF');
    } catch (e) {
      _log.error('Notification fehlgeschlagen: $e', tag: 'NOTIF');
    }
  }

  /// macOS native notification via dual approach:
  /// 1. UNUserNotificationCenter via MethodChannel (proper API)
  /// 2. osascript fallback (guaranteed visual banner)
  Future<void> _showMacOSNotification(String title, String body, {String? payload}) async {
    // Try native UNUserNotificationCenter first
    try {
      await _macOSChannel.invokeMethod('showNotification', {
        'title': title,
        'body': body,
        if (payload != null) 'payload': payload,
      });
      _log.debug('macOS: UNUserNotificationCenter notification sent', tag: 'NOTIF');
    } catch (e) {
      _log.error('macOS native notification failed: $e', tag: 'NOTIF');
    }

    // Also use osascript as guaranteed visual fallback
    // osascript always shows a visible banner on macOS
    try {
      final safeTitle = title.replaceAll('"', '\\"').replaceAll("'", "'");
      final safeBody = body.replaceAll('"', '\\"').replaceAll("'", "'");
      await Process.run('osascript', [
        '-e',
        'display notification "$safeBody" with title "$safeTitle" sound name "default"',
      ]);
      _log.debug('macOS: osascript notification sent', tag: 'NOTIF');
    } catch (e) {
      _log.error('macOS osascript notification failed: $e', tag: 'NOTIF');
    }
  }

  /// Chat-Benachrichtigung anzeigen (nur wenn Chat-Dialog geschlossen ist)
  Future<void> showChatMessage({
    required String senderName,
    required String message,
    int? conversationId,
  }) async {
    _log.info(
        'Chat-Benachrichtigung: "$senderName" - $message (chatOffen=$_isChatDialogOpen)',
        tag: 'NOTIF');

    // Nur benachrichtigen wenn Chat-Dialog NICHT geöffnet ist
    if (!_isChatDialogOpen) {
      // Native notification on all platforms
      await show(
        title: 'Neue Nachricht im Live-Chat',
        body: 'Sie haben eine neue Nachricht erhalten.',
        payload: 'chat:$conversationId',
      );

      // Desktop: Tray Badge + Taskbar Flash
      if (PlatformService.isDesktop) {
        await TrayService().incrementUnread();
      }
    } else {
      _log.debug('Benachrichtigung übersprungen - Chat-Dialog ist geöffnet',
          tag: 'NOTIF');
    }
  }

  /// Show an incoming call notification
  Future<void> showIncomingCall({
    required String callerName,
    int? conversationId,
  }) async {
    await show(
      title: 'Eingehender Anruf',
      body: '$callerName ruft an...',
      payload: 'call:$conversationId',
    );

    // Desktop: Taskbar flash
    if (PlatformService.isDesktop) {
      await TrayService().flashTaskbar();
    }

    _log.info('Anruf-Benachrichtigung: $callerName', tag: 'NOTIF');
  }

  /// Show update available notification
  Future<void> showUpdateAvailable({
    required String version,
  }) async {
    await show(
      title: 'Update verfügbar',
      body:
          'Version $version ist verfügbar. Klicken Sie hier zum Aktualisieren.',
      payload: 'update:$version',
    );
    _log.info('Update-Benachrichtigung: v$version', tag: 'NOTIF');
  }

  /// Show connection status notification
  Future<void> showConnectionStatus({
    required bool connected,
  }) async {
    await show(
      title: connected ? 'Verbunden' : 'Verbindung getrennt',
      body: connected
          ? 'Sie sind jetzt mit dem Server verbunden.'
          : 'Die Verbindung zum Server wurde getrennt.',
      payload: 'connection:$connected',
    );
    _log.info('Verbindung: ${connected ? "verbunden" : "getrennt"}',
        tag: 'NOTIF');
  }

  /// Show error notification
  Future<void> showError({
    required String message,
  }) async {
    await show(
      title: 'Fehler',
      body: message,
      payload: 'error',
    );
    _log.error('Fehler-Benachrichtigung: $message', tag: 'NOTIF');
  }

  /// Show success notification
  Future<void> showSuccess({
    required String title,
    required String message,
  }) async {
    await show(
      title: title,
      body: message,
      payload: 'success',
    );
    _log.info('Erfolg: $title - $message', tag: 'NOTIF');
  }

  /// Test notification
  Future<void> testNotification() async {
    await show(
      title: 'Test Benachrichtigung',
      body: 'Dies ist eine Test-Benachrichtigung von ICD360S e.V.',
      payload: 'test',
    );

    // Desktop: Taskbar flash
    if (PlatformService.isDesktop) {
      await TrayService().flashTaskbar();
    }

    _log.info('TEST NOTIFICATION gesendet', tag: 'NOTIF');
  }

  /// Cancel all notifications
  Future<void> cancelAll() async {
    await _notifications.cancelAll();
    _log.debug('Alle Benachrichtigungen abgebrochen', tag: 'NOTIF');
  }

  /// Cancel a specific notification by ID
  Future<void> cancel(int id) async {
    await _notifications.cancel(id: id);
  }
}
