import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import '../services/handelsregister_client_service.dart';
import '../widgets/file_viewer_dialog.dart';

class HandelsregisterScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onBack;

  const HandelsregisterScreen({
    super.key,
    required this.apiService,
    required this.onBack,
  });

  @override
  State<HandelsregisterScreen> createState() => _HandelsregisterScreenState();
}

class _HandelsregisterScreenState extends State<HandelsregisterScreen> {
  final _hrService = HandelsregisterClientService();

  // Search form
  String _registerArt = 'HRB';
  final _nummerController = TextEditingController();
  final _gerichtController = TextEditingController();
  final _schlagwoerterController = TextEditingController();

  // Results
  List<Map<String, dynamic>> _entries = [];
  bool _isSearching = false;
  String? _error;
  bool _hasSearched = false;

  // Document download
  String? _downloadingDoc;

  static const _registerArten = ['HRA', 'HRB', 'VR', 'PR', 'GnR'];

  @override
  void dispose() {
    _nummerController.dispose();
    _gerichtController.dispose();
    _schlagwoerterController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final nummer = _nummerController.text.trim();
    final schlagwoerter = _schlagwoerterController.text.trim();

    if (nummer.isEmpty && schlagwoerter.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte Registernummer oder Schlagwörter eingeben'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      final result = await _hrService.search(
        registerArt: _registerArt,
        registerNummer: nummer,
        registerGericht: _gerichtController.text.trim(),
        schlagwoerter: schlagwoerter,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        final regData = result['data']?['register_data'] ?? result['register_data'];
        if (regData != null) {
          final entries = List<Map<String, dynamic>>.from(regData['entries'] ?? []);
          setState(() {
            _entries = entries;
            _hasSearched = true;
            _isSearching = false;
            if (entries.isEmpty) {
              _error = regData['message'] ?? 'Keine Ergebnisse gefunden';
            }
          });
        } else {
          setState(() {
            _isSearching = false;
            _hasSearched = true;
            _error = 'Unerwartete Antwort vom Server';
          });
        }
      } else {
        setState(() {
          _isSearching = false;
          _hasSearched = true;
          _error = result['message'] ?? 'Abfrage fehlgeschlagen';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          _hasSearched = true;
          _error = 'Fehler: $e';
        });
      }
    }
  }

  Future<void> _downloadDocument(Map<String, dynamic> entry, String docType, String label) async {
    setState(() => _downloadingDoc = docType);

    // Entry data: register_nummer="VR 201335", register_gericht="Amtsgericht Memmingen"
    // Server expects: register_nummer="201335", register_gericht="Memmingen"
    final rawNummer = entry['register_nummer'] as String? ?? '';
    final rawGericht = entry['register_gericht'] as String? ?? '';
    final entryArt = entry['register_art'] as String? ?? _registerArt;
    // Strip art prefix from nummer (e.g. "VR 201335" -> "201335")
    final entryNummer = rawNummer.replaceFirst(RegExp(r'^(VR|HRA|HRB|GnR|PR|GsR)\s*'), '').isNotEmpty
        ? rawNummer.replaceFirst(RegExp(r'^(VR|HRA|HRB|GnR|PR|GsR)\s*'), '')
        : _nummerController.text.trim();
    // Strip "Amtsgericht " prefix from gericht (e.g. "Amtsgericht Memmingen" -> "Memmingen")
    final entryGericht = rawGericht.replaceFirst(RegExp(r'^Amtsgericht\s+'), '').isNotEmpty
        ? rawGericht.replaceFirst(RegExp(r'^Amtsgericht\s+'), '')
        : _gerichtController.text.trim();

    try {
      final result = await _hrService.downloadDocument(
        registerArt: entryArt,
        registerNummer: entryNummer,
        registerGericht: entryGericht,
        documentType: docType,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        final data = result['data'];
        final bytes = data['bytes'] as Uint8List;
        final fileName = data['document_name'] as String;

        final tempDir = await getTemporaryDirectory();
        final filePath = '${tempDir.path}/$fileName';
        await File(filePath).writeAsBytes(bytes);

        if (mounted) {
          await FileViewerDialog.show(context, filePath, fileName);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Download fehlgeschlagen'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingDoc = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
                tooltip: 'Zurück',
              ),
              const SizedBox(width: 8),
              Icon(Icons.search, size: 32, color: Colors.green.shade700),
              const SizedBox(width: 12),
              const Text(
                'Handelsregister',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                'handelsregister.de',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Content
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: Search form
                SizedBox(
                  width: 320,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.manage_search, color: Colors.green, size: 24),
                              ),
                              const SizedBox(width: 12),
                              const Text('Suche', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const Divider(height: 24),
                          // Register-Art dropdown
                          Text('Register-Art', style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 4),
                          DropdownButtonFormField<String>(
                            initialValue: _registerArt,
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(),
                            ),
                            items: _registerArten.map((art) => DropdownMenuItem(
                              value: art,
                              child: Text(art, style: const TextStyle(fontSize: 14)),
                            )).toList(),
                            onChanged: (v) { if (v != null) setState(() => _registerArt = v); },
                          ),
                          const SizedBox(height: 14),
                          // Registernummer
                          Text('Registernummer', style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _nummerController,
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(),
                              hintText: 'z.B. 201335',
                            ),
                            style: const TextStyle(fontSize: 14),
                            onSubmitted: (_) => _search(),
                          ),
                          const SizedBox(height: 14),
                          // Registergericht
                          Text('Registergericht', style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _gerichtController,
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(),
                              hintText: 'z.B. München',
                            ),
                            style: const TextStyle(fontSize: 14),
                            onSubmitted: (_) => _search(),
                          ),
                          const SizedBox(height: 14),
                          // Schlagwörter
                          Text('Schlagwörter', style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _schlagwoerterController,
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(),
                              hintText: 'Firmenname...',
                            ),
                            style: const TextStyle(fontSize: 14),
                            onSubmitted: (_) => _search(),
                          ),
                          const SizedBox(height: 20),
                          // Search button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: _isSearching
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.search, size: 18),
                              label: Text(_isSearching ? 'Suche läuft...' : 'Suchen'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade600,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: _isSearching ? null : _search,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Right: Results
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.list_alt, color: Colors.blue, size: 24),
                              ),
                              const SizedBox(width: 12),
                              const Text('Ergebnisse', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              if (_hasSearched && _entries.isNotEmpty) ...[
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.green.shade200),
                                  ),
                                  child: Text(
                                    '${_entries.length} Treffer',
                                    style: TextStyle(fontSize: 12, color: Colors.green.shade700, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const Divider(height: 24),
                          Expanded(child: _buildResults()),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_isSearching) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Handelsregister wird abgefragt...', style: TextStyle(fontSize: 13)),
          ],
        ),
      );
    }

    if (!_hasSearched) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'Geben Sie Suchkriterien ein\nund klicken Sie "Suchen"',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber, size: 36, color: Colors.orange.shade400),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Colors.orange.shade700, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView(
      children: [
        for (final entry in _entries) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry['name'] ?? 'Unbekannt',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 6),
                _buildDetail(Icons.account_balance, 'Gericht', entry['register_gericht']),
                _buildDetail(Icons.tag, 'Register-Nr.', entry['register_nummer']),
                _buildDetail(Icons.map, 'Bundesland', entry['bundesland']),
                _buildDetail(Icons.business, 'Sitz', entry['sitz']),
                _buildDetail(Icons.info_outline, 'Status', entry['status']),
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Text('Dokumente', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildDocChip(entry, 'AD', 'Aktueller Abdruck'),
                    _buildDocChip(entry, 'CD', 'Chronologischer Abdruck'),
                    _buildDocChip(entry, 'SI', 'Strukturierte Inhalte'),
                    _buildDocChip(entry, 'DK', 'Dokumentenkorb'),
                    _buildDocChip(entry, 'UT', 'Unternehmensträger'),
                    _buildDocChip(entry, 'VÖ', 'Veröffentlichungen'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDetail(IconData icon, String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: Colors.green.shade600),
          const SizedBox(width: 6),
          Text('$label: ', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _buildDocChip(Map<String, dynamic> entry, String docType, String label) {
    final isDownloading = _downloadingDoc == docType;
    return ActionChip(
      avatar: isDownloading
          ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.green.shade400))
          : null,
      label: Text(isDownloading ? '$docType...' : docType, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      tooltip: label,
      side: BorderSide(color: Colors.green.shade300),
      backgroundColor: Colors.white,
      onPressed: isDownloading || _downloadingDoc != null ? null : () => _downloadDocument(entry, docType, label),
    );
  }
}
