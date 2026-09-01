import 'dart:io';

import 'package:win32_registry/win32_registry.dart';

/// Auto-Start beim Anmelden — ohne Plugin.
///
/// ⚠️ WARUM NICHT `launch_at_startup`. Dessen letzte Fassung (0.5.1) verlangt
/// `win32_registry ^2.0.0`. Daran hing ein ganzer Knoten: `device_info_plus`
/// musste auf 12 bleiben (13 will `win32_registry ^3`), dadurch `win32` auf 5,
/// und dadurch blieben `flutter_secure_storage`, `file_picker`, `geolocator`
/// und `windows_single_instance` fest. Fünf direkte Abhängigkeiten wegen
/// eines Pakets, das hier vier Aufrufe leistet.
///
/// Was es tut, ist auf beiden Systemen eine Zeile Betriebssystem-Konvention:
///   Linux    `~/.config/autostart/<name>.desktop`  (XDG Autostart)
///   Windows  `HKCU\...\CurrentVersion\Run`       (ein Wert)
///
/// ⚠️ macOS bleibt aussen vor — genau wie vorher. `launch_at_startup` konnte
/// es auch nicht; dort wäre es ein LaunchAgent-plist, und niemand hat das je
/// gebraucht. `istUnterstuetzt` sagt es ehrlich, statt still nichts zu tun.
class AutoStart {
  const AutoStart({required this.appName, required this.exePfad, this.args = const []});

  final String appName;
  final String exePfad;
  final List<String> args;

  static bool get istUnterstuetzt => Platform.isWindows || Platform.isLinux;

  // ── Windows ────────────────────────────────────────────────────────────
  static const _runPfad = r'Software\Microsoft\Windows\CurrentVersion\Run';

  /// ⚠️ Der Pfad MUSS in Anführungszeichen, sonst liest Windows bei einem
  /// Leerzeichen im Programmpfad („Program Files") alles danach als Argument.
  /// ⚠️ Oeffentlich, damit ein Test sie prueft. Der Windows-Zweig laeuft hier
  /// nie — ohne das waere die Anfuehrungszeichen-Regel unten durch nichts
  /// gedeckt und faende erst auf einem Rechner auf, den wir nicht bauen.
  String get windowsBefehl {
    final teile = ['"$exePfad"', ...args];
    return teile.join(' ');
  }

  // ── Linux ──────────────────────────────────────────────────────────────
  /// Oeffentlich aus demselben Grund wie [windowsBefehl].
  String get desktopDateiName =>
      '${appName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '')}.desktop';

  File get _desktopDatei {
    final heim = Platform.environment['HOME'] ?? '';
    final basis = Platform.environment['XDG_CONFIG_HOME'] ?? '$heim/.config';
    return File('$basis/autostart/$desktopDateiName');
  }

  /// ⚠️ `Exec=` verträgt keine Anführungszeichen um den ganzen Befehl, aber
  /// Leerzeichen im Pfad müssen escapt werden — das ist die Regel des
  /// Desktop-Entry-Standards, nicht die der Shell.
  /// Oeffentlich aus demselben Grund wie [windowsBefehl].
  String get desktopInhalt {
    final befehl = [exePfad, ...args].map((t) => t.replaceAll(' ', r'\ ')).join(' ');
    return '[Desktop Entry]\n'
        'Type=Application\n'
        'Name=$appName\n'
        'Exec=$befehl\n'
        'X-GNOME-Autostart-enabled=true\n'
        'Terminal=false\n';
  }

  Future<bool> istAktiv() async {
    if (Platform.isLinux) return _desktopDatei.existsSync();
    if (Platform.isWindows) {
      final hkcu = RegistryKey.openCurrentUser();
      try {
        final key = hkcu.open(_runPfad);
        try {
          return key.getString(appName) != null;
        } finally {
          key.close();
        }
      } finally {
        hkcu.close();
      }
    }
    return false;
  }

  Future<void> einschalten() async {
    if (Platform.isLinux) {
      final d = _desktopDatei;
      await d.parent.create(recursive: true);
      await d.writeAsString(desktopInhalt);
      return;
    }
    if (Platform.isWindows) {
      final hkcu = RegistryKey.openCurrentUser(RegistryAccess.all);
      try {
        final key = hkcu.open(_runPfad,
            config: const RegistryOpenConfig(access: RegistryAccess.readWrite));
        try {
          key.setValue(appName, RegistryValue.string(windowsBefehl));
        } finally {
          key.close();
        }
      } finally {
        hkcu.close();
      }
    }
  }

  Future<void> ausschalten() async {
    if (Platform.isLinux) {
      final d = _desktopDatei;
      if (d.existsSync()) await d.delete();
      return;
    }
    if (Platform.isWindows) {
      final hkcu = RegistryKey.openCurrentUser(RegistryAccess.all);
      try {
        final key = hkcu.open(_runPfad,
            config: const RegistryOpenConfig(access: RegistryAccess.readWrite));
        try {
          key.removeValue(appName);
        } catch (_) {
          // Wert war nicht da — dann ist das Ziel schon erreicht.
        } finally {
          key.close();
        }
      } finally {
        hkcu.close();
      }
    }
  }
}
