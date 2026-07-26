import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/secure_cloud_service.dart';

/// Fragt die Passphrase der verschlüsselten Cloud ab, sobald die App startet.
///
/// Die Cloud ist Zero-Knowledge: der Schlüssel entsteht aus der Passphrase und
/// lebt nur im Arbeitsspeicher. Der Server kann nichts entschlüsseln und daher
/// auch nichts von sich aus dort ablegen — Anhänge automatisch zu archivieren
/// geht nur, solange die Sitzung offen ist.
///
/// Deshalb einmal beim Start fragen, dann bleibt sie offen, bis die App
/// beendet wird. Beim nächsten Start wird wieder gefragt.
class CloudUnlockDialog extends StatefulWidget {
  const CloudUnlockDialog({super.key, required this.service});

  final SecureCloudService service;

  /// Sorgt dafür, dass die Cloud-Sitzung offen ist, und fragt nur, wenn nötig.
  ///
  /// Gibt `false` zurück, wenn abgebrochen wurde, keine Cloud eingerichtet ist
  /// oder der Server nicht erreichbar war. Der Aufrufer soll das nicht als
  /// Fehler behandeln: ohne Cloud läuft der Rest der App unverändert weiter.
  static Future<bool> ensureUnlocked(
    BuildContext context,
    ApiService api,
    String mitgliedernummer,
  ) async {
    final svc = SecureCloudService(api, mitgliedernummer);
    if (svc.isUnlocked) return true;

    // Android kann den Prozess beenden, während eine fremde Activity oben ist
    // (Kamera, Dateiwahl). Dafür gibt es das kurzlebige Resume-Token — es zählt
    // als dieselbe Sitzung, also hier zuerst versuchen, statt erneut zu fragen.
    if (await svc.tryResume()) return true;

    // Wer keine Cloud eingerichtet hat, soll bei jedem Start nicht mit einer
    // Passphrase-Abfrage begrüßt werden. Bei Netzfehler (null) ebenso wenig.
    if (await svc.hasCloud() != true) return false;
    if (!context.mounted) return false;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CloudUnlockDialog(service: svc),
    );
    return ok == true;
  }

  @override
  State<CloudUnlockDialog> createState() => _CloudUnlockDialogState();
}

class _CloudUnlockDialogState extends State<CloudUnlockDialog> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pass = _ctrl.text;
    if (pass.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await widget.service.unlock(pass);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      // Das Feld leeren, aber den Fokus behalten: nach einem Vertipper will man
      // sofort weitertippen, nicht erst wieder hineinklicken.
      _ctrl.clear();
      _focus.requestFocus();
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(Icons.lock_outline, color: cs.primary),
      title: const Text('Verschlüsselte Cloud entsperren'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Solange die Cloud offen ist, werden Anhänge aus E-Mails '
            'automatisch dort gesichert. Beim Beenden der App wird sie wieder '
            'gesperrt.',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            focusNode: _focus,
            autofocus: true,
            obscureText: _obscure,
            enabled: !_busy,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Passphrase',
              errorText: _error,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                tooltip: _obscure ? 'Anzeigen' : 'Verbergen',
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Später'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Entsperren'),
        ),
      ],
    );
  }
}
