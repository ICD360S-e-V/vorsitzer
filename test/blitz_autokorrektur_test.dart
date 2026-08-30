import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/wortliste_service.dart';
import 'package:icd360sev_vorsitzer/utils/diakritika.dart';
import 'package:icd360sev_vorsitzer/utils/tippfehler.dart';
import 'package:icd360sev_vorsitzer/utils/wort_vervollstaendigung.dart';
import 'package:icd360sev_vorsitzer/models/blitz_nachricht.dart';
import 'package:icd360sev_vorsitzer/widgets/blitz_karte.dart';

/// Der Blitz hat ein eigenes Feld und einen eigenen Sendeweg — er lief
/// deshalb zuerst ganz an der Korrektur vorbei, obwohl dort besonders schnell
/// getippt wird. Gemeldet aus dem Betrieb.
void main() {
  late List<String> gesendet;

  setUp(() {
    WortlisteService.setzenFuerTest(
      WortIndex.aufbauen(['rog', 'document', 'bine', 'și', 'vă', 'Radu']),
      Diakritika.ausJson(const {
        'kurz': {'si': 'și'},
        'kontext': {
          'va': {'vă': {'r': ['rog'], 'l': []}},
        },
      }),
      Tippfehler.aufbauen(['document', 'bine', 'trimite']),
    );
    gesendet = [];
  });

  Future<TextEditingController> aufbauen(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BlitzKarte(
          nachricht: BlitzNachricht(
            conversationId: 1,
            absender: 'Test',
            zeilen: const ['Hallo'],
            zeit: DateTime(2026, 8, 30),
          ),
          onSenden: (s) async {
            gesendet.add(s);
            return null;
          },
          onSchliessen: () {},
        ),
      ),
    ));
    await t.pump();
    return t
        .widget<TextField>(find.byType(TextField))
        .controller!;
  }

  testWidgets('der Blitz korrigiert vor dem Senden', (t) async {
    final c = await aufbauen(t);
    c.text = 'dovument';
    await t.pump();
    await t.tap(find.byIcon(Icons.send));
    await t.pump();
    expect(gesendet, ['document']);
  });

  testWidgets('auch die Häkchen aus dem Kontext', (t) async {
    final c = await aufbauen(t);
    c.text = 'si';
    await t.pump();
    await t.tap(find.byIcon(Icons.send));
    await t.pump();
    expect(gesendet, ['și']);
  });

  testWidgets('ein Eigenname mitten im Satz bleibt', (t) async {
    final c = await aufbauen(t);
    c.text = 'vorbit cu Radu';
    await t.pump();
    await t.tap(find.byIcon(Icons.send));
    await t.pump();
    expect(gesendet, ['vorbit cu Radu']);
  });

  testWidgets('richtiger Text bleibt unverändert', (t) async {
    final c = await aufbauen(t);
    c.text = 'totul este bine';
    await t.pump();
    await t.tap(find.byIcon(Icons.send));
    await t.pump();
    expect(gesendet, ['totul este bine']);
  });
}
