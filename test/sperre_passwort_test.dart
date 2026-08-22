import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/sperre_passwort.dart';

void main() {
  group('Passwort erzeugen und prüfen', () {
    test('das richtige Passwort passt, ein falsches nicht', () async {
      final p = await sperrePasswortErzeugen('Mein-App-Passwort-1');
      expect(await sperrePasswortPruefen(p, 'Mein-App-Passwort-1'), isTrue);
      expect(await sperrePasswortPruefen(p, 'Mein-App-Passwort-2'), isFalse);
      expect(await sperrePasswortPruefen(p, ''), isFalse);
      expect(await sperrePasswortPruefen(p, 'mein-app-passwort-1'), isFalse,
          reason: 'Groß- und Kleinschreibung zählt');
    });

    test('ohne abgelegten Wert passt NICHTS', () async {
      // Der wichtigste Fall: ein kaputter oder fehlender Datensatz darf nicht
      // dazu führen, dass jede Eingabe durchgeht.
      expect(await sperrePasswortPruefen(null, ''), isFalse);
      expect(await sperrePasswortPruefen(null, 'irgendwas'), isFalse);
    });

    test('zweimal dasselbe Passwort ergibt verschiedene Hashes', () async {
      // Eigenes Salz je Eintrag — sonst verriete ein Vergleich zweier Geräte,
      // dass dort dasselbe Passwort benutzt wird.
      final a = await sperrePasswortErzeugen('gleich');
      final b = await sperrePasswortErzeugen('gleich');
      expect(a.salz, isNot(equals(b.salz)));
      expect(a.hash, isNot(equals(b.hash)));
      expect(await sperrePasswortPruefen(a, 'gleich'), isTrue);
      expect(await sperrePasswortPruefen(b, 'gleich'), isTrue);
    });

    test('Umlaute und Leerzeichen überleben', () async {
      const pw = 'Grüße aus Ülm — mit Leerzeichen';
      final p = await sperrePasswortErzeugen(pw);
      expect(await sperrePasswortPruefen(p, pw), isTrue);
      expect(await sperrePasswortPruefen(p, pw.trim()), isTrue);
    });
  });

  group('Ablage als JSON', () {
    test('Rundlauf verändert nichts', () async {
      final p = await sperrePasswortErzeugen('rundlauf');
      final zurueck = SperrePasswort.ausJson(p.alsJson());
      expect(zurueck, isNotNull);
      expect(zurueck!.salz, p.salz);
      expect(zurueck.hash, p.hash);
      expect(zurueck.runden, p.runden);
      expect(await sperrePasswortPruefen(zurueck, 'rundlauf'), isTrue);
    });

    test('kaputte Ablage ergibt null, nicht einen leeren Treffer', () async {
      for (final roh in [
        null, '', '   ', 'kein json', '{}', '{"salz":"!!","hash":"x"}',
        '{"salz":"","hash":"","runden":120000}',
        '{"salz":"AAAA","hash":"AAAA","runden":1}', // absurd wenige Runden
      ]) {
        final p = SperrePasswort.ausJson(roh);
        expect(p, isNull, reason: 'bei: $roh');
        expect(await sperrePasswortPruefen(p, 'egal'), isFalse);
      }
    });

    test('die Rundenzahl kommt aus dem Datensatz, nicht aus der Konstanten',
        () async {
      // Sonst würden beim nächsten Anheben alle bestehenden Passwörter
      // ungültig und niemand käme mehr hinein.
      final p = await sperrePasswortErzeugen('alt');
      final j = jsonDecode(p.alsJson()) as Map<String, dynamic>;
      expect(j['runden'], sperreRunden);
      final mitAndererZahl = SperrePasswort.ausJson(
          jsonEncode({...j, 'runden': p.runden}));
      expect(await sperrePasswortPruefen(mitAndererZahl, 'alt'), isTrue);
    });
  });

  group('Wartestaffel bei Fehlversuchen', () {
    test('die ersten vier Versuche kosten nichts', () {
      for (var i = 0; i <= 4; i++) {
        expect(sperreWartezeit(i), Duration.zero, reason: '$i Versuche');
      }
    });

    test('ab dem fünften wird gewartet, und es wird mehr', () {
      final a = sperreWartezeit(5);
      final b = sperreWartezeit(6);
      final c = sperreWartezeit(7);
      expect(a, greaterThan(Duration.zero));
      expect(b, greaterThan(a));
      expect(c, greaterThan(b));
    });

    test('gedeckelt bei fünf Minuten — kein Aussperren für immer', () {
      // Wer sein Passwort wirklich weiss, soll nach einer Tippfehlerserie
      // nicht stundenlang draussen stehen.
      for (final n in [20, 100, 10000]) {
        expect(sperreWartezeit(n), lessThanOrEqualTo(const Duration(minutes: 5)),
            reason: '$n Versuche');
      }
    });
  });

  group('Vorgaben', () {
    test('Rundenzahl ist gemessen gewählt, nicht geraten', () {
      // 310 000 (wie CloudCrypto) brauchte auf dem Entwicklungsrechner 1329 ms
      // und auf einem Tablet ein Vielfaches davon — mehrmals täglich.
      expect(sperreRunden, 120000);
      expect(sperreRunden, greaterThanOrEqualTo(100000),
          reason: 'nicht unter das Vertretbare fallen');
    });

    test('Mindestlänge steht auf Länge statt auf Zeichenklassen', () {
      expect(sperreMindestlaenge, greaterThanOrEqualTo(8));
    });
  });
}
