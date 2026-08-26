import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/arzt_suche_dialog.dart';

/// Ein Ausschnitt aus `aerzte_datenbank`, wie er am 26.08.2026 dort stand.
final _katalog = <Map<String, dynamic>>[
  {'praxis_name': 'Praxis für Gastroenterologie — Dres. Böck & Hägele',
   'arzt_name': 'Dr. med. Wolfgang Böck', 'fachrichtung': 'Gastroenterologie',
   'strasse': 'Frauenstr. 51', 'plz_ort': '89077 Ulm'},
  {'praxis_name': 'Gemeinschaftspraxis für Orthopädie', 'arzt_name': 'Dr. med. H. Egle',
   'fachrichtung': 'Orthopädie', 'strasse': '', 'plz_ort': '89073 Ulm'},
  {'praxis_name': 'Zahnarztpraxis Musterweg', 'arzt_name': 'Dr. Zahn',
   'fachrichtung': 'Zahnmedizin', 'strasse': '', 'plz_ort': '89073 Ulm'},
];

Future<void> _oeffnen(
  WidgetTester tester, {
  required String fachrichtung,
  ArztKatalogAbfrage? katalog,
  bool nurFachVoreinstellung = true,
  void Function(Map<String, dynamic>)? onSelect,
  Future<Map<String, dynamic>?> Function(String)? onAnlegen,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () => ArztSucheDialog.oeffnen(
            context: ctx,
            fachrichtung: fachrichtung,
            nurFachVoreinstellung: nurFachVoreinstellung,
            katalog: katalog ?? (_) async => _katalog,
            onSelect: onSelect ?? (_) {},
            onAnlegen: onAnlegen,
            anlegenBeschriftung: 'Klinik aufnehmen',
          ),
          child: const Text('auf'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('auf'));
  // ⚠️ KEIN pumpAndSettle: solange der Ladekreis steht, plant er endlos
  // Bilder — der Test würde nicht scheitern, sondern hängen.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('der gemeldete Fall: Gastroenterologie findet ihre Praxis',
      (tester) async {
    // 🔴 Die Praxis liegt unter 'Gastroenterologie', der Reiter sucht mit
    // 'Gastroenterologie / Magen-Darm-Erkrankungen'. Zeichengleich verglichen
    // blieb die Liste leer, obwohl der Eintrag da war.
    await _oeffnen(tester, fachrichtung: 'Gastroenterologie / Magen-Darm-Erkrankungen');
    expect(find.textContaining('Dres. Böck & Hägele'), findsOneWidget);
    expect(find.textContaining('Zahnarztpraxis'), findsNothing);
    expect(find.text('2 ausgeblendet'), findsOneWidget);
  });

  testWidgets('der Filter lässt sich abschalten — und wieder an', (tester) async {
    // Das ist der Ausweg, den es bis zum 26.08.2026 nicht gab: eine zu enge
    // Liste war eine Sackgasse.
    await _oeffnen(tester, fachrichtung: 'Zahnmedizin');
    expect(find.textContaining('Zahnarztpraxis'), findsOneWidget);
    expect(find.textContaining('Dres. Böck & Hägele'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, 'Nur Zahnmedizin'));
    await tester.pump();
    expect(find.textContaining('Dres. Böck & Hägele'), findsOneWidget);
    expect(find.text('2 ausgeblendet'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, 'Nur Zahnmedizin'));
    await tester.pump();
    expect(find.textContaining('Dres. Böck & Hägele'), findsNothing);
  });

  testWidgets('eine leere Liste sagt, dass gefiltert wurde — und wie viele',
      (tester) async {
    await _oeffnen(tester, fachrichtung: 'Urologie');
    expect(find.text('Keine Ärzte gefunden'), findsOneWidget);
    expect(find.textContaining('3 andere sind vorhanden'), findsOneWidget);
  });

  testWidgets('ohne Fach gibt es weder Filter noch Schalter', (tester) async {
    // Der Reiter „Sonstiger Arzt" ist der Sammelplatz und darf nicht eingrenzen.
    await _oeffnen(tester, fachrichtung: '');
    expect(find.byType(FilterChip), findsNothing);
    expect(find.textContaining('Zahnarztpraxis'), findsOneWidget);
    expect(find.textContaining('Dres. Böck & Hägele'), findsOneWidget);
  });

  testWidgets('ein gescheiterter Aufruf ist NICHT „nichts gefunden"',
      (tester) async {
    // ⚠️ Beides als leere Liste zu zeigen war die zweite Hälfte des Fehlers.
    await _oeffnen(tester, fachrichtung: 'Zahnmedizin', katalog: (_) async => null);
    expect(find.text('Die Datenbank hat nicht geantwortet'), findsOneWidget);
    expect(find.textContaining('andere sind vorhanden'), findsNothing);
  });

  testWidgets('eine Ausnahme im Katalog beendet den Ladekreis', (tester) async {
    await _oeffnen(tester,
        fachrichtung: 'Zahnmedizin', katalog: (_) async => throw StateError('weg'));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Die Datenbank hat nicht geantwortet'), findsOneWidget);
  });

  testWidgets('die Auswahl schliesst den Dialog und meldet die Zeile',
      (tester) async {
    Map<String, dynamic>? gewaehlt;
    await _oeffnen(tester,
        fachrichtung: 'Gastroenterologie',
        onSelect: (a) => gewaehlt = a);
    await tester.tap(find.textContaining('Dres. Böck & Hägele'));
    await tester.pump();
    expect(gewaehlt?['fachrichtung'], 'Gastroenterologie');
    // Der Dialog fährt animiert heraus — ohne die Übergangszeit steht er noch da.
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(AlertDialog), findsNothing);
  });

  group('Weg aus einer leeren Liste', () {
    // 🔴 Der Klinik-Katalog war bis zum 26.08.2026 nur lesbar. Wer in einem
    // Haus behandelt wurde, das nicht unter den gespeicherten stand, hatte
    // nichts zu wählen und nichts anzulegen — eine Sackgasse.
    testWidgets('ohne onAnlegen gibt es keinen Knopf', (tester) async {
      await _oeffnen(tester, fachrichtung: 'Urologie');
      expect(find.text('Keine Ärzte gefunden'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Klinik aufnehmen'), findsNothing);
    });

    testWidgets('der Knopf steht IN der leeren Liste, nicht nur in der Leiste',
        (tester) async {
      // Unten in der Leiste würde ihn dort niemand suchen.
      await _oeffnen(tester,
          fachrichtung: 'Urologie', onAnlegen: (_) async => null);
      expect(find.widgetWithText(FilledButton, 'Klinik aufnehmen'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Klinik aufnehmen'), findsOneWidget);
    });

    testWidgets('der Suchtext wird durchgereicht', (tester) async {
      // Wer „Katharinenhospital" getippt hat, soll den Namen im Formular
      // wiederfinden statt ihn abzutippen.
      String? gesehen;
      await _oeffnen(tester,
          fachrichtung: '', onAnlegen: (t) async { gesehen = t; return null; });
      await tester.enterText(find.byType(TextField), 'Katharinenhospital');
      await tester.tap(find.widgetWithText(TextButton, 'Klinik aufnehmen'));
      await tester.pump();
      expect(gesehen, 'Katharinenhospital');
    });

    testWidgets('das Angelegte ist sofort das Gewählte', (tester) async {
      Map<String, dynamic>? gewaehlt;
      final neu = {'id': 145, 'praxis_name': 'Katharinenhospital', 'fachrichtung': 'Urologie'};
      await _oeffnen(tester,
          fachrichtung: 'Urologie',
          onSelect: (a) => gewaehlt = a,
          onAnlegen: (_) async => neu);
      await tester.tap(find.widgetWithText(FilledButton, 'Klinik aufnehmen'));
      await tester.pump();
      expect(gewaehlt?['id'], 145);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('ein Abbruch im Formular wählt nichts und schliesst nichts',
        (tester) async {
      var gewaehlt = false;
      await _oeffnen(tester,
          fachrichtung: 'Urologie',
          onSelect: (_) => gewaehlt = true,
          onAnlegen: (_) async => null);
      await tester.tap(find.widgetWithText(FilledButton, 'Klinik aufnehmen'));
      await tester.pump(const Duration(seconds: 1));
      expect(gewaehlt, isFalse);
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });

  group('arztKatalog', () {
    test('gescheiterte Antwort → null, nicht leere Liste', () async {
      final k = arztKatalog((_) async => {'success': false});
      expect(await k(''), isNull);
      final k2 = arztKatalog((_) async => {'success': true, 'data': null});
      expect(await k2(''), isNull);
    });
    test('leere Antwort → leere Liste', () async {
      final k = arztKatalog((_) async => {'success': true, 'data': []});
      expect(await k(''), isEmpty);
    });
    test('benennt Spalten um, wenn verlangt', () async {
      final k = arztKatalog(
        (_) async => {'success': true, 'kliniken': [{'name': 'Innere', 'krankenhaus': 'RKU'}]},
        schluessel: 'kliniken',
        abbilden: (k) => {...k, 'arzt_name': k['name'], 'praxis_name': k['krankenhaus']},
      );
      final r = await k('');
      expect(r!.single['praxis_name'], 'RKU');
      expect(r.single['arzt_name'], 'Innere');
    });
  });
}
