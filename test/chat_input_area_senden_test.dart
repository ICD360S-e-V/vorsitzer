import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/wortliste_service.dart';
import 'package:icd360sev_vorsitzer/utils/diakritika.dart';
import 'package:icd360sev_vorsitzer/utils/wort_vervollstaendigung.dart';
import 'package:icd360sev_vorsitzer/widgets/chat_input_area.dart';

/// Prüft die ECHTE Eingabezeile, nicht einen nachgebauten Aufbau.
///
/// ⚠️ Der Sendeknopf ist ein Geschwister des Textfeldes, kein Kind. Als die
/// Vorschlagsleiste nur das Feld umschloss, kam der Knopf an der Korrektur
/// vorbei — und über ihn geht auf dem Telefon fast jede Nachricht raus.
void main() {
  late TextEditingController c;
  late int gesendet;

  setUp(() {
    WortlisteService.setzenFuerTest(
      WortIndex.aufbauen(['rog', 'bine', 'și', 'Radu']),
      Diakritika.ausJson(const {
        'kurz': {'si': 'și'},
        'kontext': {
          'va': {'vă': {'r': ['rog'], 'l': []}},
        },
      }),
    );
    c = TextEditingController();
    gesendet = 0;
  });

  tearDown(() => c.dispose());

  Future<void> aufbauen(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChatInputArea(
          controller: c,
          isSending: false,
          isUploading: false,
          onSend: () => gesendet++,
          onPickFiles: () {},
        ),
      ),
    ));
    await t.pump();
  }

  void tippen(String text) => c.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );

  testWidgets('der Sendeknopf korrigiert, bevor er sendet', (t) async {
    await aufbauen(t);
    tippen('va rog');
    await t.pump();

    await t.tap(find.byIcon(Icons.send));
    await t.pump();

    expect(c.text, 'vă rog', reason: 'der Knopf darf nicht daran vorbei');
    expect(gesendet, 1);
  });

  testWidgets('kurzes Nicht-Wort ebenfalls', (t) async {
    await aufbauen(t);
    tippen('si');
    await t.pump();
    await t.tap(find.byIcon(Icons.send));
    await t.pump();
    expect(c.text, 'și');
    expect(gesendet, 1);
  });

  testWidgets('ein Eigenname bleibt auch über den Knopf unangetastet',
      (t) async {
    await aufbauen(t);
    tippen('am vorbit cu Radu');
    await t.pump();
    await t.tap(find.byIcon(Icons.send));
    await t.pump();
    expect(c.text, 'am vorbit cu Radu');
    expect(gesendet, 1);
  });

  testWidgets('die Vorschlagsleiste steht ÜBER der ganzen Zeile', (t) async {
    // Belegt die Umbauten: sie umschließt jetzt Textfeld UND Sendeknopf,
    // liegt also oberhalb von beiden.
    await aufbauen(t);
    tippen('bin');
    await t.pump();

    final chip = find.text('bine');
    expect(chip, findsOneWidget);
    final oben = t.getTopLeft(chip).dy;
    final knopf = t.getTopLeft(find.byIcon(Icons.send)).dy;
    expect(oben, lessThan(knopf),
        reason: 'der Vorschlag muss über dem Sendeknopf liegen');
  });
}
