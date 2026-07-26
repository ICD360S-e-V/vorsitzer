import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/korrespondenz_attachments_widget.dart';

void main() {
  group('freieAnhangSlots', () {
    test('ohne maxTotal gibt es keine Grenze — auch bei vielen Anhängen', () {
      expect(freieAnhangSlots(maxTotal: null, bestand: 0, geladen: true), isNull);
      expect(freieAnhangSlots(maxTotal: null, bestand: 99, geladen: true), isNull);
    });

    test('zählt den Bestand mit, nicht nur den einzelnen Upload-Vorgang', () {
      expect(freieAnhangSlots(maxTotal: 5, bestand: 0, geladen: true), 5);
      expect(freieAnhangSlots(maxTotal: 5, bestand: 3, geladen: true), 2);
      expect(freieAnhangSlots(maxTotal: 5, bestand: 5, geladen: true), 0);
    });

    test('nie negativ — ein Altbestand über der Grenze sperrt nur, statt Unsinn zu rechnen', () {
      expect(freieAnhangSlots(maxTotal: 5, bestand: 8, geladen: true), 0);
    });

    test('vor dem Laden keine Grenze: bestand ist dort immer 0 und würde einen '
        'vollen Anhang fälschlich als leer ausweisen', () {
      expect(freieAnhangSlots(maxTotal: 5, bestand: 0, geladen: false), isNull);
    });

    test('maxTotal 0 sperrt sofort', () {
      expect(freieAnhangSlots(maxTotal: 0, bestand: 0, geladen: true), 0);
    });
  });
}
