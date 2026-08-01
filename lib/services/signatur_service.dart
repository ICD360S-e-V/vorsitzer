import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'device_key_service.dart';
import 'http_client_factory.dart';
import 'logger_service.dart';

final _log = LoggerService();

/// Ein Unterschriftsvorgang, wie ihn der Reiter „Unterschriften" der
/// Mitgliederverwaltung zeigt.
///
/// Die Beweisfelder (IP, Gerät, TAN-Ziel, Hash-Kette) stecken bewusst NICHT
/// hier drin: die Liste lädt bei jedem Öffnen des Reiters, und das Bündel
/// gehört in die Detailansicht, die man bewusst aufruft.
class Signaturvorgang {
  final int id;
  final String dokumentTyp;
  final String dokumentTitel;

  /// offen | signiert | abgelehnt | abgelaufen | widerrufen
  final String status;

  final int? pdfSeiten;
  final DateTime? angefordertAt;
  final DateTime? fristBis;
  final DateTime? signedAtUtc;
  final DateTime? abgelehntAt;
  final String? abgelehntGrund;
  final DateTime? widerrufenAt;
  final String? verifyCode;

  /// Woher das Dokument stammt, wenn es aus einem Modul heraus gestellt wurde
  /// — etwa `korrespondenz_attachments` und die ID der abgelegten Datei.
  ///
  /// Damit findet die Herkunftsstelle ihren eigenen Vorgang wieder. Über den
  /// Dateinamen ginge es nicht: der ist je Antrag konstant, eine zweite
  /// Erzeugung trüge denselben, und die Zuordnung wäre geraten.
  final String? quelleTabelle;
  final int? quelleId;

  const Signaturvorgang({
    required this.id,
    required this.dokumentTyp,
    required this.dokumentTitel,
    required this.status,
    this.pdfSeiten,
    this.angefordertAt,
    this.fristBis,
    this.signedAtUtc,
    this.abgelehntAt,
    this.abgelehntGrund,
    this.widerrufenAt,
    this.verifyCode,
    this.quelleTabelle,
    this.quelleId,
  });

  /// Ob dieser Vorgang zu einer bestimmten Quelle gehört.
  bool stammtAus(String tabelle, int id) =>
      quelleTabelle == tabelle && quelleId == id;

  bool get istOffen => status == 'offen';
  bool get istSigniert => status == 'signiert';

  /// Eine Frist, die vorbei ist, während der Vorgang noch offen steht. Der
  /// Server setzt den Status erst beim nächsten Zugriff auf `abgelaufen` —
  /// bis dahin soll die Liste trotzdem die Wahrheit zeigen.
  bool get istUeberfaellig =>
      istOffen && fristBis != null && fristBis!.isBefore(DateTime.now().toUtc());

  static DateTime? _zeit(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString());

  factory Signaturvorgang.fromJson(Map<String, dynamic> j) => Signaturvorgang(
        id: j['id'] is int ? j['id'] : int.tryParse('${j['id']}') ?? 0,
        dokumentTyp: (j['dokument_typ'] ?? '').toString(),
        dokumentTitel: (j['dokument_titel'] ?? '').toString(),
        status: (j['status'] ?? 'offen').toString(),
        pdfSeiten: j['pdf_seiten'] is int
            ? j['pdf_seiten']
            : int.tryParse('${j['pdf_seiten']}'),
        angefordertAt: _zeit(j['angefordert_at']),
        fristBis: _zeit(j['frist_bis']),
        signedAtUtc: _zeit(j['signed_at_utc']),
        abgelehntAt: _zeit(j['abgelehnt_at']),
        abgelehntGrund: j['abgelehnt_grund']?.toString(),
        widerrufenAt: _zeit(j['widerrufen_at']),
        verifyCode: j['verify_code']?.toString(),
        quelleTabelle: (j['quelle_tabelle']?.toString().isEmpty ?? true)
            ? null
            : j['quelle_tabelle'].toString(),
        quelleId: j['quelle_id'] is int
            ? j['quelle_id']
            : int.tryParse('${j['quelle_id']}'),
      );
}

/// Der Vorsitzer-Zugang zur digitalen Unterschrift.
///
/// Anfordern und Nachlesen — mehr kann diese Seite nicht, und mehr darf sie
/// auch nicht können. Gäbe es hier einen Weg, eine Unterschrift zu setzen oder
/// nachträglich zu ändern, wäre der ganze Beweis wertlos: derjenige, der das
/// Dokument verlangt, könnte es sich selbst unterschreiben.
class SignaturService {
  static const String baseUrl = 'https://icd360sev.icd360s.de/api';

  late http.Client _client;
  final DeviceKeyService _deviceKeyService = DeviceKeyService();

  static final SignaturService _instance = SignaturService._internal();
  factory SignaturService() => _instance;
  SignaturService._internal() {
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

  Future<Map<String, dynamic>?> _post(String action, Map<String, dynamic> felder) async {
    try {
      final r = await _client
          .post(
            Uri.parse('$baseUrl/vorstand/signatur_manage.php'),
            headers: _headers,
            body: jsonEncode({'action': action, ...felder}),
          )
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(r.body);
      if (data is! Map) return null;
      return Map<String, dynamic>.from(data);
    } catch (e) {
      _log.error('SignaturService.$action: $e', tag: 'SIGNATUR');
      return null;
    }
  }

  /// Alle Vorgänge eines Mitglieds, neueste zuerst.
  Future<List<Signaturvorgang>> liste({
    required String callerMitgliedernummer,
    required int userId,
  }) async {
    final data = await _post('list', {
      'mitgliedernummer': callerMitgliedernummer,
      'user_id': userId,
    });
    if (data == null || data['success'] != true) return [];

    final roh = (data['signaturen'] as List?) ?? const [];
    return roh
        .map((e) => Signaturvorgang.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Das vollständige Beweisbündel eines Vorgangs — Zeit, Netz, Gerät,
  /// TAN-Ziel, Unterschrift und das Ergebnis der nachgerechneten Hash-Kette.
  Future<Map<String, dynamic>?> detail({
    required String callerMitgliedernummer,
    required int signaturId,
  }) async {
    final data = await _post('detail', {
      'mitgliedernummer': callerMitgliedernummer,
      'signatur_id': signaturId,
    });
    if (data == null || data['success'] != true) return null;
    final sig = data['signatur'];
    return sig is Map ? Map<String, dynamic>.from(sig) : null;
  }

  /// Ein PDF zur Unterschrift stellen.
  ///
  /// Der Upload läuft als multipart, weil die Datei mitgeht; der Server bildet
  /// den Hash über die Bytes, die bei ihm ankommen, nicht über das, was wir
  /// gesendet zu haben glauben.
  Future<({bool ok, String? fehler, int? signaturId})> anfordern({
    required String callerMitgliedernummer,
    required int userId,
    required String dokumentTyp,
    required String dokumentTitel,
    required String pdfPfad,
    DateTime? fristBis,
    String? quelleTabelle,
    int? quelleId,
  }) async =>
      _stellen(
        callerMitgliedernummer: callerMitgliedernummer,
        userId: userId,
        dokumentTyp: dokumentTyp,
        dokumentTitel: dokumentTitel,
        datei: await http.MultipartFile.fromPath('pdf', pdfPfad),
        fristBis: fristBis,
        quelleTabelle: quelleTabelle,
        quelleId: quelleId,
      );

  /// Wie [anfordern], nur mit dem PDF direkt aus dem Speicher.
  ///
  /// Gebraucht für Dokumente, die schon auf dem Server liegen und dort
  /// verschlüsselt sind — sie kommen entschlüsselt im RAM an. Sie erst über
  /// eine temporäre Datei zu schicken hieße, den Klartext auf die Platte zu
  /// legen, und das ausgerechnet für ein Dokument, dessen Unversehrtheit
  /// gleich beglaubigt werden soll.
  Future<({bool ok, String? fehler, int? signaturId})> anfordernAusBytes({
    required String callerMitgliedernummer,
    required int userId,
    required String dokumentTyp,
    required String dokumentTitel,
    required List<int> pdfBytes,
    required String dateiname,
    DateTime? fristBis,
    String? quelleTabelle,
    int? quelleId,
  }) async =>
      _stellen(
        callerMitgliedernummer: callerMitgliedernummer,
        userId: userId,
        dokumentTyp: dokumentTyp,
        dokumentTitel: dokumentTitel,
        datei: http.MultipartFile.fromBytes('pdf', pdfBytes, filename: dateiname),
        fristBis: fristBis,
        quelleTabelle: quelleTabelle,
        quelleId: quelleId,
      );

  Future<({bool ok, String? fehler, int? signaturId})> _stellen({
    required String callerMitgliedernummer,
    required int userId,
    required String dokumentTyp,
    required String dokumentTitel,
    required http.MultipartFile datei,
    DateTime? fristBis,
    String? quelleTabelle,
    int? quelleId,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/vorstand/signatur_manage.php'),
      );
      // Ohne Content-Type: das setzt MultipartRequest selbst inklusive
      // boundary, und ein handgesetztes application/json würde den Upload
      // beim Server als kaputtes JSON ankommen lassen.
      final deviceKey = _deviceKeyService.deviceKey;
      request.headers['User-Agent'] = 'ICD360S-Vorsitzer/1.0';
      if (deviceKey != null) request.headers['X-Device-Key'] = deviceKey;

      request.fields['action'] = 'anfordern';
      request.fields['mitgliedernummer'] = callerMitgliedernummer;
      request.fields['user_id'] = userId.toString();
      request.fields['dokument_typ'] = dokumentTyp;
      request.fields['dokument_titel'] = dokumentTitel;
      if (fristBis != null) {
        request.fields['frist_bis'] =
            fristBis.toUtc().toIso8601String().substring(0, 19).replaceFirst('T', ' ');
      }
      if (quelleTabelle != null && quelleId != null && quelleId > 0) {
        request.fields['quelle_tabelle'] = quelleTabelle;
        request.fields['quelle_id'] = quelleId.toString();
      }
      request.files.add(datei);

      final response = await _client.send(request).timeout(const Duration(seconds: 90));
      final body = await response.stream.bytesToString();
      final data = jsonDecode(body);

      if (data is Map && data['success'] == true) {
        return (ok: true, fehler: null, signaturId: data['signatur_id'] as int?);
      }
      return (
        ok: false,
        fehler: (data is Map ? data['message']?.toString() : null) ??
            'Anforderung fehlgeschlagen',
        signaturId: null,
      );
    } catch (e) {
      _log.error('SignaturService.anfordern: $e', tag: 'SIGNATUR');
      return (ok: false, fehler: 'Netzwerkfehler', signaturId: null);
    }
  }

  /// Lädt eine Fassung des Dokuments herunter.
  ///
  /// [welche] ist `original`, `signiert` oder `tsr`. Der Zeitstempel-Token
  /// gehört ausdrücklich dazu: wer die Unterschrift von dritter Seite prüfen
  /// lassen will, braucht PDF *und* Token — mit beiden rechnet jeder ohne
  /// unsere Mithilfe nach, ob das Dokument zum genannten Zeitpunkt so vorlag.
  Future<List<int>?> herunterladen({
    required String callerMitgliedernummer,
    required int signaturId,
    String welche = 'signiert',
  }) async {
    try {
      final r = await _client.get(
        Uri.parse('$baseUrl/vorstand/signatur_pdf.php'
            '?mitgliedernummer=$callerMitgliedernummer'
            '&id=$signaturId&which=$welche'),
        headers: _headers,
      ).timeout(const Duration(seconds: 60));

      // Der Server antwortet mit JSON, wenn es die Fassung noch nicht gibt —
      // die gesiegelte entsteht erst im Minutentakt. Das als PDF zu speichern
      // ergäbe eine kaputte Datei statt einer Erklärung.
      if (r.statusCode != 200 ||
          (r.headers['content-type'] ?? '').contains('json')) {
        return null;
      }
      return r.bodyBytes;
    } catch (e) {
      _log.error('SignaturService.herunterladen: $e', tag: 'SIGNATUR');
      return null;
    }
  }

  /// Eine noch offene Anforderung zurückziehen.
  Future<bool> widerrufen({
    required String callerMitgliedernummer,
    required int signaturId,
    String grund = '',
  }) async {
    final data = await _post('widerrufen', {
      'mitgliedernummer': callerMitgliedernummer,
      'signatur_id': signaturId,
      'grund': grund,
    });
    return data != null && data['success'] == true;
  }
}
