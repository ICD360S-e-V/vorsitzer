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

import 'flaggen.dart';
import 'sprach_flaggen.dart';
import 'visitenkarte_daten.dart';
import 'visitenkarte_farben.dart';
import 'visitenkarte_masse.dart';

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

/// Die vier Sinnbilder, die als Bilddatei mitgeliefert werden.
///
/// Bezogen von Google Fonts (Material Icons, **Apache-2.0**) in 48 px und
/// einmalig beim Bauen in den Vereinston eingefärbt. Es sind dieselben
/// Zeichen, die das Widget auf dem Bildschirm setzt — `Icons.email`,
/// `Icons.phone`, `Icons.smartphone`, `Icons.language`.
///
/// ⚠️ Eingefärbt beim Bauen und nicht beim Zeichnen: der PDF-Erzeuger kann ein
/// Bild nicht umfärben, und ein schwarzes Sinnbild neben tealfarbener Schrift
/// sähe aus wie versehentlich stehen geblieben.
const List<String> kIkonen = [
  'email',
  'phone',
  'smartphone',
  'language',
  // ⚠️ Auch das Rollstuhlzeichen als Bild, nicht als Schriftzeichen ♿ U+267F.
  // DejaVu zeichnet es als feine Strichfigur, die Emoji-Schrift des Bildschirms
  // als blaue Kachel — zwei sehr verschiedene Bilder für dasselbe Symbol.
  // Als Datei sehen Karte und Ausdruck dasselbe.
  'accessible',
];

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

  // ⚠️ Die Sinnbilder als Bilddateien, NICHT als Icon-Schrift.
  //
  // Der naheliegende Weg war, `fonts/MaterialIcons-Regular.otf` einzubetten —
  // dieselbe Schrift, die die App auf dem Bildschirm benutzt. Sie lässt sich
  // laden und `pw.Font.ttf` nimmt sie sogar an, aber beim Setzen bricht es ab:
  // die Datei trägt die Kennung `OTTO` und enthält eine `CFF `-Tabelle statt
  // `glyf`, also OpenType mit PostScript-Umrissen. Der PDF-Erzeuger kann nur
  // TrueType und fällt still auf eine Standardschrift zurück, die den
  // Codepunkt aus der Private Use Area nicht kennt — Ausgang ist eine
  // Latin-1-Ausnahme mitten im Seitenaufbau.
  final ikonen = <String, pw.ImageProvider>{};
  for (final name in kIkonen) {
    ikonen[name] = pw.MemoryImage(
        (await rootBundle.load('assets/ikonen/$name.png')).buffer.asUint8List());
  }

  // ⚠️ Einmal laden, nicht je Karte. Zehn Karten auf dem Bogen zeigen dieselben
  // Fahnen; würde je Karte ein eigenes `MemoryImage` gebaut, läge dasselbe Bild
  // zwanzigmal im PDF. So ist es ein Objekt und wird einmal eingebettet.
  final fahnen = <String, pw.ImageProvider>{};
  for (final sp in daten.sprachen) {
    final pfad = flaggenPfad(sp.code);
    if (pfad == null) continue;
    fahnen[sp.code] =
        pw.MemoryImage((await rootBundle.load(pfad)).buffer.asUint8List());
  }

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
            // ⚠️ Reihenfolge im Stack = Zeichenreihenfolge. Die Schnittlinien
            // standen zuerst und lagen damit UNTER den Karten — die weißen
            // Kartenflächen haben sie verdeckt, sichtbar blieben nur die
            // Stummel in den Rändern. Auf einem Bogen ohne Steg heißt das: in
            // der ganzen Blattmitte war nichts zu sehen, woran man schneiden
            // könnte. Sie stehen jetzt zuletzt und liegen oben auf.
            for (var i = 0; i < kKartenProBogen; i++)
              _platziert(
                i,
                rueckseite: rueckseite,
                kind: rueckseite
                    ? _karteHinten(daten, regular, fett, ikonen)
                    : _karteVorne(daten, regular, fett, ikonen, fahnen),
              ),
            _bogenHinweis(rueckseite: rueckseite, schrift: regular),
            _wendemarke(schrift: regular),
            _schnittmarken(),
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

/// Die Schnittlinien — **durchgehend über den ganzen Bogen**, plus kräftigere
/// Marken in den Rändern.
///
/// ## ⚠️ Warum die Linien jetzt durchs Blatt laufen
///
/// Die erste Fassung hatte nur kurze Marken in den Rändern. Das ist die
/// Konvention der Druckerei — dort schneidet eine Maschine, die zwei Marken zu
/// einer Geraden verlängert. Wer zu Hause mit Schere oder Lineal schneidet,
/// steht damit vor einem Blatt, auf dem in der Mitte **nichts** zu sehen ist:
/// zehn Karten stoßen ohne Steg aneinander, es gibt keine Fuge, an der man sich
/// entlanghangeln könnte. Man müsste ein Lineal zwischen zwei Marken am
/// Blattrand anlegen und hoffen.
///
/// Deshalb liegt jetzt auf jeder Schnittkante eine feine gestrichelte Linie
/// über die volle Breite bzw. Höhe. Man schneidet **auf** der Linie; ein
/// sauberer Schnitt nimmt sie mit.
///
/// ⚠️ Genau das geht nur, weil die Karte weiß ist. Auf der vollflächig
/// eingefärbten Fassung hätte eine graue Linie quer über zehn Karten gelegen
/// und jeder ungenaue Schnitt hätte einen Strich auf der fertigen Karte
/// stehen lassen. Die sparsame Farbfläche und die sichtbaren Schnittlinien
/// bedingen einander — wer die eine zurückdreht, muss die andere mitdenken.
///
/// ⚠️ Im PDF-Koordinatensystem liegt der Nullpunkt **unten links**, in der
/// Widget-Welt oben links. Die waagerechten Linien müssen deshalb gespiegelt
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
        final marke = kMarkeLaengeMm * _mm;
        final obenY = (kBogenHoeheMm - kRandYMm) * _mm;
        final untenY =
            (kBogenHoeheMm - (kRandYMm + kZeilen * kKarteHoeheMm)) * _mm;
        final linksX = kRandXMm * _mm;
        final rechtsX = (kRandXMm + kSpalten * kKarteBreiteMm) * _mm;

        // ── 1. Die gestrichelten Linien über die Karten ────────────────────
        // Fein und hellgrau: sie sollen führen, nicht auffallen. 1,5 pt Strich
        // auf 1,5 pt Lücke ist bei 600 dpi noch sauber gerastert und mit dem
        // Auge klar als Linie zu lesen.
        canvas
          ..saveContext()
          ..setStrokeColor(PdfColors.grey400)
          ..setLineWidth(0.3)
          ..setLineDashPattern(const [1.5, 1.5]);

        for (final x in linien.senkrecht) {
          final px = x * _mm;
          canvas
            ..moveTo(px, untenY)
            ..lineTo(px, obenY);
        }
        for (final y in linien.waagerecht) {
          final py = (kBogenHoeheMm - y) * _mm;
          canvas
            ..moveTo(linksX, py)
            ..lineTo(rechtsX, py);
        }
        canvas
          ..strokePath()
          ..restoreContext();

        // ── 2. Die kräftigen Marken in den Rändern ────────────────────────
        // Durchgezogen und dunkler als die Führungslinien: an ihnen legt man
        // ein Lineal an, wenn man lieber schneidet als der gestrichelten Linie
        // zu folgen. Sie liegen außerhalb der Karten und werden mit
        // weggeschnitten.
        canvas
          ..setStrokeColor(PdfColors.grey700)
          ..setLineWidth(0.4);

        for (final x in linien.senkrecht) {
          final px = x * _mm;
          canvas
            ..moveTo(px, obenY)
            ..lineTo(px, obenY + marke)
            ..moveTo(px, untenY)
            ..lineTo(px, untenY - marke);
        }
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

/// Die Vorderseite — weiß, mit einem schmalen Tealbalken an der Stange.
///
/// ## ⚠️ Warum nicht mehr vollflächig eingefärbt
///
/// Die erste Fassung war ganzflächig teal. Auf einem Bogen sind das zehn
/// Karten × zwei Seiten — bei einem Tintendrucker eine halbe Patrone je Bogen,
/// dazu wellt sich das Papier und der Farbauftrag wird fleckig. Gemessen:
/// **56,3 % Farbauftrag** vorher, **6,4 %** jetzt.
///
/// ## ⚠️ Schriftgrößen: nichts unter 7 pt
///
/// Am 13.08.2026 gegen die Empfehlungen der Druckereien geprüft und dabei
/// mehrere eigene Werte als zu klein erkannt: Slogan 5,6 pt, Amt 6,5 pt,
/// Mitgliedsnummer 5,5 pt, Sprachkürzel 5 pt. Der übereinstimmende Rat ist
/// **7 pt als absolutes Minimum**, darunter wird es im Druck unleserlich —
/// und zwar nicht „grenzwertig", sondern unlesbar für genau die Menschen, für
/// die dieser Verein da ist. Dazu die übliche Staffelung: Name 9–12 pt,
/// Funktion und Kontaktdaten 7–8 pt.
///
/// Die Höhe war dafür da: unter dem Kontaktblock standen rund 14 mm leer,
/// während oben alles aneinanderklebte. Jetzt verteilt sich der Satz über die
/// Karte, statt sich in der oberen Hälfte zu stapeln.
///
/// ⚠️ Sicherheitsabstand: 5 mm ringsum statt 4 mm unten. Druckereien nennen
/// 3 mm als Minimum und 5 mm als das Bessere — bei einem Bogen, den jemand
/// mit der Schere schneidet, ist das Bessere die richtige Wahl.
pw.Widget _karteVorne(VisitenkarteDaten d, pw.Font regular, pw.Font fett,
    Map<String, pw.ImageProvider> ikonen, Map<String, pw.ImageProvider> fahnen) {
  return pw.Container(
    color: PdfColors.white,
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(width: kBalkenBreite, color: kTonHell),
        pw.Expanded(
          child: pw.Padding(
            padding: const pw.EdgeInsets.all(kPolster),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(d.vereinsname,
                              style: pw.TextStyle(
                                  font: fett,
                                  fontSize: kGradVereinsname,
                                  color: kTonHell,
                                  letterSpacing: 0.5)),
                          pw.SizedBox(height: kAbstandNameLinie),
                          pw.Container(
                              width: kLinieBreite,
                              height: kLinieHoehe,
                              color: kTonHell),
                        ],
                      ),
                    ),
                    _sprachBlock(d, fett, ikonen, fahnen),
                  ],
                ),
                // ⚠️ Der Slogan steht UNTER der Zeile mit dem Sprachblock, nicht
                // neben ihm. Bei 7 pt braucht er rund 179 pt Breite; neben dem
                // Sprachblock blieben ihm nur etwa 145, und er brach zwischen
                // „360°" und „Support" um — also mitten in dem Teil, der die
                // Auflösung des Vereinsnamens trägt. Über die volle Breite
                // passt er in eine Zeile.
                pw.SizedBox(height: kAbstandLinieSlogan),
                pw.Text(d.slogan,
                    style: pw.TextStyle(
                        font: regular, fontSize: kGradSlogan, color: kTextLeise)),
                pw.Spacer(),
                // ⚠️ Der QR steht NEBEN dem ganzen Personenblock, nicht unter
                // ihm. Unter ihm addierte sich seine Höhe (59 pt) auf die von
                // Name, Amt und Kontaktzeilen — zusammen 140 pt bei 127,6 pt
                // verfügbarer Höhe. Der Column des PDF-Erzeugers wirft dann,
                // was nicht passt, **stillschweigend weg**: im Ausdruck fehlten
                // QR, Kontaktzeilen und Fußzeile, ohne Fehlermeldung, ohne
                // Warnung. Nebeneinander teilen sich beide dieselbe Höhe.
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.RichText(
                            text: pw.TextSpan(children: [
                              if (d.vorname.isNotEmpty)
                                pw.TextSpan(
                                    text: d.nachname.isEmpty
                                        ? d.vorname
                                        : '${d.vorname} ',
                                    style: pw.TextStyle(
                                        font: regular, fontSize: kGradName)),
                              if (d.nachname.isNotEmpty)
                                pw.TextSpan(
                                    text: d.nachname,
                                    style:
                                        pw.TextStyle(font: fett, fontSize: kGradName)),
                            ], style: pw.TextStyle(color: kTextDunkel)),
                          ),
                          pw.SizedBox(height: kAbstandNameAmt),
                          pw.Text(
                            [d.funktion, if (d.istGruender) 'Gründer']
                                .where((t) => t.isNotEmpty)
                                .join('  ·  '),
                            style: pw.TextStyle(
                                font: fett, fontSize: kGradAmt, color: kTonHell),
                          ),
                          pw.SizedBox(height: kAbstandAmtKontakt),
                          if (d.email.isNotEmpty)
                            _zeile(ikonen['email']!, d.email, regular),
                          if (d.festnetz.isNotEmpty)
                            _zeile(ikonen['phone']!, d.festnetz, regular),
                          if (d.mobil.isNotEmpty)
                            _zeile(ikonen['smartphone']!, d.mobil, regular),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: kAbstandQrSpalte),
                    _qrFeld(d),
                  ],
                ),
                pw.Spacer(),
                // ⚠️ Die Mitgliedsnummer ist der Anmeldename, nicht bloß eine
                // Ordnungszahl. Sie steht hier auf ausdrückliche Entscheidung
                // des Users (13.08.2026), nachdem sie kurz entfernt war —
                // nicht aus Unachtsamkeit.
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(d.mitgliedernummer,
                        style: pw.TextStyle(
                            font: regular,
                            fontSize: kGradFussNummer,
                            color: kTextLeise)),
                    pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
                      pw.SizedBox(
                        width: kIkoneWeb,
                        height: kIkoneWeb,
                        child: pw.Image(ikonen['language']!, fit: pw.BoxFit.contain),
                      ),
                      pw.SizedBox(width: 3),
                      pw.Text(d.web,
                          style: pw.TextStyle(
                              font: fett, fontSize: kGradFussWeb, color: kTonHell)),
                    ]),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// ♿ über den Sprachen, rechts oben.
pw.Widget _sprachBlock(VisitenkarteDaten d, pw.Font fett,
    Map<String, pw.ImageProvider> ikonen, Map<String, pw.ImageProvider> fahnen) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.end,
    children: [
      pw.SizedBox(
        width: kGradRollstuhl,
        height: kGradRollstuhl,
        child: pw.Image(ikonen['accessible']!, fit: pw.BoxFit.contain),
      ),
      if (d.sprachen.isNotEmpty) ...[
        pw.SizedBox(height: 2),
        pw.Row(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            for (final sp in d.sprachen) _sprachChip(sp, fett, fahnen),
          ],
        ),
      ],
    ],
  );
}

/// Fahne **und** Kürzel, übereinander.
///
/// Die Fahne ist eine mitgelieferte Bilddatei, kein Emoji und keine
/// gezeichnete Geometrie — die Gründe stehen in lib/utils/flaggen.dart. Wo
/// keine hinterlegt ist (Arabisch), steht das Kürzel allein.
///
/// ⚠️ `BoxFit.contain`, nicht `fill`: die Fahnen haben verschiedene
/// Seitenverhältnisse (Dänemark 37 : 28, Lettland 2 : 1). Gestreckt sähen sie
/// aus wie schlecht eingescannt.
pw.Widget _sprachChip(
    SprachAnzeige sp, pw.Font fett, Map<String, pw.ImageProvider> fahnen) {
  final bild = fahnen[sp.code];
  return pw.Padding(
    padding: const pw.EdgeInsets.only(left: kFahneAbstand),
    child: pw.Column(
      children: [
        if (bild != null)
          pw.Container(
            width: kFahneBreite,
            height: kFahneHoehe,
            decoration: pw.BoxDecoration(
              // Dünne Umrandung: die weißen Anteile (Polen, Finnland) gingen
              // sonst auf weißem Papier verloren, und die Fahne hätte plötzlich
              // eine andere Form.
              border: pw.Border.all(color: PdfColors.grey500, width: 0.2),
            ),
            child: pw.Image(bild, fit: pw.BoxFit.contain),
          ),
        pw.SizedBox(height: 1),
        pw.Text(sp.kuerzel,
            style: pw.TextStyle(
                font: fett, fontSize: kGradSprachKuerzel, color: kTextLeise)),
      ],
    ),
  );
}

/// Eine Kontaktzeile: Sinnbild, dann der Wert.
///
/// ⚠️ Sinnbild statt der Wortmarken „E-Mail" / „Tel." / „Mobil". Auf einer
/// Visitenkarte ist das die Konvention — Umschlag, Hörer und Handy versteht
/// man ohne Beschriftung, und die gesparte Breite kommt der Nummer zugute.
/// Es sind genau die Zeichen, die auch auf dem Bildschirm stehen.
/// Das QR-Feld: MECARD, damit die Kamera „Kontakt speichern" anbietet.
///
/// ## ⚠️ Die Kantenlänge ist gerechnet, nicht gewählt
///
/// Ein QR-Code ist nur so gut wie sein kleinstes Modul. Der MECARD dieser
/// Karte ergibt **45 × 45 Module**; bei [kQrKanteMm] = 18 mm sind das
/// **0,40 mm je Modul**. Unter etwa 0,4 mm verläuft die Tinte eines
/// Tintendruckers auf Normalpapier so weit, dass benachbarte Module
/// zusammenlaufen — der Code wäre dann nicht schlecht lesbar, sondern gar
/// nicht.
///
/// Deshalb steht im MECARD nur die Mobilnummer und nicht auch das Festnetz:
/// mit beiden wären es 49 Module und 0,37 mm. Und deshalb prüft ein Test die
/// Modulzahl — wer ein Feld hinzufügt, merkt es dort, nicht am toten Ausdruck.
///
/// ## ⚠️ Die Ruhezone kommt vom Papier
///
/// Ein QR braucht ringsum vier Module frei. Sie sind hier NICHT in die 18 mm
/// eingerechnet, sondern entstehen aus dem weißen Kartengrund — dafür hält der
/// Abstand zum Kontaktblock (6 pt) und zum Kartenrand mehr als die nötigen
/// 1,6 mm.
pw.Widget _qrFeld(VisitenkarteDaten d) {
  return pw.SizedBox(
        width: kQrKante,
        height: kQrKante,
        child: pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(
            // Stufe M (15 % Redundanz). L wäre luftiger, aber eine Karte im
            // Portemonnaie bekommt Knicke und Fingerabdrücke — dagegen hilft
            // Redundanz mehr als ein halbes Zehntel Millimeter je Modul.
            errorCorrectLevel: pw.BarcodeQRCorrectionLevel.medium,
          ),
          data: d.mecard,
          drawText: false,
          color: kTextDunkel,
        ),
  );
}

pw.Widget _zeile(pw.ImageProvider bild, String wert, pw.Font schrift) =>
    pw.Padding(
      // ⚠️ 4 pt, nicht 2. Bei 2 pt standen Umschlag, Hörer und Handy so dicht
      // untereinander, dass die drei Zeilen als ein Block gelesen wurden — auf
      // 85 mm ist der leere Raum das einzige Mittel, das sie trennt. Platz ist
      // da: unter dem Kontaktblock bleiben rund 14 mm frei.
      padding: const pw.EdgeInsets.only(bottom: kAbstandKontaktZeilen),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.SizedBox(
            width: kSpalteIkone,
            height: kIkoneKontakt,
            child: pw.Align(
              alignment: pw.Alignment.centerLeft,
              child: pw.SizedBox(
                width: kIkoneKontakt,
                height: kIkoneKontakt,
                child: pw.Image(bild, fit: pw.BoxFit.contain),
              ),
            ),
          ),
          pw.Text(wert,
              style: pw.TextStyle(
                  font: schrift, fontSize: kGradKontakt, color: kTextDunkel)),
        ],
      ),
    );

/// Die Rückseite — derselbe Balken an der Stange, damit beide Seiten als eine
/// Karte lesbar sind.
pw.Widget _karteHinten(VisitenkarteDaten d, pw.Font regular, pw.Font fett,
    Map<String, pw.ImageProvider> ikonen) {
  return pw.Container(
    color: PdfColors.white,
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(width: kBalkenBreite, color: kTonHell),
        pw.Expanded(
          child: pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(5 * _mm, 4.5 * _mm, 5 * _mm, 4 * _mm),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Text('Was wir tun',
                          style: pw.TextStyle(
                              font: fett, fontSize: 8.5, color: kTonHell)),
                    ),
                    pw.Text(d.vereinsname,
                        style: pw.TextStyle(
                            font: fett, fontSize: 5.5, color: kTextLeise)),
                  ],
                ),
                pw.SizedBox(height: 1.5),
                pw.Container(width: 18, height: 1.1, color: kTonHell),
                pw.SizedBox(height: 3.5),
                for (final (titel, was) in kVisitenkarteLeistungenPdf)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 1.3),
                    child: pw.RichText(
                      text: pw.TextSpan(children: [
                        pw.TextSpan(
                            text: '$titel  ',
                            style: pw.TextStyle(
                                font: fett, fontSize: 5.8, color: kTextDunkel)),
                        pw.TextSpan(
                            text: was,
                            style: pw.TextStyle(
                                font: regular, fontSize: 5.8, color: kTextLeise)),
                      ]),
                    ),
                  ),
                pw.SizedBox(height: 2.5),
                pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.SizedBox(
                      width: 7,
                      height: 7,
                      child: pw.Image(ikonen['accessible']!, fit: pw.BoxFit.contain)),
                  pw.SizedBox(width: 3),
                  pw.Expanded(
                    child: pw.Text(kVisitenkarteLeitsatzPdf,
                        style: pw.TextStyle(
                            font: regular, fontSize: 5.5, color: kTextDunkel)),
                  ),
                ]),
                pw.SizedBox(height: 2),
                pw.Text(kVisitenkarteAbgrenzungPdf,
                    style: pw.TextStyle(
                        font: regular,
                        fontSize: 5,
                        color: kTextLeise,
                        fontStyle: pw.FontStyle.italic)),
                pw.Spacer(),
                if (d.anschrift.isNotEmpty)
                  pw.Text(d.anschrift,
                      style: pw.TextStyle(
                          font: regular, fontSize: 5.3, color: kTextLeise)),
                pw.Text(
                  [d.web, if (d.register.isNotEmpty) d.register, 'gemeinnützig']
                      .join(' · '),
                  style: pw.TextStyle(font: regular, fontSize: 5.3, color: kTextLeise),
                ),
              ],
            ),
          ),
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
