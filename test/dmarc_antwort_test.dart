import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/screens/dmarc_screen.dart';
import 'package:icd360sev_vorsitzer/widgets/mail_korrespondenz_badge.dart';

/// Echte Antworten von api/admin/dmarc/berichte.php und
/// api/admin/dmarc/korrespondenz.php, aufgezeichnet am 23.08.2026 gegen die
/// laufende Datenbank (20 archivierte Mails, 20 ausgewertete Berichte).
///
/// ⚠️ Der Sinn ist NICHT, die Zahlen zu prüfen, sondern die FORM. PHP kennt
/// nur einen Array-Typ: `['a'=>1]` kodiert `json_encode` als Objekt, `[]`
/// dagegen als Liste. Ein `as Map` auf einer Liste liefert nicht null, sondern
/// wirft — genau daran blieb der Speedtest-Bildschirm am 05.08.2026 in der
/// Produktion beim Aufbau hängen und zeigte nur eine graue Fläche. Weder
/// `flutter analyze` noch die Widget-Tests sehen so etwas, weil keiner davon
/// die echte Serverantwort anfasst.

const String _berichte = r'''
{"success":true,"uebersicht":{"tage":30,"berichte":20,"melder":6,"nachrichten":44,"bestanden":44,"durchgefallen":0,"quote":100,"erster":"2026-08-13 00:00:00","letzter":"2026-08-22 23:59:59"},"tage":[{"tag":"2026-08-13","nachrichten":1,"bestanden":1,"durchgefallen":0},{"tag":"2026-08-22","nachrichten":3,"bestanden":3,"durchgefallen":0}],"quellen":[{"source_ip":"135.125.128.33","eigen":true,"eigen_name":"unser Mailserver","anzahl":44,"bestanden":44,"durchgefallen":0,"header_from":"icd360s.de","dkim_domain":"icd360s.de","dkim_selector":"rsa202607","spf_domain":"icd360s.de","disposition":"none","melder":6,"zuletzt":"2026-08-22 23:59:59"}],"berichte":[{"id":20,"korrespondenz_id":20,"org_name":"Yahoo","org_email":"dmarchelp@yahooinc.com","report_id":"1787462884.873041","domain":"icd360s.de","zeit_von":"2026-08-22 00:00:00","zeit_bis":"2026-08-22 23:59:59","policy_p":"reject","policy_sp":"","policy_pct":100,"adkim":"r","aspf":"r","nachrichten":1,"bestanden":1,"durchgefallen":0,"dateiname":"yahoo.com!icd360s.de!1787356800!1787443199.xml.gz","created_at":"2026-08-23 22:48:16"},{"id":18,"korrespondenz_id":18,"org_name":"WEB.DE","org_email":"noreply-dmarc@sicher.web.de","report_id":"bafac325891a43bdb547d4f6739cacd6","domain":"icd360s.de","zeit_von":"2026-08-22 00:00:00","zeit_bis":"2026-08-22 23:59:59","policy_p":"reject","policy_sp":"reject","policy_pct":null,"adkim":"r","aspf":"r","nachrichten":1,"bestanden":1,"durchgefallen":0,"dateiname":"web.de!icd360s.de!1787356800!1787443199!bafac325891a43bdb547d4f6739cacd6.xml.gz","created_at":"2026-08-23 22:48:16"}],"message":"OK"}
''';

/// Kein einziger Bericht: PHP macht aus jeder der drei Listen `[]`, nicht `{}`.
/// `uebersicht` bleibt ein Objekt, weil es String-Schlüssel hat — genau die
/// Mischung, an der ein pauschales `as Map` scheitert.
const String _berichteLeer = r'''
{"success":true,"uebersicht":{"tage":30,"berichte":0,"melder":0,"nachrichten":0,"bestanden":0,"durchgefallen":0,"quote":null,"erster":null,"letzter":null},"tage":[],"quellen":[],"berichte":[],"message":"OK"}
''';

/// Ein archivierter Bericht aus korrespondenz.php. Der Anhang ist ein ZIP,
/// kein PDF — deshalb hat die Datei-Kachel hier ein anderes Symbol und der
/// Inhalt steht im Tab „Berichte", nicht im Dateibetrachter.
const String _korrespondenz = r'''
{"success":true,"korrespondenz":[{"id":19,"richtung":"eingang","weg":"email","datum":"2026-08-23 11:49:08","betreff":"Report domain: icd360s.de Submitter: google.com Report-ID: 13993825246748190726","absender":"noreply-dmarc-support@google.com","empfaenger":"dmarc@icd360s.de","gespraechspartner":"","notiz":"","quelle":"mail","created_by":"cron","created_at":"2026-08-23 22:48:16","dateien":[{"id":37,"original_name":"Nachricht_2026-08-22.eml","file_size":2318,"mime_type":"message/rfc822","rolle":"eml","created_at":"2026-08-23 22:48:16"},{"id":38,"original_name":"google.com!icd360s.de!1787356800!1787443199.zip","file_size":954,"mime_type":"application/zip","rolle":"attachment","created_at":"2026-08-23 22:48:16"}]}],"count":1}
''';

void main() {
  group('Antwortform berichte.php', () {
    test('die drei Listen sind Listen, uebersicht ist eine Map', () {
      final r = jsonDecode(_berichte) as Map<String, dynamic>;
      expect(r['tage'], isA<List>());
      expect(r['quellen'], isA<List>());
      expect(r['berichte'], isA<List>());
      expect(r['uebersicht'], isA<Map>());

      expect(dmarcListe(r['quellen']), hasLength(1));
      expect(dmarcMap(r['uebersicht'])['nachrichten'], 44);
    });

    test('leere Antwort wirft nicht — Listen bleiben Listen', () {
      final r = jsonDecode(_berichteLeer) as Map<String, dynamic>;
      expect(dmarcListe(r['tage']), isEmpty);
      expect(dmarcListe(r['quellen']), isEmpty);
      expect(dmarcListe(r['berichte']), isEmpty);
      expect(dmarcMap(r['uebersicht'])['berichte'], 0);
    });

    test('eine Liste als uebersicht ergibt Leeres statt einer Ausnahme', () {
      // Der Fall, der den Speedtest-Schirm grau werden liess: derselbe Platz
      // kommt einmal als Objekt und einmal als Liste zurück.
      expect(() => dmarcMap(const []), returnsNormally);
      expect(dmarcMap(const []), isEmpty);
      expect(dmarcListe(const {'a': 1}), isEmpty);
    });

    test('quote ist einmal Ganzzahl, einmal null — beides muss tragen', () {
      // json_encode schreibt round(100.0, 1) als `100`, nicht als `100.0`.
      // Ein `as double` würde hier werfen; deshalb liest der Schirm num.
      final voll = dmarcMap(jsonDecode(_berichte)['uebersicht']);
      final leer = dmarcMap(jsonDecode(_berichteLeer)['uebersicht']);
      expect(voll['quote'], isA<int>());
      expect((voll['quote'] as num?)?.toDouble(), 100.0);
      expect(leer['quote'], isNull);
      expect((leer['quote'] as num?)?.toDouble(), isNull);
    });

    test('policy_pct darf null sein — WEB.DE schickt es nicht', () {
      final liste = dmarcListe(jsonDecode(_berichte)['berichte']);
      expect(liste.firstWhere((b) => b['org_name'] == 'WEB.DE')['policy_pct'], isNull);
      expect(liste.firstWhere((b) => b['org_name'] == 'Yahoo')['policy_pct'], 100);
    });
  });

  group('Antwortform korrespondenz.php (modul dmarc)', () {
    test('Eintrag trägt .eml und den gepackten Bericht', () {
      final r = jsonDecode(_korrespondenz) as Map<String, dynamic>;
      final eintraege = dmarcListe(r['korrespondenz']);
      expect(eintraege, hasLength(1));

      final dateien = dmarcListe(eintraege.first['dateien']);
      expect(dateien.map((f) => f['rolle']), containsAll(['eml', 'attachment']));

      // Der Anhang ist ein ZIP. Das ist der Grund für den ganzen
      // Auswertungs-Tab: der Dateibetrachter kennt PDFs und Bilder.
      final anhang = dateien.firstWhere((f) => f['rolle'] == 'attachment');
      expect(anhang['mime_type'], 'application/zip');
      expect(anhang['original_name'], endsWith('.zip'));

      expect(eintraege.first['quelle'], 'mail');
      expect(eintraege.first['empfaenger'], 'dmarc@icd360s.de');
    });
  });

  group('dmarcZeit', () {
    test('formatiert Datum mit und ohne Uhrzeit', () {
      expect(dmarcZeit('2026-08-22 23:59:59'), '22.08.2026 23:59');
      expect(dmarcZeit('2026-08-22'), '22.08.2026');
    });

    test('gibt Unlesbares unverändert zurück, statt zu werfen', () {
      expect(dmarcZeit(''), '');
      expect(dmarcZeit('unbekannt'), 'unbekannt');
    });
  });

  group('Mail-Plakette', () {
    testWidgets('ein DMARC-Archiv wird benannt, nicht als Schlüssel gezeigt', (t) async {
      // ⚠️ Diese Kopplung fällt sonst still aus: der Server legt ab, der
      // Client zeigt „dmarc" neben einem allgemeinen Ordnersymbol.
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: MailKorrespondenzBadge(
            eintraege: [
              {'bereich': 'dmarc', 'korrespondenz_id': 19, 'datum': '2026-08-23', 'dateien': 2}
            ],
            compact: false,
          ),
        ),
      ));
      expect(find.textContaining('DMARC'), findsWidgets);
    });
  });
}
