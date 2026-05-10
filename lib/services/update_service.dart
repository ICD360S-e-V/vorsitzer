import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path_provider/path_provider.dart';
import 'package:android_package_installer/android_package_installer.dart';
import 'device_key_service.dart';
import 'http_client_factory.dart';
import 'platform_service.dart';
import 'logger_service.dart';

final _log = LoggerService();

/// Update Service - checks for app updates and handles download
/// Cross-platform: Windows (Inno Setup), macOS (DMG), Linux (AppImage),
/// Android (APK), iOS (not supported - use TestFlight)
class UpdateService {
  // Protected API endpoint (requires Device Key)
  static const String versionUrl = 'https://icd360sev.icd360s.de/api/version_vorsitzer.php';
  static const String currentVersion = '4.4.18';
  static const int currentBuildNumber = 543;
  // ✅ SECURITY FIX: Removed hardcoded API key (extractable via reverse engineering)
  // All requests now use dynamic Device Key only

  late http.Client _client;
  late HttpClient _httpClient;
  final _deviceKeyService = DeviceKeyService();

  // Singleton
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal() {
    _httpClient = HttpClientFactory.createPinnedHttpClient();
    _client = IOClient(_httpClient);
  }

  /// Check if an update is available (protected endpoint - requires Device Key)
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final deviceKey = _deviceKeyService.deviceKey;

      // Build headers with Device Key authentication
      if (deviceKey == null) {
        _log.error('Device not registered - cannot check for updates', tag: 'UPDATE');
        return null;
      }

      final headers = <String, String>{
        'Content-Type': 'application/json',
        'User-Agent': 'ICD360S-Vorsitzer/1.0',
        'X-Device-Key': deviceKey,
      };

      final response = await _client.get(
        Uri.parse(versionUrl),
        headers: headers,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);

        // Check if API returned success
        if (result['success'] == true) {
          final serverVersion = result['version'] as String;
          final serverBuildNumber = result['build_number'] as int;
          // Select download URL based on platform
          String downloadUrl = result['download_url'] as String;
          if (Platform.isAndroid && result['download_url_android'] != null) {
            downloadUrl = result['download_url_android'] as String;
          } else if (Platform.isMacOS && result['download_url_macos'] != null) {
            downloadUrl = result['download_url_macos'] as String;
          }
          final changelog = result['changelog'] as String? ?? '';
          final minVersion = result['min_version'] as String?;
          final forceUpdate = result['force_update'] as bool? ?? false;

          // Compare versions
          if (_isNewerVersion(serverVersion, serverBuildNumber)) {
            return UpdateInfo(
              version: serverVersion,
              buildNumber: serverBuildNumber,
              downloadUrl: downloadUrl,
              changelog: changelog,
              minVersion: minVersion,
              forceUpdate: forceUpdate,
            );
          }
        }
      }
    } catch (e) {
      // Silently fail - don't interrupt user if update check fails
    }
    return null;
  }

  /// Compare versions to determine if server has newer version
  bool _isNewerVersion(String serverVersion, int serverBuildNumber) {
    // First compare build numbers (most reliable)
    if (serverBuildNumber > currentBuildNumber) {
      return true;
    }

    // Then compare version strings
    final serverParts = serverVersion.split('.').map(int.parse).toList();
    final currentParts = currentVersion.split('.').map(int.parse).toList();

    for (int i = 0; i < serverParts.length && i < currentParts.length; i++) {
      if (serverParts[i] > currentParts[i]) {
        return true;
      } else if (serverParts[i] < currentParts[i]) {
        return false;
      }
    }

    return false;
  }

  /// Get platform-specific filename for the installer
  String _getInstallerFilename() {
    if (Platform.isWindows) {
      return 'icd360sev_vorsitzer_setup.exe';
    } else if (Platform.isMacOS) {
      return 'icd360sev_vorsitzer.dmg';
    } else if (Platform.isLinux) {
      return 'icd360sev_vorsitzer.AppImage';
    } else if (Platform.isAndroid) {
      return 'icd360sev_vorsitzer.apk';
    } else if (Platform.isIOS) {
      // iOS doesn't support direct install - redirect to TestFlight
      return 'icd360sev_vorsitzer.ipa';
    }
    return 'icd360sev_vorsitzer_update';
  }

  /// Download the update installer (cross-platform)
  Future<String?> downloadUpdate(String downloadUrl, Function(double) onProgress) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final separator = Platform.isWindows ? '\\' : '/';
      final filePath = '${tempDir.path}$separator${_getInstallerFilename()}';
      final file = File(filePath);

      _log.info('Downloading update to: $filePath', tag: 'UPDATE');

      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await _client.send(request);

      if (response.statusCode == 200) {
        final totalBytes = response.contentLength ?? 0;
        int receivedBytes = 0;

        final sink = file.openWrite();
        await for (final chunk in response.stream) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (totalBytes > 0) {
            onProgress(receivedBytes / totalBytes);
          }
        }
        await sink.close();

        _log.info('Update downloaded successfully: $filePath', tag: 'UPDATE');
        return filePath;
      }
    } catch (e) {
      _log.error('Update download failed: $e', tag: 'UPDATE');
    }
    return null;
  }

  /// Launch the installer (cross-platform)
  /// - Windows: Inno Setup with silent flags
  /// - macOS: Mount DMG → copy .app to /Applications → unmount → relaunch
  /// - Linux: Make AppImage executable and run
  /// - Android: Install APK via file manager
  /// - iOS: Open TestFlight URL (direct install not supported)
  Future<void> launchInstaller(String installerPath, {bool silent = true}) async {
    _log.info('Launching installer: $installerPath (${PlatformService.platformName})', tag: 'UPDATE');

    if (Platform.isWindows) {
      // Windows: Inno Setup silent installer
      final args = silent
          ? ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART']
          : <String>[];
      await Process.start(installerPath, args, mode: ProcessStartMode.detached);
      exit(0);

    } else if (Platform.isMacOS) {
      // macOS: Mount DMG, copy .app to /Applications, unmount, relaunch
      await _macOSAutoUpdate(installerPath);

    } else if (Platform.isLinux) {
      // Linux: Make AppImage executable and run
      await Process.run('chmod', ['+x', installerPath]);
      await Process.start(installerPath, [], mode: ProcessStartMode.detached);
      exit(0);

    } else if (Platform.isAndroid) {
      // Android: Install APK via PackageInstaller (handles FileProvider + permissions)
      _log.info('Installing APK: $installerPath', tag: 'UPDATE');
      try {
        final statusCode = await AndroidPackageInstaller.installApk(apkFilePath: installerPath);
        final status = PackageInstallerStatus.byCode(statusCode ?? -1);
        _log.info('APK install status: ${status.name}', tag: 'UPDATE');
      } catch (e) {
        _log.error('APK install failed: $e', tag: 'UPDATE');
      }
      // Don't exit on Android - system will handle installation

    } else if (Platform.isIOS) {
      // iOS: Direct installation not supported - redirect to download page
      _log.warning('iOS direct update not supported - use TestFlight', tag: 'UPDATE');
      // Could open a URL to TestFlight or download page
    }
  }

  /// macOS: Mount DMG, copy .app to /Applications, unmount DMG, relaunch
  Future<void> _macOSAutoUpdate(String dmgPath) async {
    try {
      // 1. Mount the DMG silently with -plist for reliable mount-point parsing
      //    NOTE: -quiet suppresses ALL stdout (including mount point) so we must NOT use it.
      //    -nobrowse prevents the volume from appearing in Finder.
      //    -plist gives us structured XML output to parse the mount point reliably.
      final mountResult = await Process.run('hdiutil', [
        'attach', dmgPath, '-nobrowse', '-plist',
      ]);

      if (mountResult.exitCode != 0) {
        _log.error('Failed to mount DMG: ${mountResult.stderr}', tag: 'UPDATE');
        await Process.start('open', [dmgPath], mode: ProcessStartMode.detached);
        return;
      }

      // 2. Extract mount point from plist output using python3 (always available on macOS)
      //    We write the plist to a temp file and parse with python3 since
      //    Process.run doesn't support piping stdin easily in Dart.
      final tempDir = await getTemporaryDirectory();
      final plistFile = File('${tempDir.path}/hdiutil_output.plist');
      await plistFile.writeAsString(mountResult.stdout as String);

      final parseResult = await Process.run('python3', [
        '-c',
        'import plistlib\n'
        'with open("${plistFile.path}","rb") as f:\n'
        '  pl=plistlib.load(f)\n'
        'mp=[e["mount-point"] for e in pl.get("system-entities",[]) if "mount-point" in e]\n'
        'print(mp[0] if mp else "")',
      ]);
      await plistFile.delete().catchError((_) => plistFile);

      final mountPoint = (parseResult.stdout as String).trim();

      if (mountPoint.isEmpty) {
        _log.error('Could not parse mount point from hdiutil plist output', tag: 'UPDATE');
        await Process.start('open', [dmgPath], mode: ProcessStartMode.detached);
        return;
      }

      _log.info('DMG mounted at: $mountPoint', tag: 'UPDATE');

      // 3. Find the .app bundle in the mounted volume
      final lsResult = await Process.run('find', [mountPoint, '-maxdepth', '1', '-name', '*.app', '-type', 'd']);
      final appPath = (lsResult.stdout as String).trim().split('\n').firstOrNull;

      if (appPath == null || appPath.isEmpty) {
        _log.error('No .app found in $mountPoint', tag: 'UPDATE');
        await Process.run('hdiutil', ['detach', mountPoint, '-force']);
        await Process.start('open', [dmgPath], mode: ProcessStartMode.detached);
        return;
      }

      final appName = appPath.split('/').last; // e.g. "vorsitzer.app"
      final targetPath = '/Applications/$appName';
      final appPid = pid; // current process PID from dart:io

      _log.info('Updating: $appPath → $targetPath', tag: 'UPDATE');

      // 4. Create a shell script that waits for this app to exit, then replaces and relaunches
      //    Uses ditto (Apple's recommended tool for copying .app bundles)
      //    Strips quarantine xattr to prevent Gatekeeper dialog & app translocation
      final scriptPath = '${tempDir.path}/vorsitzer_update.sh';
      final script = '#!/bin/bash\n'
          'APP_PID=$appPid\n'
          'SRC_APP="$appPath"\n'
          'DST_APP="$targetPath"\n'
          'MOUNT_POINT="$mountPoint"\n'
          'DMG_FILE="$dmgPath"\n'
          'SCRIPT_FILE="$scriptPath"\n'
          '\n'
          '# Wait for the current app to exit (max 30 seconds)\n'
          'while kill -0 \$APP_PID 2>/dev/null; do\n'
          '  sleep 0.5\n'
          'done\n'
          '\n'
          '# Remove old version and copy new one (ditto preserves macOS bundle metadata)\n'
          'rm -rf "\$DST_APP"\n'
          'ditto "\$SRC_APP" "\$DST_APP"\n'
          '\n'
          '# Strip quarantine attribute to prevent Gatekeeper dialog and app translocation\n'
          'xattr -r -d com.apple.quarantine "\$DST_APP" 2>/dev/null\n'
          '\n'
          '# Unmount DMG (try graceful first, then force)\n'
          'hdiutil detach "\$MOUNT_POINT" -quiet 2>/dev/null || hdiutil detach "\$MOUNT_POINT" -force 2>/dev/null\n'
          '\n'
          '# Clean up DMG and this script\n'
          'rm -f "\$DMG_FILE"\n'
          '\n'
          '# Relaunch the updated app\n'
          'open "\$DST_APP"\n'
          '\n'
          'rm -f "\$SCRIPT_FILE"\n';

      await File(scriptPath).writeAsString(script);
      await Process.run('chmod', ['+x', scriptPath]);

      // 5. Run the updater script detached and exit the current app
      await Process.start('/bin/bash', [scriptPath], mode: ProcessStartMode.detached);
      _log.info('macOS updater script launched, exiting app...', tag: 'UPDATE');
      exit(0);

    } catch (e) {
      _log.error('macOS auto-update failed: $e', tag: 'UPDATE');
      // Fallback: just open the DMG for manual installation
      await Process.start('open', [dmgPath], mode: ProcessStartMode.detached);
    }
  }

  /// Check if automatic updates are supported on current platform
  bool get supportsAutoUpdate {
    // iOS doesn't support direct APK/IPA installation
    return !Platform.isIOS;
  }
}

/// Update information model
class UpdateInfo {
  final String version;
  final int buildNumber;
  final String downloadUrl;
  final String changelog;
  final String? minVersion;
  final bool forceUpdate;

  UpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.downloadUrl,
    required this.changelog,
    this.minVersion,
    this.forceUpdate = false,
  });
}
