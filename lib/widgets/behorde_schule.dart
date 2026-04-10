import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../services/api_service.dart';
import 'file_viewer_dialog.dart';
import '../utils/file_picker_helper.dart';

class BehordeSchuleContent extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final Map<String, dynamic> Function(String type) getData;
  final bool Function(String type) isLoading;
  final bool Function(String type) isSaving;
  final void Function(String type) loadData;
  final void Function(String type, Map<String, dynamic> data) saveData;

  const BehordeSchuleContent({
    super.key,
    required this.apiService,
    required this.userId,
    required this.getData,
    required this.isLoading,
    required this.isSaving,
    required this.loadData,
    required this.saveData,
  });

  @override
  State<BehordeSchuleContent> createState() => _BehordeSchuleContentState();
}

class _BehordeSchuleContentState extends State<BehordeSchuleContent> {
  List<Map<String, dynamic>> _schulen = [];
  List<Map<String, dynamic>> _schulenDB = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final sbResult = await widget.apiService.getUserSchulbildung(widget.userId);
      final dbResult = await widget.apiService.getSchulen();
      if (mounted) {
        setState(() {
          _loaded = true;
          if (sbResult['success'] == true && sbResult['data'] != null) {
            _schulen = List<Map<String, dynamic>>.from(sbResult['data']);
          }
          _schulenDB = dbResult;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _reload() async {
    try {
      final result = await widget.apiService.getUserSchulbildung(widget.userId);
      if (mounted && result['success'] == true && result['data'] != null) {
        setState(() => _schulen = List<Map<String, dynamic>>.from(result['data']));
      }
    } catch (_) {}
  }

  void _addSchuleFromDB(Map<String, dynamic> s) async {
    final data = {
      'schul_name': s['name']?.toString() ?? '',
      'schulart': s['schulart']?.toString() ?? '',
      'schul_adresse': s['strasse']?.toString() ?? '',
      'schul_plz_ort': s['plz_ort']?.toString() ?? '',
      'schul_telefon': s['telefon']?.toString() ?? '',
      'schul_email': s['email']?.toString() ?? '',
      'schul_website': s['website']?.toString() ?? '',
      'klassenlehrer': s['schulleitung']?.toString() ?? '',
    };
    await widget.apiService.saveUserSchulbildung(widget.userId, data);
    _reload();
  }

  void _deleteSchule(int id) async {
    await widget.apiService.deleteUserSchulbildung(widget.userId, id);
    _reload();
  }

  Widget _detailRow(IconData icon, String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: Colors.indigo.shade400),
        const SizedBox(width: 8),
        SizedBox(width: 110, child: Text('$label:', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  void _showSchuleDetailModal(BuildContext context, Map<String, dynamic> schule) {
    final dbId = int.tryParse(schule['id'].toString()) ?? 0;
    final dokTypLabels = {
      'halbjahreszeugnis': 'Halbjahreszeugnis',
      'jahreszeugnis': 'Jahreszeugnis',
      'abschlusszeugnis': 'Abschlusszeugnis',
      'abgangszeugnis': 'Abgangszeugnis',
      'schulbescheinigung': 'Schulbescheinigung',
      'zeugnis_anerkennung': 'Zeugnis-Anerkennung',
      'sonstiges': 'Sonstiges',
    };
    List<Map<String, dynamic>> dokumente = [];
    bool docsLoading = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) {
          if (docsLoading) {
            widget.apiService.getSchulbildungDokumente(dbId, widget.userId).then((result) {
              if (ctx.mounted) {
                setM(() {
                  docsLoading = false;
                  if (result['success'] == true && result['data'] != null) {
                    dokumente = List<Map<String, dynamic>>.from(result['data']);
                  }
                });
              }
            }).catchError((_) { if (ctx.mounted) setM(() => docsLoading = false); });
            docsLoading = false;
          }

          Future<void> uploadDok(String dokTyp) async {
            final picked = await FilePickerHelper.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
            if (picked == null || picked.files.isEmpty || picked.files.first.path == null) return;
            final file = picked.files.first;
            try {
              final result = await widget.apiService.uploadSchulbildungDokument(sbId: dbId, userId: widget.userId, dokTyp: dokTyp, dokTitel: file.name, filePath: file.path!, fileName: file.name);
              if (result['success'] == true && ctx.mounted) {
                final reloaded = await widget.apiService.getSchulbildungDokumente(dbId, widget.userId);
                if (ctx.mounted) setM(() { if (reloaded['success'] == true && reloaded['data'] != null) dokumente = List<Map<String, dynamic>>.from(reloaded['data']); });
              }
            } catch (e) { if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red)); }
          }

          Widget buildDokList() {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Align(alignment: Alignment.centerRight, child: ElevatedButton.icon(
                onPressed: () async {
                  final chosen = await showDialog<String>(context: ctx, builder: (dlgCtx) => SimpleDialog(
                    title: const Text('Dokumenttyp wählen', style: TextStyle(fontSize: 15)),
                    children: dokTypLabels.entries.map((e) => SimpleDialogOption(onPressed: () => Navigator.pop(dlgCtx, e.key), child: Text(e.value, style: const TextStyle(fontSize: 14)))).toList(),
                  ));
                  if (chosen != null) await uploadDok(chosen);
                },
                icon: const Icon(Icons.upload_file, size: 16),
                label: const Text('Hochladen', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              )),
              const SizedBox(height: 8),
              if (dokumente.isEmpty)
                Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(children: [Icon(Icons.folder_open, size: 40, color: Colors.grey.shade400), const SizedBox(height: 8), Text('Keine Dokumente', style: TextStyle(fontSize: 13, color: Colors.grey.shade500))])))
              else
                ...dokumente.map((doc) {
                  final docId = int.tryParse(doc['id'].toString()) ?? 0;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
                    child: Row(children: [
                      Icon(Icons.description, size: 20, color: Colors.indigo.shade400),
                      const SizedBox(width: 8),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(doc['dok_titel'] ?? doc['datei_name'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                        Text(dokTypLabels[doc['dok_typ']] ?? doc['dok_typ'] ?? '', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      ])),
                      IconButton(icon: Icon(Icons.visibility, size: 18, color: Colors.blue.shade600), tooltip: 'Ansehen', onPressed: () async {
                        try {
                          final response = await widget.apiService.downloadSchulbildungDokument(docId);
                          if (response.statusCode == 200 && ctx.mounted) {
                            final dir = await getTemporaryDirectory();
                            final f = File('${dir.path}/${doc['datei_name'] ?? 'dokument'}');
                            await f.writeAsBytes(response.bodyBytes);
                            if (ctx.mounted) { final handled = await FileViewerDialog.show(ctx, f.path, doc['datei_name'] ?? ''); if (!handled && ctx.mounted) await OpenFilex.open(f.path); }
                          }
                        } catch (e) { if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red)); }
                      }, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                      const SizedBox(width: 4),
                      IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400), tooltip: 'Löschen', onPressed: () async {
                        await widget.apiService.deleteSchulbildungDokument(docId);
                        final reloaded = await widget.apiService.getSchulbildungDokumente(dbId, widget.userId);
                        if (ctx.mounted) setM(() { if (reloaded['success'] == true && reloaded['data'] != null) dokumente = List<Map<String, dynamic>>.from(reloaded['data']); });
                      }, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                    ]),
                  );
                }),
            ]);
          }

          return DefaultTabController(
            length: 2,
            child: AlertDialog(
              title: Row(children: [
                Icon(Icons.school, size: 22, color: Colors.indigo.shade700),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(schule['schul_name'] ?? '', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
                  if ((schule['schulart'] ?? '').toString().isNotEmpty)
                    Text(schule['schulart'], style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ])),
                IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () { Navigator.pop(ctx); _reload(); }, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
              ]),
              content: SizedBox(width: 600, height: 450, child: Column(children: [
                TabBar(labelColor: Colors.indigo.shade700, unselectedLabelColor: Colors.grey.shade600, indicatorColor: Colors.indigo, labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), tabs: const [Tab(text: 'Details'), Tab(text: 'Zeugnisse & Dokumente')]),
                Expanded(child: TabBarView(children: [
                  SingleChildScrollView(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.indigo.shade200)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Schulinformationen', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
                        const SizedBox(height: 8),
                        _detailRow(Icons.school, 'Schule', schule['schul_name']),
                        _detailRow(Icons.category, 'Schulart', schule['schulart']),
                        _detailRow(Icons.location_on, 'Adresse', '${schule['schul_adresse'] ?? ''}${(schule['schul_plz_ort'] ?? '').toString().isNotEmpty ? ', ${schule['schul_plz_ort']}' : ''}'),
                        _detailRow(Icons.phone, 'Telefon', schule['schul_telefon']),
                        _detailRow(Icons.email, 'E-Mail', schule['schul_email']),
                        _detailRow(Icons.language, 'Website', schule['schul_website']),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.green.shade200)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text('Schülerdaten', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                          const Spacer(),
                          InkWell(
                            onTap: () => _showEditSchulerdatenDialog(ctx, schule),
                            child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(6)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.edit, size: 13, color: Colors.green.shade700), const SizedBox(width: 4), Text('Bearbeiten', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.green.shade700))])),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        _detailRow(Icons.class_, 'Klasse', schule['klasse']),
                        _detailRow(Icons.person, 'Klassenlehrer/in', schule['klassenlehrer']),
                        _detailRow(Icons.calendar_today, 'Schulbeginn', schule['schul_beginn']),
                        _detailRow(Icons.event, 'Schulende', schule['schul_ende']),
                        if ((schule['notizen'] ?? '').toString().isNotEmpty) _detailRow(Icons.note, 'Notizen', schule['notizen']),
                      ]),
                    ),
                  ])),
                  SingleChildScrollView(padding: const EdgeInsets.all(12), child: buildDokList()),
                ])),
              ])),
              contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              actions: [TextButton(onPressed: () { Navigator.pop(ctx); _reload(); }, child: const Text('Schließen'))],
            ),
          );
        },
      ),
    );
  }

  void _showEditSchulerdatenDialog(BuildContext parentCtx, Map<String, dynamic> schule) {
    final kC = TextEditingController(text: schule['klasse'] ?? '');
    final klC = TextEditingController(text: schule['klassenlehrer'] ?? '');
    final sbC = TextEditingController(text: schule['schul_beginn'] ?? '');
    final seC = TextEditingController(text: schule['schul_ende'] ?? '');
    final nC = TextEditingController(text: schule['notizen'] ?? '');

    Future<void> pickDate(BuildContext dlgCtx, TextEditingController ctrl) async {
      final picked = await showDatePicker(context: dlgCtx, initialDate: DateTime.now(), firstDate: DateTime(1900), lastDate: DateTime(2500), locale: const Locale('de'));
      if (picked != null) ctrl.text = '${picked.day.toString().padLeft(2, '0')}.${picked.month.toString().padLeft(2, '0')}.${picked.year}';
    }

    showDialog(
      context: parentCtx,
      builder: (ctx) => AlertDialog(
        title: const Text('Schülerdaten bearbeiten', style: TextStyle(fontSize: 16)),
        content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: TextField(controller: kC, decoration: InputDecoration(labelText: 'Klasse', hintText: 'z.B. 8a', prefixIcon: const Icon(Icons.class_, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), style: const TextStyle(fontSize: 13))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: klC, decoration: InputDecoration(labelText: 'Klassenlehrer/in', prefixIcon: const Icon(Icons.person, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), style: const TextStyle(fontSize: 13))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: sbC, readOnly: true, onTap: () => pickDate(ctx, sbC), decoration: InputDecoration(labelText: 'Schulbeginn', prefixIcon: const Icon(Icons.calendar_today, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), style: const TextStyle(fontSize: 13))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: seC, readOnly: true, onTap: () => pickDate(ctx, seC), decoration: InputDecoration(labelText: 'Schulende', prefixIcon: const Icon(Icons.event, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), style: const TextStyle(fontSize: 13))),
          ]),
          const SizedBox(height: 12),
          TextField(controller: nC, maxLines: 3, decoration: InputDecoration(labelText: 'Notizen', prefixIcon: const Icon(Icons.note, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), style: const TextStyle(fontSize: 13)),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () async {
              final updated = Map<String, dynamic>.from(schule);
              updated['klasse'] = kC.text.trim();
              updated['klassenlehrer'] = klC.text.trim();
              updated['schul_beginn'] = sbC.text.trim();
              updated['schul_ende'] = seC.text.trim();
              updated['notizen'] = nC.text.trim();
              await widget.apiService.saveUserSchulbildung(widget.userId, updated);
              if (ctx.mounted) Navigator.pop(ctx);
              // Update local data
              setState(() {
                final idx = _schulen.indexWhere((s) => s['id'].toString() == schule['id'].toString());
                if (idx >= 0) _schulen[idx] = updated;
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.indigo.shade600, Colors.indigo.shade400]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              const Icon(Icons.school, size: 32, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Schulbildung', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                Text('${_schulen.length} Schule(n) eingetragen', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8))),
              ])),
              ElevatedButton.icon(
                onPressed: () => _showAddSchuleDialog(),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Hinzufügen', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.indigo.shade700, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // List of schools
          if (_schulen.isEmpty)
            Container(
              width: double.infinity, padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
              child: Column(children: [
                Icon(Icons.school_outlined, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 8),
                Text('Keine Schulbildung eingetragen', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
              ]),
            )
          else
            ..._schulen.map((schule) {
              final name = schule['schul_name'] ?? '';
              final art = schule['schulart'] ?? '';
              final ort = schule['schul_plz_ort'] ?? '';
              final klasse = schule['klasse'] ?? '';
              final beginn = schule['schul_beginn'] ?? '';
              final ende = schule['schul_ende'] ?? '';
              final id = int.tryParse(schule['id'].toString()) ?? 0;

              return InkWell(
                onTap: () => _showSchuleDetailModal(context, schule),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.indigo.shade200)),
                  child: Row(children: [
                    Icon(Icons.school, size: 28, color: Colors.indigo.shade700),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
                      if (art.isNotEmpty) Text(art, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      if (ort.isNotEmpty) Text(ort, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                      if (klasse.isNotEmpty || beginn.isNotEmpty)
                        Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [
                          if (klasse.isNotEmpty) ...[
                            Icon(Icons.class_, size: 12, color: Colors.indigo.shade400),
                            const SizedBox(width: 4),
                            Text('Klasse $klasse', style: TextStyle(fontSize: 11, color: Colors.indigo.shade600)),
                            const SizedBox(width: 8),
                          ],
                          if (beginn.isNotEmpty) ...[
                            Icon(Icons.calendar_today, size: 12, color: Colors.indigo.shade400),
                            const SizedBox(width: 4),
                            Text('$beginn${ende.isNotEmpty ? ' – $ende' : ''}', style: TextStyle(fontSize: 11, color: Colors.indigo.shade600)),
                          ],
                        ])),
                    ])),
                    Column(children: [
                      Icon(Icons.open_in_new, size: 16, color: Colors.indigo.shade400),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () => _deleteSchule(id),
                        child: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400),
                      ),
                    ]),
                  ]),
                ),
              );
            }),
        ],
      ),
    );
  }

  void _showAddSchuleDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Row(children: [
            Icon(Icons.school, size: 22, color: Colors.indigo.shade700),
            const SizedBox(width: 8),
            const Text('Schule hinzufügen', style: TextStyle(fontSize: 16)),
          ]),
          content: SizedBox(
            width: 500,
            height: 400,
            child: _schulenDB.isEmpty
                ? Center(child: Text('Keine Schulen in der Datenbank', style: TextStyle(color: Colors.grey.shade500)))
                : ListView.builder(
                    itemCount: _schulenDB.length,
                    itemBuilder: (ctx, i) {
                      final s = _schulenDB[i];
                      final name = s['name']?.toString() ?? '';
                      final art = s['schulart']?.toString() ?? '';
                      final ort = s['plz_ort']?.toString() ?? '';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.indigo.shade100)),
                        child: InkWell(
                          onTap: () {
                            Navigator.pop(ctx);
                            _addSchuleFromDB(s);
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
                            Icon(Icons.school, size: 24, color: Colors.indigo.shade400),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
                              if (art.isNotEmpty) Text(art, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                              if (ort.isNotEmpty) Text(ort, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                            ])),
                            Icon(Icons.add_circle_outline, size: 20, color: Colors.indigo.shade400),
                          ])),
                        ),
                      );
                    },
                  ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen'))],
        );
      },
    );
  }
}
