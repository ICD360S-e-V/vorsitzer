import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'api_service.dart';
import 'notification_service.dart';
import 'logger_service.dart';
import 'http_client_factory.dart';

/// Service for receiving push notifications via ntfy (self-hosted).
/// Connects to the ntfy server using HTTP streaming (NDJSON).
/// Topic pattern: vorsitzer_{mitgliedernummer}
/// Auth: fetches ntfy token from server (never hardcoded).
class NtfyService {
  static final NtfyService _instance = NtfyService._internal();
  factory NtfyService() => _instance;
  NtfyService._internal();

  static const String _ntfyUrl = 'https://icd360sev.icd360s.de/ntfy';
  static const String _tokenUrl = 'https://icd360sev.icd360s.de/api/auth/ntfy_token.php';
  static const String _topicPrefix = 'vorsitzer_';
  static const Duration _baseReconnectDelay = Duration(seconds: 5);
  static const Duration _maxReconnectDelay = Duration(minutes: 5);

  final _log = LoggerService();

  /// Wird bei einem stillen Gateway-Auftrag gerufen. Als Callback statt als
  /// direkter Aufruf, damit dieser Dienst nichts vom SMS-Gateway wissen muss.
  static void Function()? onGatewayWake;

  String? _mitgliedernummer;
  String? _jwtToken;
  String? _ntfyToken;
  http.Client? _client;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  bool _running = false;
  int _reconnectAttempts = 0;

  /// Start listening for ntfy notifications.
  /// [mitgliedernummer] - e.g. "V12345" (will be lowercased)
  /// [jwtToken] - JWT token for fetching ntfy auth token from server
  void start(String mitgliedernummer, {String? jwtToken}) {
    if (_running && _mitgliedernummer == mitgliedernummer.toLowerCase()) return;
    stop();
    _mitgliedernummer = mitgliedernummer.toLowerCase();
    _jwtToken = jwtToken;
    _running = true;
    _reconnectAttempts = 0;
    _log.info('ntfy: Starting for $_mitgliedernummer', tag: 'NTFY');
    _fetchTokenAndConnect();
  }

  /// Update JWT token (e.g. after token refresh)
  void updateJwtToken(String jwtToken) {
    _jwtToken = jwtToken;
  }

  /// Stop listening.
  void stop() {
    _running = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _client?.close();
    _client = null;
    if (_mitgliedernummer != null) {
      _log.info('ntfy: Stopped', tag: 'NTFY');
    }
    _mitgliedernummer = null;
    _ntfyToken = null;
  }

  Future<void> _fetchTokenAndConnect() async {
    if (!_running) return;

    if (_ntfyToken == null && _jwtToken == null) {
      // Dashboard can start us before ApiService has settled its tokens, and
      // a cleared session leaves us with nothing to authenticate with. Either
      // way, silently doing nothing is what hid this failure for months.
      _log.warning('ntfy: No JWT yet — requesting one', tag: 'NTFY');
      await ApiService().ensureFreshToken();
      if (_jwtToken == null) {
        _scheduleReconnect();
        return;
      }
    }

    // Fetch ntfy token from server
    if (_ntfyToken == null && _jwtToken != null) {
      try {
        final tokenClient = IOClient(HttpClientFactory.createPinnedHttpClient());
        final response = await tokenClient.get(
          Uri.parse(_tokenUrl),
          headers: {
            'Authorization': 'Bearer $_jwtToken',
            'User-Agent': 'ICD360S-Vorsitzer/1.0',
          },
        ).timeout(const Duration(seconds: 15));
        tokenClient.close();

        if (response.statusCode == 200) {
          try {
            final body = jsonDecode(response.body);
            if (body['success'] == true && body['ntfy_token'] != null) {
              _ntfyToken = body['ntfy_token'] as String;
              _log.info('ntfy: Token fetched', tag: 'NTFY');
            } else {
              _log.error('ntfy: Token fetch failed: ${body['message'] ?? 'unknown'}', tag: 'NTFY');
              _scheduleReconnect();
              return;
            }
          } on FormatException {
            _log.error('ntfy: Invalid token response', tag: 'NTFY');
            _scheduleReconnect();
            return;
          }
        } else {
          _log.error('ntfy: Token fetch HTTP ${response.statusCode}', tag: 'NTFY');
          if (response.statusCode == 401 || response.statusCode == 403) {
            // A refused JWT never heals by being sent again. Ask ApiService for
            // a live one — it pushes the result back here via updateJwtToken().
            await ApiService().ensureFreshToken();
          }
          _scheduleReconnect();
          return;
        }
      } catch (e) {
        _log.error('ntfy: Token fetch error: $e', tag: 'NTFY');
        _scheduleReconnect();
        return;
      }
    }

    _connect();
  }

  void _connect() async {
    if (!_running || _mitgliedernummer == null) return;

    final topic = '$_topicPrefix$_mitgliedernummer';
    final url = '$_ntfyUrl/$topic/json';

    _log.info('ntfy: Connecting to $topic', tag: 'NTFY');

    try {
      _client?.close();
      _client = IOClient(HttpClientFactory.createPinnedHttpClient());

      final request = http.Request('GET', Uri.parse(url));
      request.headers['Accept'] = 'application/x-ndjson';
      if (_ntfyToken != null) {
        request.headers['Authorization'] = 'Bearer $_ntfyToken';
      }

      final response = await _client!.send(request).timeout(
        const Duration(seconds: 15),
      );

      if (response.statusCode == 401 || response.statusCode == 403) {
        _log.error('ntfy: Auth failed (${response.statusCode}), refetching token', tag: 'NTFY');
        _ntfyToken = null;
        _scheduleReconnect();
        return;
      }

      if (response.statusCode != 200) {
        _log.error('ntfy: HTTP ${response.statusCode}', tag: 'NTFY');
        _scheduleReconnect();
        return;
      }

      _log.info('ntfy: Connected to $topic', tag: 'NTFY');
      _reconnectAttempts = 0;

      _subscription = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        _handleLine,
        onError: (error) {
          _log.error('ntfy: Stream error: $error', tag: 'NTFY');
          _scheduleReconnect();
        },
        onDone: () {
          _log.info('ntfy: Stream closed', tag: 'NTFY');
          _scheduleReconnect();
        },
        cancelOnError: false,
      );
    } catch (e) {
      _log.error('ntfy: Connection failed: $e', tag: 'NTFY');
      _scheduleReconnect();
    }
  }

  void _handleLine(String line) {
    if (line.trim().isEmpty) return;

    try {
      final data = jsonDecode(line);
      if (data is! Map<String, dynamic>) return;

      // Skip non-message events (keepalive, open, etc.)
      final event = data['event'] as String? ?? '';
      if (event != 'message') return;

      // Maschinen-Auftrag statt Nachricht an den Menschen: das Gateway soll
      // die SMS-Warteschlange sofort leeren. Ohne diesen Zweig bekäme der
      // Vorstand bei jeder von Hand ausgelösten SMS eine sinnlose
      // "SMS-Auftrag"-Benachrichtigung auf den Bildschirm.
      final tags = (data['tags'] as List?)?.map((t) => '$t').toList() ?? const [];
      if (tags.contains('sms_gateway')) {
        onGatewayWake?.call();
        return;
      }

      final title = data['title'] as String? ?? 'ICD360S e.V';
      final body = data['message'] as String? ?? '';

      _log.info('ntfy: Notification: $title - $body', tag: 'NTFY');

      NotificationService().show(title: title, body: body);
    } on FormatException {
      // Not valid JSON, ignore (could be keepalive)
    } catch (e) {
      _log.error('ntfy: Parse error: $e', tag: 'NTFY');
    }
  }

  void _scheduleReconnect() {
    if (!_running) return;
    _reconnectTimer?.cancel();
    // Exponential backoff, capped. Retrying every 5s against a failure that
    // cannot fix itself — a dead JWT, say — costs thousands of requests a day
    // and buries the real error under its own noise.
    final delay = _reconnectAttempts >= 6
        ? _maxReconnectDelay
        : Duration(seconds: _baseReconnectDelay.inSeconds << _reconnectAttempts);
    _reconnectAttempts++;
    _log.debug('ntfy: Reconnect in ${delay.inSeconds}s', tag: 'NTFY');
    _reconnectTimer = Timer(delay, _fetchTokenAndConnect);
  }
}
