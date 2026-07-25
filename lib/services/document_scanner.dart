import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:opencv_core/opencv.dart' as cv;

import 'scan_geometry.dart';

/// Result of [DocumentScanner.prepare]: the orientation-normalized image plus
/// the auto-detected corners (null if none found → caller shows a default quad).
class PreparedScan {
  final Uint8List image; // EXIF-baked, upright JPEG — use this everywhere after
  final List<double>? corners; // 8 doubles (TL,TR,BR,BL px) or null
  final double score; // 0..1 quality of [corners]; 0 when none were found
  const PreparedScan(this.image, this.corners, this.score);
}

/// On-device document detection + perspective de-skew, powered by OpenCV (FFI).
///
/// Everything heavy runs in a background isolate via [compute], so the camera
/// UI never blocks. Only plain bytes / doubles cross the isolate boundary — no
/// OpenCV objects — which keeps it isolate-safe. 100% on-device: nothing leaves
/// the phone, matching the Secure Cloud's zero-knowledge design.
///
/// The live preview scanner shares [findDocumentQuad] with this still path, so
/// "the overlay locked on" is real evidence that the still will detect too.
class DocumentScanner {
  /// Bake the JPEG's EXIF orientation into pixels (so the Flutter preview and
  /// OpenCV agree on coordinates), then auto-detect the document corners.
  static Future<PreparedScan> prepare(Uint8List jpg) => compute(_prepare, jpg);

  /// De-skew [jpg] so the quad [corners8] (8 doubles, any corner order) becomes
  /// an upright rectangle sized to the document. Returns JPEG bytes (the
  /// original on any failure).
  static Future<Uint8List> deskew(Uint8List jpg, List<double> corners8) =>
      compute(_warp, _DeskewArgs(jpg, corners8));
}

PreparedScan _prepare(Uint8List jpg) {
  var normalized = jpg;
  try {
    final decoded = img.decodeImage(jpg);
    if (decoded != null) {
      normalized = img.encodeJpg(img.bakeOrientation(decoded), quality: 95);
    }
  } catch (_) {
    normalized = jpg;
  }
  final found = _detect(normalized);
  return PreparedScan(normalized, found?.quad, found?.score ?? 0.0);
}

// ── shared scoring ───────────────────────────────────────────────────────────

/// A document quad plus how strongly the geometry supports it.
class QuadCandidate {
  final List<double> quad; // 8 doubles, ordered TL, TR, BR, BL
  final double score; // 0..1
  const QuadCandidate(this.quad, this.score);
}

/// Hard gates. Any failure means *no quad this frame* rather than a low score —
/// a confidently-drawn wrong quad is worse for the user than no quad at all.
const double _kMinAreaFrac = 0.15;
const double _kMaxAreaFrac = 0.985; // above this it locked onto the frame border
const double _kMaxAngleDev = 45.0;
const double _kMinSideRatio = 0.50;
const double _kMinEdgeSupport = 0.50;
const double _kMinSolidity = 0.85;

/// Best document quad among [contours], scored against [edges] (a Canny image
/// of the same [w] x [h]). Coordinates are downscaled buffer pixels — square,
/// so every angle/ratio below is isotropic without correction.
///
/// The second pass with a looser epsilon recovers pages whose corners are
/// rounded or whose edge curls, which a single 0.02 pass approximates as 5+
/// vertices and discards.
QuadCandidate? findDocumentQuad(cv.Contours contours, cv.Mat edges, int w, int h) {
  final imgArea = (w * h).toDouble();
  QuadCandidate? best;
  for (final epsFrac in const [0.02, 0.035]) {
    for (final c in contours) {
      // NOTE: `c` is a non-owning reference into `contours` — disposing it is a
      // double free. Only the approxPolyDP result below belongs to us.
      final area = cv.contourArea(c);
      if (area < imgArea * _kMinAreaFrac || area > imgArea * _kMaxAreaFrac) {
        continue;
      }
      final peri = cv.arcLength(c, true);
      if (peri <= 0) continue;
      cv.VecPoint? approx;
      try {
        approx = cv.approxPolyDP(c, epsFrac * peri, true);
        if (approx.length != 4) continue;
        if (!cv.isContourConvex(approx)) continue;
        final q = ScanGeometry.orderQuad([
          for (final p in approx) ...[p.x.toDouble(), p.y.toDouble()],
        ]);
        final s = _scoreQuad(q, area, imgArea, edges, w, h);
        if (s > 0 && (best == null || s > best.score)) {
          best = QuadCandidate(q, s);
        }
      } finally {
        approx?.dispose();
      }
    }
    if (best != null) break;
  }
  return best;
}

/// 0 when any hard gate fails, otherwise a weighted 0..1 quality.
double _scoreQuad(
  List<double> q,
  double contourArea,
  double imgArea,
  cv.Mat edges,
  int w,
  int h,
) {
  // Every corner must lie inside the frame (with a 2% tolerance for a page
  // running slightly off-screen). Without this the frame border itself scores
  // beautifully.
  for (var i = 0; i < 8; i += 2) {
    if (q[i] < -0.02 * w || q[i] > 1.02 * w) return 0;
    if (q[i + 1] < -0.02 * h || q[i + 1] > 1.02 * h) return 0;
  }

  final qArea = ScanGeometry.quadArea(q);
  if (qArea <= 0) return 0;
  final areaFrac = qArea / imgArea;
  if (areaFrac < _kMinAreaFrac || areaFrac > _kMaxAreaFrac) return 0;

  // approxPolyDP must not have cut off a big bulge of the contour.
  final solidity = math.min(qArea, contourArea) / math.max(qArea, contourArea);
  if (solidity < _kMinSolidity) return 0;

  final angleDev = ScanGeometry.maxAngleDeviationDeg(q);
  if (angleDev > _kMaxAngleDev) return 0;

  final sideRatio = ScanGeometry.minOppositeSideRatio(q);
  if (sideRatio < _kMinSideRatio) return 0;

  final edgeSupport = _edgeSupport(q, edges);
  if (edgeSupport < _kMinEdgeSupport) return 0;

  final fArea = ((areaFrac - 0.15) / 0.30).clamp(0.0, 1.0);
  final fAngle = (1 - (angleDev - 12) / 28).clamp(0.0, 1.0);
  final fSides = ((sideRatio - 0.55) / 0.30).clamp(0.0, 1.0);
  final fEdge = ((edgeSupport - 0.55) / 0.30).clamp(0.0, 1.0);
  return 0.30 * fArea + 0.25 * fAngle + 0.20 * fSides + 0.25 * fEdge;
}

/// Fraction of points sampled along the four sides that sit within 2 px of a
/// Canny edge pixel.
///
/// This is the anti-false-positive term, and the one thing separating "found
/// *a* quadrilateral" from "found *the document*": a quad stitched together
/// from a table edge and a shadow passes every shape gate but has almost no
/// real edge underneath its sides.
double _edgeSupport(List<double> q, cv.Mat edges) {
  const perSide = 40, tol = 2;
  // `data` is a view over native memory — valid only while `edges` is alive.
  final data = edges.data;
  final rows = edges.rows, cols = edges.cols;
  if (rows <= 0 || cols <= 0 || data.length < rows * cols) return 0;
  var hit = 0, total = 0;
  for (var i = 0; i < 4; i++) {
    final ax = q[i * 2], ay = q[i * 2 + 1];
    final bx = q[((i + 1) % 4) * 2], by = q[((i + 1) % 4) * 2 + 1];
    for (var s = 1; s < perSide; s++) {
      final t = s / perSide;
      final x = (ax + (bx - ax) * t).round();
      final y = (ay + (by - ay) * t).round();
      total++;
      search:
      for (var dy = -tol; dy <= tol; dy++) {
        final yy = y + dy;
        if (yy < 0 || yy >= rows) continue;
        for (var dx = -tol; dx <= tol; dx++) {
          final xx = x + dx;
          if (xx < 0 || xx >= cols) continue;
          if (data[yy * cols + xx] != 0) {
            hit++;
            break search;
          }
        }
      }
    }
  }
  return total == 0 ? 0.0 : hit / total;
}

/// Canny thresholds derived from the image itself.
///
/// Otsu picks a scene-dependent split, so the same code survives a lit desk and
/// a dim hallway. A fixed (75, 200) is the single biggest cause of "it stopped
/// detecting indoors", and on iOS the luma is video-range (16–235), which fixed
/// thresholds handle badly.
(double, double) cannyThresholds(cv.Mat blurred) {
  cv.Mat? dst;
  try {
    final (otsu, d) =
        cv.threshold(blurred, 0, 255, cv.THRESH_BINARY | cv.THRESH_OTSU);
    dst = d;
    final hi = otsu.clamp(40.0, 200.0);
    return (hi * 0.4, hi);
  } catch (_) {
    return (75.0, 200.0);
  } finally {
    dst?.dispose();
  }
}

// ── isolate entry points (top-level, so `compute` can run them) ──────────────

QuadCandidate? _detect(Uint8List jpg) {
  final src = cv.imdecode(jpg, cv.IMREAD_COLOR);
  if (src.isEmpty) {
    src.dispose();
    return null;
  }
  cv.Mat? small, gray, blur, edges, closed, kernel;
  cv.Contours? contours;
  cv.VecVec4i? hierarchy;
  try {
    final w = src.cols, h = src.rows;
    final longSide = math.max(w, h);
    // Detect on a downscaled copy — much faster, corners scaled back up after.
    final scale = longSide > 1000 ? 1000 / longSide : 1.0;
    small = scale < 1.0
        ? cv.resize(src, ((w * scale).round(), (h * scale).round()),
            interpolation: cv.INTER_AREA)
        : src.clone();
    gray = cv.cvtColor(small, cv.COLOR_BGR2GRAY);
    blur = cv.gaussianBlur(gray, (5, 5), 0);
    final (lo, hi) = cannyThresholds(blur);
    edges = cv.canny(blur, lo, hi);
    kernel = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));
    closed = cv.morphologyEx(edges, cv.MORPH_CLOSE, kernel);
    // RETR_LIST, not RETR_EXTERNAL: a page on a desk is frequently *enclosed*
    // by the desk's own edge contour, and RETR_EXTERNAL would return the desk
    // and drop the page.
    final (cs, hi2) =
        cv.findContours(closed, cv.RETR_LIST, cv.CHAIN_APPROX_SIMPLE);
    contours = cs;
    hierarchy = hi2;
    final best = findDocumentQuad(contours, closed, small.cols, small.rows);
    if (best == null) return null;
    return QuadCandidate(
      [for (final v in best.quad) v / scale],
      best.score,
    );
  } catch (_) {
    return null;
  } finally {
    contours?.dispose();
    hierarchy?.dispose();
    closed?.dispose();
    edges?.dispose();
    blur?.dispose();
    gray?.dispose();
    small?.dispose();
    kernel?.dispose();
    src.dispose();
  }
}

class _DeskewArgs {
  final Uint8List jpg;
  final List<double> corners8;
  const _DeskewArgs(this.jpg, this.corners8);
}

Uint8List _warp(_DeskewArgs args) {
  final jpg = args.jpg;
  final src = cv.imdecode(jpg, cv.IMREAD_COLOR);
  if (src.isEmpty) {
    src.dispose();
    return jpg;
  }
  cv.Mat? m, out;
  cv.VecPoint2f? srcV, dstV;
  try {
    final o = ScanGeometry.orderQuad(args.corners8); // TL, TR, BR, BL
    // Keep sub-pixel accuracy: rounding corners to ints before the transform
    // visibly skews a 4000px-wide scan.
    final tl = cv.Point2f(o[0], o[1]);
    final tr = cv.Point2f(o[2], o[3]);
    final br = cv.Point2f(o[4], o[5]);
    final bl = cv.Point2f(o[6], o[7]);
    double dist(cv.Point2f a, cv.Point2f b) =>
        math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2)).toDouble();
    final wOut = math.max(dist(tl, tr), dist(bl, br)).round().clamp(1, 10000);
    final hOut = math.max(dist(tl, bl), dist(tr, br)).round().clamp(1, 10000);
    srcV = cv.VecPoint2f.fromList([tl, tr, br, bl]);
    dstV = cv.VecPoint2f.fromList([
      cv.Point2f(0, 0),
      cv.Point2f(wOut - 1, 0),
      cv.Point2f(wOut - 1, hOut - 1),
      cv.Point2f(0, hOut - 1),
    ]);
    m = cv.getPerspectiveTransform2f(srcV, dstV);
    out = cv.warpPerspective(src, m, (wOut, hOut));
    final (ok, buf) =
        cv.imencode('.jpg', out, params: [cv.IMWRITE_JPEG_QUALITY, 92].i32);
    return ok ? buf : jpg;
  } catch (_) {
    return jpg;
  } finally {
    srcV?.dispose();
    dstV?.dispose();
    m?.dispose();
    out?.dispose();
    src.dispose();
  }
}
