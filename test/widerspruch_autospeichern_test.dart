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
/// Gemeldet war „ein Kreuz speichert nicht" und „Zinsen und
/// Inkassokosten speichern nicht". Der Weg selbst war in Ordnung — der
/// Knopf war es nicht: er stand am Ende eines Formulars, das auf einem
/// 360 px breiten Telefon **zehneinhalb Bildschirmhöhen** lang ist
/// (7756 px Scrollweg, gemessen). Wer oben etwas einträgt, sieht ihn nie
/// und hält ihn für nicht vorhanden. Genau das war die Rückmeldung:
/// „der Speichern-Knopf existiert nicht".
///
/// Der Knopf ist deshalb weg, und der Reiter legt von selbst ab — wie
/// die Inkasso-Karte in diesem Modul, wo Auswählen schon lange das
/// Speichern IST.
///
/// Der Test hält die drei Eigenschaften fest, an denen so etwas
/// scheitert:
///
///   1. ein Kreuz allein löst es aus (Kreuze rufen kein
///      Controller-Listener auf — das war die eigentliche Lücke),
///   2. es geht wirklich hinaus und der Stand oben sagt es,
///   3. das blosse ÖFFNEN legt nichts an.
void main() {
  http.Response j(Object b) => http.Response(b as String, 200,
      headers: const {'content-type': 'application/json; charset=utf-8'});

  late List<Map<String, dynamic>> gesendet;
  Map<String, dynamic>? gespeichert;

  http.Client mandant(List<Map<String, dynamic>> quellen) =>
      MockClient((anfrage) async {
        if (anfrage.method == 'GET') {
          return j(jsonEncode({'success': true, 'items': const []}));
        }
        final k = anfrage.body.isEmpty
            ? const <String, dynamic>{}
            : (jsonDecode(anfrage.body) as Map<String, dynamic>);
        switch (k['action']?.toString() ?? '') {
          case 'save_widerspruch':
            gesendet.add(Map<String, dynamic>.from(k)..remove('action'));
            gespeichert = gesendet.last;
            return j(jsonEncode({'success': true, 'saved': true, 'status': 'entwurf'}));
          case 'get_widerspruch':
            return gespeichert == null
                ? j(jsonEncode({'success': true, 'exists': false}))
                : j(jsonEncode(
                    {'success': true, 'exists': true, 'data': gespeichert}));
          case 'list_insolvenz_quellen':
            return j(jsonEncode({'success': true, 'quellen': quellen}));
        }
        return j(jsonEncode({'success': true, 'items': const []}));
      });

  Future<void> zeigen(WidgetTester tester,
      {List<Map<String, dynamic>> quellen = const []}) async {
    gesendet = [];
    gespeichert = null;
    DeviceKeyService().setTestCredentials('TEST-KEY');
    ApiService().testClient = mandant(quellen);
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
  }

  /// Wartet die Verzögerung ab und lässt die Anfrage durchlaufen.
  Future<void> abwarten(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
  }

  Finder feld(String etikett) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == etikett);

  String inhalt(WidgetTester tester, String etikett) => tester
          .widgetList<TextField>(find.byType(TextField))
          .firstWhere((t) => t.decoration?.labelText == etikett)
          .controller
          ?.text ??
      '';

  testWidgets('es gibt keinen Speichern-Knopf mehr', (tester) async {
    await zeigen(tester);
    expect(find.widgetWithText(ElevatedButton, 'Speichern'), findsNothing);
    expect(find.textContaining('Speichern (offen)'), findsNothing);
  });

  testWidgets('das blosse Öffnen legt nichts an', (tester) async {
    // ⚠️ Sonst bekäme jeder Vorfall, den jemand nur angesehen hat, einen
    // Widerspruch — und „gibt es hier einen Widerspruch?" hieße für
    // immer ja.
    await zeigen(tester);
    await abwarten(tester);
    expect(gesendet, isEmpty);
    expect(find.textContaining('Abgelegt um'), findsNothing);
  });

  testWidgets('ein Kreuz allein legt ab', (tester) async {
    // ⚠️ Das ist die eigentliche Lücke gewesen: `CheckboxListTile` löst
    // kein Controller-Listener aus. Ohne die Prüfung nach jedem Bild
    // bliebe ein angekreuzter Grund liegen, bis jemand zusätzlich in ein
    // Textfeld tippt.
    await zeigen(tester);
    final kasten = find.ancestor(
        of: find.textContaining('Die Forderung ist bereits bezahlt'),
        matching: find.byType(CheckboxListTile));
    await tester.ensureVisible(kasten);
    await tester.pumpAndSettle();
    await tester.tap(kasten);
    await tester.pumpAndSettle();

    expect(find.textContaining('wird gleich abgelegt'), findsOneWidget);
    await abwarten(tester);

    expect(gesendet, hasLength(1));
    expect(gesendet.single['gruende'], ['bereits_bezahlt']);
    expect(find.textContaining('Abgelegt um'), findsOneWidget);
  });

  testWidgets('Zinsen und Inkassokosten gehen hinaus und kommen zurück',
      (tester) async {
    await zeigen(tester);
    for (final e in {'Zinsen €': '48,90', 'Inkassokosten €': '112,50'}.entries) {
      await tester.ensureVisible(feld(e.key));
      await tester.pumpAndSettle();
      await tester.enterText(feld(e.key), e.value);
      await tester.pumpAndSettle();
    }
    await abwarten(tester);

    // ⚠️ EINE Anfrage für beide Felder. Ohne die Wartezeit wäre jeder
    // Anschlag eine eigene gewesen — „48,90" sind fünf.
    expect(gesendet, hasLength(1));
    expect(gesendet.single['zinsen'], '48,90');
    expect(gesendet.single['inkassokosten'], '112,50');
    expect(inhalt(tester, 'Zinsen €'), '48,90');
    expect(inhalt(tester, 'Inkassokosten €'), '112,50');
  });

  testWidgets('⚠️ ohne angekreuzten Insolvenzgrund geht keine Verknüpfung hinaus',
      (tester) async {
    // Vorher wurde `insolvenz_vorfall_id` geschrieben, sobald das
    // Mitglied überhaupt eine Insolvenz in der Akte hatte: der Reiter
    // hatte den Vorgang beim Öffnen von selbst gewählt. Im Datensatz
    // stand danach eine Verbindung zu einem Insolvenzverfahren, die
    // niemand behauptet hatte.
    await zeigen(tester, quellen: [
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
    ]);
    expect(find.textContaining('ist eine Insolvenz vermerkt'), findsOneWidget);

    // Irgendein anderer Grund, damit überhaupt etwas abgelegt wird.
    final kasten = find.ancestor(
        of: find.textContaining('Die Forderung ist bereits bezahlt'),
        matching: find.byType(CheckboxListTile));
    await tester.ensureVisible(kasten);
    await tester.pumpAndSettle();
    await tester.tap(kasten);
    await tester.pumpAndSettle();
    await abwarten(tester);

    expect(gesendet, hasLength(1));
    expect(gesendet.single['insolvenz_vorfall_id'], 0,
        reason: 'ohne Kreuz darf der Datensatz kein Verfahren behaupten');
    expect(gesendet.single['insolvenz_akte_id'], 0);
  });

  testWidgets('scheitert die Ablage, bleibt es sichtbar stehen', (tester) async {
    // ⚠️ Kein SnackBar: bei einem Netzausfall käme er alle 1,2 Sekunden
    // wieder und legte sich über das Formular.
    gesendet = [];
    gespeichert = null;
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
          return j(jsonEncode({'success': false, 'message': 'kein Netz'}));
        case 'get_widerspruch':
          return j(jsonEncode({'success': true, 'exists': false}));
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
            apiService: ApiService(), vorfallId: 1, userId: 23),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(feld('Zinsen €'));
    await tester.pumpAndSettle();
    await tester.enterText(feld('Zinsen €'), '10');
    await tester.pumpAndSettle();
    await abwarten(tester);

    expect(find.text('Nicht abgelegt'), findsOneWidget);
    expect(find.textContaining('kein Netz'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsOneWidget);
    // Der Wert steht weiter im Feld — verloren ist nichts.
    expect(inhalt(tester, 'Zinsen €'), '10');
  });
}
