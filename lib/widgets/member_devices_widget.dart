import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';

/// Admin (vorsitzer) UI to manage a member's enrolled devices + issue
/// one-time 16-char activation codes. Embeddable inside the user detail dialog.
class MemberDevicesSection extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final String mitgliedernummer;
  final String userName;

  const MemberDevicesSection({
    super.key,
    required this.apiService,
    required this.userId,
    required this.mitgliedernummer,
    required this.userName,
  });

  @override
  State<MemberDevicesSection> createState() => _MemberDevicesSectionState();
}

class _MemberDevicesSectionState extends State<MemberDevicesSection> {
  List<Map<String, dynamic>> _devices = [];
  List<Map<String, dynamic>> _codes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await widget.apiService.listUserDevices(widget.userId);
    if (!mounted) return;
    if (r['success'] == true && r['data'] is Map) {
      final d = r['data'] as Map;
      setState(() {
        _devices = (d['devices'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _codes = (d['activation_codes'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));

    final activeDevices = _devices.where((d) => d['is_active'] == 1 || d['is_active'] == true).toList();
    final revokedDevices = _devices.where((d) => !(d['is_active'] == 1 || d['is_active'] == true)).toList();
    final pendingCode = _codes.firstWhere(
      (c) => c['used_at'] == null && c['revoked_at'] == null,
      orElse: () => {},
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ═══ GENERATE CODE ═══
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.indigo.shade50, Colors.indigo.shade100]),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.indigo.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.vpn_key, size: 18, color: Colors.indigo.shade700),
                  const SizedBox(width: 6),
                  Text('Aktivierungscode', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade900)),
                  const Spacer(),
                  FilledButton.icon(
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text('Neuen Code erstellen', style: TextStyle(fontSize: 11)),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.indigo.shade700,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                    ),
                    onPressed: _generateCode,
                  ),
                ]),
                if (pendingCode.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Icon(Icons.hourglass_top, size: 12, color: Colors.orange.shade700),
                    const SizedBox(width: 4),
                    Text('Ein Code ist aktiv (${pendingCode['code_preview']}…)', style: TextStyle(fontSize: 11, color: Colors.orange.shade900)),
                    const SizedBox(width: 6),
                    Text('gültig bis ${(pendingCode['expires_at']?.toString() ?? '').replaceAll('T', ' ').substring(0, 16)}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  ]),
                ] else ...[
                  const SizedBox(height: 4),
                  Text('Kein aktiver Code. Neuen erstellen, um das Mitglied ein Gerät aktivieren zu lassen.', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          // ═══ ACTIVE DEVICES ═══
          Row(children: [
            Icon(Icons.devices, size: 18, color: Colors.green.shade700),
            const SizedBox(width: 6),
            Text('Aktive Geräte (${activeDevices.length})', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
          ]),
          const Divider(height: 16),
          if (activeDevices.isEmpty)
            _emptyHint('Kein Gerät aktiviert')
          else
            for (final d in activeDevices) _deviceCard(d, active: true),
          // ═══ REVOKED DEVICES ═══
          if (revokedDevices.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(children: [
              Icon(Icons.block, size: 18, color: Colors.red.shade400),
              const SizedBox(width: 6),
              Text('Entzogene Geräte (${revokedDevices.length})', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
            ]),
            const Divider(height: 16),
            for (final d in revokedDevices) _deviceCard(d, active: false),
          ],
        ],
      ),
    );
  }

  Widget _emptyHint(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
      child: Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade500), textAlign: TextAlign.center),
    );
  }

  Widget _deviceCard(Map<String, dynamic> d, {required bool active}) {
    final name = d['device_name']?.toString() ?? 'Unbekannt';
    final platform = d['platform']?.toString() ?? '?';
    final type = d['device_type']?.toString() ?? '?';
    final version = d['app_version']?.toString() ?? '';
    final createdAt = (d['created_at']?.toString() ?? '').replaceAll('T', ' ').substring(0, 16);
    final lastUsed = (d['last_used_at']?.toString() ?? '').replaceAll('T', ' ');
    final keyPreview = d['device_key_preview']?.toString() ?? '';
    final reason = d['revoked_reason']?.toString() ?? '';

    final icon = switch (platform.toLowerCase()) {
      'android' => Icons.phone_android,
      'ios' => Icons.phone_iphone,
      'macos' => Icons.laptop_mac,
      'windows' => Icons.laptop_windows,
      'linux' => Icons.computer,
      _ => Icons.devices_other,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: active ? Colors.white : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: active ? Colors.green.shade200 : Colors.grey.shade300),
      ),
      child: Row(children: [
        Icon(icon, size: 24, color: active ? Colors.green.shade700 : Colors.grey.shade500),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: active ? Colors.black87 : Colors.grey.shade600)),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
                  child: Text('$platform · $type', style: TextStyle(fontSize: 9, color: Colors.grey.shade700)),
                ),
                if (version.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text('v$version', style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
                ],
              ]),
              const SizedBox(height: 2),
              Text('Registriert: $createdAt', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
              if (lastUsed.isNotEmpty && active)
                Text('Zuletzt gesehen: ${lastUsed.substring(0, lastUsed.length >= 16 ? 16 : lastUsed.length)}', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
              if (keyPreview.isNotEmpty)
                Text('Key: $keyPreview', style: TextStyle(fontSize: 9, color: Colors.grey.shade400, fontFamily: 'monospace')),
              if (!active && reason.isNotEmpty)
                Text('Entzogen: $reason', style: TextStyle(fontSize: 10, color: Colors.red.shade400, fontStyle: FontStyle.italic)),
            ],
          ),
        ),
        if (active)
          IconButton(
            icon: Icon(Icons.block, color: Colors.red.shade400, size: 20),
            tooltip: 'Gerät entziehen',
            onPressed: () => _revokeDevice(d['id'] as int, name),
          ),
      ]),
    );
  }

  Future<void> _generateCode() async {
    final r = await widget.apiService.generateActivationCode(targetUserId: widget.userId);
    if (!mounted) return;
    if (r['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r['message']?.toString() ?? 'Fehler beim Erstellen'), backgroundColor: Colors.red),
      );
      return;
    }
    final data = (r['data'] as Map?) ?? {};
    final code = data['code']?.toString() ?? '';
    final expiresAt = (data['expires_at']?.toString() ?? '').replaceAll('T', ' ');
    if (code.isEmpty) return;
    await _showCodeDialog(code, expiresAt);
    _load();
  }

  Future<void> _showCodeDialog(String code, String expiresAt) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(children: [
          Icon(Icons.vpn_key, color: Colors.green.shade700),
          const SizedBox(width: 8),
          const Text('Aktivierungscode erstellt'),
        ]),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Für ${widget.mitgliedernummer} — ${widget.userName}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Colors.indigo.shade50, Colors.indigo.shade100]),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.indigo.shade300),
                ),
                child: Column(children: [
                  SelectableText(
                    code,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                      fontFamily: 'monospace',
                      color: Colors.indigo.shade900,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text('gültig bis ${expiresAt.substring(0, expiresAt.length >= 16 ? 16 : expiresAt.length)}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ]),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.shade200)),
                child: Row(children: [
                  Icon(Icons.warning, size: 16, color: Colors.red.shade700),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'One-Time-Code — wird NIE wieder angezeigt. Jetzt kopieren und an das Mitglied weitergeben.',
                      style: TextStyle(fontSize: 11, color: Colors.red.shade900),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Kopieren'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('In Zwischenablage kopiert'), backgroundColor: Colors.green, duration: Duration(seconds: 1)));
            },
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fertig'),
          ),
        ],
      ),
    );
  }

  Future<void> _revokeDevice(int deviceKeyId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gerät entziehen?'),
        content: Text('Das Gerät "$name" wird sofort abgemeldet und kann nicht mehr auf die App zugreifen.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Entziehen'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final r = await widget.apiService.revokeUserDevice(deviceKeyId: deviceKeyId, reason: 'revoked via admin UI');
    if (!mounted) return;
    if (r['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gerät entzogen'), backgroundColor: Colors.green));
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r['message']?.toString() ?? 'Fehler'), backgroundColor: Colors.red));
    }
  }
}
