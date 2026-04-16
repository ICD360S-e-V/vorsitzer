import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/login_screen.dart';
import 'screens/login_with_code_screen.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';
import 'services/logger_service.dart';
import 'services/startup_service.dart';
import 'services/platform_service.dart';

// Desktop-only packages (compile on all platforms, but only used on desktop)
import 'package:window_manager/window_manager.dart';
import 'services/tray_service.dart';

// Windows-only package
import 'package:windows_single_instance/windows_single_instance.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // ============================================================
  // DESKTOP-ONLY INITIALIZATION
  // ============================================================
  if (PlatformService.isDesktop) {
    // Windows: Ensure only one instance of the app runs at a time
    if (Platform.isWindows) {
      await WindowsSingleInstance.ensureSingleInstance(
        [],
        'icd360sev_vorsitzer_single_instance',
        onSecondWindow: (args) {
          // This callback runs when a second instance tries to start
          // Show the existing window
          TrayService().showWindow();
        },
      );
    }

    // Initialize window manager and maximize window
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      minimumSize: Size(800, 600),
      center: true,
      title: 'ICD360S e.V - Vorsitzer Portal',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.maximize();
      await windowManager.show();
      await windowManager.focus();
    });

    // Initialize system tray (desktop only)
    await TrayService().initialize();
  }

  // Fix Flutter keyboard desync bug on desktop
  FlutterError.onError = (FlutterErrorDetails details) {
    final message = details.exceptionAsString();
    if (message.contains('KeyDownEvent') || message.contains('KeyUpEvent') || message.contains('KeyRepeatEvent')) {
      if (message.contains('physical key is already pressed') ||
          message.contains('physical key is not pressed') ||
          message.contains('pressed on a different logical key')) {
        debugPrint('[KEYBOARD-FIX] Suppressed keyboard desync assertion, re-syncing...');
        HardwareKeyboard.instance.syncKeyboardState();
        return;
      }
    }
    FlutterError.presentError(details);
  };

  // Start app IMMEDIATELY (no black screen), init services in background
  runApp(const VorsitzerApp());

  // Initialize services in background (after UI is showing)
  try {
    LoggerService().init();
    ApiService().initialize();
    NotificationService().initialize();
    StartupService().initialize();
  } catch (e) {
    debugPrint('[INIT] Background service initialization error: $e');
  }
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
