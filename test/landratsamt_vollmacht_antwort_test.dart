// Die Antwort von `landratsamt_vollmacht_versand.php?action=vorlagen`, so
// gelesen wie im Vollmacht-Reiter.
//
// ⚠️ Die Werte hier sind ERFUNDEN, die FORM ist die echte. Am 29.08.2026 wurde
// die reale Antwort auf dem Server ausgegeben und Feld für Feld abgeglichen;
// hineinkopiert wird sie nicht — dieses Repository ist öffentlich, und über
// mitgeschnittene echte Antworten sind hier schon dreimal Zugangsdaten
// abgeflossen. Ein Prüfcode oder ein Klarname gehört in keinen Testbaum.
//
// Was der Test festhält, ist die Falle, an der dieser Bildschirm sonst stirbt:
// PHP kennt nur EINEN Array-Typ. Eine leere Unterzeichnerliste kommt als `[]`
// heraus, eine gefüllte als `[{…}]`, und eine ältere Serverfassung liefert das
// Feld gar nicht. `as List` wirft in zwei dieser drei Fälle — im Release-Build
// als graue Fläche ohne jede Meldung.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/landratsamt_vollmacht_tab.dart';

/// Form der echten Antwort, mit erfundenen Werten.
const _vollstaendig = '''
{"success":true,"bereit":true,"unterschrieben":2,"noetig":2,"signatur_id":4711,
 "unterzeichner":[
   {"id":4711,"name":"Erika Mustermann","rolle":"vollmachtgeber",
    "status":"signiert","signiert_am":"01.02.2026 09:15",
    "signiert_am_utc":"2026-02-01 08:15:00"},
   {"id":4712,"name":"Max Mustermann","rolle":"bevollmaechtigter",
    "status":"offen","signiert_am":"","signiert_am_utc":""}]}
''';

/// Noch nichts zur Unterschrift gestellt — die Regel, nicht die Ausnahme.
const _leer = '{"success":true,"bereit":false,"unterschrieben":0,'
    '"noetig":0,"signatur_id":0,"unterzeichner":[]}';

/// Eine Serverfassung, die das Feld noch nicht kennt.
const _ohneFeld = '{"success":true,"bereit":false,"unterschrieben":0,"noetig":0}';

void main() {
  group('vollmachtFeldAlsZeilen', () {
    test('liest die Unterzeichner der echten Antwortform', () {
      final a = jsonDecode(_vollstaendig) as Map<String, dynamic>;
      final u = vollmachtFeldAlsZeilen(a['unterzeichner']);

      expect(u, hasLength(2));
      expect(u[0]['rolle'], 'vollmachtgeber');
      expect(u[0]['status'], 'signiert');
      expect(u[0]['signiert_am'], '01.02.2026 09:15');
      // ⚠️ Der zweite ist NICHT weggefiltert. Auf wen noch gewartet wird, ist
      // die eigentliche Auskunft — eine Liste nur der Fertigen sähe aus wie
      // „alles unterschrieben".
      expect(u[1]['rolle'], 'bevollmaechtigter');
      expect(u[1]['status'], 'offen');
    });

    test('leere PHP-Liste wirft nicht, sondern ergibt nichts', () {
      final a = jsonDecode(_leer) as Map<String, dynamic>;
      expect(vollmachtFeldAlsZeilen(a['unterzeichner']), isEmpty);
    });

    test('fehlendes Feld wirft nicht', () {
      final a = jsonDecode(_ohneFeld) as Map<String, dynamic>;
      expect(vollmachtFeldAlsZeilen(a['unterzeichner']), isEmpty);
    });

    test('ein Objekt statt einer Liste wirft nicht', () {
      // Käme es je als Objekt (weil jemand serverseitig Schlüssel vergibt),
      // ist eine leere Anzeige richtig — ein Absturz nie.
      expect(vollmachtFeldAlsZeilen(<String, dynamic>{'a': 1}), isEmpty);
      expect(vollmachtFeldAlsZeilen(null), isEmpty);
      expect(vollmachtFeldAlsZeilen('kaputt'), isEmpty);
    });

    test('Einträge, die keine Karte sind, reißen nicht alles mit', () {
      final u = vollmachtFeldAlsZeilen([
        {'id': 1, 'rolle': 'vollmachtgeber'},
        'unsinn',
        42,
      ]);
      expect(u, hasLength(1));
      expect(u.first['rolle'], 'vollmachtgeber');
    });
  });

  group('Stand der Unterschriften', () {
    // Die beiden Zustände, die der Reiter vor dem 29.08.2026 nicht auseinander
    // hielt: „beide haben unterschrieben" und „die gesiegelte Fassung liegt
    // vor". Gesiegelt wird in einem eigenen Lauf im Minutentakt, es gibt also
    // ein Fenster, in dem das erste stimmt und das zweite noch nicht. Wer sie
    // gleichsetzt, schreibt in genau diesem Fenster „erst unterschreiben
    // lassen" unter zwei fertige Unterschriften.
    bool vollstaendig(Map<String, dynamic> a) =>
        (a['noetig'] as int) > 0 &&
        (a['unterschrieben'] as int) >= (a['noetig'] as int);

    test('vollständig und gesiegelt', () {
      final a = jsonDecode(_vollstaendig) as Map<String, dynamic>;
      expect(vollstaendig(a), isTrue);
      expect(a['bereit'], isTrue);
    });

    test('nichts gestellt heißt nicht vollständig', () {
      final a = jsonDecode(_leer) as Map<String, dynamic>;
      // ⚠️ 0 von 0 ist NICHT „alles erledigt". Ohne die Bedingung `noetig > 0`
      // meldete der Reiter bei einer Vollmacht, die nie zur Unterschrift
      // gestellt wurde, beide Unterschriften lägen vor.
      expect(vollstaendig(a), isFalse);
      expect(a['signatur_id'], 0);
    });
  });
}
