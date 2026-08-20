import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/mail_ordnerzuordnung.dart';

Map<String, dynamic> _zeile(int uid, [String? box]) =>
    {'uid': uid, if (box != null) 'box': box};

void main() {
  group('Ordner einer Zeile', () {
    test('ohne box gilt der geöffnete Ordner', () {
      expect(mailZeileOrdner(_zeile(7), 'INBOX'), 'INBOX');
      expect(mailZeileOrdner({'uid': 7, 'box': ''}, 'Archive'), 'Archive');
    });

    test('mit box gilt die box der Zeile', () {
      expect(mailZeileOrdner(_zeile(7, 'Trash'), 'INBOX'), 'Trash');
    });
  });

  group('Auswahlschlüssel', () {
    test('trennt gleiche UID in verschiedenen Ordnern', () {
      // ⚠️ DER Punkt. UIDs werden je Ordner vergeben: dieselbe 42 ist im
      // Eingang und im Papierkorb eine andere Nachricht. Ein Schlüssel aus
      // der blossen UID hätte beide Zeilen markiert — und die zweite hat
      // niemand gesehen.
      expect(mailWahlSchluessel('INBOX', 42),
          isNot(mailWahlSchluessel('Trash', 42)));
    });

    test('ist beständig', () {
      expect(mailWahlSchluessel('INBOX', 42), mailWahlSchluessel('INBOX', 42));
    });
  });

  group('Gruppierung nach Ordner', () {
    test('eine gemischte Auswahl zerfällt in ihre Ordner', () {
      final g = mailNachOrdner([
        _zeile(1, 'INBOX'),
        _zeile(2, 'Trash'),
        _zeile(3, 'INBOX'),
        _zeile(4, 'Archive'),
      ], 'INBOX');
      expect(g.keys.toSet(), {'INBOX', 'Trash', 'Archive'});
      expect(g['INBOX'], [1, 3]);
      expect(g['Trash'], [2]);
      expect(g['Archive'], [4]);
    });

    test('KEINE UID landet im falschen Ordner', () {
      // Der eigentliche Schaden, wenn das schiefgeht: die UID des einen
      // Ordners trifft im anderen eine fremde Nachricht.
      final g = mailNachOrdner([
        _zeile(42, 'INBOX'),
        _zeile(42, 'Trash'),
      ], 'INBOX');
      expect(g['INBOX'], [42]);
      expect(g['Trash'], [42]);
      expect(g.values.fold<int>(0, (s, l) => s + l.length), 2);
    });

    test('ohne box fällt alles auf den geöffneten Ordner', () {
      final g = mailNachOrdner([_zeile(1), _zeile(2)], 'Junk');
      expect(g, {'Junk': [1, 2]});
    });

    test('UID 0 oder fehlend wird ausgelassen', () {
      final g = mailNachOrdner([
        _zeile(0, 'INBOX'),
        {'box': 'INBOX'},
        _zeile(5, 'INBOX'),
      ], 'INBOX');
      expect(g, {'INBOX': [5]});
    });

    test('leere Auswahl ergibt nichts', () {
      expect(mailNachOrdner(const [], 'INBOX'), isEmpty);
    });

    test('die Reihenfolge innerhalb eines Ordners bleibt erhalten', () {
      final g = mailNachOrdner(
          [_zeile(9, 'INBOX'), _zeile(3, 'INBOX'), _zeile(7, 'INBOX')], 'INBOX');
      expect(g['INBOX'], [9, 3, 7]);
    });
  });
}
