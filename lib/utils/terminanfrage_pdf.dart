import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'terminanfrage_vorlagen.dart';

/// Die Terminanfrage als Fax-taugliches PDF, im Namen des Mitglieds.
///
/// WARUM ÜBERHAUPT EIN PDF
/// Weil sipgate nichts anderes annimmt: `api/sipgate/sipgate_fax.php` prüft
/// vor dem Hochladen die `%PDF`-Kennung und lehnt alles andere ab. Der
/// E-Mail-Weg schickt denselben Inhalt als Text
/// ([TerminanfrageText.alsMailText]) — eine Anfrage, zwei Ausgänge, eine
/// Quelle. Wer den Brieftext hier noch einmal formuliert, lässt die beiden
/// Fassungen ab dem ersten Tag auseinanderlaufen.
///
/// LAYOUT
/// DIN 5008 wie [generateBetriebskostenAntragPdf]: A4, Rand links 24,1 mm,
/// rechts 8,1 mm, Anschriftenfeld ab 45 mm. Das ist kein Selbstzweck — ein
/// Brief, der aussieht wie jeder andere Geschäftsbrief, wird in einer
/// Anmeldung ohne Nachdenken einsortiert.
///
/// 🔴 SCHRIFT: DejaVu AUS DEM PAKET, NIEMALS DIE EINGEBAUTE HELVETICA.
/// Die erste Fassung nahm Helvetica — „reicht für Deutsch" — und das PDF sah
/// beim Durchlesen des Codes einwandfrei aus. Gerendert und mit `pdftotext`
/// zurückgelesen stand dort:
///
///     Ionu -Cristian Düinea-Müller
///     … ist hier nicht bekannt  ein früherer Termin ist nicht vermerkt.
///
/// Das rumänische `ț` und der Gedankenstrich sind in WinAnsi nicht enthalten
/// und wurden **stillschweigend weggelassen** — kein Fehler, keine Warnung,
/// nur weg. Beim Namen ist das nicht Kosmetik: auf einem Dokument, das später
/// als Nachweis dienen soll, stand der Name des Mitglieds falsch. Und der
/// Verein hat rumänische und ukrainische Mitglieder, bei kyrillischen Namen
/// wäre die Zeile leer geblieben.
///
/// `assets/fonts/DejaVuSans*.ttf` liegt bereits im Paket und wird aus
/// demselben Grund schon von `visitenkarte_pdf.dart` und `mail_print.dart`
/// benutzt. Es deckt Latin Extended (ă â î ș ț) und Kyrillisch ab.
///
/// ⚠️ Kein Nachladen aus dem Netz: das Fax entsteht auf dem Gerät, oft über
/// genau die Mobilfunkleitung, deren Langsamkeit wir beim Anbieter
/// reklamieren.
///
/// ⚠️ KEIN Vereinslogo und kein Briefkopf des Vereins. Absender ist das
/// Mitglied; der Verein steht im Text als derjenige, der die Termine
/// organisiert. Ein Vereinsbriefkopf über einer Patientenanfrage sieht aus wie
/// eine Anfrage des Vereins — und dann fragt die Praxis zu Recht nach einer
/// Vollmacht, die für eine Terminvereinbarung niemand braucht.
Future<Uint8List> terminanfragePdf({
  /// Wird, falls gesetzt, mit der Seitenzahl des fertigen Dokuments gerufen.
  ///
  /// ⚠️ Die Seitenzahl lässt sich NICHT aus den Bytes ablesen: das Paket
  /// komprimiert die Objektströme, `/Type /Page` steht nicht im Klartext im
  /// Dokument. Ein Test, der danach sucht, zählt still null und ist damit
  /// wertlos — genau so ist der erste Anlauf gescheitert. Die einzige
  /// verlässliche Quelle ist die Seitenliste des Dokuments selbst.
  ///
  /// Ein Fax wird pro Seite übertragen; wer wissen will, was rausgeht, will
  /// das vorher wissen.
  void Function(int seiten)? seitenzahl,
  required TerminanfrageVorlage vorlage,
  required TerminanfrageDaten daten,
  /// Datum in der Datumszeile, `dd.MM.yyyy`. Wird übergeben statt hier
  /// gebildet, damit ein Test dasselbe PDF zweimal erzeugen kann.
  required String datum,
  /// Faxnummer des Empfängers — nur für die Kopfzeile. Leer = keine Kopfzeile.
  String empfaengerFax = '',
}) async {
  final text = terminanfrageText(vorlage, daten);

  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
  final fett =
      pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'));
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: regular, bold: fett),
  );

  const mm = PdfPageFormat.mm;
  final format = PdfPageFormat.a4.copyWith(
    marginLeft: 24.1 * mm,
    marginRight: 8.1 * mm,
    marginTop: 4.5 * mm,
    marginBottom: 20 * mm,
  );

  const absenderGroesse = 8.5;
  const textGroesse = 10.5;

  final grau = PdfColors.grey700;

  // ── Kopfzeile ──────────────────────────────────────────────────────
  // ⚠️ „TELEFAX" oben drauf ist kein Schmuck. In einer Anmeldung liegt der
  // Ausdruck zwischen Rezepten und Befunden; die Zeile sagt in einer
  // Sekunde, was das Blatt ist und an welche Nummer es ging — und wenn
  // jemand später fragt „haben Sie das bekommen?", steht die Nummer drauf.
  pw.Widget kopfzeile() {
    if (empfaengerFax.trim().isEmpty) return pw.SizedBox(height: 6 * mm);
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 3),
      margin: const pw.EdgeInsets.only(bottom: 4 * mm),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('TELEFAX',
              style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 1.2,
                  color: grau)),
          pw.Text('an ${empfaengerFax.trim()}',
              style: pw.TextStyle(fontSize: 8, color: grau)),
        ],
      ),
    );
  }

  // ── Absender (Mitglied) ────────────────────────────────────────────
  //
  // ⚠️ OHNE Telefonnummer, aus demselben Grund wie im Angabenblock: den Termin
  // vereinbaren wir, und im Brief steht unsere Nummer mit dem Zeitfenster. Die
  // private Nummer des Mitglieds daneben führt nur dazu, dass die Anmeldung
  // dort anruft — bei jemandem, für den wir gerade deshalb anfragen.
  pw.Widget absender() {
    final zeilen = <String>[
      daten.vollerName,
      if (daten.strasse.isNotEmpty) daten.strasse,
      if ('${daten.plz} ${daten.ort}'.trim().isNotEmpty)
        '${daten.plz} ${daten.ort}'.trim(),
    ];
    return pw.Container(
      height: 26 * mm,
      alignment: pw.Alignment.bottomLeft,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          for (final z in zeilen)
            pw.Text(z, style: const pw.TextStyle(fontSize: absenderGroesse)),
          // ⚠️ Luft zwischen Absender und Anschriftenfeld. Ohne sie kleben
          // die beiden Blöcke aneinander und lesen sich auf dem Ausdruck wie
          // EINE Adresse — auf dem Screenshot sofort zu sehen, im Code nicht.
          pw.SizedBox(height: 5 * mm),
        ],
      ),
    );
  }

  // ── Anschriftenfeld (Praxis) ───────────────────────────────────────
  //
  // ⚠️ Die Anschrift MUSS im PDF stehen, nicht nur in der Faxnummer. Beim
  // Fax gibt es keinen Umschlag: was nicht auf dem Blatt steht, kommt nicht
  // an. Dieselbe Falle wie beim Briefversand über LetterXpress.
  pw.Widget anschrift() {
    final zeilen = <String>[
      if (daten.praxisName.isNotEmpty) daten.praxisName,
      if (daten.arztName.isNotEmpty && daten.arztName != daten.praxisName)
        daten.arztName,
      if (daten.praxisStrasse.isNotEmpty) daten.praxisStrasse,
      if (daten.praxisPlzOrt.isNotEmpty) daten.praxisPlzOrt,
    ];
    return pw.Container(
      height: 34 * mm,
      width: 85 * mm,
      alignment: pw.Alignment.topLeft,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (final z in zeilen.isEmpty ? const ['An die Praxis'] : zeilen)
            pw.Text(z, style: const pw.TextStyle(fontSize: textGroesse)),
        ],
      ),
    );
  }

  // ── Angabenblock ───────────────────────────────────────────────────
  //
  // Im Brief eine Tabelle, in der E-Mail Zeilen — derselbe Inhalt. Ein Kasten
  // deshalb, weil die Anmeldung genau hier abtippt: Name, Geburtsdatum,
  // Versichertennummer. Was sie sucht, soll nicht im Fließtext liegen.
  pw.Widget angaben() => pw.Container(
        width: double.infinity,
        margin: const pw.EdgeInsets.only(top: 4 * mm),
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Angaben zur Patientin / zum Patienten',
                style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: grau)),
            pw.SizedBox(height: 4),
            for (final (label, wert) in text.angaben)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 1.5),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.SizedBox(
                      width: 42 * mm,
                      child: pw.Text('$label:',
                          style: const pw.TextStyle(fontSize: 10)),
                    ),
                    pw.Expanded(
                      child: pw.Text(wert,
                          style: pw.TextStyle(
                              fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );

  doc.addPage(
    pw.MultiPage(
      pageFormat: format,
      // ⚠️ „Seite x von y" ist beim Fax nicht optional: eine Übertragung kann
      // mittendrin abbrechen, und dann liegt in der Anmeldung ein halber
      // Brief, den niemand als halb erkennt.
      footer: (ctx) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 6),
        child: pw.Text(
          'Seite ${ctx.pageNumber} von ${ctx.pagesCount}',
          style: pw.TextStyle(fontSize: 8, color: grau),
        ),
      ),
      build: (ctx) => [
        kopfzeile(),
        absender(),
        anschrift(),
        pw.Container(
          alignment: pw.Alignment.centerRight,
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            '${daten.ort.isEmpty ? '' : '${daten.ort}, '}$datum',
            style: const pw.TextStyle(fontSize: textGroesse),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 10),
          child: pw.Text(text.betreff,
              style: pw.TextStyle(
                  fontSize: 11.5, fontWeight: pw.FontWeight.bold)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 12),
          child: pw.Text('Sehr geehrte Damen und Herren,',
              style: const pw.TextStyle(fontSize: textGroesse)),
        ),
        for (final absatz in text.absaetze)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6),
            child: pw.Text(
              absatz,
              textAlign: pw.TextAlign.justify,
              style: const pw.TextStyle(fontSize: textGroesse, lineSpacing: 1.2),
            ),
          ),
        angaben(),
        // 🔴 UNTEILBAR. Beim ersten Anlauf stand hier ein `pw.Padding` um
        // eine `pw.Column` — und `MultiPage` darf eine Column zwischen ihren
        // Kindern trennen. Bei einem etwas längeren Brief (Sanitätshaus mit
        // drei Gründen und der Rezeptfrist) landete deshalb „Mit
        // freundlichen Grüßen" auf Seite 1 und der NAME allein auf Seite 2.
        // Ein Fax, dessen zweite Seite aus einem Wort besteht, kostet eine
        // Seite Übertragung und sieht in der Anmeldung nach Fehler aus.
        //
        // Ein `pw.Container` ist kein spannendes Widget: passt er nicht mehr
        // aufs Blatt, wandert er GANZ auf das nächste — Grußformel und Name
        // bleiben zusammen.
        pw.Container(
          margin: const pw.EdgeInsets.only(top: 4 * mm),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Mit freundlichen Grüßen',
                  style: const pw.TextStyle(fontSize: textGroesse)),
              // ⚠️ Kein Unterschriftsstrich und kein Bild. Eine
              // Terminvereinbarung ist formlos; ein leerer Strich auf einem
              // Fax sieht dagegen nach „hier fehlt etwas" aus, und eine
              // eingesetzte Unterschriftsgrafik wäre eine Unterschrift, die
              // das Mitglied unter diesen konkreten Text nie geleistet hat.
              pw.SizedBox(height: 6 * mm),
              pw.Text(daten.vollerName,
                  style: const pw.TextStyle(fontSize: textGroesse)),
            ],
          ),
        ),
      ],
    ),
  );

  final bytes = await doc.save();
  seitenzahl?.call(doc.document.pdfPageList.pages.length);
  return bytes;
}

/// Dateiname des Fax-Anhangs.
///
/// ⚠️ Nur ASCII und keine Leerzeichen: der Name geht als `filename` in die
/// sipgate-REST-Anfrage und taucht später in Verlauf und Sendebericht auf.
/// Umlaute überleben diesen Weg nicht zuverlässig, und ein Name wie
/// `Terminanfrage_Müller.pdf` wird dort zu Zeichensalat — genau in dem
/// Dokument, das später als Nachweis dienen soll.
String terminanfrageDateiname(TerminanfrageDaten d, String datum) {
  const umschrift = {
    'ä': 'ae', 'ö': 'oe', 'ü': 'ue', 'Ä': 'Ae', 'Ö': 'Oe', 'Ü': 'Ue',
    'ß': 'ss',
    // ⚠️ Rumänisch und Ukrainisch sind hier keine Sonderfälle, sondern der
    // Alltag: aus „Ionuț" wurde vorher „Ionu_".
    'ă': 'a', 'â': 'a', 'î': 'i', 'ș': 's', 'ş': 's', 'ț': 't', 'ţ': 't',
    'Ă': 'A', 'Â': 'A', 'Î': 'I', 'Ș': 'S', 'Ş': 'S', 'Ț': 'T', 'Ţ': 'T',
    'é': 'e', 'è': 'e', 'ê': 'e', 'á': 'a', 'à': 'a', 'ó': 'o', 'ô': 'o',
    'í': 'i', 'ú': 'u', 'ç': 'c', 'ñ': 'n', 'ł': 'l', 'ż': 'z', 'ź': 'z',
    'ć': 'c', 'ę': 'e', 'ą': 'a', 'ś': 's', 'ń': 'n',
  };
  var name = '${d.nachname}_${d.vorname}';
  umschrift.forEach((von, nach) => name = name.replaceAll(von, nach));
  name = name
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')
      .replaceAll(RegExp(r'_+'), '_');
  final tag = datum.replaceAll('.', '-');
  return 'Terminanfrage_${name}_$tag.pdf';
}
