/// Zeigt einen HTML-Anhang IN der App an — nie in einem fremden Programm.
///
/// Warum überhaupt eigens dafür etwas gebaut wird:
/// Bis hierher fiel ein `.html`-Anhang durch den eingebauten Betrachter
/// (der kennt nur PDF und Bilder), wurde auf die Platte geschrieben und an
/// `OpenFilex` übergeben — also an den Systembrowser. Damit war jede
/// Schutzmaßnahme des Mailpfads auf einen Schlag weg: der Browser führt
/// JavaScript aus, lädt externe Bilder (Zählpixel), folgt `meta refresh`,
/// stellt Formulare zu und legt eine unverschlüsselte Kopie im
/// Temp-Verzeichnis ab. Ein HTML-Anhang ist der klassische Weg für
/// Phishing-Seiten („Rechnung.html", die eine Anmeldemaske nachbaut), und
/// hier gehen Arzt-, Jobcenter- und Behördenunterlagen durch.
///
/// ⚠️ Bewusst KEIN WebView. Der wäre der naheliegende Weg, bringt aber genau
/// die Maschine mit, die wir loswerden wollen — JavaScript, Netzzugriff,
/// eigener Cache. Stattdessen läuft der Anhang durch [sanitizeMailHtml] und
/// [MailHtmlView], also durch dieselbe Kette wie der Nachrichtentext:
/// Skripte, Formulare, `meta refresh` und fremde Schemata sind schon vor dem
/// Rendern weg, externe Bilder sind blockiert, Links zeigen erst ihr Ziel.
/// Eine zweite Darstellungsart wäre eine zweite Stelle zum Reparieren.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/mail_html_sanitizer.dart';
import '../utils/app_farben.dart';
import '../utils/file_picker_helper.dart';
import 'mail_html_view.dart';

/// Die 32 Stellen, in denen sich Windows-1252 von Latin-1 unterscheidet.
///
/// ⚠️ Nicht Zierrat: dort liegen „ " ‚ ' – — … € ‰ — also genau die Zeichen,
/// die Word und Outlook in jeden zweiten deutschen Brief setzen. Ein Anhang
/// als reines Latin-1 zu lesen ergibt an diesen Stellen Steuerzeichen, die der
/// Sanitizer anschließend entfernt: das Wort verliert sein Anführungszeichen
/// lautlos. Deshalb ist Windows-1252 hier der Rückfall, nicht Latin-1.
const Map<int, int> _cp1252Oben = {
  0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E, 0x85: 0x2026,
  0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02C6, 0x89: 0x2030, 0x8A: 0x0160,
  0x8B: 0x2039, 0x8C: 0x0152, 0x8E: 0x017D, 0x91: 0x2018, 0x92: 0x2019,
  0x93: 0x201C, 0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014,
  0x98: 0x02DC, 0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A, 0x9C: 0x0153,
  0x9E: 0x017E, 0x9F: 0x0178,
};

String _cp1252Dekodieren(Uint8List bytes) {
  final buf = StringBuffer();
  for (final b in bytes) {
    buf.writeCharCode(b >= 0x80 && b <= 0x9F ? (_cp1252Oben[b] ?? b) : b);
  }
  return buf.toString();
}

String _utf16Dekodieren(Uint8List bytes, {required bool little}) {
  final buf = StringBuffer();
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    buf.writeCharCode(
        little ? bytes[i] | (bytes[i + 1] << 8) : (bytes[i] << 8) | bytes[i + 1]);
  }
  return buf.toString();
}

/// Macht aus den Anhangsbytes Text.
///
/// Reihenfolge, und jeder Schritt hat einen Grund:
/// 1. **BOM** — steht sie da, ist sie die verlässlichste Aussage, die es gibt.
///    Word und „Seite speichern unter" aus dem Internet Explorer liefern
///    UTF-16 mit BOM; ohne diesen Schritt käme Text mit einem Nullbyte hinter
///    jedem Buchstaben an, den der Sanitizer dann kommentarlos wegwirft.
/// 2. **Content-Type des Servers** — die Angabe des Absenders im MIME-Teil.
/// 3. **`<meta charset>` im Dokument** — oft die einzige Angabe, die es gibt.
/// 4. **UTF-8 streng**, und erst wenn das scheitert Windows-1252. Streng ist
///    hier richtig: `allowMalformed` würde ein Latin-1-Dokument klaglos in
///    lauter Ersatzzeichen verwandeln, statt den Rückfall auszulösen.
String htmlAnhangText(Uint8List bytes, [String contentType = '']) {
  if (bytes.length >= 2) {
    if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _utf16Dekodieren(Uint8List.sublistView(bytes, 2), little: true);
    }
    if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _utf16Dekodieren(Uint8List.sublistView(bytes, 2), little: false);
    }
  }
  var nutz = bytes;
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    nutz = Uint8List.sublistView(bytes, 3);
    return _utf8OderCp1252(nutz);
  }

  var deklariert = _charsetAus(contentType);
  if (deklariert == null) {
    // Nur der Kopf des Dokuments — die Angabe steht laut HTML-Norm in den
    // ersten 1024 Bytes, und Latin-1 kann hier nie scheitern.
    final kopf = _cp1252Dekodieren(
        Uint8List.sublistView(nutz, 0, nutz.length < 2048 ? nutz.length : 2048));
    deklariert = _charsetAus(kopf);
  }

  switch (deklariert) {
    case 'utf8':
    case 'utf-8':
    case 'utf':
      return _utf8OderCp1252(nutz);
    case 'iso-8859-1':
    case 'iso8859-1':
    case 'latin1':
    case 'latin-1':
    case 'windows-1252':
    case 'cp1252':
    case 'iso-8859-15':
      return _cp1252Dekodieren(nutz);
  }
  return _utf8OderCp1252(nutz);
}

String _utf8OderCp1252(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return _cp1252Dekodieren(bytes);
  }
}

/// Findet `charset=…` in einem Content-Type ODER in einem `<meta>`-Kopf.
String? _charsetAus(String quelle) {
  if (quelle.isEmpty) return null;
  final m = RegExp(r'''charset\s*=\s*["']?\s*([a-zA-Z0-9_\-]+)''',
          caseSensitive: false)
      .firstMatch(quelle);
  return m?.group(1)?.toLowerCase();
}

class HtmlAnhangDialog extends StatefulWidget {
  final Uint8List bytes;
  final String fileName;
  final String contentType;

  /// Auflösung von `cid:` — Teile DERSELBEN Nachricht, kein Netzzugriff.
  ///
  /// Ein HTML-Anhang darf auf die eingebetteten Bilder seiner Mail zeigen;
  /// ohne diesen Rückweg bliebe an ihrer Stelle nur der Alternativtext.
  final Future<Uint8List?> Function(String contentId)? loadInlineImage;

  const HtmlAnhangDialog({
    super.key,
    required this.bytes,
    required this.fileName,
    this.contentType = '',
    this.loadInlineImage,
  });

  /// Ist das ein HTML-Anhang?
  ///
  /// ⚠️ Endung UND Content-Type, weil beide einzeln unzuverlässig sind:
  /// Anhänge aus fremden Programmen kommen oft als `datei` ohne Endung, und
  /// umgekehrt schicken manche Absender jedes Anhängsel als
  /// `application/octet-stream`. Fällt eins von beidem eindeutig aus, reicht
  /// das — im schlimmsten Fall zeigen wir eine Datei im eigenen Betrachter
  /// an, die dort nicht hingehört, statt sie nach außen zu geben.
  static bool istHtml(String fileName, [String contentType = '']) {
    final ext = fileName.toLowerCase().split('.').last;
    if (ext == 'html' || ext == 'htm' || ext == 'xhtml' || ext == 'shtml') {
      return true;
    }
    final typ = contentType.toLowerCase().split(';').first.trim();
    return typ == 'text/html' || typ == 'application/xhtml+xml';
  }

  static Future<void> zeigen(
    BuildContext context, {
    required Uint8List bytes,
    required String fileName,
    String contentType = '',
    Future<Uint8List?> Function(String contentId)? loadInlineImage,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => HtmlAnhangDialog(
        bytes: bytes,
        fileName: fileName,
        contentType: contentType,
        loadInlineImage: loadInlineImage,
      ),
    );
  }

  @override
  State<HtmlAnhangDialog> createState() => _HtmlAnhangDialogState();
}

class _HtmlAnhangDialogState extends State<HtmlAnhangDialog> {
  late final String _quelle = htmlAnhangText(widget.bytes, widget.contentType);
  late final MailSanitizedHtml _sauber = sanitizeMailHtml(_quelle);

  /// Quelltext statt Darstellung.
  ///
  /// Der Sanitizer wirft absichtlich viel weg. Wer wissen will, was der
  /// Absender wirklich geschickt hat — etwa weil eine Seite verdächtig
  /// aussieht —, muss das nachlesen können, ohne die Datei dafür nach außen
  /// zu geben. Genau dafür ist diese Ansicht da, nicht als Notbehelf.
  bool _quelltext = false;

  Future<void> _speichern() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = await FilePickerHelper.saveBytes(
        bytes: widget.bytes,
        fileName: widget.fileName,
        dialogTitle: 'Anhang speichern',
      );
      if (saved == null) return; // abgebrochen
      messenger.showSnackBar(SnackBar(
        content: Text('Gespeichert: ${saved.split(Platform.pathSeparator).last}'),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Fehler beim Speichern: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final leer = _sauber.html.trim().isEmpty;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 800,
        height: 650,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: F.h(Colors.grey, 100),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Icon(Icons.html, color: F.h(Colors.orange, 700)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.fileName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(_quelltext ? Icons.article_outlined : Icons.code),
                    tooltip: _quelltext ? 'Darstellung' : 'Quelltext',
                    onPressed: () => setState(() => _quelltext = !_quelltext),
                  ),
                  IconButton(
                    icon: const Icon(Icons.download),
                    tooltip: 'Speichern',
                    onPressed: _speichern,
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            _hinweis(cs),
            Expanded(
              child: _quelltext
                  ? _quelltextAnsicht()
                  : leer
                      ? _leerAnsicht(cs)
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: SelectionArea(
                            child: MailHtmlView(
                              sanitized: _sauber,
                              loadInlineImage: widget.loadInlineImage,
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  /// Sagt beim Namen, was gerade NICHT passiert.
  ///
  /// Ein Anhang, der wie eine Webseite aussieht, weckt die Erwartung einer
  /// Webseite. Ohne diesen Satz wirkt eine Anmeldemaske, deren Knopf nichts
  /// tut, wie ein Fehler der App — und der nächste Griff wäre, sie doch im
  /// Browser zu öffnen.
  Widget _hinweis(ColorScheme cs) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: F.h(Colors.blue, 50),
        child: Row(
          children: [
            Icon(Icons.shield_outlined, size: 16, color: F.h(Colors.blue, 700)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'In der App dargestellt: keine Skripte, kein Nachladen von außen. '
                'Formulare in diesem Anhang senden nichts.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );

  Widget _quelltextAnsicht() => Container(
        color: F.h(Colors.grey, 50),
        child: SelectionArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Text(
              _quelle,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.45),
            ),
          ),
        ),
      );

  /// Nach dem Sanitisieren ist nichts übrig.
  ///
  /// Das ist keine kaputte Datei, sondern meistens eine Seite, die
  /// ausschließlich aus Skript bestand — und genau das gehört gesagt, statt
  /// eine leere Fläche zu zeigen.
  Widget _leerAnsicht(ColorScheme cs) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.report_gmailerrorred_outlined, size: 40, color: cs.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(
                _sauber.truncated
                    ? 'Dieser Anhang war zu groß oder zu tief verschachtelt, um ihn '
                        'gefahrlos darzustellen.'
                    : 'Dieser Anhang enthält keinen darstellbaren Inhalt — was darin '
                        'stand, war ausführbarer Code oder Nachladeanweisung.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.code, size: 18),
                label: const Text('Quelltext ansehen'),
                onPressed: () => setState(() => _quelltext = true),
              ),
            ],
          ),
        ),
      );
}
