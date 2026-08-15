import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/signatur_service.dart';

/// Echte Antwort von `vorstand/signatur_manage.php`, Aktion `list`,
/// abgenommen am 15.08.2026 für Mitglied 48.
///
/// ⚠️ Der Fehler, den diese Datei festhält, hatte zwei Hälften:
///
///  1. Der Server lieferte `quelle_tabelle`/`quelle_id` GAR NICHT. Der
///     Vollmacht-Reiter filtert darauf, bekam überall null und ließ jede
///     Zeile fallen — auf dem Server war alles unterschrieben und gesiegelt,
///     im Bildschirm stand nichts.
///  2. Danach zählte der Reiter die Unterschriften aus den gelieferten
///     Zeilen. Die Liste steht aber unter EINEM Mitglied und enthält die
///     Zeile des Vorsitzenden nicht — „1 von 1", obwohl zwei nötig sind.
void main() {
  Signaturvorgang ausJson(Map<String, dynamic> j) => Signaturvorgang.fromJson(j);

  group('Herkunft muss ankommen', () {
    test('quelle_tabelle und quelle_id werden gelesen', () {
      final v = ausJson({
        'id': 33, 'dokument_typ': 'ra_vollmacht', 'dokument_titel': 'Vollmacht',
        'status': 'signiert',
        'quelle_tabelle': 'vertrag_ra_vollmacht', 'quelle_id': 22,
        'gruppe_gesamt': 2, 'gruppe_signiert': 2,
      });
      expect(v.quelleTabelle, 'vertrag_ra_vollmacht');
      expect(v.quelleId, 22);
      expect(v.stammtAus('vertrag_ra_vollmacht', 22), isTrue);
      expect(v.stammtAus('vertrag_ra_vollmacht', 21), isFalse);
    });

    test('fehlt die Herkunft, ist sie null — nicht der leere String', () {
      final v = ausJson({'id': 1, 'dokument_typ': 'x', 'dokument_titel': 'x', 'status': 'offen'});
      expect(v.quelleTabelle, isNull);
      expect(v.quelleId, isNull);
      expect(v.stammtAus('vertrag_ra_vollmacht', 22), isFalse);
    });
  });

  group('Die Gruppenzahlen entscheiden, nicht die Listenlänge', () {
    test('2 von 2 gilt als vollständig', () {
      final v = ausJson({'id': 33, 'dokument_typ': 'ra_vollmacht', 'dokument_titel': 'V',
        'status': 'signiert', 'gruppe_gesamt': 2, 'gruppe_signiert': 2});
      expect(v.gruppeVollstaendig, isTrue);
    });

    test('1 von 2 gilt NICHT als vollständig — auch wenn diese Zeile signiert ist', () {
      // Genau der Fall von Vollmacht 20: das Mitglied hat unterschrieben,
      // der Vorsitzende nicht. Aus der gelieferten Liste wäre das „1 von 1".
      final v = ausJson({'id': 31, 'dokument_typ': 'ra_vollmacht', 'dokument_titel': 'V',
        'status': 'signiert', 'gruppe_gesamt': 2, 'gruppe_signiert': 1});
      expect(v.istSigniert, isTrue, reason: 'diese eine Zeile ist unterschrieben');
      expect(v.gruppeVollstaendig, isFalse,
          reason: 'das Dokument aber nicht — es fehlt die zweite Unterschrift');
    });

    test('ohne Gruppenzahlen bleibt das alte Verhalten richtig', () {
      // Ein Dokument mit nur einem Unterzeichner, wie vor der Gruppenfunktion.
      final signiert = ausJson({'id': 5, 'dokument_typ': 'x', 'dokument_titel': 'x',
        'status': 'signiert'});
      expect(signiert.gruppeGesamt, 1);
      expect(signiert.gruppeVollstaendig, isTrue);

      final offen = ausJson({'id': 6, 'dokument_typ': 'x', 'dokument_titel': 'x',
        'status': 'offen'});
      expect(offen.gruppeVollstaendig, isFalse);
    });

    test('eine widerrufene Zeile ist nicht vollständig', () {
      final v = ausJson({'id': 7, 'dokument_typ': 'ra_vollmacht', 'dokument_titel': 'V',
        'status': 'widerrufen', 'gruppe_gesamt': 2, 'gruppe_signiert': 0});
      expect(v.istOffen, isFalse);
      expect(v.gruppeVollstaendig, isFalse);
    });
  });
}
