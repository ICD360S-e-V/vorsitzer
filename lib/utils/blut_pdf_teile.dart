import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'blut_bedeutung.dart';

/// Bausteine des Blutanalyse-PDF.
///
/// ⚠️ Liegt EINMAL hier und nicht sechsmal in den Ärzte-Dialogen. Die
/// Erzeugung des Berichts stand vorher in jeder Kopie; eine Kopie, die einen
/// Baustein nicht mitbekommt, druckt still ein anderes Blatt.
///
/// ⚠️ KEINE Sonderzeichen im Text. Die Standardschrift eines PDF (Helvetica)
/// kennt nur die Zeichen aus CP1252. Pfeile wie „↑" und „↓" gehören NICHT
/// dazu — im alten Bericht standen deshalb an jeder auffälligen Zahl leere
/// Kästchen. Richtung und Lage werden hier GEZEICHNET: ein Balken für den
/// Referenzbereich, ein Punkt für den Messwert, und in Worten „über dem
/// Referenzbereich". Umlaute und „µ" sind in CP1252 enthalten und dürfen
/// bleiben.

/// Breite des Referenzbalkens in Punkt.
const double kBalkenBreite = 210;

const PdfColor _grauText = PdfColors.grey700;
const PdfColor _grauLeise = PdfColors.grey600;
const PdfColor _balkenBett = PdfColors.grey300;
const PdfColor _balkenGut = PdfColors.green600;
const PdfColor _hoch = PdfColors.red700;
const PdfColor _tief = PdfColors.blue700;

/// Text, den die eingebaute PDF-Schrift auch zeichnen kann.
///
/// ⚠️ Helvetica bringt im PDF nur einen festen Zeichensatz mit. Fehlt ein
/// Zeichen, malt das Paket ein leeres Kästchen — im alten Bericht stand
/// deshalb hinter jedem auffälligen Wert ein Kasten statt eines Pfeils.
///
/// ⚠️ Gefiltert wird BEIM DRUCKEN, nicht in den Texten selbst. Dieselben
/// Erklärungen stehen auch auf dem Bildschirm, und dort ist der Gedankenstrich
/// richtig; ihn in der Quelle zu entfernen hieße, die Anzeige zu verschlechtern,
/// um eine Einschränkung der PDF-Schrift zu umgehen.
///
/// ⚠️ Gefunden wurde die Lücke beim ANSEHEN des erzeugten Blattes, nicht beim
/// Lesen des Quelltextes: `flutter analyze` sieht nichts, und die Warnung
/// „Unable to find a font to draw" steht nur im Testprotokoll.
String pdfText(String s) => s
    .replaceAll('\u2014', '-')   // — Geviertstrich
    .replaceAll('\u2013', '-')   // – Halbgeviertstrich
    .replaceAll('\u2212', '-')   // − Minus
    .replaceAll('\u201e', '"')   // „
    .replaceAll('\u201c', '"')   // “
    .replaceAll('\u201d', '"')   // ”
    .replaceAll('\u2018', "'")
    .replaceAll('\u2019', "'")
    .replaceAll('\u2026', '...')
    .replaceAll('\u2192', '->')
    // ⚠️ Diese drei kommen aus echten Inhalten, nicht aus Zierrat: das
    // Warnzeichen steht in den Erklärungen zu Medikamentenspiegeln („geringe
    // therapeutische Breite"), und ‰ ist die richtige Einheit der
    // Retikulozyten. Beide wurden vom Test gefunden, nicht beim Lesen.
    .replaceAll('\u26a0\ufe0f', 'Achtung:')
    .replaceAll('\u26a0', 'Achtung:')
    .replaceAll('\ufe0f', '')      // Variantenwähler, hängt an Emoji
    .replaceAll('\u2030', 'Promille')
    .replaceAll('\u2191', '')    // ↑ — Richtung steht jetzt in Worten da
    .replaceAll('\u2193', '');

/// Ein Messwert mit Balken, Lage und Erklärung.
///
/// [status] ist 'normal', 'hoch' oder 'niedrig' — dieselben Werte, die der
/// Dialog schon berechnet.
pw.Widget blutPdfZeile({
  required String key,
  required String label,
  required String einheit,
  required String anzeige,
  required String status,
  required bool qualitativ,
  required num min,
  required num max,
  double? wert,
}) {
  final b = kBlutBedeutung[key];
  final aussen = status == 'hoch' || status == 'niedrig';

  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 10),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Kopfzeile: Bezeichnung links, Wert rechts
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Text(pdfText(label),
                  style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Text(pdfText('$anzeige${einheit.isEmpty ? '' : ' $einheit'}'),
                style: pw.TextStyle(
                    fontSize: 10.5,
                    fontWeight: pw.FontWeight.bold,
                    color: status == 'hoch'
                        ? _hoch
                        : status == 'niedrig'
                            ? _tief
                            : PdfColors.black)),
          ],
        ),
        if (!qualitativ && _hatBalken(min, max)) ...[
          pw.SizedBox(height: 3),
          _balken(min: min, max: max, wert: wert, status: status),
        ] else if (!qualitativ && _grenzText(min, max) != null) ...[
          pw.SizedBox(height: 2),
          pw.Text('Referenz: ${_grenzText(min, max)}',
              style: const pw.TextStyle(fontSize: 7.5, color: _grauLeise)),
        ],
        if (aussen) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            status == 'hoch'
                ? 'über dem Referenzbereich${_abstand(wert, max, true)}'
                : 'unter dem Referenzbereich${_abstand(wert, min, false)}',
            style: pw.TextStyle(fontSize: 8, color: status == 'hoch' ? _hoch : _tief),
          ),
        ],
        if (b != null) ...[
          pw.SizedBox(height: 3),
          pw.Text(pdfText(b.ist), style: const pw.TextStyle(fontSize: 8.5, color: _grauText)),
          if (status == 'hoch' && b.hoch.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 1),
              child: pw.Text(pdfText('Mögliche Ursachen: ${b.hoch}'),
                  style: const pw.TextStyle(fontSize: 8.5, color: _grauText)),
            ),
          if (status == 'niedrig' && b.tief.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 1),
              child: pw.Text(pdfText('Mögliche Ursachen: ${b.tief}'),
                  style: const pw.TextStyle(fontSize: 8.5, color: _grauText)),
            ),
        ],
      ],
    ),
  );
}

/// Wie weit der Wert daneben liegt, in Prozent der Grenze.
///
/// ⚠️ Nur wenn die Grenze größer als null ist. Bei Parametern, deren
/// Referenzbereich bei 0 beginnt (etwa LDL „0 bis 116"), wäre die
/// Prozentrechnung eine Division durch null.
String _abstand(double? wert, num grenze, bool nachOben) {
  if (wert == null || grenze <= 0) return '';
  // ⚠️ Nur, wenn die Zahl die Richtung auch belegt. `status` kommt aus dem
  // Dialog; stimmt er einmal nicht mit dem Wert überein, stünde hier sonst
  // „unter dem Referenzbereich (2,7 %)" an einem Wert, der darüber liegt —
  // eine Prozentzahl, die die Falschaussage bestätigt statt sie aufzudecken.
  if (nachOben && wert <= grenze) return '';
  if (!nachOben && wert >= grenze) return '';
  final p = ((wert - grenze) / grenze * 100).abs();
  if (p < 0.5) return '';
  final t = p >= 10 ? '${p.round()}' : p.toStringAsFixed(1).replaceAll('.', ',');
  return ' ($t %)';
}

/// Der Referenzbalken mit dem Punkt für den Messwert.
///
/// ⚠️ Alles gezeichnet, kein einziges Sonderzeichen: der Balken ist ein
/// Container, der Punkt ein Kreis. Damit gibt es nichts, was die Schrift
/// nicht darstellen könnte.
pw.Widget _balken({
  required num min,
  required num max,
  required double? wert,
  required String status,
}) {
  final spanne = (max - min).toDouble();
  // Lage des Punktes auf dem Balken, 0..1. Außerhalb liegende Werte werden an
  // den Rand gesetzt und zusätzlich in Worten benannt — den Balken zu dehnen
  // würde den Referenzbereich optisch verfälschen.
  double? anteil;
  if (wert != null && spanne > 0) {
    anteil = ((wert - min) / spanne).clamp(0.0, 1.0).toDouble();
  }
  final farbe = status == 'hoch' ? _hoch : (status == 'niedrig' ? _tief : _balkenGut);

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.SizedBox(
        width: 46,
        child: pw.Text(_zahlPaar(min, max),
            textAlign: pw.TextAlign.right,
            style: const pw.TextStyle(fontSize: 7.5, color: _grauLeise)),
      ),
      pw.SizedBox(width: 4),
      pw.Stack(
        alignment: pw.Alignment.centerLeft,
        children: [
          pw.Container(
            width: kBalkenBreite,
            height: 5,
            decoration: pw.BoxDecoration(
              color: _balkenBett,
              borderRadius: pw.BorderRadius.circular(2.5),
            ),
          ),
          if (anteil != null)
            pw.Container(
              margin: pw.EdgeInsets.only(
                  left: (anteil * kBalkenBreite - 3.5).clamp(0.0, kBalkenBreite - 7)),
              width: 7,
              height: 7,
              decoration: pw.BoxDecoration(color: farbe, shape: pw.BoxShape.circle),
            ),
        ],
      ),
      pw.SizedBox(width: 4),
      pw.SizedBox(
        width: 46,
        child: pw.Text(_zahlPaar(max, min),
            style: const pw.TextStyle(fontSize: 7.5, color: _grauLeise)),
      ),
      pw.SizedBox(width: 6),
      pw.Text('Referenz', style: const pw.TextStyle(fontSize: 7.5, color: _grauLeise)),
    ],
  );
}

String _zahl(num n) {
  final s = n.toStringAsFixed(n == n.roundToDouble() ? 0 : 2);
  return s.replaceAll('.', ',');
}

/// Die Quellenzeile unter dem Bericht.
///
/// ⚠️ Gehört ins Blatt, nicht nur in den Quelltext. Wer die Erklärungen liest,
/// muss nachsehen können, woher sie stammen — und sehen, dass sie keine
/// Diagnose sind.
pw.Widget blutPdfQuellen(Set<String> quellen) {
  final liste = quellen.where((q) => q.isNotEmpty).toList()..sort();
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 14),
    padding: const pw.EdgeInsets.only(top: 6),
    decoration: const pw.BoxDecoration(
      border: pw.Border(top: pw.BorderSide(color: PdfColors.grey400, width: 0.5)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Die Erklärungen sagen, was ein Wert misst und was eine Abweichung '
          'bedeuten kann. Sie sind keine Diagnose. Maßgeblich sind der '
          'Referenzbereich des Labors und die ärztliche Beurteilung.',
          style: const pw.TextStyle(fontSize: 7.5, color: _grauLeise),
        ),
        if (liste.isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 2),
            child: pw.Text(pdfText('Quellen: ${liste.join(' · ')}'),
                style: const pw.TextStyle(fontSize: 7.5, color: _grauLeise)),
          ),
      ],
    ),
  );
}

/// Der gesamte Blutanalyse-Bericht.
///
/// [werte] sind die ausgefuellten Parameter aus dem Dialog: die Eintraege der
/// gemeinsamen Parameterliste, ergaenzt um `value` (double oder String) und
/// `status` ('normal' | 'hoch' | 'niedrig' | 'auffällig').
pw.Document blutBerichtPdf({
  required String datum,
  required String patient,
  required String mitgliedsnummer,
  required List<Map<String, dynamic>> werte,
  required List<Map<String, dynamic>> auffaellig,
}) {
  final pdf = pw.Document();
  final quellen = <String>{};
  for (final p in werte) {
    final b = kBlutBedeutung[p['key'] as String];
    if (b != null) quellen.add(b.quelle);
  }

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 44),
      header: (ctx) => ctx.pageNumber == 1
          ? pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Blutanalyse',
                  style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 3),
              pw.Text(
                  pdfText([patient, datum, mitgliedsnummer]
                      .where((s) => s.trim().isNotEmpty)
                      .join('   ·   ')),
                  style: const pw.TextStyle(fontSize: 9.5, color: _grauLeise)),
              pw.SizedBox(height: 10),
            ])
          : pw.Container(),
      // ⚠️ Seitenzahl gehoert auf ein Blatt, das aus der Hand gegeben wird:
      // ein Befund ueber mehrere Seiten ist sonst nicht als vollstaendig
      // erkennbar.
      footer: (ctx) => pw.Container(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Seite ${ctx.pageNumber} von ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 7.5, color: _grauLeise)),
      ),
      build: (ctx) {
        final teile = <pw.Widget>[];

        teile.add(_zusammenfassung(werte.length, auffaellig.length));
        teile.add(pw.SizedBox(height: 12));

        String? letzteGruppe;
        for (final p in werte) {
          final gruppe = (p['gruppe'] as String?) ?? '';
          if (gruppe != letzteGruppe) {
            teile.add(pw.Container(
              margin: pw.EdgeInsets.only(top: letzteGruppe == null ? 0 : 8, bottom: 6),
              padding: const pw.EdgeInsets.only(bottom: 2),
              decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey500, width: 0.8)),
              ),
              child: pw.Text(pdfText(gruppe.toUpperCase()),
                  style: pw.TextStyle(
                      fontSize: 8.5,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 0.8,
                      color: _grauText)),
            ));
            letzteGruppe = gruppe;
          }

          final istQ = p['qualitativ'] == true;
          final roh = p['value'];
          teile.add(blutPdfZeile(
            key: p['key'] as String,
            label: p['label'] as String,
            einheit: istQ ? '' : ((p['unit'] as String?) ?? ''),
            anzeige: istQ ? '$roh' : _zahlText(roh),
            status: p['status'] as String,
            qualitativ: istQ,
            min: (p['min'] as num?) ?? 0,
            max: (p['max'] as num?) ?? 0,
            wert: roh is num ? roh.toDouble() : null,
          ));
        }

        teile.add(blutPdfQuellen(quellen));
        return teile;
      },
    ),
  );
  return pdf;
}

pw.Widget _zusammenfassung(int gesamt, int auffaellig) {
  final gut = auffaellig == 0;
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: pw.BoxDecoration(
      color: gut ? PdfColors.green50 : PdfColors.orange50,
      border: pw.Border(
          left: pw.BorderSide(color: gut ? _balkenGut : PdfColors.orange700, width: 3)),
    ),
    child: pw.Text(
      gut
          ? 'Alle $gesamt erfassten Werte liegen im Referenzbereich.'
          : '$auffaellig von $gesamt erfassten Werten liegen außerhalb des Referenzbereichs.',
      style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
    ),
  );
}

/// Messwert als Text — Komma statt Punkt, und keine erfundene Genauigkeit.
///
/// ⚠️ `toString()` auf einem double macht aus 7,9 die Zeichenfolge „7.9", aus
/// 201 aber „201.0". Eine ganze Zahl mit angehaengter Null sieht im Befund aus,
/// als waere sie genauer gemessen.
String _zahlText(dynamic roh) {
  if (roh is! num) return '$roh';
  final d = roh.toDouble();
  final s = d == d.roundToDouble() ? d.toStringAsFixed(0) : '$d';
  return s.replaceAll('.', ',');
}

/// Lohnt sich ein Balken?
///
/// ⚠️ `max = 999` ist in der Parameterliste die Marke für „nach oben offen"
/// (HDL-Cholesterin: „ab 40"). Ein Balken von 40 bis 999 setzt den Messwert
/// ganz an den linken Rand und behauptet damit eine Obergrenze, die es nicht
/// gibt — genau die Art Grafik, die schlimmer ist als keine.
bool _hatBalken(num min, num max) => max > min && max < 999;

/// Der Referenzbereich in Worten, wo kein Balken taugt.
String? _grenzText(num min, num max) {
  if (max >= 999 && min > 0) return 'ab ${_zahl(min)}';
  if (max < 999 && max > 0 && min <= 0) return 'bis ${_zahl(max)}';
  return null;
}

/// Zahl mit so vielen Nachkommastellen, wie das andere Ende des Balkens hat.
///
/// ⚠️ Einzeln formatiert stand am selben Balken „3,50" und „5". Beide Enden
/// gehören zu einer Angabe; unterschiedlich genau geschrieben sehen sie aus,
/// als wären sie unterschiedlich genau gemessen.
String _zahlPaar(num n, num anderes) {
  final stellen = _nachkomma(n) >= _nachkomma(anderes)
      ? _nachkomma(n)
      : _nachkomma(anderes);
  return n.toStringAsFixed(stellen).replaceAll('.', ',');
}

int _nachkomma(num n) {
  final d = n.toDouble();
  if (d == d.roundToDouble()) return 0;
  if ((d * 10) == (d * 10).roundToDouble()) return 1;
  return 2;
}
