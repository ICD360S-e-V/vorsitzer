import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:icd360sev_vorsitzer/services/document_scanner.dart';

Uint8List _jpg(int w, int h) {
  final b = img.Image(width: w, height: h);
  // etwas Struktur, damit JPEG nicht auf eine Fläche zusammenfällt
  for (var y = 0; y < h; y += 7) {
    for (var x = 0; x < w; x++) {
      b.setPixelRgb(x, y, 20, 20, 20);
    }
  }
  return Uint8List.fromList(img.encodeJpg(b, quality: 92));
}

void main() {
  group('DocumentScanner.begrenzen', () {
    test('A4 hochkant bei 150 dpi ist die Zielgröße', () {
      // 210 x 297 mm bei 150 dpi
      expect(kScanLangeSeitePx, 1754);
    });

    test('ein zu großes Bild wird auf die lange Kante begrenzt', () async {
      final raus = await DocumentScanner.begrenzen(_jpg(3000, 4000));
      final b = img.decodeImage(raus)!;
      expect(b.height, kScanLangeSeitePx);
      // Seitenverhältnis bleibt
      expect(b.width, closeTo(3000 * kScanLangeSeitePx / 4000, 1));
    });

    test('quer: die lange Kante ist die breite', () async {
      final raus = await DocumentScanner.begrenzen(_jpg(4000, 3000));
      final b = img.decodeImage(raus)!;
      expect(b.width, kScanLangeSeitePx);
    });

    // ⚠️ Ein kleiner Beleg darf NICHT auf A4-Maß aufgeblasen werden — das
    // erfände Bildpunkte, die nie aufgenommen wurden, und macht die Erkennung
    // nicht besser, nur die Datei größer.
    // ⚠️ Byte-Gleichheit, nicht Identität: compute() schickt die Daten durch
    // einen Isolate, dort kommt zwangsläufig eine Kopie zurück. Ein
    // `same()` kann hier nie halten, egal wie richtig der Code ist.
    test('ein kleineres Bild bleibt unverändert — Byte für Byte', () async {
      final rein = _jpg(800, 1000);
      final raus = await DocumentScanner.begrenzen(rein);
      expect(raus, orderedEquals(rein), reason: 'nicht neu kodieren, wenn nichts zu tun ist');
    });

    test('genau auf der Grenze bleibt unverändert', () async {
      final rein = _jpg(1240, kScanLangeSeitePx);
      expect(await DocumentScanner.begrenzen(rein), orderedEquals(rein));
    });

    // ⚠️ Lieber zu groß als gar nichts: ein kaputtes Bild darf den Upload
    // nicht verschlucken.
    test('unlesbare Bytes kommen unverändert zurück', () async {
      final muell = Uint8List.fromList(List.filled(64, 7));
      expect(await DocumentScanner.begrenzen(muell), orderedEquals(muell));
    });
  });
}
