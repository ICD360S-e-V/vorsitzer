import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/fachrichtung_map.dart';

/// Die 24 Schreibweisen, die `aerzte_datenbank` am 26.08.2026 wirklich führte,
/// mit ihrer Zeilenzahl.
///
/// ⚠️ Das ist ein GEMESSENER Stand, keine Wunschliste. Er steht hier, weil
/// genau an ihm der Fehler hing: die Reiter suchten mit Bezeichnungen, die in
/// dieser Spalte nirgends vorkommen, und bekamen wahrheitsgemäß nichts.
/// Ändert sich der Katalog, ändert sich diese Tabelle — nicht die Erwartung,
/// dass ein Reiter seine Praxen findet.
const Map<String, int> kDatenbankStand = {
  'Physiotherapie': 6,
  'Allgemeinmedizin': 5,
  'Gynäkologie': 3,
  'Zahnmedizin': 3,
  'Augenheilkunde': 2,
  'Endokrinologie': 2,
  'Ergotherapie': 2,
  'Neurologie': 2,
  'Orthopädie und Unfallchirurgie': 2,
  'Pneumologie': 2,
  'Radiologie': 2,
  'Sanitätshaus': 2,
  'Dermatologie': 1,
  'Gastroenterologie': 1,
  'Hals-Nasen-Ohren-Heilkunde': 1,
  'Logopädie': 1,
  'Neurologie, Psychiatrie und Psychotherapie': 1,
  'Orthopädie': 1,
  'Orthopädie / Unfallchirurgie / Gefäßchirurgie / Neurochirurgie': 1,
  'Physikalische und Rehabilitative Medizin': 1,
  'Podologie': 1,
  'Psychiatrie und Psychotherapie': 1,
  'Wundversorgung': 1,
};

/// Wie viele Zeilen des Standes eine Suche nach [fach] findet.
int treffer(String fach) {
  var n = 0;
  kDatenbankStand.forEach((schreibweise, anzahl) {
    if (fachrichtungPasst(fach, schreibweise)) n += anzahl;
  });
  return n;
}

void main() {
  group('Begriffe zerlegen', () {
    test('trennt an Schrägstrich, Komma und „und"', () {
      expect(fachrichtungBegriffe('Orthopädie und Unfallchirurgie'),
          {'orthopädie', 'unfallchirurgie'});
      expect(fachrichtungBegriffe('Gastroenterologie / Magen-Darm-Erkrankungen'),
          {'gastroenterologie', 'magen-darm-erkrankungen'});
      expect(fachrichtungBegriffe('Neurologie, Psychiatrie und Psychotherapie'),
          {'neurologie', 'psychiatrie', 'psychotherapie'});
    });

    test('der Bindestrich trennt NICHT — sonst zerfällt ein Fachwort', () {
      // „Hals-Nasen-Ohren-Heilkunde" ist ein Begriff. Zerlegt man ihn, passt
      // plötzlich jede Praxis, die irgendwo „Heilkunde" führt.
      expect(fachrichtungBegriffe('Hals-Nasen-Ohren-Heilkunde'),
          {'hals-nasen-ohren-heilkunde'});
    });

    test('„und" mitten im Wort ist kein Trennzeichen', () {
      expect(fachrichtungBegriffe('Wundversorgung'), {'wundversorgung'});
      expect(fachrichtungBegriffe('Gesundheitsvorsorge'), {'gesundheitsvorsorge'});
    });
  });

  group('Der gemeldete Fehler', () {
    test('Gastroenterologie findet die gespeicherte Praxis', () {
      // 🔴 Das ist der Fall aus der Meldung. Vor dem 26.08.2026 wurde
      // zeichengleich verglichen: die Praxis lag unter 'Gastroenterologie',
      // gesucht wurde nach 'Gastroenterologie / Magen-Darm-Erkrankungen',
      // Ergebnis 0 — bei vorhandener Praxis.
      expect(
          fachrichtungPasst(
              'Gastroenterologie / Magen-Darm-Erkrankungen', 'Gastroenterologie'),
          isTrue);
      expect(treffer('Gastroenterologie / Magen-Darm-Erkrankungen'), 1);
    });
  });

  group('Jeder Reiter findet, was für ihn da ist', () {
    // Die Bezeichnungen stammen wörtlich aus den `_buildArztContent`-Aufrufen.
    // ⚠️ Erwartet wird die Zeilenzahl aus [kDatenbankStand], nicht „mehr als 0":
    // eine Suche, die von drei Schreibweisen desselben Fachs nur eine findet,
    // wäre sonst grün.
    const erwartet = <String, int>{
      'Allgemeinmedizin / Innere Medizin': 5,
      'Pneumologie / Pulmologie': 2,
      'Psychiatrie / Psychotherapie': 2, // die Einzelpraxis + die Gemeinschaftspraxis
      'Neurologie / Nervenheilkunde': 3, // Neurologie (2) + die Gemeinschaftspraxis
      'Orthopädie / Unfallchirurgie': 4, // alle drei Schreibweisen zusammen
      'Dermatologie': 1,
      'Zahnmedizin': 3,
      'Gynäkologie / Frauenheilkunde': 3,
      'Endokrinologie / Hormonerkrankungen / Schilddrüse': 2,
      'Gastroenterologie / Magen-Darm-Erkrankungen': 1,
      'Wundversorgung / Chronische Wunden': 1,
    };
    erwartet.forEach((fach, anzahl) {
      test('„$fach" → $anzahl', () => expect(treffer(fach), anzahl));
    });

    test('Fächer ohne Eintrag bleiben leer — das ist kein Fehler', () {
      for (final leer in const [
        'Kardiologie / Herzmedizin',
        'Urologie',
        'Onkologie / Krebsmedizin',
        'Diabetologie / Diabetes mellitus / Stoffwechsel',
      ]) {
        expect(treffer(leer), 0, reason: leer);
      }
    });
  });

  group('Kurzformen der Überweisung', () {
    test('HNO trifft die amtliche Langform', () {
      expect(treffer('HNO'), 1);
    });
    test('Ophthalmologie trifft Augenheilkunde', () {
      // Der Augenarzt-Reiter nennt sein Fach anders als beide Kataloge.
      expect(treffer('Ophthalmologie'), 2);
      expect(treffer('Augenheilkunde'), 2);
    });
    test('Chirurgie landet bei der Unfallchirurgie', () {
      expect(treffer('Chirurgie'), 4);
    });
    test('Radiologie und Physiotherapie treffen unmittelbar', () {
      expect(treffer('Radiologie'), 2);
      expect(treffer('Physiotherapie'), 6);
    });
  });

  group('Keine falschen Treffer', () {
    test('ein Fach zieht kein fremdes mit', () {
      expect(fachrichtungPasst('Zahnmedizin', 'Physiotherapie'), isFalse);
      expect(fachrichtungPasst('Dermatologie', 'Allgemeinmedizin'), isFalse);
      // Beide enden auf „-therapie", teilen aber keinen Begriff.
      expect(fachrichtungPasst('Physiotherapie', 'Ergotherapie'), isFalse);
      // Beide enden auf „-medizin".
      expect(fachrichtungPasst('Zahnmedizin', 'Allgemeinmedizin'), isFalse);
      expect(fachrichtungPasst('Gastroenterologie', 'Podologie'), isFalse);
    });

    test('Orthopädie zieht die Neurochirurgie NICHT als Neurologie herein', () {
      expect(
          fachrichtungPasst('Neurologie / Nervenheilkunde',
              'Orthopädie / Unfallchirurgie / Gefäßchirurgie / Neurochirurgie'),
          isFalse);
    });
  });

  group('Ränder', () {
    test('ohne Fach wird nicht eingegrenzt', () {
      expect(fachrichtungPasst('', 'Zahnmedizin'), isTrue);
      expect(fachrichtungPasst('   ', 'Zahnmedizin'), isTrue);
      expect(treffer(''), kDatenbankStand.values.reduce((a, b) => a + b));
    });
    test('ein Eintrag ohne Fachrichtung passt zu keiner Suche', () {
      // Sonst würde eine unvollständige Zeile in JEDEM Reiter auftauchen.
      expect(fachrichtungPasst('Zahnmedizin', ''), isFalse);
    });
    test('Gross-/Kleinschreibung und Leerraum sind egal', () {
      expect(fachrichtungPasst('gastroenterologie', '  GASTROENTEROLOGIE '), isTrue);
      expect(fachrichtungPasst('Orthopädie  /  Unfallchirurgie',
          'Orthopädie und Unfallchirurgie'), isTrue);
    });
  });
}
