import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/screens/ovh_screen.dart';
import 'package:icd360sev_vorsitzer/services/api_service.dart';
import 'package:icd360sev_vorsitzer/widgets/mail_korrespondenz_badge.dart';

/// Echte Antwort von api/admin/ovh/korrespondenz.php, aufgezeichnet am
/// 24.08.2026 gegen die laufende Datenbank (16 archivierte Nachrichten).
///
/// ⚠️ Der Sinn ist die FORM, nicht die Zahlen. PHP kennt nur einen Array-Typ:
/// eine lückenlose Liste kodiert als `[]`, dieselbe Struktur mit
/// String-Schlüsseln als Objekt. Ein `as Map` auf einer Liste wirft — genau
/// daran blieb der Speedtest-Bildschirm am 05.08.2026 in der Produktion grau
/// hängen.
const String _korrespondenz = r'''
{"success":true,"korrespondenz":[{"id":16,"richtung":"eingang","weg":"email","datum":"2026-08-24 20:40:54","betreff":"[qm40639-ovh] Verlängerung Ihrer Dienste - qm40639-ovh","absender":"OVH Kundendienst <support@services.ovhcloud.com>","empfaenger":"ovh@icd360s.de","gespraechspartner":"","notiz":"","quelle":"mail","created_by":"cron","created_at":"2026-08-24 22:47:48","dateien":[{"id":16,"original_name":"Nachricht_2026-08-24.eml","file_size":5916,"mime_type":"message/rfc822","rolle":"eml","created_at":"2026-08-24 22:47:48"}]},{"id":15,"richtung":"eingang","weg":"email","datum":"2026-08-24 06:01:07","betreff":"[qm40639-ovh] Verlängerung Ihrer Dienste - qm40639-ovh","absender":"OVH Kundendienst <support@services.ovhcloud.com>","empfaenger":"ovh@icd360s.de","gespraechspartner":"","notiz":"","quelle":"mail","created_by":"cron","created_at":"2026-08-24 22:47:48","dateien":[{"id":15,"original_name":"Nachricht_2026-08-24.eml","file_size":5993,"mime_type":"message/rfc822","rolle":"eml","created_at":"2026-08-24 22:47:48"}]}],"count":2}
''';

/// Noch nichts archiviert: `korrespondenz` ist `[]`, nicht `{}`.
const String _leer = r'''
{"success":true,"korrespondenz":[],"count":0}
''';

void main() {
  group('Antwortform korrespondenz.php (modul ovh)', () {
    test('Liste bleibt Liste, Eintrag trägt die .eml', () {
      final r = jsonDecode(_korrespondenz) as Map<String, dynamic>;
      expect(r['korrespondenz'], isA<List>());

      final eintraege = ovhListe(r['korrespondenz']);
      expect(eintraege, hasLength(2));
      expect(eintraege.first['empfaenger'], 'ovh@icd360s.de');
      expect(eintraege.first['quelle'], 'mail');
      expect(eintraege.first['richtung'], 'eingang');

      // ⚠️ OVH hängt nichts an — Rechnungen sind ein Link ins Kundencenter.
      // Für dieses Archiv IST die .eml der Inhalt; fiele sie weg, bliebe vom
      // Eintrag eine Betreffzeile und sonst nichts.
      final dateien = ovhListe(eintraege.first['dateien']);
      expect(dateien, hasLength(1));
      expect(dateien.first['rolle'], 'eml');
      expect(dateien.first['mime_type'], 'message/rfc822');
    });

    test('leere Antwort wirft nicht', () {
      final r = jsonDecode(_leer) as Map<String, dynamic>;
      expect(ovhListe(r['korrespondenz']), isEmpty);
      // Eine Liste — auch die leere — ist keine Map und darf keine werden.
      expect(ovhMap(r['korrespondenz']), isEmpty);
    });

    test('fehlende Felder ergeben Leeres statt einer Ausnahme', () {
      expect(ovhListe(null), isEmpty);
      expect(ovhListe(<String, dynamic>{}), isEmpty);
      expect(ovhMap(<dynamic>[]), isEmpty);
      expect(ovhMap(null), isEmpty);
    });
  });

  group('ovhZeit', () {
    test('formatiert Datum mit und ohne Uhrzeit', () {
      expect(ovhZeit('2026-08-24 20:40:54'), '24.08.2026 20:40');
      expect(ovhZeit('2026-08-24'), '24.08.2026');
    });

    test('gibt Unlesbares unverändert zurück, statt zu werfen', () {
      expect(ovhZeit(''), '');
      expect(ovhZeit('unbekannt'), 'unbekannt');
    });
  });

  group('Erklärung', () {
    testWidgets('sagt, was übernommen wird und was hier NICHT steht', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => ElevatedButton(
              onPressed: () => ovhErklaerungZeigen(c),
              child: const Text('?'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('?'));
      await t.pumpAndSettle();

      expect(find.text('Was ist OVH?'), findsOneWidget);
      for (final ueberschrift in const [
        'Kurz gesagt',
        'Was hier ankommt',
        'Warum es archiviert wird',
        'Was übernommen wird',
        'Was hier nicht steht',
      ]) {
        expect(find.text(ueberschrift), findsOneWidget, reason: ueberschrift);
      }

      // Zwei Sätze, die nicht wegfallen dürfen: warum es kein Auswertungs-Tab
      // gibt, und dass ein Teil der OVH-Post weiterhin nur im Postfach liegt.
      // Ohne den zweiten hielte man das Archiv für vollständig.
      expect(find.textContaining('Zahlen daraus zu bilden'), findsOneWidget);
      expect(find.textContaining('icd@icd360s.de'), findsOneWidget);
    });
  });

  group('Zwei Tabs', () {
    test('Korrespondenz steht vorn, Online-Konto daneben', () {
      expect(kOvhTabs, ['Korrespondenz', 'Online-Konto']);
    });

    testWidgets('beide Tabs werden angeschrieben', (t) async {
      // ⚠️ KEIN pumpAndSettle: der Korrespondenz-Tab zeigt beim Start einen
      // CircularProgressIndicator, und der läuft endlos. pumpAndSettle würde
      // hier nicht scheitern, sondern hängen — bis der Test nach zehn Minuten
      // abgeschossen wird und niemand weiss, warum.
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OvhScreen(apiService: ApiService(), onBack: () {}),
        ),
      ));
      await t.pump();

      for (final name in kOvhTabs) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
    });
  });

  group('Platzhalter Online-Konto', () {
    // ⚠️ Der eigentliche Punkt dieses Bereichs: solange nichts abgerufen wird,
    // darf dort keine Zahl stehen. Ein Platzhalter mit einem Betrag oder einer
    // Laufzeit sieht fertig aus, und niemand prüft eine Zahl nach, die
    // dasteht, als käme sie vom Anbieter.
    test('trägt keine einzige Ziffer', () {
      for (final z in [...kOvhKontoGeplant, kOvhKontoHinweis]) {
        expect(RegExp(r'[0-9]').hasMatch(z), isFalse, reason: z);
      }
    });

    test('ist als noch nicht fertig beschriftet', () {
      expect(kOvhKontoHinweis, contains('Zukunft'));
      expect(kOvhKontoGeplant, isNotEmpty);
    });
  });

  group('Mail-Plakette', () {
    testWidgets('OVH wird benannt, nicht als roher Schlüssel gezeigt', (t) async {
      // ⚠️ Ohne den Eintrag in _bereiche bekäme die Mail zwar ein Abzeichen —
      // der Endpunkt liefert den Bereich ja —, aber beschriftet mit `ovh`
      // neben einem allgemeinen Ordner-Symbol.
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: MailKorrespondenzBadge(
            eintraege: [
              {'bereich': 'ovh', 'korrespondenz_id': 16, 'datum': '2026-08-24', 'dateien': 1}
            ],
            compact: false,
          ),
        ),
      ));
      expect(find.textContaining('OVHcloud'), findsWidgets);
      expect(find.textContaining('bereich'), findsNothing);
    });
  });
}
