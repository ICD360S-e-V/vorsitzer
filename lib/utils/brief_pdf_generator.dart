import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Data assembled from users / jobcenter_data / jobcenter_datenbank / vermieter_mietvertraege / NKA
/// to render a DIN 5008 Antrag auf Übernahme der Betriebskostennachforderung KdU.
class BetriebskostenBriefData {
  // Absender (member)
  final String absVorname;
  final String absNachname;
  final String absStrasse;
  final String absHausnummer;
  final String absPlz;
  final String absOrt;
  final String absTelefon;

  // Empfänger (Jobcenter)
  final String jcDienststelle;
  final String jcAnsprechpartner; // optional, can be empty
  final String jcStrasse;
  final String jcHausnummer;
  final String jcPlz;
  final String jcOrt;

  // Reference numbers
  final String kundennummer;
  final String bgNummer;

  // Wohnung (rented address — appears in brieftext for clarity)
  final String wohnungStrasse;
  final String wohnungHausnummer;
  final String wohnungPlz;
  final String wohnungOrt;

  // NKA details
  final String abrechnungsjahr; // e.g. "2025"
  final String zeitraumVon; // "01.01.2025"
  final String zeitraumBis; // "31.12.2025"
  final String nachzahlungBetrag; // "234,50"
  final List<String> anlagen; // filename list

  // Datum/Ort line (top-right, after Anschriftenfeld)
  final String briefOrt;
  final String briefDatum; // "04.06.2026"

  BetriebskostenBriefData({
    required this.absVorname,
    required this.absNachname,
    required this.absStrasse,
    required this.absHausnummer,
    required this.absPlz,
    required this.absOrt,
    required this.absTelefon,
    required this.jcDienststelle,
    required this.jcAnsprechpartner,
    required this.jcStrasse,
    required this.jcHausnummer,
    required this.jcPlz,
    required this.jcOrt,
    required this.kundennummer,
    required this.bgNummer,
    required this.wohnungStrasse,
    required this.wohnungHausnummer,
    required this.wohnungPlz,
    required this.wohnungOrt,
    required this.abrechnungsjahr,
    required this.zeitraumVon,
    required this.zeitraumBis,
    required this.nachzahlungBetrag,
    required this.anlagen,
    required this.briefOrt,
    required this.briefDatum,
  });
}

/// Generates a DIN 5008 conformant Antrag PDF.
///
/// Layout follows DIN 5008:2020 — A4 portrait, margins 24.1mm left / 8.1mm right /
/// 4.5mm top / 25mm bottom. Briefkopf (Absender) at top-left, Anschriftenfeld
/// (recipient) begins at 45mm from top. Falzmarken at 105mm and 210mm on the
/// left edge for tri-fold. No handwritten signature line — § 9 SGB X allows
/// formless requests.
Future<Uint8List> generateBetriebskostenAntragPdf(BetriebskostenBriefData d) async {
  final doc = pw.Document();

  // DIN 5008 measurements in PDF points (1mm ≈ 2.83465 points)
  const mm = PdfPageFormat.mm;
  final pageFormat = PdfPageFormat.a4.copyWith(
    marginLeft: 24.1 * mm,
    marginRight: 8.1 * mm,
    marginTop: 4.5 * mm,
    marginBottom: 25 * mm,
  );

  // Anschriftenfeld starts at 45mm from page top => from content top (4.5mm)
  // that's 40.5mm of empty Briefkopf area. We reserve ~30mm for Absender (5 lines)
  // and pad to 40.5mm.
  const absenderFontSize = 9.0;
  const bodyFontSize = 11.0;
  const betreffFontSize = 11.5;

  pw.Widget buildAbsenderBlock() => pw.Container(
    height: 40.5 * mm,
    alignment: pw.Alignment.topLeft,
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, mainAxisAlignment: pw.MainAxisAlignment.end, children: [
      pw.Text('${d.absVorname} ${d.absNachname}'.trim(), style: pw.TextStyle(fontSize: absenderFontSize, fontWeight: pw.FontWeight.normal)),
      pw.Text('${d.absStrasse} ${d.absHausnummer}'.trim(), style: const pw.TextStyle(fontSize: absenderFontSize)),
      pw.Text('${d.absPlz} ${d.absOrt}'.trim(), style: const pw.TextStyle(fontSize: absenderFontSize)),
      if (d.absTelefon.trim().isNotEmpty)
        pw.Text('Tel.: ${d.absTelefon}', style: const pw.TextStyle(fontSize: absenderFontSize)),
      pw.SizedBox(height: 2 * mm),
    ]),
  );

  pw.Widget buildAnschriftenfeld() => pw.Container(
    height: 45 * mm, // 9 lines × 4.23mm-ish = ~40mm + padding
    width: 85 * mm,
    alignment: pw.Alignment.topLeft,
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('An das', style: const pw.TextStyle(fontSize: bodyFontSize)),
      pw.Text(() {
        final name = d.jcDienststelle.trim();
        if (name.isEmpty) return 'Jobcenter';
        // selected_amt_name already starts with "Jobcenter ..." for proper Behörden;
        // only prepend when the field has just a city name (legacy "dienststelle" value).
        return name.toLowerCase().startsWith('jobcenter') ? name : 'Jobcenter $name';
      }(), style: const pw.TextStyle(fontSize: bodyFontSize)),
      if (d.jcAnsprechpartner.trim().isNotEmpty)
        pw.Text('z. Hd. ${d.jcAnsprechpartner}', style: const pw.TextStyle(fontSize: bodyFontSize)),
      pw.Text('${d.jcStrasse} ${d.jcHausnummer}'.trim(), style: const pw.TextStyle(fontSize: bodyFontSize)),
      pw.Text('${d.jcPlz} ${d.jcOrt}'.trim(), style: const pw.TextStyle(fontSize: bodyFontSize)),
    ]),
  );

  pw.Widget buildDatumLine() => pw.Container(
    alignment: pw.Alignment.centerRight,
    padding: const pw.EdgeInsets.only(top: 8),
    child: pw.Text('${d.briefOrt.isEmpty ? d.absOrt : d.briefOrt}, ${d.briefDatum}', style: const pw.TextStyle(fontSize: bodyFontSize)),
  );

  pw.Widget buildBetreff() => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 14),
    child: pw.Text(
      'Antrag auf Übernahme der Nebenkostenabrechnung nach § 22 Abs. 1 SGB II',
      style: pw.TextStyle(fontSize: betreffFontSize, fontWeight: pw.FontWeight.bold),
    ),
  );

  pw.Widget buildBezugszeile() => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 14),
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      if (d.kundennummer.trim().isNotEmpty)
        pw.Text('Kundennummer: ${d.kundennummer}', style: const pw.TextStyle(fontSize: bodyFontSize)),
      if (d.bgNummer.trim().isNotEmpty)
        pw.Text('BG-Nummer:    ${d.bgNummer}', style: const pw.TextStyle(fontSize: bodyFontSize)),
    ]),
  );

  pw.Widget buildBrieftext() {
    final wohnungParts = <String>[];
    final wAdr = '${d.wohnungStrasse} ${d.wohnungHausnummer}'.trim();
    if (wAdr.isNotEmpty) wohnungParts.add(wAdr);
    final wOrt = '${d.wohnungPlz} ${d.wohnungOrt}'.trim();
    if (wOrt.isNotEmpty) wohnungParts.add(wOrt);
    final wohnungSatz = wohnungParts.isEmpty
        ? ''
        : ' für die Wohnung ${wohnungParts.join(', ')}';

    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 18),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('Sehr geehrte Damen und Herren,', style: const pw.TextStyle(fontSize: bodyFontSize)),
        pw.SizedBox(height: 12),
        pw.Text(
          'hiermit beantrage ich die Übernahme der Kosten aus der beigefügten Nebenkostenabrechnung$wohnungSatz.',
          style: const pw.TextStyle(fontSize: bodyFontSize),
        ),
        pw.SizedBox(height: 14),
        pw.Text(
          'Abrechnungszeitraum: ${d.zeitraumVon} bis ${d.zeitraumBis}',
          style: const pw.TextStyle(fontSize: bodyFontSize),
        ),
        pw.SizedBox(height: 10),
        pw.Row(children: [
          pw.SizedBox(width: 250, child: pw.Text('Nachzahlungsbetrag:', style: const pw.TextStyle(fontSize: bodyFontSize))),
          pw.Text('${d.nachzahlungBetrag} EUR', style: pw.TextStyle(fontSize: bodyFontSize, fontWeight: pw.FontWeight.bold)),
        ]),
        pw.SizedBox(height: 14),
        pw.Text(
          'Die Nebenkostenabrechnung ist diesem Antrag in Kopie beigefügt.',
          style: const pw.TextStyle(fontSize: bodyFontSize),
        ),
      ]),
    );
  }

  pw.Widget buildGruss() => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 22),
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('Mit freundlichen Grüßen', style: const pw.TextStyle(fontSize: bodyFontSize)),
      pw.SizedBox(height: 22),
      // No handwritten signature line — § 9 SGB X allows formless (no signature required)
      pw.Text('${d.absVorname} ${d.absNachname}'.trim(), style: const pw.TextStyle(fontSize: bodyFontSize)),
    ]),
  );

  pw.Widget buildAnlagen() => d.anlagen.isEmpty
      ? pw.SizedBox()
      : pw.Padding(
          padding: const pw.EdgeInsets.only(top: 18),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Anlagen:', style: pw.TextStyle(fontSize: bodyFontSize, fontWeight: pw.FontWeight.bold)),
            ...d.anlagen.map((a) => pw.Padding(padding: const pw.EdgeInsets.only(top: 2), child: pw.Text('- $a', style: const pw.TextStyle(fontSize: bodyFontSize)))),
          ]),
        );

  doc.addPage(pw.Page(
    pageFormat: pageFormat,
    build: (ctx) {
      return pw.Stack(children: [
        // Falzmarken: thin horizontal ticks on the LEFT edge of the page at 105mm and 210mm from page top.
        // These help fold the paper into thirds. They sit just outside the content area (in the left margin).
        pw.Positioned(left: -22 * mm, top: 105 * mm - 4.5 * mm, child: pw.Container(width: 4 * mm, height: 0.3, color: PdfColors.grey400)),
        pw.Positioned(left: -22 * mm, top: 210 * mm - 4.5 * mm, child: pw.Container(width: 4 * mm, height: 0.3, color: PdfColors.grey400)),
        // Lochmarke: 1mm tick at 148.5mm (mid-page) — for archive hole punch.
        pw.Positioned(left: -22 * mm, top: 148.5 * mm - 4.5 * mm, child: pw.Container(width: 4 * mm, height: 0.3, color: PdfColors.grey400)),

        // Content column
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          buildAbsenderBlock(),
          buildAnschriftenfeld(),
          buildDatumLine(),
          buildBetreff(),
          buildBezugszeile(),
          buildBrieftext(),
          buildGruss(),
          buildAnlagen(),
        ]),
      ]);
    },
  ));

  return doc.save();
}
