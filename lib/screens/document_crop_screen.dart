import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../services/document_scanner.dart';

/// Review step after an in-app camera capture: shows the photo with the four
/// auto-detected document corners (OpenCV) as draggable handles, then de-skews
/// & crops to an upright rectangle. Pops with the final JPEG bytes to upload,
/// or null if the user cancels. All processing is on-device.
class DocumentCropScreen extends StatefulWidget {
  final Uint8List jpg;
  const DocumentCropScreen({super.key, required this.jpg});

  @override
  State<DocumentCropScreen> createState() => _DocumentCropScreenState();
}

class _DocumentCropScreenState extends State<DocumentCropScreen> {
  Uint8List? _img; // orientation-normalized bytes (display + processing)
  ui.Image? _decoded; // for the intrinsic pixel size
  final List<Offset> _corners = []; // image-space px, order TL, TR, BR, BL
  bool _busy = true;
  String _status = 'Dokument wird erkannt …';

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _decoded?.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    final prep = await DocumentScanner.prepare(widget.jpg);
    final decoded = await decodeImageFromList(prep.image);
    if (!mounted) return;
    final w = decoded.width.toDouble(), h = decoded.height.toDouble();
    final c = prep.corners;
    final corners = (c != null && c.length == 8)
        ? [Offset(c[0], c[1]), Offset(c[2], c[3]), Offset(c[4], c[5]), Offset(c[6], c[7])]
        // No detection → a sensible 8% inset the user can drag to fit.
        : [
            Offset(w * 0.08, h * 0.08),
            Offset(w * 0.92, h * 0.08),
            Offset(w * 0.92, h * 0.92),
            Offset(w * 0.08, h * 0.92),
          ];
    setState(() {
      _img = prep.image;
      _decoded = decoded;
      _corners
        ..clear()
        ..addAll(corners);
      _busy = false;
    });
  }

  Future<void> _finish({required bool crop}) async {
    final bytes = _img;
    if (bytes == null) return;
    if (!crop) {
      Navigator.of(context).pop(bytes); // upload the upright photo as-is
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Zuschneiden …';
    });
    final out = await DocumentScanner.deskew(
      bytes,
      [for (final p in _corners) ...[p.dx, p.dy]],
    );
    if (!mounted) return;
    Navigator.of(context).pop(out);
  }

  @override
  Widget build(BuildContext context) {
    final ready = _img != null && _decoded != null;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Ecken anpassen'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: !ready
          ? _loading()
          : Column(
              children: [
                Expanded(child: _editor()),
                _bar(),
              ],
            ),
    );
  }

  Widget _loading() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(_status, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      );

  Widget _editor() {
    final decoded = _decoded!;
    final imgW = decoded.width.toDouble(), imgH = decoded.height.toDouble();
    return LayoutBuilder(
      builder: (ctx, cons) {
        final s = math.min(cons.maxWidth / imgW, cons.maxHeight / imgH);
        final dispW = imgW * s, dispH = imgH * s;
        final ox = (cons.maxWidth - dispW) / 2, oy = (cons.maxHeight - dispH) / 2;
        Offset toWidget(Offset p) => Offset(ox + p.dx * s, oy + p.dy * s);
        return Stack(
          children: [
            Positioned(
              left: ox,
              top: oy,
              width: dispW,
              height: dispH,
              child: Image.memory(_img!, fit: BoxFit.fill, gaplessPlayback: true),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _QuadPainter(_corners.map(toWidget).toList()),
                ),
              ),
            ),
            for (var i = 0; i < _corners.length; i++)
              Positioned(
                left: toWidget(_corners[i]).dx - 22,
                top: toWidget(_corners[i]).dy - 22,
                child: GestureDetector(
                  onPanUpdate: (d) => setState(() {
                    final np = _corners[i] + Offset(d.delta.dx / s, d.delta.dy / s);
                    _corners[i] =
                        Offset(np.dx.clamp(0.0, imgW), np.dy.clamp(0.0, imgH));
                  }),
                  child: _handle(),
                ),
              ),
            if (_busy)
              Positioned.fill(
                child: ColoredBox(color: const Color(0x99000000), child: _loading()),
              ),
          ],
        );
      },
    );
  }

  Widget _handle() => SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.tealAccent.withValues(alpha: 0.5),
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      );

  Widget _bar() => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _finish(crop: false),
                  icon: const Icon(Icons.image_outlined),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                  label: const Text('Ohne Zuschnitt'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _finish(crop: true),
                  icon: const Icon(Icons.crop),
                  label: const Text('Zuschneiden'),
                ),
              ),
            ],
          ),
        ),
      );
}

class _QuadPainter extends CustomPainter {
  final List<Offset> pts; // widget-space, order TL, TR, BR, BL
  _QuadPainter(this.pts);

  @override
  void paint(Canvas canvas, Size size) {
    if (pts.length != 4) return;
    final path = Path()..addPolygon(pts, true);
    canvas.drawPath(
        path,
        Paint()
          ..color = Colors.tealAccent.withValues(alpha: 0.15)
          ..style = PaintingStyle.fill);
    canvas.drawPath(
        path,
        Paint()
          ..color = Colors.tealAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_QuadPainter old) => _differs(old.pts, pts);

  static bool _differs(List<Offset> a, List<Offset> b) {
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return true;
    }
    return false;
  }
}
