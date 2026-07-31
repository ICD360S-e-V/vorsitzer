import 'dart:io';
import 'dart:typed_data';
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

  // Ein „saveFile", das nur einen Pfad liefert und das Schreiben dem Aufrufer
  // überlässt, gibt es hier absichtlich nicht mehr: auf Android/iOS wirft
  // `file_picker` in dem Fall `ArgumentError` („Bytes are required…"). Genau
  // daran sind vorher alle zehn Download-Knöpfe der App auf dem Tablet
  // gescheitert. Zum Speichern führt nur [saveBytes].

  /// Speichert [bytes] dorthin, wo der Nutzer die Datei danach wiederfindet.
  /// Gibt die Zielbeschreibung zurück (Pfad bzw. der vom System gewählte Ort)
  /// oder `null`, wenn abgebrochen wurde.
  ///
  /// Warum nicht `saveFile` + selbst schreiben, wie es der ganze Code bisher
  /// gemacht hat: auf Android/iOS gibt es keinen Pfad, den die App vorher
  /// bekommt. Dort läuft das Speichern über die Systemauswahl
  /// (`ACTION_CREATE_DOCUMENT`), die die Bytes selbst schreibt und danach nur
  /// noch eine content-URI zurückmeldet. `File(pfad).writeAsBytes(...)` auf
  /// diese Rückgabe schlägt fehl — und ohne `bytes` wirft der Aufruf schon
  /// vorher. Deshalb muss das Schreiben hier drin passieren, nicht beim
  /// Aufrufer.
  ///
  /// - Android/iOS: Systemauswahl schreibt die Datei (Downloads, Drive, …).
  /// - macOS: direkt nach `~/Downloads` (NSSavePanel scheitert an fehlenden
  ///   Entitlements, siehe [_saveViaMacOS]).
  /// - Linux/Windows: Speichern-Dialog (Linux via XDG-Portal, also auch im
  ///   Flatpak), danach schreiben wir die Bytes selbst.
  static Future<String?> saveBytes({
    required Uint8List bytes,
    required String fileName,
    String? dialogTitle,
  }) async {
    final safeName = sanitizeFileName(fileName);
    final ext = safeName.contains('.') ? safeName.split('.').last.toLowerCase() : '';
    final type = ext.isEmpty ? FileType.any : FileType.custom;
    final allowed = ext.isEmpty ? null : [ext];

    if (Platform.isAndroid || Platform.isIOS) {
      // Das Plugin schreibt hier selbst; die Rückgabe ist eine content-URI,
      // kein Dateisystempfad — nicht damit weiterrechnen.
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: safeName,
        type: type,
        allowedExtensions: allowed,
        bytes: bytes,
      );
      return saved == null ? null : safeName;
    }

    final path = Platform.isMacOS
        ? await _saveViaMacOS(fileName: safeName)
        : await FilePicker.platform.saveFile(
            dialogTitle: dialogTitle,
            fileName: safeName,
            type: type,
            allowedExtensions: allowed,
          );
    if (path == null) return null;

    // Manche Dialoge geben den Namen ohne Endung zurück, wenn der Nutzer sie
    // wegeditiert — dann hätte die Datei keinen Typ mehr.
    final target = (ext.isNotEmpty && !path.toLowerCase().endsWith('.$ext'))
        ? '$path.$ext'
        : path;
    await File(target).writeAsBytes(bytes, flush: true);
    return target;
  }

  /// Ob [saveBytes] einen echten Dateisystempfad zurückgibt. Auf Android/iOS
  /// nicht — dort kommt nur der Dateiname zurück, den man weder öffnen noch
  /// in einen `File` stecken kann.
  static bool get savesToRealPath => !(Platform.isAndroid || Platform.isIOS);

  /// Dateinamen kommen aus Serverdaten und Betreffzeilen — nichts davon darf
  /// zu einem Pfad werden.
  static String sanitizeFileName(String name) {
    var s = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
    s = s.replaceFirst(RegExp(r'^\.+'), '');
    if (s.length > 120) {
      final dot = s.lastIndexOf('.');
      final ext = dot > 0 ? s.substring(dot) : '';
      s = s.substring(0, 120 - ext.length) + ext;
    }
    return s.isEmpty ? 'download' : s;
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
