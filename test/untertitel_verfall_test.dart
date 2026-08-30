// Die Verfallsregel der Mitschrift.
//
// ⚠️ WOZU: bis zum 30.08.2026 sammelte der Dienst die letzten zwölf Sätze des
// GANZEN Gesprächs. In der Gesprächskarte ist aber nur Platz für drei Zeilen —
// und ein Text, der ein ganzes Telefonat mitführt, ist der Sache nach ein
// Protokoll, auch wenn er nur im Speicher steht. Jetzt macht Gesagtes Platz
// für das, was gerade gesagt wird.
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/untertitel_service.dart';

void main() {
  final t0 = DateTime(2026, 8, 30, 20, 0, 0);
  ({String satz, DateTime seit}) satz(String s, int vorSekunden) =>
      (satz: s, seit: t0.subtract(Duration(seconds: vorSekunden)));

  test('was älter ist als die Haltezeit, fällt weg', () {
    final sicht = untertitelSichtbar(
      [satz('ganz alt', kUntertitelHaltenSekunden + 1), satz('frisch', 1)],
      '',
      t0,
    );
    expect(sicht, 'frisch');
  });

  test('genau an der Grenze bleibt es stehen', () {
    // ⚠️ Absichtlich `isBefore` und nicht `<=`: an der Sekundengrenze lieber
    // einen Takt zu lang stehen lassen als einen Satz zu früh wegnehmen.
    final sicht = untertitelSichtbar(
      [satz('gerade noch', kUntertitelHaltenSekunden)],
      '',
      t0,
    );
    expect(sicht, 'gerade noch');
  });

  test('die Reihenfolge bleibt, älteste zuerst', () {
    final sicht = untertitelSichtbar(
      [satz('erster', 4), satz('zweiter', 2), satz('dritter', 1)],
      '',
      t0,
    );
    expect(sicht, 'erster zweiter dritter');
  });

  test('der angefangene Satz verfällt NIE', () {
    // Er ist das, was gerade gesprochen wird — er hat noch gar keine Zeit
    // gehabt, alt zu werden.
    final sicht = untertitelSichtbar(
      [satz('lange her', 99)],
      'und jetzt rede ich',
      t0,
    );
    expect(sicht, 'und jetzt rede ich');
  });

  test('der angefangene Satz steht HINTER den fertigen', () {
    final sicht = untertitelSichtbar([satz('fertig', 1)], 'im Gange', t0);
    expect(sicht, 'fertig im Gange');
  });

  test('alles abgelaufen und nichts im Gange heisst leer', () {
    // Das Fenster wird bewusst leer — kein Rest, der stehen bleibt.
    expect(untertitelSichtbar([satz('weg', 60)], '', t0), '');
    expect(untertitelSichtbar([], '', t0), '');
  });

  test('Leerraum im angefangenen Satz zählt nicht als Text', () {
    expect(untertitelSichtbar([], '   ', t0), '');
  });
}
