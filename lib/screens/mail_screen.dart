import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// In-App E-Mail Postfach (icd@icd360s.de) für den Vorsitzer.
/// Liest/sendet über icd360sev -> mail.icd360s.de (mTLS, mail_crypt).
class MailScreen extends StatefulWidget {
  final String mitgliedernummer;
  final String userName;
  final String email;

  const MailScreen({
    super.key,
    required this.mitgliedernummer,
    required this.userName,
    required this.email,
  });

  @override
  State<MailScreen> createState() => _MailScreenState();
}

class _MailScreenState extends State<MailScreen> {
  final _api = ApiService();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _messages = [];
  String _quotaLabel = '';

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
      final res = await _api.getMailInbox(limit: 100);
      if (res['success'] == true) {
        _messages = List<Map<String, dynamic>>.from(res['messages'] ?? []);
      } else {
        _error = res['message']?.toString() ?? 'Fehler beim Laden';
      }
    } catch (e) {
      _error = 'Verbindungsfehler';
    }
    _loadQuota();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadQuota() async {
    try {
      final res = await _api.getMailQuota();
      final quota = (res['quota'] as List?) ?? [];
      for (final q in quota) {
        if (q is Map && q['type'] == 'STORAGE') {
          final usedKb = double.tryParse('${q['value']}') ?? 0;
          final limitKb = double.tryParse('${q['limit']}') ?? 0;
          final usedMb = (usedKb / 1024).toStringAsFixed(usedKb < 1024 ? 1 : 0);
          final limitMb = limitKb > 0 ? (limitKb / 1024 / 1024).toStringAsFixed(0) : '∞';
          if (mounted) setState(() => _quotaLabel = '$usedMb MB / $limitMb GB');
        }
      }
    } catch (_) {/* quota is non-critical */}
  }

  int get _unread => _messages.where((m) => m['seen'] != true).length;

  Future<void> _openMessage(Map<String, dynamic> msg) async {
    final uid = (msg['uid'] as num?)?.toInt() ?? 0;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _MessageDetailScreen(uid: uid, selfEmail: widget.email),
    ));
    // returning from detail: refresh flags/list
    _load();
  }

  Future<void> _compose({String? to, String? subject}) async {
    final sent = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _ComposeScreen(selfEmail: widget.email, to: to, subject: subject),
    ));
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('E-Mail gesendet')),
      );
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('E-Mail'),
            Text(
              widget.email + (_quotaLabel.isNotEmpty ? '  ·  $_quotaLabel' : ''),
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Aktualisieren',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _compose(),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Neue E-Mail'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(_error!),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Erneut versuchen'),
            ),
          ],
        ),
      );
    }
    if (_messages.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Center(child: Text('Keine Nachrichten')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: Column(
        children: [
          if (_unread > 0)
            Container(
              width: double.infinity,
              color: Colors.blue.withValues(alpha: 0.08),
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              child: Text('$_unread ungelesen',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          Expanded(
            child: ListView.separated(
              itemCount: _messages.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final m = _messages[i];
                final seen = m['seen'] == true;
                final from = _displayName('${m['from'] ?? ''}');
                final subject = '${m['subject'] ?? '(kein Betreff)'}';
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: seen ? Colors.grey.shade300 : Colors.blue,
                    child: Text(
                      from.isNotEmpty ? from[0].toUpperCase() : '?',
                      style: TextStyle(color: seen ? Colors.black54 : Colors.white),
                    ),
                  ),
                  title: Text(
                    from,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: seen ? FontWeight.normal : FontWeight.bold),
                  ),
                  subtitle: Text(
                    subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: seen ? FontWeight.normal : FontWeight.w600),
                  ),
                  trailing: Text(
                    _shortDate('${m['date'] ?? ''}'),
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  onTap: () => _openMessage(m),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- helpers ----------------

String _extractEmail(String raw) {
  final m = RegExp(r'<([^>]+)>').firstMatch(raw);
  if (m != null) return m.group(1)!.trim();
  return raw.trim();
}

String _displayName(String raw) {
  final m = RegExp(r'^\s*"?([^"<]+?)"?\s*<').firstMatch(raw);
  if (m != null && m.group(1)!.trim().isNotEmpty) return m.group(1)!.trim();
  return _extractEmail(raw);
}

String _shortDate(String raw) {
  // API date is like "2026-07-24 13:25:22"; show date + HH:MM.
  if (raw.length >= 16 && raw.contains('-')) {
    return raw.substring(5, 16).replaceFirst(' ', '  ');
  }
  return raw.length > 16 ? raw.substring(0, 16) : raw;
}

// ---------------- message detail ----------------

class _MessageDetailScreen extends StatefulWidget {
  final int uid;
  final String selfEmail;
  const _MessageDetailScreen({required this.uid, required this.selfEmail});

  @override
  State<_MessageDetailScreen> createState() => _MessageDetailScreenState();
}

class _MessageDetailScreenState extends State<_MessageDetailScreen> {
  final _api = ApiService();
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _msg = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await _api.getMailMessage(widget.uid);
      if (res['success'] == true) {
        _msg = Map<String, dynamic>.from(res['message_data'] ?? {});
        _api.flagMail(widget.uid, seen: true); // mark read (fire-and-forget)
      } else {
        _error = res['message']?.toString() ?? 'Fehler';
      }
    } catch (e) {
      _error = 'Verbindungsfehler';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('In den Papierkorb?'),
        content: const Text('Diese Nachricht in den Papierkorb verschieben?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true) return;
    final res = await _api.deleteMail(widget.uid);
    if (!mounted) return;
    if (res['success'] == true) {
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message']?.toString() ?? 'Löschen fehlgeschlagen')),
      );
    }
  }

  void _reply() {
    final from = '${_msg['from'] ?? ''}';
    final subject = '${_msg['subject'] ?? ''}';
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _ComposeScreen(
        selfEmail: widget.selfEmail,
        to: _extractEmail(from),
        subject: subject.startsWith('Re:') ? subject : 'Re: $subject',
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final subject = '${_msg['subject'] ?? '(kein Betreff)'}';
    final body = '${_msg['text'] ?? ''}'.trim().isNotEmpty
        ? '${_msg['text']}'
        : _stripHtml('${_msg['html'] ?? ''}');
    final attachments = (_msg['attachments'] as List?) ?? [];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nachricht'),
        actions: [
          IconButton(icon: const Icon(Icons.reply), tooltip: 'Antworten', onPressed: _loading ? null : _reply),
          IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Löschen', onPressed: _loading ? null : _delete),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(subject, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _kv('Von', '${_msg['from'] ?? ''}'),
                    _kv('An', '${_msg['to'] ?? ''}'),
                    if ('${_msg['date'] ?? ''}'.isNotEmpty) _kv('Datum', '${_msg['date']}'),
                    const Divider(height: 24),
                    SelectableText(body, style: const TextStyle(fontSize: 15, height: 1.4)),
                    if (attachments.isNotEmpty) ...[
                      const Divider(height: 24),
                      const Text('Anhänge', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      ...attachments.map((a) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.attach_file),
                            title: Text('${a['name'] ?? 'Anhang'}'),
                            subtitle: Text(_fmtSize((a['size'] as num?)?.toInt() ?? 0)),
                          )),
                    ],
                  ],
                ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 52, child: Text(k, style: const TextStyle(color: Colors.grey, fontSize: 13))),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );
}

String _stripHtml(String html) =>
    html.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

String _fmtSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

// ---------------- compose ----------------

class _ComposeScreen extends StatefulWidget {
  final String selfEmail;
  final String? to;
  final String? subject;
  const _ComposeScreen({required this.selfEmail, this.to, this.subject});

  @override
  State<_ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<_ComposeScreen> {
  final _api = ApiService();
  final _toCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _toCtrl.text = widget.to ?? '';
    _subjectCtrl.text = widget.subject ?? '';
  }

  @override
  void dispose() {
    _toCtrl.dispose();
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  bool _validEmail(String s) =>
      RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(s.trim());

  Future<void> _send() async {
    final to = _toCtrl.text.trim();
    if (!_validEmail(to)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte eine gültige Empfänger-Adresse eingeben')),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      final res = await _api.sendMail(
        to: to,
        subject: _subjectCtrl.text.trim(),
        body: _bodyCtrl.text,
      );
      if (!mounted) return;
      if (res['success'] == true) {
        Navigator.pop(context, true);
      } else {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['message']?.toString() ?? 'Senden fehlgeschlagen')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verbindungsfehler')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Neue E-Mail'),
        actions: [
          _sending
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : IconButton(icon: const Icon(Icons.send), tooltip: 'Senden', onPressed: _send),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Von: ${widget.selfEmail}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 8),
          TextField(
            controller: _toCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'An', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _subjectCtrl,
            decoration: const InputDecoration(labelText: 'Betreff', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bodyCtrl,
            minLines: 8,
            maxLines: 20,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              labelText: 'Nachricht',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}
