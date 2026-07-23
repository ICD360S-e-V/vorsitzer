import 'dart:io';
import 'package:flutter/material.dart';
import '../services/rdp_service.dart';
import 'rdp_session_screen.dart';

/// Remote Desktop (RDP via Guacamole). Connection profiles are stored SERVER-SIDE
/// (encrypted in MariaDB, per-admin) and synced across the admin's devices. The
/// password never lives on the device; the connect is done server-side. Runs
/// in-app on Android, iOS and macOS (WebView); other desktops are not supported.
class RemoteDesktopScreen extends StatefulWidget {
  final String mitgliedernummer;
  const RemoteDesktopScreen({super.key, required this.mitgliedernummer});

  @override
  State<RemoteDesktopScreen> createState() => _RemoteDesktopScreenState();
}

class _RemoteDesktopScreenState extends State<RemoteDesktopScreen> {
  final RdpService _svc = RdpService();
  List<RdpProfile> _profiles = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await _svc.loadProfiles(widget.mitgliedernummer);
      if (!mounted) return;
      setState(() {
        _profiles = p;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  bool get _canRunInApp => Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  Future<void> _connect(RdpProfile p) async {
    if (!_canRunInApp) {
      _snack('Die RDP-Sitzung läuft auf Tablet, Handy und macOS.', isError: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final url = await _svc.requestSessionUrl(widget.mitgliedernummer, p.id);
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

  Future<void> _editProfile({RdpProfile? existing}) async {
    final isNew = existing == null;
    final name = TextEditingController(text: existing?.name ?? '');
    final host = TextEditingController(text: existing?.host ?? '');
    final port = TextEditingController(text: (existing?.port ?? RdpService.defaultRdpPort).toString());
    final user = TextEditingController(text: existing?.username ?? '');
    final pass = TextEditingController();
    var obscure = true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(isNew ? 'Neue Verbindung' : 'Verbindung bearbeiten'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(name, 'Name', hint: 'z. B. Mint-Server'),
                _field(host, 'IP / Host', hint: '192.168.1.50', keyboard: TextInputType.url),
                _field(port, 'Port', hint: '31456', keyboard: TextInputType.number),
                _field(user, 'Benutzername'),
                TextField(
                  controller: pass,
                  obscureText: obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Passwort',
                    hintText: isNew ? null : 'Leer lassen = unverändert',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setSt(() => obscure = !obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Gespeichert wird verschlüsselt auf dem Server — das Passwort '
                  'verlässt nie das Gerät und wird nie zurückgegeben.',
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
    if (ok != true) return;
    if (host.text.trim().isEmpty) {
      _snack('IP / Host darf nicht leer sein.', isError: true);
      return;
    }

    // On edit, an empty password means "keep the stored one" (send null).
    final pw = pass.text;
    final String? passwordArg = isNew ? pw : (pw.isEmpty ? null : pw);

    setState(() => _busy = true);
    final err = await _svc.saveProfile(
      widget.mitgliedernummer,
      id: existing?.id,
      name: name.text.trim().isEmpty ? host.text.trim() : name.text.trim(),
      host: host.text.trim(),
      port: int.tryParse(port.text.trim()) ?? RdpService.defaultRdpPort,
      username: user.text.trim(),
      password: passwordArg,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      _snack(err, isError: true);
      return;
    }
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
    setState(() => _busy = true);
    final err = await _svc.deleteProfile(widget.mitgliedernummer, p.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      _snack(err, isError: true);
      return;
    }
    await _load();
  }

  Widget _field(TextEditingController c, String label, {String? hint, TextInputType? keyboard}) {
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
            icon: const Icon(Icons.refresh),
            tooltip: 'Aktualisieren',
            onPressed: _loading ? null : _load,
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
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            _errorView()
          else if (_profiles.isEmpty)
            _empty()
          else
            RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                itemCount: _profiles.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) => _profileTile(_profiles[i]),
              ),
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

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(_error ?? '', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Erneut')),
          ],
        ),
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
