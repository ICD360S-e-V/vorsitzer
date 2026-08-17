import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/signatur_service.dart';

/// Bei einer Vollmacht unterschreiben ZWEI: das Mitglied und der Vorstand.
///
/// ⚠️ `liste` steht unter EINEM Mitglied und liefert nur dessen Zeile. Wer die
/// zurückgegebenen Zeilen zählt, kommt auf „0 von 1" statt „0 von 2" — genau
/// das stand im Bildschirm — und hält die Sache für erledigt, sobald das
/// Mitglied unterschrieben hat. Der Server rechnet die Gruppe je Zeile mit;
/// diese Tests halten fest, dass sie auch gelesen wird.
void main() {
  Signaturvorgang ausJson(Map<String, dynamic> j) => Signaturvorgang.fromJson({
        'id': 1,
        'dokument_typ': 'insolvenz_vollmacht',
        'dokument_titel': 'Vollmacht',
        'quelle_tabelle': 'member_vollmachten',
        'quelle_id': 77,
        ...j,
      });

  group('Gruppenzahlen der Unterschriften', () {
    test('liest gruppe_gesamt und gruppe_signiert vom Server', () {
      final v = ausJson({'status': 'offen', 'gruppe_gesamt': 2, 'gruppe_signiert': 0});
      expect(v.gruppeGesamt, 2, reason: 'zwei Unterzeichner: Mitglied und Vorstand');
      expect(v.gruppeSigniert, 0);
      expect(v.gruppeVollstaendig, isFalse);
    });

    test('nur das Mitglied unterschrieben ist NICHT vollstaendig', () {
      // Die einzige gelieferte Zeile steht auf „signiert" — die des Vorstands
      // ist gar nicht dabei. Genau hier hat `every(istSigniert)` gelogen.
      final v = ausJson({'status': 'signiert', 'gruppe_gesamt': 2, 'gruppe_signiert': 1});
      expect(v.istSigniert, isTrue, reason: 'die eigene Zeile ist unterschrieben');
      expect(v.gruppeVollstaendig, isFalse, reason: 'der Vorstand fehlt noch');
    });

    test('beide unterschrieben ist vollstaendig', () {
      final v = ausJson({'status': 'signiert', 'gruppe_gesamt': 2, 'gruppe_signiert': 2});
      expect(v.gruppeVollstaendig, isTrue);
    });

    test('eine Antwort OHNE die Felder verhaelt sich wie bisher', () {
      // Ein älterer Server soll nicht „null von null" ergeben, sondern den
      // Einzelunterzeichner-Fall.
      final offen = ausJson({'status': 'offen'});
      expect(offen.gruppeGesamt, 1);
      expect(offen.gruppeVollstaendig, isFalse);
      final fertig = ausJson({'status': 'signiert', 'gruppe_signiert': 1});
      expect(fertig.gruppeVollstaendig, isTrue);
    });

    test('Rolle und Gruppe kommen mit', () {
      final v = ausJson({'status': 'offen', 'rolle': 'bevollmaechtigter',
                         'gruppe_id': 'abc123', 'gruppe_gesamt': 2});
      expect(v.rolle, 'bevollmaechtigter');
      expect(v.gruppeId, 'abc123');
    });
  });
}
