/// Wie gut ein laufendes Gespräch gerade ist — aus dem, was WebRTC misst.
///
/// ⚠️ WARUM NICHT DAS E-MODELL AUS DEM SPEEDTEST.
/// `api/speedtest/_common.php` rechnet ITU-T G.107 mit den Vorgabewerten der
/// Tabelle 2 — darunter `Bpl = 1,0`, den Verlust-Robustheitsfaktor. Der
/// Parameter steht dort auf dem ungünstigsten denkbaren Wert, weil Verlust über
/// TCP gar nicht messbar war und deshalb immer 0 eingesetzt wurde; er fiel nie
/// ins Gewicht.
///
/// Auf der Sprachstrecke IST er messbar — und mit `Bpl = 1,0` ergäbe schon
/// **1 % Verlust ein MOS von 2,35** und 2 % eines von 1,60 (nachgerechnet mit
/// genau jener Funktion). Für Opus ist das schlicht falsch: der Codec hat
/// Fehlerverschleierung und optional FEC und übersteht ein paar Prozent nahezu
/// unhörbar. Eine solche Zahl in einer Beschwerde wäre in einem Satz zu
/// widerlegen.
///
/// ⚠️ UND DIE ITU HAT DAFÜR KEINE ZAHLEN. Opus steht **nicht** in Anhang I der
/// G.113; offizielle `Ie`/`Bpl` für ihn gibt es nicht (die Frage danach auf der
/// Opus-Liste blieb unbeantwortet). Was es gibt, sind Schätzungen aus der
/// Praxis.
///
/// DESHALB: die Rechnung hier folgt `rtcscore` von Gustavo García
/// (github.com/ggarber/rtcscore) in der Fassung, die LiveKit als
/// `rtcscore-go/pkg/rtcmos/audioscore.go` pflegt — ein **abgewandeltes**
/// E-Modell, ausdrücklich für WebRTC und Opus parametriert. Abweichungen von
/// G.107, die man kennen muss:
///
///   * `R0 = 100` statt 93,2
///   * `Ie` wird aus der Bitrate geschätzt, nicht aus einer Codec-Tabelle
///   * `Bpl = 10`, mit Opus-FEC `20`, mit RED `90` — gegen 1,0 bei uns
///   * die Verzögerung geht linear ein (`0,03 · Ta`), nicht über Gl. 3-27/3-28
///
/// Das Ergebnis heisst deshalb **nie** „nach ITU-T G.107". Es ist eine
/// Schätzung nach einem verbreiteten Verfahren, und genau so steht es an jeder
/// Ausgabe.
library;

import 'dart:math' as math;

/// Vorgaben aus `rtcmos.go`, wenn eine Grösse fehlt.
const double kQualitaetRttVorgabeMs = 50;
const double kQualitaetPufferVorgabeMs = 50;

/// Paketierungsverzögerung, die `audioscore.go` fest annimmt.
const double kQualitaetPaketierungMs = 20;

/// Verlust-Robustheit. ⚠️ Der Unterschied zu `SPEEDTEST_MOS_BPL = 1.0` ist der
/// ganze Grund für diese Datei.
const double kQualitaetBpl = 10;
const double kQualitaetBplFec = 20;
const double kQualitaetBplRed = 90;

double _klemm(double w, double min, double max) =>
    math.max(min, math.min(w, max));

/// Wie eine Bewertung einzuordnen ist. Die Grenzen folgen der üblichen
/// MOS-Einteilung; sie stehen hier, damit die Oberfläche nicht selbst welche
/// erfindet.
enum QualitaetsStufe { gut, brauchbar, schlecht, unbrauchbar, unbekannt }

class Gespraechsqualitaet {
  const Gespraechsqualitaet({
    required this.r,
    required this.mos,
    required this.verlustProzent,
    required this.rttMs,
    required this.pufferMs,
    this.verdecktAnteil,
    this.fec = true,
  });

  /// Bewertungsfaktor 0–100 (⚠️ nicht der R-Wert der G.107, dort 0–93,2).
  final double r;

  /// Geschätzte Hörqualität 1–5.
  final double mos;

  final double verlustProzent;
  final double rttMs;
  final double pufferMs;

  /// Anteil der Tonproben, die der Decoder selbst erfinden musste (0–1).
  ///
  /// ⚠️ DAS IST DIE EINZIGE ZAHL HIER, DIE KEIN MODELL IST. `mos` ist eine
  /// Schätzung aus Verlust und Verzögerung; dies ist eine Messung dessen, was
  /// dem Ton tatsächlich zugestossen ist. Wo beide auseinandergehen, hat diese
  /// recht.
  final double? verdecktAnteil;

  final bool fec;

  QualitaetsStufe get stufe => switch (mos) {
        >= 4.0 => QualitaetsStufe.gut,
        >= 3.4 => QualitaetsStufe.brauchbar,
        >= 2.6 => QualitaetsStufe.schlecht,
        _ => QualitaetsStufe.unbrauchbar,
      };

  String get stufeText => switch (stufe) {
        QualitaetsStufe.gut => 'gut',
        QualitaetsStufe.brauchbar => 'brauchbar',
        QualitaetsStufe.schlecht => 'schlecht',
        QualitaetsStufe.unbrauchbar => 'kaum verständlich',
        QualitaetsStufe.unbekannt => 'unbekannt',
      };
}

/// Rechnet eine Momentaufnahme in eine Bewertung um.
///
/// [bitrate] in bit/s; `null` heisst „nicht bekannt" und führt auf `Ie = 6`,
/// den Vorgabewert der Vorlage.
Gespraechsqualitaet gespraechsQualitaet({
  required double verlustProzent,
  double? rttMs,
  double? pufferMs,
  int? bitrate,
  bool fec = true,
  bool dtx = false,
  bool red = false,
  double? verdecktAnteil,
}) {
  final rtt = rttMs ?? kQualitaetRttVorgabeMs;
  final puffer = pufferMs ?? kQualitaetPufferVorgabeMs;
  final pl = math.max(0.0, verlustProzent);

  // Einweg: halbe Umlaufzeit plus Entzerrerpuffer plus Paketierung.
  final verzoegerung = kQualitaetPaketierungMs + puffer + rtt / 2;

  final double ie;
  if (dtx) {
    ie = 8;
  } else if (bitrate != null && bitrate > 0) {
    ie = _klemm(55 - 4.6 * math.log(bitrate.toDouble()), 0, 30);
  } else {
    ie = 6;
  }

  final bpl = red ? kQualitaetBplRed : (fec ? kQualitaetBplFec : kQualitaetBpl);
  final ipl = ie + (100 - ie) * (pl / (pl + bpl));

  // ⚠️ Der Knick bei 150 ms ist der Punkt, ab dem Verzögerung im Gespräch
  // wirklich stört (Gegenrede kommt zu spät). Unterhalb wächst die
  // Beeinträchtigung nur linear mit.
  final knick = verzoegerung > 150 ? 0.1 * (verzoegerung - 150) : 0.0;
  final id = verzoegerung * 0.03 + knick;

  final r = _klemm(100 - ipl - id, 0, 100);
  // Umrechnung R -> MOS wie in Anhang B/G.107; diese Hälfte ist unverändert.
  final mos = _klemm(1 + 0.035 * r + (r * (r - 60) * (100 - r) * 7) / 1000000, 1, 5);

  return Gespraechsqualitaet(
    r: r,
    mos: (mos * 100).roundToDouble() / 100,
    verlustProzent: pl,
    rttMs: rtt,
    pufferMs: puffer,
    verdecktAnteil: verdecktAnteil,
    fec: fec,
  );
}
