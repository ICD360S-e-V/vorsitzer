import 'package:flutter/material.dart';

/// Widget for displaying member device info and sessions.
/// Used in user_details_dialog.dart as the "Geräte" tab.
class MitgliederDeviceWidget extends StatelessWidget {
  final List<Map<String, dynamic>> sessions;
  final List<Map<String, dynamic>> devices;
  final bool isLoading;
  final Future<void> Function(int sessionId) onRevokeSession;

  const MitgliederDeviceWidget({
    super.key,
    required this.sessions,
    required this.devices,
    required this.isLoading,
    required this.onRevokeSession,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ==================== GERÄTE ====================
          _sectionHeader(Icons.phone_android, Colors.green, 'Registrierte Geräte',
              '${devices.length} Gerät${devices.length == 1 ? '' : 'e'}'),
          const SizedBox(height: 12),

          if (devices.isEmpty)
            _buildEmptyCard('Keine registrierten Geräte', Icons.devices)
          else
            ...devices.map((device) => _buildDeviceCard(device)),

          const SizedBox(height: 24),

          // ==================== SITZUNGEN ====================
          _sectionHeader(Icons.computer, Colors.blue, 'Aktive Sitzungen',
              '${sessions.length} Sitzung${sessions.length == 1 ? '' : 'en'}'),
          const SizedBox(height: 12),

          if (sessions.isEmpty)
            _buildEmptyCard('Keine aktiven Sitzungen', Icons.login)
          else
            ...sessions.map((session) => _buildSessionCard(session)),
        ],
      ),
    );
  }

  Widget _sectionHeader(IconData icon, MaterialColor color, String title, String badge) {
    return Row(
      children: [
        Icon(icon, size: 24, color: color.shade700),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(badge, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        ),
      ],
    );
  }

  // ==================== DEVICE CARD ====================

  Widget _buildDeviceCard(Map<String, dynamic> device) {
    final isActive = device['is_active'] == 1 || device['is_active'] == true;
    final isRooted = device['is_rooted'] == 1 || device['is_rooted'] == true;
    final hasRootInfo = device['is_rooted'] != null;
    final deviceType = device['device_type'] ?? 'unknown';
    final osVersion = device['os_version'] as String?;
    final platform = device['platform'] ?? 'Unbekannt';
    final diskEncrypted = device['disk_encrypted'];
    final firewallActive = device['firewall_active'];
    final hasDiskInfo = diskEncrypted != null;
    final hasFirewallInfo = firewallActive != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isRooted ? const BorderSide(color: Colors.red, width: 2) : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: icon + name + badges
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isActive ? Colors.green.shade50 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _getDeviceTypeIcon(deviceType, platform),
                    color: isActive ? Colors.green.shade700 : Colors.grey,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device['device_name'] ?? 'Unbekannt',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(platform, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildBadge(isActive ? 'Aktiv' : 'Inaktiv', isActive ? Colors.green : Colors.grey),
                    const SizedBox(height: 4),
                    _buildBadge(_getDeviceTypeLabel(deviceType), Colors.blue),
                  ],
                ),
              ],
            ),
            const Divider(height: 20),

            // OS Version
            if (osVersion != null && osVersion.isNotEmpty)
              _infoRow(Icons.computer, 'Betriebssystem', osVersion),

            // App Version
            if (device['app_version'] != null)
              _infoRow(Icons.update, 'Client-Version', 'ICD360S e.V Vorsitzer v${device['app_version']}'),

            // Connection type
            if (device['connection_type'] != null)
              _infoRow(
                _getConnectionTypeIcon(device['connection_type']),
                'Verbindung',
                device['connection_type'].toString(),
              ),
            // VPN status (always show)
            if (device['is_vpn'] != null)
              _infoRow(
                Icons.vpn_key,
                'VPN',
                (device['is_vpn'] == 1 || device['is_vpn'] == true) ? 'Aktiv' : 'Nicht aktiv',
              ),

            // Battery
            if (device['battery_level'] != null)
              _infoRow(
                _getBatteryIcon(device['battery_level'], device['battery_state']),
                'Akku',
                '${device['battery_level']}%${device['battery_state'] == 'charging' ? ' (lädt)' : device['battery_state'] == 'full' ? ' (voll)' : ''}',
              ),

            // Disk space
            if (device['disk_total_gb'] != null)
              _infoRow(Icons.storage, 'Speicher',
                '${device['disk_free_gb'] ?? '?'} GB frei / ${device['disk_total_gb']} GB gesamt'),

            // Disk health (SMART)
            if (device['smart_status'] != null && device['smart_status'] != 'Unknown')
              _infoRow(
                _getSmartIcon(device['smart_status']),
                'Festplatte',
                _getSmartLabel(device['smart_status']),
              ),

            // OS Update status
            if (device['os_up_to_date'] != null)
              _infoRow(
                device['os_up_to_date'] == 1 || device['os_up_to_date'] == true
                    ? Icons.check_circle : Icons.system_update,
                'System-Update',
                device['os_up_to_date'] == 1 || device['os_up_to_date'] == true
                    ? 'Auf dem neuesten Stand'
                    : '${device['os_updates_count'] ?? '?'} Update${(device['os_updates_count'] ?? 0) == 1 ? '' : 's'} verfügbar',
              ),

            // Last used
            if (device['last_used_at'] != null)
              _infoRow(Icons.access_time, 'Zuletzt aktiv', _formatDate(device['last_used_at'])),

            // Security section
            if (hasDiskInfo || hasFirewallInfo || hasRootInfo) ...[
              const SizedBox(height: 10),
              const Text('Sicherheit', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (hasDiskInfo)
                    _buildSecurityChip(
                      diskEncrypted == 1 || diskEncrypted == true,
                      'Verschlüsselung',
                      Icons.lock,
                      Icons.lock_open,
                    ),
                  if (hasFirewallInfo)
                    _buildSecurityChip(
                      firewallActive == 1 || firewallActive == true,
                      'Firewall',
                      Icons.shield,
                      Icons.shield_outlined,
                    ),
                  if (hasRootInfo && deviceType != 'desktop')
                    _buildSecurityChip(
                      !isRooted,
                      isRooted ? 'Root/Jailbreak' : 'Nicht gerootet',
                      Icons.verified_user,
                      Icons.warning,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ==================== SESSION CARD ====================

  Widget _buildSessionCard(Map<String, dynamic> session) {
    final platform = session['platform'] ?? 'Unbekannt';
    final ipProvider = session['ip_provider'] as Map<String, dynamic>?;
    final ipReputation = session['ip_reputation'];
    final isBlacklisted = ipReputation != null && ipReputation['clean'] == false;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isBlacklisted ? const BorderSide(color: Colors.red, width: 2) : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: device icon + name + revoke button
            Row(
              children: [
                Icon(_getSessionDeviceIcon(platform), color: Colors.blue.shade700, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    session['device_name'] ?? 'Unbekanntes Gerät',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.logout, color: Colors.red, size: 20),
                  tooltip: 'Sitzung widerrufen (Force Logout)',
                  onPressed: () => onRevokeSession(session['id']),
                ),
              ],
            ),
            const Divider(height: 16),

            // IP + Blacklist
            Row(
              children: [
                const Icon(Icons.public, size: 14, color: Colors.grey),
                const SizedBox(width: 6),
                Text('IP: ${session['ip_address'] ?? '?'}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                const SizedBox(width: 6),
                _buildIpReputationBadge(ipReputation),
              ],
            ),

            // Netzwerk: Provider + Verbindungstyp
            if (ipProvider != null && ipProvider['provider'] != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(_getConnectionTypeIcon(ipProvider['connection_type']),
                      size: 14, color: _getConnectionTypeColor(ipProvider['connection_type'])),
                  const SizedBox(width: 6),
                  Text(
                    _buildConnectionLabel(ipProvider),
                    style: TextStyle(fontSize: 12, color: _getConnectionTypeColor(ipProvider['connection_type']),
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ],

            // Blacklist warning
            if (isBlacklisted) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, size: 14, color: Colors.red.shade700),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'IP Blacklisted: ${(ipReputation['blacklists'] as List?)?.join(', ') ?? ''}',
                        style: TextStyle(fontSize: 11, color: Colors.red.shade700, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 8),

            // Angemeldet + Läuft ab
            Row(
              children: [
                const Icon(Icons.login, size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Text('Angemeldet: ${_formatDate(session['created_at'])}', style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 16),
                const Icon(Icons.timer_off, size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Text('Läuft ab: ${_formatDate(session['expires_at'])}', style: const TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==================== HELPERS ====================

  String _buildConnectionLabel(Map<String, dynamic> ipProvider) {
    final provider = ipProvider['provider'] ?? '';
    final connectionType = ipProvider['connection_type'] as String?;

    if (connectionType == null) return provider;

    // Build clear label: "Mobilfunk: Telekom (5G)" or "DSL: Vodafone" or "WiFi: Unitymedia"
    return '$connectionType: $provider';
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade500),
          const SizedBox(width: 6),
          SizedBox(
            width: 110,
            child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCard(String text, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.grey.shade400),
            const SizedBox(width: 12),
            Text(text, style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(String label, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.shade200),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color.shade700)),
    );
  }

  Widget _buildSecurityChip(bool isOk, String label, IconData okIcon, IconData badIcon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isOk ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isOk ? Colors.green.shade200 : Colors.red.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isOk ? okIcon : badIcon, size: 16, color: isOk ? Colors.green.shade700 : Colors.red.shade700),
          const SizedBox(width: 6),
          Text(
            '$label: ${isOk ? 'Aktiv' : 'Inaktiv'}',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isOk ? Colors.green.shade700 : Colors.red.shade700),
          ),
        ],
      ),
    );
  }

  Widget _buildIpReputationBadge(dynamic reputation) {
    if (reputation == null) return const SizedBox.shrink();
    final isClean = reputation['clean'] == true;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isClean ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: isClean ? Colors.green.shade200 : Colors.red.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isClean ? Icons.verified_user : Icons.warning, size: 12,
              color: isClean ? Colors.green.shade700 : Colors.red.shade700),
          const SizedBox(width: 3),
          Text(
            isClean ? 'Sauber' : 'Blacklisted',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                color: isClean ? Colors.green.shade700 : Colors.red.shade700),
          ),
        ],
      ),
    );
  }

  IconData _getDeviceTypeIcon(String deviceType, String platform) {
    switch (deviceType) {
      case 'phone':
        return platform.toLowerCase().contains('ios') ? Icons.phone_iphone : Icons.phone_android;
      case 'tablet':
        return Icons.tablet;
      case 'desktop':
        final p = platform.toLowerCase();
        if (p.contains('mac')) return Icons.laptop_mac;
        if (p.contains('linux')) return Icons.laptop;
        return Icons.computer;
      default:
        return _getSessionDeviceIcon(platform);
    }
  }

  IconData _getSmartIcon(dynamic status) {
    final s = (status ?? '').toString().toLowerCase();
    if (s == 'verified' || s == 'healthy' || s == 'ok') return Icons.check_circle;
    if (s == 'failing' || s == 'unhealthy') return Icons.error;
    if (s == 'warning') return Icons.warning;
    return Icons.help_outline;
  }

  String _getSmartLabel(dynamic status) {
    final s = (status ?? '').toString();
    // If it already contains percentage (e.g. "Verified (95% Gesund)")
    if (s.contains('%')) return s;
    final sl = s.toLowerCase();
    if (sl == 'verified' || sl == 'healthy' || sl == 'ok') return 'Gesund';
    if (sl == 'failing' || sl == 'unhealthy') return 'Defekt!';
    if (sl == 'warning') return 'Warnung';
    return s;
  }

  IconData _getBatteryIcon(dynamic level, dynamic state) {
    if (state == 'charging') return Icons.battery_charging_full;
    if (state == 'full') return Icons.battery_full;
    final l = (level is int) ? level : int.tryParse(level.toString()) ?? 50;
    if (l <= 15) return Icons.battery_alert;
    if (l <= 30) return Icons.battery_2_bar;
    if (l <= 50) return Icons.battery_3_bar;
    if (l <= 70) return Icons.battery_4_bar;
    if (l <= 90) return Icons.battery_5_bar;
    return Icons.battery_full;
  }

  String _getDeviceTypeLabel(String deviceType) {
    switch (deviceType) {
      case 'phone': return 'Smartphone';
      case 'tablet': return 'Tablet';
      case 'desktop': return 'Desktop';
      default: return 'Unbekannt';
    }
  }

  IconData _getSessionDeviceIcon(String platform) {
    final p = platform.toLowerCase();
    if (p.contains('windows')) return Icons.computer;
    if (p.contains('android')) return Icons.phone_android;
    if (p.contains('ios') || p.contains('iphone')) return Icons.phone_iphone;
    if (p.contains('mac')) return Icons.laptop_mac;
    if (p.contains('linux')) return Icons.laptop;
    return Icons.devices;
  }

  IconData _getConnectionTypeIcon(String? type) {
    if (type == null) return Icons.wifi;
    if (type.contains('Mobilfunk') || type.contains('5G') || type.contains('LTE') || type.contains('4G')) return Icons.cell_tower;
    if (type.contains('DSL')) return Icons.router;
    if (type.contains('Kabel') || type.contains('Fiber')) return Icons.cable;
    if (type.contains('WiFi') || type.contains('WLAN')) return Icons.wifi;
    if (type.contains('Server') || type.contains('Cloud')) return Icons.cloud;
    return Icons.wifi;
  }

  Color _getConnectionTypeColor(String? type) {
    if (type == null) return Colors.grey;
    if (type.contains('Mobilfunk') || type.contains('5G') || type.contains('LTE')) return Colors.orange;
    if (type.contains('DSL')) return Colors.blue;
    if (type.contains('Kabel') || type.contains('Fiber')) return Colors.green;
    if (type.contains('Server') || type.contains('Cloud')) return Colors.purple;
    return Colors.grey;
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '-';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }
}
