import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/mail_print.dart';

/// Das PDF wird hier wirklich gerendert, nicht bloß angelegt: `doc.save()` ist
/// der Schritt, in dem ein falsches Widget, eine fehlende Schrift oder ein
/// Zeichen ohne Glyphe auffliegt.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('baut ein PDF aus einer gewöhnlichen Nachricht', () async {
    final bytes = await buildMailPdf(
      subject: 'Ihr Antrag vom 12.03.',
      from: 'Jobcenter <post@jobcenter.example>',
      to: 'icd@icd360s.de',
      cc: 'kopie@icd360s.de',
      date: 'Mi, 26. Jul 2026 09:14',
      folder: 'Posteingang',
      body: 'Guten Tag,\n\nihr Antrag ist eingegangen.\n\nMit freundlichen '
          'Grüßen\nSachbearbeitung',
      attachments: const ['Bescheid.pdf (24.3 KB)', 'Anlage.jpg (1.2 MB)'],
    );

    expect(bytes.length, greaterThan(1000));
    // %PDF-Signatur
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('leerer Betreff und leerer Text kippen nicht', () async {
    final bytes = await buildMailPdf(
      subject: '   ',
      from: 'a@example.org',
      to: 'b@example.org',
      body: '   \n  \n',
    );
    expect(bytes.length, greaterThan(1000));
  });

  /// Der eigentliche Grund für DejaVu statt der PDF-Standardschriften: die
  /// kennen nur Latin-1 und werfen bei kyrillischen oder rumänischen Zeichen.
  test('rumänisch, ukrainisch, russisch und türkisch drucken durch', () async {
    final bytes = await buildMailPdf(
      subject: 'Cerere înregistrată — Заява прийнята',
      from: 'Consulat <birou@example.ro>',
      to: 'icd@icd360s.de',
      body: 'Bună ziua,\n\nсправа зареєстрована. Ваша заява прийнята.\n'
          'Приложение отсутствует.\nİyi günler, teşekkür ederiz.\n'
          'Grüße aus Böblingen — ăâîșț ÄÖÜß «guillemets» €',
      attachments: const ['Împuternicire.pdf (8.0 KB)'],
    );
    expect(bytes.length, greaterThan(1000));
  });

  test('sehr langer Text wird gekappt statt endlos umgebrochen', () async {
    final bytes = await buildMailPdf(
      subject: 'Log',
      from: 'a@example.org',
      to: 'b@example.org',
      body: 'Zeile mit etwas Inhalt.\n' * 20000,
    );
    expect(bytes.length, greaterThan(1000));
  });

  /// Wenige Zeichen, aber ohne Grenze tausende Seiten — genau der Fall, den eine
  /// reine Zeichengrenze durchlässt.
  test('zehntausende Leerzeilen erzeugen keine Seitenflut', () async {
    final bytes = await buildMailPdf(
      subject: 'Newsletter',
      from: 'a@example.org',
      to: 'b@example.org',
      body: 'Oben.${'\n' * 80000}Unten.',
    );
    expect(bytes.length, greaterThan(1000));
  });

  /// Ein einzelner Absatz ohne ein einziges Zeilenende: der Umbruch muss ihn
  /// über Seiten hinweg tragen (`TextOverflow.span`), sonst wirft `MultiPage`.
  test('ein Absatz ohne Zeilenumbruch läuft über mehrere Seiten', () async {
    final bytes = await buildMailPdf(
      subject: 'Bescheid',
      from: 'a@example.org',
      to: 'b@example.org',
      body: 'Sachverhalt und Begründung folgen ohne Absatz. ' * 2000,
    );
    expect(bytes.length, greaterThan(1000));
  });

  group('Druckauswahl', () {
    const channel = MethodChannel('net.nfet.printing');
    late TestDefaultBinaryMessenger messenger;

    setUp(() {
      messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    });

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    /// Antwortet wie das Plugin. `null` für `printingInfo` heißt: es gibt keine
    /// Antwort — genau das passiert ohne registriertes Plugin, und es darf die
    /// Auswahl nicht verhindern.
    void mockPlugin({
      Map<String, Object?>? info,
      List<Map<String, Object?>>? printers,
    }) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'printingInfo':
            return info;
          case 'listPrinters':
            return printers;
          default:
            return null;
        }
      });
    }

    Future<void> openSheet(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showMailPrintOptions(
                  context,
                  pdf: Uint8List.fromList(const [0x25, 0x50, 0x44, 0x46]),
                  docName: 'Test',
                ),
                child: const Text('los'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('los'));
      await tester.pumpAndSettle();
    }

    testWidgets('gefundene Drucker stehen zur Wahl, Standard zuerst',
        (tester) async {
      mockPlugin(
        info: const {
          'canPrint': true,
          'canListPrinters': true,
          'canShare': true,
          'directPrint': true,
          'dynamicLayout': true,
        },
        printers: const [
          {'url': 'ipp://z', 'name': 'Zebra Etiketten', 'available': true},
          {
            'url': 'ipp://b',
            'name': 'Brother HL-2340',
            'location': 'Büro',
            'default': true,
            'available': true,
          },
          {'url': 'ipp://k', 'name': 'Kaputt', 'available': false},
        ],
      );

      await openSheet(tester);

      expect(find.text('Brother HL-2340'), findsOneWidget);
      expect(find.text('Zebra Etiketten'), findsOneWidget);
      // Nicht verfügbare Drucker gehören nicht in die Liste — man würde darauf
      // drucken und nichts käme heraus.
      expect(find.text('Kaputt'), findsNothing);
      expect(find.textContaining('Standarddrucker'), findsOneWidget);

      final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
      expect((tiles.first.title as Text).data, 'Brother HL-2340');
      expect(find.text('Als PDF speichern'), findsOneWidget);
    });

    /// Der Fall, den es auf dem Tablet ohne Druckdienst und im Flatpak ohne
    /// CUPS-Socket wirklich gibt: die Auswahl darf nicht leer aufgehen.
    testWidgets('ohne auffindbaren Drucker bleibt der PDF-Weg', (tester) async {
      mockPlugin(
        info: const {
          'canPrint': true,
          'canListPrinters': true,
          'canShare': true,
        },
        printers: const [],
      );

      await openSheet(tester);

      expect(find.textContaining('Kein Drucker gefunden'), findsOneWidget);
      expect(find.text('Drucker wählen (Systemdialog)'), findsOneWidget);
      expect(find.text('Als PDF speichern'), findsOneWidget);
    });

    /// Antwortet die Plattform gar nicht, wird trotzdem gedruckt werden können:
    /// „kein Drucker gefunden" wäre hier eine Behauptung ohne Grundlage.
    testWidgets('stumme Plattform behauptet nicht, es gäbe keinen Drucker',
        (tester) async {
      mockPlugin();

      await openSheet(tester);

      expect(find.text('Drucken'), findsOneWidget);
      expect(find.textContaining('Kein Drucker gefunden'), findsNothing);
      expect(find.text('Drucker wählen (Systemdialog)'), findsOneWidget);
      expect(find.text('Als PDF speichern'), findsOneWidget);
    });
  });
}
