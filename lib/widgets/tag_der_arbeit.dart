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
    final opacity = isDark ? 0.15 : 0.22;

    _drawSkyGradient(canvas, size, isDark);
    _drawCityline(canvas, size, opacity);
    _drawWorkers(canvas, size, opacity, rng);
    _drawToolsScattered(canvas, size, opacity, rng);
    _drawBanner(canvas, size, opacity);
  }

  void _drawSkyGradient(Canvas canvas, Size size, bool isDark) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? [Colors.indigo.shade900.withValues(alpha: 0.08), Colors.transparent]
            : [Colors.amber.shade50.withValues(alpha: 0.2), Colors.lightBlue.shade50.withValues(alpha: 0.1)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * 0.5));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height * 0.5), paint);
  }

  void _drawCityline(Canvas canvas, Size size, double opacity) {
    final paint = Paint()
      ..color = Colors.blueGrey.shade400.withValues(alpha: opacity * 0.4)
      ..style = PaintingStyle.fill;

    final rng = Random(77);
    final baseY = size.height * 0.88;

    for (double x = 0; x < size.width; x += 25 + rng.nextDouble() * 15) {
      final w = 15.0 + rng.nextDouble() * 20;
      final h = 30.0 + rng.nextDouble() * 60;
      canvas.drawRect(Rect.fromLTWH(x, baseY - h, w, h + 20), paint);

      final windowPaint = Paint()
        ..color = Colors.amber.shade300.withValues(alpha: opacity * 0.3)
        ..style = PaintingStyle.fill;
      for (double wy = baseY - h + 5; wy < baseY - 5; wy += 8) {
        for (double wx = x + 3; wx < x + w - 3; wx += 6) {
          if (rng.nextDouble() > 0.4) {
            canvas.drawRect(Rect.fromLTWH(wx, wy, 3, 4), windowPaint);
          }
        }
      }
    }
  }

  void _drawWorkers(Canvas canvas, Size size, double opacity, Random rng) {
    final workers = <_WorkerDef>[
      _WorkerDef(0.08, 0.75, Colors.blue.shade700, _WorkerType.builder),
      _WorkerDef(0.22, 0.78, Colors.orange.shade700, _WorkerType.doctor),
      _WorkerDef(0.38, 0.73, Colors.brown.shade600, _WorkerType.farmer),
      _WorkerDef(0.52, 0.76, Colors.red.shade700, _WorkerType.firefighter),
      _WorkerDef(0.66, 0.74, Colors.teal.shade700, _WorkerType.teacher),
      _WorkerDef(0.80, 0.77, Colors.purple.shade600, _WorkerType.chef),
      _WorkerDef(0.15, 0.55, Colors.indigo.shade600, _WorkerType.engineer),
      _WorkerDef(0.45, 0.52, Colors.green.shade700, _WorkerType.gardener),
      _WorkerDef(0.72, 0.54, Colors.cyan.shade700, _WorkerType.mechanic),
    ];

    for (final w in workers) {
      _drawWorkerFigure(canvas, size.width * w.x, size.height * w.y, w.color, opacity, w.type, rng);
    }
  }

  void _drawWorkerFigure(Canvas canvas, double x, double y, Color color, double opacity, _WorkerType type, Random rng) {
    final scale = 0.8 + rng.nextDouble() * 0.3;
    canvas.save();
    canvas.translate(x, y);
    canvas.scale(scale);

    final skinPaint = Paint()
      ..color = Color.lerp(Colors.orange.shade200, Colors.brown.shade300, rng.nextDouble())!.withValues(alpha: opacity * 1.2)
      ..style = PaintingStyle.fill;

    // Head
    canvas.drawCircle(const Offset(0, -28), 7, skinPaint);

    // Body
    final bodyPaint = Paint()..color = color.withValues(alpha: opacity * 0.8)..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(0, -14), width: 14, height: 20), const Radius.circular(3)),
      bodyPaint,
    );

    // Legs
    final legPaint = Paint()
      ..color = Colors.grey.shade700.withValues(alpha: opacity * 0.7)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(-3, -4), const Offset(-4, 10), legPaint);
    canvas.drawLine(const Offset(3, -4), const Offset(4, 10), legPaint);

    // Arms
    final armPaint = Paint()
      ..color = color.withValues(alpha: opacity * 0.7)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    // Type-specific details
    switch (type) {
      case _WorkerType.builder:
        // Hard hat
        canvas.drawArc(Rect.fromCenter(center: const Offset(0, -33), width: 18, height: 10), pi, pi, true,
          Paint()..color = Colors.yellow.shade600.withValues(alpha: opacity * 0.9)..style = PaintingStyle.fill);
        // Arm holding hammer
        canvas.drawLine(const Offset(7, -18), const Offset(16, -26), armPaint);
        canvas.drawLine(const Offset(-7, -18), const Offset(-12, -10), armPaint);
        // Hammer
        final hammerPaint = Paint()..color = Colors.grey.shade600.withValues(alpha: opacity * 0.8)..strokeWidth = 2..strokeCap = StrokeCap.round;
        canvas.drawLine(const Offset(16, -26), const Offset(16, -36), hammerPaint);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(16, -38), width: 10, height: 5), const Radius.circular(1)),
          Paint()..color = Colors.grey.shade500.withValues(alpha: opacity * 0.9)..style = PaintingStyle.fill);
        break;

      case _WorkerType.doctor:
        // White coat
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(0, -14), width: 16, height: 22), const Radius.circular(3)),
          Paint()..color = Colors.white.withValues(alpha: opacity * 0.7)..style = PaintingStyle.fill);
        // Stethoscope
        canvas.drawArc(Rect.fromCenter(center: const Offset(0, -18), width: 8, height: 8), 0, pi, false,
          Paint()..color = Colors.grey.shade600.withValues(alpha: opacity * 0.6)..strokeWidth = 1.5..style = PaintingStyle.stroke);
        // Cross
        final crossP = Paint()..color = Colors.red.shade500.withValues(alpha: opacity * 0.8)..strokeWidth = 2..strokeCap = StrokeCap.round;
        canvas.drawLine(const Offset(0, -17), const Offset(0, -11), crossP);
        canvas.drawLine(const Offset(-3, -14), const Offset(3, -14), crossP);
        canvas.drawLine(const Offset(7, -18), const Offset(12, -14), armPaint);
        canvas.drawLine(const Offset(-7, -18), const Offset(-12, -14), armPaint);
        break;

      case _WorkerType.farmer:
        // Straw hat
        canvas.drawOval(Rect.fromCenter(center: const Offset(0, -34), width: 20, height: 6),
          Paint()..color = Colors.amber.shade300.withValues(alpha: opacity * 0.8)..style = PaintingStyle.fill);
        canvas.drawArc(Rect.fromCenter(center: const Offset(0, -34), width: 14, height: 10), pi, pi, true,
          Paint()..color = Colors.amber.shade400.withValues(alpha: opacity * 0.8)..style = PaintingStyle.fill);
        // Pitchfork
        canvas.drawLine(const Offset(7, -18), const Offset(14, -30), armPaint);
        canvas.drawLine(const Offset(-7, -18), const Offset(-10, -12), armPaint);
        final forkP = Paint()..color = Colors.brown.shade500.withValues(alpha: opacity * 0.7)..strokeWidth = 1.5..strokeCap = StrokeCap.round;
        canvas.drawLine(const Offset(14, -30), const Offset(14, -42), forkP);
        canvas.drawLine(const Offset(12, -42), const Offset(12, -38), forkP);
        canvas.drawLine(const Offset(14, -42), const Offset(14, -38), forkP);
        canvas.drawLine(const Offset(16, -42), const Offset(16, -38), forkP);
        break;

      case _WorkerType.firefighter:
        // Helmet
        canvas.drawArc(Rect.fromCenter(center: const Offset(0, -33), width: 18, height: 12), pi, pi, true,
          Paint()..color = Colors.red.shade700.withValues(alpha: opacity * 0.9)..style = PaintingStyle.fill);
        canvas.drawRect(Rect.fromLTWH(-10, -33, 20, 3),
          Paint()..color = Colors.red.shade800.withValues(alpha: opacity * 0.7)..style = PaintingStyle.fill);
        // Hose
        canvas.drawLine(const Offset(7, -18), const Offset(14, -14), armPaint);
        canvas.drawLine(const Offset(-7, -18), const Offset(-5, -10), armPaint);
        canvas.drawLine(const Offset(14, -14), const Offset(20, -12),
          Paint()..color = Colors.grey.shade500.withValues(alpha: opacity * 0.5)..strokeWidth = 3..strokeCap = StrokeCap.round);
        break;

      case _WorkerType.teacher:
        // Glasses
        canvas.drawCircle(const Offset(-3, -28), 3,
          Paint()..color = Colors.grey.shade600.withValues(alpha: opacity * 0.5)..strokeWidth = 1..style = PaintingStyle.stroke);
        canvas.drawCircle(const Offset(3, -28), 3,
          Paint()..color = Colors.grey.shade600.withValues(alpha: opacity * 0.5)..strokeWidth = 1..style = PaintingStyle.stroke);
        // Book
        canvas.drawLine(const Offset(7, -18), const Offset(12, -16), armPaint);
        canvas.drawLine(const Offset(-7, -18), const Offset(-8, -12), armPaint);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(14, -14), width: 8, height: 10), const Radius.circular(1)),
          Paint()..color = Colors.green.shade700.withValues(alpha: opacity * 0.7)..style = PaintingStyle.fill);
        break;

      case _WorkerType.chef:
        // Chef hat
        canvas.drawCircle(const Offset(0, -37), 8,
          Paint()..color = Colors.white.withValues(alpha: opacity * 0.8)..style = PaintingStyle.fill);
        canvas.drawRect(Rect.fromLTWH(-7, -34, 14, 4),
          Paint()..color = Colors.white.withValues(alpha: opacity * 0.7)..style = PaintingStyle.fill);
        // Spoon
        canvas.drawLine(const Offset(7, -18), const Offset(15, -24), armPaint);
        canvas.drawLine(const Offset(-7, -18), const Offset(-10, -12), armPaint);
        canvas.drawOval(Rect.fromCenter(center: const Offset(16, -27), width: 5, height: 3),
          Paint()..color = Colors.grey.shade400.withValues(alpha: opacity * 0.7)..style = PaintingStyle.fill);
        break;

      case _WorkerType.engineer:
        // Safety vest stripes
        final stripePaint = Paint()..color = Colors.yellow.shade500.withValues(alpha: opacity * 0.5)..strokeWidth = 2;
        canvas.drawLine(const Offset(-5, -20), const Offset(-5, -8), stripePaint);
        canvas.drawLine(const Offset(5, -20), const Offset(5, -8), stripePaint);
        // Blueprint
        canvas.drawLine(const Offset(7, -18), const Offset(12, -16), armPaint);
        canvas.drawLine(const Offset(-7, -18), const Offset(-12, -16), armPaint);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(0, -8), width: 16, height: 6), const Radius.circular(1)),
          Paint()..color = Colors.blue.shade200.withValues(alpha: opacity * 0.5)..style = PaintingStyle.fill);
        break;

      case _WorkerType.gardener:
        // Sun hat
        canvas.drawOval(Rect.fromCenter(center: const Offset(0, -34), width: 18, height: 5),
          Paint()..color = Colors.green.shade300.withValues(alpha: opacity * 0.7)..style = PaintingStyle.fill);
        // Watering can
        canvas.drawLine(const Offset(7, -18), const Offset(14, -14), armPaint);
        canvas.drawLine(const Offset(-7, -18), const Offset(-10, -14), armPaint);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(16, -12), width: 8, height: 7), const Radius.circular(2)),
          Paint()..color = Colors.grey.shade500.withValues(alpha: opacity * 0.6)..style = PaintingStyle.fill);
        canvas.drawLine(const Offset(20, -14), const Offset(23, -18),
          Paint()..color = Colors.grey.shade500.withValues(alpha: opacity * 0.5)..strokeWidth = 1.5..strokeCap = StrokeCap.round);
        break;

      case _WorkerType.mechanic:
        // Cap
        canvas.drawArc(Rect.fromCenter(center: const Offset(0, -33), width: 16, height: 10), pi, pi, true,
          Paint()..color = Colors.grey.shade700.withValues(alpha: opacity * 0.7)..style = PaintingStyle.fill);
        // Wrench
        canvas.drawLine(const Offset(7, -18), const Offset(16, -22), armPaint);
        canvas.drawLine(const Offset(-7, -18), const Offset(-10, -12), armPaint);
        final wrenchP = Paint()..color = Colors.grey.shade500.withValues(alpha: opacity * 0.7)..strokeWidth = 2..strokeCap = StrokeCap.round;
        canvas.drawLine(const Offset(16, -22), const Offset(16, -34), wrenchP);
        canvas.drawCircle(const Offset(16, -35), 3,
          Paint()..color = Colors.grey.shade500.withValues(alpha: opacity * 0.5)..strokeWidth = 1.5..style = PaintingStyle.stroke);
        break;
    }

    canvas.restore();
  }

  void _drawToolsScattered(Canvas canvas, Size size, double opacity, Random rng) {
    // Small scattered work symbols
    final tools = <(IconData, Color, double, double)>[
      (Icons.computer, Colors.blue.shade400, 0.3, 0.15),
      (Icons.local_hospital, Colors.red.shade400, 0.55, 0.2),
      (Icons.restaurant, Colors.orange.shade400, 0.12, 0.35),
      (Icons.precision_manufacturing, Colors.grey, 0.85, 0.3),
      (Icons.science, Colors.purple.shade400, 0.4, 0.38),
      (Icons.music_note, Colors.pink.shade300, 0.7, 0.4),
      (Icons.local_shipping, Colors.brown.shade400, 0.25, 0.48),
      (Icons.architecture, Colors.teal.shade400, 0.6, 0.12),
    ];

    for (final (_, color, fx, fy) in tools) {
      final x = size.width * fx;
      final y = size.height * fy;
      final r = 8.0 + rng.nextDouble() * 4;

      // Simple gear/circle representation
      canvas.drawCircle(Offset(x, y), r,
        Paint()..color = color.withValues(alpha: opacity * 0.25)..style = PaintingStyle.fill);
      canvas.drawCircle(Offset(x, y), r,
        Paint()..color = color.withValues(alpha: opacity * 0.4)..style = PaintingStyle.stroke..strokeWidth = 1.5);
      canvas.drawCircle(Offset(x, y), r * 0.4,
        Paint()..color = color.withValues(alpha: opacity * 0.5)..style = PaintingStyle.fill);
    }
  }

  void _drawBanner(Canvas canvas, Size size, double opacity) {
    // Subtle "1. Mai" ribbon at top
    final bannerY = size.height * 0.03;
    final bannerH = 22.0;
    final bannerW = 100.0;
    final bannerX = size.width * 0.5 - bannerW / 2;

    final bannerPaint = Paint()
      ..color = Colors.red.shade700.withValues(alpha: opacity * 0.4)
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(bannerX - 10, bannerY);
    path.lineTo(bannerX + bannerW + 10, bannerY);
    path.lineTo(bannerX + bannerW + 5, bannerY + bannerH);
    path.lineTo(bannerX + bannerW / 2, bannerY + bannerH - 5);
    path.lineTo(bannerX - 5, bannerY + bannerH);
    path.close();
    canvas.drawPath(path, bannerPaint);

    // "1. Mai" text
    final textPainter = TextPainter(
      text: TextSpan(
        text: '1. Mai — Tag der Arbeit',
        style: TextStyle(
          color: Colors.white.withValues(alpha: opacity * 1.5),
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width / 2 - textPainter.width / 2, bannerY + 4));
  }

  @override
  bool shouldRepaint(covariant _TagDerArbeitPainter oldDelegate) => oldDelegate.brightness != brightness;
}

enum _WorkerType { builder, doctor, farmer, firefighter, teacher, chef, engineer, gardener, mechanic }

class _WorkerDef {
  final double x, y;
  final Color color;
  final _WorkerType type;
  const _WorkerDef(this.x, this.y, this.color, this.type);
}
