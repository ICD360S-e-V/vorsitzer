import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:file_picker/file_picker.dart' as fp;
import 'package:file_selector/file_selector.dart' as fs;

/// Die Dateityp-Auswahl kommt unveraendert aus `file_picker`; nur `any` und
/// `custom` werden hier benutzt.
typedef FileType = fp.FileType;

/// ⚠️ ERSATZ FUER EINEN TYP, DEN `file_picker` 12 GESTRICHEN HAT.
///
/// Bis 11.x gab `pickFiles` ein `FilePickerResult?` mit `files` zurueck, und
/// jede `PlatformFile` trug `bytes` und `size` fertig bei sich. In 12 gibt
/// `pickFiles` eine `List<PlatformFile>`, `FilePickerResult` existiert nicht
/// mehr, und `bytes`/`size` sind zu `readAsBytes()`/`length()` geworden — also
/// asynchron.
///
/// Diese beiden kleinen Klassen halten die alte Form. Der Grund ist nicht
/// Bequemlichkeit: `FilePickerResult?` steht in ueber hundert Signaturen quer
/// durch die App (`Future<void> _upload({FilePickerResult? ausCloud})`), fast
/// immer als reiner Durchreichetyp. Sie alle auf eine asynchrone Oberflaeche
/// umzubauen hiesse, 39 Dateien anzufassen, um an einer einzigen Stelle etwas
/// zu gewinnen. Stattdessen liest der Helper die Bytes EINMAL beim Auswaehlen
/// und reicht sie fertig weiter — genau das, was 11.x mit `withData: true`
/// ohnehin tat.
class PlatformFile {
  const PlatformFile({
    required this.name,
    required this.size,
    this.path,
    this.bytes,
  });

  final String name;
  final int size;
  final String? path;
  final Uint8List? bytes;

  /// Endung ohne Punkt, oder `null`. Gleiche Bedeutung wie frueher.
  String? get extension {
    final i = name.lastIndexOf('.');
    return (i <= 0 || i == name.length - 1) ? null : name.substring(i + 1);
  }
}

/// Ergebnis einer Auswahl. Siehe [PlatformFile] fuer den Grund.
class FilePickerResult {
  const FilePickerResult(this.files);
  final List<PlatformFile> files;
}

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
  }) async {
    if (Platform.isMacOS) {
      return _pickViaMacOSFileSelector(
        allowMultiple: allowMultiple,
        withData: withData,
        dialogTitle: dialogTitle,
      );
    }
    // ⚠️ `allowMultiple` ist in 12 veraltet; fuer die Einzelauswahl gibt es
    // jetzt `pickFile`. Beide Wege muenden in dieselbe Umwandlung.
    //
    // ⚠️ UND BEIDE MUESSEN GEFANGEN WERDEN. Bis 11.x gab die Auswahl `null`
    // zurueck, wenn auf der Plattform keine Umsetzung bereitsteht; seit 12
    // wirft sie stattdessen `UnimplementedError: pickFiles() has not been
    // implemented`. Von den rund dreissig Aufrufstellen hat keine ein
    // try/catch — sie alle rechnen mit `null` fuer „abgebrochen oder geht
    // hier nicht". Ohne dieses catch platzt stattdessen der Knopfdruck.
    // (Gefunden, weil drei Widget-Tests genau daran zerbrachen.)
    try {
      if (!allowMultiple) {
        final eine = await fp.FilePicker.pickFile(
          dialogTitle: dialogTitle,
          type: type,
          allowedExtensions: allowedExtensions,
        );
        return await _umwandeln(eine == null ? const [] : [eine],
            withData: withData);
      }
      final gewaehlt = await fp.FilePicker.pickFiles(
        dialogTitle: dialogTitle,
        type: type,
        allowedExtensions: allowedExtensions,
      );
      return await _umwandeln(gewaehlt, withData: withData);
    } on UnimplementedError catch (e) {
      // Nur DIESER Fall wird geschluckt, und er wird protokolliert. Ein
      // Rechte- oder Lesefehler soll weiterhin nach oben durchschlagen.
      debugPrint('[FilePicker] Auswahl auf dieser Plattform nicht verfuegbar: $e');
      return null;
    }
  }

  /// `file_picker` 12 liefert `PlatformFile`-Objekte, die Groesse und Inhalt
  /// erst auf Nachfrage herausgeben. Hier wird beides EINMAL geholt und in
  /// unsere Form gelegt.
  ///
  /// ⚠️ `withData: false` liest bewusst KEINE Bytes — ein 100-MB-Anhang
  /// soll nicht im Speicher landen, nur weil jemand seinen Namen wissen will.
  /// Die Groesse kostet nichts und kommt immer mit.
  static Future<FilePickerResult?> _umwandeln(
    List<fp.PlatformFile> gewaehlt, {
    required bool withData,
  }) async {
    if (gewaehlt.isEmpty) return null;
    final dateien = <PlatformFile>[];
    for (final f in gewaehlt) {
      dateien.add(PlatformFile(
        name: f.name,
        size: await f.length(),
        path: f.path,
        bytes: withData ? await f.readAsBytes() : null,
      ));
    }
    return FilePickerResult(dateien);
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

    // macOS zuerst: dort scheitert NSSavePanel an fehlenden Entitlements,
    // deshalb schreiben wir selbst nach ~/Downloads (siehe [_saveViaMacOS]).
    if (Platform.isMacOS) {
      final path = await _saveViaMacOS(fileName: safeName);
      if (path == null) return null;
      final target = (ext.isNotEmpty && !path.toLowerCase().endsWith('.$ext'))
          ? '$path.$ext'
          : path;
      await File(target).writeAsBytes(bytes, flush: true);
      return target;
    }

    // ⚠️ Ab `file_picker` 12 verlangt `saveFile` die Bytes IMMER und schreibt
    // die Datei auf JEDER Plattform selbst — vorher tat es das nur auf
    // Android/iOS, und auf Linux/Windows mussten wir hinterher selbst
    // schreiben. Zurueck kommt jetzt eine `Uri` statt eines Pfades.
    final uri = await fp.FilePicker.saveFile(
      dialogTitle: dialogTitle,
      fileName: safeName,
      type: type,
      allowedExtensions: allowed,
      bytes: bytes,
    );
    if (uri == null) return null;

    // ⚠️ Nur ein `file:`-Uri ist ein Pfad, den der Aufrufer oeffnen kann. Auf
    // Android kommt eine `content:`-Uri zurueck — die darf NICHT in einen
    // `File` wandern; dort ist der Dateiname alles, was wir ehrlich sagen
    // koennen. Genau diese Unterscheidung traegt [savesToRealPath].
    if (uri.scheme != 'file') return safeName;
    return uri.toFilePath();
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
        if (!allowMultiple) {
          final eine = await fp.FilePicker.pickFile();
          return await _umwandeln(eine == null ? const [] : [eine],
              withData: withData);
        }
        return await _umwandeln(await fp.FilePicker.pickFiles(),
            withData: withData);
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
