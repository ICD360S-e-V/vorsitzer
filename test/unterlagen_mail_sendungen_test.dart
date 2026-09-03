import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/models/mail_models.dart';
import 'package:icd360sev_vorsitzer/utils/mail_sendungen.dart';

/// Prüft die Aufteilung der Unterlagen auf mehrere E-Mails.
///
/// ⚠️ Warum das überhaupt getestet wird: PHP nimmt je Anfrage nur
/// `max_file_uploads` Dateien an und **verwirft den Rest still**. Ein Fehler
/// hier meldet sich also nirgends — die Mail geht hinaus, das Anschreiben
/// zählt 25 Anlagen auf, und im Umschlag liegen 20.
void main() {
  MailAnhangPlan a(int id, int groesse, {String quelle = 'akte'}) =>
      MailAnhangPlan(
          docId: id, name: 'Steuerbescheid-$id.jpg', groesse: groesse, quelle: quelle);

  group('mailSendungenPlanen', () {
    test('passt alles in eine Mail, bleibt es eine', () {
      final p = mailSendungenPlanen([a(1, 100), a(2, 100), a(3, 100)]);
      expect(p.teile, 1);
      expect(p.sendungen.single.anhaenge.length, 3);
      expect(p.zuGross, isEmpty);
    });

    test('25 Dateien werden zu 20 + 5 — der Fall aus der echten Akte', () {
      final p = mailSendungenPlanen(
          [for (var i = 1; i <= 25; i++) a(i, 1024)],
          maxDateien: 20);
      expect(p.teile, 2);
      expect(p.sendungen[0].anhaenge.length, 20);
      expect(p.sendungen[1].anhaenge.length, 5);
    });

    test('keine Datei geht verloren und keine wird doppelt gesendet', () {
      final p = mailSendungenPlanen(
          [for (var i = 1; i <= 47; i++) a(i, 300 * 1024)],
          maxDateien: 20);
      final ids = [
        for (final s in p.sendungen) ...s.anhaenge.map((x) => x.docId),
      ];
      expect(ids.length, 47);
      expect(ids.toSet().length, 47);
      expect(ids, List.generate(47, (i) => i + 1),
          reason: 'die Reihenfolge ist bei einem Bescheid die Seitenfolge');
    });

    test('die Größengrenze bricht auch unterhalb der Dateigrenze um', () {
      // Drei Dateien zu 10 MB: zwei passen in 25 MB, die dritte nicht.
      final p = mailSendungenPlanen(
          [a(1, 10 << 20), a(2, 10 << 20), a(3, 10 << 20)],
          maxBytes: 25 << 20);
      expect(p.teile, 2);
      expect(p.sendungen[0].anhaenge.length, 2);
      expect(p.sendungen[1].anhaenge.length, 1);
      for (final s in p.sendungen) {
        expect(s.groesse, lessThanOrEqualTo(25 << 20));
      }
    });

    test('eine allein zu große Datei wird BENANNT, nicht weggelassen', () {
      final p = mailSendungenPlanen([a(1, 100), a(2, 30 << 20), a(3, 100)],
          maxBytes: 25 << 20);
      expect(p.zuGross.map((x) => x.docId), [2],
          reason: 'sie darf nicht stillschweigend verschwinden — das '
              'Anschreiben zählt die Anlagen namentlich auf');
      final ids = [
        for (final s in p.sendungen) ...s.anhaenge.map((x) => x.docId),
      ];
      expect(ids, [1, 3]);
    });

    test('leere Liste ergibt keine leere Mail', () {
      expect(mailSendungenPlanen(const []).teile, 0);
    });

    // ⚠️ Dieselbe Id in beiden Tabellen: `akte:17` und `jobcenter:17` sind
    // zwei verschiedene Dateien. Ginge die Herkunft beim Aufteilen verloren,
    // läge im Umschlag zweimal dieselbe — und zwar unauffällig, weil beide
    // Namen stimmen.
    test('gleiche Id aus zwei Quellen bleibt unterscheidbar', () {
      final p = mailSendungenPlanen(
          [a(17, 100), a(17, 100, quelle: 'jobcenter')]);
      final teile = p.sendungen.single.anhaenge;
      expect(teile.length, 2);
      expect(teile.map((x) => x.quelle), ['akte', 'jobcenter']);
    });
  });

  group('mailAnhaengeEinpassen — der Weg ohne Aufteilung', () {
    MailOutgoingAttachment m(String name, int n) => MailOutgoingAttachment(
        filename: name, bytes: Uint8List(n));

    test('21 Anhänge: 20 gehen mit, der 21. wird BENANNT', () {
      final (passend, abgelehnt) = mailAnhaengeEinpassen(
          [for (var i = 1; i <= 21; i++) m('a$i.pdf', 10)]);
      expect(passend.length, 20);
      expect(abgelehnt, ['a21.pdf'],
          reason: 'genau das ging vorher lautlos verloren: PHP schneidet den '
              '21. aus \$_FILES, bevor das Skript startet');
    });

    test('die Größengrenze greift ebenso', () {
      final (passend, abgelehnt) = mailAnhaengeEinpassen(
          [m('gross.pdf', 20 << 20), m('auch_gross.pdf', 20 << 20)],
          maxBytes: 25 << 20);
      expect(passend.map((a) => a.filename), ['gross.pdf']);
      expect(abgelehnt, ['auch_gross.pdf']);
    });

    test('was hineinpasst, bleibt unverändert und in Reihenfolge', () {
      final e = [m('1.pdf', 5), m('2.pdf', 5), m('3.pdf', 5)];
      final (passend, abgelehnt) = mailAnhaengeEinpassen(e);
      expect(passend.map((a) => a.filename), ['1.pdf', '2.pdf', '3.pdf']);
      expect(abgelehnt, isEmpty);
    });
  });

  // ⚠️ Am Quelltext geprüft, nicht am Verhalten: die Stelle liegt in
  // initState() eines Bildschirms, der zum Aufbau ein Postfach, eine Signatur
  // und einen Autosave-Timer braucht. Genau diese eine Zeile war der Fehler —
  // sie nahm die Anhänge ungeprüft entgegen.
  test('der Verfassen-Bildschirm übernimmt Anhänge NICHT mehr ungeprüft', () {
    final quelle = File('lib/screens/mail_compose_screen.dart').readAsStringSync();
    expect(quelle.contains('_newAttachments.addAll(widget.initialAttachments)'),
        isFalse,
        reason: 'die ungeprüfte Übernahme ist zurück — 21 Anhänge gehen dann '
            'wieder als 20 hinaus, ohne dass irgendwo etwas fehlschlägt');
    expect(quelle.contains('mailAnhaengeEinpassen('), isTrue,
        reason: 'die Grenze muss HIER gezogen werden: PHP schneidet den '
            'Überhang vor der ersten Zeile des Skripts aus, der Server kann '
            'es also gar nicht melden');
  });

  // ⚠️ Die Zahl steht an ZWEI Orten: hier und als `_maxFiles` im
  // Verfassen-Bildschirm. Laufen sie auseinander, plant diese Datei 25
  // Anhänge in eine Mail, der Bildschirm nimmt sie an — und PHP wirft fünf
  // davon weg, ohne dass irgendwo etwas fehlschlägt.
  test('kMailMaxAnhaenge deckt sich mit _maxFiles im Verfassen-Bildschirm', () {
    final quelle = File('lib/screens/mail_compose_screen.dart').readAsStringSync();
    final treffer =
        RegExp(r'static const int _maxFiles = (\d+);').firstMatch(quelle);
    expect(treffer, isNotNull,
        reason: '_maxFiles wurde umbenannt — dann muss diese Prüfung mit');
    expect(int.parse(treffer!.group(1)!), kMailMaxAnhaenge);
  });
}
