import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/tippfehler.dart';

void main() {
  // Nach Häufigkeit sortiert, wie die echte Liste.
  final t = Tippfehler.aufbauen([
    'document', 'documentul', 'documente', 'cerere', 'trimit', 'mulțumesc',
    'hotărâre', 'contestație', 'membru', 'ședință', 'care', 'mare', 'sare',
  ]);

  group('repariert einen Anschlag daneben', () {
    const faelle = {
      'dovument': 'document',      // falsche Taste
      'documnt': 'document',       // ausgelassen
      'docuument': 'document',     // doppelt
      'ducoment': 'document',      // vertauscht
      'cerrere': 'cerere',
      'trimir': 'trimit',
    };
    faelle.forEach((falsch, richtig) {
      test('„$falsch" -> „$richtig"', () {
        expect(t.korrektur(falsch), richtig);
      });
    });
  });

  test('ein richtiges Wort wird nie angefasst', () {
    for (final w in ['document', 'cerere', 'mulțumesc', 'ședință']) {
      expect(t.korrektur(w), isNull, reason: w);
    }
  });

  test('unter drei Zeichen passiert nichts', () {
    // Bei zwei Buchstaben ist jedes andere Wort einen Schritt entfernt.
    expect(t.korrektur('ca'), isNull);
    expect(t.korrektur('do'), isNull);
  });

  test('bei Gleichstand wird NICHT geraten', () {
    // ⚠️ Der wichtigste Test. „nare" ist von „mare" und „care" gleich weit
    // entfernt — welches gemeint war, steht in keiner Häufigkeitsliste.
    // Ohne diese Regel waren 27,6 % aller Korrekturen falsch.
    expect(t.korrektur('nare'), isNull);
    expect(t.korrektur('bare'), isNull);
  });

  test('zu weit weg bleibt unangetastet', () {
    expect(t.korrektur('xyzabc'), isNull);
    expect(t.korrektur('Vollmacht'), isNull);
  });

  test('kurze Wörter bekommen nur einen Schritt zugestanden', () {
    // „carr" -> „care" ist einer. „cxrr" wären zwei, und bei vier Zeichen
    // ist das das halbe Wort.
    expect(t.korrektur('carr'), 'care');
    expect(t.korrektur('cxrr'), isNull);
  });

  test('lange Wörter dürfen zwei', () {
    expect(t.korrektur('contestatie'), 'contestație');
    expect(t.korrektur('mulzumesk'), 'mulțumesc');
  });

  test('die Schreibung wird übernommen', () {
    expect(t.korrektur('Dovument'), 'Document');
  });

  test('leerer Index ändert nie etwas', () {
    expect(Tippfehler.leer.bereit, isFalse);
    expect(Tippfehler.leer.korrektur('dovument'), isNull);
  });
}
