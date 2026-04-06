import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'api_service.dart';
import 'device_key_service.dart';
import 'http_client_factory.dart';
import 'logger_service.dart';

final _log = LoggerService();

// ─── AES-256 Encryption ──────────────────────────────────────────────
// Client-side encryption: data is encrypted BEFORE sending to server.
// Server stores only ciphertext. Only this app can decrypt.

class _RoutineCrypto {
  // SECURITY NOTE: encryption key should ideally be server-side config
  // AES-256 key (32 bytes hex) — only exists in the app binary
  static final _key = enc.Key.fromBase16('52307574316e336e4175666734623321494344333630532d323032365f4b6579');
  static final _encrypter = enc.Encrypter(enc.AES(_key, mode: enc.AESMode.cbc, padding: 'PKCS7'));

  /// Encrypt a plaintext string → Base64(IV + ciphertext)
  static String encrypt(String plaintext) {
    final iv = enc.IV.fromSecureRandom(16);
    final encrypted = _encrypter.encrypt(plaintext, iv: iv);
    // Prepend IV (16 bytes) to ciphertext for decryption
    final combined = iv.bytes + encrypted.bytes;
    return base64Encode(combined);
  }

  /// Decrypt Base64(IV + ciphertext) → plaintext
  static String decrypt(String cipherBase64) {
    try {
      final combined = base64Decode(cipherBase64);
      if (combined.length < 17) return cipherBase64; // Not encrypted
      final iv = enc.IV(combined.sublist(0, 16));
      final cipherBytes = combined.sublist(16);
      return _encrypter.decrypt(enc.Encrypted(cipherBytes), iv: iv);
    } catch (_) {
      // If decryption fails, return as-is (legacy unencrypted data)
      return cipherBase64;
    }
  }

  /// Decrypt if non-null and non-empty
  static String? decryptNullable(String? value) {
    if (value == null || value.isEmpty) return value;
    return decrypt(value);
  }
}

// ─── Models ───────────────────────────────────────────────────────────

class Routine {
  final int id;
  final int userId;
  final String title;
  final String? description;
  final String frequency; // daily, weekly, monthly, yearly
  final int? dayOfWeek;   // 1=Mon..5=Fri
  final int? dayOfMonth;  // 1-28
  final int? monthOfYear; // 1-12
  final String? category;
  final String preferredTime; // HH:mm:ss
  final bool isActive;
  final String createdBy;
  final String? memberName;
  final String? memberNummer;
  final DateTime createdAt;

  Routine({
    required this.id,
    required this.userId,
    required this.title,
    this.description,
    required this.frequency,
    this.dayOfWeek,
    this.dayOfMonth,
    this.monthOfYear,
    this.category,
    this.preferredTime = '09:00:00',
    required this.isActive,
    required this.createdBy,
    this.memberName,
    this.memberNummer,
    required this.createdAt,
  });

  /// Deserialize + DECRYPT encrypted fields from server
  factory Routine.fromJson(Map<String, dynamic> json) {
    return Routine(
      id: _parseInt(json['id']),
      userId: _parseInt(json['user_id']),
      title: _RoutineCrypto.decrypt(json['title'] ?? ''),
      description: _RoutineCrypto.decryptNullable(json['description']),
      frequency: json['frequency'] ?? 'weekly',
      dayOfWeek: json['day_of_week'] != null ? _parseInt(json['day_of_week']) : null,
      dayOfMonth: json['day_of_month'] != null ? _parseInt(json['day_of_month']) : null,
      monthOfYear: json['month_of_year'] != null ? _parseInt(json['month_of_year']) : null,
      category: _RoutineCrypto.decryptNullable(json['category']),
      preferredTime: json['preferred_time'] ?? '09:00:00',
      isActive: (json['is_active'] ?? 1) == 1 || json['is_active'] == true,
      createdBy: json['created_by'] ?? '',
      memberName: json['member_name'],
      memberNummer: json['member_nummer'],
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
    );
  }

  String get preferredTimeShort {
    final parts = preferredTime.split(':');
    if (parts.length >= 2) return '${parts[0]}:${parts[1]}';
    return preferredTime;
  }

  String get frequencyLabel {
    switch (frequency) {
      case 'once': return 'Einmal';
      case 'daily': return 'Täglich';
      case 'weekly': return 'Wöchentlich';
      case 'monthly': return 'Monatlich';
      case 'yearly': return 'Jährlich';
      default: return frequency;
    }
  }

  String get dayOfWeekLabel {
    switch (dayOfWeek) {
      case 1: return 'Montag';
      case 2: return 'Dienstag';
      case 3: return 'Mittwoch';
      case 4: return 'Donnerstag';
      case 5: return 'Freitag';
      default: return '';
    }
  }
}

class RoutineExecution {
  final int id;
  final int routineId;
  final DateTime scheduledDate;
  final String status; // pending, done, skipped
  final String? notes;
  final String? completedBy;
  final DateTime? completedAt;
  // From join
  final String? routineTitle;
  final String? routineCategory;
  final String? frequency;
  final String? preferredTime; // HH:mm:ss
  final int? userId;
  final String? memberName;
  final String? memberNummer;

  RoutineExecution({
    required this.id,
    required this.routineId,
    required this.scheduledDate,
    required this.status,
    this.notes,
    this.completedBy,
    this.completedAt,
    this.routineTitle,
    this.routineCategory,
    this.frequency,
    this.preferredTime,
    this.userId,
    this.memberName,
    this.memberNummer,
  });

  /// Deserialize + DECRYPT encrypted fields from server
  factory RoutineExecution.fromJson(Map<String, dynamic> json) {
    return RoutineExecution(
      id: _parseInt(json['id']),
      routineId: _parseInt(json['routine_id']),
      scheduledDate: DateTime.tryParse(json['scheduled_date'] ?? '') ?? DateTime.now(),
      status: json['status'] ?? 'pending',
      notes: _RoutineCrypto.decryptNullable(json['notes']),
      completedBy: json['completed_by'],
      completedAt: json['completed_at'] != null ? DateTime.tryParse(json['completed_at']) : null,
      routineTitle: _RoutineCrypto.decryptNullable(json['routine_title']),
      routineCategory: _RoutineCrypto.decryptNullable(json['routine_category']),
      frequency: json['frequency'],
      preferredTime: json['preferred_time'],
      userId: json['user_id'] != null ? _parseInt(json['user_id']) : null,
      memberName: json['member_name'],
      memberNummer: json['member_nummer'],
    );
  }

  bool get isPending => status == 'pending';
  bool get isDone => status == 'done';
  bool get isSkipped => status == 'skipped';

  String get preferredTimeShort {
    if (preferredTime == null) return '';
    final parts = preferredTime!.split(':');
    if (parts.length >= 2) return '${parts[0]}:${parts[1]}';
    return preferredTime!;
  }
}

class RoutineStats {
  final int totalActive;
  final int totalMembers;

  RoutineStats({required this.totalActive, required this.totalMembers});

  factory RoutineStats.fromJson(Map<String, dynamic> json) {
    return RoutineStats(
      totalActive: _parseInt(json['total_active']),
      totalMembers: _parseInt(json['total_members']),
    );
  }
}

class ExecutionStats {
  final int total;
  final int done;
  final int pending;
  final int skipped;

  ExecutionStats({
    required this.total,
    required this.done,
    required this.pending,
    required this.skipped,
  });

  factory ExecutionStats.fromJson(Map<String, dynamic> json) {
    return ExecutionStats(
      total: _parseInt(json['total']),
      done: _parseInt(json['done']),
      pending: _parseInt(json['pending']),
      skipped: _parseInt(json['skipped']),
    );
  }

  double get progressPercent => total > 0 ? (done / total) * 100 : 0;
}

int _parseInt(dynamic v) {
  if (v is int) return v;
  if (v is String) return int.tryParse(v) ?? 0;
  if (v is double) return v.toInt();
  return 0;
}

// ─── Service ──────────────────────────────────────────────────────────

class RoutineService {
  static const String baseUrl = 'https://icd360sev.icd360s.de/api';
  final DeviceKeyService _deviceKeyService = DeviceKeyService();

  late http.Client _client;

  static final RoutineService _instance = RoutineService._internal();
  factory RoutineService() => _instance;
  RoutineService._internal() {
    _client = IOClient(HttpClientFactory.createPinnedHttpClient());
  }

  final _apiService = ApiService();

  Map<String, String> get _headers {
    final deviceKey = _deviceKeyService.deviceKey;
    final token = _apiService.token;
    return {
      'Content-Type': 'application/json',
      'User-Agent': 'ICD360S-Vorsitzer/1.0',
      if (deviceKey != null) 'X-Device-Key': deviceKey,
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ─── Routines CRUD ────────────────────────────────────────────────

  Future<List<Routine>> getRoutines({int? userId, String? category, bool activeOnly = true}) async {
    try {
      final params = <String, String>{
        'active_only': activeOnly ? '1' : '0',
      };
      if (userId != null) params['user_id'] = userId.toString();
      if (category != null) params['category'] = category;

      final uri = Uri.parse('$baseUrl/admin/routine_list.php').replace(queryParameters: params);
      final response = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final list = (data['routines'] as List?) ?? [];
          return list.map((j) => Routine.fromJson(j)).toList();
        }
      }
      return [];
    } catch (e) {
      _log.error('RoutineService: getRoutines failed: $e', tag: 'ROUTINE');
      return [];
    }
  }

  Future<RoutineStats?> getRoutineStats() async {
    try {
      final uri = Uri.parse('$baseUrl/admin/routine_list.php?active_only=1');
      final response = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['stats'] != null) {
          return RoutineStats.fromJson(data['stats']);
        }
      }
      return null;
    } catch (e) {
      _log.error('RoutineService: getRoutineStats failed: $e', tag: 'ROUTINE');
      return null;
    }
  }

  Future<List<String>> getCategories() async {
    try {
      final uri = Uri.parse('$baseUrl/admin/routine_list.php?active_only=1');
      final response = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          // Categories are stored encrypted — decrypt each one
          final rawList = (data['categories'] as List?) ?? [];
          return rawList.map((c) => _RoutineCrypto.decrypt(c.toString())).toList();
        }
      }
      return [];
    } catch (e) {
      _log.error('RoutineService: getCategories failed: $e', tag: 'ROUTINE');
      return [];
    }
  }

  /// Create routine — ENCRYPTS title, description, category before sending
  Future<Routine?> createRoutine({
    required int userId,
    required String title,
    String? description,
    required String frequency,
    int? dayOfWeek,
    int? dayOfMonth,
    int? monthOfYear,
    String? category,
    String? preferredTime,
    String? onceDate,
  }) async {
    try {
      final body = {
        'user_id': userId,
        'title': _RoutineCrypto.encrypt(title),
        'frequency': frequency,
        if (description != null && description.isNotEmpty)
          'description': _RoutineCrypto.encrypt(description),
        if (dayOfWeek != null) 'day_of_week': dayOfWeek,
        if (dayOfMonth != null) 'day_of_month': dayOfMonth,
        if (monthOfYear != null) 'month_of_year': monthOfYear,
        if (category != null && category.isNotEmpty)
          'category': _RoutineCrypto.encrypt(category),
        if (preferredTime != null) 'preferred_time': preferredTime,
        if (onceDate != null) 'once_date': onceDate,
      };

      final response = await _client.post(
        Uri.parse('$baseUrl/admin/routine_create.php'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['routine'] != null) {
          return Routine.fromJson(data['routine']);
        }
      }
      return null;
    } catch (e) {
      _log.error('RoutineService: createRoutine failed: $e', tag: 'ROUTINE');
      return null;
    }
  }

  /// Update routine — ENCRYPTS text fields before sending
  Future<Routine?> updateRoutine(int routineId, Map<String, dynamic> fields) async {
    try {
      // Encrypt text fields if present
      final encFields = Map<String, dynamic>.from(fields);
      if (encFields.containsKey('title') && encFields['title'] != null) {
        encFields['title'] = _RoutineCrypto.encrypt(encFields['title'].toString());
      }
      if (encFields.containsKey('description') && encFields['description'] != null) {
        encFields['description'] = _RoutineCrypto.encrypt(encFields['description'].toString());
      }
      if (encFields.containsKey('category') && encFields['category'] != null) {
        encFields['category'] = _RoutineCrypto.encrypt(encFields['category'].toString());
      }

      final body = {'routine_id': routineId, ...encFields};
      final response = await _client.post(
        Uri.parse('$baseUrl/admin/routine_update.php'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['routine'] != null) {
          return Routine.fromJson(data['routine']);
        }
      }
      return null;
    } catch (e) {
      _log.error('RoutineService: updateRoutine failed: $e', tag: 'ROUTINE');
      return null;
    }
  }

  Future<bool> deleteRoutine(int routineId) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/admin/routine_delete.php'),
        headers: _headers,
        body: jsonEncode({'routine_id': routineId}),
      ).timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body);
      return data['success'] == true;
    } catch (e) {
      _log.error('RoutineService: deleteRoutine failed: $e', tag: 'ROUTINE');
      return false;
    }
  }

  // ─── Executions ───────────────────────────────────────────────────

  Future<({List<RoutineExecution> executions, ExecutionStats? stats})> getExecutions({
    required String startDate,
    required String endDate,
    int? userId,
  }) async {
    try {
      final params = <String, String>{
        'start_date': startDate,
        'end_date': endDate,
        'auto_generate': '1',
      };
      if (userId != null) params['user_id'] = userId.toString();

      final uri = Uri.parse('$baseUrl/admin/routine_executions.php').replace(queryParameters: params);
      final response = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final list = (data['executions'] as List?) ?? [];
          final executions = list.map((j) => RoutineExecution.fromJson(j)).toList();
          final statsJson = data['stats'];
          final stats = statsJson != null ? ExecutionStats.fromJson(statsJson) : null;
          return (executions: executions, stats: stats);
        }
      }
      return (executions: <RoutineExecution>[], stats: null);
    } catch (e) {
      _log.error('RoutineService: getExecutions failed: $e', tag: 'ROUTINE');
      return (executions: <RoutineExecution>[], stats: null);
    }
  }

  /// Update execution — ENCRYPTS notes before sending
  Future<bool> updateExecution({
    int? executionId,
    int? routineId,
    String? scheduledDate,
    required String status,
    String? notes,
  }) async {
    try {
      final body = <String, dynamic>{
        'status': status,
        if (notes != null) 'notes': _RoutineCrypto.encrypt(notes),
      };
      if (executionId != null) {
        body['execution_id'] = executionId;
      } else if (routineId != null && scheduledDate != null) {
        body['routine_id'] = routineId;
        body['scheduled_date'] = scheduledDate;
      }

      final response = await _client.post(
        Uri.parse('$baseUrl/admin/routine_executions.php'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body);
      return data['success'] == true;
    } catch (e) {
      _log.error('RoutineService: updateExecution failed: $e', tag: 'ROUTINE');
      return false;
    }
  }
}
