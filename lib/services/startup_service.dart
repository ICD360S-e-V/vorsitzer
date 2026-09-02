import 'dart:io';
import '../utils/autostart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'logger_service.dart';
import 'platform_service.dart';

/// Startup Service - manages auto-start with OS login
/// Windows und Linux. macOS bleibt aussen vor — siehe [AutoStart].
class StartupService {
  static final _log = LoggerService();
  static const String _prefKey = 'start_with_os';

  // Singleton
  static final StartupService _instance = StartupService._internal();
  factory StartupService() => _instance;
  StartupService._internal();

  bool _isEnabled = false;
  bool get isEnabled => _isEnabled;

  /// Check if auto-start is supported on current platform
  bool get isSupported => AutoStart.istUnterstuetzt;

  AutoStart get _autostart => AutoStart(
        appName: 'ICD360S e.V',
        exePfad: Platform.resolvedExecutable,
        args: const ['--autostart'],
      );

  /// Initialize the startup service
  Future<void> initialize() async {
    // Skip on unsupported platforms (mobile + macOS)
    if (!isSupported) {
      _log.debug('Auto-Start nicht unterstützt auf ${PlatformService.platformName}', tag: 'STARTUP');
      return;
    }

    try {
      // Load saved preference
      final prefs = await SharedPreferences.getInstance();
      _isEnabled = prefs.getBool(_prefKey) ?? false;

      // Sync with actual system state
      final isActuallyEnabled = await _autostart.istAktiv();

      if (_isEnabled != isActuallyEnabled) {
        // Preference and actual state don't match, update preference
        _isEnabled = isActuallyEnabled;
        await prefs.setBool(_prefKey, _isEnabled);
      }

      _log.info('StartupService initialisiert (${PlatformService.platformName}). Auto-start: $_isEnabled', tag: 'STARTUP');
    } catch (e) {
      _log.error('StartupService Initialisierung fehlgeschlagen: $e', tag: 'STARTUP');
    }
  }

  /// Enable auto-start with OS login
  Future<bool> enable() async {
    if (!isSupported) return false;

    try {
      await _autostart.einschalten();
      _isEnabled = true;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, true);

      _log.info('Auto-start aktiviert', tag: 'STARTUP');
      return true;
    } catch (e) {
      _log.error('Auto-start Aktivierung fehlgeschlagen: $e', tag: 'STARTUP');
      return false;
    }
  }

  /// Disable auto-start with OS login
  Future<bool> disable() async {
    if (!isSupported) return false;

    try {
      await _autostart.ausschalten();
      _isEnabled = false;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, false);

      _log.info('Auto-start deaktiviert', tag: 'STARTUP');
      return true;
    } catch (e) {
      _log.error('Auto-start Deaktivierung fehlgeschlagen: $e', tag: 'STARTUP');
      return false;
    }
  }

  /// Toggle auto-start
  Future<bool> toggle() async {
    if (_isEnabled) {
      return await disable();
    } else {
      return await enable();
    }
  }

  /// Set auto-start state
  Future<bool> setEnabled(bool enabled) async {
    if (enabled) {
      return await enable();
    } else {
      return await disable();
    }
  }
}
