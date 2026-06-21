import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Generates the "Nachweis von Eigenbemühungen" PDF in the richer Rhein-Lahn
/// 6-column layout: Datum | Firma (Adresse) | Ansprechpartner | Beworben als |
/// Art | Ergebnis — fed from `jobcenter_av_eigenbem` entries.
///
/// Header data:
/// - Name, Vorname, Geburtsdatum: aus `users` (= Verifizierung Stufe 1).
/// - Kunden-Nr.: aus `jobcenter_data.stammdaten.kundennummer`.
///
/// Kein Vereinsname/Logo — das Formular gehört dem Mitglied, nicht dem Verein.
class EigenbemPdfGenerator {
  static const _artCodes = {
    'stellenangebot_ba':  4,  // online (BA-Portal)
    'initiativbewerbung': 4,  // online/E-Mail
    'online_portal':      4,  // online/E-Mail
    'zeitung':            2,  // schriftlich
    'vermittlung':        2,  // schriftlich (per Post via Jobcenter)
    'sonstige':           2,  // schriftlich (default)
  };
  static const _ergCodes = {
    'offen':                 1,
    'laeuft':                1,
    'keine_rueckmeldung':    1,
    'vorstellungsgespraech': 2,
    'absage':                3,
    'einstellung':           4,
  };

  static String _fmtDateDE(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final p = iso.split('-');
      if (p.length >= 3) return '${p[2].substring(0, 2)}.${p[1]}.${p[0]}';
    } catch (_) {}
    return iso;
  }

  static String _monatLabel(String ym) {
    const de = ['','Januar','Februar','März','April','Mai','Juni','Juli',
                'August','September','Oktober','November','Dezember'];
    if (ym.length != 7) return ym;
    final p = ym.split('-');
    final m = int.tryParse(p[1]) ?? 0;
    if (m < 1 || m > 12) return ym;
    return '${de[m]} ${p[0]}';
  }

  static Future<Uint8List> build({
    required String vorname,
    required String nachname,
    required String? geburtsdatum,   // ISO YYYY-MM-DD
    required String kundennummer,
    required String monat,           // YYYY-MM
    required List<Map<String, dynamic>> eintraege,
  }) async {
    final doc = pw.Document();

    final today = DateTime.now();
    final todayStr = '${today.day.toString().padLeft(2, '0')}.'
                     '${today.month.toString().padLeft(2, '0')}.${today.year}';

    final headerCellStyle = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);
    final cellStyle = pw.TextStyle(fontSize: 8);
    final smallGray = pw.TextStyle(fontSize: 7, color: PdfColors.grey700);

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(20, 18, 20, 18),
      header: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('Nachweis von Eigenbemühungen',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 2),
        pw.Text('Meine Bewerbungsaktivitäten — ${_monatLabel(monat)}',
          style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.SizedBox(height: 8),
        // Personenfelder als Tabellenzeile
        pw.Container(
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400, width: 0.5)),
          padding: const pw.EdgeInsets.all(6),
          child: pw.Row(children: [
            pw.Expanded(flex: 5, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Name, Vorname:', style: smallGray),
              pw.Text('$nachname, $vorname', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            ])),
            pw.Expanded(flex: 3, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Kunden-Nr.:', style: smallGray),
              pw.Text(kundennummer.isEmpty ? '—' : kundennummer,
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            ])),
            pw.Expanded(flex: 3, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Geb.-Datum:', style: smallGray),
              pw.Text(_fmtDateDE(geburtsdatum).isEmpty ? '—' : _fmtDateDE(geburtsdatum),
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            ])),
          ]),
        ),
        pw.SizedBox(height: 8),
      ]),
      footer: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.SizedBox(height: 6),
        pw.Text(
          'Wichtig: Bitte diese Unterlagen spätestens zu dem in Ihrer Eingliederungsvereinbarung '
          'vereinbarten Termin beim Jobcenter einreichen.',
          style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 10),
        pw.Row(children: [
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Container(width: 200, height: 0.5, color: PdfColors.grey700),
            pw.SizedBox(height: 2),
            pw.Text('Ort, Datum', style: smallGray),
          ])),
          pw.SizedBox(width: 30),
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Container(width: 200, height: 0.5, color: PdfColors.grey700),
            pw.SizedBox(height: 2),
            pw.Text('Unterschrift', style: smallGray),
          ])),
        ]),
        pw.SizedBox(height: 4),
        pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text(
          'Erstellt am $todayStr · Seite ${ctx.pageNumber} / ${ctx.pagesCount}',
          style: pw.TextStyle(fontSize: 7, color: PdfColors.grey500),
        )),
      ]),
      build: (ctx) => [
        // Tabel cu 6 coloane
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
          columnWidths: const {
            0: pw.FixedColumnWidth(55),   // Datum
            1: pw.FlexColumnWidth(2.5),   // Firma + Adresse
            2: pw.FlexColumnWidth(1.5),   // Ansprechpartner
            3: pw.FlexColumnWidth(2),     // Beworben als
            4: pw.FixedColumnWidth(35),   // Art
            5: pw.FixedColumnWidth(45),   // Ergebnis
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                _hCell('Datum', headerCellStyle),
                _hCell('Firma (Straße, Ort, Telefon)', headerCellStyle),
                _hCell('Ansprech-\npartner', headerCellStyle),
                _hCell('Beworben als\n(Tätigkeit / Beruf)', headerCellStyle),
                _hCell('Art', headerCellStyle),
                _hCell('Ergebnis', headerCellStyle),
              ],
            ),
            ...eintraege.map((e) {
              final art = (e['art'] ?? 'sonstige').toString();
              final erg = (e['ergebnis'] ?? 'offen').toString();
              final artCode = _artCodes[art] ?? 2;
              final ergCode = _ergCodes[erg] ?? 1;
              final firma = (e['arbeitgeber'] ?? '').toString();
              final adresse = (e['adresse'] ?? '').toString();
              final taet = (e['taetigkeit'] ?? '').toString();
              return pw.TableRow(children: [
                _cell(_fmtDateDE(e['datum_bewerbung']?.toString()), cellStyle),
                _firmaCell(firma, adresse, cellStyle, smallGray),
                _cell('', cellStyle), // Ansprechpartner blank (nu salvăm încă)
                _cell(taet, cellStyle),
                _cell('$artCode', cellStyle, center: true),
                _cell('$ergCode', cellStyle, center: true),
              ]);
            }),
            // Umple rândurile rămase la minim 10 (estetic)
            for (int i = eintraege.length; i < 10; i++)
              pw.TableRow(children: [
                _cell('', cellStyle), _cell('', cellStyle), _cell('', cellStyle),
                _cell('', cellStyle), _cell('', cellStyle), _cell('', cellStyle),
              ]),
          ],
        ),
        pw.SizedBox(height: 8),
        // Legendă codes
        pw.Container(
          padding: const pw.EdgeInsets.all(6),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
          ),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Art der Bewerbung:', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 2),
              pw.Text('1 = persönlich', style: cellStyle),
              pw.Text('2 = schriftlich', style: cellStyle),
              pw.Text('3 = telefonisch', style: cellStyle),
              pw.Text('4 = online / E-Mail', style: cellStyle),
            ])),
            pw.SizedBox(width: 20),
            pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Ergebnis:', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 2),
              pw.Text('1 = beworben, Antwort steht aus', style: cellStyle),
              pw.Text('2 = Vorstellungsgespräch', style: cellStyle),
              pw.Text('3 = Absage', style: cellStyle),
              pw.Text('4 = eingestellt zum', style: cellStyle),
            ])),
          ]),
        ),
      ],
    ));

    return doc.save();
  }

  static pw.Widget _hCell(String text, pw.TextStyle style) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
    child: pw.Text(text, style: style, textAlign: pw.TextAlign.center),
  );

  static pw.Widget _cell(String text, pw.TextStyle style, {bool center = false}) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
    constraints: const pw.BoxConstraints(minHeight: 26),
    alignment: center ? pw.Alignment.center : pw.Alignment.centerLeft,
    child: pw.Text(text, style: style),
  );

  static pw.Widget _firmaCell(String firma, String adresse, pw.TextStyle main, pw.TextStyle sub) =>
    pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      constraints: const pw.BoxConstraints(minHeight: 26),
      alignment: pw.Alignment.centerLeft,
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, mainAxisSize: pw.MainAxisSize.min, children: [
        if (firma.isNotEmpty)
          pw.Text(firma, style: main.copyWith(fontWeight: pw.FontWeight.bold)),
        if (adresse.isNotEmpty)
          pw.Text(adresse, style: sub, maxLines: 2),
      ]),
    );
}
