// Das 3-Monats-Nachweisfenster der WBA-Unterlagen.
//
// Reine Rechnung, deshalb ohne Widget-Aufbau prüfbar — und prüfenswert, weil
// der Monatsrücksprung in Dart genau dort überläuft, wo das Fenster am
// häufigsten anfängt: am Monatsletzten.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_jobcenter.dart';

DateTimeRange _r(String von, String bis) =>
    DateTimeRange(start: jcParseDatum(von)!, end: jcParseDatum(bis)!);

void main() {
  group('jcMonateZurueck', () {
    test('31.07. minus 3 Monate ist der 30.04., nicht der 01.05.', () {
      // Der Fall aus der Praxis: DateTime(2026, 4, 31) wäre in Dart der
      // 1. Mai, das Fenster verlöre seinen ersten Tag.
      expect(jcMonateZurueck(DateTime(2026, 7, 31), 3), DateTime(2026, 4, 30));
    });

    test('kappt auf den Februar — mit und ohne Schaltjahr', () {
      expect(jcMonateZurueck(DateTime(2026, 5, 31), 3), DateTime(2026, 2, 28));
      expect(jcMonateZurueck(DateTime(2024, 5, 31), 3), DateTime(2024, 2, 29));
    });

    test('rechnet über den Jahreswechsel', () {
      expect(jcMonateZurueck(DateTime(2026, 2, 15), 3), DateTime(2025, 11, 15));
      expect(jcMonateZurueck(DateTime(2026, 1, 31), 3), DateTime(2025, 10, 31));
    });

    test('lässt einen gültigen Tag unangetastet', () {
      expect(jcMonateZurueck(DateTime(2026, 7, 15), 3), DateTime(2026, 4, 15));
    });
  });

  group('jcKontoauszugLuecken', () {
    final von = DateTime(2026, 4, 30);
    final bis = DateTime(2026, 7, 31);

    test('lückenlos abgedeckt ergibt keine Lücke', () {
      expect(
        jcKontoauszugLuecken(von: von, bis: bis, auszuege: [
          _r('2026-04-01', '2026-05-31'),
          _r('2026-06-01', '2026-06-30'),
          _r('2026-07-01', '2026-08-15'),
        ]),
        isEmpty,
      );
    });

    test('nahtlos aneinander grenzende Auszüge lassen keine Lücke', () {
      // 31.05. → 01.06. ist kein Loch, auch wenn kein Tag doppelt vorkommt.
      expect(
        jcKontoauszugLuecken(von: von, bis: bis, auszuege: [
          _r('2026-04-30', '2026-05-31'),
          _r('2026-06-01', '2026-07-31'),
        ]),
        isEmpty,
      );
    });

    test('meldet den fehlenden Monat in der Mitte', () {
      final luecken = jcKontoauszugLuecken(von: von, bis: bis, auszuege: [
        _r('2026-04-01', '2026-05-31'),
        _r('2026-07-01', '2026-07-31'),
      ]);
      expect(luecken, hasLength(1));
      expect(luecken.first.start, DateTime(2026, 6, 1));
      expect(luecken.first.end, DateTime(2026, 6, 30));
    });

    test('ohne Auszüge fehlt das ganze Fenster', () {
      final luecken = jcKontoauszugLuecken(von: von, bis: bis, auszuege: const []);
      expect(luecken, hasLength(1));
      expect(luecken.first.start, von);
      expect(luecken.first.end, bis);
    });

    test('Auszüge außerhalb des Fensters decken nichts ab', () {
      final luecken = jcKontoauszugLuecken(von: von, bis: bis, auszuege: [
        _r('2025-01-01', '2025-03-31'),
        _r('2026-09-01', '2026-09-30'),
      ]);
      expect(luecken, hasLength(1));
      expect(luecken.first.start, von);
      expect(luecken.first.end, bis);
    });

    test('überlappende und doppelte Auszüge verschmelzen', () {
      expect(
        jcKontoauszugLuecken(von: von, bis: bis, auszuege: [
          _r('2026-07-01', '2026-07-31'),
          _r('2026-04-01', '2026-06-15'),
          _r('2026-04-01', '2026-06-15'),
          _r('2026-06-10', '2026-07-05'),
        ]),
        isEmpty,
      );
    });

    test('meldet Rand-Lücken an beiden Enden', () {
      final luecken = jcKontoauszugLuecken(von: von, bis: bis, auszuege: [
        _r('2026-05-10', '2026-07-20'),
      ]);
      expect(luecken, hasLength(2));
      expect(luecken.first.start, DateTime(2026, 4, 30));
      expect(luecken.first.end, DateTime(2026, 5, 9));
      expect(luecken.last.start, DateTime(2026, 7, 21));
      expect(luecken.last.end, DateTime(2026, 7, 31));
    });
  });

  group('jcNachweisFenster', () {
    final heute = DateTime(2026, 7, 31);

    test('ein Erstellungsdatum ergibt genau die 3 Monate davor', () {
      final f = jcNachweisFenster(erstellt: [DateTime(2026, 7, 31)], heute: heute);
      expect(f.von, DateTime(2026, 4, 30));
      expect(f.bis, DateTime(2026, 7, 31));
    });

    test('zwei Erstellungsdaten spannen über beide', () {
      // WBA am 10.07., Anlage VM am 25.07.: der WBA verlangt die Auszüge ab
      // dem 10.04., die Anlage VM die bis zum 25.07. Beides muss drin sein.
      final f = jcNachweisFenster(
        erstellt: [DateTime(2026, 7, 25), DateTime(2026, 7, 10)],
        antragDatum: DateTime(2026, 6, 1),
        heute: heute,
      );
      expect(f.von, DateTime(2026, 4, 10));
      expect(f.bis, DateTime(2026, 7, 25));
    });

    test('am selben Tag erzeugt heißt dasselbe Fenster wie mit einem Datum', () {
      final zwei = jcNachweisFenster(
        erstellt: [DateTime(2026, 7, 31), DateTime(2026, 7, 31)],
        heute: heute,
      );
      final eins = jcNachweisFenster(erstellt: [DateTime(2026, 7, 31)], heute: heute);
      expect(zwei.von, eins.von);
      expect(zwei.bis, eins.bis);
    });

    test('schneidet die Uhrzeit aus dem created_at ab', () {
      final f = jcNachweisFenster(erstellt: [DateTime(2026, 7, 10, 14, 33, 7)], heute: heute);
      expect(f.von, DateTime(2026, 4, 10));
      expect(f.bis, DateTime(2026, 7, 10));
    });

    test('fällt ohne Erstellung auf das Antragsdatum zurück', () {
      final f = jcNachweisFenster(
        erstellt: const [],
        antragDatum: DateTime(2026, 6, 1),
        heute: heute,
      );
      expect(f.von, DateTime(2026, 3, 1));
      expect(f.bis, DateTime(2026, 6, 1));
    });

    test('fällt ganz ohne Datum auf heute zurück', () {
      final f = jcNachweisFenster(erstellt: const [], heute: heute);
      expect(f.von, DateTime(2026, 4, 30));
      expect(f.bis, heute);
    });
  });

  group('jcParseDatum', () {
    test('liest ISO, ISO mit Uhrzeit und das deutsche Format', () {
      expect(jcParseDatum('2026-07-31'), DateTime(2026, 7, 31));
      expect(jcParseDatum('2026-07-31 14:33:07'), DateTime(2026, 7, 31));
      expect(jcParseDatum('31.07.2026'), DateTime(2026, 7, 31));
      expect(jcParseDatum('1.7.2026'), DateTime(2026, 7, 1));
    });

    test('gibt bei Leer und Unsinn null zurück', () {
      expect(jcParseDatum(null), isNull);
      expect(jcParseDatum('  '), isNull);
      expect(jcParseDatum('demnächst'), isNull);
    });
  });
}
