/// Sanitizer für HTML aus E-Mails.
///
/// Nimmt Absender-HTML und gibt eine **kleine, bekannte Teilmenge** zurück, die
/// `flutter_widget_from_html_core` rendern darf. Absolut nichts wird geladen und
/// nichts ausgeführt.
///
/// Die Entwurfsentscheidungen kommen aus der CVE-Historie der Mail-Clients und
/// sind bewusst restriktiver als ein Allowlist-Ansatz:
///
/// * **Keine URL des Absenders landet im Baum.** Ziele werden durch opake
///   Tokens ersetzt (`lnk:3`, `blk:1`, `cid:0`); die geprüften Werte liegen in
///   Seitentabellen. Proton hatte mXSS über `<proton-svg>`, weil der Baum nach
///   dem Allowlist-Durchgang noch verändert wurde — hier gibt es nichts zu
///   verändern.
/// * **SVG und MathML werden komplett verworfen**, nicht innen gefiltert.
///   CVE-2026-25916 (`<feImage href>`), CVE-2025-68461 (`xlink:href`),
///   CVE-2024-23330 (Tuta: DOMPurify korrekt, `<svg><image>` lud trotzdem):
///   Fetcher aufzuzählen verliert.
/// * **Jedes Attribut mit `:` im Namen wird abgelehnt** — genau die
///   Namespace-Verwechslung aus CVE-2025-68461.
/// * **CSS gibt es nicht.** Kein `style`, kein `<style>`, keine At-Rules. Damit
///   entfällt StyleMail (ACM CCS 2025, PGP-Klartext-Exfiltration aus
///   Thunderbird mit reinem CSS), `url()` als Fetcher, `position:fixed` als
///   Overlay über die eigene UI, und die CSS-Matching-DoS.
/// * **Rawtext- und Foreign-Content-Kontexte fliegen raus**, weil nur dort
///   `parse(serialize(t)) != t` gilt. Der Renderer parst die Ausgabe erneut,
///   aber mit demselben exakt gepinnten html5lib-Port (`html: 0.15.6`) — das ist
///   nicht die html5lib-gegen-Blink-Differenz, aus der die mXSS-Bypässe kamen.
library;

import 'dart:convert' show htmlEscape;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Ergebnis der Sanitisierung.
class MailSanitizedHtml {
  /// Die bereinigte Teilmenge, bereit für den Renderer.
  final String html;

  /// `lnk:N` -> geprüfte absolute URL.
  final Map<String, String> linkTargets;

  /// `blk:N` -> externe Bild-URL, standardmäßig NICHT geladen.
  final Map<String, String> blockedImages;

  /// `cid:N` -> Content-ID eines Teils dieser Nachricht.
  final Map<String, String> cidImages;

  /// Zeichen, die der Absender unsichtbar gemacht hatte (Preheader, Salting).
  final int hiddenCharCount;

  /// Struktur-Obergrenze erreicht, Ausgabe ist gekürzt.
  final bool truncated;

  const MailSanitizedHtml({
    required this.html,
    this.linkTargets = const {},
    this.blockedImages = const {},
    this.cidImages = const {},
    this.hiddenCharCount = 0,
    this.truncated = false,
  });

  int get blockedImageCount => blockedImages.length;
  bool get isEmpty => html.trim().isEmpty;
}

/// Erlaubte Elemente — die Teilmenge, die echte E-Mail tatsächlich braucht.
const Set<String> _allowed = {
  'p', 'div', 'span', 'br', 'hr', 'center',
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  'b', 'strong', 'i', 'em', 'u', 's', 'strike', 'del', 'ins',
  'sub', 'sup', 'small', 'code', 'pre', 'font',
  'a', 'img',
  'ul', 'ol', 'li', 'dl', 'dt', 'dd', 'blockquote',
  'table', 'thead', 'tbody', 'tfoot', 'tr', 'td', 'th', 'caption',
};

/// Elemente, die samt Inhalt verschwinden.
///
/// Enthält alle Rawtext- und Foreign-Content-Kontexte: nur dort kann ein
/// Reparse ein anderes Ergebnis liefern als der sanitisierte Baum.
const Set<String> _dropSubtree = {
  'script', 'style', 'head', 'title', 'noscript', 'noembed', 'noframes',
  'template', 'xmp', 'plaintext', 'listing', 'svg', 'math',
  'iframe', 'object', 'embed', 'applet', 'frame', 'frameset',
  'form', 'input', 'button', 'select', 'textarea', 'option', 'optgroup',
  'label', 'fieldset', 'legend', 'datalist', 'output', 'progress', 'meter',
  'link', 'meta', 'base',
  'audio', 'video', 'source', 'track', 'canvas', 'map', 'area', 'param',
  // Markup-Form der Bidi-Overrides (Trojan Source, CVE-2021-42574).
  'bdo', 'bdi',
};

const Set<String> _voidTags = {'br', 'hr', 'img'};

/// Zeichen, die die Anzeige manipulieren oder unsichtbar sind.
/// U+200C/U+200D bleiben: arabischer und indischer Text braucht sie.
final RegExp _unsafeChars = RegExp(
    r'[\u202a-\u202e\u2066-\u2069\u200b\ufeff\u00ad'
    r'\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f-\u009f]');

/// Erlaubte Schemata in `href`. Keins davon holt etwas nach.
const Set<String> _allowedSchemes = {'http', 'https', 'mailto', 'tel'};

/// Bereinigt Absender-HTML.
MailSanitizedHtml sanitizeMailHtml(
  String source, {
  int maxInputChars = 512 * 1024,
  int maxElements = 5000,
  int maxDepth = 100,
  int maxTableCells = 4000,
}) {
  if (source.trim().isEmpty) return const MailSanitizedHtml(html: '');

  var truncated = false;
  var input = source;
  if (input.length > maxInputChars) {
    input = input.substring(0, maxInputChars);
    truncated = true;
  }

  // Vor dem Parser: html5lib baut den Baum rekursiv und ohne eigene Grenze auf.
  if (_looksHostile(input, maxTags: maxElements * 4, maxNestDepth: maxDepth)) {
    return MailSanitizedHtml(html: '', truncated: true);
  }

  dom.Document doc;
  try {
    doc = html_parser.parse(input);
  } catch (_) {
    return MailSanitizedHtml(html: '', truncated: true);
  }

  final w = _Walker(
    maxElements: maxElements,
    maxDepth: maxDepth,
    maxTableCells: maxTableCells,
  );
  try {
    w.walk(doc.body ?? doc.documentElement ?? doc, 0);
  } catch (_) {
    w.truncated = true;
  }

  return MailSanitizedHtml(
    html: w.out.toString().trim(),
    linkTargets: w.links,
    blockedImages: w.blocked,
    cidImages: w.cids,
    hiddenCharCount: w.hiddenChars,
    truncated: truncated || w.truncated,
  );
}

class _Walker {
  _Walker({
    required this.maxElements,
    required this.maxDepth,
    required this.maxTableCells,
  });

  final int maxElements;
  final int maxDepth;
  final int maxTableCells;

  final out = StringBuffer();
  final links = <String, String>{};
  final blocked = <String, String>{};
  final cids = <String, String>{};

  int elements = 0;
  int cells = 0;
  int hiddenChars = 0;
  bool truncated = false;

  void walk(dom.Node node, int depth) {
    if (truncated) return;
    if (depth > maxDepth) {
      truncated = true;
      return;
    }

    if (node is dom.Text) {
      final t = node.data.replaceAll(_unsafeChars, '');
      if (t.isNotEmpty) out.write(htmlEscape.convert(t));
      return;
    }
    if (node is! dom.Element) return; // Kommentare, Doctype, …

    final tag = (node.localName ?? '').toLowerCase();

    if (_dropSubtree.contains(tag)) return;
    if (_isHidden(node)) {
      hiddenChars += node.text.length;
      return;
    }

    if (++elements > maxElements) {
      truncated = true;
      return;
    }

    // Unbekannt und nicht verboten: Tag weg, Kinder behalten.
    if (!_allowed.contains(tag)) {
      for (final c in node.nodes) {
        walk(c, depth + 1);
      }
      return;
    }

    if (tag == 'td' || tag == 'th') {
      if (++cells > maxTableCells) {
        truncated = true;
        return;
      }
    }

    final attrs = _safeAttributes(tag, node);

    if (_voidTags.contains(tag)) {
      // Ein <img> ohne verwendbare Quelle ist nur Rauschen.
      if (tag == 'img' && !attrs.containsKey('src')) {
        final alt = attrs['alt'];
        if (alt != null && alt.isNotEmpty) out.write(htmlEscape.convert(alt));
        return;
      }
      out.write('<$tag${_render(attrs)} />');
      return;
    }

    out.write('<$tag${_render(attrs)}>');
    for (final c in node.nodes) {
      walk(c, depth + 1);
    }
    out.write('</$tag>');
  }

  String _render(Map<String, String> attrs) {
    if (attrs.isEmpty) return '';
    final b = StringBuffer();
    attrs.forEach((k, v) => b.write(' $k="${htmlEscape.convert(v)}"'));
    return b.toString();
  }

  /// Attribut-Allowlist. Nichts kommt unverändert aus dem Absender-HTML durch,
  /// außer kurzen, geprüften Werten.
  Map<String, String> _safeAttributes(String tag, dom.Element e) {
    final ok = <String, String>{};

    e.attributes.forEach((rawKey, rawVal) {
      final key = rawKey.toString().toLowerCase();

      // Namespace-Verwechslung (CVE-2025-68461) und Event-Handler: nie.
      if (key.contains(':')) return;
      if (key.startsWith('on')) return;
      // Keine data-*: der Baum darf keine Absender-Nutzlast tragen.
      if (key.startsWith('data-')) return;
      // Kein CSS, keine Textrichtung, keine Fetch-Attribute.
      if (key == 'style' || key == 'dir' || key == 'srcset' ||
          key == 'background' || key == 'lowsrc' || key == 'dynsrc' ||
          key == 'formaction' || key == 'title') {
        return;
      }

      final val = rawVal.replaceAll(_unsafeChars, '').trim();

      switch (key) {
        case 'href':
          if (tag != 'a') return;
          final url = _normalizeUrl(val);
          if (url == null) return;
          final token = 'lnk:${links.length}';
          links[token] = url;
          ok['href'] = token;
          return;
        case 'src':
          if (tag != 'img') return;
          final cid = _cidValue(val);
          if (cid != null) {
            final token = 'cid:${cids.length}';
            cids[token] = cid;
            ok['src'] = token;
            return;
          }
          final url = _normalizeUrl(val, imagesOnly: true);
          if (url == null) return; // data:, javascript:, alles andere
          final token = 'blk:${blocked.length}';
          blocked[token] = url;
          ok['src'] = token;
          return;
        case 'alt':
          if (tag != 'img') return;
          if (val.isNotEmpty) ok['alt'] = _clip(val, 250);
          return;
        case 'colspan':
        case 'rowspan':
          if (tag != 'td' && tag != 'th') return;
          final n = int.tryParse(val);
          if (n != null && n >= 1 && n <= 64) ok[key] = '$n';
          return;
        case 'align':
        case 'valign':
          const allowed = {'left', 'right', 'center', 'top', 'bottom', 'middle'};
          final v = val.toLowerCase();
          if (allowed.contains(v)) ok[key] = v;
          return;
        default:
          return; // alles andere fällt weg
      }
    });

    return ok;
  }

  static String _clip(String s, int n) => s.length <= n ? s : s.substring(0, n);

  /// `cid:` Wert nach RFC 2392, prozent-dekodiert geprüft. Der Wert ist nur ein
  /// Schlüssel in die Teile DIESER Nachricht — er darf nie ein Pfad werden.
  static String? _cidValue(String raw) {
    final m = RegExp(r'^\s*cid\s*:\s*(.+)$', caseSensitive: false).firstMatch(raw);
    if (m == null) return null;
    var v = m.group(1)!.trim();
    try {
      v = Uri.decodeComponent(v);
    } catch (_) {
      return null;
    }
    if (v.isEmpty || v.length > 255) return null;
    if (v.contains('/') || v.contains('\\') || v.contains('..') || v.contains(':')) {
      return null;
    }
    if (RegExp(r'[\x00-\x1f\x7f]').hasMatch(v)) return null;
    return v;
  }

  /// Normalisiert eine URL oder verwirft sie.
  ///
  /// Bewusst NICHT über `Uri`: Dart folgt RFC 3986, Browser folgen WHATWG URL,
  /// und `https://sparkasse.de\@evil.tld` wird von beiden unterschiedlich
  /// zerlegt — eine Bestätigung, die den einen Host zeigt und den anderen
  /// öffnet, ist schlimmer als keine. Hier wird nur ein streng gebautes
  /// `scheme://rest` akzeptiert und roh weitergegeben; die Anzeige-Entscheidung
  /// trifft der Aufrufer auf demselben String.
  static String? _normalizeUrl(String raw, {bool imagesOnly = false}) {
    // Whitespace und Steuerzeichen im Schema sind der klassische Schmuggelweg
    // für `java\tscript:`.
    final s = raw.replaceAll(
        RegExp(r'[\s\u0000-\u001f\u007f-\u009f]'), '');
    if (s.isEmpty || s.length > 2000) return null;

    final m = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.\-]*):').firstMatch(s);
    if (m == null) return null; // relative URLs: kein Basis-Dokument, also nein
    final scheme = m.group(1)!.toLowerCase();

    if (imagesOnly) {
      // data: wird verworfen — data:image/svg+xml ist ausführbarer Inhalt, und
      // eine Magic-Byte-Prüfung gehört nicht in den Sanitizer.
      if (scheme != 'http' && scheme != 'https') return null;
    } else if (!_allowedSchemes.contains(scheme)) {
      return null;
    }

    if ((scheme == 'http' || scheme == 'https') &&
        !RegExp(r'^https?://[^/\\?#]+').hasMatch(s)) {
      return null; // kein Host
    }
    return s;
  }

  /// Vom Absender unsichtbar gemachte Blöcke. Das `style`-Attribut wird sonst
  /// verworfen, hier wird es nur GELESEN, um solche Teilbäume zu erkennen.
  static bool _isHidden(dom.Element e) {
    if (e.attributes.containsKey('hidden')) return true;
    if (e.attributes['aria-hidden']?.toString().toLowerCase() == 'true') return true;
    final style =
        (e.attributes['style']?.toString() ?? '').toLowerCase().replaceAll(' ', '');
    if (style.isEmpty) return false;
    if (style.contains('display:none')) return true;
    if (style.contains('visibility:hidden')) return true;
    if (style.contains('mso-hide:all')) return true;
    // Nicht nur opacity:0 — 0.03 ist genauso unsichtbar.
    final op = RegExp(r'opacity:(0?\.\d+|0)\b').firstMatch(style);
    if (op != null && (double.tryParse(op.group(1)!) ?? 1) < 0.5) return true;
    if (RegExp(r'(font-size|max-height|line-height):0(\.0+)?(px|pt|em|rem|%)?\b')
        .hasMatch(style)) {
      return true;
    }
    if (RegExp(r'text-indent:-\d{4,}').hasMatch(style)) return true;
    return false;
  }
}

const Set<String> _voidForScan = {
  'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link',
  'meta', 'param', 'source', 'track', 'wbr',
};

/// O(n)-Vorabscan gegen Verschachtelungsbomben, VOR dem Parser.
bool _looksHostile(String s, {required int maxTags, required int maxNestDepth}) {
  var tags = 0, depth = 0, i = 0;
  while (true) {
    i = s.indexOf('<', i);
    if (i < 0) return false;
    if (++tags > maxTags) return true;
    var j = i + 1;
    final closing = j < s.length && s.codeUnitAt(j) == 0x2F;
    if (closing) j++;
    final start = j;
    while (j < s.length) {
      final c = s.codeUnitAt(j);
      final alnum = (c >= 0x61 && c <= 0x7A) ||
          (c >= 0x41 && c <= 0x5A) ||
          (c >= 0x30 && c <= 0x39);
      if (!alnum) break;
      j++;
    }
    if (j == start) {
      i += 1;
      continue;
    }
    final name = s.substring(start, j).toLowerCase();
    if (closing) {
      if (depth > 0) depth--;
    } else if (!_voidForScan.contains(name)) {
      final gt = s.indexOf('>', j);
      if (!(gt > 0 && s.codeUnitAt(gt - 1) == 0x2F)) {
        if (++depth > maxNestDepth) return true;
      }
    }
    i = j;
  }
}
