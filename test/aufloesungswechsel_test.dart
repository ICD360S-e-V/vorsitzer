// Was passiert, wenn sich die Auflösung im laufenden Betrieb ändert.
//
// Das Gerät hängt zeitweise per HDMI an einem Monitor. Beim Ein- und
// Ausstecken wechselt `MediaQuery` mitten in einer offenen Ansicht — aus
// 448 dp werden 1920, und zurück. Alles, was die Breite in `build` liest,
// zieht automatisch mit; alles, was sie einmal merkt, bleibt stehen.
//
// Geprüft wird deshalb beides: dass der Umschaltpunkt in beide Richtungen
// greift, und dass dabei nichts überläuft. Ein Test, der nur einmal bei
// einer Größe aufbaut, würde ein eingefrorenes Layout nicht bemerken —
// er sieht ja nie einen Wechsel.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icd360sev_vorsitzer/widgets/chat_header.dart';
import 'package:icd360sev_vorsitzer/widgets/chat_message_bubble.dart';
import 'package:icd360sev_vorsitzer/widgets/chat_input_area.dart';
import 'package:icd360sev_vorsitzer/widgets/responsive_layout.dart';

const Size kPixel8Pro = Size(448, 997.3);
const Size kTablet = Size(800, 1280);
const Size kMonitor2K = Size(2560, 1440);

Map<String, dynamic> _konversation() => {
      'id': 7,
      'mitgliedernummer': 'M51060',
      'status': 'open',
      'telefon_mobil': '+4915112345678',
    };

Widget _kopf() => ConversationHeader(
      conversation: _konversation(),
      canCall: true,
      isOpen: true,
      onCall: () {},
      onVideoCall: () {},
      onRemoteControl: () {},
      onClose: () {},
      onMuteToggle: () {},
      onScheduledSettings: () {},
      onInfoTap: () {},
      onAufgabenTap: () {},
      aufgabenTotal: 4,
      aufgabenOffen: 2,
      onCloudTap: () {},
      cloudFileCount: 12,
    );

/// Setzt die Größe und baut einen Frame — ohne neues `pumpWidget`, damit
/// derselbe State erhalten bleibt. Genau das macht das HDMI-Kabel auch.
Future<void> groesseWechseln(WidgetTester tester, Size groesse) async {
  tester.view.physicalSize = groesse * 3;
  tester.view.devicePixelRatio = 3;
  await tester.pump();
}

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

  group('Umschaltpunkt greift in beide Richtungen', () {
    testWidgets('istTelefon folgt dem Kabel, nicht dem Startwert',
        (tester) async {
      addTearDown(tester.view.reset);
      final verlauf = <bool>[];

      tester.view.physicalSize = kPixel8Pro * 3;
      tester.view.devicePixelRatio = 3;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          verlauf.add(ResponsiveLayout.istTelefon(ctx));
          return const SizedBox.shrink();
        }),
      ));

      await groesseWechseln(tester, kMonitor2K);
      await groesseWechseln(tester, kPixel8Pro);

      // Telefon → Monitor → Telefon. Bliebe ein Wert hängen, stünde hier
      // dreimal dasselbe.
      expect(verlauf, [true, false, true]);
    });
  });

  group('ConversationHeader am HDMI-Monitor', () {
    testWidgets('das ⋮-Menü verschwindet, wenn das Kabel kommt — und kehrt '
        'zurück, wenn es geht', (tester) async {
      addTearDown(tester.view.reset);

      tester.view.physicalSize = kPixel8Pro * 3;
      tester.view.devicePixelRatio = 3;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: _kopf())));

      // Telefon: gestaucht, also Überlaufmenü.
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      expect(find.byTooltip('Fernwartung (Bildschirm)'), findsNothing);

      await groesseWechseln(tester, kMonitor2K);

      // Monitor: alles nebeneinander, kein Menü mehr.
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.more_vert), findsNothing);
      expect(find.byTooltip('Fernwartung (Bildschirm)'), findsOneWidget);
      expect(find.byTooltip('Konversation schließen'), findsOneWidget);

      await groesseWechseln(tester, kPixel8Pro);

      // Kabel raus: zurück ins Menü, ohne Überlauf.
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });
  });

  group('ChatInputArea am HDMI-Monitor', () {
    Widget eingabe() => ChatInputArea(
          controller: TextEditingController(),
          isSending: false,
          isUploading: false,
          onSend: () {},
          onPickFiles: () {},
          hintText: 'Antwort eingeben...',
          showUrgentCheckbox: true,
          isUrgent: false,
          onUrgentChanged: (_) {},
        );

    testWidgets('die URGENT-Beschriftung kommt am Monitor zurück',
        (tester) async {
      addTearDown(tester.view.reset);

      tester.view.physicalSize = kPixel8Pro * 3;
      tester.view.devicePixelRatio = 3;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: eingabe())));
      expect(find.text('URGENT'), findsNothing);

      await groesseWechseln(tester, kMonitor2K);
      expect(find.text('URGENT'), findsOneWidget);

      await groesseWechseln(tester, kPixel8Pro);
      expect(find.text('URGENT'), findsNothing);
    });
  });

  group('Lesbarkeit auf breiten Bildschirmen', () {
    // ⚠️ Kein Überlauf heißt nicht „sieht gut aus". Auf 2560 dp läuft ein
    // Fließtext ohne Breitenbegrenzung über die ganze Fläche — rund 400
    // Zeichen pro Zeile. Typografisch liegt die Obergrenze bei etwa 80;
    // darüber verliert das Auge beim Zeilenwechsel die Spur. Der Test hält
    // fest, wo eine Begrenzung schon da ist, damit sie niemand entfernt.
    testWidgets('ResponsiveDialog wächst nicht mit dem Monitor',
        (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = kMonitor2K * 3;
      tester.view.devicePixelRatio = 3;

      await tester.pumpWidget(const MaterialApp(
        home: ResponsiveDialog(
          title: 'Test',
          content: Text('Inhalt'),
        ),
      ));

      final kasten = tester.getSize(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(Container),
        ).first,
      );
      // 600 dp Vorgabe, gedeckelt auf 80 % der Bildschirmbreite — auf einem
      // 2560-dp-Monitor müssen die 600 stehen bleiben, nicht 2048 werden.
      expect(kasten.width, 600);
    });

    testWidgets('Telefonbreite bleibt beim Faktor, nicht bei den 600 dp',
        (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = kPixel8Pro * 3;
      tester.view.devicePixelRatio = 3;

      await tester.pumpWidget(const MaterialApp(
        home: ResponsiveDialog(
          title: 'Test',
          content: Text('Inhalt'),
        ),
      ));

      final kasten = tester.getSize(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(Container),
        ).first,
      );
      expect(kasten.width, closeTo(448 * 0.9, 1));
    });
  });

  group('Chat-Blase bleibt lesbar', () {
    // ⚠️ Hier lief kein Überlauf auf — die Blase passte immer. Sie war nur
    // unlesbar: `MediaQuery.size.width * 0.75` ergab am 2560-dp-Monitor
    // 1920 dp, also rund 380 Zeichen pro Zeile. Kein Test, der nur auf
    // RenderFlex-Überläufe schaut, findet das je.
    for (final (name, breite, erwartet) in [
      ('Pixel 8 Pro', 448.0, 336.0),
      ('Tab A11', 800.0, 560.0),
      ('HDMI Full HD', 1920.0, 560.0),
      ('HDMI 2K', 2560.0, 560.0),
      ('HDMI 4K', 3840.0, 560.0),
    ]) {
      testWidgets('$name → höchstens ${erwartet.toInt()} dp', (tester) async {
        addTearDown(tester.view.reset);
        tester.view.physicalSize = Size(breite, 1000) * 3;
        tester.view.devicePixelRatio = 3;

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: ChatMessageBubble(
              message: {
                'id': 1,
                'message': 'Ein Satz, der lang genug ist, um die volle Breite '
                    'der Blase auszureizen und damit zu zeigen, wo der Deckel '
                    'greift und wo nicht.',
                'created_at': '2026-08-08 10:00:00',
                'sender_type': 'admin',
              },
              isOwn: true,
              onDownloadAttachment: (_) {},
            ),
          ),
        ));

        final blase = tester.widgetList<Container>(find.byType(Container))
            .firstWhere((c) => c.constraints?.maxWidth != null);
        expect(blase.constraints!.maxWidth, erwartet);
      });
    }
  });

  group('Gegenprobe: der Umschaltpunkt liegt nicht an der Plattform', () {
    testWidgets('das Tablet bekommt die Monitor-Ansicht, nicht die Telefon-Ansicht',
        (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = kTablet * 3;
      tester.view.devicePixelRatio = 3;

      late bool telefon;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          telefon = ResponsiveLayout.istTelefon(ctx);
          return const SizedBox.shrink();
        }),
      ));
      // `isMobile` wäre hier true — `istTelefon` darf es nicht sein.
      expect(telefon, isFalse);
    });
  });
}
