import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/live_document_detector.dart';

/// Build a synthetic NV21 frame: dark background with a bright, rotated
/// quadrilateral "document" — the shape the live detector must lock onto.
Uint8List _frameWithDocument(
  int w,
  int h, {
  required List<math.Point<double>> quad,
}) {
  final nv21 = Uint8List(w * h + (w * h) ~/ 2);
  nv21.fillRange(0, w * h, 30); // dark table
  nv21.fillRange(w * h, nv21.length, 128); // neutral chroma

  bool inside(double px, double py) {
    var sign = 0;
    for (var i = 0; i < 4; i++) {
      final a = quad[i], b = quad[(i + 1) % 4];
      final cross = (b.x - a.x) * (py - a.y) - (b.y - a.y) * (px - a.x);
      if (cross == 0) continue;
      final s = cross > 0 ? 1 : -1;
      if (sign == 0) {
        sign = s;
      } else if (s != sign) {
        return false;
      }
    }
    return true;
  }

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (inside(x + 0.5, y + 0.5)) nv21[y * w + x] = 225; // white paper
    }
  }
  return nv21;
}

void main() {
  const w = 640, h = 480;
  final quad = <math.Point<double>>[
    const math.Point(120, 70), // TL
    const math.Point(540, 110), // TR
    const math.Point(505, 415), // BR
    const math.Point(95, 380), // BL
  ];

  test('detects the four corners of a skewed document in an NV21 frame', () {
    final frame = _frameWithDocument(w, h, quad: quad);
    final got = LiveDocumentDetector.detectNv21(frame, w, h);

    expect(got, isNotNull, reason: 'detector found no quad at all');
    expect(got!.length, 8);

    // Every expected corner must have a detected corner near it. Tolerance is
    // generous because detection runs on a 480px-downscaled copy.
    final found = [
      for (var i = 0; i < 8; i += 2) math.Point<double>(got[i], got[i + 1]),
    ];
    for (final want in quad) {
      final nearest = found
          .map((f) => math.sqrt(
              math.pow(f.x - want.x, 2) + math.pow(f.y - want.y, 2)))
          .reduce(math.min);
      expect(nearest, lessThan(15.0),
          reason: 'corner $want unmatched; detector returned $found');
    }
  });

  test('returns null on a frame with no document', () {
    final blank = Uint8List(w * h + (w * h) ~/ 2)..fillRange(0, w * h, 30);
    expect(LiveDocumentDetector.detectNv21(blank, w, h), isNull);
  });

  test('per-frame cost is fast enough for a live preview', () {
    final frame = _frameWithDocument(w, h, quad: quad);
    LiveDocumentDetector.detectNv21(frame, w, h); // warm up

    const runs = 30;
    final sw = Stopwatch()..start();
    for (var i = 0; i < runs; i++) {
      LiveDocumentDetector.detectNv21(frame, w, h);
    }
    sw.stop();
    final perFrameMs = sw.elapsedMicroseconds / runs / 1000;
    // ignore: avoid_print
    print('detectNv21: ${perFrameMs.toStringAsFixed(2)} ms/frame (${runs}x)');
    expect(perFrameMs, lessThan(100.0));
  });
}
