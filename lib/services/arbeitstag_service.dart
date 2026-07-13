import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'api_service.dart';
import 'device_key_service.dart';
import 'http_client_factory.dart';
import 'logger_service.dart';

final _log = LoggerService();

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

// ─── Granularity ──────────────────────────────────────────────────────

enum ArbeitsbereichGranularity { tag, woche, monat }

extension ArbeitsbereichGranularityX on ArbeitsbereichGranularity {
  String get wire {
    switch (this) {
      case ArbeitsbereichGranularity.tag: return 'tag';
      case ArbeitsbereichGranularity.woche: return 'woche';
      case ArbeitsbereichGranularity.monat: return 'monat';
    }
  }

  static ArbeitsbereichGranularity fromWire(String? s) {
    switch (s) {
      case 'tag': return ArbeitsbereichGranularity.tag;
      case 'monat': return ArbeitsbereichGranularity.monat;
      default: return ArbeitsbereichGranularity.woche;
    }
  }
}

/// PeriodKey — identifică unic o perioadă (day / KW / month).
/// Trimitem toate câmpurile la server; server-ul folosește ce corespunde granularity.
class PeriodKey {
  final ArbeitsbereichGranularity granularity;
  final DateTime? date;   // used for tag (YYYY-MM-DD)
  final int? kwYear;      // used for woche
  final int? kwNumber;    // used for woche
  final int? year;        // used for monat
  final int? month;       // used for monat (1-12)

  const PeriodKey._({
    required this.granularity,
    this.date,
    this.kwYear,
    this.kwNumber,
    this.year,
    this.month,
  });

  factory PeriodKey.tag(DateTime d) => PeriodKey._(
        granularity: ArbeitsbereichGranularity.tag,
        date: DateTime(d.year, d.month, d.day),
      );

  factory PeriodKey.woche(int kwYear, int kwNumber) => PeriodKey._(
        granularity: ArbeitsbereichGranularity.woche,
        kwYear: kwYear,
        kwNumber: kwNumber,
      );

  factory PeriodKey.monat(int year, int month) => PeriodKey._(
        granularity: ArbeitsbereichGranularity.monat,
        year: year,
        month: month,
      );

  Map<String, String> toQuery() {
    final q = <String, String>{'granularity': granularity.wire};
    if (date != null) {
      q['date'] = '${date!.year.toString().padLeft(4, '0')}-'
          '${date!.month.toString().padLeft(2, '0')}-'
          '${date!.day.toString().padLeft(2, '0')}';
    }
    if (kwYear != null) q['kw_year'] = kwYear!.toString();
    if (kwNumber != null) q['kw_number'] = kwNumber!.toString();
    if (year != null) q['year'] = year!.toString();
    if (month != null) q['month'] = month!.toString();
    return q;
  }

  Map<String, dynamic> toBody() {
    final b = <String, dynamic>{'granularity': granularity.wire};
    if (date != null) {
      b['date'] = '${date!.year.toString().padLeft(4, '0')}-'
          '${date!.month.toString().padLeft(2, '0')}-'
          '${date!.day.toString().padLeft(2, '0')}';
    }
    if (kwYear != null) b['kw_year'] = kwYear;
    if (kwNumber != null) b['kw_number'] = kwNumber;
    if (year != null) b['year'] = year;
    if (month != null) b['month'] = month;
    return b;
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
  final String? routineTitle;
  final DateTime? routineScheduledDate;
  final String routineState;

  final DateTime? notfallDoneAt;
  final int? notfallTerminId;
  final String? notfallTerminTitle;
  final DateTime? notfallTerminDate;
  final String notfallState;

  final int prioritaet;
  final String? prioGrund;
  final int? bearbeiterUserId;
  final String? bearbeiterName;
  final String? notiz;

  final int openTicketsCount;
  final int termineKwCount;
  final int routinesKwCount;
  final int notfallKwCount;

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
    this.routineTitle,
    this.routineScheduledDate,
    this.routineState = 'offen',
    this.notfallDoneAt,
    this.notfallTerminId,
    this.notfallTerminTitle,
    this.notfallTerminDate,
    this.notfallState = 'offen',
    required this.prioritaet,
    this.prioGrund,
    this.bearbeiterUserId,
    this.bearbeiterName,
    this.notiz,
    required this.openTicketsCount,
    required this.termineKwCount,
    required this.routinesKwCount,
    this.notfallKwCount = 0,
    this.archivedAt,
    this.archivedBy,
    this.archivGrund,
  });

  bool get isArchived => archivedAt != null;

  // „Done" implicit dacă membrul n-are activitate în period (chip-ul e ascuns
  // în UI, deci nu-l ține la „neterminați"). „Erledigt" explicit rămâne valid.
  bool get ticketDone  => ticketState == 'erledigt' || openTicketsCount == 0;
  bool get terminDone  => terminState == 'erledigt' || termineKwCount == 0;
  bool get routineDone => routineState == 'erledigt' || routinesKwCount == 0;
  bool get notfallDone => notfallState == 'erledigt' || notfallKwCount == 0;
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
        routineTitle: _AtRoutineCrypto.decryptNullable(j['routine_title']?.toString()),
        routineScheduledDate: _dt(j['routine_scheduled_date']),
        routineState: j['routine_state'] ?? 'offen',
        notfallDoneAt: _dt(j['notfall_done_at']),
        notfallTerminId: _intN(j['notfall_termin_id']),
        notfallTerminTitle: j['notfall_termin_title'],
        notfallTerminDate: _dt(j['notfall_termin_date']),
        notfallState: j['notfall_state'] ?? 'offen',
        prioritaet: _int(j['prioritaet']),
        prioGrund: j['prio_grund'],
        bearbeiterUserId: _intN(j['bearbeiter_user_id']),
        bearbeiterName: j['bearbeiter_name'],
        notiz: j['notiz'],
        openTicketsCount: _int(j['open_tickets_count']),
        termineKwCount: _int(j['termine_kw_count']),
        routinesKwCount: _int(j['routines_kw_count']),
        notfallKwCount: _int(j['notfall_kw_count']),
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

/// Wrapper pentru o perioadă completă (Tag / Woche / Monat) încărcată de server.
/// Anterior era `ArbeitstagWoche` — acum generalizat cu granularity + range.
class ArbeitsbereichPeriod {
  final ArbeitsbereichGranularity granularity;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final String label;
  final int? kwYear;
  final int? kwNumber;
  final int? year;
  final int? month;
  final DateTime? date;
  final List<ArbeitstagMember> members;
  final ArbeitstagStats stats;

  ArbeitsbereichPeriod({
    required this.granularity,
    required this.rangeStart,
    required this.rangeEnd,
    required this.label,
    this.kwYear,
    this.kwNumber,
    this.year,
    this.month,
    this.date,
    required this.members,
    required this.stats,
  });

  // Compat cu codul UI existent (arbeitstag_screen se aștepta la monday/sunday).
  DateTime get monday => rangeStart;
  DateTime get sunday => rangeEnd;

  factory ArbeitsbereichPeriod.fromJson(Map<String, dynamic> j) {
    final gran = ArbeitsbereichGranularityX.fromWire(j['granularity']?.toString());
    // Server backwards-compat: dacă lipsește range_start/end, fallback la monday/sunday.
    final start = _dt(j['range_start']) ?? _dt(j['monday']) ?? DateTime.now();
    final end = _dt(j['range_end']) ?? _dt(j['sunday']) ?? DateTime.now();
    return ArbeitsbereichPeriod(
      granularity: gran,
      rangeStart: start,
      rangeEnd: end,
      label: j['label']?.toString() ?? '',
      kwYear: _intN(j['kw_year']),
      kwNumber: _intN(j['kw_number']),
      year: _intN(j['year']),
      month: _intN(j['month']),
      date: _dt(j['date']),
      members: ((j['members'] as List?) ?? []).map((m) => ArbeitstagMember.fromJson(m)).toList(),
      stats: ArbeitstagStats.fromJson(j['stats'] ?? {}),
    );
  }
}

// ─── History entry (per period × user) ────────────────────────────────

class ArbeitstagHistoryEntry {
  final ArbeitsbereichGranularity granularity;
  final String periodLabel;   // "Mo, 13.07.2026" / "KW 28 / 2026" / "Juli 2026"
  final int? kwYear;
  final int? kwNumber;
  final int? year;
  final int? month;
  final DateTime? date;
  final String ticketState;
  final int? ticketId;
  final String? ticketSubject;
  final String terminState;
  final int? terminId;
  final String? terminTitle;
  final DateTime? terminDate;
  final String routineState;
  final int? routineExecutionId;
  final String? routineTitle;
  final String notfallState;
  final int? notfallTerminId;
  final String? notfallTerminTitle;
  final int prioritaet;
  final String? prioGrund;
  final String? notiz;
  final int? bearbeiterUserId;
  final String? bearbeiterName;
  final DateTime? updatedAt;

  ArbeitstagHistoryEntry({
    this.granularity = ArbeitsbereichGranularity.woche,
    this.periodLabel = '',
    this.kwYear,
    this.kwNumber,
    this.year,
    this.month,
    this.date,
    this.ticketState = 'offen',
    this.ticketId,
    this.ticketSubject,
    this.terminState = 'offen',
    this.terminId,
    this.terminTitle,
    this.terminDate,
    this.routineState = 'offen',
    this.routineExecutionId,
    this.routineTitle,
    this.notfallState = 'offen',
    this.notfallTerminId,
    this.notfallTerminTitle,
    required this.prioritaet,
    this.prioGrund,
    this.notiz,
    this.bearbeiterUserId,
    this.bearbeiterName,
    this.updatedAt,
  });

  bool get allErledigt =>
      ticketState == 'erledigt' && terminState == 'erledigt' && routineState == 'erledigt';

  String stateFor(String typ) {
    switch (typ) {
      case 'ticket':  return ticketState;
      case 'termin':  return terminState;
      case 'routine': return routineState;
      case 'notfall': return notfallState;
      default: return 'offen';
    }
  }

  factory ArbeitstagHistoryEntry.fromJson(Map<String, dynamic> j) => ArbeitstagHistoryEntry(
        granularity: ArbeitsbereichGranularityX.fromWire(j['granularity']?.toString()),
        periodLabel: j['period_label']?.toString() ?? '',
        kwYear: _intN(j['kw_year']),
        kwNumber: _intN(j['kw_number']),
        year: _intN(j['year']),
        month: _intN(j['month']),
        date: _dt(j['date']),
        ticketState: j['ticket_state'] ?? 'offen',
        ticketId: _intN(j['ticket_id']),
        ticketSubject: j['ticket_subject'],
        terminState: j['termin_state'] ?? 'offen',
        terminId: _intN(j['termin_id']),
        terminTitle: j['termin_title'],
        terminDate: _dt(j['termin_date']),
        routineState: j['routine_state'] ?? 'offen',
        routineExecutionId: _intN(j['routine_execution_id']),
        routineTitle: _AtRoutineCrypto.decryptNullable(j['routine_title']?.toString()),
        notfallState: j['notfall_state'] ?? 'offen',
        notfallTerminId: _intN(j['notfall_termin_id']),
        notfallTerminTitle: j['notfall_termin_title'],
        prioritaet: _int(j['prioritaet']),
        prioGrund: j['prio_grund'],
        notiz: j['notiz'],
        bearbeiterUserId: _intN(j['bearbeiter_user_id']),
        bearbeiterName: j['bearbeiter_name'],
        updatedAt: _dt(j['updated_at']),
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

  /// Unified — încarcă orice period (Tag/Woche/Monat) folosind același endpoint.
  Future<ArbeitsbereichPeriod?> getPeriod({
    required PeriodKey key,
    String view = 'active',
  }) async {
    final swStart = DateTime.now();
    try {
      final params = {...key.toQuery(), 'view': view};
      final uri = Uri.parse('$baseUrl/admin/arbeitstag_list.php')
          .replace(queryParameters: params);
      _log.info('[getPeriod] GET $uri', tag: 'ARBEITSTAG');
      final res = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 12));
      final dt = DateTime.now().difference(swStart).inMilliseconds;
      _log.info('[getPeriod] HTTP ${res.statusCode} in ${dt}ms body=${res.body.length}B', tag: 'ARBEITSTAG');
      if (res.statusCode != 200) {
        _log.error('arbeitstag getPeriod HTTP ${res.statusCode}', tag: 'ARBEITSTAG');
        return null;
      }
      final data = jsonDecode(res.body);
      if (data['success'] != true) return null;
      final result = ArbeitsbereichPeriod.fromJson(data);
      _log.info('[getPeriod] parsed ${result.members.length} members', tag: 'ARBEITSTAG');
      return result;
    } catch (e, st) {
      final dt = DateTime.now().difference(swStart).inMilliseconds;
      _log.error('arbeitstag getPeriod failed after ${dt}ms: $e\n$st', tag: 'ARBEITSTAG');
      return null;
    }
  }

  Future<List<ArbeitstagHistoryEntry>> getHistory({
    required int userId,
    ArbeitsbereichGranularity granularity = ArbeitsbereichGranularity.woche,
    int limit = 10,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/admin/arbeitstag_history.php').replace(queryParameters: {
        'user_id': userId.toString(),
        'granularity': granularity.wire,
        'limit': limit.toString(),
      });
      final res = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body);
      if (data['success'] != true) return [];
      final list = (data['entries'] as List?) ?? [];
      return list.map((j) => ArbeitstagHistoryEntry.fromJson(j)).toList();
    } catch (e) {
      _log.error('arbeitstag getHistory failed: $e', tag: 'ARBEITSTAG');
      return [];
    }
  }

  Future<bool> setNotiz({
    required PeriodKey key,
    required int userId,
    required String notiz,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/admin/arbeitstag_notiz.php');
      final body = {...key.toBody(), 'user_id': userId, 'notiz': notiz};
      final res = await _client
          .post(uri, headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return false;
      return jsonDecode(res.body)['success'] == true;
    } catch (e) {
      _log.error('arbeitstag setNotiz failed: $e', tag: 'ARBEITSTAG');
      return false;
    }
  }

  /// Archive/unarchive rămâne GLOBAL per membru (nu per period) — un membru
  /// arhivat dispare din toate view-urile (Tag/Woche/Monat).
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
    required PeriodKey key,
  }) async {
    try {
      final params = {...key.toQuery(), 'user_id': userId.toString(), 'typ': typ};
      final uri = Uri.parse('$baseUrl/admin/arbeitstag_picker.php')
          .replace(queryParameters: params);
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
    required PeriodKey key,
    required int userId,
    required String typ,
    required String state,
    int? refId,
    String? notiz,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/admin/arbeitstag_bearbeitet.php');
      final body = {
        ...key.toBody(),
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
