import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icd360sev_vorsitzer/services/api_service.dart';
import 'package:icd360sev_vorsitzer/services/device_key_service.dart';
import 'package:icd360sev_vorsitzer/widgets/vermieter_widerspruch.dart';

/// Was rausgeht, muss in der Akte stehen.
///
/// ⚠️ Vorher stand davon nichts: der Versand füllte nur eine Liste, die
/// mit dem Reiter verschwindet, und ein Hinweis bat darum, es von Hand
/// abzuheften. Der Widerspruch war also raus, aber der Verlauf des
/// Vorfalls zeigte unter Ausgang nichts — wer zwei Jahre später nachsah,
/// fand einen Eingang ohne Antwort.
void main() {
  http.Response alsJson(Object body, int code) => http.Response(
        body as String,
        code,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );

  /// Alles, was als Korrespondenz gespeichert wurde.
  late List<Map<String, dynamic>> abgelegt;

  http.Client mandant({bool ablageGehtSchief = false}) =>
      MockClient((anfrage) async {
        if (anfrage.method == 'GET') {
          return alsJson(jsonEncode({'success': true, 'items': const []}), 200);
        }
        final k = anfrage.body.isEmpty
            ? const <String, dynamic>{}
            : (jsonDecode(anfrage.body) as Map<String, dynamic>);
        final aktion = k['action']?.toString() ?? '';
        if (aktion == 'get_widerspruch') {
          return alsJson(jsonEncode({'success': true, 'exists': false}), 200);
        }
        if (aktion == 'save_korrespondenz') {
          abgelegt.add(k);
          return ablageGehtSchief
              ? alsJson(
                  jsonEncode({'success': false, 'message': 'Tabelle gesperrt'}), 200)
              : alsJson(jsonEncode({'success': true, 'id': 5}), 200);
        }
        return alsJson(
            jsonEncode({'success': true, 'items': const [], 'quellen': const []}), 200);
      });

  Future<dynamic> zeigen(WidgetTester tester,
      {bool ablageGehtSchief = false}) async {
    abgelegt = [];
    DeviceKeyService().setTestCredentials('TEST-KEY');
    ApiService().testClient = mandant(ablageGehtSchief: ablageGehtSchief);
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
          inkassoFax: '+49 2133 2463-99',
          inkassoEmail: 'info@coeo-inkasso.de',
          aktenzeichen: '9763281440',
          glaeubigerName: 'Ulmer Wohnungs- und Siedlungs-Gesellschaft mbH (UWS)',
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

  testWidgets('nach dem Fax steht ein AUSGANG in der Korrespondenz',
      (tester) async {
    final z = await zeigen(tester);
    await z.versandAblegenFuerTest('fax', '+49 2133 2463-99', const <String>[]);
    await tester.pumpAndSettle();

    expect(abgelegt, hasLength(1));
    final e = abgelegt.single;
    expect(e['vorfall_id'], 1);
    expect(e['richtung'], 'ausgehend', reason: 'nicht eingehend — wir schreiben');
    expect(e['medium'], 'fax');
    // ⚠️ Der WORTLAUT, nicht ein Vermerk „wurde gefaxt": beim Anbieter ist
    // der Verlauf nach Monaten gelöscht, unsere Akte muss den Text tragen.
    final text = (e['text'] ?? '').toString();
    expect(text, contains('widerspreche ich in vollem Umfang'));
    expect(text, contains('11.629,88 €'),
        reason: 'die Summe muss in der Akte stehen wie im Brief');
    expect(text, contains('Gläubiger nach unseren Unterlagen'));
    expect((e['betreff'] ?? '').toString(), contains('9763281440'));
    expect((e['notizen'] ?? '').toString(), contains('+49 2133 2463-99'));
    // Der Satz gehört an den Vorgang, nicht nur auf den Bildschirm.
    expect((e['notizen'] ?? '').toString(), contains('kein Anscheinsbeweis'));
  });

  testWidgets('bei E-Mail steht das Medium richtig und ohne Fax-Satz',
      (tester) async {
    final z = await zeigen(tester);
    await z.versandAblegenFuerTest(
        'email', 'info@coeo-inkasso.de', const ['Anlage „Beschluss.pdf" im selben Mail']);
    await tester.pumpAndSettle();

    final e = abgelegt.single;
    expect(e['medium'], 'email');
    expect((e['notizen'] ?? '').toString(), contains('Beschluss.pdf'));
    expect((e['notizen'] ?? '').toString(), isNot(contains('Anscheinsbeweis')));
  });

  testWidgets('⚠️ eine gescheiterte Ablage wird GEMELDET, nicht verschluckt',
      (tester) async {
    // Der Brief ist raus. Hat die Akte ihn nicht, muss das jemand
    // erfahren, solange der Text noch auf dem Schirm steht — sonst fehlt
    // er für immer und niemand weiss davon.
    final z = await zeigen(tester, ablageGehtSchief: true);
    await z.versandAblegenFuerTest('fax', '+49 2133 2463-99', const <String>[]);
    await tester.pumpAndSettle();

    expect(find.textContaining('NICHT in der Korrespondenz abgelegt'), findsOneWidget);
    expect(find.textContaining('Tabelle gesperrt'), findsOneWidget);
  });
}
