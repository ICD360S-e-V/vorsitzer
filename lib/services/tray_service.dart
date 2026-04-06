import 'dart:io';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:windows_taskbar/windows_taskbar.dart';
import 'logger_service.dart';
import 'platform_service.dart';

/// System Tray Service - manages System Tray Icon and minimize-to-tray
/// Currently Windows only (ICO icons available)
/// macOS/Linux: skipped until PNG icons are added
/// Uses dynamic tray icon with badge (like WhatsApp) for notification counter
class TrayService with TrayListener {
  static final TrayService _instance = TrayService._internal();
  factory TrayService() => _instance;
  TrayService._internal();

  final _log = LoggerService();
  bool _isInitialized = false;
  int _unreadCount = 0;
  String? _exeDir;

  /// Get current unread count
  int get unreadCount => _unreadCount;

  /// Check if tray is supported on current platform
  bool get isSupported => Platform.isWindows;

  /// Get the absolute path for tray icons
  String _getTrayIconPath(String iconName) {
    if (Platform.isWindows && _exeDir != null) {
      return '$_exeDir\\data\\flutter_assets\\assets\\tray_icons\\$iconName';
    } else if (Platform.isMacOS) {
      return 'assets/tray_icons/$iconName';
    } else if (Platform.isLinux) {
      return 'assets/tray_icons/$iconName';
    }
    return 'assets/tray_icons/$iconName';
  }

  /// Get icon file extension based on platform
  String _getIconExtension() {
    if (Platform.isWindows) return '.ico';
    if (Platform.isMacOS) return '.png';
    if (Platform.isLinux) return '.png';
    return '.ico';
  }

  /// Initialize system tray (Windows only for now)
  Future<void> initialize() async {
    if (!isSupported) {
      _log.debug('System Tray übersprungen auf ${PlatformService.platformName} (nur Windows unterstützt)', tag: 'TRAY');
      return;
    }

    if (_isInitialized) return;

    try {
      // Get executable directory for absolute paths (Windows)
      if (Platform.isWindows) {
        final exePath = Platform.resolvedExecutable;
        _exeDir = exePath.substring(0, exePath.lastIndexOf('\\'));
        _log.debug('Exe directory: $_exeDir', tag: 'TRAY');
      }

      final ext = _getIconExtension();
      final iconPath = _getTrayIconPath('tray_icon_0$ext');

      await trayManager.setIcon(iconPath);
      await trayManager.setToolTip('ICD360S e.V - Vorsitzer Portal');

      // Create context menu
      final menu = Menu(
        items: [
          MenuItem(key: 'open', label: 'Öffnen'),
          MenuItem.separator(),
          MenuItem(key: 'exit', label: 'Beenden'),
        ],
      );
      await trayManager.setContextMenu(menu);

      // Register event listener
      trayManager.addListener(this);

      _isInitialized = true;
      _log.info('System Tray initialisiert (${PlatformService.platformName})', tag: 'TRAY');
    } catch (e) {
      _log.error('System Tray Initialisierung fehlgeschlagen: $e', tag: 'TRAY');
    }
  }

  /// TrayListener: handle tray icon click
  @override
  void onTrayIconMouseDown() {
    showWindow();
  }

  /// TrayListener: handle tray icon right click
  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  /// TrayListener: handle menu item click
  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'open':
        showWindow();
        break;
      case 'exit':
        exitApp();
        break;
    }
  }

  /// Show main window
  Future<void> showWindow() async {
    if (!isSupported) return;

    await windowManager.show();
    await windowManager.focus();
    _log.debug('Fenster aus Tray angezeigt', tag: 'TRAY');
  }

  /// Minimize window to tray
  Future<void> hideToTray() async {
    if (!isSupported) return;

    await windowManager.hide();
    _log.debug('Fenster in Tray minimiert', tag: 'TRAY');
  }

  /// Get the absolute path for badge icons (for Windows taskbar overlay)
  String _getBadgeIconPath(String iconName) {
    if (Platform.isWindows && _exeDir != null) {
      return '$_exeDir\\data\\flutter_assets\\assets\\badges\\$iconName';
    }
    return 'assets/badges/$iconName';
  }

  /// Update tray icon and taskbar badge with unread count (WhatsApp style)
  Future<void> updateUnreadCount(int count) async {
    if (!isSupported || !_isInitialized) return;

    _unreadCount = count;
    final tooltip = count > 0
        ? 'ICD360S e.V - $count neue Nachricht${count > 1 ? 'en' : ''}'
        : 'ICD360S e.V - Vorsitzer Portal';

    try {
      await trayManager.setToolTip(tooltip);

      // Update tray icon with badge
      final ext = _getIconExtension();
      final trayIconName = count == 0
          ? 'tray_icon_0$ext'
          : count >= 9
              ? 'tray_icon_9plus$ext'
              : 'tray_icon_$count$ext';

      final trayIconPath = _getTrayIconPath(trayIconName);
      _log.debug('Setze Tray-Icon: $trayIconPath', tag: 'TRAY');
      await trayManager.setIcon(trayIconPath);

      // WINDOWS ONLY: Taskbar overlay badge
      if (Platform.isWindows) {
        if (count > 0) {
          final badgeIconName = count >= 9 ? 'badge_9plus.ico' : 'badge_$count.ico';
          final badgePath = _getBadgeIconPath(badgeIconName);
          _log.debug('Setze Taskbar-Badge: $badgePath', tag: 'TRAY');
          await WindowsTaskbar.setOverlayIcon(
            ThumbnailToolbarAssetIcon(badgePath),
            tooltip: '$count neue Nachricht${count > 1 ? 'en' : ''}',
          );
        } else {
          await WindowsTaskbar.resetOverlayIcon();
        }
      }

      _log.info('Tray Badge aktualisiert (Anzahl: $count)', tag: 'TRAY');
    } catch (e) {
      _log.error('Badge Aktualisierung fehlgeschlagen: $e', tag: 'TRAY');
    }
  }

  /// Increment unread count and flash taskbar
  Future<void> incrementUnread() async {
    if (!isSupported) return;

    await updateUnreadCount(_unreadCount + 1);
    await flashTaskbar();
  }

  /// Reset unread count
  Future<void> clearUnread() async {
    if (!isSupported) return;

    await updateUnreadCount(0);
  }

  /// Flash taskbar icon (Windows only)
  Future<void> flashTaskbar() async {
    if (!Platform.isWindows) return;

    try {
      await WindowsTaskbar.setFlashTaskbarAppIcon(
        mode: TaskbarFlashMode.all | TaskbarFlashMode.timernofg,
        flashCount: 0,
        timeout: const Duration(milliseconds: 0),
      );
      _log.info('Taskleiste blinkt für neue Nachricht', tag: 'TRAY');
    } catch (e) {
      _log.error('Taskleisten-Blinken fehlgeschlagen: $e', tag: 'TRAY');
    }
  }

  /// Stop taskbar flashing (call on window focus)
  Future<void> stopFlashing() async {
    if (!Platform.isWindows) return;

    try {
      await WindowsTaskbar.resetFlashTaskbarAppIcon();
    } catch (e) {
      // Ignore errors when stopping flash
    }
  }

  /// Exit application completely
  Future<void> exitApp() async {
    _log.info('Anwendung wird beendet (aus Tray)', tag: 'TRAY');
    await destroy();
    exit(0);
  }

  /// Destroy tray icon
  Future<void> destroy() async {
    if (!isSupported || !_isInitialized) return;

    try {
      trayManager.removeListener(this);
      await trayManager.destroy();
      _isInitialized = false;
    } catch (e) {
      // Ignore errors when destroying
    }
  }
}
