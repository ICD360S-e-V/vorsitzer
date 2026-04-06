import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../services/api_service.dart';
import '../services/update_service.dart';
import '../utils/role_helpers.dart';

class ClientScreen extends StatefulWidget {
  const ClientScreen({super.key});

  @override
  State<ClientScreen> createState() => _ClientScreenState();
}

class _ClientScreenState extends State<ClientScreen> {
  final ApiService _apiService = ApiService();
  final UpdateService _updateService = UpdateService();

  bool _isLoading = true;
  String? _error;
  UpdateInfo? _updateInfo;
  bool _updateChecked = false;
  Map<String, dynamic>? _devicesData;
  Timer? _refreshTimer;

  // Local client info
  String _dartVersion = '';
  String _platform = '';
  String _osVersion = '';
  String _deviceName = '';

  static const _flutterVersion = String.fromEnvironment('FLUTTER_VERSION', defaultValue: 'unbekannt');
  static const _flutterDartVersion = String.fromEnvironment('FLUTTER_DART_VERSION', defaultValue: '');

  @override
  void initState() {
    super.initState();
    _loadClientInfo();
    _loadAll();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _loadDevices(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadDevices(), _checkForUpdates()]);
  }

  Future<void> _loadClientInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    String osVer = '';
    String devName = '';

    try {
      if (Platform.isMacOS) {
        final info = await deviceInfo.macOsInfo;
        osVer = 'macOS ${info.osRelease}';
        devName = info.computerName;
      } else if (Platform.isWindows) {
        final info = await deviceInfo.windowsInfo;
        osVer = 'Windows ${info.displayVersion} (Build ${info.buildNumber})';
        devName = info.computerName;
      } else if (Platform.isLinux) {
        final info = await deviceInfo.linuxInfo;
        osVer = info.prettyName;
        devName = info.machineId ?? 'Linux';
      } else if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        osVer = 'Android ${info.version.release} (SDK ${info.version.sdkInt})';
        devName = '${info.manufacturer} ${info.model}';
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        osVer = 'iOS ${info.systemVersion}';
        devName = info.name;
      }
    } catch (_) {
      osVer = Platform.operatingSystemVersion;
      devName = Platform.localHostname;
    }

    if (mounted) {
      setState(() {
        _dartVersion = Platform.version.split(' ').first;
        _platform = Platform.operatingSystem;
        _osVersion = osVer;
        _deviceName = devName;
      });
    }
  }

  Future<void> _loadDevices({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      final response = await _apiService.getConnectedDevices();
      if (mounted) {
        setState(() {
          if (response['success'] == true) {
            _devicesData = response;
          } else {
            _error = response['message'] ?? 'Fehler';
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && !silent) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _checkForUpdates() async {
    try {
      final result = await _updateService.checkForUpdate();
      if (mounted) setState(() { _updateInfo = result; _updateChecked = true; });
    } catch (_) {
      if (mounted) setState(() => _updateChecked = true);
    }
  }

  String _getArchitecture() {
    final ver = Platform.version;
    if (ver.contains('arm64') || ver.contains('aarch64')) return 'ARM64 (Apple Silicon)';
    if (ver.contains('x64') || ver.contains('x86_64')) return 'x86_64 (64-bit)';
    if (ver.contains('arm')) return 'ARM';
    return Platform.operatingSystem;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.devices, size: 28, color: Colors.blueGrey),
              const SizedBox(width: 12),
              const Text('Client', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll, tooltip: 'Aktualisieren'),
            ],
          ),
          const SizedBox(height: 24),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text('Fehler: $_error', style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _loadAll, child: const Text('Erneut versuchen')),
            ]))
          else
            Expanded(child: SingleChildScrollView(child: _buildContent())),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final hasUpdate = _updateInfo != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // App + Update
        _buildCard('Anwendung', Icons.apps, Colors.blue, [
          _buildInfoRowWithStatus(
            'Version',
            UpdateService.currentVersion,
            !hasUpdate,
            hasUpdate ? 'Update: ${_updateInfo!.version}' : (_updateChecked ? 'Aktuell' : 'Prüfung...'),
          ),
          _buildInfoRow('Build-Nummer', UpdateService.currentBuildNumber.toString()),
          _buildInfoRow('Flutter', _flutterVersion.isNotEmpty ? _flutterVersion : 'N/A'),
          _buildInfoRow('Dart', _flutterDartVersion.isNotEmpty ? _flutterDartVersion : _dartVersion),
          _buildInfoRow('Modus', kReleaseMode ? 'Release' : (kProfileMode ? 'Profile' : 'Debug')),
        ]),
        const SizedBox(height: 16),

        // This device
        _buildCard('Dieses Gerät', Icons.computer, Colors.green, [
          _buildInfoRow('Gerätename', _deviceName),
          _buildInfoRow('Betriebssystem', _osVersion),
          _buildInfoRow('Plattform', _platform),
          _buildInfoRow('Architektur', _getArchitecture()),
          _buildInfoRow('Prozessoren', Platform.numberOfProcessors.toString()),
          _buildInfoRow('Locale', Platform.localeName),
        ]),
        const SizedBox(height: 16),

        // Connected devices stats
        if (_devicesData != null) ...[
          _buildCard('Verbundene Geräte', Icons.devices_other, Colors.deepPurple, [
            Row(
              children: [
                _buildStatBox('Sitzungen', '${_devicesData!['total_sessions'] ?? 0}', Colors.deepPurple),
                const SizedBox(width: 12),
                _buildStatBox('Benutzer', '${_devicesData!['unique_users'] ?? 0}', Colors.blue),
                const SizedBox(width: 12),
                _buildStatBox('Veraltet', '${_devicesData!['outdated_count'] ?? 0}', (_devicesData!['outdated_count'] ?? 0) > 0 ? Colors.orange : Colors.green),
              ],
            ),
            if (_devicesData!['portals'] != null) ...[
              const SizedBox(height: 16),
              const Text('Portale', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              ...(_devicesData!['portals'] as Map<String, dynamic>).entries.map((e) {
                final total = _devicesData!['total_sessions'] as int;
                final count = e.value as int;
                final color = e.key == 'Vorsitzer' ? Colors.purple : (e.key == 'Schatzmeister' ? Colors.teal : Colors.blue);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Icon(Icons.apps, size: 14, color: color),
                    const SizedBox(width: 8),
                    SizedBox(width: 110, child: Text(e.key, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600))),
                    Expanded(child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(value: count / (total > 0 ? total : 1), backgroundColor: Colors.grey.shade200, color: color, minHeight: 8),
                    )),
                    SizedBox(width: 40, child: Text('$count', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                  ]),
                );
              }),
            ],
            const SizedBox(height: 16),
            if (_devicesData!['platforms'] != null) ...[
              const Text('Plattformen', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              ...(_devicesData!['platforms'] as Map<String, dynamic>).entries.map((e) {
                final total = _devicesData!['total_sessions'] as int;
                final count = e.value as int;
                final pct = total > 0 ? (count / total * 100).toStringAsFixed(0) : '0';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Icon(_platformIcon(e.key), size: 16, color: Colors.deepPurple.shade300),
                    const SizedBox(width: 8),
                    SizedBox(width: 80, child: Text(e.key, style: const TextStyle(fontSize: 13))),
                    Expanded(child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(value: count / (total > 0 ? total : 1), backgroundColor: Colors.grey.shade200, color: Colors.deepPurple.shade300, minHeight: 8),
                    )),
                    SizedBox(width: 60, child: Text('$count ($pct%)', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                  ]),
                );
              }),
            ],
            const SizedBox(height: 12),
            if (_devicesData!['app_versions'] != null) ...[
              const Text('App-Versionen', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              ...(_devicesData!['app_versions'] as Map<String, dynamic>).entries.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  const Icon(Icons.tag, size: 14, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text('v${e.key}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: Colors.deepPurple.shade50, borderRadius: BorderRadius.circular(10)),
                    child: Text('${e.value}', style: TextStyle(fontSize: 12, color: Colors.deepPurple.shade700, fontWeight: FontWeight.w600)),
                  ),
                ]),
              )),
            ],
          ]),
          const SizedBox(height: 16),

          // Sessions list
          _buildCard('Aktive Sitzungen (${_devicesData!['total_sessions'] ?? 0})', Icons.list, Colors.teal, [
            if (_devicesData!['sessions'] != null)
              ...(_devicesData!['sessions'] as List).map<Widget>((session) {
                final roleColor = getRoleColor(session['role'] ?? '');
                final isOutdated = session['is_outdated'] == true;
                final portal = session['portal'] ?? '';
                final appVer = session['app_version'] ?? '-';
                final latestVer = session['latest_version'] ?? '-';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: isOutdated ? Colors.orange.shade300 : Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(8),
                    color: isOutdated ? Colors.orange.shade50 : Colors.grey.shade50,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.person, size: 16, color: roleColor),
                        const SizedBox(width: 6),
                        Text('${session['name'] ?? '-'}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: roleColor)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: roleColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                          child: Text('${session['mitgliedernummer'] ?? ''}', style: TextStyle(fontSize: 11, color: roleColor, fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
                          child: Text(portal, style: TextStyle(fontSize: 10, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: isOutdated ? Colors.orange.shade100 : Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('v$appVer', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isOutdated ? Colors.orange.shade800 : Colors.green.shade700)),
                              if (isOutdated) ...[
                                const SizedBox(width: 4),
                                Icon(Icons.arrow_forward, size: 10, color: Colors.orange.shade700),
                                const SizedBox(width: 2),
                                Text(latestVer, style: TextStyle(fontSize: 10, color: Colors.orange.shade700)),
                              ] else ...[
                                const SizedBox(width: 4),
                                Icon(Icons.check, size: 10, color: Colors.green.shade700),
                              ],
                            ],
                          ),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Row(children: [
                        Icon(_platformIcon(session['platform'] ?? ''), size: 14, color: Colors.grey),
                        const SizedBox(width: 6),
                        Expanded(child: Text('${session['device_name'] ?? '-'} · ${session['platform'] ?? '-'}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
                      ]),
                      const SizedBox(height: 4),
                      Row(children: [
                        Icon(Icons.wifi, size: 14, color: Colors.grey.shade400),
                        const SizedBox(width: 6),
                        Text('${session['ip_address'] ?? '-'}', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                        const Spacer(),
                        Icon(Icons.access_time, size: 14, color: Colors.grey.shade400),
                        const SizedBox(width: 4),
                        Text('${session['login_time'] ?? '-'}', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                      ]),
                    ],
                  ),
                );
              }),
          ]),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  IconData _platformIcon(String platform) {
    final p = platform.toLowerCase();
    if (p.contains('android')) return Icons.phone_android;
    if (p.contains('ios') || p.contains('iphone')) return Icons.phone_iphone;
    if (p.contains('windows')) return Icons.desktop_windows;
    if (p.contains('mac')) return Icons.laptop_mac;
    if (p.contains('linux')) return Icons.computer;
    return Icons.devices;
  }

  Widget _buildStatBox(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(children: [
          Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.7))),
        ]),
      ),
    );
  }

  Widget _buildCard(String title, IconData icon, Color color, List<Widget> children) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 10),
              Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            ]),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 180, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.grey))),
          Expanded(child: SelectableText(value, style: const TextStyle(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _buildInfoRowWithStatus(String label, String value, bool isGood, String statusText) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 180, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.grey))),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              children: [
                SelectableText(value, style: const TextStyle(fontWeight: FontWeight.w500)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isGood ? Colors.green.shade50 : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isGood ? Colors.green.shade300 : Colors.orange.shade300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(isGood ? Icons.check_circle : Icons.warning, size: 14, color: isGood ? Colors.green.shade700 : Colors.orange.shade700),
                      const SizedBox(width: 4),
                      Text(statusText, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: isGood ? Colors.green.shade700 : Colors.orange.shade700)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
