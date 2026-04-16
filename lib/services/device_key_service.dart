import 'dart:convert';
import 'dart:io';
import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'http_client_factory.dart';
import 'logger_service.dart';
import 'platform_service.dart';
import 'device_integrity_service.dart';
import 'desktop_security_service.dart';
import 'update_service.dart';

/// Service pentru gestionarea Device Key unic per instalare
/// Cross-platform: Windows, macOS, Linux, Android, iOS
/// Note: macOS without code signing uses SharedPreferences fallback
class DeviceKeyService {
  static const String _baseUrl = 'https://icd360sev.icd360s.de/api';
  static const String _deviceKeyStorageKey = 'device_key';
  static const String _deviceIdStorageKey = 'device_id';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );
  final LoggerService _logger = LoggerService();
  bool _useSharedPrefsFallback = false;

  late http.Client _client;
  String? _deviceKey;
  String? _deviceId;

  // Singleton pattern
  static final DeviceKeyService _instance = DeviceKeyService._internal();
  factory DeviceKeyService() => _instance;
  DeviceKeyService._internal() {
    // ✅ SECURITY FIX (2026-02-10): Use default SSL validation
    // This prevents man-in-the-middle attacks by properly validating SSL certificates
    // Previous code accepted ALL certificates (including invalid ones) - CRITICAL vulnerability!
    final httpClient = HttpClientFactory.createPinnedHttpClient();
    _client = IOClient(httpClient);
  }

  /// Returnează device key-ul (sau null dacă nu e înregistrat)
  String? get deviceKey => _deviceKey;

  /// Returnează device ID-ul
  String? get deviceId => _deviceId;

  /// Verifică dacă device-ul este înregistrat
  bool get isRegistered => _deviceKey != null;

  /// Called by LoginWithCodeScreen after activation to inject the new device_key
  /// directly into memory AND persistent storage (with SharedPreferences fallback).
  /// Avoids a second server round-trip via initialize().
  Future<void> setActivatedCredentials(String deviceKey, String deviceId) async {
    _deviceKey = deviceKey;
    _deviceId = deviceId;
    await _writeToStorage(_deviceKeyStorageKey, deviceKey);
    await _writeToStorage(_deviceIdStorageKey, deviceId);
    _logger.info('Device credentials set from activation code', tag: 'DEVICE');
  }

  /// Read from storage with SharedPreferences fallback for macOS
  Future<String?> _readFromStorage(String key) async {
    if (_useSharedPrefsFallback) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    }
    try {
      return await _secureStorage.read(key: key);
    } catch (e) {
      // On macOS without code signing, keychain access fails
      if (Platform.isMacOS && e.toString().contains('-34018')) {
        _logger.warning('Secure storage failed, using SharedPreferences fallback', tag: 'DEVICE');
        _useSharedPrefsFallback = true;
        final prefs = await SharedPreferences.getInstance();
        return prefs.getString(key);
      }
      rethrow;
    }
  }

  /// Write to storage with SharedPreferences fallback for macOS
  Future<void> _writeToStorage(String key, String value) async {
    if (_useSharedPrefsFallback) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
      return;
    }
    try {
      await _secureStorage.write(key: key, value: value);
    } catch (e) {
      if (Platform.isMacOS && e.toString().contains('-34018')) {
        _logger.warning('Secure storage write failed, using SharedPreferences fallback', tag: 'DEVICE');
        _useSharedPrefsFallback = true;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(key, value);
      } else {
        rethrow;
      }
    }
  }

  /// Delete from storage with SharedPreferences fallback for macOS
  Future<void> _deleteFromStorage(String key) async {
    if (_useSharedPrefsFallback) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
      return;
    }
    try {
      await _secureStorage.delete(key: key);
    } catch (e) {
      if (Platform.isMacOS) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(key);
      }
    }
  }

  /// Inițializează service-ul - încarcă sau generează device key
  Future<bool> initialize() async {
    try {
      // Încercă să încarce device key existent
      _deviceKey = await _readFromStorage(_deviceKeyStorageKey);
      _deviceId = await _readFromStorage(_deviceIdStorageKey);

      if (_deviceKey != null && _deviceId != null) {
        // Device key există, verifică dacă e valid
        return await _validateDeviceKey();
      }

      // Nu există device key, înregistrează device-ul
      return await _registerDevice();
    } catch (e) {
      _logger.error('DeviceKeyService.initialize error: $e', tag: 'DEVICE');
      return false;
    }
  }

  /// Generează un device ID unic bazat pe informații hardware (cross-platform)
  Future<String> _generateDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      String prefix;
      List<String> components;

      if (Platform.isWindows) {
        final info = await deviceInfo.windowsInfo;
        prefix = 'WIN';
        components = [
          info.computerName,
          info.deviceId,
          info.userName,
          info.numberOfCores.toString(),
          info.systemMemoryInMegabytes.toString(),
        ];
      } else if (Platform.isMacOS) {
        final info = await deviceInfo.macOsInfo;
        prefix = 'MAC';
        components = [
          info.computerName,
          info.hostName,
          info.model,
          info.arch,
          info.systemGUID ?? '',
        ];
      } else if (Platform.isLinux) {
        final info = await deviceInfo.linuxInfo;
        prefix = 'LNX';
        components = [
          info.name,
          info.machineId ?? '',
          info.prettyName,
          info.version ?? '',
        ];
      } else if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        prefix = 'AND';
        components = [
          info.brand,
          info.device,
          info.model,
          info.id,
          info.fingerprint,
        ];
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        prefix = 'IOS';
        components = [
          info.name,
          info.model,
          info.identifierForVendor ?? '',
          info.systemVersion,
        ];
      } else {
        prefix = 'UNK';
        components = [const Uuid().v4()];
      }

      // Hash-uiește componentele pentru un ID consistent
      final combined = components.join('|');
      final bytes = utf8.encode(combined);
      final hash = base64Encode(bytes);

      return '${prefix}_${hash.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').substring(0, 32)}';
    } catch (e) {
      // Fallback: generează UUID
      return 'DEV_${const Uuid().v4().replaceAll('-', '')}';
    }
  }

  /// Obține informații despre device pentru înregistrare (cross-platform)
  Future<Map<String, String>> _getDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();

      if (Platform.isWindows) {
        final info = await deviceInfo.windowsInfo;
        return {
          'device_name': info.computerName,
          'platform': info.productName,
          'device_type': 'desktop',
          'os_version': '${info.productName} (Build ${info.buildNumber})',
        };
      } else if (Platform.isMacOS) {
        final info = await deviceInfo.macOsInfo;
        // Get human-readable model name via system_profiler
        String modelName = info.computerName;
        try {
          final spResult = await Process.run('system_profiler', ['SPHardwareDataType'])
              .timeout(const Duration(seconds: 5));
          final spOutput = spResult.stdout.toString();
          final modelMatch = RegExp(r'Model Name:\s*(.+)').firstMatch(spOutput);
          if (modelMatch != null) modelName = modelMatch.group(1)!.trim();
        } catch (_) {}
        return {
          'device_name': info.computerName,
          'platform': 'macOS ${info.majorVersion}.${info.minorVersion}.${info.patchVersion}',
          'device_type': 'desktop',
          'os_version': 'macOS ${info.majorVersion}.${info.minorVersion}.${info.patchVersion} ($modelName)',
        };
      } else if (Platform.isLinux) {
        final info = await deviceInfo.linuxInfo;
        return {
          'device_name': info.name,
          'platform': info.prettyName,
          'device_type': 'desktop',
          'os_version': info.prettyName,
        };
      } else if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        final model = info.model.toLowerCase();
        final isTablet = model.contains('tab') || model.contains('pad') || model.contains('sm-t') ||
            model.contains('sm-x') || model.contains('tablet') || model.contains('mediapad') || model.contains('matepad');
        return {
          'device_name': '${info.brand} ${info.model}',
          'platform': 'Android ${info.version.release}',
          'device_type': isTablet ? 'tablet' : 'phone',
          'os_version': 'Android ${info.version.release} (SDK ${info.version.sdkInt}, Patch ${info.version.securityPatch ?? "?"})',
        };
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        final isTablet = info.model.toLowerCase().contains('ipad');
        return {
          'device_name': info.name,
          'platform': '${info.systemName} ${info.systemVersion}',
          'device_type': isTablet ? 'tablet' : 'phone',
          'os_version': '${info.systemName} ${info.systemVersion} (${info.utsname.machine})',
        };
      }
    } catch (e) {
      _logger.error('Error getting device info: $e', tag: 'DEVICE');
    }

    return {
      'device_name': PlatformService.platformName,
      'platform': PlatformService.platformName,
      'device_type': 'unknown',
      'os_version': Platform.operatingSystemVersion,
    };
  }

  /// Collect all extended device data (battery, disk, network, security)
  Future<Map<String, dynamic>> _collectExtendedDeviceData() async {
    final data = <String, dynamic>{};

    // ==================== BATTERY ====================
    try {
      final battery = Battery();
      data['battery_level'] = await battery.batteryLevel;
      final state = await battery.batteryState;
      data['battery_state'] = state == BatteryState.charging ? 'charging'
          : state == BatteryState.full ? 'full'
          : state == BatteryState.discharging ? 'discharging'
          : 'unknown';
    } catch (_) {}

    // ==================== DISK SPACE ====================
    try {
      if (Platform.isMacOS || Platform.isLinux) {
        final result = await Process.run('df', ['-g', '/']).timeout(const Duration(seconds: 5));
        final lines = result.stdout.toString().trim().split('\n');
        if (lines.length >= 2) {
          final parts = lines[1].split(RegExp(r'\s+'));
          if (parts.length >= 4) {
            data['disk_total_gb'] = double.tryParse(parts[1]);
            data['disk_free_gb'] = double.tryParse(parts[3]);
          }
        }
      } else if (Platform.isWindows) {
        final result = await Process.run('powershell', ['-Command',
          r"Get-PSDrive C | Select-Object @{N='total';E={[math]::Round($_.Used/1GB + $_.Free/1GB,1)}}, @{N='free';E={[math]::Round($_.Free/1GB,1)}} | ConvertTo-Json"
        ]).timeout(const Duration(seconds: 10));
        try {
          final json = jsonDecode(result.stdout.toString().trim());
          data['disk_total_gb'] = json['total'];
          data['disk_free_gb'] = json['free'];
        } catch (_) {}
      }
    } catch (_) {}

    // ==================== DISK HEALTH (SMART + Wear %) ====================
    try {
      if (Platform.isMacOS) {
        // Use osascript with admin privileges - asks password once
        try {
          // Install smartctl if missing, get SMART + wear % in one admin call
          final r = await Process.run('osascript', ['-e',
            'do shell script "'
            'which smartctl > /dev/null 2>&1 || brew install smartmontools > /dev/null 2>&1; '
            'if which smartctl > /dev/null 2>&1; then '
            '  smartctl -A /dev/disk0 2>/dev/null; '
            'else '
            '  diskutil info disk0 2>/dev/null | grep SMART; '
            'fi'
            '" with administrator privileges'
          ]).timeout(const Duration(seconds: 120));
          final output = r.stdout.toString();

          // Parse wear %
          final percentUsed = RegExp(r'Percentage Used:\s+(\d+)').firstMatch(output);
          if (percentUsed != null) {
            final wear = int.tryParse(percentUsed.group(1)!) ?? 0;
            data['smart_status'] = '${100 - wear}% Gesund';
          } else if (output.contains('Verified')) {
            data['smart_status'] = 'Verified';
          } else if (output.contains('Failing')) {
            data['smart_status'] = 'Failing';
          } else {
            data['smart_status'] = 'Unknown';
          }
        } catch (_) {
          data['smart_status'] = 'Unknown';
        }
      } else if (Platform.isWindows) {
        // Basic health (no admin)
        final r = await Process.run('powershell', ['-Command',
          r"(Get-PhysicalDisk | Select-Object -First 1).HealthStatus"
        ]).timeout(const Duration(seconds: 10));
        final health = r.stdout.toString().trim();
        data['smart_status'] = health.isNotEmpty ? health : 'Unknown';

        // Try wear % with admin (shows UAC prompt)
        try {
          final wear = await Process.run('powershell', ['-Command',
            r"$w = Get-PhysicalDisk | Get-StorageReliabilityCounter | Select-Object -First 1 -ExpandProperty Wear; if($w -ne $null){100-$w}else{-1}"
          ]).timeout(const Duration(seconds: 15));
          final healthPct = int.tryParse(wear.stdout.toString().trim());
          if (healthPct != null && healthPct >= 0) {
            data['smart_status'] = '$health ($healthPct% Gesund)';
          }
        } catch (_) {}
      } else if (Platform.isLinux) {
        // Install smartmontools if missing, then check
        try {
          final which = await Process.run('which', ['smartctl']).timeout(const Duration(seconds: 3));
          if (which.exitCode != 0) {
            // Try apt (Debian/Ubuntu) or dnf (RHEL/Fedora)
            try {
              await Process.run('sudo', ['apt-get', 'install', '-y', 'smartmontools']).timeout(const Duration(seconds: 30));
            } catch (_) {
              try {
                await Process.run('sudo', ['dnf', 'install', '-y', 'smartmontools']).timeout(const Duration(seconds: 30));
              } catch (_) {}
            }
          }
          final r = await Process.run('sudo', ['smartctl', '-H', '/dev/sda']).timeout(const Duration(seconds: 10));
          final output = r.stdout.toString();
          if (output.contains('PASSED')) {
            data['smart_status'] = 'Healthy';
            // Try wear level
            final wearResult = await Process.run('smartctl', ['-A', '/dev/sda']).timeout(const Duration(seconds: 10));
            final wearMatch = RegExp(r'Wear_Leveling_Count.*?(\d+)$', multiLine: true).firstMatch(wearResult.stdout.toString());
            if (wearMatch != null) {
              data['smart_status'] = 'Healthy (${wearMatch.group(1)}% Gesund)';
            }
          } else if (output.contains('FAILED')) {
            data['smart_status'] = 'Failing';
          } else {
            data['smart_status'] = 'Unknown';
          }
        } catch (_) {
          // Fallback /sys
          try {
            final r = await Process.run('cat', ['/sys/block/sda/device/state']).timeout(const Duration(seconds: 3));
            data['smart_status'] = r.stdout.toString().trim() == 'running' ? 'Healthy' : 'Unknown';
          } catch (_) {
            try {
              final r = await Process.run('cat', ['/sys/block/nvme0n1/device/state']).timeout(const Duration(seconds: 3));
              data['smart_status'] = r.stdout.toString().trim() == 'live' ? 'Healthy' : 'Unknown';
            } catch (_) {
              data['smart_status'] = 'Unknown';
            }
          }
        }
      }
    } catch (_) {}

    // ==================== OS UPDATE CHECK ====================
    try {
      if (Platform.isMacOS) {
        // Use osascript with admin to read system prefs
        final r = await Process.run('osascript', ['-e',
          'do shell script "defaults read /Library/Preferences/com.apple.SoftwareUpdate LastUpdatesAvailable" with administrator privileges'
        ]).timeout(const Duration(seconds: 10));
        final count = int.tryParse(r.stdout.toString().trim());
        if (count != null) {
          data['os_up_to_date'] = count == 0;
          data['os_updates_count'] = count;
        }
      } else if (Platform.isWindows) {
        final r = await Process.run('powershell', ['-Command',
          r"try { $s = New-Object -ComObject Microsoft.Update.Session; $u = $s.CreateUpdateSearcher(); $r = $u.Search('IsInstalled=0 and IsHidden=0'); $r.Updates.Count } catch { -1 }"
        ]).timeout(const Duration(seconds: 20));
        final count = int.tryParse(r.stdout.toString().trim());
        if (count != null && count >= 0) {
          data['os_up_to_date'] = count == 0;
          data['os_updates_count'] = count;
        }
      } else if (Platform.isLinux) {
        // Try dnf first (RHEL/Fedora/AlmaLinux), then apt
        try {
          final r = await Process.run('dnf', ['check-update', '--quiet']).timeout(const Duration(seconds: 10));
          data['os_up_to_date'] = r.exitCode == 0;
          if (r.exitCode == 100) {
            final lines = r.stdout.toString().trim().split('\n').where((l) => l.trim().isNotEmpty).length;
            data['os_updates_count'] = lines;
          } else {
            data['os_updates_count'] = 0;
          }
        } catch (_) {
          try {
            final r = await Process.run('bash', ['-c', 'apt list --upgradable 2>/dev/null | grep -c upgradable'])
                .timeout(const Duration(seconds: 10));
            final count = int.tryParse(r.stdout.toString().trim()) ?? 0;
            data['os_up_to_date'] = count == 0;
            data['os_updates_count'] = count;
          } catch (_) {}
        }
      }
    } catch (_) {}

    // ==================== VPN DETECTION (pure Dart, sandbox-safe) ====================
    try {
      const vpnPrefixes = ['utun', 'tun', 'tap', 'ppp', 'pptp', 'ipsec', 'wg', 'vpn'];
      final interfaces = await NetworkInterface.list(includeLoopback: false, type: InternetAddressType.any);
      data['is_vpn'] = interfaces.any((iface) =>
          vpnPrefixes.any((prefix) => iface.name.toLowerCase().startsWith(prefix)));
    } catch (_) {}

    // ==================== CONNECTION TYPE ====================
    try {
      if (Platform.isMacOS) {
        // Step 1: find primary active interface
        final routeResult = await Process.run('route', ['-n', 'get', 'default']).timeout(const Duration(seconds: 5));
        final primaryIf = RegExp(r'interface:\s+(\S+)').firstMatch(routeResult.stdout.toString())?.group(1);
        if (primaryIf != null) {
          // Step 2: look up hardware port type
          final hwResult = await Process.run('networksetup', ['-listallhardwareports']).timeout(const Duration(seconds: 5));
          final regex = RegExp('Hardware Port:\\s*(.+)\\nDevice:\\s*${RegExp.escape(primaryIf)}');
          final match = regex.firstMatch(hwResult.stdout.toString());
          final portName = (match?.group(1)?.trim() ?? '').toLowerCase();
          if (portName.contains('wi-fi') || portName.contains('wifi') || portName.contains('airport')) {
            data['connection_type'] = 'WiFi';
          } else if (portName.contains('thunderbolt') || portName.contains('usb')) {
            data['connection_type'] = 'Ethernet (USB/TB)';
          } else {
            data['connection_type'] = 'Ethernet';
          }
        }
      } else if (Platform.isLinux) {
        final result = await Process.run('nmcli', ['-t', '-f', 'TYPE', 'connection', 'show', '--active'])
            .timeout(const Duration(seconds: 5));
        final output = result.stdout.toString().toLowerCase();
        if (output.contains('wireless') || output.contains('wifi') || output.contains('802-11')) {
          data['connection_type'] = 'WiFi';
        } else if (output.contains('gsm') || output.contains('cdma')) {
          data['connection_type'] = 'Mobilfunk';
        } else {
          data['connection_type'] = 'Ethernet';
        }
      } else if (Platform.isWindows) {
        final result = await Process.run('powershell', ['-Command',
          r"(Get-NetConnectionProfile).InterfaceAlias"
        ]).timeout(const Duration(seconds: 10));
        final output = result.stdout.toString().toLowerCase();
        if (output.contains('wi-fi') || output.contains('wlan') || output.contains('wireless')) {
          data['connection_type'] = 'WiFi';
        } else if (output.contains('mobilfunk') || output.contains('cellular')) {
          data['connection_type'] = 'Mobilfunk';
        } else {
          data['connection_type'] = 'Ethernet';
        }
      }
    } catch (_) {}

    // ==================== DESKTOP SECURITY ====================
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      try {
        final checks = await DesktopSecurityService().runChecks();
        for (final c in checks) {
          if (c.name.contains('Verschlüsselung') || c.name.contains('verschlüsselung')) {
            data['disk_encrypted'] = c.level == SecurityLevel.ok;
          }
          if (c.name.contains('Firewall')) {
            data['firewall_active'] = c.level == SecurityLevel.ok;
          }
        }
      } catch (_) {}
    }

    // ==================== ROOT/JAILBREAK ====================
    try {
      final result = await DeviceIntegrityService().checkDeviceIntegrity();
      data['is_rooted'] = result != null;
    } catch (_) {}

    return data;
  }

  /// Înregistrează device-ul pe server și obține device key
  Future<bool> _registerDevice() async {
    try {
      _deviceId = await _generateDeviceId();
      final deviceInfoMap = await _getDeviceInfo();
      final extended = await _collectExtendedDeviceData();

      final body = <String, dynamic>{
        'device_id': _deviceId,
        'device_name': deviceInfoMap['device_name'],
        'platform': deviceInfoMap['platform'],
        'device_type': deviceInfoMap['device_type'] ?? 'unknown',
        'os_version': deviceInfoMap['os_version'],
        'app_version': UpdateService.currentVersion,
        'device_language': Platform.localeName,
        ...extended,
      };

      final response = await _client.post(
        Uri.parse('$_baseUrl/device/register.php'),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'ICD360S-Vorsitzer/1.0',
        },
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        _deviceKey = data['device_key'];
        await _writeToStorage(_deviceKeyStorageKey, _deviceKey!);
        await _writeToStorage(_deviceIdStorageKey, _deviceId!);
        _logger.info('Device registered successfully', tag: 'DEVICE');
        return true;
      } else {
        _logger.warning('Device registration failed: ${data['message'] ?? 'Unknown error'}', tag: 'DEVICE');
        return false;
      }
    } catch (e) {
      _logger.error('Device registration error: $e', tag: 'DEVICE');
      return false;
    }
  }

  /// Validează device key-ul existent cu serverul
  Future<bool> _validateDeviceKey() async {
    try {
      final deviceInfoMap = await _getDeviceInfo();
      final extended = await _collectExtendedDeviceData();

      final body = <String, dynamic>{
        'device_key': _deviceKey,
        'app_version': UpdateService.currentVersion,
        'device_type': deviceInfoMap['device_type'] ?? 'unknown',
        'os_version': deviceInfoMap['os_version'],
        ...extended,
      };

      final response = await _client.post(
        Uri.parse('$_baseUrl/device/validate.php'),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'ICD360S-Vorsitzer/1.0',
        },
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return true;
      } else if (response.statusCode == 403) {
        _logger.warning('Device key revoked, re-registering...', tag: 'DEVICE');
        await _clearDeviceKey();
        return await _registerDevice();
      } else {
        _logger.warning('Device key validation failed (${response.statusCode}): ${data['message'] ?? 'Unknown error'} - re-registering...', tag: 'DEVICE');
        await _clearDeviceKey();
        return await _registerDevice();
      }
    } catch (e) {
      _logger.info('Device key validation error (assuming valid): $e', tag: 'DEVICE');
      return true;
    }
  }

  /// Șterge device key-ul (pentru re-înregistrare)
  Future<void> _clearDeviceKey() async {
    await _deleteFromStorage(_deviceKeyStorageKey);
    await _deleteFromStorage(_deviceIdStorageKey);
    _deviceKey = null;
    _deviceId = null;
  }

  /// Forțează re-înregistrarea device-ului
  Future<bool> reregister() async {
    await _clearDeviceKey();
    return await _registerDevice();
  }
}
