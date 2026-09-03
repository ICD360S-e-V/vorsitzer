import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/insolvenz_quellen.dart';

/// Liest die Antwort von `insolvenz_manage.php?type=quellen`.
///
/// ⚠️ Der Prüffall bildet die **Form** einer echten Antwort nach (abgenommen
/// am 03.09.2026), aber mit erfundenen Werten. Die echte Antwort trägt
/// Aktenzeichen, Bewilligungszeiträume und Dateinamen eines Mitglieds — und
/// dieses Repository ist öffentlich. Geprüft wird ohnehin die Form: Liste
/// gegen Objekt, Typen, fehlende Felder.
void main() {
  // Struktur wie vom Server: 12 Schlüssel, `buergergeld` mit Zeitraum und
  // verknüpften Unterlagen, die übrigen als reine Zählstände.
  const echteForm = '''
{
  "success": true,
  "quellen": {
    "einkommen_gehalt": {"wo": "Behörde ▸ Arbeitgeber ▸ Lohnabrechnung", "anzahl": 0, "zustand": "leer"},
    "buergergeld": {
      "wo": "Behörde ▸ Jobcenter ▸ Antrag ▸ Bewilligungsbescheid",
      "anzahl": 2,
      "zustand": "vorhanden",
      "zeitraum": "01.01.2026 – 31.12.2026",
      "laufend": true,
      "antrag_id": 4711,
      "dokumente": [
        {"id": 1, "name": "Bescheid.pdf", "groesse": 188167},
        {"id": 2, "name": "Aenderungsbescheid.pdf", "groesse": 177311}
      ],
      "grund": null
    },
    "mietvertrag": {"wo": "Behörde ▸ Vermieter ▸ Mietvertrag", "anzahl": 0, "zustand": "leer"}
  }
}
''';

  Map<String, dynamic> j(String s) => jsonDecode(s) as Map<String, dynamic>;

  group('insolvenzQuellenLesen', () {
    test('liest die echte Antwortform', () {
      final q = insolvenzQuellenLesen(j(echteForm)['quellen']);
      expect(q.length, 3);
      expect(q['buergergeld']!['zustand'], 'vorhanden');
      expect(q['buergergeld']!['zeitraum'], '01.01.2026 – 31.12.2026');
      expect(q['buergergeld']!['laufend'], isTrue);
    });

    // 🔴 Der Fall, der den Speedtest-Bildschirm einmal grau gemacht hat: eine
    // leere PHP-Struktur kommt als `[]` heraus, nicht als `{}`. Ein `as Map`
    // darauf wirft — und im Release-Build bleibt eine graue Fläche ohne
    // Meldung. Der Server codiert deshalb mit (object); DASS er es tut, ist
    // eine Nebenwirkung der Schlüssel und kein Vertrag.
    test('eine leere Antwort kommt als Liste an und wirft NICHT', () {
      expect(insolvenzQuellenLesen(jsonDecode('[]')), isEmpty);
      expect(insolvenzQuellenLesen(null), isEmpty);
      expect(insolvenzQuellenLesen('kaputt'), isEmpty);
    });

    test('ein Eintrag, der keine Karte ist, wird zur leeren Karte', () {
      final q = insolvenzQuellenLesen(jsonDecode('{"buergergeld": []}'));
      expect(q['buergergeld'], isEmpty);
      expect(insolvenzQuelleDokumente(q['buergergeld']), isEmpty);
    });
  });

  group('insolvenzQuelleDokumente', () {
    test('liefert die verknüpften Unterlagen in Reihenfolge', () {
      final q = insolvenzQuellenLesen(j(echteForm)['quellen']);
      final d = insolvenzQuelleDokumente(q['buergergeld']);
      expect(d.map((e) => e['id']), [1, 2]);
      expect(d.first['name'], 'Bescheid.pdf');
    });

    // ⚠️ Eine Quelle ohne `dokumente` ist der Regelfall — nur Bürgergeld
    // liefert welche. Sie darf keine Ausnahme werfen und nicht null ergeben:
    // die Anzeige unterscheidet „nichts da" allein über `zustand`.
    test('eine Quelle ohne Unterlagen ergibt eine leere Liste', () {
      final q = insolvenzQuellenLesen(j(echteForm)['quellen']);
      expect(insolvenzQuelleDokumente(q['mietvertrag']), isEmpty);
      expect(insolvenzQuelleDokumente(null), isEmpty);
    });

    // Eine Zeile ohne brauchbare Id wäre ein Knopf, der ins Leere führt.
    test('Einträge ohne Id fallen heraus', () {
      final q = insolvenzQuellenLesen(jsonDecode(
          '{"buergergeld": {"dokumente": [{"id": 0, "name": "x"}, {"name": "y"}, {"id": 9, "name": "z"}]}}'));
      final d = insolvenzQuelleDokumente(q['buergergeld']);
      expect(d.map((e) => e['name']), ['z']);
    });
  });
}
