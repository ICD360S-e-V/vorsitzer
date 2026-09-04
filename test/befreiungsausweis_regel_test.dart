import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_krankenkasse.dart';

/// Der Befreiungsausweis (Zuzahlungsbefreiung) gilt fuer ein Kalenderjahr und
/// laeuft am 31.12. ab. Erinnert wird zwei Monate vorher.
///
/// ⚠️ Dieselben drei Regeln stehen im Server-Cron
/// `api/cron/befreiungsausweis_ablauf_check.php`, und PHP liegt in keinem
/// Repo — hier ist die einzige Stelle, an der ein Auseinanderlaufen auffallen
/// kann. Vor allem der Betreff: an ihm erkennt `tickets/admin_create.php` das
/// Duplikat, weicht er ab, bekommt das Mitglied zwei Tickets zur selben Sache.
void main() {
  group('Anstoss: 1. November, nicht der erste Montag', () {
    test('ist genau zwei Monate vor dem Ablauf', () {
      expect(befreiungAnstossTag(2026), DateTime(2026, 11, 1));
      expect(befreiungAnstossTag(2027), DateTime(2027, 11, 1));
    });

    test('haengt nicht am Wochentag', () {
      // 01.11.2026 ist ein Sonntag; die fruehere Regel „erster Montag im
      // November" haette erst am 02.11. ausgeloest — einen Tag spaeter als
      // der Cron, und damit an zwei verschiedenen Tagen fuer dieselbe Sache.
      expect(befreiungAnstossTag(2026).weekday, DateTime.sunday);
      expect(befreiungAnstossTag(2026).day, 1);
    });

    test('am 31.10. noch nicht, am 01.11. schon', () {
      expect(befreiungLaeuftBaldAb(2026, DateTime(2026, 10, 31, 23, 59)), isFalse);
      expect(befreiungLaeuftBaldAb(2026, DateTime(2026, 11, 1)), isTrue);
      expect(befreiungLaeuftBaldAb(2026, DateTime(2026, 12, 31)), isTrue);
    });

    test('ein Ausweis eines anderen Jahres loest die Warnung nicht aus', () {
      // 2025 ist abgelaufen (eigener Zustand isExpired), 2027 noch nicht dran.
      expect(befreiungLaeuftBaldAb(2025, DateTime(2026, 11, 1)), isFalse);
      expect(befreiungLaeuftBaldAb(2027, DateTime(2026, 11, 1)), isFalse);
    });
  });

  group('Zieljahr', () {
    test('laufender Ausweis: das Folgejahr', () {
      expect(befreiungZieljahr(2026, DateTime(2026, 11, 1)), 2027);
    });

    test('abgelaufener Ausweis: das laufende Jahr', () {
      expect(befreiungZieljahr(2025, DateTime(2026, 3, 5)), 2026);
    });

    test('im Voraus erfasster Ausweis rechnet vom AUSWEISJAHR, nicht von heute', () {
      // Sonst hiesse das Ticket des Knopfes anders als das des Crons — und der
      // Betreff ist alles, woran der Server das Duplikat erkennt.
      expect(befreiungZieljahr(2027, DateTime(2026, 11, 1)), 2028);
    });
  });

  group('Betreff', () {
    test('ist zeichengleich mit dem des Crons', () {
      expect(befreiungTicketBetreff(2027), 'Befreiungsausweis 2027 beantragen');
      expect(befreiungTicketBetreff(2026), 'Befreiungsausweis 2026 beantragen');
    });
  });

  group('Kopplung im Quelltext', () {
    late String quelle;
    setUpAll(() {
      quelle = File('lib/widgets/behorde_krankenkasse.dart').readAsStringSync();
    });

    test('der Knopf laesst den Server auf Duplikate pruefen', () {
      // Ohne das entstuende beim Druck auf den Knopf ein zweites Ticket neben
      // dem, das der Cron ab dem 1. November schon angelegt hat.
      final ab = quelle.indexOf('befreiungTicketBetreff(nextYear)');
      expect(ab, greaterThan(0), reason: 'Betreff des Knopfes nicht gefunden');
      final block = quelle.substring(ab, ab + 900);
      expect(block.contains('dedupeSubject: true'), isTrue,
          reason: 'Der Befreiungs-Knopf schickt kein dedupe_subject');
    });

    test('keine Montagsverschiebung mehr im Befreiungsteil', () {
      expect(quelle.contains('firstMondayNov'), isFalse);
      expect(quelle.contains('DateTime.monday - novFirst.weekday'), isFalse);
    });
  });
}
