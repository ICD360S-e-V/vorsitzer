import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'screens/login_with_code_screen.dart';
import 'screens/blitz_fenster_app.dart';
import 'models/blitz_nachricht.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'services/api_service.dart';
import 'utils/privater_temp.dart';
import 'services/device_key_service.dart';
import 'services/notification_service.dart';
import 'services/logger_service.dart';
import 'services/startup_diagnostics.dart';
import 'services/startup_service.dart';
import 'services/update_service.dart';
import 'services/platform_service.dart';
import 'services/theme_service.dart';
import 'utils/app_farben.dart';
import 'utils/app_theme.dart';
import 'utils/keyboard_rdp_fix.dart';

// Desktop-only packages (compile on all platforms, but only used on desktop)
import 'package:window_manager/window_manager.dart';
import 'services/tray_service.dart';
import 'services/weather_profile_service.dart';
import 'widgets/app_sperre_huelle.dart';

// Windows-only package
import 'package:windows_single_instance/windows_single_instance.dart';

/// Gibt das Fensterargument zurück, wenn dieses Isolate ein Blitz-Fenster
/// bedient — sonst `null`.
///
/// ⚠️ Fehler werden geschluckt und als „kein Blitz-Fenster" gewertet. Das ist
/// Absicht: schlägt die Erkennung fehl, muss die App normal starten. Ein
/// Hauptfenster, das wegen einer Kanalstörung nie hochkommt, wäre der weitaus
/// schlimmere Fehler als ein Blitz, der einmal ausbleibt.
Future<String?> _blitzFensterArgument() async {
  try {
    final controller = await WindowController.fromCurrentEngine();
    final arg = controller.arguments;
    if (arg.startsWith('$kBlitzFensterArgument:')) return arg;
  } catch (_) {
    // Plugin noch nicht bereit oder gar nicht vorhanden → Hauptfenster.
  }
  return null;
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // ══════════════════════════════════════════════════════════════════
  // BLITZ-FENSTER? Dann hier abbiegen — und zwar VOR allem anderen.
  //
  // Jedes Fenster von desktop_multi_window bekommt eine eigene Engine und
  // damit ein eigenes Isolate, in dem `main()` ein zweites Mal läuft. Der
  // ganze Rumpf darunter darf dort NICHT laufen: StartupDiagnostics würde
  // in dieselbe Protokolldatei schreiben, das Tray-Symbol entstünde
  // doppelt, media_kit würde ein zweites Mal initialisiert, und der
  // Fensterverwalter bekäme die Optionen des Hauptfensters auf die kleine
  // Karte gelegt.
  //
  // Nur Linux: dort ist der Rückruf zur Plugin-Registrierung im Runner
  // gesetzt (linux/runner/my_application.cc). Unter Windows und macOS
  // entsteht gar kein Blitz-Fenster, also gibt es auch nichts zu erkennen.
  if (Platform.isLinux) {
    final blitzArgument = await _blitzFensterArgument();
    if (blitzArgument != null) {
      await blitzFensterStarten(blitzArgument);
      return;
    }
  }

  // Android 15 (targetSdk 35) zeichnet randlos (edge-to-edge). Bewusst
  // aktiviert, Systemleisten transparent: AppBar-Bildschirme versorgen ihre
  // Insets selbst (Scaffold/AppBar), die wenigen ohne AppBar sind in SafeArea
  // gefasst. `systemNavigationBarContrastEnforced` lässt das System bei Bedarf
  // einen dezenten Schleier hinter die Gestenleiste legen, damit Inhalt darunter
  // lesbar bleibt. Icon-Helligkeit setzt jede AppBar selbst je nach Farbe.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
  ));
  // Load the on-device Weather-sensitivity profile so the first fetch already
  // uses personalised thresholds (cold/heat/PM/UV shifts).
  unawaited(WeatherProfileService.instance.load());

  // ──────────────────────────────────────────────────────────────────
  // StartupDiagnostics: open the on-disk transcript at the FIRST line of
  // main() so a startup that never reaches runApp() is still debuggable
  // via ~/.cache/vorsitzer/startup.log. The transcript is also POSTed
  // (AES-256-GCM-encrypted) to /api/logs/vorsitzer_*.php three seconds
  // after runApp(), once the first frame has rendered.
  // ──────────────────────────────────────────────────────────────────
  StartupDiagnostics.init();

  // Sicherheit: auf Linux Temp-Dateien in ein privates 0700-Verzeichnis
  // umleiten (statt world-readable /tmp) und Reste der letzten Sitzung löschen.
  // MUSS vor dem ersten getTemporaryDirectory() laufen; No-op außer Linux.
  await privaterTempEinrichten();

  // Pre-empt the AltGr-phantom-Ctrl bug that drops Z/Y/X/C/V keystrokes
  // under Windows RDP. Must install before any widget receives input.
  if (Platform.isWindows) {
    StartupDiagnostics.log('→ KeyboardRdpFix.install (Windows)');
    KeyboardRdpFix.install();
  }

  // Route just_audio through media_kit (libmpv) on Windows/Linux so HTTP MP3
  // radio streams actually produce sound. Must run before any AudioPlayer is
  // constructed (RadioService creates one at field-init time).
  if (Platform.isWindows || Platform.isLinux) {
    await StartupDiagnostics.stepWithTimeout(
      'JustAudioMediaKit.ensureInitialized',
      const Duration(seconds: 5),
      () async {
        JustAudioMediaKit.title = 'Vorsitzer Portal';
        JustAudioMediaKit.ensureInitialized(windows: true, linux: true);
        return null;
      },
    );
  }

  // ============================================================
  // DESKTOP-ONLY INITIALIZATION
  // ============================================================
  if (PlatformService.isDesktop) {
    if (Platform.isWindows) {
      await StartupDiagnostics.stepWithTimeout(
        'WindowsSingleInstance.ensureSingleInstance',
        const Duration(seconds: 5),
        () => WindowsSingleInstance.ensureSingleInstance(
          [],
          'icd360sev_vorsitzer_single_instance',
          onSecondWindow: (args) {
            TrayService().showWindow();
          },
        ),
      );
    }

    await StartupDiagnostics.stepWithTimeout(
      'windowManager.ensureInitialized',
      const Duration(seconds: 5),
      () => windowManager.ensureInitialized(),
    );

    WindowOptions windowOptions = const WindowOptions(
      minimumSize: Size(800, 600),
      center: true,
      title: 'ICD360S e.V - Vorsitzer Portal',
    );

    await StartupDiagnostics.stepWithTimeout(
      'windowManager.waitUntilReadyToShow+maximize',
      const Duration(seconds: 8),
      () => windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.maximize();
        await windowManager.show();
        await windowManager.focus();
      }),
    );

    // libayatana-appindicator may be missing inside Flatpak sandbox until
    // bundled as a module — guard so we don't crash if tray init fails.
    await StartupDiagnostics.stepWithTimeout(
      'TrayService.initialize',
      const Duration(seconds: 5),
      () => TrayService().initialize(),
    );
  }

  // Fix Flutter keyboard desync bug on desktop + funnel FlutterError into
  // the diagnostics transcript so render-time crashes show up alongside
  // init failures.
  FlutterError.onError = (FlutterErrorDetails details) {
    final message = details.exceptionAsString();
    if (message.contains('KeyDownEvent') ||
        message.contains('KeyUpEvent') ||
        message.contains('KeyRepeatEvent')) {
      if (message.contains('physical key is already pressed') ||
          message.contains('physical key is not pressed') ||
          message.contains('pressed on a different logical key')) {
        debugPrint('[KEYBOARD-FIX] Suppressed keyboard desync assertion, re-syncing...');
        HardwareKeyboard.instance.syncKeyboardState();
        return;
      }
    }
    StartupDiagnostics.log('FlutterError: ${details.exception}');
    FlutterError.presentError(details);
  };

  // ⚠️ Die gespeicherte Hell/Dunkel-Wahl wird VOR runApp() gelesen. Es ist ein
  // einzelner Lesezugriff auf SharedPreferences (Millisekunden), und dafür
  // startet die Anwendung nicht sichtbar hell, um eine Sekunde später ins
  // Dunkle zu springen. Schlägt der Zugriff fehl, liefert stepWithTimeout
  // null und es bleibt bei ThemeMode.system — das ist die Voreinstellung.
  await StartupDiagnostics.stepWithTimeout(
    'ThemeService.laden',
    const Duration(seconds: 3),
    () => ThemeService.instance.laden(),
  );

  // Start app IMMEDIATELY (no black screen), init services in background
  StartupDiagnostics.log('→ runApp()');
  runApp(const VorsitzerApp());

  // Background service init — wrapped per service so a single hang is
  // visible in the transcript instead of swallowing everything in one
  // try/catch. None of these block runApp().
  //
  // ⚠️ The bodies MUST return the service's own Future. They used to call
  // `LoggerService().init();` and drop the result, so every step logged
  // "DONE (0ms)" for work that had only just begun and the 5s budget policed
  // nothing. During the Linux keyring freeze the transcript therefore reported
  // a perfectly healthy startup while the app was frozen for over a minute.
  //
  // They run concurrently (as they did before, by accident of not being
  // awaited); Future.wait keeps that while still measuring each one honestly.
  // ignore: unawaited_futures
  () async {
    await Future.wait(<Future<void>>[
      StartupDiagnostics.stepWithTimeout(
        'LoggerService.init',
        const Duration(seconds: 5),
        () => LoggerService().init(),
      ),
      StartupDiagnostics.stepWithTimeout(
        'ApiService.initialize',
        const Duration(seconds: 5),
        () => ApiService().initialize(),
      ),
      StartupDiagnostics.stepWithTimeout(
        'NotificationService.initialize',
        const Duration(seconds: 5),
        () => NotificationService().initialize(),
      ),
      StartupDiagnostics.stepWithTimeout(
        'StartupService.initialize',
        const Duration(seconds: 5),
        () => StartupService().initialize(),
      ),
    ]);
  }();

  // Three seconds after runApp() — first frame is rendered, network stack
  // is warm, device_id should be readable. Fire-and-forget; never blocks
  // the UI.
  // ignore: unawaited_futures
  Future<void>.delayed(const Duration(seconds: 3), () async {
    await StartupDiagnostics.uploadToServer(
      appVersion:
          '${UpdateService.currentVersion}+${UpdateService.currentBuildNumber}',
      deviceId: DeviceKeyService().deviceId ?? 'pre-login',
    );
  });
}

class VorsitzerApp extends StatefulWidget {
  const VorsitzerApp({super.key});

  @override
  State<VorsitzerApp> createState() => _VorsitzerAppState();
}

class _VorsitzerAppState extends State<VorsitzerApp> {
  @override
  void initState() {
    super.initState();

    // Desktop-only: Add window listener for tray minimize
    if (PlatformService.isDesktop) {
      _initDesktopWindowListener();
    }
  }

  void _initDesktopWindowListener() {
    windowManager.addListener(_DesktopWindowListener());
    // Prevent closing ONLY where there is a tray icon to restore the window
    // from. TrayService is Windows-only (no PNG icons are shipped for the
    // other desktops), so on Linux this used to leave the X button doing
    // nothing whatsoever: the window did not close, hideToTray() returned on
    // its first line without hiding anything, and the single exit path in the
    // app — the tray menu — did not exist. The process could only be killed.
    windowManager.setPreventClose(TrayService().isSupported);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.instance.modus,
      builder: (context, modus, _) => _bauen(modus),
    );
  }

  Widget _bauen(ThemeMode modus) {
    return MaterialApp(
      title: 'ICD360S e.V - Vorsitzer Portal',
      debugShowCheckedModeBanner: false,
      // Navigator key for in-app notifications overlay
      navigatorKey: NotificationService.navigatorKey,
      // German localization for date/time pickers
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('de', 'DE'),
        Locale('en', 'US'),
      ],
      locale: const Locale('de', 'DE'),
      theme: AppTheme.hell,
      darkTheme: AppTheme.dunkel,
      themeMode: modus,
      // ⚠️ Hier wird der globale Schalter für die Farbtokens gesetzt — und
      // zwar aus `builder`, weil das die einzige Stelle ist, die BEIDE Fälle
      // abdeckt: die eigene Wahl (Hell/Dunkel) und das Umschalten des
      // Betriebssystems, während ThemeMode.system aktiv ist. Ein
      // `ValueListenableBuilder` allein sähe den zweiten Fall nie.
      //
      // `builder` läuft innerhalb des Themas, aber oberhalb des Navigators,
      // also bevor irgendein Bildschirm baut — der Wert steht rechtzeitig.
      builder: (context, child) {
        F.istDunkel = Theme.of(context).brightness == Brightness.dark;
        // Bildschirmsperre ueber der ganzen App. Hier, weil `builder`
        // oberhalb des Navigators laeuft — nur so deckt sie auch offene
        // Dialoge und Vollbildseiten ab. Im Normalfall ist das bloss ein
        // `Listener`; die Sperrflaeche entsteht erst beim Sperren.
        return AppSperreHuelle(child: child ?? const SizedBox.shrink());
      },
      home: const LoginWithCodeScreen(),
      // Hier stand bis 26.08.2026 ein auskommentierter GlobalChatOverlay
      // („TEMPORARY DIAGNOSTIC", 11.07.2026) — sechs Wochen lang war die
      // Funktion damit tot. Ersetzt durch den Blitz, siehe
      // [BlitzNachrichtService]. Die Blasen sind entfallen.
    );
  }
}

/// Desktop-only window listener for tray minimize behavior
class _DesktopWindowListener extends WindowListener {
  @override
  void onWindowClose() {
    if (!TrayService().isSupported) {
      // No tray: X has to close. Announcing "still running in the background"
      // here was wrong twice over — nothing had been hidden, and there was no
      // tray icon to click. Destroy only if something is actually holding the
      // close back, so we never fight the normal close path.
      windowManager.isPreventClose().then((prevented) {
        if (prevented) windowManager.destroy();
      });
      return;
    }
    // Instead of closing, hide to tray
    TrayService().hideToTray().then((_) {
      // Show notification that app is still running
      NotificationService().showSuccess(
        title: 'App im Hintergrund',
        message:
            'ICD360S e.V läuft weiter im Hintergrund. Klicken Sie auf das Tray-Icon zum Öffnen.',
      );
    }).catchError((e) {
      debugPrint('[WINDOW] Error hiding to tray: $e');
    });
  }

  @override
  void onWindowFocus() {
    // Stop taskbar flashing when window gains focus
    TrayService().stopFlashing();
    // Re-sync keyboard state when window regains focus (fixes macOS keyboard desync)
    HardwareKeyboard.instance.syncKeyboardState();
    // Note: Don't clear unread count here - only clear when chat dialog is opened
    // This way the badge stays visible until user actually reads the messages
  }
}
