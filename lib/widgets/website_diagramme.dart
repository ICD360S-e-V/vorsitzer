import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Diagramme für den Bildschirm „Website".
///
/// Alle rechnen mit ganzen Zahlen und zeichnen selbst — es kommt keine
/// Diagrammbibliothek dazu. Der Auftritt, um den es geht, kommt ohne fremde
/// Gegenstellen aus; eine Bibliothek für vier Balkenarten wäre hier die
/// falsche Richtung, und jede zusätzliche Abhängigkeit ist eine, die bei
/// einem Flutter-Wechsel bricht.
///
/// ⚠️ Farben bedeuten in diesem Bildschirm ÜBERALL dasselbe:
/// grün = Menschen, blaugrau = Maschinen, rot = Angriffsversuche.
/// Wer eine davon ändert, ändert sie in [webArtFarbe] und damit in allen
/// Diagrammen zugleich — zwei Karten mit vertauschten Farben wären schlimmer
/// als gar keine Farbe.

const Color kWebMensch = Color(0xFF2E7D32);
const Color kWebMaschine = Color(0xFF546E7A);
const Color kWebScan = Color(0xFFC62828);

Color webArtFarbe(String art) => switch (art) {
      'mensch' => kWebMensch,
      'bot' || 'maschine' => kWebMaschine,
      'scan' => kWebScan,
      _ => const Color(0xFF9E9E9E),
    };

String webArtName(String art) => switch (art) {
      'mensch' => 'Menschen',
      'bot' || 'maschine' => 'Maschinen',
      'scan' => 'Angriffsversuche',
      _ => art,
    };

/// Prozent in deutscher Schreibweise.
/// ⚠️ `toStringAsFixed` liefert den Punkt als Dezimaltrennzeichen — auf einer
/// durchweg deutschen Oberflaeche liest sich „83.1 %" wie ein Tippfehler.
String webProzent(int teil, int gesamt) {
  if (gesamt <= 0) return '—';
  return '${(teil / gesamt * 100).toStringAsFixed(1).replaceFirst('.', ',')} %';
}

/// Ein Wert einer Reihe.
class WebPunkt {
  final String beschriftung;
  final String? unterBeschriftung;
  final List<int> werte;
  const WebPunkt(this.beschriftung, this.werte, {this.unterBeschriftung});

  int get summe => werte.fold(0, (a, b) => a + b);
}

/// Gestapelte Säulen mit waagerechtem Bildlauf.
///
/// ⚠️ Nicht auf die Breite verteilen, sondern scrollen: bei einem Jahr wären
/// 365 Säulen schmaler als ein Pixel, und das Diagramm zeigte nichts mehr.
class WebSaeulen extends StatelessWidget {
  final List<WebPunkt> punkte;
  final List<Color> farben;
  final List<String> reihenNamen;
  final double hoehe;
  final bool neuesteRechts;

  const WebSaeulen({
    super.key,
    required this.punkte,
    required this.farben,
    required this.reihenNamen,
    this.hoehe = 150,
    this.neuesteRechts = true,
  });

  /// ⚠️ Feste Zeilenhöhen, keine Schriftvorgabe.
  ///
  /// Ohne `height:` bestimmt die Schrift die Zeilenhöhe, und die Rechnung
  /// unten stimmt nur zufällig für die gerade eingestellte. Beim Rendern mit
  /// Noto lief die Säule um 1,5 Pixel über — sichtbar als gelb-schwarzer
  /// Streifen, von `flutter analyze` nicht zu finden und von keinem Test, der
  /// die Oberfläche nicht wirklich zeichnet.
  static const double _zeile = 1.25;
  static const double _zahlGroesse = 9;
  static const double _labelGroesse = 9;
  static const double _unterGroesse = 8;
  static const double _abstaende = 5;

  /// Höhen aller Segmente EINER Säule.
  ///
  /// ⚠️ Muss für den ganzen Stapel auf einmal gerechnet werden. Die erste
  /// Fassung gab jedem Segment einzeln `clamp(2, balkenHoehe)` — bei drei
  /// Reihen summierten sich die Mindesthöhen dann über die zugeteilte Höhe
  /// hinaus, und die Säule lief unten heraus. Ein Wert von 3 neben einem von
  /// 1005 ist genau der Fall: rechnerisch 0,13 Pixel, gezeichnet 2.
  ///
  /// Die Mindesthöhe bleibt trotzdem: eine Reihe mit einem einzigen Zugriff
  /// darf nicht unsichtbar sein, sonst liest man „gar keine Angriffe", wo
  /// einer war.
  static List<double> _segmentHoehen(
      List<int> werte, int hoechst, double platz) {
    final hoehen = [
      for (final w in werte)
        w <= 0 ? 0.0 : math.max(2.0, w / hoechst * platz),
    ];
    final summe = hoehen.fold<double>(0, (a, b) => a + b);
    if (summe <= platz) return hoehen;
    // Zu hoch geworden — alles gleichmäßig stauchen statt abzuschneiden.
    return [for (final h in hoehen) h * platz / summe];
  }

  @override
  Widget build(BuildContext context) {
    if (punkte.isEmpty) return const SizedBox.shrink();
    final hoechst = punkte.map((p) => p.summe).fold<int>(1, math.max);

    // Der Platz für die Säulen ist das, was nach den Beschriftungen übrig
    // bleibt — gerechnet, nicht geschätzt. Ohne zweite Zeile bleibt mehr.
    final hatUnterzeile = punkte.any((p) => p.unterBeschriftung != null);
    final reserve = _zahlGroesse * _zeile +
        _abstaende +
        _labelGroesse * _zeile +
        (hatUnterzeile ? _unterGroesse * _zeile : 0);
    final balkenHoehe = math.max(10.0, hoehe - reserve);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WebLegende(farben: farben, namen: reihenNamen),
        const SizedBox(height: 8),
        SizedBox(
          height: hoehe,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            // ⚠️ `reverse` verschiebt nur die ANFANGSPOSITION der Rolle, nicht
            // die Reihenfolge der Kinder. Passt alles in die Breite, hat es
            // gar keine Wirkung. Die erste Fassung drehte deshalb zusätzlich
            // die Liste — und beim Rendern stand die Zeitachse verkehrt herum
            // da: 15., 14., 13. von links nach rechts. Die Reihenfolge bleibt
            // jetzt chronologisch; `reverse` sorgt nur dafür, dass bei einem
            // langen Zeitraum der jüngste Tag gleich sichtbar ist.
            reverse: neuesteRechts,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: punkte.map((p) {
                final hoehen = _segmentHoehen(p.werte, hoechst, balkenHoehe);
                return Tooltip(
                  message: [
                    p.beschluessel,
                    for (var i = 0; i < p.werte.length; i++)
                      '${reihenNamen[i]}: ${p.werte[i]}',
                  ].join('\n'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text('${p.summe}',
                            style: const TextStyle(
                                fontSize: _zahlGroesse, height: _zeile)),
                        const SizedBox(height: 2),
                        // Von unten nach oben stapeln: die wichtigste Reihe
                        // (Menschen) steht als erste und damit unten, wo sie
                        // eine gemeinsame Grundlinie hat und vergleichbar ist.
                        for (var i = p.werte.length - 1; i >= 0; i--)
                          Container(
                            width: 18,
                            height: hoehen[i],
                            color: farben[i],
                          ),
                        const SizedBox(height: 3),
                        SizedBox(
                          width: 30,
                          child: Text(p.beschriftung,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: _labelGroesse, height: _zeile)),
                        ),
                        if (p.unterBeschriftung != null)
                          SizedBox(
                            width: 30,
                            child: Text(p.unterBeschriftung!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: _unterGroesse,
                                    height: _zeile,
                                    color: Colors.grey.shade600)),
                          ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

extension on WebPunkt {
  String get beschluessel =>
      unterBeschriftung == null ? beschriftung : '$beschriftung $unterBeschriftung';
}

/// Ein einziger waagerechter Balken, der eine Zusammensetzung zeigt.
/// Für „wie viel davon waren echte Menschen" die klarste Form: die Anteile
/// liegen nebeneinander und ergeben sichtbar ein Ganzes.
class WebAnteilsBalken extends StatelessWidget {
  final List<({String name, int wert, Color farbe})> teile;
  final double hoehe;

  const WebAnteilsBalken({super.key, required this.teile, this.hoehe = 26});

  @override
  Widget build(BuildContext context) {
    final gesamt = teile.fold<int>(0, (a, t) => a + t.wert);
    if (gesamt <= 0) {
      return Text('Keine Zugriffe im Zeitraum.',
          style: TextStyle(color: Colors.grey.shade600, fontStyle: FontStyle.italic));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: hoehe,
            child: Row(
              children: [
                for (final t in teile)
                  if (t.wert > 0)
                    Expanded(
                      flex: t.wert,
                      child: Tooltip(
                        message: '${t.name}: ${t.wert} '
                            '(${webProzent(t.wert, gesamt)})',
                        child: Container(color: t.farbe),
                      ),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            for (final t in teile)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 10, height: 10,
                      decoration: BoxDecoration(
                          color: t.farbe, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 5),
                  Text('${t.name} ${webProzent(t.wert, gesamt)}',
                      style: const TextStyle(fontSize: 11)),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// Ring — zeigt dieselbe Zusammensetzung, wenn ein Balken zu flach wirkt.
class WebRing extends StatelessWidget {
  final List<({String name, int wert, Color farbe})> teile;
  final String? mitte;
  final String? mitteUnten;
  final double groesse;

  const WebRing({super.key, required this.teile, this.mitte, this.mitteUnten,
      this.groesse = 132});

  @override
  Widget build(BuildContext context) {
    final gesamt = teile.fold<int>(0, (a, t) => a + t.wert);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: groesse,
          height: groesse,
          child: CustomPaint(
            painter: _RingMaler(teile: teile,
                leerFarbe: Theme.of(context).dividerColor),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (mitte != null)
                    Text(mitte!,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                  if (mitteUnten != null)
                    Text(mitteUnten!,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final t in teile)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Container(width: 10, height: 10,
                          decoration: BoxDecoration(
                              color: t.farbe, borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(t.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12))),
                      Text(webProzent(t.wert, gesamt),
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RingMaler extends CustomPainter {
  final List<({String name, int wert, Color farbe})> teile;
  final Color leerFarbe;
  _RingMaler({required this.teile, required this.leerFarbe});

  @override
  void paint(Canvas canvas, Size size) {
    final gesamt = teile.fold<int>(0, (a, t) => a + t.wert);
    final mitte = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;
    final stift = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15;

    if (gesamt <= 0) {
      stift.color = leerFarbe;
      canvas.drawCircle(mitte, radius, stift);
      return;
    }

    // Bei zwölf Uhr anfangen: sonst liest man den größten Anteil nicht sofort.
    var winkel = -math.pi / 2;
    for (final t in teile) {
      if (t.wert <= 0) continue;
      final bogen = t.wert / gesamt * 2 * math.pi;
      stift.color = t.farbe;
      canvas.drawArc(Rect.fromCircle(center: mitte, radius: radius),
          winkel, bogen, false, stift);
      winkel += bogen;
    }
  }

  @override
  bool shouldRepaint(_RingMaler alt) => alt.teile != teile;
}

/// Mehrere Linien in einem Bild — für den Verlauf der Spitzenseiten.
class WebLinien extends StatelessWidget {
  final List<String> namen;
  final List<List<int>> reihen;
  final List<String> xBeschriftung;
  final double hoehe;

  const WebLinien({super.key, required this.namen, required this.reihen,
      required this.xBeschriftung, this.hoehe = 150});

  static const _palette = [
    Color(0xFF1565C0), Color(0xFF2E7D32), Color(0xFFEF6C00),
    Color(0xFF6A1B9A), Color(0xFF00838F),
  ];

  @override
  Widget build(BuildContext context) {
    if (reihen.isEmpty || reihen.every((r) => r.isEmpty)) {
      return Text('Zu wenige Tage für einen Verlauf.',
          style: TextStyle(color: Colors.grey.shade600, fontStyle: FontStyle.italic));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WebLegende(
            farben: [for (var i = 0; i < namen.length; i++) _palette[i % _palette.length]],
            namen: namen),
        const SizedBox(height: 10),
        SizedBox(
          height: hoehe,
          width: double.infinity,
          child: CustomPaint(
            painter: _LinienMaler(
              reihen: reihen,
              farben: [
                for (var i = 0; i < reihen.length; i++) _palette[i % _palette.length]
              ],
              gitterFarbe: Theme.of(context).dividerColor,
            ),
          ),
        ),
        if (xBeschriftung.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(xBeschriftung.first,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                Text(xBeschriftung.last,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
              ],
            ),
          ),
      ],
    );
  }
}

class _LinienMaler extends CustomPainter {
  final List<List<int>> reihen;
  final List<Color> farben;
  final Color gitterFarbe;
  _LinienMaler({required this.reihen, required this.farben, required this.gitterFarbe});

  @override
  void paint(Canvas canvas, Size size) {
    final hoechst = reihen
        .expand((r) => r)
        .fold<int>(1, math.max)
        .toDouble();

    final gitter = Paint()
      ..color = gitterFarbe
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gitter);
    }

    for (var r = 0; r < reihen.length; r++) {
      final werte = reihen[r];
      if (werte.length < 2) {
        // Ein einzelner Punkt ergibt keine Linie — dann wenigstens ein Punkt,
        // statt gar nichts zu zeichnen und „keine Daten" vorzutäuschen.
        if (werte.length == 1) {
          canvas.drawCircle(Offset(size.width / 2,
              size.height - werte[0] / hoechst * size.height), 3,
              Paint()..color = farben[r]);
        }
        continue;
      }
      final pfad = Path();
      for (var i = 0; i < werte.length; i++) {
        final x = werte.length == 1 ? 0.0 : size.width * i / (werte.length - 1);
        final y = size.height - werte[i] / hoechst * size.height;
        if (i == 0) {
          pfad.moveTo(x, y);
        } else {
          pfad.lineTo(x, y);
        }
      }
      canvas.drawPath(
          pfad,
          Paint()
            ..color = farben[r]
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(_LinienMaler alt) => alt.reihen != reihen;
}

/// Tagesrhythmus über 24 Stunden.
///
/// ⚠️ Der Server liefert NUR Stunden, in denen etwas passiert ist. Die Lücken
/// müssen hier gefüllt werden — sonst rutschen die Säulen zusammen und ein
/// stiller Vormittag sähe aus wie ein voller.
class WebStunden extends StatelessWidget {
  final List<int> proStunde;
  final Color farbe;
  final String einheit;

  const WebStunden({super.key, required this.proStunde,
      this.farbe = kWebMensch, this.einheit = 'Aufrufe'});

  @override
  Widget build(BuildContext context) {
    final hoechst = proStunde.fold<int>(1, math.max);
    return Column(
      children: [
        SizedBox(
          height: 78,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(24, (h) {
              return Expanded(
                child: Tooltip(
                  message: '${h.toString().padLeft(2, '0')}:00 — '
                      '${proStunde[h]} $einheit',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Container(
                      height: (proStunde[h] / hoechst * 70).clamp(2.0, 70.0),
                      decoration: BoxDecoration(
                        color: farbe.withValues(
                            alpha: proStunde[h] == 0 ? 0.15 : 0.85),
                        borderRadius:
                            const BorderRadius.vertical(top: Radius.circular(2)),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final h in ['00', '06', '12', '18', '23'])
              Text(h, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          ],
        ),
      ],
    );
  }
}

/// Wochentage. Index 0 = Montag.
class WebWochentage extends StatelessWidget {
  final List<int> proTag;
  final Color farbe;
  const WebWochentage({super.key, required this.proTag, this.farbe = kWebMensch});

  static const _namen = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

  @override
  Widget build(BuildContext context) {
    final hoechst = proTag.fold<int>(1, math.max);
    return SizedBox(
      height: 96,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(7, (t) {
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('${proTag[t]}', style: const TextStyle(fontSize: 10)),
                  const SizedBox(height: 2),
                  Container(
                    height: (proTag[t] / hoechst * 58).clamp(2.0, 58.0),
                    decoration: BoxDecoration(
                      color: farbe.withValues(alpha: proTag[t] == 0 ? 0.15 : 0.85),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(3)),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(_namen[t], style: const TextStyle(fontSize: 10)),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class WebLegende extends StatelessWidget {
  final List<Color> farben;
  final List<String> namen;
  const WebLegende({super.key, required this.farben, required this.namen});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        for (var i = 0; i < namen.length && i < farben.length; i++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 10, height: 10,
                  decoration: BoxDecoration(
                      color: farben[i], borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 5),
              Text(namen[i], style: const TextStyle(fontSize: 11)),
            ],
          ),
      ],
    );
  }
}
