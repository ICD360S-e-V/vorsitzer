import 'dart:io';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../services/rdp_service.dart';
import 'rdp_session_screen.dart';

/// Manages Guacamole RDP connections: the (separate) gateway URL, saved
/// connection profiles, and launching a fullscreen in-app session.
class RemoteDesktopScreen extends StatefulWidget {
  const RemoteDesktopScreen({super.key});

  @override
  State<RemoteDesktopScreen> createState() => _RemoteDesktopScreenState();
}

class _RemoteDesktopScreenState extends State<RemoteDesktopScreen> {
  final RdpService _svc = RdpService();
  String? _gateway;
  List<RdpProfile> _profiles = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final g = await _svc.getGateway();
    final p = await _svc.loadProfiles();
    if (!mounted) return;
    setState(() {
      _gateway = g;
      _profiles = p;
      _loading = false;
    });
  }

  bool get _canRunInApp => Platform.isAndroid || Platform.isIOS;

  Future<void> _connect(RdpProfile p) async {
    if (!_canRunInApp) {
      _snack('Die RDP-Sitzung läuft nur auf Tablet/Handy (In-App-Browser).',
          isError: true);
      return;
    }
    final gw = _gateway;
    if (gw == null || gw.isEmpty) {
      _snack('Bitte zuerst das Guacamole-Gateway einstellen.', isError: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final url = await _svc.requestSessionUrl(gw, p);
      if (!mounted) return;
      setState(() => _busy = false);
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RdpSessionScreen(sessionUrl: url, title: p.name),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('$e', isError: true);
    }
  }

  Future<void> _editGateway() async {
    final urlCtrl = TextEditingController(text: _gateway ?? RdpService.defaultGateway);
    final keyCtrl = TextEditingController(text: await _svc.getGatewayKey() ?? '');
    if (!mounted) return;
    var obscure = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Guacamole-Gateway'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: urlCtrl,
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Gateway-URL',
                    hintText: 'https://rdp.icd360s.de',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: keyCtrl,
                  obscureText: obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Gateway-Schlüssel',
                    hintText: 'X-Gateway-Key',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setSt(() => obscure = !obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Adresse + Schlüssel des separaten Guacamole-Servers (nicht der '
                  'App-Server). Muss per HTTPS erreichbar sein. Der Schlüssel sorgt '
                  'dafür, dass nur diese App verbinden darf.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Speichern')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _svc.setGateway(urlCtrl.text);
      await _svc.setGatewayKey(keyCtrl.text);
      await _load();
    }
  }

  Future<void> _editProfile({RdpProfile? existing}) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final host = TextEditingController(text: existing?.host ?? '');
    final port = TextEditingController(text: (existing?.port ?? RdpService.defaultRdpPort).toString());
    final user = TextEditingController(text: existing?.username ?? '');
    final pass = TextEditingController(text: existing?.password ?? '');
    var obscure = true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(existing == null ? 'Neue Verbindung' : 'Verbindung bearbeiten'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(name, 'Name', hint: 'z. B. Mint-Server'),
                _field(host, 'IP / Host', hint: '192.168.1.50', keyboard: TextInputType.url),
                _field(port, 'Port', hint: '9999', keyboard: TextInputType.number),
                _field(user, 'Benutzername'),
                TextField(
                  controller: pass,
                  obscureText: obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Passwort',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setSt(() => obscure = !obscure),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Speichern')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (host.text.trim().isEmpty) {
      _snack('IP / Host darf nicht leer sein.', isError: true);
      return;
    }
    final profile = RdpProfile(
      id: existing?.id ?? const Uuid().v4(),
      name: name.text.trim().isEmpty ? host.text.trim() : name.text.trim(),
      host: host.text.trim(),
      port: int.tryParse(port.text.trim()) ?? RdpService.defaultRdpPort,
      username: user.text.trim(),
      password: pass.text,
    );
    final list = [..._profiles];
    final idx = list.indexWhere((e) => e.id == profile.id);
    if (idx >= 0) {
      list[idx] = profile;
    } else {
      list.add(profile);
    }
    await _svc.saveProfiles(list);
    await _load();
  }

  Future<void> _deleteProfile(RdpProfile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Verbindung löschen?'),
        content: Text('„${p.name}" wird gelöscht.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _svc.saveProfiles(_profiles.where((e) => e.id != p.id).toList());
    await _load();
  }

  Widget _field(TextEditingController c, String label,
      {String? hint, TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: keyboard,
        autocorrect: false,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red.shade700 : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Remote Desktop (RDP)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.dns),
            tooltip: 'Gateway',
            onPressed: _editGateway,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editProfile(),
        icon: const Icon(Icons.add),
        label: const Text('Verbindung'),
      ),
      body: Stack(
        children: [
          _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    _gatewayBanner(),
                    Expanded(
                      child: _profiles.isEmpty
                          ? _empty()
                          : ListView.separated(
                              itemCount: _profiles.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (_, i) => _profileTile(_profiles[i]),
                            ),
                    ),
                  ],
                ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x66000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _gatewayBanner() {
    final set = _gateway != null && _gateway!.isNotEmpty;
    return Material(
      color: set ? Colors.green.withValues(alpha: 0.08) : Colors.orange.withValues(alpha: 0.12),
      child: ListTile(
        leading: Icon(Icons.dns, color: set ? Colors.green : Colors.orange),
        title: Text(set ? 'Gateway: $_gateway' : 'Kein Gateway eingestellt',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(set
            ? 'Guacamole-Server (separat)'
            : 'Tippen, um die Adresse des Guacamole-Servers einzutragen'),
        trailing: const Icon(Icons.edit, size: 18),
        onTap: _editGateway,
      ),
    );
  }

  Widget _profileTile(RdpProfile p) {
    return ListTile(
      leading: const Icon(Icons.desktop_windows),
      title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${p.username}@${p.host}:${p.port}'),
      onTap: () => _connect(p),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'connect') _connect(p);
          if (v == 'edit') _editProfile(existing: p);
          if (v == 'del') _deleteProfile(p);
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'connect', child: Text('Verbinden')),
          PopupMenuItem(value: 'edit', child: Text('Bearbeiten')),
          PopupMenuItem(value: 'del', child: Text('Löschen')),
        ],
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.desktop_windows, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('Noch keine Verbindungen.',
                style: TextStyle(color: Colors.grey), textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text('Mit „+ Verbindung" IP, Benutzer, Passwort und Port eintragen.',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
