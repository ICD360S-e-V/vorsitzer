// Die Auswahllisten des Schriftwechsels von Kindergarten ▸ Zahlung gegen
// den Server gehalten.
//
// 🔴 WARUM ES DIESEN TEST GIBT: das PHP liegt NICHT in diesem Repository.
// Diese Datei ist damit die einzige Stelle, an der eine Abweichung
// zwischen Bildschirm und Server überhaupt auffallen kann. Und die
// Abweichung ist stumm: `enumWert($plain['medium'], 'korr_medium',
// 'brief')` schreibt einen unbekannten Wert ohne Fehler als „Brief" fort.
// In der Akte stünde dann „Brief", wo jemand telefoniert hat.
//
// ⚠️ Die Literale unten sind ABGESCHRIEBEN aus
// api/admin/kindergarten_zahlung_manage.php (Stand 2026-08-28, Zeilen
// 139-141). Wer sie anpasst, muss vorher in die laufende Fassung auf dem
// Server gesehen haben — sonst bestätigt der Test nur sich selbst.

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/kiga_korr_optionen.dart';

void main() {
  // 'korr_medium' => ['brief', 'einschreiben', 'email', 'de_mail',
  //                   'telefon', 'fax', 'persoenlich', 'sonstiges'],
  const serverMedien = <String>[
    'brief', 'einschreiben', 'email', 'de_mail',
    'telefon', 'fax', 'persoenlich', 'sonstiges',
  ];

  // 'korr_richtung' => ['eingehend', 'ausgehend'],
  const serverRichtungen = <String>['eingehend', 'ausgehend'];

  group('Kindergarten ▸ Zahlung ▸ Korrespondenz — Auswahllisten', () {
    test('jeder angebotene Weg existiert auch auf dem Server', () {
      for (final k in kKigaKorrMedien.keys) {
        expect(serverMedien, contains(k),
            reason: 'Der Weg „$k" wird angeboten, aber der Server kennt ihn nicht — '
                'er würde ihn still als „brief" ablegen.');
      }
    });

    test('kein Weg des Servers fehlt im Bildschirm', () {
      for (final k in serverMedien) {
        expect(kKigaKorrMedien.keys, contains(k),
            reason: 'Der Server kennt „$k", der Bildschirm bietet ihn nicht an. '
                'Ein automatisch angelegter Eintrag mit diesem Weg stünde dann '
                'ohne Beschriftung in der Liste.');
      }
    });

    test('jeder Weg hat eine Beschriftung, keine ist leer', () {
      for (final e in kKigaKorrMedien.entries) {
        expect(e.value.trim(), isNotEmpty, reason: 'Weg „${e.key}" ohne Beschriftung');
      }
    });

    test('die Richtungen sind genau die des Servers, in derselben Reihenfolge', () {
      // Die Reihenfolge ist nicht Geschmack: 'eingehend' steht zuerst,
      // weil es auch der Vorgabewert des Servers ist. Ein Dialog, der
      // 'ausgehend' vorbelegt, dreht bei Unachtsamkeit die Beweisrichtung.
      expect(kKigaKorrRichtungen, serverRichtungen);
      expect(kKigaKorrRichtungen.first, 'eingehend');
    });

    test('die erlaubten Endungen decken PDF und die drei Bildformate ab', () {
      // Der Upload-Endpunkt prüft die Endung NICHT. Fällt eine hier
      // heraus, lässt sich der Beleg nicht mehr ablegen — ohne dass
      // irgendwo etwas fehlschlägt.
      expect(kKigaKorrEndungen, containsAll(<String>['pdf', 'jpg', 'jpeg', 'png']));
      for (final e in kKigaKorrEndungen) {
        expect(e, equals(e.toLowerCase()),
            reason: 'file_picker vergleicht kleingeschrieben: „$e" träfe nie zu.');
        expect(e.startsWith('.'), isFalse,
            reason: 'allowedExtensions erwartet „pdf", nicht „.pdf".');
      }
      expect(kKigaKorrEndungen.toSet().length, kKigaKorrEndungen.length,
          reason: 'doppelte Endung');
    });

    test('die Stapelgrenze ist positiv und bleibt unter dem Serverdeckel', () {
      // Der Endpunkt nimmt eine Datei je Aufruf; die Grenze ist die
      // Schleife hier, nicht der Server. Sie muss trotzdem eine sein —
      // 0 hieße, es ginge gar nichts, und niemand bekäme es gesagt.
      expect(kKigaKorrMaxDateien, greaterThan(0));
      expect(kKigaKorrMaxDateien, lessThanOrEqualTo(20));
    });
  });
}
