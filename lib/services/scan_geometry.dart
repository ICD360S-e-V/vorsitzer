import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

/// Pure geometry shared by the UI isolate, the detector worker and the still
/// path. No OpenCV types and no Flutter bindings, so every function here is
/// callable from any isolate.
///
/// Two coordinate spaces show up throughout:
///
///  * **buffer-normalized** — 0..1 over the analysis frame as the sensor
///    delivers it, origin top-left. What the worker returns.
///  * **upright-normalized** — the same points after the rotation the preview
///    applies, so they line up with what the user sees.
class ScanGeometry {
  // ── rotation ───────────────────────────────────────────────────────────────

  /// Buffer-normalized → upright-normalized.
  ///
  /// Mirror FIRST (buffer space), then rotate: the camera plugin composes
  /// `R ∘ Flip`, not `Flip ∘ R`.
  static (double, double) toUpright(double u, double v, int rotCW, bool mirrorY) {
    if (mirrorY) v = 1.0 - v;
    return switch (rotCW) {
      90 => (1.0 - v, u),
      180 => (1.0 - u, 1.0 - v),
      270 => (v, 1.0 - u),
      _ => (u, v),
    };
  }

  /// Width/height of the analysis frame *after* [rotCW] is applied.
  static double uprightAspect(int fw, int fh, int rotCW) =>
      rotCW % 180 == 0 ? fw / fh : fh / fw;

  /// Upright-normalized → pixels inside [box].
  ///
  /// Degenerates to a pure scale when the aspect ratios match, which is the
  /// normal case: `veryHigh` pins preview, capture and analysis to the same
  /// 16:9 selector. When a device's fallback rule resolves one use case to 4:3,
  /// the narrower stream is a centre crop of the wider one — that is what the
  /// two branches undo. Also used with [box] = the captured JPEG's pixel size.
  static Offset project(double u, double v, Size box, double uprightAspect) {
    final ba = box.width / box.height;
    if ((uprightAspect - ba).abs() <= 0.02 * ba) {
      return Offset(u * box.width, v * box.height);
    }
    if (uprightAspect > ba) {
      // Analysis is wider than the box → the box is a horizontal centre crop.
      final f = ba / uprightAspect;
      return Offset(((u - (1 - f) / 2) / f) * box.width, v * box.height);
    }
    final f = uprightAspect / ba; // analysis taller → vertical centre crop
    return Offset(u * box.width, ((v - (1 - f) / 2) / f) * box.height);
  }

  /// [quadN] is 8 upright-normalized doubles; result is 4 points inside [box].
  static List<Offset> projectQuad(List<double> quadN, double uprightAspect, Size box) => [
        for (var i = 0; i < 8; i += 2)
          project(quadN[i], quadN[i + 1], box, uprightAspect),
      ];

  // ── ordering ───────────────────────────────────────────────────────────────

  /// Order 4 points (8 flat doubles) into TL, TR, BR, BL.
  ///
  /// Sorting by angle around the centroid yields a consistent cycle for any
  /// convex quad; the cycle is then rotated to start at the corner nearest the
  /// top-left. The older min(x+y)/max(x−y) trick picks the *same* point for two
  /// corners on a ~45°-rotated page — e.g. (0,1),(1,0),(2,1),(1,2) gives
  /// TL == BL == (0,1) — which warps to a degenerate rectangle.
  static List<double> orderQuad(List<double> p) {
    final pts = [for (var i = 0; i < 8; i += 2) Offset(p[i], p[i + 1])];
    final c = pts.reduce((a, b) => a + b) / 4.0;
    // y grows downward, so ascending atan2 is clockwise on screen.
    pts.sort((a, b) => (a - c).direction.compareTo((b - c).direction));
    var k = 0;
    var best = double.infinity;
    for (var i = 0; i < 4; i++) {
      final s = pts[i].dx + pts[i].dy;
      if (s < best) {
        best = s;
        k = i;
      }
    }
    return [
      for (var i = 0; i < 4; i++) ...[pts[(k + i) % 4].dx, pts[(k + i) % 4].dy],
    ];
  }

  // ── metrics ────────────────────────────────────────────────────────────────
  // Callers must pass isotropic (square-pixel) coordinates: downscaled buffer
  // pixels in the worker, or (u * uprightAspect, v) in the UI.

  /// Shoelace area of the quad.
  static double quadArea(List<double> q) {
    var s = 0.0;
    for (var i = 0; i < 4; i++) {
      final j = (i + 1) % 4;
      s += q[i * 2] * q[j * 2 + 1] - q[j * 2] * q[i * 2 + 1];
    }
    return s.abs() / 2.0;
  }

  /// Largest deviation of an interior angle from 90°, in degrees.
  static double maxAngleDeviationDeg(List<double> q) {
    var worst = 0.0;
    for (var i = 0; i < 4; i++) {
      final p = Offset(q[((i + 3) % 4) * 2], q[((i + 3) % 4) * 2 + 1]);
      final c = Offset(q[i * 2], q[i * 2 + 1]);
      final n = Offset(q[((i + 1) % 4) * 2], q[((i + 1) % 4) * 2 + 1]);
      final a = p - c, b = n - c;
      final la = a.distance, lb = b.distance;
      if (la == 0 || lb == 0) return 180.0;
      final cos = ((a.dx * b.dx + a.dy * b.dy) / (la * lb)).clamp(-1.0, 1.0);
      final deg = math.acos(cos) * 180.0 / math.pi;
      worst = math.max(worst, (deg - 90.0).abs());
    }
    return worst;
  }

  /// How parallel the two pairs of opposite sides are: 1.0 for a rectangle
  /// viewed head-on, → 0 for extreme perspective.
  static double minOppositeSideRatio(List<double> q) {
    double side(int i) {
      final j = (i + 1) % 4;
      return (Offset(q[j * 2], q[j * 2 + 1]) - Offset(q[i * 2], q[i * 2 + 1]))
          .distance;
    }

    final top = side(0), right = side(1), bottom = side(2), left = side(3);
    double ratio(double a, double b) {
      final hi = math.max(a, b);
      return hi == 0 ? 0.0 : math.min(a, b) / hi;
    }

    return math.min(ratio(top, bottom), ratio(left, right));
  }

  /// Mean per-corner distance between two quads in the same order/space.
  static double meanCornerDistance(List<double> a, List<double> b) {
    var sum = 0.0;
    for (var i = 0; i < 8; i += 2) {
      sum += (Offset(a[i], a[i + 1]) - Offset(b[i], b[i + 1])).distance;
    }
    return sum / 4.0;
  }

  /// Largest per-corner distance between two quads in the same order/space.
  static double maxCornerDistance(List<double> a, List<double> b) {
    var worst = 0.0;
    for (var i = 0; i < 8; i += 2) {
      worst = math.max(
          worst, (Offset(a[i], a[i + 1]) - Offset(b[i], b[i + 1])).distance);
    }
    return worst;
  }

  // ── smoothing ──────────────────────────────────────────────────────────────

  /// Heavy averaging at rest, near-passthrough while moving.
  ///
  /// At rest this kills the ±1–2 px per-frame contour jitter that makes cheap
  /// scanners look nervous; while moving it lets the outline keep up so it
  /// never lags and lies about where the corners are. [d] is the corner's
  /// movement since the previous accepted frame, in isotropic upright units
  /// (1.0 == frame height).
  static double alphaFor(double d) {
    const aSlow = 0.18, aFast = 0.85, dLo = 0.002, dHi = 0.015;
    final t = ((d - dLo) / (dHi - dLo)).clamp(0.0, 1.0);
    return aSlow + (aFast - aSlow) * t;
  }

  /// Beyond this the filter is bypassed entirely — it is a different document,
  /// not a nudge of the same one.
  static const double snapDistance = 0.08;
}

/// The live overlay's belief about the document at the moment the shutter
/// fired, carried into the crop screen so it can skip the manual step.
class ScanHint {
  /// 8 upright-normalized doubles, ordered TL, TR, BR, BL.
  final List<double> quadN;
  final double uprightAspect;

  /// 0..1 — how strongly the live pipeline believed this quad.
  final double confidence;

  const ScanHint(this.quadN, this.uprightAspect, this.confidence);
}
