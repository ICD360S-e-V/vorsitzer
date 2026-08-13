/// Ein A4-Bogen Visitenkarten zum Selberdrucken — Vorder- und Rückseite,
/// mit Schnittmarken.
///
/// ## Die Geometrie, und warum genau diese
///
/// Eine Visitenkarte misst in Deutschland 85 × 55 mm. Auf A4 (210 × 297 mm)
/// gehen davon **2 × 5 = 10** Stück auf: 2 × 85 = 170 mm breit, 5 × 55 = 275 mm
/// hoch. Es bleiben 20 mm Rand links und rechts, 11 mm oben und unten. Mehr
/// passen nicht, ohne die Karte zu verkleinern — und eine verkleinerte
/// Visitenkarte ist keine mehr.
///
/// Die Karten stoßen **ohne Steg** aneinander. Das ist Absicht: ein Schnitt
/// zwischen zwei Karten trennt beide zugleich, und weil beide dieselbe Fläche
/// tragen, fällt ein um einen Millimeter verrutschter Schnitt nicht als weiße
/// Blitzer auf. Mit Steg wäre jeder Schnitt zweimal zu führen und jeder Fehler
/// sichtbar.
///
/// ## ⚠️ Der Bogen ist für HANDWENDEN gemacht, nicht für einen Duplexdrucker
///
/// Der Verein hat keinen Duplexdrucker. Der Ablauf ist: Seite 1 drucken, das
/// bedruckte Blatt entnehmen, **um die lange (senkrechte) Kante wenden** —
/// also wie eine Buchseite —, wieder einlegen, Seite 2 drucken.
///
/// Geometrisch ist das dasselbe wie „Duplex über die lange Kante": das Blatt
/// klappt um die senkrechte Achse, ein Punkt bei x liegt danach bei
/// (Blattbreite − x). Die Spalten tauschen also die Plätze, [spalteGespiegelt]
/// bildet das ab.
///
/// ⚠️ **Wendet jemand um die kurze Kante** (oben nach unten), landen die
/// Rückseiten zwar wieder auf Kartenkanten — das Raster ist auch senkrecht
/// symmetrisch —, aber **um 180° verdreht**. Die Karte wäre benutzbar und
/// trotzdem falsch. Dagegen steht die Wendemarke: „▲ OBEN" mittig im oberen
/// Rand BEIDER Seiten. Beim richtigen Wenden decken sich die beiden Marken,
/// wenn man das Blatt gegen das Licht hält; beim falschen steht die eine oben
/// und die andere unten. Das ist eine Probe, die man in zwei Sekunden macht,
/// bevor man zehn Karten verschneidet.
///
/// ⚠️ Solange **alle zehn Karten gleich sind**, ändert die Spiegelung nichts —
/// das Raster ist symmetrisch. Sie steht trotzdem hier, und der Test hält sie
/// fest: in der Sekunde, in der jemand einen Bogen mit zwei verschiedenen
/// Personen druckt, hätte ohne sie jede Karte die Rückseite der falschen.
///
/// ## ⚠️ Was der Drucker kaputt machen kann
///
/// „An Seite anpassen" skaliert den Bogen um ein paar Prozent — die Karten sind
/// dann nicht mehr 85 × 55, und die Schnittmarken zeigen ins Leere. Deshalb
/// steht der Hinweis „100 % / Tatsächliche Größe" auf dem Bogen selbst und
/// nicht bloß in einem Dialog, den man wegklickt.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/painting.dart' show Color;
import 'package:printing/printing.dart';

import 'visitenkarte_daten.dart';
import 'visitenkarte_farben.dart';

const double _mm = PdfPageFormat.mm;

/// 85 × 55 mm — das übliche Format in Deutschland.
const double kKarteBreiteMm = 85;
const double kKarteHoeheMm = 55;

const int kSpalten = 2;
const int kZeilen = 5;

/// Zehn Karten je Bogen. Mehr gehen auf A4 nicht in Originalgröße.
const int kKartenProBogen = kSpalten * kZeilen;

const double kBogenBreiteMm = 210;
const double kBogenHoeheMm = 297;

/// Ränder ergeben sich aus dem Raster, sie sind nicht gewählt.
const double kRandXMm = (kBogenBreiteMm - kSpalten * kKarteBreiteMm) / 2;   // 20
const double kRandYMm = (kBogenHoeheMm - kZeilen * kKarteHoeheMm) / 2;      // 11

/// Länge der Schnittmarken, gemessen vom Kartenrand nach außen.
const double kMarkeLaengeMm = 4;

// ── Farben ────────────────────────────────────────────────────────────────
//
// Abgeleitet aus lib/utils/visitenkarte_farben.dart, damit die Zahl nur an
// EINER Stelle steht. Die Begründung der Werte (gemessene Kontraste, Herkunft
// aus dem Webauftritt) steht dort.
PdfColor _pdf(Color c) => PdfColor.fromInt(c.toARGB32());

final PdfColor kTonHell = _pdf(kVkTonHell);
final PdfColor kTonDunkel = _pdf(kVkTonDunkel);
final PdfColor kTonFlaeche = _pdf(kVkTonFlaeche);
final PdfColor kTextDunkel = _pdf(kVkTextDunkel);
final PdfColor kTextLeise = _pdf(kVkTextLeise);

/// Welche Spalte eine Karte auf der Rückseite belegt.
///
/// Siehe die Erklärung zum Duplexdruck im Kopf dieser Datei.
int spalteGespiegelt(int spalte) => kSpalten - 1 - spalte;

/// Die Position einer Karte auf dem Bogen, in Millimetern von links oben.
///
/// [rueckseite] spiegelt die Spalten für den beidseitigen Druck.
({double x, double y}) kartenPosition(int index, {bool rueckseite = false}) {
  if (index < 0 || index >= kKartenProBogen) {
    throw RangeError.range(index, 0, kKartenProBogen - 1, 'index');
  }
  final zeile = index ~/ kSpalten;
  var spalte = index % kSpalten;
  if (rueckseite) spalte = spalteGespiegelt(spalte);
  return (
    x: kRandXMm + spalte * kKarteBreiteMm,
    y: kRandYMm + zeile * kKarteHoeheMm,
  );
}

/// Die Linien, an denen geschnitten wird — in Millimetern.
///
/// Senkrecht drei (linker Rand, Mitte, rechter Rand), waagerecht sechs.
({List<double> senkrecht, List<double> waagerecht}) schnittlinien() => (
      senkrecht: [
        for (var s = 0; s <= kSpalten; s++) kRandXMm + s * kKarteBreiteMm,
      ],
      waagerecht: [
        for (var z = 0; z <= kZeilen; z++) kRandYMm + z * kKarteHoeheMm,
      ],
    );

/// Baut den Bogen und gibt ihn als PDF-Bytes zurück.
///
/// Zwei Seiten: erst zehnmal die Vorderseite, dann zehnmal die Rückseite.
Future<Uint8List> visitenkartenBogen(VisitenkarteDaten daten) async {
  // DejaVu liegt bereits im Bundle (assets/fonts) und deckt alles ab, was die
  // Karte braucht — ♿ U+267F, ° U+00B0, · U+00B7, § U+00A7. Die eingebauten
  // PDF-Schriften können davon nur den Grad; das Rollstuhlzeichen käme als
  // leeres Kästchen heraus.
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
  final fett = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'));

  final doc = pw.Document(
    title: 'Visitenkarten ${daten.vorname} ${daten.nachname}',
    author: daten.vereinsname,
  );

  for (final rueckseite in [false, true]) {
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (context) => pw.Stack(
          children: [
            _schnittmarken(),
            for (var i = 0; i < kKartenProBogen; i++)
              _platziert(
                i,
                rueckseite: rueckseite,
                kind: rueckseite
                    ? _karteHinten(daten, regular, fett)
                    : _karteVorne(daten, regular, fett),
              ),
            _bogenHinweis(rueckseite: rueckseite, schrift: regular),
            _wendemarke(schrift: regular),
          ],
        ),
      ),
    );
  }

  return doc.save();
}

/// Baut den Bogen und öffnet den Teilen-/Drucken-Dialog des Systems.
///
/// ⚠️ Über `Printing`, nicht über eine Datei im App-Verzeichnis. Ein Export,
/// der stumm in den privaten Speicher fällt und sich nirgends öffnen lässt,
/// ist schon einmal genau so passiert (Speedtest-Export).
Future<void> visitenkartenBogenTeilen(VisitenkarteDaten daten) async {
  await Printing.sharePdf(
    bytes: await visitenkartenBogen(daten),
    filename: 'visitenkarten_${daten.mitgliedernummer.toLowerCase()}.pdf',
  );
}

pw.Widget _platziert(int index,
    {required bool rueckseite, required pw.Widget kind}) {
  final p = kartenPosition(index, rueckseite: rueckseite);
  return pw.Positioned(
    left: p.x * _mm,
    top: p.y * _mm,
    child: pw.SizedBox(
      width: kKarteBreiteMm * _mm,
      height: kKarteHoeheMm * _mm,
      child: kind,
    ),
  );
}

/// Schnittmarken in den Rändern, nie über die Karten hinweg.
///
/// ⚠️ Im PDF-Koordinatensystem liegt der Nullpunkt **unten links**, in der
/// Widget-Welt oben links. Die waagerechten Marken müssen deshalb gespiegelt
/// gerechnet werden — ohne das säßen sie an der falschen Kante, und zwar
/// plausibel genug, dass es erst nach dem Schneiden auffiele.
pw.Widget _schnittmarken() {
  final linien = schnittlinien();
  return pw.Positioned(
    left: 0,
    top: 0,
    child: pw.CustomPaint(
      size: PdfPoint(kBogenBreiteMm * _mm, kBogenHoeheMm * _mm),
      painter: (canvas, size) {
        canvas
          ..setStrokeColor(PdfColors.grey600)
          ..setLineWidth(0.25);

        final marke = kMarkeLaengeMm * _mm;
        final obenY = (kBogenHoeheMm - kRandYMm) * _mm;
        final untenY = (kBogenHoeheMm - (kRandYMm + kZeilen * kKarteHoeheMm)) * _mm;

        // Senkrechte Schnitte: Marken oben und unten, außerhalb des Rasters.
        for (final x in linien.senkrecht) {
          final px = x * _mm;
          canvas
            ..moveTo(px, obenY)
            ..lineTo(px, obenY + marke)
            ..moveTo(px, untenY)
            ..lineTo(px, untenY - marke);
        }

        // Waagerechte Schnitte: Marken links und rechts.
        final linksX = kRandXMm * _mm;
        final rechtsX = (kRandXMm + kSpalten * kKarteBreiteMm) * _mm;
        for (final y in linien.waagerecht) {
          final py = (kBogenHoeheMm - y) * _mm;
          canvas
            ..moveTo(linksX, py)
            ..lineTo(linksX - marke, py)
            ..moveTo(rechtsX, py)
            ..lineTo(rechtsX + marke, py);
        }

        canvas.strokePath();
      },
    ),
  );
}

/// Der Druckhinweis im unteren Rand — auf dem Bogen, nicht in einem Dialog.
///
/// Er steht auf dem Papier, das ohnehin weggeschnitten wird. Wer den Bogen
/// weiterreicht oder ihn morgen noch einmal druckt, hat die beiden Angaben
/// dabei, auf die alles ankommt: keine Skalierung, lange Kante.
pw.Widget _bogenHinweis({required bool rueckseite, required pw.Font schrift}) {
  final oben = (kRandYMm + kZeilen * kKarteHoeheMm + 2.5) * _mm;
  return pw.Positioned(
    left: 0,
    top: oben,
    child: pw.SizedBox(
      width: kBogenBreiteMm * _mm,
      child: pw.Center(
        child: pw.Text(
          rueckseite
              ? 'Seite 2 — RÜCKSEITE · Bedrucktes Blatt entnehmen, um die LANGE '
                  '(senkrechte) Kante wenden wie eine Buchseite, wieder einlegen · '
                  'in 100 % drucken · danach an den Marken schneiden'
              : 'Seite 1 — VORDERSEITE · 10 Karten à 85 × 55 mm · in 100 % drucken, '
                  'nicht „an Seite anpassen" · danach Blatt wenden und Seite 2 drucken',
          style: pw.TextStyle(font: schrift, fontSize: 6, color: PdfColors.grey600),
        ),
      ),
    ),
  );
}

/// „▲ OBEN" mittig im oberen Rand — die Wendeprobe.
///
/// ⚠️ Sie steht auf BEIDEN Seiten an derselben Stelle, und genau darin liegt
/// ihr Nutzen. Wendet man das Blatt richtig (um die senkrechte Kante), decken
/// sich die zwei Marken, wenn man gegen das Licht schaut. Wendet man falsch
/// (oben nach unten), steht die zweite Marke am unteren Rand — sofort sichtbar,
/// und zwar BEVOR geschnitten wird.
///
/// Ohne sie wäre der Fehler erst an der fertigen Karte zu bemerken: die
/// Rückseiten lägen richtig auf den Kartenflächen, nur eben auf dem Kopf.
pw.Widget _wendemarke({required pw.Font schrift}) {
  return pw.Positioned(
    left: 0,
    top: 3 * _mm,
    child: pw.SizedBox(
      width: kBogenBreiteMm * _mm,
      child: pw.Center(
        child: pw.Text('▲ OBEN',
            style: pw.TextStyle(
                font: schrift, fontSize: 6, color: PdfColors.grey600, letterSpacing: 1)),
      ),
    ),
  );
}

// ══ Die Karte ═══════════════════════════════════════════════════════════════

pw.Widget _karteVorne(VisitenkarteDaten d, pw.Font regular, pw.Font fett) {
  return pw.Container(
    decoration: pw.BoxDecoration(
      gradient: pw.LinearGradient(
        begin: pw.Alignment.topLeft,
        end: pw.Alignment.bottomRight,
        colors: [kTonHell, kTonDunkel],
      ),
    ),
    padding: const pw.EdgeInsets.all(6 * _mm),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(d.vereinsname,
            style: pw.TextStyle(
                font: fett, fontSize: 13, color: PdfColors.white, letterSpacing: 0.6)),
        pw.SizedBox(height: 2),
        pw.Container(width: 26, height: 1.6, color: PdfColors.white),
        pw.SizedBox(height: 3.5),
        pw.Text(d.slogan,
            style: pw.TextStyle(font: regular, fontSize: 6, color: PdfColors.white)),
        pw.SizedBox(height: 7),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.RichText(
                    text: pw.TextSpan(children: [
                      if (d.vorname.isNotEmpty)
                        pw.TextSpan(
                            text: d.nachname.isEmpty ? d.vorname : '${d.vorname} ',
                            style: pw.TextStyle(font: regular, fontSize: 10.5)),
                      if (d.nachname.isNotEmpty)
                        pw.TextSpan(
                            text: d.nachname,
                            style: pw.TextStyle(font: fett, fontSize: 10.5)),
                    ], style: const pw.TextStyle(color: PdfColors.white)),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Row(children: [
                    if (d.funktion.isNotEmpty) _pille(d.funktion, regular),
                    if (d.istGruender) ...[
                      pw.SizedBox(width: 3),
                      _pille('Gründer', regular),
                    ],
                  ]),
                ],
              ),
            ),
            pw.SizedBox(width: 5),
            _sprachBlock(d, regular, fett),
          ],
        ),
        pw.SizedBox(height: 5),
        if (d.email.isNotEmpty) _zeile('E-Mail', d.email, regular),
        if (d.festnetz.isNotEmpty) _zeile('Tel.', d.festnetz, regular),
        if (d.mobil.isNotEmpty) _zeile('Mobil', d.mobil, regular),
        pw.Spacer(),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(d.mitgliedernummer,
                style: pw.TextStyle(
                    font: regular, fontSize: 6, color: PdfColor.fromInt(0xCCFFFFFF))),
            pw.Text(d.web,
                style: pw.TextStyle(font: fett, fontSize: 6.5, color: PdfColors.white)),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _pille(String text, pw.Font schrift) => pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(7),
        border: pw.Border.all(color: PdfColor.fromInt(0x99FFFFFF), width: 0.4),
      ),
      child: pw.Text(text,
          style: pw.TextStyle(font: schrift, fontSize: 6.5, color: PdfColors.white)),
    );

/// ♿ über den Sprachkürzeln — wie auf dem Bildschirm, nur ohne Flaggen.
pw.Widget _sprachBlock(VisitenkarteDaten d, pw.Font regular, pw.Font fett) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
    decoration: pw.BoxDecoration(
      borderRadius: pw.BorderRadius.circular(5),
      border: pw.Border.all(color: PdfColor.fromInt(0x66FFFFFF), width: 0.4),
    ),
    child: pw.Column(children: [
      pw.Text('♿',
          style: pw.TextStyle(font: regular, fontSize: 11, color: PdfColors.white)),
      if (d.sprachen.isNotEmpty) ...[
        pw.SizedBox(height: 2),
        pw.Text(d.sprachZeile,
            style: pw.TextStyle(
                font: fett, fontSize: 5.5, color: PdfColors.white, letterSpacing: 0.3)),
      ],
    ]),
  );
}

pw.Widget _zeile(String etikett, String wert, pw.Font schrift) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 1.6),
      child: pw.Row(children: [
        pw.SizedBox(
          width: 24,
          child: pw.Text(etikett,
              style: pw.TextStyle(
                  font: schrift, fontSize: 6.5, color: PdfColor.fromInt(0xBBFFFFFF))),
        ),
        pw.Text(wert,
            style: pw.TextStyle(font: schrift, fontSize: 7, color: PdfColors.white)),
      ]),
    );

pw.Widget _karteHinten(VisitenkarteDaten d, pw.Font regular, pw.Font fett) {
  // Die Texte kommen aus derselben Quelle wie der Bildschirm — sonst stünde auf
  // dem Papier eine zweite, irgendwann abweichende Selbstbeschreibung.
  return pw.Container(
    color: PdfColors.white,
    padding: const pw.EdgeInsets.all(5 * _mm),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Text('Was wir tun',
                  style: pw.TextStyle(font: fett, fontSize: 9, color: kTonHell)),
            ),
            pw.Text(d.vereinsname,
                style: pw.TextStyle(font: fett, fontSize: 6, color: kTextLeise)),
          ],
        ),
        pw.SizedBox(height: 1.5),
        pw.Container(width: 20, height: 1.2, color: kTonHell),
        pw.SizedBox(height: 4),
        for (final (titel, was) in kVisitenkarteLeistungenPdf)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 1.4),
            child: pw.RichText(
              text: pw.TextSpan(children: [
                pw.TextSpan(
                    text: '• $titel  ',
                    style: pw.TextStyle(font: fett, fontSize: 6, color: kTextDunkel)),
                pw.TextSpan(
                    text: was,
                    style: pw.TextStyle(font: regular, fontSize: 6, color: kTextLeise)),
              ]),
            ),
          ),
        pw.SizedBox(height: 3),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: pw.BoxDecoration(color: kTonFlaeche),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('♿',
                style: pw.TextStyle(font: regular, fontSize: 8, color: kTonHell)),
            pw.SizedBox(width: 3),
            pw.Expanded(
              child: pw.Text(kVisitenkarteLeitsatzPdf,
                  style: pw.TextStyle(font: regular, fontSize: 5.7, color: kTextDunkel)),
            ),
          ]),
        ),
        pw.SizedBox(height: 2.5),
        pw.Text(kVisitenkarteAbgrenzungPdf,
            style: pw.TextStyle(
                font: regular,
                fontSize: 5.2,
                color: kTextLeise,
                fontStyle: pw.FontStyle.italic)),
        pw.Spacer(),
        pw.Divider(height: 2, thickness: 0.3, color: PdfColors.grey400),
        if (d.anschrift.isNotEmpty)
          pw.Text(d.anschrift,
              style: pw.TextStyle(font: regular, fontSize: 5.5, color: kTextLeise)),
        pw.Text(
          [d.web, if (d.register.isNotEmpty) d.register, 'gemeinnützig'].join(' · '),
          style: pw.TextStyle(font: regular, fontSize: 5.5, color: kTextLeise),
        ),
      ],
    ),
  );
}

/// ⚠️ Bewusst eigene Konstanten statt eines Imports aus `widgets/visitenkarte.dart`:
/// diese Datei darf nichts aus dem Widget-Baum ziehen, sonst wäre der Bogen nur
/// mit laufender Oberfläche zu bauen. Der Wortlaut MUSS identisch bleiben — ein
/// Test vergleicht beide Listen Zeichen für Zeichen.
const List<(String, String)> kVisitenkarteLeistungenPdf = [
  ('Behörden & Anträge', 'Begleitung, Formulare, Bescheide, Fristen'),
  ('Sprache', 'Dolmetschen, Übersetzen, Telefonate mit Ämtern'),
  ('Alltag', 'Einkauf, Arzt- und Therapietermine, Nahverkehr'),
  ('Bildung & Arbeit', 'Anerkennung, Bewerbung, digitale Grundbildung'),
  ('Geld & Existenz', 'Haushaltsplanung, Ansprüche, Nothilfe'),
  ('Zusammen leben', 'Begegnung, Sport, Freizeit, Nachbarschaft'),
];

const String kVisitenkarteLeitsatzPdf =
    'Der Vorstand besteht mehrheitlich aus Menschen mit Behinderung. '
    'Selbstvertretung statt Fürsorge.';

const String kVisitenkarteAbgrenzungPdf =
    'Keine Rechts-, Steuer- oder medizinische Beratung (§ 3 Abs. 4 der Satzung) '
    '— wir vermitteln an zugelassene Fachleute weiter.';
