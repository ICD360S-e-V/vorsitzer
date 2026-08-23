import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/anruf_badge_service.dart';

/// Gemessen am 23.08.2026: **58 verpasste eingehende Anrufe in zehn Tagen**,
/// jeden Tag zwischen einem und zwanzig. Zu sehen waren sie ausschliesslich im
/// Verlauf innerhalb des sipgate-Bildschirms — kein Abzeichen, keine Meldung
/// im Nachhinein.
///
/// Anders als beim Fax kann die Zahl nicht bei sipgate geholt werden: am
/// selben Tag gemessen liefert `GET /history?types=CALL` auf diesem Konto null
/// Positionen, während `/history` ohne Filter acht FAX-Positionen zurückgibt.
/// Sie kommt deshalb aus unserer eigenen Tabelle, und der Bildschirm schreibt
/// diese Grenze hin.
void main() {
  group('verpasst_ungesehen aus der Antwort', () {
    test('eine Zahl wird übernommen', () {
      expect(anrufVerpassteAusAntwort({'verpasst_ungesehen': 3}), 3);
      expect(anrufVerpassteAusAntwort({'verpasst_ungesehen': 0}), 0);
    });

    test('auch als double — PHP entscheidet das nicht immer gleich', () {
      // Dieselbe Falle wie beim Fax: ein `as int` auf einem `double` wirft
      // erst im Release-Build beim Benutzer.
      expect(anrufVerpassteAusAntwort({'verpasst_ungesehen': 3.0}), 3);
    });

    test('fehlt das Feld, ist die Antwort null — NICHT null Anrufe', () {
      // Der Unterschied entscheidet, ob ein bestehendes Abzeichen stehen
      // bleibt oder faelschlich erlischt.
      expect(anrufVerpassteAusAntwort({'success': true}), isNull);
      expect(anrufVerpassteAusAntwort({'verpasst_ungesehen': null}), isNull);
      expect(anrufVerpassteAusAntwort({'verpasst_ungesehen': 'zwei'}), isNull);
    });

    test('etwas Negatives wird nicht durchgereicht', () {
      expect(anrufVerpassteAusAntwort({'verpasst_ungesehen': -1}), 0);
    });
  });

  group('der Dienst haelt den letzten bekannten Stand', () {
    test('uebernehmen setzt die Zahl', () {
      final d = AnrufBadgeService();
      d.verpasst.value = 0;
      d.uebernehmen({'verpasst_ungesehen': 4});
      expect(d.verpasst.value, 4);
    });

    test('eine Antwort ohne die Zahl loescht das Abzeichen NICHT', () {
      // Genau hier waere eine erfundene 0 der Schaden: ein Netzfehler wuerde
      // die Meldung wegnehmen, auf die jemand noch reagieren muss.
      final d = AnrufBadgeService();
      d.verpasst.value = 4;
      d.uebernehmen({'success': true});
      expect(d.verpasst.value, 4);
    });

    test('null wird uebernommen, wenn sie wirklich dasteht', () {
      final d = AnrufBadgeService();
      d.verpasst.value = 4;
      d.uebernehmen({'verpasst_ungesehen': 0});
      expect(d.verpasst.value, 0);
    });
  });
}
