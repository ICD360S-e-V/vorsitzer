import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/sprachen_options.dart';

/// Die Liste stammt aus ISO 639-1. Diese Tests halten zwei Dinge fest, die
/// beim Nachpflegen leicht kaputtgehen: dass Europa wirklich vollständig ist
/// (dort kommen die Mitglieder her) und dass alle fünf Erdteile vertreten
/// sind — eine Muttersprachenliste, die nur Europa kennt, ist eine Ausrede.
void main() {
  Sprache? nach(String bezeichnung) {
    for (final s in alleSprachen) {
      if (s.bezeichnung == bezeichnung) return s;
    }
    return null;
  }

  group('Vollständigkeit Europa', () {
    // Die 24 Amtssprachen der EU. Fehlt eine, kann ein Mitglied aus diesem
    // Land seine Muttersprache nicht angeben.
    const amtssprachenEu = [
      'Bulgarisch', 'Dänisch', 'Deutsch', 'Englisch', 'Estnisch', 'Finnisch',
      'Französisch', 'Griechisch', 'Irisch', 'Italienisch', 'Kroatisch',
      'Lettisch', 'Litauisch', 'Maltesisch', 'Niederländisch', 'Polnisch',
      'Portugiesisch', 'Rumänisch', 'Schwedisch', 'Slowakisch', 'Slowenisch',
      'Spanisch', 'Tschechisch', 'Ungarisch',
    ];

    test('alle 24 EU-Amtssprachen sind enthalten und stehen unter Europa', () {
      for (final a in amtssprachenEu) {
        final s = nach(a);
        expect(s, isNotNull, reason: 'EU-Amtssprache fehlt: $a');
        expect(s!.kontinent, Kontinent.europa, reason: '$a ist nicht Europa zugeordnet');
      }
    });

    test('Landessprachen außerhalb der EU sind enthalten', () {
      const weitere = [
        'Albanisch', 'Belarussisch', 'Bosnisch', 'Isländisch', 'Mazedonisch',
        'Norwegisch', 'Russisch', 'Serbisch', 'Ukrainisch',
      ];
      for (final a in weitere) {
        expect(nach(a), isNotNull, reason: 'Europäische Landessprache fehlt: $a');
      }
    });

    test('Regional- und Minderheitensprachen sind enthalten', () {
      const regional = [
        'Baskisch', 'Bretonisch', 'Bündnerromanisch', 'Färöisch', 'Galicisch',
        'Jiddisch', 'Katalanisch', 'Luxemburgisch', 'Nordsamisch', 'Okzitanisch',
        'Sardisch', 'Schottisch-gälisch', 'Walisisch', 'Westfriesisch',
      ];
      for (final a in regional) {
        expect(nach(a), isNotNull, reason: 'Regionalsprache fehlt: $a');
      }
    });
  });

  group('Alle fünf Erdteile', () {
    test('jeder Erdteil ist besetzt', () {
      for (final k in Kontinent.values) {
        expect(sprachenNachKontinent(k), isNotEmpty, reason: 'Erdteil leer: ${k.bezeichnung}');
      }
    });

    test('kein Erdteil ist nur symbolisch vertreten', () {
      // Untergrenzen bewusst niedrig: sie sollen ein versehentliches
      // Zusammenstreichen bemerken, nicht die Liste einfrieren.
      const mindestens = {
        Kontinent.europa: 50,
        Kontinent.asien: 40,
        Kontinent.afrika: 30,
        Kontinent.amerika: 8,
        Kontinent.ozeanien: 8,
      };
      mindestens.forEach((k, n) {
        expect(sprachenNachKontinent(k).length, greaterThanOrEqualTo(n),
            reason: '${k.bezeichnung} hat nur ${sprachenNachKontinent(k).length} Sprachen');
      });
    });

    test('je Erdteil sind die großen Sprachen dabei', () {
      const stichproben = {
        Kontinent.asien: ['Chinesisch', 'Hindi', 'Arabisch', 'Japanisch', 'Vietnamesisch', 'Kurdisch', 'Persisch'],
        Kontinent.afrika: ['Swahili', 'Amharisch', 'Hausa', 'Yoruba', 'Somali', 'Afrikaans'],
        Kontinent.amerika: ['Quechua', 'Guaraní', 'Haitianisch-Kreolisch', 'Grönländisch'],
        Kontinent.ozeanien: ['Maori', 'Samoanisch', 'Fidschi', 'Tongaisch'],
      };
      stichproben.forEach((k, liste) {
        for (final a in liste) {
          final s = nach(a);
          expect(s, isNotNull, reason: 'fehlt: $a');
          expect(s!.kontinent, k, reason: '$a steht nicht unter ${k.bezeichnung}');
        }
      });
    });
  });

  group('Sauberkeit der Liste', () {
    test('keine doppelten Codes und keine doppelten Bezeichnungen', () {
      final codes = alleSprachen.map((s) => s.code).toList();
      final namen = alleSprachen.map((s) => s.bezeichnung).toList();
      expect(codes.toSet().length, codes.length, reason: 'doppelter ISO-Code');
      expect(namen.toSet().length, namen.length, reason: 'doppelte Bezeichnung');
    });

    test('alle Codes sind zweistellige ISO-639-1-Codes in Kleinschreibung', () {
      for (final s in alleSprachen) {
        expect(RegExp(r'^[a-z]{2}$').hasMatch(s.code), isTrue,
            reason: 'kein gültiger Code: ${s.code} (${s.bezeichnung})');
      }
    });

    test('keine Bezeichnung ist leer oder hat Leerzeichen am Rand', () {
      for (final s in alleSprachen) {
        expect(s.bezeichnung.trim(), s.bezeichnung, reason: 'Rand-Leerzeichen: "${s.bezeichnung}"');
        expect(s.bezeichnung, isNotEmpty);
      }
    });

    test('Plansprachen und tote Sprachen sind bewusst nicht enthalten', () {
      // Eine Muttersprache ist eine gesprochene Sprache. Stünden Latein oder
      // Esperanto in der Auswahl, wären sie irgendwann auch angeklickt.
      const draussen = ['Esperanto', 'Interlingua', 'Interlingue', 'Ido', 'Volapük',
                        'Latein', 'Sanskrit', 'Pali', 'Avestisch', 'Kirchenslawisch',
                        'Serbokroatisch', 'Bihari'];
      for (final a in draussen) {
        expect(nach(a), isNull, reason: 'sollte nicht in der Auswahl stehen: $a');
      }
    });
  });

  group('Sortierung fürs Dropdown', () {
    test('die häufigen Sprachen stehen im Erdteil oben', () {
      final europa = sprachenNachKontinent(Kontinent.europa);
      expect(europa.first.bezeichnung, 'Deutsch');
      expect(europa.take(6).map((s) => s.bezeichnung),
          containsAll(['Deutsch', 'Rumänisch', 'Russisch', 'Ukrainisch', 'Polnisch', 'Englisch']));

      final asien = sprachenNachKontinent(Kontinent.asien);
      expect(asien.take(4).map((s) => s.bezeichnung),
          containsAll(['Türkisch', 'Arabisch', 'Kurdisch', 'Persisch']));
    });

    test('hinter den häufigen wird alphabetisch sortiert', () {
      final rest = sprachenNachKontinent(Kontinent.afrika).map((s) => s.bezeichnung).toList();
      final sortiert = [...rest]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      expect(rest, sortiert, reason: 'Afrika hat keine häufigen, muss also rein alphabetisch sein');
    });

    test('sprachenOptionen enthält jede Sprache genau einmal', () {
      // Doppelte Werte lassen DropdownButton beim Auswählen werfen.
      expect(sprachenOptionen.length, alleSprachen.length);
      expect(sprachenOptionen.toSet().length, sprachenOptionen.length);
    });
  });

  group('Normalisierung bestehender Freitexte', () {
    test('die tatsächlich gespeicherten Werte werden erkannt', () {
      // Genau diese drei stehen heute in der Datenbank.
      expect(sprachNormalisieren('Rumanisch'), 'Rumänisch');
      expect(sprachNormalisieren('rumanisch'), 'Rumänisch');
      expect(sprachNormalisieren('Ukrainisch'), 'Ukrainisch');
    });

    test('fehlende Umlaute und Groß-/Kleinschreibung stören nicht', () {
      expect(sprachNormalisieren('Turkisch'), 'Türkisch');
      expect(sprachNormalisieren('TÜRKISCH'), 'Türkisch');
      expect(sprachNormalisieren('  danisch  '), 'Dänisch');
      expect(sprachNormalisieren('griechisch'), 'Griechisch');
    });

    test('ein ISO-Code wird ebenfalls aufgelöst', () {
      expect(sprachNormalisieren('ro'), 'Rumänisch');
      expect(sprachNormalisieren('uk'), 'Ukrainisch');
    });

    test('leer bleibt leer', () {
      expect(sprachNormalisieren(null), '');
      expect(sprachNormalisieren(''), '');
      expect(sprachNormalisieren('   '), '');
    });

    test('Unbekanntes wird nicht verbogen', () {
      // Lieber eine Angabe stehen lassen, die wir nicht kennen, als sie auf
      // die nächstbeste Sprache zu verbiegen.
      expect(sprachNormalisieren('Suaheli'), 'Suaheli');
      expect(sprachNormalisieren('Plattdeutsch'), 'Plattdeutsch');
    });

    test('jede Bezeichnung normalisiert auf sich selbst', () {
      for (final s in alleSprachen) {
        expect(sprachNormalisieren(s.bezeichnung), s.bezeichnung);
        expect(sprachNormalisieren(s.bezeichnung.toLowerCase()), s.bezeichnung);
      }
    });
  });
}
