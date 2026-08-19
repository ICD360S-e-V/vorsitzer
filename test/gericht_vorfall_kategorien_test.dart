import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_gericht.dart';

/// Die Whitelist aus `api/admin/gericht_vorfall_detail.php`:
///
/// ```php
/// define('GV_KATEGORIEN', ['antrag','beschluss','sonstiges']);
/// ```
///
/// ⚠️ Das PHP liegt nur auf dem Server, nicht im Repository — dieser Test ist
/// die einzige Stelle, an der die Kopplung überhaupt auffallen kann. Und sie
/// fällt sonst NICHT auf: der Server wirft keinen Fehler, er setzt eine
/// unbekannte Kategorie still auf `sonstiges`. Auf dem Schirm sieht das aus
/// wie ein geglückter Upload — nur eben im falschen Abschnitt.
///
/// Genau das war vor dem 19.08.2026 der Zustand für `beschluss`: der Client
/// hätte die Kategorie geschickt, der Server hätte sie verworfen, und der
/// Beschluss über die Restschuldbefreiung wäre in „Sonstiges" gelandet.
const _serverKategorien = <String>{'antrag', 'beschluss', 'sonstiges'};

void main() {
  group('Dokumentkategorien am Gerichts-Vorfall', () {
    test('decken sich mit der Whitelist des Servers', () {
      expect(kGerichtVorfallDokKategorien.keys.toSet(), _serverKategorien);
    });

    test('jede Kategorie hat einen lesbaren deutschen Namen', () {
      for (final e in kGerichtVorfallDokKategorien.entries) {
        expect(e.value.trim(), isNotEmpty);
        // Der Schlüssel selbst wäre kein Name — genau so sähe ein vergessener
        // Eintrag aus, und im Verlauf stünde dann „hochgeladen (beschluss)".
        expect(e.value, isNot(e.key),
            reason: '„${e.key}" hat keinen eigenen Namen bekommen');
      }
    });

    test('`beschluss` ist vorhanden — der Abschnitt hängt daran', () {
      // Ohne diesen Schlüssel fällt der Beschluss-Abschnitt im Reiter
      // „Dokumente" beim Insolvenzgericht auf „Sonstiges" zurück.
      expect(kGerichtVorfallDokKategorien['beschluss'], 'Beschluss');
    });

    test('`sonstiges` bleibt der Auffang', () {
      // Der Verlauf liest über `?? 'Sonstiges'`. Fehlte der Eintrag, stünde
      // dort für ein Dokument ohne Kategorie gar nichts.
      expect(kGerichtVorfallDokKategorien.containsKey('sonstiges'), isTrue);
    });
  });
}
