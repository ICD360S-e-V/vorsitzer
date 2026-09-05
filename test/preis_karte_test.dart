import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/preis_karte.dart';

/// Die Zahlen stammen von der echten Karte vom 05.09.2026:
/// lavera Deo Roll-on — dm 5,95 · Müller 5,95 · Rossmann 5,99.

Map<String, dynamic> l(String markt, double? preis, {String? geprueft}) => {
      'haendler_name': markt,
      'letzter_preis': preis,
      'zuletzt_geprueft': geprueft,
    };

void main() {
  group('Spanne', () {
    test('drei Preise — günstigster, teuerster, Differenz', () {
      final s = preisSpanne([l('dm', 5.95), l('Müller', 5.95), l('Rossmann', 5.99)])!;
      expect(s.guenstigster, 5.95);
      expect(s.teuerster, 5.99);
      expect(s.differenz, closeTo(0.04, 0.0001));
      expect(s.prozent, closeTo(0.67, 0.01));
      expect(s.vergleichbar, isTrue);
    });

    // ⚠️ Der wichtigste Test hier. Mit einem einzigen Preis gibt es keinen
    // Gewinner — ein Häkchen an der einzigen Zeile behauptet einen Vergleich,
    // den niemand angestellt hat.
    test('ein Markt allein ist kein Vergleich', () {
      final s = preisSpanne([l('dm', 5.95)])!;
      expect(s.mitPreis, 1);
      expect(s.vergleichbar, isFalse);
      expect(istGuenstigster(l('dm', 5.95), [l('dm', 5.95)]), isFalse);
    });

    test('gleiche Preise sind kein Unterschied', () {
      final s = preisSpanne([l('dm', 5.95), l('Müller', 5.95)])!;
      expect(s.differenz, 0);
      expect(s.vergleichbar, isFalse);
    });

    // ⚠️ Ein Markt, dessen Seite heute nicht gelesen werden konnte, darf den
    // Vergleich weder gewinnen noch verlieren.
    test('Zeilen ohne Preis zählen nicht mit — auch nicht als 0', () {
      final s = preisSpanne([l('dm', 5.95), l('Müller', null), l('Rossmann', 5.99)])!;
      expect(s.mitPreis, 2);
      expect(s.guenstigster, 5.95);
      expect(s.teuerster, 5.99);
    });

    test('gar keine Preise → null, nicht 0', () {
      expect(preisSpanne([l('dm', null), l('Müller', null)]), isNull);
      expect(preisSpanne([]), isNull);
    });
  });

  group('Wer ist der günstigste', () {
    final karte = [l('dm', 5.95), l('Müller', 6.49), l('Rossmann', 5.99)];

    test('genau einer', () {
      expect(istGuenstigster(karte[0], karte), isTrue);
      expect(istGuenstigster(karte[1], karte), isFalse);
      expect(istGuenstigster(karte[2], karte), isFalse);
    });

    test('bei Gleichstand sind es beide', () {
      final g = [l('dm', 5.95), l('Müller', 5.95), l('Rossmann', 6.49)];
      expect(istGuenstigster(g[0], g), isTrue);
      expect(istGuenstigster(g[1], g), isTrue);
      expect(istGuenstigster(g[2], g), isFalse);
    });

    test('eine Zeile ohne Preis ist nie der günstigste', () {
      final k = [l('dm', 5.95), l('Müller', null)];
      expect(istGuenstigster(k[1], k), isFalse);
    });
  });

  group('Alter des Vergleichs', () {
    final jetzt = DateTime(2026, 9, 5, 12, 0);

    test('nimmt die älteste Lesung, die mitzählt', () {
      final d = aeltesteLesung([
        l('dm', 5.95, geprueft: '2026-09-05 08:00:00'),
        l('Müller', 5.99, geprueft: '2026-09-02 08:00:00'),
      ], jetzt: jetzt)!;
      expect(d.inDays, 3);
    });

    // ⚠️ Eine Zeile ohne Preis geht in den Vergleich nicht ein, also darf ihr
    // Alter ihn auch nicht alt aussehen lassen.
    test('Zeilen ohne Preis zählen nicht', () {
      final d = aeltesteLesung([
        l('dm', 5.95, geprueft: '2026-09-05 08:00:00'),
        l('Müller', null, geprueft: '2026-01-01 08:00:00'),
      ], jetzt: jetzt)!;
      expect(d.inHours, 4);
    });

    test('ohne Lesung → null', () {
      expect(aeltesteLesung([l('dm', 5.95)], jetzt: jetzt), isNull);
      expect(aeltesteLesung([], jetzt: jetzt), isNull);
    });
  });

  prozentPruefungen();

  test('Euro deutsch, mit Komma', () {
    expect(euro(5.95), '5,95 €');
    expect(euro(0.04), '0,04 €');
    expect(euro(null), '—');
  });
}

// ⚠️ Nachgetragen, nachdem die Ansicht 0,67 % als „1 %" gezeigt hat: das
// übertreibt den Unterschied um die Hälfte, und zwar bei genau den kleinen
// Abständen, die den Alltag ausmachen.
void prozentPruefungen() {
  group('Prozentangabe', () {
    test('unter zehn Prozent mit Nachkommastelle', () {
      expect(prozentText(0.67), '0,7 %');
      expect(prozentText(1.0), '1,0 %');
      expect(prozentText(9.94), '9,9 %');
    });
    test('ab zehn Prozent ohne', () {
      expect(prozentText(30.0), '30 %');
      expect(prozentText(23.456), '23 %');
    });
  });
}
