import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/spki_pin.dart';

/// Bis zum 22.08.2026 hing die App an den WURZELN von Let's Encrypt. OWASP
/// nennt genau das nicht empfehlenswert — praktisch hiess es: jedes
/// Let's-Encrypt-Zertifikat für unseren Namen wurde angenommen, und die stellt
/// Let's Encrypt jedem aus, der Kontrolle über DNS oder Port 80 nachweist.
///
/// ⚠️ Diese Proben laufen ohne Netz. Der Live-Abgleich gegen den echten Server
/// steht im Merge-Antrag; ein Test, der ohne Leitung rot wird, sagt am Ende
/// nichts mehr.
void main() {
  group('Die Pinliste', () {
    test('trägt zwei Einträge — den zweiten braucht es wirklich', () {
      // Ohne Reservepin waeren beim naechsten erzwungenen Schluesselwechsel
      // ALLE Geraete gleichzeitig draussen, und die einzige Rettung waere eine
      // neue Fassung. Mit Reserve stellt man das Zertifikat auf den zweiten
      // Schluessel aus und niemand merkt etwas.
      expect(spkiPins.length, 2);
      expect(spkiPins.toSet().length, 2, reason: 'zweimal derselbe wäre keiner');
    });

    test('jeder Pin ist ein SHA-256 in base64', () {
      for (final p in spkiPins) {
        final roh = base64.decode(p);
        expect(roh.length, 32, reason: 'bei: $p');
      }
    });

    test('gepinnt wird genau ein Rechnername', () {
      // ⚠️ Nachgemessen: `turn.icd360s.de` liegt auf derselben Maschine, hat
      // aber ein eigenes Zertifikat mit eigenem Schluessel (Pin Zw7rDD…).
      // Gaelte der Pin auch dort, braeche TURN sofort.
      expect(spkiHost, 'icd360sev.icd360s.de');
      expect(spkiHost, isNot(contains('turn')));
      expect(spkiHost, isNot(contains('mail')));
    });
  });

  group('Prüfung', () {
    test('ohne Zertifikat wird abgewiesen, nicht durchgewunken', () {
      expect(spkiPinVon(null), isNull);
      expect(spkiPasst(null), isFalse);
    });

    test('eine leere Pinliste lässt nichts durch', () {
      expect(spkiPasst(null, pins: const []), isFalse);
    });
  });

  group('Der SPKI wird nach Gestalt gefunden, nicht nach Position', () {
    test('gegen ein selbst erzeugtes Zertifikat', () async {
      // Ein Wegwerf-Zertifikat, zur Laufzeit erzeugt und danach geloescht —
      // ein privater Schluessel gehoert nicht ins Repo. Geprueft wird, dass
      // unsere Extraktion denselben Wert liefert wie openssl.
      final ordner = Directory.systemTemp.createTempSync('spki_test');
      final crt = '${ordner.path}/t.crt';
      final key = '${ordner.path}/t.key';
      final erzeugt = await Process.run('openssl', [
        'req', '-x509', '-newkey', 'rsa:2048', '-keyout', key, '-out', crt,
        '-days', '2', '-nodes', '-subj', '/CN=probe',
      ]);
      if (erzeugt.exitCode != 0) {
        ordner.deleteSync(recursive: true);
        markTestSkipped('openssl nicht vorhanden');
        return;
      }

      // openssl rechnet den Vergleichswert.
      final pub = await Process.run('sh', [
        '-c',
        'openssl x509 -in $crt -pubkey -noout | openssl pkey -pubin -outform DER '
            '| openssl dgst -sha256 -binary | base64'
      ]);
      final erwartet = (pub.stdout as String).trim();

      // Und unsere Extraktion rechnet ihn auch — über einen echten TLS-Server,
      // weil `X509Certificate` sich nicht von Hand bauen lässt.
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        SecurityContext()
          ..useCertificateChain(crt)
          ..usePrivateKey(key),
      );
      server.listen((r) => r.response.close());
      final sock = await SecureSocket.connect(
        InternetAddress.loopbackIPv4.address,
        server.port,
        onBadCertificate: (_) => true, // selbstsigniert, hier egal
      );
      final unser = spkiPinVon(sock.peerCertificate);
      sock.destroy();
      await server.close(force: true);
      ordner.deleteSync(recursive: true);

      expect(unser, erwartet,
          reason: 'unsere ASN.1-Suche muss dasselbe finden wie openssl');
      expect(spkiPasst(null, pins: [erwartet]), isFalse);
    });
  });
}
