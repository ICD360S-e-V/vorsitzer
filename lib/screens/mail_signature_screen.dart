import 'package:flutter/material.dart';

import '../services/api_service.dart';

/// Signatur des eigenen Postfachs.
///
/// Normalfall ist die AUTOMATISCH erzeugte Signatur: Name, Amt und Telefonnummer
/// der angemeldeten Person plus die Pflichtangaben des Vereins, alles aus der
/// Datenbank. Melden sich Vorsitzer 1 und 2 abwechselnd an, stimmt die Signatur
/// dadurch immer mit dem Absender überein, und ein Wechsel im Vorstand oder eine
/// neue Registernummer wird an einer Stelle gepflegt statt in einem Textblock.
///
/// Eine eigene Fassung ist möglich, friert dann aber genau diese Synchronisierung
/// ein — deshalb sagt der Bildschirm das auch.
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

  /// Die serverseitig erzeugte Fassung, zum Vergleich und zum Zurücksetzen.
  String _generated = '';

  /// Es gilt gerade die automatische Fassung.
  bool _usesGenerated = true;

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

  bool get _isEdited => _ctrl.text.trim() != _generated.trim();

  Future<void> _load() async {
    try {
      final res = await _api.getMailSignature();
      if (!mounted) return;
      if (res['success'] == true) {
        _apply(res);
      } else {
        _error = res['message']?.toString() ?? 'Signatur konnte nicht geladen werden.';
      }
    } catch (_) {
      _error = 'Keine Verbindung zum Server.';
    }
    if (mounted) setState(() => _loading = false);
  }

  void _apply(Map<String, dynamic> res) {
    _ctrl.text = '${res['signature'] ?? ''}';
    _generated = '${res['signature_generated'] ?? ''}';
    _usesGenerated = res['uses_generated'] != false;
    _receiptDefault = res['request_receipt_default'] == true;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final res = await _api.saveMailSignature(
        signature: _ctrl.text,
        requestReceiptDefault: _receiptDefault,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        if (res['success'] == true) _apply(res);
      });
      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_usesGenerated
              ? 'Gespeichert — die Signatur bleibt automatisch'
              : 'Eigene Signatur gespeichert'),
        ));
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

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Auf automatisch zurücksetzen?'),
        content: const Text(
            'Die eigene Fassung wird verworfen. Danach wird die Signatur wieder '
            'aus den Vereinsdaten und der angemeldeten Person gebaut.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('Zurücksetzen')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      final res = await _api.resetMailSignature();
      if (!mounted) return;
      setState(() {
        _saving = false;
        if (res['success'] == true) _apply(res);
      });
    } catch (_) {
      if (mounted) setState(() => _saving = false);
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
                _statusCard(cs),
                const SizedBox(height: 12),
                TextField(
                  controller: _ctrl,
                  minLines: 12,
                  maxLines: 24,
                  maxLength: 4000,
                  keyboardType: TextInputType.multiline,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Signaturtext',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                if (!_usesGenerated || _isEdited)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _saving ? null : _reset,
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: const Text('Wieder automatisch erzeugen'),
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

  Widget _statusCard(ColorScheme cs) {
    final auto = _usesGenerated && !_isEdited;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: auto
            ? const Color(0xFF2E9E4F).withValues(alpha: 0.10)
            : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(auto ? Icons.autorenew : Icons.edit_outlined,
                  size: 18,
                  color: auto ? const Color(0xFF2E9E4F) : cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  auto ? 'Wird automatisch erzeugt' : 'Eigene Fassung',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            auto
                ? 'Name, Amt und Telefonnummer kommen von der angemeldeten Person, '
                    'die Pflichtangaben aus den Vereinsdaten. Meldet sich ein anderes '
                    'Vorstandsmitglied an, stimmt die Signatur automatisch.'
                : 'Diese Fassung ist eingefroren: ein Wechsel im Vorstand, eine neue '
                    'Registernummer oder eine andere angemeldete Person ändern sie '
                    'nicht mehr mit.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          Text(
            'Postfach: ${widget.mailboxAddress}',
            style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
