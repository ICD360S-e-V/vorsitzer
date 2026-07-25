import 'dart:async';
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:opencv_core/opencv.dart' as cv;

import 'document_scanner.dart';
import 'scan_geometry.dart';

/// One analysed camera frame.
class DetectionResult {
  /// 8 doubles, buffer-normalized 0..1, ordered TL, TR, BR, BL — or null when
  /// no quad passed the gates.
  final List<double>? quadN;

  /// 0..1 geometric quality; 0 when [quadN] is null.
  final double score;

  /// Size of the downscaled frame the detection actually ran on.
  final int frameWidth, frameHeight;

  const DetectionResult(this.quadN, this.score, this.frameWidth, this.frameHeight);

  static const DetectionResult miss = DetectionResult(null, 0, 0, 0);
}

/// Long-lived background worker turning camera luma planes into document quads.
///
/// One isolate for the whole scanning session. `compute` is `Isolate.run` — a
/// fresh spawn per call — which would re-`dlopen` libdartcv and re-allocate the
/// OpenCV scratch on every single frame.
///
/// Back-pressure is a single in-flight flag: while a frame is being analysed,
/// every new frame is dropped. A queue would be unbounded, and a frame
/// processed seconds late is worthless for a live preview.
class LiveDocumentDetector {
  /// Long side the worker detects at. Small on purpose: document edges are
  /// low-frequency, and this is the difference between 1 ms and 20 ms a frame.
  static const int kDetectLongSide = 480;

  /// Long side the UI decimates to before shipping bytes to the worker. Two
  /// stages so the UI-thread copy stays cheap while the final downscale is a
  /// proper area filter rather than nearest-neighbour aliasing.
  static const int kSubmitLongSide = 960;

  static const Duration kMinFrameInterval = Duration(milliseconds: 70);
  static const Duration _kWatchdog = Duration(seconds: 2);

  LiveDocumentDetector._(this._iso, this._tx, this._rx, this._err, this._exit);

  final Isolate _iso;
  final SendPort _tx;
  final ReceivePort _rx, _err, _exit;
  final StreamController<DetectionResult> _out =
      StreamController<DetectionResult>.broadcast();

  bool _inFlight = false;
  bool _paused = false;
  bool _stopped = false;
  bool _dead = false;
  DateTime _lastSubmit = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _watchdog;

  /// Emits one event per *analysed* frame; dropped frames emit nothing.
  /// Broadcast, so the camera screen can re-listen after a lifecycle pause.
  Stream<DetectionResult> get results => _out.stream;

  /// True once the worker isolate has died. The screen then falls back to the
  /// manual shutter instead of silently never detecting anything again.
  bool get dead => _dead;

  static Future<LiveDocumentDetector> start() async {
    final rx = ReceivePort();
    final err = ReceivePort();
    final exit = ReceivePort();
    final iso = await Isolate.spawn<List<Object>>(
      _workerMain,
      <Object>[rx.sendPort],
      onError: err.sendPort,
      onExit: exit.sendPort,
      errorsAreFatal: true,
      debugName: 'doc-scan',
    );
    final ready = Completer<SendPort>();
    LiveDocumentDetector? self;

    rx.listen((msg) {
      if (msg is SendPort) {
        if (!ready.isCompleted) ready.complete(msg);
        return;
      }
      final d = self;
      if (d == null) return;
      d._watchdog?.cancel();
      d._watchdog = null;
      // Clear the flag BEFORE pushing: a synchronous listener that submits the
      // next frame would otherwise be dropped.
      d._inFlight = false;
      if (!d._paused && !d._stopped && !d._out.isClosed) {
        d._out.add(msg as DetectionResult);
      }
    });

    final tx = await ready.future;
    final detector = LiveDocumentDetector._(iso, tx, rx, err, exit);
    self = detector;

    // Both ports do the same thing. Without this, one uncaught worker error
    // leaves _inFlight true forever and live detection is silently dead for the
    // rest of the session — the worst failure mode, because the UI keeps
    // looking alive.
    void die(Object? _) {
      if (detector._dead) return;
      detector._dead = true;
      detector._inFlight = false;
      detector._watchdog?.cancel();
      detector._watchdog = null;
      if (!detector._out.isClosed) detector._out.add(DetectionResult.miss);
    }

    err.listen(die);
    exit.listen(die);
    return detector;
  }

  /// Extracts and decimates the luma plane, then hands it to the worker.
  /// Returns false when the frame was dropped.
  ///
  /// MUST be called synchronously inside the camera callback, before any
  /// `await`: on iOS the plane bytes are backed by a `CVPixelBuffer` that can
  /// be recycled the moment the callback returns.
  bool submit(CameraImage image) {
    if (_stopped || _paused || _dead || _inFlight) return false;
    final now = DateTime.now();
    if (now.difference(_lastSubmit) < kMinFrameInterval) return false;
    if (image.planes.isEmpty) return false;

    final w = image.width, h = image.height;
    if (w < 64 || h < 64) return false;
    final p = image.planes.first;

    // Plane 0 is luma for yuv420 on both platforms (Android: 3 planes, iOS:
    // 2 bi-planar) and for nv21 on Android (1 plane, first w*h bytes).
    final int pxStride;
    switch (image.format.group) {
      case ImageFormatGroup.yuv420:
      case ImageFormatGroup.nv21:
        pxStride = p.bytesPerPixel ?? 1; // null on iOS ⇒ 1
      case ImageFormatGroup.bgra8888:
        pxStride = 4; // sample the B channel; close enough to luma for edges
      default:
        return false;
    }

    final rowStride = p.bytesPerRow; // may exceed width (Android row padding)
    final src = p.bytes;
    if (rowStride <= 0 || src.isEmpty) return false;
    final step = math.max(1, math.max(w, h) ~/ kSubmitLongSide);
    final ow = w ~/ step;
    if (ow < 64) return false;
    if ((ow - 1) * step * pxStride >= rowStride) return false; // malformed
    // Android Y planes are usually rowStride*(h-1)+width bytes, not
    // rowStride*h — clamp to what the buffer actually holds.
    final maxRow = (src.length - 1) ~/ rowStride;
    final rows = math.min(h ~/ step, (maxRow ~/ step) + 1);
    if (rows < 64) return false;

    final out = Uint8List(ow * rows);
    var o = 0;
    for (var y = 0; y < rows; y++) {
      final base = (y * step) * rowStride;
      for (var x = 0; x < ow; x++) {
        out[o++] = src[base + x * step * pxStride];
      }
    }

    _lastSubmit = now;
    _inFlight = true;
    _watchdog = Timer(_kWatchdog, () {
      // A wedged frame must not stall the loop forever.
      _watchdog = null;
      _inFlight = false;
    });
    _tx.send(<Object>[
      TransferableTypedData.fromList(<TypedData>[out]),
      ow,
      rows,
      kDetectLongSide,
    ]);
    return true;
  }

  /// Stop delivering results without tearing the isolate down, so a lifecycle
  /// pause does not cost a respawn.
  void pause() => _paused = true;

  void resume() {
    _paused = false;
    _inFlight = false;
  }

  Future<void> dispose() async {
    if (_stopped) return;
    _stopped = true;
    _watchdog?.cancel();
    _watchdog = null;
    // Ask the worker to close its own port and dispose its OpenCV scratch;
    // killing it outright would strand the native allocations.
    if (!_dead) {
      try {
        _tx.send(null);
      } catch (_) {
        // worker already gone
      }
    }
    await _out.close();
    _rx.close();
    _err.close();
    _exit.close();
    _iso.kill(priority: Isolate.beforeNextEvent);
  }
}

// ── worker isolate ───────────────────────────────────────────────────────────

void _workerMain(List<Object> boot) {
  final host = boot[0] as SendPort;
  final rx = ReceivePort();
  host.send(rx.sendPort);
  final scratch = _Scratch();
  rx.listen((msg) {
    if (msg == null) {
      scratch.dispose();
      rx.close();
      return;
    }
    try {
      host.send(analyseLumaFrame(msg as List<Object?>, scratch));
    } catch (_) {
      host.send(DetectionResult.miss); // never let a bad frame kill the isolate
    }
  });
}

/// Per-session OpenCV allocations, reused across frames.
///
/// Rebuilding these every frame costs native allocations the Dart GC gets no
/// pressure signal about, so the churn is invisible right up until it OOMs.
class ScanScratch {
  cv.Mat? _kernel;
  cv.VecU8? buf;

  cv.Mat kernel() => _kernel ??= cv.getStructuringElement(cv.MORPH_RECT, (3, 3));

  void dispose() {
    _kernel?.dispose();
    buf?.dispose();
    _kernel = null;
    buf = null;
  }
}

typedef _Scratch = ScanScratch;

/// Analyse one decimated luma frame. Exposed (rather than private) so tests can
/// drive the exact pipeline the worker runs, without spawning an isolate.
///
/// [job] is `[TransferableTypedData | Uint8List, width, height, targetLongSide]`.
DetectionResult analyseLumaFrame(List<Object?> job, ScanScratch s) {
  final raw = job[0];
  final luma = raw is TransferableTypedData
      ? raw.materialize().asUint8List()
      : raw as Uint8List;
  final fw = job[1] as int, fh = job[2] as int, target = job[3] as int;
  if (fw <= 0 || fh <= 0 || luma.length < fw * fh) return DetectionResult.miss;

  if (s.buf == null || s.buf!.length < luma.length) {
    s.buf?.dispose();
    s.buf = cv.VecU8(luma.length);
  }
  s.buf!.data.setRange(0, luma.length, luma);

  cv.Mat? full, small, blur, edges, closed;
  cv.Contours? contours;
  cv.VecVec4i? hierarchy;
  try {
    // copyData:false ⇒ this Mat aliases s.buf and does NOT own the memory, so
    // it must be disposed before s.buf is.
    full = cv.Mat.fromVec(s.buf!,
        rows: fh, cols: fw, type: cv.MatType.CV_8UC1, copyData: false);
    final sc = target / math.max(fw, fh);
    final dw = math.max(32, (fw * sc).round());
    final dh = math.max(32, (fh * sc).round());
    small = cv.resize(full, (dw, dh), interpolation: cv.INTER_AREA);
    blur = cv.gaussianBlur(small, (5, 5), 0);
    final (lo, hi) = cannyThresholds(blur);
    edges = cv.canny(blur, lo, hi);
    closed = cv.morphologyEx(edges, cv.MORPH_CLOSE, s.kernel());
    final (cs, h2) =
        cv.findContours(closed, cv.RETR_LIST, cv.CHAIN_APPROX_SIMPLE);
    contours = cs;
    hierarchy = h2;

    final best = findDocumentQuad(contours, closed, dw, dh);
    if (best == null) return DetectionResult(null, 0, dw, dh);
    return DetectionResult(
      [
        for (var i = 0; i < 8; i += 2) ...[
          best.quad[i] / dw,
          best.quad[i + 1] / dh,
        ],
      ],
      best.score,
      dw,
      dh,
    );
  } catch (_) {
    return DetectionResult.miss;
  } finally {
    contours?.dispose();
    hierarchy?.dispose(); // the one everybody forgets
    closed?.dispose();
    edges?.dispose();
    blur?.dispose();
    small?.dispose();
    full?.dispose(); // before s.buf — it aliases that memory
  }
}

// ── camera geometry ──────────────────────────────────────────────────────────

/// Net clockwise rotation from the analysis buffer to the `CameraPreview` box.
///
/// Android: the plugin wraps the texture in two `RotatedBox`es whose
/// device-orientation terms cancel out, leaving `sensorOrientation ∓
/// uiOrientation`. The ImageReader and SurfaceTexture preview delegates
/// converge on the same value, which matters because Dart cannot tell which one
/// a given device uses.
///
/// iOS: `AVCaptureConnection.videoOrientation` is applied to the stream output
/// itself, so the buffer already arrives upright.
int previewRotationCW(CameraController c) {
  if (!Platform.isAndroid) return 0;
  final s = c.description.sensorOrientation % 360;
  final u = switch (c.value.deviceOrientation) {
    DeviceOrientation.portraitUp => 0,
    DeviceOrientation.landscapeRight => 90,
    DeviceOrientation.portraitDown => 180,
    DeviceOrientation.landscapeLeft => 270,
  };
  final front = c.description.lensDirection == CameraLensDirection.front;
  return front ? (s - u + 360) % 360 : (s + u) % 360;
}

/// Live detection needs a back lens: the front-camera mirror differs between
/// Android's two preview delegates and is not determinable from Dart, so a
/// front-only device gets the manual shutter and no overlay.
bool supportsLiveDetection(CameraDescription cam) =>
    cam.lensDirection == CameraLensDirection.back;

/// Upright aspect of [c]'s analysis frames, for a frame of [fw] x [fh].
double uprightAspectFor(CameraController c, int fw, int fh) =>
    ScanGeometry.uprightAspect(fw, fh, previewRotationCW(c));
