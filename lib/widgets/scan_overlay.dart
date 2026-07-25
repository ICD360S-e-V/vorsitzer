import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../services/scan_geometry.dart';

/// Where the live scanner is in its capture cycle.
enum ScanPhase {
  /// No usable quad yet.
  searching,

  /// A good quad, but not yet steady enough to arm the countdown.
  holding,

  /// Counting down to an automatic shutter.
  counting,

  /// The shutter has fired; the overlay is frozen.
  capturing,
}

/// What the overlay should draw right now. Pushed through a [ValueNotifier] so
/// detection results repaint the `CustomPaint` directly, without a `setState`
/// at frame rate rebuilding the whole screen.
@immutable
class ScanFrame {
  /// Smoothed quad, upright-normalized, ordered TL, TR, BR, BL. Null → nothing
  /// to draw.
  final List<double>? quadN;

  final double uprightAspect;

  /// 0..1 belief in this quad; drives the colour.
  final double confidence;

  /// Fades the quad out over a short miss streak, so one dropped detection
  /// does not make the outline blink.
  final double opacity;

  const ScanFrame({
    this.quadN,
    this.uprightAspect = 1.0,
    this.confidence = 0.0,
    this.opacity = 1.0,
  });

  static const ScanFrame empty = ScanFrame();
}

/// Draws the detected document outline and the countdown badge on top of the
/// camera preview.
///
/// Sits inside `CameraPreview`'s `child`, which the plugin places in a
/// `Stack(fit: StackFit.expand)` *inside* the `AspectRatio` and *outside* the
/// `RotatedBox`. So the constraints handed to this widget are exactly the
/// preview box: no AppBar, SafeArea or letterbox offset ever has to be
/// subtracted, and the overlay is never itself rotated.
class ScanOverlay extends StatelessWidget {
  const ScanOverlay({
    super.key,
    required this.box,
    required this.frame,
    required this.countdown,
    required this.phase,
    required this.lockThreshold,
  });

  final Size box;
  final ValueListenable<ScanFrame> frame;

  /// Runs 0 → 1 across the whole countdown; the displayed integer is derived
  /// from its value so the sweep and the number can never disagree.
  final Animation<double> countdown;

  final ScanPhase phase;
  final double lockThreshold;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: _QuadPainter(frame, box, lockThreshold),
          size: box,
        ),
        if (phase == ScanPhase.counting)
          RepaintBoundary(
            child: _CountdownBadge(
              frame: frame,
              countdown: countdown,
              box: box,
            ),
          ),
      ],
    );
  }
}

class _QuadPainter extends CustomPainter {
  _QuadPainter(this.frame, this.box, this.lockThreshold) : super(repaint: frame);

  final ValueListenable<ScanFrame> frame;
  final Size box;
  final double lockThreshold;

  @override
  void paint(Canvas canvas, Size size) {
    final f = frame.value;
    final q = f.quadN;
    if (q == null || q.length != 8 || f.opacity <= 0.01) return;

    final pts = ScanGeometry.projectQuad(q, f.uprightAspect, size);
    final path = Path()..addPolygon(pts, true);
    final locked = f.confidence >= lockThreshold;
    final tint = locked ? Colors.tealAccent : Colors.white;
    final a = f.opacity.clamp(0.0, 1.0);

    // Dim everything outside the document so the eye goes straight to it.
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      path,
    );
    canvas.drawPath(
      outside,
      Paint()..color = Color(0x66000000).withValues(alpha: 0.4 * a),
    );

    if (locked) {
      canvas.drawPath(
        path,
        Paint()
          ..color = tint.withValues(alpha: 0.15 * a)
          ..style = PaintingStyle.fill,
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = tint.withValues(alpha: (locked ? 1.0 : 0.55) * a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = locked ? 2.0 : 1.5,
    );

    // Corner brackets — they read as "these are the corners I picked" far more
    // clearly than the bare outline does.
    final bracket = Paint()
      ..color = tint.withValues(alpha: a)
      ..style = PaintingStyle.stroke
      ..strokeWidth = locked ? 4.0 : 3.0
      ..strokeCap = StrokeCap.round;
    const len = 24.0;
    for (var i = 0; i < 4; i++) {
      final c = pts[i];
      final prev = pts[(i + 3) % 4];
      final next = pts[(i + 1) % 4];
      for (final other in [prev, next]) {
        final d = other - c;
        final n = d.distance;
        if (n < 1) continue;
        final unit = d / n;
        canvas.drawLine(c, c + unit * math.min(len, n * 0.4), bracket);
      }
    }
  }

  @override
  bool shouldRepaint(_QuadPainter old) =>
      old.box != box || old.lockThreshold != lockThreshold;
}

/// The 5 · 4 · 3 · 2 · 1 · 0 badge, centred on the document.
class _CountdownBadge extends StatelessWidget {
  const _CountdownBadge({
    required this.frame,
    required this.countdown,
    required this.box,
  });

  final ValueListenable<ScanFrame> frame;
  final Animation<double> countdown;
  final Size box;

  static const double _size = 88.0;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ScanFrame>(
      valueListenable: frame,
      builder: (context, f, _) {
        final q = f.quadN;
        Offset centre = Offset(box.width / 2, box.height / 2);
        if (q != null && q.length == 8) {
          final pts = ScanGeometry.projectQuad(q, f.uprightAspect, box);
          centre = pts.reduce((a, b) => a + b) / 4.0;
        }
        return Positioned(
          left: centre.dx - _size / 2,
          top: centre.dy - _size / 2,
          width: _size,
          height: _size,
          child: AnimatedBuilder(
            animation: countdown,
            builder: (context, _) {
              final t = countdown.value.clamp(0.0, 1.0);
              final secondsLeft = (5 - (t * 5).floor()).clamp(0, 5);
              return CustomPaint(
                painter: _RingPainter(t),
                child: Center(
                  child: Text(
                    '$secondsLeft',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 44,
                      fontWeight: FontWeight.w300,
                      height: 1.0,
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawCircle(
      rect.center,
      size.width / 2,
      Paint()..color = const Color(0x99000000),
    );
    canvas.drawArc(
      rect.deflate(4),
      -math.pi / 2,
      2 * math.pi * (1 - t),
      false,
      Paint()
        ..color = Colors.tealAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.t != t;
}

/// Short German hint telling the user what to change. Null while counting —
/// the number is the message.
String? scanHintText({
  required ScanPhase phase,
  required bool autoEnabled,
  required bool detectorDead,
  required ScanFrame frame,
}) {
  if (detectorDead) return 'Automatik nicht verfügbar';
  if (!autoEnabled) return 'Automatik aus — Auslöser antippen';
  return switch (phase) {
    ScanPhase.counting => null,
    ScanPhase.capturing => null,
    ScanPhase.holding => 'Ruhig halten …',
    ScanPhase.searching =>
      frame.quadN == null ? 'Dokument im Rahmen platzieren' : 'Ruhig halten …',
  };
}
