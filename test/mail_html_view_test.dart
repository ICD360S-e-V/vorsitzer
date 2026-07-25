import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/mail_html_sanitizer.dart';
import 'package:icd360sev_vorsitzer/widgets/mail_html_view.dart';

/// Wichtig für die Finder: flutter_widget_from_html_core rendert Fließtext als
/// RichText/TextSpan, nicht als Text-Widget. Assertions auf Text aus dem
/// Nachrichtenkörper brauchen deshalb `findRichText: true` — die eigenen Banner
/// dieses Widgets sind dagegen echte Text-Widgets.
///
/// Ein 1x1-PNG, damit Image.memory im Test echte Bytes bekommt.
final _png1x1 = Uint8List.fromList([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
  0x0a, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);

Future<void> _pump(
  WidgetTester tester,
  String rawHtml, {
  Future<Uint8List?> Function(String)? loadInline,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: MailHtmlView(
          sanitized: sanitizeMailHtml(rawHtml),
          loadInlineImage: loadInline,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('einfache Nachricht rendert ohne Ausnahme', (tester) async {
    await _pump(tester, '<p>Guten Tag <b>Herr Duinea</b></p><p>Zweiter Absatz</p>');
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Guten Tag', findRichText: true), findsWidgets);
  });

  testWidgets('Tabelle rendert', (tester) async {
    await _pump(tester,
        '<table><tr><th>Position</th><th>Betrag</th></tr>'
        '<tr><td>Mitgliedsbeitrag</td><td>60,00 EUR</td></tr></table>');
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Mitgliedsbeitrag', findRichText: true), findsWidgets);
    expect(find.textContaining('60,00 EUR', findRichText: true), findsWidgets);
  });

  group('externe Bilder', () {
    const html = '<p>oben</p><img src="https://t.evil/pixel.gif" alt="Grafik">'
        '<img src="https://t.evil/2.png">';

    testWidgets('Banner nennt die Anzahl und es wird nichts geladen', (tester) async {
      await _pump(tester, html);
      expect(tester.takeException(), isNull,
          reason: 'kein Netzzugriff im Test => keine Ausnahme');
      expect(find.textContaining('2 externe Bilder blockiert'), findsOneWidget);
      // Statt des Bildes steht der Platzhalter mit dem alt-Text.
      expect(find.textContaining('Grafik'), findsWidgets);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('"Bilder laden" entfernt das Banner', (tester) async {
      await _pump(tester, html);
      await tester.tap(find.text('Bilder laden'));
      await tester.pump();
      expect(find.textContaining('externe Bilder blockiert'), findsNothing);
    });

    testWidgets('ein einzelnes Bild wird im Singular gemeldet', (tester) async {
      await _pump(tester, '<img src="https://t.evil/one.png">');
      expect(find.textContaining('1 externes Bild blockiert'), findsOneWidget);
    });
  });

  group('eingebettete Bilder (cid:)', () {
    testWidgets('werden ohne Zutun aus der Nachricht geladen', (tester) async {
      var asked = '';
      await _pump(
        tester,
        '<p>Logo:</p><img src="cid:logo@firma.de" alt="Logo">',
        loadInline: (cid) async {
          asked = cid;
          return _png1x1;
        },
      );
      expect(tester.takeException(), isNull);
      expect(asked, 'logo@firma.de', reason: 'die Content-ID wird aufgelöst');
      expect(find.byType(Image), findsOneWidget);
      // Kein Banner: cid geht nicht ins Netz.
      expect(find.textContaining('blockiert'), findsNothing);
    });

    testWidgets('fehlender Teil fällt auf den alt-Text zurück', (tester) async {
      await _pump(
        tester,
        '<img src="cid:weg@firma.de" alt="Briefkopf">',
        loadInline: (_) async => null,
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Briefkopf'), findsWidgets);
      expect(find.byType(Image), findsNothing);
    });
  });

  testWidgets('versteckter Text wird gemeldet, nicht angezeigt', (tester) async {
    await _pump(
        tester,
        '<div style="display:none">Diese Mail im Browser ansehen und mehr</div>'
        '<p>sichtbar</p>');
    expect(find.textContaining('unsichtbar gemacht'), findsOneWidget);
    expect(find.textContaining('Browser ansehen', findRichText: true), findsNothing);
  });

  group('Links', () {
    testWidgets('zeigen das vollständige Ziel, bevor etwas geöffnet wird',
        (tester) async {
      await _pump(tester,
          '<a href="https://boese.example/login?u=icd">Sparkasse Online-Banking</a>');
      await tester.tap(find.textContaining('Sparkasse', findRichText: true));
      await tester.pumpAndSettle();
      expect(find.text('Link öffnen?'), findsOneWidget);
      // Die ganze URL, unzerlegt — kein hervorgehobener "Host".
      expect(find.textContaining('https://boese.example/login?u=icd'), findsOneWidget);
      expect(find.text('Abbrechen'), findsOneWidget);
    });

    testWidgets('Abbrechen öffnet nichts', (tester) async {
      await _pump(tester, '<a href="https://x.tld/y">Link</a>');
      await tester.tap(find.textContaining('Link', findRichText: true));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(find.text('Link öffnen?'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('javascript: erreicht die Ansicht gar nicht', (tester) async {
      await _pump(tester, '<a href="javascript:alert(1)">Klicken</a>');
      await tester.tap(find.textContaining('Klicken', findRichText: true));
      await tester.pumpAndSettle();
      expect(find.text('Link öffnen?'), findsNothing,
          reason: 'der Sanitizer hat das href schon entfernt');
    });
  });

  testWidgets('gekürzte Nachricht sagt das und verweist auf die Textansicht',
      (tester) async {
    final bomb = '${'<div>' * 3000}x${'</div>' * 3000}';
    await _pump(tester, bomb);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('gekürzt'), findsOneWidget);
  });

  testWidgets('leere Nachricht rendert nichts Kaputtes', (tester) async {
    await _pump(tester, '');
    expect(tester.takeException(), isNull);
  });
}
