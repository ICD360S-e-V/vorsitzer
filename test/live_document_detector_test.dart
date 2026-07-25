import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/live_document_detector.dart';

/// Build a synthetic 8-bit luma frame: dark background with a bright, rotated
/// quadrilateral "document" — the shape the live detector must lock onto.
Uint8List _luma(
  int w,
  int h, {
  required List<math.Point<double>> quad,
  int background = 30,
  int paper = 225,
}) {
  final buf = Uint8List(w * h)..fillRange(0, w * h, background);

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
      if (inside(x + 0.5, y + 0.5)) buf[y * w + x] = paper;
    }
  }
  return buf;
}

DetectionResult _analyse(Uint8List luma, int w, int h, ScanScratch s) =>
    analyseLumaFrame(<Object?>[luma, w, h, 480], s);

void main() {
  const w = 640, h = 480;
  final skewed = <math.Point<double>>[
    const math.Point(120, 70), // TL
    const math.Point(540, 110), // TR
    const math.Point(505, 415), // BR
    const math.Point(95, 380), // BL
  ];

  late ScanScratch scratch;
  setUp(() => scratch = ScanScratch());
  tearDown(() => scratch.dispose());

  test('detects the four corners of a skewed document', () {
    final got = _analyse(_luma(w, h, quad: skewed), w, h, scratch);

    expect(got.quadN, isNotNull, reason: 'detector found no quad at all');
    expect(got.quadN!.length, 8);
    expect(got.score, greaterThan(0.0));

    // Corners come back buffer-normalized; compare in source pixels.
    final found = [
      for (var i = 0; i < 8; i += 2)
        math.Point<double>(got.quadN![i] * w, got.quadN![i + 1] * h),
    ];
    for (final want in skewed) {
      final nearest = found
          .map((f) =>
              math.sqrt(math.pow(f.x - want.x, 2) + math.pow(f.y - want.y, 2)))
          .reduce(math.min);
      expect(nearest, lessThan(15.0),
          reason: 'corner $want unmatched; detector returned $found');
    }
  });

  test('returns the corners in TL, TR, BR, BL order', () {
    final got = _analyse(_luma(w, h, quad: skewed), w, h, scratch);
    final q = got.quadN!;
    expect(q[0], lessThan(q[2]), reason: 'TL should be left of TR');
    expect(q[3], lessThan(q[5]), reason: 'TR should be above BR');
    expect(q[6], lessThan(q[4]), reason: 'BL should be left of BR');
    expect(q[1], lessThan(q[7]), reason: 'TL should be above BL');
  });

  test('a flat, well-lit page scores high enough to auto-crop', () {
    final flat = <math.Point<double>>[
      const math.Point(110, 60),
      const math.Point(530, 60),
      const math.Point(530, 420),
      const math.Point(110, 420),
    ];
    final got = _analyse(_luma(w, h, quad: flat), w, h, scratch);
    expect(got.quadN, isNotNull);
    // 0.72 is the bar the crop screen uses to skip the manual editor.
    expect(got.score, greaterThan(0.72));
  });

  test('finds nothing in an empty frame', () {
    final blank = Uint8List(w * h)..fillRange(0, w * h, 30);
    final got = _analyse(blank, w, h, scratch);
    expect(got.quadN, isNull);
    expect(got.score, 0);
  });

  test('finds nothing in a uniformly bright frame', () {
    final white = Uint8List(w * h)..fillRange(0, w * h, 240);
    expect(_analyse(white, w, h, scratch).quadN, isNull);
  });

  test('rejects a page too small to be the subject', () {
    // ~2% of the frame — well under the 15% area gate.
    final tiny = <math.Point<double>>[
      const math.Point(300, 220),
      const math.Point(380, 220),
      const math.Point(380, 280),
      const math.Point(300, 280),
    ];
    expect(_analyse(_luma(w, h, quad: tiny), w, h, scratch).quadN, isNull);
  });

  test('survives a malformed frame instead of throwing', () {
    expect(_analyse(Uint8List(10), w, h, scratch).quadN, isNull);
    expect(analyseLumaFrame(<Object?>[Uint8List(0), 0, 0, 480], scratch).quadN,
        isNull);
  });

  test('reuses one scratch across many frames without degrading', () {
    final frame = _luma(w, h, quad: skewed);
    late DetectionResult first;
    for (var i = 0; i < 40; i++) {
      final got = _analyse(frame, w, h, scratch);
      if (i == 0) first = got;
      expect(got.quadN, isNotNull, reason: 'lost detection on frame $i');
      expect(got.quadN, first.quadN, reason: 'result drifted on frame $i');
    }
  });

  test('per-frame cost is fast enough for a live preview', () {
    final frame = _luma(w, h, quad: skewed);
    _analyse(frame, w, h, scratch); // warm up

    const runs = 30;
    final sw = Stopwatch()..start();
    for (var i = 0; i < runs; i++) {
      _analyse(frame, w, h, scratch);
    }
    sw.stop();
    final perFrameMs = sw.elapsedMicroseconds / runs / 1000;
    // ignore: avoid_print
    print('analyseLumaFrame: ${perFrameMs.toStringAsFixed(2)} ms/frame '
        '(${runs}x @ ${w}x$h)');
    // The 70 ms submit throttle targets ~14 fps; under 33 ms means even a slow
    // tablet never makes the preview wait.
    expect(perFrameMs, lessThan(33.0));
  });
}
