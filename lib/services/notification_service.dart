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

  /// Das LAUFENDE Gespräch — ein anderer Kanal als [channelIdAnruf].
  ///
  /// ⚠️ Und zwar zwingend. `channelIdAnruf` steht auf `Importance.max` mit Ton,
  /// weil es dort gerade klingelt. Dieselbe Einstufung für ein Gespräch, das
  /// schon läuft, hiesse: es klingelt ein zweites Mal, mitten im Satz. Ein
  /// Android-Kanal lässt sich nach dem Anlegen nicht mehr leiser stellen —
  /// deshalb von Anfang an ein eigener.
  static const String channelIdGespraech = 'sipgate_gespraech';

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
  static const String aktionAuflegen = 'sipgate_auflegen';

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
    // 4. Eingehende Anrufe (max — es klingelt gerade, das ist der Sinn)
    await impl.createNotificationChannel(const AndroidNotificationChannel(
      channelIdAnruf,
      'Eingehende Anrufe',
      description: 'Klingelt und zeigt, wer über sipgate anruft.',
      importance: Importance.max,
    ));

    // 5. Laufendes Gespräch (low — es soll dastehen, nicht rufen)
    await impl.createNotificationChannel(const AndroidNotificationChannel(
      channelIdGespraech,
      'Laufendes Gespräch',
      description: 'Zeigt ein laufendes Telefonat und den Auflegen-Knopf, '
          'solange die App nicht im Vordergrund ist.',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
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
  /// stand im Manifest, wurde aber nie abgefragt — und weil die App ab Ziel-33
  /// zielt (derzeit `targetSdk = 37`, siehe `android/app/build.gradle.kts`),
  /// zeigt Android den Dialog nicht mehr von selbst (das tat es nur bei Apps
  /// unter Ziel-33, beim ersten Anlegen eines Kanals).
  ///
  /// ⚠️ Die Zahl steht hier als Beleg, nicht als Bedingung: die Aussage haengt
  /// an „>= 33", nicht an einem bestimmten Ziel. Sie stand zweimal als 34 im
  /// Baum, nachdem das Ziel laengst weitergezogen war — wer sie anfasst, prueft
  /// `build.gradle.kts`, statt die Zahl fortzuschreiben.
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
    /// Nicht wegwischbar. Siehe [show].
    bool ongoing = false,
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
      case channelIdGespraech:
        chName = 'Laufendes Gespräch';
        chDesc = 'Zeigt ein laufendes Telefonat und den Auflegen-Knopf, '
            'solange die App nicht im Vordergrund ist.';
        imp = Importance.low;
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
        actions: actions,
        ongoing: ongoing,
        // ⚠️ Ein laufendes Gespräch ist eine Tätigkeit, keine Meldung: Android
        // stellt `category: call` in der Leiste nach oben und behandelt sie im
        // „Nicht stören"-Modus richtig. Der Vollbild-Fall braucht dieselbe
        // Einstufung — deshalb beides hier.
        category: (fullScreenIntent || chId == channelIdGespraech)
            ? AndroidNotificationCategory.call
            : null,
        playSound: playSound && chId != channelIdGespraech,
        enableVibration:
            chId != channelIdOpnvStoerung && chId != channelIdGespraech,
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
    /// Dauerbenachrichtigung: nicht wegwischbar, solange sie steht.
    ///
    /// ⚠️ Nur für etwas, das WIRKLICH läuft und das der Nutzer selbst beenden
    /// kann — sonst ist es eine Meldung, die man nicht loswird. Bei uns genau
    /// ein Fall: das laufende Gespräch, mit „Auflegen" daneben.
    bool ongoing = false,
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
            ongoing: ongoing,
          ),
          payload: payload,
        );
      }

      // 🔴 HIER STAND `'... "$title" - $body'` — der volle Wortlaut JEDER
      // angezeigten Benachrichtigung, also auch jeder Chat-Nachricht eines
      // Mitglieds. `LoggerService` lädt die Protokollzeilen zum Server, und
      // dort lagen sie bis zum 30.08.2026 unter einem Pfad, der über HTTPS
      // ohne Anmeldung abrufbar war. Nur Länge, kein Wortlaut.
      _log.info(
        'Benachrichtigung angezeigt (Titel ${title.length} Z., '
        'Text ${body.length} Z.)',
        tag: 'NOTIF',
      );
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

  /// Die gewöhnliche Chat-Benachrichtigung — bewusst OHNE Namen und OHNE Text.
  ///
  /// 🔴 Bis zum 01.09.2026 stand hier `'$senderName: neue Nachricht'` als Titel
  /// und die ersten 80 Zeichen der Nachricht als Text. Eine Benachrichtigung
  /// liegt auf dem Sperrbildschirm und im Streifen — also unter den Augen von
  /// jedem, der neben dem Tablet steht. Bei einem Behindertenverein ist der
  /// Wortlaut einer Mitgliedsnachricht regelmässig eine Gesundheitsangabe, und
  /// der Name daneben macht sie zuordenbar. Das gehört nicht dorthin.
  ///
  /// ⚠️ Die Sperre sitzt in der METHODE, nicht bei den Aufrufern: ein Aufrufer,
  /// der es künftig vergisst, wäre eine stille Scheibe ins Fenster. Name und
  /// Text werden nicht mehr entgegengenommen — es gibt schlicht keinen
  /// Parameter mehr, über den sie hereinkommen könnten. Ein Test hält das fest.
  ///
  /// ⚠️ Der Blitz ist hiervon NICHT betroffen und wurde bewusst nicht
  /// angefasst ([showBlitzVollbild], [BlitzKarte]). Dort ist das Anzeigen der
  /// Nachricht der Zweck der Sache, und die Karte ist dafür eigens hergerichtet
  /// (Mitgliedsnummer statt Name, Text deckt sich nach kurzem Lesen selbst zu).
  ///
  /// ⚠️ `unreadCount` ist keine Angabe ÜBER ein Mitglied, sondern über den
  /// eigenen Posteingang — er darf deshalb dastehen. Er ersetzt zugleich die
  /// frühere Unterscheidbarkeit nach Absender, die KDE Plasma davon abhielt,
  /// gleichlautende Meldungen als Dubletten zu drosseln
  /// (`org.freedesktop.Notifications.Error.ExcessNotificationGeneration`).
  /// Ob das reicht, ist auf einem Plasma-Rechner nicht nachgemessen; die
  /// Kennung je Unterhaltung unterscheidet die Meldungen ohnehin.
  Future<void> showChatMessage({
    int? conversationId,
    int unreadCount = 1,
  }) async {
    _log.info('Chat-Benachrichtigung (ungelesen=$unreadCount, '
        'chatOffen=$_isChatDialogOpen)',
        tag: 'NOTIF');

    // Nur benachrichtigen wenn Chat-Dialog NICHT geöffnet ist
    if (!_isChatDialogOpen) {
      await show(
        title: 'Neue Nachricht',
        body: unreadCount > 1
            ? 'Sie haben $unreadCount neue Nachrichten von einem Mitglied.'
            : 'Sie haben eine neue Nachricht von einem Mitglied.',
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

  /// Räumt den Blitz-Hinweis für eine Unterhaltung weg.
  ///
  /// ⚠️ WOFÜR: Der Vorsitzende sitzt an mehreren Geräten gleichzeitig. Wer am
  /// Rechner antwortet, hat gelesen — dann darf auf dem Tablet kein Hinweis
  /// mehr stehen. Gemeldet aus dem Betrieb: „warum verschwindet die
  /// Benachrichtigung nicht vom Android, wenn ich am Linux schon geantwortet
  /// habe".
  ///
  /// ⚠️ Es wird KEIN neuer Serverweg dafür gebraucht. Die eigene Antwort
  /// kommt über den WebSocket ohnehin auf allen Geräten des Benutzers an —
  /// nachgemessen am 27.08.2026, Nachricht 29398 traf in derselben Sekunde
  /// auf Linux und Android ein. Bisher hat das dort nur niemand ausgewertet.
  ///
  /// Beide Kanäle wegräumen: welcher es war, weiss der Aufrufer nicht, und
  /// eine Kennung, die auf nichts zeigt, kostet nichts.
  Future<void> blitzWegraeumen(int conversationId) async {
    for (final kanal in const ['app', 'sms']) {
      try {
        await _notifications.cancel(id: _notificationIdFor("blitz:$conversationId:$kanal"));
      } catch (_) {
        // Nicht vorhanden ist der Normalfall, kein Fehler.
      }
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
      // ⚠️ KEINE Zeitschaltung (`timeoutAfter`). Sie stand hier bis zum
      // 27.08.2026 auf zehn Minuten und war der falsche Hebel: gestört hat
      // nie die Dauer, sondern dass der Hinweis noch dastand, wenn die Sache
      // längst erledigt war. Das erledigt jetzt [blitzWegraeumen], sobald ein
      // anderes Gerät gelesen oder geantwortet hat.
      //
      // Eine Zeitschaltung daneben wäre sogar schädlich: wer zwanzig Minuten
      // aus dem Zimmer geht, fände nichts mehr vor — obwohl niemand
      // geantwortet hat und die Nachricht noch offen ist.
      payload: 'blitz:$conversationId:$kanal',
    );
    // ⚠️ Ohne Namen: die Gesprächsnummer genügt, um den Weg zu verfolgen.
      _log.info('Blitz-Vollbild angezeigt (conv=$conversationId)', tag: 'NOTIF');
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

  /// Zeigt das laufende Gespräch, solange die App nicht davor steht.
  ///
  /// ⚠️ WOFÜR — DIE SCHWEBENDE KARTE REICHT NICHT.
  /// [SipgateAnrufOverlay] hängt im Navigator-Overlay dieser App. Wer während
  /// des Gesprächs zum Browser wechselt oder den Bildschirm sperrt, hat weder
  /// Dauer noch Auflegen-Knopf mehr vor sich — und auf Android ist die
  /// Dauerbenachrichtigung die eingeführte Form dafür.
  ///
  /// ⚠️ OHNE UHRZEIT IM TEXT, UND DAS IST ABSICHT. Eine mitlaufende Dauer
  /// müsste im Sekundentakt neu gesetzt werden; das sind rund 3.600
  /// Neuzeichnungen je Stunde Gespräch für eine Zahl, die daneben ohnehin in
  /// der Karte steht. `usesChronometer` wäre der richtige Weg, ist aber in
  /// dieser Plugin-Fassung nicht durchgereicht — also lieber gar keine Zahl
  /// als eine, die stehenbleibt und dabei falsch aussieht.
  Future<void> showOngoingCall({
    required String wer,
    required String zustand,
  }) async {
    await show(
      title: zustand,
      body: wer,
      payload: 'gespraech',
      androidChannelId: channelIdGespraech,
      ongoing: true,
      actions: !Platform.isAndroid
          ? null
          : const <AndroidNotificationAction>[
              // ⚠️ Mit Oberfläche, wie Annehmen/Ablehnen: auflegen tut der
              // SIP-Stack, und der lebt im Haupt-Isolat. Ein Knopf ohne
              // Oberfläche landete im Hintergrund-Isolat, wo es ihn nicht gibt.
              AndroidNotificationAction(aktionAuflegen, 'Auflegen',
                  showsUserInterface: true),
            ],
    );
  }

  Future<void> cancelOngoingCall() async {
    await _notifications.cancel(id: _notificationIdFor('gespraech'));
  }

  /// Nimmt die Anruf-Benachrichtigung zurück.
  ///
  /// ⚠️ DAS GEGENSTÜCK ZU [showIncomingCall] HAT BIS ZUM 30.08.2026 GEFEHLT.
  /// `SipgateService._klingelnBeenden()` stoppte nur den Klingelton — die
  /// Benachrichtigung „`<Name>` ruft an..." blieb stehen: während des
  /// Gesprächs, nach dem Auflegen, bis jemand sie wegwischte. Weil der
  /// Nutzlast-Text `call:null` fest ist, ist auch die Kennung fest, und jeder
  /// neue Anruf ersetzte nur den alten Text. Es stand also dauerhaft jemand
  /// in der Leiste, der angeblich gerade anruft.
  ///
  /// [conversationId] muss derselbe Wert sein wie beim Anzeigen — die Kennung
  /// wird aus der Nutzlast gerechnet. Für sipgate ist das `null`, für die
  /// WebRTC-Gespräche die Gesprächsnummer.
  Future<void> cancelIncomingCall({int? conversationId}) async {
    await _notifications.cancel(id: _notificationIdFor('call:$conversationId'));
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
    _log.error('Fehler-Benachrichtigung angezeigt (${message.length} Z.)',
          tag: 'NOTIF');
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
    // Auch hier kein Wortlaut: `showSuccess` wird mit Texten gerufen, in denen
    // Namen und Vorgänge stehen.
    _log.info(
      'Erfolgsmeldung angezeigt (Titel ${title.length} Z., '
      'Text ${message.length} Z.)',
      tag: 'NOTIF',
    );
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
