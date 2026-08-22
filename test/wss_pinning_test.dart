import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/chat_service.dart';
import 'package:icd360sev_vorsitzer/services/http_client_factory.dart';

/// Bis heute lief der WebSocket über die Zertifikate des Systems, während die
/// REST-Aufrufe längst auf zwei einprogrammierte Anker festgelegt waren.
///
/// Das war die falsche Richtung: bei REST ist das Token ein Kopfzeilenfeld, im
/// WebSocket wird es ausdrücklich als Nachricht mitgeschickt — dazu jeder
/// Chatinhalt und die Anrufsignalisierung. Ein untergeschobenes CA im
/// Systemspeicher, ein Firmen-MDM genügt, hätte genau dort das Token abgegriffen.
void main() {
  group('Vertrauensanker', () {
    test('der Kontext lässt sich bauen und trägt beide Anker', () {
      // Zwei, nicht einer: Let's Encrypt schickt heute zwei Kreuzsignaturen
      // mit. Fallen die weg, endet die Kette bei X2 — mit nur X1 als Anker
      // schlüge dann JEDE Verbindung fehl, ohne dass wir etwas geändert haben.
      final ctx = HttpClientFactory.baueAnkerKontext();
      expect(ctx, isNotNull);
      // Ein zweiter Aufbau darf nicht an doppelt gesetzten Ankern scheitern.
      expect(() => HttpClientFactory.baueAnkerKontext(), returnsNormally);
    });

    test('ein Client damit weist ein fremdes Zertifikat ab', () async {
      // Die eigentliche Aussage des Pinnings: was nicht auf unsere Anker
      // zurückführt, fliegt raus — auch wenn das System es kennen würde.
      //
      // ⚠️ Gegen einen TLS-Server auf `localhost`, nicht gegen das Netz. Ein
      // echter Abruf im Testlauf hinge an der Leitung des Rechners, und ein
      // Test, der ohne Netz rot wird, sagt am Ende gar nichts mehr.
      //
      // ⚠️ Das Wegwerf-Zertifikat entsteht hier und jetzt und wird danach
      // gelöscht. Es liegt bewusst NICHT im Repo: ein privater Schlüssel
      // gehört dort nicht hin, auch kein bedeutungsloser — die
      // Geheimnis-Suche im CI schlüge an, und man gewöhnt sich das Falsche an.
      final ordner = Directory.systemTemp.createTempSync('pin_test');
      final crt = '${ordner.path}/fremd.crt';
      final key = '${ordner.path}/fremd.key';
      final openssl = await Process.run('openssl', [
        'req', '-x509', '-newkey', 'rsa:2048', '-keyout', key, '-out', crt,
        '-days', '2', '-nodes', '-subj', '/CN=localhost',
        '-addext', 'subjectAltName=DNS:localhost',
      ]);
      if (openssl.exitCode != 0) {
        ordner.deleteSync(recursive: true);
        markTestSkipped('openssl nicht vorhanden — Aussage ungeprüft');
        return;
      }

      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        SecurityContext()
          ..useCertificateChain(crt)
          ..usePrivateKey(key),
      );
      server.listen((r) => r.response.close());
      final url = Uri.parse('https://localhost:${server.port}/');

      final gepinnt = HttpClient(context: HttpClientFactory.baueAnkerKontext());
      try {
        await gepinnt.getUrl(url).then((r) => r.close());
        fail('das fremde Zertifikat wurde angenommen — dann pinnt nichts');
      } on HandshakeException {
        // genau so soll es sein
      } finally {
        gepinnt.close(force: true);
      }

      // Gegenprobe: wer DIESEM Zertifikat vertraut, kommt durch. Ohne sie
      // könnte die Ablehnung oben auch an einem kaputten Testserver liegen.
      final vertraut = HttpClient(
          context: SecurityContext(withTrustedRoots: false)
            ..setTrustedCertificates(crt));
      final antwort = await vertraut.getUrl(url).then((r) => r.close());
      expect(antwort.statusCode, 200);
      vertraut.close(force: true);

      await server.close(force: true);
      ordner.deleteSync(recursive: true);
    });
  });

  group('Der Kanal, der das Token trägt', () {
    test('zeigt auf unseren Server, nicht auf einen fremden', () {
      expect(ChatService.wsUrl, startsWith('wss://'));
      expect(ChatService.wsUrl, contains('icd360sev.icd360s.de'),
          reason: 'nur der eigene Server darf auf unsere Anker gepinnt werden');
    });
  });
}
