import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/arzt_quelle.dart';
import 'package:icd360sev_vorsitzer/utils/krankenhaus_gruppen.dart';

Map<String, dynamic> abteilung(String name, String haus, {String? fach}) => {
      'selected_arzt': klinikAlsArzt({
        'id': name.hashCode.abs() % 1000,
        'name': name,
        'krankenhaus': haus,
        if (fach != null) 'fachrichtung': fach,
      }),
    };

void main() {
  group('hausAusInstanz', () {
    test('nimmt die Spalte krankenhaus aus kliniken_datenbank', () {
      expect(
        hausAusInstanz(abteilung('Klinik für Innere Medizin – Gastroenterologie',
            'Bundeswehrkrankenhaus Ulm')),
        'Bundeswehrkrankenhaus Ulm',
      );
    });

    test('eine leere Instanz bleibt sichtbar statt zu verschwinden', () {
      expect(hausAusInstanz(null), kOhneHaus);
      expect(hausAusInstanz({}), kOhneHaus);
      expect(hausAusInstanz({'selected_arzt': {}}), kOhneHaus);
    });

    test('ein Praxis-Eintrag nutzt praxis_name, nicht krankenhaus', () {
      // Praxis-Tabellen haben keine Spalte `krankenhaus`; ein zufällig
      // gleichnamiges Feld darf die Gruppierung nicht kapern.
      final praxis = {
        'selected_arzt': {'id': 3, 'praxis_name': 'Praxis am Ring', 'arzt_name': 'Dr. Muster'}
      };
      expect(hausAusInstanz(praxis), 'Praxis am Ring');
    });
  });

  group('abteilungsName', () {
    test('schneidet den Hausnamen hinten ab', () {
      final a = abteilung('Klinik für Augenheilkunde — Universitätsklinikum Ulm',
          'Universitätsklinikum Ulm');
      expect(abteilungsName(a, nummer: 1), 'Klinik für Augenheilkunde');
    });

    test('lässt einen Namen ohne Hausanhang unverändert', () {
      final a = abteilung('Sturzambulanz', 'Agaplesion Bethesda Klinik Ulm');
      expect(abteilungsName(a, nummer: 1), 'Sturzambulanz');
    });

    test('das Haus selbst zeigt seine Fachrichtung, nicht sich doppelt', () {
      final a = abteilung('Bundeswehrkrankenhaus Ulm', 'Bundeswehrkrankenhaus Ulm',
          fach: 'Alle Fachrichtungen');
      expect(abteilungsName(a, nummer: 1), 'Alle Fachrichtungen');
    });

    test('ohne Auswahl eine brauchbare Ersatzbeschriftung', () {
      expect(abteilungsName(null, nummer: 4), 'Abteilung 4');
    });
  });

  group('krankenhausGruppieren', () {
    test('gruppiert nach Haus in Reihenfolge des ersten Auftretens', () {
      final g = krankenhausGruppieren([
        abteilung('Gastroenterologie', 'Bundeswehrkrankenhaus Ulm'),
        abteilung('Klinik für Augenheilkunde', 'Universitätsklinikum Ulm'),
        abteilung('Neurologie', 'Bundeswehrkrankenhaus Ulm'),
      ]);
      expect(g.map((x) => x.haus).toList(),
          ['Bundeswehrkrankenhaus Ulm', 'Universitätsklinikum Ulm']);
      expect(g[0].instanzen, [0, 2]);
      expect(g[1].instanzen, [1]);
    });

    test('⚠️ die Indizes bleiben GLOBAL — sonst schreibt das Speichern falsch', () {
      final g = krankenhausGruppieren([
        abteilung('A', 'Haus 1'),
        abteilung('B', 'Haus 2'),
        abteilung('C', 'Haus 2'),
        abteilung('D', 'Haus 1'),
      ]);
      expect(g[1].instanzen, [1, 2]);
      expect(g[0].instanzen, [0, 3]);
      // Jeder Index kommt genau einmal vor, keiner geht verloren.
      final alle = g.expand((x) => x.instanzen).toList()..sort();
      expect(alle, [0, 1, 2, 3]);
    });

    test('eine noch leere Instanz bekommt eine eigene Gruppe', () {
      final g = krankenhausGruppieren([abteilung('A', 'Haus 1'), null]);
      expect(g.length, 2);
      expect(g.last.haus, kOhneHaus);
      expect(g.last.instanzen, [1]);
    });

    test('21 Abteilungen eines Hauses bleiben eine Gruppe', () {
      final g = krankenhausGruppieren([
        for (var i = 0; i < 21; i++) abteilung('Abteilung $i', 'Bundeswehrkrankenhaus Ulm')
      ]);
      expect(g.length, 1);
      expect(g.single.instanzen.length, 21);
      expect(g.single.instanzen.last, 20);
    });

    test('leere Liste ergibt keine Gruppe', () {
      expect(krankenhausGruppieren([]), isEmpty);
    });
  });

  group('gruppeVonInstanz', () {
    final g = krankenhausGruppieren([
      abteilung('A', 'Haus 1'),
      abteilung('B', 'Haus 2'),
      abteilung('C', 'Haus 1'),
    ]);

    test('findet die Gruppe der gewählten Instanz', () {
      expect(gruppeVonInstanz(g, 0), 0);
      expect(gruppeVonInstanz(g, 1), 1);
      expect(gruppeVonInstanz(g, 2), 0);
    });

    test('ein unbekannter Index landet auf einem gültigen Haus, nicht im Leeren', () {
      expect(gruppeVonInstanz(g, 99), 0);
      expect(gruppeVonInstanz(const [], 0), 0);
    });
  });
}
