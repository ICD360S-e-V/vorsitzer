import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ChangelogDialog extends StatefulWidget {
  const ChangelogDialog({super.key});

  @override
  State<ChangelogDialog> createState() => _ChangelogDialogState();
}

class _ChangelogDialogState extends State<ChangelogDialog> {
  final _apiService = ApiService();
  bool _isLoading = true;
  String? _errorMessage;
  List<ChangelogVersion> _versions = [];

  @override
  void initState() {
    super.initState();
    _loadChangelog();
  }

  Future<void> _loadChangelog() async {
    try {
      final result = await _apiService.getChangelog();

      if (mounted) {
        if (result['success'] == true) {
          final versions = (result['versions'] as List)
              .map((v) => ChangelogVersion.fromJson(v))
              .toList();

          setState(() {
            _versions = versions;
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = result['message'] ?? 'Fehler beim Laden';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Verbindungsfehler: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.history, color: Colors.blue.shade700),
          const SizedBox(width: 12),
          const Text('Änderungsprotokoll'),
        ],
      ),
      content: SizedBox(
        width: 450,
        child: _isLoading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(48),
                  child: CircularProgressIndicator(),
                ),
              )
            : _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, size: 48, color: Colors.red),
                          const SizedBox(height: 16),
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                _isLoading = true;
                                _errorMessage = null;
                              });
                              _loadChangelog();
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Erneut versuchen'),
                          ),
                        ],
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: _versions
                          .map((version) => _buildVersionEntry(
                                version.version,
                                version.date,
                                version.changes,
                                isLatest: version.isLatest,
                              ))
                          .toList(),
                    ),
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Schließen'),
        ),
      ],
    );
  }

  Widget _buildVersionEntry(
    String version,
    String date,
    List<String> changes, {
    bool isLatest = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isLatest ? Colors.blue.shade50 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLatest ? Colors.blue.shade200 : Colors.grey.shade300,
          width: isLatest ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                version,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isLatest ? Colors.blue.shade800 : Colors.black87,
                ),
              ),
              const SizedBox(width: 8),
              if (isLatest)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'AKTUELL',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const Spacer(),
              Text(
                date,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...changes.map(
            (change) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• ',
                    style: TextStyle(
                      color: isLatest ? Colors.blue.shade700 : Colors.grey.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      change,
                      style: TextStyle(
                        color: Colors.grey.shade800,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ChangelogVersion {
  final String version;
  final String date;
  final List<String> changes;
  final bool isLatest;

  ChangelogVersion({
    required this.version,
    required this.date,
    required this.changes,
    required this.isLatest,
  });

  factory ChangelogVersion.fromJson(Map<String, dynamic> json) {
    return ChangelogVersion(
      version: json['version'] as String,
      date: json['date'] as String,
      changes: (json['changes'] as List).map((e) => e as String).toList(),
      isLatest: json['is_latest'] as bool? ?? false,
    );
  }
}
