import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/such_text.dart';

void main() {
  group('suchText faltet, was auf keiner Tastatur liegt', () {
    test('deutsche Umlaute', () {
      expect(suchText('Müller'), 'muller');
      expect(suchText('Öztürk'), 'ozturk');
      expect(suchText('Straße'), 'strasse');
    });

    test('rumänisch — Komma darunter UND Cedille fallen gleich', () {
      // ⚠️ Dieselbe Person, zwei Bytefolgen: ș U+0219 gegen ş U+015F.
      // Ohne diese Prüfung hängt das Finden davon ab, mit welcher Tastatur
      // der Name irgendwann eingetragen wurde.
      expect(suchText('Țănase'), 'tanase');
      expect(suchText('Ţănase'), 'tanase');
      expect(suchText('Grădinar'), 'gradinar');
      expect(suchText('Ș'), suchText('Ş'));
    });

    test('türkisches punktloses ı und das grosse İ', () {
      expect(suchText('Işık'), 'isik');
      // İ wird zu i PLUS angehängtem Punkt — der muss mit weg.
      expect(suchText('İstanbul'), 'istanbul');
    });

    test('zusammengesetztes ö ist dasselbe wie einteiliges', () {
      // ⚠️ Beide Schreibweisen MUESSEN als Escape dastehen. Tippt man sie
      // als Zeichen hin, macht eine Normalisierung im Editor zwei gleiche
      // daraus, und der Test prueft nur noch sich selbst.
      expect(suchText('\u00f6'), 'o');      // oe als EIN Zeichen
      expect(suchText('o\u0308'), 'o');     // o + angehaengtes Trema
      expect(suchText('M\u00fcller'), suchText('Mu\u0308ller'));
    });

    test('was nichts zu falten hat, bleibt', () {
      expect(suchText('M10001'), 'm10001');
      expect(suchText('Дуйня'), 'дуйня');
    });
  });

  group('suchTreffer', () {
    test('findet ohne Häkchen getippt', () {
      expect(suchTreffer('Țănase Grădinar', 'tanase'), isTrue);
      expect(suchTreffer('Müller', 'muller'), isTrue);
    });

    test('Reihenfolge der Wörter ist egal', () {
      // Im Verzeichnis steht „Ionut Doe", getippt wird „doe ionut".
      expect(suchTreffer('Ionut Doe M10001', 'doe ionut'), isTrue);
    });

    test('jedes Wort muss vorkommen, nicht irgendeines', () {
      expect(suchTreffer('Ionut Doe', 'ionut tanase'), isFalse);
    });

    test('Mitgliedsnummer trifft', () {
      expect(suchTreffer('Grădinar M10001', 'm10001'), isTrue);
      expect(suchTreffer('Grădinar M10001', '10001'), isTrue);
    });

    test('leerer Begriff schliesst niemanden aus', () {
      expect(suchTreffer('Ionut Doe', ''), isTrue);
      expect(suchTreffer('Ionut Doe', '   '), isTrue);
    });

    test('was nicht passt, passt nicht', () {
      expect(suchTreffer('Ionut Doe', 'schmidt'), isFalse);
    });
  });
}
