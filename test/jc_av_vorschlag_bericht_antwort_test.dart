import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_jobcenter.dart';

/// Die Antworten, die `jc_av_vorschlag_bericht.php` und das gepatchte
/// `list_vorschlag_korr` am 21.08.2026 wirklich geliefert haben — in der
/// Form, in der sie ankamen. Nur Namen, Nummern und Betreffzeilen sind gegen
/// Probewerte getauscht: das Repo ist öffentlich.
///
/// ⚠️ Nachgebaute Antworten prüfen nichts. Der Fehler, den ein solcher Test
/// fangen soll, sitzt genau dort, wo Server und Client sich über die Form
/// uneinig sind — und diese Uneinigkeit lässt sich aus dem Dart-Code nicht
/// ableiten. Das PHP liegt in keinem Repo; hier ist die einzige Stelle, an
/// der die Kopplung überhaupt auffallen kann.
const String kBerichtListeAntwort = r'''
{"success":true,"berichte":[{"id":3,"korr_id":8,"erstellt_am":"2026-08-21 20:22:30","status_stand":"beworben","mit_verlauf":true,"pdf_filename":"vv_bericht_3_20260821_202230_a1b2c3d4.pdf.enc","groesse_b":3027,"fax":{"fax_id":19,"status":"zugestellt","typ":"SENT","seiten":1,"fehler":"","gesendet":"2026-08-21 20:22:30","zugestellt":"2026-08-21 20:22:30"}}],"fax_nummer":"0731 1759-175","jobcenter_name":"Jobcenter Musterstadt","av_name":"Musterfrau"}
''';

/// Derselbe Endpunkt, solange noch kein Bericht erzeugt wurde.
///
/// ⚠️ `berichte` ist dann eine LEERE LISTE, kein Objekt: PHP kennt nur einen
/// Array-Typ, und `fetchAll()` auf null Zeilen wird zu `[]`. Wer hier ein
/// `Map` erwartet, bekommt keinen `null`, sondern einen `TypeError` — und im
/// Release-Bau eine graue Fläche ohne jede Meldung.
const String kBerichtLeerAntwort = r'''
{"success":true,"berichte":[],"fax_nummer":"","jobcenter_name":"Jobcenter Musterstadt","av_name":""}
''';

/// `list_vorschlag_korr` nach dem Patch: drei Zeilen, davon EINE aus einem
/// gefaxten Bericht entstanden.
const String kKorrAntwort = r'''
{"success":true,"korrespondenz":[{"id":8,"user_id":58,"vorschlag_id":3,"richtung":"ausgang","kontaktart":"fax","datum":"2026-08-21","betreff":"Rückmeldung zum Vermittlungsvorschlag (Bericht vom 21.08.2026 20:22 Uhr)","text":"Per Fax an Jobcenter Musterstadt (+490000000000).","erstellt_von":"V00000","created_at":"2026-08-21 20:22:30","updated_at":"2026-08-21 20:22:30","fax":{"fax_id":19,"status":"zugestellt","typ":"SENT","seiten":1,"fehler":"","gesendet":"2026-08-21 20:22:30","zugestellt":"2026-08-21 20:22:30"}},{"id":4,"user_id":58,"vorschlag_id":3,"richtung":"eingang","kontaktart":"post","datum":"2026-08-21","betreff":"Vermittlungsvorschlag vom 11.08.2026","text":"kommt als Brief","erstellt_von":"V00000","created_at":"2026-08-21 19:34:34","updated_at":"2026-08-21 19:34:34","fax":null},{"id":5,"user_id":58,"vorschlag_id":3,"richtung":"eingang","kontaktart":"persoenlich","datum":"2026-08-20","betreff":"Bestätigung","text":"Notiz","erstellt_von":"V00000","created_at":"2026-08-21 19:46:26","updated_at":"2026-08-21 19:46:26","fax":null}]}
''';

/// Ein gescheiterter Versuch — die Form, in der ein Fehlschlag ankommt.
const String kFaxFehlerAntwort = r'''
{"success":true,"berichte":[{"id":4,"korr_id":null,"erstellt_am":"2026-08-21 21:05:00","status_stand":"nicht_beworben","mit_verlauf":false,"pdf_filename":"vv_bericht_3_20260821_210500_ffee1122.pdf.enc","groesse_b":2811,"fax":{"fax_id":20,"status":"fehlgeschlagen","typ":null,"seiten":null,"fehler":"Gegenstelle besetzt","gesendet":null,"zugestellt":null}}],"fax_nummer":"0731 1759-175","jobcenter_name":"Jobcenter Musterstadt","av_name":"Musterfrau"}
''';

/// So liest der Bildschirm die Liste — dieselben Ausdrücke wie im Widget.
List<Map<String, dynamic>> berichteLesen(String rohantwort) {
  final j = jsonDecode(rohantwort) as Map<String, dynamic>;
  return (j['berichte'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
}

void main() {
  group('action: liste', () {
    test('ein Bericht mit zugestelltem Fax wird vollständig gelesen', () {
      final berichte = berichteLesen(kBerichtListeAntwort);
      expect(berichte, hasLength(1));
      final b = berichte.single;
      expect(b['id'], 3);
      expect(b['korr_id'], 8);
      expect(b['status_stand'], 'beworben');
      // Der Server schickt einen echten Bool, keine 1/0 — das Widget zeigt
      // „ohne Ablauf" ueber `mit_verlauf == false`, und '0' waere wahr.
      expect(b['mit_verlauf'], isA<bool>());
      expect(b['mit_verlauf'], isTrue);

      final fax = b['fax'];
      expect(fax, isA<Map>(), reason: 'das Widget prueft mit `is Map`');
      final f = Map<String, dynamic>.from(fax as Map);
      expect(f['status'], 'zugestellt');
      expect(f['seiten'], 1);
      expect(f['zugestellt'], isNotNull);
    });

    test('ohne Bericht kommt eine leere LISTE, kein Objekt', () {
      // Sonst waere `as List?` ein TypeError statt null — siehe Kopf der Datei.
      final j = jsonDecode(kBerichtLeerAntwort) as Map<String, dynamic>;
      expect(j['berichte'], isA<List>());
      expect(berichteLesen(kBerichtLeerAntwort), isEmpty);
    });

    test('fehlende Faxnummer kommt als leerer String, nicht als null', () {
      final j = jsonDecode(kBerichtLeerAntwort) as Map<String, dynamic>;
      // `(r['fax_nummer'] ?? '').toString().trim()` traegt beides, aber der
      // leere String ist das, was der Bildschirm als „nicht hinterlegt" zeigt.
      expect((j['fax_nummer'] ?? '').toString().trim(), isEmpty);
    });

    test('ein gescheitertes Fax hat keine Seiten und keine Sendezeit', () {
      final b = berichteLesen(kFaxFehlerAntwort).single;
      final f = Map<String, dynamic>.from(b['fax'] as Map);
      expect(f['status'], 'fehlgeschlagen');
      expect(f['seiten'], isNull);
      expect(f['gesendet'], isNull);
      expect(f['fehler'], 'Gegenstelle besetzt');
      // ⚠️ Ohne Ausgang in der Korrespondenz: es hat nichts das Haus
      // verlassen, also darf auch die 14-Tage-Frist nicht neu starten.
      expect(b['korr_id'], isNull);
    });
  });

  group('list_vorschlag_korr traegt den Faxstand', () {
    late List<Map<String, dynamic>> korr;
    setUp(() {
      final j = jsonDecode(kKorrAntwort) as Map<String, dynamic>;
      korr = (j['korrespondenz'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    });

    test('genau die gefaxte Zeile traegt einen Stand', () {
      expect(korr.where((k) => k['fax'] is Map), hasLength(1));
      final mitFax = korr.firstWhere((k) => k['fax'] is Map);
      expect(mitFax['kontaktart'], 'fax');
      expect(mitFax['richtung'], 'ausgang');
    });

    test('die uebrigen Zeilen bleiben ausdruecklich ohne Stand', () {
      // `null` und nicht „fehlt": ein fehlender Schluessel und ein leeres
      // Fax saehen im Widget gleich aus, aber nur eins davon ist Absicht.
      for (final k in korr.where((k) => k['id'] != 8)) {
        expect(k.containsKey('fax'), isTrue);
        expect(k['fax'], isNull);
      }
    });

    test('der Betreff zeigt auf genau diesen Bericht', () {
      final mitFax = korr.firstWhere((k) => k['fax'] is Map);
      // Datum UND Uhrzeit — sonst liesse sich bei mehreren Berichten am
      // selben Tag nicht sagen, welcher gefaxt wurde.
      expect(mitFax['betreff'], contains('21.08.2026 20:22'));
    });
  });

  group('jcParseZeitpunkt', () {
    // ⚠️ Der Fehler, den das hier festhält, ist beim Rendern aufgefallen und
    // wäre durch Codelesen nie aufgefallen: `jcParseDatum` schneidet die Zeit
    // weg, das DATUM stimmte also — und jeder Bericht stand mit „00:00 Uhr"
    // auf dem Schirm. Genau die Uhrzeit unterscheidet aber zwei Berichte
    // desselben Tages voneinander.
    test('MySQL-Zeitstempel behält die Uhrzeit', () {
      final t = jcParseZeitpunkt('2026-08-21 20:22:30');
      expect(t, isNotNull);
      expect(t!.hour, 20);
      expect(t.minute, 22);
      expect(t.second, 30);
      expect(t.day, 21);
      expect(t.month, 8);
      expect(t.year, 2026);
    });

    test('jcParseDatum wirft dieselbe Zeit weg — deshalb gibt es beide', () {
      expect(jcParseDatum('2026-08-21 20:22:30')!.hour, 0);
      expect(jcParseZeitpunkt('2026-08-21 20:22:30')!.hour, 20);
    });

    test('ISO mit T wird ebenso gelesen', () {
      expect(jcParseZeitpunkt('2026-08-21T09:05:00')!.hour, 9);
      expect(jcParseZeitpunkt('2026-08-21T09:05')!.minute, 5);
    });

    test('reines Datum bleibt Mitternacht, leer bleibt null', () {
      expect(jcParseZeitpunkt('2026-08-21')!.hour, 0);
      expect(jcParseZeitpunkt(''), isNull);
      expect(jcParseZeitpunkt(null), isNull);
    });
  });

  group('jcFaxStandAnzeige', () {
    test('jeder Stand aus der ENUM-Spalte hat eigenen Text', () {
      // Genau die Werte der Spalte `sipgate_faxe.status`.
      const staende = ['vorbereitet', 'in_zustellung', 'zugestellt', 'fehlgeschlagen', 'storniert'];
      final texte = <String>{};
      for (final s in staende) {
        final (text, _, _) = jcFaxStandAnzeige(s);
        expect(text, isNot(s), reason: '$s faellt in den Vorgabezweig');
        texte.add(text);
      }
      expect(texte, hasLength(staende.length), reason: 'zwei Staende sagen dasselbe');
    });

    test('nur „zugestellt" darf angekommen sagen', () {
      // ⚠️ Der ganze Grund, warum der Stand ueberhaupt angezeigt wird: „an
      // sipgate uebergeben" ist NICHT „beim Jobcenter angekommen". Wer das
      // vermischt, laesst eine Frist gegen eine Meldung laufen, die nie ankam.
      final (zugestellt, _, _) = jcFaxStandAnzeige('zugestellt');
      expect(zugestellt.toLowerCase(), contains('angekommen'));
      for (final s in ['vorbereitet', 'in_zustellung', 'storniert']) {
        final (text, _, _) = jcFaxStandAnzeige(s);
        expect(text.toLowerCase(), isNot(contains('angekommen')), reason: s);
      }
      final (fehl, _, _) = jcFaxStandAnzeige('fehlgeschlagen');
      expect(fehl.toLowerCase(), contains('nicht angekommen'));
    });

    test('unbekannter Stand wird gezeigt statt verschluckt', () {
      final (text, icon, _) = jcFaxStandAnzeige('irgendwas_neues');
      expect(text, 'irgendwas_neues');
      expect(icon, Icons.help_outline);
      final (leer, _, _) = jcFaxStandAnzeige('');
      expect(leer, 'Unbekannt');
    });

    test('gescheitert ist rot, angekommen ist gruen', () {
      final (_, _, gruen) = jcFaxStandAnzeige('zugestellt');
      final (_, _, rot) = jcFaxStandAnzeige('fehlgeschlagen');
      expect(gruen, isNot(rot));
    });
  });
}
