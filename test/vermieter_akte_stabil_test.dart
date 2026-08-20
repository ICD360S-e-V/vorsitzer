import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icd360sev_vorsitzer/services/api_service.dart';
import 'package:icd360sev_vorsitzer/services/device_key_service.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_vermieter.dart';

/// Die Akte eines Vermieters darf sich nicht selbst abräumen.
///
/// Der Fehler, den dieser Test festhält, war am Gerät als Flackern zu sehen:
/// beim Tippen auf einen Vermieter erschien die Akte und verschwand sofort
/// wieder, „bis sie sich nach ein paar Klicks beruhigt". Es war keine
/// Klick-Frage, sondern eine Endlosschleife — die Akte meldete nach jedem
/// Laden an die Liste zurück, die Liste setzte dabei ihre Ladeanzeige und
/// ersetzte damit die Akte, die daraufhin neu gebaut wurde und wieder lud.
///
/// ⚠️ `pumpAndSettle` taugt hier NICHT als Nachweis, obwohl es nahe liegt.
/// Es hört auf, sobald ein Durchlauf keinen weiteren Rahmen anfordert — und
/// während der Wartezeit auf eine Antwort ist genau das der Fall. Es kehrt
/// mitten in der Schleife zufrieden zurück. Nachgewiesen wird der Fehler
/// deshalb anders: eine feste Zeit lang pumpen und die AUFRUFE ZÄHLEN.
/// Läuft die Schleife, sind es Dutzende statt einem.
void main() {
  int aufrufeListe = 0;
  int aufrufeAkte = 0;

  // ⚠️ Die Verzögerung ist der Kern dieses Tests, keine Zierde.
  //
  // Ohne sie antwortet der Mock im selben Microtask-Durchlauf: `_laedt`
  // geht true → false, bevor überhaupt ein Rahmen gebaut wird. Die
  // Ladeanzeige erscheint nie, die Akte wird nie abgeräumt — und der
  // Fehler ist unsichtbar. Genau das ist passiert: die erste Fassung
  // dieses Tests lief auch mit wieder eingebautem Fehler grün durch.
  // Auf dem Gerät dauert eine Antwort zig Millisekunden, dort wird
  // sehr wohl ein Rahmen mit Ladeanzeige gebaut.
  http.Client mandant() => MockClient((anfrage) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final pfad = anfrage.url.path;
        final koerper = anfrage.body.isEmpty
            ? const <String, dynamic>{}
            : (jsonDecode(anfrage.body) as Map<String, dynamic>);
        final aktion = koerper['action']?.toString() ?? anfrage.url.queryParameters['action'] ?? '';

        if (pfad.endsWith('vermieter_manage.php')) {
          if (aktion == 'all') {
            aufrufeAkte++;
            return http.Response(
                jsonEncode({
                  'success': true,
                  'data': <String, dynamic>{},
                  'vermieter': _zweiVermieter,
                  'mietvertraege': const [],
                  'bescheinigungen': const [],
                  'zahlungen': const [],
                }),
                200);
          }
          if (aktion == 'list_vermieter') {
            aufrufeListe++;
            return http.Response(
                jsonEncode({'success': true, 'vermieter': _zweiVermieter}), 200);
          }
          return http.Response(jsonEncode({'success': true}), 200);
        }
        // Inkasso, Anhänge und alles Übrige antworten leer, aber gültig.
        return http.Response(jsonEncode({'success': true, 'items': const []}), 200);
      });

  setUp(() {
    aufrufeListe = 0;
    aufrufeAkte = 0;
    DeviceKeyService().setTestCredentials('TEST-KEY');
    ApiService().testClient = mandant();
  });
  tearDown(() => DeviceKeyService().setTestCredentials(null));

  /// Pumpt eine feste Spanne ab, ohne auf Ruhe zu warten.
  ///
  /// ⚠️ Die Schrittweite muss KLEINER sein als die Antwortzeit des Mocks
  /// (20 ms). Mit groesseren Schritten springt die Uhr ueber die ganze
  /// Anfrage hinweg: `_laedt` geht innerhalb EINES Schrittes true → false,
  /// es wird nie ein Rahmen mit Ladeanzeige gebaut, und der Fehler bleibt
  /// unsichtbar. Auch das ist hier schon passiert — mit 50-ms-Schritten
  /// lief der Test mit eingebautem Fehler gruen durch.
  Future<void> laufenLassen(WidgetTester tester,
      {Duration spanne = const Duration(seconds: 2)}) async {
    const schritt = Duration(milliseconds: 5);
    final schritte = spanne.inMilliseconds ~/ schritt.inMilliseconds;
    for (var i = 0; i < schritte; i++) {
      await tester.pump(schritt);
    }
  }

  Future<void> zeigen(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      home: Scaffold(
        body: BehordeVermieterContent(apiService: ApiService(), userId: 13),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('beide Vermieter stehen in der Liste', (tester) async {
    await zeigen(tester);
    expect(find.text('Musterverwaltung Nord'), findsOneWidget);
    expect(find.text('Privatvermieter Süd'), findsOneWidget);
    expect(find.textContaining('Zuständige Vermieter (2)'), findsOneWidget);
  });

  testWidgets('die geöffnete Akte bleibt stehen — kein Flackern', (tester) async {
    await zeigen(tester);
    await tester.tap(find.text('Musterverwaltung Nord'));
    await laufenLassen(tester);

    // Der Kopf der Akte trägt den Namen, und der Details-Reiter ist da —
    // beides war am Gerät genau das, was fehlte.
    expect(find.text('Musterverwaltung Nord'), findsWidgets);
    expect(find.text('Details'), findsOneWidget);
    expect(find.text('Mietvertrag'), findsOneWidget);
    // Der Inhalt des Details-Reiters, nicht nur seine Beschriftung.
    expect(find.text('Musterstraße 1, 89073 Ulm'), findsOneWidget);

    // ⚠️ Und das Gegenstück: seit 20.08.2026 hängt alles am MIETVERTRAG.
    // Stünden diese Reiter wieder beim Vermieter, wäre die Trennung
    // zwischen zwei Wohnungen desselben Vermieters still zurückgedreht —
    // ohne dass irgendetwas rot würde.
    expect(find.text('Inkasso'), findsNothing);
    expect(find.text('Korrespondenz'), findsNothing);
    expect(find.text('Akteneinsicht'), findsNothing);
    expect(find.text('Zahlungen'), findsNothing);
  });

  testWidgets('das Nachladen der Zähler ruft die Liste genau einmal', (tester) async {
    await zeigen(tester);
    final vorherListe = aufrufeListe;
    await tester.tap(find.text('Musterverwaltung Nord'));
    await laufenLassen(tester);

    // Die Akte lädt ihre eigenen Listen (1×) und meldet einmal zurück,
    // damit die Zähler stimmen. Mehr darf es nicht sein: jede weitere
    // Runde wäre der Anfang derselben Schleife. Mit dem Fehler standen
    // hier zweistellige Zahlen — zwei Sekunden reichen für Dutzende
    // Umläufe.
    expect(aufrufeAkte, 1, reason: 'die Akte lädt sich selbst neu');
    expect(aufrufeListe - vorherListe, 1, reason: 'die Liste wird endlos aufgefrischt');
  });

  testWidgets('zurück führt wieder auf die Liste', (tester) async {
    await zeigen(tester);
    await tester.tap(find.text('Musterverwaltung Nord'));
    await laufenLassen(tester);
    await tester.tap(find.byTooltip('Zurück zur Vermieterliste'));
    await laufenLassen(tester, spanne: const Duration(milliseconds: 500));
    expect(find.textContaining('Zuständige Vermieter (2)'), findsOneWidget);
    expect(find.text('Details'), findsNothing);
  });
}

const _zweiVermieter = [
  {
    'id': 1,
    'name': 'Musterverwaltung Nord',
    'strasse': 'Musterstraße 1',
    'plz': '89073',
    'ort': 'Ulm',
    'telefon': '',
    'email': '',
    'website': '',
    'typ': 'Hausverwaltung',
    'notiz': '',
    'status': 'aktiv',
    'sortierung': 0,
    'vermieter_db_id': null,
    'counts': {
      'mietvertraege': 1,
      'bescheinigungen': 0,
      'zahlungen': 0,
      'korrespondenz': 0,
      'vorfaelle': 0,
    },
  },
  {
    'id': 2,
    'name': 'Privatvermieter Süd',
    'strasse': '',
    'plz': '',
    'ort': 'Neu-Ulm',
    'telefon': '',
    'email': '',
    'website': '',
    'typ': '',
    'notiz': '',
    'status': 'ehemalig',
    'sortierung': 0,
    'vermieter_db_id': null,
    'counts': {
      'mietvertraege': 0,
      'bescheinigungen': 0,
      'zahlungen': 0,
      'korrespondenz': 0,
      'vorfaelle': 0,
    },
  },
];
