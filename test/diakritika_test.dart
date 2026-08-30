import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/diakritika.dart';

void main() {
  final d = Diakritika.ausJson(const {
    'kurz': {'si': 'și', 'in': 'în', 'ti': 'ți'},
    'kontext': {
      'sa': {
        'să': {'r': ['faca', 'trimit', 'imi'], 'l': ['ajunge', 'vrea']}
      },
      'va': {
        'vă': {'r': ['rog', 'trimit'], 'l': []}
      },
      'pana': {
        'până': {'r': ['in', 'cand'], 'l': ['din']}
      },
      // Zwei Zielformen — der Nachbar entscheidet, welche.
      'tara': {
        'țara': {'r': ['noastra'], 'l': []},
        'țară': {'r': [], 'l': ['o']},
      },
    },
  });

  group('kurze Nicht-Wörter', () {
    test('brauchen keinen Kontext', () {
      expect(d.korrektur('si'), 'și');
      expect(d.korrektur('in'), 'în');
      expect(d.korrektur('ti'), 'ți');
    });
    test('übernehmen die Schreibung', () {
      expect(d.korrektur('Si'), 'Și');
      expect(d.korrektur('IN'), 'ÎN');
    });
  });

  group('Kontext', () {
    test('rechter Nachbar entscheidet', () {
      expect(d.korrektur('sa', rechts: 'faca'), 'să');
      expect(d.korrektur('va', rechts: 'rog'), 'vă');
      expect(d.korrektur('pana', rechts: 'in'), 'până');
    });

    test('linker Nachbar entscheidet', () {
      expect(d.korrektur('sa', links: 'ajunge'), 'să');
      expect(d.korrektur('pana', links: 'din'), 'până');
    });

    test('der Nachbar wird OHNE Häkchen nachgeschlagen', () {
      // ⚠️ Der eigentliche Punkt: wer die Häkchen weglässt, lässt sie überall
      // weg. Neben „sa" steht „faca", nicht „facă" — beides muss greifen.
      expect(d.korrektur('sa', rechts: 'facă'), 'să');
      expect(d.korrektur('pana', rechts: 'în'), 'până');
    });

    test('ohne passenden Nachbarn bleibt alles stehen', () {
      // „va mai" ist Futur und völlig richtig.
      expect(d.korrektur('va', rechts: 'mai'), isNull);
      expect(d.korrektur('sa', rechts: 'casa'), isNull);
      expect(d.korrektur('pana'), isNull);
    });

    test('unbekanntes Wort wird nie angefasst', () {
      expect(d.korrektur('Duinea', rechts: 'rog'), isNull);
      expect(d.korrektur('Vollmacht'), isNull);
    });
  });

  group('zwei mögliche Zielformen', () {
    test('der Nachbar wählt die richtige', () {
      expect(d.korrektur('tara', rechts: 'noastra'), 'țara');
      expect(d.korrektur('tara', links: 'o'), 'țară');
    });

    test('passen beide, wird NICHTS geändert', () {
      // ⚠️ Genau hier ging die erste Fassung schief: global ist „țară"
      // häufiger, in „în tara noastră" ist aber „țara" richtig. Wer bei
      // Gleichstand rät, schreibt zuverlässig das Falsche.
      expect(d.korrektur('tara', links: 'o', rechts: 'noastra'), isNull);
    });
  });

  test('leere Regeln ändern nie etwas', () {
    expect(Diakritika.leer.bereit, isFalse);
    expect(Diakritika.leer.korrektur('sa', rechts: 'faca'), isNull);
  });
}
