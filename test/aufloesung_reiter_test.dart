// Zeichnet auch die Reiter, die beim Aufbau NICHT sichtbar sind.
//
// ⚠️ Das größte Loch der bisherigen Prüfungen: `TabBarView` baut faul. Wer
// einen Bildschirm nur aufbaut, sieht ausschließlich den ersten Reiter —
// Reiter 2 bis 6 existieren im Test schlicht nicht. Bei Bildschirmen mit
// sechs Reitern waren das fünf Sechstel der Oberfläche, die noch nie ein
// Test berührt hat.
//
// Dieser Test tippt sich durch alle Reiter und misst nach jedem Wechsel.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:icd360sev_vorsitzer/models/user.dart';
import 'package:icd360sev_vorsitzer/services/api_service.dart';
import 'package:icd360sev_vorsitzer/services/device_key_service.dart';
import 'package:icd360sev_vorsitzer/services/termin_service.dart';
import 'package:icd360sev_vorsitzer/services/ticket_service.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_jobcenter.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_konsulat.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_tab_content.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_wbs.dart';
import 'package:icd360sev_vorsitzer/widgets/gesundheit_tab_content.dart';
import 'package:icd360sev_vorsitzer/widgets/mitgliederverwaltung_arzten_augenarzt.dart';
import 'package:icd360sev_vorsitzer/widgets/mitgliederverwaltung_arzten_hno.dart';
import 'package:icd360sev_vorsitzer/widgets/mitgliederverwaltung_arzten_krankenhaus.dart';
import 'package:icd360sev_vorsitzer/widgets/mitgliederverwaltung_arzten_md.dart';
import 'package:icd360sev_vorsitzer/widgets/mitgliederverwaltung_arzten_rheumatologie.dart';
import 'package:icd360sev_vorsitzer/widgets/reparatur.dart';

const _groessen = <String, ({Size groesse, double schrift})>{
  'Pixel 8 Pro (448 dp)': (groesse: Size(448, 997.3), schrift: 1.0),
  'Pixel 8 Pro, Schrift 2,0': (groesse: Size(448, 997.3), schrift: 2.0),
  'Tab A11 (800 dp)': (groesse: Size(800, 1280), schrift: 1.0),
};

final _user = User(
  id: 13,
  mitgliedernummer: 'M10002',
  email: 'alexandra.musterfrau-schmidt@icd360s.de',
  name: 'Alexandra Katharina Musterfrau-Schmidt',
  vorname: 'Alexandra Katharina',
  nachname: 'Musterfrau-Schmidt',
  status: 'aktiv',
  role: 'mitglied',
  preferredLanguage: 'de',
);

http.Client _mock() => MockClient((anfrage) async {
      // ⚠️ Ein einziges Antwortschema reicht nicht: manche Bildschirme
      // greifen mit `r['data']['bewerbungen']` zu (dann muss `data` ein
      // Objekt sein), andere casten `r['data'] as List` (dann eine Liste).
      // Beides zugleich geht nicht — also nach Endpunkt entscheiden.
      final pfad = anfrage.url.path.toLowerCase();
      // ⚠️ Ausgemessen, nicht geraten: `sendungsverfolgung` macht
      // `List.from(result['data'])`, `arbeitgeber_bewerbungsuebersicht`
      // dagegen `result['data']['bewerbungen']`. Beides aus einem Schema zu
      // bedienen geht nicht — die Liste ist der Normalfall, das Objekt die
      // Ausnahme für genau die Endpunkte, die verschachtelt zugreifen.
      final alsObjekt =
          pfad.contains('bewerbung') || pfad.contains('korrespondenz');
      return http.Response(
        jsonEncode({
          'success': true,
          'data': alsObjekt
              ? <String, dynamic>{
                  'bewerbungen': [],
                  'eintraege': [],
                  'message': <String, dynamic>{'body_html': '', 'body_text': ''},
                }
              : [],
          'items': [],
          'vorfaelle': [],
          'termine': [],
          'tickets': [],
          'institutionen': [],
          'message': '',
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

/// Baut auf, tippt sich durch **alle** Reiter und sammelt dabei jeden
/// Layout-Fehler — mit dem Reiter, bei dem er auftrat.
Future<List<String>> reiterDurchgehen(
  WidgetTester tester,
  Size groesse,
  double schrift,
  Widget Function() bauen,
) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = groesse * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final gesammelt = <String>[];
  var reiter = 0;
  final vorher = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.exceptionAsString();
    if (text.contains('overflowed') || text.contains('RenderFlex')) {
      final ort = RegExp(r'lib/[\w/]+\.dart:\d+:\d+')
              .firstMatch(details.toString())
              ?.group(0) ??
          'Ort unbekannt';
      final zeile = '${text.split('\n').first}  ← $ort  [Reiter $reiter]';
      if (!gesammelt.contains(zeile)) gesammelt.add(zeile);
    }
  };

  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: groesse,
        devicePixelRatio: 3,
        textScaler: TextScaler.linear(schrift),
      ),
      child: Scaffold(body: bauen()),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 50));

  // Alle Reiter der Reihe nach antippen. `warnIfMissed: false`, weil ein
  // Reiter am Rand einer scrollbaren Leiste teilweise verdeckt sein kann —
  // gezeichnet wird er trotzdem, und darum geht es hier.
  final tabs = find.byType(Tab);
  final anzahl = tabs.evaluate().length;
  for (var i = 1; i < anzahl; i++) {
    reiter = i;
    try {
      await tester.tap(tabs.at(i), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
    } catch (_) {
      // Ein Reiter, der sich nicht antippen lässt, ist kein Layout-Befund.
    }
  }

  await tester.pump(const Duration(seconds: 16));
  FlutterError.onError = vorher;
  tester.takeException();
  return gesammelt;
}

void main() {
  setUpAll(() {
    DeviceKeyService().setTestCredentials('TEST-KEY');
    ApiService().testClient = _mock();
  });
  tearDownAll(() => DeviceKeyService().setTestCredentials(null));

  final api = ApiService();
  final tickets = TicketService();
  final termine = TerminService();

  // Die Bildschirme mit den meisten Reitern — dort ist am meisten ungeprüft.
  final faelle = <String, Widget Function()>{
    'Jobcenter': () => BehordeJobcenterContent(apiService: api, userId: 13),
    'WBS': () => BehordeWbsContent(apiService: api, userId: 13),
    'Konsulat': () => BehordeKonsulatContent(apiService: api, userId: 13),
    'Reparatur': () => ReparaturContent(apiService: api, userId: 13),
    'Gesundheit': () => GesundheitTabContent(
          user: _user,
          apiService: api,
          ticketService: tickets,
          terminService: termine,
          adminMitgliedernummer: 'V10001',
        ),
    'Behörden': () => BehoerdeTabContent(
          user: _user,
          apiService: api,
          ticketService: tickets,
          terminService: termine,
          adminMitgliedernummer: 'V10001',
        ),
    'Ärzte Augenarzt': () => MitgliederverwaltungArztenAugenarzt(
          user: _user,
          apiService: api,
          ticketService: tickets,
          terminService: termine,
          adminMitgliedernummer: 'V10001',
        ),
    'Ärzte HNO': () => MitgliederverwaltungArztenHno(
          user: _user,
          apiService: api,
          ticketService: tickets,
          terminService: termine,
          adminMitgliedernummer: 'V10001',
        ),
    'Ärzte Krankenhaus': () => MitgliederverwaltungArztenKrankenhaus(
          user: _user,
          apiService: api,
          ticketService: tickets,
          terminService: termine,
          adminMitgliedernummer: 'V10001',
        ),
    'Ärzte MD': () => MitgliederverwaltungArztenMd(
          user: _user,
          apiService: api,
          ticketService: tickets,
          terminService: termine,
          adminMitgliedernummer: 'V10001',
        ),
    'Ärzte Rheumatologie': () => MitgliederverwaltungArztenRheumatologie(
          user: _user,
          apiService: api,
          ticketService: tickets,
          terminService: termine,
          adminMitgliedernummer: 'V10001',
        ),
  };

  _groessen.forEach((groessenName, lage) {
    group('Alle Reiter bei $groessenName', () {
      faelle.forEach((name, bauen) {
        testWidgets(name, (tester) async {
          final fehler = await reiterDurchgehen(
              tester, lage.groesse, lage.schrift, bauen);
          expect(fehler, isEmpty,
              reason: '$name bei $groessenName:\n${fehler.join("\n")}');
        });
      });
    });
  });
}
