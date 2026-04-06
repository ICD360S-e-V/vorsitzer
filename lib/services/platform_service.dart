import 'dart:io';

/// Platform detection helper service for cross-platform support.
/// Use this service to check platform capabilities and conditionally
/// enable/disable features based on the current platform.
class PlatformService {
  // Singleton
  static final PlatformService _instance = PlatformService._internal();
  factory PlatformService() => _instance;
  PlatformService._internal();

  // ============================================================
  // PLATFORM TYPE DETECTION
  // ============================================================

  /// Returns true if running on any desktop platform (Windows, macOS, Linux)
  static bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  /// Returns true if running on any mobile platform (Android, iOS)
  static bool get isMobile => Platform.isAndroid || Platform.isIOS;

  /// Returns true if running on Windows
  static bool get isWindows => Platform.isWindows;

  /// Returns true if running on macOS
  static bool get isMacOS => Platform.isMacOS;

  /// Returns true if running on Linux
  static bool get isLinux => Platform.isLinux;

  /// Returns true if running on Android
  static bool get isAndroid => Platform.isAndroid;

  /// Returns true if running on iOS
  static bool get isIOS => Platform.isIOS;

  // ============================================================
  // FEATURE SUPPORT DETECTION
  // ============================================================

  /// Returns true if the platform supports system tray (desktop only)
  static bool get supportsSystemTray => isDesktop;

  /// Returns true if the platform supports window management (desktop only)
  static bool get supportsWindowManager => isDesktop;

  /// Returns true if the platform supports taskbar badges
  /// Windows: Windows Taskbar, macOS: Dock, Linux: varies
  static bool get supportsTaskbarBadge => isDesktop;

  /// Returns true if the platform supports app icon badges (mobile)
  static bool get supportsAppBadge => isMobile;

  /// Returns true if the platform supports auto-start with OS login
  static bool get supportsAutoStart => isDesktop;

  /// Returns true if the platform supports background work scheduling
  static bool get supportsWorkManager => Platform.isAndroid;

  /// Returns true if the platform supports single instance enforcement
  /// Currently only Windows has robust support
  static bool get supportsSingleInstance => Platform.isWindows;

  /// Returns true if the platform supports WebView2 (Windows)
  static bool get supportsWebView2 => Platform.isWindows;

  /// Returns true if the platform uses WKWebView (iOS, macOS)
  static bool get supportsWKWebView => Platform.isIOS || Platform.isMacOS;

  /// Returns true if the platform uses Android WebView
  static bool get supportsAndroidWebView => Platform.isAndroid;

  // ============================================================
  // PATH HELPERS
  // ============================================================

  /// Returns the path separator for the current platform
  static String get pathSeparator => Platform.pathSeparator;

  /// Returns true if the platform uses backslash as path separator (Windows)
  static bool get usesBackslashPaths => Platform.isWindows;

  // ============================================================
  // PLATFORM INFO
  // ============================================================

  /// Returns a human-readable platform name
  static String get platformName {
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    return 'Unknown';
  }

  /// Returns the platform operating system version
  static String get osVersion => Platform.operatingSystemVersion;

  /// Returns the local hostname
  static String get hostName => Platform.localHostname;

  /// Returns the number of processors
  static int get numberOfProcessors => Platform.numberOfProcessors;
}
