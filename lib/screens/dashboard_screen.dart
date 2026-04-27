import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/api_service.dart';
import '../services/logger_service.dart';
import '../services/chat_service.dart';
import '../services/heartbeat_service.dart';
import '../services/tray_service.dart';
import '../services/ticket_service.dart';
import '../services/ticket_notification_service.dart';
import '../services/notification_service.dart';
import '../services/weather_service.dart';
import '../services/transit_service.dart';
import '../services/news_service.dart';
import '../services/radio_service.dart';
import '../services/ntfy_service.dart';
import '../services/diagnostic_service.dart';
import '../services/update_service.dart';
import '../widgets/login_approval_dialog.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/eastern.dart';
import '../models/user.dart';
import '../widgets/legal_footer.dart';
import '../widgets/admin_chat_dialog.dart';
import '../widgets/update_dialog.dart';
import '../widgets/incoming_call_dialog.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/moon.dart';
import 'login_screen.dart';
import 'terminverwaltung_screen.dart';
import '../widgets/profile_dialog.dart';
import '../widgets/user_details_dialog.dart';
import '../widgets/dashboard_sidebar.dart';
import '../widgets/dashboard_stats.dart';
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
import 'einstellungen_screen.dart';
import 'server_screen.dart';
import 'client_screen.dart';

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

  // Payment reminder
  Timer? _paymentReminderTimer;
  bool _paymentReminderShownToday = false;

  // Weather
  final _weatherService = WeatherService();
  WeatherData? _weatherData;
  List<WeatherAlert> _weatherAlerts = [];

  // Transit (DING EFA)
  final _transitService = TransitService();
  List<Departure> _departures = [];

  // News (Tagesschau RSS)
  final _newsService = NewsService();

  // Radio (HR Info live stream)
  final _radioService = RadioService();
  bool _radioPlaying = false;

  // Background conversation IDs for receiving messages
  List<int> _backgroundConversationIds = [];

  // Ticket management
  final _ticketService = TicketService();
  List<Ticket> _tickets = [];
  TicketStats? _ticketStats;
  bool _isLoadingTickets = false;
  String _ticketFilter = 'all'; // all, open, in_progress, closed

  // Weekly time tracking
  WeeklyTimeSummary? _weeklyTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Start periodic log upload to server (every 30s)
    _log.startUpload(widget.currentMitgliedernummer);

    _currentEmail = widget.currentEmail;
    _loadUsers();
    _loadTickets();
    _loadWeeklyTime();
    _connectWebSocket();
    _setupMessageListener();
    _setupTicketNotificationListener();
    _setupNotificationClickListener();
    _startTicketAutoRefresh();
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
    _autoUpdateTimer = Timer.periodic(const Duration(seconds: 60), (_) => _autoUpdateCheck());
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
      debugPrint('[Dashboard] App paused - UI timers stopped');
    } else if (state == AppLifecycleState.resumed) {
      _loadUsers();
      _autoUpdateCheck();
      _autoUpdateTimer = Timer.periodic(const Duration(seconds: 60), (_) => _autoUpdateCheck());
      debugPrint('[Dashboard] App resumed - data refreshed, update check restarted');
    }
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
    _newsService.stop();
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
        final path = await updateService.downloadUpdate(info.downloadUrl, (p) {});
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
      if (mounted) {
        setState(() {
          _unreadChatCount++;
        });
        _log.info('New message received, unread count: $_unreadChatCount', tag: 'DASH');
      }
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

      // Parse payload format: 'type:data'
      final parts = payload.split(':');
      final type = parts.isNotEmpty ? parts[0] : '';

      if (type == 'chat' && !_isAdminChatOpen) {
        _showAdminChatDialog();
      }
    });
  }

  void _startTicketAutoRefresh() {
    // Auto-refresh tickets every 30 seconds (fallback if WebSocket fails)
    _ticketRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted && _selectedMenuIndex == 2) {
        // Only refresh if we're on Ticketverwaltung tab
        _log.debug('Auto-refreshing tickets...', tag: 'TICKET');
        _loadTickets();
      }
      // Auto-refresh Arbeitszeit on dashboard overview
      if (mounted && _selectedMenuIndex == 0) {
        _loadWeeklyTime();
      }
    });
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
              }
            }
          }
        }
        if (totalUnread > 0 && mounted) {
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
        _transitService.onDeparturesUpdate = (deps) {
          if (mounted) setState(() => _departures = deps);
        };

        // When transit detects a new city (GPS moved >2km), update weather + news
        _transitService.onLocationChanged = (lat, lon, city) async {
          _log.info('Dashboard: Location changed → $city ($lat, $lon)', tag: 'WEATHER');
          await _weatherService.updateLocation(city, lat: lat, lon: lon);
          await _newsService.start(lat: lat, lon: lon);
        };

        // Start transit first (it gets GPS) then share coordinates with weather
        await _transitService.start(ort);

        // Use GPS coordinates from transit if available, else city fallback
        if (_transitService.latitude != null && _transitService.longitude != null) {
          final cityName = _transitService.gpsCity ?? ort;
          await _weatherService.start(
            cityName.isNotEmpty ? cityName : 'Mein Standort',
            lat: _transitService.latitude,
            lon: _transitService.longitude,
          );
        } else if (ort.isNotEmpty) {
          await _weatherService.start(ort);
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

  void _showWeatherDialog() {
    final weather = _weatherData;
    if (weather == null) return;

    final df = DateFormat('HH:mm', 'de_DE');
    final dfDay = DateFormat('E dd.MM.', 'de_DE');
    final dfDayShort = DateFormat('E', 'de_DE');
    final now = DateTime.now();

    // Filter hourly forecast: next 24 hours
    final next24h = _weatherService.hourlyForecast
        .where((h) => h.time.isAfter(now) && h.time.isBefore(now.add(const Duration(hours: 25))))
        .toList();

    // Filter daily forecast: next 3 days
    final next3Days = _weatherService.dailyForecast.take(3).toList();

    // Full week (7 days)
    final weekForecast = _weatherService.dailyForecast.toList();

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: SizedBox(
          width: 520,
          height: 580,
          child: DefaultTabController(
            length: 4,
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Text(weather.icon, style: const TextStyle(fontSize: 32)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Wetter in ${weather.city}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                Text(
                                  '${weather.description} • ${weather.temperature.toStringAsFixed(1)}°C',
                                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh, size: 20),
                            tooltip: 'Aktualisieren',
                            onPressed: () async {
                              await _weatherService.refresh();
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (mounted) _showWeatherDialog();
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const TabBar(
                        labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        unselectedLabelStyle: TextStyle(fontSize: 12),
                        indicatorSize: TabBarIndicatorSize.tab,
                        tabs: [
                          Tab(text: 'Aktuell'),
                          Tab(text: 'Stündlich'),
                          Tab(text: '3 Tage'),
                          Tab(text: 'Woche'),
                        ],
                      ),
                    ],
                  ),
                ),
                // Tab content
                Expanded(
                  child: TabBarView(
                    children: [
                      // === TAB 1: Aktuell ===
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Current conditions
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  _weatherDetailColumn('Temperatur', '${weather.temperature.toStringAsFixed(1)}°C', Icons.thermostat),
                                  _weatherDetailColumn('Wind', '${weather.windSpeed.toStringAsFixed(0)} km/h', Icons.air),
                                  _weatherDetailColumn('Feuchtigkeit', '${weather.humidity}%', Icons.water_drop),
                                ],
                              ),
                            ),
                            // DWD Alerts
                            if (_weatherAlerts.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  const Icon(Icons.warning_amber, color: Colors.red, size: 18),
                                  const SizedBox(width: 6),
                                  Text(
                                    'DWD Warnungen (${_weatherAlerts.length})',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.red),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ..._weatherAlerts.map((alert) => _buildAlertCard(alert)),
                            ] else ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
                                    const SizedBox(width: 8),
                                    Text('Keine DWD Warnungen aktiv', style: TextStyle(fontSize: 12, color: Colors.green.shade700)),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Text(
                              'Daten: Open-Meteo • Warnungen: DWD via Bright Sky',
                              style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),

                      // === TAB 2: Stündlich (next 24h) ===
                      next24h.isEmpty
                          ? const Center(child: Text('Keine stündlichen Daten verfügbar'))
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: next24h.length,
                              itemBuilder: (_, i) {
                                final h = next24h[i];
                                final isNow = i == 0;
                                return Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isNow ? Colors.blue.shade50 : (i.isEven ? Colors.grey.shade50 : null),
                                    borderRadius: BorderRadius.circular(6),
                                    border: isNow ? Border.all(color: Colors.blue.shade200) : null,
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 45,
                                        child: Text(
                                          df.format(h.time),
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: isNow ? FontWeight.bold : FontWeight.normal,
                                            color: isNow ? Colors.blue.shade800 : null,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(h.icon, style: const TextStyle(fontSize: 18)),
                                      const SizedBox(width: 10),
                                      SizedBox(
                                        width: 50,
                                        child: Text(
                                          '${h.temperature.toStringAsFixed(1)}°',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: h.temperature < 0 ? Colors.blue.shade800 : Colors.orange.shade800,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(Icons.air, size: 14, color: Colors.grey.shade500),
                                      const SizedBox(width: 2),
                                      SizedBox(
                                        width: 55,
                                        child: Text(
                                          '${h.windSpeed.toStringAsFixed(0)} km/h',
                                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                        ),
                                      ),
                                      if (h.precipitation > 0) ...[
                                        Icon(Icons.water_drop, size: 14, color: Colors.blue.shade400),
                                        const SizedBox(width: 2),
                                        Text(
                                          '${h.precipitation.toStringAsFixed(1)} mm',
                                          style: TextStyle(fontSize: 11, color: Colors.blue.shade600),
                                        ),
                                      ],
                                      const Spacer(),
                                      SizedBox(
                                        width: 90,
                                        child: Text(
                                          h.description,
                                          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),

                      // === TAB 3: 3 Tage ===
                      next3Days.isEmpty
                          ? const Center(child: Text('Keine Vorhersage verfügbar'))
                          : SingleChildScrollView(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                children: next3Days.map((d) => _buildDayForecastCard(d, dfDay)).toList(),
                              ),
                            ),

                      // === TAB 4: Woche ===
                      weekForecast.isEmpty
                          ? const Center(child: Text('Keine Vorhersage verfügbar'))
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: weekForecast.length,
                              itemBuilder: (_, i) {
                                final d = weekForecast[i];
                                final isToday = d.date.day == now.day && d.date.month == now.month;
                                return Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isToday ? Colors.blue.shade50 : (i.isEven ? Colors.grey.shade50 : null),
                                    borderRadius: BorderRadius.circular(8),
                                    border: isToday ? Border.all(color: Colors.blue.shade200) : null,
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 35,
                                        child: Text(
                                          isToday ? 'Heu.' : dfDayShort.format(d.date),
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(d.icon, style: const TextStyle(fontSize: 20)),
                                      const SizedBox(width: 10),
                                      // Temperature range bar
                                      Text(
                                        '${d.tempMin.toStringAsFixed(0)}°',
                                        style: TextStyle(fontSize: 13, color: Colors.blue.shade700),
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: _buildTempRangeBar(d.tempMin, d.tempMax, weekForecast),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${d.tempMax.toStringAsFixed(0)}°',
                                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange.shade800),
                                      ),
                                      const SizedBox(width: 10),
                                      if (d.precipitationSum > 0) ...[
                                        Icon(Icons.water_drop, size: 14, color: Colors.blue.shade400),
                                        Text(
                                          d.precipitationSum.toStringAsFixed(1),
                                          style: TextStyle(fontSize: 11, color: Colors.blue.shade600),
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      Icon(Icons.air, size: 14, color: Colors.grey.shade400),
                                      const SizedBox(width: 2),
                                      SizedBox(
                                        width: 30,
                                        child: Text(
                                          d.windSpeedMax.toStringAsFixed(0),
                                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAlertCard(WeatherAlert alert) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _alertColor(alert.severity).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _alertColor(alert.severity).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _alertColor(alert.severity),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  alert.severityLabel,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(alert.event, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(alert.headline, style: const TextStyle(fontSize: 11)),
          if (alert.onset != null || alert.expires != null) ...[
            const SizedBox(height: 4),
            Text(
              [
                if (alert.onset != null) 'Von: ${alert.onset!.day}.${alert.onset!.month}.${alert.onset!.year} ${alert.onset!.hour}:${alert.onset!.minute.toString().padLeft(2, '0')}',
                if (alert.expires != null) 'Bis: ${alert.expires!.day}.${alert.expires!.month}.${alert.expires!.year} ${alert.expires!.hour}:${alert.expires!.minute.toString().padLeft(2, '0')} Uhr',
              ].join(' • '),
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDayForecastCard(DailyForecast day, DateFormat dfDay) {
    final now = DateTime.now();
    final isToday = day.date.day == now.day && day.date.month == now.month;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: isToday ? 2 : 0.5,
      color: isToday ? Colors.blue.shade50 : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: isToday ? BorderSide(color: Colors.blue.shade200) : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(day.icon, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isToday ? 'Heute' : dfDay.format(day.date),
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isToday ? Colors.blue.shade800 : null),
                      ),
                      Text(day.description, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${day.tempMax.toStringAsFixed(0)}°C',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange.shade800),
                    ),
                    Text(
                      '${day.tempMin.toStringAsFixed(0)}°C',
                      style: TextStyle(fontSize: 13, color: Colors.blue.shade700),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _weatherSmallInfo(Icons.air, '${day.windSpeedMax.toStringAsFixed(0)} km/h'),
                _weatherSmallInfo(Icons.water_drop, '${day.precipitationSum.toStringAsFixed(1)} mm'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTempRangeBar(double tempMin, double tempMax, List<DailyForecast> all) {
    // Calculate range across all days for normalization
    double globalMin = all.fold(double.infinity, (v, d) => d.tempMin < v ? d.tempMin : v);
    double globalMax = all.fold(-double.infinity, (v, d) => d.tempMax > v ? d.tempMax : v);
    final range = globalMax - globalMin;
    if (range <= 0) return const SizedBox();

    final leftFraction = (tempMin - globalMin) / range;
    final widthFraction = (tempMax - tempMin) / range;

    return LayoutBuilder(
      builder: (_, constraints) {
        final totalWidth = constraints.maxWidth;
        return Stack(
          children: [
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Positioned(
              left: leftFraction * totalWidth,
              child: Container(
                width: (widthFraction * totalWidth).clamp(4, totalWidth),
                height: 4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade300, Colors.orange.shade400],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _weatherSmallInfo(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
      ],
    );
  }

  Widget _weatherDetailColumn(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Colors.blue.shade700),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue.shade800)),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      ],
    );
  }

  Color _alertColor(String severity) {
    switch (severity) {
      case 'extreme': return Colors.red.shade800;
      case 'severe': return Colors.orange.shade700;
      case 'moderate': return Colors.amber.shade700;
      default: return Colors.yellow.shade700;
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

  void _showTransitDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _TransitDialog(
        transitService: _transitService,
        departures: _departures,
        city: _weatherData?.city ?? '',
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

  Future<void> _updateTicket(int ticketId, String action) async {
    final result = await _ticketService.updateTicket(
      mitgliedernummer: widget.currentMitgliedernummer,
      ticketId: ticketId,
      action: action,
    );

    if (result != null) {
      _loadTickets();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_getActionMessage(action)),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  String _getActionMessage(String action) {
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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => UserDetailsDialog(
        user: user,
        apiService: _apiService,
        adminMitgliedernummer: widget.currentMitgliedernummer,
        onUpdated: () {
          _loadUsers(); // Reload user list after update
        },
      ),
    );
  }

  void _showAdminChatDialog() {
    _showAdminChatDialogInternal(null);
  }

  void _showAdminChatDialogWithCall() {
    _showAdminChatDialogInternal(_pendingCall);
  }

  void _showAdminChatDialogInternal(CallOfferEvent? pendingCall) {
    // Clear unread count when opening chat
    setState(() {
      _unreadChatCount = 0;
      _isAdminChatOpen = true;
    });
    // Also clear tray unread count
    TrayService().clearUnread();

    showDialog(
      context: context,
      builder: (context) => AdminChatDialog(
        mitgliedernummer: widget.currentMitgliedernummer,
        userName: widget.userName,
        pendingCall: pendingCall,
      ),
    ).then((_) {
      // Mark dialog as closed
      setState(() {
        _isAdminChatOpen = false;
        _pendingCall = null;
      });
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

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
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
          // Moon phase & decision advisor
          if (!isMobile)
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
          if (!isMobile)
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
          // News (Tagesschau)
          if (!isMobile)
            IconButton(
              icon: const Icon(Icons.newspaper),
              tooltip: 'Nachrichten',
              onPressed: _showNewsDialog,
            ),
          // Transit (ÖPNV departures)
          if (!isMobile)
            IconButton(
              icon: const Icon(Icons.directions_bus),
              tooltip: 'ÖPNV Abfahrten',
              onPressed: _showTransitDialog,
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
          // Weather widget
          if (_weatherData != null && !isMobile)
            InkWell(
              onTap: () => _showWeatherDialog(),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_weatherData!.icon, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 4),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_weatherData!.temperature.toStringAsFixed(0)}°C',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        Text(
                          _weatherData!.city,
                          style: TextStyle(fontSize: 9, color: Colors.white.withValues(alpha: 0.7)),
                        ),
                      ],
                    ),
                    if (_weatherAlerts.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${_weatherAlerts.length}',
                          style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
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
      ),
      // Mobile: Use drawer for navigation
      drawer: isMobile
          ? Drawer(
              child: DashboardSidebar(
                userName: widget.userName,
                mitgliedernummer: widget.currentMitgliedernummer,
                selectedMenuIndex: _selectedMenuIndex,
                onMenuSelected: (index) {
                  setState(() => _selectedMenuIndex = index);
                  Navigator.pop(context); // Close drawer after selection
                },
              ),
            )
          : null,
      // Desktop: Sidebar + content, Mobile: Just content
      body: SeasonalBackground(
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
      // Mobile: Bottom navigation bar for quick access
      bottomNavigationBar: isMobile
          ? _buildMobileBottomNav()
          : const LegalFooter(darkMode: true),
    );
  }

  /// Mobile bottom navigation bar
  Widget _buildMobileBottomNav() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BottomNavigationBar(
          currentIndex: _selectedMenuIndex,
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
        );
      case 3:
        return TerminverwaltungScreen(currentMitgliedernummer: widget.currentMitgliedernummer);
      case 4:
        return VereinverwaltungScreen(
          apiService: _apiService,
          users: _users,
          getRoleColor: getRoleColor,
          getRoleText: getRoleText,
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
        );
      case 11:
        return const ServerScreen();
      case 12:
        return const ClientScreen();
      case 13:
        return EinstellungenScreen(apiService: _apiService);
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
          Row(
            children: [
              const Icon(Icons.dashboard, size: 28, color: Color(0xFF4a90d9)),
              const SizedBox(width: 12),
              const Text(
                'Dashboard',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              // Reveal/hide dashboard data
              IconButton(
                icon: Icon(
                  _dashboardRevealed ? Icons.visibility : Icons.visibility_off,
                  color: _dashboardRevealed ? Colors.green : Colors.grey,
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
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'KW ${wt.kw}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue.shade700),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${wt.weekStart.substring(8, 10)}.${wt.weekStart.substring(5, 7)}. - ${wt.weekEnd.substring(8, 10)}.${wt.weekEnd.substring(5, 7)}.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
                      style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
                    ),
                    const Spacer(),
                    if (wt.isOverLimit)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.warning_amber, size: 14, color: Colors.red.shade700),
                            const SizedBox(width: 4),
                            Text('Limit erreicht', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
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
                    backgroundColor: Colors.grey.shade200,
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
              Row(
                children: [
                  Icon(icon, color: color, size: 24),
                  const Spacer(),
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
                  color: Colors.grey.shade600,
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
      case 1: // Mitglieder
        return _users.where((u) => u.role == 'mitglied' || u.role == 'ehrenmitglied' || u.role == 'foerdermitglied').toList();
      case 2: // Ehrenamtlich
        return _users.where((u) => u.role == 'ehrenamtlich').toList();
      case 3: // Vorstand
        return _users.where((u) => isVorstandRole(u.role)).toList();
      case 4: // Kassierer
        return _users.where((u) => u.role == 'kassierer' || u.role == 'kassenprufer').toList();
      case 5: // Gründungsmitglieder
        return _users.where((u) => u.role == 'mitgliedergrunder').toList();
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

    return DefaultTabController(
      length: 6,
      child: Column(
        children: [
          UserStatsBar(
            totalUsers: _dashboardRevealed ? _users.length : 0,
            activeUsers: _dashboardRevealed ? _users.where((u) => u.isActive).length : 0,
            newUsers: _dashboardRevealed ? _users.where((u) => u.isNeu).length : 0,
            suspendedUsers: _dashboardRevealed ? _users.where((u) => u.isSuspended).length : 0,
            gekuendigtUsers: _dashboardRevealed ? _users.where((u) => u.isGekuendigt).length : 0,
          ),
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
                      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                      prefixIcon: Icon(Icons.search, size: 18, color: Colors.blue.shade400),
                      suffixIcon: _memberSearchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, size: 16, color: Colors.grey.shade500),
                              padding: EdgeInsets.zero,
                              onPressed: () { _memberSearchController.clear(); setState(() => _memberSearchQuery = ''); },
                            )
                          : null,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.grey.shade300)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.grey.shade300)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.blue.shade400, width: 1.5)),
                      filled: true,
                      fillColor: Colors.white,
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
            color: Colors.grey.shade50,
            child: TabBar(
              labelColor: Colors.blue.shade800,
              unselectedLabelColor: Colors.grey.shade600,
              indicatorColor: Colors.blue.shade800,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                _buildMitgliederTab('Alle', _users.length, Icons.groups),
                _buildMitgliederTab('Mitglieder', _users.where((u) => u.role == 'mitglied' || u.role == 'ehrenmitglied' || u.role == 'foerdermitglied').length, Icons.person),
                _buildMitgliederTab('Ehrenamtlich', _users.where((u) => u.role == 'ehrenamtlich').length, Icons.volunteer_activism),
                _buildMitgliederTab('Vorstand', _users.where((u) => isVorstandRole(u.role)).length, Icons.admin_panel_settings),
                _buildMitgliederTab('Kassierer', _users.where((u) => u.role == 'kassierer' || u.role == 'kassenprufer').length, Icons.account_balance_wallet),
                _buildMitgliederTab('Gründungsmitglieder', _users.where((u) => u.role == 'mitgliedergrunder').length, Icons.star),
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
                                Icon(Icons.people_outline, size: 64, color: Colors.grey.shade300),
                                const SizedBox(height: 16),
                                Text('Keine Mitglieder in dieser Kategorie', style: TextStyle(color: Colors.grey.shade500)),
                              ],
                            ),
                          )
                        : UserDataTable(
                            users: filteredUsers,
                            currentMitgliedernummer: widget.currentMitgliedernummer,
                            onUserTap: _showUserDetailsDialog,
                            onStatusChange: _updateUserStatus,
                            onDelete: _deleteUser,
                          );
                  },
                );
              },
            ),
          ),
        ],
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
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
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
                Icon(Icons.person_add, color: Colors.green.shade700),
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
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.amber.shade800, size: 20),
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
// Transit Dialog — ÖPNV Abfahrten (DING EFA API)
// ══════════════════════════════════════════════════════════════

class _TransitDialog extends StatefulWidget {
  final TransitService transitService;
  final List<Departure> departures;
  final String city;

  const _TransitDialog({
    required this.transitService,
    required this.departures,
    required this.city,
  });

  @override
  State<_TransitDialog> createState() => _TransitDialogState();
}

class _TransitDialogState extends State<_TransitDialog> {
  late List<Departure> _departures;
  bool _isLoading = false;
  Timer? _autoRefresh;
  String? _selectedStop; // null = all stops

  @override
  void initState() {
    super.initState();
    _departures = List.from(widget.departures);

    // Default to closest stop
    _selectedStop = widget.transitService.closestStopName;

    // Auto-refresh every 30 seconds while dialog is open
    _autoRefresh = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());

    // If no data yet, fetch now
    if (_departures.isEmpty) {
      _refresh();
    }
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    await widget.transitService.refresh();
    if (mounted) {
      setState(() {
        _departures = List.from(widget.transitService.departures);
        _isLoading = false;
      });
    }
  }

  List<Departure> get _filteredDepartures {
    if (_selectedStop == null) return _departures;
    return _departures.where((d) => d.stopName == _selectedStop).toList();
  }

  /// Unique stop names from departures
  List<String> get _stopNames {
    final names = <String>{};
    for (final d in _departures) {
      if (d.stopName.isNotEmpty) names.add(d.stopName);
    }
    return names.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    final stops = _stopNames;
    final filtered = _filteredDepartures;
    final now = DateTime.now();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 500,
        height: 560,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.directions_bus, color: Colors.teal.shade700, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ÖPNV Abfahrten',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal.shade800),
                            ),
                            if (widget.transitService.closestStopName != null)
                              Row(
                                children: [
                                  Icon(Icons.location_on, size: 12, color: Colors.teal.shade400),
                                  const SizedBox(width: 2),
                                  Text(
                                    _buildSubtitle(),
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                  ),
                                ],
                              )
                            else
                              Text(
                                widget.city.isNotEmpty ? widget.city : 'Nahverkehr',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                          ],
                        ),
                      ),
                      if (_isLoading)
                        const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 20),
                          tooltip: 'Aktualisieren',
                          onPressed: _refresh,
                        ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  // Stop filter chips
                  if (stops.length > 1) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 32,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: const Text('Alle', style: TextStyle(fontSize: 11)),
                              selected: _selectedStop == null,
                              onSelected: (_) => setState(() => _selectedStop = null),
                              visualDensity: VisualDensity.compact,
                              selectedColor: Colors.teal.shade200,
                            ),
                          ),
                          ...stops.map((s) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(s, style: const TextStyle(fontSize: 11)),
                              selected: _selectedStop == s,
                              onSelected: (_) => setState(() => _selectedStop = s),
                              visualDensity: VisualDensity.compact,
                              selectedColor: Colors.teal.shade200,
                            ),
                          )),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Departure list
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.schedule, size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          Text(
                            _isLoading ? 'Abfahrten werden geladen...' : 'Keine Abfahrten gefunden',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final dep = filtered[i];
                        final mins = dep.minutesUntil;
                        final isPast = mins < 0;
                        if (isPast) return const SizedBox.shrink();

                        final isImminent = mins <= 2;
                        final isSoon = mins <= 5;

                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isImminent
                                ? Colors.red.shade50
                                : isSoon
                                    ? Colors.orange.shade50
                                    : (i.isEven ? Colors.grey.shade50 : null),
                            borderRadius: BorderRadius.circular(6),
                            border: isImminent ? Border.all(color: Colors.red.shade200) : null,
                          ),
                          child: Row(
                            children: [
                              // Line badge
                              Container(
                                width: 44,
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _lineColor(dep.productType),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  dep.line,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 10),
                              // Direction
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      dep.direction,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (_selectedStop == null && dep.stopName.isNotEmpty)
                                      Text(
                                        dep.stopName,
                                        style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              // Delay indicator
                              if (dep.delay > 0) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: dep.delay >= 5 ? Colors.red.shade100 : Colors.orange.shade100,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    '+${dep.delay}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: dep.delay >= 5 ? Colors.red.shade800 : Colors.orange.shade800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              // Platform
                              if (dep.platform != null) ...[
                                Text(
                                  dep.platform!,
                                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                                ),
                                const SizedBox(width: 6),
                              ],
                              // Time
                              SizedBox(
                                width: 42,
                                child: Text(
                                  dep.timeString,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade700,
                                    decoration: dep.delay > 0 ? TextDecoration.lineThrough : null,
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Minutes until
                              SizedBox(
                                width: 40,
                                child: Text(
                                  mins == 0 ? 'jetzt' : '$mins Min',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isImminent
                                        ? Colors.red.shade700
                                        : isSoon
                                            ? Colors.orange.shade700
                                            : Colors.teal.shade700,
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Text(
                    'Daten: ${widget.transitService.activeProvider?.displayName ?? 'ÖPNV'} • Echtzeit',
                    style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
                  ),
                  const Spacer(),
                  Text(
                    'Aktualisiert: ${now.hour}:${now.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildSubtitle() {
    final closest = widget.transitService.nearbyStops.isNotEmpty
        ? widget.transitService.nearbyStops.first
        : null;
    if (closest != null) {
      final dist = closest.distance;
      final distStr = dist >= 1000
          ? '${(dist / 1000).toStringAsFixed(1)} km'
          : '$dist m';
      return '${closest.name} ($distStr)';
    }
    return widget.city;
  }

  Color _lineColor(String productType) {
    switch (productType) {
      case 'tram':
        return Colors.blue.shade700;
      case 'train':
      case 'regional':
        return Colors.red.shade700;
      case 'suburban':
        return Colors.green.shade700;
      default:
        return Colors.teal.shade700;
    }
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
                  Icon(Icons.newspaper, color: Colors.deepOrange.shade700, size: 24),
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
              labelColor: Colors.deepOrange.shade700,
              unselectedLabelColor: Colors.grey,
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
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Text(
                'Quelle: tagesschau.de (ARD)',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewsList(List<NewsArticle> articles) {
    if (articles.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.article_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text('Keine Nachrichten verfügbar',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: articles.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
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
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.image, color: Colors.grey),
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
                      color: Colors.grey.shade600,
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
