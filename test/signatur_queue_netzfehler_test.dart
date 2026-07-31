import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:icd360sev_vorsitzer/services/api_service.dart';

/// Was passiert, wenn das Netz wegbricht, während der Wachdienst die
/// TAN-Warteschlange abfragt.
///
/// Anlass ist ein echter Fehler auf dem Vereins-Tablet: die Dauerbenachrichtigung
/// stand bei „seit 236 Versuchen keine Verbindung — Codes gehen nicht raus", und
/// im nginx-Log des Servers waren NULL Anfragen angekommen. Der Fehler flog also
/// im Client, bevor eine Verbindung zustande kam — und riss jeden einzelnen
/// Durchlauf des Dienstes mit.
///
/// Die Regel, die hier festgehalten wird: ein Netzfehler ist ein ERGEBNIS,
/// keine Ausnahme. Er muss als `success: false` zurückkommen, so wie es bei
/// kaputtem JSON längst der Fall ist. Sonst kann eine einzelne Funklücke einen
/// Hintergrunddienst dauerhaft in den Fehlerzustand kippen, aus dem er sich
/// nicht mehr erholt.
class _WerfenderClient extends http.BaseClient {
  final Object fehler;
  _WerfenderClient(this.fehler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw fehler;
  }
}

/// Antwortet mit etwas, das kein JSON ist — der Fall, der bereits sauber
/// behandelt wird. Dient als Gegenprobe: die Naht selbst funktioniert.
class _MuellClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.value('<html>502 Bad Gateway</html>'.codeUnits),
      502,
    );
  }
}

void main() {
  final api = ApiService();

  group('TAN-Warteschlange bei Netzfehlern', () {
    // Genau die Fehler, die auf einem Tablet im Hintergrund real vorkommen:
    // WLAN schläft ein, Mobilfunk bricht weg, TLS-Aufbau scheitert, Server
    // antwortet nicht rechtzeitig.
    final faelle = <String, Object>{
      'WLAN weg (SocketException)':
          const SocketException('Network is unreachable'),
      'TLS scheitert (HandshakeException)':
          const HandshakeException('Handshake error in client'),
      'Server antwortet nicht (TimeoutException)':
          TimeoutException20(),
      'Client bricht ab (ClientException)':
          http.ClientException('Connection closed before full header'),
    };

    for (final fall in faelle.entries) {
      test('${fall.key}: liefert success=false statt zu werfen', () async {
        api.testClient = _WerfenderClient(fall.value);

        final antwort = await api.getSignaturTanQueue();

        expect(antwort['success'], isFalse,
            reason: 'Ein Netzfehler muss als Ergebnis ankommen, nicht als '
                'Ausnahme — sonst reisst er den ganzen Durchlauf des '
                'Wachdienstes mit.');
      });
    }

    test('auch claim und report ueberleben einen Netzfehler', () async {
      api.testClient = _WerfenderClient(
          const SocketException('Network is unreachable'));

      final claim = await api.claimSignaturTan(deviceId: 'test', ids: const [1]);
      expect(claim['success'], isFalse);

      final report = await api.reportSignaturTan(id: 1, status: 'gesendet');
      expect(report['success'], isFalse);
    });

    test('Gegenprobe: kaputte Antwort wird weiterhin sauber gemeldet',
        () async {
      api.testClient = _MuellClient();

      final antwort = await api.getSignaturTanQueue();

      expect(antwort['success'], isFalse);
    });
  });
}

/// `TimeoutException` aus dart:async, ohne den Import zu verschatten.
class TimeoutException20 implements Exception {
  @override
  String toString() => 'TimeoutException after 0:00:20.000000';
}
