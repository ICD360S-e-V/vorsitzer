import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/landratsamt_vollmacht_tab.dart';

/// Die Antwort von `vollmacht_data.php?behoerde=landratsamt`, so wie der
/// Server sie baut.
///
/// ⚠️ SYNTHETISCH, keine mitgeschnittene echte Antwort. Das Repo ist
/// öffentlich; ein aufgezeichneter Mitschnitt hat hier schon dreimal echte
/// Zugangsdaten hineingetragen. Nachgebildet ist nur die FORM — und die ist
/// das, worüber dieser Test wacht.
String _antwort({required bool mitZusatz}) => jsonEncode({
  'success': true,
  'user': {'vorname': 'Paula', 'nachname': 'Muster', 'geburtsdatum': '1990-01-01'},
  'vorfall': {'id': 5, 'art': 'Führerschein Umschreibung', 'aktenzeichen': 'AZ-1'},
  'amt': {'name': 'Landratsamt Musterkreis'},
  'recht': {
    'bereich': mitZusatz ? 'allgemein' : 'betreuung',
    'label': mitZusatz ? 'Allgemeines Verwaltungsverfahren' : 'Betreuungsbehörde (BtOG)',
    'norm': '§ 14 Abs. 1 VwVfG i.V.m. § 7 RDG',
    'rechtsweg': 'Verwaltungsgericht',
    'umfang_katalog': {'bescheide': 'Empfang von Bescheiden', 'termine': 'Teilnahme an Terminen'},
    // 🔴 Hier liegt die Falle: PHP hat nur EINEN Array-Typ. Ein leerer
    // Katalog wird als LISTE `[]` kodiert, ein gefüllter als Objekt.
    'zusatz_katalog': mitZusatz ? {'rueckstaende': 'Einwilligung Rückstände'} : <String>[],
    'grenzen': ['Keine Rechtsdienstleistung über § 7 RDG hinaus.'],
  },
});

void main() {
  group('Serverantwort lesen', () {
    test('gefüllter Katalog kommt als Objekt und wird gelesen', () {
      final d = jsonDecode(_antwort(mitZusatz: true)) as Map<String, dynamic>;
      final recht = vollmachtFeldAlsMap(d['recht']);
      expect(vollmachtFeldAlsKatalog(recht['umfang_katalog']).keys,
          containsAll(['bescheide', 'termine']));
      expect(vollmachtFeldAlsKatalog(recht['zusatz_katalog']),
          {'rueckstaende': 'Einwilligung Rückstände'});
    });

    test('LEERER Katalog kommt als Liste [] — und darf nicht werfen', () {
      // Ohne die tolerante Lesart wäre das eine TypeError und im
      // Release-Build eine graue Fläche ohne Meldung. Drei der vier
      // Rechtskreise haben keinen Zusatzkatalog, also ist das der Regelfall
      // und nicht die Ausnahme.
      final d = jsonDecode(_antwort(mitZusatz: false)) as Map<String, dynamic>;
      final recht = vollmachtFeldAlsMap(d['recht']);
      expect(recht['zusatz_katalog'], isA<List<dynamic>>(),
          reason: 'die Vorlage muss die echte PHP-Form nachbilden, sonst prüft der Test nichts');
      expect(() => vollmachtFeldAlsKatalog(recht['zusatz_katalog']), returnsNormally);
      expect(vollmachtFeldAlsKatalog(recht['zusatz_katalog']), isEmpty);
      // Der Umfang steht trotzdem — der leere Zusatz darf ihn nicht mitreißen.
      expect(vollmachtFeldAlsKatalog(recht['umfang_katalog']), hasLength(2));
    });

    test('Grenzen sind eine Liste, ein Objekt darf nicht werfen', () {
      expect(vollmachtFeldAlsTexte(['a', 'b']), ['a', 'b']);
      expect(vollmachtFeldAlsTexte(<String, dynamic>{}), isEmpty);
      expect(vollmachtFeldAlsTexte(null), isEmpty);
    });

    test('fehlende Felder kippen nichts', () {
      expect(vollmachtFeldAlsMap(null), isEmpty);
      expect(vollmachtFeldAlsMap('kein Objekt'), isEmpty);
      expect(vollmachtFeldAlsKatalog(null), isEmpty);
      expect(vollmachtFeldAlsKatalog(42), isEmpty);
    });

    test('Zahlen im Katalog werden zu Text, nicht zu einem Absturz', () {
      // Ein Katalogwert ist immer Text — aber wenn je einer als Zahl käme,
      // soll die Seite stehen bleiben, nicht verschwinden.
      expect(vollmachtFeldAlsKatalog({'a': 1}), {'a': '1'});
    });
  });
}
