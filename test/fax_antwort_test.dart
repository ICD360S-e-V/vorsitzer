import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/screens/fax_nummer_waehlen_screen.dart';
import 'package:icd360sev_vorsitzer/screens/sipgate_fax_screen.dart';
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

  group('Zweite Runde (22.08.2026)', () {
    /// Wörtlich vom Server. Ein EINGEGANGENES Fax, dessen Absender die
    /// Rückwärtssuche aufgelöst hat.
    Map<String, dynamic> eingang() => jsonDecode('''
      {"id":5,"richtung":"ein","empfaenger":"+4973180159737",
       "empfaenger_name":"ICD360S e.V.","dateiname":"Fax von +4973180159737.pdf",
       "groesse_b":14326,"seiten":1,"deckblatt":false,"status":"empfangen",
       "fax_status_type":"RECEIVED","fehler":"","hat_dokument":true,
       "hat_bericht":false,"bezug_typ":null,"bezug_id":null,"bezug_text":"",
       "name_quelle":"verzeichnis","notiz":"Eingang bestätigt, Frist notiert",
       "hat_miniatur":false,"gruppe_key":null,"gruppe_pos":0,"gruppe_von":0,
       "wiederholung_von":null,"gelesen":true,
       "gesendet_am":"2026-08-16 22:04:01","zugestellt_am":"2026-08-16 22:04:01",
       "erstellt_am":"2026-08-16 22:04:23"}
    ''') as Map<String, dynamic>;

    test('Absender wurde aus den Stammdaten aufgelöst', () {
      final f = eingang();
      expect(f['empfaenger_name'], 'ICD360S e.V.');
      // ⚠️ Sagt, dass WIR den Namen gefunden haben — nicht sipgate und nicht
      // ein Mensch. Davon hängt ab, ob ein späterer Abgleich ihn anfassen darf.
      expect(f['name_quelle'], 'verzeichnis');
    });

    test('Notiz kommt entschlüsselt zurück', () {
      expect(eingang()['notiz'], 'Eingang bestätigt, Frist notiert');
    });

    test('„Antworten" nur beim Eingang', () {
      // Auf ein selbst gesendetes Fax zu antworten hiesse, an uns selbst zu
      // faxen.
      bool zeigt(Map<String, dynamic> f) => f['richtung'] == 'ein';
      expect(zeigt(eingang()), isTrue);
      expect(zeigt({...eingang(), 'richtung': 'aus'}), isFalse);
    });

    test('hat_miniatur=false heisst NICHT „gibt es nicht"', () {
      // ⚠️ Der Server erzeugt die Vorschau erst bei Bedarf. Ein Bildschirm,
      // der aus `false` „kein Bild" macht, würde nie eines anfordern — und
      // damit nie eines bekommen.
      final f = eingang();
      expect(f['hat_miniatur'], isFalse);
      expect(f['hat_dokument'], isTrue,
          reason: 'ein Dokument ist da, also ist eine Vorschau erzeugbar');
    });

    test('Miniatur-Merker unterscheidet „noch nicht" von „gibt es nicht"', () {
      // Dieselbe Logik wie im Bildschirm: kein Eintrag = noch nicht geholt,
      // Eintrag mit null = versucht und nichts da. Ohne den Unterschied fragt
      // der Bildschirm bei jedem Neuaufbau erneut, also endlos.
      final cache = <int, List<int>?>{};
      bool nochmalFragen(int id) => !cache.containsKey(id);

      expect(nochmalFragen(5), isTrue);
      cache[5] = null;
      expect(nochmalFragen(5), isFalse, reason: 'null heisst: schon versucht');
    });
  });

  group('Dritte Runde (22.08.2026)', () {
    /// Wörtlich vom Server: eine Zeile, die der Ausgangsabgleich
    /// nachgetragen hat — sie ging an unserem Sendeweg vorbei.
    Map<String, dynamic> nachgetragen() => jsonDecode('''
      {"id":24,"richtung":"aus","gegenstelle":"+4973180159737",
       "gegenstelle_name":"ICD360S e.V.","empfaenger":"+4973180159737",
       "empfaenger_name":"ICD360S e.V.","dateiname":"Fax an +4973180159737.pdf",
       "groesse_b":192,"seiten":1,"deckblatt":false,"status":"zugestellt",
       "fax_status_type":"SENT","fehler":"","hat_dokument":true,
       "hat_bericht":true,"bezug_typ":null,"bezug_id":null,"bezug_text":"",
       "name_quelle":"verzeichnis","notiz":"","ocr_text":"","ocr_stand":"leer",
       "herkunft":"abgleich","user_id":0,"hat_miniatur":false,
       "gruppe_key":null,"gruppe_pos":0,"gruppe_von":0,"wiederholung_von":null,
       "gesendet_von":""}
    ''') as Map<String, dynamic>;

    test('gegenstelle ersetzt empfaenger — beide sind noch da', () {
      // ⚠️ Die Spalte hiess bis zum 22.08.2026 `empfaenger` und trug bei
      // EINGEGANGENEN Faxen die Nummer des ABSENDERS. Der alte Schlüssel geht
      // eine Fassung lang weiter mit, damit eine schon ausgelieferte App
      // nicht plötzlich leere Rufnummern zeigt.
      final f = nachgetragen();
      expect(f['gegenstelle'], '+4973180159737');
      expect(f['empfaenger'], f['gegenstelle'],
          reason: 'Übergangsschlüssel muss denselben Wert tragen');
    });

    test('der Bildschirm liest neu, fällt aber auf alt zurück', () {
      String nummer(Map<String, dynamic> f) =>
          (f['gegenstelle'] ?? f['empfaenger'] ?? '').toString();

      expect(nummer(nachgetragen()), '+4973180159737');
      // Eine ältere Serverfassung liefert nur den alten Schlüssel.
      final alt = Map<String, dynamic>.from(nachgetragen())..remove('gegenstelle');
      expect(nummer(alt), '+4973180159737');
    });

    test('nachgetragene Zeile ist als solche erkennbar', () {
      // Wir wissen von ihr nur, was sipgate erzählt — kein Anlass, kein Bezug,
      // kein Absender. Ein rekonstruierter Beleg darf nicht aussehen wie ein
      // selbst erzeugter.
      final f = nachgetragen();
      expect(f['herkunft'], 'abgleich');
      expect(f['user_id'], 0);
      expect(f['bezug_typ'], isNull);
    });

    test('„von wem" bleibt leer, wenn es niemand von uns war', () {
      expect('${nachgetragen()['gesendet_von']}', isEmpty);
    });

    test('ocr_stand unterscheidet „leer" von „noch nicht versucht"', () {
      // ⚠️ Ohne diesen Unterschied versuchte jeder Lauf die Erkennung erneut —
      // bei einem Fax, das nur ein Unterschriftenbild enthält, also für immer.
      expect(nachgetragen()['ocr_stand'], 'leer');
      final offen = Map<String, dynamic>.from(nachgetragen())..['ocr_stand'] = null;
      expect(offen['ocr_stand'], isNull);
    });
  });

  // =========================================================================
  //  Vierte Runde (22.08.2026)
  //
  //  Zeichenketten wörtlich vom Server geholt, nachdem die Änderungen live
  //  waren — nicht von Hand nachgebaut.
  // =========================================================================
  group('Vierte Runde (22.08.2026)', () {
    // Echte Antwort auf {"action":"list","limit":1,"richtung":"ein"},
    // gekürzt auf die Felder dieser Runde.
    final zeile = jsonDecode(
        '{"id":7,"richtung":"ein","gegenstelle":"+4973180159737",'
        '"gegenstelle_name":"ICD360S e.V.","status":"empfangen",'
        '"hat_dokument":true,"hat_bericht":false,"bezug_text":"","notiz":"",'
        '"ocr_auszug":"16.08.26 23:17:10 Seite 1 von 1","ocr_zeichen":31,'
        '"ocr_stand":"erkannt","gelesen":true,"sync_offen":false,'
        '"gruppe_von":0,"gruppe_pos":0,"wiederholung_von":null}')
        as Map<String, dynamic>;

    test('der Volltext ist NICHT mehr in der Zeile', () {
      // 🔴 Bis zum 22.08.2026 ging `ocr_text` in jeder Zeile mit — im Schnitt
      // 2.365 Zeichen je Fax, über 40 kB für den ganzen Bestand — und der
      // Bildschirm hat ihn kein einziges Mal angefasst. Der Anriss ersetzt
      // ihn; der ganze Text kommt über die eigene Aktion `volltext`.
      expect(zeile.containsKey('ocr_text'), isFalse);
      expect(zeile['ocr_auszug'], '16.08.26 23:17:10 Seite 1 von 1');
      expect(zeile['ocr_zeichen'], 31);
    });

    test('ocr_zeichen entscheidet, ob der Menüpunkt erscheint', () {
      // Ein Punkt, der verlässlich „nichts erkannt" antwortet, ist einer, den
      // man einmal probiert und danach nie wieder.
      expect((zeile['ocr_zeichen'] as num).toInt() > 0, isTrue);
      final leer = jsonDecode('{"ocr_auszug":"","ocr_zeichen":0,"ocr_stand":"leer"}')
          as Map<String, dynamic>;
      expect((leer['ocr_zeichen'] as num).toInt() > 0, isFalse);
    });

    test('sync_offen sagt, ob der Stand schon bei sipgate steht', () {
      expect(zeile['sync_offen'], isFalse);
    });

    test('Guthaben kommt fertig gerechnet — die Einheit war die Falle', () {
      // 🔴 sipgate antwortet mit {"amount":186378}. Das sind NICHT 1.863,78 €,
      // sondern 18,64 € — die Referenzanwendung von sipgate selbst teilt durch
      // 10000. Der Server rechnet um; hier kommt nur noch der fertige Text an.
      final status = jsonDecode(
          '{"success":true,"eingerichtet":true,"faxline_id":"f0",'
          '"absender":"+4973180159737","live":true,'
          '"guthaben":18.64,"guthaben_text":"18,64 €",'
          '"guthaben_knapp":false,"sync_offen":0}') as Map<String, dynamic>;
      expect(status['guthaben_text'], '18,64 €');
      expect(status['guthaben_knapp'], isFalse);
      expect((status['guthaben'] as num) < 20, isTrue,
          reason: 'wer den Rohwert für Cent hält, liest das Hundertfache');
    });

    test('knappes Guthaben ist eine Aussage des Servers, keine Rechnung hier', () {
      final status =
          jsonDecode('{"guthaben":3.5,"guthaben_text":"3,50 €","guthaben_knapp":true}')
              as Map<String, dynamic>;
      expect(status['guthaben_knapp'], isTrue);
    });

    test('volltext liefert Text und Zeichenzahl', () {
      final v = jsonDecode(
          '{"success":true,"id":22,"text":"TELEFAX an 0731 9679413",'
          '"zeichen":23,"ocr_stand":"erkannt"}') as Map<String, dynamic>;
      expect(v['text'], startsWith('TELEFAX'));
      expect(v['zeichen'], 23);
    });

    test('bezug_setzen weist eine halbe Vorgangskennung ab', () {
      // Typ ohne Kennung wäre eine Verknüpfung, die der Filter nie anfasst,
      // in der Zeile aber aussieht wie eine, die gilt.
      final r = jsonDecode('{"success":false,"message":"Vorgangskennung unvollstaendig"}')
          as Map<String, dynamic>;
      expect(r['success'], isFalse);
    });
  });

  group('Entwurf: gemerkte Empfänger', () {
    test('liest die gespeicherte Liste', () {
      final z = faxZieleAusEntwurf(jsonDecode(
          '[{"nummer":"+497311759175","name":"Jobcenter Neu-Ulm"},'
          '{"nummer":"+4973140018200","name":""}]'));
      expect(z.length, 2);
      expect(z.first.nummer, '+497311759175');
      expect(z.first.name, 'Jobcenter Neu-Ulm');
      expect(z.last.name, '');
    });

    test('ein Entwurf aus einer älteren Fassung darf nicht werfen', () {
      // ⚠️ Der Entwurf kommt aus dem Speicher des Geräts. Was dort liegt, hat
      // womöglich eine Fassung geschrieben, die es so nicht mehr gibt — und
      // ein Absturz beim Öffnen des Faxbildschirms wäre der schlechteste aller
      // Ausgänge.
      expect(faxZieleAusEntwurf(null), isEmpty);
      expect(faxZieleAusEntwurf('kaputt'), isEmpty);
      expect(faxZieleAusEntwurf(jsonDecode('{"nummer":"123"}')), isEmpty);
      expect(faxZieleAusEntwurf(jsonDecode('[42,"x",null]')), isEmpty);
    });

    test('Einträge ohne Nummer fallen raus — gefaxt wird die Nummer', () {
      final z = faxZieleAusEntwurf(jsonDecode(
          '[{"name":"nur ein Name"},{"nummer":"  ","name":"leer"},'
          '{"nummer":" +49301 ","name":" Amt "}]'));
      expect(z.length, 1);
      expect(z.single.nummer, '+49301');
      expect(z.single.name, 'Amt');
    });
  });
}
