import 'dart:async';
import 'package:flutter/material.dart';

import '../services/secure_cloud_service.dart';
import '../widgets/cloud_unlock_dialog.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/api_service.dart';
import '../services/logger_service.dart';
import '../services/chat_service.dart';
import '../services/voice_call_service.dart';
import '../services/heartbeat_service.dart';
import '../services/tray_service.dart';
import '../services/ticket_service.dart';
import '../services/ticket_notification_service.dart';
import '../services/termin_service.dart';
import '../services/routine_service.dart';
import '../services/notification_service.dart';
import '../services/weather_service.dart';
import '../services/transit_service.dart';
import '../services/transit_disruptions_service.dart';
import '../services/transit_termin_reminder_service.dart';
import '../services/anruf_gateway_service.dart';
import '../services/termin_sms_gateway_service.dart';
import '../widgets/opnv_dialog.dart';
import '../services/news_service.dart';
import '../services/radio_service.dart';
import '../services/sipgate_service.dart';
import '../widgets/sipgate_anruf_overlay.dart';
import '../services/ntfy_service.dart';
import '../services/diagnostic_service.dart';
import '../services/update_service.dart';
import '../widgets/login_approval_dialog.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/eastern.dart';
import '../models/user.dart';
import '../models/member_activity.dart';
import '../widgets/legal_footer.dart';
import '../widgets/trial_warning_banner.dart';
import '../widgets/admin_chat_dialog.dart';
import '../widgets/chat_bubble_overlay.dart';
import '../widgets/weather_widget.dart';
import '../services/weather_auto_broadcast_service.dart';
import '../widgets/sturmwarnung_broadcast_dialog.dart';
import '../services/global_chat_service.dart';
import '../widgets/update_dialog.dart';
import '../widgets/incoming_call_dialog.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/moon.dart';
import 'login_screen.dart';
import 'secure_cloud_screen.dart';
import 'remote_desktop_screen.dart';
import 'mail_screen.dart';
import 'tv_screen.dart';
import 'eigene_unterschriften_screen.dart';
import 'sipgate_fax_screen.dart';
import '../services/fax_badge_service.dart';
import 'post_screen.dart';
import 'sipgate_screen.dart';
import 'speedtest_screen.dart';
import 'website_screen.dart';
import 'terminverwaltung_screen.dart';
import '../services/youtube_service.dart';
import '../services/mail_badge_service.dart';
import '../services/speedtest_service.dart';
import '../widgets/profile_dialog.dart';
import '../utils/familie_selector_dialog.dart';
import '../widgets/dashboard_sidebar.dart';
import '../widgets/user_data_table.dart';
import '../widgets/confirm_dialogs.dart';
import '../utils/role_helpers.dart';
import 'ticketverwaltung_screen.dart';
import 'vereinverwaltung_screen.dart';
import 'netzwerk_screen.dart';
import 'finanzverwaltung_screen.dart';
import 'statistik_screen.dart';
import 'archiv_screen.dart';
import 'dienste_screen.dart';
import 'routinenaufgaben_screen.dart';
import 'arbeitsbereich_screen.dart';
import 'bug_reports_screen.dart';
import 'pending_parent_consent_screen.dart';
import 'einstellungen_screen.dart';
import '../widgets/faltbare_kopfleiste.dart';
import '../widgets/theme_umschalter.dart';
import '../services/theme_service.dart';
import '../utils/app_farben.dart';

final _log = LoggerService();

class DashboardScreen extends StatefulWidget {
  final String userName;
  final String currentMitgliedernummer;
  final String currentEmail;
  final String currentRole;

  const DashboardScreen({
    super.key,
    required this.userName,
    required this.currentMitgliedernummer,
    required this.currentEmail,
    required this.currentRole,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  final _apiService = ApiService();
  final _chatService = ChatService();
  late final _heartbeatService = HeartbeatService(_apiService);
  final _ticketNotificationService = TicketNotificationService();
  List<User> _users = [];
  bool _isLoading = true;
  String? _errorMessage;
  late String _currentEmail;
  String _memberSearchQuery = '';
  bool _dashboardRevealed = false;
  final _memberSearchController = TextEditingController();

  // Sidebar navigation
  int _selectedMenuIndex = 0;

  // Deep-link focus IDs — set când Arbeitswochen navighează prin tap pe title;
  // target screen le consumă în initState + apelează onFocusConsumed → clear.
  int? _pendingFocusTicketId;
  int? _pendingFocusTerminId;
  int? _pendingFocusRoutineExecutionId;

  // Unread chat messages counter
  int _unreadChatCount = 0;
  StreamSubscription<ChatMessage>? _messageSubscription;
  StreamSubscription<CallOfferEvent>? _callOfferSubscription;
  StreamSubscription<TicketNotificationEvent>? _ticketNotificationSubscription;
  StreamSubscription<String>? _notificationClickSubscription;
  StreamSubscription<Map<String, dynamic>>? _loginApprovalSubscription;

  // Pending incoming call (when AdminChatDialog is not open)
  CallOfferEvent? _pendingCall;
  bool _isAdminChatOpen = false;

  // Auto-refresh timer for tickets
  Timer? _ticketRefreshTimer;

  // Auto-update timer (every 60 seconds)
  Timer? _autoUpdateTimer;

  /// Abstand zwischen zwei Update-Prüfungen.
  ///
  /// ⚠️ Stand auf 60 Sekunden — 1.440 Anfragen am Tag an GitHub, für eine
  /// Datei, die sich an einem geschäftigen Tag ein halbes Dutzend Mal ändert.
  /// Und teurer als sie aussieht: github.com ist ein fremder Wirt, jede Prüfung
  /// braucht einen eigenen TLS-Handschlag, während die Anfragen an den
  /// Vereinsserver auf einer stehenden Verbindung reisen.
  ///
  /// ⚠️ Diese Last war in allen bisherigen Messungen UNSICHTBAR: das
  /// nginx-Protokoll des Vereinsservers sieht nur, was an ihn geht. Alles, was
  /// die App an GitHub, efa-bw, open-meteo oder tagesschau schickt, taucht dort
  /// nicht auf.
  ///
  /// Eine Viertelstunde statt einer Minute: 96 % weniger, und ein Release ist
  /// spätestens nach fünfzehn Minuten auf dem Gerät. Sofort geht weiterhin über
  /// den Knopf im Fußbereich.
  static const Duration _kUpdateTakt = Duration(minutes: 15);

  // Payment reminder
  Timer? _paymentReminderTimer;
  bool _paymentReminderShownToday = false;

  // Weather
  final _weatherService = WeatherService();
  WeatherData? _weatherData;
  List<WeatherAlert> _weatherAlerts = [];
  List<HealthAlert> _healthAlerts = [];

  // Testphase (nur für Konten mit Status 'neu'). Ohne Vorwarnung wurde das
  // Konto bisher stillschweigend von auto_suspend.php gesperrt.
  bool _isTrialAccount = false;
  int _trialDaysRemaining = 0;
  DateTime? _trialEndsAt;

  // Transit (DING EFA)
  final _transitService = TransitService();
  final _disruptionsService = TransitDisruptionsService();
  List<Departure> _departures = [];

  // News (Tagesschau RSS)
  final _newsService = NewsService();

  // Radio (HR Info live stream)
  final _radioService = RadioService();
  bool _radioPlaying = false;

  // Background conversation IDs for receiving messages
  List<int> _backgroundConversationIds = [];

  // Floating chat bubbles: unread messages grouped per conversation.
  // Populated by the messageStream listener; cleared when the user opens
  // that conversation in the admin chat dialog.
  final Map<int, ChatBubbleEntry> _chatBubbles = {};

  // Ticket management
  final _ticketService = TicketService();
  List<Ticket> _tickets = [];
  TicketStats? _ticketStats;
  bool _isLoadingTickets = false;
  String _ticketFilter = 'all'; // all, open, in_progress, closed

  // Per-member "Diese Woche" activity indicators (Termin / Ticket / Routine)
  final _terminService = TerminService();
  final _routineService = RoutineService();
  Map<String, MemberActivity> _memberActivity = {};

  // Applicants with at least one Stufe awaiting this Vorstand's vote.
  // Populated from /api/admin/list_pending_my_vote.php on dashboard load.
  // Feeds the "Mein Vote" FAB inside Mitgliederverwaltung.
  List<Map<String, dynamic>> _pendingMyVote = [];

  // Weekly time tracking
  WeeklyTimeSummary? _weeklyTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Cloud-Passphrase einmal pro App-Start abfragen. Ohne offene Sitzung kann
    // die App Mail-Anhänge nicht automatisch verschlüsselt ablegen.
    _scheduleCloudUnlock();

    // Start periodic log upload to server (every 30s)
    _log.startUpload(widget.currentMitgliedernummer);

    // Warnung anzeigen, solange die Testphase des Kontos noch läuft.
    _loadTrialStatus();

    // Activate the global Messenger-style chat overlay (bubbles + mini
    // panels visible across every page). Provides mitgliedernummer for the
    // overlay so mini panels can send/receive without dashboard context.
    GlobalChatService()
      ..currentMitgliedernummer = widget.currentMitgliedernummer
      ..enabled = true
      ..start();

    _currentEmail = widget.currentEmail;
    // Badge only — one request; the actual feed polling runs server-side.
    YoutubeService().refreshBadge();
    // Dito fürs Postfach — eine Anfrage nach den Ordnerzählern, danach nur
    // noch alle fünf Minuten (siehe MailBadgeService.taktweite).
    MailBadgeService()
      ..refreshBadge()
      ..start();
    // Und fürs Fax. Eingehende Faxe holt ein Cron alle fünf Minuten ab und
    // meldet sie per ntfy — wer die Meldung wegwischt, erfuhr davon in der App
    // bislang gar nichts.
    FaxBadgeService()
      ..aktualisieren()
      ..start();

    // sipgate: registriert NUR, wenn der Schalter im Bildschirm an ist —
    // Standard ist aus, wie die Automatik beim Speedtest. Eine dauerhaft
    // offene Verbindung schaltet man selbst ein.
    //
    // ⚠️ Hier, im Haupt-Isolat. `sip_ua` scheitert in einem
    // Hintergrund-Isolat (PlatformException bei der Activity-Registrierung),
    // und `flutter_foreground_task` fährt grundsätzlich ein eigenes — der
    // Vordergrunddienst kann den Stack also nicht beherbergen, nur den
    // Prozess am Leben halten.
    SipgateService().beimStart();

    // Die schwebende Gesprächskarte, sichtbar über jedem Bildschirm. Ohne sie
    // verliert man bei einem Wechsel in eine Behördenkarte — also genau dort,
    // wofür man anruft — Dauer und Auflegen-Knopf aus den Augen, und ein
    // eingehender Anruf bliebe unbemerkt.
    SipgateAnrufOverlay().aktivieren();
    _loadUsers();
    _loadTickets();
    _loadWeeklyTime();
    _connectWebSocket();
    _setupMessageListener();
    _setupTicketNotificationListener();
    _setupNotificationClickListener();
    // Auto-refresh disabled — was hitting /api every 30s on the Ticketverwaltung
    // tab, which made the list jump and felt noisy. Tickets now refresh via:
    //   • WebSocket push on server-side change (ChatService stream)
    //   • The TicketNotificationService poll (already running below)
    //   • Pull-to-refresh on the list
    //   • Explicit _loadTickets() after a Vorstand action (create/edit/close)
    // The `_ticketRefreshTimer` field + cancel calls in dispose / lifecycle
    // are left intact in case we want to re-enable a slower cadence later.
    // Start heartbeat to update last_seen in real-time
    _heartbeatService.start(widget.currentMitgliedernummer);
    // Start ticket notification polling - WebSocket not working reliably
    _ticketNotificationService.start(widget.currentMitgliedernummer);
    // Start ntfy push notification listener
    NtfyService().start(widget.currentMitgliedernummer, jwtToken: _apiService.token);
    // Start login approval polling + WebSocket listener
    LoginApprovalOverlay().startPolling();
    _loginApprovalSubscription = _chatService.loginApprovalStream.listen((data) {
      LoginApprovalOverlay().onNewRequest(data);
      if (mounted) LoginApprovalOverlay.show(context);
    });
    // Set diagnostic service user info
    DiagnosticService().setUser(widget.currentMitgliedernummer, widget.currentRole);
    // Check for updates and push logs after widget is built
    // Start weather service (uses city from user profile)
    _startWeatherService();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await checkAndShowUpdateDialog(context);
      // Push logs to server after login
      _log.pushToServer(widget.currentMitgliedernummer);
      // Check payment reminder
      _checkPaymentReminder();
    });
    _autoUpdateTimer = Timer.periodic(_kUpdateTakt, (_) => _autoUpdateCheck());
    // Check payment reminder every hour
    _paymentReminderTimer = Timer.periodic(const Duration(hours: 1), (_) => _checkPaymentReminder());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // App goes to background: pause UI-only timers to save battery
      // DO NOT stop: WebSocket, ntfy, heartbeat (notifications must work!)
      _ticketRefreshTimer?.cancel();
      _paymentReminderTimer?.cancel();
      _autoUpdateTimer?.cancel();
      // Die Anmelde-Anfragen ebenfalls: sie sind eine Überlagerung auf dem
      // Bildschirm, und den sieht gerade niemand. Es geht dabei nichts
      // verloren — kommt eine Anfrage herein, meldet sie der WebSocket über
      // `loginApprovalStream` samt Benachrichtigung, und beim Aufwachen wird
      // ohnehin sofort neu abgefragt.
      LoginApprovalOverlay().stopPolling();
      // Und die Ortung. Beide Ströme liefen bisher weiter, während der
      // Bildschirm aus war — der des ÖPNV mit `LocationAccuracy.high` alle 15
      // Sekunden, also mit dauernd eingeschaltetem Satellitenempfänger, für
      // eine Abfahrtstafel, die in der Hosentasche niemand ansieht.
      //
      // Der Ausstieg-Alarm ist davon nicht betroffen: der hat einen eigenen
      // Strom mit eigener Dauerbenachrichtigung und soll gerade dann laufen.
      // Die Wetterabrufe laufen ebenfalls weiter, nur ohne Ortung — an ihnen
      // hängen die Unwetterwarnungen.
      _transitService.pausieren();
      _weatherService.ortungPausieren();
      debugPrint('[Dashboard] App paused - UI timers + Ortung gestoppt');
    } else if (state == AppLifecycleState.resumed) {
      _loadUsers();
      _autoUpdateCheck();
      _autoUpdateTimer = Timer.periodic(_kUpdateTakt, (_) => _autoUpdateCheck());
      // startPolling() fragt selbst sofort ab — eine Anfrage, die während der
      // Pause eingegangen ist, steht also da, sobald der Bildschirm angeht.
      LoginApprovalOverlay().startPolling();
      // fortsetzen() ruft die Abfahrten sofort ab: wer die App aufklappt, will
      // die Tafel von jetzt sehen, nicht die von vor einer Stunde.
      _transitService.fortsetzen();
      _weatherService.ortungFortsetzen();
      // Re-scan termine on resume — critical if user opens the app in the
      // morning and a termin bus leaves in <3h.
      TransitTerminReminderService.checkUpcoming();
      // Offene SMS-Erinnerungen nachholen: der Cron reiht um 9 Uhr ein, und
      // beim Aufwecken ist das Tablet sicher online.
      TerminSmsGatewayService.runOnce();
      // Und der Wählauftrag, der eingegangen ist, während das Telefon in der
      // Tasche lag. Er gilt nur zwei Minuten — beim Aufwecken ist er meistens
      // schon verfallen, aber genau dann soll er es auch sein.
      AnrufGatewayService.runOnce();
      // The TV badge is set server-side by the cron, so it can only appear
      // while we were away.
      YoutubeService().refreshBadge();
      // Post kommt genauso an, während das Telefon in der Tasche liegt.
      MailBadgeService().refreshBadge();
      // Ein Fax kommt genauso an, während das Telefon in der Tasche liegt.
      FaxBadgeService().aktualisieren();
      debugPrint('[Dashboard] App resumed - data refreshed, update check restarted');
    } else if (state == AppLifecycleState.detached) {
      // Die App wird beendet: den Cloud-Schlüssel aus dem Speicher werfen und
      // das Resume-Token löschen, damit sich beim nächsten Start nichts still
      // von selbst wieder entsperrt. Danach ist wieder die Passphrase fällig.
      SecureCloudService(_apiService, widget.currentMitgliedernummer).lock();
      debugPrint('[Dashboard] App detached - secure cloud locked');
    }
  }

  /// Einmal pro App-Start nach der Cloud-Passphrase fragen.
  ///
  /// Erst nach dem ersten Frame, damit der Dialog einen fertigen Navigator
  /// vorfindet, und still übersprungen, wenn gar keine Cloud eingerichtet ist.
  void _scheduleCloudUnlock() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await CloudUnlockDialog.ensureUnlocked(
          context, _apiService, widget.currentMitgliedernummer);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _log.stopUpload(); // Stop periodic log upload
    _messageSubscription?.cancel();
    _callOfferSubscription?.cancel();
    _ticketNotificationSubscription?.cancel();
    _notificationClickSubscription?.cancel();
    _loginApprovalSubscription?.cancel();
    LoginApprovalOverlay().stopPolling();
    _ticketRefreshTimer?.cancel();
    _heartbeatService.stop();
    _ticketNotificationService.stop();
    NtfyService().stop();
    _paymentReminderTimer?.cancel();
    _autoUpdateTimer?.cancel();
    _weatherService.stop();
    _transitService.stop();
    _disruptionsService.removeListener(_onDisruptionsChanged);
    _disruptionsService.stop();
    _newsService.stop();
    MailBadgeService().stop();
    FaxBadgeService().stop();
    _radioService.dispose();
    super.dispose();
  }

  bool _autoUpdating = false;
  Future<void> _autoUpdateCheck() async {
    if (_autoUpdating) return;
    try {
      final updateService = UpdateService();
      final info = await updateService.checkForUpdate();
      if (info != null && mounted) {
        _autoUpdating = true;
        _log.info('Auto-update: v${info.version} (build ${info.buildNumber}) available, downloading...', tag: 'AUTO-UPDATE');
        final path = await updateService.downloadUpdate(info, (p) {});
        if (path != null && mounted) {
          _log.info('Auto-update: downloaded, installing...', tag: 'AUTO-UPDATE');
          await updateService.launchInstaller(path);
        }
        _autoUpdating = false;
      }
    } catch (e) {
      _autoUpdating = false;
      debugPrint('[AUTO-UPDATE] error: $e');
    }
  }

  void _setupMessageListener() {
    // Listen for new messages at dashboard level for badge updates
    _messageSubscription = _chatService.messageStream.listen((message) {
      if (!mounted) return;
      // Skip our own messages — don't bubble our own outbound sends.
      // Match ChatService.isOwnMessage logic: prefer senderId because
      // widget.userName can be empty when the dashboard mounts before the
      // WebSocket handshake stores the user name.
      final myId = _chatService.currentUserId;
      final isOwnMessage = (myId != null && message.senderId == myId) ||
          (widget.userName.isNotEmpty && message.senderName == widget.userName);
      if (isOwnMessage) return;
      // Skip if the admin chat dialog is already open — user is actively
      // reading there. Bumping the badge would leave it stuck > 0 after
      // the user closes the dialog ("dialog says 0 unread, icon says unread").
      if (_isAdminChatOpen) return;
      setState(() {
        _unreadChatCount++;
        final existing = _chatBubbles[message.conversationId];
        _chatBubbles[message.conversationId] = ChatBubbleEntry(
          conversationId: message.conversationId,
          senderName: message.senderName,
          unreadCount: (existing?.unreadCount ?? 0) + 1,
          lastMessagePreview: message.message.length > 80
              ? '${message.message.substring(0, 80)}…'
              : message.message,
        );
      });
      _log.info(
        'New message from ${message.senderName} (conv ${message.conversationId}), unread total: $_unreadChatCount',
        tag: 'DASH',
      );
    });

    // Listen for incoming calls at dashboard level
    _callOfferSubscription = _chatService.callOfferStream.listen((event) {
      if (mounted && !_isAdminChatOpen) {
        _handleIncomingCall(event);
      }
    });
  }

  void _handleIncomingCall(CallOfferEvent event) {
    _log.info('Incoming call from ${event.callerName} (conv: ${event.conversationId})', tag: 'DASH');
    _pendingCall = event;

    // Show incoming call dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => IncomingCallDialog(
        callerName: event.callerName,
        isVideo: VoiceCallService().offerSendsVideo(event.sdp),
        onAccept: () {
          Navigator.of(ctx).pop();
          // Open AdminChatDialog with pending call
          _showAdminChatDialogWithCall();
        },
        onReject: () {
          Navigator.of(ctx).pop();
          // Reject the call
          _chatService.sendCallReject(event.conversationId, 'rejected');
          _pendingCall = null;
        },
      ),
    );
  }

  void _setupTicketNotificationListener() {
    // Listen for ticket notifications via WebSocket
    _ticketNotificationSubscription = _chatService.ticketNotificationStream.listen((event) {
      _log.info('Ticket notification received: ${event.title}', tag: 'TICKET');

      // Auto-refresh ticket list when notification arrives
      if (mounted) {
        _loadTickets();
      }
    });
  }

  void _setupNotificationClickListener() {
    _notificationClickSubscription = NotificationService().onNotificationClicked.listen((payload) {
      if (!mounted) return;
      _log.info('Notification clicked with payload: $payload', tag: 'DASH');

      // Parse payload format: 'type:data[:extra]'
      final parts = payload.split(':');
      final type = parts.isNotEmpty ? parts[0] : '';
      final data = parts.length > 1 ? parts[1] : '';

      if (type == 'chat' && !_isAdminChatOpen) {
        _showAdminChatDialog();
      } else if (type == 'termin') {
        // Reminder termin → deschide ÖPNV cu deep-link (Verein → termin loc,
        // ArrivalTime = terminDate). Route se caută auto-la open.
        _openTerminOpnvDeepLink(data);
      } else if (type == 'opnv') {
        // 'opnv:ausstieg:X' sau 'opnv:reminder:X' — deschide dialogul simplu.
        _showTransitDialog();
      } else if (type == 'grippe') {
        // Doar deschide dialogul cu Störungen — userul poate vedea contextul.
        _showTransitDialog();
      }
    });
  }

  /// Fetch termin details by ID → găsește locația → deschide OpnvDialog cu
  /// initialFrom = Verein-Adresse, initialTo = termin location, arrivalTime.
  Future<void> _openTerminOpnvDeepLink(String terminId) async {
    if (terminId.isEmpty) return;
    try {
      final res = await _terminService.getMyTermine(filter: 'upcoming');
      if (res['success'] != true) return;
      final list = (res['termine'] as List?) ?? [];
      Map<String, dynamic>? termin;
      for (final raw in list) {
        if (raw is Map && raw['id']?.toString() == terminId) {
          termin = Map<String, dynamic>.from(raw);
          break;
        }
      }
      if (termin == null || !mounted) return;
      final location = (termin['location'] ?? termin['ort'])?.toString() ?? '';
      final dateStr = (termin['termin_date'] ?? termin['date'])?.toString() ?? '';
      final arrivalTime = DateTime.tryParse(dateStr);
      if (location.isEmpty) {
        _showTransitDialog();
        return;
      }
      // Verein-Adresse ca point de plecare (best-effort — pentru 24h reminder
      // e cel mai des utilizat sursa).
      const vereinAddr = 'ICD360S e.V., Neu-Ulm';
      showDialog(
        context: context,
        builder: (ctx) => OpnvDialog(
          transitService: _transitService,
          initialDepartures: _departures,
          city: _weatherData?.city ?? '',
          currentMitgliedernummer: widget.currentMitgliedernummer,
          users: _users,
          initialFrom: TransitLocation(id: vereinAddr, name: vereinAddr),
          initialTo: TransitLocation(id: location, name: location),
          initialArrivalTime: arrivalTime,
        ),
      );
    } catch (e) {
      _log.debug('Termin deep-link failed: $e', tag: 'DASH');
    }
  }

  Future<void> _connectWebSocket() async {
    // Connect to WebSocket for background notifications
    final connected = await _chatService.connect(widget.currentMitgliedernummer, userName: widget.userName);
    _log.info('WebSocket connected at login: $connected', tag: 'DASH');
    // Clear tray unread count when user is active
    TrayService().clearUnread();

    // Auto-join all conversations to receive messages even when chat dialog is closed
    if (connected) {
      await _joinBackgroundConversations();
    }
  }

  Future<void> _joinBackgroundConversations() async {
    try {
      // Get all conversations for admin
      final result = await _apiService.getChatConversations(widget.currentMitgliedernummer);
      if (result['success'] == true) {
        final conversations = List<Map<String, dynamic>>.from(result['conversations'] ?? []);
        _backgroundConversationIds = [];
        int totalUnread = 0;
        for (final conv in conversations) {
          final status = conv['status'] ?? 'open';
          if (status == 'open') {
            final convId = conv['id'];
            final id = convId is int ? convId : int.tryParse(convId.toString());
            if (id != null) {
              _backgroundConversationIds.add(id);
              _chatService.joinConversation(id);

              // Check for unread messages and send push notification
              final unreadCount = conv['unread_count'] ?? 0;
              if (unreadCount > 0) {
                totalUnread += unreadCount as int;
                final memberName = conv['member_name'] ?? 'Unbekannt';
                final lastMessage = conv['last_message'] ?? '';
                final msgPreview = lastMessage.length > 80
                    ? '${lastMessage.substring(0, 80)}...'
                    : lastMessage;

                NotificationService().showChatMessage(
                  senderName: memberName,
                  message: unreadCount == 1
                      ? msgPreview
                      : '$unreadCount ungelesene Nachrichten: $msgPreview',
                  conversationId: id,
                );

                _chatBubbles[id] = ChatBubbleEntry(
                  conversationId: id,
                  senderName: memberName,
                  unreadCount: unreadCount,
                  lastMessagePreview: msgPreview,
                );
                // Mirror into the global Messenger-style overlay so the
                // bubble appears on every page, not just dashboard.
                GlobalChatService().upsertBubble(
                  conversationId: id,
                  senderName: memberName,
                  unreadCount: unreadCount,
                  lastMessagePreview: msgPreview,
                );
              }
            }
          }
        }
        if (mounted && (totalUnread > 0 || _chatBubbles.isNotEmpty)) {
          setState(() {
            _unreadChatCount = totalUnread;
          });
        }
        _log.info('Background joined ${_backgroundConversationIds.length} conversations, $totalUnread unread', tag: 'DASH');
      }
    } catch (e) {
      _log.error('Failed to join background conversations: $e', tag: 'DASH');
    }
  }

  Future<void> _checkPaymentReminder() async {
    if (_paymentReminderShownToday) return;
    try {
      final result = await _apiService.getProfile(widget.currentMitgliedernummer);
      if (result['success'] != true) return;
      final zahlungstag = result['zahlungstag'] != null
          ? int.tryParse(result['zahlungstag'].toString())
          : null;
      if (zahlungstag == null) return;
      final now = DateTime.now();
      if (now.day == zahlungstag) {
        _paymentReminderShownToday = true;
        final zahlungsmethode = result['zahlungsmethode']?.toString() ?? 'Überweisung';
        final methodLabel = {
          'ueberweisung': 'Überweisung',
          'sepa_lastschrift': 'SEPA-Lastschrift',
          'dauerauftrag': 'Dauerauftrag',
        }[zahlungsmethode] ?? zahlungsmethode;
        await NotificationService().show(
          title: 'Zahlungserinnerung',
          body: 'Heute ist der $zahlungstag. - bitte $methodLabel durchführen.',
          payload: 'payment',
        );
        _log.info('Payment reminder shown for day $zahlungstag', tag: 'DASH');
      }
    } catch (e) {
      _log.error('Payment reminder check failed: $e', tag: 'DASH');
    }
  }

  /// Holt den Kontostatus, damit ein Konto in der Testphase gewarnt wird,
  /// bevor auto_suspend.php es sperrt. Für verifizierte Konten ('active')
  /// liefert der Endpunkt is_trial_active=false und es wird nichts angezeigt.
  Future<void> _loadTrialStatus() async {
    try {
      final result = await _apiService.getAccountStatus(widget.currentMitgliedernummer);
      if (result['success'] != true || !mounted) return;

      setState(() {
        _isTrialAccount = result['is_trial_active'] == true;
        _trialDaysRemaining = result['days_remaining'] ?? 0;
        _trialEndsAt = DateTime.tryParse(result['trial_ends_at']?.toString() ?? '');
      });
    } catch (e) {
      _log.error('Failed to load trial status: $e', tag: 'DASH');
    }
  }

  Future<void> _startWeatherService() async {
    try {
      final result = await _apiService.getProfile(widget.currentMitgliedernummer);
      if (result['success'] == true) {
        final ort = result['ort']?.toString() ?? '';

        // Setup callbacks
        _weatherService.onWeatherUpdate = (weather) {
          if (mounted) setState(() => _weatherData = weather);
        };
        _weatherService.onAlertsUpdate = (alerts) {
          if (mounted) setState(() => _weatherAlerts = alerts);
        };
        _weatherService.onHealthAlertsUpdate = (health) {
          if (mounted) setState(() => _healthAlerts = health);
        };
        _transitService.onDeparturesUpdate = (deps) {
          if (mounted) setState(() => _departures = deps);
        };

        // When transit detects a new city (GPS moved >2km), update weather + news
        _transitService.onLocationChanged = (lat, lon, city) async {
          _log.info('Dashboard: Location changed → $city ($lat, $lon)', tag: 'WEATHER');
          await _weatherService.updateLocation(city, lat: lat, lon: lon);
          await _newsService.start(lat: lat, lon: lon);
          // GPS-city changed → recompute Störungen region filter.
          _publishRegionTokens();
        };

        // Start transit first (it gets GPS) then share coordinates with weather
        await _transitService.start(ort);

        // Start disruption polling (15 min interval, badge on bus icon)
        _disruptionsService.start();
        _disruptionsService.addListener(_onDisruptionsChanged);
        // First region-token publish now that GPS + provider are ready.
        // (_users may still be loading — _loadUsers() calls again when ready.)
        _publishRegionTokens();

        // Scan upcoming termine (next 24h) and surface a local notification
        // for any whose ÖPNV departure is within the next 3 hours and hasn't
        // been reminded today. Fire-and-forget; failures logged inside.
        TransitTerminReminderService.checkUpcoming();

        // SMS-Gateway: den WorkManager-Job anmelden (nur auf dem Tablet, das
        // in den Einstellungen dafür markiert ist) und die Warteschlange
        // gleich einmal leeren — der Hintergrundjob läuft frühestens in 30
        // Minuten, offene Erinnerungen sollen aber sofort rausgehen.
        TerminSmsGatewayService.initialize().then((_) {
          TerminSmsGatewayService.runOnce();
          // Muss NACH initialize() laufen: auf Android registriert die den
          // WorkManager, ohne den sich kein periodischer Job anmelden lässt.
          // Aber ausdrücklich HIER und nicht dort drin — initialize() kehrt
          // auf Nicht-Android sofort zurück, und der Speedtest-Takt kam auf
          // Desktop dadurch nie in Gang.
          SpeedtestService.jobNachziehen();
        });

        // Anruf-Gateway: den Takt im laufenden Prozess anwerfen, falls dieses
        // Gerät das Telefon mit der SIM ist. Der Wachdienst deckt die
        // geschlossene App ab, dieser Timer die offene — bei offener App
        // feuert `resumed` nie, und genau dann steht das Gerät oft stundenlang
        // sichtbar da.
        AnrufGatewayService.isEnabled().then((an) async {
          if (!an) return;
          AnrufGatewayService.starteVordergrundTakt();

          // ⚠️ Ohne das bleibt ein einmal eingeschaltetes Gateway für immer
          // stumm. Gefragt wurde bisher nur beim UMLEGEN des Schalters — wer
          // ihn vor dem Update angeschaltet hat, wird also nie gefragt, und
          // jeder Klick vom Rechner endet in einer Benachrichtigung. Genau
          // das ist in Produktion passiert.
          //
          // Der Dialog geht nur bei offener App auf, und hier ist sie offen.
          // Zeigt Android ihn nicht mehr („Nicht mehr fragen"), kehrt der
          // Aufruf sofort zurück — er kann also nicht nerven.
          final caps = await AnrufGatewayService.faehigkeiten();
          if (caps.telefonie && !caps.anrufrecht) {
            await AnrufGatewayService.anrufrechtAnfragen();
          }
        });

        // Use GPS coordinates from transit if available, else city fallback.
        // followGps: true → re-reads device GPS every 15 min and updates city on movement >5km.
        if (_transitService.latitude != null && _transitService.longitude != null) {
          final cityName = _transitService.gpsCity ?? ort;
          await _weatherService.start(
            cityName.isNotEmpty ? cityName : 'Mein Standort',
            lat: _transitService.latitude,
            lon: _transitService.longitude,
            followGps: true,
          );
        } else if (ort.isNotEmpty) {
          await _weatherService.start(ort, followGps: true);
        } else {
          _log.info('Weather: No location available', tag: 'WEATHER');
        }

        // Start news service with GPS coordinates
        _newsService.onNewsUpdate = () {
          if (mounted) setState(() {});
        };
        if (_transitService.latitude != null && _transitService.longitude != null) {
          await _newsService.start(
            lat: _transitService.latitude,
            lon: _transitService.longitude,
          );
        } else {
          await _newsService.start();
        }
      }
    } catch (e) {
      _log.error('Weather: Failed to start: $e', tag: 'WEATHER');
    }
  }


  // ── News Dialog ────────────────────────────────────────────

  void _showNewsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _NewsDialog(newsService: _newsService),
    );
  }

  // ── Transit Dialog ──────────────────────────────────────────

  void _onDisruptionsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  /// Publish the logged-in user's region tokens to TransitDisruptionsService.
  /// Sources (union — the more, the better the match rate):
  ///   1. Verifizierung Stufe 1 = user profile from Mitgliederverwaltung
  ///      (User.ort / User.bundesland / User.plz first 2 digits as region hint).
  ///   2. GPS-detected city (TransitService.gpsCity).
  ///   3. Active transit provider display name (e.g. "DING", "VBB", "VRR").
  ///
  /// If none of these are resolved yet, the set stays empty and the service
  /// falls back to nationwide display (fail-open — better false positives
  /// than a silent zero when data is missing).
  void _publishRegionTokens() {
    final tokens = <String>{};
    // (1) My own Stufe-1 profile.
    User? me;
    try {
      me = _users.firstWhere(
        (u) => u.mitgliedernummer == widget.currentMitgliedernummer,
      );
    } catch (_) {}
    if (me != null) {
      if (me.ort != null && me.ort!.trim().isNotEmpty) tokens.add(me.ort!.trim());
      if (me.bundesland != null && me.bundesland!.trim().isNotEmpty) tokens.add(me.bundesland!.trim());
      // If the city contains a hyphen ("Neu-Ulm" → also match "Ulm"),
      // add each hyphen-split segment as its own token — many HIM messages
      // only mention the base name.
      final ort = me.ort?.trim() ?? '';
      if (ort.contains('-')) {
        for (final part in ort.split('-')) {
          if (part.trim().length >= 3) tokens.add(part.trim());
        }
      }
    }
    // (2) GPS-detected city.
    final gpsCity = _transitService.gpsCity;
    if (gpsCity != null && gpsCity.isNotEmpty) tokens.add(gpsCity);
    // (3) Active provider name.
    final provider = _transitService.activeProvider;
    if (provider != null) {
      tokens.add(provider.name);
      // Also add the human-readable "displayName" — often "Verkehrsverbund X"
      // which the HIM feed likes to name-drop in text.
      // Some configs have both; both are pushed.
      tokens.add(provider.displayName);
    }
    _disruptionsService.setRegionTokens(tokens);

    // Also publish Stufe-1 address to TransitService pentru:
    //   • Filtrare providers la autocomplete (nu mai spam-uim 23 provideri)
    //   • Fallback când GPS-ul e off (activeProvider derived from PLZ prefix)
    if (me != null) {
      _transitService.setMemberHomeRegion(
        ort: me.ort,
        plz: me.plz,
        bundesland: me.bundesland,
      );
    }
  }

  void _showTransitDialog() {
    // Look up the logged-in user's muttersprache from the roster so TripMap
    // TTS can announce in both German + the user's native language.
    User? me;
    try {
      me = _users.firstWhere((u) => u.mitgliedernummer == widget.currentMitgliedernummer);
    } catch (_) {}
    showDialog(
      context: context,
      builder: (ctx) => OpnvDialog(
        transitService: _transitService,
        initialDepartures: _departures,
        city: _weatherData?.city ?? '',
        currentMitgliedernummer: widget.currentMitgliedernummer,
        users: _users,
        userMuttersprache: me?.muttersprache,
      ),
    );
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _apiService.getUsers();

      if (result['success'] == true) {
        final usersList = result['users'] as List;
        setState(() {
          _users = usersList.map((u) => User.fromJson(u)).toList();
        });
        // Eigene numerische ID auflösen und global hinterlegen: Anhang-Uploads
        // müssen erkennen, ob der gerade bearbeitete Datensatz der eigene ist —
        // dann ist der verschlüsselte 50-GB-Cloud gemeint statt des
        // Mitglieder-Clouds. Über die Mitgliedsnummer, weil das Dashboard nur
        // die kennt.
        for (final u in _users) {
          if (u.mitgliedernummer == widget.currentMitgliedernummer) {
            GlobalChatService().currentAdminUserId = u.id;
            break;
          }
        }
        // Publish users + apiService to the global broadcast context (used
        // by the read-only log viewer in the weather dialog).
        SturmwarnungBroadcastContext.instance
          ..apiService = _apiService
          ..users = _users
          ..adminMitgliedernummer = widget.currentMitgliedernummer;
        // Kick off the fully-automated DWD → Chat broadcast loop. Sweeps
        // every 30 min, sends at most once per (alert, user, day).
        WeatherAutoBroadcastService.instance.start(
          apiService: _apiService,
          users: _users,
          adminMitgliedernummer: widget.currentMitgliedernummer,
        );
        // Refresh "Mein Vote" pending list in background — independent of
        // _users fetch.
        _refreshPendingMyVote();
        // Once we have _users + widget.currentMitgliedernummer, extract the
        // logged-in user's Stufe-1-Adresse (city/bundesland) and publish it
        // to TransitDisruptionsService so the badge only counts geographically
        // relevant Störungen instead of all national ones.
        _publishRegionTokens();
        // Kick off activity-indicator fetch in background. Do NOT await — the
        // user list should appear immediately; the green dots fill in when ready.
        _loadMemberActivity();
      } else {
        setState(() {
          _errorMessage = result['message'] ?? 'Fehler beim Laden der Benutzer';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Verbindungsfehler: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Computes per-member activity flags for the current calendar week
  /// (Monday 00:00 → Sunday 23:59). Three bulk fetches:
  ///   1. Tickets via `getAdminTickets` → group by `memberNummer`,
  ///      keep only tickets whose createdAt or scheduledDate falls inside the week
  ///   2. Routine executions via `getExecutions(startDate, endDate)` → group by `userId`,
  ///      map userId → mitgliedernummer via the already-loaded `_users` list
  ///   3. Termine: parallel `getAllTermine(from, to, participantId: u.id)` per user
  ///      because the list endpoint doesn't expose participant identities directly.
  ///      Acceptable cost — under 50 members in practice, runs concurrently.
  Future<void> _loadMemberActivity() async {
    if (_users.isEmpty) return;
    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1)); // Monday 00:00
    final weekEnd = weekStart.add(const Duration(days: 7)); // next Monday 00:00 (exclusive)

    // Tickets: 1 bulk call, then filter client-side.
    final ticketSet = <String>{};
    try {
      final adminTickets = await _ticketService.getAdminTickets(widget.currentMitgliedernummer);
      if (adminTickets != null) {
        for (final t in adminTickets.tickets) {
          final created = t.createdAt;
          final scheduled = t.scheduledDate;
          final inWeek = (created.isAfter(weekStart) && created.isBefore(weekEnd)) ||
              (scheduled != null && scheduled.isAfter(weekStart) && scheduled.isBefore(weekEnd));
          final mn = t.memberNummer;
          if (inWeek && mn != null && mn.isNotEmpty) {
            ticketSet.add(mn);
          }
        }
      }
    } catch (_) {/* leave ticketSet empty on failure */}

    // Routine executions: 1 bulk call, then map userId → mitgliedernummer.
    final routineSet = <String>{};
    try {
      final userIdToMgnum = <int, String>{
        for (final u in _users) u.id: u.mitgliedernummer,
      };
      final fromStr = weekStart.toIso8601String().substring(0, 10);
      final toStr = weekEnd.subtract(const Duration(days: 1)).toIso8601String().substring(0, 10);
      final result = await _routineService.getExecutions(startDate: fromStr, endDate: toStr);
      for (final e in result.executions) {
        final uid = e.userId;
        if (uid == null) continue;
        final mgnum = userIdToMgnum[uid];
        if (mgnum != null) routineSet.add(mgnum);
      }
    } catch (_) {/* leave routineSet empty */}

    // Termine: BULK single call înlocuiește N cereri paralele care
    // triggerau nginx rate-limit → 503 → aparent freeze pe Arbeitswochen.
    final terminSet = <String>{};
    try {
      final userIdToMgnum = <int, String>{
        for (final u in _users) u.id: u.mitgliedernummer,
      };
      final activeUserIds = await _terminService.getTerminUsersActivity(
        from: weekStart,
        to: weekEnd,
      );
      for (final uid in activeUserIds) {
        final mg = userIdToMgnum[uid];
        if (mg != null) terminSet.add(mg);
      }
    } catch (_) {/* leave terminSet empty */}

    if (!mounted) return;
    setState(() {
      _memberActivity = {
        for (final u in _users)
          u.mitgliedernummer: MemberActivity(
            hasTermin: terminSet.contains(u.mitgliedernummer),
            hasTicket: ticketSet.contains(u.mitgliedernummer),
            hasRoutine: routineSet.contains(u.mitgliedernummer),
          ),
      };
    });
  }

  Future<void> _loadTickets({String? filter}) async {
    setState(() => _isLoadingTickets = true);

    final filterValue = filter ?? (_ticketFilter == 'all' ? null : _ticketFilter);
    final result = await _ticketService.getAdminTickets(
      widget.currentMitgliedernummer,
      statusFilter: filterValue,
    );

    if (mounted && result != null) {
      setState(() {
        _tickets = result.tickets;
        _ticketStats = result.stats;
        _isLoadingTickets = false;
      });
    } else if (mounted) {
      setState(() => _isLoadingTickets = false);
    }
  }

  Future<void> _loadWeeklyTime() async {
    final result = await _ticketService.getWeeklyTimeSummary(
      mitgliedernummer: widget.currentMitgliedernummer,
    );
    if (mounted && result != null) {
      setState(() => _weeklyTime = result);
    }
  }

  Future<void> _updateTicket(int ticketId, String action, {String? scheduledDate}) async {
    // Quick actions (✓ Erledigen, → +1 Woche) must NOT trigger a full
    // _loadTickets() — that flips _isLoadingTickets, repaints the entire
    // ListView, and resets scroll position to the top. Instead we apply the
    // change optimistically to _tickets / _ticketStats in place, then fire the
    // API in the background and either silently merge the server response or
    // roll back on failure. The user keeps their scroll position and sees the
    // card update instantly.

    final idx = _tickets.indexWhere((t) => t.id == ticketId);
    if (idx < 0) {
      // Ticket not in current view (filter changed since the button was
      // drawn). Fall back to plain API call without optimistic UI.
      final result = await _ticketService.updateTicket(
        mitgliedernummer: widget.currentMitgliedernummer,
        ticketId: ticketId,
        action: action,
        scheduledDate: scheduledDate,
      );
      if (result != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_getActionMessage(action, scheduledDate: scheduledDate)),
            backgroundColor: Colors.green,
          ),
        );
      }
      return;
    }

    final original = _tickets[idx];
    final originalStats = _ticketStats;

    // Compute optimistic ticket + stats delta.
    Ticket optimistic;
    TicketStats? newStats = _ticketStats;
    switch (action) {
      case 'done':
        optimistic = original.copyWith(status: 'done', closedAt: DateTime.now());
        if (originalStats != null && original.status != 'done') {
          newStats = originalStats.copyWith(
            open: original.status == 'open' ? (originalStats.open - 1).clamp(0, originalStats.total) : originalStats.open,
            inProgress: original.status == 'in_progress' ? (originalStats.inProgress - 1).clamp(0, originalStats.total) : originalStats.inProgress,
            waitingMember: original.status == 'waiting_member' ? (originalStats.waitingMember - 1).clamp(0, originalStats.total) : originalStats.waitingMember,
            waitingStaff: original.status == 'waiting_staff' ? (originalStats.waitingStaff - 1).clamp(0, originalStats.total) : originalStats.waitingStaff,
            waitingAuthority: original.status == 'waiting_authority' ? (originalStats.waitingAuthority - 1).clamp(0, originalStats.total) : originalStats.waitingAuthority,
            done: originalStats.done + 1,
          );
        }
        break;
      case 'set_scheduled_date':
        if (scheduledDate != null) {
          try {
            final parsed = DateTime.parse(scheduledDate.replaceAll(' ', 'T'));
            optimistic = original.copyWith(scheduledDate: parsed);
          } catch (_) {
            optimistic = original;
          }
        } else {
          optimistic = original;
        }
        break;
      default:
        // Other actions (assign, reopen, set_in_progress, set_waiting_*) come
        // from the details dialog — leave their existing reload behavior
        // intact for now by falling back to the old path.
        final result = await _ticketService.updateTicket(
          mitgliedernummer: widget.currentMitgliedernummer,
          ticketId: ticketId,
          action: action,
          scheduledDate: scheduledDate,
        );
        if (result != null) {
          _loadTickets();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_getActionMessage(action, scheduledDate: scheduledDate)),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
        return;
    }

    // Replace ticket in-place. We deliberately do NOT remove tickets that no
    // longer match the active filter (e.g. filter='open' and new status='done')
    // — the Vorsitzer wants instant visual confirmation on the card itself
    // (badge goes green / scheduled date updates) without anything vanishing.
    // The list re-aligns on the next manual refresh or filter change.
    setState(() {
      final mutable = List<Ticket>.from(_tickets);
      mutable[idx] = optimistic;
      _tickets = mutable;
      _ticketStats = newStats;
    });

    // Fire API in background.
    final result = await _ticketService.updateTicket(
      mitgliedernummer: widget.currentMitgliedernummer,
      ticketId: ticketId,
      action: action,
      scheduledDate: scheduledDate,
    );

    if (!mounted) return;

    if (result != null) {
      // Silent merge: replace optimistic with server-truth. No spinner, no
      // full reload — scroll preserved.
      final newIdx = _tickets.indexWhere((t) => t.id == ticketId);
      if (newIdx >= 0) {
        setState(() {
          final mutable = List<Ticket>.from(_tickets);
          mutable[newIdx] = result;
          _tickets = mutable;
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_getActionMessage(action, scheduledDate: scheduledDate)),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      // Rollback: restore original ticket + stats.
      setState(() {
        final mutable = List<Ticket>.from(_tickets);
        final stillIdx = mutable.indexWhere((t) => t.id == ticketId);
        if (stillIdx >= 0) {
          mutable[stillIdx] = original;
        }
        _tickets = mutable;
        _ticketStats = originalStats;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Aktion fehlgeschlagen — Ticket wiederhergestellt'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  String _getActionMessage(String action, {String? scheduledDate}) {
    switch (action) {
      case 'assign':
        return 'Ticket übernommen';
      case 'done':
        return 'Ticket erledigt';
      case 'reopen':
        return 'Ticket wiedereröffnet';
      case 'set_in_progress':
        return 'Ticket in Bearbeitung';
      case 'set_waiting_member':
        return 'Warten auf Benutzer';
      case 'set_waiting_staff':
        return 'Warten auf Mitarbeiter';
      case 'set_waiting_authority':
        return 'Warten auf Behörde';
      case 'set_scheduled_date':
        if (scheduledDate != null) {
          try {
            final dt = DateTime.parse(scheduledDate.replaceAll(' ', 'T'));
            return 'Ticket verschoben auf ${DateFormat('dd.MM.yyyy').format(dt)}';
          } catch (_) {}
        }
        return 'Ticket verschoben';
      default:
        return 'Ticket aktualisiert';
    }
  }

  Future<void> _updateUserStatus(User user, String newStatus) async {
    final confirm = await showStatusChangeDialog(
      context: context,
      user: user,
      newStatus: newStatus,
    );

    if (!confirm) return;

    try {
      final result = await _apiService.updateUserStatus(user.id, newStatus);

      if (!mounted) return;
      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status erfolgreich auf "$newStatus" geändert'),
            backgroundColor: Colors.green,
          ),
        );
        _loadUsers();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Fehler beim Ändern des Status'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteUser(User user) async {
    final confirm = await showDeleteUserDialog(
      context: context,
      user: user,
    );

    if (!confirm) return;

    try {
      final result = await _apiService.deleteUser(user.id);

      if (!mounted) return;
      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Benutzer erfolgreich gelöscht'),
            backgroundColor: Colors.green,
          ),
        );
        _loadUsers();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Fehler beim Löschen'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _logout() async {
    // Clear API tokens
    await _apiService.logout();

    // Clear auto-login flag and saved credentials
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_login', false);

    // Clear encrypted credentials
    const secureStorage = FlutterSecureStorage();
    await secureStorage.delete(key: 'mitgliedernummer');
    await secureStorage.delete(key: 'password');

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  void _showProfileDialog() {
    final currentUser = _users.where((u) => u.mitgliedernummer == widget.currentMitgliedernummer).firstOrNull;
    showDialog(
      context: context,
      builder: (context) => ProfileDialog(
        userName: widget.userName,
        mitgliedernummer: widget.currentMitgliedernummer,
        email: _currentEmail,
        role: widget.currentRole,
        userId: currentUser?.id,
        apiService: _apiService,
        onEmailChanged: (newEmail) {
          setState(() {
            _currentEmail = newEmail;
          });
        },
      ),
    );
  }

  void _showUserDetailsDialog(User user) {
    openMitgliedProfile(
      context: context,
      apiService: _apiService,
      user: user,
      adminMitgliedernummer: widget.currentMitgliedernummer,
      onUpdated: () {
        _loadUsers(); // Reload user list after update
      },
    );
  }

  void _showAdminChatDialog() {
    _showAdminChatDialogInternal(null);
  }

  void _showAdminChatDialogWithCall() {
    _showAdminChatDialogInternal(_pendingCall);
  }

  void _showAdminChatDialogInternal(CallOfferEvent? pendingCall, {int? initialConversationId}) {
    // Clear unread count when opening chat. Bubbles stay (user closes them
    // explicitly with the × on each bubble); just zero their unread badges.
    setState(() {
      _unreadChatCount = 0;
      _isAdminChatOpen = true;
      for (final convId in _chatBubbles.keys.toList()) {
        final b = _chatBubbles[convId]!;
        if (b.unreadCount > 0) {
          _chatBubbles[convId] = ChatBubbleEntry(
            conversationId: b.conversationId,
            senderName: b.senderName,
            unreadCount: 0,
            lastMessagePreview: b.lastMessagePreview,
          );
        }
      }
    });
    // Also clear tray unread count
    TrayService().clearUnread();

    showDialog(
      context: context,
      builder: (context) => AdminChatDialog(
        mitgliedernummer: widget.currentMitgliedernummer,
        userName: widget.userName,
        pendingCall: pendingCall,
        initialConversationId: initialConversationId,
      ),
    ).then((_) {
      // Mark dialog as closed and re-zero the unread counter — any messages
      // that arrived while the dialog was open were read in-place and must
      // not leave the badge stuck > 0.
      setState(() {
        _isAdminChatOpen = false;
        _pendingCall = null;
        _unreadChatCount = 0;
      });
      TrayService().clearUnread();
      // Re-join all conversations after dialog closes to keep receiving messages
      for (final convId in _backgroundConversationIds) {
        _chatService.joinConversation(convId);
      }
      _log.info('Re-joined ${_backgroundConversationIds.length} conversations after dialog close', tag: 'DASH');
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);
    // Weather pill: compact variant on phones (<600px), full otherwise (tablets — including Android — and desktop).
    final showWeatherCompact = MediaQuery.of(context).size.width < 600;
    // Nach gemessener Breite, nicht nach Plattform — auf dem Tablet (800 dp)
    // passen die dreizehn Knöpfe, dort bleibt die Leiste wie gehabt.
    final istTelefon = ResponsiveLayout.istTelefon(context);

    return Scaffold(
      backgroundColor: F.hd(const Color(0xFFF5F5F5), F.flaecheGedaempft),
      appBar: AppBar(
        title: Text(isMobile ? 'ICD360S e.V' : 'ICD360S e.V - Vorsitzer Panel'),
        backgroundColor: const Color(0xFF1a1a2e),
        foregroundColor: Colors.white,
        flexibleSpace: SeasonalBackground.isEasterSeason
            ? IgnorePointer(
                child: CustomPaint(
                  painter: EasterAppBarPainter(),
                  size: Size.infinite,
                ),
              )
            : null,
        // Show hamburger menu on mobile
        leading: isMobile
            ? Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  tooltip: 'Menü',
                ),
              )
            : null,
        actions: [
          // Login-Anfragen button with badge
          ValueListenableBuilder<List<Map<String, dynamic>>>(
            valueListenable: LoginApprovalOverlay().requests,
            builder: (context, requests, _) {
              return IconButton(
                icon: Badge(
                  isLabelVisible: requests.isNotEmpty,
                  label: Text('${requests.length}'),
                  backgroundColor: Colors.red,
                  child: Icon(Icons.key, color: requests.isNotEmpty ? Colors.amber : Colors.white70),
                ),
                tooltip: 'Login-Anfragen${requests.isNotEmpty ? ' (${requests.length})' : ''}',
                onPressed: () => LoginApprovalOverlay.show(context),
              );
            },
          ),
          // ⚠️ Auf Telefonbreite (Pixel 8: 411 dp, Pixel 8 Pro: 448 dp) sind
          // dreizehn Knöpfe à 48 dp = 624 dp — mehr als der ganze Bildschirm.
          // Die AppBar legt ihre `actions` in eine Row, das lief schlicht über.
          // Sichtbar bleiben deshalb nur Login-Anfragen, Live Chat und das
          // Wetter; alles andere zieht ins ⋮-Menü, mit einem Punkt darauf,
          // wenn eines der versteckten Abzeichen etwas meldet.
          if (istTelefon) ..._appBarTelefonAktionen() else ...[
          // Der öffentliche Webauftritt icd360s.de — Besucherzahlen und
          // Sicherheitsbefund. Steht direkt neben dem Schlüssel, weil es der
          // eine Knopf ist, an dem sich ablesen lässt, ob der Auftritt
          // überhaupt jemanden erreicht.
          //
          // ⚠️ Bewusst NICHT vor dem `if`: unbedingt eingehängt wäre er auch
          // auf dem Telefon sichtbar, und genau dort ist die Zeile schon voll
          // (siehe den Absatz darüber). Auf dem Telefon liegt er im ⋮-Menü,
          // wie alles andere auch.
          IconButton(
            icon: const Icon(Icons.public),
            tooltip: 'Website — icd360s.de',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const WebsiteScreen(),
            )),
          ),
          // Moon phase, radio and news — auf allen Plattformen sichtbar.
          // NICHT hinter `!isMobile` hängen: ResponsiveLayout.isMobile ist auf
          // Android/iOS immer true (auch auf dem Tablet, weil es zusätzlich zur
          // Breite auf PlatformService.isMobile prüft), die drei Buttons wären
          // dort also nie da gewesen.
          Builder(builder: (ctx) {
            final phase = MoonPhaseHelper.getMoonPhase(DateTime.now());
            final info = MoonPhaseHelper.getDecisionInfo(phase);
            final emoji = MoonPhaseHelper.getPhaseEmoji(phase);
            return IconButton(
              icon: Text(emoji, style: const TextStyle(fontSize: 20)),
              tooltip: '${info.title}: ${info.shortAdvice}',
              onPressed: () => showMoonPhaseDialog(ctx),
            );
          }),
          // Radio (HR Info live stream toggle)
          IconButton(
            icon: Icon(
              _radioPlaying ? Icons.radio : Icons.radio_outlined,
              color: _radioPlaying ? Colors.deepOrange : null,
            ),
            tooltip: _radioPlaying
                ? 'Radio stoppen (${_radioService.stationName})'
                : 'Radio starten (${_radioService.stationName})',
            onPressed: () async {
              await _radioService.toggle();
              setState(() => _radioPlaying = _radioService.isPlaying);
            },
          ),
          // Telefonieren über sipgate, direkt in der App.
          //
          // Der Knopf zeigt die Registrierung mit, weil eine verlorene
          // Anmeldung sonst unbemerkt bliebe — und dann fällt es erst auf,
          // wenn ein Anruf nicht klingelt.
          //
          // Bewusst NUR hier, nicht in _appBarTelefonAktionen(): auf
          // Telefonbreite ist die Leiste ohnehin voll, und ein Gerät mit SIM
          // braucht kein Softphone. Der Gewinn liegt am Linux-Rechner, wo es
          // keine SIM gibt und die Fernwahl die Sprache nur per Bluetooth
          // über höchstens zehn Meter bringt.
          ValueListenableBuilder<SipgateZustand>(
            valueListenable: SipgateService().zustand,
            builder: (ctx, z, _) {
              final imGespraech = z.gespraech != null;
              // ⚠️ Auf dem Rechner gibt es keine Registrierung, also darf der
              // Knopf auch keine anzeigen. Ein grauer „nicht angemeldet"-Zustand
              // wäre dort eine Fehlmeldung: der Rechner SOLL sich nicht anmelden.
              if (!SipgateService().plattformFaehig) {
                return IconButton(
                  icon: const Icon(Icons.settings_phone),
                  tooltip: 'Anruf vom Rechner — womit das Tablet wählt',
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const SipgateScreen(),
                  )),
                );
              }
              return IconButton(
                icon: Icon(
                  z.stand == SipgateStand.registriert || imGespraech
                      ? Icons.phone_in_talk
                      : Icons.phone_in_talk_outlined,
                  color: switch (z.stand) {
                    SipgateStand.registriert => imGespraech ? Colors.lightGreenAccent : Colors.greenAccent,
                    SipgateStand.verbindet => Colors.amber,
                    SipgateStand.fehler => Colors.redAccent,
                    SipgateStand.aus => null,
                  },
                ),
                tooltip: switch (z.stand) {
                  SipgateStand.registriert => imGespraech
                      ? 'Gespräch läuft — ${z.gespraech!.nummer}'
                      : 'sipgate — angemeldet${z.sipId == null ? '' : ' (${z.sipId})'}',
                  SipgateStand.verbindet => 'sipgate — melde an …',
                  SipgateStand.fehler => 'sipgate — nicht angemeldet',
                  SipgateStand.aus => 'sipgate — Telefonie',
                },
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const SipgateScreen(),
                )),
              );
            },
          ),
          // Fax über sipgate — direkt neben dem Telefon, weil es dieselbe
          // Leitung und dasselbe Konto ist.
          //
          // ⚠️ Aber NICHT derselbe Weg: die App telefoniert per SIP over
          // WebSocket, und ein Fax ist ein Modem, kein Gespräch — ein
          // WebRTC-Stack hat weder T.38 noch G.711-Passthrough. Fax läuft über
          // die REST-API und braucht ein eigenes Zugangsmittel. Deshalb hängt
          // dieser Knopf auch nicht am SipgateService: er hat mit der
          // SIP-Registrierung nichts zu tun und darf nicht ausgrauen, wenn das
          // Softphone gerade nicht angemeldet ist.
          //
          // Abzeichen = eingegangene, noch nicht angesehene Faxe. Ohne das gab
          // es in der App **kein einziges Zeichen** für ein eingegangenes Fax:
          // der Cron meldete es per ntfy, und wer die Meldung wegwischte,
          // erfuhr davon nichts mehr. sipgate löscht seinen Verlauf nach
          // 30 Tagen — bei uns bleibt es, aber nur, wenn jemand hinsieht.
          ValueListenableBuilder<int>(
            valueListenable: FaxBadgeService().ungelesen,
            builder: (context, ungelesen, _) => Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.fax),
                  tooltip: ungelesen > 0
                      ? 'Fax — $ungelesen neu im Eingang'
                      : 'Fax senden und empfangen',
                  onPressed: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const SipgateFaxScreen(),
                    ));
                    // Nach dem Verlassen neu zählen: im Bildschirm wurden
                    // vermutlich gerade welche angesehen.
                    FaxBadgeService().aktualisieren();
                  },
                ),
                if (ungelesen > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints:
                          const BoxConstraints(minWidth: 18, minHeight: 18),
                      child: Text(
                        ungelesen > 9 ? '9+' : '$ungelesen',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Briefversand — direkt neben dem Fax, weil es derselbe Gedanke ist:
          // ein Dokument verlässt das Haus, ohne dass jemand zum Briefkasten
          // läuft. Nur eben auf Papier.
          //
          // ⚠️ NICHT Deutsche Post direkt: deren E-POST BUSINESS API kostet
          // 275 € Anschluss und 59 €/Monat, bevor der erste Brief geschrieben
          // ist, und die Internetmarke-API frankiert bloß — drucken und
          // einwerfen bliebe bei uns. Gedruckt und zugestellt wird über
          // LetterXpress; zugestellt wird am Ende doch von der Deutschen Post.
          IconButton(
            icon: const Icon(Icons.markunread_mailbox_outlined),
            tooltip: 'Briefversand — PDF als echten Brief verschicken',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PostScreen(apiService: _apiService),
            )),
          ),
          // News (Tagesschau)
          IconButton(
            icon: const Icon(Icons.newspaper),
            tooltip: 'Nachrichten',
            onPressed: _showNewsDialog,
          ),
          // Transit (ÖPNV departures) — visible on all screen sizes.
          // Badge shows count of active national disruptions (bahn.de HIM feed,
          // refreshed every 15 min). Red for high-priority, orange otherwise.
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.directions_bus),
                tooltip: _disruptionsService.count > 0
                    ? 'ÖPNV Abfahrten — ${_disruptionsService.count} '
                        'Störung${_disruptionsService.count == 1 ? "" : "en"} in deiner Region'
                    : 'ÖPNV Abfahrten',
                onPressed: _showTransitDialog,
              ),
              if (_disruptionsService.count > 0)
                Positioned(
                  right: 4, top: 4,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      decoration: BoxDecoration(
                        color: _disruptionsService.highPriorityCount > 0
                            ? Colors.red.shade600
                            : Colors.orange.shade600,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                      child: Text(
                        _disruptionsService.count > 99 ? '99+' : '${_disruptionsService.count}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // Speedtest gegen den EIGENEN Server, kein Fremdanbieter.
          // Bewusst NICHT hinter `!isMobile`: das Tablet ist das Gerät mit der
          // Telekom-SIM und damit dasjenige, um dessen Leitung es überhaupt
          // geht. Hier stand vorher der Debug-Knopf „Test Chat Bubble".
          IconButton(
            icon: const Icon(Icons.speed),
            tooltip: 'Speedtest',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const SpeedtestScreen(),
            )),
          ),
          // Dokumente, die der Vorsitzende SELBST unterschreiben soll — bei der
          // Vollmacht unterschreiben zwei Leute.
          //
          // BEWUSST OHNE ZÄHLERABZEICHEN: dafür müsste im Hintergrund gezählt
          // werden, und der Wachdienst dieser App fragt ohnehin schon reichlich
          // oft nach. Ein weiterer Takt für einen Fall, der ein paar Mal im Jahr
          // eintritt, wäre schlecht getauscht — zumal der Vorsitzende selbst
          // derjenige ist, der die Unterschrift angefordert hat.
          IconButton(
            icon: const Icon(Icons.draw_outlined),
            tooltip: 'Meine Unterschriften',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => EigeneUnterschriftenScreen(
                apiService: ApiService(),
              ),
            )),
          ),
          // Live Chat (Admin can chat with members) with unread badge
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.chat_outlined),
                onPressed: _showAdminChatDialog,
                tooltip: 'Live Chat',
              ),
              // Unread count badge (shows when > 0)
              if (_unreadChatCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Text(
                      _unreadChatCount > 9 ? '9+' : '$_unreadChatCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                // Online indicator (only when no unread messages)
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
          // E-Mail (icd@icd360s.de Postfach) — direkt neben Live Chat.
          // Abzeichen = ungelesene Nachrichten im Eingang. Die Zahl kommt aus
          // mail/folders.php; gesetzt wird sie beim Start, beim Aufwecken und
          // beim Verlassen des Postfachs, nicht in einem Dauertakt.
          ValueListenableBuilder<int>(
            valueListenable: MailBadgeService().unreadCount,
            builder: (context, ungelesen, _) => Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.mail_outline),
                  tooltip: ungelesen > 0
                      ? 'E-Mail — $ungelesen ungelesen'
                      : 'E-Mail',
                  onPressed: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => MailScreen(
                        mitgliedernummer: widget.currentMitgliedernummer,
                        userName: widget.userName,
                        email: widget.currentEmail,
                      ),
                    ));
                    MailBadgeService().refreshBadge();
                  },
                ),
                if (ungelesen > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints:
                          const BoxConstraints(minWidth: 18, minHeight: 18),
                      child: Text(
                        ungelesen > 9 ? '9+' : '$ungelesen',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Sichere Cloud (zero-knowledge, 50 GB) — right next to Live Chat.
          IconButton(
            icon: const Icon(Icons.cloud_outlined),
            tooltip: 'Sichere Cloud',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SecureCloudScreen(
                mitgliedernummer: widget.currentMitgliedernummer,
                userName: widget.userName,
              ),
            )),
          ),
          // Remote Desktop (RDP via Guacamole gateway) — next to the cloud button.
          IconButton(
            icon: const Icon(Icons.desktop_windows_outlined),
            tooltip: 'Remote Desktop (RDP)',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => RemoteDesktopScreen(
                mitgliedernummer: widget.currentMitgliedernummer,
              ),
            )),
          ),
          // TV (gespeicherte YouTube-Kanäle) — direkt neben Remote Desktop.
          // Badge = Kanäle mit einem Video, das noch niemand geöffnet hat;
          // gesetzt wird es vom Cron (check_youtube_channels.php), nicht hier.
          ValueListenableBuilder<int>(
            valueListenable: YoutubeService().newCount,
            builder: (context, newCount, _) => Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.live_tv_outlined),
                  tooltip: 'TV — YouTube-Kanäle',
                  onPressed: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const TvScreen(),
                    ));
                    YoutubeService().refreshBadge();
                  },
                ),
                if (newCount > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                      child: Text(
                        newCount > 9 ? '9+' : '$newCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Weather pill: full on tablets/desktop (width>=600), compact on phones.
          // Alerts count combines DWD warnings and locally-derived health alerts
          // so the badge always reflects the total number of things to check on.
          if (_weatherData != null)
            WeatherPill(
              weather: _weatherData!,
              alertsCount: _weatherAlerts.length + _healthAlerts.length,
              compact: showWeatherCompact,
              trendArrow: _weatherService.temperatureTrend(),
              imminentPrecipitation: _weatherService.hasImminentPrecipitation(),
              isStale: _weatherService.isDataStale,
              gpsFollowing: _weatherService.isFollowingGps,
              onTap: () => showWeatherDialog(context, _weatherService),
            ),
          // Hell / Dunkel / System. Steht bewusst neben Profil und Abmelden,
          // also bei dem, was das eigene Konto betrifft — nicht zwischen den
          // Fachknöpfen.
          const ThemeUmschalterKnopf(),
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: _showProfileDialog,
            tooltip: 'Mein Profil',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'Abmelden',
          ),
          ],
        ],
      ),
      // Mobile: Use drawer for navigation
      drawer: isMobile
          ? Builder(
              builder: (drawerCtx) => Drawer(
                child: DashboardSidebar(
                  userName: widget.userName,
                  mitgliedernummer: widget.currentMitgliedernummer,
                  selectedMenuIndex: _selectedMenuIndex,
                  onMenuSelected: (index) {
                    // Close drawer FIRST via Scaffold.of (correct API pe mobile),
                    // apoi setState la end of frame — ordinea inversă poate lăsa
                    // drawer scrim în tranziție pe Android.
                    Scaffold.of(drawerCtx).closeDrawer();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _selectedMenuIndex = index);
                    });
                  },
                ),
              ),
            )
          : null,
      // Desktop: Sidebar + content, Mobile: Just content + floating chat bubbles
      body: Column(
        children: [
          // Testphase läuft noch: Vorwarnung, bevor auto_suspend.php sperrt.
          if (_isTrialAccount)
            TrialWarningBanner(
              daysRemaining: _trialDaysRemaining,
              trialEndsAt: _trialEndsAt,
            ),
          // Local vulnerability warnings (heat / cold / UV / PM2.5 / ozone).
          // Auto-hide when the user acknowledges via "OK Verstanden".
          if (_healthAlerts.isNotEmpty)
            HealthAlertBanner(
              alerts: _healthAlerts,
              onAcknowledge: (a) {
                _weatherService.acknowledgeHealthAlert(a);
                setState(() => _healthAlerts = _weatherService.activeHealthAlerts);
              },
              onTap: (_) => showWeatherDialog(context, _weatherService),
            ),
          // wetter.com-style sticky 15-min forecast bar directly under the AppBar.
          // Tap opens the full weather dialog.
          if (_weatherService.minutelyForecast.isNotEmpty)
            Material(
              color: const Color(0xFF1a1a2e),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                child: WeatherMinutelyBar(
                  entries: _weatherService.minutelyForecast,
                  onTap: () => showWeatherDialog(context, _weatherService),
                  compact: true,
                ),
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                SeasonalBackground(
                  child: isMobile
                    ? _buildMainContent()
                    : Row(
                        children: [
                          DashboardSidebar(
                            userName: widget.userName,
                            mitgliedernummer: widget.currentMitgliedernummer,
                            selectedMenuIndex: _selectedMenuIndex,
                            onMenuSelected: (index) => setState(() => _selectedMenuIndex = index),
                          ),
                          Expanded(
                            child: _buildMainContent(),
                          ),
                        ],
                      ),
                ),
                // NOTE 2026-06-25: Local ChatBubbleOverlay + ChatBubblePopup au fost
                // mutate la nivel global (MaterialApp.builder → GlobalChatOverlay),
                // ca să apară pe orice pagină nu doar pe Dashboard. State sync:
                // GlobalChatService.start() ascultă messageStream singur; dashboard-ul
                // doar populeaza bubble-urile de start în _joinBackgroundConversations.
              ],
            ),
          ),
        ],
      ),
      // Mobile: Bottom navigation bar for quick access
      bottomNavigationBar: isMobile
          ? _buildMobileBottomNav()
          : const LegalFooter(darkMode: true),
    );
  }

  /// Die AppBar-Aktionen auf Telefonbreite: drei Knöpfe und ein ⋮-Menü.
  ///
  /// Sichtbar bleibt, was ungefragt etwas meldet (Login-Anfragen steht schon
  /// davor, Live Chat trägt die ungelesenen Nachrichten) und das Wetter, weil
  /// es eine Anzeige ist und kein Knopf. Der Rest wandert ins Menü — als Text
  /// sogar auffindbarer als ein Icon, dessen Tooltip auf einem Telefon
  /// niemand zu sehen bekommt.
  List<Widget> _appBarTelefonAktionen() {
    return [
      // Live Chat mit Zähler ungelesener Nachrichten.
      Stack(
        children: [
          IconButton(
            icon: const Icon(Icons.chat_outlined),
            onPressed: _showAdminChatDialog,
            tooltip: 'Live Chat',
          ),
          if (_unreadChatCount > 0)
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                child: Text(
                  _unreadChatCount > 9 ? '9+' : '$_unreadChatCount',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      if (_weatherData != null)
        WeatherPill(
          weather: _weatherData!,
          alertsCount: _weatherAlerts.length + _healthAlerts.length,
          compact: true,
          trendArrow: _weatherService.temperatureTrend(),
          imminentPrecipitation: _weatherService.hasImminentPrecipitation(),
          isStale: _weatherService.isDataStale,
          gpsFollowing: _weatherService.isFollowingGps,
          onTap: () => showWeatherDialog(context, _weatherService),
        ),
      ValueListenableBuilder<int>(
        valueListenable: YoutubeService().newCount,
        builder: (context, tvNeu, _) => ValueListenableBuilder<int>(
        valueListenable: MailBadgeService().unreadCount,
        builder: (context, mailNeu, _) {
          // Die versteckten Abzeichen dürfen nicht verschwinden, sonst merkt
          // niemand mehr, dass hinter dem ⋮ etwas wartet.
          final verstecktesAbzeichen =
              tvNeu > 0 || mailNeu > 0 || _disruptionsService.count > 0;
          return PopupMenuButton<String>(
            icon: Badge(
              isLabelVisible: verstecktesAbzeichen,
              backgroundColor: Colors.red,
              smallSize: 8,
              child: const Icon(Icons.more_vert),
            ),
            tooltip: 'Weitere Aktionen',
            onSelected: (wahl) => _appBarMenueWahl(wahl),
            itemBuilder: (_) => [
              _menuePunkt('mond', MoonPhaseHelper.getPhaseEmoji(
                  MoonPhaseHelper.getMoonPhase(DateTime.now())),
                  MoonPhaseHelper.getDecisionInfo(
                      MoonPhaseHelper.getMoonPhase(DateTime.now())).title),
              _menuePunktIcon(
                'radio',
                _radioPlaying ? Icons.radio : Icons.radio_outlined,
                _radioPlaying
                    ? 'Radio stoppen (${_radioService.stationName})'
                    : 'Radio starten (${_radioService.stationName})',
                farbe: _radioPlaying ? Colors.deepOrange : null,
              ),
              _menuePunktIcon('news', Icons.newspaper, 'Nachrichten'),
              _menuePunktIcon(
                'oepnv',
                Icons.directions_bus,
                'ÖPNV Abfahrten',
                zaehler: _disruptionsService.count,
                zaehlerFarbe: _disruptionsService.highPriorityCount > 0
                    ? Colors.red.shade600
                    : Colors.orange.shade600,
              ),
              _menuePunktIcon('speedtest', Icons.speed, 'Speedtest'),
              _menuePunktIcon('website', Icons.public, 'Website — icd360s.de'),
              _menuePunktIcon('mail', Icons.mail_outline, 'E-Mail',
                  zaehler: mailNeu, zaehlerFarbe: Colors.red),
              // ⚠️ Fax gehört hier hinein, obwohl sipgate es NICHT tut: das
              // Softphone bleibt der Telefonbreite fern, weil ein Gerät mit SIM
              // keins braucht. Fax braucht dagegen kein SIP und keine SIM —
              // es ist ein Dokumentenweg wie E-Mail und auf dem Telefon
              // genauso nützlich wie am Rechner.
              _menuePunktIcon('fax', Icons.fax, 'Fax'),
              // Aus demselben Grund wie Fax: ein Dokumentenweg, der weder SIM
              // noch Bildschirmbreite braucht.
              _menuePunktIcon('brief', Icons.markunread_mailbox_outlined, 'Briefversand'),
              _menuePunktIcon('cloud', Icons.cloud_outlined, 'Sichere Cloud'),
              _menuePunktIcon('rdp', Icons.desktop_windows_outlined, 'Remote Desktop (RDP)'),
              _menuePunktIcon('tv', Icons.live_tv_outlined, 'TV — YouTube-Kanäle',
                  zaehler: tvNeu, zaehlerFarbe: Colors.red),
              const PopupMenuDivider(),
              // ⚠️ Auf Telefonbreite ist das ⋮-Menü der EINZIGE Weg zum
              // Erscheinungsbild — der Knopf oben steht in der anderen
              // Zweigstelle von `actions`, die hier gar nicht läuft. Der
              // eingestellte Modus steht als Text dabei, weil ein Tooltip auf
              // einem Telefon nie jemand zu sehen bekommt.
              _menuePunktIcon(
                'erscheinungsbild',
                ThemeService.symbol(ThemeService.instance.modus.value),
                'Erscheinungsbild: '
                    '${ThemeService.bezeichnung(ThemeService.instance.modus.value)}',
              ),
              _menuePunktIcon('profil', Icons.person, 'Mein Profil'),
              _menuePunktIcon('abmelden', Icons.logout, 'Abmelden'),
            ],
          );
        },
        ),
      ),
    ];
  }

  PopupMenuItem<String> _menuePunkt(String wert, String emoji, String text) {
    return PopupMenuItem<String>(
      value: wert,
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(child: Text(text, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuePunktIcon(
    String wert,
    IconData icon,
    String text, {
    Color? farbe,
    int zaehler = 0,
    Color? zaehlerFarbe,
  }) {
    return PopupMenuItem<String>(
      value: wert,
      child: Row(
        children: [
          Icon(icon, size: 20, color: farbe),
          const SizedBox(width: 12),
          Expanded(child: Text(text, overflow: TextOverflow.ellipsis)),
          if (zaehler > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: zaehlerFarbe ?? Colors.red,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                zaehler > 99 ? '99+' : '$zaehler',
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _appBarMenueWahl(String wahl) async {
    switch (wahl) {
      case 'mond':
        showMoonPhaseDialog(context);
      case 'radio':
        await _radioService.toggle();
        if (mounted) setState(() => _radioPlaying = _radioService.isPlaying);
      case 'news':
        _showNewsDialog();
      case 'oepnv':
        _showTransitDialog();
      case 'erscheinungsbild':
        await ThemeService.instance
            .weiterschalten(Theme.of(context).brightness);
      case 'speedtest':
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const SpeedtestScreen(),
        ));
      case 'website':
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const WebsiteScreen(),
        ));
      case 'mail':
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => MailScreen(
            mitgliedernummer: widget.currentMitgliedernummer,
            userName: widget.userName,
            email: widget.currentEmail,
          ),
        ));
        MailBadgeService().refreshBadge();
      case 'fax':
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const SipgateFaxScreen(),
        ));
      case 'brief':
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PostScreen(apiService: _apiService),
        ));
      case 'cloud':
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SecureCloudScreen(
            mitgliedernummer: widget.currentMitgliedernummer,
            userName: widget.userName,
          ),
        ));
      case 'rdp':
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => RemoteDesktopScreen(
            mitgliedernummer: widget.currentMitgliedernummer,
          ),
        ));
      case 'tv':
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const TvScreen(),
        ));
        YoutubeService().refreshBadge();
      case 'profil':
        _showProfileDialog();
      case 'abmelden':
        await _logout();
    }
  }

  /// Mobile bottom navigation bar
  Widget _buildMobileBottomNav() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BottomNavigationBar(
          // Clamp la [0, 7] fiindcă BottomNavigationBar are 8 items dar
          // _selectedMenuIndex poate fi până la 14 (Arbeitswochen via drawer).
          // Index out-of-bounds triggers assertion failure în debug și
          // undefined behavior în release Android → touch dispatch rupt.
          currentIndex: _selectedMenuIndex.clamp(0, 7),
          onTap: (index) => setState(() => _selectedMenuIndex = index),
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFF4a90d9),
          unselectedItemColor: Colors.grey,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people),
              label: 'Benutzer',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.confirmation_number),
              label: 'Tickets',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_month),
              label: 'Termine',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.business),
              label: 'Verein',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.location_city),
              label: 'Netzwerk',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.account_balance_wallet),
              label: 'Finanzen',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart),
              label: 'Statistik',
            ),
          ],
        ),
        const LegalFooter(darkMode: true),
      ],
    );
  }

  Widget _buildMainContent() {
    switch (_selectedMenuIndex) {
      case 0:
        return _buildDashboardOverview();
      case 1:
        return _buildMitgliederverwaltung();
      case 2:
        return TicketverwaltungScreen(
          tickets: _tickets,
          ticketStats: _ticketStats,
          isLoading: _isLoadingTickets,
          ticketFilter: _ticketFilter,
          mitgliedernummer: widget.currentMitgliedernummer,
          users: _users,
          onRefresh: _loadTickets,
          onFilterChanged: (filter) {
            setState(() => _ticketFilter = filter);
            _loadTickets(filter: filter == 'all' ? null : filter);
          },
          onTicketAction: _updateTicket,
          initialFocusTicketId: _pendingFocusTicketId,
          onFocusConsumed: () => setState(() => _pendingFocusTicketId = null),
        );
      case 3:
        return TerminverwaltungScreen(
          currentMitgliedernummer: widget.currentMitgliedernummer,
          initialFocusTerminId: _pendingFocusTerminId,
          onFocusConsumed: () => setState(() => _pendingFocusTerminId = null),
        );
      case 4:
        return VereinverwaltungScreen(
          apiService: _apiService,
          users: _users,
          getRoleColor: getRoleColor,
          getRoleText: getRoleText,
          mitgliedernummer: widget.currentMitgliedernummer,
        );
      case 5:
        return const NetzwerkScreen();
      case 6:
        return const FinanzverwaltungScreen();
      case 7:
        return StatistikScreen(apiService: _apiService, users: _users, currentMitgliedernummer: widget.currentMitgliedernummer);
      case 8:
        return ArchivScreen(apiService: _apiService, users: _users);
      case 9:
        return const DiensteScreen();
      case 10:
        return RoutinenaufgabenScreen(
          users: _users,
          currentMitgliedernummer: widget.currentMitgliedernummer,
          initialFocusRoutineExecutionId: _pendingFocusRoutineExecutionId,
          onFocusConsumed: () => setState(() => _pendingFocusRoutineExecutionId = null),
        );
      case 11:
        return BugReportsScreen(currentMitgliedernummer: widget.currentMitgliedernummer);
      case 12:
        return PendingParentConsentScreen(currentMitgliedernummer: widget.currentMitgliedernummer);
      case 13:
        return EinstellungenScreen(apiService: _apiService);
      case 14:
        return ArbeitsbereichScreen(
          onNavigate: (idx, {int? focusTicketId, int? focusTerminId, int? focusRoutineExecutionId}) => setState(() {
            _selectedMenuIndex = idx;
            _pendingFocusTicketId = focusTicketId;
            _pendingFocusTerminId = focusTerminId;
            _pendingFocusRoutineExecutionId = focusRoutineExecutionId;
          }),
        );
      default:
        return _buildDashboardOverview();
    }
  }

  Widget _buildDashboardOverview() {
    // User stats
    final totalUsers = _users.length;
    final activeUsers = _users.where((u) => u.isActive).length;
    final newUsers = _users.where((u) => u.isNeu).length;
    final suspendedUsers = _users.where((u) => u.isSuspended).length;
    final gekuendigtUsers = _users.where((u) => u.isGekuendigt).length;

    // Role counts
    final mitglieder = _users.where((u) => u.role == 'mitglied').length;
    final vorsitzer = _users.where((u) => u.role == 'vorsitzer').length;
    final schatzmeister = _users.where((u) => u.role == 'schatzmeister').length;
    final kassierer = _users.where((u) => u.role == 'kassierer').length;

    // Ticket stats
    final ts = _ticketStats;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          FaltbareKopfleiste(
            // Bei doppelter Systemschrift passt die Beschriftung des
            // Knopfes allein nicht mehr neben die Überschrift — kein
            // Kürzen hilft da, nur Umbrechen.
            links: [
              const Icon(Icons.dashboard, size: 28, color: Color(0xFF4a90d9)),
              const Text(
                'Dashboard',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ],
            aktionen: [
              // Reveal/hide dashboard data
              IconButton(
                icon: Icon(
                  _dashboardRevealed ? Icons.visibility : Icons.visibility_off,
                  color: _dashboardRevealed ? Colors.green : F.h(Colors.grey, 500),
                ),
                tooltip: _dashboardRevealed ? 'Daten ausblenden' : 'Daten anzeigen',
                onPressed: () => setState(() => _dashboardRevealed = !_dashboardRevealed),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Aktualisieren',
                onPressed: () {
                  _loadUsers();
                  _loadTickets();
                  _loadWeeklyTime();
                },
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Section: Mitglieder
          const Text(
            'Mitglieder',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _dashCard('Gesamt', _dashboardRevealed ? '$totalUsers' : '***', Icons.people, Colors.blue),
              _dashCard('Aktiv', _dashboardRevealed ? '$activeUsers' : '***', Icons.check_circle, Colors.green),
              _dashCard('Neu', _dashboardRevealed ? '$newUsers' : '***', Icons.fiber_new, Colors.amber.shade700),
              _dashCard('Gesperrt', _dashboardRevealed ? '$suspendedUsers' : '***', Icons.pause_circle, Colors.orange),
              _dashCard('Gekündigt', _dashboardRevealed ? '$gekuendigtUsers' : '***', Icons.exit_to_app, Colors.brown),
            ],
          ),
          const SizedBox(height: 24),

          // Section: Rollen
          const Text(
            'Rollen',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _dashCard('Mitglieder', _dashboardRevealed ? '$mitglieder' : '***', Icons.person, Colors.blue),
              _dashCard('Vorsitzer', _dashboardRevealed ? '$vorsitzer' : '***', Icons.admin_panel_settings, Colors.purple),
              _dashCard('Schatzmeister', _dashboardRevealed ? '$schatzmeister' : '***', Icons.account_balance, Colors.indigo),
              _dashCard('Kassierer', _dashboardRevealed ? '$kassierer' : '***', Icons.point_of_sale, Colors.teal),
            ],
          ),
          const SizedBox(height: 24),

          // Section: Tickets
          const Text(
            'Tickets',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          if (ts != null)
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _dashCard('Gesamt', _dashboardRevealed ? '${ts.total}' : '***', Icons.confirmation_number, Colors.blue),
                _dashCard('Offen', _dashboardRevealed ? '${ts.open}' : '***', Icons.inbox, Colors.red),
                _dashCard('In Bearbeitung', _dashboardRevealed ? '${ts.inProgress}' : '***', Icons.hourglass_top, Colors.orange),
                _dashCard('Warten (Mitglied)', _dashboardRevealed ? '${ts.waitingMember}' : '***', Icons.person_outline, Colors.amber.shade700),
                _dashCard('Warten (Amt)', _dashboardRevealed ? '${ts.waitingAuthority}' : '***', Icons.account_balance, Colors.deepPurple),
                _dashCard('Erledigt', _dashboardRevealed ? '${ts.done}' : '***', Icons.check_circle, Colors.green),
              ],
            )
          else
            const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 24),

          // Section: Arbeitszeit
          _buildWeeklyTimeSection(),
        ],
      ),
    );
  }

  Widget _buildWeeklyTimeSection() {
    final wt = _weeklyTime;
    if (wt == null) {
      return const SizedBox.shrink();
    }

    final progressColor = wt.isOverLimit ? Colors.red : Colors.green;
    final progressValue = wt.progressPercent.clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Arbeitszeit',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: F.h(Colors.blue, 50),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'KW ${wt.kw}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: F.h(Colors.blue, 700)),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${wt.weekStart.substring(8, 10)}.${wt.weekStart.substring(5, 7)}. - ${wt.weekEnd.substring(8, 10)}.${wt.weekEnd.substring(5, 7)}.',
              style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Progress bar
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.timer, color: progressColor, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      _dashboardRevealed ? wt.totalDisplay : '**:**',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: progressColor),
                    ),
                    Text(
                      _dashboardRevealed ? ' / ${wt.maxDisplay}' : ' / **:**',
                      style: TextStyle(fontSize: 16, color: F.h(Colors.grey, 500)),
                    ),
                    const Spacer(),
                    if (wt.isOverLimit)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: F.h(Colors.red, 50),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.warning_amber, size: 14, color: F.h(Colors.red, 700)),
                            const SizedBox(width: 4),
                            Text('Limit erreicht', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: F.h(Colors.red, 700))),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: _dashboardRevealed ? progressValue : 0.0,
                    minHeight: 10,
                    backgroundColor: F.h(Colors.grey, 200),
                    valueColor: AlwaysStoppedAnimation<Color>(_dashboardRevealed ? progressColor : Colors.grey.shade300),
                  ),
                ),
                const SizedBox(height: 12),
                // Category breakdown
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _timeChip(Icons.directions_car, 'Fahrzeit', wt.summary.fahrzeitDisplay, Colors.blue),
                    _timeChip(Icons.work, 'Arbeitszeit', wt.summary.arbeitszeitDisplay, Colors.green),
                    _timeChip(Icons.hourglass_empty, 'Wartezeit', wt.summary.wartezeitDisplay, Colors.orange),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _timeChip(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
          const SizedBox(width: 6),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _dashCard(String title, String value, IconData icon, Color color) {
    return SizedBox(
      width: 180,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FaltbareKopfleiste(
                // Bei doppelter Systemschrift passt die Beschriftung des
                // Knopfes allein nicht mehr neben die Überschrift — kein
                // Kürzen hilft da, nur Umbrechen.
                links: [
                  Icon(icon, color: color, size: 24),
                ],
                aktionen: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  color: F.h(Colors.grey, 600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<User> _filterUsersByTab(int tabIndex) {
    switch (tabIndex) {
      case 0: // Alle
        return _users;
      case 1: // Mitglieder — only currently-membered statuses: active, neu, passiv
        return _users.where((u) =>
          (u.role == 'mitglied' || u.role == 'ehrenmitglied' || u.role == 'foerdermitglied') &&
          (u.isActive || u.isNeu || u.isPassiv)
        ).toList();
      case 2: // Ehrenamtlich
        return _users.where((u) => u.role == 'ehrenamtlich').toList();
      case 3: // Vorstand
        return _users.where((u) => isVorstandRole(u.role)).toList();
      case 4: // Kassierer
        return _users.where((u) => u.role == 'kassierer' || u.role == 'kassenprufer').toList();
      case 5: // Gründungsmitglieder
        return _users.where((u) => u.role == 'mitgliedergrunder').toList();
      case 6: // Neu — newly registered, regardless of role
        return _users.where((u) => u.isNeu).toList();
      case 7: // Pasiv — pays Beitrag but doesn't actively participate
        return _users.where((u) => u.isPassiv).toList();
      case 8: // Nicht verifiziert — identity not yet confirmed (30-day window)
        return _users.where((u) => u.isNichtVerifiziert).toList();
      case 9: // Gekündigt — covers all three cancellation statuses, regardless of role
        return _users.where((u) => u.isGekuendigt).toList();
      default:
        return _users;
    }
  }

  Widget _buildMitgliederverwaltung() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadUsers,
              child: const Text('Erneut versuchen'),
            ),
          ],
        ),
      );
    }

    // Validation queue — applicants whose registration is awaiting Vorstand
    // action: status 'neu' (wizard finalized, never reviewed) or
    // 'nicht_verifiziert' (registered but not validated within deadline).
    // Surfaces as a floating button so the queue is reachable from anywhere
    // in the Mitgliederverwaltung, not just by switching to the right tab.
    final validationQueue = _users
        .where((u) => u.isNeu || u.isNichtVerifiziert)
        .toList()
      ..sort((a, b) =>
          (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000)));

    return Stack(
      children: [
        DefaultTabController(
      length: 10,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 280,
                  height: 36,
                  child: TextField(
                    controller: _memberSearchController,
                    decoration: InputDecoration(
                      hintText: 'Mitglied suchen (Name, Nr.)',
                      hintStyle: TextStyle(fontSize: 13, color: F.h(Colors.grey, 400)),
                      prefixIcon: Icon(Icons.search, size: 18, color: Colors.blue.shade400),
                      suffixIcon: _memberSearchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, size: 16, color: F.h(Colors.grey, 500)),
                              padding: EdgeInsets.zero,
                              onPressed: () { _memberSearchController.clear(); setState(() => _memberSearchQuery = ''); },
                            )
                          : null,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: F.h(Colors.grey, 300))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: F.h(Colors.grey, 300))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.blue.shade400, width: 1.5)),
                      filled: true,
                      fillColor: F.flaeche,
                    ),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (v) => setState(() => _memberSearchQuery = v.trim()),
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _showAddMemberDialog,
                  icon: const Icon(Icons.person_add),
                  label: const Text('Neues Mitglied'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Container(
            color: F.h(Colors.grey, 50),
            child: TabBar(
              labelColor: F.h(Colors.blue, 800),
              unselectedLabelColor: F.h(Colors.grey, 600),
              indicatorColor: Colors.blue.shade800,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                _buildMitgliederTab('Alle', _users.length, Icons.groups),
                _buildMitgliederTab('Mitglieder', _users.where((u) =>
                  (u.role == 'mitglied' || u.role == 'ehrenmitglied' || u.role == 'foerdermitglied') &&
                  (u.isActive || u.isNeu || u.isPassiv)
                ).length, Icons.person),
                _buildMitgliederTab('Ehrenamtlich', _users.where((u) => u.role == 'ehrenamtlich').length, Icons.volunteer_activism),
                _buildMitgliederTab('Vorstand', _users.where((u) => isVorstandRole(u.role)).length, Icons.admin_panel_settings),
                _buildMitgliederTab('Kassierer', _users.where((u) => u.role == 'kassierer' || u.role == 'kassenprufer').length, Icons.account_balance_wallet),
                _buildMitgliederTab('Gründungsmitglieder', _users.where((u) => u.role == 'mitgliedergrunder').length, Icons.star),
                _buildMitgliederTab('Neu', _users.where((u) => u.isNeu).length, Icons.fiber_new),
                _buildMitgliederTab('Pasiv', _users.where((u) => u.isPassiv).length, Icons.pause_circle_outline),
                _buildMitgliederTab('Nicht verifiziert', _users.where((u) => u.isNichtVerifiziert).length, Icons.help_outline),
                _buildMitgliederTab('Gekündigt', _users.where((u) => u.isGekuendigt).length, Icons.person_off),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Builder(
              builder: (context) {
                return AnimatedBuilder(
                  animation: DefaultTabController.of(context),
                  builder: (context, _) {
                    final currentIndex = DefaultTabController.of(context).index;
                    var filteredUsers = _filterUsersByTab(currentIndex);
                    if (_memberSearchQuery.isNotEmpty) {
                      final q = _memberSearchQuery.toLowerCase();
                      filteredUsers = filteredUsers.where((u) =>
                        u.name.toLowerCase().contains(q) ||
                        u.mitgliedernummer.toLowerCase().contains(q) ||
                        u.email.toLowerCase().contains(q)
                      ).toList();
                    }
                    return filteredUsers.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.people_outline, size: 64, color: F.h(Colors.grey, 300)),
                                const SizedBox(height: 16),
                                Text('Keine Mitglieder in dieser Kategorie', style: TextStyle(color: F.h(Colors.grey, 500))),
                              ],
                            ),
                          )
                        : UserDataTable(
                            users: filteredUsers,
                            currentMitgliedernummer: widget.currentMitgliedernummer,
                            onUserTap: _showUserDetailsDialog,
                            onStatusChange: _updateUserStatus,
                            onDelete: _deleteUser,
                            memberActivity: _memberActivity,
                          );
                  },
                );
              },
            ),
          ),
        ],
      ),
        ),
        if (_pendingMyVote.isNotEmpty)
          Positioned(
            right: 24,
            bottom: validationQueue.isNotEmpty ? 92 : 24,
            child: FloatingActionButton.extended(
              heroTag: 'mitgliederverwaltung_my_vote_fab',
              backgroundColor: Colors.purple.shade700,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.how_to_vote),
              label: Text('Mein Vote (${_pendingMyVote.length})'),
              onPressed: _showPendingMyVote,
            ),
          ),
        if (validationQueue.isNotEmpty)
          Positioned(
            right: 24,
            bottom: 24,
            child: FloatingActionButton.extended(
              heroTag: 'mitgliederverwaltung_validation_queue_fab',
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.pending_actions),
              label: Text('Validierung (${validationQueue.length})'),
              onPressed: () => _showValidationQueue(validationQueue),
            ),
          ),
      ],
    );
  }

  Future<void> _refreshPendingMyVote() async {
    try {
      final r = await _apiService.listPendingMyVote();
      if (!mounted) return;
      if (r['success'] == true && r['data'] is List) {
        setState(() {
          _pendingMyVote = (r['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        });
      }
    } catch (_) {}
  }

  void _showPendingMyVote() {
    final df = DateFormat('dd.MM.yyyy');
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => Dialog(
        insetPadding: const EdgeInsets.all(40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: F.h(Colors.purple, 50),
                border: Border(bottom: BorderSide(color: F.h(Colors.purple, 200))),
              ),
              child: Row(children: [
                Icon(Icons.how_to_vote, color: F.h(Colors.purple, 700), size: 26),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Wartet auf meinen Vote',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: F.h(Colors.purple, 900))),
                  Text('${_pendingMyVote.length} Antragsteller',
                    style: TextStyle(fontSize: 12, color: F.h(Colors.purple, 700))),
                ])),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(dialogCtx)),
              ]),
            ),
            Flexible(
              child: _pendingMyVote.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.check_circle_outline, size: 64, color: Colors.green.shade300),
                        const SizedBox(height: 12),
                        Text('Keine offenen Stimmen', style: TextStyle(fontSize: 14, color: F.h(Colors.grey, 600))),
                      ]),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _pendingMyVote.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final p = _pendingMyVote[i];
                        final vorname = p['vorname']?.toString() ?? '';
                        final nachname = p['nachname']?.toString() ?? '';
                        final mnr = p['mitgliedernummer']?.toString() ?? '';
                        final count = p['pending_stufen_count'] ?? 0;
                        final created = p['created_at']?.toString();
                        DateTime? createdDt;
                        try { createdDt = created != null ? DateTime.parse(created) : null; } catch (_) {}
                        return Card(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: F.h(Colors.purple, 100),
                              child: Icon(Icons.person, color: F.h(Colors.purple, 700)),
                            ),
                            title: Text('$vorname $nachname'.trim().isEmpty ? mnr : '$vorname $nachname'.trim(),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Nr.: $mnr', style: const TextStyle(fontSize: 11)),
                              if (createdDt != null)
                                Text('Beantragt: ${df.format(createdDt)}', style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
                            ]),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.purple.shade600,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text('$count Stufen',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                            ),
                            onTap: () {
                              Navigator.pop(dialogCtx);
                              final uid = int.tryParse(p['id']?.toString() ?? '');
                              if (uid == null) return;
                              final match = _users.where((u) => u.id == uid).firstOrNull;
                              if (match != null) _showUserDetailsDialog(match);
                            },
                          ),
                        );
                      },
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  void _showValidationQueue(List<User> queue) {
    final df = DateFormat('dd.MM.yyyy, HH:mm');
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => Dialog(
        insetPadding: const EdgeInsets.all(40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade700,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(children: [
                  const Icon(Icons.pending_actions, color: Colors.white, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Validierungs-Warteschlange',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${queue.length} Antrag${queue.length == 1 ? "" : "äge"} '
                          'wartet auf Prüfung durch den Vorstand',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(dialogCtx),
                  ),
                ]),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: queue.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final u = queue[i];
                    final isNeu = u.isNeu;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isNeu ? F.h(Colors.blue, 100) : F.h(Colors.amber, 100),
                        child: Icon(
                          isNeu ? Icons.fiber_new : Icons.help_outline,
                          color: isNeu ? F.h(Colors.blue, 800) : F.h(Colors.amber, 800),
                          size: 22,
                        ),
                      ),
                      title: Text(
                        u.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${u.mitgliedernummer} · ${u.email}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          if (u.createdAt != null)
                            Text(
                              'Registriert am ${df.format(u.createdAt!.toLocal())}',
                              style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600)),
                            ),
                        ],
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isNeu ? F.h(Colors.blue, 50) : F.h(Colors.amber, 50),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isNeu ? F.h(Colors.blue, 300) : F.h(Colors.amber, 300),
                          ),
                        ),
                        child: Text(
                          isNeu ? 'NEU' : 'Nicht verifiziert',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isNeu ? F.h(Colors.blue, 800) : F.h(Colors.amber, 800),
                          ),
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(dialogCtx);
                        _showUserDetailsDialog(u);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMitgliederTab(String label, int count, IconData icon) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Text(label),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: F.h(Colors.grey, 300),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: F.h(Colors.grey, 700)),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddMemberDialog() {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    String selectedRole = 'mitglied';
    bool isSubmitting = false;
    bool obscurePassword = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.person_add, color: F.h(Colors.green, 700)),
                const SizedBox(width: 12),
                const Text('Neues Mitglied hinzufügen'),
              ],
            ),
            content: SizedBox(
              width: 450,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Name',
                        prefixIcon: const Icon(Icons.person),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: emailController,
                      decoration: InputDecoration(
                        labelText: 'E-Mail',
                        prefixIcon: const Icon(Icons.email),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: passwordController,
                      obscureText: obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Passwort',
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(
                          icon: Icon(obscurePassword ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setDialogState(() => obscurePassword = !obscurePassword),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        hintText: 'Mindestens 6 Zeichen',
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      // Ohne `isExpanded` richtet sich ein Dropdown nach seinem
                      // breitesten Eintrag, nicht nach dem Feld. Ein langer Name
                      // sprengte damit die Zeile — gemessen 241 dp in
                      // ordnungsmassnahmen_screen. Als Formularfeld soll es
                      // ohnehin die volle Breite haben.
                      isExpanded: true,
                      initialValue: selectedRole,
                      decoration: InputDecoration(
                        labelText: 'Rolle',
                        prefixIcon: const Icon(Icons.badge),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: allRoles
                          .map((r) => DropdownMenuItem(
                                value: r['value'] as String,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: getRoleColor(r['value'] as String),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(r['label'] as String),
                                  ],
                                ),
                              ))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedRole = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: F.h(Colors.amber, 50),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: F.h(Colors.amber, 200)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: F.h(Colors.amber, 800), size: 20),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Das Mitglied wird mit Status "Neu" erstellt und muss noch verifiziert werden.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                child: const Text('Abbrechen'),
              ),
              ElevatedButton(
                onPressed: isSubmitting ? null : () async {
                  final name = nameController.text.trim();
                  final email = emailController.text.trim();
                  final password = passwordController.text;

                  if (name.isEmpty || email.isEmpty || password.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Bitte alle Felder ausfüllen'), backgroundColor: Colors.orange),
                    );
                    return;
                  }

                  if (password.length < 6) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Passwort muss mindestens 6 Zeichen haben'), backgroundColor: Colors.orange),
                    );
                    return;
                  }

                  setDialogState(() => isSubmitting = true);

                  try {
                    final result = await _apiService.adminRegisterMember(
                      name: name,
                      email: email,
                      password: password,
                      role: selectedRole,
                    );

                    if (!ctx.mounted) return;

                    if (result['success'] == true) {
                      final mitgliedernummer = result['user']?['mitgliedernummer'] ?? '';
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: Text('Mitglied $name erstellt ($mitgliedernummer)'),
                          backgroundColor: Colors.green,
                        ),
                      );
                      _loadUsers();
                    } else {
                      setDialogState(() => isSubmitting = false);
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: Text(result['message'] ?? 'Fehler beim Erstellen'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  } catch (e) {
                    if (!ctx.mounted) return;
                    setDialogState(() => isSubmitting = false);
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                ),
                child: isSubmitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Mitglied erstellen'),
              ),
            ],
          );
        },
      ),
    );
  }
}


// ══════════════════════════════════════════════════════════════
// NEWS DIALOG (Tagesschau RSS — national + regional)
// ══════════════════════════════════════════════════════════════

class _NewsDialog extends StatefulWidget {
  final NewsService newsService;

  const _NewsDialog({required this.newsService});

  @override
  State<_NewsDialog> createState() => _NewsDialogState();
}

class _NewsDialogState extends State<_NewsDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    final hasRegional = widget.newsService.regionalNews.isNotEmpty ||
        widget.newsService.regionName != null;
    _tabController = TabController(length: hasRegional ? 2 : 1, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    await widget.newsService.refresh();
    if (mounted) {
      setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasRegional = widget.newsService.regionalNews.isNotEmpty ||
        widget.newsService.regionName != null;
    final regionName = widget.newsService.regionName ?? 'Regional';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 600,
        height: 550,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  Icon(Icons.newspaper, color: F.h(Colors.deepOrange, 700), size: 24),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Nachrichten',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (_isRefreshing)
                    const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      tooltip: 'Aktualisieren',
                      onPressed: _refresh,
                    ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Tabs
            TabBar(
              controller: _tabController,
              labelColor: F.h(Colors.deepOrange, 700),
              unselectedLabelColor: F.h(Colors.grey, 500),
              indicatorColor: Colors.deepOrange.shade700,
              tabs: [
                const Tab(text: 'Deutschland'),
                if (hasRegional) Tab(text: regionName),
              ],
            ),
            // Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildNewsList(widget.newsService.nationalNews),
                  if (hasRegional) _buildNewsList(widget.newsService.regionalNews),
                ],
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: F.h(Colors.grey, 200))),
              ),
              child: Text(
                'Quelle: tagesschau.de (ARD)',
                style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 500)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewsList(List<NewsArticle> articles) {
    if (articles.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.article_outlined, size: 48, color: F.h(Colors.grey, 500)),
            SizedBox(height: 12),
            Text('Keine Nachrichten verfügbar',
                style: TextStyle(color: F.h(Colors.grey, 500))),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: articles.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: F.h(Colors.grey, 200)),
      itemBuilder: (context, index) {
        final article = articles[index];
        return _buildArticleItem(article);
      },
    );
  }

  Widget _buildArticleItem(NewsArticle article) {
    return InkWell(
      onTap: () {
        // Open article link in browser
        _openUrl(article.link);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            if (article.imageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  article.imageUrl!.contains('width=')
                      ? article.imageUrl!
                      : '${article.imageUrl!}?width=120',
                  width: 90,
                  height: 60,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 90,
                    height: 60,
                    decoration: BoxDecoration(
                      color: F.h(Colors.grey, 200),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.image, color: F.h(Colors.grey, 500)),
                  ),
                ),
              ),
            if (article.imageUrl != null) const SizedBox(width: 12),
            // Text content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    article.description,
                    style: TextStyle(
                      fontSize: 12,
                      color: F.h(Colors.grey, 600),
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    article.timeAgo,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.deepOrange.shade400,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openUrl(String url) {
    if (url.isEmpty) return;
    try {
      final uri = Uri.parse(url);
      launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}
