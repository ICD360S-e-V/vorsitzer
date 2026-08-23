import 'dart:io';

import 'package:path_provider_linux/path_provider_linux.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Leitet auf **Linux** das Temp-Verzeichnis in ein privates Cache-Verzeichnis
/// mit Modus 0700 um und räumt beim Start die Reste der letzten Sitzung weg.
///
/// ## Das Problem
/// `getTemporaryDirectory()` liefert auf Linux `/tmp` — ein von ALLEN Nutzern
/// les- und beschreibbares Verzeichnis (Modus 1777). Rund 38 Stellen schreiben
/// dorthin heruntergeladene Mitgliedsdokumente (Jobcenter, Gericht, Arzt,
/// Behörde) zum Öffnen im externen Viewer, mit Modus 664 (umask 002) — für
/// jeden lokalen Prozess und jeden anderen Nutzer lesbar. Gelöscht werden sie
/// nie; `systemd-tmpfiles` räumt `/tmp` erst nach 30 Tagen. Gemessen: 141 MB in
/// 231 Dateien, 230 davon world-readable, die älteste einen Monat alt.
/// CWE-377/378/379, OWASP MASVS-STORAGE.
///
/// ## Warum hier zentral statt an 38 Stellen
/// `getTemporaryDirectory()` liest `PathProviderPlatform.instance`. Eine
/// Unterklasse von [PathProviderLinux], die nur `getTemporaryPath()`
/// überschreibt, biegt damit ALLE Aufrufer auf einmal um — auch künftige — und
/// bündelt Rechtevergabe und Aufräumen an einer Stelle. Das 0700-Elternver-
/// zeichnis verhindert, dass andere Nutzer/Prozesse die Dateien darin überhaupt
/// erreichen (kein Traversal), unabhängig vom Datei-Modus. `~/.cache` liegt
/// zudem im (üblicherweise verschlüsselten) Home, `/tmp` oft auf unverschlüssel-
/// tem tmpfs.
///
/// ## Nur Linux
/// Android/iOS/macOS haben ohnehin ein privates Sandbox-Temp; Androids
/// FileProvider (APK-Update) erwartet den Cache-Pfad. Dort wird NICHTS umgebogen.
class _PrivaterTempPfad extends PathProviderLinux {
  String? _pfad;

  @override
  Future<String?> getTemporaryPath() async {
    final zwischen = _pfad;
    if (zwischen != null) return zwischen;
    try {
      final cache = await getApplicationCachePath(); // ~/.cache/<appid>
      if (cache == null) return super.getTemporaryPath();
      final dir = Directory('$cache/tmp-privat');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      // 0700: nur der Eigentümer darf hinein. Das schützt die 664-Dateien
      // darin, ohne dass jede einzeln gechmod-et werden muss.
      await Process.run('chmod', ['700', dir.path]);
      _pfad = dir.path;
      return dir.path;
    } catch (_) {
      // Lieber funktionierendes /tmp als ein kaputtes Dokument-Öffnen.
      return super.getTemporaryPath();
    }
  }
}

/// Einmal beim Start aufrufen, VOR dem ersten `getTemporaryDirectory()`.
/// No-op außerhalb von Linux. Wirft nie.
Future<void> privaterTempEinrichten() async {
  if (!Platform.isLinux) return;
  try {
    final pfad = _PrivaterTempPfad();
    PathProviderPlatform.instance = pfad;
    // Reste der letzten Sitzung löschen — beim Start ist noch kein Viewer offen,
    // also kann nichts weggezogen werden, das gerade angesehen wird.
    final tmp = await pfad.getTemporaryPath();
    if (tmp != null) {
      final dir = Directory(tmp);
      if (dir.existsSync()) {
        for (final e in dir.listSync()) {
          try {
            e.deleteSync(recursive: true);
          } catch (_) {}
        }
      }
    }
  } catch (_) {}
}
