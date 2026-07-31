import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import 'package:printing/printing.dart';

import '../utils/file_picker_helper.dart';

/// In-app file viewer for PDFs and images
/// Features: View, Download (save as), Print, Zoom, Rotate (images)
/// Supports both file paths and in-memory bytes (for encrypted docs)
class FileViewerDialog extends StatefulWidget {
  final String? filePath;
  final Uint8List? fileBytes;
  final String fileName;

  const FileViewerDialog({
    super.key,
    this.filePath,
    this.fileBytes,
    required this.fileName,
  });

  /// Show file viewer from file path
  static Future<bool> show(BuildContext context, String filePath, String fileName) async {
    final ext = fileName.toLowerCase().split('.').last;

    if (ext == 'pdf' || ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'tiff'].contains(ext)) {
      await showDialog(
        context: context,
        builder: (context) => FileViewerDialog(filePath: filePath, fileName: fileName),
      );
      return true;
    }

    return false;
  }

  /// Show file viewer from bytes in memory (for encrypted/decrypted docs)
  static Future<bool> showFromBytes(BuildContext context, Uint8List bytes, String fileName) async {
    final ext = fileName.toLowerCase().split('.').last;

    if (ext == 'pdf' || ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'tiff'].contains(ext)) {
      await showDialog(
        context: context,
        builder: (context) => FileViewerDialog(fileBytes: bytes, fileName: fileName),
      );
      return true;
    }

    return false;
  }

  @override
  State<FileViewerDialog> createState() => _FileViewerDialogState();
}

class _FileViewerDialogState extends State<FileViewerDialog> {
  bool get _isPdf => widget.fileName.toLowerCase().endsWith('.pdf');
  bool get _isImage {
    final ext = widget.fileName.toLowerCase().split('.').last;
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'tiff'].contains(ext);
  }

  // Image rotation and zoom
  int _rotation = 0; // 0, 90, 180, 270
  final TransformationController _transformController = TransformationController();

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  void _rotateLeft() {
    setState(() => _rotation = (_rotation - 90) % 360);
  }

  void _rotateRight() {
    setState(() => _rotation = (_rotation + 90) % 360);
  }

  void _zoomIn() {
    final currentScale = _transformController.value.getMaxScaleOnAxis();
    final newScale = (currentScale * 1.3).clamp(0.5, 8.0);
    _transformController.value = Matrix4.identity()..scaleByDouble(newScale, newScale, 1.0, 1);
  }

  void _zoomOut() {
    final currentScale = _transformController.value.getMaxScaleOnAxis();
    final newScale = (currentScale / 1.3).clamp(0.5, 8.0);
    _transformController.value = Matrix4.identity()..scaleByDouble(newScale, newScale, 1.0, 1);
  }

  void _resetZoom() {
    _transformController.value = Matrix4.identity();
    setState(() => _rotation = 0);
  }

  /// Die angezeigte Datei als Bytes.
  ///
  /// Kam sie schon aus dem RAM (entschlüsselte Dokumente), bleibt sie dort.
  /// Nur beim Pfad-Fall wird gelesen — und auch dann liegt sie danach nur im
  /// Speicher, es entsteht keine zweite Kopie auf der Platte.
  Future<Uint8List> _bytes() async {
    if (widget.fileBytes != null) return widget.fileBytes!;
    if (widget.filePath != null) return File(widget.filePath!).readAsBytes();
    throw StateError('Keine Datei vorhanden');
  }

  /// Datei speichern — überall dort, wo der Nutzer sie danach wiederfindet.
  ///
  /// Das Wohin unterscheidet sich je Plattform stark genug, dass es nicht
  /// hierher gehört: [FilePickerHelper.saveBytes] kennt die Fälle (Android/iOS
  /// Systemauswahl, macOS `~/Downloads`, Linux/Windows Speichern-Dialog).
  /// Vorher schrieb dieser Knopf auf allen Plattformen in den Downloads-Ordner
  /// von `path_provider` — auf Android ist das ein app-privates Verzeichnis,
  /// das in der Dateien-App nicht auftaucht. Die Meldung sagte „Gespeichert",
  /// die Datei war für den Nutzer trotzdem weg.
  Future<void> _saveFile(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = await FilePickerHelper.saveBytes(
        bytes: await _bytes(),
        fileName: widget.fileName,
        dialogTitle: 'Datei speichern',
      );
      if (saved == null) return; // abgebrochen
      messenger.showSnackBar(SnackBar(
        content: Text('Gespeichert: ${saved.split(Platform.pathSeparator).last}'),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Fehler beim Speichern: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

  /// Drucken über das Druck-Blatt des Systems.
  ///
  /// Vorher lief das über `Process.run` — `open -a Preview` auf macOS,
  /// `rundll32` auf Windows, und auf Android und Linux gar nichts: der Knopf
  /// tat dort schlicht nichts, ohne Fehlermeldung. `Printing.layoutPdf` gibt
  /// es auf allen fünf Plattformen (Linux über CUPS, im Flatpak über
  /// `--socket=cups`) und zeigt die echte Druckerauswahl.
  ///
  /// Nebenbei erledigt: der alte Pfad schrieb entschlüsselte Dokumente zum
  /// Drucken nach `/tmp` und ließ sie dort liegen. Hier bleibt alles im RAM.
  Future<void> _printFile(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await _bytes();
      if (_isPdf) {
        await Printing.layoutPdf(
          onLayout: (_) async => bytes,
          name: widget.fileName,
        );
        return;
      }
      // Bilder kann das System nicht direkt drucken — ein Blatt drumherum.
      final doc = pw.Document();
      final img = pw.MemoryImage(bytes);
      doc.addPage(pw.Page(build: (_) => pw.Center(child: pw.Image(img))));
      await Printing.layoutPdf(
        onLayout: (_) async => doc.save(),
        name: widget.fileName,
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Fehler beim Drucken: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 800,
        height: 650,
        child: Column(
          children: [
            // Header with actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Icon(
                    _isPdf ? Icons.picture_as_pdf : Icons.image,
                    color: _isPdf ? Colors.red : Colors.blue,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.fileName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Image controls (zoom + rotate)
                  if (_isImage) ...[
                    IconButton(
                      icon: const Icon(Icons.zoom_in, size: 20),
                      tooltip: 'Vergrößern',
                      onPressed: _zoomIn,
                    ),
                    IconButton(
                      icon: const Icon(Icons.zoom_out, size: 20),
                      tooltip: 'Verkleinern',
                      onPressed: _zoomOut,
                    ),
                    IconButton(
                      icon: const Icon(Icons.rotate_left, size: 20),
                      tooltip: 'Links drehen',
                      onPressed: _rotateLeft,
                    ),
                    IconButton(
                      icon: const Icon(Icons.rotate_right, size: 20),
                      tooltip: 'Rechts drehen',
                      onPressed: _rotateRight,
                    ),
                    IconButton(
                      icon: const Icon(Icons.restart_alt, size: 20),
                      tooltip: 'Zurücksetzen',
                      onPressed: _resetZoom,
                    ),
                    Container(width: 1, height: 24, color: Colors.grey.shade300),
                    const SizedBox(width: 4),
                  ],
                  // Download button
                  IconButton(
                    icon: const Icon(Icons.download),
                    tooltip: 'Herunterladen',
                    onPressed: () => _saveFile(context),
                  ),
                  // Print button
                  IconButton(
                    icon: const Icon(Icons.print),
                    tooltip: 'Drucken',
                    onPressed: () => _printFile(context),
                  ),
                  const SizedBox(width: 4),
                  // Close button
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: _isPdf ? _buildPdfViewer() : _isImage ? _buildImageViewer() : const SizedBox(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPdfViewer() {
    if (widget.fileBytes != null) {
      return PdfViewer.data(widget.fileBytes!, sourceName: widget.fileName);
    }
    return PdfViewer.file(widget.filePath!);
  }

  Widget _buildImageViewer() {
    final imageWidget = widget.fileBytes != null
        ? Image.memory(widget.fileBytes!, fit: BoxFit.contain)
        : Image.file(File(widget.filePath!), fit: BoxFit.contain);

    return Container(
      color: Colors.grey.shade900,
      child: InteractiveViewer(
        transformationController: _transformController,
        constrained: false,
        boundaryMargin: const EdgeInsets.all(double.infinity),
        minScale: 0.3,
        maxScale: 8.0,
        child: Center(
          child: Transform.rotate(
            angle: _rotation * math.pi / 180,
            child: imageWidget,
          ),
        ),
      ),
    );
  }
}
