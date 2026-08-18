// Festgenagelt auf die ECHTE, ungekürzte Antwort von
// `api/admin/versorgungsamt_data_manage.php` (gemessen am 18.08.2026 gegen die
// Produktion, einmal für ein Mitglied ohne und einmal für eines mit Daten).
//
// Anlass: für jedes Mitglied ohne einen einzigen gespeicherten Wert lieferte der
// Endpunkt `"data": []` — PHP kennt nur einen Array-Typ, ein leeres Array wird
// zur JSON-**Liste**. Der Tab prüfte auf `is Map`, hielt das für einen
// fehlgeschlagenen Abruf und zeigte „Versorgungsamt-Daten konnten nicht geladen
// werden" mit gesperrter Bearbeitung. Betroffen war damit jedes Mitglied, bei
// dem noch nichts erfasst war — also fast alle.
//
// Weder `flutter analyze` noch ein Widget-Test hätte das gefunden: keiner davon
// berührt die echte Serverantwort. Deshalb dieser Test.
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_versorgungsamt.dart';

void main() {
  group('vaDatenAusAntwort — echte Serverantworten', () {
    test('Mitglied ohne Daten: leere Liste ist KEIN Fehler', () {
      // Server vor der Korrektur (und jeder noch nicht aktualisierte Endpunkt).
      final (daten, fehler) = vaDatenAusAntwort({'success': true, 'data': []});
      expect(fehler, isNull, reason: 'leere Liste heißt „noch nichts erfasst", nicht „Abruf kaputt"');
      expect(daten, isNotNull);
      expect(daten, isEmpty);
    });

    test('Mitglied ohne Daten: leeres Objekt ebenso', () {
      // Server nach der Korrektur: (object)$result.
      final (daten, fehler) = vaDatenAusAntwort({'success': true, 'data': <String, dynamic>{}});
      expect(fehler, isNull);
      expect(daten, isEmpty);
    });

    test('Mitglied mit Daten: Bereiche kommen vollständig an', () {
      // Gekürzt auf drei Bereiche, aber Form und Werte sind die gemessenen.
      final (daten, fehler) = vaDatenAusAntwort({
        'success': true,
        'data': {
          'ausweis': {
            'ausweis_unbefristet': 'false',
            'ausweis_nr': '',
            'ausweis_ausgestellt_am': '',
            'ausweis_gueltig_bis': '2032-02-29',
          },
          'gdb': {'gdb_aktuell': '50', 'gdb_feststellung_datum': '', 'gdb_bescheid_datum': ''},
          'sonstige': {'selected_amt_id': '3'},
        },
      });
      expect(fehler, isNull);
      expect(daten!.keys, containsAll(['ausweis', 'gdb', 'sonstige']));
      expect(daten['gdb']!['gdb_aktuell'], '50');
      expect(daten['ausweis']!['ausweis_gueltig_bis'], '2032-02-29');
    });

    test('Bereich, der kein Objekt ist, wird übersprungen statt zu werfen', () {
      final (daten, fehler) = vaDatenAusAntwort({
        'success': true,
        'data': {'gdb': {'gdb_aktuell': '50'}, 'kaputt': 'kein Objekt'},
      });
      expect(fehler, isNull);
      expect(daten!.keys, ['gdb']);
    });

    test('success:false bleibt ein Fehler, mit dem Grund des Servers', () {
      final (daten, fehler) = vaDatenAusAntwort({'success': false, 'message': 'user_id required'});
      expect(daten, isNull);
      expect(fehler, 'user_id required');
    });

    test('success:false ohne message bekommt einen Ersatztext', () {
      final (daten, fehler) = vaDatenAusAntwort({'success': false});
      expect(daten, isNull);
      expect(fehler, isNotEmpty);
    });

    test('nicht leere Liste bleibt ein Fehler — das ist eine echt falsche Form', () {
      final (daten, fehler) = vaDatenAusAntwort({
        'success': true,
        'data': [
          {'gdb': 1}
        ],
      });
      expect(daten, isNull);
      expect(fehler, isNotEmpty);
    });
  });
}
