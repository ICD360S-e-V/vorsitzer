import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/sipgate_service.dart';
import 'package:icd360sev_vorsitzer/widgets/sipgate_waehltastatur.dart';

/// Kontaktliste und Wähltastatur.
///
/// ⚠️ Die drei Antworten unten sind **echte Ausgaben** von
/// `api/sipgate/sipgate_manage.php` (Aktion `kontakte`), am 2026-08-13 auf dem
/// Produktivserver abgenommen — nicht nachgebaut. Nachgebaute Antworten haben
/// hier schon zweimal genau das verschwiegen, woran es dann scheiterte: einmal
/// die Frage, ob die Nutzlast unter `data` liegt (sie liegt es nicht), und
/// einmal, ob ein leeres PHP-Array als `{}` oder als `[]` ankommt.
void main() {
  // Volle Antwort: `kategorien` ist ein OBJEKT, weil das PHP-Array
  // Zeichenketten als Schlüssel hat.
  final voll = jsonDecode(r'''
{"success":true,"gesamt":174,"kategorien":{"apotheke":23,"arbeitgeber":10,
"arzt":17,"bank":7,"behoerde":18,"bildung":4,"dienstleister":4,"gericht":12,
"klinik":5,"mitglied":19,"pflege":9,"polizei":6,"rettung":7,
"sanitaetshaus":18,"sonstige":2,"verein":10,"vermieter":3},
"kontakte":[
{"name":"ADAC — Geschäftsstelle Ulm","nummer":"+4973196280","kategorie":"verein",
 "quelle":"verein_datenbank","eigen":false},
{"name":"Agaplesion Bethesda Klinik Ulm","nummer":"+497311870","kategorie":"klinik",
 "quelle":"kliniken_datenbank","eigen":false},
{"name":"Agentur für Arbeit Ulm","nummer":"+4980045555000731160900",
 "kategorie":"behoerde","quelle":"behoerden_standorte","eigen":false}]}
''') as Map<String, dynamic>;

  final eigen = jsonDecode(r'''
{"success":true,"gesamt":1,"kategorien":{"eigen":1},"kontakte":[
{"id":8,"name":"Frau Merkle (Wohngeldstelle)","nummer":"+4973197049214",
 "notiz":"Durchwahl, Di + Do","kategorie":"eigen","quelle":"sipgate_kontakte",
 "eigen":true}]}
''') as Map<String, dynamic>;

  // ⚠️ Hier wird aus dem Objekt eine LISTE: ein leeres PHP-Array kennt keine
  // Schlüssel mehr, also codiert json_encode es als `[]`.
  final leer = jsonDecode(
    '{"success":true,"gesamt":0,"kategorien":[],"kontakte":[]}',
  ) as Map<String, dynamic>;

  group('kontakteAusAntwort — die echte Antwort des Servers', () {
    test('liest die Nutzlast flach, nicht unter „data"', () {
      final g = SipgateService.kontakteAusAntwort(voll);
      expect(g.gesamt, 174);
      expect(g.kontakte, hasLength(3));
      expect(g.kontakte.first['name'], 'ADAC — Geschäftsstelle Ulm');
      expect(g.kategorien['apotheke'], 23);
    });

    test('ein `data`-Umschlag würde alles leer lassen — deshalb dieser Test',
        () {
      // Genau dieser Griff war der Fehler, der die ganze sipgate-Ansicht leer
      // aussehen liess, ohne dass irgendwo etwas rot wurde.
      final g = SipgateService.kontakteAusAntwort({
        'success': true,
        'data': {'gesamt': 174, 'kontakte': voll['kontakte']},
      });
      expect(g.kontakte, isEmpty);
      expect(g.gesamt, 0);
    });

    test('leere Kategorien kommen als LISTE — und dürfen nicht werfen', () {
      // `as Map?` auf eine Liste gibt nicht null zurück, sondern wirft. Im
      // Release-Build ist das Ergebnis ein grauer Bildschirm ohne Meldung.
      late final ({int gesamt, List<Map<String, dynamic>> kontakte, Map<String, int> kategorien}) g;
      expect(() => g = SipgateService.kontakteAusAntwort(leer), returnsNormally);
      expect(g.kategorien, isEmpty);
      expect(g.kontakte, isEmpty);
      expect(g.gesamt, 0);
    });

    test('eigene Kontakte tragen id, Notiz und die Kennung „eigen"', () {
      // Ohne `id` gäbe es kein Ändern und kein Löschen; ohne `eigen` stünde das
      // Menü dafür an jeder Zeile, auch an denen aus den Stammdaten.
      final k = SipgateService.kontakteAusAntwort(eigen).kontakte.single;
      expect(k['id'], 8);
      expect(k['eigen'], isTrue);
      expect(k['notiz'], 'Durchwahl, Di + Do');
      expect(k['nummer'], '+4973197049214');
    });

    test('eine kaputte Antwort liefert Leere statt einer Ausnahme', () {
      final g = SipgateService.kontakteAusAntwort(
          {'success': true, 'kontakte': 'nein', 'kategorien': 42, 'gesamt': 'viele'});
      expect(g.kontakte, isEmpty);
      expect(g.kategorien, isEmpty);
      expect(g.gesamt, 0);
    });
  });

  group('kategorieName', () {
    test('übersetzt die Kennungen des Servers', () {
      expect(SipgateService.kategorieName('behoerde'), 'Behörden');
      expect(SipgateService.kategorieName('arzt'), 'Ärzte');
      expect(SipgateService.kategorieName('eigen'), 'Eigene Kontakte');
    });

    test('reicht Unbekanntes durch, statt es zu verschlucken', () {
      // Eine neue Tabelle auf dem Server soll in der Leiste auftauchen, auch
      // wenn niemand daran gedacht hat, sie hier einzutragen.
      expect(SipgateService.kategorieName('notariat'), 'notariat');
      expect(SipgateService.kategorieName(null), 'Sonstige');
    });

    test('jede Kategorie der echten Antwort hat ein deutsches Wort', () {
      final kennungen = SipgateService.kontakteAusAntwort(voll).kategorien.keys;
      expect(kennungen, isNotEmpty);
      for (final k in kennungen) {
        expect(SipgateService.kategorieName(k), isNot(k),
            reason: '„$k" kommt vom Server, hat hier aber keine Übersetzung — '
                'in der Leiste stünde dann die technische Kennung.');
      }
    });
  });

  group('Wähltastatur', () {
    Future<List<String>> tasten(WidgetTester t,
        {double breite = 900, bool schmal = false}) async {
      final gedrueckt = <String>[];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: breite,
              child: SipgateWaehltastatur(
                schmal: schmal,
                beiTaste: gedrueckt.add,
              ),
            ),
          ),
        ),
      ));
      return gedrueckt;
    }

    Offset mitte(WidgetTester t, String zeichen) => t.getCenter(
        find.ancestor(of: find.text(zeichen), matching: find.byType(InkWell)));

    testWidgets('zwölf Tasten in vier Reihen zu drei — wie auf jedem Telefon',
        (t) async {
      await tasten(t);

      const alle = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'];
      for (final z in alle) {
        expect(find.text(z), findsOneWidget, reason: 'Taste $z fehlt');
      }

      // ⚠️ Der eigentliche Punkt dieser Datei. Vorher lagen die Zwölf in einem
      // `Wrap`: der bricht nach verfügbarer Breite um, also je nach Fenster
      // nach vier, fünf oder sechs Tasten — die 5 stand mal in der Mitte, mal
      // am Rand. Hier wird geprüft, dass es wirklich DREI Spalten sind.
      //
      // ⚠️ Gemessen wird die TASTE, nicht die Beschriftung: unter der 2 stehen
      // Buchstaben, unter der 1 nicht, also sitzt die Ziffer dort ein paar
      // Pixel tiefer. Wer die Textmitten vergleicht, misst diesen Unterschied
      // und hält vier Reihen für acht.
      final mitten = {for (final z in alle) z: mitte(t, z)};
      final spalten = mitten.values.map((p) => p.dx.round()).toSet();
      final reihen = mitten.values.map((p) => p.dy.round()).toSet();
      expect(spalten, hasLength(3), reason: 'drei Spalten, nicht mehr');
      expect(reihen, hasLength(4), reason: 'vier Reihen, nicht mehr');

      // Und in der richtigen Ordnung: 1-2-3 nebeneinander, 1 über 4 über 7.
      expect(mitten['1']!.dy, mitten['2']!.dy);
      expect(mitten['1']!.dx, lessThan(mitten['2']!.dx));
      expect(mitten['2']!.dx, lessThan(mitten['3']!.dx));
      expect(mitten['1']!.dx, mitten['4']!.dx);
      expect(mitten['1']!.dy, lessThan(mitten['4']!.dy));
      expect(mitten['0']!.dx, mitten['2']!.dx,
          reason: 'die Null steht unter der Zwei, nicht am Rand');
    });

    testWidgets('die Buchstaben stehen unter den Ziffern', (t) async {
      await tasten(t);
      for (final b in ['ABC', 'DEF', 'GHI', 'JKL', 'MNO', 'PQRS', 'TUV', 'WXYZ']) {
        expect(find.text(b), findsOneWidget);
      }
    });

    testWidgets('ein Tipp meldet genau ein Zeichen', (t) async {
      final gedrueckt = await tasten(t);
      await t.tap(find.text('5'));
      await t.tap(find.text('#'));
      expect(gedrueckt, ['5', '#']);
    });

    testWidgets('das „+" liegt auf der Null, nicht auf einer 13. Taste',
        (t) async {
      // Ein dreizehnter Knopf hat vorher die Reihen gebrochen — genau das,
      // was das Muster kaputt macht.
      final gedrueckt = await tasten(t);
      expect(find.text('+'), findsOneWidget,
          reason: 'als Beschriftung unter der Null, sonst findet es niemand');

      await t.tap(find.text('0'));
      expect(gedrueckt, ['0']);

      await t.longPress(find.text('0'));
      expect(gedrueckt, ['0', '+']);
    });

    testWidgets('auf breitem Fenster wird die Tastatur NICHT auseinandergezogen',
        (t) async {
      // Auf dem Tablet stünde die 1 sonst 900 dp von der 3 entfernt und man
      // müsste die Hand versetzen, um eine Nummer zu tippen.
      await tasten(t, breite: 1200);
      final links = mitte(t, '1').dx;
      final rechts = mitte(t, '3').dx;
      expect(rechts - links, lessThan(300));
    });

    testWidgets('auf dem Telefon bleibt dasselbe Muster, nur enger', (t) async {
      await tasten(t, breite: 320, schmal: true);
      final mitten = {for (final z in ['1', '2', '3', '0']) z: mitte(t, z)};
      expect(mitten.values.map((p) => p.dx.round()).toSet(), hasLength(3));
      expect(mitten['0']!.dx, mitten['2']!.dx);
    });
  });
}
