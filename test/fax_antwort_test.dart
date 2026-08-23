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

  // =========================================================================
  //  Fünfte Runde (23.08.2026) — Beweiswert und Vertragstreue
  //
  //  Zeichenketten wörtlich vom Server, geholt nachdem die Änderungen live
  //  waren.
  // =========================================================================
  group('Fünfte Runde (23.08.2026)', () {
    test('eine weggelegte Zeile ist als solche erkennbar', () {
      // 🔴 Beim ersten Abgleich mit der ECHTEN Antwort fiel auf, dass
      // `abgelegt_am` gar nicht mitkam — `sipgateFaxZeile()` gab es nicht
      // heraus. Der Filter „Archiv" hätte die Zeilen zwar angezeigt, aber das
      // Menü hätte „Ins Archiv legen" statt „Zurückholen" geboten. Kein
      // Absturz, nur eine Oberfläche, die das Gegenteil anbietet.
      final archiv = jsonDecode(
          '{"id":24,"abgelegt_am":"2026-08-23 11:43:07","hash_stand":"nachgetragen",'
          '"gegenstelle_name":"ICD360S e.V."}') as Map<String, dynamic>;
      expect((archiv['abgelegt_am'] ?? '').toString().isNotEmpty, isTrue);

      // Und der Regelfall: der Schlüssel IST da, sein Wert ist null.
      final normal = jsonDecode('{"id":26,"abgelegt_am":null,"hash_stand":"nachgetragen"}')
          as Map<String, dynamic>;
      expect(normal.containsKey('abgelegt_am'), isTrue);
      expect((normal['abgelegt_am'] ?? '').toString().isNotEmpty, isFalse);
    });

    test('hash_stand sagt, WAS die Prüfsumme belegt', () {
      // „nachgetragen" heißt: heute aus der abgelegten Datei gerechnet, also
      // „seit dem Nachtragen unverändert" — nicht „seit dem Senden". Diesen
      // Unterschied zu verwischen wäre schlimmer als gar keine Prüfsumme.
      final z = jsonDecode('{"hash_stand":"nachgetragen"}') as Map<String, dynamic>;
      expect(z['hash_stand'], 'nachgetragen');
      expect(['original', 'nachgetragen'].contains(z['hash_stand']), isTrue);
    });

    test('ziel_pruefen trennt gesperrt, teuer und unauffällig', () {
      final p = jsonDecode(
          '{"success":true,"ziele":['
          '{"eingabe":"073180159737","nummer":"+4973180159737","gueltig":true,'
          '"erlaubt":true,"warnung":"","grund":""},'
          '{"eingabe":"0900123456","nummer":"+49900123456","gueltig":true,'
          '"erlaubt":false,"warnung":"",'
          '"grund":"Diese Nummer liegt in einem Mehrwert- oder Satellitenbereich (+49900). '
          'Dorthin faxt dieser Verein nicht — bitte die Nummer pruefen."},'
          '{"eingabe":"01805123456","nummer":"+491805123456","gueltig":true,'
          '"erlaubt":true,'
          '"warnung":"Service-Rufnummer (0180) — die Uebertragung kostet zusaetzlich.",'
          '"grund":""}]}') as Map<String, dynamic>;
      final ziele = (p['ziele'] as List).cast<Map<String, dynamic>>();
      expect(ziele[0]['erlaubt'], isTrue);
      expect((ziele[0]['warnung'] as String).isEmpty, isTrue);
      // 0900 wird GESPERRT, nicht gewarnt: ein Fax dorthin ist für diesen
      // Verein unter keinen Umständen richtig, also gäbe es nichts zu
      // bestätigen — nur eine Falle für den Tippfehler.
      expect(ziele[1]['erlaubt'], isFalse);
      expect(ziele[1]['grund'], contains('+49900'));
      // 0180 ist erlaubt und kostet: Jobcenter und Krankenkassen benutzen den
      // Bereich wirklich. Sperren hieße echte Empfänger ausschließen.
      expect(ziele[2]['erlaubt'], isTrue);
      expect(ziele[2]['warnung'], contains('0180'));
    });

    test('eine ungültige Nummer ist weder gültig noch erlaubt', () {
      final z = jsonDecode(
          '{"eingabe":"abc","gueltig":false,"erlaubt":false,"warnung":"",'
          '"grund":"Keine vollstaendige Faxnummer"}') as Map<String, dynamic>;
      expect(z['gueltig'], isFalse);
      // ⚠️ `nummer` fehlt hier ganz — der Server setzt den Schlüssel nur bei
      // einer auflösbaren Nummer. Ein `as String` darauf würfe.
      expect(z.containsKey('nummer'), isFalse);
    });

    test('das Protokoll nennt wer, wann und warum', () {
      final p = jsonDecode(
          '{"success":true,"eintraege":['
          '{"id":2,"fax_id":24,"aktion":"zurueckgeholt","wer":"Ionut-Claudiu Duinea",'
          '"vorher":[],"grund":"","erstellt_am":"2026-08-23 11:30:25"},'
          '{"id":1,"fax_id":24,"aktion":"abgelegt","wer":"Ionut-Claudiu Duinea",'
          '"vorher":{"gegenstelle":"+4973180159737","name":"ICD360S e.V.",'
          '"dateiname":"Fax an +4973180159737.pdf","status":"zugestellt",'
          '"richtung":"aus","erstellt_am":"2026-08-22 15:21:36"},'
          '"grund":"PROBE 23.08. — Pruefung des Archivwegs",'
          '"erstellt_am":"2026-08-23 11:30:25"}]}') as Map<String, dynamic>;
      final e = (p['eintraege'] as List).cast<Map<String, dynamic>>();
      expect(e.length, 2);
      expect(e.last['aktion'], 'abgelegt');
      expect(e.last['grund'], contains('PROBE'));
      expect(e.last['wer'], 'Ionut-Claudiu Duinea');
    });

    test('vorher ist mal Objekt und mal LISTE — niemals blind als Map lesen', () {
      // ⚠️ Dieselbe PHP-Eigenheit, die 2026-08-05 den Speedtest-Bildschirm
      // grau gemacht hat: ein leeres PHP-Array wird zu `[]`, also zu einer
      // JSON-LISTE, nicht zu `{}`. `as Map` darauf gibt nicht null zurück,
      // sondern wirft — im Release-Build ohne jede Meldung.
      final p = jsonDecode(
          '[{"aktion":"zurueckgeholt","vorher":[]},'
          '{"aktion":"abgelegt","vorher":{"status":"zugestellt"}}]') as List;
      expect(p[0]['vorher'], isA<List>());
      expect(p[1]['vorher'], isA<Map>());
    });

    test('das Siegel läuft asynchron — die Antwort ist eine Auftragsnummer', () {
      // Der Signierschlüssel liegt so, dass der Webserver nicht herankommt;
      // gesiegelt wird im Cron. Die Antwort auf `journal` kann deshalb kein
      // Dokument enthalten.
      final r = jsonDecode(
          '{"success":true,"message":"Zum Siegeln vorgemerkt. Das fertige Journal '
          'steht in wenigen Minuten bereit.","auftrag_id":1,'
          '"dateiname":"Faxjournal 2026-08-23.pdf","eintraege":17}')
          as Map<String, dynamic>;
      expect(r.containsKey('inhalt_b64'), isFalse);
      expect((r['auftrag_id'] as num).toInt(), greaterThan(0));
    });

    test('ein noch nicht fertiges Siegel meldet seinen Stand, keinen Fehler', () {
      final r = jsonDecode('{"success":false,"stand":"offen","message":"Noch nicht fertig"}')
          as Map<String, dynamic>;
      expect(r['success'], isFalse);
      expect(r['stand'], 'offen');
      // Der Bildschirm unterscheidet daran „warte weiter" von „gib auf".
      expect(['offen', 'laeuft', 'fehler'].contains(r['stand']), isTrue);
    });

    test('die abgewiesenen Fälle tragen einen maschinenlesbaren Grund', () {
      for (final (roh, erwartet) in [
        ('{"success":false,"message":"…","grund":"gesperrtes_ziel"}', 'gesperrtes_ziel'),
        ('{"success":false,"message":"…","grund":"unbekannter_typ"}', 'unbekannter_typ'),
        ('{"success":false,"message":"…","grund":"begruendung_fehlt"}', 'begruendung_fehlt'),
      ]) {
        final r = jsonDecode(roh) as Map<String, dynamic>;
        expect(r['grund'], erwartet);
      }
    });
  });

  // =========================================================================
  //  Sechste Runde (23.08.2026) — ein Sendeweg, Siegel, Zeitstempel
  // =========================================================================
  group('Sechste Runde (23.08.2026)', () {
    test('eine Zeile sagt, ob das gesendete Dokument gesiegelt war', () {
      // 🔴 `jobcenter_vollmacht_versand.php` faxt die UNTERSCHRIEBENE
      // Vollmacht — die trägt das Dokumentensiegel des Vereins. Bis zum
      // 23.08.2026 hielt das niemand fest. Zusammen mit der Prüfsumme ergibt
      // es die Aussage, auf die es hinterher ankommt: „was rausging, war das
      // gesiegelte Dokument, unverändert."
      final z = jsonDecode(
              '{"id":9,"signiert":true,"hash_stand":"nachgetragen","abgelegt_am":null}')
          as Map<String, dynamic>;
      expect(z['signiert'], isTrue);
      // ⚠️ Ein echtes bool, kein 1/0 — der Server wandelt es um. Ein
      // `== true` auf einer 1 wäre still falsch.
      expect(z['signiert'], isA<bool>());
    });

    test('nicht gesiegelt ist false, nicht null', () {
      final z = jsonDecode('{"id":25,"signiert":false}') as Map<String, dynamic>;
      expect(z['signiert'], isFalse);
      expect(z['signiert'] == true, isFalse);
    });

    test('der gemeinsame Sendeweg weist ein gesperrtes Ziel ab', () {
      // Bis heute hatten SIEBEN Module je eine eigene Kopie des Sendewegs,
      // und keine kannte diese Sperre. Jetzt steht sie in der Funktion, durch
      // die alle müssen.
      final r = jsonDecode(
          '{"ok":false,"id":0,"grund":"gesperrtes_ziel",'
          '"meldung":"Diese Nummer liegt in einem Mehrwert- oder Satellitenbereich '
          '(+49900). Dorthin faxt dieser Verein nicht — bitte die Nummer pruefen."}')
          as Map<String, dynamic>;
      expect(r['ok'], isFalse);
      expect(r['grund'], 'gesperrtes_ziel');
      // ⚠️ id = 0: es wurde KEINE Zeile angelegt. Die Sperre greift vor dem
      // INSERT, sonst stünde im Verlauf ein Fax, das nie eines war.
      expect(r['id'], 0);
    });

    test('die Dublettensperre nennt das frühere Fax', () {
      final r = jsonDecode(
          '{"ok":false,"id":0,"grund":"dublette","fruehere_id":25,'
          '"meldung":"Dieses Dokument wurde an diese Nummer bereits zugestellt (Fax #25)."}')
          as Map<String, dynamic>;
      expect(r['grund'], 'dublette');
      expect(r['fruehere_id'], 25);
    });

    test('der Zeitstempel kommt als EIGENES Stück, nicht im PDF', () {
      // ⚠️ Er gilt über die FERTIGE Datei — das Siegelblatt ist Teil dessen,
      // worüber gestempelt wird, also kann er dort per Bauart nicht stehen.
      // (Und TCPDFs setTimeStamp() ist ohnehin eine leere Hülle.)
      final a = jsonDecode(
          '{"success":true,"dateiname":"Faxjournal 2026-08-23.pdf",'
          '"inhalt_b64":"JVBERi0=",'
          '"siegel_hash":"7c601156e314e0d130ff4423846d3df5264a7d4e948ea8597890e8d67f4865ed",'
          '"tsa_b64":"MIIB","tsa_quelle":"http://timestamp.digicert.com",'
          '"tsa_zeit":"2026-08-23 12:22:59"}') as Map<String, dynamic>;
      expect((a['siegel_hash'] as String).length, 64);
      expect(a['tsa_quelle'], contains('digicert'));
      expect(a['tsa_b64'], isNotNull);
    });

    test('ein fehlender Zeitstempel ist kein Fehler — das Siegel gilt trotzdem', () {
      // Der Zeitstempeldienst kann ausfallen. Dann fehlt der Zeitpunkt, nicht
      // das Siegel. Der Bildschirm sagt das, statt es zu verschweigen.
      final a = jsonDecode(
          '{"success":true,"dateiname":"Faxjournal 2026-08-23.pdf",'
          '"inhalt_b64":"JVBERi0=","siegel_hash":"7c60","tsa_b64":null,'
          '"tsa_quelle":"","tsa_zeit":null}') as Map<String, dynamic>;
      expect(a['success'], isTrue);
      expect(a['tsa_b64'], isNull);
    });

    test('die Positivliste der Vorgangsarten nennt nur, was es gibt', () {
      // ⚠️ Sie hatte fünf Einträge; drei davon hatte ich am 22.08. angenommen.
      // Nachgezählt gegen Code und Datenbank: es gibt genau zwei.
      const echte = ['jc_av_schweigepflicht', 'jc_av_vorschlag_bericht'];
      final r = jsonDecode('{"ok":false,"id":0,"grund":"unbekannter_typ",'
          '"meldung":"Unbekannte Vorgangsart: jobcenter_av"}') as Map<String, dynamic>;
      expect(r['grund'], 'unbekannter_typ');
      expect(echte.contains('jobcenter_av'), isFalse);
      expect(echte.length, 2);
    });
  });

  // =========================================================================
  //  Wen ein Fax betrifft (23.08.2026)
  // =========================================================================
  group('Betroffenes Mitglied', () {
    // Echte Antwort auf {"action":"list","betrifft_user_id":48}.
    final zeile = jsonDecode(
        '{"id":14,"betrifft_user_id":48,"betrifft_name":"Olha Pasichnyk",'
        '"gesendet_von":"","user_id":0,"bezug_typ":"jc_av_schweigepflicht"}')
        as Map<String, dynamic>;

    test('Absender und Betroffener sind zwei verschiedene Felder', () {
      // 🔴 Bis zum 23.08.2026 war es EINE Spalte, und sie bedeutete je nach
      // Sendeweg etwas anderes: aus dem Faxbildschirm der Vorstand, aus drei
      // Modulen das Mitglied. `list` gab sie als `gesendet_von` heraus — der
      // Verlauf hätte „gesendet von Olha Pasichnyk" gezeigt, ein Mitglied,
      // das gar keine Faxe senden kann.
      expect(zeile['betrifft_name'], 'Olha Pasichnyk');
      expect(zeile['betrifft_user_id'], 48);
      expect(zeile.containsKey('gesendet_von'), isTrue);
    });

    test('leerer Absender heisst „nicht vermerkt", nicht „niemand"', () {
      // Bei den zwei alten Zeilen wissen wir nicht mehr, wer getippt hat —
      // das Mitglied stand an seiner Stelle. Ehrlicher ist leer als ein Name,
      // der nicht stimmt.
      expect(zeile['gesendet_von'], '');
      expect(zeile['user_id'], 0);
    });

    test('ein Fax aus dem Faxbildschirm hat keinen Betroffenen', () {
      // Dort gibt niemand ein Mitglied an — und das ist richtig so, keine
      // Lücke. Der Bildschirm darf daraus nichts erfinden.
      final ausDemBildschirm = jsonDecode(
          '{"id":22,"betrifft_user_id":null,"betrifft_name":"",'
          '"gesendet_von":"Ionut-Claudiu Duinea","user_id":2}')
          as Map<String, dynamic>;
      expect(ausDemBildschirm['betrifft_user_id'], isNull);
      expect((ausDemBildschirm['betrifft_name'] as String).isEmpty, isTrue);
      expect(ausDemBildschirm['gesendet_von'], 'Ionut-Claudiu Duinea');
    });

    test('der Bildschirm kann auf einen Ausschnitt zeigen', () {
      // ⚠️ `gefiltert` entscheidet, ob Zugangskarte und Sendefeld wegfallen.
      // Ohne diesen Zustand sähe die Mitgliedsakte aus wie der ganze Verlauf.
      expect(const SipgateFaxScreen().gefiltert, isFalse);
      expect(const SipgateFaxScreen(betrifftUserId: 48).gefiltert, isTrue);
      expect(const SipgateFaxScreen(bezugTyp: 'jc_av_schweigepflicht', bezugId: 16)
          .gefiltert, isTrue);
      // Halbe Vorgangskennung ist kein Ausschnitt — sonst zeigte der
      // Bildschirm alles und behauptete, es sei ein Vorgang.
      expect(const SipgateFaxScreen(bezugTyp: 'jc_av_schweigepflicht').gefiltert, isFalse);
      expect(const SipgateFaxScreen(bezugId: 16).gefiltert, isFalse);
    });
  });
  // =========================================================================
  group('Grenzen von sipgate — Dokument vor dem Hochladen', () {
    // ⚠️ Die Zahlen sind NICHT unsere Wahl. sipgate nennt im eigenen
    // Hilfecenter „PDF-Dateien mit bis zu 10 MB" und „maximal 30 Seiten"
    // (abgerufen 24.08.2026). Wer sie hier ändert, ändert nur, wann der
    // Fehlschlag kommt — nicht ob.
    test('die Grenzen sind die von sipgate', () {
      expect(kFaxMaxBytes, 10 * 1024 * 1024);
      expect(kFaxMaxSeiten, 30);
    });

    test('ein gewöhnliches Dokument geht durch', () {
      expect(faxDokumentBeanstandung('Widerspruch.pdf', 240 * 1024, 3), '');
    });

    test('genau auf der Grenze geht noch durch', () {
      expect(faxDokumentBeanstandung('a.pdf', kFaxMaxBytes, kFaxMaxSeiten), '');
    });

    test('ein Byte darüber wird beanstandet', () {
      final k = faxDokumentBeanstandung('scan.pdf', kFaxMaxBytes + 1, 2);
      expect(k, contains('scan.pdf'));
      expect(k, contains('10 MB'));
    });

    test('eine Seite darüber wird beanstandet', () {
      final k = faxDokumentBeanstandung('akte.pdf', 90 * 1024, 31);
      expect(k, contains('31 Seiten'));
      expect(k, contains('30'));
    });

    // 🔴 DER FALL, DEN DIE BYTEGRENZE NIE GEFANGEN HÄTTE — auf dem Server
    // nachgemessen: ein selbst erzeugtes PDF mit 35 Seiten ist 77,6 kB groß.
    // Bis zum 24.08.2026 gab es überhaupt keine Seitenprüfung, weder hier
    // noch dort; sipgate wies solche Dokumente erst nach dem Hochladen ab.
    test('viele Seiten in einer winzigen Datei werden trotzdem gefangen', () {
      expect(faxDokumentBeanstandung('60seiten.pdf', 78 * 1024, 60), isNotEmpty);
    });

    // ⚠️ null heißt „nicht zählbar", nicht „null Seiten". pdfium scheitert an
    // verschlüsselten PDF, die sipgate trotzdem faxt — ein sendbares Fax
    // wegen unserer eigenen Unfähigkeit zu blockieren wäre der schlechtere
    // Fehler. Der Server prüft ohnehin noch einmal.
    test('unbekannte Seitenzahl blockiert nicht', () {
      expect(faxDokumentBeanstandung('krypto.pdf', 500 * 1024, null), '');
    });

    test('unbekannte Seitenzahl rettet aber kein zu großes Dokument', () {
      expect(faxDokumentBeanstandung('riesig.pdf', kFaxMaxBytes + 1, null),
          isNotEmpty);
    });
  });

  // =========================================================================
  group('Tagesüberschriften im Verlauf', () {
    // ⚠️ `jetzt` ist ein Parameter, damit der Test an jedem Tag des Jahres
    // dasselbe Ergebnis hat. Mit DateTime.now() drinnen wäre er am 31.12.
    // rot und sonst grün.
    final jetzt = DateTime(2026, 8, 24, 14, 30);

    test('heute', () {
      expect(faxTagesgruppe(DateTime(2026, 8, 24, 0, 5), jetzt), 'Heute');
      expect(faxTagesgruppe(DateTime(2026, 8, 24, 23, 59), jetzt), 'Heute');
    });

    test('gestern', () {
      expect(faxTagesgruppe(DateTime(2026, 8, 23, 23, 59), jetzt), 'Gestern');
    });

    test('älter im selben Jahr — ohne Jahreszahl', () {
      expect(faxTagesgruppe(DateTime(2026, 8, 21, 18, 22), jetzt), '21. August');
      expect(faxTagesgruppe(DateTime(2026, 1, 3), jetzt), '3. Januar');
    });

    // Das Jahr steht nur da, wenn es ein anderes ist — sonst stünde es in
    // einer Liste fünfzig Mal und trüge nichts bei.
    test('anderes Jahr — mit Jahreszahl', () {
      expect(faxTagesgruppe(DateTime(2025, 12, 31), jetzt), '31. Dezember 2025');
    });

    // ⚠️ Über die Monatsgrenze: der 31.07. ist der Vortag des 01.08., nicht
    // „irgendwann im Juli". Eine Differenz in Tagen statt in Kalendertagen
    // hätte hier gepatzt.
    test('über die Monatsgrenze hinweg', () {
      final erster = DateTime(2026, 8, 1, 9, 0);
      expect(faxTagesgruppe(DateTime(2026, 7, 31, 22, 0), erster), 'Gestern');
      expect(faxTagesgruppe(DateTime(2026, 7, 30, 22, 0), erster), '30. Juli');
    });

    // ⚠️ Die Uhrzeit darf nicht mitreden: 23:59 gestern und 00:01 heute sind
    // zwei Minuten auseinander und trotzdem zwei Überschriften.
    test('zwei Minuten Abstand, zwei Überschriften', () {
      final kurzNachMitternacht = DateTime(2026, 8, 24, 0, 1);
      expect(faxTagesgruppe(DateTime(2026, 8, 24, 0, 0), kurzNachMitternacht),
          'Heute');
      expect(faxTagesgruppe(DateTime(2026, 8, 23, 23, 59), kurzNachMitternacht),
          'Gestern');
    });
  });

}
