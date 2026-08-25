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

  group('Der Anschluss hinter der Adresse', () {
    // 🔴 Der Befund vom 25.08.2026: seit dem Pinning des WebSockets stand im
    // Kopf des Live-Chats „Offline", und Anruf- und Videoknopf fehlten — beide
    // hängen an derselben Fahne. Auf dem Telefon wie auf dem Linux-Rechner,
    // jeder Versuch nach genau 15,05 s mit
    // `SocketException: Connection timed out, host: …, port: 0`.
    test('Uri kennt für wss KEINEN Standardanschluss', () {
      // Die Wurzel des Ganzen, und nichts, was wir uns ausgedacht haben.
      expect(Uri.parse(ChatService.wsUrl).port, 0,
          reason: 'ändert Dart das je, darf der Rest hier trotzdem stimmen');
      expect(Uri.parse('https://icd360sev.icd360s.de/api/x.php').port, 443,
          reason: 'deshalb blieben die REST-Aufrufe heil');
    });

    test('die vom Aufstieg umgeschriebene Adresse führt auf 443', () {
      // Genau die Umschreibung aus `_WebSocketImpl.connect`: Schema auf https,
      // Anschluss wörtlich übernommen. Nicht nachgetippt, sondern nachgebaut,
      // damit der Test die Stelle beschreibt statt ein Ergebnis zu behaupten.
      final roh = Uri.parse(ChatService.wsUrl);
      final umgeschrieben = Uri(
        scheme: roh.isScheme('wss') ? 'https' : 'http',
        host: roh.host,
        port: roh.port,
        path: roh.path,
      );
      expect(umgeschrieben.port, 0, reason: 'so kommt sie beim HttpClient an');
      expect(HttpClientFactory.zielPort(umgeschrieben), 443);
    });

    test('ein ausdrücklicher Anschluss bleibt unangetastet', () {
      // Sonst würde die Reparatur einen Zwischenrechner oder einen Testserver
      // auf einem eigenen Anschluss stillschweigend auf 443 umbiegen.
      expect(HttpClientFactory.zielPort(Uri.parse('https://localhost:8443/')), 8443);
      expect(HttpClientFactory.zielPort(Uri.parse('http://localhost:8080/')), 8080);
    });

    test('unverschlüsselt fällt auf 80, nicht auf 443', () {
      expect(HttpClientFactory.zielPort(Uri.parse('http://example.org/')), 80);
      expect(HttpClientFactory.zielPort(Uri.parse('ws://example.org/')), 80);
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
