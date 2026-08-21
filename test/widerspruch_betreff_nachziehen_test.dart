import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icd360sev_vorsitzer/services/api_service.dart';
import 'package:icd360sev_vorsitzer/services/device_key_service.dart';
import 'package:icd360sev_vorsitzer/widgets/vermieter_widerspruch.dart';

/// Ein gespeicherter Betreff kann eine Ersatzfassung sein.
///
/// ⚠️ Der Betreff wird beim ersten Speichern mitgeschrieben, auch wenn ihn
/// nie ein Mensch angefasst hat. Kam das Aktenzeichen später dazu, gewann
/// trotzdem der gespeicherte Text — und im Kopf des Schreibens stand für
/// immer „Widerspruch — Miete und Nebenkosten" statt der Nummer, nach der
/// das Büro ablegt. Genau das war auf dem Schirm zu sehen.
void main() {
  http.Response alsJson(Object body, int code) => http.Response(
        body as String,
        code,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );

  http.Client mandant(String gespeicherterBetreff) => MockClient((anfrage) async {
        if (anfrage.method == 'GET') {
          return alsJson(jsonEncode({'success': true, 'items': const []}), 200);
        }
        final k = anfrage.body.isEmpty
            ? const <String, dynamic>{}
            : (jsonDecode(anfrage.body) as Map<String, dynamic>);
        if ((k['action']?.toString() ?? '') == 'get_widerspruch') {
          return alsJson(
              jsonEncode({
                'success': true,
                'exists': true,
                'data': {
                  'id': 1,
                  'umfang': 'voll',
                  'status': 'entwurf',
                  'betreff': gespeicherterBetreff,
                  'versandweg': 'fax',
                },
              }),
              200);
        }
        return alsJson(
            jsonEncode({'success': true, 'items': const [], 'quellen': const []}), 200);
      });

  Future<void> zeigen(WidgetTester tester, String gespeichert,
      {String? az = '6865140/26/0'}) async {
    DeviceKeyService().setTestCredentials('TEST-KEY');
    ApiService().testClient = mandant(gespeichert);
    tester.view.physicalSize = const Size(800, 1600);
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
          aktenzeichen: az,
          vorfallBezeichnung: 'Miete und Nebenkosten',
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  String betreffImFeld(WidgetTester tester) => tester
      .widgetList<TextField>(find.byType(TextField))
      .firstWhere((f) =>
          (f.decoration?.labelText ?? '') == 'Betreff')
      .controller!
      .text;

  testWidgets('die alte Ersatzfassung wird durch das Aktenzeichen ersetzt',
      (tester) async {
    await zeigen(tester, 'Widerspruch — Miete und Nebenkosten');
    expect(betreffImFeld(tester), 'Aktenzeichen 6865140/26/0 - Widerspruch');
    // ⚠️ Und es steht auf dem Schirm. Einen gespeicherten Betreff
    // stillschweigend auszutauschen wäre genau der Fehler, den die Regel
    // verhindern soll.
    expect(find.textContaining('Betreff um das Aktenzeichen ergänzt'), findsOneWidget);
    expect(find.textContaining('Widerspruch — Miete und Nebenkosten'), findsOneWidget);
  });

  testWidgets('auch die namenlose Ersatzfassung', (tester) async {
    await zeigen(tester, 'Widerspruch gegen Ihre Forderung');
    expect(betreffImFeld(tester), 'Aktenzeichen 6865140/26/0 - Widerspruch');
  });

  testWidgets('⚠️ ein selbst geschriebener Betreff bleibt unangetastet',
      (tester) async {
    await zeigen(tester, 'Zahlungsaufforderung vom 10.03.2026 — Rückfrage');
    expect(betreffImFeld(tester), 'Zahlungsaufforderung vom 10.03.2026 — Rückfrage');
    expect(find.textContaining('Betreff um das Aktenzeichen ergänzt'), findsNothing);
  });

  testWidgets('ohne Aktenzeichen wird gar nichts angefasst', (tester) async {
    // Es gäbe nichts Besseres — dann bleibt auch die Ersatzfassung stehen.
    await zeigen(tester, 'Widerspruch — Miete und Nebenkosten', az: null);
    expect(betreffImFeld(tester), 'Widerspruch — Miete und Nebenkosten');
    expect(find.textContaining('Betreff um das Aktenzeichen ergänzt'), findsNothing);
  });

  group('istErsatzBetreff', () {
    test('erkennt genau die zwei eigenen Formen', () {
      expect(istErsatzBetreff('Widerspruch gegen Ihre Forderung'), isTrue);
      expect(istErsatzBetreff('Widerspruch — irgendetwas'), isTrue);
      expect(istErsatzBetreff('  Widerspruch — Miete  '), isTrue);
    });
    test('und sonst nichts', () {
      // Der neue Betreff darf sich nie selbst als Ersatzfassung sehen —
      // sonst würde er bei jedem Öffnen neu gebaut.
      expect(istErsatzBetreff('Aktenzeichen 6865140/26/0 - Widerspruch'), isFalse);
      // Ein Bindestrich ist kein Geviertstrich: „Widerspruch - X" hat
      // dieser Reiter nie erzeugt, das hat jemand getippt.
      expect(istErsatzBetreff('Widerspruch - Miete'), isFalse);
      expect(istErsatzBetreff('Mein eigener Betreff'), isFalse);
      expect(istErsatzBetreff(''), isFalse);
      expect(istErsatzBetreff(null), isFalse);
    });
  });
}
