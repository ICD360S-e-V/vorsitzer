import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/massnahme_konstanten.dart';

/// ⚠️ Zeichengleich mit MN_STATUS / MN_ART in massnahme_manage.php UND mit
/// der ENUM-Spalte jobcenter_user_massnahme.status. Das PHP liegt in KEINEM
/// Repo (`_server_*/` ist gitignored), deshalb steht die Liste hier als
/// Literal — dieselbe Vorgehensweise wie `_serverWhitelist` bei den
/// Chat-Reaktionen. Weicht sie ab, weist der Server mit „Unbekannter Status"
/// ab, und für den Nutzer sieht das aus wie ein Fehler der App.
const _serverStatus = ['zugewiesen','angetreten','laufend','beendet','abgebrochen','abgelehnt'];
const _serverArten  = ['MAT','MAG','AVGS','Weiterbildung','sonstige'];

void main() {
  group('Kopplung an den Server', () {
    test('Status-Liste ist zeichengleich', () {
      expect(kMassnahmeStatus, _serverStatus);
    });

    test('Art-Liste ist zeichengleich', () {
      expect(kMassnahmeArten, _serverArten);
    });

    test('jeder Status und jede Art hat eine Beschriftung', () {
      for (final s in kMassnahmeStatus) {
        expect(kMassnahmeStatusLabel[s], isNotNull, reason: 'ohne Beschriftung: $s');
      }
      for (final a in kMassnahmeArten) {
        expect(kMassnahmeArtLabel[a], isNotNull, reason: 'ohne Beschriftung: $a');
      }
    });

    // Läuft nur lokal, wo die Serverquelle daneben liegt. Auf dem Runner
    // fehlt sie — dann trägt der Literal-Test oben die Aussage allein.
    test('stimmt mit massnahme_manage.php überein (nur lokal)', () {
      final f = File('_server_massnahme/massnahme_manage.php');
      if (!f.existsSync()) return;
      final php = f.readAsStringSync();
      for (final s in kMassnahmeStatus) {
        expect(php.contains("'$s'"), isTrue, reason: 'Status fehlt im PHP: $s');
      }
      for (final a in kMassnahmeArten) {
        expect(php.contains("'$a'"), isTrue, reason: 'Art fehlt im PHP: $a');
      }
    });
  });

  group('Beschriftung', () {
    test('der Reiter nennt den Träger — MAT ist nicht MAG', () {
      expect(kMassnahmeTabTitel.contains('Träger'), isTrue);
    });

    test('der amtliche Wortlaut bleibt vollständig', () {
      expect(kMassnahmeVollTitel,
          'Zuweisung zu einer Maßnahme zur Aktivierung und beruflichen '
          'Eingliederung bei einem Träger');
      expect(kMassnahmeRechtsgrundlage, '§ 16 Abs. 1 SGB II i.V.m. § 45 SGB III');
      // ⚠️ Wortlaut aus dem echten Bescheid vom 04.09.2026: „Abs. 1" gehört an
      // § 16 SGB II, NICHT an § 45 SGB III. Ich hatte es zuerst vertauscht.
    });
  });

  group('Widerspruchsfrist § 84 Abs. 1 SGG', () {
    test('ein Monat ab Bekanntgabe', () {
      expect(massnahmeWiderspruchsfrist(DateTime(2026, 3, 15)), DateTime(2026, 4, 15));
    });

    // ⚠️ Der eigentliche Punkt: „Monat plus eins" gibt es nicht immer.
    test('31.01. → 28.02., nicht der 31.02.', () {
      expect(massnahmeWiderspruchsfrist(DateTime(2026, 1, 31)), DateTime(2026, 2, 28));
    });

    test('Schaltjahr: 31.01.2028 → 29.02.2028', () {
      expect(massnahmeWiderspruchsfrist(DateTime(2028, 1, 31)), DateTime(2028, 2, 29));
    });

    test('31.03. → 30.04.', () {
      expect(massnahmeWiderspruchsfrist(DateTime(2026, 3, 31)), DateTime(2026, 4, 30));
    });

    test('Jahreswechsel: 31.12. → 31.01. des Folgejahres', () {
      expect(massnahmeWiderspruchsfrist(DateTime(2026, 12, 31)), DateTime(2027, 1, 31));
    });

    test('ohne Bekanntgabedatum wird nichts geraten', () {
      expect(massnahmeWiderspruchsfrist(null), isNull);
      expect(massnahmeTageBisFrist(null), isNull);
    });

    test('Tage bis zur Frist, auch negativ', () {
      expect(massnahmeTageBisFrist(DateTime(2026, 9, 1), heute: DateTime(2026, 9, 20)), 11);
      expect(massnahmeTageBisFrist(DateTime(2026, 1, 1), heute: DateTime(2026, 9, 20)), lessThan(0));
    });
  });

  group('Zustand und Datum', () {
    test('offen sind genau zugewiesen/angetreten/laufend', () {
      expect(kMassnahmeStatus.where(massnahmeIstOffen).toList(),
          ['zugewiesen', 'angetreten', 'laufend']);
    });

    test('unbekannter Status gilt nicht als offen', () {
      expect(massnahmeIstOffen(null), isFalse);
      expect(massnahmeIstOffen('quatsch'), isFalse);
    });

    // Ein leeres Feld heisst „nicht erfasst". Deutsche Schreibweise wird NICHT
    // geraten — der Datumswähler schreibt immer ISO.
    test('nur ISO wird gelesen', () {
      expect(massnahmeDatum('2026-09-15'), DateTime(2026, 9, 15));
      expect(massnahmeDatum('2026-09-15 00:00:00'), DateTime(2026, 9, 15));
      expect(massnahmeDatum(''), isNull);
      expect(massnahmeDatum(null), isNull);
      expect(massnahmeDatum('15.09.2026'), isNull);
    });
  });
}
