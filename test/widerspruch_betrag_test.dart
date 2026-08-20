import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/vermieter_widerspruch.dart';

/// Der Betrag im Widerspruch muss derselben Zahl gleichen, die im
/// Schreiben des Inkassobüros steht.
///
/// ⚠️ Die erste Fassung warf jeden Punkt als Tausenderzeichen weg und
/// machte aus 1240.55 die Zahl 124.055,00 €. Ein falscher Betrag ist
/// schlimmer als gar keiner: er gibt dem Büro die Antwort „Sie bestreiten
/// einen Betrag, den wir nie gefordert haben" frei Haus.
void main() {
  void gleich(String roh, String erwartet) =>
      expect(widerspruchBetrag(roh), erwartet, reason: 'Eingabe: „$roh"');

  test('englische Schreibweise wird als Dezimalpunkt gelesen', () {
    gleich('1240.55', '1.240,55 €');
    gleich('268.5', '268,50 €');
    gleich('0.99', '0,99 €');
    gleich('12345678.9', '12.345.678,90 €');
  });

  test('deutsche Schreibweise bleibt deutsch', () {
    gleich('1240,55', '1.240,55 €');
    gleich('1.240,55', '1.240,55 €');
    gleich('99,9', '99,90 €');
  });

  test('ein einzelner Punkt vor genau drei Ziffern ist ein Tausenderzeichen', () {
    // ⚠️ Der eine Fall, in dem der Punkt NICHT die Dezimalstelle trennt.
    gleich('1.240', '1.240,00 €');
    gleich('2.500', '2.500,00 €');
  });

  test('gemischte Schreibweise: das letzte Zeichen entscheidet', () {
    gleich('1,240.55', '1.240,55 €');
    gleich('1.240,55', '1.240,55 €');
  });

  test('Zeichen drumherum stören nicht', () {
    gleich('€ 1240,55', '1.240,55 €');
    gleich('  890  ', '890,00 €');
  });

  test('leer bleibt leer, Unsinn bleibt sichtbar', () {
    gleich('', '');
    // Kein stilles Verschlucken: was nicht als Zahl lesbar ist, steht so
    // da, damit es auffällt — statt als 0,00 € im Brief zu landen.
    gleich('abc', 'abc €');
  });
}
