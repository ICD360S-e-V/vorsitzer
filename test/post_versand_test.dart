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

/// Protokoll mit zwei Zeilen: ein Testauftrag MIT archivierter PDF
/// (stornierbar) und ein gescheiterter Live-Versand ohne Auftragsnummer und
/// ohne Archiv (nicht stornierbar).
const String _getAllVoll =
    r'''{"success":true,"zugang":{"benutzername":"","apikey_gesetzt":false,"betriebsart":"test","eingerichtet":false},"guthaben":null,"waehrung":"EUR","verbunden":false,"fehler":"","storno_min":15,"sendungen":[{"id":10,"auftrag_id":null,"betriebsart":"live","status":"fehler","seiten":1,"preis":null,"farbe":null,"duplex":false,"versandart":"national","einschreiben":null,"empfaenger":"","dateiname":"Kuendigung.pdf","notiz":"","fehler_text":"Insufficient credit","erstellt_am":"2026-08-17 08:53:52","hat_dokument":false,"datei_bytes":null,"stornierbar":false},{"id":9,"auftrag_id":6035143,"betriebsart":"test","status":"queue","seiten":1,"preis":0.96,"farbe":"1","duplex":false,"versandart":"national","einschreiben":null,"empfaenger":"Jim Knopf, Bahnhofstr. 1, 21337 Lüneburg","dateiname":"Widerspruch-Jobcenter.pdf","notiz":"","fehler_text":"","erstellt_am":"2026-08-17 08:53:52","hat_dokument":true,"datei_bytes":1356,"stornierbar":true}]}''';

/// Archivierten Brief zurückholen — Base64 hier gekürzt.
const String _dokumentDa =
    r'''{"success":true,"protokoll_id":9,"dateiname":"Widerspruch-Jobcenter.pdf","bytes":1356,"base64_pdf":"JVBERi0xLjcK"}''';

/// Die drei Gründe, aus denen ein Brief NICHT zurückkommt. Sie sind bewusst
/// getrennt: fehlendes Archiv, verlorene Datei und fehlende Leserechte
/// verlangen drei völlig verschiedene Handgriffe.
const String _dokumentKeins =
    r'''{"success":false,"message":"Zu diesem Brief ist keine Datei archiviert"}''';
const String _dokumentUnlesbar =
    r'''{"success":false,"message":"Archivdatei ist fuer den Webnutzer nicht lesbar (Eigentuemer/Rechte pruefen)"}''';
const String _dokumentUnbekannt =
    r'''{"success":false,"message":"Eintrag nicht gefunden"}''';

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
      // ⚠️ BRUTTO. Siehe die Gruppe „Netto und Brutto" weiter unten.
      expect(s.last['preis'], 0.96);
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

  group('Netto und Brutto', () {
    // Gemessen am 17.08.2026 an einem echten Testauftrag gegen das laufende
    // LXP-Konto: /price meldete 0,96 — der angelegte Auftrag meldete
    // amount 0,81 und vat 0,15.
    const preisAbfrage = 0.96; // /price
    const amount = 0.81; // items[].amount
    const vat = 0.15; // items[].vat

    test('/price ist BRUTTO, items[].amount ist NETTO', () {
      expect(amount + vat, closeTo(preisAbfrage, 0.005));
      // Wer amount für den Endpreis hält, zeigt 15 Cent zu wenig an.
      expect(amount, lessThan(preisAbfrage));
    });

    test('das Protokoll zeigt denselben Betrag wie die Bestätigung', () {
      // Der Mensch bestätigt den Preis aus /price. Stünde danach der
      // Nettobetrag im Protokoll, sähe das nach einem Fehler aus — und wer
      // den Zahlen einmal nicht traut, prüft sie auch dann nicht mehr, wenn
      // es darauf ankommt.
      final s = postListe((jsonDecode(_getAllVoll) as Map)['sendungen']);
      expect(s.last['preis'], preisAbfrage);
      expect(s.last['preis'], isNot(amount));
    });
  });

  group('Briefarchiv', () {
    test('das Protokoll sagt je Zeile, ob die PDF noch da ist', () {
      final s = postListe((jsonDecode(_getAllVoll) as Map)['sendungen']);
      // Der gescheiterte Versand hat nichts zu archivieren.
      expect(s.first['hat_dokument'], isFalse);
      expect(s.first['datei_bytes'], isNull);
      // Der übertragene Brief liegt bei uns.
      expect(s.last['hat_dokument'], isTrue);
      expect(s.last['datei_bytes'], 1356);
    });

    test('der zurückgeholte Brief bringt seinen sprechenden Namen mit', () {
      final r = jsonDecode(_dokumentDa) as Map<String, dynamic>;
      // Auf der Platte heißt die Datei Zufall — der ursprüngliche Name liegt
      // verschlüsselt in der Zeile und kommt nur hier heraus.
      expect(r['dateiname'], 'Widerspruch-Jobcenter.pdf');
      expect(r['bytes'], 1356);
      expect((r['base64_pdf'] as String), isNotEmpty);
      // Base64 von "%PDF-1.7\n" — es kommt wirklich ein PDF zurück.
      expect(utf8.decode(base64Decode(r['base64_pdf'] as String)), startsWith('%PDF'));
    });

    test('die drei Fehlergründe bleiben unterscheidbar', () {
      // Ein Sammelgrund wäre beim Suchen wertlos: fehlendes Archiv, verlorene
      // Datei und fehlende Leserechte verlangen drei verschiedene Handgriffe.
      final gruende = [_dokumentKeins, _dokumentUnlesbar, _dokumentUnbekannt]
          .map((j) => (jsonDecode(j) as Map)['message'] as String)
          .toList();
      expect(gruende.toSet(), hasLength(3));
      expect(gruende[0], contains('keine Datei archiviert'));
      expect(gruende[1], contains('nicht lesbar'));
      expect(gruende[2], contains('nicht gefunden'));
      for (final j in [_dokumentKeins, _dokumentUnlesbar, _dokumentUnbekannt]) {
        expect((jsonDecode(j) as Map)['success'], isFalse);
        // Kein base64 im Fehlerfall — sonst würde der Client eine leere Datei
        // speichern und sie für den Brief halten.
        expect((jsonDecode(j) as Map).containsKey('base64_pdf'), isFalse);
      }
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

    testWidgets('archiviert oder nicht steht an jeder Zeile', (tester) async {
      serverAntwortetMit(_getAllVoll);
      await oeffne(tester);

      // Ohne diesen Unterschied sähe eine Zeile ohne Archiv genauso aus wie
      // eine mit — und man merkte erst beim Suchen, dass der Brief weg ist.
      expect(find.textContaining('Brief archiviert'), findsOneWidget);
      expect(find.textContaining('ohne Archiv'), findsOneWidget);
      // Nur die archivierte Zeile bekommt das PDF-Menü.
      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
    });

    testWidgets('ein Serverfehler beim Laden wird gezeigt, nicht verschluckt',
        (tester) async {
      serverAntwortetMit(r'''{"success":false,"message":"Serverfehler: Zugangsdaten nicht entschluesselbar"}''');
      await oeffne(tester);

      expect(find.textContaining('Zugangsdaten nicht entschluesselbar'), findsOneWidget);
    });
  });
}
