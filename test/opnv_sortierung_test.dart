// Die Sortierung der Trefferliste in „Verbindung suchen".
//
// ⚠️ Der Grund, warum das überhaupt geprüft wird, ist nicht die Reihenfolge
// selbst — Vergleiche sind langweilig. Es ist die Index-Buchführung: sortiert
// wird eine Liste von Original-Positionen, weil die Barrierefreiheits-Prüfung
// daran hängt. Wer stattdessen die Fahrten umsortiert, hängt jeder Verbindung
// das Aufzugs-Ergebnis einer anderen an, und beides sieht plausibel aus.

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/transit_service.dart';
import 'package:icd360sev_vorsitzer/utils/opnv_sortierung.dart';

DateTime _t(int h, int m) => DateTime(2026, 8, 14, h, m);

JourneyLeg _leg(String line, DateTime ab, DateTime an, {bool walk = false}) =>
    JourneyLeg(
      line: line, direction: '', fromName: 'A', toName: 'B',
      depTime: ab, arrTime: an,
      productType: walk ? 'walk' : 'bus', isWalk: walk,
      productTypeVerlaesslich: true,
    );

/// [umstiege] Fahrzeug-Etappen ⇒ `transfers` = umstiege - 1.
Journey _fahrt({
  required DateTime ab,
  required DateTime an,
  int fahrzeuge = 1,
}) {
  final legs = <JourneyLeg>[
    for (int i = 0; i < fahrzeuge; i++) _leg('L$i', ab, an),
  ];
  return Journey(legs: legs, depTime: ab, arrTime: an);
}

void main() {
  group('sortiereOpnvTreffer', () {
    // 0: 09:00→10:00 (60 min, 1 Umstieg), 1: 09:30→10:00 (30 min, 2 Umstiege),
    // 2: 08:00→10:00 (120 min, direkt)
    late List<Journey> alle;
    setUp(() {
      alle = [
        _fahrt(ab: _t(9, 0), an: _t(10, 0), fahrzeuge: 2),
        _fahrt(ab: _t(9, 30), an: _t(10, 0), fahrzeuge: 3),
        _fahrt(ab: _t(8, 0), an: _t(10, 0), fahrzeuge: 1),
      ];
    });

    int keinPreis(Journey j) => 0;

    test('Abfahrt lässt die Reihenfolge unangetastet', () {
      final sichtbar = [0, 1, 2];
      sortiereOpnvTreffer(sichtbar, alle, OpnvSortierung.abfahrt, preis: keinPreis);
      expect(sichtbar, [0, 1, 2]);
    });

    test('Schnellste ordnet nach Fahrtdauer, nicht nach Abfahrtszeit', () {
      final sichtbar = [0, 1, 2];
      sortiereOpnvTreffer(sichtbar, alle, OpnvSortierung.schnell, preis: keinPreis);
      // 30 min, 60 min, 120 min
      expect(sichtbar, [1, 0, 2]);
    });

    test('Wenig Umsteigen zählt Fahrzeugwechsel, Dauer entscheidet nur bei Gleichstand', () {
      final sichtbar = [0, 1, 2];
      sortiereOpnvTreffer(sichtbar, alle, OpnvSortierung.umstiege, preis: keinPreis);
      // 0 Umstiege, 1 Umstieg, 2 Umstiege — obwohl die direkte die längste ist.
      expect(sichtbar, [2, 0, 1]);
      expect(alle[sichtbar.first].transfers, 0);
    });

    test('Günstigste stellt voran, was das Deutschlandticket deckt', () {
      final sichtbar = [0, 1, 2];
      // Fahrt 1 kostet 45 €, Fahrt 0 kostet 10 €, Fahrt 2 ist gedeckt.
      int preis(Journey j) {
        final i = alle.indexOf(j);
        return const [10, 45, 0][i];
      }
      sortiereOpnvTreffer(sichtbar, alle, OpnvSortierung.billig, preis: preis);
      expect(sichtbar, [2, 0, 1]);
    });

    test('bei gleichem Preis gewinnt die kürzere Fahrt', () {
      final sichtbar = [0, 1, 2];
      sortiereOpnvTreffer(sichtbar, alle, OpnvSortierung.billig, preis: keinPreis);
      expect(sichtbar, [1, 0, 2]);
    });

    test('sortiert die ORIGINAL-Indizes, nicht die Fahrten', () {
      // Der eigentliche Punkt: nach dem Umsortieren muss Position x weiterhin
      // auf dieselbe Fahrt zeigen wie vorher — sonst bekommt eine Verbindung
      // die Aufzugs-Auskunft einer anderen angeheftet.
      final sichtbar = [0, 1, 2];
      final vorher = {for (final i in sichtbar) i: alle[i]};
      sortiereOpnvTreffer(sichtbar, alle, OpnvSortierung.schnell, preis: keinPreis);
      expect(sichtbar.toSet(), {0, 1, 2}, reason: 'keine Fahrt darf verschwinden');
      for (final i in sichtbar) {
        expect(identical(alle[i], vorher[i]), isTrue,
            reason: 'Index $i muss weiter auf dieselbe Fahrt zeigen');
      }
    });

    test('eine ausgeblendete Fahrt bleibt ausgeblendet', () {
      // „Barrierefrei" hat Fahrt 0 entfernt — Sortieren darf sie nicht
      // zurückholen.
      final sichtbar = [1, 2];
      sortiereOpnvTreffer(sichtbar, alle, OpnvSortierung.schnell, preis: keinPreis);
      expect(sichtbar, [1, 2]);
      expect(sichtbar.contains(0), isFalse);
    });

    test('leere und einelementige Listen sind harmlos', () {
      for (final s in OpnvSortierung.values) {
        final leer = <int>[];
        sortiereOpnvTreffer(leer, alle, s, preis: keinPreis);
        expect(leer, isEmpty);
        final eins = [1];
        sortiereOpnvTreffer(eins, alle, s, preis: keinPreis);
        expect(eins, [1]);
      }
    });
  });

  group('OpnvSortierung.ausName', () {
    test('erkennt gespeicherte Namen', () {
      expect(OpnvSortierung.ausName('schnell'), OpnvSortierung.schnell);
      expect(OpnvSortierung.ausName('billig'), OpnvSortierung.billig);
      expect(OpnvSortierung.ausName('umstiege'), OpnvSortierung.umstiege);
    });

    test('fällt bei Unbekanntem und null auf Abfahrt zurück', () {
      // Nach Name gespeichert, nicht nach Index — sonst würde eine neue
      // Sortierung in der Mitte der Aufzählung die Wahl still verschieben.
      expect(OpnvSortierung.ausName(null), OpnvSortierung.abfahrt);
      expect(OpnvSortierung.ausName(''), OpnvSortierung.abfahrt);
      expect(OpnvSortierung.ausName('gibtsnicht'), OpnvSortierung.abfahrt);
      expect(OpnvSortierung.ausName('2'), OpnvSortierung.abfahrt);
    });

    test('jede Sortierung hat einen Titel für den Knopf', () {
      for (final s in OpnvSortierung.values) {
        expect(s.titel.trim(), isNotEmpty);
      }
    });
  });
}
