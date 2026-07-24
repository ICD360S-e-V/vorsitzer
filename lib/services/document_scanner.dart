import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:opencv_core/opencv.dart' as cv;

/// Result of [DocumentScanner.prepare]: the orientation-normalized image plus
/// the auto-detected corners (null if none found → caller shows a default quad).
class PreparedScan {
  final Uint8List image; // EXIF-baked, upright JPEG — use this everywhere after
  final List<double>? corners; // 8 doubles (TL,TR,BR,BL px) or null
  const PreparedScan(this.image, this.corners);
}

/// On-device document detection + perspective de-skew, powered by OpenCV (FFI).
///
/// Everything heavy runs in a background isolate via [compute], so the camera
/// UI never blocks. Only plain bytes / doubles cross the isolate boundary — no
/// OpenCV objects — which keeps it isolate-safe. 100% on-device: nothing leaves
/// the phone, matching the Secure Cloud's zero-knowledge design.
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
  return PreparedScan(normalized, _detect(normalized));
}

// ── isolate entry points (top-level, so `compute` can run them) ──────────────

List<double>? _detect(Uint8List jpg) {
  final src = cv.imdecode(jpg, cv.IMREAD_COLOR);
  if (src.isEmpty) {
    src.dispose();
    return null;
  }
  cv.Mat? small, gray, blur, edges, dil, kernel;
  try {
    final w = src.cols, h = src.rows;
    final longSide = math.max(w, h);
    // Detect on a downscaled copy — much faster, corners scaled back up after.
    final scale = longSide > 1000 ? 1000 / longSide : 1.0;
    small = scale < 1.0
        ? cv.resize(src, ((w * scale).round(), (h * scale).round()))
        : src.clone();
    gray = cv.cvtColor(small, cv.COLOR_BGR2GRAY);
    blur = cv.gaussianBlur(gray, (5, 5), 0);
    edges = cv.canny(blur, 75, 200);
    kernel = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));
    dil = cv.dilate(edges, kernel); // close small gaps in the border
    final (contours, _) =
        cv.findContours(dil, cv.RETR_LIST, cv.CHAIN_APPROX_SIMPLE);
    final imgArea = small.cols * small.rows;
    double bestArea = 0;
    List<double>? best;
    for (final c in contours) {
      final area = cv.contourArea(c);
      if (area < imgArea * 0.2) continue; // ignore small blobs
      final approx = cv.approxPolyDP(c, 0.02 * cv.arcLength(c, true), true);
      if (approx.length == 4 && area > bestArea) {
        bestArea = area;
        final pts = <double>[];
        for (final p in approx) {
          pts.add(p.x / scale);
          pts.add(p.y / scale);
        }
        best = pts;
      }
    }
    return best == null ? null : _order(best);
  } catch (_) {
    return null;
  } finally {
    src.dispose();
    small?.dispose();
    gray?.dispose();
    blur?.dispose();
    edges?.dispose();
    dil?.dispose();
    kernel?.dispose();
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
  try {
    final o = _order(args.corners8); // TL, TR, BR, BL
    final tl = cv.Point(o[0].round(), o[1].round());
    final tr = cv.Point(o[2].round(), o[3].round());
    final br = cv.Point(o[4].round(), o[5].round());
    final bl = cv.Point(o[6].round(), o[7].round());
    double dist(cv.Point a, cv.Point b) =>
        math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2)).toDouble();
    final wOut = math.max(dist(tl, tr), dist(bl, br)).round().clamp(1, 10000);
    final hOut = math.max(dist(tl, bl), dist(tr, br)).round().clamp(1, 10000);
    final srcV = cv.VecPoint.fromList([tl, tr, br, bl]);
    final dstV = cv.VecPoint.fromList([
      cv.Point(0, 0),
      cv.Point(wOut - 1, 0),
      cv.Point(wOut - 1, hOut - 1),
      cv.Point(0, hOut - 1),
    ]);
    m = cv.getPerspectiveTransform(srcV, dstV);
    out = cv.warpPerspective(src, m, (wOut, hOut));
    final (ok, buf) =
        cv.imencode('.jpg', out, params: [cv.IMWRITE_JPEG_QUALITY, 92].i32);
    return ok ? buf : jpg;
  } catch (_) {
    return jpg;
  } finally {
    src.dispose();
    m?.dispose();
    out?.dispose();
  }
}

/// Order 4 points (as 8 flat doubles) into TL, TR, BR, BL. TL has the smallest
/// x+y, BR the largest; TR the largest x−y, BL the smallest.
List<double> _order(List<double> p) {
  final pts = [for (var i = 0; i < 8; i += 2) (p[i], p[i + 1])];
  (double, double) pick(double Function((double, double)) f, bool max) =>
      pts.reduce((a, b) => (max ? f(a) >= f(b) : f(a) <= f(b)) ? a : b);
  final tl = pick((e) => e.$1 + e.$2, false);
  final br = pick((e) => e.$1 + e.$2, true);
  final tr = pick((e) => e.$1 - e.$2, true);
  final bl = pick((e) => e.$1 - e.$2, false);
  return [tl.$1, tl.$2, tr.$1, tr.$2, br.$1, br.$2, bl.$1, bl.$2];
}
