import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:icd360sev_vorsitzer/services/api_service.dart';
import 'package:icd360sev_vorsitzer/services/device_key_service.dart';

/// Was passiert, wenn ein Aufruf der SMS-Warteschlangen scheitert.
///
/// Anlass ist ein echter Fehler auf dem Vereins-Tablet: die Dauerbenachrichtigung
/// stand bei „seit 236 Versuchen keine Verbindung — Codes gehen nicht raus", und
/// im nginx-Log des Servers waren NULL Anfragen angekommen. Der Fehler flog im
/// Client, bevor eine Verbindung zustande kam: der Getter `ApiService._headers`
/// wirft, wenn kein Device-Key geladen ist, und er steht als Argument von
/// `post(...)` — also wird er ausgewertet, bevor `post` überhaupt betreten wird.
///
/// Zwei Regeln werden hier festgehalten:
/// 1. Ein Fehlschlag ist ein ERGEBNIS (`success: false`), keine Ausnahme. Sonst
///    reißt ein einzelner Wackler den ganzen Durchlauf des Wachdienstes mit.
/// 2. `message` benennt die Ursache. Genau das fehlte: „keine Verbindung" war
///    falsch, es gab nie einen Verbindungsversuch.
class _WerfenderClient extends http.BaseClient {
  final Object fehler;
  int versuche = 0;
  _WerfenderClient(this.fehler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    versuche++;
    throw fehler;
  }
}

/// Antwortet mit etwas, das kein JSON ist — der Fall, der schon immer sauber
/// behandelt wurde. Gegenprobe, dass die Naht wirklich greift.
class _MuellClient extends http.BaseClient {
  int versuche = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    versuche++;
    return http.StreamedResponse(
      Stream.value('<html>502 Bad Gateway</html>'.codeUnits),
      502,
    );
  }
}

void main() {
  final api = ApiService();

  // OHNE das hier ist der Device-Key in einem Test immer null, `_headers` wirft,
  // und JEDER dieser Tests wäre grün, ohne den HTTP-Client je erreicht zu haben.
  // Deshalb prüft unten zusätzlich jeder Fall `versuche`, statt sich auf
  // `success: false` allein zu verlassen.
  setUp(() {
    DeviceKeyService().setTestCredentials('TESTKEY');
  });

  group('SMS-Warteschlangen bei Netzfehlern', () {
    // Genau die Fehler, die auf einem Tablet im Hintergrund real vorkommen:
    // Mobilfunk bricht weg, TLS-Aufbau scheitert, Server antwortet nicht.
    final faelle = <String, ({Object fehler, String erwarteterText})>{
      'WLAN weg': (
        fehler: const SocketException('Network is unreachable'),
        erwarteterText: 'Kein Netz erreichbar',
      ),
      'TLS scheitert': (
        fehler: const HandshakeException('Handshake error in client'),
        erwarteterText: 'TLS-Verbindung abgelehnt',
      ),
      'Server antwortet nicht': (
        fehler: TimeoutException('20 s'),
        erwarteterText: 'Server antwortet nicht',
      ),
      'Verbindung bricht ab': (
        fehler: http.ClientException('Connection closed before full header'),
        erwarteterText: 'Verbindung abgebrochen',
      ),
    };

    for (final fall in faelle.entries) {
      test('${fall.key}: Ergebnis statt Ausnahme, mit benanntem Grund',
          () async {
        final client = _WerfenderClient(fall.value.fehler);
        api.testClient = client;

        final antwort = await api.getSignaturTanQueue();

        expect(client.versuche, 1,
            reason: 'Der Test muss den HTTP-Client wirklich erreichen. '
                'Steht hier 0, hat _headers geworfen und der Test wäre aus '
                'dem falschen Grund grün — genau der Fehler vom Tablet.');
        expect(antwort['success'], isFalse);
        expect(antwort['message'], contains(fall.value.erwarteterText),
            reason: 'Die Meldung muss die Ursache benennen, nicht „keine '
                'Verbindung" behaupten.');
      });
    }

    test('alle fünf Warteschlangen verhalten sich gleich', () async {
      api.testClient =
          _WerfenderClient(const SocketException('Network is unreachable'));

      for (final aufruf in <Future<Map<String, dynamic>> Function()>[
        api.getSignaturTanQueue,
        api.getTerminSmsQueue,
        api.getChatSmsOutbox,
        api.getMedikamentSmsQueue,
        api.getWetterSmsQueue,
      ]) {
        final antwort = await aufruf();
        expect(antwort['success'], isFalse);
        expect(antwort['message'], 'Kein Netz erreichbar');
      }
    });

    test('claim und report überleben einen Netzfehler ebenfalls', () async {
      api.testClient =
          _WerfenderClient(const SocketException('Network is unreachable'));

      final claim = await api.claimSignaturTan(deviceId: 'test', ids: const [1]);
      expect(claim['success'], isFalse);

      final report = await api.reportSignaturTan(id: 1, status: 'gesendet');
      expect(report['success'], isFalse);
    });

    test('Gegenprobe: kaputte Antwort nennt den HTTP-Status', () async {
      final client = _MuellClient();
      api.testClient = client;

      final antwort = await api.getSignaturTanQueue();

      expect(client.versuche, 1);
      expect(antwort['success'], isFalse);
      expect(antwort['message'], contains('502'));
    });
  });

  group('Der Fehler vom 31.07.2026 selbst', () {
    test('ohne Device-Key wird der Client nie erreicht — und die Meldung '
        'sagt genau das', () async {
      // Der Zustand im Isolate des Vordergrunddienstes: frische Singletons,
      // kein Device-Key, weil niemand ApiService().initialize() gerufen hat.
      DeviceKeyService().setTestCredentials(null);
      final client = _WerfenderClient(const SocketException('unbenutzt'));
      api.testClient = client;

      final antwort = await api.getSignaturTanQueue();

      expect(client.versuche, 0,
          reason: 'Beweis für die 0 Zeilen im nginx-Log: `headers: _headers` '
              'wird ausgewertet, bevor post() betreten wird.');
      expect(antwort['success'], isFalse);
      expect(antwort['message'],
          'Gerät in diesem Hintergrunddienst nicht angemeldet',
          reason: 'Statt „keine Verbindung" muss die Meldung die echte '
              'Ursache tragen.');
    });
  });
}
