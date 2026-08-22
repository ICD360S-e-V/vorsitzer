import 'dart:io';
import 'package:flutter/material.dart';
import '../services/update_service.dart';
import '../utils/app_farben.dart';

/// Update Available Dialog - prompts user to download and install update
class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;

  const UpdateDialog({super.key, required this.updateInfo});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.system_update, color: F.h(Colors.blue, 700)),
          const SizedBox(width: 12),
          const Text('Update verfügbar'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Eine neue Version ist verfügbar: ${widget.updateInfo.version}',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Aktuelle Version: ${UpdateService.currentVersion}',
              style: TextStyle(color: F.h(Colors.grey, 600), fontSize: 14),
            ),
            if (widget.updateInfo.changelog.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Änderungen:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: F.h(Colors.grey, 100),
                  borderRadius: BorderRadius.circular(8),
                ),
                constraints: const BoxConstraints(maxHeight: 150),
                child: SingleChildScrollView(
                  child: Text(
                    widget.updateInfo.changelog,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ],
            if (_isDownloading) ...[
              const SizedBox(height: 20),
              LinearProgressIndicator(value: _downloadProgress),
              const SizedBox(height: 8),
              Text(
                _downloadProgress < 1.0
                    ? 'Download: ${(_downloadProgress * 100).toStringAsFixed(0)}%'
                    : Platform.isAndroid ? 'APK wird installiert...' : 'Installation wird gestartet...',
                style: TextStyle(color: F.h(Colors.grey, 600)),
              ),
              const SizedBox(height: 8),
              Text(
                Platform.isAndroid
                    ? 'Bitte bestätigen Sie die Installation.'
                    : 'Die Anwendung wird automatisch neu gestartet.',
                style: TextStyle(
                  color: F.h(Colors.blue, 700),
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: F.h(Colors.red, 50),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: F.h(Colors.red, 200)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: F.h(Colors.red, 700)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: F.h(Colors.red, 700)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_isDownloading && !widget.updateInfo.forceUpdate)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Später'),
          ),
        if (!_isDownloading)
          ElevatedButton.icon(
            onPressed: _downloadAndInstall,
            icon: const Icon(Icons.download),
            label: const Text('Jetzt aktualisieren'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
            ),
          ),
        if (_isDownloading)
          TextButton(
            onPressed: null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: F.h(Colors.blue, 700),
                  ),
                ),
                const SizedBox(width: 8),
                const Text('Wird heruntergeladen...'),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _downloadAndInstall() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _errorMessage = null;
    });

    final updateService = UpdateService();
    final installerPath = await updateService.downloadUpdate(
      widget.updateInfo,
      (progress) {
        setState(() => _downloadProgress = progress);
      },
    );

    if (installerPath != null) {
      final started = await updateService.launchInstaller(installerPath);
      // On Android, close dialog - system handles APK installation
      if (Platform.isAndroid && mounted) {
        Navigator.pop(context);
      } else if (!started && mounted) {
        // Desktop: a successful install never returns here (the app exits), so
        // reaching this point means the installer could not be started. Drop
        // the spinner instead of leaving it running forever.
        setState(() {
          _isDownloading = false;
          _errorMessage = 'Update konnte nicht installiert werden. '
              'Bitte laden Sie die neue Version manuell herunter.';
        });
      }
    } else {
      setState(() {
        _isDownloading = false;
        _errorMessage = 'Download fehlgeschlagen. Bitte versuchen Sie es später erneut.';
      });
    }
  }
}

/// Shows update dialog if update is available
Future<void> checkAndShowUpdateDialog(BuildContext context) async {
  final updateService = UpdateService();
  final updateInfo = await updateService.checkForUpdate();

  if (updateInfo != null && context.mounted) {
    showDialog(
      context: context,
      barrierDismissible: !updateInfo.forceUpdate,
      builder: (context) => UpdateDialog(updateInfo: updateInfo),
    );
  }
}
