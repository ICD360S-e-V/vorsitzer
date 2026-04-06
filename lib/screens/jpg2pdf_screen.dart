import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;

class Jpg2PdfScreen extends StatefulWidget {
  final VoidCallback onBack;

  const Jpg2PdfScreen({super.key, required this.onBack});

  @override
  State<Jpg2PdfScreen> createState() => _Jpg2PdfScreenState();
}

class _Jpg2PdfScreenState extends State<Jpg2PdfScreen> {
  final List<_ImageItem> _images = [];
  bool _isConverting = false;
  String _pageOrientation = 'auto'; // auto, portrait, landscape
  double _margin = 10; // mm

  Future<void> _pickImages() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'bmp', 'webp', 'tiff', 'tif'],
      allowMultiple: true,
      dialogTitle: 'Bilder auswählen',
    );

    if (result == null || result.files.isEmpty) return;

    final newItems = <_ImageItem>[];
    for (final f in result.files) {
      if (f.path == null) continue;
      final bytes = await File(f.path!).readAsBytes();
      newItems.add(_ImageItem(
        name: f.name,
        path: f.path!,
        bytes: bytes,
        size: f.size,
      ));
    }

    if (newItems.isNotEmpty) {
      setState(() => _images.addAll(newItems));
    }
  }

  void _removeImage(int index) {
    setState(() => _images.removeAt(index));
  }

  void _clearAll() {
    setState(() => _images.clear());
  }

  Future<void> _convertToPdf() async {
    if (_images.isEmpty) return;

    setState(() => _isConverting = true);

    try {
      final pdfDoc = pw.Document();

      for (final item in _images) {
        final decoded = img.decodeImage(item.bytes);
        if (decoded == null) continue;

        final imgWidth = decoded.width.toDouble();
        final imgHeight = decoded.height.toDouble();

        // Determine page format
        PdfPageFormat pageFormat;
        if (_pageOrientation == 'landscape') {
          pageFormat = PdfPageFormat.a4.landscape;
        } else if (_pageOrientation == 'portrait') {
          pageFormat = PdfPageFormat.a4.portrait;
        } else {
          // Auto: match image orientation
          if (imgWidth > imgHeight) {
            pageFormat = PdfPageFormat.a4.landscape;
          } else {
            pageFormat = PdfPageFormat.a4.portrait;
          }
        }

        final marginPt = _margin * PdfPageFormat.mm;
        final availW = pageFormat.width - 2 * marginPt;
        final availH = pageFormat.height - 2 * marginPt;

        // Scale to fit
        final scaleX = availW / imgWidth;
        final scaleY = availH / imgHeight;
        final scale = scaleX < scaleY ? scaleX : scaleY;
        final finalW = imgWidth * scale;
        final finalH = imgHeight * scale;

        // Re-encode as PNG for pdf package
        final pngBytes = Uint8List.fromList(img.encodePng(decoded));

        pdfDoc.addPage(
          pw.Page(
            pageFormat: pageFormat,
            margin: pw.EdgeInsets.all(marginPt),
            build: (pw.Context ctx) => pw.Center(
              child: pw.Image(
                pw.MemoryImage(pngBytes),
                width: finalW,
                height: finalH,
              ),
            ),
          ),
        );
      }

      final pdfBytes = await pdfDoc.save();
      final downloadsDir = await getDownloadsDirectory();

      if (downloadsDir == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Downloads-Ordner nicht gefunden.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final timestamp = DateTime.now()
          .toString()
          .substring(0, 16)
          .replaceAll(':', '-')
          .replaceAll(' ', '_');
      final outFile = File('${downloadsDir.path}/Bilder_zu_PDF_$timestamp.pdf');
      await outFile.writeAsBytes(pdfBytes);

      if (mounted) {
        final sizeStr = pdfBytes.length < 1024 * 1024
            ? '${(pdfBytes.length / 1024).toStringAsFixed(1)} KB'
            : '${(pdfBytes.length / (1024 * 1024)).toStringAsFixed(1)} MB';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_images.length} Bilder als PDF gespeichert ($sizeStr) — Downloads-Ordner',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isConverting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.grey.shade200,
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Zurück',
              ),
              const SizedBox(width: 8),
              Icon(Icons.image, color: Colors.orange.shade700, size: 24),
              const SizedBox(width: 8),
              const Text(
                'Bilder zu PDF',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              // Settings
              _buildOrientationChip(),
              const SizedBox(width: 8),
              _buildMarginChip(),
              const SizedBox(width: 16),
              // Actions
              OutlinedButton.icon(
                onPressed: _images.isEmpty ? null : _clearAll,
                icon: const Icon(Icons.delete_sweep, size: 18),
                label: const Text('Alle entfernen'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _pickImages,
                icon: const Icon(Icons.add_photo_alternate, size: 18),
                label: const Text('Bilder hinzufügen'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed:
                    _images.isEmpty || _isConverting ? null : _convertToPdf,
                icon: Icon(
                  _isConverting ? Icons.hourglass_empty : Icons.picture_as_pdf,
                  size: 18,
                ),
                label: Text(_isConverting
                    ? 'Konvertiert...'
                    : 'Als PDF speichern (${_images.length})'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
        // Content
        Expanded(
          child: _images.isEmpty ? _buildEmptyState() : _buildImageGrid(),
        ),
      ],
    );
  }

  Widget _buildOrientationChip() {
    final labels = {
      'auto': 'Auto',
      'portrait': 'Hochformat',
      'landscape': 'Querformat',
    };
    final icons = {
      'auto': Icons.auto_fix_high,
      'portrait': Icons.crop_portrait,
      'landscape': Icons.crop_landscape,
    };
    return PopupMenuButton<String>(
      onSelected: (v) => setState(() => _pageOrientation = v),
      tooltip: 'Seitenausrichtung',
      itemBuilder: (_) => labels.entries
          .map((e) => PopupMenuItem(
                value: e.key,
                child: Row(
                  children: [
                    Icon(icons[e.key], size: 18),
                    const SizedBox(width: 8),
                    Text(e.value),
                    if (e.key == _pageOrientation) ...[
                      const Spacer(),
                      const Icon(Icons.check, size: 18, color: Colors.green),
                    ],
                  ],
                ),
              ))
          .toList(),
      child: Chip(
        avatar: Icon(icons[_pageOrientation], size: 16),
        label: Text(labels[_pageOrientation]!, style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  Widget _buildMarginChip() {
    return PopupMenuButton<double>(
      onSelected: (v) => setState(() => _margin = v),
      tooltip: 'Seitenrand',
      itemBuilder: (_) => [0.0, 5.0, 10.0, 15.0, 20.0]
          .map((v) => PopupMenuItem(
                value: v,
                child: Row(
                  children: [
                    Text('${v.toInt()} mm'),
                    if (v == _margin) ...[
                      const Spacer(),
                      const Icon(Icons.check, size: 18, color: Colors.green),
                    ],
                  ],
                ),
              ))
          .toList(),
      child: Chip(
        avatar: const Icon(Icons.border_all, size: 16),
        label: Text('${_margin.toInt()} mm', style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_photo_alternate,
              size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'Bilder auswählen um sie in PDF zu konvertieren',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 8),
          Text(
            'JPG, PNG, BMP, WebP, TIFF',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _pickImages,
            icon: const Icon(Icons.add_photo_alternate),
            label: const Text('Bilder auswählen'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageGrid() {
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _images.length,
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) newIndex--;
          final item = _images.removeAt(oldIndex);
          _images.insert(newIndex, item);
        });
      },
      itemBuilder: (context, index) {
        final item = _images[index];
        final sizeStr = item.size < 1024 * 1024
            ? '${(item.size / 1024).toStringAsFixed(1)} KB'
            : '${(item.size / (1024 * 1024)).toStringAsFixed(1)} MB';

        return Card(
          key: ValueKey('${item.path}_$index'),
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: SizedBox(
              width: 60,
              height: 60,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.memory(
                  item.bytes,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.broken_image),
                  ),
                ),
              ),
            ),
            title: Text(
              item.name,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              sizeStr,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: Colors.orange.shade100,
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _removeImage(index),
                  icon: const Icon(Icons.close, size: 18),
                  color: Colors.red,
                  tooltip: 'Entfernen',
                ),
                const SizedBox(width: 4),
                Icon(Icons.drag_handle, color: Colors.grey.shade400),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ImageItem {
  final String name;
  final String path;
  final Uint8List bytes;
  final int size;

  _ImageItem({
    required this.name,
    required this.path,
    required this.bytes,
    required this.size,
  });
}
