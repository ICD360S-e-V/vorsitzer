import 'dart:io';
import 'package:file_picker/file_picker.dart';

/// Cross-platform file picker that works on ALL platforms including
/// unsigned / ad-hoc signed macOS builds.
///
/// On macOS, `FilePicker.platform.pickFiles` uses `NSOpenPanel` which
/// silently fails on unsigned builds (entitlement required). We bypass
/// this by calling `osascript -e 'choose file'` which invokes an
/// AppleScript dialog that works without ANY entitlement.
///
/// On all other platforms, the standard `file_picker` plugin is used.
class FilePickerHelper {
  FilePickerHelper._();

  /// Pick one or more files. Returns a list of [File] objects.
  /// Returns an empty list if the user cancels or an error occurs.
  static Future<List<File>> pickFiles({bool allowMultiple = true}) async {
    if (Platform.isMacOS) {
      return _pickViaMacOS(allowMultiple: allowMultiple);
    }
    return _pickViaPlugin(allowMultiple: allowMultiple);
  }

  /// Pick a single file. Returns null if the user cancels.
  static Future<File?> pickSingleFile() async {
    final files = await pickFiles(allowMultiple: false);
    return files.isNotEmpty ? files.first : null;
  }

  /// Standard file_picker plugin (works on Windows, Linux, Android, iOS).
  static Future<List<File>> _pickViaPlugin({bool allowMultiple = true}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: allowMultiple,
        withData: false,
      );
      if (result == null) return [];
      return result.files
          .where((f) => f.path != null)
          .map((f) => File(f.path!))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// macOS fallback: use AppleScript `choose file` dialog via osascript.
  /// Works without any entitlement on non-sandboxed apps.
  static Future<List<File>> _pickViaMacOS({bool allowMultiple = true}) async {
    try {
      final multiFlag = allowMultiple ? ' with multiple selections allowed' : '';
      final result = await Process.run('osascript', [
        '-e', 'set theFiles to choose file with prompt "Dateien auswählen"$multiFlag',
        '-e', 'set filePaths to ""',
        '-e', 'repeat with f in theFiles',
        '-e', '  set filePaths to filePaths & POSIX path of f & linefeed',
        '-e', 'end repeat',
        '-e', 'return filePaths',
      ]);
      if (result.exitCode != 0) return []; // user cancelled
      final output = (result.stdout as String).trim();
      if (output.isEmpty) return [];
      return output
          .split('\n')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .map((p) => File(p))
          .where((f) => f.existsSync())
          .toList();
    } catch (_) {
      // If osascript also fails, try plugin as last resort
      return _pickViaPlugin(allowMultiple: allowMultiple);
    }
  }
}
