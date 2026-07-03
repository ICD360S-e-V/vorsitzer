import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'api_service.dart';
import 'device_key_service.dart';
import 'http_client_factory.dart';
import 'logger_service.dart';

final _log = LoggerService();

// ─── Models ───────────────────────────────────────────────────────────

class ArbeitstagMember {
  final int userId;
  final String mitgliedernummer;
  final String name;
  final String? vorname;
  final String? nachname;

  final DateTime? ticketDoneAt;
  final int? ticketId;
  final String? ticketSubject;
  final String? ticketStatus;

  final DateTime? terminDoneAt;
  final int? terminId;
  final String? terminTitle;
  final DateTime? terminDate;

  final DateTime? routineDoneAt;
  final int? routineExecutionId;

  final int prioritaet;
  final String? prioGrund;
  final int? bearbeiterUserId;
  final String? notiz;

  final int openTicketsCount;
  final int termineKwCount;
  final int routinesPendingCount;

  ArbeitstagMember({
    required this.userId,
    required this.mitgliedernummer,
    required this.name,
    this.vorname,
    this.nachname,
    this.ticketDoneAt,
    this.ticketId,
    this.ticketSubject,
    this.ticketStatus,
    this.terminDoneAt,
    this.terminId,
    this.terminTitle,
    this.terminDate,
    this.routineDoneAt,
    this.routineExecutionId,
    required this.prioritaet,
    this.prioGrund,
    this.bearbeiterUserId,
    this.notiz,
    required this.openTicketsCount,
    required this.termineKwCount,
    required this.routinesPendingCount,
  });

  bool get ticketDone => ticketDoneAt != null;
  bool get terminDone => terminDoneAt != null;
  bool get routineDone => routineDoneAt != null;
  bool get allDone => ticketDone && terminDone && routineDone;

  factory ArbeitstagMember.fromJson(Map<String, dynamic> j) => ArbeitstagMember(
        userId: _int(j['user_id']),
        mitgliedernummer: j['mitgliedernummer'] ?? '',
        name: j['name'] ?? '',
        vorname: j['vorname'],
        nachname: j['nachname'],
        ticketDoneAt: _dt(j['ticket_done_at']),
        ticketId: _intN(j['ticket_id']),
        ticketSubject: j['ticket_subject'],
        ticketStatus: j['ticket_status'],
        terminDoneAt: _dt(j['termin_done_at']),
        terminId: _intN(j['termin_id']),
        terminTitle: j['termin_title'],
        terminDate: _dt(j['termin_date']),
        routineDoneAt: _dt(j['routine_done_at']),
        routineExecutionId: _intN(j['routine_execution_id']),
        prioritaet: _int(j['prioritaet']),
        prioGrund: j['prio_grund'],
        bearbeiterUserId: _intN(j['bearbeiter_user_id']),
        notiz: j['notiz'],
        openTicketsCount: _int(j['open_tickets_count']),
        termineKwCount: _int(j['termine_kw_count']),
        routinesPendingCount: _int(j['routines_pending_count']),
      );
}

class ArbeitstagStats {
  final int totalMembers;
  final int totalDone;
  final int totalUrgent;
  ArbeitstagStats({required this.totalMembers, required this.totalDone, required this.totalUrgent});

  factory ArbeitstagStats.fromJson(Map<String, dynamic> j) => ArbeitstagStats(
        totalMembers: _int(j['total_members']),
        totalDone: _int(j['total_done']),
        totalUrgent: _int(j['total_urgent']),
      );
}

class ArbeitstagWoche {
  final int kwYear;
  final int kwNumber;
  final DateTime monday;
  final DateTime sunday;
  final List<ArbeitstagMember> members;
  final ArbeitstagStats stats;

  ArbeitstagWoche({
    required this.kwYear,
    required this.kwNumber,
    required this.monday,
    required this.sunday,
    required this.members,
    required this.stats,
  });

  factory ArbeitstagWoche.fromJson(Map<String, dynamic> j) => ArbeitstagWoche(
        kwYear: _int(j['kw_year']),
        kwNumber: _int(j['kw_number']),
        monday: DateTime.parse(j['monday']),
        sunday: DateTime.parse(j['sunday']),
        members: ((j['members'] as List?) ?? []).map((m) => ArbeitstagMember.fromJson(m)).toList(),
        stats: ArbeitstagStats.fromJson(j['stats'] ?? {}),
      );
}

int _int(dynamic v) {
  if (v is int) return v;
  if (v is String) return int.tryParse(v) ?? 0;
  if (v is double) return v.toInt();
  return 0;
}

int? _intN(dynamic v) {
  if (v == null) return null;
  return _int(v);
}

DateTime? _dt(dynamic v) {
  if (v == null || v == '') return null;
  return DateTime.tryParse(v.toString());
}

// ─── Service ──────────────────────────────────────────────────────────

class ArbeitstagService {
  static const String baseUrl = 'https://icd360sev.icd360s.de/api';
  final DeviceKeyService _deviceKeyService = DeviceKeyService();
  late http.Client _client;

  static final ArbeitstagService _instance = ArbeitstagService._internal();
  factory ArbeitstagService() => _instance;
  ArbeitstagService._internal() {
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

  Future<ArbeitstagWoche?> getWoche({required int kwYear, required int kwNumber}) async {
    try {
      final uri = Uri.parse('$baseUrl/admin/arbeitstag_list.php').replace(queryParameters: {
        'kw_year': kwYear.toString(),
        'kw_number': kwNumber.toString(),
      });
      final res = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        _log.error('arbeitstag getWoche HTTP ${res.statusCode}', tag: 'ARBEITSTAG');
        return null;
      }
      final data = jsonDecode(res.body);
      if (data['success'] != true) return null;
      return ArbeitstagWoche.fromJson(data['data']);
    } catch (e) {
      _log.error('arbeitstag getWoche failed: $e', tag: 'ARBEITSTAG');
      return null;
    }
  }

  Future<bool> bearbeitet({
    required int kwYear,
    required int kwNumber,
    required int userId,
    required String typ, // 'ticket' | 'termin' | 'routine'
    int? refId,
    String? notiz,
    String action = 'set', // 'set' | 'reset'
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/admin/arbeitstag_bearbeitet.php');
      final body = <String, dynamic>{
        'kw_year': kwYear,
        'kw_number': kwNumber,
        'user_id': userId,
        'typ': typ,
        'action': action,
      };
      if (refId != null) body['ref_id'] = refId;
      if (notiz != null) body['notiz'] = notiz;
      final res = await _client
          .post(uri, headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return false;
      final data = jsonDecode(res.body);
      return data['success'] == true;
    } catch (e) {
      _log.error('arbeitstag bearbeitet failed: $e', tag: 'ARBEITSTAG');
      return false;
    }
  }
}
