import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_core/opencv.dart' as cv;

/// COMPILE PROBE — verifies every OpenCV API the live detector needs really
/// exists in opencv_core 1.4.5 / dartcv4 1.1.8. Not wired into the UI yet.
class LiveDocumentDetector {
  /// Detect a document quad in a single NV21 camera frame.
  ///
  /// The first [w]*[h] bytes of an NV21 buffer are the luminance plane, so we
  /// can wrap them as an 8-bit single-channel Mat with no colour conversion and
  /// no row-stride arithmetic — the CameraX plugin hands us a contiguous plane.
  static List<double>? detectNv21(Uint8List nv21, int w, int h) {
    final yPlane = Uint8List.sublistView(nv21, 0, w * h);
    cv.Mat? gray, small, blur, edges, kernel, dil;
    cv.VecUChar? vec;
    try {
      vec = cv.VecUChar.fromList(yPlane);
      gray = cv.Mat.fromVec(vec, rows: h, cols: w, type: cv.MatType.CV_8UC1);

      final longSide = math.max(w, h);
      final scale = longSide > 480 ? 480 / longSide : 1.0;
      small = scale < 1.0
          ? cv.resize(gray, ((w * scale).round(), (h * scale).round()))
          : gray.clone();

      blur = cv.gaussianBlur(small, (5, 5), 0);
      edges = cv.canny(blur, 60, 180);
      kernel = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));
      dil = cv.dilate(edges, kernel);

      final (contours, _) =
          cv.findContours(dil, cv.RETR_LIST, cv.CHAIN_APPROX_SIMPLE);
      final frameArea = small.cols * small.rows;
      double bestArea = 0;
      List<double>? best;
      for (final c in contours) {
        final area = cv.contourArea(c);
        if (area < frameArea * 0.15 || area <= bestArea) continue;
        final approx = cv.approxPolyDP(c, 0.02 * cv.arcLength(c, true), true);
        if (approx.length != 4) continue;
        if (!cv.isContourConvex(approx)) continue;
        bestArea = area;
        best = [
          for (final p in approx) ...[p.x / scale, p.y / scale],
        ];
      }
      return best;
    } catch (_) {
      return null; // a bad frame must never kill the preview
    } finally {
      vec?.dispose();
      gray?.dispose();
      small?.dispose();
      blur?.dispose();
      edges?.dispose();
      kernel?.dispose();
      dil?.dispose();
    }
  }
}
