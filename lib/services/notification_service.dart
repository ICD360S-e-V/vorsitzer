import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'logger_service.dart';
import 'tray_service.dart';
import 'platform_service.dart';
import 'weather_service.dart';

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

  // Default notification channel for Android
  static const String _channelId = 'icd360sev_vorsitzer_channel';
  static const String _channelName = 'ICD360S e.V Benachrichtigungen';
  static const String _channelDescription =
      'Benachrichtigungen für Chat, Anrufe und Updates';

  // ÖPNV-specific channels — the user can independently mute e.g. Störungen
  // while keeping Ausstieg-Alarm at full volume via Android system settings.
  //
  // - opnvReminder: 'ÖPNV-Erinnerungen' (Termin-Reminder, Häufigkeit hoch)
  // - opnvAlarm:    'Ausstieg-Alarm' (max importance, vibrate — safety-critical)
  // - opnvStoerung: 'Verkehrsstörungen' (default importance, optional)
  static const String channelIdOpnvReminder = 'opnv_reminder';
  static const String channelIdOpnvAlarm = 'opnv_alarm';
  static const String channelIdOpnvStoerung = 'opnv_stoerung';

  /// Eingehender sipgate-Anruf.
  ///
  /// ⚠️ Eigener Kanal mit `Importance.max`.
  ///
  /// Ein Vollbild-Intent braucht mindestens einen Kanal mit `HIGH`; die AOSP-
  /// Dokumentation zu den FSI-Grenzen nennt gar keine Schwelle, verbreitete
  /// Praxis ist `MAX`. Also: `HIGH` reicht vermutlich, `MAX` sicher — und weil
  /// der Standardkanal dieser App `high` ist und noch drei andere Funktionen
  /// trägt, ist ein eigener Kanal ohnehin richtig. Der Nutzer kann Anrufe dann
  /// getrennt von ÖPNV-Meldungen stummschalten, was er sonst nicht könnte.
  static const String channelIdAnruf = 'sipgate_anruf';

  /// Kanal für den Blitz — die Nachricht, die sich als Vollbild-Schirm mitten
  /// auf das Tablet legt.
  ///
  /// ⚠️ Eigener Kanal, nicht der Anruf-Kanal: sonst könnte man Anrufe nicht
  /// stumm schalten, ohne die Nachrichten mit stumm zu schalten. Und
  /// `Importance.max`, weil ein Vollbild-Intent bei niedrigerer Stufe
  /// wortlos zu einem gewöhnlichen Streifen wird.
  static const String channelIdBlitz = 'blitz_nachricht';

  /// Kennungen der beiden Knöpfe in der Anruf-Benachrichtigung. Kommen als
  /// `response.actionId` zurück und werden auf [onNotificationClicked] als
  /// `sipgate-aktion:<id>` weitergereicht.
  static const String aktionAnnehmen = 'sipgate_annehmen';
  static const String aktionAblehnen = 'sipgate_ablehnen';

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
        await requestAndroidPermission();
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

  /// Create Android notification channels — default + 3 ÖPNV-specific.
  Future<void> _createAndroidNotificationChannel() async {
    final impl = _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (impl == null) return;

    // 1. Default channel (chat / calls / updates)
    await impl.createNotificationChannel(const AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    ));
    // 2. ÖPNV Termin-Reminder (high — but user can mute independently)
    await impl.createNotificationChannel(const AndroidNotificationChannel(
      channelIdOpnvReminder,
      'ÖPNV-Erinnerungen',
      description: 'Erinnert dich rechtzeitig loszufahren zum Termin.',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    ));
    // 3. Ausstieg-Alarm (max — safety-critical, hardest to accidentally silence)
    await impl.createNotificationChannel(const AndroidNotificationChannel(
      channelIdOpnvAlarm,
      'Ausstieg-Alarm',
      description: 'Vibriert wenn du deine gewählte Ausstiegs-Haltestelle erreichst.',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    ));
    // 4. Verkehrsstörungen (default — informative, can be muted without loss)
    await impl.createNotificationChannel(const AndroidNotificationChannel(
      channelIdAnruf,
      'Eingehende Anrufe',
      description: 'Klingelt und zeigt, wer über sipgate anruft.',
      importance: Importance.max,
    ));

    await impl.createNotificationChannel(const AndroidNotificationChannel(
      channelIdBlitz,
      'Blitz-Nachrichten',
      description: 'Legt eine eingehende Nachricht sofort auf den Bildschirm.',
      importance: Importance.max,
    ));

    await impl.createNotificationChannel(const AndroidNotificationChannel(
      channelIdOpnvStoerung,
      'Verkehrsstörungen',
      description: 'Aktive HIM-Störungsmeldungen in deiner Region.',
      importance: Importance.defaultImportance,
      playSound: false,
      enableVibration: false,
    ));
  }

  /// Fragt POST_NOTIFICATIONS auf Android ab.
  ///
  /// ⚠️ DAS FEHLTE, UND DAMIT KONNTE JEDE BENACHRICHTIGUNG STILL AUSFALLEN.
  /// `POST_NOTIFICATIONS` ist seit Android 13 eine Laufzeitberechtigung. Sie
  /// stand im Manifest, wurde aber nie abgefragt — und weil die App
  /// `targetSdk = 34` hat, zeigt Android den Dialog auch nicht mehr von selbst
  /// (das tat es nur bei Apps unter Ziel-33, beim ersten Anlegen eines Kanals).
  ///
  /// Ohne die Freigabe erscheint **nichts**: kein eingehender sipgate-Anruf,
  /// keine Fernwahl-Benachrichtigung, keine ÖPNV-Erinnerung. Und zwar
  /// geräuschlos — `show()` wirft nicht, die Benachrichtigung wird nur
  /// verworfen. Dieselbe Falle wie bei BLUETOOTH_CONNECT und
  /// USE_FULL_SCREEN_INTENT: deklariert ist nicht erteilt.
  ///
  /// Wirft nie: eine abgelehnte Berechtigung darf den Start nicht aufhalten.
  Future<bool?> requestAndroidPermission() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (e) {
      _log.warning('POST_NOTIFICATIONS nicht abfragbar: $e', tag: 'NOTIF');
      return null;
    }
  }

  /// Sind Benachrichtigungen für diese App überhaupt erlaubt?
  ///
  /// Für Bildschirme, die einen Hinweis zeigen wollen, statt den Nutzer im
  /// Glauben zu lassen, es klingle schon.
  Future<bool?> androidErlaubt() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.areNotificationsEnabled();
    } catch (_) {
      return null;
    }
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
  /// Payload format: 'type:data' (ex: 'chat:123', 'call:456', 'update:1.0.5',
  /// 'termin:42', 'opnv:ausstieg:stopId'). Router pentru tot ce nu e stream
  /// consumat by UI (dashboard listen la onNotificationClicked).
  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    _log.debug('Notificare apăsată: $payload', tag: 'NOTIF');

    // Ein Knopf IN der Benachrichtigung — getrennt vom Antippen der
    // Benachrichtigung selbst, denn „Ablehnen" soll nicht zusätzlich den
    // Anrufbildschirm öffnen.
    final aktion = response.actionId;
    if (aktion != null && aktion.startsWith('sipgate_')) {
      _log.info('Anruf-Knopf gedrückt: $aktion', tag: 'NOTIF');
      _clickController.add('sipgate-aktion:$aktion');
      return;
    }

    if (payload == null || payload.isEmpty) return;

    // Publică raw payload → dashboard poate să interpreteze context
    // ('termin:42' → deschide OpnvDialog cu deep-link,
    //  'opnv:ausstieg:X' → resume la trip-map dacă e activ).
    _clickController.add(payload);

    // Parsează payload-ul (format: 'type:data')
    final parts = payload.split(':');
    final type = parts.isNotEmpty ? parts[0] : '';
    final data = parts.length > 1 ? parts[1] : '';

    // Acțiuni bazate pe tip
    switch (type) {
      case 'chat':
        _log.info('Navigare la conversație: $data', tag: 'NOTIF');
        break;
      case 'blitz':
        // Nutzlast: 'blitz:<conversationId>:<kanal>'. Das Dashboard hört auf
        // [onNotificationClicked] und öffnet den Vollbild-Schirm.
        _log.info('Blitz angetippt: conv=$data', tag: 'NOTIF');
        break;
      case 'call':
        _log.info('Navigare la apel: $data', tag: 'NOTIF');
        break;
      case 'update':
        _log.info('Navigare la update: v$data', tag: 'NOTIF');
        break;
      case 'termin':
        _log.info('Deep-link termin ID: $data → OpnvDialog', tag: 'NOTIF');
        break;
      case 'opnv':
        // 'opnv:ausstieg:X' sau 'opnv:reminder:X'
        _log.info('Deep-link ÖPNV: ${parts.sublist(1).join(":")}', tag: 'NOTIF');
        break;
      case 'grippe':
        _log.info('Grippewelle info tap', tag: 'NOTIF');
        break;
      case 'connection':
      case 'error':
      case 'success':
      case 'test':
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
    /// Vollbild-Benachrichtigung — nur für eingehende Anrufe. Braucht
    /// `USE_FULL_SCREEN_INTENT` als **erteilte** Berechtigung und einen Kanal
    /// mit `Importance.max`; fehlt eines von beiden, zeigt Android einen
    /// gewöhnlichen Streifen statt eines Anrufbildschirms.
    bool fullScreenIntent = false,
    /// Knöpfe in der Benachrichtigung — für eingehende Anrufe „Annehmen" und
    /// „Ablehnen".
    List<AndroidNotificationAction>? actions,
    /// Overrides the default channel — for ÖPNV features which each own
    /// a dedicated Android channel (user can mute independently).
    String? androidChannelId,
  }) {
    final chId = androidChannelId ?? _channelId;
    // Match name/description/importance to whatever we registered at boot.
    String chName;
    String chDesc;
    Importance imp;
    switch (chId) {
      case channelIdOpnvReminder:
        chName = 'ÖPNV-Erinnerungen';
        chDesc = 'Erinnert dich rechtzeitig loszufahren zum Termin.';
        imp = Importance.high;
        break;
      case channelIdOpnvAlarm:
        chName = 'Ausstieg-Alarm';
        chDesc = 'Vibriert wenn du deine gewählte Ausstiegs-Haltestelle erreichst.';
        imp = Importance.max;
        break;
      case channelIdOpnvStoerung:
        chName = 'Verkehrsstörungen';
        chDesc = 'Aktive HIM-Störungsmeldungen in deiner Region.';
        imp = Importance.defaultImportance;
        break;
      case channelIdAnruf:
        chName = 'Eingehende Anrufe';
        chDesc = 'Klingelt und zeigt, wer über sipgate anruft.';
        imp = Importance.max;
        break;
      case channelIdBlitz:
        chName = 'Blitz-Nachrichten';
        chDesc = 'Legt eine eingehende Nachricht sofort auf den Bildschirm.';
        imp = Importance.max;
        break;
      default:
        chName = _channelName;
        chDesc = _channelDescription;
        imp = Importance.high;
    }
    return NotificationDetails(
      android: AndroidNotificationDetails(
        chId,
        chName,
        channelDescription: chDesc,
        importance: imp,
        priority: imp == Importance.max ? Priority.max : Priority.high,
        fullScreenIntent: fullScreenIntent,
        category: fullScreenIntent ? AndroidNotificationCategory.call : null,
        actions: actions,
        playSound: playSound,
        enableVibration: chId != channelIdOpnvStoerung,
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

  /// Deterministic notification ID from payload — same payload = same ID
  /// so a second call for the same event UPDATES the existing notification
  /// instead of stacking a new one. Different payload = different ID, they
  /// coexist. Prevents the previous "2 events in one second overwrite each
  /// other" bug where ID was millisecondsSinceEpoch ~/ 1000.
  ///
  /// Payload null → fallback to timestamp-based ID (old behavior).
  int _notificationIdFor(String? payload) {
    if (payload == null || payload.isEmpty) {
      return DateTime.now().millisecondsSinceEpoch % 0x7FFFFFFF;
    }
    // Simple FNV-1a hash — fast, 32-bit, no crypto lib needed.
    var hash = 0x811c9dc5;
    for (int i = 0; i < payload.length; i++) {
      hash = (hash ^ payload.codeUnitAt(i)) & 0xFFFFFFFF;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash & 0x7FFFFFFF;
  }

  /// Show a native notification on all platforms
  Future<void> show({
    required String title,
    required String body,
    /// Nur für eingehende Anrufe — siehe [_getNotificationDetails].
    bool fullScreenIntent = false,
    List<AndroidNotificationAction>? actions,
    Duration duration = const Duration(seconds: 5),
    Color? backgroundColor,
    IconData? icon,
    VoidCallback? onTap,
    String? payload,
    /// When set, the notification title is prefixed with the weather emoji +
    /// short label for that timestamp (e.g. "🌧 Regen · Neuer Termin"). Falls
    /// back silently if no forecast is available for that time.
    DateTime? eventTime,
    /// Android channel override — one of [channelIdOpnvReminder],
    /// [channelIdOpnvAlarm], [channelIdOpnvStoerung]. Null = default channel.
    /// Chosen channel controls importance + user-facing mute controls.
    String? androidChannelId,
  }) async {
    if (eventTime != null) {
      final hint = WeatherService.instance.weatherHintAt(eventTime);
      if (hint != null) {
        title = '${hint.emoji} ${hint.label} · $title';
      }
    }
    try {
      if (Platform.isMacOS) {
        // macOS: use native UNUserNotificationCenter via MethodChannel
        await _showMacOSNotification(title, body, payload: payload);
      } else {
        // All other platforms: use flutter_local_notifications.
        // ID derived from payload so re-triggers of the same event UPDATE
        // instead of stacking. Prevents duplicate spam when a proximity
        // callback fires 3× per second.
        final id = _notificationIdFor(payload);
        await _notifications.show(
          id: id,
          title: title,
          body: body,
          notificationDetails: _getNotificationDetails(
            payload: payload,
            androidChannelId: androidChannelId,
            fullScreenIntent: fullScreenIntent,
            actions: actions,
          ),
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
      // Personalize title+body per sender so KDE Plasma's notification
      // server doesn't classify them as duplicates and throttle them with
      // org.freedesktop.Notifications.Error.ExcessNotificationGeneration.
      final bodyPreview = message.length > 80 ? '${message.substring(0, 77)}...' : message;
      await show(
        title: '$senderName: neue Nachricht',
        body: bodyPreview.isNotEmpty ? bodyPreview : 'Sie haben eine neue Nachricht erhalten.',
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

  /// Der Blitz auf Android: Vollbild-Schirm mit der Nachricht und einem
  /// Antwortfeld, über jeder anderen App und auch über dem Sperrbildschirm.
  ///
  /// ⚠️ Ob daraus wirklich ein Vollbild wird, entscheidet Android, nicht wir.
  /// `USE_FULL_SCREEN_INTENT` ist bei einer Installation ausserhalb des Play
  /// Store standardmässig erteilt (AOSP: „For all apps being installed on
  /// Android 14, the permission is enabled by default" — es ist der Play
  /// Store, der sie Nicht-Telefonie-Apps wieder entzieht). Der Benutzer kann
  /// sie in den Einstellungen abschalten; dann zeigt Android stillschweigend
  /// einen gewöhnlichen Streifen. Das ist kein Fehlerfall, sondern der
  /// eingebaute Rückfall — deshalb wird hier auch nichts geprüft und nichts
  /// erzwungen.
  Future<void> showBlitzVollbild({
    required String senderName,
    required String message,
    required int conversationId,
    String kanal = 'app',
  }) async {
    final kurz = message.length > 120 ? '${message.substring(0, 117)}...' : message;
    await show(
      title: senderName,
      body: kurz.isNotEmpty ? kurz : 'Neue Nachricht',
      // ⚠️ Der Kanal MUSS mit — ohne `Importance.max` wird der Vollbild-Intent
      // von Android auf einen Streifen zurückgestuft, ohne jede Meldung.
      androidChannelId: channelIdBlitz,
      fullScreenIntent: true,
      payload: 'blitz:$conversationId:$kanal',
    );
    _log.info('Blitz-Vollbild: $senderName (conv=$conversationId)', tag: 'NOTIF');
  }

  /// Show an incoming call notification
  Future<void> showIncomingCall({
    required String callerName,
    int? conversationId,
    /// Vollbild-Anrufbildschirm statt Streifen. Für sipgate-Anrufe auf dem
    /// Tablet: dort liegt das Gerät mit dunklem Bildschirm, und ein Streifen
    /// hinter dem Sperrbildschirm sieht niemand.
    bool vollbild = false,
    /// Knöpfe „Annehmen" / „Ablehnen" direkt in der Benachrichtigung.
    ///
    /// ⚠️ Beide mit `showsUserInterface: true`, und das ist kein Versehen:
    /// annehmen und ablehnen tut der SIP-Stack, und der lebt im Haupt-Isolat.
    /// Ein Knopf ohne Oberfläche landet im Hintergrund-Isolat, wo es diesen
    /// Stack nicht gibt — er täte dann nichts, sichtbar wäre nur, dass die
    /// Benachrichtigung verschwindet. Lieber die App in den Vordergrund holen
    /// und wirklich auflegen.
    bool mitKnoepfen = false,
  }) async {
    await show(
      title: 'Eingehender Anruf',
      body: '$callerName ruft an...',
      payload: 'call:$conversationId',
      androidChannelId: vollbild || mitKnoepfen ? channelIdAnruf : null,
      fullScreenIntent: vollbild,
      actions: !mitKnoepfen || !Platform.isAndroid
          ? null
          : const <AndroidNotificationAction>[
              AndroidNotificationAction(aktionAnnehmen, 'Annehmen',
                  showsUserInterface: true),
              AndroidNotificationAction(aktionAblehnen, 'Ablehnen',
                  showsUserInterface: true),
            ],
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
