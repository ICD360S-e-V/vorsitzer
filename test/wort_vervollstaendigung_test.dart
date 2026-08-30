import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/wort_vervollstaendigung.dart';

void main() {
  // Nach Häufigkeit sortiert, wie die echte Liste.
  final index = WortIndex.aufbauen([
    'de', 'nu', 'să', 'mulțumesc', 'dacă', 'ești', 'trimiteți', 'bine',
    'mulțumiri', 'documentul', 'document', 'marți', 'îmi', 'așa',
  ]);

  group('ohneDiakritika', () {
    test('legt Komma-unten und Cedille auf denselben Buchstaben', () {
      expect(WortIndex.ohneDiakritika('mulțumesc'), 'multumesc');
      expect(WortIndex.ohneDiakritika('mulţumesc'), 'multumesc'); // Cedille
      expect(WortIndex.ohneDiakritika('DACĂ'), 'daca');
      expect(WortIndex.ohneDiakritika('îmi'), 'imi');
      expect(WortIndex.ohneDiakritika('așa'), 'asa');
    });
  });

  group('vorschlaege', () {
    test('ohne Häkchen getippt findet die richtige Schreibung', () {
      expect(index.vorschlaege('multu'), contains('mulțumesc'));
      expect(index.vorschlaege('daca'), contains('dacă'));
      expect(index.vorschlaege('trimiteti'), contains('trimiteți'));
    });

    test('die häufigere Form steht vorn', () {
      // 'mulțumesc' steht in der Liste vor 'mulțumiri'.
      expect(index.vorschlaege('mult').first, 'mulțumesc');
    });

    test('unter drei Zeichen kommt nichts', () {
      expect(index.vorschlaege('mu'), isEmpty);
      expect(index.vorschlaege('d'), isEmpty);
    });

    test('das zeichengleiche Wort ist kein Vorschlag für sich selbst', () {
      expect(index.vorschlaege('mulțumesc'), isNot(contains('mulțumesc')));
    });

    test('aber die Fassung ohne Häkchen bleibt einer', () {
      // Genau das ist der Nutzen: 'multumesc' ist kein Wort, 'mulțumesc' schon.
      expect(index.vorschlaege('multumesc'), contains('mulțumesc'));
    });

    test('unbekannter Anfang liefert nichts statt zu raten', () {
      expect(index.vorschlaege('xyzab'), isEmpty);
    });
  });

  group('kennt', () {
    test('nur die zeichengleiche Schreibung gilt als Wort', () {
      expect(index.kennt('mulțumesc'), isTrue);
      expect(index.kennt('multumesc'), isFalse);
      expect(index.kennt('bine'), isTrue);
    });
  });

  group('schreibungUebernehmen', () {
    test('erster Buchstabe groß bleibt groß', () {
      expect(WortIndex.schreibungUebernehmen('Multu', 'mulțumesc'),
          'Mulțumesc');
    });
    test('durchgehend groß bleibt durchgehend groß', () {
      expect(WortIndex.schreibungUebernehmen('MULTU', 'mulțumesc'),
          'MULȚUMESC');
    });
    test('ein einzelner Großbuchstabe schreit noch nicht', () {
      expect(WortIndex.schreibungUebernehmen('M', 'mulțumesc'), 'Mulțumesc');
    });
    test('klein bleibt klein', () {
      expect(WortIndex.schreibungUebernehmen('multu', 'mulțumesc'),
          'mulțumesc');
    });
  });

  group('AngefangenesWort', () {
    test('nimmt das Wort links vom Cursor', () {
      final w = AngefangenesWort.ausEingabe('Va rog multu', 12);
      expect(w?.text, 'multu');
      expect(w?.von, 7);
      expect(w?.bis, 12);
    });

    test('mitten im Wort gibt es nichts', () {
      // Sonst verschluckte die Übernahme den Rest des Wortes.
      expect(AngefangenesWort.ausEingabe('Va rog multumesc', 10), isNull);
    });

    test('nach einem Leerzeichen gibt es nichts', () {
      expect(AngefangenesWort.ausEingabe('Va rog ', 7), isNull);
    });

    test('Satzzeichen trennen', () {
      expect(AngefangenesWort.ausEingabe('Buna, multu', 11)?.text, 'multu');
      expect(AngefangenesWort.ausEingabe('(multu', 6)?.text, 'multu');
    });

    test('leerer Index liefert nie Vorschläge', () {
      expect(WortIndex.leer.vorschlaege('multu'), isEmpty);
      expect(WortIndex.leer.kennt('bine'), isFalse);
    });
  });
}
