import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/screens/tlsrpt_screen.dart';
import 'package:icd360sev_vorsitzer/widgets/mail_korrespondenz_badge.dart';

/// Echte Antworten von api/admin/tlsrpt/berichte.php und
/// api/admin/tlsrpt/korrespondenz.php, aufgezeichnet am 24.08.2026 gegen die
/// laufende Datenbank (7 archivierte Mails, 7 ausgewertete Berichte).
///
/// ⚠️ Der Sinn ist die FORM, nicht die Zahlen. PHP kennt nur einen Array-Typ:
/// eine lückenlose Liste kodiert als `[]`, dieselbe Struktur mit
/// String-Schlüsseln als Objekt. Ein `as Map` auf einer Liste wirft — genau
/// daran blieb der Speedtest-Bildschirm am 05.08.2026 in der Produktion grau
/// hängen. Hier trifft das doppelt: `fehler` ist heute leer, also eine LISTE,
/// und `richtlinie` ist ein OBJEKT im selben Block.

const String _berichte = r'''
{"success":true,"uebersicht":{"tage":30,"berichte":7,"melder":1,"sitzungen":24,"erfolgreich":24,"fehlgeschlagen":0,"quote":100,"erster":"2026-08-13 00:00:00","letzter":"2026-08-22 23:59:59","richtlinie":{"typ":"sts","modus":"enforce","domain":"icd360s.de","mx":"mail.icd360s.de","stand":"2026-08-22 23:59:59"}},"tage":[{"tag":"2026-08-13","erfolgreich":1,"fehlgeschlagen":0},{"tag":"2026-08-18","erfolgreich":10,"fehlgeschlagen":0}],"fehler":[],"berichte":[{"id":7,"korrespondenz_id":7,"org_name":"Google Inc.","kontakt":"smtp-tls-reporting@google.com","report_id":"2026-08-22T00:00:00Z_icd360s.de","policy_index":0,"policy_typ":"sts","policy_domain":"icd360s.de","policy_modus":"enforce","mx_hosts":"mail.icd360s.de","zeit_von":"2026-08-22 00:00:00","zeit_bis":"2026-08-22 23:59:59","erfolgreich":1,"fehlgeschlagen":0,"dateiname":"google.com!icd360s.de!1787356800!1787443199!001.json.gz","created_at":"2026-08-24 00:17:24"}],"message":"OK"}
''';

/// Noch kein Bericht: alle drei Listen sind `[]`, `richtlinie` ist `null` —
/// und `uebersicht` bleibt trotzdem ein Objekt.
const String _berichteLeer = r'''
{"success":true,"uebersicht":{"tage":30,"berichte":0,"melder":0,"sitzungen":0,"erfolgreich":0,"fehlgeschlagen":0,"quote":null,"erster":null,"letzter":null,"richtlinie":null},"tage":[],"fehler":[],"berichte":[],"message":"OK"}
''';

/// Ein erfundener Fehlerfall — bei uns steht dort bisher nichts, und genau
/// deshalb muss die Form einmal festgehalten werden: wenn es je so weit
/// kommt, ist keine Zeit, das Anzeigeformat zu erraten.
const String _berichteMitFehler = r'''
{"success":true,"uebersicht":{"tage":30,"berichte":2,"melder":1,"sitzungen":12,"erfolgreich":9,"fehlgeschlagen":3,"quote":75,"erster":"2026-08-20 00:00:00","letzter":"2026-08-21 23:59:59","richtlinie":{"typ":"sts","modus":"enforce","domain":"icd360s.de","mx":"mail.icd360s.de","stand":"2026-08-21 23:59:59"}},"tage":[],"fehler":[{"ergebnis":"certificate-expired","anzahl":3,"quellen":1,"empfangender_mx":"mail.icd360s.de","grund_code":"","zusatz":"","zuletzt":"2026-08-21 23:59:59"}],"berichte":[],"message":"OK"}
''';

/// Ein archivierter Bericht. Der Anhang trägt den eigenen Medientyp aus
/// RFC 8460 — nicht application/gzip.
const String _korrespondenz = r'''
{"success":true,"korrespondenz":[{"id":7,"richtung":"eingang","weg":"email","datum":"2026-08-23 15:03:54","betreff":"Report Domain: icd360s.de Submitter: google.com Report-ID: <2026.08.22T00.00.00Z+icd360s.de@google.com>","absender":"noreply-smtp-tls-reporting@google.com","empfaenger":"tls-rpt@icd360s.de","gespraechspartner":"","notiz":"","quelle":"mail","created_by":"cron","created_at":"2026-08-24 00:17:24","dateien":[{"id":13,"original_name":"Nachricht_2026-08-23.eml","file_size":4540,"mime_type":"message/rfc822","rolle":"eml","created_at":"2026-08-24 00:17:24"},{"id":14,"original_name":"google.com!icd360s.de!1787356800!1787443199!001.json.gz","file_size":305,"mime_type":"application/tlsrpt+gzip","rolle":"attachment","created_at":"2026-08-24 00:17:24"}]}],"count":1}
''';

void main() {
  group('Antwortform berichte.php', () {
    test('Listen bleiben Listen, uebersicht und richtlinie sind Maps', () {
      final r = jsonDecode(_berichte) as Map<String, dynamic>;
      expect(r['tage'], isA<List>());
      expect(r['fehler'], isA<List>());
      expect(r['berichte'], isA<List>());
      expect(r['uebersicht'], isA<Map>());

      final u = tlsrptMap(r['uebersicht']);
      expect(u['sitzungen'], 24);
      expect(tlsrptMap(u['richtlinie'])['modus'], 'enforce');
    });

    test('leere Antwort wirft nicht — auch richtlinie darf null sein', () {
      final r = jsonDecode(_berichteLeer) as Map<String, dynamic>;
      expect(tlsrptListe(r['fehler']), isEmpty);
      expect(tlsrptListe(r['berichte']), isEmpty);
      final u = tlsrptMap(r['uebersicht']);
      expect(u['richtlinie'], isNull);
      expect(tlsrptMap(u['richtlinie']), isEmpty);
      expect(u['quote'], isNull);
    });

    test('quote ist Ganzzahl, wenn sie glatt aufgeht', () {
      // json_encode schreibt round(100.0, 1) als `100`, nicht `100.0`.
      final u = tlsrptMap(jsonDecode(_berichte)['uebersicht']);
      expect(u['quote'], isA<int>());
      expect((u['quote'] as num?)?.toDouble(), 100.0);
    });

    test('ein Fehlerfall trägt Art, Anzahl und Quellen', () {
      final r = jsonDecode(_berichteMitFehler) as Map<String, dynamic>;
      final f = tlsrptListe(r['fehler']);
      expect(f, hasLength(1));
      expect(f.first['ergebnis'], 'certificate-expired');
      expect(f.first['anzahl'], 3);
      expect(f.first['quellen'], 1);
    });
  });

  group('Antwortform korrespondenz.php (modul tlsrpt)', () {
    test('Eintrag trägt .eml und den gepackten Bericht', () {
      final eintraege = tlsrptListe(jsonDecode(_korrespondenz)['korrespondenz']);
      expect(eintraege, hasLength(1));
      expect(eintraege.first['empfaenger'], 'tls-rpt@icd360s.de');
      expect(eintraege.first['quelle'], 'mail');

      final dateien = tlsrptListe(eintraege.first['dateien']);
      expect(dateien.map((f) => f['rolle']), containsAll(['eml', 'attachment']));

      // ⚠️ Eigener Medientyp aus RFC 8460, nicht application/gzip. Ein Filter,
      // der nur auf gzip prüft, liesse den Bericht liegen.
      final anhang = dateien.firstWhere((f) => f['rolle'] == 'attachment');
      expect(anhang['mime_type'], 'application/tlsrpt+gzip');
      expect(anhang['original_name'], endsWith('.json.gz'));
    });
  });

  group('tlsrptZeit', () {
    test('formatiert Datum mit und ohne Uhrzeit', () {
      expect(tlsrptZeit('2026-08-22 23:59:59'), '22.08.2026 23:59');
      expect(tlsrptZeit('2026-08-22'), '22.08.2026');
    });

    test('gibt Unlesbares unverändert zurück, statt zu werfen', () {
      expect(tlsrptZeit(''), '');
      expect(tlsrptZeit('unbekannt'), 'unbekannt');
    });
  });

  group('Erklärung', () {
    testWidgets('erklärt vor allem den Unterschied zu DMARC', (t) async {
      // ⚠️ Die beiden Bereiche sehen sich zum Verwechseln ähnlich: gleicher
      // Weg, gleiche Absender, gleicher Kachel-Nachbar. Wer sie verwechselt,
      // liest die Zahlen falsch herum — deshalb steht der Unterschied ganz
      // oben und nicht in einer Fussnote.
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => ElevatedButton(
              onPressed: () => tlsrptErklaerungZeigen(c),
              child: const Text('?'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('?'));
      await t.pumpAndSettle();

      expect(find.text('Was ist TLS-RPT?'), findsOneWidget);
      for (final ueberschrift in const [
        'Kurz gesagt',
        'Der Unterschied zu DMARC',
        'Warum das für den Verein zählt',
        'Was wir eingestellt haben',
        'Warum genau das gefährlich werden kann',
        'Wie man die Zahlen liest',
        'Was hier nicht steht',
      ]) {
        expect(find.text(ueberschrift), findsOneWidget, reason: ueberschrift);
      }

      // Die stille Ablehnung bei „enforce" ist der Grund, warum es diesen
      // Bereich überhaupt gibt — der Satz darf nicht wegfallen.
      expect(find.textContaining('liefert er gar nicht'), findsOneWidget);
      expect(find.textContaining('ausschliesslich Google'), findsOneWidget);
    });
  });

  group('Mail-Plakette', () {
    testWidgets('TLS-RPT wird benannt und nicht mit DMARC verwechselt',
        (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: MailKorrespondenzBadge(
            eintraege: [
              {'bereich': 'tlsrpt', 'korrespondenz_id': 7, 'datum': '2026-08-23', 'dateien': 2}
            ],
            compact: false,
          ),
        ),
      ));
      expect(find.textContaining('TLS-RPT'), findsWidgets);
      expect(find.textContaining('tlsrpt'), findsNothing);
    });
  });
}
