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
}
