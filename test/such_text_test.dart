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
      expect(suchText('Pădurean'), 'padurean');
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
      expect(suchText('M51060'), 'm51060');
      expect(suchText('Дуйня'), 'дуйня');
    });
  });

  group('suchTreffer', () {
    test('findet ohne Häkchen getippt', () {
      expect(suchTreffer('Țănase Pădurean', 'tanase'), isTrue);
      expect(suchTreffer('Müller', 'muller'), isTrue);
    });

    test('Reihenfolge der Wörter ist egal', () {
      // Im Verzeichnis steht „Ionut Duinea", getippt wird „duinea ionut".
      expect(suchTreffer('Ionut Duinea M27655', 'duinea ionut'), isTrue);
    });

    test('jedes Wort muss vorkommen, nicht irgendeines', () {
      expect(suchTreffer('Ionut Duinea', 'ionut tanase'), isFalse);
    });

    test('Mitgliedsnummer trifft', () {
      expect(suchTreffer('Pădurean M51060', 'm51060'), isTrue);
      expect(suchTreffer('Pădurean M51060', '51060'), isTrue);
    });

    test('leerer Begriff schliesst niemanden aus', () {
      expect(suchTreffer('Ionut Duinea', ''), isTrue);
      expect(suchTreffer('Ionut Duinea', '   '), isTrue);
    });

    test('was nicht passt, passt nicht', () {
      expect(suchTreffer('Ionut Duinea', 'schmidt'), isFalse);
    });
  });
}
