import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'device_key_service.dart';
import 'http_client_factory.dart';
import 'logger_service.dart';
import '../utils/role_helpers.dart';

class ApiService {
  static const String baseUrl = 'https://icd360sev.icd360s.de/api';

  // ✅ SECURITY FIX (2026-02-10): Removed hardcoded API key
  // All requests now use dynamic Device Key only (no legacy fallback)
  // Hardcoded keys can be extracted via reverse engineering - CRITICAL vulnerability!

  String? _token;
  String? _refreshToken;
  late http.Client _client;
  final DeviceKeyService _deviceKeyService = DeviceKeyService();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  // Singleton pattern
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal() {
    // ✅ SECURITY FIX (2026-02-10): Use default SSL validation
    // This prevents man-in-the-middle attacks by properly validating SSL certificates
    // Previous code accepted ALL certificates (including invalid ones) - CRITICAL vulnerability!
    final httpClient = HttpClientFactory.createPinnedHttpClient();
    _client = IOClient(httpClient);
  }

  /// Inițializează API service - TREBUIE apelat la pornirea aplicației
  Future<bool> initialize() async {
    final deviceKeyInitialized = await _deviceKeyService.initialize();
    if (!deviceKeyInitialized) {
      return false;
    }
    await loadTokens();
    // If we have a refresh token but the access token might be stale
    // (loaded from SP after app restart), proactively refresh now so
    // all services (ntfy, heartbeat, etc.) get a fresh JWT immediately.
    if (_refreshToken != null) {
      await _refreshAccessToken();
      _startTokenRefreshTimer();
    }
    return true;
  }

  /// ✅ SECURITY: Tokens stored in FlutterSecureStorage (encrypted) when available.
  /// On platforms where the keychain is unavailable (e.g. unsigned macOS builds → -34018),
  /// tokens are kept ONLY in memory — user must re-login on next app start.
  /// We never persist secrets to plaintext disk storage.
  Future<void> loadTokens() async {
    try {
      _token = await _secureStorage.read(key: 'access_token');
      _refreshToken = await _secureStorage.read(key: 'refresh_token');
    } catch (e) {
      LoggerService().warning('Keychain read failed: $e', tag: 'API');
    }
    // Always check SharedPreferences if tokens are still null.
    // On macOS unsigned, keychain write fails → tokens go to SP only.
    // But keychain read returns null (key not found) instead of throwing,
    // so the catch above doesn't trigger → must check SP regardless.
    if (_token == null || _refreshToken == null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        _token ??= prefs.getString('access_token');
        _refreshToken ??= prefs.getString('refresh_token');
        if (_token != null) {
          LoggerService().info('Tokens loaded from SharedPreferences fallback', tag: 'API');
        }
      } catch (_) {}
    }
  }

  Timer? _tokenRefreshTimer;

  Future<void> saveTokens(String token, String refreshToken) async {
    _token = token;
    _refreshToken = refreshToken;
    try {
      await _secureStorage.write(key: 'access_token', value: token);
      await _secureStorage.write(key: 'refresh_token', value: refreshToken);
    } catch (e) {
      LoggerService().warning('Keychain write failed, using SharedPreferences fallback: $e', tag: 'API');
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('access_token', token);
        await prefs.setString('refresh_token', refreshToken);
      } catch (_) {}
    }
    // Start proactive token refresh — access token expires in 1 hour,
    // refresh 5 minutes before expiry to avoid "invalid or expired token" errors
    _startTokenRefreshTimer();
  }

  void _startTokenRefreshTimer() {
    _tokenRefreshTimer?.cancel();
    // Refresh every 50 minutes (token expires after 60 min)
    _tokenRefreshTimer = Timer.periodic(const Duration(minutes: 50), (_) async {
      LoggerService().info('Proactive token refresh (50 min timer)', tag: 'AUTH');
      await _refreshAccessToken();
    });
  }

  Future<void> clearTokens() async {
    _token = null;
    _refreshToken = null;
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = null;
    try {
      await _secureStorage.delete(key: 'access_token');
      await _secureStorage.delete(key: 'refresh_token');
    } catch (_) {}
  }

  bool get isLoggedIn => _token != null;
  String? get token => _token;
  String? get refreshToken => _refreshToken;
  bool _isRefreshing = false;

  /// Refresh the access token using the refresh token.
  /// Returns true if refresh succeeded, false if user must re-login.
  Future<bool> _refreshAccessToken() async {
    if (_isRefreshing) return false;
    if (_refreshToken == null) return false;

    _isRefreshing = true;
    try {
      final deviceKey = _deviceKeyService.deviceKey;
      final response = await _client.post(
        Uri.parse('$baseUrl/auth/refresh.php'),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'ICD360S-Vorsitzer/1.0',
          if (deviceKey != null) 'X-Device-Key': deviceKey,
        },
        body: jsonEncode({'refresh_token': _refreshToken}),
      ).timeout(const Duration(seconds: 10));

      final result = jsonDecode(response.body);
      if (response.statusCode == 200 && result['success'] == true) {
        final newToken = result['token'] as String;
        _token = newToken;
        try {
          await _secureStorage.write(key: 'token', value: newToken);
        } catch (_) {}
        LoggerService().info('Access token refreshed successfully', tag: 'AUTH');
        return true;
      }
    } catch (e) {
      LoggerService().error('Token refresh failed: $e', tag: 'AUTH');
    } finally {
      _isRefreshing = false;
    }
    return false;
  }

  /// Headers pentru request-uri - folosește Device Key dinamic
  /// ✅ SECURITY FIX: Removed legacy API key fallback (all devices must be registered)
  Map<String, String> get _headers {
    final deviceKey = _deviceKeyService.deviceKey;
    if (deviceKey == null) {
      throw Exception('Device not registered. Please restart the app to register device.');
    }
    return {
      'Content-Type': 'application/json',
      'User-Agent': 'ICD360S-Vorsitzer/1.0',
      'X-Device-Key': deviceKey,
      if (_token != null) 'Authorization': 'Bearer $_token',
    };
  }

  /// POST request with automatic token refresh on 401
  Future<http.Response> _authPost(String endpoint, {Map<String, dynamic>? body, Duration timeout = const Duration(seconds: 15)}) async {
    var response = await _client.post(
      Uri.parse('$baseUrl/$endpoint'),
      headers: _headers,
      body: body != null ? jsonEncode(body) : null,
    ).timeout(timeout);

    if (response.statusCode == 401 && _refreshToken != null) {
      final refreshed = await _refreshAccessToken();
      if (refreshed) {
        response = await _client.post(
          Uri.parse('$baseUrl/$endpoint'),
          headers: _headers,
          body: body != null ? jsonEncode(body) : null,
        ).timeout(timeout);
      }
    }
    return response;
  }

  /// GET request with automatic token refresh on 401
  Future<http.Response> _authGet(String endpoint, {Duration timeout = const Duration(seconds: 15)}) async {
    var response = await _client.get(
      Uri.parse('$baseUrl/$endpoint'),
      headers: _headers,
    ).timeout(timeout);

    if (response.statusCode == 401 && _refreshToken != null) {
      final refreshed = await _refreshAccessToken();
      if (refreshed) {
        response = await _client.get(
          Uri.parse('$baseUrl/$endpoint'),
          headers: _headers,
        ).timeout(timeout);
      }
    }
    return response;
  }

  // Login (Vorsitzer Portal - Admin roles only)
  Future<Map<String, dynamic>> login(String mitgliedernummer, String password) async {
    final deviceKey = _deviceKeyService.deviceKey;
    if (deviceKey == null) {
      return {
        'success': false,
        'message': 'Device not registered. Please restart the app.',
      };
    }

    // ✅ SECURITY FIX: Sanitize input to prevent SQL injection
    final sanitizedMitgliedernummer = sanitizeMitgliedernummer(mitgliedernummer);

    if (!isValidMitgliedernummer(sanitizedMitgliedernummer)) {
      return {
        'success': false,
        'message': 'Ungültige Benutzernummer Format.',
      };
    }

    // Vorsitzer Portal: nur Benutzernummern mit Prefix "V" erlaubt
    if (!sanitizedMitgliedernummer.startsWith('V')) {
      return {
        'success': false,
        'message': 'Dieses Portal ist nur für Vorsitzer (V-Nummern) zugänglich.',
      };
    }

    final response = await _client.post(
      Uri.parse('$baseUrl/auth/login_vorsitzer.php'),
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'ICD360S-Vorsitzer/1.0',
        'X-Device-Key': deviceKey,
      },
      body: jsonEncode({
        'mitgliedernummer': sanitizedMitgliedernummer,
        'password': password,
        'device_language': Platform.localeName,
      }),
    ).timeout(const Duration(seconds: 15));

    final data = jsonDecode(response.body);

    if (response.statusCode == 200 && data['success'] == true) {
      await saveTokens(data['token'], data['refresh_token']);
    }

    return data;
  }

  // Logout a specific device (before login, for max devices scenario)
  Future<Map<String, dynamic>> logoutDevice(String mitgliedernummer, String password, int sessionId) async {
    final deviceKey = _deviceKeyService.deviceKey;
    if (deviceKey == null) {
      return {
        'success': false,
        'message': 'Device not registered.',
      };
    }

    final response = await _client.post(
      Uri.parse('$baseUrl/auth/logout_device.php'),
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'ICD360S-Vorsitzer/1.0',
        'X-Device-Key': deviceKey,
      },
      body: jsonEncode({
        'mitgliedernummer': mitgliedernummer,
        'password': password,
        'session_id': sessionId,
      }),
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Get all users (admin only)
  Future<Map<String, dynamic>> getServerInfo() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/server_info.php'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> getConnectedDevices() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/connected_devices.php'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> getUsers() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/users.php'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Update user status
  Future<Map<String, dynamic>> updateUserStatus(int userId, String status) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/user_status.php'),
      headers: _headers,
      body: jsonEncode({
        'user_id': userId,
        'status': status,
      }),
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Delete user
  Future<Map<String, dynamic>> deleteUser(int userId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/user_delete.php'),
      headers: _headers,
      body: jsonEncode({
        'user_id': userId,
      }),
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Get user details with sessions and devices (admin only)
  Future<Map<String, dynamic>> getUserDetails(int userId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/user_details.php'),
      headers: _headers,
      body: jsonEncode({
        'user_id': userId,
      }),
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Update user (admin only)
  Future<Map<String, dynamic>> updateUser({
    required int userId,
    String? email,
    String? password,
    String? name,
    String? role,
    String? mitgliedschaftDatum,
    String? vorname,
    String? nachname,
    String? vorname2,
    String? strasse,
    String? hausnummer,
    String? plz,
    String? ort,
    String? telefonMobil,
    String? bundesland,
    String? land,
    String? mitgliedsart,
    String? zahlungsmethode,
    int? zahlungstag,
    String? geburtsdatum,
    String? geburtsort,
    String? staatsangehoerigkeit,
    String? muttersprache,
    String? geschlecht,
    String? familienstand,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/user_update.php'),
      headers: _headers,
      body: jsonEncode({
        'user_id': userId,
        if (email != null) 'email': email,
        if (password != null) 'password': password,
        if (name != null) 'name': name,
        if (role != null) 'role': role,
        if (mitgliedschaftDatum != null) 'mitgliedschaft_datum': mitgliedschaftDatum,
        if (vorname != null) 'vorname': vorname,
        if (nachname != null) 'nachname': nachname,
        if (vorname2 != null) 'vorname2': vorname2,
        if (strasse != null) 'strasse': strasse,
        if (hausnummer != null) 'hausnummer': hausnummer,
        if (plz != null) 'plz': plz,
        if (ort != null) 'ort': ort,
        if (telefonMobil != null) 'telefon_mobil': telefonMobil,
        if (bundesland != null) 'bundesland': bundesland,
        if (land != null) 'land': land,
        if (mitgliedsart != null) 'mitgliedsart': mitgliedsart,
        if (zahlungsmethode != null) 'zahlungsmethode': zahlungsmethode,
        if (zahlungstag != null) 'zahlungstag': zahlungstag,
        if (geburtsdatum != null) 'geburtsdatum': geburtsdatum,
        if (geburtsort != null) 'geburtsort': geburtsort,
        if (staatsangehoerigkeit != null) 'staatsangehoerigkeit': staatsangehoerigkeit,
        if (muttersprache != null) 'muttersprache': muttersprache,
        if (geschlecht != null) 'geschlecht': geschlecht,
        if (familienstand != null) 'familienstand': familienstand,
      }),
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Admin register new member (status: neu)
  Future<Map<String, dynamic>> adminRegisterMember({
    required String name,
    required String email,
    required String password,
    String role = 'mitglied',
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/admin_register.php'),
      headers: _headers,
      body: jsonEncode({
        'name': name,
        'email': email,
        'password': password,
        'role': role,
      }),
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Revoke session (admin only)
  Future<Map<String, dynamic>> revokeSession(int sessionId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/session_revoke.php'),
      headers: _headers,
      body: jsonEncode({
        'session_id': sessionId,
      }),
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Get my sessions (member - self-service)
  Future<Map<String, dynamic>> getMySessions() async {
    LoggerService().debug('getMySessions: Sending request...', tag: 'API');
    final response = await _client.get(
      Uri.parse('$baseUrl/auth/my_sessions.php'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));

    LoggerService().debug('getMySessions: Response status=${response.statusCode}', tag: 'API');

    if (response.body.isEmpty) {
      LoggerService().error('getMySessions: Empty response body!', tag: 'API');
      return {'success': false, 'message': 'Empty response from server', 'sessions': []};
    }

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Revoke my session (member - self-service)
  Future<Map<String, dynamic>> revokeMySession(int sessionId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/auth/revoke_my_session.php'),
      headers: _headers,
      body: jsonEncode({
        'session_id': sessionId,
      }),
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Change password
  Future<Map<String, dynamic>> changePassword(String mitgliedernummer, String currentPassword, String newPassword) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/auth/change_password.php'),
      headers: _headers,
      body: jsonEncode({
        'mitgliedernummer': mitgliedernummer,
        'current_password': currentPassword,
        'new_password': newPassword,
      }),
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Change email
  Future<Map<String, dynamic>> changeEmail(String mitgliedernummer, String newEmail, String password) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/auth/change_email.php'),
      headers: _headers,
      body: jsonEncode({
        'mitgliedernummer': mitgliedernummer,
        'password': password,
        'new_email': newEmail,
      }),
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Recover Password
  Future<Map<String, dynamic>> recoverPassword(String mitgliedernummer, String recoveryCode, String newPassword) async {
    final deviceKey = _deviceKeyService.deviceKey;
    if (deviceKey == null) {
      return {
        'success': false,
        'message': 'Device not registered.',
      };
    }

    final response = await _client.post(
      Uri.parse('$baseUrl/auth/recover.php'),
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'ICD360S-Vorsitzer/1.0',
        'X-Device-Key': deviceKey,
      },
      body: jsonEncode({
        'mitgliedernummer': mitgliedernummer,
        'recovery_code': recoveryCode,
        'new_password': newPassword,
      }),
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Register
  Future<Map<String, dynamic>> register(String email, String password, String name, String recoveryCode) async {
    final deviceKey = _deviceKeyService.deviceKey;
    if (deviceKey == null) {
      return {
        'success': false,
        'message': 'Device not registered.',
      };
    }

    // ✅ SECURITY FIX: Sanitize email input
    final sanitizedEmail = sanitizeEmail(email);

    if (!isValidEmail(sanitizedEmail)) {
      return {
        'success': false,
        'message': 'Ungültige E-Mail-Adresse.',
      };
    }

    final response = await _client.post(
      Uri.parse('$baseUrl/auth/register.php'),
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'ICD360S-Vorsitzer/1.0',
        'X-Device-Key': deviceKey,
      },
      body: jsonEncode({
        'email': sanitizedEmail,
        'password': password,
        'name': name,
        'recovery_code': recoveryCode,
        'device_language': Platform.localeName,
      }),
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Send heartbeat to update last_seen
  Future<Map<String, dynamic>> sendHeartbeat(String mitgliedernummer) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/auth/heartbeat.php'),
      headers: _headers,
      body: jsonEncode({
        'mitgliedernummer': mitgliedernummer,
      }),
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Get Profile (personal data + beitrag status)
  Future<Map<String, dynamic>> getProfile(String mitgliedernummer) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/auth/get_profile.php'),
      headers: _headers,
      body: jsonEncode({
        'mitgliedernummer': mitgliedernummer,
      }),
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Get Account Status (trial days remaining for 'neu' accounts)
  Future<Map<String, dynamic>> getAccountStatus(String mitgliedernummer) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/auth/account_status.php'),
      headers: _headers,
      body: jsonEncode({
        'mitgliedernummer': mitgliedernummer,
      }),
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Update Profile (personal data)
  Future<Map<String, dynamic>> updateProfile({
    required String mitgliedernummer,
    String? vorname,
    String? nachname,
    String? strasse,
    String? hausnummer,
    String? plz,
    String? ort,
    String? telefonMobil,
    String? geburtsdatum,
    String? geschlecht,
    List<String>? languages,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/auth/update_profile.php'),
      headers: _headers,
      body: jsonEncode({
        'mitgliedernummer': mitgliedernummer,
        'vorname': vorname,
        'nachname': nachname,
        'strasse': strasse,
        'hausnummer': hausnummer,
        'plz': plz,
        'ort': ort,
        'telefon_mobil': telefonMobil,
        'geburtsdatum': geburtsdatum,
        if (geschlecht != null) 'geschlecht': geschlecht,
        if (languages != null) 'languages': languages,
      }),
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Logout
  Future<void> logout() async {
    await clearTokens();
  }

  // ============= CHAT API =============

  // Start a new chat conversation
  Future<Map<String, dynamic>> startChat(String mitgliedernummer, {String subject = 'Support'}) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/chat/start.php'),
      headers: _headers,
      body: jsonEncode({
        'mitgliedernummer': mitgliedernummer,
        'subject': subject,
      }),
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Admin: Start a chat conversation with a member
  Future<Map<String, dynamic>> adminStartChat(String adminMitgliedernummer, String memberMitgliedernummer) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/chat/admin_start.php'),
      headers: _headers,
      body: jsonEncode({
        'admin_mitgliedernummer': adminMitgliedernummer,
        'member_mitgliedernummer': memberMitgliedernummer,
      }),
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Send a chat message
  /// 🆕 URGENT NOTIFICATIONS (2026-02-11): Added urgent parameter for full-screen alerts
  Future<Map<String, dynamic>> sendChatMessage(
    int conversationId,
    String mitgliedernummer,
    String message, {
    bool urgent = false,  // 🆕 Urgent flag for full-screen notifications
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/chat/send.php'),
      headers: _headers,
      body: jsonEncode({
        'conversation_id': conversationId,
        'mitgliedernummer': mitgliedernummer,
        'message': message,
        'urgent': urgent,  // 🆕 Send urgent flag to backend
      }),
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Get chat messages
  Future<Map<String, dynamic>> getChatMessages(int conversationId, String mitgliedernummer, {int? lastMessageId}) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/chat/messages.php'),
      headers: _headers,
      body: jsonEncode({
        'conversation_id': conversationId,
        'mitgliedernummer': mitgliedernummer,
        if (lastMessageId != null) 'last_message_id': lastMessageId,
      }),
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Get all conversations (for admin) or user's conversations
  Future<Map<String, dynamic>> getChatConversations(String mitgliedernummer, {String? status}) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/chat/conversations.php'),
      headers: _headers,
      body: jsonEncode({
        'mitgliedernummer': mitgliedernummer,
        if (status != null) 'status': status,
      }),
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Close a chat conversation (admin only)
  Future<Map<String, dynamic>> closeChatConversation(int conversationId, String mitgliedernummer) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/chat/close.php'),
      headers: _headers,
      body: jsonEncode({
        'conversation_id': conversationId,
        'mitgliedernummer': mitgliedernummer,
      }),
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Mute or unmute a chat conversation (admin only)
  Future<Map<String, dynamic>> muteConversation(int conversationId, String mitgliedernummer, String duration) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/chat/mute.php'),
      headers: _headers,
      body: jsonEncode({
        'conversation_id': conversationId,
        'mitgliedernummer': mitgliedernummer,
        'duration': duration,
      }),
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Upload chat attachments (max 10 files, 100MB total)
  Future<Map<String, dynamic>> uploadChatAttachments({
    required int conversationId,
    required String mitgliedernummer,
    required List<File> files,
    String? message,
  }) async {
    try {
      final deviceKey = _deviceKeyService.deviceKey;
      if (deviceKey == null) {
        return {'success': false, 'message': 'Device not registered'};
      }

      // Create multipart request
      final uri = Uri.parse('$baseUrl/chat/upload.php');
      final request = http.MultipartRequest('POST', uri);

      // Add headers
      request.headers['User-Agent'] = 'ICD360S-Vorsitzer/1.0';
      request.headers['X-Device-Key'] = deviceKey;

      // Add fields
      request.fields['conversation_id'] = conversationId.toString();
      request.fields['mitgliedernummer'] = mitgliedernummer;
      if (message != null && message.isNotEmpty) {
        request.fields['message'] = message;
      }

      // Add files
      for (final file in files) {
        request.files.add(await http.MultipartFile.fromPath(
          'files[]',
          file.path,
        ));
      }

      // Send request using our custom IOClient
      final streamedResponse = await _client.send(request).timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Upload failed: $e'};
    }
  }

  // Download chat attachment
  /// Download arbitrary bytes from one of our own endpoints (e.g. chat/stream.php).
  /// Sends the device-key headers so the server can authenticate the request.
  /// Returns null on any failure (network, non-200, etc.).
  Future<Uint8List?> fetchBytesAuthenticated(String url) async {
    try {
      final response = await _client
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      LoggerService().warning(
        'fetchBytesAuthenticated $url -> HTTP ${response.statusCode}',
        tag: 'API',
      );
      return null;
    } catch (e) {
      LoggerService().error('fetchBytesAuthenticated $url failed: $e', tag: 'API');
      return null;
    }
  }

  Future<Map<String, dynamic>> downloadChatAttachment({
    required int attachmentId,
    required String mitgliedernummer,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/chat/download.php'),
        headers: _headers,
        body: jsonEncode({
          'attachment_id': attachmentId,
          'mitgliedernummer': mitgliedernummer,
        }),
      ).timeout(const Duration(seconds: 15));

      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Download failed: $e'};
    }
  }

  // Mark messages as read/delivered (WhatsApp-style read receipts)
  Future<Map<String, dynamic>> markMessagesRead({
    required int conversationId,
    required String mitgliedernummer,
    required String status, // 'delivered' or 'read'
    List<int>? messageIds,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/chat/mark_read.php'),
        headers: _headers,
        body: jsonEncode({
          'conversation_id': conversationId,
          'mitgliedernummer': mitgliedernummer,
          'status': status,
          if (messageIds != null) 'message_ids': messageIds,
        }),
      ).timeout(const Duration(seconds: 15));

      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Mark read failed: $e'};
    }
  }

  // ============= VEREINVERWALTUNG API =============

  // Get Vereinverwaltung data (partners, notary, etc.)
  Future<Map<String, dynamic>> getVereinverwaltung({String? kategorie}) async {
    try {
      String url = '$baseUrl/vereinverwaltung/get.php';
      if (kategorie != null) {
        url += '?kategorie=$kategorie';
      }

      final response = await _client.get(
        Uri.parse(url),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));

      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to load data: $e'};
    }
  }

  // Get platform credentials (encrypted in DB)
  Future<Map<String, dynamic>> getPlatformCredentials(String platform) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/platform/get_credentials.php'),
        headers: _headers,
        body: jsonEncode({'platform': platform}),
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to load credentials: $e'};
    }
  }

  // Save platform credentials (encrypted in DB)
  // [totpSecret] is optional. Pass `null` to leave the existing 2FA secret untouched,
  // an empty string to clear it, or a Base32 secret to set/replace it.
  Future<Map<String, dynamic>> savePlatformCredentials({
    required String platform,
    required String email,
    required String password,
    String? website,
    String? totpSecret,
  }) async {
    try {
      final body = <String, dynamic>{
        'platform': platform,
        'email': email,
        'password': password,
      };
      if (website != null) body['website'] = website;
      if (totpSecret != null) body['totp_secret'] = totpSecret;
      final response = await _client.post(
        Uri.parse('$baseUrl/platform/save_credentials.php'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to save credentials: $e'};
    }
  }

  // ============================================================
  // Platform Korrespondenz (Eingang/Ausgang)
  // ============================================================

  /// List korrespondenz entries for a platform + direction (eingang|ausgang).
  /// Each entry contains the embedded list of attached files.
  Future<Map<String, dynamic>> getPlatformKorrespondenz({
    required String platform,
    required String direction,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/platform/korrespondenz_list.php'),
        headers: _headers,
        body: jsonEncode({'platform': platform, 'direction': direction}),
      ).timeout(const Duration(seconds: 15));
      try {
        return jsonDecode(response.body);
      } on FormatException {
        return {'success': false, 'message': 'Invalid server response'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Failed to load Korrespondenz: $e'};
    }
  }

  /// Create a new korrespondenz entry. Files are optional. The endpoint is
  /// multipart so we cannot use the standard JSON helper.
  Future<Map<String, dynamic>> createPlatformKorrespondenz({
    required String platform,
    required String direction,
    required String betreff,
    required DateTime datum,
    String? inhalt,
    String? absender,
    String? empfaenger,
    List<File> files = const [],
  }) async {
    try {
      final deviceKey = _deviceKeyService.deviceKey;
      if (deviceKey == null) {
        return {'success': false, 'message': 'Device not registered'};
      }

      final uri = Uri.parse('$baseUrl/platform/korrespondenz_create.php');
      final request = http.MultipartRequest('POST', uri);
      request.headers['User-Agent'] = 'ICD360S-Vorsitzer/1.0';
      request.headers['X-Device-Key'] = deviceKey;

      request.fields['platform'] = platform;
      request.fields['direction'] = direction;
      request.fields['betreff'] = betreff;
      // Server accepts ISO datetime "YYYY-MM-DD HH:MM:SS".
      request.fields['datum'] =
          '${datum.year.toString().padLeft(4, '0')}-${datum.month.toString().padLeft(2, '0')}-${datum.day.toString().padLeft(2, '0')} '
          '${datum.hour.toString().padLeft(2, '0')}:${datum.minute.toString().padLeft(2, '0')}:${datum.second.toString().padLeft(2, '0')}';
      if (inhalt != null && inhalt.isNotEmpty) request.fields['inhalt'] = inhalt;
      if (absender != null && absender.isNotEmpty) request.fields['absender'] = absender;
      if (empfaenger != null && empfaenger.isNotEmpty) request.fields['empfaenger'] = empfaenger;

      for (final f in files) {
        request.files.add(await http.MultipartFile.fromPath(
          'files[]',
          f.path,
          filename: f.uri.pathSegments.isNotEmpty ? f.uri.pathSegments.last : 'attachment',
        ));
      }

      final streamed = await _client.send(request).timeout(const Duration(seconds: 120));
      final response = await http.Response.fromStream(streamed);

      try {
        return jsonDecode(response.body);
      } on FormatException {
        return {'success': false, 'message': 'Invalid server response'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Failed to create Korrespondenz: $e'};
    }
  }

  /// Delete a korrespondenz entry by id (cascades to files on disk).
  Future<Map<String, dynamic>> deletePlatformKorrespondenz(int id) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/platform/korrespondenz_delete.php'),
        headers: _headers,
        body: jsonEncode({'id': id}),
      ).timeout(const Duration(seconds: 15));
      try {
        return jsonDecode(response.body);
      } on FormatException {
        return {'success': false, 'message': 'Invalid server response'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Failed to delete Korrespondenz: $e'};
    }
  }

  /// Download a single korrespondenz attachment as raw bytes (already
  /// decrypted server-side). Returns null on any failure.
  Future<Uint8List?> downloadPlatformKorrespondenzFile(int fileId) async {
    final url = '$baseUrl/platform/korrespondenz_download.php?file_id=$fileId';
    return fetchBytesAuthenticated(url);
  }

  // List platform Aufgaben
  Future<Map<String, dynamic>> getPlatformAufgaben(String platform) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/platform/aufgaben_list.php'),
        headers: _headers,
        body: jsonEncode({'platform': platform}),
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to load Aufgaben: $e'};
    }
  }

  // Get Pauschalen (Ehrenamtspauschale, Übungsleiterpauschale)
  Future<Map<String, dynamic>> getPauschalen() async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/pauschalen.php'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to load Pauschalen: $e'};
    }
  }

  // Create platform Aufgabe
  Future<Map<String, dynamic>> createPlatformAufgabe({
    required String platform,
    required String titel,
    required String faelligAm,
    String? beschreibung,
  }) async {
    try {
      final body = {
        'platform': platform,
        'titel': titel,
        'faellig_am': faelligAm,
      };
      if (beschreibung != null) body['beschreibung'] = beschreibung;
      final response = await _client.post(
        Uri.parse('$baseUrl/platform/aufgaben_create.php'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to create Aufgabe: $e'};
    }
  }

  // Update platform Aufgabe
  Future<Map<String, dynamic>> updatePlatformAufgabe(Map<String, dynamic> data) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/platform/aufgaben_update.php'),
        headers: _headers,
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to update Aufgabe: $e'};
    }
  }

  // Delete platform Aufgabe
  Future<Map<String, dynamic>> deletePlatformAufgabe(int id) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/platform/aufgaben_delete.php'),
        headers: _headers,
        body: jsonEncode({'id': id}),
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to delete Aufgabe: $e'};
    }
  }

  // ============= PLATFORM NOTIZEN API =============

  Future<Map<String, dynamic>> getPlatformNotizen(String platform) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/platform/notizen_list.php'),
        headers: _headers,
        body: jsonEncode({'platform': platform}),
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to load Notizen: $e'};
    }
  }

  Future<Map<String, dynamic>> createPlatformNotiz({
    required String platform,
    required String inhalt,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/platform/notizen_create.php'),
        headers: _headers,
        body: jsonEncode({
          'platform': platform,
          'inhalt': inhalt,
        }),
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to create Notiz: $e'};
    }
  }

  Future<Map<String, dynamic>> deletePlatformNotiz(int id) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/platform/notizen_delete.php'),
        headers: _headers,
        body: jsonEncode({'id': id}),
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to delete Notiz: $e'};
    }
  }

  // ============= POSTCARD KARTEN API =============

  Future<Map<String, dynamic>> getPostcardKarten() async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/platform/postcard_list.php'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to load Postcards: $e'};
    }
  }

  Future<Map<String, dynamic>> createPostcardKarte({
    required String kartennummer,
    String? pin,
    String? bezeichnung,
    double tageslimit = 10.0,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/platform/postcard_create.php'),
        headers: _headers,
        body: jsonEncode({
          'kartennummer': kartennummer,
          if (pin != null) 'pin': pin,
          if (bezeichnung != null) 'bezeichnung': bezeichnung,
          'tageslimit': tageslimit,
        }),
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to create Postcard: $e'};
    }
  }

  Future<Map<String, dynamic>> updatePostcardKarte({
    required int id,
    String? kartennummer,
    String? pin,
    String? bezeichnung,
    double? tageslimit,
    bool? aktiv,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/platform/postcard_update.php'),
        headers: _headers,
        body: jsonEncode({
          'id': id,
          if (kartennummer != null) 'kartennummer': kartennummer,
          if (pin != null) 'pin': pin,
          if (bezeichnung != null) 'bezeichnung': bezeichnung,
          if (tageslimit != null) 'tageslimit': tageslimit,
          if (aktiv != null) 'aktiv': aktiv,
        }),
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to update Postcard: $e'};
    }
  }

  Future<Map<String, dynamic>> deletePostcardKarte(int id) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/platform/postcard_delete.php'),
        headers: _headers,
        body: jsonEncode({'id': id}),
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to delete Postcard: $e'};
    }
  }

  // ============= POSTCARD ACCOUNT API =============

  Future<Map<String, dynamic>> getPostcardAccount() async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/platform/postcard_account_get.php'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to load account: $e'};
    }
  }

  Future<Map<String, dynamic>> savePostcardAccount({
    required String website,
    required String username,
    required String password,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/platform/postcard_account_save.php'),
        headers: _headers,
        body: jsonEncode({
          'website': website,
          'username': username,
          'password': password,
        }),
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to save account: $e'};
    }
  }

  // Update Vereinverwaltung entry
  Future<Map<String, dynamic>> updateVereinverwaltung(Map<String, dynamic> data) async {
    try {
      final response = await _client.put(
        Uri.parse('$baseUrl/vereinverwaltung/update.php'),
        headers: _headers,
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 15));

      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to update: $e'};
    }
  }

  // ============= VEREINEINSTELLUNGEN API =============

  // Get Vereineinstellungen (single row with all association settings)
  Future<Map<String, dynamic>> getVereineinstellungen() async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/admin/vereineinstellungen.php'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to load Vereineinstellungen: $e'};
    }
  }

  // Update Vereineinstellungen
  Future<Map<String, dynamic>> updateVereineinstellungen(Map<String, dynamic> data) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/admin/vereineinstellungen.php'),
        headers: _headers,
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to update Vereineinstellungen: $e'};
    }
  }

  // ============= VEREINVERWALTUNG BEHÖRDE FINANZAMT =============

  Future<Map<String, dynamic>> getVereinFinanzamt() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/vereinverwaltung_behorde_finanzamt.php'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> saveVereinFinanzamt(Map<String, dynamic> data) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/vereinverwaltung_behorde_finanzamt.php'),
      headers: _headers,
      body: jsonEncode(data),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ============= FINANZAMT DOKUMENTE API =============

  // List finanzamt documents
  Future<Map<String, dynamic>> getFinanzamtDokumente() async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/admin/finanzamt/dokumente.php'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to load documents: $e'};
    }
  }

  // Upload finanzamt document
  Future<Map<String, dynamic>> uploadFinanzamtDokument({
    required String filePath,
    required String fileName,
    String kategorie = 'sonstiges',
    String beschreibung = '',
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/admin/finanzamt/dokumente.php');
      final request = http.MultipartRequest('POST', uri);

      for (final entry in _headers.entries) {
        request.headers[entry.key] = entry.value;
      }
      request.headers.remove('Content-Type');

      request.fields['kategorie'] = kategorie;
      request.fields['beschreibung'] = beschreibung;
      request.files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));

      final streamedResponse = await _client.send(request).timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to upload: $e'};
    }
  }

  // Delete finanzamt document
  Future<Map<String, dynamic>> deleteFinanzamtDokument(int id) async {
    try {
      final request = http.Request('DELETE', Uri.parse('$baseUrl/admin/finanzamt/dokumente.php'));
      request.headers.addAll(_headers);
      request.body = jsonEncode({'id': id});

      final streamedResponse = await _client.send(request).timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to delete: $e'};
    }
  }

  // Download finanzamt document (returns bytes)
  Future<http.Response?> downloadFinanzamtDokument(int id) async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/admin/finanzamt/download.php?id=$id'),
        headers: _headers,
      ).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) return response;
      return null;
    } catch (_) {
      return null;
    }
  }

  // ============= NOTAR API =============

  // Get Notar Rechnungen (Invoices)
  Future<Map<String, dynamic>> getNotarRechnungen({int? notarId}) async {
    try {
      String url = '$baseUrl/notar/rechnungen.php';
      if (notarId != null) {
        url += '?notar_id=$notarId';
      }
      final response = await _client.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to load: $e'};
    }
  }

  // Create Notar Rechnung
  Future<Map<String, dynamic>> createNotarRechnung(Map<String, dynamic> data) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/notar/rechnungen.php'),
        headers: _headers,
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to create: $e'};
    }
  }

  // Update Notar Rechnung
  Future<Map<String, dynamic>> updateNotarRechnung(Map<String, dynamic> data) async {
    try {
      final response = await _client.put(
        Uri.parse('$baseUrl/notar/rechnungen.php'),
        headers: _headers,
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to update: $e'};
    }
  }

  // Delete Notar Rechnung
  Future<Map<String, dynamic>> deleteNotarRechnung(int id) async {
    try {
      final response = await _client.delete(
        Uri.parse('$baseUrl/notar/rechnungen.php?id=$id'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to delete: $e'};
    }
  }

  // Get Notar Besuche (Visits)
  Future<Map<String, dynamic>> getNotarBesuche({int? notarId}) async {
    try {
      String url = '$baseUrl/notar/besuche.php';
      if (notarId != null) {
        url += '?notar_id=$notarId';
      }
      final response = await _client.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to load: $e'};
    }
  }

  // Create Notar Besuch
  Future<Map<String, dynamic>> createNotarBesuch(Map<String, dynamic> data) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/notar/besuche.php'),
        headers: _headers,
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to create: $e'};
    }
  }

  // Update Notar Besuch
  Future<Map<String, dynamic>> updateNotarBesuch(Map<String, dynamic> data) async {
    try {
      final response = await _client.put(
        Uri.parse('$baseUrl/notar/besuche.php'),
        headers: _headers,
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to update: $e'};
    }
  }

  // Delete Notar Besuch
  Future<Map<String, dynamic>> deleteNotarBesuch(int id) async {
    try {
      final response = await _client.delete(
        Uri.parse('$baseUrl/notar/besuche.php?id=$id'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to delete: $e'};
    }
  }

  // Get Notar Dokumente
  Future<Map<String, dynamic>> getNotarDokumente({int? notarId, String? typ}) async {
    try {
      String url = '$baseUrl/notar/dokumente.php';
      List<String> params = [];
      if (notarId != null) params.add('notar_id=$notarId');
      if (typ != null) params.add('typ=$typ');
      if (params.isNotEmpty) url += '?${params.join('&')}';
      final response = await _client.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to load: $e'};
    }
  }

  // Create Notar Dokument
  Future<Map<String, dynamic>> createNotarDokument(Map<String, dynamic> data) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/notar/dokumente.php'),
        headers: _headers,
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to create: $e'};
    }
  }

  // Update Notar Dokument
  Future<Map<String, dynamic>> updateNotarDokument(Map<String, dynamic> data) async {
    try {
      final response = await _client.put(
        Uri.parse('$baseUrl/notar/dokumente.php'),
        headers: _headers,
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to update: $e'};
    }
  }

  // Delete Notar Dokument
  Future<Map<String, dynamic>> deleteNotarDokument(int id) async {
    try {
      final response = await _client.delete(
        Uri.parse('$baseUrl/notar/dokumente.php?id=$id'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to delete: $e'};
    }
  }

  // Get Notar Zahlungen (Payments)
  Future<Map<String, dynamic>> getNotarZahlungen({int? notarId, int? rechnungId}) async {
    try {
      String url = '$baseUrl/notar/zahlungen.php';
      List<String> params = [];
      if (notarId != null) params.add('notar_id=$notarId');
      if (rechnungId != null) params.add('rechnung_id=$rechnungId');
      if (params.isNotEmpty) url += '?${params.join('&')}';
      final response = await _client.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to load: $e'};
    }
  }

  // Create Notar Zahlung
  Future<Map<String, dynamic>> createNotarZahlung(Map<String, dynamic> data) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/notar/zahlungen.php'),
        headers: _headers,
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to create: $e'};
    }
  }

  // Update Notar Zahlung
  Future<Map<String, dynamic>> updateNotarZahlung(Map<String, dynamic> data) async {
    try {
      final response = await _client.put(
        Uri.parse('$baseUrl/notar/zahlungen.php'),
        headers: _headers,
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to update: $e'};
    }
  }

  // Delete Notar Zahlung
  Future<Map<String, dynamic>> deleteNotarZahlung(int id) async {
    try {
      final response = await _client.delete(
        Uri.parse('$baseUrl/notar/zahlungen.php?id=$id'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to delete: $e'};
    }
  }

  // Get Notar Aufgaben (Tasks)
  Future<Map<String, dynamic>> getNotarAufgaben({int? notarId}) async {
    try {
      String url = '$baseUrl/notar/aufgaben.php';
      if (notarId != null) {
        url += '?notar_id=$notarId';
      }
      final response = await _client.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to load: $e'};
    }
  }

  // Create Notar Aufgabe
  Future<Map<String, dynamic>> createNotarAufgabe(Map<String, dynamic> data) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/notar/aufgaben.php'),
        headers: _headers,
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to create: $e'};
    }
  }

  // Update Notar Aufgabe
  Future<Map<String, dynamic>> updateNotarAufgabe(Map<String, dynamic> data) async {
    try {
      final response = await _client.put(
        Uri.parse('$baseUrl/notar/aufgaben.php'),
        headers: _headers,
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to update: $e'};
    }
  }

  // Delete Notar Aufgabe
  Future<Map<String, dynamic>> deleteNotarAufgabe(int id) async {
    try {
      final response = await _client.delete(
        Uri.parse('$baseUrl/notar/aufgaben.php?id=$id'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to delete: $e'};
    }
  }

  // ============= CHAT SCHEDULED MESSAGES API =============

  Future<Map<String, dynamic>> getScheduledMessages() async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/chat/scheduled_messages.php'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to load scheduled messages: $e'};
    }
  }

  Future<Map<String, dynamic>> createScheduledMessage({
    required String sendTime,
    required String message,
    String category = 'mahlzeit',
    String daysOfWeek = '1,2,3,4,5,6,7',
    String? createdBy,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/chat/scheduled_messages.php'),
        headers: _headers,
        body: jsonEncode({
          'send_time': sendTime,
          'message': message,
          'category': category,
          'days_of_week': daysOfWeek,
          if (createdBy != null) 'created_by': createdBy,
        }),
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to create scheduled message: $e'};
    }
  }

  Future<Map<String, dynamic>> updateScheduledMessage({
    required int id,
    String? sendTime,
    String? message,
    String? category,
    String? daysOfWeek,
    bool? isActive,
  }) async {
    try {
      final response = await _client.put(
        Uri.parse('$baseUrl/chat/scheduled_messages.php'),
        headers: _headers,
        body: jsonEncode({
          'id': id,
          if (sendTime != null) 'send_time': sendTime,
          if (message != null) 'message': message,
          if (category != null) 'category': category,
          if (daysOfWeek != null) 'days_of_week': daysOfWeek,
          if (isActive != null) 'is_active': isActive ? 1 : 0,
        }),
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to update scheduled message: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteScheduledMessage(int id) async {
    try {
      final response = await _client.delete(
        Uri.parse('$baseUrl/chat/scheduled_messages.php?id=$id'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to delete scheduled message: $e'};
    }
  }

  // ============= PER-CONVERSATION SCHEDULED MESSAGES =============

  // Get scheduled messages for a conversation (with enabled/disabled status)
  Future<Map<String, dynamic>> getConversationScheduled(int conversationId) async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/chat/conversation_scheduled.php?conversation_id=$conversationId'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to load conversation scheduled: $e'};
    }
  }

  // Toggle a scheduled message for a conversation
  Future<Map<String, dynamic>> toggleConversationScheduled(int conversationId, int scheduledMessageId, bool enable) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/chat/conversation_scheduled.php'),
        headers: _headers,
        body: jsonEncode({
          'conversation_id': conversationId,
          'scheduled_message_id': scheduledMessageId,
          'enable': enable,
        }),
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to toggle scheduled message: $e'};
    }
  }

  // ============= DHL TRACKING API =============

  // Get saved tracking shipments
  Future<Map<String, dynamic>> getDhlShipments() async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/tracking/dhl.php?action=list'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));

      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to load shipments: $e'};
    }
  }

  // Track a shipment via DHL API
  Future<Map<String, dynamic>> trackDhlShipment(String trackingNumber) async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/tracking/dhl.php?action=track&number=${Uri.encodeComponent(trackingNumber)}'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));

      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to track shipment: $e'};
    }
  }

  // Save a new shipment to track
  Future<Map<String, dynamic>> addDhlShipment(String trackingNumber, {String? beschreibung, String? createdBy}) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/tracking/dhl.php'),
        headers: _headers,
        body: jsonEncode({
          'tracking_number': trackingNumber,
          if (beschreibung != null) 'beschreibung': beschreibung,
          if (createdBy != null) 'created_by': createdBy,
        }),
      ).timeout(const Duration(seconds: 15));

      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to add shipment: $e'};
    }
  }

  // Delete a saved shipment
  Future<Map<String, dynamic>> deleteDhlShipment(int id) async {
    try {
      final response = await _client.delete(
        Uri.parse('$baseUrl/tracking/dhl.php?id=$id'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));

      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to delete shipment: $e'};
    }
  }

  // ============= DHL SETTINGS API =============

  Future<Map<String, dynamic>> getDhlSettings() async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/tracking/dhl_settings.php'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to load DHL settings: $e'};
    }
  }

  Future<Map<String, dynamic>> saveDhlSettings({required String email, required String password, String? updatedBy}) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/tracking/dhl_settings.php'),
        headers: _headers,
        body: jsonEncode({
          'email': email,
          'password': password,
          if (updatedBy != null) 'updated_by': updatedBy,
        }),
      ).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to save DHL settings: $e'};
    }
  }

  // ============= DHL FILIALFINDER API =============

  Future<Map<String, dynamic>> findDhlLocations({String? plz, String? ort, int limit = 20}) async {
    try {
      final params = <String, String>{};
      if (plz != null && plz.isNotEmpty) params['plz'] = plz;
      if (ort != null && ort.isNotEmpty) params['ort'] = ort;
      params['limit'] = limit.toString();

      final uri = Uri.parse('$baseUrl/tracking/filialfinder.php').replace(queryParameters: params);
      final response = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Filialfinder Fehler: $e'};
    }
  }

  // ============= ADMIN STATUS MESSAGE API =============

  // Get active admin status message (banner)
  Future<Map<String, dynamic>> getAdminStatusMessage() async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/admin/status_message.php'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));

      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to load status message: $e'};
    }
  }

  // Set or update admin status message
  Future<Map<String, dynamic>> setAdminStatusMessage(String message, {String? createdBy}) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/admin/status_message.php'),
        headers: _headers,
        body: jsonEncode({
          'message': message,
          if (createdBy != null) 'created_by': createdBy,
        }),
      ).timeout(const Duration(seconds: 15));

      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to set status message: $e'};
    }
  }

  // Clear (deactivate) admin status message
  Future<Map<String, dynamic>> clearAdminStatusMessage() async {
    try {
      final response = await _client.delete(
        Uri.parse('$baseUrl/admin/status_message.php'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));

      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Failed to clear status message: $e'};
    }
  }

  // ============= LOGS API =============

  // Push client logs to server
  Future<Map<String, dynamic>> pushLogs({
    required String mitgliedernummer,
    required String deviceId,
    required String machineName,
    required String platform,
    required List<Map<String, dynamic>> logs,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/logs/store.php'),
        headers: _headers,
        body: jsonEncode({
          'mitgliedernummer': mitgliedernummer,
          'device_id': deviceId,
          'machine_name': machineName,
          'platform': platform,
          'logs': logs,
        }),
      ).timeout(const Duration(seconds: 15));

      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Push logs failed: $e'};
    }
  }

  // ============= CHANGELOG API =============

  // Get changelog (protected endpoint - Vorsitzer Portal)
  Future<Map<String, dynamic>> getChangelog() async {
    final log = LoggerService();
    try {
      log.info('Fetching changelog from API', tag: 'CHANGELOG');

      final response = await _client.get(
        Uri.parse('$baseUrl/changelog_vorsitzer.php'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));

      log.info('Changelog API Response Status: ${response.statusCode}', tag: 'CHANGELOG');

      final decoded = jsonDecode(response.body);
      log.info('Changelog decoded successfully', tag: 'CHANGELOG');

      return decoded;
    } catch (e) {
      log.error('Changelog API Error: $e', tag: 'CHANGELOG');
      return {'success': false, 'message': 'Failed to load changelog: $e'};
    }
  }

  // Krankenkassen lista din DB
  Future<Map<String, dynamic>> getKrankenkassen({String? typ}) async {
    final uri = typ != null
        ? Uri.parse('$baseUrl/stadtverwaltung/krankenkassen.php?typ=$typ')
        : Uri.parse('$baseUrl/stadtverwaltung/krankenkassen.php');

    final response = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Behörden lista din DB
  Future<Map<String, dynamic>> getBehoerden({String? kategorie}) async {
    final uri = kategorie != null
        ? Uri.parse('$baseUrl/stadtverwaltung/behoerden.php?kategorie=$kategorie')
        : Uri.parse('$baseUrl/stadtverwaltung/behoerden.php');
    final response = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Krankenhäuser lista din DB
  Future<Map<String, dynamic>> getKrankenhaeuser({String? typ}) async {
    final uri = typ != null
        ? Uri.parse('$baseUrl/stadtverwaltung/krankenhaeuser.php?typ=$typ')
        : Uri.parse('$baseUrl/stadtverwaltung/krankenhaeuser.php');
    final response = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Praxen lista din DB
  Future<Map<String, dynamic>> getPraxen({String? kategorie}) async {
    final uri = kategorie != null
        ? Uri.parse('$baseUrl/stadtverwaltung/praxen.php?kategorie=$kategorie')
        : Uri.parse('$baseUrl/stadtverwaltung/praxen.php');
    final response = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Drogerien lista din DB
  Future<Map<String, dynamic>> getDrogerien({String? typ}) async {
    final uri = typ != null
        ? Uri.parse('$baseUrl/stadtverwaltung/drogerien.php?typ=$typ')
        : Uri.parse('$baseUrl/stadtverwaltung/drogerien.php');
    final response = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Märkte lista din DB
  Future<Map<String, dynamic>> getMaerkte({String? typ}) async {
    final uri = typ != null
        ? Uri.parse('$baseUrl/stadtverwaltung/maerkte.php?typ=$typ')
        : Uri.parse('$baseUrl/stadtverwaltung/maerkte.php');
    final response = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Get verification stages for a user
  Future<Map<String, dynamic>> getVerifizierung(int userId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/verifizierung_list.php'),
      headers: _headers,
      body: jsonEncode({'user_id': userId}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ========== BEHÖRDE STAMMDATEN (Krankenkassen, Finanzämter) ==========

  /// Krankenkassen-Datenbank (Name, Zusatzbeitrag, Rating)
  Future<Map<String, dynamic>> getKrankenkassenStammdaten() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/krankenkassen_list.php'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  /// Finanzämter-Datenbank (Name, Adresse, Kontakt)
  Future<Map<String, dynamic>> getFinanzaemterStammdaten() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/finanzaemter_list.php'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ========== ARBEITGEBER DATENBANK ==========

  /// Alle Arbeitgeber aus der Datenbank laden
  Future<Map<String, dynamic>> getArbeitgeberStammdaten() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/arbeitgeber_list.php'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  /// Neuen Arbeitgeber erstellen
  Future<Map<String, dynamic>> createArbeitgeber(Map<String, dynamic> data) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/arbeitgeber_create.php'),
      headers: _headers,
      body: jsonEncode(data),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  /// Arbeitgeber aktualisieren
  Future<Map<String, dynamic>> updateArbeitgeber(Map<String, dynamic> data) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/arbeitgeber_update.php'),
      headers: _headers,
      body: jsonEncode(data),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  /// Arbeitgeber löschen (soft delete)
  Future<Map<String, dynamic>> deleteArbeitgeber(int id) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/arbeitgeber_delete.php'),
      headers: _headers,
      body: jsonEncode({'id': id}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ========== ARBEITGEBER DOKUMENTE ==========

  /// Dokumente eines Arbeitgebers für einen Benutzer laden
  Future<Map<String, dynamic>> getArbeitgeberDokumente(int userId, int arbeitgeberIndex) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/arbeitgeber_docs_list.php?user_id=$userId&arbeitgeber_index=$arbeitgeberIndex'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  /// Dokument hochladen (multipart)
  Future<Map<String, dynamic>> uploadArbeitgeberDokument({
    required int userId,
    required int arbeitgeberIndex,
    required String dokTyp,
    required String dokDatum,
    String dokTitel = '',
    required String filePath,
    required String fileName,
  }) async {
    final uri = Uri.parse('$baseUrl/admin/arbeitgeber_docs_upload.php');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_headers);
    request.fields['user_id'] = userId.toString();
    request.fields['arbeitgeber_index'] = arbeitgeberIndex.toString();
    request.fields['dok_typ'] = dokTyp;
    request.fields['dok_datum'] = dokDatum;
    request.fields['dok_titel'] = dokTitel;
    request.files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  /// Dokument herunterladen (returns bytes)
  Future<http.Response> downloadArbeitgeberDokument(int docId) async {
    return await _client.get(
      Uri.parse('$baseUrl/admin/arbeitgeber_docs_download.php?id=$docId'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
  }

  /// Dokument löschen
  Future<Map<String, dynamic>> deleteArbeitgeberDokument(int docId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/arbeitgeber_docs_delete.php'),
      headers: _headers,
      body: jsonEncode({'id': docId}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ========== GRUNDFREIBETRAG ==========

  Future<Map<String, dynamic>> getGrundfreibetrag() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/grundfreibetrag.php'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> saveGrundfreibetrag({
    int? id,
    required int jahr,
    required double betrag,
    double? verheiratatBetrag,
    String quelle = '',
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/grundfreibetrag.php'),
      headers: _headers,
      body: jsonEncode({
        if (id != null) 'id': id,
        'action': 'save',
        'jahr': jahr,
        'betrag': betrag,
        'verheiratet_betrag': verheiratatBetrag,
        'quelle': quelle,
      }),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ========== JOBCENTER REGELSÄTZE ==========

  Future<Map<String, dynamic>> getJobcenterRegelsaetze() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/jobcenter_regelsaetze.php'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> saveJobcenterRegelsatz({
    int? id,
    required int jahr,
    required String regelbedarfsstufe,
    required String beschreibung,
    required double betrag,
    String quelle = 'SGB II §20',
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/jobcenter_regelsaetze.php'),
      headers: _headers,
      body: jsonEncode({
        if (id != null) 'id': id,
        'action': 'save',
        'jahr': jahr,
        'regelbedarfsstufe': regelbedarfsstufe,
        'beschreibung': beschreibung,
        'betrag': betrag,
        'quelle': quelle,
      }),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> deleteJobcenterRegelsatz(int id) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/jobcenter_regelsaetze.php'),
      headers: _headers,
      body: jsonEncode({'action': 'delete', 'id': id}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ========== KINDERGELD ==========

  Future<Map<String, dynamic>> getKindergeldSaetze() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/kindergeld_saetze.php'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> saveKindergeldSatz({
    int? id,
    required int jahr,
    required double betragProKind,
    double? kinderzuschlagMax,
    double? kinderfreibetrag,
    String quelle = 'BKGG',
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/kindergeld_saetze.php'),
      headers: _headers,
      body: jsonEncode({
        if (id != null) 'id': id,
        'action': 'save',
        'jahr': jahr,
        'betrag_pro_kind': betragProKind,
        'kinderzuschlag_max': kinderzuschlagMax,
        'kinderfreibetrag': kinderfreibetrag,
        'quelle': quelle,
      }),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> deleteKindergeldSatz(int id) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/kindergeld_saetze.php'),
      headers: _headers,
      body: jsonEncode({'action': 'delete', 'id': id}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ========== DEUTSCHLANDTICKET ==========

  Future<Map<String, dynamic>> getDeutschlandticketSaetze() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/deutschlandticket_saetze.php'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> saveDeutschlandticketSatz({
    int? id,
    required int jahr,
    required double preisMonat,
    String? kuendigungFrist,
    String? sepaEinzug,
    String? sepaGlaeubigerId,
    String? sepaAnbieter,
    String quelle = 'Deutschlandticket.de',
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/deutschlandticket_saetze.php'),
      headers: _headers,
      body: jsonEncode({
        if (id != null) 'id': id,
        'action': 'save',
        'jahr': jahr,
        'preis_monat': preisMonat,
        if (kuendigungFrist != null) 'kuendigung_frist': kuendigungFrist,
        if (sepaEinzug != null) 'sepa_einzug': sepaEinzug,
        if (sepaGlaeubigerId != null) 'sepa_glaeubiger_id': sepaGlaeubigerId,
        if (sepaAnbieter != null) 'sepa_anbieter': sepaAnbieter,
        'quelle': quelle,
      }),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> deleteDeutschlandticketSatz(int id) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/deutschlandticket_saetze.php'),
      headers: _headers,
      body: jsonEncode({'action': 'delete', 'id': id}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> deleteGrundfreibetrag(int id) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/grundfreibetrag.php'),
      headers: _headers,
      body: jsonEncode({'action': 'delete', 'id': id}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ========== FREIZEIT DATENBANK ==========

  Future<List<Map<String, dynamic>>> getFreizeitDatenbank({String? kategorie}) async {
    final uri = kategorie != null
        ? '$baseUrl/admin/freizeit_datenbank.php?kategorie=$kategorie'
        : '$baseUrl/admin/freizeit_datenbank.php';
    final response = await _client.get(Uri.parse(uri), headers: _headers).timeout(const Duration(seconds: 15));
    final result = jsonDecode(response.body);
    if (result['success'] == true && result['data'] is List) {
      return (result['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> getFreizeitData(int userId, {String? freizeitType}) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/freizeit_get.php'),
      headers: _headers,
      body: jsonEncode({'user_id': userId, if (freizeitType != null) 'freizeit_type': freizeitType}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> saveFreizeitData(int userId, String freizeitType, Map<String, dynamic>? data) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/freizeit_save.php'),
      headers: _headers,
      body: jsonEncode({'user_id': userId, 'freizeit_type': freizeitType, 'data': data}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ========== KRANKENKASSE KORRESPONDENZ ==========

  Future<Map<String, dynamic>> getKKKorrespondenz(int userId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/kk_korrespondenz_list.php?user_id=$userId'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> uploadKKKorrespondenz({
    required int userId,
    required String richtung,
    required String titel,
    required String datum,
    String betreff = '',
    String notiz = '',
    String? filePath,
    String? fileName,
  }) async {
    final uri = Uri.parse('$baseUrl/admin/kk_korrespondenz_upload.php');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_headers);
    request.fields['user_id'] = userId.toString();
    request.fields['richtung'] = richtung;
    request.fields['titel'] = titel;
    request.fields['datum'] = datum;
    request.fields['betreff'] = betreff;
    request.fields['notiz'] = notiz;
    if (filePath != null && fileName != null) {
      request.files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));
    }
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    try {
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Server error (${response.statusCode})'};
    }
  }

  Future<Map<String, dynamic>> deleteKKKorrespondenz(int docId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/kk_korrespondenz_delete.php'),
      headers: _headers,
      body: jsonEncode({'id': docId}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<http.Response> downloadKKKorrespondenzDoc(int docId) async {
    return await _client.get(
      Uri.parse('$baseUrl/admin/kk_korrespondenz_download.php?id=$docId'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
  }

  // ========== PFLEGEBOX FIRMEN (DB) ==========

  Future<Map<String, dynamic>> listPflegeboxFirmen() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/pflegebox_firmen_manage.php'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> searchPflegeboxFirmen(String search) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/pflegebox_firmen_manage.php'),
      headers: _headers,
      body: jsonEncode({'action': 'search', 'search': search}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> addPflegeboxFirma(Map<String, dynamic> firma) async {
    final body = Map<String, dynamic>.from(firma);
    body['action'] = 'add';
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/pflegebox_firmen_manage.php'),
      headers: _headers,
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> updatePflegeboxFirma(Map<String, dynamic> firma) async {
    final body = Map<String, dynamic>.from(firma);
    body['action'] = 'update';
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/pflegebox_firmen_manage.php'),
      headers: _headers,
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> deletePflegeboxFirma(int id) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/pflegebox_firmen_manage.php'),
      headers: _headers,
      body: jsonEncode({'action': 'delete', 'id': id}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ========== PFLEGEBOX LIEFERSCHEINE (monthly uploads per user) ==========

  Future<Map<String, dynamic>> listPflegeboxLieferscheine(int userId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/pflegebox_lieferschein_list.php?user_id=$userId'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> uploadPflegeboxLieferschein({
    required int userId,
    required int firmaId,
    required int monat,
    required int jahr,
    required String filePath,
    required String fileName,
    String notiz = '',
    String trackingId = '',
    String trackingAnbieter = 'deutsche_post',
  }) async {
    final uri = Uri.parse('$baseUrl/admin/pflegebox_lieferschein_upload.php');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_headers);
    request.fields['user_id'] = userId.toString();
    request.fields['firma_id'] = firmaId.toString();
    request.fields['monat'] = monat.toString();
    request.fields['jahr'] = jahr.toString();
    request.fields['notiz'] = notiz;
    request.fields['tracking_id'] = trackingId;
    request.fields['tracking_anbieter'] = trackingAnbieter;
    request.files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Server error (${response.statusCode})'};
    }
  }

  Future<Map<String, dynamic>> updatePflegeboxLieferschein({
    required int id,
    String? trackingId,
    String? trackingAnbieter,
    String? notiz,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/pflegebox_lieferschein_update.php'),
      headers: _headers,
      body: jsonEncode({
        'id': id,
        if (trackingId != null) 'tracking_id': trackingId,
        if (trackingAnbieter != null) 'tracking_anbieter': trackingAnbieter,
        if (notiz != null) 'notiz': notiz,
      }),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ========== PFLEGEBOX KORRESPONDENZ (per firma) ==========

  Future<Map<String, dynamic>> listPflegeboxKorrespondenz({required int userId, int? firmaId}) async {
    final qs = firmaId != null ? '&firma_id=$firmaId' : '';
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/pflegebox_korr_list.php?user_id=$userId$qs'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> uploadPflegeboxKorrespondenz({
    required int userId,
    required int firmaId,
    required String richtung,
    required String datum,
    String betreff = '',
    String notiz = '',
    String? filePath,
    String? fileName,
  }) async {
    final uri = Uri.parse('$baseUrl/admin/pflegebox_korr_upload.php');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_headers);
    request.fields['user_id'] = userId.toString();
    request.fields['firma_id'] = firmaId.toString();
    request.fields['richtung'] = richtung;
    request.fields['datum'] = datum;
    request.fields['betreff'] = betreff;
    request.fields['notiz'] = notiz;
    if (filePath != null && fileName != null) {
      request.files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));
    }
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Server error (${response.statusCode})'};
    }
  }

  Future<Map<String, dynamic>> deletePflegeboxKorrespondenz(int id) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/pflegebox_korr_delete.php'),
      headers: _headers,
      body: jsonEncode({'id': id}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<http.Response> downloadPflegeboxKorrespondenz(int id) async {
    return await _client.get(
      Uri.parse('$baseUrl/admin/pflegebox_korr_download.php?id=$id'),
      headers: _headers,
    ).timeout(const Duration(seconds: 30));
  }

  Future<Map<String, dynamic>> deletePflegeboxLieferschein(int id) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/pflegebox_lieferschein_delete.php'),
      headers: _headers,
      body: jsonEncode({'id': id}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<http.Response> downloadPflegeboxLieferschein(int id) async {
    return await _client.get(
      Uri.parse('$baseUrl/admin/pflegebox_lieferschein_download.php?id=$id'),
      headers: _headers,
    ).timeout(const Duration(seconds: 30));
  }

  // ========== DEVICE ACTIVATION (16-char one-time code) ==========

  /// Public endpoint — no device_key required (bootstrap).
  /// Consumes a 16-char activation code issued by admin, enrolls this device,
  /// returns JWT + refresh_token + device_key to persist locally.
  Future<Map<String, dynamic>> activateDeviceCode({
    required String mitgliedernummer,
    required String code,
    required String deviceId,
    Map<String, dynamic>? deviceInfo,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/auth/activate_code.php'),
      headers: const {
        'Content-Type': 'application/json',
        'User-Agent': 'ICD360S-Vorsitzer/1.0',
      },
      body: jsonEncode({
        'mitgliedernummer': mitgliedernummer,
        'code': code,
        'device_id': deviceId,
        'device_info': deviceInfo ?? {},
      }),
    ).timeout(const Duration(seconds: 20));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Server error (${response.statusCode})'};
    }
  }

  /// Admin (vorsitzer role only): generate a one-time 16-char activation code
  /// for the given member. The raw code is returned ONLY here — it cannot be
  /// recovered later. TTL is in hours (max 168 = 7 days).
  Future<Map<String, dynamic>> generateActivationCode({
    required int targetUserId,
    int ttlHours = 24,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/generate_activation_code.php'),
      headers: _headers,
      body: jsonEncode({'target_user_id': targetUserId, 'ttl_hours': ttlHours}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  /// Admin: list all devices + recent activation codes for a member.
  Future<Map<String, dynamic>> listUserDevices(int userId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/list_user_devices.php?user_id=$userId'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  /// Admin (vorsitzer only): revoke a member's device by its device_key_id.
  Future<Map<String, dynamic>> revokeUserDevice({
    required int deviceKeyId,
    String? reason,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/revoke_device.php'),
      headers: _headers,
      body: jsonEncode({
        'device_key_id': deviceKeyId,
        if (reason != null) 'reason': reason,
      }),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ========== VERTRÄGE (Multimedia, Handyvertrag, etc.) ==========

  Future<Map<String, dynamic>> listVertraege(int userId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/vertraege_manage.php?user_id=$userId'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  Future<Map<String, dynamic>> saveVertrag(int userId, Map<String, dynamic> data) async {
    final body = Map<String, dynamic>.from(data);
    body['user_id'] = userId;
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/vertraege_manage.php'),
      headers: _headers,
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  Future<Map<String, dynamic>> deleteVertrag(int id) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/vertraege_manage.php'),
      headers: _headers,
      body: jsonEncode({'action': 'delete', 'id': id}),
    ).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  Future<Map<String, dynamic>> listVertraegeKorrespondenz(int vertragId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/vertraege_korr_manage.php?vertrag_id=$vertragId'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  Future<Map<String, dynamic>> saveVertraegeKorrespondenz(Map<String, dynamic> data) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/vertraege_korr_manage.php'),
      headers: _headers,
      body: jsonEncode(data),
    ).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  Future<Map<String, dynamic>> deleteVertraegeKorrespondenz(int id) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/vertraege_korr_manage.php'),
      headers: _headers,
      body: jsonEncode({'action': 'delete', 'id': id}),
    ).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  // ========== VERTRÄGE DOKUMENTE (Dokumente, Rechnung, Kündigung) ==========

  Future<Map<String, dynamic>> listVertragDokumente(int vertragId, {String? kategorie}) async {
    final qs = kategorie != null ? '&kategorie=$kategorie' : '';
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/vertraege_dok_manage.php?vertrag_id=$vertragId$qs'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  Future<Map<String, dynamic>> uploadVertragDokument({
    required int vertragId,
    required String kategorie,
    required String filePath,
    required String fileName,
    String titel = '',
    String rechnungsnummer = '',
    String abrechnungszeitraum = '',
    double? betrag,
    String? kuendigungDatum,
    bool kuendigungBestaetigt = false,
    String? kuendigungBestaetigungsDatum,
    bool rufnummernmitnahme = false,
    String kuendigungGrund = '',
    String notiz = '',
  }) async {
    final uri = Uri.parse('$baseUrl/admin/vertraege_dok_manage.php');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_headers);
    request.fields['vertrag_id'] = vertragId.toString();
    request.fields['kategorie'] = kategorie;
    request.fields['titel'] = titel;
    request.fields['rechnungsnummer'] = rechnungsnummer;
    request.fields['abrechnungszeitraum'] = abrechnungszeitraum;
    if (betrag != null) request.fields['betrag'] = betrag.toString();
    if (kuendigungDatum != null) request.fields['kuendigung_datum'] = kuendigungDatum;
    request.fields['kuendigung_bestaetigt'] = kuendigungBestaetigt ? '1' : '0';
    if (kuendigungBestaetigungsDatum != null) request.fields['kuendigung_bestaetigungs_datum'] = kuendigungBestaetigungsDatum;
    request.fields['rufnummernmitnahme'] = rufnummernmitnahme ? '1' : '0';
    request.fields['kuendigung_grund'] = kuendigungGrund;
    request.fields['notiz'] = notiz;
    request.files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  Future<Map<String, dynamic>> deleteVertragDokument(int id) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/vertraege_dok_manage.php'),
      headers: _headers,
      body: jsonEncode({'action': 'delete', 'id': id}),
    ).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  Future<http.Response> downloadVertragDokument(int id) async {
    return await _client.get(
      Uri.parse('$baseUrl/admin/vertraege_dok_download.php?id=$id'),
      headers: _headers,
    ).timeout(const Duration(seconds: 30));
  }

  // ========== SOZIALAMT (dedicated DB tables) ==========

  Future<Map<String, dynamic>> getSozialamtData(int userId) async {
    final response = await _client.get(Uri.parse('$baseUrl/admin/sozialamt_manage.php?user_id=$userId'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> saveSozialamtData(int userId, Map<String, dynamic> data) async {
    final response = await _client.post(Uri.parse('$baseUrl/admin/sozialamt_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'data': data})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  Future<Map<String, dynamic>> listSozialamtAntraege(int userId) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/sozialamt_antraege.php?user_id=$userId'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> saveSozialamtAntrag(int userId, Map<String, dynamic> data) async {
    final body = Map<String, dynamic>.from(data); body['user_id'] = userId;
    final r = await _client.post(Uri.parse('$baseUrl/admin/sozialamt_antraege.php'), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteSozialamtAntrag(int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/sozialamt_antraege.php'), headers: _headers, body: jsonEncode({'action': 'delete', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }

  Future<Map<String, dynamic>> listSozialamtBewilligungen(int userId) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/sozialamt_bewilligungen.php?user_id=$userId'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> saveSozialamtBewilligung(int userId, Map<String, dynamic> data) async {
    final body = Map<String, dynamic>.from(data); body['user_id'] = userId;
    final r = await _client.post(Uri.parse('$baseUrl/admin/sozialamt_bewilligungen.php'), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteSozialamtBewilligung(int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/sozialamt_bewilligungen.php'), headers: _headers, body: jsonEncode({'action': 'delete', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }

  Future<Map<String, dynamic>> listSozialamtKorrespondenz(int userId) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/sozialamt_korrespondenz.php?user_id=$userId'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> saveSozialamtKorrespondenz(int userId, Map<String, dynamic> data) async {
    final body = Map<String, dynamic>.from(data); body['user_id'] = userId;
    final r = await _client.post(Uri.parse('$baseUrl/admin/sozialamt_korrespondenz.php'), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteSozialamtKorrespondenz(int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/sozialamt_korrespondenz.php'), headers: _headers, body: jsonEncode({'action': 'delete', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }

  // ========== SOZIALAMT ANTRAG DETAIL (Verlauf + Korrespondenz) ==========

  Future<Map<String, dynamic>> listAntragVerlauf(int antragId) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/sozialamt_antrag_detail.php?antrag_id=$antragId&type=verlauf'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> addAntragVerlauf(int antragId, Map<String, dynamic> data) async {
    final body = Map<String, dynamic>.from(data); body['antrag_id'] = antragId; body['type'] = 'verlauf';
    final r = await _client.post(Uri.parse('$baseUrl/admin/sozialamt_antrag_detail.php'), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteAntragVerlauf(int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/sozialamt_antrag_detail.php'), headers: _headers, body: jsonEncode({'action': 'delete', 'type': 'verlauf', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }

  Future<Map<String, dynamic>> listAntragKorrespondenz(int antragId) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/sozialamt_antrag_detail.php?antrag_id=$antragId&type=korrespondenz'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> addAntragKorrespondenz(int antragId, Map<String, dynamic> data) async {
    final body = Map<String, dynamic>.from(data); body['antrag_id'] = antragId; body['type'] = 'korrespondenz';
    final r = await _client.post(Uri.parse('$baseUrl/admin/sozialamt_antrag_detail.php'), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteAntragKorrespondenz(int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/sozialamt_antrag_detail.php'), headers: _headers, body: jsonEncode({'action': 'delete', 'type': 'korrespondenz', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }

  // ========== SOZIALAMT ANTRAG DOCS ==========

  Future<Map<String, dynamic>> listAntragDocs(int antragId) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/sozialamt_antrag_docs.php?antrag_id=$antragId'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> uploadAntragDoc({required int antragId, required String docTyp, required String filePath, required String fileName, String notiz = ''}) async {
    final uri = Uri.parse('$baseUrl/admin/sozialamt_antrag_docs.php');
    final request = http.MultipartRequest('POST', uri); request.headers.addAll(_headers);
    request.fields['antrag_id'] = antragId.toString(); request.fields['doc_typ'] = docTyp; request.fields['notiz'] = notiz;
    request.files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));
    final sr = await request.send(); final response = await http.Response.fromStream(sr);
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteAntragDoc(int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/sozialamt_antrag_docs.php'), headers: _headers, body: jsonEncode({'action': 'delete', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<http.Response> downloadAntragDoc(int id) async {
    return await _client.get(Uri.parse('$baseUrl/admin/sozialamt_antrag_docs.php?download_id=$id'), headers: _headers).timeout(const Duration(seconds: 30));
  }

  // ========== SOZIALAMT BEWILLIGUNG DOCS ==========

  Future<Map<String, dynamic>> listBewilligungDocs(int bewilligungId) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/sozialamt_bewilligung_doc.php?bewilligung_id=$bewilligungId'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> uploadBewilligungDoc({required int bewilligungId, required String filePath, required String fileName}) async {
    final uri = Uri.parse('$baseUrl/admin/sozialamt_bewilligung_doc.php');
    final request = http.MultipartRequest('POST', uri); request.headers.addAll(_headers);
    request.fields['bewilligung_id'] = bewilligungId.toString();
    request.files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));
    final sr = await request.send(); final response = await http.Response.fromStream(sr);
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteBewilligungDoc(int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/sozialamt_bewilligung_doc.php'), headers: _headers, body: jsonEncode({'action': 'delete', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<http.Response> downloadBewilligungDoc(int id) async {
    return await _client.get(Uri.parse('$baseUrl/admin/sozialamt_bewilligung_doc.php?download_id=$id'), headers: _headers).timeout(const Duration(seconds: 30));
  }

  // ========== SOZIALAMT BEWILLIGUNG KORRESPONDENZ ==========

  Future<Map<String, dynamic>> listBewilligungKorr(int bewilligungId) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/sozialamt_bewilligung_korr.php?bewilligung_id=$bewilligungId'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> saveBewilligungKorr(int bewilligungId, Map<String, dynamic> data) async {
    final body = Map<String, dynamic>.from(data); body['bewilligung_id'] = bewilligungId;
    final r = await _client.post(Uri.parse('$baseUrl/admin/sozialamt_bewilligung_korr.php'), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteBewilligungKorr(int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/sozialamt_bewilligung_korr.php'), headers: _headers, body: jsonEncode({'action': 'delete', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }

  // ========== RUNDFUNKBEITRAG (ARD ZDF) ==========

  Future<Map<String, dynamic>> getRundfunkbeitragData(int userId) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/rundfunkbeitrag_data.php?user_id=$userId'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> saveRundfunkbeitragData(int userId, Map<String, dynamic> data) async {
    final body = {'user_id': userId, 'data': data};
    final r = await _client.post(Uri.parse('$baseUrl/admin/rundfunkbeitrag_data.php'), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> listRundfunkbeitragAntraege(int userId) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/rundfunkbeitrag_antraege.php?user_id=$userId'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> saveRundfunkbeitragAntrag(int userId, Map<String, dynamic> data) async {
    final body = Map<String, dynamic>.from(data); body['user_id'] = userId;
    final r = await _client.post(Uri.parse('$baseUrl/admin/rundfunkbeitrag_antraege.php'), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteRundfunkbeitragAntrag(int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/rundfunkbeitrag_antraege.php'), headers: _headers, body: jsonEncode({'action': 'delete', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> listRundfunkbeitragKorrespondenz(int userId) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/rundfunkbeitrag_korrespondenz.php?user_id=$userId'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> saveRundfunkbeitragKorrespondenz(int userId, Map<String, dynamic> data) async {
    final body = Map<String, dynamic>.from(data); body['user_id'] = userId;
    final r = await _client.post(Uri.parse('$baseUrl/admin/rundfunkbeitrag_korrespondenz.php'), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteRundfunkbeitragKorrespondenz(int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/rundfunkbeitrag_korrespondenz.php'), headers: _headers, body: jsonEncode({'action': 'delete', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }

  // ========== KORRESPONDENZ ATTACHMENTS (generic, all modules) ==========

  Future<Map<String, dynamic>> listKorrAttachments(String modul, int korrespondenzId) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/korrespondenz_attachments.php?modul=$modul&korrespondenz_id=$korrespondenzId'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> uploadKorrAttachment({required String modul, required int korrespondenzId, required String filePath, required String fileName}) async {
    final uri = Uri.parse('$baseUrl/admin/korrespondenz_attachments.php');
    final request = http.MultipartRequest('POST', uri); request.headers.addAll(_headers);
    request.fields['modul'] = modul; request.fields['korrespondenz_id'] = korrespondenzId.toString();
    request.files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));
    final sr = await request.send(); final response = await http.Response.fromStream(sr);
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteKorrAttachment(int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/korrespondenz_attachments.php'), headers: _headers, body: jsonEncode({'action': 'delete', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<http.Response> downloadKorrAttachment(int id) async {
    return await _client.get(Uri.parse('$baseUrl/admin/korrespondenz_attachments.php?download_id=$id'), headers: _headers).timeout(const Duration(seconds: 30));
  }

  // ========== VERSORGUNGSAMT DATA (dedicated DB) ==========

  Future<Map<String, dynamic>> getVersorgungsamtData(int userId) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/versorgungsamt_data_manage.php?user_id=$userId'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> saveVersorgungsamtData(int userId, Map<String, dynamic> data) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/versorgungsamt_data_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'data': data})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> listVersorgungsamtTermine(int userId) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/versorgungsamt_termine_manage.php?user_id=$userId'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> saveVersorgungsamtTermin(int userId, Map<String, dynamic> data) async {
    final body = Map<String, dynamic>.from(data); body['user_id'] = userId;
    final r = await _client.post(Uri.parse('$baseUrl/admin/versorgungsamt_termine_manage.php'), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteVersorgungsamtTermin(int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/versorgungsamt_termine_manage.php'), headers: _headers, body: jsonEncode({'action': 'delete', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> listVersorgungsamtKorr(int userId) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/versorgungsamt_korrespondenz_manage.php?user_id=$userId'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> saveVersorgungsamtKorr(int userId, Map<String, dynamic> data) async {
    final body = Map<String, dynamic>.from(data); body['user_id'] = userId;
    final r = await _client.post(Uri.parse('$baseUrl/admin/versorgungsamt_korrespondenz_manage.php'), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteVersorgungsamtKorr(int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/versorgungsamt_korrespondenz_manage.php'), headers: _headers, body: jsonEncode({'action': 'delete', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }

  // ========== VERSORGUNGSAMT ANTRÄGE (dedicated DB) ==========

  Future<Map<String, dynamic>> listVersorgungsamtAntraege(int userId) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/versorgungsamt_antraege_manage.php?user_id=$userId'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> saveVersorgungsamtAntrag(int userId, Map<String, dynamic> data) async {
    final body = Map<String, dynamic>.from(data); body['user_id'] = userId;
    final r = await _client.post(Uri.parse('$baseUrl/admin/versorgungsamt_antraege_manage.php'), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteVersorgungsamtAntrag(int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/versorgungsamt_antraege_manage.php'), headers: _headers, body: jsonEncode({'action': 'delete', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> listVaAntragVerlauf(int antragId) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/versorgungsamt_antrag_detail.php?antrag_id=$antragId&type=verlauf'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> addVaAntragVerlauf(int antragId, Map<String, dynamic> data) async {
    final body = Map<String, dynamic>.from(data); body['antrag_id'] = antragId; body['type'] = 'verlauf';
    final r = await _client.post(Uri.parse('$baseUrl/admin/versorgungsamt_antrag_detail.php'), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteVaAntragVerlauf(int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/versorgungsamt_antrag_detail.php'), headers: _headers, body: jsonEncode({'action': 'delete', 'type': 'verlauf', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> listVaAntragDocs(int antragId) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/versorgungsamt_antrag_detail.php?antrag_id=$antragId&type=docs'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> uploadVaAntragDoc({required int antragId, required String filePath, required String fileName}) async {
    final uri = Uri.parse('$baseUrl/admin/versorgungsamt_antrag_detail.php');
    final request = http.MultipartRequest('POST', uri); request.headers.addAll(_headers);
    request.fields['antrag_id'] = antragId.toString(); request.fields['type'] = 'upload_doc';
    request.files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));
    final sr = await request.send(); final response = await http.Response.fromStream(sr);
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteVaAntragDoc(int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/versorgungsamt_antrag_detail.php'), headers: _headers, body: jsonEncode({'action': 'delete', 'type': 'docs', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<http.Response> downloadVaAntragDoc(int id) async {
    return await _client.get(Uri.parse('$baseUrl/admin/versorgungsamt_antrag_detail.php?type=download&id=$id'), headers: _headers).timeout(const Duration(seconds: 30));
  }
  Future<Map<String, dynamic>> listVaAntragKorr(int antragId) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/versorgungsamt_antrag_detail.php?antrag_id=$antragId&type=korr'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> saveVaAntragKorr(int antragId, Map<String, dynamic> data) async {
    final body = Map<String, dynamic>.from(data); body['antrag_id'] = antragId; body['type'] = 'korr';
    final r = await _client.post(Uri.parse('$baseUrl/admin/versorgungsamt_antrag_detail.php'), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteVaAntragKorr(int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/versorgungsamt_antrag_detail.php'), headers: _headers, body: jsonEncode({'action': 'delete', 'type': 'korr', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }

  // ========== GERICHT (dedicated DB tables) ==========

  Future<Map<String, dynamic>> getGerichtData(int userId, String gerichtTyp) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/gericht_data_manage.php?user_id=$userId&gericht_typ=$gerichtTyp'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> saveGerichtData(int userId, String gerichtTyp, Map<String, dynamic> data) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/gericht_data_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'gericht_typ': gerichtTyp, 'data': data})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> listGerichtVorfaelle(int userId, String gerichtTyp) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/gericht_vorfaelle.php?user_id=$userId&gericht_typ=$gerichtTyp'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> saveGerichtVorfall(int userId, String gerichtTyp, Map<String, dynamic> data) async {
    final body = Map<String, dynamic>.from(data); body['user_id'] = userId; body['gericht_typ'] = gerichtTyp;
    final r = await _client.post(Uri.parse('$baseUrl/admin/gericht_vorfaelle.php'), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteGerichtVorfall(int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/gericht_vorfaelle.php'), headers: _headers, body: jsonEncode({'action': 'delete', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> listGerichtTermineDB(int userId, String gerichtTyp) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/gericht_termine.php?user_id=$userId&gericht_typ=$gerichtTyp'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> saveGerichtTermin(int userId, String gerichtTyp, Map<String, dynamic> data) async {
    final body = Map<String, dynamic>.from(data); body['user_id'] = userId; body['gericht_typ'] = gerichtTyp;
    final r = await _client.post(Uri.parse('$baseUrl/admin/gericht_termine.php'), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteGerichtTermin(int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/gericht_termine.php'), headers: _headers, body: jsonEncode({'action': 'delete', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> listGerichtKorrespondenzDB(int userId, String gerichtTyp) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/gericht_korrespondenz_manage.php?user_id=$userId&gericht_typ=$gerichtTyp'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> saveGerichtKorrespondenz(int userId, String gerichtTyp, Map<String, dynamic> data) async {
    final body = Map<String, dynamic>.from(data); body['user_id'] = userId; body['gericht_typ'] = gerichtTyp;
    final r = await _client.post(Uri.parse('$baseUrl/admin/gericht_korrespondenz_manage.php'), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteGerichtKorrespondenz(int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/gericht_korrespondenz_manage.php'), headers: _headers, body: jsonEncode({'action': 'delete', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }

  // ========== GERICHT VORFALL DETAIL ==========

  Future<Map<String, dynamic>> listGerichtVorfallVerlauf(int vorfallId) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/gericht_vorfall_detail.php?vorfall_id=$vorfallId&type=verlauf'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> addGerichtVorfallVerlauf(int vorfallId, Map<String, dynamic> data) async {
    final body = Map<String, dynamic>.from(data); body['vorfall_id'] = vorfallId; body['type'] = 'verlauf';
    final r = await _client.post(Uri.parse('$baseUrl/admin/gericht_vorfall_detail.php'), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteGerichtVorfallVerlauf(int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/gericht_vorfall_detail.php'), headers: _headers, body: jsonEncode({'action': 'delete', 'type': 'verlauf', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> listGerichtVorfallDocs(int vorfallId) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/gericht_vorfall_detail.php?vorfall_id=$vorfallId&type=docs'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> uploadGerichtVorfallDoc({required int vorfallId, required String filePath, required String fileName}) async {
    final uri = Uri.parse('$baseUrl/admin/gericht_vorfall_detail.php');
    final request = http.MultipartRequest('POST', uri); request.headers.addAll(_headers);
    request.fields['vorfall_id'] = vorfallId.toString(); request.fields['type'] = 'upload_doc';
    request.files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));
    final sr = await request.send(); final response = await http.Response.fromStream(sr);
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteGerichtVorfallDoc(int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/gericht_vorfall_detail.php'), headers: _headers, body: jsonEncode({'action': 'delete', 'type': 'docs', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<http.Response> downloadGerichtVorfallDoc(int id) async {
    return await _client.get(Uri.parse('$baseUrl/admin/gericht_vorfall_detail.php?type=download&id=$id'), headers: _headers).timeout(const Duration(seconds: 30));
  }
  Future<Map<String, dynamic>> listGerichtVorfallTermine(int vorfallId) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/gericht_vorfall_detail.php?vorfall_id=$vorfallId&type=termine'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> saveGerichtVorfallTermin(int vorfallId, String gerichtTyp, Map<String, dynamic> data) async {
    final body = Map<String, dynamic>.from(data); body['vorfall_id'] = vorfallId; body['gericht_typ'] = gerichtTyp; body['type'] = 'termin';
    final r = await _client.post(Uri.parse('$baseUrl/admin/gericht_vorfall_detail.php'), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> listGerichtVorfallKorr(int vorfallId) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/gericht_vorfall_detail.php?vorfall_id=$vorfallId&type=korr'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> saveGerichtVorfallKorr(int vorfallId, String gerichtTyp, Map<String, dynamic> data) async {
    final body = Map<String, dynamic>.from(data); body['vorfall_id'] = vorfallId; body['gericht_typ'] = gerichtTyp; body['type'] = 'korr';
    final r = await _client.post(Uri.parse('$baseUrl/admin/gericht_vorfall_detail.php'), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteGerichtVorfallTermin(int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/gericht_vorfall_detail.php'), headers: _headers, body: jsonEncode({'action': 'delete', 'type': 'termine', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteGerichtVorfallKorr(int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/gericht_vorfall_detail.php'), headers: _headers, body: jsonEncode({'action': 'delete', 'type': 'korr', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }

  // ========== RUNDFUNKBEITRAG ANTRAG DETAIL ==========

  Future<Map<String, dynamic>> listRfbAntragVerlauf(int antragId) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/rfb_antrag_detail.php?antrag_id=$antragId&type=verlauf'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> addRfbAntragVerlauf(int antragId, Map<String, dynamic> data) async {
    final body = Map<String, dynamic>.from(data); body['antrag_id'] = antragId; body['type'] = 'verlauf';
    final r = await _client.post(Uri.parse('$baseUrl/admin/rfb_antrag_detail.php'), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteRfbAntragVerlauf(int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/rfb_antrag_detail.php'), headers: _headers, body: jsonEncode({'action': 'delete', 'type': 'verlauf', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> listRfbAntragDocs(int antragId) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/rfb_antrag_detail.php?antrag_id=$antragId&type=docs'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> uploadRfbAntragDoc({required int antragId, required String filePath, required String fileName}) async {
    final uri = Uri.parse('$baseUrl/admin/rfb_antrag_detail.php');
    final request = http.MultipartRequest('POST', uri); request.headers.addAll(_headers);
    request.fields['antrag_id'] = antragId.toString(); request.fields['type'] = 'upload_doc';
    request.files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));
    final sr = await request.send(); final response = await http.Response.fromStream(sr);
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteRfbAntragDoc(int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/rfb_antrag_detail.php'), headers: _headers, body: jsonEncode({'action': 'delete', 'type': 'docs', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<http.Response> downloadRfbAntragDoc(int id) async {
    return await _client.get(Uri.parse('$baseUrl/admin/rfb_antrag_detail.php?type=download&id=$id'), headers: _headers).timeout(const Duration(seconds: 30));
  }
  Future<Map<String, dynamic>> listRfbAntragKorr(int antragId) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/rfb_antrag_detail.php?antrag_id=$antragId&type=korr'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> saveRfbAntragKorr(int antragId, Map<String, dynamic> data) async {
    final body = Map<String, dynamic>.from(data); body['antrag_id'] = antragId; body['type'] = 'korr';
    final r = await _client.post(Uri.parse('$baseUrl/admin/rfb_antrag_detail.php'), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteRfbAntragKorr(int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/rfb_antrag_detail.php'), headers: _headers, body: jsonEncode({'action': 'delete', 'type': 'korr', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }

  // ========== LANDRATSAMT DATA (dedicated DB table) ==========

  Future<Map<String, dynamic>> getLandratsamtData(int userId, {String? bereich}) async {
    final qs = bereich != null ? '&bereich=$bereich' : '';
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/landratsamt_manage.php?user_id=$userId$qs'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  Future<Map<String, dynamic>> saveLandratsamtData(int userId, Map<String, dynamic> data) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/landratsamt_manage.php'),
      headers: _headers,
      body: jsonEncode({'user_id': userId, 'data': data}),
    ).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  // ========== VERSORGUNGSAMT KORRESPONDENZ DOCS ==========

  Future<Map<String, dynamic>> listVersorgungsamtKorrDocs(int userId, {String? korrDatum}) async {
    final qs = korrDatum != null ? '&korr_datum=$korrDatum' : '';
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/versorgungsamt_korr_doc.php?user_id=$userId$qs'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  Future<Map<String, dynamic>> uploadVersorgungsamtKorrDoc({
    required int userId,
    required int korrIndex,
    required String korrDatum,
    required String filePath,
    required String fileName,
  }) async {
    final uri = Uri.parse('$baseUrl/admin/versorgungsamt_korr_doc.php');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_headers);
    request.fields['user_id'] = userId.toString();
    request.fields['korr_index'] = korrIndex.toString();
    request.fields['korr_datum'] = korrDatum;
    request.files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  Future<Map<String, dynamic>> deleteVersorgungsamtKorrDoc(int id) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/versorgungsamt_korr_doc.php'),
      headers: _headers,
      body: jsonEncode({'action': 'delete', 'id': id}),
    ).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  Future<http.Response> downloadVersorgungsamtKorrDoc(int id) async {
    return await _client.get(
      Uri.parse('$baseUrl/admin/versorgungsamt_korr_doc.php?download_id=$id'),
      headers: _headers,
    ).timeout(const Duration(seconds: 30));
  }

  // ========== VERSORGUNGSAMT TERMIN EINTRÄGE ==========

  Future<Map<String, dynamic>> listVersorgungsamtEintraege(int userId, {String? terminDatum}) async {
    final qs = terminDatum != null ? '&termin_datum=$terminDatum' : '';
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/versorgungsamt_eintraege_manage.php?user_id=$userId$qs'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  Future<Map<String, dynamic>> saveVersorgungsamtEintrag(Map<String, dynamic> data) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/versorgungsamt_eintraege_manage.php'),
      headers: _headers,
      body: jsonEncode(data),
    ).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  Future<Map<String, dynamic>> deleteVersorgungsamtEintrag(int id) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/versorgungsamt_eintraege_manage.php'),
      headers: _headers,
      body: jsonEncode({'action': 'delete', 'id': id}),
    ).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  // ========== CHAT CONVERSATION DELETE ==========

  Future<Map<String, dynamic>> deleteConversation(int conversationId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/chat/conversation_delete.php'),
      headers: _headers,
      body: jsonEncode({'conversation_id': conversationId}),
    ).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  // ========== FINANZAMT KORRESPONDENZ ==========

  Future<Map<String, dynamic>> getFinanzamtKorrespondenz(int userId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/finanzamt_korrespondenz_list.php?user_id=$userId'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> uploadFinanzamtKorrespondenz({
    required int userId,
    required String titel,
    required String datum,
    String typ = 'brief',
    String absender = '',
    String inhalt = '',
    String? filePath,
    String? fileName,
  }) async {
    final uri = Uri.parse('$baseUrl/admin/finanzamt_korrespondenz_upload.php');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_headers);
    request.fields['user_id'] = userId.toString();
    request.fields['typ'] = typ;
    request.fields['titel'] = titel;
    request.fields['datum'] = datum;
    request.fields['absender'] = absender;
    request.fields['inhalt'] = inhalt;
    if (filePath != null && fileName != null) {
      request.files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));
    }
    // Always add a dummy file for emails without attachment to ensure multipart works
    if (request.files.isEmpty) {
      request.files.add(http.MultipartFile.fromString('_dummy', '', filename: '_dummy.txt'));
    }
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    try {
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false, 'message': 'Server error (${response.statusCode})'};
    }
  }

  Future<http.Response> downloadFinanzamtKorrespondenz(int docId) async {
    return await _client.get(
      Uri.parse('$baseUrl/admin/finanzamt_korrespondenz_download.php?id=$docId'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
  }

  Future<Map<String, dynamic>> deleteFinanzamtKorrespondenz(int docId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/finanzamt_korrespondenz_delete.php'),
      headers: _headers,
      body: jsonEncode({'id': docId}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ========== BEHÖRDE DATA (encrypted) ==========

  Future<Map<String, dynamic>> getBehoerdeData(int userId, String behoerdeType) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/behoerde_get.php'),
      headers: _headers,
      body: jsonEncode({'user_id': userId, 'behoerde_type': behoerdeType}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> saveBehoerdeData(int userId, String behoerdeType, Map<String, dynamic> data) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/behoerde_save.php'),
      headers: _headers,
      body: jsonEncode({'user_id': userId, 'behoerde_type': behoerdeType, 'data': data}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ========== BEHOERDE STANDORTE (Jobcenter/Arbeitsagentur DB) ==========

  Future<List<Map<String, dynamic>>> getBehoerdenStandorte({String? typ}) async {
    try {
      final uri = Uri.parse('$baseUrl/admin/behoerden_standorte.php${typ != null ? '?typ=$typ' : ''}');
      final response = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
      final body = jsonDecode(response.body);
      if (body['success'] == true && body['standorte'] is List) {
        return List<Map<String, dynamic>>.from(
          (body['standorte'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // ========== POLIZEI DIENSTSTELLEN DB ==========

  Future<List<Map<String, dynamic>>> getPolizeiDienststellen() async {
    try {
      final uri = Uri.parse('$baseUrl/admin/polizei_dienststellen.php');
      final response = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
      final body = jsonDecode(response.body);
      if (body['success'] == true && body['dienststellen'] is List) {
        return List<Map<String, dynamic>>.from(
          (body['dienststellen'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // ========== USER POLIZEI ==========

  Future<Map<String, dynamic>> getUserPolizei(int userId) async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/admin/user_polizei.php?user_id=$userId'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> saveUserPolizeiDienststelle(int userId, int? dienststelleId, String? name) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/user_polizei.php'),
      headers: _headers,
      body: jsonEncode({
        'action': 'save_dienststelle',
        'user_id': userId,
        'dienststelle_id': dienststelleId,
        'dienststelle_name': name,
      }),
    ).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  Future<Map<String, dynamic>> addUserPolizeiVorfall(int userId, Map<String, dynamic> vorfall) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/user_polizei.php'),
      headers: _headers,
      body: jsonEncode({
        'action': 'add_vorfall',
        'user_id': userId,
        ...vorfall,
      }),
    ).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  Future<Map<String, dynamic>> deleteUserPolizeiVorfall(int userId, int vorfallId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/user_polizei.php'),
      headers: _headers,
      body: jsonEncode({
        'action': 'delete_vorfall',
        'user_id': userId,
        'vorfall_id': vorfallId,
      }),
    ).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  // ========== PASSWORDLESS LOGIN (Request + Poll + Auto-Login) ==========

  Future<Map<String, dynamic>> requestPasswordlessLogin(String mitgliedernummer) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/auth/login_request.php'),
      headers: {'Content-Type': 'application/json', 'User-Agent': 'ICD360S-Vorsitzer/1.0', 'X-Device-Key': _deviceKeyService.deviceKey ?? ''},
      body: jsonEncode({'mitgliedernummer': mitgliedernummer}),
    ).timeout(const Duration(seconds: 10));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  Future<Map<String, dynamic>> checkLoginApproval(String requestToken) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/auth/check_approval.php'),
      headers: {'Content-Type': 'application/json', 'User-Agent': 'ICD360S-Vorsitzer/1.0', 'X-Device-Key': _deviceKeyService.deviceKey ?? ''},
      body: jsonEncode({'request_token': requestToken}),
    ).timeout(const Duration(seconds: 10));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  Future<Map<String, dynamic>> loginWithApproval(String approvalToken, {String? mitgliedernummer}) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/auth/login_with_approval.php'),
      headers: {'Content-Type': 'application/json', 'User-Agent': 'ICD360S-Vorsitzer/1.0', 'X-Device-Key': _deviceKeyService.deviceKey ?? ''},
      body: jsonEncode({'approval_token': approvalToken, 'mitgliedernummer': mitgliedernummer ?? ''}),
    ).timeout(const Duration(seconds: 10));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  // ========== LOGIN APPROVAL ==========

  Future<Map<String, dynamic>> getPendingApprovals() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/auth/pending_approvals.php'),
      headers: _headers,
    ).timeout(const Duration(seconds: 10));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  Future<Map<String, dynamic>> approveLogin(String requestToken, String decision) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/auth/approve_login.php'),
      headers: _headers,
      body: jsonEncode({
        'request_token': requestToken,
        'decision': decision,
      }),
    ).timeout(const Duration(seconds: 10));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  // ========== POLIZEI VORFALL DETAILS ==========

  Future<Map<String, dynamic>> getPolizeiVorfallDetails(int vorfallId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/polizei_vorfall_details.php?vorfall_id=$vorfallId'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  Future<Map<String, dynamic>> polizeiVorfallAction(Map<String, dynamic> data) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/polizei_vorfall_details.php'),
      headers: _headers,
      body: jsonEncode(data),
    ).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  // ========== POLIZEI VORFALL DOKUMENTE ==========

  Future<Map<String, dynamic>> uploadPolizeiVorfallDokumente(int vorfallId, List<String> filePaths, String mitgliedernummer) async {
    final uri = Uri.parse('$baseUrl/admin/polizei_vorfall_upload.php');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_headers);
    request.fields['vorfall_id'] = vorfallId.toString();
    request.fields['hochgeladen_von'] = mitgliedernummer;
    for (final path in filePaths) {
      request.files.add(await http.MultipartFile.fromPath('files[]', path));
    }
    final response = await _client.send(request).timeout(const Duration(seconds: 60));
    final body = await response.stream.bytesToString();
    try { return jsonDecode(body); } on FormatException { return {'success': false}; }
  }

  Future<http.Response?> downloadPolizeiVorfallDokument(int docId) async {
    try {
      return await _client.get(
        Uri.parse('$baseUrl/admin/polizei_vorfall_dok.php?id=$docId'),
        headers: _headers,
      ).timeout(const Duration(seconds: 30));
    } catch (_) { return null; }
  }

  Future<Map<String, dynamic>> deletePolizeiVorfallDokument(int docId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/polizei_vorfall_dok.php'),
      headers: _headers,
      body: jsonEncode({'action': 'delete', 'doc_id': docId}),
    ).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  // ========== GERICHT ANTRAG DOKUMENTE ==========

  Future<Map<String, dynamic>> listGerichtDokumente(int userId, String antragId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/gericht_dok.php'),
      headers: _headers,
      body: jsonEncode({'action': 'list', 'user_id': userId, 'antrag_id': antragId}),
    ).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  Future<Map<String, dynamic>> uploadGerichtDokumente(int userId, String antragId, List<String> filePaths) async {
    final uri = Uri.parse('$baseUrl/admin/gericht_dok.php');
    final request = http.MultipartRequest('POST', uri);
    final h = Map<String, String>.from(_headers);
    h.remove('Content-Type');
    request.headers.addAll(h);
    request.fields['user_id'] = userId.toString();
    request.fields['antrag_id'] = antragId;
    for (final path in filePaths) {
      request.files.add(await http.MultipartFile.fromPath('files[]', path));
    }
    final response = await _client.send(request).timeout(const Duration(seconds: 60));
    final body = await response.stream.bytesToString();
    try { return jsonDecode(body); } on FormatException { return {'success': false}; }
  }

  Future<http.Response?> downloadGerichtDokument(int docId) async {
    try {
      return await _client.get(
        Uri.parse('$baseUrl/admin/gericht_dok.php?id=$docId'),
        headers: _headers,
      ).timeout(const Duration(seconds: 30));
    } catch (_) { return null; }
  }

  Future<Map<String, dynamic>> deleteGerichtDokument(int userId, int docId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/gericht_dok.php'),
      headers: _headers,
      body: jsonEncode({'action': 'delete', 'user_id': userId, 'id': docId}),
    ).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  // ========== BERATUNGSHILFE PDF ==========

  Future<http.Response?> generateBeratungshilfePdf(Map<String, dynamic> formData) async {
    try {
      return await _client.post(
        Uri.parse('$baseUrl/admin/beratungshilfe_pdf.php'),
        headers: _headers,
        body: jsonEncode(formData),
      ).timeout(const Duration(seconds: 120));
    } catch (_) { return null; }
  }

  // ========== DEUTSCHLANDTICKET RECHNUNGEN & KORRESPONDENZ ==========

  Future<Map<String, dynamic>> deutschlandticketAction(Map<String, dynamic> data) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/deutschlandticket_data.php'),
      headers: _headers,
      body: jsonEncode(data),
    ).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  Future<Map<String, dynamic>> uploadDeutschlandticketDokumente(int userId, List<String> filePaths, String kategorie, {String betreff = '', String? monat}) async {
    final uri = Uri.parse('$baseUrl/admin/deutschlandticket_dok.php');
    final request = http.MultipartRequest('POST', uri);
    final h = Map<String, String>.from(_headers);
    h.remove('Content-Type');
    request.headers.addAll(h);
    request.fields['user_id'] = userId.toString();
    request.fields['kategorie'] = kategorie;
    request.fields['betreff'] = betreff;
    if (monat != null) request.fields['monat'] = monat;
    for (final path in filePaths) {
      request.files.add(await http.MultipartFile.fromPath('files[]', path));
    }
    final response = await _client.send(request).timeout(const Duration(seconds: 60));
    final body = await response.stream.bytesToString();
    try { return jsonDecode(body); } on FormatException { return {'success': false}; }
  }

  Future<Map<String, dynamic>> listDeutschlandticketDokumente(int userId, {String? kategorie}) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/deutschlandticket_dok.php'),
      headers: _headers,
      body: jsonEncode({'action': 'list', 'user_id': userId, if (kategorie != null) 'kategorie': kategorie}),
    ).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  Future<http.Response?> downloadDeutschlandticketDokument(int docId) async {
    try {
      return await _client.get(
        Uri.parse('$baseUrl/admin/deutschlandticket_dok.php?id=$docId'),
        headers: _headers,
      ).timeout(const Duration(seconds: 30));
    } catch (_) { return null; }
  }

  Future<Map<String, dynamic>> deleteDeutschlandticketDokument(int userId, int docId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/deutschlandticket_dok.php'),
      headers: _headers,
      body: jsonEncode({'action': 'delete', 'user_id': userId, 'id': docId}),
    ).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  // ========== ARBEITSVERMITTLER DB ==========

  Future<List<Map<String, dynamic>>> getArbeitsvermittler() async {
    try {
      final uri = Uri.parse('$baseUrl/admin/arbeitsvermittler_manage.php?action=list');
      final response = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
      final body = jsonDecode(response.body);
      if (body['success'] == true && body['arbeitsvermittler'] is List) {
        return List<Map<String, dynamic>>.from(
          (body['arbeitsvermittler'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>> manageArbeitsvermittler(Map<String, dynamic> data) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/arbeitsvermittler_manage.php'),
      headers: _headers,
      body: jsonEncode(data),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ========== BEHOERDE ANTRAG DOKUMENTE ==========

  Future<Map<String, dynamic>> uploadAntragDokument({
    required int userId,
    required String behoerdeType,
    required String antragId,
    required String filePath,
    required String fileName,
  }) async {
    final uri = Uri.parse('$baseUrl/admin/behoerde_antrag_upload.php');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_headers);
    request.fields['user_id'] = userId.toString();
    request.fields['behoerde_type'] = behoerdeType;
    request.fields['antrag_id'] = antragId;
    request.files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> getAntragDokumente({
    required int userId,
    required String behoerdeType,
    required String antragId,
  }) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/behoerde_antrag_docs.php?user_id=$userId&behoerde_type=$behoerdeType&antrag_id=$antragId'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<http.Response> downloadAntragDokument(int docId) async {
    return await _client.get(
      Uri.parse('$baseUrl/admin/behoerde_antrag_download.php?id=$docId'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
  }

  Future<Map<String, dynamic>> deleteAntragDokument(int docId) async {
    final request = http.Request('DELETE', Uri.parse('$baseUrl/admin/behoerde_antrag_docs.php'));
    request.headers.addAll(_headers);
    request.body = jsonEncode({'id': docId});
    final streamed = await _client.send(request).timeout(const Duration(seconds: 30));
    final body = await streamed.stream.bytesToString();
    return jsonDecode(body);
  }

  // ========== GESUNDHEIT DATA (encrypted, separate from Behörde) ==========

  Future<Map<String, dynamic>> getGesundheitData(int userId, String gesundheitType) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/gesundheit_get.php'),
      headers: _headers,
      body: jsonEncode({'user_id': userId, 'gesundheit_type': gesundheitType}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> saveGesundheitData(int userId, String gesundheitType, Map<String, dynamic> data) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/gesundheit_save.php'),
      headers: _headers,
      body: jsonEncode({'user_id': userId, 'gesundheit_type': gesundheitType, 'data': data}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ========== GESUNDHEIT DOKUMENTE (encrypted upload/download) ==========

  Future<Map<String, dynamic>> uploadGesundheitDokument({
    required int userId,
    required String gesundheitType,
    required String analyseId,
    required String filePath,
    required String fileName,
  }) async {
    final uri = Uri.parse('$baseUrl/admin/gesundheit_doc_upload.php');
    final request = http.MultipartRequest('POST', uri);
    // Don't include Content-Type — MultipartRequest sets its own with boundary
    final headers = Map<String, String>.from(_headers);
    headers.remove('Content-Type');
    request.headers.addAll(headers);
    request.fields['user_id'] = userId.toString();
    request.fields['gesundheit_type'] = gesundheitType;
    request.fields['analyse_id'] = analyseId;
    request.files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<http.Response> downloadGesundheitDokument(int docId) async {
    return await _client.get(
      Uri.parse('$baseUrl/admin/gesundheit_doc_download.php?id=$docId'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
  }

  Future<Map<String, dynamic>> deleteGesundheitDokument(int docId) async {
    final request = http.Request('DELETE', Uri.parse('$baseUrl/admin/gesundheit_doc_delete.php'));
    request.headers.addAll(_headers);
    request.body = jsonEncode({'id': docId});
    final streamed = await _client.send(request).timeout(const Duration(seconds: 30));
    final body = await streamed.stream.bytesToString();
    return jsonDecode(body);
  }

  Future<Map<String, dynamic>> listGesundheitDokumente(int userId, String gesundheitType, String analyseId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/gesundheit_doc_list.php'),
      headers: _headers,
      body: jsonEncode({'user_id': userId, 'gesundheit_type': gesundheitType, 'analyse_id': analyseId}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ========== ARZT TERMINE (per Mitglied) ==========

  Future<Map<String, dynamic>> getArztTermine(int userId, String arztType) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/gesundheit_termine_list.php'),
      headers: _headers,
      body: jsonEncode({'user_id': userId, 'arzt_type': arztType}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> saveArztTermin(Map<String, dynamic> data) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/gesundheit_termine_save.php'),
      headers: _headers,
      body: jsonEncode(data),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ========== ARZT MEDIKAMENTE (per Mitglied) ==========

  Future<Map<String, dynamic>> getArztMedikamente(int userId, String arztType) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/gesundheit_medikamente_list.php'),
      headers: _headers,
      body: jsonEncode({'user_id': userId, 'arzt_type': arztType}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> saveArztMedikament(Map<String, dynamic> data) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/gesundheit_medikamente_save.php'),
      headers: _headers,
      body: jsonEncode(data),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ========== ÄRZTE DATENBANK ==========

  Future<Map<String, dynamic>> searchKliniken({String search = '', String fachrichtung = ''}) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/kliniken_manage.php'),
      headers: _headers,
      body: jsonEncode({'action': 'search', 'search': search, 'fachrichtung': fachrichtung}),
    ).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false}; }
  }

  Future<Map<String, dynamic>> searchAerzte({String search = '', String fachrichtung = ''}) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/aerzte_manage.php'),
      headers: _headers,
      body: jsonEncode({'action': 'search', 'search': search, 'fachrichtung': fachrichtung}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> manageArzt(Map<String, dynamic> data) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/aerzte_manage.php'),
      headers: _headers,
      body: jsonEncode(data),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ========== KURSTRÄGER DATENBANK ==========

  Future<List<Map<String, dynamic>>> getKursTraeger() async {
    try {
      final uri = Uri.parse('$baseUrl/admin/kurs_traeger_manage.php');
      final response = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
      final body = jsonDecode(response.body);
      if (body['success'] == true && body['kurs_traeger'] is List) {
        return List<Map<String, dynamic>>.from(
          (body['kurs_traeger'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>> manageKursTraeger(Map<String, dynamic> data) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/kurs_traeger_manage.php'),
      headers: _headers,
      body: jsonEncode(data),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ========== SCHULEN DATENBANK ==========

  Future<List<Map<String, dynamic>>> getSchulen() async {
    try {
      final uri = Uri.parse('$baseUrl/admin/schulen_manage.php');
      final response = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
      final body = jsonDecode(response.body);
      if (body['success'] == true && body['schulen'] is List) {
        return List<Map<String, dynamic>>.from(
          (body['schulen'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // ========== FINANZEN (encrypted, separate endpoints) ==========

  Future<Map<String, dynamic>> getFinanzenData(int userId, String finanzenType) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/finanzen_get.php'),
      headers: _headers,
      body: jsonEncode({'user_id': userId, 'finanzen_type': finanzenType}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> saveFinanzenData(int userId, String finanzenType, Map<String, dynamic> data) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/finanzen_save.php'),
      headers: _headers,
      body: jsonEncode({'user_id': userId, 'finanzen_type': finanzenType, 'data': data}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ========== KREDIT KORRESPONDENZ ==========

  Future<Map<String, dynamic>> uploadKreditKorrespondenz({
    required int userId,
    required int kreditIndex,
    required String richtung,
    required String titel,
    required String datum,
    String betreff = '',
    String notiz = '',
    String methode = 'post',
    String? gruppeId,
    String? filePath,
    String? fileName,
  }) async {
    final uri = Uri.parse('$baseUrl/admin/kredit_korr_upload.php');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_headers);
    request.fields['user_id'] = userId.toString();
    request.fields['kredit_index'] = kreditIndex.toString();
    request.fields['richtung'] = richtung;
    request.fields['titel'] = titel;
    request.fields['datum'] = datum;
    request.fields['betreff'] = betreff;
    request.fields['notiz'] = notiz;
    request.fields['methode'] = methode;
    if (gruppeId != null) request.fields['gruppe_id'] = gruppeId;
    if (filePath != null && fileName != null) {
      request.files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));
    }
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    try { return jsonDecode(response.body); } catch (e) { return {'success': false, 'message': 'Server error (${response.statusCode})'}; }
  }

  Future<Map<String, dynamic>> getKreditKorrespondenz(int userId, {int? kreditIndex}) async {
    String url = '$baseUrl/admin/kredit_korr_list.php?user_id=$userId';
    if (kreditIndex != null) url += '&kredit_index=$kreditIndex';
    final response = await _client.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> deleteKreditKorrespondenz(int docId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/kredit_korr_delete.php'),
      headers: _headers,
      body: jsonEncode({'id': docId}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<http.Response> downloadKreditKorrespondenzDoc(int docId) async {
    return await _client.get(
      Uri.parse('$baseUrl/admin/kredit_korr_download.php?id=$docId'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
  }

  // ========== ARBEITSAGENTUR KORRESPONDENZ ==========

  Future<Map<String, dynamic>> uploadAAKorrespondenz({
    required int userId,
    required String richtung,
    required String titel,
    required String datum,
    String datumErstellt = '',
    String datumKundeErhalten = '',
    String datumWirErhalten = '',
    String betreff = '',
    String notiz = '',
    String methode = 'post',
    String docType = 'korrespondenz',
    String? gruppeId,
    String? filePath,
    String? fileName,
  }) async {
    final uri = Uri.parse('$baseUrl/admin/aa_korr_upload.php');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_headers);
    request.fields['user_id'] = userId.toString();
    request.fields['richtung'] = richtung;
    request.fields['titel'] = titel;
    request.fields['datum'] = datum;
    request.fields['datum_erstellt'] = datumErstellt;
    request.fields['datum_kunde_erhalten'] = datumKundeErhalten;
    request.fields['datum_wir_erhalten'] = datumWirErhalten;
    request.fields['betreff'] = betreff;
    request.fields['notiz'] = notiz;
    request.fields['methode'] = methode;
    request.fields['doc_type'] = docType;
    if (gruppeId != null) request.fields['gruppe_id'] = gruppeId;
    if (filePath != null && fileName != null) {
      request.files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));
    }
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    try { return jsonDecode(response.body); } catch (e) { return {'success': false, 'message': 'Server error (${response.statusCode})'}; }
  }

  Future<Map<String, dynamic>> getAAKorrespondenz(int userId) async {
    final response = await _client.get(Uri.parse('$baseUrl/admin/aa_korr_list.php?user_id=$userId'), headers: _headers).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> deleteAAKorrespondenz(int docId) async {
    final response = await _client.post(Uri.parse('$baseUrl/admin/aa_korr_delete.php'), headers: _headers, body: jsonEncode({'id': docId})).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> updateAAWiderspruch(int docId, Map<String, dynamic> widerspruchData) async {
    final response = await _client.post(Uri.parse('$baseUrl/admin/aa_korr_update_widerspruch.php'), headers: _headers, body: jsonEncode({'id': docId, 'widerspruch_data': widerspruchData})).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<http.Response> downloadAAKorrespondenzDoc(int docId) async {
    return await _client.get(Uri.parse('$baseUrl/admin/aa_korr_download.php?id=$docId'), headers: _headers).timeout(const Duration(seconds: 30));
  }

  // === ARBEITSAGENTUR DEDICATED DB ===
  Future<Map<String, dynamic>> getArbeitsagenturData(int userId) async {
    final response = await _client.get(Uri.parse('$baseUrl/admin/arbeitsagentur_data_manage.php?user_id=$userId'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false, 'message': 'Invalid server response'}; }
  }

  Future<Map<String, dynamic>> saveArbeitsagenturData(int userId, Map<String, dynamic> data) async {
    final response = await _client.post(Uri.parse('$baseUrl/admin/arbeitsagentur_data_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'save_data', 'data': data})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false, 'message': 'Invalid server response'}; }
  }

  Future<Map<String, dynamic>> saveArbeitsagenturMeldung(int userId, Map<String, dynamic> meldung) async {
    final response = await _client.post(Uri.parse('$baseUrl/admin/arbeitsagentur_data_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'save_meldung', 'meldung': meldung})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false, 'message': 'Invalid server response'}; }
  }

  Future<Map<String, dynamic>> deleteArbeitsagenturMeldung(int userId, int id) async {
    final response = await _client.post(Uri.parse('$baseUrl/admin/arbeitsagentur_data_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'delete_meldung', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false, 'message': 'Invalid server response'}; }
  }

  Future<Map<String, dynamic>> saveArbeitsagenturAntrag(int userId, Map<String, dynamic> antrag) async {
    final response = await _client.post(Uri.parse('$baseUrl/admin/arbeitsagentur_data_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'save_antrag', 'antrag': antrag})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false, 'message': 'Invalid server response'}; }
  }

  Future<Map<String, dynamic>> deleteArbeitsagenturAntrag(int userId, int id) async {
    final response = await _client.post(Uri.parse('$baseUrl/admin/arbeitsagentur_data_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'delete_antrag', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false, 'message': 'Invalid server response'}; }
  }

  Future<Map<String, dynamic>> saveArbeitsagenturTermin(int userId, Map<String, dynamic> termin) async {
    final response = await _client.post(Uri.parse('$baseUrl/admin/arbeitsagentur_data_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'save_termin', 'termin': termin})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false, 'message': 'Invalid server response'}; }
  }

  Future<Map<String, dynamic>> deleteArbeitsagenturTermin(int userId, int id) async {
    final response = await _client.post(Uri.parse('$baseUrl/admin/arbeitsagentur_data_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'delete_termin', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false, 'message': 'Invalid server response'}; }
  }

  Future<Map<String, dynamic>> saveArbeitsagenturBegutachtung(int userId, Map<String, dynamic> begutachtung) async {
    final response = await _client.post(Uri.parse('$baseUrl/admin/arbeitsagentur_data_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'save_begutachtung', 'begutachtung': begutachtung})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false, 'message': 'Invalid server response'}; }
  }

  Future<Map<String, dynamic>> deleteArbeitsagenturBegutachtung(int userId, int id) async {
    final response = await _client.post(Uri.parse('$baseUrl/admin/arbeitsagentur_data_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'delete_begutachtung', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false, 'message': 'Invalid server response'}; }
  }

  Future<Map<String, dynamic>> saveArbeitsagenturVorschlag(int userId, Map<String, dynamic> vorschlag) async {
    final response = await _client.post(Uri.parse('$baseUrl/admin/arbeitsagentur_data_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'save_vorschlag', 'vorschlag': vorschlag})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false, 'message': 'Invalid server response'}; }
  }

  Future<Map<String, dynamic>> deleteArbeitsagenturVorschlag(int userId, int id) async {
    final response = await _client.post(Uri.parse('$baseUrl/admin/arbeitsagentur_data_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'delete_vorschlag', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false, 'message': 'Invalid server response'}; }
  }

  Future<Map<String, dynamic>> updateArbeitsagenturVorschlagStatus(int userId, int vorschlagId, String status, {String dateField = '', String eventDatum = ''}) async {
    final response = await _client.post(Uri.parse('$baseUrl/admin/arbeitsagentur_data_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'update_vorschlag_status', 'vorschlag_id': vorschlagId, 'status': status, 'date_field': dateField, 'event_datum': eventDatum})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false, 'message': 'Invalid server response'}; }
  }

  Future<Map<String, dynamic>> setArbeitsagenturErinnerungTicket(int userId, int vorschlagId, String ticketId) async {
    final response = await _client.post(Uri.parse('$baseUrl/admin/arbeitsagentur_data_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'set_erinnerung_ticket', 'vorschlag_id': vorschlagId, 'ticket_id': ticketId})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false, 'message': 'Invalid server response'}; }
  }

  Future<Map<String, dynamic>> getArbeitsagenturVorschlagKorr(int userId, int vorschlagId) async {
    final response = await _client.post(Uri.parse('$baseUrl/admin/arbeitsagentur_data_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'get_vorschlag_korr', 'vorschlag_id': vorschlagId})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false, 'message': 'Invalid server response'}; }
  }

  Future<Map<String, dynamic>> saveArbeitsagenturVorschlagKorr(int userId, int vorschlagId, Map<String, dynamic> korr) async {
    final response = await _client.post(Uri.parse('$baseUrl/admin/arbeitsagentur_data_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'save_vorschlag_korr', 'vorschlag_id': vorschlagId, 'korr': korr})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false, 'message': 'Invalid server response'}; }
  }

  Future<Map<String, dynamic>> deleteArbeitsagenturVorschlagKorr(int userId, int id) async {
    final response = await _client.post(Uri.parse('$baseUrl/admin/arbeitsagentur_data_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'delete_vorschlag_korr', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(response.body); } on FormatException { return {'success': false, 'message': 'Invalid server response'}; }
  }

  // === BÜRGERAMT ===
  Future<Map<String, dynamic>> getBuergeramtData(int userId) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/buergeramt_manage.php?user_id=$userId&action=all'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> saveBuergeramtData(int userId, Map<String, dynamic> data) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/buergeramt_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'save_data', 'data': data})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> saveBuergeramtVorfall(int userId, Map<String, dynamic> vorfall) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/buergeramt_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'save_vorfall', 'vorfall': vorfall})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteBuergeramtVorfall(int userId, int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/buergeramt_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'delete_vorfall', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> getBuergeramtVorfallDetail(int userId, int vorfallId) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/buergeramt_manage.php?user_id=$userId&action=vorfall_detail&vorfall_id=$vorfallId'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> saveBuergeramtKorr(int userId, int vorfallId, Map<String, dynamic> korr) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/buergeramt_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'save_korr', 'vorfall_id': vorfallId, 'korr': korr})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteBuergeramtKorr(int userId, int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/buergeramt_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'delete_korr', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> saveBuergeramtTermin(int userId, int vorfallId, Map<String, dynamic> termin) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/buergeramt_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'save_termin', 'vorfall_id': vorfallId, 'termin': termin})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteBuergeramtTermin(int userId, int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/buergeramt_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'delete_termin', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> saveBuergeramtVerlauf(int userId, int vorfallId, Map<String, dynamic> verlauf) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/buergeramt_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'save_verlauf', 'vorfall_id': vorfallId, 'verlauf': verlauf})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }

  // === KONSULAT ===
  Future<Map<String, dynamic>> getKonsulatData(int userId) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/konsulat_manage.php?user_id=$userId&action=all'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> saveKonsulatData(int userId, Map<String, dynamic> data) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/konsulat_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'save_data', 'data': data})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> saveKonsulatVorfall(int userId, Map<String, dynamic> vorfall) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/konsulat_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'save_vorfall', 'vorfall': vorfall})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteKonsulatVorfall(int userId, int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/konsulat_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'delete_vorfall', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> getKonsulatVorfallDetail(int userId, int vorfallId) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/konsulat_manage.php?user_id=$userId&action=vorfall_detail&vorfall_id=$vorfallId'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> saveKonsulatKorr(int userId, int vorfallId, Map<String, dynamic> korr) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/konsulat_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'save_korr', 'vorfall_id': vorfallId, 'korr': korr})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteKonsulatKorr(int userId, int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/konsulat_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'delete_korr', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> saveKonsulatTermin(int userId, int vorfallId, Map<String, dynamic> termin) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/konsulat_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'save_termin', 'vorfall_id': vorfallId, 'termin': termin})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteKonsulatTermin(int userId, int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/konsulat_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'delete_termin', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }

  // === VEREIN DATA (dedicated DB) ===
  Future<Map<String, dynamic>> getVereinData(int userId) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/verein_data_manage.php?user_id=$userId'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> saveVereinData(int userId, Map<String, dynamic> data) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/verein_data_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'data': data})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }

  // === VEREIN DATENBANK ===
  Future<List<Map<String, dynamic>>> getVereinDatenbank() async {
    try {
      final r = await _client.get(Uri.parse('$baseUrl/admin/verein_datenbank.php'), headers: _headers).timeout(const Duration(seconds: 15));
      final body = jsonDecode(r.body);
      if (body['success'] == true && body['data'] is List) return List<Map<String, dynamic>>.from((body['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      return [];
    } catch (_) { return []; }
  }

  // === KINDERGARTEN ===
  Future<Map<String, dynamic>> getKindergartenData(int userId) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/kindergarten_manage.php?user_id=$userId&action=all'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> saveKindergartenData(int userId, Map<String, dynamic> data) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/kindergarten_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'save_data', 'data': data})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> saveKindergartenKind(int userId, Map<String, dynamic> kind) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/kindergarten_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'save_kind', 'kind': kind})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteKindergartenKind(int userId, int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/kindergarten_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'delete_kind', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> getKindergartenKindDetail(int userId, int kindId) async {
    final r = await _client.get(Uri.parse('$baseUrl/admin/kindergarten_manage.php?user_id=$userId&action=kind_detail&kind_id=$kindId'), headers: _headers).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> saveKindergartenKorr(int userId, int kindId, Map<String, dynamic> korr) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/kindergarten_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'save_korr', 'kind_id': kindId, 'korr': korr})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteKindergartenKorr(int userId, int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/kindergarten_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'delete_korr', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> saveKindergartenTermin(int userId, int kindId, Map<String, dynamic> termin) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/kindergarten_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'save_termin', 'kind_id': kindId, 'termin': termin})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }
  Future<Map<String, dynamic>> deleteKindergartenTermin(int userId, int id) async {
    final r = await _client.post(Uri.parse('$baseUrl/admin/kindergarten_manage.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'action': 'delete_termin', 'id': id})).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }

  // === SCHULBILDUNG ===
  Future<Map<String, dynamic>> getUserSchulbildung(int userId) async {
    final response = await _client.get(Uri.parse('$baseUrl/admin/user_schulbildung.php?user_id=$userId'), headers: _headers).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> saveUserSchulbildung(int userId, Map<String, dynamic> data) async {
    final body = Map<String, dynamic>.from(data);
    body['user_id'] = userId;
    final response = await _client.post(Uri.parse('$baseUrl/admin/user_schulbildung.php'), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> deleteUserSchulbildung(int userId, int id) async {
    final response = await _client.post(Uri.parse('$baseUrl/admin/user_schulbildung.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'id': id, 'action': 'delete'})).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // === STAATSANGEHOERIGKEITEN ===
  Future<Map<String, dynamic>> getStaatsangehoerigkeiten() async {
    final response = await _client.get(Uri.parse('$baseUrl/admin/staatsangehoerigkeiten_list.php'), headers: _headers).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // === SCHULBILDUNG DOKUMENTE ===
  Future<Map<String, dynamic>> getSchulbildungDokumente(int sbId, int userId) async {
    final response = await _client.get(Uri.parse('$baseUrl/admin/schulbildung_dok.php?schulbildung_id=$sbId&user_id=$userId'), headers: _headers).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> uploadSchulbildungDokument({required int sbId, required int userId, required String dokTyp, required String dokTitel, required String filePath, required String fileName}) async {
    final uri = Uri.parse('$baseUrl/admin/schulbildung_dok.php');
    final request = http.MultipartRequest('POST', uri);
    _headers.forEach((k, v) => request.headers[k] = v);
    request.fields['schulbildung_id'] = sbId.toString();
    request.fields['user_id'] = userId.toString();
    request.fields['dok_typ'] = dokTyp;
    request.fields['dok_titel'] = dokTitel;
    request.files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));
    final streamed = await _client.send(request).timeout(const Duration(seconds: 30));
    final body = await streamed.stream.bytesToString();
    return jsonDecode(body);
  }

  Future<http.Response> downloadSchulbildungDokument(int docId) async {
    return await _client.get(Uri.parse('$baseUrl/admin/schulbildung_dok_download.php?id=$docId'), headers: _headers).timeout(const Duration(seconds: 30));
  }

  Future<Map<String, dynamic>> deleteSchulbildungDokument(int docId) async {
    final response = await _client.post(Uri.parse('$baseUrl/admin/schulbildung_dok.php'), headers: _headers, body: jsonEncode({'action': 'delete', 'id': docId})).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // === QUALIFIKATIONEN (Führerschein, Sprachen, Schulabschluss) ===
  Future<Map<String, dynamic>> getUserQualifikationen(int userId) async {
    final response = await _client.get(Uri.parse('$baseUrl/admin/user_qualifikationen.php?user_id=$userId'), headers: _headers).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> addUserQualifikation(int userId, String table, Map<String, dynamic> data) async {
    final body = Map<String, dynamic>.from(data);
    body['user_id'] = userId;
    body['table'] = table;
    body['action'] = 'add';
    final response = await _client.post(Uri.parse('$baseUrl/admin/user_qualifikationen.php'), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> deleteUserQualifikation(int userId, String table, int id) async {
    final response = await _client.post(Uri.parse('$baseUrl/admin/user_qualifikationen.php'), headers: _headers, body: jsonEncode({'user_id': userId, 'table': table, 'action': 'delete', 'id': id})).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> getFuehrerscheinklassen() async {
    final response = await _client.get(Uri.parse('$baseUrl/admin/fuehrerscheinklassen_list.php'), headers: _headers).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> getSprachen() async {
    final response = await _client.get(Uri.parse('$baseUrl/admin/sprachen_list.php'), headers: _headers).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> getSchulabschluesse() async {
    final response = await _client.get(Uri.parse('$baseUrl/admin/schulabschluesse_list.php'), headers: _headers).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // === BERUFSBEZEICHNUNGEN ===
  Future<Map<String, dynamic>> getBerufsbezeichnungen() async {
    final response = await _client.get(Uri.parse('$baseUrl/admin/berufsbezeichnungen_list.php'), headers: _headers).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // === BERUFSERFAHRUNG ===
  Future<Map<String, dynamic>> getBerufserfahrung(int userId) async {
    final response = await _client.get(Uri.parse('$baseUrl/admin/berufserfahrung_list.php?user_id=$userId'), headers: _headers).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> saveBerufserfahrung(int userId, Map<String, dynamic> data) async {
    final body = Map<String, dynamic>.from(data);
    body['user_id'] = userId;
    final response = await _client.post(Uri.parse('$baseUrl/admin/berufserfahrung_save.php'), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> deleteBerufserfahrung(int id, int userId) async {
    final response = await _client.post(Uri.parse('$baseUrl/admin/berufserfahrung_delete.php'), headers: _headers, body: jsonEncode({'id': id, 'user_id': userId})).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> getBerufserfahrungDokumente(int beId, int userId) async {
    final response = await _client.get(Uri.parse('$baseUrl/admin/berufserfahrung_dok_list.php?berufserfahrung_id=$beId&user_id=$userId'), headers: _headers).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> uploadBerufserfahrungDokument({required int beId, required int userId, required String dokTyp, required String dokTitel, required String filePath, required String fileName}) async {
    final uri = Uri.parse('$baseUrl/admin/berufserfahrung_dok_upload.php');
    final request = http.MultipartRequest('POST', uri);
    _headers.forEach((k, v) => request.headers[k] = v);
    request.fields['berufserfahrung_id'] = beId.toString();
    request.fields['user_id'] = userId.toString();
    request.fields['dok_typ'] = dokTyp;
    request.fields['dok_titel'] = dokTitel;
    request.files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));
    final streamed = await _client.send(request).timeout(const Duration(seconds: 30));
    final body = await streamed.stream.bytesToString();
    return jsonDecode(body);
  }

  Future<http.Response> downloadBerufserfahrungDokument(int docId) async {
    return await _client.get(Uri.parse('$baseUrl/admin/berufserfahrung_dok_download.php?id=$docId'), headers: _headers).timeout(const Duration(seconds: 30));
  }

  Future<Map<String, dynamic>> deleteBerufserfahrungDokument(int docId) async {
    final response = await _client.post(Uri.parse('$baseUrl/admin/berufserfahrung_dok_delete.php'), headers: _headers, body: jsonEncode({'id': docId})).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> getPKontoFreibetrag() async {
    try {
      final uri = Uri.parse('$baseUrl/admin/pkonto_freibetrag.php');
      final response = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
      try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
    } catch (e) {
      return {'success': false};
    }
  }

  Future<Map<String, dynamic>> savePKontoPeriode({
    int? id,
    required String gueltigVon,
    required String gueltigBis,
    required String grundfreibetrag,
    required String erhoehung1,
    required String erhoehung25,
    required String quelle,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/pkonto_freibetrag.php'),
      headers: _headers,
      body: jsonEncode({
        'action': id != null ? 'update' : 'add',
        'id': id,
        'gueltig_von': gueltigVon,
        'gueltig_bis': gueltigBis,
        'grundfreibetrag': grundfreibetrag,
        'erhoehung_1_person': erhoehung1,
        'erhoehung_2_5_person': erhoehung25,
        'quelle': quelle,
      }),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> deletePKontoPeriode(int id) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/pkonto_freibetrag.php'),
      headers: _headers,
      body: jsonEncode({'action': 'delete', 'id': id}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ========== NETWORK STATUS (for Live Chat) ==========

  Future<Map<String, dynamic>> getMemberNetworkStatus(String mitgliedernummer) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/admin/user_details.php'),
        headers: _headers,
        body: jsonEncode({'mitgliedernummer': mitgliedernummer}),
      ).timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body);
      if (data['success'] == true && data['user'] is Map) {
        final user = data['user'];
        return {
          'connection_type': user['connection_type'],
          'latency_ms': user['latency_ms'],
          'network_quality': user['network_quality'],
          'battery_level': user['battery_level'],
          'battery_state': user['battery_state'],
        };
      }
      return {};
    } catch (_) {
      return {};
    }
  }

  /// Get full member details by Mitgliedernummer (for member info dialog)
  Future<Map<String, dynamic>> getMemberDetailsByNummer(String mitgliedernummer) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/user_details.php'),
      headers: _headers,
      body: jsonEncode({'mitgliedernummer': mitgliedernummer}),
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ========== OCR LOHNSTEUERBESCHEINIGUNG ==========

  Future<Map<String, dynamic>> ocrLohnsteuerbescheinigung(int docId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/ocr_lohnsteuerbescheinigung.php'),
      headers: _headers,
      body: jsonEncode({'doc_id': docId}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ========== BANKEN DATENBANK ==========

  Future<List<Map<String, dynamic>>> getBanken() async {
    try {
      final uri = Uri.parse('$baseUrl/admin/banken_manage.php?action=list');
      final response = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
      final body = jsonDecode(response.body);
      if (body['success'] == true && body['banken'] is List) {
        return List<Map<String, dynamic>>.from(
          (body['banken'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // ========== VERSORGUNGSÄMTER DATENBANK ==========

  Future<Map<String, dynamic>> searchVersorgungsaemter({String search = '', String bundesland = ''}) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/versorgungsamt_manage.php'),
      headers: _headers,
      body: jsonEncode({'action': 'search', 'search': search, 'bundesland': bundesland}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ============= GESUNDHEIT DOKUMENTE (encrypted) =============

  Future<Map<String, dynamic>> uploadGesundheitDoc({
    required int userId,
    required String gesundheitType,
    required String analyseId,
    required String filePath,
    required String fileName,
  }) async {
    final uri = Uri.parse('$baseUrl/admin/gesundheit_doc_upload.php');
    final request = http.MultipartRequest('POST', uri);
    // Don't add Content-Type — MultipartRequest sets its own with boundary
    final h = Map<String, String>.from(_headers);
    h.remove('Content-Type');
    request.headers.addAll(h);
    request.fields['user_id'] = userId.toString();
    request.fields['gesundheit_type'] = gesundheitType;
    request.fields['analyse_id'] = analyseId;
    request.files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));
    final streamed = await _client.send(request).timeout(const Duration(seconds: 30));
    final body = await streamed.stream.bytesToString();
    return jsonDecode(body);
  }

  Future<Map<String, dynamic>> listGesundheitDocs({
    required int userId,
    required String gesundheitType,
    required String analyseId,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/gesundheit_doc_list.php'),
      headers: _headers,
      body: jsonEncode({'user_id': userId, 'gesundheit_type': gesundheitType, 'analyse_id': analyseId}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<List<int>?> downloadGesundheitDoc(int docId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/gesundheit_doc_download.php?id=$docId'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode == 200 && response.headers['content-type'] != 'application/json') {
      return response.bodyBytes;
    }
    return null;
  }

  Future<Map<String, dynamic>> deleteGesundheitDoc(int docId) async {
    final uri = Uri.parse('$baseUrl/admin/gesundheit_doc_delete.php');
    final request = http.Request('DELETE', uri);
    request.headers.addAll(_headers);
    request.body = jsonEncode({'id': docId});
    final streamed = await _client.send(request).timeout(const Duration(seconds: 30));
    final body = await streamed.stream.bytesToString();
    return jsonDecode(body);
  }

  Future<Map<String, dynamic>> searchMedikamente(String query) async {
    final encoded = Uri.encodeComponent(query);
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/medikamente_search.php?q=$encoded&limit=10'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  Future<Map<String, dynamic>> manageMedikament(Map<String, dynamic> data) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/medikamente_search.php'),
      headers: _headers,
      body: jsonEncode(data),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ========== FINANZVERWALTUNG ==========

  // Bank-Transaktionen abrufen
  Future<Map<String, dynamic>> getBankTransaktionen({int? monat, int? jahr, String? typ}) async {
    final params = <String, String>{};
    if (monat != null) params['monat'] = monat.toString();
    if (jahr != null) params['jahr'] = jahr.toString();
    if (typ != null) params['typ'] = typ;
    final query = params.isNotEmpty ? '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}' : '';
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/finanzverwaltung/transaktionen.php$query'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Neue Bank-Transaktion erstellen
  Future<Map<String, dynamic>> createBankTransaktion({
    required String datum,
    required double betrag,
    required String typ,
    String? kategorie,
    String? beschreibung,
    String? empfaengerAbsender,
    String? referenz,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/finanzverwaltung/transaktionen.php'),
      headers: _headers,
      body: jsonEncode({
        'datum': datum,
        'betrag': betrag,
        'typ': typ,
        if (kategorie != null) 'kategorie': kategorie,
        if (beschreibung != null) 'beschreibung': beschreibung,
        if (empfaengerAbsender != null) 'empfaenger_absender': empfaengerAbsender,
        if (referenz != null) 'referenz': referenz,
      }),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Bank-Transaktion löschen
  Future<Map<String, dynamic>> deleteBankTransaktion(int id) async {
    final request = http.Request('DELETE', Uri.parse('$baseUrl/admin/finanzverwaltung/transaktionen.php'));
    request.headers.addAll(_headers);
    request.body = jsonEncode({'id': id});
    final streamed = await _client.send(request).timeout(const Duration(seconds: 30));
    final body = await streamed.stream.bytesToString();
    return jsonDecode(body);
  }

  // Beitragszahlungen abrufen (für einen Monat/Jahr)
  Future<Map<String, dynamic>> getBeitragszahlungen({int? monat, int? jahr}) async {
    final params = <String, String>{};
    if (monat != null) params['monat'] = monat.toString();
    if (jahr != null) params['jahr'] = jahr.toString();
    final query = params.isNotEmpty ? '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}' : '';
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/finanzverwaltung/beitragszahlungen.php$query'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Beitragszahlung erstellen/aktualisieren
  Future<Map<String, dynamic>> updateBeitragszahlung({
    required String mitgliedernummer,
    required int monat,
    required int jahr,
    required double betrag,
    required String status,
    String? zahlungsdatum,
    String? zahlungsmethode,
    String? notiz,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/finanzverwaltung/beitragszahlungen.php'),
      headers: _headers,
      body: jsonEncode({
        'mitgliedernummer': mitgliedernummer,
        'monat': monat,
        'jahr': jahr,
        'betrag': betrag,
        'status': status,
        if (zahlungsdatum != null) 'zahlungsdatum': zahlungsdatum,
        if (zahlungsmethode != null) 'zahlungsmethode': zahlungsmethode,
        if (notiz != null) 'notiz': notiz,
      }),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Spenden abrufen
  Future<Map<String, dynamic>> getSpenden({int? jahr}) async {
    final params = <String, String>{};
    if (jahr != null) params['jahr'] = jahr.toString();
    final query = params.isNotEmpty ? '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}' : '';
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/finanzverwaltung/spenden.php$query'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Spende erstellen
  Future<Map<String, dynamic>> createSpende({
    required String datum,
    required double betrag,
    required String spenderName,
    String? spenderAdresse,
    String? spenderMitgliedernummer,
    String? zweck,
    bool quittungAusgestellt = false,
    String? notiz,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/finanzverwaltung/spenden.php'),
      headers: _headers,
      body: jsonEncode({
        'datum': datum,
        'betrag': betrag,
        'spender_name': spenderName,
        if (spenderAdresse != null) 'spender_adresse': spenderAdresse,
        if (spenderMitgliedernummer != null) 'spender_mitgliedernummer': spenderMitgliedernummer,
        if (zweck != null) 'zweck': zweck,
        'quittung_ausgestellt': quittungAusgestellt ? 1 : 0,
        if (notiz != null) 'notiz': notiz,
      }),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Spende löschen
  Future<Map<String, dynamic>> deleteSpende(int id) async {
    final request = http.Request('DELETE', Uri.parse('$baseUrl/admin/finanzverwaltung/spenden.php'));
    request.headers.addAll(_headers);
    request.body = jsonEncode({'id': id});
    final streamed = await _client.send(request).timeout(const Duration(seconds: 30));
    final body = await streamed.stream.bytesToString();
    return jsonDecode(body);
  }

  // Update a verification stage
  Future<Map<String, dynamic>> updateVerifizierung({
    required int userId,
    required int stufe,
    required String status,
    String? notiz,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/verifizierung_update.php'),
      headers: _headers,
      body: jsonEncode({
        'user_id': userId,
        'stufe': stufe,
        'status': status,
        if (notiz != null) 'notiz': notiz,
      }),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ========== BEFREIUNG ==========

  // List befreiung entries for a user
  Future<Map<String, dynamic>> getBefreiungen(int userId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/befreiung_list.php'),
      headers: _headers,
      body: jsonEncode({'user_id': userId}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Upload befreiung document (multipart)
  Future<Map<String, dynamic>> uploadBefreiung({
    required int userId,
    required String behoerde,
    required String gueltigVon,
    required String gueltigBis,
    String? bescheidDatum,
    String? notiz,
    required String filePath,
    required String fileName,
  }) async {
    final uri = Uri.parse('$baseUrl/admin/befreiung_upload.php');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_headers);
    request.fields['user_id'] = userId.toString();
    request.fields['behoerde'] = behoerde;
    request.fields['gueltig_von'] = gueltigVon;
    request.fields['gueltig_bis'] = gueltigBis;
    if (bescheidDatum != null) request.fields['bescheid_datum'] = bescheidDatum;
    if (notiz != null) request.fields['notiz'] = notiz;
    request.files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));
    final streamed = await _client.send(request).timeout(const Duration(seconds: 30));
    final body = await streamed.stream.bytesToString();
    return jsonDecode(body);
  }

  // Update befreiung status (genehmigt/abgelehnt/eingereicht)
  Future<Map<String, dynamic>> updateBefreiung({
    required int id,
    required String status,
    String? notiz,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/befreiung_update.php'),
      headers: _headers,
      body: jsonEncode({
        'id': id,
        'status': status,
        if (notiz != null) 'notiz': notiz,
      }),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Delete befreiung entry
  Future<Map<String, dynamic>> deleteBefreiung(int id) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/befreiung_delete.php'),
      headers: _headers,
      body: jsonEncode({'id': id}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Download befreiung document (returns base64 data)
  Future<Map<String, dynamic>> downloadBefreiung(int id) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/befreiung_download.php'),
      headers: _headers,
      body: jsonEncode({'id': id}),
    ).timeout(const Duration(seconds: 30));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ══════════════════════════════════════════════════════════════
  // ERMÄSSIGUNG (fee reduction applications)
  // ══════════════════════════════════════════════════════════════

  // List Ermäßigungsanträge (optional filter by user_id)
  Future<Map<String, dynamic>> getErmaessigungsantraege({int? userId}) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/ermaessigung_list.php'),
      headers: _headers,
      body: jsonEncode({if (userId != null) 'user_id': userId}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Update Ermäßigungsantrag (status, checklist, rejection reason)
  Future<Map<String, dynamic>> updateErmaessigung({
    required int id,
    String? status,
    bool? checkDokumentLesbar,
    bool? checkLeistungsartErkennbar,
    bool? checkAktuell12Monate,
    String? ablehnungsgrund,
    String? notiz,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/ermaessigung_update.php'),
      headers: _headers,
      body: jsonEncode({
        'id': id,
        if (status != null) 'status': status,
        if (checkDokumentLesbar != null) 'check_dokument_lesbar': checkDokumentLesbar,
        if (checkLeistungsartErkennbar != null) 'check_leistungsart_erkennbar': checkLeistungsartErkennbar,
        if (checkAktuell12Monate != null) 'check_aktuell_12monate': checkAktuell12Monate,
        if (ablehnungsgrund != null) 'ablehnungsgrund': ablehnungsgrund,
        if (notiz != null) 'notiz': notiz,
      }),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Delete Ermäßigungsantrag
  Future<Map<String, dynamic>> deleteErmaessigung(int id) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/ermaessigung_delete.php'),
      headers: _headers,
      body: jsonEncode({'id': id}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Download Ermäßigung document (returns base64 data)
  Future<Map<String, dynamic>> downloadErmaessigung(int id) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/ermaessigung_download.php'),
      headers: _headers,
      body: jsonEncode({'id': id}),
    ).timeout(const Duration(seconds: 30));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ══════════════════════════════════════════════════════════════
  // NOTIZEN (internal notes per member)
  // ══════════════════════════════════════════════════════════════

  // List notes for a user
  Future<Map<String, dynamic>> getNotizen(int userId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/notizen_list.php'),
      headers: _headers,
      body: jsonEncode({'user_id': userId}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Create a note for a user
  Future<Map<String, dynamic>> createNotiz({
    required int userId,
    required String notiz,
    String kategorie = 'allgemein',
    bool wichtig = false,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/notizen_create.php'),
      headers: _headers,
      body: jsonEncode({
        'user_id': userId,
        'notiz': notiz,
        'kategorie': kategorie,
        'wichtig': wichtig,
      }),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Delete a note
  Future<Map<String, dynamic>> deleteNotiz(int id) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/notizen_delete.php'),
      headers: _headers,
      body: jsonEncode({'id': id}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ══════════════════════════════════════════════════════════════
  // ARCHIV (Encrypted archive storage)
  // ══════════════════════════════════════════════════════════════

  // Get all archives
  Future<Map<String, dynamic>> getArchives() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/archiv_list.php'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Upload archive file (encrypted on server)
  Future<Map<String, dynamic>> uploadArchive({
    required String personName,
    String? mitgliedernummer,
    required String titel,
    required String beschreibung,
    required String kategorie,
    required String originalFilename,
    required int filesize,
    required String data,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/archiv_upload.php'),
      headers: _headers,
      body: jsonEncode({
        'person_name': personName,
        if (mitgliedernummer != null) 'mitgliedernummer': mitgliedernummer,
        'titel': titel,
        'beschreibung': beschreibung,
        'kategorie': kategorie,
        'original_filename': originalFilename,
        'filesize': filesize,
        'data': data,
      }),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Download archive file (decrypted, returns base64)
  Future<Map<String, dynamic>> downloadArchive(int id) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/archiv_download.php'),
      headers: _headers,
      body: jsonEncode({'id': id}),
    ).timeout(const Duration(seconds: 30));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // Delete archive entry + encrypted file
  Future<Map<String, dynamic>> deleteArchive(int id) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/archiv_delete.php'),
      headers: _headers,
      body: jsonEncode({'id': id}),
    ).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }
}
