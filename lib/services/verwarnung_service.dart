import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'device_key_service.dart';
import 'http_client_factory.dart';

/// Verwarnung (Warning) model
class Verwarnung {
  final int id;
  final int userId;
  final String userName;
  final String mitgliedernummer;
  final String typ;
  final String grund;
  final String? beschreibung;
  final DateTime datum;
  final String createdByName;
  final DateTime createdAt;

  Verwarnung({
    required this.id,
    required this.userId,
    required this.userName,
    required this.mitgliedernummer,
    required this.typ,
    required this.grund,
    this.beschreibung,
    required this.datum,
    required this.createdByName,
    required this.createdAt,
  });

  factory Verwarnung.fromJson(Map<String, dynamic> json) {
    return Verwarnung(
      id: json['id'],
      userId: json['user_id'],
      userName: json['user_name'] ?? '',
      mitgliedernummer: json['mitgliedernummer'] ?? '',
      typ: json['typ'],
      grund: json['grund'],
      beschreibung: json['beschreibung'],
      datum: DateTime.parse(json['datum']),
      createdByName: json['created_by_name'] ?? '',
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  String get typDisplay {
    switch (typ) {
      case 'ermahnung':
        return 'Ermahnung';
      case 'abmahnung':
        return 'Abmahnung';
      case 'letzte_abmahnung':
        return 'Letzte Abmahnung';
      default:
        return typ;
    }
  }
}

/// Warning statistics
class VerwarnungStats {
  final int total;
  final int ermahnung;
  final int abmahnung;
  final int letzteAbmahnung;

  VerwarnungStats({
    required this.total,
    required this.ermahnung,
    required this.abmahnung,
    required this.letzteAbmahnung,
  });

  factory VerwarnungStats.fromJson(Map<String, dynamic> json) {
    return VerwarnungStats(
      total: json['total'] ?? 0,
      ermahnung: json['ermahnung'] ?? 0,
      abmahnung: json['abmahnung'] ?? 0,
      letzteAbmahnung: json['letzte_abmahnung'] ?? 0,
    );
  }
}

/// VerwarnungService - handles warning API calls
class VerwarnungService {
  static const String baseUrl = 'https://icd360sev.icd360s.de/api';
  // ✅ SECURITY FIX: Removed hardcoded API key (extractable via reverse engineering)
  // All requests now use dynamic Device Key only

  late http.Client _client;
  final DeviceKeyService _deviceKeyService = DeviceKeyService();
  String? _token;

  // Singleton
  static final VerwarnungService _instance = VerwarnungService._internal();
  factory VerwarnungService() => _instance;
  VerwarnungService._internal() {
    _client = IOClient(HttpClientFactory.createPinnedHttpClient());
  }

  void setToken(String? token) => _token = token;

  Map<String, String> get _headers {
    final deviceKey = _deviceKeyService.deviceKey;
    return {
      'Content-Type': 'application/json',
      'User-Agent': 'ICD360S-Vorsitzer/1.0',
      if (_token != null) 'Authorization': 'Bearer $_token',
      if (deviceKey != null) 'X-Device-Key': deviceKey,
    };
  }

  /// Create a warning for a user
  Future<Verwarnung?> createVerwarnung({
    required int userId,
    required String typ,
    required String grund,
    String? beschreibung,
    required String datum,
  }) async {
    try {
      final body = <String, dynamic>{
        'user_id': userId,
        'typ': typ,
        'grund': grund,
        'datum': datum,
      };
      if (beschreibung != null && beschreibung.isNotEmpty) {
        body['beschreibung'] = beschreibung;
      }

      final response = await _client.post(
        Uri.parse('$baseUrl/admin/verwarnungen_create.php'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 201 && data['success'] == true) {
        return Verwarnung.fromJson(data['warning']);
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get all warnings for a user
  Future<({List<Verwarnung> warnings, VerwarnungStats stats})?> getVerwarnungen(int userId) async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/admin/verwarnungen_list.php?user_id=$userId'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        final warningsList = data['warnings'] as List;
        final warnings = warningsList.map((w) => Verwarnung.fromJson(w)).toList();
        final stats = VerwarnungStats.fromJson(data['stats']);
        return (warnings: warnings, stats: stats);
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Delete a warning
  Future<bool> deleteVerwarnung(int id) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/admin/verwarnungen_delete.php'),
        headers: _headers,
        body: jsonEncode({'id': id}),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      return response.statusCode == 200 && data['success'] == true;
    } catch (e) {
      return false;
    }
  }
}
