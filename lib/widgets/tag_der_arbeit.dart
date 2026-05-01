import 'dart:math';
import 'package:flutter/material.dart';

class TagDerArbeitBackground extends StatelessWidget {
  final Widget child;
  final bool paintBehind;

  const TagDerArbeitBackground({super.key, required this.child, this.paintBehind = false});

  static bool get isTagDerArbeit {
    final now = DateTime.now();
    return now.month == 5 && now.day == 1;
  }

  @override
  Widget build(BuildContext context) {
    if (!isTagDerArbeit) return child;

    final decoration = Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _TagDerArbeitPainter(brightness: Theme.of(context).brightness),
        ),
      ),
    );

    return Stack(
      children: paintBehind ? [decoration, child] : [child, decoration],
    );
  }
}

class _TagDerArbeitPainter extends CustomPainter {
  final Brightness brightness;
  _TagDerArbeitPainter({required this.brightness});

  @override
  void paint(Canvas canvas, Size size) {
    final isDark = brightness == Brightness.dark;
    final rng = Random(51);
    final opacity = isDark ? 0.2 : 0.3;

    _drawSkyGradient(canvas, size, isDark);
    _drawGears(canvas, size, opacity, rng);
    _drawRedBanners(canvas, size, opacity, rng);
    _drawCarnations(canvas, size, opacity, rng);
    _drawHammers(canvas, size, opacity, rng);
    _drawStars(canvas, size, opacity, rng);
    _drawFists(canvas, size, opacity, rng);
  }

  void _drawSkyGradient(Canvas canvas, Size size, bool isDark) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? [Colors.red.shade900.withValues(alpha: 0.1), Colors.transparent]
            : [Colors.red.shade50.withValues(alpha: 0.3), Colors.transparent],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * 0.4));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height * 0.4), paint);
  }

  void _drawGears(Canvas canvas, Size size, double opacity, Random rng) {
    for (int i = 0; i < 6; i++) {
      final x = 40.0 + rng.nextDouble() * (size.width - 80);
      final y = 30.0 + rng.nextDouble() * (size.height * 0.7);
      final r = 12.0 + rng.nextDouble() * 18;
      final teeth = 8 + rng.nextInt(5);
      final rotation = rng.nextDouble() * pi;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);

      final gearPaint = Paint()
        ..color = Colors.grey.shade500.withValues(alpha: opacity * 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawCircle(Offset.zero, r * 0.6, gearPaint);
      canvas.drawCircle(Offset.zero, r * 0.25,
        Paint()..color = Colors.grey.shade500.withValues(alpha: opacity * 0.3)..style = PaintingStyle.fill);

      for (int t = 0; t < teeth; t++) {
        final angle = t * 2 * pi / teeth;
        final innerR = r * 0.6;
        final outerR = r;
        final halfTooth = pi / teeth * 0.6;
        final toothPath = Path();
        toothPath.moveTo(cos(angle - halfTooth) * innerR, sin(angle - halfTooth) * innerR);
        toothPath.lineTo(cos(angle - halfTooth * 0.7) * outerR, sin(angle - halfTooth * 0.7) * outerR);
        toothPath.lineTo(cos(angle + halfTooth * 0.7) * outerR, sin(angle + halfTooth * 0.7) * outerR);
        toothPath.lineTo(cos(angle + halfTooth) * innerR, sin(angle + halfTooth) * innerR);
        canvas.drawPath(toothPath, gearPaint);
      }
      canvas.restore();
    }
  }

  void _drawRedBanners(Canvas canvas, Size size, double opacity, Random rng) {
    for (int i = 0; i < 4; i++) {
      final x = 60.0 + rng.nextDouble() * (size.width - 120);
      final y = 20.0 + rng.nextDouble() * (size.height * 0.3);
      final w = 60.0 + rng.nextDouble() * 40;
      final h = 18.0 + rng.nextDouble() * 10;

      final bannerPaint = Paint()
        ..color = Colors.red.shade700.withValues(alpha: opacity * 0.6)
        ..style = PaintingStyle.fill;

      final path = Path();
      path.moveTo(x, y);
      path.lineTo(x + w, y);
      path.lineTo(x + w, y + h);
      path.lineTo(x + w * 0.5, y + h - 5);
      path.lineTo(x, y + h);
      path.close();
      canvas.drawPath(path, bannerPaint);

      final polePaint = Paint()
        ..color = Colors.brown.shade600.withValues(alpha: opacity * 0.8)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(x, y - 5), Offset(x, y + h + 15), polePaint);
    }
  }

  void _drawCarnations(Canvas canvas, Size size, double opacity, Random rng) {
    for (int i = 0; i < 12; i++) {
      final x = 20.0 + rng.nextDouble() * (size.width - 40);
      final y = size.height * 0.4 + rng.nextDouble() * (size.height * 0.45);
      final petalSize = 4.0 + rng.nextDouble() * 4;
      final stemH = 20.0 + rng.nextDouble() * 15;

      final stemPaint = Paint()
        ..color = Colors.green.shade700.withValues(alpha: opacity * 0.7)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(x, y), Offset(x, y + stemH), stemPaint);

      if (i % 2 == 0) {
        final leafPaint = Paint()..color = Colors.green.shade600.withValues(alpha: opacity * 0.6)..style = PaintingStyle.fill;
        final leafPath = Path();
        final ly = y + stemH * 0.5;
        leafPath.moveTo(x, ly);
        leafPath.quadraticBezierTo(x + 7, ly - 3, x + 10, ly);
        leafPath.quadraticBezierTo(x + 7, ly + 2, x, ly);
        canvas.drawPath(leafPath, leafPaint);
      }

      final petalPaint = Paint()
        ..color = Colors.red.shade400.withValues(alpha: opacity * 0.9)
        ..style = PaintingStyle.fill;

      for (int p = 0; p < 8; p++) {
        final angle = p * 2 * pi / 8 + rng.nextDouble() * 0.3;
        final px = x + cos(angle) * petalSize * 0.7;
        final py = y + sin(angle) * petalSize * 0.7;
        canvas.drawOval(Rect.fromCenter(center: Offset(px, py), width: petalSize * 0.7, height: petalSize * 0.9), petalPaint);
      }

      final centerP = Paint()..color = Colors.red.shade700.withValues(alpha: opacity)..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), petalSize * 0.3, centerP);
    }
  }

  void _drawHammers(Canvas canvas, Size size, double opacity, Random rng) {
    for (int i = 0; i < 3; i++) {
      final x = 80.0 + rng.nextDouble() * (size.width - 160);
      final y = size.height * 0.15 + rng.nextDouble() * (size.height * 0.5);
      final scale = 0.8 + rng.nextDouble() * 0.4;
      final rot = (rng.nextDouble() - 0.5) * 0.8;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rot);
      canvas.scale(scale);

      final handlePaint = Paint()
        ..color = Colors.brown.shade600.withValues(alpha: opacity * 0.7)
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(const Offset(0, 0), const Offset(0, 35), handlePaint);

      final headPaint = Paint()
        ..color = Colors.grey.shade600.withValues(alpha: opacity * 0.8)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(0, -4), width: 22, height: 10), const Radius.circular(2)),
        headPaint,
      );

      canvas.restore();
    }
  }

  void _drawStars(Canvas canvas, Size size, double opacity, Random rng) {
    for (int i = 0; i < 10; i++) {
      final x = 20.0 + rng.nextDouble() * (size.width - 40);
      final y = 15.0 + rng.nextDouble() * (size.height * 0.85);
      final r = 3.0 + rng.nextDouble() * 5;

      final starPaint = Paint()
        ..color = Colors.red.shade400.withValues(alpha: opacity * 0.6)
        ..style = PaintingStyle.fill;

      final path = Path();
      for (int s = 0; s < 5; s++) {
        final outerAngle = (s * 4 * pi / 5) - pi / 2;
        final innerAngle = outerAngle + 2 * pi / 10;
        if (s == 0) {
          path.moveTo(x + cos(outerAngle) * r, y + sin(outerAngle) * r);
        } else {
          path.lineTo(x + cos(outerAngle) * r, y + sin(outerAngle) * r);
        }
        path.lineTo(x + cos(innerAngle) * r * 0.4, y + sin(innerAngle) * r * 0.4);
      }
      path.close();
      canvas.drawPath(path, starPaint);
    }
  }

  void _drawFists(Canvas canvas, Size size, double opacity, Random rng) {
    for (int i = 0; i < 2; i++) {
      final x = 100.0 + rng.nextDouble() * (size.width - 200);
      final y = size.height * 0.5 + rng.nextDouble() * (size.height * 0.3);
      final scale = 0.6 + rng.nextDouble() * 0.3;

      canvas.save();
      canvas.translate(x, y);
      canvas.scale(scale);

      final fistPaint = Paint()
        ..color = Colors.red.shade800.withValues(alpha: opacity * 0.5)
        ..style = PaintingStyle.fill;

      final armPaint = Paint()
        ..color = Colors.red.shade700.withValues(alpha: opacity * 0.4)
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(const Offset(0, 20), const Offset(0, 45), armPaint);

      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(0, 5), width: 22, height: 28), const Radius.circular(5)),
        fistPaint,
      );

      final knucklePaint = Paint()
        ..color = Colors.red.shade900.withValues(alpha: opacity * 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      for (int k = 0; k < 4; k++) {
        canvas.drawLine(Offset(-8.0 + k * 5, -6), Offset(-8.0 + k * 5, -2), knucklePaint);
      }

      final thumbPath = Path();
      thumbPath.moveTo(-11, 8);
      thumbPath.quadraticBezierTo(-14, 2, -11, -2);
      canvas.drawPath(thumbPath, Paint()
        ..color = Colors.red.shade800.withValues(alpha: opacity * 0.5)
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round);

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _TagDerArbeitPainter oldDelegate) => oldDelegate.brightness != brightness;
}
