import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'logger_service.dart';

final _log = LoggerService();

/// Device integrity check service with native detection.
///
/// Uses Platform Channels to call native code:
/// - Android (Kotlin): root detection via native File checks, /proc scanning, Frida detection
/// - iOS (Swift): jailbreak detection via native path checks, fork(), dylib scanning
///
/// Falls back to Dart-based checks if native channel is unavailable.
/// Desktop platforms (Windows, macOS, Linux) are not checked.
class DeviceIntegrityService {
  static final DeviceIntegrityService _instance = DeviceIntegrityService._internal();
  factory DeviceIntegrityService() => _instance;
  DeviceIntegrityService._internal();

  static const _channel = MethodChannel('de.icd360sev.vorsitzer/device_integrity');

  /// Returns null if device is clean, or a reason string if compromised.
  /// Skip check in debug mode to allow development on any device.
  Future<String?> checkDeviceIntegrity() async {
    // Skip in debug mode
    if (kDebugMode) return null;

    // Only check on mobile platforms
    if (!Platform.isAndroid && !Platform.isIOS) return null;

    try {
      // Call native Kotlin/Swift via Platform Channel
      final result = await _channel.invokeMethod<String?>('checkDeviceIntegrity');
      if (result != null) {
        _log.warning('Device integrity (native): $result', tag: 'SECURITY');
      } else {
        _log.info('Device integrity (native): clean', tag: 'SECURITY');
      }
      return result;
    } on MissingPluginException {
      // Platform channel not available - fall back to Dart checks
      _log.warning('Device integrity: native channel unavailable, using Dart fallback', tag: 'SECURITY');
      return _dartFallback();
    } on PlatformException catch (e) {
      _log.error('Device integrity platform error: ${e.message}', tag: 'SECURITY');
      return _dartFallback();
    } catch (e) {
      _log.error('Device integrity error: $e', tag: 'SECURITY');
      return null; // Don't block on unexpected error
    }
  }

  /// Dart-based fallback if native channel is unavailable.
  /// Less effective than native but still catches common cases.
  Future<String?> _dartFallback() async {
    if (Platform.isAndroid) {
      return _dartCheckAndroid();
    } else if (Platform.isIOS) {
      return _dartCheckIOS();
    }
    return null;
  }

  Future<String?> _dartCheckAndroid() async {
    // su binaries
    final suPaths = [
      '/system/bin/su', '/system/xbin/su', '/sbin/su',
      '/data/local/xbin/su', '/data/local/bin/su', '/su/bin/su',
      '/vendor/bin/su', '/product/bin/su',
    ];
    for (final path in suPaths) {
      try { if (await File(path).exists()) return 'Root-Zugriff erkannt'; } catch (_) {}
    }

    // Root management paths
    final rootPaths = [
      '/data/adb/magisk', '/data/adb/ksu', '/data/adb/ap',
      '/data/adb/modules', '/data/data/com.topjohnwu.magisk',
      '/sbin/.magisk',
    ];
    for (final path in rootPaths) {
      try {
        if (await File(path).exists() || await Directory(path).exists()) return 'Root-Software erkannt';
      } catch (_) {}
    }

    // /proc/self/mounts
    try {
      final mounts = await File('/proc/self/mounts').readAsString();
      if (mounts.contains('magisk') || mounts.contains('/data/adb/modules')) {
        return 'Root-Zugriff erkannt (Mount)';
      }
    } catch (_) {}

    // /proc/self/maps for Frida
    try {
      final maps = await File('/proc/self/maps').readAsString();
      if (maps.toLowerCase().contains('frida')) return 'Frida erkannt';
    } catch (_) {}

    return null;
  }

  Future<String?> _dartCheckIOS() async {
    final paths = [
      '/Applications/Cydia.app', '/Applications/Sileo.app',
      '/var/jb', '/var/jb/basebin/',
      '/Library/MobileSubstrate/MobileSubstrate.dylib',
      '/bin/bash', '/usr/sbin/sshd',
      '/cores/binpack/',
    ];
    for (final path in paths) {
      try {
        if (await File(path).exists() || await Directory(path).exists()) return 'Jailbreak erkannt';
      } catch (_) {}
    }

    // Sandbox escape test
    try {
      final f = File('/private/jb_test_${DateTime.now().millisecondsSinceEpoch}');
      await f.writeAsString('x');
      await f.delete();
      return 'Sandbox-Escape erkannt';
    } catch (_) {}

    return null;
  }
}
