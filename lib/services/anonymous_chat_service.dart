import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'device_key_service.dart';
import 'http_client_factory.dart';
import 'logger_service.dart';
import '../utils/anonymous_chat_helper.dart';

final _log = LoggerService();

/// Fetches per-visitor metadata (language, platform, app version,
/// first_open_at, last_active) for an anonymous chat user.
///
/// The Vorsitzer chat header calls [fetchMetadata] right after the
/// operator opens an anonymous conversation, then re-injects the result
/// into the conversation map under `anonymous_metadata` so the orange
/// info panel renders real values instead of dashes.
class AnonymousChatService {
  static const String baseUrl = 'https://icd360sev.icd360s.de/api';

  late http.Client _client;
  final DeviceKeyService _deviceKeyService = DeviceKeyService();

  static final AnonymousChatService _instance = AnonymousChatService._internal();
  factory AnonymousChatService() => _instance;
  AnonymousChatService._internal() {
    _client = IOClient(HttpClientFactory.createPinnedHttpClient());
  }

  Map<String, String> get _headers {
    final deviceKey = _deviceKeyService.deviceKey;
    return {
      'Content-Type': 'application/json',
      'User-Agent': 'ICD360S-Vorsitzer/1.0',
      if (deviceKey != null) 'X-Device-Key': deviceKey,
    };
  }

  Future<AnonymousMetadata?> fetchMetadata({
    required String callerMitgliedernummer,
    required int userId,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/vorstand/anonymous_chat_users.php'),
        headers: _headers,
        body: jsonEncode({
          'mitgliedernummer': callerMitgliedernummer,
          'user_id': userId,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      if (data is! Map || data['success'] != true) return null;

      return AnonymousMetadata.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      _log.error('AnonymousChatService.fetchMetadata failed: $e', tag: 'ANONCHAT');
      return null;
    }
  }
}
