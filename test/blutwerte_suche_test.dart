import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/blut_parameter_liste.dart';
import 'package:icd360sev_vorsitzer/widgets/blutwerte_suche.dart';

void main() {
  final alle = blutParameterListe(true);

  List<String> keys(String s) =>
      blutParameterFiltern(alle, s).map((p) => p['key'] as String).toList();

  group('blutSuchform', () {
    // ⚠️ Wer schnell tippt, lässt Umlaute weg. Ein Suchfeld, das dann nichts
    // findet, sieht aus, als gäbe es das Feld nicht.
    test('Umlaute und Zierzeichen fallen weg', () {
      expect(blutSuchform('Folsäure'), 'folsaure');
      expect(blutSuchformAe('Folsäure'), 'folsaeure');
      expect(blutSuchform('Vitamin D3 (25-OH)'), 'vitamind325oh');
      expect(blutSuchform('γ-GT'), isNot(contains('-')));
    });
  });

  group('blutParameterFiltern', () {
    test('leere Suche liefert alles', () {
      expect(blutParameterFiltern(alle, '').length, alle.length);
      expect(blutParameterFiltern(alle, '   ').length, alle.length);
    });

    test('findet über die Bezeichnung', () {
      expect(keys('ferritin'), contains('ferritin'));
      expect(keys('FERRITIN'), contains('ferritin'));
    });

    // ⚠️ Ohne die Kurzformen im Suchtext findet „Ery" nichts — und genau so
    // tippt man, wenn man ein Feld unter 170 sucht.
    test('findet über die Kurzform', () {
      expect(keys('ery'), contains('erythrozyten'));
      expect(keys('tsh'), contains('tsh'));
      expect(keys('crp'), contains('crp'));
    });

    // ⚠️ Beide Schreibweisen. „folsaure" ist die, die man tippt; „folsaeure"
    // die amtliche Umschreibung. Die erste Fassung konnte nur die zweite.
    test('ohne Umlaut geschrieben wird trotzdem gefunden', () {
      expect(keys('folsaure'), contains('folsaeure'));
      expect(keys('folsaeure'), contains('folsaeure'));
      expect(keys('folsäure'), contains('folsaeure'));
      expect(keys('hamoglobin'), contains('haemoglobin'));
      expect(keys('haemoglobin'), contains('haemoglobin'));
    });

    // ⚠️ Jedes Wort muss vorkommen, nicht die ganze Zeichenkette: sonst müsste
    // man die genaue Schreibweise raten — also das, was das Feld ersparen soll.
    test('mehrere Wörter, Reihenfolge egal, Lücken erlaubt', () {
      expect(keys('vitamin d'), contains('vitamin_d3'));
      expect(keys('d vitamin'), contains('vitamin_d3'));
    });

    test('findet über die Gruppe', () {
      final s = keys('schilddruse');
      expect(s, contains('tsh'));
      expect(s.length, greaterThan(1));
    });

    test('was nicht passt, bleibt draußen', () {
      expect(keys('ferritin'), isNot(contains('kalium')));
      expect(keys('gibtesnicht'), isEmpty);
    });

    test('die Reihenfolge der Liste bleibt erhalten', () {
      final gefiltert = blutParameterFiltern(alle, 'cholesterin');
      final erwartet = alle
          .where((p) => gefiltert.any((g) => g['key'] == p['key']))
          .map((p) => p['key'])
          .toList();
      expect(gefiltert.map((p) => p['key']).toList(), erwartet,
          reason: 'sonst springen die Gruppenüberschriften durcheinander');
    });
  });
}
