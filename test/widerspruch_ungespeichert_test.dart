import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icd360sev_vorsitzer/services/api_service.dart';
import 'package:icd360sev_vorsitzer/services/device_key_service.dart';
import 'package:icd360sev_vorsitzer/widgets/vermieter_widerspruch.dart';

/// ⚠️ Warum es diesen Test gibt.
///
/// Gemeldet war „Zinsen und Inkassokosten werden nicht gespeichert". Der
/// Weg selbst ist in Ordnung — dieser Test beweist es: was eingetippt
/// wird, geht mit dem Speichern hinaus und kommt beim Neuladen zurück.
///
/// Woran es lag, ist das Formular: es ist auf dem Telefon zwei Dutzend
/// Bildschirmhöhen lang, und der Speichern-Knopf steht ganz unten. Wer
/// oben ein Kreuz setzt oder einen Betrag einträgt, sieht ihn nie und hat
/// keinen Anhaltspunkt, dass noch etwas offen ist. Deshalb steht jetzt
/// oben ein Band, und der Knopf sagt selbst, dass etwas aussteht.
///
/// Der Test hält beides fest: das Band erscheint, sobald etwas geändert
/// wurde, und es ist nach dem Speichern wieder weg. Ohne den zweiten Teil
/// wäre eine Warnung möglich, die immer leuchtet — und die liest niemand.
void main() {
  testWidgets('ungespeicherte Eingabe wird angezeigt und geht dann hinaus',
      (tester) async {
    // Der Mock spielt die Tabelle nach: er merkt sich, was gespeichert
    // wurde, und gibt es beim nächsten Laden zurück.
    Map<String, dynamic>? gespeichert;
    http.Response j(Object b) => http.Response(b as String, 200,
        headers: const {'content-type': 'application/json; charset=utf-8'});

    DeviceKeyService().setTestCredentials('TEST-KEY');
    ApiService().testClient = MockClient((anfrage) async {
      if (anfrage.method == 'GET') {
        return j(jsonEncode({'success': true, 'items': const []}));
      }
      final k = anfrage.body.isEmpty
          ? const <String, dynamic>{}
          : (jsonDecode(anfrage.body) as Map<String, dynamic>);
      switch (k['action']?.toString() ?? '') {
        case 'save_widerspruch':
          gespeichert = Map<String, dynamic>.from(k)..remove('action');
          return j(jsonEncode({'success': true, 'saved': true}));
        case 'get_widerspruch':
          return gespeichert == null
              ? j(jsonEncode({'success': true, 'exists': false}))
              : j(jsonEncode(
                  {'success': true, 'exists': true, 'data': gespeichert}));
        case 'list_insolvenz_quellen':
          return j(jsonEncode({'success': true, 'quellen': const []}));
      }
      return j(jsonEncode({'success': true, 'items': const []}));
    });

    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      DeviceKeyService().setTestCredentials(null);
    });

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      home: Scaffold(
        body: VermieterWiderspruch(
          apiService: ApiService(),
          vorfallId: 1,
          userId: 23,
          inkassoName: 'coeo Inkasso GmbH',
          aktenzeichen: '9763281440',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Frisch geladen ist nichts offen.
    expect(find.text('Nicht gespeichert'), findsNothing);

    Finder geldfeld(String etikett) => find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == etikett);
    String inhalt(String etikett) => tester
            .widgetList<TextField>(find.byType(TextField))
            .firstWhere((t) => t.decoration?.labelText == etikett)
            .controller
            ?.text ??
        '';

    for (final e in {'Zinsen €': '48,90', 'Inkassokosten €': '112,50'}.entries) {
      await tester.ensureVisible(geldfeld(e.key));
      await tester.pumpAndSettle();
      await tester.enterText(geldfeld(e.key), e.value);
      await tester.pumpAndSettle();
    }

    expect(find.text('Nicht gespeichert'), findsOneWidget,
        reason: 'der Knopf steht ganz unten — oben muss stehen, dass etwas offen ist');
    expect(find.text('Speichern (offen)'), findsOneWidget);

    final knopf = find.ancestor(
        of: find.textContaining('Speichern'), matching: find.byType(ElevatedButton));
    await tester.ensureVisible(knopf.first);
    await tester.pumpAndSettle();
    await tester.tap(knopf.first);
    await tester.pumpAndSettle();

    // Hinausgegangen …
    expect(gespeichert?['zinsen'], '48,90');
    expect(gespeichert?['inkassokosten'], '112,50');
    // … zurückgekommen …
    expect(inhalt('Zinsen €'), '48,90');
    expect(inhalt('Inkassokosten €'), '112,50');
    // … und die Warnung ist wieder weg.
    expect(find.text('Nicht gespeichert'), findsNothing);
    expect(find.text('Speichern'), findsOneWidget);
  });

  testWidgets('⚠️ ohne angekreuzten Insolvenzgrund geht keine Verknüpfung hinaus',
      (tester) async {
    // Vorher wurde `insolvenz_vorfall_id` geschrieben, sobald das
    // Mitglied überhaupt eine Insolvenz in der Akte hatte: der Reiter
    // hatte den Vorgang beim Öffnen von selbst gewählt. Im Datensatz
    // stand danach eine Verbindung zu einem Insolvenzverfahren, die
    // niemand behauptet hatte.
    Map<String, dynamic>? gespeichert;
    http.Response j(Object b) => http.Response(b as String, 200,
        headers: const {'content-type': 'application/json; charset=utf-8'});

    DeviceKeyService().setTestCredentials('TEST-KEY');
    ApiService().testClient = MockClient((anfrage) async {
      if (anfrage.method == 'GET') {
        return j(jsonEncode({'success': true, 'items': const []}));
      }
      final k = anfrage.body.isEmpty
          ? const <String, dynamic>{}
          : (jsonDecode(anfrage.body) as Map<String, dynamic>);
      switch (k['action']?.toString() ?? '') {
        case 'save_widerspruch':
          gespeichert = Map<String, dynamic>.from(k)..remove('action');
          return j(jsonEncode({'success': true, 'saved': true}));
        case 'get_widerspruch':
          return gespeichert == null
              ? j(jsonEncode({'success': true, 'exists': false}))
              : j(jsonEncode(
                  {'success': true, 'exists': true, 'data': gespeichert}));
        case 'list_insolvenz_quellen':
          return j(jsonEncode({
            'success': true,
            'quellen': [
              {
                'herkunft': 'gericht_vorfall',
                'id': 9,
                'aktenzeichen': 'IK 13/21',
                'bezeichnung': 'Verbraucherinsolvenz',
                'datum': '2022-07-05',
                'status': 'bewilligt',
                'phase': null,
                'dokumente': const [],
              }
            ]
          }));
      }
      return j(jsonEncode({'success': true, 'items': const []}));
    });

    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      DeviceKeyService().setTestCredentials(null);
    });

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      home: Scaffold(
        body: VermieterWiderspruch(
          apiService: ApiService(),
          vorfallId: 1,
          userId: 23,
          inkassoName: 'coeo Inkasso GmbH',
          aktenzeichen: '9763281440',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Das Band steht da — die Insolvenz IST vermerkt, das soll man sehen.
    expect(find.textContaining('ist eine Insolvenz vermerkt'), findsOneWidget);

    final knopf = find.ancestor(
        of: find.textContaining('Speichern'), matching: find.byType(ElevatedButton));
    await tester.ensureVisible(knopf.first);
    await tester.pumpAndSettle();
    await tester.tap(knopf.first);
    await tester.pumpAndSettle();

    expect(gespeichert?['insolvenz_vorfall_id'], 0,
        reason: 'ohne Kreuz darf der Datensatz kein Verfahren behaupten');
    expect(gespeichert?['insolvenz_akte_id'], 0);
    expect((gespeichert?['gruende'] as List?) ?? const [], isEmpty);
  });
}
