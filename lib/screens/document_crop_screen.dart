import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../services/document_scanner.dart';
import '../services/scan_geometry.dart';

/// Review step after an in-app camera capture: shows the photo with the four
/// auto-detected document corners (OpenCV) as draggable handles, then de-skews
/// & crops to an upright rectangle. Pops with the final JPEG bytes to upload,
/// or null if the user cancels. All processing is on-device.
///
/// When the live scanner was locked onto the document as the shutter fired it
/// passes a [ScanHint]. If the full-resolution detection corroborates it, the
/// crop runs automatically and this screen is never painted — which is the
/// whole point when you have fifty pages to get through.
class DocumentCropScreen extends StatefulWidget {
  final Uint8List jpg;

  /// The live overlay's belief about the corners, or null for a manual shot.
  final ScanHint? hint;

  const DocumentCropScreen({super.key, required this.jpg, this.hint});

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

  /// Confidence needed to skip the editor when the still detection agrees.
  static const double _kAutoCropAgree = 0.72;

  /// Higher bar when the still detection found nothing to corroborate with.
  static const double _kAutoCropNoStill = 0.80;

  /// How close the two detections must land, as a fraction of the still's
  /// diagonal, to count as agreeing.
  static const double _kAgreeFrac = 0.04;

  Future<void> _prepare() async {
    final prep = await DocumentScanner.prepare(widget.jpg);
    final decoded = await decodeImageFromList(prep.image);
    if (!mounted) return;
    final w = decoded.width.toDouble(), h = decoded.height.toDouble();
    final diag = math.sqrt(w * w + h * h);

    // The live quad projected onto the baked still. Valid because takePicture()
    // sets the capture rotation to the display rotation, which the portrait
    // lock pins, so bakeOrientation leaves the still in the same upright frame
    // the preview was in.
    final hint = widget.hint;
    final hinted = hint == null
        ? null
        : [
            for (final p in ScanGeometry.projectQuad(
                hint.quadN, hint.uprightAspect, Size(w, h)))
              ...[p.dx, p.dy],
          ];
    final detected = (prep.corners != null && prep.corners!.length == 8)
        ? ScanGeometry.orderQuad(prep.corners!)
        : null;
    final agree = detected != null &&
        hinted != null &&
        ScanGeometry.meanCornerDistance(detected, hinted) <= _kAgreeFrac * diag;

    // Prefer the full-resolution detection when it agrees — it is sub-pixel at
    // this scale. On disagreement trust the live quad: it survived five
    // consecutive frames of convexity, area, squareness, perspective and edge
    // support checks, whereas the still had one shot at it.
    final chosen = agree
        ? detected
        : (hinted ??
            detected ??
            [w * 0.08, h * 0.08, w * 0.92, h * 0.08, //
              w * 0.92, h * 0.92, w * 0.08, h * 0.92]);

    final conf = hint?.confidence ?? 0.0;
    final auto = hint != null &&
        (agree
            ? conf >= _kAutoCropAgree
            : (detected == null && conf >= _kAutoCropNoStill));

    final corners = [
      for (var i = 0; i < 8; i += 2) Offset(chosen[i], chosen[i + 1]),
    ];

    _img = prep.image;
    _decoded = decoded;
    _corners
      ..clear()
      ..addAll(corners);

    if (auto) {
      // Never paint the editor: straight to the crop, one brief spinner.
      setState(() => _status = 'Zuschneiden …');
      await _finish(crop: true);
      return;
    }
    setState(() => _busy = false);
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
