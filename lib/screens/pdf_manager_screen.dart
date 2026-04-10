import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdfrx/pdfrx.dart' hide PdfDocument;
import 'package:pdf/pdf.dart' hide PdfDocument, PdfPage;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart' as pdfrx show PdfDocument;
import 'package:printing/printing.dart';
import 'package:signature/signature.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import '../utils/file_picker_helper.dart';

// ==================== Data Models ====================

enum AnnotationType { text, signature }

enum _EditMode { none, text, signature }

class PdfAnnotation {
  int pageNumber;
  double xPercent;
  double yPercent;
  AnnotationType type;
  String? text;
  Uint8List? imageBytes;
  double width;
  double height;
  double fontSize;
  Color color;

  PdfAnnotation({
    required this.pageNumber,
    required this.xPercent,
    required this.yPercent,
    required this.type,
    this.text,
    this.imageBytes,
    this.width = 0.25,
    this.height = 0.08,
    this.fontSize = 14,
    this.color = Colors.black,
  });
}

// ==================== PDF Manager View ====================

class PdfManagerView extends StatefulWidget {
  final VoidCallback onBack;

  const PdfManagerView({super.key, required this.onBack});

  @override
  State<PdfManagerView> createState() => _PdfManagerViewState();
}

class _PdfManagerViewState extends State<PdfManagerView> {
  Uint8List? _pdfBytes;
  String? _pdfFileName;
  PdfViewerController? _pdfController;
  int _currentPage = 1;
  int _pageCount = 0;

  final List<PdfAnnotation> _annotations = [];
  _EditMode _editMode = _EditMode.none;

  // Signature
  late SignatureController _signatureController;
  Uint8List? _capturedSignature;

  // Text input defaults
  double _textFontSize = 14;
  Color _textColor = Colors.black;

  // Export state
  bool _isExporting = false;
  bool _isSplitting = false;
  bool _isCompressing = false;
  bool _isMerging = false;

  @override
  void initState() {
    super.initState();
    _signatureController = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black,
      exportBackgroundColor: Colors.transparent,
      exportPenColor: Colors.black,
    );
  }

  @override
  void dispose() {
    _signatureController.dispose();
    super.dispose();
  }

  // ==================== PDF Loading ====================

  Future<void> _openPdf() async {
    final result = await FilePickerHelper.saveFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      dialogTitle: 'PDF öffnen',
    );
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final bytes = await file.readAsBytes();
      _pdfController = PdfViewerController();
      setState(() {
        _pdfBytes = bytes;
        _pdfFileName = result.files.single.name;
        _annotations.clear();
        _currentPage = 1;
        _editMode = _EditMode.none;
        _capturedSignature = null;
      });
    }
  }

  // ==================== Annotation Handling ====================

  void _onPageTap(int pageNumber, Offset positionInPage, Size pageSize) {
    if (_editMode == _EditMode.none) return;

    final xPercent = positionInPage.dx / pageSize.width;
    final yPercent = positionInPage.dy / pageSize.height;

    if (_editMode == _EditMode.text) {
      _showTextInputDialog(pageNumber, xPercent, yPercent);
    } else if (_editMode == _EditMode.signature && _capturedSignature != null) {
      setState(() {
        _annotations.add(PdfAnnotation(
          pageNumber: pageNumber,
          xPercent: xPercent,
          yPercent: yPercent,
          type: AnnotationType.signature,
          imageBytes: _capturedSignature,
          width: 0.25,
          height: 0.08,
        ));
        _editMode = _EditMode.none;
        _capturedSignature = null;
      });
    }
  }

  void _showTextInputDialog(int pageNumber, double xPercent, double yPercent) {
    final textController = TextEditingController();
    double fontSize = _textFontSize;
    Color color = _textColor;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Row(
            children: [
              Icon(Icons.text_fields, color: Colors.blue),
              SizedBox(width: 8),
              Text('Text hinzufügen'),
            ],
          ),
          content: SizedBox(
            width: 350,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: textController,
                  autofocus: true,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Text eingeben...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Größe: '),
                    SizedBox(
                      width: 80,
                      child: DropdownButton<double>(
                        value: fontSize,
                        isExpanded: true,
                        items: [10, 12, 14, 16, 18, 20, 24, 28, 32]
                            .map((s) => DropdownMenuItem(
                                  value: s.toDouble(),
                                  child: Text('${s}pt'),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setDialogState(() => fontSize = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Text('Farbe: '),
                    ...([
                      Colors.black,
                      Colors.red,
                      Colors.blue,
                      Colors.green
                    ]).map((c) => Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: GestureDetector(
                            onTap: () => setDialogState(() => color = c),
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: color == c
                                    ? Border.all(
                                        color: Colors.amber, width: 2.5)
                                    : Border.all(
                                        color: Colors.grey.shade300, width: 1),
                              ),
                            ),
                          ),
                        )),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: () {
                if (textController.text.trim().isNotEmpty) {
                  setState(() {
                    _annotations.add(PdfAnnotation(
                      pageNumber: pageNumber,
                      xPercent: xPercent,
                      yPercent: yPercent,
                      type: AnnotationType.text,
                      text: textController.text.trim(),
                      fontSize: fontSize,
                      color: color,
                    ));
                    _textFontSize = fontSize;
                    _textColor = color;
                  });
                }
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
              ),
              child: const Text('Hinzufügen'),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== Signature Capture ====================

  Future<void> _captureSignature() async {
    if (_signatureController.isEmpty) return;
    final bytes = await _signatureController.toPngBytes();
    if (bytes != null) {
      setState(() {
        _capturedSignature = bytes;
        _editMode = _EditMode.signature;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Unterschrift erfasst. Klicken Sie auf die PDF-Seite, um sie zu platzieren.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  // ==================== PDF Export ====================

  Future<void> _exportPdf() async {
    if (_pdfBytes == null) return;
    if (_annotations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Keine Annotationen zum Exportieren vorhanden.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      final sourceDoc = await pdfrx.PdfDocument.openData(_pdfBytes!);
      final pdfDoc = pw.Document();

      for (int i = 0; i < sourceDoc.pages.length; i++) {
        final page = sourceDoc.pages[i];
        final pageWidth = page.width;
        final pageHeight = page.height;

        // Render page at 200 DPI for quality
        final scale = 200.0 / 72.0;
        final renderWidth = (pageWidth * scale).toInt();
        final renderHeight = (pageHeight * scale).toInt();

        final rendered = await page.render(
          x: 0,
          y: 0,
          fullWidth: renderWidth.toDouble(),
          fullHeight: renderHeight.toDouble(),
        );

        if (rendered == null) continue;

        // Convert RGBA pixels to PNG
        final pngBytes =
            await _rgbaToImage(rendered.pixels, renderWidth, renderHeight);
        if (pngBytes == null) continue;

        // Get annotations for this page (1-based)
        final pageAnnotations =
            _annotations.where((a) => a.pageNumber == i + 1).toList();

        final pageFormat = PdfPageFormat(pageWidth, pageHeight);

        pdfDoc.addPage(
          pw.Page(
            pageFormat: pageFormat,
            margin: pw.EdgeInsets.zero,
            build: (pw.Context ctx) {
              return pw.Stack(
                children: [
                  // Background: original page rendered as image
                  pw.Positioned.fill(
                    child: pw.Image(pw.MemoryImage(pngBytes)),
                  ),
                  // Text annotations
                  ...pageAnnotations
                      .where((a) => a.type == AnnotationType.text)
                      .map((a) {
                    return pw.Positioned(
                      left: a.xPercent * pageWidth,
                      top: a.yPercent * pageHeight,
                      child: pw.Text(
                        a.text ?? '',
                        style: pw.TextStyle(
                          fontSize: a.fontSize,
                          color: PdfColor(
                            a.color.r,
                            a.color.g,
                            a.color.b,
                            a.color.a,
                          ),
                        ),
                      ),
                    );
                  }),
                  // Signature annotations
                  ...pageAnnotations
                      .where((a) => a.type == AnnotationType.signature)
                      .map((a) {
                    return pw.Positioned(
                      left: a.xPercent * pageWidth,
                      top: a.yPercent * pageHeight,
                      child: pw.SizedBox(
                        width: a.width * pageWidth,
                        height: a.height * pageHeight,
                        child: pw.Image(pw.MemoryImage(a.imageBytes!)),
                      ),
                    );
                  }),
                ],
              );
            },
          ),
        );
      }

      final savedBytes = await pdfDoc.save();

      // Show print/save dialog
      if (mounted) {
        final baseName = _pdfFileName?.replaceAll('.pdf', '') ?? 'document';
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.picture_as_pdf, color: Colors.red.shade700),
                const SizedBox(width: 12),
                const Expanded(child: Text('PDF exportiert')),
              ],
            ),
            content: SizedBox(
              width: 600,
              height: 500,
              child: PdfPreview(
                build: (format) async => savedBytes,
                canChangeOrientation: false,
                canChangePageFormat: false,
                pdfFileName: '${baseName}_bearbeitet.pdf',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Schließen'),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  final downloadsDir =
                      await getDownloadsDirectory();
                  if (downloadsDir == null) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content:
                              Text('Downloads-Ordner nicht gefunden.'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                    return;
                  }
                  final file = File(
                      '${downloadsDir.path}/${baseName}_bearbeitet.pdf');
                  await file.writeAsBytes(savedBytes);
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text('Gespeichert: ${file.path}'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.save, size: 18),
                label: const Text('Speichern'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export fehlgeschlagen: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  // ==================== PDF Split ====================

  Future<void> _showSplitDialog() async {
    if (_pdfBytes == null || _pageCount == 0) return;

    final selectedPages = List<bool>.filled(_pageCount, true);
    String splitMode = 'einzeln'; // 'einzeln' or 'bereich'
    final rangeController = TextEditingController(text: '1-$_pageCount');

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.content_cut, color: Colors.purple.shade700),
              const SizedBox(width: 8),
              const Text('PDF aufteilen'),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$_pageCount Seiten', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                const SizedBox(height: 12),
                // Mode selection
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'einzeln',
                      label: Text('Einzelne Seiten', style: TextStyle(fontSize: 12)),
                      icon: Icon(Icons.looks_one, size: 18),
                    ),
                    ButtonSegment(
                      value: 'bereich',
                      label: Text('Seitenbereich', style: TextStyle(fontSize: 12)),
                      icon: Icon(Icons.format_list_numbered, size: 18),
                    ),
                  ],
                  selected: {splitMode},
                  onSelectionChanged: (v) => setDialogState(() => splitMode = v.first),
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: Colors.purple.shade100,
                    selectedForegroundColor: Colors.purple.shade800,
                  ),
                ),
                const SizedBox(height: 12),
                if (splitMode == 'bereich') ...[
                  TextField(
                    controller: rangeController,
                    decoration: InputDecoration(
                      labelText: 'Seitenbereich',
                      hintText: 'z.B. 1-3, 5, 7-10',
                      helperText: 'Jeder Bereich wird als separate PDF gespeichert',
                      helperStyle: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.format_list_numbered, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (splitMode == 'einzeln') ...[
                  Row(
                    children: [
                      Text('Seiten auswählen:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setDialogState(() {
                          for (int i = 0; i < selectedPages.length; i++) {
                            selectedPages[i] = true;
                          }
                        }),
                        child: const Text('Alle', style: TextStyle(fontSize: 11)),
                      ),
                      TextButton(
                        onPressed: () => setDialogState(() {
                          for (int i = 0; i < selectedPages.length; i++) {
                            selectedPages[i] = false;
                          }
                        }),
                        child: const Text('Keine', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: List.generate(_pageCount, (i) {
                          final isSelected = selectedPages[i];
                          return GestureDetector(
                            onTap: () => setDialogState(() => selectedPages[i] = !selectedPages[i]),
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.purple.shade50 : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected ? Colors.purple.shade400 : Colors.grey.shade300,
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                                      size: 16,
                                      color: isSelected ? Colors.purple.shade700 : Colors.grey.shade400,
                                    ),
                                    Text(
                                      '${i + 1}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                        color: isSelected ? Colors.purple.shade700 : Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                if (splitMode == 'einzeln') {
                  final pages = <int>[];
                  for (int i = 0; i < selectedPages.length; i++) {
                    if (selectedPages[i]) pages.add(i + 1);
                  }
                  if (pages.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Keine Seiten ausgewählt'), backgroundColor: Colors.orange),
                    );
                    return;
                  }
                  Navigator.pop(ctx, {'mode': 'einzeln', 'pages': pages});
                } else {
                  final ranges = _parsePageRanges(rangeController.text, _pageCount);
                  if (ranges.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Ungültiger Seitenbereich'), backgroundColor: Colors.orange),
                    );
                    return;
                  }
                  Navigator.pop(ctx, {'mode': 'bereich', 'ranges': ranges});
                }
              },
              icon: const Icon(Icons.content_cut, size: 18),
              label: const Text('Aufteilen'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      await _executeSplit(result);
    }
  }

  /// Parse page ranges like "1-3, 5, 7-10" into list of lists
  List<List<int>> _parsePageRanges(String input, int maxPages) {
    final ranges = <List<int>>[];
    final parts = input.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);

    for (final part in parts) {
      if (part.contains('-')) {
        final bounds = part.split('-');
        if (bounds.length == 2) {
          final start = int.tryParse(bounds[0].trim());
          final end = int.tryParse(bounds[1].trim());
          if (start != null && end != null && start >= 1 && end <= maxPages && start <= end) {
            ranges.add(List.generate(end - start + 1, (i) => start + i));
          }
        }
      } else {
        final page = int.tryParse(part);
        if (page != null && page >= 1 && page <= maxPages) {
          ranges.add([page]);
        }
      }
    }
    return ranges;
  }

  Future<void> _executeSplit(Map<String, dynamic> config) async {
    if (_pdfBytes == null) return;

    setState(() => _isSplitting = true);

    try {
      final sourceDoc = await pdfrx.PdfDocument.openData(_pdfBytes!);
      final baseName = _pdfFileName?.replaceAll('.pdf', '') ?? 'document';
      final downloadsDir = await getDownloadsDirectory();

      if (downloadsDir == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Downloads-Ordner nicht gefunden.'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      int savedCount = 0;

      if (config['mode'] == 'einzeln') {
        // Each selected page as separate PDF
        final pages = config['pages'] as List<int>;
        for (final pageNum in pages) {
          final pdfDoc = pw.Document();
          final pngBytes = await _renderPageToPng(sourceDoc, pageNum - 1);
          if (pngBytes == null) continue;

          final page = sourceDoc.pages[pageNum - 1];
          pdfDoc.addPage(
            pw.Page(
              pageFormat: PdfPageFormat(page.width, page.height),
              margin: pw.EdgeInsets.zero,
              build: (pw.Context ctx) => pw.Positioned.fill(
                child: pw.Image(pw.MemoryImage(pngBytes)),
              ),
            ),
          );

          final savedBytes = await pdfDoc.save();
          final file = File('${downloadsDir.path}/${baseName}_Seite_$pageNum.pdf');
          await file.writeAsBytes(savedBytes);
          savedCount++;
        }
      } else {
        // Each range as separate PDF
        final ranges = config['ranges'] as List<List<int>>;
        for (int ri = 0; ri < ranges.length; ri++) {
          final range = ranges[ri];
          final pdfDoc = pw.Document();

          for (final pageNum in range) {
            final pngBytes = await _renderPageToPng(sourceDoc, pageNum - 1);
            if (pngBytes == null) continue;

            final page = sourceDoc.pages[pageNum - 1];
            pdfDoc.addPage(
              pw.Page(
                pageFormat: PdfPageFormat(page.width, page.height),
                margin: pw.EdgeInsets.zero,
                build: (pw.Context ctx) => pw.Positioned.fill(
                  child: pw.Image(pw.MemoryImage(pngBytes)),
                ),
              ),
            );
          }

          final savedBytes = await pdfDoc.save();
          final rangeStr = range.length == 1 ? 'Seite_${range.first}' : 'Seiten_${range.first}-${range.last}';
          final file = File('${downloadsDir.path}/${baseName}_$rangeStr.pdf');
          await file.writeAsBytes(savedBytes);
          savedCount++;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$savedCount PDF${savedCount > 1 ? 's' : ''} gespeichert in Downloads'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Aufteilen: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSplitting = false);
    }
  }

  Future<Uint8List?> _renderPageToPng(pdfrx.PdfDocument doc, int pageIndex) async {
    final page = doc.pages[pageIndex];
    final scale = 200.0 / 72.0;
    final renderWidth = (page.width * scale).toInt();
    final renderHeight = (page.height * scale).toInt();

    final rendered = await page.render(
      x: 0,
      y: 0,
      fullWidth: renderWidth.toDouble(),
      fullHeight: renderHeight.toDouble(),
    );
    if (rendered == null) return null;

    return _rgbaToImage(rendered.pixels, renderWidth, renderHeight);
  }

  Future<Uint8List?> _rgbaToImage(
      Uint8List rgbaPixels, int width, int height) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(rgbaPixels);
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: width,
        height: height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final codec = await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
      return byteData?.buffer.asUint8List();
    } catch (e) {
      return null;
    }
  }

  // ==================== PDF Merge ====================

  Future<void> _mergePdfs() async {
    // Pick multiple PDF files
    final result = await FilePickerHelper.saveFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: true,
      dialogTitle: 'PDFs zum Zusammenführen auswählen',
    );

    if (result == null || result.files.length < 2) {
      if (mounted && result != null && result.files.length == 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bitte mindestens 2 PDFs auswählen.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // Show reorder dialog
    final files = result.files.where((f) => f.path != null).toList();
    if (files.length < 2) return;
    if (!mounted) return;

    final orderedFiles = await showDialog<List<PlatformFile>>(
      context: context,
      builder: (ctx) {
        final items = List<PlatformFile>.from(files);
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.merge_type, color: Colors.indigo.shade700),
                const SizedBox(width: 8),
                const Text('PDFs zusammenführen'),
              ],
            ),
            content: SizedBox(
              width: 450,
              height: 400,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${items.length} PDFs ausgewählt. Reihenfolge per Drag & Drop ändern:',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ReorderableListView.builder(
                      shrinkWrap: true,
                      itemCount: items.length,
                      onReorder: (oldIndex, newIndex) {
                        setDialogState(() {
                          if (newIndex > oldIndex) newIndex--;
                          final item = items.removeAt(oldIndex);
                          items.insert(newIndex, item);
                        });
                      },
                      itemBuilder: (context, index) {
                        final f = items[index];
                        final sizeStr = f.size < 1024 * 1024
                            ? '${(f.size / 1024).toStringAsFixed(1)} KB'
                            : '${(f.size / (1024 * 1024)).toStringAsFixed(1)} MB';
                        return Card(
                          key: ValueKey(f.path),
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          child: ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: Colors.indigo.shade100,
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.indigo.shade800,
                                ),
                              ),
                            ),
                            title: Text(
                              f.name,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(sizeStr, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                            trailing: Icon(Icons.drag_handle, color: Colors.grey.shade400),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Abbrechen'),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, items),
                icon: const Icon(Icons.merge_type, size: 18),
                label: const Text('Zusammenführen'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade700,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        );
      },
    );

    if (orderedFiles == null || orderedFiles.length < 2) return;

    setState(() => _isMerging = true);

    try {
      final pdfDoc = pw.Document();

      for (final pf in orderedFiles) {
        final fileBytes = await File(pf.path!).readAsBytes();
        final sourceDoc = await pdfrx.PdfDocument.openData(fileBytes);

        for (int i = 0; i < sourceDoc.pages.length; i++) {
          final pngBytes = await _renderPageToPng(sourceDoc, i);
          if (pngBytes == null) continue;

          final page = sourceDoc.pages[i];
          pdfDoc.addPage(
            pw.Page(
              pageFormat: PdfPageFormat(page.width, page.height),
              margin: pw.EdgeInsets.zero,
              build: (pw.Context ctx) => pw.Positioned.fill(
                child: pw.Image(pw.MemoryImage(pngBytes)),
              ),
            ),
          );
        }
      }

      final mergedBytes = await pdfDoc.save();
      final downloadsDir = await getDownloadsDirectory();

      if (downloadsDir == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Downloads-Ordner nicht gefunden.'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      // Generate filename
      final timestamp = DateTime.now().toString().substring(0, 16).replaceAll(':', '-').replaceAll(' ', '_');
      final outFile = File('${downloadsDir.path}/Zusammengeführt_$timestamp.pdf');
      await outFile.writeAsBytes(mergedBytes);

      if (mounted) {
        final sizeStr = mergedBytes.length < 1024 * 1024
            ? '${(mergedBytes.length / 1024).toStringAsFixed(1)} KB'
            : '${(mergedBytes.length / (1024 * 1024)).toStringAsFixed(1)} MB';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF zusammengeführt ($sizeStr) — gespeichert in Downloads'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );

        // Ask if user wants to open the merged PDF
        final openIt = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade600),
                const SizedBox(width: 8),
                const Text('PDF erstellt'),
              ],
            ),
            content: Text(
              '${orderedFiles.length} PDFs wurden zusammengeführt.\n'
              'Möchten Sie die zusammengeführte PDF im PDF Manager öffnen?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Nein'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade700,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Öffnen'),
              ),
            ],
          ),
        );

        if (openIt == true && mounted) {
          _pdfController = PdfViewerController();
          setState(() {
            _pdfBytes = Uint8List.fromList(mergedBytes);
            _pdfFileName = outFile.uri.pathSegments.last;
            _annotations.clear();
            _currentPage = 1;
            _editMode = _EditMode.none;
            _capturedSignature = null;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Zusammenführen: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isMerging = false);
    }
  }

  // ==================== PDF Compress ====================

  Future<void> _showCompressDialog() async {
    if (_pdfBytes == null || _pageCount == 0) return;

    final originalSize = _pdfBytes!.length;
    int quality = 60;
    int dpi = 150;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.compress, color: Colors.teal.shade700),
              const SizedBox(width: 8),
              const Text('PDF komprimieren'),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Original size
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.description, size: 20, color: Colors.grey.shade600),
                      const SizedBox(width: 8),
                      Text(_pdfFileName ?? 'PDF', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      const Spacer(),
                      Text(_formatFileSize(originalSize), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Quality slider
                Text('Qualität: $quality%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Text('Klein', style: TextStyle(fontSize: 11)),
                    Expanded(
                      child: Slider(
                        value: quality.toDouble(),
                        min: 10,
                        max: 100,
                        divisions: 9,
                        label: '$quality%',
                        activeColor: Colors.teal,
                        onChanged: (v) => setDialogState(() => quality = v.round()),
                      ),
                    ),
                    const Text('Original', style: TextStyle(fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  quality <= 30 ? 'Stark komprimiert - deutlich kleiner, niedrigere Qualität'
                  : quality <= 60 ? 'Gute Balance zwischen Größe und Qualität'
                  : quality <= 80 ? 'Hohe Qualität - moderate Komprimierung'
                  : 'Nahezu original - minimale Komprimierung',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 16),

                // DPI selection
                Text('Auflösung: $dpi DPI', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 72, label: Text('72', style: TextStyle(fontSize: 12)), icon: Icon(Icons.speed, size: 16)),
                    ButtonSegment(value: 100, label: Text('100', style: TextStyle(fontSize: 12))),
                    ButtonSegment(value: 150, label: Text('150', style: TextStyle(fontSize: 12))),
                    ButtonSegment(value: 200, label: Text('200', style: TextStyle(fontSize: 12)), icon: Icon(Icons.hd, size: 16)),
                  ],
                  selected: {dpi},
                  onSelectionChanged: (v) => setDialogState(() => dpi = v.first),
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: Colors.teal.shade100,
                    selectedForegroundColor: Colors.teal.shade800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  dpi <= 72 ? 'Bildschirmauflösung - kleinste Dateigröße'
                  : dpi <= 100 ? 'Gute Lesbarkeit - deutlich kleiner'
                  : dpi <= 150 ? 'Gute Qualität für Druck und Bildschirm'
                  : 'Hohe Qualität - größere Datei',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, {'quality': quality, 'dpi': dpi}),
              icon: const Icon(Icons.compress, size: 18),
              label: const Text('Komprimieren'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      await _executeCompress(result['quality'] as int, result['dpi'] as int);
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _executeCompress(int quality, int dpi) async {
    if (_pdfBytes == null) return;

    setState(() => _isCompressing = true);

    try {
      final originalSize = _pdfBytes!.length;
      final sourceDoc = await pdfrx.PdfDocument.openData(_pdfBytes!);
      final pdfDoc = pw.Document();

      final scale = dpi / 72.0;

      for (int i = 0; i < sourceDoc.pages.length; i++) {
        final page = sourceDoc.pages[i];
        final pageWidth = page.width;
        final pageHeight = page.height;

        final renderWidth = (pageWidth * scale).toInt();
        final renderHeight = (pageHeight * scale).toInt();

        final rendered = await page.render(
          x: 0,
          y: 0,
          fullWidth: renderWidth.toDouble(),
          fullHeight: renderHeight.toDouble(),
        );
        if (rendered == null) continue;

        // Convert RGBA to JPEG with quality control using image package
        final rawImage = img.Image.fromBytes(
          width: renderWidth,
          height: renderHeight,
          bytes: rendered.pixels.buffer,
          order: img.ChannelOrder.rgba,
        );
        final jpegBytes = Uint8List.fromList(img.encodeJpg(rawImage, quality: quality));

        final pageFormat = PdfPageFormat(pageWidth, pageHeight);

        pdfDoc.addPage(
          pw.Page(
            pageFormat: pageFormat,
            margin: pw.EdgeInsets.zero,
            build: (pw.Context ctx) => pw.Positioned.fill(
              child: pw.Image(pw.MemoryImage(jpegBytes)),
            ),
          ),
        );
      }

      final compressedBytes = await pdfDoc.save();
      final compressedSize = compressedBytes.length;
      final savings = originalSize - compressedSize;
      final savingsPercent = ((savings / originalSize) * 100).round();

      if (!mounted) return;

      final baseName = _pdfFileName?.replaceAll('.pdf', '') ?? 'document';

      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green.shade700),
              const SizedBox(width: 8),
              const Expanded(child: Text('PDF komprimiert')),
            ],
          ),
          content: SizedBox(
            width: 600,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Size comparison
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.teal.shade200),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Column(
                        children: [
                          Text('Vorher', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                          const SizedBox(height: 4),
                          Text(_formatFileSize(originalSize), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
                        ],
                      ),
                      Icon(Icons.arrow_forward, color: Colors.teal.shade700, size: 28),
                      Column(
                        children: [
                          Text('Nachher', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                          const SizedBox(height: 4),
                          Text(_formatFileSize(compressedSize), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: savingsPercent > 0 ? Colors.green.shade100 : Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          savingsPercent > 0 ? '-$savingsPercent%' : '+${-savingsPercent}%',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: savingsPercent > 0 ? Colors.green.shade800 : Colors.orange.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // PDF Preview
                SizedBox(
                  height: 400,
                  child: PdfPreview(
                    build: (format) async => Uint8List.fromList(compressedBytes),
                    canChangeOrientation: false,
                    canChangePageFormat: false,
                    pdfFileName: '${baseName}_komprimiert.pdf',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Schließen'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final downloadsDir = await getDownloadsDirectory();
                if (downloadsDir == null) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Downloads-Ordner nicht gefunden.'), backgroundColor: Colors.red),
                    );
                  }
                  return;
                }
                final file = File('${downloadsDir.path}/${baseName}_komprimiert.pdf');
                await file.writeAsBytes(compressedBytes);
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Gespeichert: ${file.path}'), backgroundColor: Colors.green),
                  );
                }
              },
              icon: const Icon(Icons.save, size: 18),
              label: const Text('Speichern'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Komprimierung fehlgeschlagen: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isCompressing = false);
    }
  }

  // ==================== Build UI ====================

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: isDesktop
              ? Row(
                  children: [
                    Expanded(flex: 6, child: _buildPdfArea()),
                    Container(width: 1, color: Colors.grey.shade300),
                    SizedBox(width: 320, child: _buildToolbar()),
                  ],
                )
              : Column(
                  children: [
                    SizedBox(height: 200, child: _buildToolbar()),
                    Expanded(child: _buildPdfArea()),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: widget.onBack,
            tooltip: 'Zurück',
          ),
          Icon(Icons.picture_as_pdf, color: Colors.red.shade700, size: 24),
          const SizedBox(width: 8),
          Text(
            _pdfFileName ?? 'PDF Manager',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          if (_pdfBytes != null) ...[
            const SizedBox(width: 8),
            Text(
              'Seite $_currentPage von $_pageCount',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
          const Spacer(),
          if (_editMode != _EditMode.none)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _editMode == _EditMode.text
                    ? Colors.blue.shade50
                    : Colors.green.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _editMode == _EditMode.text
                      ? Colors.blue
                      : Colors.green,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _editMode == _EditMode.text
                        ? Icons.text_fields
                        : Icons.draw,
                    size: 16,
                    color: _editMode == _EditMode.text
                        ? Colors.blue
                        : Colors.green,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _editMode == _EditMode.text
                        ? 'Textmodus - Klicken zum Platzieren'
                        : 'Unterschrift - Klicken zum Platzieren',
                    style: TextStyle(
                      fontSize: 12,
                      color: _editMode == _EditMode.text
                          ? Colors.blue.shade700
                          : Colors.green.shade700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => setState(() {
                      _editMode = _EditMode.none;
                      _capturedSignature = null;
                    }),
                    child: const Icon(Icons.close, size: 16),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPdfArea() {
    if (_pdfBytes == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.picture_as_pdf,
                size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'Keine PDF geladen',
              style: TextStyle(fontSize: 18, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _openPdf,
              icon: const Icon(Icons.folder_open),
              label: const Text('PDF öffnen'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      );
    }

    return PdfViewer.data(
      _pdfBytes!,
      sourceName: _pdfFileName ?? 'document.pdf',
      controller: _pdfController,
      params: PdfViewerParams(
        panEnabled: true,
        pageOverlaysBuilder: _buildPageOverlays,
        onPageChanged: (pageNumber) {
          if (pageNumber != null) {
            setState(() => _currentPage = pageNumber);
          }
        },
        onViewerReady: (document, controller) {
          setState(() => _pageCount = document.pages.length);
        },
      ),
    );
  }

  List<Widget> _buildPageOverlays(
      BuildContext context, Rect pageRect, PdfPage page) {
    final widgets = <Widget>[];

    // Tap detector for placing annotations (transparent - allows scroll through)
    if (_editMode != _EditMode.none) {
      widgets.add(
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: (details) {
              _onPageTap(
                page.pageNumber,
                details.localPosition,
                pageRect.size,
              );
            },
          ),
        ),
      );
    }

    // Render annotations for this page
    final pageAnnotations =
        _annotations.where((a) => a.pageNumber == page.pageNumber).toList();

    for (int i = 0; i < pageAnnotations.length; i++) {
      final annotation = pageAnnotations[i];
      final left = annotation.xPercent * pageRect.width;
      final top = annotation.yPercent * pageRect.height;

      if (annotation.type == AnnotationType.text) {
        final scaledFontSize =
            annotation.fontSize * (pageRect.height / 842.0);
        widgets.add(
          Positioned(
            left: left,
            top: top,
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  annotation.xPercent +=
                      details.delta.dx / pageRect.width;
                  annotation.yPercent +=
                      details.delta.dy / pageRect.height;
                  annotation.xPercent =
                      annotation.xPercent.clamp(0.0, 1.0);
                  annotation.yPercent =
                      annotation.yPercent.clamp(0.0, 1.0);
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 2, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.yellow.withValues(alpha: 0.25),
                  border: Border.all(
                      color: Colors.yellow.shade700
                          .withValues(alpha: 0.5),
                      width: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  annotation.text ?? '',
                  style: TextStyle(
                    fontSize: scaledFontSize,
                    color: annotation.color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        );
      } else if (annotation.type == AnnotationType.signature &&
          annotation.imageBytes != null) {
        final w = annotation.width * pageRect.width;
        final h = annotation.height * pageRect.height;
        widgets.add(
          Positioned(
            left: left,
            top: top,
            width: w,
            height: h,
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  annotation.xPercent +=
                      details.delta.dx / pageRect.width;
                  annotation.yPercent +=
                      details.delta.dy / pageRect.height;
                  annotation.xPercent =
                      annotation.xPercent.clamp(0.0, 1.0);
                  annotation.yPercent =
                      annotation.yPercent.clamp(0.0, 1.0);
                });
              },
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                      color: Colors.green.withValues(alpha: 0.4),
                      width: 0.5),
                ),
                child: Image.memory(annotation.imageBytes!,
                    fit: BoxFit.contain),
              ),
            ),
          ),
        );
      }
    }

    return widgets;
  }

  Widget _buildToolbar() {
    return Container(
      color: Colors.grey.shade50,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Werkzeuge',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildToolButton(
              icon: Icons.folder_open,
              label: 'PDF öffnen',
              color: Colors.blue.shade700,
              onPressed: _openPdf,
            ),
            const SizedBox(height: 8),
            _buildToolButton(
              icon: Icons.text_fields,
              label: 'Text hinzufügen',
              color: Colors.blue,
              isActive: _editMode == _EditMode.text,
              onPressed: _pdfBytes == null
                  ? null
                  : () {
                      setState(() {
                        _editMode = _editMode == _EditMode.text
                            ? _EditMode.none
                            : _EditMode.text;
                        _capturedSignature = null;
                      });
                    },
            ),
            const SizedBox(height: 8),
            _buildToolButton(
              icon: Icons.draw,
              label: 'Unterschrift platzieren',
              color: Colors.green,
              isActive: _editMode == _EditMode.signature,
              onPressed: _pdfBytes == null || _capturedSignature == null
                  ? null
                  : () {
                      setState(() {
                        _editMode = _editMode == _EditMode.signature
                            ? _EditMode.none
                            : _EditMode.signature;
                      });
                    },
            ),
            const SizedBox(height: 8),
            _buildToolButton(
              icon:
                  _isExporting ? Icons.hourglass_empty : Icons.save_alt,
              label: _isExporting
                  ? 'Exportiert...'
                  : 'Exportieren / Drucken',
              color: Colors.deepPurple,
              onPressed: _pdfBytes == null ||
                      _annotations.isEmpty ||
                      _isExporting
                  ? null
                  : _exportPdf,
            ),
            const SizedBox(height: 8),
            _buildToolButton(
              icon: _isSplitting ? Icons.hourglass_empty : Icons.content_cut,
              label: _isSplitting ? 'Wird aufgeteilt...' : 'PDF aufteilen',
              color: Colors.purple,
              onPressed: _pdfBytes == null || _pageCount == 0 || _isSplitting
                  ? null
                  : _showSplitDialog,
            ),
            const SizedBox(height: 8),
            _buildToolButton(
              icon: _isCompressing ? Icons.hourglass_empty : Icons.compress,
              label: _isCompressing ? 'Komprimiert...' : 'PDF komprimieren',
              color: Colors.teal,
              onPressed: _pdfBytes == null || _pageCount == 0 || _isCompressing
                  ? null
                  : _showCompressDialog,
            ),

            const SizedBox(height: 8),
            _buildToolButton(
              icon: _isMerging ? Icons.hourglass_empty : Icons.merge_type,
              label: _isMerging ? 'Wird zusammengeführt...' : 'PDFs zusammenführen',
              color: Colors.indigo,
              onPressed: _isMerging ? null : _mergePdfs,
            ),

            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),

            // Unterschrift-Pad
            const Text(
              'Unterschrift',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              height: 150,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Signature(
                  controller: _signatureController,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      _signatureController.clear();
                      setState(() => _capturedSignature = null);
                    },
                    icon: const Icon(Icons.clear, size: 18),
                    label: const Text('Löschen'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _captureSignature,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Übernehmen'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            if (_capturedSignature != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle,
                        color: Colors.green, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Unterschrift bereit. Klicken Sie auf die PDF-Seite.',
                        style:
                            TextStyle(fontSize: 12, color: Colors.green),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),

            // Annotations list
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Annotationen',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                if (_annotations.isNotEmpty)
                  TextButton.icon(
                    onPressed: () {
                      setState(() => _annotations.clear());
                    },
                    icon: const Icon(Icons.delete_sweep, size: 18),
                    label: const Text('Alle löschen'),
                    style:
                        TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_annotations.isEmpty)
              Text(
                'Keine Annotationen vorhanden',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade500,
                  fontStyle: FontStyle.italic,
                ),
              )
            else
              ..._annotations.asMap().entries.map((entry) {
                final i = entry.key;
                final a = entry.value;
                return Card(
                  margin: const EdgeInsets.only(bottom: 4),
                  child: ListTile(
                    dense: true,
                    leading: Icon(
                      a.type == AnnotationType.text
                          ? Icons.text_fields
                          : Icons.draw,
                      size: 20,
                      color: a.type == AnnotationType.text
                          ? Colors.blue
                          : Colors.green,
                    ),
                    title: Text(
                      a.type == AnnotationType.text
                          ? (a.text ?? '')
                          : 'Unterschrift',
                      style: const TextStyle(fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      'Seite ${a.pageNumber}',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        setState(() => _annotations.removeAt(i));
                      },
                      tooltip: 'Entfernen',
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required Color color,
    bool isActive = false,
    VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 40,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 13)),
        style: ElevatedButton.styleFrom(
          backgroundColor: isActive ? color : Colors.white,
          foregroundColor: isActive ? Colors.white : color,
          side: BorderSide(
              color: isActive ? color : Colors.grey.shade300),
          elevation: isActive ? 2 : 0,
          alignment: Alignment.centerLeft,
        ),
      ),
    );
  }
}
