import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/sozialamt_korr_optionen.dart';

/// ⚠️ Das PHP liegt in KEINEM Repository. Diese Datei ist deshalb die einzige
/// Stelle im Baum, an der auffallen kann, dass die Auswahllisten des
/// Schriftwechsels von der Datenbank abgedriftet sind.
void main() {
  // Wortgleich mit dem ENUM `weg` der Tabelle `sozialamt_antrag_korrespondenz`
  // und mit `KORR_WEGE` in `api/admin/sozialamt_antrag_detail.php`
  // (Stand 2026-09-04). Wer hier etwas ergänzt, ändert zuerst beides dort —
  // sonst antwortet der Server mit HTTP 400 „Unbekannter Weg", und zwar erst
  // in dem Augenblick, in dem jemand genau diesen Weg wählt.
  const serverEnum = <String>{
    'post', 'einschreiben', 'email', 'de_mail', 'online',
    'fax', 'telefon', 'persoenlich', 'sonstiges',
  };

  group('Wege', () {
    test('Schlüssel sind genau das Server-ENUM', () {
      expect(kSozKorrWege.keys.toSet(), serverEnum);
    });

    test('die vom Verein genannten Wege sind dabei', () {
      // Die Liste, die der Vorsitzende ausdrücklich verlangt hat.
      for (final w in ['online', 'fax', 'email', 'post', 'persoenlich']) {
        expect(kSozKorrWege.containsKey(w), isTrue, reason: 'Weg „$w" fehlt');
      }
    });

    test('Vorgabe ist ein gültiger Wert', () {
      expect(serverEnum.contains(kSozKorrWegVorgabe), isTrue);
    });

    test('jede Beschriftung ist gesetzt und einmalig', () {
      expect(kSozKorrWege.values.any((v) => v.trim().isEmpty), isFalse);
      expect(kSozKorrWege.values.toSet().length, kSozKorrWege.length);
    });

    test('Richtungen sind genau die zwei Knöpfe', () {
      expect(kSozKorrRichtungen, ['eingang', 'ausgang']);
    });
  });

  group('Anhänge', () {
    test('Endungen decken sich mit KORR_ENDUNGEN des Endpunkts', () {
      expect(kSozKorrEndungen.toSet(), {'pdf', 'jpg', 'jpeg', 'png'});
    });

    test('Obergrenze ist die vom Vorsitzenden verlangte', () {
      expect(kSozKorrMaxDateien, 20);
    });
  });

  // Die folgenden Prüfungen lesen den Quelltext, weil das Geprüfte sonst nur
  // ein laufender Dialog mit angemeldetem Server zeigen würde. Gegenprobe
  // gemacht: nimmt man die jeweilige Zeile heraus, werden sie rot.
  group('Der Dialog benutzt die Listen auch', () {
    late String quelle;

    /// ⚠️ NUR der Rumpf von `_addKorr`. Ueber die ganze Datei gemessen waere
    /// die Pruefung unwahr: der Verlauf-Reiter daneben hat weiterhin ein
    /// freies Datumsfeld (`datumC`) — bewusst unberuehrt, das war nicht die
    /// Aufgabe. Ohne diesen Zuschnitt wuerde der Test entweder falsch rot
    /// oder muesste so weich formuliert werden, dass er nichts mehr sagt.
    late String dialog;

    setUpAll(() {
      quelle = File('lib/widgets/behorde_sozialamt.dart').readAsStringSync();
      final a = quelle.indexOf('void _addKorr(String richtung) {');
      final b = quelle.indexOf('void _vormerken(', a);
      expect(a, greaterThan(0), reason: '_addKorr nicht gefunden — Test anpassen');
      expect(b, greaterThan(a), reason: '_vormerken nicht gefunden — Test anpassen');
      dialog = quelle.substring(a, b);
    });

    test('Datum kommt aus dem Kalender, nicht aus einem Textfeld', () {
      expect(dialog.contains('showDatePicker'), isTrue);
      // Das alte freie Textfeld hiess `datumC` — es darf hier nicht
      // wiederkommen, sonst liesse sich ein Datum eintippen, das MariaDB als
      // 0000-00-00 liest und das dann wie „kein Datum erfasst" aussieht.
      expect(dialog.contains('datumC'), isFalse);
    });

    test('an den Server geht ISO, nicht das deutsche Format', () {
      expect(dialog.contains("'datum': datum.toIso8601String().substring(0, 10)"), isTrue);
    });

    test('der Weg wird mitgeschickt', () {
      expect(dialog.contains("'weg': weg"), isTrue);
    });

    test('es gibt einen Cloud-Knopf neben dem Geräte-Knopf', () {
      // Zweimal: einmal im Anlege-Dialog, einmal an der bestehenden Zeile.
      expect('CloudPickButton('.allMatches(quelle).length, greaterThanOrEqualTo(2));
    });

    test('die Obergrenze steht nicht als nackte Zahl im Bildschirm', () {
      expect(quelle.contains('kSozKorrMaxDateien'), isTrue);
      expect(quelle.contains('maxFiles: 20'), isFalse);
    });
  });
}
