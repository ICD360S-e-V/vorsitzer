import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'device_key_service.dart';
import 'http_client_factory.dart';
import 'logger_service.dart';

final _log = LoggerService();

class BugReport {
  final int id;
  final String? anonymousId;
  final String? mitgliedernummer;
  final String description;
  final String status;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? resolvedBy;
  final String? internalNotes;
  final String? memberVorname;
  final String? memberNachname;

  BugReport({
    required this.id,
    this.anonymousId,
    this.mitgliedernummer,
    required this.description,
    required this.status,
    required this.createdAt,
    this.resolvedAt,
    this.resolvedBy,
    this.internalNotes,
    this.memberVorname,
    this.memberNachname,
  });

  factory BugReport.fromJson(Map<String, dynamic> json) {
    return BugReport(
      id: json['id'] is int ? json['id'] : int.parse(json['id'].toString()),
      anonymousId: json['anonymous_id'],
      mitgliedernummer: json['mitgliedernummer'],
      description: json['description'] ?? '',
      status: json['status'] ?? 'new',
      createdAt: DateTime.parse(json['created_at']),
      resolvedAt: json['resolved_at'] != null ? DateTime.parse(json['resolved_at']) : null,
      resolvedBy: json['resolved_by'],
      internalNotes: json['internal_notes'],
      memberVorname: json['member_vorname'],
      memberNachname: json['member_nachname'],
    );
  }

  String get memberDisplay {
    if (mitgliedernummer == null || mitgliedernummer!.isEmpty) return 'Anonym';
    final fullName = [memberVorname, memberNachname].where((s) => s != null && s.isNotEmpty).join(' ');
    if (fullName.isEmpty) return mitgliedernummer!;
    return '$fullName ($mitgliedernummer)';
  }

  String get statusDisplay {
    switch (status) {
      case 'new':
        return 'Neu';
      case 'in_progress':
        return 'In Bearbeitung';
      case 'resolved':
        return 'Erledigt';
      case 'dismissed':
        return 'Verworfen';
      default:
        return status;
    }
  }

  BugReport copyWith({
    String? status,
    DateTime? resolvedAt,
    String? resolvedBy,
    String? internalNotes,
  }) {
    return BugReport(
      id: id,
      anonymousId: anonymousId,
      mitgliedernummer: mitgliedernummer,
      description: description,
      status: status ?? this.status,
      createdAt: createdAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      resolvedBy: resolvedBy ?? this.resolvedBy,
      internalNotes: internalNotes ?? this.internalNotes,
      memberVorname: memberVorname,
      memberNachname: memberNachname,
    );
  }
}

class BugReportListResult {
  final List<BugReport> items;
  final int total;
  final Map<String, int> counts;

  BugReportListResult({required this.items, required this.total, required this.counts});
}

class BugReportService {
  static const String baseUrl = 'https://icd360sev.icd360s.de/api';

  late http.Client _client;
  final DeviceKeyService _deviceKeyService = DeviceKeyService();

  static final BugReportService _instance = BugReportService._internal();
  factory BugReportService() => _instance;
  BugReportService._internal() {
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

  Future<BugReportListResult?> list({
    required String mitgliedernummer,
    String status = 'new',
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/vorstand/bug_reports/list.php'),
        headers: _headers,
        body: jsonEncode({
          'mitgliedernummer': mitgliedernummer,
          'status': status,
          'limit': limit,
          'offset': offset,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      if (data['success'] != true) return null;

      final itemsList = (data['items'] as List?) ?? [];
      final items = itemsList.map((j) => BugReport.fromJson(j as Map<String, dynamic>)).toList();
      final countsRaw = (data['counts'] as Map?) ?? {};
      final counts = countsRaw.map((k, v) => MapEntry(k.toString(), v is int ? v : int.tryParse(v.toString()) ?? 0));

      return BugReportListResult(
        items: items,
        total: (data['total'] is int) ? data['total'] : int.tryParse('${data['total']}') ?? items.length,
        counts: counts,
      );
    } catch (e) {
      _log.error('BugReportService.list failed: $e', tag: 'BUGREPORT');
      return null;
    }
  }

  Future<BugReport?> update({
    required String mitgliedernummer,
    required int id,
    String? status,
    String? internalNotes,
  }) async {
    try {
      final body = <String, dynamic>{
        'mitgliedernummer': mitgliedernummer,
        'id': id,
        if (status != null) 'status': status,
        if (internalNotes != null) 'internal_notes': internalNotes,
      };

      final response = await _client.post(
        Uri.parse('$baseUrl/vorstand/bug_reports/update.php'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      if (data['success'] != true) return null;
      final item = data['item'];
      if (item == null) return null;
      return BugReport.fromJson(item as Map<String, dynamic>);
    } on SocketException {
      return null;
    } catch (e) {
      _log.error('BugReportService.update failed: $e', tag: 'BUGREPORT');
      return null;
    }
  }
}
