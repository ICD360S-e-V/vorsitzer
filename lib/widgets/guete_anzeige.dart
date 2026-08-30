/// Zeigt die gemessene Güte eines Gesprächs — als Punkt und als Tafel.
///
/// ⚠️ AN JEDER AUSGABE STEHT, WAS DIE ZAHL NICHT IST. Gemessen wird die
/// WebRTC-Strecke bis sipgate; was dahinter im Telefonnetz geschieht, sieht
/// niemand von hier. Und der MOS ist eine SCHÄTZUNG nach einem abgewandelten
/// E-Modell, keine Messung des Höreindrucks. Beides gehört an den Wert, nicht
/// in eine Fussnote, die keiner liest.
library;

import 'package:flutter/material.dart';

import '../services/qualitaets_sonde.dart';
import '../utils/gespraechsqualitaet.dart';
import '../utils/app_farben.dart';

Color gueteFarbe(QualitaetsStufe s) => switch (s) {
  QualitaetsStufe.gut => const Color(0xFF2E7D32),
  QualitaetsStufe.brauchbar => const Color(0xFFF9A825),
  QualitaetsStufe.schlecht => const Color(0xFFEF6C00),
  QualitaetsStufe.unbrauchbar => const Color(0xFFC62828),
  QualitaetsStufe.unbekannt => Colors.grey,
};

/// Aus einem gespeicherten MOS die Stufe zurückgewinnen — für den Verlauf,
/// wo nur die Zahl in der Datenbank steht.
QualitaetsStufe gueteStufeAusMos(double mos) => switch (mos) {
  >= 4.0 => QualitaetsStufe.gut,
  >= 3.4 => QualitaetsStufe.brauchbar,
  >= 2.6 => QualitaetsStufe.schlecht,
  _ => QualitaetsStufe.unbrauchbar,
};

String gueteStufeText(QualitaetsStufe s) => switch (s) {
  QualitaetsStufe.gut => 'gut',
  QualitaetsStufe.brauchbar => 'brauchbar',
  QualitaetsStufe.schlecht => 'schlecht',
  QualitaetsStufe.unbrauchbar => 'kaum verständlich',
  QualitaetsStufe.unbekannt => 'unbekannt',
};

/// Der kleine Punkt für die Gesprächskarte.
///
/// ⚠️ Farbe UND Wort, nie Farbe allein. Rot-Grün-Blindheit betrifft etwa
/// jeden zwölften Mann, und in einem Verein für Menschen mit Behinderung ist
/// das keine Feinheit (WCAG 1.4.1).
class GuetePunkt extends StatelessWidget {
  const GuetePunkt({super.key, required this.probe, this.hell = false});

  final QualitaetsProbe? probe;
  final bool hell;

  @override
  Widget build(BuildContext context) {
    final p = probe;
    if (p == null) {
      return Text(
        'Güte wird gemessen …',
        style: TextStyle(
          fontSize: 11,
          color: hell ? Colors.white70 : F.h(Colors.grey, 600),
        ),
      );
    }
    final farbe = hell ? Colors.white : gueteFarbe(p.stufe);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: hell ? Colors.white : gueteFarbe(p.stufe),
            shape: BoxShape.circle,
            // Auf farbigem Grund braucht der Punkt einen Rand, sonst
            // verschwindet Grün auf Grün.
            border: hell ? Border.all(color: Colors.white54) : null,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          'Verbindung ${gueteStufeText(p.stufe)}',
          style: TextStyle(fontSize: 11, color: farbe),
        ),
      ],
    );
  }
}

/// Die vollständige Tafel — alles, was gemessen wurde, mit Einordnung.
class GueteTafel extends StatelessWidget {
  const GueteTafel({super.key, required this.probe, this.bilanz});

  final QualitaetsProbe probe;
  final QualitaetsBilanz? bilanz;

  @override
  Widget build(BuildContext context) {
    final p = probe;
    final b = bilanz;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _kopf(context, p),
        const SizedBox(height: 10),
        _gruppe(context, 'Was bei uns ankommt', [
          _zeile(
            'Verlust',
            '${p.verlustProzent.toStringAsFixed(1)} %',
            'Anteil der Sprachpakete, die im letzten Takt nicht ankamen.',
          ),
          _zeile(
            'Schwankung (Jitter)',
            '${p.jitterMs.round()} ms',
            'Wie ungleichmässig die Pakete eintreffen. Der Entzerrerpuffer '
                'gleicht das aus — mit Verzögerung.',
          ),
          _zeile(
            'Entzerrerpuffer',
            '${p.pufferMs.round()} ms',
            'Ein grosser Puffer ist NICHT schlecht: er kauft '
                'Verständlichkeit mit Verzögerung.',
          ),
          if (p.verdecktAnteil != null)
            _zeile(
              'Erfundener Ton',
              '${(p.verdecktAnteil! * 100).toStringAsFixed(2)} %',
              'Tonproben, die der Decoder selbst erzeugen musste. ⚠️ Das ist '
                  'die einzige Zahl hier, die kein Modell ist, sondern eine '
                  'Messung dessen, was dem Ton wirklich zugestossen ist — '
                  'ohne die eingefügte Stille, die getrennt steht.',
            ),
          if (p.stilleAnteil != null && p.stilleAnteil! > 0)
            _zeile(
              'davon Stille',
              '${(p.stilleAnteil! * 100).toStringAsFixed(2)} %',
              'Eingefügte Stille oder Komfortrauschen — gehört zur Auskunft, '
                  'nicht zum Schaden. Bei aktivem DTX ist das der Normalfall in '
                  'Sprechpausen.',
            ),
          if (p.verdeckungEreignisse != null)
            _zeile(
              'Lücken (gesamt)',
              '${p.verdeckungEreignisse}',
              'Wie oft eine Lücke begonnen hat. Viele kurze Aussetzer hört '
                  'man anders als einen langen gleicher Dauer.',
            ),
          if (p.gedehnteProben != null || p.gestraffteProben != null)
            _zeile(
              'Ton gedehnt / gestrafft',
              '${p.gedehnteProben ?? 0} / ${p.gestraffteProben ?? 0}',
              'Proben, die der Entzerrer eingefügt oder weggelassen hat, um '
                  'den Puffer zu halten — die hörbare Seite von Schwankung.',
            ),
        ]),
        _gruppe(context, 'Was die Gegenstelle über uns meldet', [
          if (p.fernVerlustProzent != null)
            _zeile(
              'Verlust dorthin',
              '${p.fernVerlustProzent!.toStringAsFixed(1)} %',
              'Aus dem RTCP-Bericht der Gegenstelle — die einzige Sicht auf '
                  'die andere Richtung.',
            )
          else
            _zeile(
              'Verlust dorthin',
              'noch keine Rückmeldung',
              '⚠️ Das heisst NICHT „kein Verlust". Der Bericht der '
                  'Gegenstelle kommt erst nach ein paar Sekunden; bis dahin '
                  'wissen wir über diese Richtung nichts.',
            ),
          if (p.fernJitterMs != null)
            _zeile('Schwankung dorthin', '${p.fernJitterMs!.round()} ms', null),
          if (p.rttMs != null)
            _zeile(
              'Umlaufzeit',
              '${p.rttMs!.round()} ms',
              'Hin und zurück. Die halbe Zeit geht als Verzögerung in die '
                  'Bewertung ein.',
            ),
        ]),
        _gruppe(context, 'Verbindung', [
          if (p.codec != null)
            _zeile(
              'Codec',
              '${p.codec}${p.abtastrate != null ? ' · ${(p.abtastrate! / 1000).round()} kHz' : ''}',
              null,
            ),
          _zeile(
            'Fehlerkorrektur (FEC)',
            p.fec ? 'an' : 'aus',
            'Mit FEC übersteht Opus Verlust deutlich besser — die Bewertung '
                'rechnet das mit ein (Bpl 20 statt 10).',
          ),
          if (p.dtx)
            _zeile(
              'Sparbetrieb (DTX)',
              'an',
              'In Sprechpausen wird nichts übertragen. Das erklärt eingefügte '
                  'Stille.',
            ),
          if (p.bitrateEmpfang != null)
            _zeile(
              'Bitrate ein/aus',
              '${(p.bitrateEmpfang! / 1000).round()} / '
                  '${p.bitrateSenden == null ? '?' : (p.bitrateSenden! / 1000).round()} kbit/s',
              null,
            ),
          if (p.wegTyp != null)
            _zeile(
              'Weg',
              _wegText(p.wegTyp!, p.wegProtokoll),
              p.wegTyp == 'relay'
                  ? '⚠️ Der Ton läuft über den TURN-Server, also einen '
                        'Umweg. Das erklärt Verzögerung, ohne dass die Leitung '
                        'schlecht wäre.'
                  : null,
            ),
          if (p.netzTyp != null) _zeile('Netz', p.netzTyp!, null),
        ]),
        if (b != null && b.proben.length > 2) ...[
          _gruppe(context, 'Bisher in diesem Gespräch', [
            _zeile(
              'Mittlere Güte (Median)',
              b.mosMedian.toStringAsFixed(2),
              '⚠️ Median, nicht Mittelwert: ein einziger Aussetzer zöge einen '
                  'Mittelwert weit herunter und behauptete ein Gespräch, das so '
                  'nicht war.',
            ),
            _zeile('Schlechtester Wert', b.mosSchlechtester.toStringAsFixed(2), null),
            _zeile(
              'Anteil schlecht',
              '${b.anteilSchlecht.toStringAsFixed(0)} %',
              'Wie oft es unter „brauchbar" lag. Diese Zahl trägt eine '
                  'Beschwerde besser als jeder Einzelwert.',
            ),
            _zeile('Höchster Verlust', '${b.verlustMax.toStringAsFixed(1)} %', null),
          ]),
        ],
        const SizedBox(height: 8),
        Text(
          '⚠️ Gemessen wird die Strecke bis sipgate, nicht das ganze Gespräch: '
          'was dahinter im Telefonnetz passiert, ist von hier aus nicht '
          'sichtbar. Der Wert ist eine Schätzung nach einem für WebRTC '
          'abgewandelten E-Modell (rtcscore), nicht nach ITU-T G.107.',
          style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600)),
        ),
      ],
    );
  }

  static String _wegText(String typ, String? protokoll) {
    final t = switch (typ) {
      'host' => 'direkt',
      'srflx' => 'direkt (über STUN ermittelt)',
      'prflx' => 'direkt (unterwegs erkannt)',
      'relay' => 'über TURN-Server (Umweg)',
      _ => typ,
    };
    return protokoll == null ? t : '$t · ${protokoll.toUpperCase()}';
  }

  Widget _kopf(BuildContext ctx, QualitaetsProbe p) {
    final farbe = gueteFarbe(p.stufe);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: farbe.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: farbe),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.graphic_eq, size: 16, color: farbe),
              const SizedBox(width: 6),
              Text(
                gueteStufeText(p.stufe),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: farbe),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'MOS ${p.mos.toStringAsFixed(2)} · R ${p.bewertung.r.round()}',
            style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700)),
          ),
        ),
      ],
    );
  }

  Widget _gruppe(BuildContext ctx, String titel, List<Widget> zeilen) {
    // Eine Gruppe, aus der jede Zeile herausgefallen ist, wird gar nicht
    // gezeichnet — sonst stünde eine Überschrift über nichts.
    if (zeilen.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 10),
        Text(
          titel,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: F.h(Colors.grey, 700),
          ),
        ),
        const SizedBox(height: 4),
        ...zeilen,
      ],
    );
  }

  Widget _zeile(String was, String wert, String? erklaerung) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text(was, style: const TextStyle(fontSize: 12))),
              Text(
                wert,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (erklaerung != null)
            Padding(
              padding: const EdgeInsets.only(top: 1, right: 40),
              child: Text(
                erklaerung,
                style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600)),
              ),
            ),
        ],
      ),
    );
  }
}
