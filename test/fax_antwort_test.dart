import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/screens/fax_nummer_waehlen_screen.dart';
import 'package:icd360sev_vorsitzer/services/fax_badge_service.dart';

/// Gegen die ECHTE Antwort des Servers, nicht gegen eine nachgebaute.
///
/// ⚠️ WARUM DAS SO SEIN MUSS
/// Am 05.08.2026 blieb der Speedtest-Bildschirm nach der Auslieferung grau.
/// Weder `flutter analyze` noch die damals 514 Tests haben etwas gesehen —
/// **keiner davon fasste die echte Antwort des Servers an**. Die Ursache war
/// eine PHP-Eigenheit: `array_fill(0, 24, …)` hat lückenlose Schlüssel, wird
/// deshalb zu einer JSON-**Liste**; dieselbe Struktur mit einer Lücke wird zum
/// **Objekt**. `as Map` auf einer Liste gibt nicht `null` zurück, sondern
/// wirft — im Release-Build ohne jede Meldung.
///
/// Die Zeichenketten hier stammen wörtlich vom Server (21.08.2026,
/// `sipgate_fax.php`), nur gekürzt auf die Felder, um die es geht.
void main() {
  group('Fax-Abzeichen', () {
    test('liest die Zahl aus der echten Listenantwort', () {
      final antwort = jsonDecode('''
        {"success":true,"faxe":[],"gesamt":14,"gefunden":14,
         "offset":0,"limit":50,"mehr":false,"ungelesen":3}
      ''') as Map<String, dynamic>;
      expect(faxUngeleseneAusAntwort(antwort), 3);
    });

    test('fehlendes Feld ergibt null — und darf ein Abzeichen nicht löschen', () {
      // ⚠️ Der Unterschied zwischen „null ungelesen" und „die Antwort sagt
      // nichts dazu". Bei einer Fehlerantwort ist der letzte bekannte Stand
      // ehrlicher als eine erfundene 0.
      final antwort = jsonDecode('{"success":false,"message":"Kein Fax-Zugang"}')
          as Map<String, dynamic>;
      expect(faxUngeleseneAusAntwort(antwort), isNull);
    });

    test('nimmt auch eine Gleitkommazahl entgegen', () {
      // PHP kann dieselbe Zahl als 3 oder 3.0 kodieren, je nachdem, wie sie
      // entstanden ist. `as int` auf einem double wirft — und zwar erst beim
      // Benutzer.
      final antwort = jsonDecode('{"ungelesen":3.0}') as Map<String, dynamic>;
      expect(faxUngeleseneAusAntwort(antwort), 3);
    });

    test('negative Zahl wird zu 0, nicht zu einem Abzeichen mit Minus', () {
      final antwort = jsonDecode('{"ungelesen":-2}') as Map<String, dynamic>;
      expect(faxUngeleseneAusAntwort(antwort), 0);
    });
  });

  group('Faxverzeichnis: Kategorien', () {
    test('Objektform — so kommt sie, wenn es Treffer gibt', () {
      // Wörtlich vom Server, 221 Nummern in 13 Kategorien.
      final roh = jsonDecode('''
        {"apotheke":17,"arbeitgeber":31,"arzt":53,"behoerde":17,"bildung":3,
         "dienstleister":6,"gericht":27,"kasse":17,"klinik":2,"pflege":2,
         "polizei":7,"verein":3,"versicherung":36}
      ''');
      final k = faxKategorienAus(roh);
      expect(k['arzt'], 53);
      expect(k['versicherung'], 36);
      expect(k.length, 13);
    });

    test('LISTENFORM bei null Treffern — darf nicht werfen', () {
      // ⚠️ Das ist die echte Antwort auf eine Suche ohne Treffer:
      //     {"success":true,"gesamt":0,"kategorien":[],"kontakte":[]}
      // Genau hier ist der Speedtest-Bildschirm damals gestorben.
      final antwort = jsonDecode(
              '{"success":true,"gesamt":0,"kategorien":[],"kontakte":[]}')
          as Map<String, dynamic>;
      expect(() => faxKategorienAus(antwort['kategorien']), returnsNormally);
      expect(faxKategorienAus(antwort['kategorien']), isEmpty);
    });

    test('fehlendes Feld ergibt eine leere Karte', () {
      expect(faxKategorienAus(null), isEmpty);
    });
  });

  group('Verlaufszeile', () {
    /// Eine echte Zeile, wie `sipgateFaxZeile()` sie liefert — mit den
    /// Feldern, die am 21.08.2026 dazugekommen sind.
    Map<String, dynamic> zeile() => jsonDecode('''
      {"id":14,"richtung":"aus","empfaenger":"+4973140018200",
       "empfaenger_name":"Jobcenter Alb-Donau (Ulm)",
       "dateiname":"Schweigepflichtentbindung.pdf","groesse_b":7240,"seiten":3,
       "deckblatt":false,"status":"zugestellt","fax_status_type":"SENT",
       "fehler":"","hat_dokument":true,"hat_bericht":true,
       "bezug_typ":"jc_av_schweigepflicht","bezug_id":16,"bezug_text":"",
       "gruppe_key":null,"gruppe_pos":0,"gruppe_von":0,
       "wiederholung_von":null,"gelesen":false,
       "gesendet_am":"2026-08-21 18:22:54","zugestellt_am":"2026-08-21 18:33:02",
       "erstellt_am":"2026-08-21 18:22:53"}
    ''') as Map<String, dynamic>;

    test('die neuen Felder sind da und haben den erwarteten Typ', () {
      final f = zeile();
      expect(f['bezug_typ'], 'jc_av_schweigepflicht');
      expect(f['bezug_id'], isA<int>());
      expect(f['deckblatt'], isA<bool>());
      expect(f['gruppe_von'], isA<int>());
      expect(f['wiederholung_von'], isNull);
    });

    test('„Noch einmal senden" nur für Ausgang MIT Dokument', () {
      // Dieselbe Bedingung wie im Bildschirm. Der Server lehnt beides ab —
      // der Knopf soll gar nicht erst erscheinen.
      bool erlaubt(Map<String, dynamic> f) =>
          f['richtung'] != 'ein' && f['hat_dokument'] == true;

      expect(erlaubt(zeile()), isTrue);
      expect(erlaubt({...zeile(), 'richtung': 'ein'}), isFalse);
      expect(erlaubt({...zeile(), 'hat_dokument': false}), isFalse);
    });

    test('ungelesen gilt nur für den Eingang', () {
      // Ein gesendetes Fax hat der Mensch selbst abgeschickt; `gelesen:false`
      // steht dort zwar, darf aber kein Abzeichen erzeugen.
      bool ungelesen(Map<String, dynamic> f) =>
          f['richtung'] == 'ein' && f['gelesen'] != true;

      expect(ungelesen(zeile()), isFalse, reason: 'Ausgang zählt nie als neu');
      expect(ungelesen({...zeile(), 'richtung': 'ein'}), isTrue);
      expect(ungelesen({...zeile(), 'richtung': 'ein', 'gelesen': true}), isFalse);
    });

    test('Gruppenmarke erscheint erst ab zwei Faxen', () {
      bool zeigt(Map<String, dynamic> f) =>
          ((f['gruppe_von'] as num?)?.toInt() ?? 0) > 1;

      expect(zeigt(zeile()), isFalse);
      expect(zeigt({...zeile(), 'gruppe_von': 1}), isFalse,
          reason: 'ein einzelnes Fax ist keine Sendung aus mehreren');
      expect(zeigt({...zeile(), 'gruppe_von': 3}), isTrue);
    });
  });
}
