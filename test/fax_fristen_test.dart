import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/screens/sipgate_fax_screen.dart';

/// Prüft die Anzeige der beiden Faxfristen.
///
/// ⚠️ Die Vorlagen sind ECHTE Serverantworten, am 30.08.2026 aus
/// `sipgateFaxFristen()` gezogen und hier wörtlich eingesetzt — nicht von Hand
/// nachgebaut. Ein selbst erfundenes Gerüst prüft nur die eigene Vorstellung
/// davon, wie der Server antwortet; genau daran ist der Speedtest-Bildschirm
/// einmal grau geworden.
void main() {
  // So kommt es wirklich an (Fax 8, gesendet am 19.08.2026).
  const echt = '{"archiv":{"tage":3,"am":"2026-09-02","grund":""},'
      '"inhalt":{"tage":2316,"am":"2033-01-01","grund":""}}';

  Map<String, dynamic> vorlage({
    int? aTage,
    String aGrund = '',
    String? aAm,
    int? iTage,
    String iGrund = '',
    String? iAm,
  }) =>
      {
        'archiv': {'tage': aTage, 'am': aAm, 'grund': aGrund},
        'inhalt': {'tage': iTage, 'am': iAm, 'grund': iGrund},
      };

  group('faxFristTexte', () {
    test('echte Serverantwort ergibt beide Sätze', () {
      final t = faxFristTexte(jsonDecode(echt) as Map<String, dynamic>);
      expect(t.archiv, 'Archiv in 3 Tagen');
      // ⚠️ Datum vorn: „noch 2316 Tage" allein kann niemand einordnen.
      expect(t.inhalt, 'Inhalt bis 01.01.2033 · noch 2316 Tage');
    });

    test('heute und morgen werden ausgeschrieben', () {
      expect(faxFristTexte(vorlage(aTage: 0)).archiv, 'Archiv heute');
      expect(faxFristTexte(vorlage(aTage: 1)).archiv, 'Archiv morgen');
    });

    test('überfällig zeigt keine negative Zahl', () {
      // Kommt vor, wenn der Archivlauf einen Tag ausfällt. „in -3 Tagen" wäre
      // die Art Text, an der man merkt, dass niemand hingesehen hat.
      final t = faxFristTexte(vorlage(aTage: -3));
      expect(t.archiv, 'Archiv überfällig');
      expect(t.archiv, isNot(contains('-3')));
    });

    test('läuft keine Uhr, steht der Grund da statt einer Zahl', () {
      final t = faxFristTexte(vorlage(
        aGrund: 'noch ungelesen — die Frist beginnt beim Lesen',
        iGrund: 'gesperrt — die Frist ruht, solange das Verfahren läuft',
      ));
      expect(t.archiv, 'noch ungelesen — die Frist beginnt beim Lesen');
      expect(t.inhalt, 'gesperrt — die Frist ruht, solange das Verfahren läuft');
    });

    test('ein Zusatzgrund hängt hinter der Zahl, verdrängt sie aber nicht', () {
      final t = faxFristTexte(vorlage(
          aTage: 14, aAm: '2026-09-13', aGrund: 'nach Rückholung neu gezählt'));
      expect(t.archiv, startsWith('Archiv in 14 Tagen · '));
      expect(t.archiv, contains('Rückholung'));
    });

    test('ohne Fristen bleibt alles leer — kein Platzhalter', () {
      final t = faxFristTexte(null);
      expect(t.archiv, isEmpty);
      expect(t.inhalt, isEmpty);
    });

    test('ältere Server ohne das Feld stürzen nicht ab', () {
      // Die App wird vor dem Server ausgeliefert oder danach; in beiden
      // Richtungen darf eine fehlende Hälfte nur zu leerem Text führen.
      expect(faxFristTexte(<String, dynamic>{}).archiv, isEmpty);
      expect(faxFristTexte(<String, dynamic>{'archiv': null}).inhalt, isEmpty);
    });

    test('Datum wird deutsch geschrieben, nicht ISO', () {
      final t = faxFristTexte(vorlage(iTage: 400, iAm: '2027-01-01'));
      expect(t.inhalt, contains('01.01.2027'));
      expect(t.inhalt, isNot(contains('2027-01-01')));
    });
  });
}
