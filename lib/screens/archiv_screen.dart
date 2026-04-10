import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:archive/archive.dart' as archive;
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/logger_service.dart';
import '../widgets/eastern.dart';
import '../utils/file_picker_helper.dart';

final _log = LoggerService();

/// Archive screen for storing encrypted WhatsApp conversations and other records
class ArchivScreen extends StatefulWidget {
  final ApiService apiService;
  final List<User> users;

  const ArchivScreen({super.key, required this.apiService, required this.users});

  @override
  State<ArchivScreen> createState() => _ArchivScreenState();
}

class _ArchivScreenState extends State<ArchivScreen> {
  List<Map<String, dynamic>> _archives = [];
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadArchives();
  }

  Future<void> _loadArchives() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await widget.apiService.getArchives();

      if (result['success'] == true) {
        final list = result['archives'] as List? ?? [];
        setState(() {
          _archives = list.cast<Map<String, dynamic>>();
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = result['message']?.toString() ?? 'Fehler beim Laden';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Verbindungsfehler: $e';
        _isLoading = false;
      });
      _log.error('Archiv: Load failed: $e', tag: 'ARCHIV');
    }
  }

  Future<void> _uploadArchive() async {
    // Show dialog to get metadata first
    final metadata = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => _UploadDialog(users: widget.users),
    );

    if (metadata == null) return;

    // Pick files
    final result = await FilePickerHelper.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['txt', 'pdf', 'jpg', 'jpeg', 'png', 'zip'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      for (final file in result.files) {
        if (file.bytes == null) continue;

        final base64Data = base64Encode(file.bytes!);

        final uploadResult = await widget.apiService.uploadArchive(
          personName: metadata['person_name'] ?? '',
          mitgliedernummer: metadata['mitgliedernummer'],
          titel: metadata['titel'] ?? '',
          beschreibung: metadata['beschreibung'] ?? '',
          kategorie: metadata['kategorie'] ?? 'whatsapp',
          originalFilename: file.name,
          filesize: file.size,
          data: base64Data,
        );

        if (uploadResult['success'] != true) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Fehler: ${uploadResult['message']}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }

      await _loadArchives();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${result.files.length} Datei(en) erfolgreich archiviert'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _log.error('Archiv: Upload failed: $e', tag: 'ARCHIV');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload fehlgeschlagen: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _viewArchive(Map<String, dynamic> archive) async {
    try {
      final result = await widget.apiService.downloadArchive(
        int.parse(archive['id'].toString()),
      );

      if (result['success'] == true && result['data'] != null) {
        final bytes = Uint8List.fromList(base64Decode(result['data']));
        final filename = result['filename']?.toString() ?? 'archiv_download';

        // Show in-memory viewer — file NEVER touches disk
        if (mounted) {
          await showDialog(
            context: context,
            builder: (ctx) => _SecureFileViewer(
              filename: filename,
              bytes: bytes,
              titel: archive['titel']?.toString() ?? filename,
            ),
          );
        }
        // After dialog closes, bytes are garbage collected — nothing on disk
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Anzeige fehlgeschlagen: ${result['message']}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      _log.error('Archiv: View failed: $e', tag: 'ARCHIV');
    }
  }

  Future<void> _downloadArchive(Map<String, dynamic> archive) async {
    try {
      final result = await widget.apiService.downloadArchive(
        int.parse(archive['id'].toString()),
      );

      if (result['success'] == true && result['data'] != null) {
        final bytes = base64Decode(result['data']);
        final filename = result['filename']?.toString() ?? 'archiv_download';

        final savePath = await FilePickerHelper.pickFiles(
          dialogTitle: 'Archiv speichern',
          fileName: filename,
        );

        if (savePath != null) {
          final file = File(savePath);
          await file.writeAsBytes(bytes);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Datei gespeichert'), backgroundColor: Colors.green),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Download fehlgeschlagen: ${result['message']}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      _log.error('Archiv: Download failed: $e', tag: 'ARCHIV');
    }
  }

  Future<void> _deleteArchive(Map<String, dynamic> archive) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archiv löschen'),
        content: Text('Möchten Sie "${archive['titel']}" wirklich löschen?\n\nDiese Aktion kann nicht rückgängig gemacht werden.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final result = await widget.apiService.deleteArchive(
        int.parse(archive['id'].toString()),
      );

      if (result['success'] == true) {
        await _loadArchives();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Archiv gelöscht'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      _log.error('Archiv: Delete failed: $e', tag: 'ARCHIV');
    }
  }

  List<Map<String, dynamic>> get _filteredArchives {
    if (_searchQuery.isEmpty) return _archives;
    final q = _searchQuery.toLowerCase();
    return _archives.where((a) {
      return (a['person_name']?.toString().toLowerCase().contains(q) ?? false) ||
          (a['mitgliedernummer']?.toString().toLowerCase().contains(q) ?? false) ||
          (a['titel']?.toString().toLowerCase().contains(q) ?? false) ||
          (a['beschreibung']?.toString().toLowerCase().contains(q) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd.MM.yyyy HH:mm', 'de_DE');

    return SeasonalBackground(
      child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.archive, color: Colors.indigo.shade700, size: 28),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Archiv', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    Text(
                      'Verschlüsselte Aufbewahrung von WhatsApp-Chats und Dokumenten',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _uploadArchive,
                icon: const Icon(Icons.upload_file),
                label: const Text('Hochladen'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade700,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Stats bar
          _buildStatsBar(),
          const SizedBox(height: 16),

          // Search
          TextField(
            decoration: InputDecoration(
              hintText: 'Suchen nach Person, Titel...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
          const SizedBox(height: 16),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
                            const SizedBox(height: 12),
                            Text(_error!, style: const TextStyle(color: Colors.red)),
                            const SizedBox(height: 12),
                            ElevatedButton(onPressed: _loadArchives, child: const Text('Erneut versuchen')),
                          ],
                        ),
                      )
                    : _filteredArchives.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.archive_outlined, size: 64, color: Colors.grey.shade300),
                                const SizedBox(height: 16),
                                Text(
                                  _searchQuery.isEmpty ? 'Noch keine Archive vorhanden' : 'Keine Ergebnisse',
                                  style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
                                ),
                                if (_searchQuery.isEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Laden Sie WhatsApp-Chats oder Dokumente hoch',
                                    style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                                  ),
                                ],
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _filteredArchives.length,
                            itemBuilder: (context, index) {
                              final archive = _filteredArchives[index];
                              return _buildArchiveCard(archive, df);
                            },
                          ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildStatsBar() {
    final total = _archives.length;
    final whatsapp = _archives.where((a) => a['kategorie'] == 'whatsapp').length;
    final dokumente = _archives.where((a) => a['kategorie'] == 'dokument').length;
    final sonstige = total - whatsapp - dokumente;
    final totalSize = _archives.fold<int>(0, (sum, a) => sum + (int.tryParse(a['filesize']?.toString() ?? '0') ?? 0));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Row(
        children: [
          _statItem(Icons.archive, '$total', 'Gesamt'),
          _statDivider(),
          _statItem(Icons.chat, '$whatsapp', 'WhatsApp'),
          _statDivider(),
          _statItem(Icons.description, '$dokumente', 'Dokumente'),
          _statDivider(),
          _statItem(Icons.folder, '$sonstige', 'Sonstiges'),
          _statDivider(),
          _statItem(Icons.lock, _formatSize(totalSize), 'Verschlüsselt'),
        ],
      ),
    );
  }

  Widget _statItem(IconData icon, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: Colors.indigo.shade700, size: 20),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _statDivider() {
    return Container(width: 1, height: 40, color: Colors.indigo.shade100);
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _buildArchiveCard(Map<String, dynamic> archive, DateFormat df) {
    final kategorie = archive['kategorie']?.toString() ?? 'sonstiges';
    final isEncrypted = archive['is_encrypted'] == 1 || archive['is_encrypted'] == true;

    IconData catIcon;
    Color catColor;
    switch (kategorie) {
      case 'whatsapp':
        catIcon = Icons.chat;
        catColor = Colors.green.shade700;
        break;
      case 'dokument':
        catIcon = Icons.description;
        catColor = Colors.blue.shade700;
        break;
      default:
        catIcon = Icons.folder;
        catColor = Colors.orange.shade700;
    }

    DateTime? createdAt;
    try {
      createdAt = DateTime.parse(archive['created_at']?.toString() ?? '');
    } catch (_) {}

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: catColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Stack(
                children: [
                  Center(child: Icon(catIcon, color: catColor, size: 24)),
                  if (isEncrypted)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Icon(Icons.lock, size: 12, color: Colors.green.shade700),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          archive['titel']?.toString() ?? 'Kein Titel',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: catColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          kategorie == 'whatsapp' ? 'WhatsApp' : kategorie == 'dokument' ? 'Dokument' : 'Sonstiges',
                          style: TextStyle(fontSize: 11, color: catColor, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.person_outline, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        archive['person_name']?.toString() ?? '-',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                      ),
                      if (archive['mitgliedernummer'] != null && archive['mitgliedernummer'].toString().isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            archive['mitgliedernummer'].toString(),
                            style: TextStyle(fontSize: 11, color: Colors.blue.shade700, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                      const SizedBox(width: 16),
                      Icon(Icons.attach_file, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        archive['original_filename']?.toString() ?? '-',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatSize(int.tryParse(archive['filesize']?.toString() ?? '0') ?? 0),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                      ),
                    ],
                  ),
                  if (archive['beschreibung'] != null && archive['beschreibung'].toString().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      archive['beschreibung'].toString(),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    createdAt != null ? df.format(createdAt) : '-',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                  ),
                ],
              ),
            ),
            // Actions
            Column(
              children: [
                IconButton(
                  icon: const Icon(Icons.visibility, size: 20),
                  tooltip: 'Anzeigen (nur im Speicher)',
                  onPressed: () => _viewArchive(archive),
                  color: Colors.green.shade700,
                ),
                IconButton(
                  icon: const Icon(Icons.download, size: 20),
                  tooltip: 'Herunterladen',
                  onPressed: () => _downloadArchive(archive),
                  color: Colors.indigo,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  tooltip: 'Löschen',
                  onPressed: () => _deleteArchive(archive),
                  color: Colors.red.shade400,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// UPLOAD DIALOG
// ══════════════════════════════════════════════════════════════

class _UploadDialog extends StatefulWidget {
  final List<User> users;

  const _UploadDialog({required this.users});

  @override
  State<_UploadDialog> createState() => _UploadDialogState();
}

class _UploadDialogState extends State<_UploadDialog> {
  final _titelCtrl = TextEditingController();
  final _beschreibungCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  String _kategorie = 'whatsapp';
  User? _selectedUser;
  List<User> _filteredUsers = [];

  @override
  void initState() {
    super.initState();
    _filteredUsers = widget.users;
  }

  @override
  void dispose() {
    _titelCtrl.dispose();
    _beschreibungCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _filterUsers(String query) {
    final q = query.toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filteredUsers = widget.users;
      } else {
        _filteredUsers = widget.users.where((u) {
          return u.name.toLowerCase().contains(q) ||
              u.mitgliedernummer.toLowerCase().contains(q) ||
              u.email.toLowerCase().contains(q);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.upload_file, color: Colors.indigo.shade700),
          const SizedBox(width: 8),
          const Text('Archiv hochladen'),
        ],
      ),
      content: SizedBox(
        width: 480,
        height: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Info box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock, color: Colors.green.shade700, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Dateien werden AES-256 verschlüsselt auf dem Server gespeichert.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Member selector
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Mitglied auswählen *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Suchen nach Name, Nummer...',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                isDense: true,
              ),
              onChanged: _filterUsers,
            ),
            const SizedBox(height: 6),
            Container(
              height: 130,
              decoration: BoxDecoration(
                border: Border.all(color: _selectedUser == null ? Colors.grey.shade300 : Colors.indigo.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                itemCount: _filteredUsers.length,
                itemBuilder: (ctx, i) {
                  final user = _filteredUsers[i];
                  final isSelected = _selectedUser?.id == user.id;
                  return InkWell(
                    onTap: () => setState(() => _selectedUser = user),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      color: isSelected ? Colors.indigo.shade50 : null,
                      child: Row(
                        children: [
                          Icon(
                            isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                            size: 18,
                            color: isSelected ? Colors.indigo.shade700 : Colors.grey.shade400,
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              user.mitgliedernummer,
                              style: TextStyle(fontSize: 11, color: Colors.blue.shade700, fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              user.name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            user.role,
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_selectedUser != null) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_selectedUser!.name} (${_selectedUser!.mitgliedernummer})',
                  style: TextStyle(fontSize: 12, color: Colors.indigo.shade700, fontWeight: FontWeight.w500),
                ),
              ),
            ],
            const SizedBox(height: 12),

            TextField(
              controller: _titelCtrl,
              decoration: const InputDecoration(
                labelText: 'Titel *',
                hintText: 'z.B. WhatsApp Chat mit Max Mustermann',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.title),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _kategorie,
              decoration: const InputDecoration(
                labelText: 'Kategorie',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.category),
              ),
              items: const [
                DropdownMenuItem(value: 'whatsapp', child: Text('WhatsApp Chat')),
                DropdownMenuItem(value: 'dokument', child: Text('Dokument')),
                DropdownMenuItem(value: 'sonstiges', child: Text('Sonstiges')),
              ],
              onChanged: (v) => setState(() => _kategorie = v ?? 'whatsapp'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _beschreibungCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Beschreibung',
                hintText: 'Warum wird dieses Archiv aufbewahrt?',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.notes),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        ElevatedButton.icon(
          onPressed: () {
            if (_selectedUser == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Bitte wählen Sie ein Mitglied aus'), backgroundColor: Colors.red),
              );
              return;
            }
            if (_titelCtrl.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Titel ist erforderlich'), backgroundColor: Colors.red),
              );
              return;
            }
            Navigator.pop(context, {
              'person_name': _selectedUser!.name,
              'mitgliedernummer': _selectedUser!.mitgliedernummer,
              'titel': _titelCtrl.text.trim(),
              'beschreibung': _beschreibungCtrl.text.trim(),
              'kategorie': _kategorie,
            });
          },
          icon: const Icon(Icons.check),
          label: const Text('Weiter — Dateien auswählen'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.indigo.shade700,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SECURE IN-MEMORY FILE VIEWER — file NEVER touches disk
// ══════════════════════════════════════════════════════════════

class _SecureFileViewer extends StatefulWidget {
  final String filename;
  final Uint8List bytes;
  final String titel;

  const _SecureFileViewer({
    required this.filename,
    required this.bytes,
    required this.titel,
  });

  @override
  State<_SecureFileViewer> createState() => _SecureFileViewerState();
}

class _SecureFileViewerState extends State<_SecureFileViewer> {
  String get _ext => _activeFilename.split('.').last.toLowerCase();

  bool get _isImage => ['jpg', 'jpeg', 'png', 'bmp', 'gif', 'webp'].contains(_ext);
  bool get _isTxt => ['txt', 'html', 'htm', 'css', 'js', 'json', 'xml', 'csv', 'log', 'md'].contains(_ext);
  bool get _isPdf => _ext == 'pdf';
  bool get _isZip => ['zip'].contains(widget.filename.split('.').last.toLowerCase());

  // ZIP navigation state
  List<archive.ArchiveFile>? _zipFiles;
  archive.ArchiveFile? _selectedZipFile;
  Uint8List? _selectedFileBytes;
  String _activeFilename = '';
  String _zipSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _activeFilename = widget.filename;
    if (_isZip) {
      _extractZip();
    }
  }

  void _extractZip() {
    try {
      final decoded = archive.ZipDecoder().decodeBytes(widget.bytes);
      setState(() {
        _zipFiles = decoded.files.where((f) => !f.isFile || f.size > 0).toList()
          ..sort((a, b) {
            // Folders first, then by name
            if (a.isFile != b.isFile) return a.isFile ? 1 : -1;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
      });
    } catch (e) {
      debugPrint('ZIP extract error: $e');
    }
  }

  void _openZipFile(archive.ArchiveFile file) {
    if (!file.isFile) return;
    setState(() {
      _selectedZipFile = file;
      _selectedFileBytes = Uint8List.fromList(file.content as List<int>);
      _activeFilename = file.name.split('/').last;
    });
  }

  void _backToZipList() {
    setState(() {
      _selectedZipFile = null;
      _selectedFileBytes = null;
      _activeFilename = widget.filename;
    });
  }

  @override
  Widget build(BuildContext context) {
    final displayTitle = _selectedZipFile != null
        ? _selectedZipFile!.name.split('/').last
        : widget.titel;
    final displaySubtitle = _selectedZipFile != null
        ? '${widget.filename} → ${_selectedZipFile!.name}'
        : '${widget.filename} — Nur im Speicher (nicht auf der Festplatte)';

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 900,
        height: 650,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.white,
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.indigo.shade700,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  if (_selectedZipFile != null) ...[
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                      onPressed: _backToZipList,
                      tooltip: 'Zurück zur Dateiliste',
                    ),
                  ] else
                    const Icon(Icons.lock, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayTitle,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          displaySubtitle,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green.shade600,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shield, color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text('AES-256', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Schließen (Daten werden aus dem Speicher gelöscht)',
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: _buildContent(),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Diese Datei existiert nur im Arbeitsspeicher. Beim Schließen wird sie vollständig gelöscht.',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    // ZIP file: show file list or selected file content
    if (_isZip && _selectedZipFile == null) {
      return _buildZipViewer();
    }

    // Use selected file bytes if viewing a ZIP entry
    final viewBytes = _selectedFileBytes ?? widget.bytes;

    if (_isTxt) {
      return _buildTextViewer(viewBytes);
    } else if (_isImage) {
      return _buildImageViewer(viewBytes);
    } else if (_isPdf) {
      return _buildPdfViewer(viewBytes);
    } else {
      return _buildUnsupportedViewer();
    }
  }

  Widget _buildZipViewer() {
    if (_zipFiles == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final filtered = _zipSearchQuery.isEmpty
        ? _zipFiles!
        : _zipFiles!.where((f) => f.name.toLowerCase().contains(_zipSearchQuery.toLowerCase())).toList();

    final files = filtered.where((f) => f.isFile).toList();
    final totalSize = files.fold<int>(0, (sum, f) => sum + f.size);

    return Column(
      children: [
        // Search + stats bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.grey.shade50,
          child: Row(
            children: [
              Icon(Icons.folder_zip, color: Colors.orange.shade700, size: 20),
              const SizedBox(width: 8),
              Text(
                '${files.length} Dateien — ${_formatSize(totalSize)}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
              ),
              const Spacer(),
              SizedBox(
                width: 250,
                height: 34,
                child: TextField(
                  onChanged: (v) => setState(() => _zipSearchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Datei suchen...',
                    hintStyle: const TextStyle(fontSize: 12),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // File list
        Expanded(
          child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (ctx, i) {
              final file = filtered[i];
              final name = file.name;
              final ext = name.split('.').last.toLowerCase();
              final isDir = !file.isFile;
              final icon = isDir
                  ? Icons.folder
                  : _fileIcon(ext);
              final color = isDir
                  ? Colors.amber.shade700
                  : _fileColor(ext);

              return ListTile(
                dense: true,
                leading: Icon(icon, size: 22, color: color),
                title: Text(
                  name.split('/').last.isEmpty ? name : name.split('/').last,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isDir ? FontWeight.w600 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: isDir
                    ? null
                    : Text(
                        _formatSize(file.size),
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                trailing: file.isFile
                    ? Icon(Icons.open_in_new, size: 16, color: Colors.grey.shade400)
                    : null,
                onTap: file.isFile ? () => _openZipFile(file) : null,
                hoverColor: Colors.indigo.shade50,
              );
            },
          ),
        ),
      ],
    );
  }

  IconData _fileIcon(String ext) {
    if (['jpg', 'jpeg', 'png', 'bmp', 'gif', 'webp'].contains(ext)) return Icons.image;
    if (ext == 'pdf') return Icons.picture_as_pdf;
    if (['txt', 'log', 'md', 'csv'].contains(ext)) return Icons.description;
    if (['html', 'htm'].contains(ext)) return Icons.code;
    if (['mp4', 'avi', 'mov', 'mkv'].contains(ext)) return Icons.videocam;
    if (['mp3', 'wav', 'ogg', 'opus', 'm4a'].contains(ext)) return Icons.audiotrack;
    if (['doc', 'docx'].contains(ext)) return Icons.article;
    if (['xls', 'xlsx'].contains(ext)) return Icons.table_chart;
    if (['zip', 'rar', '7z'].contains(ext)) return Icons.folder_zip;
    return Icons.insert_drive_file;
  }

  Color _fileColor(String ext) {
    if (['jpg', 'jpeg', 'png', 'bmp', 'gif', 'webp'].contains(ext)) return Colors.green.shade700;
    if (ext == 'pdf') return Colors.red.shade700;
    if (['txt', 'log', 'md', 'csv'].contains(ext)) return Colors.blue.shade700;
    if (['html', 'htm'].contains(ext)) return Colors.orange.shade700;
    if (['mp4', 'avi', 'mov', 'mkv'].contains(ext)) return Colors.purple.shade700;
    if (['mp3', 'wav', 'ogg', 'opus', 'm4a'].contains(ext)) return Colors.pink.shade700;
    return Colors.grey.shade600;
  }

  Widget _buildTextViewer(Uint8List viewBytes) {
    String text;
    try {
      text = utf8.decode(viewBytes);
    } catch (_) {
      text = latin1.decode(viewBytes);
    }

    return Container(
      color: Colors.grey.shade50,
      child: SelectionArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Text(
            text,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageViewer(Uint8List viewBytes) {
    return Container(
      color: Colors.grey.shade200,
      child: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.memory(
            viewBytes,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }

  Widget _buildPdfViewer(Uint8List viewBytes) {
    return PdfViewer.data(viewBytes, sourceName: _activeFilename);
  }

  Widget _buildUnsupportedViewer() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'Vorschau für .$_ext nicht verfügbar',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            'Dateityp: $_ext | Größe: ${_formatSize(_selectedFileBytes?.length ?? widget.bytes.length)}',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 8),
          Text(
            'Die Datei ist im Speicher entschlüsselt, kann aber nicht angezeigt werden.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
