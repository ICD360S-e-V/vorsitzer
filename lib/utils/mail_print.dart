/// Eine E-Mail drucken — auf einen echten Drucker, sonst als PDF.
///
/// Zwei Teile, absichtlich getrennt: [buildMailPdf] macht aus der Nachricht ein
/// PDF, [showMailPrintOptions] fragt danach, wohin es geht. So ist das Blatt
/// schon fertig, wenn die Auswahl aufgeht — beim Tippen auf einen Drucker gibt
/// es keine Wartezeit mehr, in der man nicht weiß, ob etwas passiert.
///
/// Warum ein eigenes PDF und nicht die formatierte Ansicht: die formatierte
/// Ansicht ist HTML des Absenders, und es gibt keinen Weg, HTML auf allen
/// Plattformen dieser App gleich zu drucken — `Printing.convertHtml` ist
/// abgekündigt und auf dem Desktop überhaupt nicht vorhanden. Der Textkörper
/// liegt dagegen immer vor und ergibt überall dasselbe Blatt.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Grenzen für den Textkörper — beides nötig, keins reicht allein.
///
/// Die Zeichengrenze hält den Umbruch (O(n)) im Rahmen. Die Zeilengrenze fängt
/// den Fall, den die Zeichengrenze durchlässt: 100 000 Leerzeilen sind kaum
/// Zeichen, aber tausende Seiten. `MultiPage` wirft irgendwann eine
/// `TooManyPagesException`, und dann kommt gar nichts aus dem Drucker.
const int _maxBodyChars = 120 * 1000;
const int _maxBodyLines = 1500;

/// Reserve über den Grenzen oben — das PDF soll nie an der Seitenzahl
/// scheitern, auch nicht bei Text, der ungünstig umbricht.
const int _maxPages = 200;

/// Frist für das Suchen der Drucker.
///
/// Das Auflisten fragt unter der Haube CUPS, und CUPS wartet auf jeden
/// eingetragenen Netzwerkdrucker. Steht einer davon nicht mehr im Netz, hängt
/// die Antwort — ohne Frist hängt dann der Knopf. Nach Ablauf gilt schlicht
/// „nicht auflistbar": Systemdialog und PDF bleiben beide erreichbar.
const Duration _lookupTimeout = Duration(seconds: 6);

pw.Font? _fontRegular;
pw.Font? _fontBold;

/// DejaVu liegt im Bundle (`assets/fonts/`).
///
/// Die eingebauten PDF-Standardschriften kennen nur Latin-1: rumänische,
/// ukrainische und russische Nachrichten — hier der Normalfall — kämen darin
/// als leere Kästchen aus dem Drucker. `PdfGoogleFonts` fällt aus, weil es die
/// Schrift bei Google nachlädt; Drucken muss offline gehen und darf nicht
/// nebenbei nach außen melden, dass gedruckt wird.
Future<void> _ensureFonts() async {
  _fontRegular ??=
      pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
  _fontBold ??=
      pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'));
}

/// Bringt den Textkörper auf eine druckbare Größe.
///
/// Leerzeilenketten werden auf zwei zusammengezogen: sie sind der billigste Weg
/// zu tausend Seiten, sichtbar ist ohnehin nichts davon.
String _prepareBody(String body) {
  var text = body
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
  if (text.isEmpty) return '(kein Text)';

  var cut = false;
  if (text.length > _maxBodyChars) {
    text = text.substring(0, _maxBodyChars);
    cut = true;
  }
  final lines = text.split('\n');
  if (lines.length > _maxBodyLines) {
    text = lines.take(_maxBodyLines).join('\n');
    cut = true;
  }
  return cut ? '$text\n\n[… für den Druck gekürzt]' : text;
}

/// Baut das druckfertige PDF einer Nachricht.
Future<Uint8List> buildMailPdf({
  required String subject,
  required String from,
  required String to,
  required String body,
  String cc = '',
  String date = '',
  String folder = '',
  List<String> attachments = const [],
}) async {
  await _ensureFonts();

  final title = subject.trim().isEmpty ? '(kein Betreff)' : subject.trim();
  final text = _prepareBody(body);
  final printedAt = DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now());

  final doc = pw.Document(
    title: title,
    theme: pw.ThemeData.withFont(base: _fontRegular, bold: _fontBold),
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(46, 42, 46, 34),
      maxPages: _maxPages,
      footer: (ctx) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 10),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Gedruckt am $printedAt',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            pw.Text('Seite ${ctx.pageNumber} von ${ctx.pagesCount}',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          ],
        ),
      ),
      build: (ctx) => [
        pw.Text(title,
            style: pw.TextStyle(
                font: _fontBold, fontSize: 15, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 12),
        _field('Von', from),
        _field('An', to),
        if (cc.trim().isNotEmpty) _field('Cc', cc),
        if (date.trim().isNotEmpty) _field('Datum', date),
        if (folder.trim().isNotEmpty) _field('Ordner', folder),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 12),
          child: pw.Divider(height: 1, color: PdfColors.grey400),
        ),
        // `TextOverflow.span` ist das, was den Textkörper über Seiten hinweg
        // umbrechen lässt. Ohne das wirft `MultiPage` bei jeder Nachricht, die
        // länger als eine Seite ist — der Standard ist `visible`, und ein
        // einzelnes Text-Widget gilt dann als unteilbar.
        pw.Text(text,
            style: const pw.TextStyle(fontSize: 10, lineSpacing: 2.2),
            overflow: pw.TextOverflow.span),
        if (attachments.isNotEmpty) ...[
          pw.SizedBox(height: 18),
          pw.Divider(height: 1, color: PdfColors.grey400),
          pw.SizedBox(height: 8),
          pw.Text(
            'Anhänge (${attachments.length}) — nicht mitgedruckt',
            style: pw.TextStyle(
                font: _fontBold, fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          for (final a in attachments)
            pw.Bullet(
                text: a,
                style: const pw.TextStyle(fontSize: 9.5),
                bulletSize: 1.6),
        ],
      ],
    ),
  );

  return doc.save();
}

pw.Widget _field(String label, String value) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 48,
            child: pw.Text(label,
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          ),
          pw.Expanded(
            child: pw.Text(value.trim(), style: const pw.TextStyle(fontSize: 9.5)),
          ),
        ],
      ),
    );

/// Fragt, wohin gedruckt wird: erst die gefundenen Drucker, dann der
/// Systemdialog, und als Ausweg das PDF.
///
/// Der PDF-Weg steht immer da, nicht nur wenn kein Drucker gefunden wurde. Im
/// Flatpak-Sandkasten ohne CUPS-Socket, auf einem Tablet ohne Druckdienst und
/// bei einem Drucker, der gerade offline ist, sieht das Auflisten identisch aus
/// — „kein Drucker gefunden" ist also nie ein sicherer Befund, und ein zweiter
/// Weg zum Papier gehört immer dazu.
Future<void> showMailPrintOptions(
  BuildContext context, {
  required Uint8List pdf,
  required String docName,
}) async {
  var canPrint = true;
  var canList = false;
  var printers = <Printer>[];
  try {
    final info = await Printing.info().timeout(_lookupTimeout);
    canPrint = info.canPrint;
    canList = info.canListPrinters;
    if (canList) {
      printers = (await Printing.listPrinters().timeout(_lookupTimeout))
          .where((p) => p.isAvailable)
          .toList()
        ..sort((a, b) {
          if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
    }
  } catch (_) {
    // Auflisten kann werfen (Flatpak ohne CUPS-Socket). Das ist kein Grund,
    // das Drucken ganz zu verweigern — Systemdialog und PDF bleiben.
    canList = false;
  }

  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) {
      final cs = Theme.of(sheet).colorScheme;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Row(
                children: [
                  const Icon(Icons.print_outlined, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Drucken',
                        style: Theme.of(sheet).textTheme.titleMedium),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(50, 0, 20, 8),
              child: Text(
                canList
                    ? (printers.isEmpty
                        ? 'Kein Drucker gefunden. Die Nachricht kann als PDF '
                            'gespeichert werden.'
                        : 'Auf einen Drucker legen oder als PDF speichern.')
                    : 'Der Systemdialog zeigt die Drucker des Geräts. Ohne '
                        'Drucker geht es als PDF.',
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  ...printers.map((p) {
                    final detail = _printerDetail(p);
                    return ListTile(
                      leading: Icon(
                          p.isDefault ? Icons.print : Icons.print_outlined),
                      title: Text(p.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: detail == null
                          ? null
                          : Text(detail,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () {
                        Navigator.pop(sheet);
                        _printToPrinter(messenger, p, pdf, docName);
                      },
                    );
                  }),
                  if (printers.isNotEmpty) const Divider(height: 1),
                  if (canPrint)
                    ListTile(
                      leading: const Icon(Icons.tune),
                      title: Text(printers.isEmpty
                          ? 'Drucker wählen (Systemdialog)'
                          : 'Anderer Drucker / Einstellungen'),
                      subtitle: const Text(
                          'Papierformat, Seiten und Anzahl einstellen'),
                      onTap: () {
                        Navigator.pop(sheet);
                        _printViaDialog(messenger, pdf, docName);
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.picture_as_pdf_outlined),
                    title: Text(_savesToFile
                        ? 'Als PDF speichern'
                        : 'Als PDF weitergeben'),
                    subtitle: Text(_savesToFile
                        ? 'Legt die Datei in den Ordner „Downloads"'
                        : 'Öffnet die Auswahl zum Teilen oder Speichern'),
                    onTap: () {
                      Navigator.pop(sheet);
                      _savePdf(messenger, pdf, docName);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Zweite Zeile eines Druckereintrags — `null`, wenn es nichts zu sagen gibt.
/// Ein leerer Untertitel macht die Zeile hoch und den Eintrag schief.
String? _printerDetail(Printer p) {
  final parts = [
    if (p.isDefault) 'Standarddrucker',
    if ((p.location ?? '').trim().isNotEmpty) p.location!.trim(),
    if ((p.model ?? '').trim().isNotEmpty) p.model!.trim(),
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Auf dem Desktop landet die Datei im Downloads-Ordner. Auf Android/iOS gibt es
/// keinen für die App erreichbaren Ordner, den der Nutzer danach wiederfindet —
/// dort übernimmt das Teilen-Blatt des Systems.
bool get _savesToFile => !(Platform.isAndroid || Platform.isIOS);

void _snack(ScaffoldMessengerState m, String text, {bool error = false}) {
  m.showSnackBar(SnackBar(
    content: Text(text),
    backgroundColor: error ? Colors.red.shade700 : null,
  ));
}

Future<void> _printToPrinter(ScaffoldMessengerState m, Printer printer,
    Uint8List pdf, String docName) async {
  try {
    final ok = await Printing.directPrintPdf(
      printer: printer,
      onLayout: (_) async => pdf,
      name: docName,
    );
    if (!ok) _snack(m, 'Druck abgebrochen.');
  } catch (e) {
    _snack(m, 'Drucken auf „${printer.name}" fehlgeschlagen: $e', error: true);
  }
}

Future<void> _printViaDialog(
    ScaffoldMessengerState m, Uint8List pdf, String docName) async {
  try {
    await Printing.layoutPdf(
      onLayout: (_) async => pdf,
      name: docName,
      // Das Blatt ist auf A4 gesetzt; ein erneutes Layout je Drucker würde nur
      // dasselbe PDF nochmal liefern.
      dynamicLayout: false,
    );
  } catch (e) {
    _snack(m, 'Drucken fehlgeschlagen: $e', error: true);
  }
}

Future<void> _savePdf(
    ScaffoldMessengerState m, Uint8List pdf, String docName) async {
  final fileName = '${_safeName(docName)}.pdf';
  try {
    if (!_savesToFile) {
      await Printing.sharePdf(bytes: pdf, filename: fileName);
      return;
    }

    Directory? dir;
    try {
      dir = await getDownloadsDirectory();
    } catch (_) {
      dir = null;
    }
    dir ??= await getApplicationDocumentsDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);

    final path = await _uniquePath(dir.path, fileName);
    await File(path).writeAsBytes(pdf, flush: true);

    m.showSnackBar(SnackBar(
      content: Text('Gespeichert: ${path.split(Platform.pathSeparator).last}'),
      action: SnackBarAction(
        label: 'Öffnen',
        onPressed: () => OpenFilex.open(path),
      ),
    ));
  } catch (e) {
    _snack(m, 'Speichern fehlgeschlagen: $e', error: true);
  }
}

/// Dateinamen aus dem Betreff — der kommt vom Absender, also nichts davon in
/// einen Pfad übernehmen, was einen Pfad ergeben könnte.
String _safeName(String name) {
  var s = name
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (s.length > 80) s = s.substring(0, 80).trim();
  s = s.replaceAll(RegExp(r'^\.+'), '');
  return s.isEmpty ? 'email' : s;
}

/// Nie stillschweigend überschreiben: `(1)`, `(2)`, … vor die Endung.
Future<String> _uniquePath(String dirPath, String fileName) async {
  final sep = Platform.pathSeparator;
  final dot = fileName.lastIndexOf('.');
  final base = dot > 0 ? fileName.substring(0, dot) : fileName;
  final ext = dot > 0 ? fileName.substring(dot) : '';
  var candidate = '$dirPath$sep$fileName';
  var i = 1;
  while (await File(candidate).exists()) {
    candidate = '$dirPath$sep$base ($i)$ext';
    i++;
  }
  return candidate;
}
