import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/diagnostic_service.dart';

/// Dialog to ask user for diagnostic consent
class DiagnosticConsentDialog extends StatelessWidget {
  const DiagnosticConsentDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.analytics_outlined, color: Colors.blue.shade700),
          const SizedBox(width: 12),
          const Text('Diagnose-Daten'),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 450),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Möchten Sie uns helfen, die App zu verbessern?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow(Icons.check_circle, 'Anonyme Nutzungsstatistiken'),
                  const SizedBox(height: 8),
                  _buildInfoRow(Icons.check_circle, 'Fehlermeldungen zur Verbesserung'),
                  const SizedBox(height: 8),
                  _buildInfoRow(Icons.check_circle, 'App-Performance-Daten'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.security, color: Colors.green.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Keine persönlichen Daten werden gesammelt. Diese Einstellung kann jederzeit geändert werden.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _handleResponse(context, false),
          child: const Text('Nein, danke'),
        ),
        ElevatedButton.icon(
          onPressed: () => _handleResponse(context, true),
          icon: const Icon(Icons.check),
          label: const Text('Ja, aktivieren'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue.shade700,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: Colors.blue.shade700, size: 18),
        const SizedBox(width: 8),
        Flexible(child: Text(text, style: const TextStyle(fontSize: 14))),
      ],
    );
  }

  Future<void> _handleResponse(BuildContext context, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('diagnostic_asked', true);
    await prefs.setBool('diagnostic_enabled', enabled);

    if (enabled) {
      DiagnosticService().start();
    }

    if (context.mounted) {
      Navigator.of(context).pop(enabled);
    }
  }
}

/// Check if diagnostic consent dialog should be shown
Future<bool> shouldShowDiagnosticConsent() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('diagnostic_asked') != true;
}

/// Check if diagnostics are enabled
Future<bool> isDiagnosticEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('diagnostic_enabled') ?? false;
}

/// Show diagnostic consent dialog if not already asked
Future<void> checkAndShowDiagnosticConsent(BuildContext context) async {
  if (await shouldShowDiagnosticConsent()) {
    if (context.mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const DiagnosticConsentDialog(),
      );
    }
  } else {
    // Already asked - start service if enabled
    if (await isDiagnosticEnabled()) {
      DiagnosticService().start();
    }
  }
}
