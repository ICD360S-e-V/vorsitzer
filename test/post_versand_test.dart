import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icd360sev_vorsitzer/screens/post_screen.dart';
import 'package:icd360sev_vorsitzer/services/api_service.dart';
import 'package:icd360sev_vorsitzer/services/device_key_service.dart';

/// Echte Antworten von api/vereinverwaltung/letterxpress_manage.php,
/// aufgezeichnet am 16.08.2026 gegen den laufenden Server (Loopback, durch
/// nginx und PHP-FPM, also durch die komplette Anmeldung).
///
/// ⚠️ Der Sinn ist NICHT, die Zahlen zu prüfen, sondern die FORM. PHP kennt
/// nur einen Array-Typ: `['a'=>1]` kodiert `json_encode` als Objekt, `[]`
/// dagegen als Liste. Ein `as Map` auf einer Liste liefert nicht null,
/// sondern wirft — genau daran blieb der Speedtest-Bildschirm am 05.08.2026
/// in der Produktion als graue Fläche hängen. Weder `flutter analyze` noch
/// die üblichen Widget-Tests sehen das, weil keiner davon die echte
/// Serverantwort anfasst.

/// Kein Zugang hinterlegt, leeres Protokoll. `sendungen` ist hier eine LISTE.
const String _getAllLeer =
    r'''{"success":true,"zugang":{"benutzername":"","apikey_gesetzt":false,"betriebsart":"test","eingerichtet":false},"guthaben":null,"waehrung":"EUR","verbunden":false,"fehler":"","storno_min":15,"sendungen":[]}''';

/// Protokoll mit zwei Zeilen: ein frischer Testauftrag (stornierbar) und ein
/// gescheiterter Live-Versand ohne Auftragsnummer (nicht stornierbar).
const String _getAllVoll =
    r'''{"success":true,"zugang":{"benutzername":"","apikey_gesetzt":false,"betriebsart":"test","eingerichtet":false},"guthaben":null,"waehrung":"EUR","verbunden":false,"fehler":"","storno_min":15,"sendungen":[{"id":4,"auftrag_id":null,"betriebsart":"live","status":"fehler","seiten":1,"preis":null,"farbe":"4","duplex":false,"versandart":"international","einschreiben":null,"empfaenger":"","dateiname":"Kuendigung.pdf","notiz":"","fehler_text":"Insufficient credit","erstellt_am":"2026-08-16 23:45:15","stornierbar":false},{"id":3,"auftrag_id":6035143,"betriebsart":"test","status":"draft","seiten":2,"preis":0.94,"farbe":"1","duplex":true,"versandart":"national","einschreiben":null,"empfaenger":"Jim Knopf, Bahnhofstr. 1, 21337 Lüneburg","dateiname":"Widerspruch.pdf","notiz":"Probe","fehler_text":"","erstellt_am":"2026-08-16 23:45:15","stornierbar":true}]}''';

/// Eingerichtet, verbunden und SCHARF — der Zustand, der auf dem Schirm
/// unübersehbar sein muss.
const String _getAllLive =
    r'''{"success":true,"zugang":{"benutzername":"icd360sev","apikey_gesetzt":true,"betriebsart":"live","eingerichtet":true},"guthaben":54.89,"waehrung":"EUR","verbunden":true,"fehler":"","storno_min":15,"sendungen":[]}''';

/// Gültiges A4-PDF, aber ohne LXP-Zugang gibt es keinen Preis.
const String _pruefenOk =
    r'''{"success":true,"pdf":{"ok":true,"fehler":"","seiten":1,"format":"595 x 842 pt"},"preis":null,"betriebsart":"test","preis_fehler":""}''';

const String _pruefenQuer =
    r'''{"success":false,"message":"Das PDF ist A4 quer. LetterXpress druckt nur A4 hoch.","pdf":{"ok":false,"fehler":"Das PDF ist A4 quer. LetterXpress druckt nur A4 hoch.","seiten":1,"format":"842 x 595 pt"},"preis":null,"betriebsart":"test","preis_fehler":""}''';

const String _pruefenKeinPdf =
    r'''{"success":false,"message":"Das ist keine PDF-Datei","pdf":{"ok":false,"fehler":"Das ist keine PDF-Datei","seiten":0,"format":""},"preis":null,"betriebsart":"test","preis_fehler":""}''';

const String _sendenOhneZugang =
    r'''{"success":false,"message":"Kein LetterXpress-Zugang hinterlegt"}''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Form der echten Serverantwort', () {
    test('leeres Protokoll kommt als LISTE an und wirft nicht', () {
      final r = jsonDecode(_getAllLeer) as Map<String, dynamic>;
      // Genau der Fall, der den Speedtest-Bildschirm grau werden ließ.
      expect(r['sendungen'], isA<List<dynamic>>());
      expect(postListe(r['sendungen']), isEmpty);
      expect(postAlsMap(r['zugang'])!['eingerichtet'], isFalse);
      expect(r['storno_min'], 15);
    });

    test('gefülltes Protokoll wird vollständig gelesen', () {
      final r = jsonDecode(_getAllVoll) as Map<String, dynamic>;
      final s = postListe(r['sendungen']);
      expect(s, hasLength(2));

      // Neueste zuerst — der gescheiterte Live-Versand.
      expect(s.first['betriebsart'], 'live');
      expect(s.first['status'], 'fehler');
      expect(s.first['auftrag_id'], isNull);
      expect(s.first['fehler_text'], 'Insufficient credit');
      // Ohne Auftragsnummer gibt es nichts zu stornieren, und der Server sagt
      // das auch — die Oberfläche darf keinen Knopf anbieten, der sicher
      // scheitert.
      expect(s.first['stornierbar'], isFalse);

      expect(s.last['auftrag_id'], 6035143);
      expect(s.last['preis'], 0.94);
      expect(s.last['duplex'], isTrue);
      expect(s.last['stornierbar'], isTrue);
      // Umlaute überleben den ganzen Weg: GCM-Verschlüsselung in der DB,
      // Entschlüsselung in PHP, \u-Escape im JSON.
      expect(s.last['empfaenger'], 'Jim Knopf, Bahnhofstr. 1, 21337 Lüneburg');
    });

    test('der API-Key kommt NIE mit', () {
      for (final roh in [_getAllLeer, _getAllVoll, _getAllLive]) {
        final z = postAlsMap((jsonDecode(roh) as Map)['zugang'])!;
        expect(z.containsKey('apikey'), isFalse);
        expect(z.containsKey('apikey_klartext'), isFalse);
        expect(z.containsKey('apikey_gesetzt'), isTrue);
      }
    });

    test('pdf-Block ist ein Objekt, auch wenn die Prüfung scheitert', () {
      for (final roh in [_pruefenOk, _pruefenQuer, _pruefenKeinPdf]) {
        final p = postAlsMap((jsonDecode(roh) as Map)['pdf']);
        expect(p, isNotNull, reason: 'pdf muss ein Objekt bleiben: $roh');
        expect(p!.containsKey('ok'), isTrue);
      }
      expect(postAlsMap(jsonDecode(_pruefenQuer)['pdf'])!['format'], '842 x 595 pt');
      expect(postAlsMap(jsonDecode(_pruefenKeinPdf)['pdf'])!['seiten'], 0);
    });

    test('eine Antwort ganz ohne pdf-Block wirft nicht', () {
      final r = jsonDecode(_sendenOhneZugang) as Map<String, dynamic>;
      expect(postAlsMap(r['pdf']), isNull);
      expect(postListe(r['sendungen']), isEmpty);
    });
  });

  group('Einschreiben nur im Inland', () {
    test('Auslandsversand streicht das Einschreiben', () {
      // LetterXpress lehnt die Kombination ab — aber erst beim Senden, also
      // nachdem der Mensch schon bestätigt hat.
      expect(postEinschreibenBereinigen('r1', 'international'), isNull);
      expect(postEinschreibenBereinigen('r2', 'international'), isNull);
    });

    test('im Inland bleibt es erhalten', () {
      expect(postEinschreibenBereinigen('r1', 'national'), 'r1');
      expect(postEinschreibenBereinigen('r2', 'auto'), 'r2');
    });

    test('unbekannte Werte werden verworfen', () {
      expect(postEinschreibenBereinigen('r9', 'national'), isNull);
      expect(postEinschreibenBereinigen(null, 'national'), isNull);
      expect(postEinschreibenBereinigen('-', 'national'), isNull);
    });
  });

  group('Bildschirm', () {
    late List<String> gerufeneAktionen;

    void serverAntwortetMit(String antwort) {
      gerufeneAktionen = [];
      ApiService().testClient = MockClient((req) async {
        final koerper = jsonDecode(req.body) as Map<String, dynamic>;
        gerufeneAktionen.add(koerper['action'] as String);
        return http.Response(antwort, 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      });
    }

    setUp(() {
      DeviceKeyService().setTestCredentials('TESTKEY');
    });

    Future<void> oeffne(WidgetTester tester) async {
      // ⚠️ Die Standardfläche im Test ist 800×600. Der Bildschirm ist eine
      // ListView, die nur baut, was sichtbar ist — das Versandprotokoll steht
      // ganz unten und existiert bei 600 dp Höhe schlicht nicht. Ein
      // `findsNothing` darauf wäre grün, ohne irgendetwas zu beweisen.
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: PostScreen(apiService: ApiService()),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('ohne Zugang wird nur die Einrichtung angeboten', (tester) async {
      serverAntwortetMit(_getAllLeer);
      await oeffne(tester);

      expect(gerufeneAktionen, contains('get_all'),
          reason: 'Ohne Serverabfrage prüft der Test nichts.');
      expect(find.text('Noch kein LetterXpress-Zugang hinterlegt'), findsOneWidget);
      // Solange kein Zugang da ist, gibt es keinen Versandkasten — ein
      // Sendeknopf, der sicher scheitert, ist schlimmer als keiner.
      expect(find.text('Neuer Brief'), findsNothing);
      expect(find.text('Noch nichts verschickt.'), findsOneWidget);
    });

    testWidgets('der scharfe Modus ist unübersehbar', (tester) async {
      serverAntwortetMit(_getAllLive);
      await oeffne(tester);

      expect(find.text('SCHARF — Briefe gehen wirklich raus'), findsOneWidget);
      expect(find.text('Guthaben: 54.89 €'), findsOneWidget);
      expect(find.text('Neuer Brief'), findsOneWidget);
      expect(find.text('Scharf verschicken'), findsOneWidget);
      // Im Testmodus hieße der Knopf anders — wer nur auf die Form des Knopfes
      // schaut, muss den Unterschied sehen.
      expect(find.text('Testauftrag übertragen'), findsNothing);
    });

    testWidgets('der Testmodus sagt, dass nichts rausgeht', (tester) async {
      serverAntwortetMit(_getAllLive.replaceAll('"live"', '"test"'));
      await oeffne(tester);

      expect(find.text('Testmodus — Aufträge landen nur in der Postbox'), findsOneWidget);
      expect(find.text('Testauftrag übertragen'), findsOneWidget);
      expect(find.text('Scharf verschicken'), findsNothing);
    });

    testWidgets('das Protokoll zeigt Empfänger, Fehler und den Storno-Knopf',
        (tester) async {
      serverAntwortetMit(_getAllVoll);
      await oeffne(tester);

      expect(find.text('Jim Knopf, Bahnhofstr. 1, 21337 Lüneburg'), findsOneWidget);
      // Die gescheiterte Zeile hat keinen Empfänger — dann muss der Dateiname
      // einspringen, sonst steht dort eine leere Zeile.
      expect(find.text('Kuendigung.pdf'), findsOneWidget);
      expect(find.textContaining('Insufficient credit'), findsOneWidget);
      // Genau ein Storno-Knopf: nur die stornierbare Zeile bekommt einen.
      expect(find.text('Storno'), findsOneWidget);
    });

    testWidgets('ein Serverfehler beim Laden wird gezeigt, nicht verschluckt',
        (tester) async {
      serverAntwortetMit(r'''{"success":false,"message":"Serverfehler: Zugangsdaten nicht entschluesselbar"}''');
      await oeffne(tester);

      expect(find.textContaining('Zugangsdaten nicht entschluesselbar'), findsOneWidget);
    });
  });
}
