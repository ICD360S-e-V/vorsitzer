import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/mail_html_text.dart';

void main() {
  group('mailHtmlToText — Inhalte, die verschwinden müssen', () {
    test('style-Inhalt landet nicht im Text', () {
      const html = '<html><head><style>.a{color:red}p{font-size:12px}</style>'
          '</head><body><p>Guten Tag</p></body></html>';
      final out = mailHtmlToText(html);
      expect(out, contains('Guten Tag'));
      expect(out, isNot(contains('color')));
      expect(out, isNot(contains('font-size')));
    });

    test('script-Inhalt landet nicht im Text', () {
      const html = '<body><script>var x=1;alert("hi")</script><p>Text</p></body>';
      final out = mailHtmlToText(html);
      expect(out, contains('Text'));
      expect(out, isNot(contains('alert')));
      expect(out, isNot(contains('var x')));
    });

    test('svg und math werden samt Inhalt verworfen', () {
      const html = '<body><svg><text>SVGTEXT</text></svg>'
          '<math><mi>MATHTEXT</mi></math><p>Echt</p></body>';
      final out = mailHtmlToText(html);
      expect(out, contains('Echt'));
      expect(out, isNot(contains('SVGTEXT')));
      expect(out, isNot(contains('MATHTEXT')));
    });

    test('versteckter Preheader erscheint nicht', () {
      const html = '<body>'
          '<div style="display:none;max-height:0">Diese Mail im Browser ansehen</div>'
          '<div style="mso-hide:all">Outlook-Vorschautext</div>'
          '<span hidden>versteckt</span>'
          '<div style="font-size:0px">Spam-Salting</div>'
          '<p>Sichtbarer Inhalt</p></body>';
      final out = mailHtmlToText(html);
      expect(out, contains('Sichtbarer Inhalt'));
      expect(out, isNot(contains('Browser ansehen')));
      expect(out, isNot(contains('Outlook-Vorschautext')));
      expect(out, isNot(contains('versteckt')));
      expect(out, isNot(contains('Spam-Salting')));
    });

    test('display: none mit Leerzeichen wird auch erkannt', () {
      const html = '<body><div style="display: none">weg</div><p>da</p></body>';
      final out = mailHtmlToText(html);
      expect(out, contains('da'));
      expect(out, isNot(contains('weg')));
    });
  });

  group('mailHtmlToText — Formatierung', () {
    test('Entities werden aufgelöst', () {
      const html = '<p>M&uuml;ller &amp; S&ouml;hne &lt;GmbH&gt; &nbsp;100&nbsp;&euro;</p>';
      final out = mailHtmlToText(html);
      expect(out, contains('Müller & Söhne <GmbH>'));
      expect(out, contains('€'));
    });

    test('br und p erzeugen Zeilenumbrüche', () {
      const html = '<p>Zeile eins<br>Zeile zwei</p><p>Absatz zwei</p>';
      final out = mailHtmlToText(html);
      expect(out.split('\n').where((l) => l.trim().isNotEmpty).length, greaterThanOrEqualTo(3));
      expect(out, contains('Zeile eins'));
      expect(out, contains('Zeile zwei'));
      expect(out, contains('Absatz zwei'));
    });

    test('Listenpunkte bekommen einen Marker', () {
      const html = '<ul><li>Erstens</li><li>Zweitens</li></ul>';
      final out = mailHtmlToText(html);
      expect(out, contains('• Erstens'));
      expect(out, contains('• Zweitens'));
    });

    test('Tabellenzellen bleiben lesbar getrennt', () {
      const html = '<table><tr><td>Betrag</td><td>100 EUR</td></tr>'
          '<tr><td>Frist</td><td>14 Tage</td></tr></table>';
      final out = mailHtmlToText(html);
      expect(out, contains('Betrag'));
      expect(out, contains('100 EUR'));
      // Zeilen der Tabelle dürfen nicht zu einer einzigen verschmelzen.
      expect(out, contains('\n'));
      final betragLine = out.split('\n').firstWhere((l) => l.contains('Betrag'));
      expect(betragLine, isNot(contains('Frist')));
    });

    test('img wird durch seinen alt-Text ersetzt', () {
      const html = '<p>Logo: <img src="https://x.tld/l.png" alt="Firmenlogo"></p>';
      final out = mailHtmlToText(html);
      expect(out, contains('[Bild: Firmenlogo]'));
      expect(out, isNot(contains('x.tld')));
    });

    test('img ohne alt hinterlässt keinen Müll', () {
      const html = '<p>Vorher<img src="https://x.tld/pixel.gif" width="1" height="1">Nachher</p>';
      final out = mailHtmlToText(html);
      expect(out, contains('Vorher'));
      expect(out, contains('Nachher'));
      expect(out, isNot(contains('pixel.gif')));
    });

    test('pre bewahrt Zeilenstruktur', () {
      const html = '<pre>a\n  b\n    c</pre>';
      final out = mailHtmlToText(html);
      expect(out, contains('a\n'));
      expect(out, contains('  b'));
    });
  });

  group('mailHtmlToText — Linkziele offenlegen (Phishing)', () {
    test('irreführender Ankertext bekommt das echte Ziel angehängt', () {
      const html = '<a href="https://boese.example/login">Sparkasse Online-Banking</a>';
      final out = mailHtmlToText(html);
      expect(out, contains('Sparkasse Online-Banking'));
      expect(out, contains('<https://boese.example/login>'));
    });

    test('Ankertext, der schon die URL ist, wird nicht verdoppelt', () {
      const html = '<a href="https://icd360s.de">https://icd360s.de</a>';
      final out = mailHtmlToText(html);
      expect(out.split('icd360s.de').length - 1, 1);
    });

    test('mailto und javascript werden nicht als Ziel angehängt', () {
      const html = '<a href="mailto:x@y.de">Schreiben</a>'
          '<a href="javascript:alert(1)">Klicken</a>';
      final out = mailHtmlToText(html);
      expect(out, isNot(contains('javascript')));
      expect(out, isNot(contains('mailto:')));
    });
  });

  group('mailHtmlToText — Robustheit gegen feindliche Eingaben', () {
    test('sehr tiefe Verschachtelung stürzt nicht ab', () {
      final html = '${'<div>' * 5000}tief${'</div>' * 5000}';
      expect(() => mailHtmlToText(html), returnsNormally);
    });

    test('übergroße Eingabe wird gekappt statt zu hängen', () {
      final html = '<p>${'A' * (600 * 1024)}</p>';
      final out = mailHtmlToText(html, maxInputChars: 64 * 1024);
      expect(out.length, lessThan(70 * 1024));
    });

    test('Ausgabe wird auf maxOutputChars begrenzt', () {
      final html = '<p>${'B' * 5000}</p>';
      final out = mailHtmlToText(html, maxOutputChars: 1000);
      expect(out.length, lessThanOrEqualTo(1000 + 20));
      expect(out, contains('gekürzt'));
    });

    test('kaputtes HTML ergibt trotzdem Text', () {
      const html = '<p>offen <div><span>ohne Ende';
      final out = mailHtmlToText(html);
      expect(out, contains('offen'));
      expect(out, contains('ohne Ende'));
    });

    test('leerer und reiner Whitespace-Input ergibt leeren String', () {
      expect(mailHtmlToText(''), '');
      expect(mailHtmlToText('   \n  '), '');
      expect(mailHtmlToText('<p>   </p>'), '');
    });

    test('Kommentare erscheinen nicht im Text', () {
      const html = '<body><!-- interner Hinweis --><p>Sichtbar</p></body>';
      final out = mailHtmlToText(html);
      expect(out, contains('Sichtbar'));
      expect(out, isNot(contains('interner Hinweis')));
    });

    test('MSO-Conditional-Comments werden nicht ausgegeben', () {
      const html = '<body><!--[if mso]><table><tr><td>NUR OUTLOOK</td></tr></table>'
          '<![endif]--><p>Alle</p></body>';
      final out = mailHtmlToText(html);
      expect(out, contains('Alle'));
      expect(out, isNot(contains('NUR OUTLOOK')));
    });
  });
}
