/// Warum „Per Fax" abbricht — und dass der Schirm den RICHTIGEN Grund nennt.
///
/// 🔴 Anlass: am 04.09.2026 stand bei einem Mitglied keine Geschäftsstelle im
/// Datensatz. Der Schirm meldete daraufhin „Zu dieser Geschäftsstelle steht
/// überhaupt kein Eintrag im Verzeichnis" — eine Aussage über das
/// Verzeichnis, obwohl das Verzeichnis in Ordnung war und die Faxnummer der
/// Kasse dort seit jeher steht. Gesucht wurde danach an der falschen Stelle.
///
/// ⚠️ Diese Datei ist die EINZIGE Stelle im Baum, an der ein Auseinanderlaufen
/// mit dem Server auffallen kann: `kkvEmpfaenger()` liegt in
/// `api/admin/krankenkasse_vollmacht_versand.php`, und das PHP ist in keinem
/// Repo. Wer dort einen Schlüssel umbenennt, macht hier einen Test rot statt
/// im Betrieb eine stumme Fehlmeldung.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/krankenkasse_vollmacht.dart';

void main() {
  group('kkKontaktGrund', () {
    test('nicht_gewaehlt zeigt auf den eigenen Datensatz, nicht auf das Verzeichnis', () {
      final t = kkKontaktGrund('nicht_gewaehlt');
      expect(t, contains('keine Geschäftsstelle ausgewählt'));
      expect(t, contains('Behörde ▸ Krankenkasse'));
      // 🔴 Der Kern: dieser Fall darf NICHT behaupten, im Verzeichnis fehle
      // etwas. Genau diese Verwechslung war der Fehler.
      expect(t.toLowerCase(), isNot(contains('steht im verzeichnis kein')));
    });

    test('keine zeigt auf das Verzeichnis, nicht auf den Datensatz', () {
      final t = kkKontaktGrund('keine');
      expect(t, contains('Verzeichnis'));
      expect(t, isNot(contains('noch keine Geschäftsstelle ausgewählt')));
    });

    test('die beiden Lagen sind unterscheidbar', () {
      expect(kkKontaktGrund('nicht_gewaehlt'), isNot(kkKontaktGrund('keine')));
    });

    test('unbekannter Schlüssel behauptet keine der beiden Lagen', () {
      // Ältere App gegen neueren Server: raten ist erlaubt, falsch behaupten
      // nicht.
      for (final q in ['', 'standort', 'irgendwas_neues']) {
        final t = kkKontaktGrund(q);
        expect(t, isNot(contains('Verzeichnis')), reason: 'quelle=$q');
        expect(t, isNot(contains('ausgewählt')), reason: 'quelle=$q');
        expect(t, contains('Post'), reason: 'quelle=$q');
      }
    });

    test('kein Grund ist leer — eine leere Meldung ist so gut wie gar keine', () {
      for (final q in ['nicht_gewaehlt', 'keine', 'standort', '']) {
        expect(kkKontaktGrund(q).trim(), isNotEmpty, reason: 'quelle=$q');
      }
    });
  });

  group('Kopplung an den Server', () {
    // ⚠️ Quelltextprüfung, weil die Regel in einer privaten Getter-/Dialog-
    // Logik steckt, die ohne laufenden Server und echte Vollmacht nicht
    // auslösbar ist. Gegenprobe gemacht: nimmt man die Reparatur zurück,
    // werden diese Prüfungen rot.
    late String quelle;

    setUpAll(() {
      quelle = File('lib/widgets/krankenkasse_vollmacht.dart').readAsStringSync();
    });

    test('die drei Serverschlüssel stehen im Client', () {
      for (final k in ['nicht_gewaehlt', 'keine']) {
        expect(quelle, contains("'$k'"), reason: 'Schlüssel $k fehlt');
      }
    });

    test('die Karte warnt, BEVOR jemand auf „Per Fax" drückt', () {
      // Die Meldung im Fehlerfall allein genügt nicht: sie erscheint erst
      // nach dem Druck und verschwindet nach sechs Sekunden.
      expect(quelle, contains('_stelleGewaehlt'));
      expect(quelle, contains('if (!_stelleGewaehlt)'));
    });

    test('_stelleGewaehlt liest dienststelle, nicht den Kassennamen', () {
      // 🔴 `name` ist gefüllt, sobald jemand die Kasse gewählt hat — daran
      // hängt aber kein Kontaktweg. Wer hier `name` prüft, baut genau die
      // Verwechslung nach, die der Nutzer auf dem Schirm hatte.
      final i = quelle.indexOf('bool get _stelleGewaehlt');
      expect(i, greaterThan(0));
      final rumpf = quelle.substring(i, i + 300);
      expect(rumpf, contains("k['dienststelle']"));
      expect(rumpf, isNot(contains("k['name']")));
    });

    test('die alte, unwahre Meldung ist weg', () {
      expect(quelle,
          isNot(contains('steht überhaupt kein Eintrag im Verzeichnis')));
    });
  });
}
