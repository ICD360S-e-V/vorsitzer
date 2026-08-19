import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_gericht.dart';

/// Die Versandwege der Vollmacht sind an DREI Stellen gekoppelt, und zwei
/// davon scheitern lautlos:
///
///   1. `vollmacht_versand.weg` — das ENUM in der Datenbank
///   2. `insolvenz_manage.php`  — die Liste in `vollmacht_versand_eintragen`
///   3. `kVollmachtVersandWege` — die Beschriftung im Versandprotokoll
///
/// Fehlt ein Weg in (3), zeigt das Protokoll den ROHWERT: da stand vorher
/// „fax an +49 731 …" statt „per Fax an …". Kein Absturz, keine Meldung —
/// es sieht nur aus wie ein Datenbankauszug, und genau deshalb fällt es
/// niemandem auf, der es nicht sucht.
///
/// ⚠️ Die Liste hier ist das ENUM aus der Migration, ABGESCHRIEBEN, nicht
/// abgeleitet. Das ist Absicht: würde der Test seine Erwartung aus derselben
/// Konstante ziehen, die er prüft, bestätigte er nur sich selbst.
void main() {
  // Stand 18.08.2026, `DESCRIBE vollmacht_versand`:
  //   weg enum('chat','email','bea','fax','post','persoenlich')
  const enumAusDerDatenbank = <String>[
    'chat', 'email', 'bea', 'fax', 'post', 'persoenlich',
  ];

  group('Versandwege der Vollmacht', () {
    test('jeder Weg aus dem Datenbank-ENUM hat eine Beschriftung', () {
      for (final weg in enumAusDerDatenbank) {
        expect(kVollmachtVersandWege.containsKey(weg), isTrue,
            reason: 'Der Weg "$weg" steht im ENUM, aber nicht in '
                'kVollmachtVersandWege — das Versandprotokoll zeigt dafür '
                'den Rohwert.');
      }
    });

    test('keine Beschriftung ohne Entsprechung im ENUM', () {
      for (final weg in kVollmachtVersandWege.keys) {
        expect(enumAusDerDatenbank.contains(weg), isTrue,
            reason: 'Für "$weg" gibt es eine Beschriftung, aber das ENUM '
                'kennt den Wert nicht — der Server könnte ihn nie liefern.');
      }
    });

    test('die Beschriftung ist ein Satzteil, kein Rohwert', () {
      // Sie wird als „<Weg> an <Empfänger>" gesetzt. Ohne Präposition ergibt
      // das „fax an …" — der Fehler, wegen dem es diese Tabelle gibt.
      for (final eintrag in kVollmachtVersandWege.entries) {
        expect(eintrag.value, isNot(equals(eintrag.key)),
            reason: 'Die Beschriftung von "${eintrag.key}" ist der Rohwert.');
        expect(eintrag.value.contains(' '), isTrue,
            reason: '"${eintrag.value}" liest sich nicht wie ein Satzteil.');
      }
    });

    test('Fax ist dabei — der Weg, für den dieser Zweig gebaut wurde', () {
      expect(kVollmachtVersandWege['fax'], 'per Fax');
    });
  });
}
