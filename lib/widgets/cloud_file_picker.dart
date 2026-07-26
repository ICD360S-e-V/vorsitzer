import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import '../services/global_chat_service.dart';
import '../services/secure_cloud_service.dart';
import 'file_viewer_dialog.dart';

/// Convenience wrapper: open the cloud picker (admin mitgliedernummer taken
/// from GlobalChatService) and attach each selected file via [attach].
/// Returns (ok, total) counts, or null if cancelled / nothing selected.
Future<({int ok, int total})?> pickAndAttachFromCloud(
  BuildContext context, {
  required ApiService apiService,
  required int memberId,
  required Future<Map<String, dynamic>> Function(int cloudFileId) attach,
  /// Optional: höchstens so viele Dateien übernehmen. Der Picker erlaubt
  /// weiterhin jede Mehrfachauswahl — was darüber liegt, wird verworfen und
  /// dem Nutzer gemeldet, statt ein Ziellimit still zu überschreiten.
  int? maxFiles,
}) async {
  final mnr = GlobalChatService().currentMitgliedernummer;
  if (mnr == null || mnr.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Kein Admin angemeldet'), backgroundColor: Colors.red));
    }
    return null;
  }
  final picked = await showCloudFilePicker(
    context,
    apiService: apiService,
    memberId: memberId,
    mitgliedernummer: mnr,
  );
  if (picked == null || picked.isEmpty) return null;
  var auswahl = picked;
  if (maxFiles != null && auswahl.length > maxFiles) {
    final verworfen = auswahl.length - maxFiles;
    auswahl = auswahl.take(maxFiles).toList();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Nur noch $maxFiles Datei(en) frei — $verworfen übersprungen.'),
        backgroundColor: Colors.orange));
    }
  }
  var ok = 0;
  for (final id in auswahl) {
    final r = await attach(id);
    if (r['success'] == true) ok++;
  }
  return (ok: ok, total: auswahl.length);
}

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
}) async {
  final files = await showCloudFilePickerFiles(context,
      apiService: apiService, memberId: memberId, mitgliedernummer: mitgliedernummer);
  return files?.map((f) => (f['id'] as num).toInt()).toList();
}

/// Like [showCloudFilePickerFiles], but resolves the admin mitgliedernummer from
/// GlobalChatService itself — for callers that only know the member id.
/// Returns null if cancelled or when no admin is signed in.
Future<List<Map<String, dynamic>>?> showCloudFilePickerFilesForMember(
  BuildContext context, {
  required ApiService apiService,
  required int memberId,
}) async {
  final mnr = GlobalChatService().currentMitgliedernummer;
  if (mnr == null || mnr.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Kein Admin angemeldet'), backgroundColor: Colors.red));
    }
    return null;
  }
  if (!context.mounted) return null;
  return showCloudFilePickerFiles(context,
      apiService: apiService, memberId: memberId, mitgliedernummer: mnr);
}

/// Same picker, but returns the full cloud rows (`id`, `filename`, `size`, …)
/// instead of bare ids — for callers that must show the picked names before
/// the attach actually happens (e.g. a "new entry" dialog where the parent
/// record does not exist yet).
Future<List<Map<String, dynamic>>?> showCloudFilePickerFiles(
  BuildContext context, {
  required ApiService apiService,
  required int memberId,
  required String mitgliedernummer,
}) {
  return showDialog<List<Map<String, dynamic>>>(
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
              : () => Navigator.of(context).pop(
                    _files.where((f) => _selected.contains((f['id'] as num).toInt())).toList(),
                  ),
          icon: const Icon(Icons.check, size: 18),
          label: Text('Übernehmen (${_selected.length})'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// VORSITZER-CLOUD (50 GB, Ende-zu-Ende verschlüsselt)
// ═══════════════════════════════════════════════════════════════════

/// Picker für den eigenen 50-GB-Cloud des Vorsitzenden.
///
/// Bewusst getrennt vom Mitglieder-Picker oben, denn es ist ein anderer
/// Speicher mit anderen Regeln: `admin_cloud_files` statt `member_cloud_files`,
/// 50 GB statt 1 GB, und vor allem Ende-zu-Ende verschlüsselt. Der Server sieht
/// nur undurchsichtige Blobs — Dateinamen entstehen erst, wenn die Sitzung mit
/// der Passphrase entsperrt ist, und eine Server-zu-Server-Übernahme ist
/// unmöglich. Der Aufrufer muss die Auswahl über [SecureCloudService.downloadToMemory]
/// entschlüsseln und den Klartext hochladen.
///
/// Gibt die ausgewählten Dateien zurück, oder null bei Abbruch.
Future<List<CloudFile>?> showAdminCloudFilePicker(
  BuildContext context, {
  required ApiService apiService,
  required String mitgliedernummer,
  /// Höchstens so viele Dateien auswählbar (Rest der Anhang-Obergrenze).
  int? maxFiles,
}) {
  return showDialog<List<CloudFile>>(
    context: context,
    builder: (_) => _AdminCloudPickerDialog(
      svc: SecureCloudService(apiService, mitgliedernummer),
      maxFiles: maxFiles,
    ),
  );
}

class _AdminCloudPickerDialog extends StatefulWidget {
  final SecureCloudService svc;
  final int? maxFiles;
  const _AdminCloudPickerDialog({required this.svc, this.maxFiles});
  @override
  State<_AdminCloudPickerDialog> createState() => _AdminCloudPickerDialogState();
}

enum _AdminCloudPhase { laden, gesperrt, nichtEingerichtet, bereit, fehler }

class _AdminCloudPickerDialogState extends State<_AdminCloudPickerDialog> {
  _AdminCloudPhase _phase = _AdminCloudPhase.laden;
  String? _fehler;
  List<CloudFile> _files = [];
  int _quotaUsed = 0, _quotaTotal = 0;
  final Set<int> _selected = {};
  final TextEditingController _passC = TextEditingController();
  bool _entsperrt = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _passC.dispose();
    super.dispose();
  }

  /// Die Sitzung wird pro Mitgliedsnummer statisch gehalten — war der Cloud
  /// schon über den Kopfbereich entsperrt, ist hier keine Passphrase nötig.
  Future<void> _start() async {
    if (widget.svc.isUnlocked) {
      await _liste();
      return;
    }
    if (await widget.svc.tryResume() && mounted) {
      await _liste();
      return;
    }
    final da = await widget.svc.hasCloud();
    if (!mounted) return;
    setState(() {
      if (da == null) {
        _phase = _AdminCloudPhase.fehler;
        _fehler = 'Cloud nicht erreichbar';
      } else {
        _phase = da ? _AdminCloudPhase.gesperrt : _AdminCloudPhase.nichtEingerichtet;
      }
    });
  }

  Future<void> _liste() async {
    if (mounted) setState(() => _phase = _AdminCloudPhase.laden);
    final l = await widget.svc.list();
    if (!mounted) return;
    if (l == null) {
      setState(() {
        _phase = _AdminCloudPhase.fehler;
        _fehler = 'Cloud konnte nicht geladen werden';
      });
      return;
    }
    setState(() {
      // Unlesbare Einträge ausblenden: ohne entschlüsselbare Metadaten gibt es
      // weder Namen noch Dateityp, eine Auswahl wäre ein Blindflug.
      _files = l.files.where((f) => f.readable).toList();
      _quotaUsed = l.quotaUsed;
      _quotaTotal = l.quotaTotal;
      _phase = _AdminCloudPhase.bereit;
    });
  }

  Future<void> _entsperren() async {
    setState(() {
      _entsperrt = true;
      _fehler = null;
    });
    final err = await widget.svc.unlock(_passC.text);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _entsperrt = false;
        _fehler = err;
      });
      return;
    }
    _passC.clear();
    await _liste();
  }

  String _fmt(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  IconData _icon(CloudFile f) {
    final m = f.mime ?? '';
    if (m.contains('pdf') || f.name.toLowerCase().endsWith('.pdf')) return Icons.picture_as_pdf;
    if (m.startsWith('image/')) return Icons.image;
    return Icons.insert_drive_file;
  }

  bool get _limitErreicht => widget.maxFiles != null && _selected.length >= widget.maxFiles!;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        Icon(Icons.lock, color: Colors.deepPurple.shade600, size: 20),
        const SizedBox(width: 8),
        const Expanded(child: Text('Aus verschlüsseltem Cloud wählen', style: TextStyle(fontSize: 16))),
      ]),
      contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      content: SizedBox(width: 460, height: 420, child: _inhalt()),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
        if (_phase == _AdminCloudPhase.gesperrt)
          FilledButton.icon(
            onPressed: _entsperrt ? null : _entsperren,
            icon: const Icon(Icons.lock_open, size: 16),
            label: const Text('Entsperren'),
            style: FilledButton.styleFrom(backgroundColor: Colors.deepPurple),
          )
        else if (_phase == _AdminCloudPhase.bereit)
          FilledButton(
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.of(context).pop(_files.where((f) => _selected.contains(f.id)).toList()),
            style: FilledButton.styleFrom(backgroundColor: Colors.deepPurple),
            child: Text('Übernehmen (${_selected.length})'),
          ),
      ],
    );
  }

  Widget _inhalt() {
    switch (_phase) {
      case _AdminCloudPhase.laden:
        return const Center(child: CircularProgressIndicator());

      case _AdminCloudPhase.fehler:
        return Center(child: Text(_fehler ?? 'Fehler', style: TextStyle(color: Colors.red.shade600)));

      case _AdminCloudPhase.nichtEingerichtet:
        return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.cloud_off, size: 44, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Text('Verschlüsselter Cloud noch nicht eingerichtet',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          Text('Einrichtung erfolgt im Cloud-Bereich in der Kopfzeile.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ]));

      case _AdminCloudPhase.gesperrt:
        return Padding(padding: const EdgeInsets.all(16), child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Icon(Icons.lock_outline, size: 44, color: Colors.deepPurple.shade200)),
            const SizedBox(height: 12),
            Text('Der Cloud ist gesperrt. Die Dateinamen liegen verschlüsselt auf '
                'dem Server und werden erst nach Eingabe der Passphrase lesbar.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            const SizedBox(height: 14),
            TextField(
              controller: _passC,
              obscureText: true,
              autofocus: true,
              enabled: !_entsperrt,
              decoration: InputDecoration(
                labelText: 'Passphrase',
                prefixIcon: const Icon(Icons.key, size: 18),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onSubmitted: (_) => _entsperrt ? null : _entsperren(),
            ),
            if (_fehler != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.error_outline, size: 15, color: Colors.red.shade700),
                const SizedBox(width: 6),
                Expanded(child: Text(_fehler!, style: TextStyle(fontSize: 12, color: Colors.red.shade700))),
              ]),
            ],
          ],
        ));

      case _AdminCloudPhase.bereit:
        if (_files.isEmpty) {
          return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.cloud_off, size: 44, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text('Keine Dateien im verschlüsselten Cloud', style: TextStyle(color: Colors.grey.shade600)),
          ]));
        }
        return Column(children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: Row(children: [
            Icon(Icons.storage, size: 13, color: Colors.grey.shade500),
            const SizedBox(width: 4),
            Text('${_fmt(_quotaUsed)} von ${_fmt(_quotaTotal)} belegt · ${_files.length} Dateien',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            const Spacer(),
            if (widget.maxFiles != null)
              Text('${_selected.length}/${widget.maxFiles} gewählt',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                      color: _limitErreicht ? Colors.orange.shade800 : Colors.grey.shade600)),
          ])),
          const Divider(height: 1),
          Expanded(child: ListView.separated(
            itemCount: _files.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final f = _files[i];
              final checked = _selected.contains(f.id);
              // Bei erreichtem Limit bleiben nur die bereits Gewählten bedienbar,
              // damit man abwählen kann statt in einer Sackgasse zu landen.
              final sperren = !checked && _limitErreicht;
              return CheckboxListTile(
                value: checked,
                dense: true,
                enabled: !sperren,
                controlAffinity: ListTileControlAffinity.leading,
                title: Row(children: [
                  Icon(_icon(f), size: 18, color: sperren ? Colors.grey.shade300 : Colors.blueGrey.shade600),
                  const SizedBox(width: 8),
                  Expanded(child: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13))),
                ]),
                subtitle: Padding(padding: const EdgeInsets.only(left: 26),
                    child: Text('${_fmt(f.plainSize)}${f.source == 'scan' ? ' · Scan' : ''}',
                        style: const TextStyle(fontSize: 11))),
                onChanged: sperren ? null : (v) => setState(() {
                  if (v == true) {
                    _selected.add(f.id);
                  } else {
                    _selected.remove(f.id);
                  }
                }),
              );
            },
          )),
        ]);
    }
  }
}
