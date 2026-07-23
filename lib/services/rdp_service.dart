import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'device_key_service.dart';

// ─── Remote Desktop (RDP via Guacamole gateway) ─────────────────────────────
//
// The app is only the CLIENT. Guacamole (guacamole-lite + guacd) runs on a
// SEPARATE server that this app talks to. The gateway base URL is configurable
// here (it is NOT this project's API server).
//
// Connection flow (the gateway on the other server must implement this):
//   POST {gateway}/token
//     headers: X-Device-Key, User-Agent: ICD360S-Vorsitzer/1.0
//     body:    {"protocol":"rdp","hostname":..,"port":..,"username":..,"password":..}
//     200  ->  {"url":"https://.../?token=<enc>"}   (preferred)
//        or     {"token":"<enc>"}                   (app builds {gateway}/?token=)
//
// The gateway should reject requests that lack a valid X-Device-Key / are not
// from the app (block browsers), and issue short-lived, single-use tokens, so
// only THIS app can obtain a session.

class RdpProfile {
  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String password;

  RdpProfile({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'password': password,
      };

  factory RdpProfile.fromJson(Map<String, dynamic> j) => RdpProfile(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        host: (j['host'] ?? '') as String,
        port: (j['port'] as num?)?.toInt() ?? 3389,
        username: (j['username'] ?? '') as String,
        password: (j['password'] ?? '') as String,
      );

  RdpProfile copyWith({
    String? name,
    String? host,
    int? port,
    String? username,
    String? password,
  }) =>
      RdpProfile(
        id: id,
        name: name ?? this.name,
        host: host ?? this.host,
        port: port ?? this.port,
        username: username ?? this.username,
        password: password ?? this.password,
      );
}

class RdpService {
  static const _kGateway = 'rdp_gateway_url';
  static const _kGatewayKey = 'rdp_gateway_key';
  static const _kProfiles = 'rdp_profiles';

  /// Default Guacamole gateway (public host — not a secret).
  static const String defaultGateway = 'https://rdp.icd360s.de';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final DeviceKeyService _deviceKeyService = DeviceKeyService();

  /// Stored gateway URL, or the default if none set.
  Future<String> getGateway() async {
    final v = await _storage.read(key: _kGateway);
    return (v == null || v.trim().isEmpty) ? defaultGateway : v;
  }

  Future<void> setGateway(String url) async =>
      _storage.write(key: _kGateway, value: url.trim());

  /// Shared gateway secret (X-Gateway-Key) so the gateway accepts only our app.
  Future<String?> getGatewayKey() async => _storage.read(key: _kGatewayKey);
  Future<void> setGatewayKey(String key) async =>
      _storage.write(key: _kGatewayKey, value: key.trim());

  Future<List<RdpProfile>> loadProfiles() async {
    final raw = await _storage.read(key: _kProfiles);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => RdpProfile.fromJson((e as Map).cast<String, dynamic>())).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveProfiles(List<RdpProfile> profiles) async {
    await _storage.write(
        key: _kProfiles, value: jsonEncode(profiles.map((e) => e.toJson()).toList()));
  }

  /// Ask the gateway for a session URL for [p]. Returns the URL to open in the
  /// fullscreen WebView. Throws a human-readable message on failure.
  Future<String> requestSessionUrl(String gateway, RdpProfile p) async {
    final base = gateway.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) throw 'Kein Gateway konfiguriert';
    if (!base.startsWith('https://')) {
      throw 'Gateway muss über HTTPS erreichbar sein';
    }
    final deviceKey = _deviceKeyService.deviceKey;
    final gatewayKey = await getGatewayKey();
    try {
      final res = await http
          .post(
            Uri.parse('$base/token'),
            headers: {
              'Content-Type': 'application/json',
              'User-Agent': 'ICD360S-Vorsitzer/1.0',
              if (deviceKey != null) 'X-Device-Key': deviceKey,
              if (gatewayKey != null && gatewayKey.isNotEmpty)
                'X-Gateway-Key': gatewayKey,
            },
            body: jsonEncode({
              'protocol': 'rdp',
              'hostname': p.host,
              'port': p.port,
              'username': p.username,
              'password': p.password,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        throw 'Gateway-Fehler (HTTP ${res.statusCode})';
      }
      final data = (jsonDecode(res.body) as Map).cast<String, dynamic>();
      if (data['url'] is String && (data['url'] as String).isNotEmpty) {
        return data['url'] as String;
      }
      if (data['token'] is String && (data['token'] as String).isNotEmpty) {
        return '$base/?token=${Uri.encodeComponent(data['token'] as String)}';
      }
      throw 'Ungültige Gateway-Antwort';
    } on FormatException {
      throw 'Ungültige Gateway-Antwort';
    }
  }
}
