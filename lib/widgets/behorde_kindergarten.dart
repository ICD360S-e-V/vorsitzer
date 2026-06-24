import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';

/// Behörde > Kindergarten — Vorsitzer-only Verwaltung pentru
/// "zuständiger Kindergarten" + documente asociate (Vertrag, Kündigung).
///
/// Layout simplificat 2026-06-24: tab-ul "Kinder" eliminat la cererea
/// userului. Click pe card-ul gradiniței → modal cu 3 sub-tab-uri:
/// Details, Vertrag, Kündigung — fiecare cu multi-upload până la
/// 20 documente simultan (jpeg/jpg/pdf), 50 MB per fișier.
class BehordeKindergartenContent extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  const BehordeKindergartenContent({super.key, required this.apiService, required this.userId});
  @override
  State<BehordeKindergartenContent> createState() => _State();
}

class _State extends State<BehordeKindergartenContent> {
  bool _loaded = false, _loading = false;
  Map<String, dynamic> _data = {};

  @override
  void initState() { super.initState(); _load(); }

  String _v(String f) => _data[f]?.toString() ?? '';

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final res = await widget.apiService.getKindergartenData(widget.userId);
      if (res['success'] == true && mounted) {
        final raw = res['data'];
        if (raw is Map) {
          _data = {};
          for (final e in raw.entries) {
            final p = e.key.toString().split('.');
            _data[p.length == 2 ? p[1] : e.key.toString()] = e.value;
          }
        }
      }
    } catch (_) {}
    if (mounted) setState(() { _loading = false; _loaded = true; });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded && !_loading) _load();
    if (_loading || !_loaded) return const Center(child: CircularProgressIndicator());
    return _buildKigaView();
  }

  Future<void> _searchKiga() async {
    final standorte = await widget.apiService.getBehoerdenStandorte(typ: 'kindergarten');
    if (!mounted || standorte.isEmpty) return;
    final selected = await showDialog<Map<String, dynamic>>(context: context, builder: (sCtx) {
      String search = '';
      List<Map<String, dynamic>> results = standorte;
      return StatefulBuilder(builder: (sCtx, setS) => AlertDialog(
        title: Row(children: [Icon(Icons.child_care, size: 18, color: Colors.pink.shade700), const SizedBox(width: 8), const Text('Kindergarten suchen', style: TextStyle(fontSize: 14))]),
        content: SizedBox(width: 450, height: 400, child: Column(children: [
          TextField(autofocus: true, decoration: InputDecoration(hintText: 'Name oder Ort eingeben...', prefixIcon: const Icon(Icons.search, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
            onChanged: (v) => setS(() {
              search = v.toLowerCase();
              results = standorte.where((s) => (s['name']?.toString() ?? '').toLowerCase().contains(search) || (s['plz_ort']?.toString() ?? '').toLowerCase().contains(search)).toList();
            })),
          const SizedBox(height: 8),
          Expanded(child: results.isEmpty ? Center(child: Text('Keine Ergebnisse', style: TextStyle(color: Colors.grey.shade500)))
            : ListView.builder(itemCount: results.length, itemBuilder: (_, i) {
                final s = results[i];
                return ListTile(dense: true, leading: Icon(Icons.child_care, size: 18, color: Colors.pink.shade400),
                  title: Text(s['name']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text([s['strasse'], s['plz_ort']].where((v) => v != null && v.toString().isNotEmpty).join(', '), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  onTap: () => Navigator.pop(sCtx, s));
              })),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(sCtx), child: const Text('Abbrechen'))],
      ));
    });
    if (selected != null) {
      final str = selected['strasse']?.toString() ?? '';
      final plz = selected['plz_ort']?.toString() ?? '';
      final m = <String, dynamic>{
        'stammdaten.name': selected['name']?.toString() ?? '',
        'stammdaten.adresse': [str, plz].where((v) => v.isNotEmpty).join(', '),
        'stammdaten.telefon': selected['telefon']?.toString() ?? '',
        'stammdaten.email': selected['email']?.toString() ?? '',
        'stammdaten.oeffnungszeiten': selected['oeffnungszeiten']?.toString() ?? '',
      };
      await widget.apiService.saveKindergartenData(widget.userId, m);
      for (final e in m.entries) { _data[e.key.split('.').last] = e.value; }
      if (mounted) setState(() {});
    }
  }

  Widget _buildKigaView() {
    final hasKiga = _v('name').isNotEmpty;
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.child_care, size: 20, color: Colors.pink.shade700), const SizedBox(width: 8),
        Text('Zuständiger Kindergarten', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.pink.shade700)),
        const Spacer(),
        FilledButton.icon(
          icon: const Icon(Icons.search, size: 16),
          label: Text(hasKiga ? 'Ändern' : 'Suchen', style: const TextStyle(fontSize: 12)),
          style: FilledButton.styleFrom(backgroundColor: Colors.pink.shade600, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero),
          onPressed: _searchKiga,
        ),
      ]),
      const SizedBox(height: 16),
      if (!hasKiga)
        Container(width: double.infinity, padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
          child: Column(children: [
            Icon(Icons.search, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text('Kein Kindergarten ausgewählt', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
            const SizedBox(height: 4),
            Text('Klicken Sie auf "Suchen" um einen Kindergarten auszuwählen', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
          ]),
        )
      else
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _openDetailDialog,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.pink.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.pink.shade200)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                CircleAvatar(radius: 22, backgroundColor: Colors.pink.shade100, child: Icon(Icons.child_care, size: 24, color: Colors.pink.shade700)),
                const SizedBox(width: 12),
                Expanded(child: Text(_v('name'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.pink.shade800))),
                Icon(Icons.chevron_right, color: Colors.pink.shade400),
                IconButton(
                  icon: Icon(Icons.close, size: 18, color: Colors.red.shade400),
                  tooltip: 'Entfernen',
                  onPressed: () async {
                    await widget.apiService.saveKindergartenData(widget.userId, {'stammdaten.name': '', 'stammdaten.adresse': '', 'stammdaten.telefon': '', 'stammdaten.email': '', 'stammdaten.oeffnungszeiten': ''});
                    _data.clear();
                    if (mounted) setState(() {});
                  },
                ),
              ]),
              const Divider(height: 20),
              if (_v('adresse').isNotEmpty) _infoRow(Icons.location_on, _v('adresse'), Colors.pink),
              if (_v('telefon').isNotEmpty) _infoRow(Icons.phone, _v('telefon'), Colors.blue),
              if (_v('email').isNotEmpty) _infoRow(Icons.email, _v('email'), Colors.teal),
              if (_v('oeffnungszeiten').isNotEmpty) _infoRow(Icons.schedule, _v('oeffnungszeiten'), Colors.orange),
              if (_v('leiterin').isNotEmpty) _infoRow(Icons.person, 'Leitung: ${_v('leiterin')}', Colors.purple),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.pink.shade300)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.folder_open, size: 14, color: Colors.pink.shade700),
                  const SizedBox(width: 6),
                  Text('Klicken für Details, Vertrag & Kündigung', style: TextStyle(fontSize: 11, color: Colors.pink.shade700, fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
          ),
        ),
    ]));
  }

  void _openDetailDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
          child: _KigaDetailDialog(
            apiService: widget.apiService,
            userId: widget.userId,
            data: _data,
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text, MaterialColor c) {
    return Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [
      Icon(icon, size: 16, color: c.shade600), const SizedBox(width: 10),
      Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: Colors.grey.shade800))),
    ]));
  }
}

// ════════════════════════════════════════════════════════════════════
// DETAIL DIALOG — 3 sub-taburi: Details / Vertrag / Kündigung
// ════════════════════════════════════════════════════════════════════
class _KigaDetailDialog extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final Map<String, dynamic> data;
  const _KigaDetailDialog({required this.apiService, required this.userId, required this.data});
  @override
  State<_KigaDetailDialog> createState() => _KigaDetailDialogState();
}

class _KigaDetailDialogState extends State<_KigaDetailDialog> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(children: [
            Icon(Icons.child_care, size: 20, color: Colors.pink.shade700),
            const SizedBox(width: 8),
            Expanded(child: Text(
              widget.data['name']?.toString() ?? 'Kindergarten',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.pink.shade800),
            )),
            IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.pop(context)),
          ]),
        ),
        TabBar(
          labelColor: Colors.pink.shade700,
          unselectedLabelColor: Colors.grey.shade500,
          indicatorColor: Colors.pink.shade700,
          tabs: const [
            Tab(icon: Icon(Icons.info_outline, size: 16), text: 'Details'),
            Tab(icon: Icon(Icons.description, size: 16), text: 'Vertrag'),
            Tab(icon: Icon(Icons.event_busy, size: 16), text: 'Kündigung'),
          ],
        ),
        Expanded(
          child: TabBarView(children: [
            _DetailsTab(data: widget.data),
            _DokTab(apiService: widget.apiService, userId: widget.userId, typ: 'vertrag'),
            _DokTab(apiService: widget.apiService, userId: widget.userId, typ: 'kuendigung'),
          ]),
        ),
      ]),
    );
  }
}

// ──────────────────────── DETAILS TAB ────────────────────────
class _DetailsTab extends StatelessWidget {
  final Map<String, dynamic> data;
  const _DetailsTab({required this.data});

  String _v(String k) => data[k]?.toString() ?? '';

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _row(Icons.child_care, 'Name', _v('name')),
        _row(Icons.location_on, 'Adresse', _v('adresse')),
        _row(Icons.phone, 'Telefon', _v('telefon')),
        _row(Icons.email, 'E-Mail', _v('email')),
        _row(Icons.schedule, 'Öffnungszeiten', _v('oeffnungszeiten')),
        _row(Icons.person, 'Leitung', _v('leiterin')),
      ]),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: Colors.pink.shade600),
        const SizedBox(width: 10),
        SizedBox(width: 130, child: Text('$label:', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

// ──────────────────────── DOK TAB (Vertrag / Kündigung) ────────────────────────
class _DokTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final String typ; // 'vertrag' or 'kuendigung'
  const _DokTab({required this.apiService, required this.userId, required this.typ});
  @override
  State<_DokTab> createState() => _DokTabState();
}

class _DokTabState extends State<_DokTab> {
  List<Map<String, dynamic>> _dokumente = [];
  bool _loading = true;
  bool _uploading = false;
  String _uploadProgress = '';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await widget.apiService.listKindergartenDokumente(userId: widget.userId, typ: widget.typ);
    if (!mounted) return;
    setState(() {
      _dokumente = (r['dokumente'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      _loading = false;
    });
  }

  Future<void> _pickAndUpload() async {
    final result = await FilePickerHelper.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg'],
    );
    if (result == null || result.files.isEmpty) return;
    var files = result.files;
    if (files.length > 20) {
      files = files.sublist(0, 20);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximal 20 Dateien gleichzeitig — nur die ersten 20 werden hochgeladen'), backgroundColor: Colors.orange),
      );
    }
    setState(() { _uploading = true; _uploadProgress = '0 / ${files.length}'; });
    int done = 0;
    int failed = 0;
    for (final f in files) {
      if (f.path == null) { failed++; continue; }
      try {
        final r = await widget.apiService.uploadKindergartenDokument(
          userId: widget.userId,
          typ: widget.typ,
          filePath: f.path!,
          fileName: f.name,
        );
        if (r['success'] != true) failed++;
      } catch (_) { failed++; }
      done++;
      if (mounted) setState(() => _uploadProgress = '$done / ${files.length}');
    }
    if (mounted) {
      setState(() { _uploading = false; _uploadProgress = ''; });
      if (failed > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${files.length - failed} hochgeladen, $failed fehlgeschlagen'), backgroundColor: failed == files.length ? Colors.red : Colors.orange),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${files.length} Datei(en) hochgeladen'), backgroundColor: Colors.green),
        );
      }
    }
    await _load();
  }

  Future<void> _delete(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dokument löschen?'),
        content: const Text('Diese Aktion kann nicht rückgängig gemacht werden.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.apiService.deleteKindergartenDokument(id: id);
    await _load();
  }

  Future<void> _open(int id, String filename) async {
    try {
      final r = await widget.apiService.downloadKindergartenDokument(id);
      if (r.statusCode != 200) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download fehlgeschlagen (${r.statusCode})'), backgroundColor: Colors.red),
        );
        return;
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(r.bodyBytes);
      await OpenFilex.open(file.path);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
      );
    }
  }

  String _humanSize(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  String _fmtDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try { return DateFormat('dd.MM.yyyy HH:mm').format(DateTime.parse(raw)); } catch (_) { return raw; }
  }

  @override
  Widget build(BuildContext context) {
    final isVertrag = widget.typ == 'vertrag';
    final col = isVertrag ? Colors.teal : Colors.deepOrange;
    final label = isVertrag ? 'Vertrag' : 'Kündigung';

    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Icon(isVertrag ? Icons.description : Icons.event_busy, size: 18, color: col.shade700),
          const SizedBox(width: 8),
          Text('${_dokumente.length} $label-Dokument(e)', style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
          const Spacer(),
          if (_uploading) Row(children: [
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            Text(_uploadProgress, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            const SizedBox(width: 8),
          ]),
          FilledButton.icon(
            onPressed: _uploading ? null : _pickAndUpload,
            icon: const Icon(Icons.upload_file, size: 16),
            label: const Text('Hochladen (max 20)', style: TextStyle(fontSize: 12)),
            style: FilledButton.styleFrom(backgroundColor: col.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), minimumSize: Size.zero),
          ),
        ]),
      ),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: col.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: col.shade200)),
        child: Row(children: [
          Icon(Icons.info_outline, size: 13, color: col.shade700),
          const SizedBox(width: 6),
          Expanded(child: Text(
            'Erlaubte Formate: PDF, JPG, JPEG · max. 50 MB pro Datei · max. 20 Dateien gleichzeitig',
            style: TextStyle(fontSize: 10, color: col.shade800),
          )),
        ]),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _dokumente.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.folder_open, size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 8),
                Text('Keine $label-Dokumente', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ]))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _dokumente.length,
                itemBuilder: (_, i) {
                  final d = _dokumente[i];
                  final id = d['id'] is int ? d['id'] as int : int.parse(d['id'].toString());
                  final fn = d['filename']?.toString() ?? 'document';
                  final size = (d['size_bytes'] is int) ? d['size_bytes'] as int : int.tryParse(d['size_bytes']?.toString() ?? '0') ?? 0;
                  final ext = fn.contains('.') ? fn.split('.').last.toLowerCase() : '';
                  final icon = ext == 'pdf' ? Icons.picture_as_pdf : Icons.image;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: col.shade200)),
                    child: Row(children: [
                      Icon(icon, size: 24, color: ext == 'pdf' ? Colors.red.shade400 : Colors.blue.shade400),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(fn, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Row(children: [
                            Text(_humanSize(size), style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                            const SizedBox(width: 10),
                            Text(_fmtDate(d['uploaded_at']?.toString()), style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                          ]),
                        ]),
                      ),
                      IconButton(
                        icon: Icon(Icons.download, size: 18, color: col.shade700),
                        tooltip: 'Öffnen',
                        onPressed: () => _open(id, fn),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                        tooltip: 'Löschen',
                        onPressed: () => _delete(id),
                      ),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }
}
