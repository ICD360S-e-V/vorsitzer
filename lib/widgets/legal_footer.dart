import 'dart:async';
import 'dart:math' show pi;
import 'package:flutter/material.dart';
import '../screens/webview_screen.dart';
import '../services/update_service.dart';
import '../services/logger_service.dart';
import 'debug_console.dart';
import 'update_dialog.dart';
import 'changelog.dart';

class LegalFooter extends StatefulWidget {
  final bool darkMode;

  const LegalFooter({
    super.key,
    this.darkMode = false,
  });

  @override
  State<LegalFooter> createState() => _LegalFooterState();
}

class _LegalFooterState extends State<LegalFooter> with SingleTickerProviderStateMixin {
  final _log = LoggerService();
  bool _isChecking = false;
  Timer? _autoCheckTimer;
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );

    // Start auto-check timer (every 5 minutes)
    _autoCheckTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (!mounted) return;
      _checkForUpdates(silent: true);
    });
  }

  @override
  void dispose() {
    _autoCheckTimer?.cancel();
    _rotationController.dispose();
    super.dispose();
  }

  Future<void> _checkForUpdates({bool silent = false}) async {
    if (_isChecking) return;

    setState(() => _isChecking = true);
    _rotationController.repeat();

    if (!silent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              const Text('Suche nach Updates...'),
            ],
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.blue.shade700,
        ),
      );
    }

    _log.info('Checking for updates...', tag: 'UPDATE');

    try {
      final updateService = UpdateService();
      final updateInfo = await updateService.checkForUpdate();

      if (!mounted) return;

      _rotationController.stop();
      _rotationController.reset();
      setState(() => _isChecking = false);

      if (updateInfo != null) {
        _log.info('Update available: ${updateInfo.version}', tag: 'UPDATE');
        // Show update dialog
        showDialog(
          context: context,
          barrierDismissible: !updateInfo.forceUpdate,
          builder: (context) => UpdateDialog(updateInfo: updateInfo),
        );
      } else if (!silent && mounted) {
        _log.info('No updates available', tag: 'UPDATE');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                const Text('Die App ist auf dem neuesten Stand'),
              ],
            ),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.green.shade600,
          ),
        );
      }
    } catch (e) {
      _log.error('Update check failed: $e', tag: 'UPDATE');
      if (!mounted) return;

      _rotationController.stop();
      _rotationController.reset();
      setState(() => _isChecking = false);

      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                const Text('Fehler bei der Update-Prüfung'),
              ],
            ),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  void _showChangelog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const ChangelogDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.darkMode ? Colors.grey.shade400 : Colors.grey.shade600;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: widget.darkMode ? const Color(0xFF1a1a2e) : Colors.grey.shade100,
        border: Border(
          top: BorderSide(
            color: widget.darkMode ? Colors.grey.shade800 : Colors.grey.shade300,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('© 2025 - ${DateTime.now().year} ICD360S e.V', style: TextStyle(fontSize: 11, color: textColor)),
                ],
              ),
            ),
          ),
          InkWell(
            onTap: () => _showChangelog(context),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                'v${UpdateService.currentVersion}',
                style: TextStyle(
                  color: textColor,
                  fontSize: 11,
                  decoration: TextDecoration.underline,
                  decorationColor: textColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Update check button
          Tooltip(
            message: 'Nach Updates suchen',
            child: InkWell(
              onTap: _isChecking ? null : () => _checkForUpdates(silent: false),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: AnimatedBuilder(
                  animation: _rotationController,
                  builder: (context, child) {
                    return Transform.rotate(
                      angle: _rotationController.value * 2 * pi,
                      child: Icon(
                        Icons.refresh,
                        size: 16,
                        color: _isChecking ? Colors.blue.shade600 : textColor,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => showDebugConsole(context),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                '>_',
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Consolas',
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Website link
          Tooltip(
            message: 'icd360s.de',
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const WebViewScreen(
                      title: 'ICD360S e.V.',
                      url: 'https://icd360s.de',
                    ),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Icon(
                  Icons.language,
                  size: 16,
                  color: textColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

}
