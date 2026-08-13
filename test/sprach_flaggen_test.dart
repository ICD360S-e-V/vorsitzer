import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/sprach_flaggen.dart';
import 'package:icd360sev_vorsitzer/utils/sprachen_options.dart';

/// Was hier festgehalten wird, ist eine Anzeigeregel mit zwei Gründen:
///
/// 1. **Windows stellt keine Flaggen dar.** Segoe UI Emoji bildet die
///    Regional-Indicator-Paare bewusst nicht ab; dort erscheinen die zwei
///    Buchstaben des Ländercodes. Eine Karte, die nur Flaggen zeigt, wäre auf
///    einer der vier Zielplattformen leer an dieser Stelle.
/// 2. **Eine Flagge ist keine Sprache.** Deshalb muss neben jeder Flagge ein
///    Kürzel stehen, und deshalb darf eine Sprache ohne vertretbare Flagge
///    (Arabisch) auch keine bekommen.
///
/// Der wichtigste Test unten ist der erste: er prüft ALLE 28 App-Sprachen auf
/// einmal. Kommt ein Code ins ENUM, fällt hier auf, dass die Flaggentabelle
/// nachgezogen werden muss — statt dass die Karte still eine Lücke zeigt.
void main() {
  group('jede App-Sprache ist anzeigbar', () {
    test('alle 28 Codes ergeben ein nicht-leeres Kürzel und einen Namen', () {
      for (final code in appSprachCodes) {
        final a = sprachAnzeige(code);
        expect(a.code, code, reason: 'Code darf sich nicht verändern: $code');
        expect(a.kuerzel, isNotEmpty, reason: 'Kürzel fehlt für $code');
        expect(a.kuerzel, code.toUpperCase(), reason: 'Kürzel falsch für $code');
        expect(a.bezeichnung, isNotEmpty, reason: 'Name fehlt für $code');
        // Der Name darf nicht bloß der großgeschriebene Code sein — genau das
        // liefert appSprachBezeichnung als letzten Ausweg zurück.
        expect(a.bezeichnung, isNot(code.toUpperCase()),
            reason: 'Kein deutscher Name für $code');
      }
    });

    test('alle bis auf Arabisch haben eine Flagge', () {
      final ohne = appSprachCodes
          .where((c) => sprachAnzeige(c).flagge == null)
          .toList();
      // Arabisch wird in über zwanzig Ländern gesprochen; eine Nationalflagge
      // dafür auszuwählen wäre eine politische Aussage, keine sprachliche.
      expect(ohne, ['ar']);
    });

    test('das Kürzel steht auch dann, wenn die Flagge fehlt', () {
      final ar = sprachAnzeige('ar');
      expect(ar.flagge, isNull);
      expect(ar.kuerzel, 'AR');
      expect(ar.bezeichnung, 'Arabisch');
    });
  });

  group('Eingabeformen', () {
    test('erkennt den Code in beliebiger Schreibweise', () {
      expect(sprachAnzeige('RO').code, 'ro');
      expect(sprachAnzeige('  ro  ').code, 'ro');
    });

    test('erkennt auch die deutsche Bezeichnung', () {
      // `users.muttersprache` ist historisch mit deutschen Namen gefüllt,
      // `users.languages` mit Codes. Beide Formen müssen ankommen.
      final a = sprachAnzeige('Rumänisch');
      expect(a.code, 'ro');
      expect(a.flagge, isNotNull);
      expect(a.kuerzel, 'RO');
    });

    test('lässt einen unbekannten Code sichtbar, statt ihn zu schlucken', () {
      final a = sprachAnzeige('xx');
      expect(a.kuerzel, 'XX');
      expect(a.flagge, isNull);
    });

    test('leere Eingabe ergibt einen leeren Code', () {
      expect(sprachAnzeige('   ').code, isEmpty);
    });
  });

  group('sprachAnzeigen (Liste)', () {
    test('behält die Reihenfolge der gespeicherten Sprachen', () {
      final a = sprachAnzeigen(['de', 'ro', 'en']);
      expect(a.map((e) => e.code).toList(), ['de', 'ro', 'en']);
    });

    test('wirft Dubletten über Schreibweisen hinweg raus', () {
      // Jemand kann „de" und „Deutsch" gespeichert haben.
      final a = sprachAnzeigen(['de', 'Deutsch', 'DE', 'ro']);
      expect(a.map((e) => e.code).toList(), ['de', 'ro']);
    });

    test('überspringt leere Einträge, ohne die Liste abzubrechen', () {
      final a = sprachAnzeigen(['de', '', null, '  ', 'ro']);
      expect(a.map((e) => e.code).toList(), ['de', 'ro']);
    });

    test('eine leere Liste ergibt eine leere Liste', () {
      expect(sprachAnzeigen(const []), isEmpty);
    });
  });
}
