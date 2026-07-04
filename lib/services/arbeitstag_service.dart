import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'api_service.dart';
import 'device_key_service.dart';
import 'http_client_factory.dart';
import 'logger_service.dart';

final _log = LoggerService();

// Duplicate of _RoutineCrypto in routine_service.dart — same key,
// same v2 wire format. Duplicated (not shared) to keep Arbeitswochen
// self-contained; if a third consumer appears, extract to shared file.
class _AtRoutineCrypto {
  static const _keyHex = String.fromEnvironment('ROUTINE_AES_KEY_V2');
  static final enc.Encrypter? _enc = _keyHex.isEmpty
      ? null
      : enc.Encrypter(enc.AES(enc.Key.fromBase16(_keyHex),
          mode: enc.AESMode.cbc, padding: 'PKCS7'));
  static const String _v2Prefix = 'v2:';

  static String decrypt(String ciphertext) {
    if (_enc == null || !ciphertext.startsWith(_v2Prefix)) return ciphertext;
    try {
      final combined = base64Decode(ciphertext.substring(_v2Prefix.length));
      if (combined.length < 17) return ciphertext;
      final iv = enc.IV(combined.sublist(0, 16));
      return _enc!.decrypt(enc.Encrypted(combined.sublist(16)), iv: iv);
    } catch (_) {
      return ciphertext;
    }
  }

  static String? decryptNullable(String? v) {
    if (v == null || v.isEmpty) return v;
    return decrypt(v);
  }
}

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
  final String ticketState; // offen | geplant | in_bearbeitung | erledigt

  final DateTime? terminDoneAt;
  final int? terminId;
  final String? terminTitle;
  final DateTime? terminDate;
  final String terminState;

  final DateTime? routineDoneAt;
  final int? routineExecutionId;
  final String routineState;

  final DateTime? notfallDoneAt;
  final int? notfallTerminId;
  final String? notfallTerminTitle;
  final DateTime? notfallTerminDate;
  final String notfallState;

  final int prioritaet;
  final String? prioGrund;
  final int? bearbeiterUserId;
  final String? notiz;

  final int openTicketsCount;
  final int termineHeuteCount;
  final int routinesHeuteCount;

  final DateTime? archivedAt;
  final int? archivedBy;
  final String? archivGrund;

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
    this.ticketState = 'offen',
    this.terminDoneAt,
    this.terminId,
    this.terminTitle,
    this.terminDate,
    this.terminState = 'offen',
    this.routineDoneAt,
    this.routineExecutionId,
    this.routineState = 'offen',
    this.notfallDoneAt,
    this.notfallTerminId,
    this.notfallTerminTitle,
    this.notfallTerminDate,
    this.notfallState = 'offen',
    required this.prioritaet,
    this.prioGrund,
    this.bearbeiterUserId,
    this.notiz,
    required this.openTicketsCount,
    required this.termineHeuteCount,
    required this.routinesHeuteCount,
    this.archivedAt,
    this.archivedBy,
    this.archivGrund,
  });

  bool get isArchived => archivedAt != null;

  bool get ticketDone  => ticketState == 'erledigt';
  bool get terminDone  => terminState == 'erledigt';
  bool get routineDone => routineState == 'erledigt';
  bool get notfallDone => notfallState == 'erledigt';
  // "allDone" NU include notfall — e slot opțional, ne-standard
  bool get allDone => ticketDone && terminDone && routineDone;

  String stateFor(String typ) {
    switch (typ) {
      case 'ticket':  return ticketState;
      case 'termin':  return terminState;
      case 'routine': return routineState;
      case 'notfall': return notfallState;
      default: return 'offen';
    }
  }

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
        ticketState: j['ticket_state'] ?? 'offen',
        terminDoneAt: _dt(j['termin_done_at']),
        terminId: _intN(j['termin_id']),
        terminTitle: j['termin_title'],
        terminDate: _dt(j['termin_date']),
        terminState: j['termin_state'] ?? 'offen',
        routineDoneAt: _dt(j['routine_done_at']),
        routineExecutionId: _intN(j['routine_execution_id']),
        routineState: j['routine_state'] ?? 'offen',
        notfallDoneAt: _dt(j['notfall_done_at']),
        notfallTerminId: _intN(j['notfall_termin_id']),
        notfallTerminTitle: j['notfall_termin_title'],
        notfallTerminDate: _dt(j['notfall_termin_date']),
        notfallState: j['notfall_state'] ?? 'offen',
        prioritaet: _int(j['prioritaet']),
        prioGrund: j['prio_grund'],
        bearbeiterUserId: _intN(j['bearbeiter_user_id']),
        notiz: j['notiz'],
        openTicketsCount: _int(j['open_tickets_count']),
        termineHeuteCount: _int(j['termine_heute_count']),
        routinesHeuteCount: _int(j['routines_heute_count']),
        archivedAt: _dt(j['archived_at']),
        archivedBy: _intN(j['archived_by']),
        archivGrund: j['archiv_grund'],
      );
}

class ArbeitstagStats {
  final int totalMembers;
  final int totalDone;
  final int totalUrgent;
  final int totalArchived;
  ArbeitstagStats({
    required this.totalMembers,
    required this.totalDone,
    required this.totalUrgent,
    this.totalArchived = 0,
  });

  factory ArbeitstagStats.fromJson(Map<String, dynamic> j) => ArbeitstagStats(
        totalMembers: _int(j['total_members']),
        totalDone: _int(j['total_done']),
        totalUrgent: _int(j['total_urgent']),
        totalArchived: _int(j['total_archived']),
      );
}

class ArbeitstagPickerItem {
  final int id;
  final String title;
  final String? subtitle;
  final String? meta;

  ArbeitstagPickerItem({required this.id, required this.title, this.subtitle, this.meta});

  factory ArbeitstagPickerItem.fromJson(Map<String, dynamic> j, {bool decryptTitle = false}) {
    final rawTitle = j['title']?.toString() ?? '';
    return ArbeitstagPickerItem(
      id: _int(j['id']),
      title: decryptTitle ? _AtRoutineCrypto.decrypt(rawTitle) : rawTitle,
      subtitle: j['subtitle']?.toString(),
      meta: decryptTitle ? _AtRoutineCrypto.decryptNullable(j['meta']?.toString()) : j['meta']?.toString(),
    );
  }
}

class ArbeitstagTag {
  final DateTime datum;
  final List<ArbeitstagMember> members;
  final ArbeitstagStats stats;

  ArbeitstagTag({required this.datum, required this.members, required this.stats});

  factory ArbeitstagTag.fromJson(Map<String, dynamic> j) => ArbeitstagTag(
        datum: DateTime.parse(j['datum']),
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

  Future<ArbeitstagTag?> getTag({
    required String datum, // YYYY-MM-DD
    String view = 'active',
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/admin/arbeitstag_list.php').replace(queryParameters: {
        'datum': datum,
        'view': view,
      });
      final res = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        _log.error('arbeitstag getTag HTTP ${res.statusCode}', tag: 'ARBEITSTAG');
        return null;
      }
      final data = jsonDecode(res.body);
      if (data['success'] != true) return null;
      return ArbeitstagTag.fromJson(data);
    } catch (e) {
      _log.error('arbeitstag getTag failed: $e', tag: 'ARBEITSTAG');
      return null;
    }
  }

  Future<bool> archiveToggle({
    required int userId,
    required String action, // 'archive' | 'unarchive'
    String? grund,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/admin/arbeitstag_archiv_toggle.php');
      final body = <String, dynamic>{'user_id': userId, 'action': action};
      if (grund != null) body['grund'] = grund;
      final res = await _client
          .post(uri, headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return false;
      return jsonDecode(res.body)['success'] == true;
    } catch (e) {
      _log.error('arbeitstag archiveToggle failed: $e', tag: 'ARBEITSTAG');
      return false;
    }
  }

  Future<List<ArbeitstagPickerItem>> getPickerItems({
    required int userId,
    required String typ,
    required String datum,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/admin/arbeitstag_picker.php').replace(queryParameters: {
        'user_id': userId.toString(),
        'typ': typ,
        'datum': datum,
      });
      final res = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body);
      if (data['success'] != true) return [];
      final list = (data['items'] as List?) ?? [];
      return list.map((j) => ArbeitstagPickerItem.fromJson(j, decryptTitle: typ == 'routine')).toList();
    } catch (e) {
      _log.error('arbeitstag getPickerItems failed: $e', tag: 'ARBEITSTAG');
      return [];
    }
  }

  Future<bool> setState({
    required String datum,
    required int userId,
    required String typ, // 'ticket' | 'termin' | 'routine'
    required String state, // 'offen' | 'geplant' | 'in_bearbeitung' | 'erledigt'
    int? refId,
    String? notiz,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/admin/arbeitstag_bearbeitet.php');
      final body = <String, dynamic>{
        'datum': datum,
        'user_id': userId,
        'typ': typ,
        'state': state,
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
      _log.error('arbeitstag setState failed: $e', tag: 'ARBEITSTAG');
      return false;
    }
  }
}
