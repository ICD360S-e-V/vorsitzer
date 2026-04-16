import 'dart:io';
import 'logger_service.dart';

final _log = LoggerService();

/// Security warning level
enum SecurityLevel { ok, warning, critical }

/// A single security check result
class SecurityCheck {
  final String name;        // German name shown in UI
  final SecurityLevel level;
  final String detail;      // German detail text

  const SecurityCheck({
    required this.name,
    required this.level,
    required this.detail,
  });
}

/// Desktop security check service.
/// Checks OS updates, disk encryption, firewall, antivirus (Windows).
/// Shows warnings (does NOT block) — desktop is admin's own device.
///
/// All checks run WITHOUT admin/root privileges.
class DesktopSecurityService {
  static final DesktopSecurityService _instance = DesktopSecurityService._internal();
  factory DesktopSecurityService() => _instance;
  DesktopSecurityService._internal();

  /// Run all checks for current platform. Returns list of findings.
  Future<List<SecurityCheck>> runChecks() async {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return [];

    final checks = <SecurityCheck>[];
    try {
      if (Platform.isWindows) {
        checks.addAll(await _checkWindows());
      } else if (Platform.isMacOS) {
        checks.addAll(await _checkMacOS());
      } else if (Platform.isLinux) {
        checks.addAll(await _checkLinux());
      }
    } catch (e) {
      _log.error('Desktop security check error: $e', tag: 'SECURITY');
    }
    return checks;
  }

  /// Returns only warnings and critical issues (filters out OK)
  Future<List<SecurityCheck>> getIssues() async {
    final all = await runChecks();
    return all.where((c) => c.level != SecurityLevel.ok).toList();
  }

  // ===========================================================================
  // WINDOWS
  // ===========================================================================

  Future<List<SecurityCheck>> _checkWindows() async {
    final checks = <SecurityCheck>[];
    checks.add(await _winCheckFirewall());
    checks.add(await _winCheckAntivirus());
    checks.add(await _winCheckDiskEncryption());
    checks.add(await _winCheckLastUpdate());
    checks.add(await _winCheckOsVersion());
    return checks;
  }

  /// Windows Firewall (netsh - no admin needed)
  Future<SecurityCheck> _winCheckFirewall() async {
    try {
      final result = await Process.run('netsh', [
        'advfirewall', 'show', 'allprofiles', 'state'
      ]).timeout(const Duration(seconds: 10));

      final output = result.stdout.toString();
      // Check for OFF or AUS (German locale)
      final hasOff = output.contains('OFF') || output.contains('AUS');
      final hasOn = output.contains('ON') || output.contains('EIN');

      if (hasOff) {
        return const SecurityCheck(
          name: 'Firewall',
          level: SecurityLevel.critical,
          detail: 'Windows-Firewall ist teilweise oder vollständig deaktiviert',
        );
      }
      if (hasOn) {
        return const SecurityCheck(
          name: 'Firewall',
          level: SecurityLevel.ok,
          detail: 'Windows-Firewall ist aktiv',
        );
      }
    } catch (e) {
      _log.debug('Firewall check failed: $e', tag: 'SECURITY');
    }
    return const SecurityCheck(
      name: 'Firewall',
      level: SecurityLevel.warning,
      detail: 'Firewall-Status konnte nicht ermittelt werden',
    );
  }

  /// Windows Defender / Antivirus (PowerShell - mostly no admin)
  Future<SecurityCheck> _winCheckAntivirus() async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile', '-NonInteractive', '-Command',
        r"try { $s = Get-MpComputerStatus; Write-Output ('{0}|{1}|{2}' -f $s.AntivirusEnabled,$s.RealTimeProtectionEnabled,$s.AMRunningMode) } catch { try { $av = Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct | Select-Object -First 1; Write-Output ('AV|{0}|{1}' -f $av.displayName,$av.productState) } catch { Write-Output 'FAIL' } }"
      ]).timeout(const Duration(seconds: 15));

      final output = result.stdout.toString().trim();

      if (output == 'FAIL' || output.isEmpty) {
        return const SecurityCheck(
          name: 'Antivirus',
          level: SecurityLevel.warning,
          detail: 'Antivirus-Status konnte nicht ermittelt werden',
        );
      }

      // Defender format: True|True|Normal
      if (output.startsWith('AV|')) {
        // Third-party AV detected
        final parts = output.split('|');
        final avName = parts.length > 1 ? parts[1] : 'Unbekannt';
        return SecurityCheck(
          name: 'Antivirus',
          level: SecurityLevel.ok,
          detail: 'Antivirus aktiv: $avName',
        );
      }

      final parts = output.split('|');
      final avEnabled = parts.isNotEmpty && parts[0].toLowerCase() == 'true';
      final rtEnabled = parts.length > 1 && parts[1].toLowerCase() == 'true';
      final mode = parts.length > 2 ? parts[2] : '';

      if (mode == 'Passive') {
        return const SecurityCheck(
          name: 'Antivirus',
          level: SecurityLevel.ok,
          detail: 'Drittanbieter-Antivirus erkannt (Defender im Passivmodus)',
        );
      }

      if (!avEnabled || !rtEnabled) {
        return const SecurityCheck(
          name: 'Antivirus',
          level: SecurityLevel.critical,
          detail: 'Windows Defender ist deaktiviert oder Echtzeitschutz ist aus',
        );
      }

      return const SecurityCheck(
        name: 'Antivirus',
        level: SecurityLevel.ok,
        detail: 'Windows Defender ist aktiv mit Echtzeitschutz',
      );
    } catch (e) {
      _log.debug('Antivirus check failed: $e', tag: 'SECURITY');
    }
    return const SecurityCheck(
      name: 'Antivirus',
      level: SecurityLevel.warning,
      detail: 'Antivirus-Status konnte nicht ermittelt werden',
    );
  }

  /// BitLocker disk encryption (needs admin - best effort)
  Future<SecurityCheck> _winCheckDiskEncryption() async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile', '-NonInteractive', '-Command',
        r"try { $v = Get-BitLockerVolume -MountPoint 'C:' -ErrorAction Stop; Write-Output $v.ProtectionStatus } catch { Write-Output 'NOACCESS' }"
      ]).timeout(const Duration(seconds: 10));

      final output = result.stdout.toString().trim();

      if (output == 'On' || output == '1') {
        return const SecurityCheck(
          name: 'Festplattenverschlüsselung',
          level: SecurityLevel.ok,
          detail: 'BitLocker ist aktiv',
        );
      }
      if (output == 'Off' || output == '0') {
        return const SecurityCheck(
          name: 'Festplattenverschlüsselung',
          level: SecurityLevel.critical,
          detail: 'BitLocker ist nicht aktiviert — Festplatte ist unverschlüsselt',
        );
      }
    } catch (e) {
      _log.debug('BitLocker check failed: $e', tag: 'SECURITY');
    }
    return const SecurityCheck(
      name: 'Festplattenverschlüsselung',
      level: SecurityLevel.warning,
      detail: 'Verschlüsselungsstatus unbekannt (Administratorrechte erforderlich)',
    );
  }

  /// Windows last update date (Get-HotFix - no admin)
  Future<SecurityCheck> _winCheckLastUpdate() async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile', '-NonInteractive', '-Command',
        r"Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1 InstalledOn | ForEach-Object { $_.InstalledOn.ToString('yyyy-MM-dd') }"
      ]).timeout(const Duration(seconds: 15));

      final dateStr = result.stdout.toString().trim();
      if (dateStr.isNotEmpty) {
        final lastUpdate = DateTime.tryParse(dateStr);
        if (lastUpdate != null) {
          final daysSince = DateTime.now().difference(lastUpdate).inDays;
          if (daysSince > 90) {
            return SecurityCheck(
              name: 'Systemaktualisierung',
              level: SecurityLevel.critical,
              detail: 'Letztes Update vor $daysSince Tagen — dringend aktualisieren!',
            );
          }
          if (daysSince > 30) {
            return SecurityCheck(
              name: 'Systemaktualisierung',
              level: SecurityLevel.warning,
              detail: 'Letztes Update vor $daysSince Tagen',
            );
          }
          return SecurityCheck(
            name: 'Systemaktualisierung',
            level: SecurityLevel.ok,
            detail: 'Letztes Update vor $daysSince Tagen',
          );
        }
      }
    } catch (e) {
      _log.debug('Update check failed: $e', tag: 'SECURITY');
    }
    return const SecurityCheck(
      name: 'Systemaktualisierung',
      level: SecurityLevel.warning,
      detail: 'Update-Status konnte nicht ermittelt werden',
    );
  }

  /// Windows version (EOL check)
  Future<SecurityCheck> _winCheckOsVersion() async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile', '-NonInteractive', '-Command',
        r"$v = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'; Write-Output ('{0}|{1}|{2}' -f $v.ProductName,$v.DisplayVersion,$v.CurrentBuild)"
      ]).timeout(const Duration(seconds: 10));

      final output = result.stdout.toString().trim();
      final parts = output.split('|');
      final productName = parts.isNotEmpty ? parts[0] : '';
      final displayVersion = parts.length > 1 ? parts[1] : '';
      final currentBuild = int.tryParse(parts.length > 2 ? parts[2] : '') ?? 0;

      // Windows 10 EOL: October 2025
      if (productName.contains('10') && !productName.contains('11')) {
        return SecurityCheck(
          name: 'Betriebssystem',
          level: SecurityLevel.critical,
          detail: 'Windows 10 wird nicht mehr unterstützt — bitte auf Windows 11 aktualisieren',
        );
      }

      // Windows 11 old versions
      if (currentBuild > 0 && currentBuild < 22631) {
        return SecurityCheck(
          name: 'Betriebssystem',
          level: SecurityLevel.warning,
          detail: '$productName $displayVersion — eine neuere Version ist verfügbar',
        );
      }

      return SecurityCheck(
        name: 'Betriebssystem',
        level: SecurityLevel.ok,
        detail: '$productName $displayVersion',
      );
    } catch (e) {
      _log.debug('OS version check failed: $e', tag: 'SECURITY');
    }
    return SecurityCheck(
      name: 'Betriebssystem',
      level: SecurityLevel.ok,
      detail: Platform.operatingSystemVersion,
    );
  }

  // ===========================================================================
  // macOS
  // ===========================================================================

  Future<List<SecurityCheck>> _checkMacOS() async {
    final checks = <SecurityCheck>[];
    checks.add(await _macCheckFileVault());
    checks.add(await _macCheckFirewall());
    checks.add(await _macCheckOsVersion());
    checks.add(await _macCheckLastUpdate());
    checks.add(await _macCheckSIP());
    checks.add(await _macCheckGatekeeper());
    return checks;
  }

  /// FileVault disk encryption (no admin required)
  Future<SecurityCheck> _macCheckFileVault() async {
    try {
      final result = await Process.run('fdesetup', ['status'])
          .timeout(const Duration(seconds: 10));
      final output = result.stdout.toString().trim();

      if (output.contains('On')) {
        return const SecurityCheck(
          name: 'Festplattenverschlüsselung',
          level: SecurityLevel.ok,
          detail: 'FileVault ist aktiviert',
        );
      }
      if (output.contains('Off')) {
        return const SecurityCheck(
          name: 'Festplattenverschlüsselung',
          level: SecurityLevel.critical,
          detail: 'FileVault ist nicht aktiviert — Festplatte ist unverschlüsselt',
        );
      }
    } catch (e) {
      _log.debug('FileVault check via osascript failed: $e', tag: 'SECURITY');
    }

    return const SecurityCheck(
      name: 'Festplattenverschlüsselung',
      level: SecurityLevel.warning,
      detail: 'FileVault-Status konnte nicht ermittelt werden',
    );
  }

  /// macOS Firewall (no admin required)
  Future<SecurityCheck> _macCheckFirewall() async {
    try {
      final result = await Process.run(
        '/usr/libexec/ApplicationFirewall/socketfilterfw', ['--getglobalstate'],
      ).timeout(const Duration(seconds: 10));

      final output = result.stdout.toString().trim();
      if (output.contains('enabled')) {
        return const SecurityCheck(
          name: 'Firewall',
          level: SecurityLevel.ok,
          detail: 'macOS-Firewall ist aktiviert',
        );
      }
      return const SecurityCheck(
        name: 'Firewall',
        level: SecurityLevel.critical,
        detail: 'macOS-Firewall ist deaktiviert',
      );
    } catch (e) {
      _log.debug('Firewall check failed: $e', tag: 'SECURITY');
    }
    return const SecurityCheck(
      name: 'Firewall',
      level: SecurityLevel.warning,
      detail: 'Firewall-Status konnte nicht ermittelt werden',
    );
  }

  /// macOS version (EOL check)
  Future<SecurityCheck> _macCheckOsVersion() async {
    try {
      final result = await Process.run('sw_vers', ['-productVersion'])
          .timeout(const Duration(seconds: 5));
      final version = result.stdout.toString().trim();
      final major = int.tryParse(version.split('.').first) ?? 0;

      // Apple supports latest 3 major versions (as of 2026: 26, 15, 14)
      if (major > 0 && major < 14) {
        return SecurityCheck(
          name: 'Betriebssystem',
          level: SecurityLevel.critical,
          detail: 'macOS $version wird nicht mehr unterstützt — bitte aktualisieren',
        );
      }
      return SecurityCheck(
        name: 'Betriebssystem',
        level: SecurityLevel.ok,
        detail: 'macOS $version',
      );
    } catch (e) {
      _log.debug('macOS version check failed: $e', tag: 'SECURITY');
    }
    return const SecurityCheck(
      name: 'Betriebssystem',
      level: SecurityLevel.ok,
      detail: 'macOS',
    );
  }

  /// macOS last update date
  Future<SecurityCheck> _macCheckLastUpdate() async {
    try {
      final result = await Process.run('defaults', [
        'read', '/Library/Preferences/com.apple.SoftwareUpdate', 'LastFullSuccessfulDate'
      ]).timeout(const Duration(seconds: 5));

      final output = result.stdout.toString().trim();
      if (output.isNotEmpty) {
        // Format: "2026-04-04 09:35:04 +0000"
        final lastUpdate = DateTime.tryParse(output.replaceAll(' +0000', 'Z'));
        if (lastUpdate != null) {
          final daysSince = DateTime.now().difference(lastUpdate).inDays;
          if (daysSince > 90) {
            return SecurityCheck(
              name: 'Systemaktualisierung',
              level: SecurityLevel.critical,
              detail: 'Letztes Update vor $daysSince Tagen — dringend aktualisieren!',
            );
          }
          if (daysSince > 30) {
            return SecurityCheck(
              name: 'Systemaktualisierung',
              level: SecurityLevel.warning,
              detail: 'Letztes Update vor $daysSince Tagen',
            );
          }
          return SecurityCheck(
            name: 'Systemaktualisierung',
            level: SecurityLevel.ok,
            detail: 'Letztes Update vor $daysSince Tagen',
          );
        }
      }
    } catch (e) {
      _log.debug('macOS update check failed: $e', tag: 'SECURITY');
    }
    return const SecurityCheck(
      name: 'Systemaktualisierung',
      level: SecurityLevel.ok,
      detail: 'Update-Status nicht verfügbar',
    );
  }

  /// System Integrity Protection (SIP)
  Future<SecurityCheck> _macCheckSIP() async {
    try {
      final result = await Process.run('csrutil', ['status'])
          .timeout(const Duration(seconds: 5));
      final output = result.stdout.toString();

      if (output.contains('enabled')) {
        return const SecurityCheck(
          name: 'System Integrity Protection',
          level: SecurityLevel.ok,
          detail: 'SIP ist aktiviert',
        );
      }
      return const SecurityCheck(
        name: 'System Integrity Protection',
        level: SecurityLevel.critical,
        detail: 'SIP ist deaktiviert — Systemschutz fehlt',
      );
    } catch (e) {
      _log.debug('SIP check failed: $e', tag: 'SECURITY');
    }
    return const SecurityCheck(
      name: 'System Integrity Protection',
      level: SecurityLevel.ok,
      detail: 'SIP-Status nicht verfügbar',
    );
  }

  /// Gatekeeper
  Future<SecurityCheck> _macCheckGatekeeper() async {
    try {
      final result = await Process.run('spctl', ['--status'])
          .timeout(const Duration(seconds: 5));
      final output = result.stdout.toString();

      if (output.contains('enabled')) {
        return const SecurityCheck(
          name: 'Gatekeeper',
          level: SecurityLevel.ok,
          detail: 'Gatekeeper ist aktiviert',
        );
      }
      return const SecurityCheck(
        name: 'Gatekeeper',
        level: SecurityLevel.warning,
        detail: 'Gatekeeper ist deaktiviert — unsignierte Apps können installiert werden',
      );
    } catch (e) {
      _log.debug('Gatekeeper check failed: $e', tag: 'SECURITY');
    }
    return const SecurityCheck(
      name: 'Gatekeeper',
      level: SecurityLevel.ok,
      detail: 'Gatekeeper-Status nicht verfügbar',
    );
  }

  // ===========================================================================
  // LINUX
  // ===========================================================================

  Future<List<SecurityCheck>> _checkLinux() async {
    final checks = <SecurityCheck>[];
    checks.add(await _linuxCheckDiskEncryption());
    checks.add(await _linuxCheckFirewall());
    checks.add(await _linuxCheckOsVersion());
    return checks;
  }

  /// LUKS disk encryption (lsblk - no root needed)
  Future<SecurityCheck> _linuxCheckDiskEncryption() async {
    try {
      final result = await Process.run('lsblk', ['-f', '-o', 'NAME,FSTYPE'])
          .timeout(const Duration(seconds: 10));
      final output = result.stdout.toString();

      if (output.contains('crypto_LUKS')) {
        return const SecurityCheck(
          name: 'Festplattenverschlüsselung',
          level: SecurityLevel.ok,
          detail: 'LUKS-Verschlüsselung ist aktiv',
        );
      }
      return const SecurityCheck(
        name: 'Festplattenverschlüsselung',
        level: SecurityLevel.critical,
        detail: 'Keine LUKS-Verschlüsselung erkannt — Festplatte ist unverschlüsselt',
      );
    } catch (e) {
      _log.debug('LUKS check failed: $e', tag: 'SECURITY');
    }
    return const SecurityCheck(
      name: 'Festplattenverschlüsselung',
      level: SecurityLevel.warning,
      detail: 'Verschlüsselungsstatus konnte nicht ermittelt werden',
    );
  }

  /// Linux firewall (systemctl - no root needed)
  Future<SecurityCheck> _linuxCheckFirewall() async {
    final firewalls = ['firewalld', 'ufw', 'nftables'];
    for (final fw in firewalls) {
      try {
        final result = await Process.run('systemctl', ['is-active', fw])
            .timeout(const Duration(seconds: 5));
        if (result.stdout.toString().trim() == 'active') {
          return SecurityCheck(
            name: 'Firewall',
            level: SecurityLevel.ok,
            detail: '$fw ist aktiv',
          );
        }
      } catch (_) {}
    }
    return const SecurityCheck(
      name: 'Firewall',
      level: SecurityLevel.critical,
      detail: 'Keine aktive Firewall erkannt (firewalld/ufw/nftables)',
    );
  }

  /// Linux OS version
  Future<SecurityCheck> _linuxCheckOsVersion() async {
    try {
      final result = await Process.run('/bin/sh', ['-c', 'cat /etc/os-release'])
          .timeout(const Duration(seconds: 5));
      final output = result.stdout.toString();

      String prettyName = 'Linux';
      for (final line in output.split('\n')) {
        if (line.startsWith('PRETTY_NAME=')) {
          prettyName = line.split('=').last.replaceAll('"', '');
          break;
        }
      }

      return SecurityCheck(
        name: 'Betriebssystem',
        level: SecurityLevel.ok,
        detail: prettyName,
      );
    } catch (e) {
      _log.debug('Linux version check failed: $e', tag: 'SECURITY');
    }
    return const SecurityCheck(
      name: 'Betriebssystem',
      level: SecurityLevel.ok,
      detail: 'Linux',
    );
  }
}
