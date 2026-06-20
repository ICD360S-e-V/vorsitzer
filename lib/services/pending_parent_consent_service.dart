import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'device_key_service.dart';
import 'http_client_factory.dart';
import 'logger_service.dart';

final _log = LoggerService();

/// Minor (16-17 yo) who started the Mitglieder onboarding wizard and is
/// now waiting for their parent / Sorgeberechtigter to be contacted
/// and linked by the Vorstand. Server-side state lives on
/// users.status='waiting_for_parent_consent' + users.parent_hint_*.
class PendingParentConsent {
  final int id;
  final String mitgliedernummer;
  final String vorname;
  final String nachname;
  final String? geburtsdatum;
  final String? parentVorname;
  final String? parentNachname;
  final String? parentTelefon;
  final String? parentRelation; // mutter | vater | sorgeberechtigter | andere
  final DateTime? parentHintCreatedAt;
  final int daysWaiting;
  final int age;
  final int callsLogged;

  PendingParentConsent({
    required this.id,
    required this.mitgliedernummer,
    required this.vorname,
    required this.nachname,
    this.geburtsdatum,
    this.parentVorname,
    this.parentNachname,
    this.parentTelefon,
    this.parentRelation,
    this.parentHintCreatedAt,
    this.daysWaiting = 0,
    this.age = 0,
    this.callsLogged = 0,
  });

  factory PendingParentConsent.fromJson(Map<String, dynamic> j) {
    return PendingParentConsent(
      id: j['id'] is int ? j['id'] : int.parse(j['id'].toString()),
      mitgliedernummer: (j['mitgliedernummer'] ?? '').toString(),
      vorname: (j['vorname'] ?? '').toString(),
      nachname: (j['nachname'] ?? '').toString(),
      geburtsdatum: j['geburtsdatum']?.toString(),
      parentVorname: j['parent_hint_vorname']?.toString(),
      parentNachname: j['parent_hint_nachname']?.toString(),
      parentTelefon: j['parent_hint_telefon']?.toString(),
      parentRelation: j['parent_hint_relation']?.toString(),
      parentHintCreatedAt: j['parent_hint_created_at'] != null
          ? DateTime.tryParse(j['parent_hint_created_at'].toString())
          : null,
      daysWaiting: j['days_waiting'] is int ? j['days_waiting'] : int.tryParse('${j['days_waiting']}') ?? 0,
      age: j['age'] is int ? j['age'] : int.tryParse('${j['age']}') ?? 0,
      callsLogged: j['calls_logged'] is int ? j['calls_logged'] : int.tryParse('${j['calls_logged']}') ?? 0,
    );
  }

  String get childFullName => [vorname, nachname].where((s) => s.isNotEmpty).join(' ');
  String get parentFullName => [parentVorname, parentNachname].where((s) => s != null && s!.isNotEmpty).join(' ');

  String get relationLabel {
    switch (parentRelation) {
      case 'mutter':
        return 'Mutter';
      case 'vater':
        return 'Vater';
      case 'sorgeberechtigter':
        return 'Sorgeberechtigte/r';
      case 'andere':
        return 'Andere';
      default:
        return parentRelation ?? '—';
    }
  }
}

class PendingParentConsentService {
  static const String baseUrl = 'https://icd360sev.icd360s.de/api';

  late http.Client _client;
  final DeviceKeyService _deviceKeyService = DeviceKeyService();

  static final PendingParentConsentService _instance =
      PendingParentConsentService._internal();
  factory PendingParentConsentService() => _instance;
  PendingParentConsentService._internal() {
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

  Future<List<PendingParentConsent>> list({required String callerMitgliedernummer}) async {
    try {
      final r = await _client.post(
        Uri.parse('$baseUrl/vorstand/pending_parent_consent.php'),
        headers: _headers,
        body: jsonEncode({'mitgliedernummer': callerMitgliedernummer}),
      ).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return [];
      final data = jsonDecode(r.body);
      if (data is! Map || data['success'] != true) return [];
      final items = (data['items'] as List?) ?? [];
      return items.map((j) => PendingParentConsent.fromJson(Map<String, dynamic>.from(j as Map))).toList();
    } catch (e) {
      _log.error('PendingParentConsentService.list: $e', tag: 'PARENT-CONSENT');
      return [];
    }
  }

  // ── Call log ──

  Future<List<ParentCallLogEntry>> listCalls({
    required String callerMitgliedernummer,
    required int childUserId,
  }) async {
    try {
      final r = await _client.post(
        Uri.parse('$baseUrl/vorstand/parent_call_log.php'),
        headers: _headers,
        body: jsonEncode({
          'action': 'list',
          'mitgliedernummer': callerMitgliedernummer,
          'child_user_id': childUserId,
        }),
      ).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return [];
      final data = jsonDecode(r.body);
      if (data is! Map || data['success'] != true) return [];
      final items = (data['items'] as List?) ?? [];
      return items.map((j) => ParentCallLogEntry.fromJson(Map<String, dynamic>.from(j as Map))).toList();
    } catch (e) {
      _log.error('PendingParentConsentService.listCalls: $e', tag: 'PARENT-CONSENT');
      return [];
    }
  }

  Future<bool> logCall({
    required String callerMitgliedernummer,
    required int childUserId,
    required String result,
    int durationMin = 0,
    String? meetingScheduledAt,
    String? note,
  }) async {
    try {
      final r = await _client.post(
        Uri.parse('$baseUrl/vorstand/parent_call_log.php'),
        headers: _headers,
        body: jsonEncode({
          'action': 'create',
          'mitgliedernummer': callerMitgliedernummer,
          'child_user_id': childUserId,
          'result': result,
          'duration_min': durationMin,
          if (meetingScheduledAt != null) 'meeting_scheduled_at': meetingScheduledAt,
          if (note != null && note.isNotEmpty) 'note': note,
        }),
      ).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return false;
      final data = jsonDecode(r.body);
      return data is Map && data['success'] == true;
    } catch (e) {
      _log.error('PendingParentConsentService.logCall: $e', tag: 'PARENT-CONSENT');
      return false;
    }
  }

  // ── Parent search + link (re-uses /api/admin/admin_vormund_link.php) ──

  Future<List<Map<String, dynamic>>> searchParent(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final r = await _client.get(
        Uri.parse('$baseUrl/admin/admin_vormund_link.php?action=search&q=${Uri.encodeQueryComponent(query)}'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return [];
      final data = jsonDecode(r.body);
      if (data is! Map || data['success'] != true) return [];
      final items = (data['results'] as List?) ?? (data['members'] as List?) ?? [];
      return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      _log.error('PendingParentConsentService.searchParent: $e', tag: 'PARENT-CONSENT');
      return [];
    }
  }

  /// Derive vormund_typ from parent_hint_relation. mutter/vater/
  /// sorgeberechtigter → 'sorgeberechtigter'; andere → 'familienangehoeriger'.
  static String deriveVormundTyp(String? relation) {
    switch (relation) {
      case 'mutter':
      case 'vater':
      case 'sorgeberechtigter':
        return 'sorgeberechtigter';
      default:
        return 'familienangehoeriger';
    }
  }

  Future<Map<String, dynamic>?> linkExistingParent({
    required int childUserId,
    required int parentUserId,
    required String vormundTyp,
    bool forceOverwrite = false,
  }) async {
    try {
      final r = await _client.post(
        Uri.parse('$baseUrl/admin/admin_vormund_link.php'),
        headers: _headers,
        body: jsonEncode({
          'action': 'link_existing',
          'target_user_id': childUserId,
          'vormund_user_id': parentUserId,
          'vormund_typ': vormundTyp,
          if (forceOverwrite) 'force_overwrite': true,
        }),
      ).timeout(const Duration(seconds: 15));
      final data = jsonDecode(r.body);
      if (data is! Map) return null;
      return Map<String, dynamic>.from(data);
    } catch (e) {
      _log.error('PendingParentConsentService.linkExistingParent: $e', tag: 'PARENT-CONSENT');
      return null;
    }
  }

  // ── Signature inspect + validate / reject ──

  Future<Map<String, dynamic>?> getSignature({
    required String callerMitgliedernummer,
    required int childUserId,
  }) async {
    try {
      final r = await _client.post(
        Uri.parse('$baseUrl/vorstand/get_parent_signature.php'),
        headers: _headers,
        body: jsonEncode({
          'mitgliedernummer': callerMitgliedernummer,
          'child_user_id': childUserId,
        }),
      ).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return null;
      final data = jsonDecode(r.body);
      if (data is! Map || data['success'] != true) return null;
      return Map<String, dynamic>.from(data);
    } catch (e) {
      _log.error('PendingParentConsentService.getSignature: $e', tag: 'PARENT-CONSENT');
      return null;
    }
  }

  Future<bool> validateSignature({
    required String callerMitgliedernummer,
    required int signatureId,
  }) async {
    try {
      final r = await _client.post(
        Uri.parse('$baseUrl/vorstand/validate_parent_signature.php'),
        headers: _headers,
        body: jsonEncode({
          'mitgliedernummer': callerMitgliedernummer,
          'signature_id': signatureId,
        }),
      ).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return false;
      final data = jsonDecode(r.body);
      return data is Map && data['success'] == true;
    } catch (e) {
      _log.error('PendingParentConsentService.validateSignature: $e', tag: 'PARENT-CONSENT');
      return false;
    }
  }

  Future<bool> rejectSignature({
    required String callerMitgliedernummer,
    required int signatureId,
    required String reason,
  }) async {
    try {
      final r = await _client.post(
        Uri.parse('$baseUrl/vorstand/reject_parent_signature.php'),
        headers: _headers,
        body: jsonEncode({
          'mitgliedernummer': callerMitgliedernummer,
          'signature_id': signatureId,
          'reason': reason,
        }),
      ).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return false;
      final data = jsonDecode(r.body);
      return data is Map && data['success'] == true;
    } catch (e) {
      _log.error('PendingParentConsentService.rejectSignature: $e', tag: 'PARENT-CONSENT');
      return false;
    }
  }
}

class ParentCallLogEntry {
  final int id;
  final DateTime? calledAt;
  final int durationMin;
  final String result;
  final DateTime? meetingScheduledAt;
  final String? note;
  final String? calledByName;

  ParentCallLogEntry({
    required this.id,
    this.calledAt,
    this.durationMin = 0,
    required this.result,
    this.meetingScheduledAt,
    this.note,
    this.calledByName,
  });

  factory ParentCallLogEntry.fromJson(Map<String, dynamic> j) => ParentCallLogEntry(
        id: j['id'] is int ? j['id'] : int.parse(j['id'].toString()),
        calledAt: j['called_at'] != null ? DateTime.tryParse(j['called_at'].toString()) : null,
        durationMin: j['duration_min'] is int ? j['duration_min'] : int.tryParse('${j['duration_min']}') ?? 0,
        result: (j['result'] ?? '').toString(),
        meetingScheduledAt: j['meeting_scheduled_at'] != null ? DateTime.tryParse(j['meeting_scheduled_at'].toString()) : null,
        note: j['note']?.toString(),
        calledByName: j['called_by_name']?.toString(),
      );

  String get resultLabel {
    switch (result) {
      case 'stabilit_intalnire':
        return 'Termin vereinbart';
      case 'stabilit_videoapel':
        return 'Videoanruf vereinbart';
      case 'refuz':
        return 'Abgelehnt';
      case 'nu_raspunde':
        return 'Nicht erreicht';
      case 'gresit_numar':
        return 'Falsche Nummer';
      default:
        return result;
    }
  }
}
