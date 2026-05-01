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
          painter: _MaifestPainter(brightness: Theme.of(context).brightness),
        ),
      ),
    );

    return Stack(
      children: paintBehind ? [decoration, child] : [child, decoration],
    );
  }
}

class _MaifestPainter extends CustomPainter {
  final Brightness brightness;
  _MaifestPainter({required this.brightness});

  @override
  void paint(Canvas canvas, Size size) {
    final isDark = brightness == Brightness.dark;
    final rng = Random(51);
    final opacity = isDark ? 0.18 : 0.25;

    _drawSkyGradient(canvas, size, isDark);
    _drawBirchBranches(canvas, size, opacity, rng);
    _drawMaibaum(canvas, size, opacity);
    _drawRibbons(canvas, size, opacity, rng);
    _drawMaigloeckchen(canvas, size, opacity, rng);
    _drawSpringFlowers(canvas, size, opacity, rng);
    _drawWreath(canvas, size, opacity);
  }

  void _drawSkyGradient(Canvas canvas, Size size, bool isDark) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? [Colors.indigo.shade900.withValues(alpha: 0.08), Colors.transparent]
            : [Colors.lightBlue.shade100.withValues(alpha: 0.2), Colors.amber.shade50.withValues(alpha: 0.08)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * 0.5));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height * 0.5), paint);
  }

  void _drawMaibaum(Canvas canvas, Size size, double opacity) {
    final poleX = size.width * 0.85;
    final poleTop = size.height * 0.05;
    final poleBottom = size.height * 0.95;

    // Pole with blue-white Bavarian spiral
    final poleW = 6.0;
    final polePaint = Paint()..strokeWidth = poleW..strokeCap = StrokeCap.round;

    final segmentH = 14.0;
    for (double y = poleTop; y < poleBottom; y += segmentH) {
      final isBlue = ((y - poleTop) / segmentH).floor() % 2 == 0;
      polePaint.color = (isBlue ? Colors.blue.shade600 : Colors.white)
          .withValues(alpha: opacity * 0.7);
      canvas.drawLine(Offset(poleX, y), Offset(poleX, min(y + segmentH, poleBottom)), polePaint);
    }

    // Green crown at top
    final crownPaint = Paint()
      ..color = Colors.green.shade700.withValues(alpha: opacity * 0.8)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(poleX, poleTop - 5), 12, crownPaint);
    canvas.drawCircle(Offset(poleX - 8, poleTop), 8, crownPaint);
    canvas.drawCircle(Offset(poleX + 8, poleTop), 8, crownPaint);
    canvas.drawCircle(Offset(poleX, poleTop + 5), 7, crownPaint);

    // Darker leaves detail
    final leafDetail = Paint()
      ..color = Colors.green.shade900.withValues(alpha: opacity * 0.4)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(poleX - 4, poleTop - 3), 5, leafDetail);
    canvas.drawCircle(Offset(poleX + 5, poleTop + 2), 4, leafDetail);
  }

  void _drawRibbons(Canvas canvas, Size size, double opacity, Random rng) {
    final poleX = size.width * 0.85;
    final startY = size.height * 0.08;

    final ribbonColors = [
      Colors.red.shade400, Colors.yellow.shade600, Colors.blue.shade400,
      Colors.green.shade500, Colors.pink.shade300, Colors.orange.shade400,
      Colors.purple.shade300, Colors.teal.shade400,
    ];

    for (int i = 0; i < 8; i++) {
      final color = ribbonColors[i];
      final endX = poleX + (i - 3.5) * 35 + rng.nextDouble() * 20 - 10;
      final endY = startY + 80 + rng.nextDouble() * (size.height * 0.5);

      final ribbonPaint = Paint()
        ..color = color.withValues(alpha: opacity * 0.5)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final path = Path();
      path.moveTo(poleX, startY);
      final cp1x = poleX + (endX - poleX) * 0.3 + sin(i * 1.5) * 20;
      final cp1y = startY + (endY - startY) * 0.4;
      final cp2x = endX - sin(i * 0.8) * 15;
      final cp2y = endY - (endY - startY) * 0.2;
      path.cubicTo(cp1x, cp1y, cp2x, cp2y, endX, endY);
      canvas.drawPath(path, ribbonPaint);
    }
  }

  void _drawMaigloeckchen(Canvas canvas, Size size, double opacity, Random rng) {
    for (int cluster = 0; cluster < 5; cluster++) {
      final baseX = 20.0 + rng.nextDouble() * (size.width * 0.65);
      final baseY = size.height * 0.5 + rng.nextDouble() * (size.height * 0.35);

      // Broad leaf
      final leafPaint = Paint()
        ..color = Colors.green.shade600.withValues(alpha: opacity * 0.7)
        ..style = PaintingStyle.fill;
      final leafPath = Path();
      leafPath.moveTo(baseX, baseY + 20);
      leafPath.quadraticBezierTo(baseX - 12, baseY, baseX - 3, baseY - 15);
      leafPath.quadraticBezierTo(baseX + 2, baseY - 5, baseX + 5, baseY + 20);
      canvas.drawPath(leafPath, leafPaint);

      // Second leaf
      final leaf2 = Path();
      leaf2.moveTo(baseX + 3, baseY + 18);
      leaf2.quadraticBezierTo(baseX + 15, baseY + 2, baseX + 8, baseY - 10);
      leaf2.quadraticBezierTo(baseX + 4, baseY, baseX + 1, baseY + 18);
      canvas.drawPath(leaf2, leafPaint);

      // Curved stem
      final stemPaint = Paint()
        ..color = Colors.green.shade700.withValues(alpha: opacity * 0.6)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final stemPath = Path();
      stemPath.moveTo(baseX, baseY + 5);
      stemPath.quadraticBezierTo(baseX + 10, baseY - 15, baseX + 5, baseY - 30);
      canvas.drawPath(stemPath, stemPaint);

      // Bell-shaped flowers hanging from stem
      final bellPaint = Paint()
        ..color = Colors.white.withValues(alpha: opacity * 0.9)
        ..style = PaintingStyle.fill;
      final bellOutline = Paint()
        ..color = Colors.grey.shade400.withValues(alpha: opacity * 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;

      for (int b = 0; b < 4; b++) {
        final t = (b + 1) / 5.0;
        final bx = baseX + 10 * t * (1 - t) * 4 * 0.25 + 5 * t;
        final by = baseY + 5 - t * 35;
        final bellSize = 3.5 - b * 0.3;

        // Small stem to bell
        canvas.drawLine(
          Offset(bx - 1, by - bellSize),
          Offset(bx + (b.isEven ? 3 : -3), by - bellSize - 3),
          stemPaint,
        );

        // Bell shape
        final bellPath = Path();
        bellPath.moveTo(bx - bellSize, by - bellSize);
        bellPath.quadraticBezierTo(bx - bellSize * 1.2, by, bx - bellSize * 0.5, by + bellSize * 0.3);
        bellPath.lineTo(bx + bellSize * 0.5, by + bellSize * 0.3);
        bellPath.quadraticBezierTo(bx + bellSize * 1.2, by, bx + bellSize, by - bellSize);
        canvas.drawPath(bellPath, bellPaint);
        canvas.drawPath(bellPath, bellOutline);
      }
    }
  }

  void _drawBirchBranches(Canvas canvas, Size size, double opacity, Random rng) {
    for (int i = 0; i < 4; i++) {
      final startX = rng.nextDouble() * size.width;
      final startY = rng.nextDouble() * size.height * 0.4;
      final length = 40.0 + rng.nextDouble() * 60;
      final angle = 0.3 + rng.nextDouble() * 0.8;

      // White birch bark branch
      final branchPaint = Paint()
        ..color = Colors.grey.shade300.withValues(alpha: opacity * 0.5)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;

      final endX = startX + cos(angle) * length;
      final endY = startY + sin(angle) * length;
      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), branchPaint);

      // Dark birch marks
      final markPaint = Paint()
        ..color = Colors.grey.shade600.withValues(alpha: opacity * 0.3)
        ..strokeWidth = 1.0;
      for (int m = 0; m < 3; m++) {
        final t = 0.2 + m * 0.25;
        final mx = startX + (endX - startX) * t;
        final my = startY + (endY - startY) * t;
        canvas.drawLine(Offset(mx - 2, my), Offset(mx + 2, my), markPaint);
      }

      // Small leaves
      final leafPaint = Paint()
        ..color = Colors.green.shade400.withValues(alpha: opacity * 0.6)
        ..style = PaintingStyle.fill;

      for (int l = 0; l < 6; l++) {
        final t = 0.15 + rng.nextDouble() * 0.75;
        final lx = startX + (endX - startX) * t;
        final ly = startY + (endY - startY) * t;
        final side = rng.nextBool() ? 1.0 : -1.0;
        final leafLen = 5.0 + rng.nextDouble() * 4;

        final leafPath = Path();
        leafPath.moveTo(lx, ly);
        leafPath.quadraticBezierTo(
          lx + side * leafLen * 0.8, ly - leafLen * 0.3,
          lx + side * leafLen, ly + leafLen * 0.2,
        );
        leafPath.quadraticBezierTo(
          lx + side * leafLen * 0.5, ly + leafLen * 0.1,
          lx, ly,
        );
        canvas.drawPath(leafPath, leafPaint);
      }
    }
  }

  void _drawSpringFlowers(Canvas canvas, Size size, double opacity, Random rng) {
    final flowerColors = [
      Colors.pink.shade300, Colors.yellow.shade400, Colors.white,
      Colors.purple.shade200, Colors.orange.shade300,
    ];

    for (int i = 0; i < 15; i++) {
      final x = 15.0 + rng.nextDouble() * (size.width * 0.7);
      final y = size.height * 0.3 + rng.nextDouble() * (size.height * 0.55);
      final color = flowerColors[i % flowerColors.length];
      final petalSize = 3.0 + rng.nextDouble() * 3;
      final stemH = 12.0 + rng.nextDouble() * 15;

      // Stem
      final stemPaint = Paint()
        ..color = Colors.green.shade600.withValues(alpha: opacity * 0.5)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(x, y), Offset(x, y + stemH), stemPaint);

      // Petals
      final petalPaint = Paint()
        ..color = color.withValues(alpha: opacity * 0.7)
        ..style = PaintingStyle.fill;

      final petalCount = 5;
      for (int p = 0; p < petalCount; p++) {
        final angle = (p * 2 * pi / petalCount) + i * 0.5;
        final px = x + cos(angle) * petalSize;
        final py = y + sin(angle) * petalSize;
        canvas.drawOval(
          Rect.fromCenter(center: Offset(px, py), width: petalSize * 0.7, height: petalSize),
          petalPaint,
        );
      }

      // Center
      canvas.drawCircle(Offset(x, y), petalSize * 0.35,
        Paint()..color = Colors.amber.shade500.withValues(alpha: opacity * 0.8)..style = PaintingStyle.fill);
    }
  }

  void _drawWreath(Canvas canvas, Size size, double opacity) {
    final cx = size.width * 0.85;
    final cy = size.height * 0.15;
    final radius = 18.0;

    // Wreath circle base
    final wreathPaint = Paint()
      ..color = Colors.green.shade600.withValues(alpha: opacity * 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0;
    canvas.drawCircle(Offset(cx, cy), radius, wreathPaint);

    // Leaf details around wreath
    final leafPaint = Paint()
      ..color = Colors.green.shade500.withValues(alpha: opacity * 0.6)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 12; i++) {
      final angle = i * 2 * pi / 12;
      final lx = cx + cos(angle) * radius;
      final ly = cy + sin(angle) * radius;
      final leafAngle = angle + pi / 2;

      canvas.save();
      canvas.translate(lx, ly);
      canvas.rotate(leafAngle);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 4, height: 8), leafPaint);
      canvas.restore();
    }

    // Small flowers on wreath
    final flowerColors = [Colors.red.shade300, Colors.yellow.shade400, Colors.white, Colors.pink.shade300];
    for (int i = 0; i < 4; i++) {
      final angle = i * pi / 2 + 0.3;
      final fx = cx + cos(angle) * radius;
      final fy = cy + sin(angle) * radius;
      canvas.drawCircle(Offset(fx, fy), 3,
        Paint()..color = flowerColors[i].withValues(alpha: opacity * 0.8)..style = PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(covariant _MaifestPainter oldDelegate) => oldDelegate.brightness != brightness;
}
