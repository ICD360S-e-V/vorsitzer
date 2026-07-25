/// Wandelt den HTML-Teil einer E-Mail in lesbaren Text um.
///
/// Ersetzt das frühere regex-basierte Strippen, das drei Fehler hatte:
/// der Inhalt von `<style>` und `<script>` landete als Müll im Text, versteckte
/// Preheader-Blöcke ("Diese Mail im Browser ansehen") standen ganz oben, und
/// nur eine Handvoll HTML-Entities wurde überhaupt aufgelöst.
///
/// Sicherheitshinweise:
/// - Das `html`-Paket ist ein html5lib-Port mit rekursivem Tree-Builder und
///   bringt selbst KEINE Tiefen- oder Größenbegrenzung mit. Deshalb wird vor dem
///   Parsen auf [maxInputChars] gekappt und beim Absteigen auf [_maxDepth]
///   geachtet — tief verschachteltes HTML ist eine bekannte DoS- und
///   mXSS-Klasse, nicht bloß ein Performance-Thema.
/// - Ganze Teilbäume werden MIT ihrem Textinhalt verworfen, nicht nur die Tags.
/// - Hier wird nichts nachgeladen und nichts ausgeführt; das Ergebnis ist Text.
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Elemente, die samt Inhalt verschwinden. `style` und `script` stehen hier,
/// weil ihr Textknoten sonst im Ergebnis auftaucht.
const Set<String> _dropSubtree = {
  'script', 'style', 'head', 'title', 'noscript', 'template',
  // Aktive bzw. einbettende Inhalte — im Textpfad grundsätzlich irrelevant.
  'iframe', 'object', 'embed', 'applet', 'frame', 'frameset',
  'form', 'button', 'select', 'textarea', 'input', 'option', 'optgroup',
  'link', 'meta', 'base', 'map', 'area',
  'audio', 'video', 'source', 'track', 'canvas',
  // SVG und MathML komplett: eigene Namespaces mit eigener Angriffsfläche.
  'svg', 'math',
};

/// Elemente, die eine neue Zeile erzwingen.
const Set<String> _blockLevel = {
  'p', 'div', 'section', 'article', 'header', 'footer', 'aside', 'nav',
  'main', 'figure', 'figcaption', 'address', 'center', 'fieldset',
  'details', 'summary', 'blockquote', 'pre',
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  'ul', 'ol', 'dl', 'dt', 'dd', 'li',
  'table', 'thead', 'tbody', 'tfoot', 'tr', 'caption',
};

const int _maxDepth = 200;

/// Markiert `<pre>`-Bereiche, damit die Schlussnormalisierung ihre Einrückung
/// nicht wieder zusammenfaltet. NUL kommt in E-Mail-Text nicht vor und wird
/// vorsichtshalber aus allen Textknoten entfernt, damit ein Absender die Marke
/// nicht selbst einschmuggeln kann.
const String _preMark = '\u0000';

/// HTML-Teil einer Nachricht als Text.
String mailHtmlToText(
  String html, {
  int maxInputChars = 512 * 1024,
  int maxOutputChars = 200 * 1024,
}) {
  if (html.isEmpty) return '';

  // Kappen VOR dem Parsen: der Parser ist rekursiv.
  final source = html.length > maxInputChars ? html.substring(0, maxInputChars) : html;

  dom.Document doc;
  try {
    doc = html_parser.parse(source);
  } catch (_) {
    // Lieber ein grober Fallback als eine leere Nachricht.
    return _normalize(_stripTagsFallback(source), maxOutputChars);
  }

  final out = StringBuffer();
  try {
    _walk(doc.body ?? doc.documentElement ?? doc, out, 0, false);
  } catch (_) {
    return _normalize(_stripTagsFallback(source), maxOutputChars);
  }
  return _normalize(out.toString(), maxOutputChars);
}

void _walk(dom.Node node, StringBuffer out, int depth, bool inPre) {
  if (depth > _maxDepth) return;

  if (node is dom.Text) {
    // Die Marke aus dem Absendertext entfernen, bevor sie etwas schützen könnte.
    final raw = node.data.replaceAll(_preMark, '');
    out.write(inPre ? raw : raw.replaceAll(RegExp(r'\s+'), ' '));
    return;
  }
  if (node is! dom.Element) return; // Kommentare, Doctype, …

  final tag = (node.localName ?? '').toLowerCase();
  if (_dropSubtree.contains(tag)) return;
  if (_isHidden(node)) return;

  switch (tag) {
    case 'br':
      out.write('\n');
      return;
    case 'hr':
      out.write('\n———\n');
      return;
    case 'img':
      final alt = (node.attributes['alt'] ?? '').trim();
      if (alt.isNotEmpty) out.write('[Bild: $alt]');
      return;
  }

  final pre = inPre || tag == 'pre';
  final opensPre = pre && !inPre;
  final isBlock = _blockLevel.contains(tag);
  if (isBlock) out.write('\n');
  if (tag == 'li') out.write('• ');
  if (opensPre) out.write(_preMark);

  for (final child in node.nodes) {
    _walk(child, out, depth + 1, pre);
  }

  if (opensPre) out.write(_preMark);

  // Linkziel offenlegen: im Textpfad ist der Anker sonst nicht prüfbar, und
  // "hier klicken" ohne Ziel ist genau das, worauf Phishing baut.
  if (tag == 'a') {
    final href = (node.attributes['href'] ?? '').trim();
    final label = node.text.trim();
    if (_isHttpUrl(href) &&
        label.isNotEmpty &&
        !_looksLikeUrl(label) &&
        !href.contains(label)) {
      out.write(' <$href>');
    }
  }

  if (tag == 'td' || tag == 'th') out.write('  ');
  if (isBlock) out.write('\n');
}

/// Vom Absender absichtlich unsichtbar gemachte Blöcke — Preheader, Spam-Salting,
/// `mso-hide` für Outlook. Ihr Text gehört nicht in die Anzeige.
bool _isHidden(dom.Element e) {
  if (e.attributes.containsKey('hidden')) return true;
  final style = (e.attributes['style'] ?? '').toLowerCase().replaceAll(' ', '');
  if (style.isEmpty) return false;
  if (style.contains('display:none')) return true;
  if (style.contains('visibility:hidden')) return true;
  if (style.contains('mso-hide:all')) return true;
  if (RegExp(r'font-size:0(\.0+)?(px|pt|em|rem|%)?\b').hasMatch(style)) return true;
  if (RegExp(r'max-height:0(\.0+)?(px|pt|em|rem|%)?\b').hasMatch(style)) return true;
  if (RegExp(r'opacity:0(\.0+)?\b').hasMatch(style)) return true;
  return false;
}

bool _isHttpUrl(String s) {
  final l = s.toLowerCase();
  return l.startsWith('http://') || l.startsWith('https://');
}

bool _looksLikeUrl(String s) {
  final l = s.toLowerCase();
  return l.startsWith('http://') || l.startsWith('https://') || l.startsWith('www.');
}

/// Notausgang, wenn das Parsen scheitert: Tags entfernen, Entities auflösen.
String _stripTagsFallback(String html) => html
    .replaceAll(
        RegExp(r'<(script|style|head|svg|math)\b[^>]*>.*?</\1\s*>',
            dotAll: true, caseSensitive: false),
        ' ')
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'</(p|div|tr|li|h[1-6])\s*>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]+>'), ' ')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'");

String _normalize(String s, int maxOutputChars) {
  var t = s
      .replaceAll('\u00a0', ' ') // NBSP
      .replaceAll('\u200b', '') // zero-width space
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');

  // Whitespace nur außerhalb der <pre>-Marken zusammenfassen — sonst wäre die
  // Einrückung zitierter Logs oder Texttabellen wieder zerstört.
  final parts = t.split(_preMark);
  for (var i = 0; i < parts.length; i++) {
    if (i.isOdd) continue; // innerhalb <pre>
    parts[i] = parts[i]
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'[ \t]+$'), ''))
        .join('\n')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ');
  }
  t = parts.join();

  t = t.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  if (t.length > maxOutputChars) {
    t = '${t.substring(0, maxOutputChars)}\n\n[… gekürzt]';
  }
  return t;
}
