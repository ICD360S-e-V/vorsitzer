// „0 von 1" statt „0 von 2" — der Zähler auf der Vollmachtkarte.
//
// 🔴 DER FEHLER, DEN DIESER TEST FESTHÄLT
// `SignaturService().liste(userId:)` steht unter EINEM Mitglied und liefert
// nur dessen Zeilen. Bei einer Vollmacht ist das genau eine von zweien —
// die zweite gehört dem Vorstand und trägt eine andere `user_id`. Wer die
// gelieferten Zeilen zählt, schreibt „0 von 1" und hält die Sache für
// fertig, sobald das Mitglied unterschrieben hat.
//
// ⚠️ Auf dem Schirm ist das unauffällig: eine Zahl, die plausibel aussieht.
// Am Server gemessen (18.08.2026, echte Zeilen): `list` liefert unter dem
// Mitglied 1 Zeile, die aber `gruppe_gesamt = 2` trägt.
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/signatur_service.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_kindergarten_zahlung_akte.dart';

Signaturvorgang _zeile({
  required int gesamt,
  required int signiert,
  String status = 'offen',
}) =>
    Signaturvorgang(
      id: 1,
      dokumentTyp: 'vollmacht',
      dokumentTitel: 'Vollmacht Elternbeitrag',
      status: status,
      quelleTabelle: 'kiga_zahlung_vollmacht',
      quelleId: 42,
      gruppeGesamt: gesamt,
      gruppeSigniert: signiert,
    );

void main() {
  group('Unterschriftsstand kommt aus der Gruppe', () {
    test('eine gelieferte Zeile, aber zwei Unterzeichner → 0 von 2', () {
      final stand = kigaUnterschriftStand([_zeile(gesamt: 2, signiert: 0)]);
      expect(stand.noetig, 2,
          reason: 'Die Zeile des Vorstands fehlt in der Liste — gezählt wird '
              'trotzdem die ganze Gruppe');
      expect(stand.vorhanden, 0);
    });

    test('das Mitglied hat unterschrieben, der Vorstand nicht → 1 von 2', () {
      // ⚠️ Der gefährliche Fall: mit der Listenzählung stünde hier „1 von 1"
      // und damit „fertig", obwohl die Vollmacht unwirksam ist.
      final stand = kigaUnterschriftStand(
          [_zeile(gesamt: 2, signiert: 1, status: 'signiert')]);
      expect(stand.noetig, 2);
      expect(stand.vorhanden, 1);
    });

    test('beide haben unterschrieben → 2 von 2', () {
      final stand = kigaUnterschriftStand(
          [_zeile(gesamt: 2, signiert: 2, status: 'signiert')]);
      expect((stand.vorhanden, stand.noetig), (2, 2));
    });

    test('nichts angefordert → 0 von 0', () {
      final stand = kigaUnterschriftStand(const []);
      expect((stand.vorhanden, stand.noetig), (0, 0));
    });

    // Wenn der Server gar keine Gruppe kennt (`gruppe_id` NULL), liefert er
    // `gruppe_gesamt = 1`. Dann IST die Liste die Wahrheit — der Rückfall
    // darf die Einzelunterschrift nicht kaputt machen.
    test('Einzelunterschrift ohne Gruppe bleibt 0 von 1', () {
      final stand = kigaUnterschriftStand([_zeile(gesamt: 1, signiert: 0)]);
      expect((stand.vorhanden, stand.noetig), (0, 1));
    });

    test('gruppeGesamt 0 fällt auf die Listenlänge zurück', () {
      final stand = kigaUnterschriftStand(
          [_zeile(gesamt: 0, signiert: 0), _zeile(gesamt: 0, signiert: 0)]);
      expect(stand.noetig, 2, reason: 'lieber die Liste als eine Null anzeigen');
    });
  });

  group('Faxstand', () {
    // Wortgleich aus der Spaltendefinition:
    //   enum('vorbereitet','in_zustellung','zugestellt','fehlgeschlagen',
    //        'storniert','empfangen')
    const serverEnum = {
      'vorbereitet', 'in_zustellung', 'zugestellt',
      'fehlgeschlagen', 'storniert', 'empfangen',
    };

    test('jeder Status hat einen Klartext', () {
      expect(serverEnum.difference(kFaxStaende.keys.toSet()), isEmpty);
    });

    test('kein Klartext ohne Status in der Spalte', () {
      expect(kFaxStaende.keys.toSet().difference(serverEnum), isEmpty);
    });

    // 🔴 „übergeben" und „zugestellt" duerfen sich nicht gleichen.
    test('in_zustellung klingt nicht nach zugestellt', () {
      expect(kFaxStaende['in_zustellung'], isNot(contains('zugestellt')));
      expect(kFaxStaende['zugestellt'], 'zugestellt');
    });

    test('ein unbekannter Status faellt durch', () {
      expect(kFaxStaende['unterwegs'], isNull);
    });
  });
}
