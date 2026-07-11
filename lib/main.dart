import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'screens/login_with_code_screen.dart';
import 'services/api_service.dart';
import 'services/device_key_service.dart';
import 'services/notification_service.dart';
import 'services/logger_service.dart';
import 'services/startup_diagnostics.dart';
import 'services/startup_service.dart';
import 'services/update_service.dart';
import 'services/platform_service.dart';
import 'utils/keyboard_rdp_fix.dart';
import 'widgets/global_chat_overlay.dart';

// Desktop-only packages (compile on all platforms, but only used on desktop)
import 'package:window_manager/window_manager.dart';
import 'services/tray_service.dart';
import 'services/weather_profile_service.dart';

// Windows-only package
import 'package:windows_single_instance/windows_single_instance.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
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

  // Start app IMMEDIATELY (no black screen), init services in background
  StartupDiagnostics.log('→ runApp()');
  runApp(const VorsitzerApp());

  // Background service init — wrapped per service so a single hang is
  // visible in the transcript instead of swallowing everything in one
  // try/catch. None of these block runApp().
  // ignore: unawaited_futures
  () async {
    await StartupDiagnostics.stepWithTimeout(
      'LoggerService.init',
      const Duration(seconds: 5),
      () async {
        LoggerService().init();
        return null;
      },
    );
    await StartupDiagnostics.stepWithTimeout(
      'ApiService.initialize',
      const Duration(seconds: 5),
      () async {
        ApiService().initialize();
        return null;
      },
    );
    await StartupDiagnostics.stepWithTimeout(
      'NotificationService.initialize',
      const Duration(seconds: 5),
      () async {
        NotificationService().initialize();
        return null;
      },
    );
    await StartupDiagnostics.stepWithTimeout(
      'StartupService.initialize',
      const Duration(seconds: 5),
      () async {
        StartupService().initialize();
        return null;
      },
    );
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
    // Prevent window from closing, minimize to tray instead
    windowManager.setPreventClose(true);
  }

  @override
  Widget build(BuildContext context) {
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4a90d9),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        // Use system font on each platform
        fontFamily: Platform.isWindows ? 'Segoe UI' : null,
      ),
      home: const LoginWithCodeScreen(),
      // TEMPORARY DIAGNOSTIC — elimin GlobalChatOverlay complet ca să
      // izolez cauza freeze Android. Dacă butoanele Arbeitswochen merg
      // fără el, e confirmat că overlay blochează. Restore după fix real.
      // builder: (context, child) {
      //   return Stack(children: [
      //     child ?? const SizedBox.shrink(),
      //     const Positioned.fill(child: GlobalChatOverlay()),
      //   ]);
      // },
    );
  }
}

/// Desktop-only window listener for tray minimize behavior
class _DesktopWindowListener extends WindowListener {
  @override
  void onWindowClose() {
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
