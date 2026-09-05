import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icd360sev_vorsitzer/services/api_service.dart';
import 'package:icd360sev_vorsitzer/services/device_key_service.dart';
import 'package:icd360sev_vorsitzer/services/ticket_service.dart';

/// Bis zum 31.08.2026 schickte `TicketService` **kein** `Authorization` mit —
/// seine Kopfzeilen kannten nur Content-Type, User-Agent und `X-Device-Key`.
///
/// Solange die Ticket-Endpunkte allein `validateApiKey()` hatten, fiel das
/// nicht auf: ein lebender Geräteschlüssel genügte. Am 30.08.2026 bekamen
/// `tickets/admin_list.php` und `tickets/admin_create.php` eine Rollenprüfung,
/// und die verlangt einen Bearer. Ab 18:40 Uhr antwortete der Server auf jeden
/// Aufruf mit **401 „Missing Authorization header"** — die Ticketverwaltung
/// zeigte keine Tickets mehr an und konnte keine anlegen.
///
/// ⚠️ Das PHP liegt in keinem Repo. Diese Datei ist damit die einzige Stelle
/// im Baum, an der die Kopplung „Endpunkt fragt nach der Rolle ↔ Client
/// schickt ein Token" überhaupt auffallen kann.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('ticket_bearer');
    for (final kanal in [
      'plugins.flutter.io/path_provider',
      'plugins.flutter.io/path_provider_linux',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              MethodChannel(kanal), (call) async => tempDir.path);
    }
    DeviceKeyService().setTestCredentials('GERAETESCHLUESSEL');
  });

  tearDown(() async {
    await ApiService().clearTokens();
    DeviceKeyService().setTestCredentials(null);
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Fängt die Kopfzeilen des nächsten Aufrufs ab und antwortet freundlich.
  Map<String, String> lauschen(String rumpf) {
    final gesehen = <String, String>{};
    TicketService().testClient = MockClient((anfrage) async {
      gesehen.addAll(anfrage.headers);
      return http.Response(rumpf, 200,
          headers: {'content-type': 'application/json'});
    });
    return gesehen;
  }

  test('admin_list bekommt den Bearer — der Fehler vom 30.08.2026', () async {
    await ApiService().saveTokens('DAS-TOKEN', 'DER-REFRESH');
    final kopf = lauschen(jsonEncode({
      'success': true,
      'tickets': <dynamic>[],
      'stats': {
        'total': 0,
        'open': 0,
        'in_progress': 0,
        'closed': 0,
      },
    }));

    await TicketService().getAdminTickets('V10001');

    expect(kopf['Authorization'], 'Bearer DAS-TOKEN',
        reason: 'ohne diesen Kopf antwortet admin_list.php mit 401');
    // Der Geräteschlüssel bleibt daneben stehen — validateApiKey() verlangt
    // ihn weiterhin auf jedem einzelnen Aufruf.
    expect(kopf['X-Device-Key'], 'GERAETESCHLUESSEL');
  });

  test('admin_create bekommt den Bearer', () async {
    await ApiService().saveTokens('DAS-TOKEN', 'DER-REFRESH');
    final kopf = lauschen(jsonEncode({'success': false, 'message': 'egal'}));

    await TicketService().createTicketForMember(
      adminMitgliedernummer: 'V10001',
      memberMitgliedernummer: 'M12345',
      subject: 'Betreff',
      message: 'Text',
      scheduledDate: '2026-09-01',
    );

    expect(kopf['Authorization'], 'Bearer DAS-TOKEN');
  });

  test('ohne Token steht KEIN Authorization da', () async {
    // „Bearer null" wäre schlimmer als gar nichts: der Server würde es als
    // ungültiges Token abweisen, statt auf den Geräteschlüssel zurückzufallen.
    final kopf = lauschen(jsonEncode({'success': true, 'tickets': <dynamic>[]}));

    await TicketService().getTickets('V10001');

    expect(kopf.containsKey('Authorization'), isFalse);
    expect(kopf['X-Device-Key'], 'GERAETESCHLUESSEL');
  });

  test('auch der Datei-Upload trägt den Bearer', () async {
    // ⚠️ MultipartRequest baut seine Kopfzeilen von Hand und bekommt
    // `_headers` nicht ab. Genau daran ist am 30.08.2026 schon
    // platform/korrespondenz_create.php zerbrochen.
    await ApiService().saveTokens('DAS-TOKEN', 'DER-REFRESH');
    final datei = File('${tempDir.path}/anhang.txt')..writeAsStringSync('x');
    final kopf = lauschen(jsonEncode({'success': false}));

    await TicketService().uploadAttachment(
      mitgliedernummer: 'V10001',
      ticketId: 1,
      filePath: datei.path,
    );

    expect(kopf['Authorization'], 'Bearer DAS-TOKEN');
    expect(kopf['X-Device-Key'], 'GERAETESCHLUESSEL');
  });

  test('kein Aufruf baut seine Kopfzeilen an `_headers` vorbei', () {
    // Die vier Prüfungen oben decken vier Aufrufe ab; die Datei hat über
    // dreissig. Diese hier fängt den nächsten, der von Hand gebaut wird —
    // das ist die Form, in der der Fehler beide Male aufgetreten ist.
    final quelle = File('lib/services/ticket_service.dart').readAsStringSync();

    final vonHand = RegExp(r"headers:\s*\{").allMatches(quelle);
    expect(vonHand, isEmpty,
        reason: 'Kopfzeilen gehören über `_headers`, nicht als Literal — '
            'sonst fehlt beim nächsten Rollen-Tor wieder der Bearer');

    // Und jeder Multipart-Aufbau muss den Kopf selbst setzen.
    final multipart = RegExp(r'MultipartRequest\(').allMatches(quelle).length;
    final gesetzt =
        RegExp(r"request\.headers\['Authorization'\]").allMatches(quelle).length;
    expect(gesetzt, multipart,
        reason: '$multipart MultipartRequest, aber $gesetzt setzen '
            'Authorization');
  });
}
