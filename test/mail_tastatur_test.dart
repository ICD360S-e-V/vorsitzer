import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/mail_tastatur.dart';

void main() {
  late List<String> gedrueckt;
  late TextEditingController ctrl;

  Widget bauen({bool aktiv = true}) {
    gedrueckt = [];
    ctrl = TextEditingController();
    return MaterialApp(
      home: Scaffold(
        body: MailTastaturhuelle(
          aktiv: aktiv,
          aktionen: {
            const SingleActivator(LogicalKeyboardKey.keyC): () =>
                gedrueckt.add('c'),
            const SingleActivator(LogicalKeyboardKey.keyJ): () =>
                gedrueckt.add('j'),
            const SingleActivator(LogicalKeyboardKey.delete): () =>
                gedrueckt.add('entf'),
          },
          child: Column(
            children: [
              const Text('Liste'),
              TextField(controller: ctrl, key: const Key('suche')),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('ohne Textfeld im Fokus lösen die Tasten aus', (t) async {
    await t.pumpWidget(bauen());
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.keyC);
    await t.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await t.pump();
    expect(gedrueckt, ['c', 'j']);
  });

  testWidgets('WÄHREND getippt wird, löst KEINE Taste aus', (t) async {
    // ⚠️ Das ist der ganze Punkt. Ohne diese Sperre wäre ein Postfach, in dem
    // man nicht nach „Rechnung" suchen kann, weil jedes „c" ein neues Fenster
    // aufmacht — und genau daran scheitern die meisten selbstgebauten Kürzel.
    await t.pumpWidget(bauen());
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('suche')));
    await t.pumpAndSettle();

    await t.sendKeyEvent(LogicalKeyboardKey.keyC);
    await t.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await t.sendKeyEvent(LogicalKeyboardKey.delete);
    await t.pump();
    expect(gedrueckt, isEmpty);
  });

  testWidgets('nach dem Verlassen des Feldes gehen sie wieder', (t) async {
    await t.pumpWidget(bauen());
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('suche')));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.keyC);
    expect(gedrueckt, isEmpty);

    // Fokus weg vom Textfeld.
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.keyC);
    await t.pump();
    expect(gedrueckt, ['c']);
  });

  testWidgets('ausgeschaltet reicht die Hülle die Tasten durch, ohne zu handeln',
      (t) async {
    await t.pumpWidget(bauen(aktiv: false));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.keyC);
    await t.pump();
    expect(gedrueckt, isEmpty);
    // Und der Inhalt ist trotzdem da — die Hülle darf nichts verschlucken.
    expect(find.text('Liste'), findsOneWidget);
  });

  testWidgets('die Tastenübersicht nennt jede belegte Taste', (t) async {
    // Eine Hilfe, die eine Taste verschweigt, ist schlimmer als keine.
    expect(kMailTasten, isNotEmpty);
    for (final k in kMailTasten) {
      expect(k.taste.trim(), isNotEmpty);
      expect(k.was.trim(), isNotEmpty);
    }
  });
}
