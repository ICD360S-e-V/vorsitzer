import 'package:flutter/material.dart';

/// Eine Kopfleiste, die umbricht statt überzulaufen.
///
/// Fast jeder Bildschirm beginnt mit derselben Zeile: Zurück-Pfeil, Symbol,
/// Überschrift, `Spacer`, dann zwei bis fünf Bedienelemente. Solange die
/// Fläche breit genug ist, sieht das gut aus. Wird sie schmaler, läuft die
/// Reihe über — gemessen am 08.08.2026 bei
/// `jpg2pdf_screen.dart` um **1154 dp** und bei `vereinsinventar_screen.dart`
/// um **499 dp**, und zwar nicht nur auf dem Telefon, sondern auch auf dem
/// Tablet mit 800 dp.
///
/// ⚠️ Ein `Row` mit `Spacer` verdeckt genau das: der `Spacer` schluckt den
/// Rest, solange es einen gibt, und sobald es keinen mehr gibt, gibt es
/// keine Warnung, sondern schwarz-gelbe Streifen. Deshalb hier ein `Wrap`:
/// passt beides nebeneinander, sieht es aus wie vorher; passt es nicht,
/// rutschen die Bedienelemente unter die Überschrift.
///
/// Absichtlich **ohne** Breiten-Schwellwert. Ein Schwellwert müsste raten,
/// wie breit die Bedienelemente sind — und läge bei jedem Bildschirm anders
/// falsch. `Wrap` misst.
class FaltbareKopfleiste extends StatelessWidget {
  /// Zurück-Pfeil, Symbol, Überschrift — alles, was links steht.
  final List<Widget> links;

  /// Was rechts steht. Bricht bei Bedarf in mehrere Zeilen um.
  final List<Widget> aktionen;

  /// Abstand zwischen den Bedienelementen.
  final double abstand;

  /// Abstand zwischen den Zeilen, wenn umgebrochen wird.
  final double zeilenAbstand;

  const FaltbareKopfleiste({
    super.key,
    required this.links,
    required this.aktionen,
    this.abstand = 8,
    this.zeilenAbstand = 8,
  });

  @override
  Widget build(BuildContext context) {
    // ⚠️ `LayoutBuilder` ist hier nicht Zierde: **ein `Wrap` gibt seinen
    // Kindern auf der Hauptachse unbegrenzte Breite.** Ein `Wrap` im `Wrap`
    // erfährt also nie, wie viel Platz da ist, und bricht nie um — die erste
    // Fassung dieser Datei lief deshalb selbst um 100 dp über, obwohl sie
    // genau dagegen gebaut war. Gefunden hat das der Aufbau-Test, nicht das
    // Nachdenken. Die gemessene Breite wird darum ausdrücklich
    // weitergereicht.
    return LayoutBuilder(
      builder: (context, zwang) {
        final breite = zwang.maxWidth;
        return Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: abstand,
          runSpacing: zeilenAbstand,
          children: [
            // `mainAxisSize.min`, damit die Überschrift nur so breit wird,
            // wie sie ist — sonst nähme sie die ganze Zeile und erzwänge den
            // Umbruch auch dort, wo alles nebeneinander gepasst hätte.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: breite),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                // ⚠️ Die Begrenzung allein reicht nicht: ein `Text` in einem
                // `Row` nimmt sich seine Wunschbreite, auch wenn der Kasten
                // enger ist — `VereinsinventarScreen` lief so noch um 100 dp
                // über, obwohl die ConstrainedBox schon da war. Erst
                // `Flexible` erlaubt dem Titel, umzubrechen. Andere Kinder
                // (Symbole, Zurück-Pfeil) bleiben unangetastet, die sollen
                // ihre Größe behalten.
                children: [
                  for (final w in links)
                    if (w is Text) Flexible(child: w) else w,
                ],
              ),
            ),
            if (aktionen.isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: breite),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: abstand,
                  runSpacing: zeilenAbstand,
                  children: aktionen,
                ),
              ),
          ],
        );
      },
    );
  }
}
