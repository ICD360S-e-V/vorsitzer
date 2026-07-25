import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/mail_html_sanitizer.dart';

/// Diese Tests sind nach der Bypass-Liste aus dem Sicherheits-Review gebaut,
/// nicht nach dem Glücksfall. Jeder Fall nennt, was er abwehrt.
void main() {
  group('Aktive Inhalte verschwinden samt Text', () {
    test('script', () {
      final r = sanitizeMailHtml('<p>ok</p><script>alert(1)</script>');
      expect(r.html, contains('ok'));
      expect(r.html, isNot(contains('alert')));
      expect(r.html, isNot(contains('script')));
    });

    test('style-Element und style-Attribut', () {
      final r = sanitizeMailHtml(
          '<style>p{color:red}</style><p style="position:fixed;top:0">x</p>');
      expect(r.html, contains('x'));
      expect(r.html, isNot(contains('color')));
      expect(r.html, isNot(contains('position')));
      expect(r.html, isNot(contains('style')));
    });

    test('svg komplett — auch <svg><image xlink:href> (CVE-2024-23330)', () {
      final r = sanitizeMailHtml(
          '<svg><image xlink:href="https://t.evil/p.png"/><text>X</text></svg><p>ok</p>');
      expect(r.html, contains('ok'));
      expect(r.html, isNot(contains('evil')));
      expect(r.html, isNot(contains('X')));
      expect(r.blockedImages, isEmpty);
    });

    test('math komplett', () {
      final r = sanitizeMailHtml('<math><mi>M</mi></math><p>ok</p>');
      expect(r.html, contains('ok'));
      expect(r.html, isNot(contains('M</')));
    });

    test('iframe, object, form, input', () {
      final r = sanitizeMailHtml(
          '<iframe src="https://e.tld"></iframe><object data="x"></object>'
          '<form action="https://e.tld"><input name="pw"></form><p>ok</p>');
      expect(r.html, contains('ok'));
      for (final s in ['iframe', 'object', 'form', 'input', 'e.tld']) {
        expect(r.html, isNot(contains(s)), reason: s);
      }
    });

    test('meta und base mitten im Body (Foster-Parenting)', () {
      final r = sanitizeMailHtml(
          '<p>a</p><meta http-equiv="refresh" content="0;url=https://e.tld">'
          '<base href="https://e.tld/"><p>b</p>');
      expect(r.html, contains('a'));
      expect(r.html, contains('b'));
      expect(r.html, isNot(contains('e.tld')));
      expect(r.html, isNot(contains('refresh')));
    });
  });

  group('Attribute', () {
    test('jedes Attribut mit ":" fliegt (CVE-2025-68461)', () {
      final r = sanitizeMailHtml('<a xlink:href="javascript:alert(1)" href="https://ok.tld/x">t</a>');
      expect(r.html, isNot(contains('xlink')));
      expect(r.html, isNot(contains('javascript')));
    });

    test('on*-Handler fliegen (CVE-2024-42009)', () {
      final r = sanitizeMailHtml(
          '<p onanimationstart="alert(1)" onerror="x" ONCLICK="y">t</p>');
      expect(r.html, contains('t'));
      expect(r.html.toLowerCase(), isNot(contains('onanimationstart')));
      expect(r.html.toLowerCase(), isNot(contains('onclick')));
      expect(r.html, isNot(contains('alert')));
    });

    test('data-*, srcset, background, formaction, dir, title fliegen', () {
      final r = sanitizeMailHtml(
          '<p data-blocked-src="https://e.tld" dir="rtl" title="spoof">'
          '<img src="cid:a" srcset="https://e.tld/2x.png">'
          '<table background="https://e.tld/bg.png"><tr><td>c</td></tr></table></p>');
      for (final s in ['data-', 'srcset', 'background', 'dir=', 'title=', 'e.tld']) {
        expect(r.html, isNot(contains(s)), reason: s);
      }
      expect(r.html, contains('c'));
    });

    test('colspan/rowspan werden validiert', () {
      final r = sanitizeMailHtml(
          '<table><tr><td colspan="3" rowspan="99999">a</td>'
          '<td colspan="abc">b</td><td colspan="0">c</td></tr></table>');
      expect(r.html, contains('colspan="3"'));
      expect(r.html, isNot(contains('99999')));
      expect(r.html, isNot(contains('abc')));
      expect(r.html, isNot(contains('colspan="0"')));
    });
  });

  group('URLs werden zu opaken Tokens', () {
    test('href landet in der Seitentabelle, nicht im Baum', () {
      final r = sanitizeMailHtml('<a href="https://boese.example/login?u=icd">Bank</a>');
      expect(r.html, contains('Bank'));
      expect(r.html, contains('lnk:0'));
      expect(r.html, isNot(contains('boese.example')),
          reason: 'keine Absender-URL im serialisierten HTML');
      expect(r.linkTargets['lnk:0'], 'https://boese.example/login?u=icd');
    });

    test('externes Bild wird blockiert und getokenisiert', () {
      final r = sanitizeMailHtml('<img src="https://t.evil/o?m=1&r=icd@x.de" alt="a">');
      expect(r.html, contains('blk:0'));
      expect(r.html, isNot(contains('t.evil')));
      expect(r.blockedImageCount, 1);
      expect(r.blockedImages['blk:0'], contains('t.evil'));
    });

    test('javascript: wird abgelehnt, auch mit Tab/Newline geschmuggelt', () {
      for (final bad in [
        'javascript:alert(1)',
        'java\tscript:alert(1)',
        'java\nscript:alert(1)',
        'JaVaScRiPt:alert(1)',
        ' javascript:alert(1)',
        'vbscript:msgbox',
        'file:///etc/passwd',
        'blob:https://x',
      ]) {
        final r = sanitizeMailHtml('<a href="$bad">t</a>');
        expect(r.linkTargets, isEmpty, reason: bad);
        expect(r.html, isNot(contains('href')), reason: bad);
      }
    });

    test('data: im img wird abgelehnt, auch svg+xml', () {
      for (final bad in [
        'data:image/svg+xml;base64,PHN2Zz48L3N2Zz4=',
        'data:text/html,<script>alert(1)</script>',
        'data:image/png;base64,iVBORw0KGgo=',
      ]) {
        final r = sanitizeMailHtml('<img src="$bad">');
        expect(r.blockedImages, isEmpty, reason: bad);
        expect(r.html, isNot(contains('data:')), reason: bad);
      }
    });

    test('relative URLs werden abgelehnt (kein Basisdokument)', () {
      final r = sanitizeMailHtml('<a href="/konto">t</a><img src="bild.png">');
      expect(r.linkTargets, isEmpty);
      expect(r.blockedImages, isEmpty);
    });

    test('mailto und tel sind erlaubt', () {
      final r = sanitizeMailHtml('<a href="mailto:icd@icd360s.de">schreiben</a>');
      expect(r.linkTargets['lnk:0'], 'mailto:icd@icd360s.de');
    });
  });

  group('cid: — der einzige Pfad, der ohne Zustimmung lädt', () {
    test('gültige Content-ID wird getokenisiert', () {
      final r = sanitizeMailHtml('<img src="cid:logo123@firma.de" alt="Logo">');
      expect(r.html, contains('cid:0'));
      expect(r.cidImages['cid:0'], 'logo123@firma.de');
    });

    test('Pfad-Tricks werden abgelehnt, auch prozent-kodiert', () {
      for (final bad in [
        'cid:../../etc/passwd',
        'cid:a/b',
        r'cid:a\b',
        'cid:%2e%2e%2fetc',
        'cid:a:b',
      ]) {
        final r = sanitizeMailHtml('<img src="$bad">');
        expect(r.cidImages, isEmpty, reason: bad);
      }
    });
  });

  group('Unicode und versteckter Inhalt', () {
    test('Bidi-Overrides werden aus dem Text entfernt', () {
      const rlo = '\u202e';
      final r = sanitizeMailHtml('<p>Rechnung${rlo}gpj.exe</p>');
      expect(r.html.contains(rlo), isFalse);
      expect(r.html, contains('Rechnung'));
    });

    test('bdo und bdi sind Markup-Form desselben Angriffs', () {
      final r = sanitizeMailHtml('<p>a<bdo dir="rtl">bcd</bdo>e</p>');
      expect(r.html, isNot(contains('bdo')));
      expect(r.html, contains('a'));
      expect(r.html, contains('e'));
    });

    test('versteckte Blöcke werden verworfen UND gezählt', () {
      final r = sanitizeMailHtml(
          '<div style="display:none">Im Browser ansehen</div>'
          '<div style="opacity:0.03">salting text</div>'
          '<div style="mso-hide:all">outlook</div>'
          '<div aria-hidden="true">aria</div>'
          '<p>sichtbar</p>');
      expect(r.html, contains('sichtbar'));
      for (final s in ['Browser', 'salting', 'outlook', 'aria']) {
        expect(r.html, isNot(contains(s)), reason: s);
      }
      expect(r.hiddenCharCount, greaterThan(0));
    });
  });

  group('Struktur, Kappungen, Robustheit', () {
    test('Tabellen bleiben erhalten', () {
      final r = sanitizeMailHtml(
          '<table><thead><tr><th>Pos</th></tr></thead>'
          '<tbody><tr><td>100 EUR</td></tr></tbody></table>');
      for (final t in ['<table>', '<thead>', '<tr>', '<th>', '<td>']) {
        expect(r.html, contains(t), reason: t);
      }
      expect(r.html, contains('100 EUR'));
    });

    test('unbekannte Tags werden entpackt, Kinder bleiben', () {
      final r = sanitizeMailHtml('<article><section><p>Inhalt</p></section></article>');
      expect(r.html, contains('Inhalt'));
      expect(r.html, isNot(contains('article')));
      expect(r.html, isNot(contains('section')));
    });

    test('Text wird escaped — kein Wiedereinschleusen von Markup', () {
      final r = sanitizeMailHtml('<p>&lt;script&gt;alert(1)&lt;/script&gt;</p>');
      expect(r.html, contains('&lt;script&gt;'));
      expect(r.html, isNot(contains('<script>')));
    });

    test('Verschachtelungsbombe wird vor dem Parsen abgewiesen', () {
      final bomb = '${'<div>' * 3000}x${'</div>' * 3000}';
      final sw = Stopwatch()..start();
      final r = sanitizeMailHtml(bomb);
      sw.stop();
      expect(r.truncated, isTrue);
      expect(sw.elapsedMilliseconds, lessThan(3000));
    });

    test('Element-Obergrenze greift', () {
      final many = '<p>x</p>' * 500;
      final r = sanitizeMailHtml(many, maxElements: 50);
      expect(r.truncated, isTrue);
    });

    test('Zell-Obergrenze greift', () {
      final cells = '<table><tr>${'<td>c</td>' * 500}</tr></table>';
      final r = sanitizeMailHtml(cells, maxTableCells: 20);
      expect(r.truncated, isTrue);
    });

    test('normal verschachtelte Tabellen gehen durch', () {
      var inner = '<td>Inhalt</td>';
      for (var i = 0; i < 5; i++) {
        inner = '<table><tr><td><table><tr>$inner</tr></table></td></tr></table>';
      }
      final r = sanitizeMailHtml(inner);
      expect(r.html, contains('Inhalt'));
      expect(r.truncated, isFalse);
    });

    test('leer und kaputt', () {
      expect(sanitizeMailHtml('').isEmpty, isTrue);
      expect(sanitizeMailHtml('   ').isEmpty, isTrue);
      final r = sanitizeMailHtml('<p>offen<div><span>ohne Ende');
      expect(r.html, contains('offen'));
      expect(r.html, contains('ohne Ende'));
    });

    test('Ausgabe ist stabil bei erneutem Sanitisieren (kein mXSS-Drift)', () {
      const nasty = '<p><b>a<i>b</b>c</i></p><img src="cid:x"><a href="https://ok.tld">l</a>';
      final once = sanitizeMailHtml(nasty).html;
      final twice = sanitizeMailHtml(once).html;
      // Beim zweiten Durchgang werden die Tokens als URLs verworfen; die
      // Struktur selbst darf sich nicht mehr ändern.
      expect(sanitizeMailHtml(twice).html, twice);
    });
  });
}
