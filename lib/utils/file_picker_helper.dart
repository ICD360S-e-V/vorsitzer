import 'dart:io';
import 'package:file_picker/file_picker.dart';

/// Drop-in replacement for `FilePicker.platform.pickFiles(...)` that works on
/// ALL platforms including unsigned / ad-hoc signed macOS builds.
///
/// Usage — just replace:
///   `FilePicker.platform.pickFiles(allowMultiple: true)`
/// with:
///   `FilePickerHelper.pickFiles(allowMultiple: true)`
///
/// Returns the same `FilePickerResult?` type so no other code changes are needed.
///
/// On **macOS**, `NSOpenPanel` silently fails on unsigned builds. We bypass it
/// with `osascript -e 'choose file'` (AppleScript dialog, no entitlements needed).
/// On all other platforms, the standard `file_picker` plugin is used unchanged.
class FilePickerHelper {
  FilePickerHelper._();

  /// Drop-in replacement for `FilePicker.platform.pickFiles(...)`.
  /// Same signature, same return type (`FilePickerResult?`).
  static Future<FilePickerResult?> pickFiles({
    bool allowMultiple = false,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool withData = false,
  }) async {
    if (Platform.isMacOS) {
      return _pickViaMacOS(allowMultiple: allowMultiple, withData: withData);
    }
    // Non-macOS: delegate to standard plugin
    return FilePicker.platform.pickFiles(
      allowMultiple: allowMultiple,
      type: type,
      allowedExtensions: allowedExtensions,
      withData: withData,
    );
  }

  /// macOS: use AppleScript `choose file` dialog via osascript.
  /// Constructs a FilePickerResult from the selected paths so callers
  /// don't need any code changes.
  static Future<FilePickerResult?> _pickViaMacOS({
    bool allowMultiple = false,
    bool withData = false,
  }) async {
    try {
      final multiFlag = allowMultiple ? ' with multiple selections allowed' : '';
      final result = await Process.run('osascript', [
        '-e',
        'set theFiles to choose file with prompt "Dateien auswählen"$multiFlag',
        '-e', 'set filePaths to ""',
        '-e', 'repeat with f in theFiles',
        '-e', '  set filePaths to filePaths & POSIX path of f & linefeed',
        '-e', 'end repeat',
        '-e', 'return filePaths',
      ]);
      if (result.exitCode != 0) return null; // user cancelled
      final output = (result.stdout as String).trim();
      if (output.isEmpty) return null;

      final paths = output
          .split('\n')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty && File(p).existsSync())
          .toList();

      if (paths.isEmpty) return null;

      // Build PlatformFile objects that mirror what FilePicker would return.
      final platformFiles = <PlatformFile>[];
      for (final path in paths) {
        final file = File(path);
        final name = path.split('/').last;
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
      // If osascript fails, try standard plugin as last resort
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
}
