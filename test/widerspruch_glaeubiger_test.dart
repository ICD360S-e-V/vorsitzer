import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icd360sev_vorsitzer/services/api_service.dart';
import 'package:icd360sev_vorsitzer/services/device_key_service.dart';
import 'package:icd360sev_vorsitzer/widgets/vermieter_widerspruch.dart';

/// Der Gläubiger steht im Mietvertrag — abtippen muss ihn niemand.
///
/// ⚠️ Er war einmal bewusst leer gelassen, weil „von Ihnen benannter
/// Gläubiger" eine Aussage über den Brief der GEGENSEITE ist. Das Argument
/// stimmt; die Schlussfolgerung war falsch. Aufgelöst wird der Widerspruch
/// nicht durch Weglassen, sondern indem der Brief sagt, woher der Name
/// kommt — genau das prüfen diese Tests.
void main() {
  http.Response alsJson(Object body, int code) => http.Response(
        body as String,
        code,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );

  http.Client leer() => MockClient((anfrage) async {
        if (anfrage.method == 'GET') {
          return alsJson(jsonEncode({'success': true, 'items': const []}), 200);
        }
        final k = anfrage.body.isEmpty
            ? const <String, dynamic>{}
            : (jsonDecode(anfrage.body) as Map<String, dynamic>);
        if ((k['action']?.toString() ?? '') == 'get_widerspruch') {
          return alsJson(jsonEncode({'success': true, 'exists': false}), 200);
        }
        return alsJson(
            jsonEncode({'success': true, 'items': const [], 'quellen': const []}), 200);
      });

  Future<dynamic> zeigen(WidgetTester tester, {String? vermieter}) async {
    DeviceKeyService().setTestCredentials('TEST-KEY');
    ApiService().testClient = leer();
    tester.view.physicalSize = const Size(800, 1400);
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
          glaeubigerName: vermieter,
          vorfall: const {
            'bezeichnung': 'Miete und Nebenkosten',
            'forderung_brutto': '11.629,88',
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return tester.state(find.byType(VermieterWiderspruch)) as dynamic;
  }

  const uws = 'Ulmer Wohnungs- und Siedlungs-Gesellschaft mbH (UWS)';

  testWidgets('der Vermieter steht von selbst im Feld', (tester) async {
    await zeigen(tester, vermieter: uws);
    final feld = tester.widget<TextField>(find.ancestor(
        of: find.text(uws), matching: find.byType(TextField)));
    expect(feld.controller?.text, uws,
        reason: 'Er steht im Mietvertrag — niemand soll ihn abtippen');
  });

  testWidgets('⚠️ der Brief zitiert die Gegenseite NICHT falsch', (tester) async {
    final z = await zeigen(tester, vermieter: uws);
    final brief = z.brieftextFuerTest() as String;
    // Der Name kommt aus UNSERER Akte. Zu schreiben, das Büro habe ihn
    // genannt, wäre eine Behauptung über deren Brief — und falsch, sobald
    // die Forderung verkauft wurde.
    expect(brief, contains('Gläubiger nach unseren Unterlagen: $uws'));
    expect(brief, isNot(contains('Von Ihnen benannter Gläubiger')));
    // Und im selben Zug die Bitte um Berichtigung.
    expect(brief, contains('bitte berichtigen'));
  });

  testWidgets('von Hand eingetragen: dann ist es IHRE Angabe', (tester) async {
    final z = await zeigen(tester, vermieter: uws);
    await tester.enterText(
        find.ancestor(of: find.text(uws), matching: find.byType(TextField)),
        'Forderungskäufer XY GmbH');
    await tester.pumpAndSettle();
    final brief = z.brieftextFuerTest() as String;
    expect(brief, contains('Von Ihnen benannter Gläubiger: Forderungskäufer XY GmbH'));
    expect(brief, isNot(contains('nach unseren Unterlagen')));
  });

  testWidgets('ohne Vermieter bleibt die Zeile ganz weg', (tester) async {
    final z = await zeigen(tester);
    final brief = z.brieftextFuerTest() as String;
    expect(brief, isNot(contains('Gläubiger nach unseren Unterlagen')));
    expect(brief, isNot(contains('Von Ihnen benannter Gläubiger')));
  });
}
