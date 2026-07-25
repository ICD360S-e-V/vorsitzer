import 'package:flutter/material.dart';

import '../services/api_service.dart';

/// Signatur des eigenen Postfachs bearbeiten. Sie wird beim Verfassen
/// automatisch unter die Nachricht gesetzt.
class MailSignatureScreen extends StatefulWidget {
  final String mailboxAddress;

  const MailSignatureScreen({super.key, required this.mailboxAddress});

  @override
  State<MailSignatureScreen> createState() => _MailSignatureScreenState();
}

class _MailSignatureScreenState extends State<MailSignatureScreen> {
  final _api = ApiService();
  final _ctrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _receiptDefault = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await _api.getMailSignature();
      if (!mounted) return;
      if (res['success'] == true) {
        _ctrl.text = '${res['signature'] ?? ''}';
        _receiptDefault = res['request_receipt_default'] == true;
      } else {
        _error = res['message']?.toString() ?? 'Signatur konnte nicht geladen werden.';
      }
    } catch (_) {
      _error = 'Keine Verbindung zum Server.';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final res = await _api.saveMailSignature(
        signature: _ctrl.text,
        requestReceiptDefault: _receiptDefault,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      if (res['success'] == true) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Signatur gespeichert')));
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(res['message']?.toString() ?? 'Speichern fehlgeschlagen.')));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Keine Verbindung zum Server.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Signatur'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: 'Speichern',
              onPressed: _loading ? null : _save,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null) ...[
                  Text(_error!, style: TextStyle(color: cs.error)),
                  const SizedBox(height: 12),
                ],
                Text(
                  'Diese Signatur steht unter jeder E-Mail von ${widget.mailboxAddress}.',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ctrl,
                  minLines: 8,
                  maxLines: 20,
                  maxLength: 4000,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    labelText: 'Signaturtext',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _receiptDefault,
                  onChanged: (v) => setState(() => _receiptDefault = v),
                  title: const Text('Lesebestätigung immer anfordern',
                      style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                    'Neue E-Mails starten mit aktivierter Lesebestätigung.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
    );
  }
}
