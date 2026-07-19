import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import 'file_viewer_dialog.dart';

/// Reusable "Aus Cloud wählen" picker — Stage 2 of the member-cloud feature.
///
/// Shows the member's permanent cloud documents with multi-select (+ "select
/// all"), so an admin can attach files to any destination straight from the
/// cloud — the file is then copied server-to-server, never touching the PC.
///
/// Returns the list of selected `cloud_file_id`s, or null if cancelled.
Future<List<int>?> showCloudFilePicker(
  BuildContext context, {
  required ApiService apiService,
  required int memberId,
  required String mitgliedernummer,
}) {
  return showDialog<List<int>>(
    context: context,
    builder: (_) => _CloudFilePickerDialog(
      apiService: apiService,
      memberId: memberId,
      mitgliedernummer: mitgliedernummer,
    ),
  );
}

class _CloudFilePickerDialog extends StatefulWidget {
  final ApiService apiService;
  final int memberId;
  final String mitgliedernummer;

  const _CloudFilePickerDialog({
    required this.apiService,
    required this.memberId,
    required this.mitgliedernummer,
  });

  @override
  State<_CloudFilePickerDialog> createState() => _CloudFilePickerDialogState();
}

class _CloudFilePickerDialogState extends State<_CloudFilePickerDialog> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _files = [];
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.apiService.listMemberCloud(
      mitgliedernummer: widget.mitgliedernummer,
      memberId: widget.memberId,
    );
    if (!mounted) return;
    if (r['success'] == true) {
      setState(() {
        _files = List<Map<String, dynamic>>.from(r['files'] ?? []);
        _loading = false;
      });
    } else {
      setState(() {
        _error = r['message']?.toString() ?? 'Cloud konnte nicht geladen werden';
        _loading = false;
      });
    }
  }

  String _fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  IconData _icon(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'png':
      case 'jpg':
      case 'jpeg':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  /// Preview a cloud file before selecting it (download -> temp -> viewer).
  Future<void> _preview(Map<String, dynamic> f) async {
    final id = (f['id'] as num).toInt();
    final name = f['filename']?.toString() ?? 'datei';
    final r = await widget.apiService.downloadCloudFile(
      cloudFileId: id,
      mitgliedernummer: widget.mitgliedernummer,
    );
    if (!mounted) return;
    if (r['success'] == true && r['content'] != null) {
      final bytes = base64Decode(r['content']);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(bytes);
      if (mounted) await FileViewerDialog.show(context, file.path, name);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r['message']?.toString() ?? 'Vorschau fehlgeschlagen'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  void _toggleAll() {
    setState(() {
      if (_selected.length == _files.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(_files.map((f) => (f['id'] as num).toInt()));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final allSelected = _files.isNotEmpty && _selected.length == _files.length;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.cloud, color: Colors.blue.shade600),
          const SizedBox(width: 8),
          const Expanded(child: Text('Aus Cloud wählen', style: TextStyle(fontSize: 17))),
          if (_files.isNotEmpty)
            TextButton(
              onPressed: _toggleAll,
              child: Text(allSelected ? 'Keine' : 'Alle'),
            ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      content: SizedBox(
        width: 460,
        height: 420,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, style: TextStyle(color: Colors.red.shade600)))
                : _files.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.cloud_off, size: 44, color: Colors.grey.shade300),
                            const SizedBox(height: 8),
                            Text('Keine Dateien im Cloud dieses Mitglieds',
                                style: TextStyle(color: Colors.grey.shade600)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: _files.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final f = _files[i];
                          final id = (f['id'] as num).toInt();
                          final ext = f['extension']?.toString() ?? '';
                          final size = (f['size'] as num?)?.toInt() ?? 0;
                          final checked = _selected.contains(id);
                          return CheckboxListTile(
                            value: checked,
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Row(
                              children: [
                                Icon(_icon(ext), size: 18, color: Colors.blueGrey.shade600),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    f['filename']?.toString() ?? 'Datei',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(left: 26),
                              child: Text(_fmtBytes(size), style: const TextStyle(fontSize: 11)),
                            ),
                            secondary: IconButton(
                              icon: Icon(Icons.visibility_outlined, size: 20, color: Colors.indigo.shade400),
                              tooltip: 'Ansehen',
                              onPressed: () => _preview(f),
                            ),
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                _selected.add(id);
                              } else {
                                _selected.remove(id);
                              }
                            }),
                          );
                        },
                      ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        ElevatedButton.icon(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop(_selected.toList()),
          icon: const Icon(Icons.check, size: 18),
          label: Text('Übernehmen (${_selected.length})'),
        ),
      ],
    );
  }
}
