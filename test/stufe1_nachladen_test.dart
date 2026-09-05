// Verifizierung ▸ Stufe 1: das Formular muss den Datensatz vom Server zeigen,
// nicht das halbe Objekt, mit dem der Dialog geöffnet wurde.
//
// Anlass ist ein realer Fall vom 16.08.2026: ein fünfjähriges Kind (J19999)
// unter dem Konto der Mutter. Wer es über den Familien-Auswähler öffnete,
// bekam ein LEERES Stufe-1-Formular — Adresse, Geschlecht, Staatsangehörigkeit,
// Aufenthaltsstatus und Muttersprache standen längst in der Datenbank. Trug
// der Vorstand sie ein und speicherte, sah er beim nächsten Öffnen wieder
// nichts: gespeichert wurde tatsächlich, angezeigt wurde nie.
//
// Die Ursache lag an zwei Stellen gleichzeitig:
//   1. `_FamilieEntry.toUser()` baute aus dem Kind-Eintrag einen `User` mit
//      neun Feldern; alles Übrige war null.
//   2. `_loadUserDetails()` warf `result['user']` weg und las nur `sessions`
//      und `devices` — der vollständige Datensatz kam also an und wurde nicht
//      benutzt.
//
// Der zweite Punkt ist der gefährliche: solange das Formular leer aussieht,
// schickt „Speichern" für Geschlecht und Staatsangehörigkeit trotzdem Werte
// mit, weil beide Felder vorbelegt waren ('M' und 'deutsch'). Aus einem
// ukrainischen Kind wurde so ein deutsches.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';
import 'package:icd360sev_vorsitzer/models/user.dart';
import 'package:icd360sev_vorsitzer/services/api_service.dart';
import 'package:icd360sev_vorsitzer/services/device_key_service.dart';
import 'package:icd360sev_vorsitzer/utils/anredeform.dart';
import 'package:icd360sev_vorsitzer/widgets/user_details_dialog.dart';

/// Der Datensatz, wie ihn `user_details.php` für das Kind liefert.
const _kindAufDemServer = {
  'id': 54,
  'mitgliedernummer': 'J19999',
  'email': 'kind-j23960@verwaltet.icd360sev.local',
  'name': 'mykhailo tsynhalov',
  'vorname': 'mykhailo',
  'nachname': 'tsynhalov',
  'role': 'jugendmitglied',
  'status': 'active',
  'geburtsdatum': '2021-05-27',
  'geschlecht': 'M',
  'familienstand': 'ledig',
  'staatsangehoerigkeit': 'ukrainisch',
  'muttersprache': 'Ukrainisch',
  'preferred_language': 'uk',
  'aufenthaltsstatus': 'Aufenthaltserlaubnis § 24 AufenthG (Ukraine-Vertriebene)',
  'strasse': 'Gutenbergstr.',
  'hausnummer': '1',
  'plz': '89155',
  'ort': 'Erbach',
  'telefon_mobil': null,
  'telefon_fix': null,
};

/// So kam das Kind bisher im Dialog an: neun Felder aus der `kinder`-Liste.
User _kindWieUebergeben() => User.fromJson({
      'id': 54,
      'mitgliedernummer': 'J19999',
      'email': 'kind-j23960@verwaltet.icd360sev.local',
      'name': 'mykhailo tsynhalov',
      'vorname': 'mykhailo',
      'nachname': 'tsynhalov',
      'role': 'jugendmitglied',
      'status': 'active',
      'geburtsdatum': '2021-05-27',
    });

/// Antwortet auf alles mit etwas Unverfänglichem; nur `user_details.php`
/// liefert den echten Datensatz. Der Dialog stößt beim Öffnen rund ein Dutzend
/// Ladevorgänge an — die dürfen hier ins Leere laufen, ohne den Test zu stören.
class _ServerAttrappe extends http.BaseClient {
  int userDetailsAufrufe = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final pfad = request.url.path;
    Map<String, dynamic> antwort = {'success': true, 'data': []};

    if (pfad.endsWith('/admin/user_details.php')) {
      userDetailsAufrufe++;
      antwort = {
        'success': true,
        'user': _kindAufDemServer,
        'sessions': <dynamic>[],
        'devices': <dynamic>[],
        'vormund': null,
        'kinder': <dynamic>[],
      };
    } else if (pfad.endsWith('/admin/verifizierung_list.php')) {
      // Ohne Stufen zeigt der Reiter nur „Keine Verifizierungsdaten geladen" —
      // dann gäbe es gar kein Stufe-1-Formular zu prüfen.
      antwort = {
        'success': true,
        'stages': [
          {'stufe': 1, 'status': 'offen'},
        ],
        'document_acceptances': <String, dynamic>{},
      };
    } else if (pfad.endsWith('/admin/staatsangehoerigkeiten_list.php')) {
      antwort = {
        'success': true,
        'data': [
          {'bezeichnung': 'deutsch', 'kontinent': 'Europa'},
          {'bezeichnung': 'ukrainisch', 'kontinent': 'Europa'},
        ],
      };
    }

    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(antwort))),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

Future<void> _oeffneDialog(WidgetTester tester, User user) async {
  // Der Dialog hat 24 Reiter und ein langes Formular — auf der
  // Vorgabefläche von 800x600 wird das meiste nie gebaut.
  tester.view.physicalSize = const Size(1600, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: UserDetailsDialog(
        user: user,
        apiService: ApiService(),
        adminMitgliedernummer: 'V10001',
        onUpdated: () {},
      ),
    ),
  ));
}

/// Liest den Text eines Eingabefeldes anhand seiner Beschriftung in derselben
/// Zeile. Die Stufe-1-Zeilen sind als Row(Label, Feld) gebaut.
String _feldText(WidgetTester tester, String label) {
  final zeile = find.ancestor(of: find.text(label), matching: find.byType(Row)).first;
  final feld = find.descendant(of: zeile, matching: find.byType(TextField));
  return tester.widget<TextField>(feld.first).controller?.text ?? '';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ServerAttrappe server;

  setUpAll(() async {
    // Der Dialog formatiert Datumsangaben auf Deutsch; ohne die Locale-Daten
    // wirft schon der erste Aufbau.
    await initializeDateFormatting('de_DE', null);
    await initializeDateFormatting('de', null);
  });

  setUp(() {
    // Ohne Device-Key wirft `_headers`, bevor je ein Client erreicht wird —
    // der Test wäre grün, ohne irgendetwas geprüft zu haben. Deshalb prüft
    // unten zusätzlich `userDetailsAufrufe`.
    DeviceKeyService().setTestCredentials('TESTKEY');
    server = _ServerAttrappe();
    ApiService().testClient = server;
  });

  group('Stufe 1 lädt den vollständigen Datensatz nach', () {
    testWidgets('Adressfelder erscheinen, obwohl das übergebene Objekt sie nicht hat',
        (tester) async {
      await _oeffneDialog(tester, _kindWieUebergeben());
      await tester.pumpAndSettle();

      expect(server.userDetailsAufrufe, greaterThan(0),
          reason: 'Der Dialog hat den Server nie gefragt — dann prüft der Test nichts.');

      // Zur Verifizierung wechseln und Stufe 1 aufklappen.
      await tester.tap(find.byIcon(Icons.verified_user));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Persönliche Daten').first);
      await tester.pumpAndSettle();

      // Genau die Felder, die im übergebenen Objekt fehlten.
      expect(_feldText(tester, 'Strasse'), 'Gutenbergstr.');
      expect(_feldText(tester, 'Hausnummer'), '1');
      expect(_feldText(tester, 'PLZ'), '89155');
      expect(_feldText(tester, 'Ort'), 'Erbach');
    });

    testWidgets('Staatsangehörigkeit zeigt „ukrainisch", nicht die Vorbelegung „deutsch"',
        (tester) async {
      await _oeffneDialog(tester, _kindWieUebergeben());
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.verified_user));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Persönliche Daten').first);
      await tester.pumpAndSettle();

      // „deutsch" darf nur als Auswahlmöglichkeit im Klappmenü vorkommen,
      // nicht als angezeigter Wert des Feldes.
      final feld = tester.widget<DropdownButtonFormField<String>>(
        find.byWidgetPredicate((w) =>
            w is DropdownButtonFormField<String> && w.initialValue == 'ukrainisch'),
      );
      expect(feld.initialValue, 'ukrainisch');
    });

    testWidgets('Speichern bleibt gesperrt, solange der Datensatz nicht da ist',
        (tester) async {
      await _oeffneDialog(tester, _kindWieUebergeben());
      await tester.pump(); // initState läuft, Antworten stehen noch aus
      await tester.tap(find.byIcon(Icons.verified_user));
      await tester.pump();

      // Die Sperre hängt an `_stufe1Geladen`. Vor der Antwort darf der Knopf
      // nicht auslösen — sonst schreibt er die Vorbelegung fest.
      final knopf = find.widgetWithText(ElevatedButton, 'Speichern');
      if (knopf.evaluate().isNotEmpty) {
        expect(tester.widget<ElevatedButton>(knopf.first).onPressed, isNull,
            reason: 'Vor dem Laden darf Speichern nicht anklickbar sein.');
      }

      await tester.pumpAndSettle();
    });
  });

  group('geschlechtCode', () {
    // Die Datenbank enthält fünf Schreibweisen. Die alte Zeile im Panel war
    // `['M','W','D'].contains(g) ? g : 'M'` — sie machte aus 7 Frauen und
    // 18 Mitgliedern ohne Angabe jeweils „männlich".
    test('erkennt die lange Schreibweise', () {
      expect(geschlechtCode('weiblich'), 'W');
      expect(geschlechtCode('maennlich'), 'M');
      expect(geschlechtCode('männlich'), 'M');
      expect(geschlechtCode('divers'), 'D');
    });

    test('lässt die kurze Schreibweise unverändert', () {
      expect(geschlechtCode('M'), 'M');
      expect(geschlechtCode('W'), 'W');
      expect(geschlechtCode('D'), 'D');
      expect(geschlechtCode('w'), 'W');
    });

    test('fehlende Angabe bleibt leer statt „männlich"', () {
      expect(geschlechtCode(null), '');
      expect(geschlechtCode(''), '');
      expect(geschlechtCode('   '), '');
      expect(geschlechtCode('keine Angabe'), '');
    });
  });
}
