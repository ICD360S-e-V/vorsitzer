import 'api_service.dart';

// ─── Remote Desktop (RDP) ────────────────────────────────────────────────────
//
// Connection profiles live SERVER-SIDE only: each admin's RDP connections are
// stored AES-256-GCM encrypted in MariaDB (icd360sev). The password NEVER
// reaches the device — the connect is performed server-side (session endpoint),
// which decrypts the profile + gateway key and returns a ready Guacamole URL.
//
// This service is a thin wrapper over ApiService. No local storage, no baked
// gateway secret: the gateway URL + key also live encrypted in the DB.

class RdpProfile {
  final int id; // server id (0 = new/unsaved)
  final String name;
  final String host;
  final int port;
  final String username;
  // NB: no password field — it is server-only and never sent to the client.

  RdpProfile({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
  });

  factory RdpProfile.fromJson(Map<String, dynamic> j) => RdpProfile(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: (j['name'] ?? '') as String,
        host: (j['host'] ?? '') as String,
        port: (j['port'] as num?)?.toInt() ?? RdpService.defaultRdpPort,
        username: (j['username'] ?? '') as String,
      );
}

class RdpService {
  /// Default RDP port (the xrdp target listens on a non-standard, localhost-only
  /// port on the gateway; still the sensible default for new connections).
  static const int defaultRdpPort = 31456;

  final ApiService _api = ApiService();

  /// List the acting admin's saved connections (no passwords).
  Future<List<RdpProfile>> loadProfiles(String mitgliedernummer) async {
    final r = await _api.rdpListProfiles(mitgliedernummer);
    if (r['success'] != true) return [];
    final list = (r['profiles'] as List?) ?? const [];
    return list
        .map((e) => RdpProfile.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Create ([id] null/0) or update a connection. Pass [password] only when
  /// setting/changing it; omit on edit to keep the stored one. Returns null on
  /// success, else an error message.
  Future<String?> saveProfile(
    String mitgliedernummer, {
    int? id,
    required String name,
    required String host,
    required int port,
    required String username,
    String? password,
  }) async {
    final r = await _api.rdpSaveProfile(
      mitgliedernummer,
      id: id,
      name: name,
      host: host,
      port: port,
      username: username,
      password: password,
    );
    return r['success'] == true ? null : (r['message']?.toString() ?? 'Speichern fehlgeschlagen');
  }

  /// Delete a connection. Returns null on success, else an error message.
  Future<String?> deleteProfile(String mitgliedernummer, int id) async {
    final r = await _api.rdpDeleteProfile(mitgliedernummer, id);
    return r['success'] == true ? null : (r['message']?.toString() ?? 'Löschen fehlgeschlagen');
  }

  /// Ask the server to open a session for profile [id]. Returns the Guacamole
  /// URL to load in the WebView. Throws a human-readable message on failure.
  Future<String> requestSessionUrl(String mitgliedernummer, int id) async {
    final r = await _api.rdpSession(mitgliedernummer, id);
    if (r['success'] == true && r['url'] is String && (r['url'] as String).isNotEmpty) {
      return r['url'] as String;
    }
    throw (r['message']?.toString() ?? 'Verbindung fehlgeschlagen');
  }
}
