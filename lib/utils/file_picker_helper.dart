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

  /// Rät die Dateiendung aus den ersten Bytes — nur für die Formate, die diese
  /// App tatsächlich erzeugt oder vom Server bekommt.
  ///
  /// Bewusst klein gehalten: das ist kein Ersatz für eine Inhaltserkennung,
  /// sondern eine Notbremse für [saveBytes], wenn der Server zu einem Dokument
  /// keinen Dateinamen mitliefert. Wird nichts erkannt, kommt `null` zurück und
  /// der Name bleibt, wie er war.
  static String? extensionFromMagicBytes(Uint8List b) {
    bool at(int offset, List<int> sig) {
      if (b.length < offset + sig.length) return false;
      for (var i = 0; i < sig.length; i++) {
        if (b[offset + i] != sig[i]) return false;
      }
      return true;
    }

    if (at(0, [0x25, 0x50, 0x44, 0x46])) return 'pdf'; // %PDF
    if (at(0, [0x89, 0x50, 0x4E, 0x47])) return 'png';
    if (at(0, [0xFF, 0xD8, 0xFF])) return 'jpg';
    if (at(0, [0x47, 0x49, 0x46, 0x38])) return 'gif'; // GIF8
    if (at(0, [0x49, 0x49, 0x2A, 0x00]) || at(0, [0x4D, 0x4D, 0x00, 0x2A])) {
      return 'tif';
    }
    // HEIC/HEIF tragen ihre Kennung erst hinter der Box-Länge, ab Byte 4.
    if (at(4, [0x66, 0x74, 0x79, 0x70])) {
      const heic = [0x68, 0x65, 0x69, 0x63]; // heic
      const heix = [0x68, 0x65, 0x69, 0x78]; // heix
      const mif1 = [0x6D, 0x69, 0x66, 0x31]; // mif1
      if (at(8, heic) || at(8, heix) || at(8, mif1)) return 'heic';
    }
    // ZIP steht auch für docx/xlsx/odt — die unterscheiden sich erst tief im
    // Archiv, und für den Speichern-Dialog reicht die Hülle.
    if (at(0, [0x50, 0x4B, 0x03, 0x04])) return 'zip';
    if (at(0, [0x3C, 0x3F, 0x78, 0x6D, 0x6C])) return 'xml'; // <?xml
    return null;
  }

  /// Drop-in for `FilePicker.pickFiles(...)`.
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
    return FilePicker.pickFiles(
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
    var safeName = sanitizeFileName(fileName);
    // Namen ohne Endung nicht so weiterreichen: unter Android hängt das Plugin
    // dann selbst eine an, die es aus dem Inhalt errät — und errät seit 11.0.3
    // deutlich schlechter als vorher. Ein PDF landete so als
    // `dokument.octet-stream` statt als `dokument.pdf`. Wir bestimmen die
    // Endung lieber selbst; dann wird der Rateweg des Plugins nie betreten,
    // egal welche Fassung darunter liegt.
    if (!safeName.contains('.')) {
      final guessed = extensionFromMagicBytes(bytes);
      if (guessed != null) safeName = '$safeName.$guessed';
    }
    final ext = safeName.contains('.') ? safeName.split('.').last.toLowerCase() : '';
    final type = ext.isEmpty ? FileType.any : FileType.custom;
    final allowed = ext.isEmpty ? null : [ext];

    if (Platform.isAndroid || Platform.isIOS) {
      // Das Plugin schreibt hier selbst; die Rückgabe ist eine content-URI,
      // kein Dateisystempfad — nicht damit weiterrechnen.
      final saved = await FilePicker.saveFile(
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
        : await FilePicker.saveFile(
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
        return await FilePicker.pickFiles(
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
