import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/eingabe_tasten.dart';

void main() {
  late List<String> gesendet;
  late TextEditingController c;

  setUp(() {
    gesendet = [];
    c = TextEditingController();
  });
  tearDown(() => c.dispose());

  Future<void> bauen(WidgetTester tester, {int maxLines = 1}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EingabeTasten(
          onSend: () => gesendet.add(c.text),
          bauen: (senden) => TextField(
            controller: c,
            autofocus: true,
            maxLines: maxLines,
            onSubmitted: (_) => senden(),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('Eingabetaste schickt ab', (tester) async {
    await bauen(tester);
    await tester.enterText(find.byType(TextField), 'Hallo');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(gesendet, ['Hallo']);
  });

  testWidgets('auch bei einem MEHRZEILIGEN Feld', (tester) async {
    // Der eigentliche Grund für diese Klasse: `onSubmitted` löst bei
    // mehrzeiligen Feldern NIE aus. Wer nur darauf baut, verliert das Senden
    // per Tastatur in dem Moment, in dem jemand `maxLines` erhöht.
    await bauen(tester, maxLines: 3);
    await tester.enterText(find.byType(TextField), 'Mehrzeilig');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(gesendet, ['Mehrzeilig']);
  });

  testWidgets('Ziffernblock-Eingabe zaehlt auch', (tester) async {
    await bauen(tester);
    await tester.enterText(find.byType(TextField), 'Ziffernblock');
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    await tester.pump();
    expect(gesendet, ['Ziffernblock']);
  });

  testWidgets('Umschalt+Eingabe schickt NICHT', (tester) async {
    await bauen(tester);
    await tester.enterText(find.byType(TextField), 'Neue Zeile');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(gesendet, isEmpty);
  });

  testWidgets('ein Tastendruck schickt nur EINMAL', (tester) async {
    // Beide Wege hängen an derselben Funktion: die Taste und `onSubmitted`
    // (der Senden-Knopf der Bildschirmtastatur). Bei einem einzeiligen Feld
    // können beide auf denselben Druck reagieren — ohne Sperre ginge die
    // Nachricht doppelt raus.
    await bauen(tester);
    await tester.enterText(find.byType(TextField), 'Nur einmal');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(gesendet.length, 1, reason: 'zwei Wege, ein Druck, eine Nachricht');
  });

  testWidgets('nach der Sperre geht das naechste Senden wieder', (tester) async {
    // Die Sperre darf nur einen Doppelschlag schlucken, nicht das Tippen
    // bremsen: wer zwei Nachrichten hintereinander schickt, muss beide
    // loswerden.
    await bauen(tester);
    await tester.enterText(find.byType(TextField), 'Eins');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    // ⚠️ `pump(Dauer)` dreht nur die FALSCHE Uhr des Tests weiter; die Sperre
    // misst die echte. Ohne `runAsync` verginge hier gar keine Zeit und der
    // Test würde einen Fehler behaupten, den es nicht gibt.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.enterText(find.byType(TextField), 'Zwei');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(gesendet, ['Eins', 'Zwei']);
  });
}
