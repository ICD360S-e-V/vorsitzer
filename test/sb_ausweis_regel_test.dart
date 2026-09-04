import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_versorgungsamt.dart';

/// Der Schwerbehindertenausweis ist meist befristet; die Verlaengerung wird
/// beim Versorgungsamt (ZBFS) fruehestens drei Monate vor Ablauf beantragt.
///
/// ⚠️ Dieselbe Rechnung steht im Server-Cron `sb_ausweis_ablauf_check.php`,
/// und PHP liegt in keinem Repo — hier ist die einzige Stelle, an der ein
/// Auseinanderlaufen auffallen kann.
void main() {
  group('Anstoss: drei Monate vorher, am Monatsende geklemmt', () {
    test('gewoehnlicher Fall', () {
      expect(sbAusweisAnstossTag(DateTime(2027, 3, 31)), DateTime(2026, 12, 31));
      expect(sbAusweisAnstossTag(DateTime(2027, 6, 15)), DateTime(2027, 3, 15));
    });

    test('kein Monatsueberlauf: 31.05. wird zum 28.02., nicht zum 03.03.', () {
      // Naiv gerechnet landet der 31. im Februar drei Tage im Maerz — die
      // Erinnerung kaeme zu SPAET, also genau in die schaedliche Richtung.
      expect(sbAusweisAnstossTag(DateTime(2027, 5, 31)), DateTime(2027, 2, 28));
      expect(sbAusweisAnstossTag(DateTime(2028, 5, 31)), DateTime(2028, 2, 29)); // Schaltjahr
      expect(sbAusweisAnstossTag(DateTime(2026, 12, 31)), DateTime(2026, 9, 30));
    });

    test('ueber die Jahresgrenze', () {
      expect(sbAusweisAnstossTag(DateTime(2027, 1, 31)), DateTime(2026, 10, 31));
      expect(sbAusweisAnstossTag(DateTime(2032, 2, 29)), DateTime(2031, 11, 29));
    });
  });

  group('Faelligkeit', () {
    final ablauf = DateTime(2027, 3, 31);

    test('einen Tag vor der Schwelle noch nicht', () {
      expect(sbAusweisFaellig(ablauf, DateTime(2026, 12, 30)), isFalse);
    });

    test('am Stichtag selbst schon', () {
      expect(sbAusweisFaellig(ablauf, DateTime(2026, 12, 31)), isTrue);
    });

    test('ein abgelaufener Ausweis bleibt faellig', () {
      // ⚠️ Anders als bei der Wertmarke, wo Ablauf das Ticket schliesst: ohne
      // gueltigen Ausweis entfallen die Nachteilsausgleiche, das ist der
      // dringendste Fall und nicht der Grund aufzuhoeren.
      expect(sbAusweisFaellig(ablauf, DateTime(2027, 8, 1)), isTrue);
    });

    test('unbefristet und leer erinnern nie', () {
      expect(sbAusweisFaellig(ablauf, DateTime(2027, 1, 1), unbefristet: true), isFalse);
      expect(sbAusweisFaellig(null, DateTime(2027, 1, 1)), isFalse);
    });
  });

  group('Datum lesen', () {
    test('nimmt ISO, sonst nichts', () {
      expect(sbAusweisAblaufLesen('2027-03-31'), DateTime(2027, 3, 31));
      expect(sbAusweisAblaufLesen('  2027-03-31 '), DateTime(2027, 3, 31));
    });

    test('leer heisst nicht erfasst, nicht unbefristet', () {
      // „unbefristet" ist ein eigenes Kaestchen; ein leeres Feld darf nicht als
      // „laeuft nie ab" durchgehen, sonst erinnert niemand mehr.
      expect(sbAusweisAblaufLesen(''), isNull);
      expect(sbAusweisAblaufLesen('31.03.2027'), isNull); // deutsches Format wird NICHT geraten
      expect(sbAusweisAblaufLesen('unbefristet'), isNull);
    });
  });

  group('Kopplung im Quelltext', () {
    test('der Hinweis haengt an der Gueltig-bis-Zeile', () {
      final q = File('lib/widgets/behorde_versorgungsamt.dart').readAsStringSync();
      // ⚠️ Zweimal: einmal die Deklaration, einmal der Aufruf im Aufbau. Ein
      // blosses contains() haette auch dann gehalten, wenn der Hinweis nur noch
      // definiert, aber nirgends mehr eingehaengt waere — genau der Zustand, den
      // niemand bemerkt. (Bei der Gegenprobe aufgefallen, nicht beim Schreiben.)
      expect(RegExp(r'_ausweisAblaufHinweis\(\)').allMatches(q).length, greaterThanOrEqualTo(2),
          reason: 'Der Hinweis ist definiert, aber nicht in den Aufbau eingehaengt');
      // Der Vorlauf steht an genau einer Stelle, nicht als Zahl im Text.
      expect(q.contains('kSbAusweisVorlaufMonate = 3'), isTrue);
    });
  });
}
