import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/chat_header.dart';
import 'package:icd360sev_vorsitzer/widgets/chat_input_area.dart';
import 'package:icd360sev_vorsitzer/widgets/responsive_layout.dart';

/// Der Live-Chat war auf dem Pixel 8 unbenutzbar: der Dialog ist fest auf
/// 800×600 ausgelegt, der Standard-Rand presste ihn auf ~331 dp zusammen,
/// davon gingen 250 an die Konversationsliste — dem Chat blieben rund 80 dp
/// und damit kein Eingabefeld mehr.
///
/// ⚠️ Ein RenderFlex-Überlauf ist im Test eine geworfene FlutterError, also
/// ein roter Test. Genau darum reicht hier das Aufbauen bei Telefonbreite:
/// die abgeschnittene Kopfleiste meldet sich von selbst. `flutter analyze`
/// sieht davon nichts, und auf dem Tablet (800 dp) tritt nichts davon auf.

/// Pixel 8: 1080×2400 px, densityDpi 420 → 411,4 × 914,3 dp.
const Size _pixel8 = Size(411.4, 914.3);

/// Pixel 8 Pro: 1344×2992 px, densityDpi 480 → 448 × 997,3 dp.
const Size _pixel8Pro = Size(448, 997.3);

/// Samsung Tab A11 — die Breite, auf der bisher alles entwickelt wurde.
const Size _tablet = Size(800, 1280);

Future<void> _pump(WidgetTester tester, Size groesse, Widget kind) async {
  tester.view.physicalSize = groesse * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: kind)),
    ),
  );
}

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

/// Die Kanalleiste steht seit der Trennung von App- und SMS-Verlauf unter dem
/// Kopf, nicht mehr darin. Zwei Tabs nebeneinander sind auf 411 dp knapp —
/// und „SMS nicht verfügbar" ist die längste Beschriftung, die vorkommt.
Widget _kanalleiste({String? telefon = '+4915112345678'}) => ChatKanalTabs(
      conversation: {..._konversation(), 'telefon_mobil': telefon},
      channel: ChatChannel.app,
      onChanged: (_) {},
      ungeleseneApp: 12,
      ungeleseneSms: 7,
    );

void main() {
  group('ResponsiveLayout.istTelefon', () {
    // Der eine Schalter, an dem die gesamte Telefon-Anpassung hängt. Er geht
    // nach gemessener Breite — `isMobile` wäre auf dem Tablet ebenfalls true
    // und hätte dort die Notlösungen eingeschaltet.
    for (final (name, groesse, erwartet) in [
      ('Pixel 8', _pixel8, true),
      ('Pixel 8 Pro', _pixel8Pro, true),
      ('Tab A11', _tablet, false),
    ]) {
      testWidgets('$name → $erwartet', (tester) async {
        late bool gemessen;
        await _pump(
          tester,
          groesse,
          Builder(builder: (ctx) {
            gemessen = ResponsiveLayout.istTelefon(ctx);
            return const SizedBox.shrink();
          }),
        );
        expect(gemessen, erwartet);
      });
    }
  });

  group('ConversationHeader auf Telefonbreite', () {
    testWidgets('läuft nicht über, wenn alle neun Aktionen aktiv sind',
        (tester) async {
      await _pump(tester, _pixel8, _kopf());
      expect(tester.takeException(), isNull);
    });

    testWidgets('läuft auch auf dem Pixel 8 Pro nicht über', (tester) async {
      await _pump(tester, _pixel8Pro, _kopf());
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets('legt die überzähligen Aktionen ins ⋮-Menü, statt sie zu '
        'verlieren', (tester) async {
      await _pump(tester, _pixel8, _kopf());

      expect(find.byIcon(Icons.more_vert), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      // Was auf dem Telefon aus der Reihe fällt, muss im Menü stehen.
      // „Konversation schließen" bewusst mit: das weiße × neben einem echten
      // Schließen-Kreuz war die Falle, deretwegen es nicht sichtbar bleibt.
      for (final eintrag in [
        'Cloud des Mitglieds (Dokumente)',
        'Aufgaben',
        'Automatische Nachrichten',
        'Videoanruf',
        'Fernwartung (Bildschirm)',
        'Konversation schließen',
      ]) {
        expect(find.text(eintrag), findsOneWidget, reason: '$eintrag fehlt');
      }
    });

    testWidgets('behält Anrufen und Mitglied-Informationen in der Reihe',
        (tester) async {
      await _pump(tester, _pixel8, _kopf());

      // Beide sind als wichtig markiert — sie dürfen nicht ins Menü rutschen,
      // solange überhaupt Platz für Knöpfe ist.
      expect(find.byTooltip('Benutzer anrufen'), findsOneWidget);
      expect(find.byTooltip('Mitglied-Informationen'), findsOneWidget);
    });

    testWidgets('wo alles nebeneinander passt, bleibt die Reihe offen',
        (tester) async {
      // 9 Knöpfe à 48 dp + Avatar + Mindestbreite für den Namen + Rand.
      await _pump(tester, _tablet, SizedBox(width: 700, child: _kopf()));

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.more_vert), findsNothing);
      expect(find.byTooltip('Fernwartung (Bildschirm)'), findsOneWidget);
      expect(find.byTooltip('Konversation schließen'), findsOneWidget);
    });

    testWidgets('auch auf dem Tablet gewinnt der Name Platz zurück',
        (tester) async {
      // Die Chat-Spalte des Tablets ist rund 517 dp breit (800 − Rand − 250
      // für die Liste). Dort belegten neun Knöpfe 432 dp und ließen dem Namen
      // gut 13 — kein Überlauf, aber auch nichts mehr zu lesen. Das Menü ist
      // hier also nicht nur Telefon-Kosmetik.
      await _pump(tester, _tablet, SizedBox(width: 517, child: _kopf()));

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      expect(tester.getSize(find.text('M51060')).width, greaterThan(50));
    });
  });

  group('ChatKanalTabs auf Telefonbreite', () {
    // Ein RenderFlex-Überlauf ist im Test eine geworfene FlutterError. Das
    // Aufbauen allein ist deshalb schon die Prüfung.
    testWidgets('läuft auf dem Pixel 8 nicht über', (tester) async {
      await _pump(tester, _pixel8, _kanalleiste());

      expect(find.text('App-Chat'), findsOneWidget);
      expect(find.text('SMS'), findsOneWidget);
    });

    testWidgets('auch mit der längsten Beschriftung nicht — „SMS nicht '
        'verfügbar" trifft 19 der 42 Mitglieder', (tester) async {
      await _pump(tester, _pixel8, _kanalleiste(telefon: null));

      expect(find.text('SMS nicht verfügbar'), findsOneWidget);
    });

    testWidgets('auch auf dem Pixel 8 Pro nicht', (tester) async {
      await _pump(tester, _pixel8Pro, _kanalleiste(telefon: null));

      expect(find.text('SMS nicht verfügbar'), findsOneWidget);
    });
  });

  group('ChatInputArea auf Telefonbreite', () {
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

    testWidgets('kürzt den URGENT-Chip auf das Warndreieck', (tester) async {
      await _pump(tester, _pixel8, eingabe());

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.warning), findsOneWidget);
      // Die Beschriftung kostet rund 52 dp — die fehlen sonst dem Textfeld.
      expect(find.text('URGENT'), findsNothing);
    });

    testWidgets('dem Textfeld bleibt brauchbare Breite', (tester) async {
      await _pump(tester, _pixel8, eingabe());

      final feld = tester.getSize(find.byType(TextField));
      // Vor der Reparatur waren es im Zwei-Panel-Layout rund 80 dp.
      expect(feld.width, greaterThan(200));
    });

    testWidgets('auf dem Tablet bleibt die Beschriftung stehen',
        (tester) async {
      await _pump(tester, _tablet, SizedBox(width: 520, child: eingabe()));

      expect(find.text('URGENT'), findsOneWidget);
    });
  });
}
