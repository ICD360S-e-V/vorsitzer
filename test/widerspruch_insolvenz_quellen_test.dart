import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icd360sev_vorsitzer/services/api_service.dart';
import 'package:icd360sev_vorsitzer/services/device_key_service.dart';
import 'package:icd360sev_vorsitzer/widgets/vermieter_widerspruch.dart';

/// Die Insolvenz eines Mitglieds steht an ZWEI Orten.
///
/// ⚠️ Warum es diesen Test gibt: der Reiter fragte nur `insolvenz_akten`
/// ab. Ein Mitglied mit einem Verfahren von 2022 — das als
/// `gericht_vorfaelle` mit `gericht_typ=insolvenzgericht` gespeichert ist,
/// mit drei Beschlüssen daran — sah aus wie eines ohne Insolvenz. Der
/// Reiter meldete keinen Fehler; er zeigte schlicht nichts an, und der
/// stärkste Einwand, den dieses Mitglied hat, ging nicht mit.
void main() {
  http.Response alsJson(Object body, int code) => http.Response(
        body as String,
        code,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );

  /// Merkt sich, was heruntergeladen wurde — der Weg des Anhangs ist die
  /// halbe Prüfung: dieselbe id gibt es in BEIDEN Tabellen.
  late List<String> geholt;

  http.Client mandant(List<Map<String, dynamic>> quellen) =>
      MockClient((anfrage) async {
        if (anfrage.method == 'GET') {
          final q = anfrage.url.queryParameters;
          if (anfrage.url.path.endsWith('vermieter_docs_download.php')) {
            geholt.add('${q['type']}/${q['id']}');
            return http.Response.bytes([37, 80, 68, 70], 200);
          }
          return alsJson(jsonEncode({'success': true, 'items': const []}), 200);
        }
        final koerper = anfrage.body.isEmpty
            ? const <String, dynamic>{}
            : (jsonDecode(anfrage.body) as Map<String, dynamic>);
        switch (koerper['action']?.toString() ?? '') {
          case 'list_insolvenz_quellen':
            return alsJson(
                jsonEncode({'success': true, 'quellen': quellen}), 200);
          case 'get_widerspruch':
            return alsJson(jsonEncode({'success': true, 'exists': false}), 200);
        }
        return alsJson(jsonEncode({'success': true, 'items': const []}), 200);
      });

  Future<void> zeigen(WidgetTester tester,
      List<Map<String, dynamic>> quellen) async {
    geholt = [];
    DeviceKeyService().setTestCredentials('TEST-KEY');
    ApiService().testClient = mandant(quellen);
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
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('ein Gerichtsvorfall zählt als Insolvenz — samt Beschlüssen',
      (tester) async {
    await zeigen(tester, [_weber]);
    // Das Band muss stehen, sonst tippt jemand eine Begründung, obwohl
    // der stärkste Einwand schon in der Akte liegt.
    expect(find.textContaining('ist eine Insolvenz vermerkt'), findsOneWidget);
    expect(find.textContaining('IK 13/21'), findsWidgets);
    // Alle drei Beschlüsse stehen zum Anhängen bereit.
    for (final n in ['Beschluss_1.jpg', 'Beschluss_2.jpg', 'Beschluss_3.jpg']) {
      expect(find.text(n), findsOneWidget, reason: '$n fehlt in der Anlagenliste');
    }
  });

  testWidgets('⚠️ der Grund wird NICHT geraten', (tester) async {
    await zeigen(tester, [_weber]);
    // `status=bewilligt` heißt: dem ANTRAG wurde stattgegeben. Ob am Ende
    // Restschuldbefreiung erteilt ist, sagt der Datensatz nicht. § 301
    // InsO und §§ 87/89 InsO sind verschiedene Aussagen; die falsche im
    // Brief an ein Inkassobüro nimmt dem Widerspruch seine Kraft.
    final kasten = tester.widgetList<CheckboxListTile>(find.byType(CheckboxListTile));
    final angekreuzteGruende = kasten.where((k) {
      final t = (k.title is Text) ? ((k.title as Text).data ?? '') : '';
      return k.value == true &&
          (t.contains('Restschuldbefreiung') || t.contains('Insolvenzverfahren'));
    });
    expect(angekreuzteGruende, isEmpty,
        reason: 'Kein Grund darf vorangekreuzt sein, wenn er nicht ableitbar ist');
    expect(find.textContaining('der Reiter rät das nicht'), findsOneWidget);
  });

  testWidgets('eine Akte mit erteilter Restschuldbefreiung kreuzt sehr wohl an',
      (tester) async {
    await zeigen(tester, [_befreit]);
    expect(find.textContaining('Restschuldbefreiung vermerkt'), findsOneWidget);
    final kasten = tester.widgetList<CheckboxListTile>(find.byType(CheckboxListTile));
    expect(
        kasten.any((k) =>
            k.value == true &&
            (k.title is Text) &&
            ((k.title as Text).data ?? '').contains('Restschuldbefreiung')),
        isTrue);
  });

  /// ⚠️ Zwei getrennte Blöcke, nicht einer mit zweimal `zeigen`: ein
  /// zweites `pumpWidget` desselben Typs an derselben Stelle bringt kein
  /// neues `State` hervor, Flutter aktualisiert das vorhandene. Der Reiter
  /// bliebe also auf der ersten Auswahl stehen — und die Prüfung maß den
  /// ersten Durchgang ein zweites Mal, ohne dass etwas rot wurde.
  testWidgets('⚠️ nur der Gerichtsvorfall: dort wird gelesen', (tester) async {
    // Beide Quellen tragen ein Dokument mit der id 26 — die Zahl allein
    // ist mehrdeutig, erst die Herkunft macht sie eindeutig.
    await zeigen(tester, [_weber]);
    await (tester.state(find.byType(VermieterWiderspruch)) as dynamic)
        .anhaengeFuerTest();
    expect(geholt, ['gericht_vorfall/26', 'gericht_vorfall/27', 'gericht_vorfall/28']);
  });

  testWidgets('⚠️ beide da: die Restschuldbefreiung gewinnt — und nur ihr Dokument',
      (tester) async {
    // Gewollt: sie ist der stärkere Einwand. Dann darf aber auch nur ihr
    // Dokument mitgehen, nicht das gleichnummerige des anderen Vorgangs.
    await zeigen(tester, [_weber, _befreit]);
    await (tester.state(find.byType(VermieterWiderspruch)) as dynamic)
        .anhaengeFuerTest();
    expect(geholt, ['insolvenz_akte/26']);
  });
}

/// Der echte Datensatz des Mitglieds V75715: Verfahren von 2022, drei
/// Beschlüsse, KEIN Feld `phase`.
const _weber = {
  'herkunft': 'gericht_vorfall',
  'id': 9,
  'aktenzeichen': 'IK 13/21',
  'bezeichnung': 'Verbraucherinsolvenz (Privatinsolvenz)',
  'datum': '2022-07-05',
  'status': 'bewilligt',
  'phase': null,
  'dokumente': [
    {'id': 26, 'datei_name': 'Beschluss_1.jpg', 'kategorie': 'beschluss', 'quelle': 'gericht_vorfall'},
    {'id': 27, 'datei_name': 'Beschluss_2.jpg', 'kategorie': 'beschluss', 'quelle': 'gericht_vorfall'},
    {'id': 28, 'datei_name': 'Beschluss_3.jpg', 'kategorie': 'beschluss', 'quelle': 'gericht_vorfall'},
  ],
};

const _befreit = {
  'herkunft': 'insolvenz_akte',
  'id': 4,
  'aktenzeichen': 'IN 88/19',
  'bezeichnung': 'Regelinsolvenz',
  'datum': '2019-02-01',
  'ende_am': '2025-02-01',
  'status': 'beendet',
  'phase': 'restschuldbefreiung',
  'dokumente': [
    {'id': 26, 'datei_name': 'RSB_Beschluss.pdf', 'kategorie': 'beschluss', 'quelle': 'insolvenz_akte'},
  ],
};
