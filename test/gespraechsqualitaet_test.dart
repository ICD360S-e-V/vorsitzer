import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/gespraechsqualitaet.dart';

/// ⚠️ DER GRUND FÜR DIESE DATEI STEHT IN EINER ZAHL.
///
/// Das E-Modell des Speedtests (`api/speedtest/_common.php`) rechnet mit
/// `Bpl = 1,0` — dem Verlust-Robustheitsfaktor eines Codecs ohne jede
/// Fehlerverschleierung. Dort fiel das nie auf, weil Verlust über TCP nicht
/// messbar ist und immer 0 eingesetzt wurde. Auf der Sprachstrecke ist er
/// messbar, und mit jenen Werten ergäbe 1 % Verlust ein MOS von **2,35** —
/// nachgerechnet mit genau jener Funktion. Für Opus mit FEC ist das falsch.
///
/// Hier gelten `Bpl = 20` (mit FEC) bzw. 10, nach `rtcscore` /
/// `livekit/rtcscore-go`. Diese Tests halten den Unterschied fest, damit
/// niemand die Parameter „vereinheitlicht".
void main() {
  group('Verlust darf Opus nicht umbringen', () {
    test('1 % Verlust mit FEC bleibt gut hörbar', () {
      final q = gespraechsQualitaet(
          verlustProzent: 1, rttMs: 40, pufferMs: 40, bitrate: 24000);
      // Das Gegenstück im Speedtest-Modell wäre 2,35.
      expect(q.mos, greaterThan(4.0), reason: 'MOS war ${q.mos}');
      expect(q.stufe, QualitaetsStufe.gut);
    });

    test('ohne FEC ist derselbe Verlust spürbarer', () {
      final mit = gespraechsQualitaet(
          verlustProzent: 3, rttMs: 40, pufferMs: 40, bitrate: 24000, fec: true);
      final ohne = gespraechsQualitaet(
          verlustProzent: 3, rttMs: 40, pufferMs: 40, bitrate: 24000, fec: false);
      expect(ohne.mos, lessThan(mit.mos));
    });

    test('RED steckt selbst 10 % weitgehend weg', () {
      final q = gespraechsQualitaet(
          verlustProzent: 10, rttMs: 40, pufferMs: 40, bitrate: 24000, red: true);
      expect(q.mos, greaterThan(3.5), reason: 'MOS war ${q.mos}');
    });

    test('sehr hoher Verlust wird trotzdem als schlecht erkannt', () {
      final q = gespraechsQualitaet(
          verlustProzent: 30, rttMs: 40, pufferMs: 40, bitrate: 24000);
      expect(q.mos, lessThan(3.0), reason: 'MOS war ${q.mos}');
    });
  });

  group('Verzögerung', () {
    test('unter dem Knick von 150 ms nur linear', () {
      final a = gespraechsQualitaet(verlustProzent: 0, rttMs: 40, pufferMs: 40);
      final b = gespraechsQualitaet(verlustProzent: 0, rttMs: 80, pufferMs: 40);
      expect(a.mos, greaterThan(b.mos));
      expect(a.mos - b.mos, lessThan(0.2), reason: 'kein Absturz unterhalb des Knicks');
    });

    test('jenseits des Knicks fällt es deutlich', () {
      final nah = gespraechsQualitaet(verlustProzent: 0, rttMs: 40, pufferMs: 40);
      final fern = gespraechsQualitaet(verlustProzent: 0, rttMs: 600, pufferMs: 400);
      expect(fern.mos, lessThan(nah.mos - 1.0), reason: 'MOS war ${fern.mos}');
    });
  });

  group('Ränder und Vorgaben', () {
    test('MOS bleibt zwischen 1 und 5', () {
      final schlimm = gespraechsQualitaet(
          verlustProzent: 100, rttMs: 5000, pufferMs: 5000, bitrate: 6000);
      expect(schlimm.mos, inInclusiveRange(1, 5));
      expect(schlimm.r, inInclusiveRange(0, 100));
      final bestens = gespraechsQualitaet(
          verlustProzent: 0, rttMs: 0, pufferMs: 0, bitrate: 64000);
      expect(bestens.mos, inInclusiveRange(1, 5));
    });

    test('fehlende Werte greifen auf die Vorgaben der Vorlage zurück', () {
      final q = gespraechsQualitaet(verlustProzent: 0);
      expect(q.rttMs, kQualitaetRttVorgabeMs);
      expect(q.pufferMs, kQualitaetPufferVorgabeMs);
    });

    test('negativer Verlust wird nicht zu einem Bonus', () {
      final q = gespraechsQualitaet(verlustProzent: -5, rttMs: 40, pufferMs: 40);
      expect(q.verlustProzent, 0);
    });
  });

  group('die Messung schlägt das Modell', () {
    test('der verdeckte Anteil wird durchgereicht, nicht verrechnet', () {
      // ⚠️ Absichtlich: `mos` ist eine Schätzung, `verdecktAnteil` eine
      // Messung dessen, was dem Ton wirklich zugestossen ist. Sie in eine Zahl
      // zu mischen hiesse, die belastbarere hinter der schwächeren zu
      // verstecken.
      final q = gespraechsQualitaet(
          verlustProzent: 0, rttMs: 40, pufferMs: 40, verdecktAnteil: 0.12);
      expect(q.verdecktAnteil, 0.12);
      expect(q.mos, greaterThan(4.0));
    });
  });
}
