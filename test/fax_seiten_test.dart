import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/screens/sipgate_fax_screen.dart';

/// Die Seitenzeile an der Faxkarte.
///
/// ⚠️ Die Werte sind echte Zeilen vom 30.08.2026: Fax 8 (5 Seiten, vollständig
/// angekommen), Fax 1 (gescheitert, `cannot parse content`, nie an sipgate
/// übergeben) und Fax 41 (eingegangen). Nachgebaute Gerüste prüfen nur die
/// eigene Vorstellung davon, wie der Server antwortet.
void main() {
  Map<String, dynamic> fax({
    int? seiten,
    int? bestaetigt,
    bool fehlen = false,
    String richtung = 'aus',
    String status = 'zugestellt',
  }) =>
      {
        'seiten': seiten,
        'seiten_bestaetigt': bestaetigt,
        'seiten_fehlen': fehlen,
        'richtung': richtung,
        'status': status,
      };

  group('faxSeitenText', () {
    test('vollständig angekommen — steht auch im Regelfall da', () {
      // Genau das war der Wunsch: nicht nur bei Verlust etwas zeigen. Ein Satz,
      // der nur im Fehlerfall erscheint, beweist im Regelfall nichts.
      final r = faxSeitenText(fax(seiten: 5, bestaetigt: 5));
      expect(r.text, '5 von 5 Seiten angekommen');
      expect(r.dringend, isFalse);
    });

    test('Seiten fehlen — dringend, mit Aufforderung', () {
      final r = faxSeitenText(fax(seiten: 9, bestaetigt: 1, fehlen: true));
      expect(r.text, 'nur 1 von 9 Seiten angekommen — bitte erneut senden');
      expect(r.dringend, isTrue);
    });

    test('noch unterwegs ist etwas anderes als gescheitert', () {
      // Beides hat keine Bestätigung. Wären sie derselbe Satz, sähe ein
      // abgeschlossener Vorgang wie ein offener aus.
      expect(faxSeitenText(fax(seiten: 3, status: 'in_zustellung')).text,
          '3 Seiten gesendet · Bestätigung steht aus');
      expect(faxSeitenText(fax(seiten: 1, status: 'fehlgeschlagen')).text,
          '1 Seite — nicht übertragen');
    });

    test('Einzahl und Mehrzahl stimmen', () {
      expect(faxSeitenText(fax(seiten: 1, status: 'fehlgeschlagen')).text, contains('1 Seite —'));
      expect(faxSeitenText(fax(seiten: 2, status: 'fehlgeschlagen')).text, contains('2 Seiten'));
    });

    test('eingegangenes Fax spricht nicht von „angekommen"', () {
      // Dort ist sipgate die einzige Quelle; es gibt nichts zu vergleichen.
      final r = faxSeitenText(fax(seiten: 1, bestaetigt: 1, richtung: 'ein'));
      expect(r.text, '1 Seite empfangen');
      expect(r.text, isNot(contains('von')));
    });

    test('ohne jede Zahl bleibt die Zeile leer — kein Platzhalter', () {
      expect(faxSeitenText(fax()).text, isEmpty);
    });

    test('mehr bestätigt als gesendet geht nicht als „alles gut" durch', () {
      final r = faxSeitenText(fax(seiten: 2, bestaetigt: 3));
      expect(r.text, '3 Seiten bestätigt, 2 gesendet');
    });

    test('älterer Server ohne die neuen Felder stürzt nicht ab', () {
      expect(faxSeitenText(<String, dynamic>{'seiten': 4, 'richtung': 'aus',
              'status': 'zugestellt'}).text,
          '4 Seiten gesendet · Bestätigung steht aus');
      expect(faxSeitenText(<String, dynamic>{}).text, isEmpty);
    });
  });
}
