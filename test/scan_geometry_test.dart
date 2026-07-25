import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/scan_geometry.dart';

void main() {
  group('orderQuad', () {
    test('orders an axis-aligned rectangle TL, TR, BR, BL', () {
      final got = ScanGeometry.orderQuad([10, 10, 90, 10, 90, 50, 10, 50]);
      expect(got, [10, 10, 90, 10, 90, 50, 10, 50]);
    });

    test('orders the same rectangle regardless of input rotation', () {
      const rect = [10.0, 10.0, 90.0, 10.0, 90.0, 50.0, 10.0, 50.0];
      for (var shift = 0; shift < 4; shift++) {
        final rotated = <double>[
          for (var i = 0; i < 4; i++) ...[
            rect[((i + shift) % 4) * 2],
            rect[((i + shift) % 4) * 2 + 1],
          ],
        ];
        expect(ScanGeometry.orderQuad(rotated), rect,
            reason: 'input shifted by $shift');
      }
    });

    test('handles a 45°-rotated diamond without duplicating a corner', () {
      // This is the case the old min(x+y)/max(x−y) ordering got wrong: it
      // picked (0,1) as BOTH top-left and bottom-left, warping to a degenerate
      // rectangle.
      final got = ScanGeometry.orderQuad([0, 1, 1, 0, 2, 1, 1, 2]);
      final pts = [
        for (var i = 0; i < 8; i += 2) Offset(got[i], got[i + 1]),
      ];
      expect(pts.toSet().length, 4, reason: 'a corner was used twice: $pts');
      // Still a valid, non-degenerate quad.
      expect(ScanGeometry.quadArea(got), closeTo(2.0, 1e-9));
    });

    test('produces a consistent clockwise cycle', () {
      final got = ScanGeometry.orderQuad([0, 1, 1, 0, 2, 1, 1, 2]);
      // Shoelace of a clockwise polygon in screen coords (y down) is positive.
      var s = 0.0;
      for (var i = 0; i < 4; i++) {
        final j = (i + 1) % 4;
        s += got[i * 2] * got[j * 2 + 1] - got[j * 2] * got[i * 2 + 1];
      }
      expect(s, greaterThan(0));
    });
  });

  group('toUpright', () {
    test('0° is identity', () {
      expect(ScanGeometry.toUpright(0.25, 0.75, 0, false), (0.25, 0.75));
    });

    test('90° CW maps buffer top-left to box top-right', () {
      final (u, v) = ScanGeometry.toUpright(0, 0, 90, false);
      expect(u, closeTo(1.0, 1e-12));
      expect(v, closeTo(0.0, 1e-12));
    });

    test('90° CW maps buffer top-right to box bottom-right', () {
      final (u, v) = ScanGeometry.toUpright(1, 0, 90, false);
      expect(u, closeTo(1.0, 1e-12));
      expect(v, closeTo(1.0, 1e-12));
    });

    test('four 90° turns return to the original point', () {
      var p = (0.3, 0.8);
      for (var i = 0; i < 4; i++) {
        p = ScanGeometry.toUpright(p.$1, p.$2, 90, false);
      }
      expect(p.$1, closeTo(0.3, 1e-12));
      expect(p.$2, closeTo(0.8, 1e-12));
    });

    test('mirror is applied in buffer space, before the rotation', () {
      // Flip then rotate 90° CW: (u,v) -> (u, 1-v) -> (1-(1-v), u) = (v, u).
      final (u, v) = ScanGeometry.toUpright(0.2, 0.9, 90, true);
      expect(u, closeTo(0.9, 1e-12));
      expect(v, closeTo(0.2, 1e-12));
    });
  });

  group('uprightAspect', () {
    test('passes through at 0/180 and transposes at 90/270', () {
      expect(ScanGeometry.uprightAspect(1920, 1080, 0), closeTo(16 / 9, 1e-9));
      expect(ScanGeometry.uprightAspect(1920, 1080, 180), closeTo(16 / 9, 1e-9));
      expect(ScanGeometry.uprightAspect(1920, 1080, 90), closeTo(9 / 16, 1e-9));
      expect(ScanGeometry.uprightAspect(1920, 1080, 270), closeTo(9 / 16, 1e-9));
    });
  });

  group('project', () {
    test('is a pure scale when aspects match', () {
      final p = ScanGeometry.project(0.5, 0.25, const Size(360, 640), 360 / 640);
      expect(p.dx, closeTo(180, 1e-9));
      expect(p.dy, closeTo(160, 1e-9));
    });

    test('undoes a horizontal centre crop when the analysis is wider', () {
      // Analysis 2:1, box 1:1 → the box shows the middle half horizontally.
      const box = Size(100, 100);
      expect(ScanGeometry.project(0.5, 0.5, box, 2.0).dx, closeTo(50, 1e-9));
      expect(ScanGeometry.project(0.25, 0.5, box, 2.0).dx, closeTo(0, 1e-9));
      expect(ScanGeometry.project(0.75, 0.5, box, 2.0).dx, closeTo(100, 1e-9));
    });

    test('undoes a vertical centre crop when the analysis is taller', () {
      const box = Size(100, 100);
      expect(ScanGeometry.project(0.5, 0.5, box, 0.5).dy, closeTo(50, 1e-9));
      expect(ScanGeometry.project(0.5, 0.25, box, 0.5).dy, closeTo(0, 1e-9));
    });
  });

  group('metrics', () {
    const rect = [0.0, 0.0, 100.0, 0.0, 100.0, 50.0, 0.0, 50.0];

    test('quadArea uses the shoelace formula', () {
      expect(ScanGeometry.quadArea(rect), closeTo(5000, 1e-9));
    });

    test('a rectangle has zero angle deviation and ratio 1', () {
      expect(ScanGeometry.maxAngleDeviationDeg(rect), closeTo(0, 1e-6));
      expect(ScanGeometry.minOppositeSideRatio(rect), closeTo(1, 1e-9));
    });

    test('a trapezoid scores a lower opposite-side ratio', () {
      const trapezoid = [20.0, 0.0, 80.0, 0.0, 100.0, 50.0, 0.0, 50.0];
      expect(ScanGeometry.minOppositeSideRatio(trapezoid), closeTo(0.6, 1e-9));
      expect(ScanGeometry.maxAngleDeviationDeg(trapezoid), greaterThan(10));
    });

    test('corner distances', () {
      const shifted = [3.0, 4.0, 103.0, 4.0, 100.0, 50.0, 0.0, 50.0];
      expect(ScanGeometry.maxCornerDistance(rect, shifted), closeTo(5, 1e-9));
      expect(ScanGeometry.meanCornerDistance(rect, shifted), closeTo(2.5, 1e-9));
    });
  });

  group('alphaFor', () {
    test('averages heavily at rest and passes through while moving', () {
      expect(ScanGeometry.alphaFor(0.0), closeTo(0.18, 1e-9));
      expect(ScanGeometry.alphaFor(1.0), closeTo(0.85, 1e-9));
    });

    test('is monotonic in movement', () {
      var prev = -1.0;
      for (var d = 0.0; d <= 0.02; d += 0.001) {
        final a = ScanGeometry.alphaFor(d);
        expect(a, greaterThanOrEqualTo(prev));
        prev = a;
      }
    });
  });

  test('a full buffer→preview round trip lands where you would draw it', () {
    // Portrait phone: 16:9 sensor buffer, 90° sensor orientation, preview box
    // 1080x1920. A quad in the middle of the buffer must land in the middle of
    // the box, and buffer-top-left must land at box-top-right.
    const rotCW = 90;
    const fw = 1920, fh = 1080;
    final ua = ScanGeometry.uprightAspect(fw, fh, rotCW);
    const box = Size(1080, 1920);

    final (cu, cv) = ScanGeometry.toUpright(0.5, 0.5, rotCW, false);
    final centre = ScanGeometry.project(cu, cv, box, ua);
    expect(centre.dx, closeTo(540, 1e-6));
    expect(centre.dy, closeTo(960, 1e-6));

    final (tu, tv) = ScanGeometry.toUpright(0, 0, rotCW, false);
    final topLeft = ScanGeometry.project(tu, tv, box, ua);
    expect(topLeft.dx, closeTo(1080, 1e-6));
    expect(topLeft.dy, closeTo(0, 1e-6));
  });

  test('projectQuad keeps corner order and stays inside the box', () {
    final pts = ScanGeometry.projectQuad(
      [0.1, 0.1, 0.9, 0.1, 0.9, 0.9, 0.1, 0.9],
      1.0,
      const Size(200, 200),
    );
    expect(pts.length, 4);
    expect(pts[0], const Offset(20, 20));
    expect(pts[2], const Offset(180, 180));
    for (final p in pts) {
      expect(p.dx, inInclusiveRange(0, 200));
      expect(p.dy, inInclusiveRange(0, 200));
    }
  });

  test('ScanHint carries the quad verbatim', () {
    final h = ScanHint(const [1, 2, 3, 4, 5, 6, 7, 8], 0.5625, 0.9);
    expect(h.quadN.length, 8);
    expect(h.uprightAspect, closeTo(0.5625, 1e-9));
    expect(h.confidence, closeTo(0.9, 1e-9));
  });

  test('orderQuad is stable under small jitter', () {
    final rnd = math.Random(7);
    const base = [10.0, 12.0, 90.0, 10.0, 92.0, 51.0, 11.0, 49.0];
    final first = ScanGeometry.orderQuad(base);
    for (var i = 0; i < 50; i++) {
      final jittered = [
        for (final v in base) v + (rnd.nextDouble() - 0.5) * 0.4,
      ];
      final got = ScanGeometry.orderQuad(jittered);
      for (var k = 0; k < 8; k++) {
        expect(got[k], closeTo(first[k], 1.0));
      }
    }
  });
}
