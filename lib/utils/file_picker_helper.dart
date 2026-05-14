import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart' as fs;

/// Drop-in replacement for [FilePicker.platform] that works on ALL platforms
/// including unsigned / ad-hoc signed macOS builds.
///
/// **Problem:** `file_picker` has a built-in entitlement check on macOS that
/// refuses to open NSOpenPanel when `com.apple.security.files.user-selected.*`
/// is not found — even though NSOpenPanel works fine without it on non-sandboxed
/// apps. See: https://github.com/miguelpruivo/flutter_file_picker/issues/1845
///
/// **Solution:** On macOS we delegate to `file_selector` (Google's official
/// Flutter file selection plugin) which has NO entitlement check and just calls
/// NSOpenPanel directly. On all other platforms, the standard `file_picker` is
/// used unchanged.
///
/// Returns the same `FilePickerResult?` type so callers don't need changes.
class FilePickerHelper {
  FilePickerHelper._();

  /// Drop-in for `FilePicker.platform.pickFiles(...)`.
  static Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? fileName,
    bool allowMultiple = false,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool withData = false,
    bool withReadStream = false,
  }) async {
    if (Platform.isMacOS) {
      return _pickViaMacOSFileSelector(
        allowMultiple: allowMultiple,
        withData: withData,
        dialogTitle: dialogTitle,
      );
    }
    return FilePicker.platform.pickFiles(
      dialogTitle: dialogTitle,
      allowMultiple: allowMultiple,
      type: type,
      allowedExtensions: allowedExtensions,
      withData: withData,
      withReadStream: withReadStream,
    );
  }

  /// Drop-in for `FilePicker.platform.saveFile(...)`.
  static Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
  }) async {
    if (Platform.isMacOS) {
      return _saveViaMacOS(fileName: fileName);
    }
    return FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      type: type,
      allowedExtensions: allowedExtensions,
    );
  }

  // ──────────────────────────────────────────────────────────────
  //  macOS implementation via file_selector (no entitlement check)
  // ──────────────────────────────────────────────────────────────

  static Future<FilePickerResult?> _pickViaMacOSFileSelector({
    required bool allowMultiple,
    required bool withData,
    String? dialogTitle,
  }) async {
    try {
      // file_selector's openFile / openFiles use NSOpenPanel without
      // any entitlement verification — exactly what we need.
      final acceptAll = const fs.XTypeGroup(label: 'Alle Dateien');

      List<fs.XFile> xFiles;
      if (allowMultiple) {
        xFiles = await fs.openFiles(
          acceptedTypeGroups: [acceptAll],
          confirmButtonText: dialogTitle,
        );
      } else {
        final single = await fs.openFile(
          acceptedTypeGroups: [acceptAll],
          confirmButtonText: dialogTitle,
        );
        xFiles = single != null ? [single] : [];
      }

      if (xFiles.isEmpty) return null;

      // Convert XFile → PlatformFile so the return type is FilePickerResult
      final platformFiles = <PlatformFile>[];
      for (final xf in xFiles) {
        final path = xf.path;
        final name = xf.name;
        final file = File(path);
        final size = await file.length();
        final bytes = withData ? await file.readAsBytes() : null;
        platformFiles.add(PlatformFile(
          name: name,
          size: size,
          path: path,
          bytes: bytes,
        ));
      }

      return FilePickerResult(platformFiles);
    } catch (_) {
      // Last resort: try the original file_picker anyway
      try {
        return await FilePicker.platform.pickFiles(
          allowMultiple: allowMultiple,
          withData: withData,
        );
      } catch (_) {
        return null;
      }
    }
  }

  /// macOS saveFile: write directly to ~/Downloads (no NSSavePanel).
  static Future<String?> _saveViaMacOS({String? fileName}) async {
    try {
      final home = Platform.environment['HOME'] ?? '/tmp';
      final dir = Directory('$home/Downloads');
      if (!await dir.exists()) await dir.create(recursive: true);
      final safeName = (fileName ?? 'download')
          .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
      var path = '${dir.path}/$safeName';
      if (await File(path).exists()) {
        final dot = safeName.lastIndexOf('.');
        final base = dot > 0 ? safeName.substring(0, dot) : safeName;
        final ext = dot > 0 ? safeName.substring(dot) : '';
        for (var i = 1; i < 1000; i++) {
          path = '${dir.path}/$base($i)$ext';
          if (!await File(path).exists()) break;
        }
      }
      return path;
    } catch (_) {
      return null;
    }
  }
}
