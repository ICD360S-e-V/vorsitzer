// Der Antrags-Dialog im Sozialamt-Tab: dass er sich bearbeiten lässt und dass
// die Felder der Sachbearbeitung wirklich ankommen.
//
// ⚠️ Der Grund für diese Datei: `_showAntragDialog({int? editIndex})` konnte
// schon immer bearbeiten — nur rief es niemand mit `editIndex` auf. Ein Antrag
// war nach dem Anlegen unveränderbar, und **kein Test hätte das gemerkt**, weil
// die Methode ja existierte. Geprüft wird deshalb der Weg über die Oberfläche.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:icd360sev_vorsitzer/services/api_service.dart';
import 'package:icd360sev_vorsitzer/services/device_key_service.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_sozialamt.dart';

/// Ein Antrag, wie ihn `sozialamt_antraege.php` nach dem Entschlüsseln liefert.
final _antrag = <String, dynamic>{
  'id': 42,
  'user_id': 13,
  'leistung': 'Grundsicherung im Alter',
  'datum': '2026-08-23',
  'aktenzeichen': 'SG-2026/00815',
  'ansprechpartner': 'Frau Müller-Schäfer',
  'telefon': '0731 161-5153',
  'email': 'sachbearbeitung@ulm.de',
  'methode': 'postalisch',
  'status': 'eingereicht',
  'notiz': '',
  'hat_bewilligung': 0,
  'bew_bewilligt': null,
  'bew_zeitraum_bis': null,
};

/// Merkt sich, was gespeichert wurde — daran hängt der Beweis, dass die neuen
/// Felder auch wirklich zum Server gehen.
final _gesendet = <Map<String, dynamic>>[];

http.Client _mock() => MockClient((anfrage) async {
      final pfad = anfrage.url.path.toLowerCase();
      if (anfrage.method == 'POST') {
        try {
          _gesendet.add(Map<String, dynamic>.from(jsonDecode(anfrage.body) as Map));
        } catch (_) {}
        return http.Response(jsonEncode({'success': true, 'id': 42}), 200);
      }
      if (pfad.contains('sozialamt_antraege')) {
        return http.Response(jsonEncode({'success': true, 'data': [_antrag]}), 200);
      }
      if (pfad.contains('sozialamt_manage')) {
        return http.Response(jsonEncode({'success': true, 'data': <String, dynamic>{}}), 200);
      }
      return http.Response(jsonEncode({'success': true, 'data': []}), 200);
    });

Widget _bauen() => BehordeSozialamtContent(
      apiService: ApiService(),
      userId: 13,
      getData: (_) => <String, dynamic>{},
      isLoading: (_) => false,
      isSaving: (_) => false,
      loadData: (_) {},
      saveData: (_, __) {},
      dienststelleBuilder: (_, __) => const SizedBox.shrink(),
    );

/// ⚠️ Kein `pumpAndSettle`: der Ladekreisel ist eine Dauer-Animation, die nie
/// zur Ruhe kommt — der Aufruf läuft dann in seinen eigenen 10-Minuten-Deckel
/// und der Test hängt, statt zu scheitern.
Future<void> _ruhen(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

/// Baut das Widget auf einem Pixel-8-Pro-Schirm auf.
///
/// ⚠️ Ein eigener `FlutterError.onError`-Sammler ist hier falsch: `flutter_test`
/// meldet einen Überlauf ohnehin als Testfehler, und wer den Haken übernimmt
/// und erst im `tearDown` zurückgibt, lässt das Binding mit einer nicht
/// abgeholten Ausnahme stehen — der Test hängt dann, statt zu scheitern.
Future<void> _aufbauen(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  const groesse = Size(412, 915);
  tester.view.physicalSize = groesse * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(size: groesse, devicePixelRatio: 3),
      child: Scaffold(body: _bauen()),
    ),
  ));
  await _ruhen(tester);
}

/// ⚠️ Der Reiter „Anträge" liegt auf 412 dp **ausserhalb** des Schirms — die
/// Leiste ist `isScrollable`. Gemessen: Mittelpunkt bei x = 467. Ohne Wischen
/// trifft ein `tap` ins Leere, und zwar mit einer Warnung statt einem Fehler.
Future<void> _zuAntraege(WidgetTester tester) async {
  await tester.drag(find.byType(TabBar), const Offset(-200, 0));
  await _ruhen(tester);
  await tester.tap(find.text('Anträge'));
  await _ruhen(tester);
}

void main() {
  setUpAll(() {
    DeviceKeyService().setTestCredentials('TEST-KEY');
    ApiService().testClient = _mock();
  });
  tearDownAll(() => DeviceKeyService().setTestCredentials(null));
  setUp(_gesendet.clear);

  testWidgets('Antrag lässt sich über das Menü bearbeiten', (tester) async {
    await _aufbauen(tester);
    await _zuAntraege(tester);

    // Aktenzeichen und Ansprechpartner stehen schon auf der Karte — sonst muss
    // man jeden Antrag öffnen, nur um zu sehen, welcher es ist.
    expect(find.text('Az. SG-2026/00815'), findsOneWidget);
    expect(find.text('Frau Müller-Schäfer'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert));
    await _ruhen(tester);
    expect(find.text('Bearbeiten'), findsOneWidget);
    expect(find.text('Löschen'), findsOneWidget);

    await tester.tap(find.text('Bearbeiten'));
    await _ruhen(tester);

    // Der Dialog ist im Bearbeiten-Modus und die Werte stehen drin.
    expect(find.text('Antrag bearbeiten'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'SG-2026/00815'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Frau Müller-Schäfer'), findsOneWidget);
    expect(find.widgetWithText(TextField, '0731 161-5153'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'sachbearbeitung@ulm.de'), findsOneWidget);

    // Überläufe meldet `flutter_test` selbst — dass dieser Test grün ist,
    // heisst also auch: der Dialog passt auf 412 dp.
  });

  testWidgets('neue Felder gehen beim Speichern mit zum Server', (tester) async {
    await _aufbauen(tester);
    await _zuAntraege(tester);
    await tester.tap(find.byIcon(Icons.more_vert));
    await _ruhen(tester);
    await tester.tap(find.text('Bearbeiten'));
    await _ruhen(tester);

    await tester.enterText(find.widgetWithText(TextField, 'SG-2026/00815'), 'SG-2026/00999');
    await tester.tap(find.text('Speichern'));
    await _ruhen(tester);

    final antrag = _gesendet.firstWhere((e) => e.containsKey('leistung'), orElse: () => {});
    expect(antrag, isNotEmpty, reason: 'Es wurde gar nichts gespeichert');
    // ⚠️ Diese vier Schlüssel heißen serverseitig genauso. Ein Tippfehler wäre
    // still: unbekannte Schlüssel wirft `sozialamt_antraege.php` weg, die
    // Antwort bliebe `success: true` und das Feld einfach leer.
    expect(antrag['aktenzeichen'], 'SG-2026/00999');
    expect(antrag['ansprechpartner'], 'Frau Müller-Schäfer');
    expect(antrag['telefon'], '0731 161-5153');
    expect(antrag['email'], 'sachbearbeitung@ulm.de');
    expect(antrag['id'], 42, reason: 'Ohne id legt der Server einen zweiten Antrag an');
    expect(antrag['user_id'], 13);
  });

  testWidgets('neuer Antrag zeigt die Felder der Sachbearbeitung', (tester) async {
    await _aufbauen(tester);
    await _zuAntraege(tester);
    await tester.tap(find.text('Neuer Antrag'));
    await _ruhen(tester);

    expect(find.text('Neuer Antrag'), findsWidgets);
    for (final label in ['Aktenzeichen', 'Sachbearbeitung', 'Ansprechpartner/in', 'Telefon (Durchwahl)', 'E-Mail']) {
      expect(find.text(label), findsWidgets, reason: 'Feld „$label" fehlt im Dialog');
    }

  });
}
