import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

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

  /// Persist the current file to ~/Downloads (or the platform equivalent).
  ///
  /// We deliberately avoid `FilePicker.platform.saveFile` here: on macOS it
  /// shells out to NSSavePanel, which on unsigned/hardened-runtime builds
  /// fails with "entitlement required" because it tries to mint a
  /// security-scoped bookmark for the user-selected URL. Writing directly to
  /// the Downloads folder works without any entitlement on a non-sandboxed
  /// app and is what the user expects from a "Download" button anyway.
  ///
  /// If a file with the same name already exists we append `(1)`, `(2)`, …
  /// before the extension so we never silently overwrite.
  Future<void> _saveFile(BuildContext context) async {
    try {
      Directory? targetDir;
      try {
        targetDir = await getDownloadsDirectory();
      } catch (_) {
        targetDir = null;
      }
      // Mobile (iOS/Android) returns null — fall back to documents dir there.
      targetDir ??= await getApplicationDocumentsDirectory();
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      final safeName = _sanitize(widget.fileName);
      final savePath = await _uniquePath(targetDir.path, safeName);

      if (widget.fileBytes != null) {
        await File(savePath).writeAsBytes(widget.fileBytes!, flush: true);
      } else if (widget.filePath != null) {
        await File(widget.filePath!).copy(savePath);
      } else {
        throw StateError('Keine Datei zum Speichern vorhanden');
      }

      if (context.mounted) {
        final savedName = savePath.split(Platform.pathSeparator).last;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gespeichert in Downloads: $savedName'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'Öffnen',
              textColor: Colors.white,
              onPressed: () {
                // Reveal the containing folder via the OS default handler.
                // Best-effort: ignore failures.
                try {
                  Process.run(
                    Platform.isMacOS
                        ? 'open'
                        : (Platform.isWindows ? 'explorer' : 'xdg-open'),
                    [targetDir!.path],
                  );
                } catch (_) {}
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler beim Speichern: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _sanitize(String name) {
    var s = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
    s = s.replaceFirst(RegExp(r'^\.+'), '');
    if (s.isEmpty) s = 'attachment';
    return s;
  }

  /// Build a path that doesn't collide with an existing file by inserting
  /// `(1)`, `(2)`, … before the extension.
  Future<String> _uniquePath(String dir, String fileName) async {
    final sep = Platform.pathSeparator;
    var candidate = '$dir$sep$fileName';
    if (!await File(candidate).exists()) return candidate;

    final dot = fileName.lastIndexOf('.');
    final base = dot > 0 ? fileName.substring(0, dot) : fileName;
    final ext = dot > 0 ? fileName.substring(dot) : '';
    for (var i = 1; i < 1000; i++) {
      candidate = '$dir$sep$base($i)$ext';
      if (!await File(candidate).exists()) return candidate;
    }
    // Give up after 1000 attempts and return the last candidate.
    return candidate;
  }

  Future<void> _printFile(BuildContext context) async {
    try {
      String printPath;
      if (widget.fileBytes != null) {
        final dir = Directory.systemTemp;
        final tmpFile = File('${dir.path}/print_${widget.fileName}');
        await tmpFile.writeAsBytes(widget.fileBytes!);
        printPath = tmpFile.path;
      } else {
        printPath = widget.filePath!;
      }

      if (Platform.isMacOS) {
        await Process.run('open', ['-a', 'Preview', printPath]);
      } else if (Platform.isWindows) {
        await Process.run('rundll32', ['mshtml.dll,PrintHTML', printPath]);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fehler beim Drucken'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
