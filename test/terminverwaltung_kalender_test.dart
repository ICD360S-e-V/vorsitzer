// Die Termine waren unsichtbar, obwohl der Server sie lieferte.
//
// Ursache war kein Datenfehler: #197 legte den Bildschirm in einen
// `SingleChildScrollView`, sein `Expanded`-Kind bekam damit UNBEGRENZTE Höhe
// und warf „RenderFlex children have non-zero flex but incoming height
// constraints are unbounded". Die Column bekam keine Größe — im Release-Build
// heißt das: kein Kalender, keine Meldung, nur Fläche.
//
// ⚠️ Der Prüfstand, der genau diesen Fehler findet
// (`aufloesung_dienste_test.dart`), hatte `TerminverwaltungScreen`
// ausgenommen — mit der Begründung, `TerminService` habe keine Mock-Naht.
// Die Naht gibt es jetzt, die Ausnahme ist weg.
//
// Dieser Test prüft die andere Hälfte, die ein Überlauf-Prüfstand nicht
// abdeckt: dass ein gelieferter Termin auch wirklich GEZEICHNET wird. Ein
// leerer Kalender wirft nicht — er schweigt.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:icd360sev_vorsitzer/screens/terminverwaltung_screen.dart';
import 'package:icd360sev_vorsitzer/services/api_service.dart';
import 'package:icd360sev_vorsitzer/services/device_key_service.dart';
import 'package:icd360sev_vorsitzer/services/termin_service.dart';
import 'package:icd360sev_vorsitzer/services/ticket_service.dart';

/// Montag der laufenden Woche — genau die Woche, die der Bildschirm beim
/// Start zeigt. Ein fest verdrahtetes Datum wäre nach sieben Tagen außerhalb
/// des Rasters und der Test grün, ohne etwas zu prüfen.
DateTime _wochenStart() {
  final jetzt = DateTime.now();
  return DateTime(jetzt.year, jetzt.month, jetzt.day)
      .subtract(Duration(days: jetzt.weekday - 1));
}

/// Ein Termin am Mittwoch um 14:00 — innerhalb des Rasters, das nur 8 bis 18
/// Uhr zeichnet. 07:00 oder 21:00 wären unsichtbar, ohne dass etwas kaputt
/// wäre; solche Randfälle gehören nicht in einen Regressionstest für „der
/// Kalender zeichnet überhaupt".
Map<String, dynamic> _termin(String titel) {
  final wann = _wochenStart().add(const Duration(days: 2, hours: 14));
  String z(int n) => n.toString().padLeft(2, '0');
  final stempel =
      '${wann.year}-${z(wann.month)}-${z(wann.day)} ${z(wann.hour)}:${z(wann.minute)}:00';
  return {
    'id': 4711,
    'title': titel,
    'category': 'sonstiges',
    'description': '',
    'termin_date': stempel,
    'duration_minutes': 60,
    'location': 'Neu-Ulm',
    'created_by': 2,
    'created_by_name': 'Ionut Duinea',
    'braucht_mich': 1,
    'is_notfall': 0,
    'status': 'scheduled',
    'created_at': stempel,
    'updated_at': stempel,
    'total_participants': 1,
    'confirmed_count': 1,
    'declined_count': 0,
    'pending_count': 0,
  };
}

http.Client _mock(List<Map<String, dynamic>> termine) =>
    MockClient((anfrage) async => http.Response(
          jsonEncode({
            'success': true,
            'data': [],
            'termine': termine,
            'urlaub': [],
            'feiertage': [],
            'users': [],
            'tickets': [],
            'items': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ));

Future<List<String>> _bauen(
  WidgetTester tester, {
  required List<Map<String, dynamic>> termine,
  Size groesse = const Size(1280, 900),
  double schrift = 1.0,
}) async {
  SharedPreferences.setMockInitialValues({});
  DeviceKeyService().setTestCredentials('TEST-KEY');
  ApiService().testClient = _mock(termine);
  TicketService().testClient = _mock(termine);
  TerminService().testClient = _mock(termine);
  addTearDown(() => DeviceKeyService().setTestCredentials(null));

  tester.view.physicalSize = groesse * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final fehler = <String>[];
  final vorher = FlutterError.onError;
  FlutterError.onError = (details) => fehler.add(details.exceptionAsString());

  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: groesse,
        devicePixelRatio: 3,
        textScaler: TextScaler.linear(schrift),
      ),
      child: const Scaffold(
        body: TerminverwaltungScreen(currentMitgliedernummer: 'V27655'),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(seconds: 16));

  FlutterError.onError = vorher;
  tester.takeException();
  return fehler;
}

void main() {
  testWidgets('das Wochenraster wird überhaupt aufgebaut', (tester) async {
    final fehler = await _bauen(tester, termine: []);

    expect(fehler, isEmpty, reason: fehler.join('\n'));
    // Die Stundenspalte ist der Beweis, dass das Raster Größe bekommen hat.
    // Ohne sie hing der Fehler an der unbegrenzten Höhe.
    expect(find.text('Uhr'), findsOneWidget);
    expect(find.text('13'), findsOneWidget);
  });

  testWidgets('ein gelieferter Termin erscheint im Raster', (tester) async {
    final fehler = await _bauen(tester, termine: [_termin('Orthopaede-Termin')]);

    expect(fehler, isEmpty, reason: fehler.join('\n'));
    expect(find.textContaining('Orthopaede-Termin'), findsWidgets,
        reason: 'Der Server liefert den Termin — gezeichnet wurde er nicht.');
  });

  testWidgets('kein unbegrenzter Flex — auch bei Systemschrift 2,0',
      (tester) async {
    // Die Schriftgröße ist der Fall, an dem die feste Zeilenhöhe von 56 dp
    // zerbrach: Zahl und Symbol der 12-Uhr-Beschriftung liefen um 38 px
    // heraus. Android erlaubt 2,0, die App setzt keinen eigenen textScaler.
    final fehler = await _bauen(
      tester,
      termine: [_termin('Orthopaede-Termin')],
      groesse: const Size(448, 998),
      schrift: 2.0,
    );

    expect(fehler, isEmpty, reason: fehler.join('\n'));
  });
}
