import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';
import 'file_viewer_dialog.dart';

class BehordeSozialamtContent extends StatefulWidget {
  final ApiService? apiService;
  final int? userId;
  final Map<String, dynamic> Function(String type) getData;
  final bool Function(String type) isLoading;
  final bool Function(String type) isSaving;
  final void Function(String type) loadData;
  final void Function(String type, Map<String, dynamic> data) saveData;
  final Widget Function(String type, TextEditingController controller) dienststelleBuilder;

  const BehordeSozialamtContent({
    super.key,
    this.apiService,
    this.userId,
    required this.getData,
    required this.isLoading,
    required this.isSaving,
    required this.loadData,
    required this.saveData,
    required this.dienststelleBuilder,
  });

  static const type = 'sozialamt';

  @override
  State<BehordeSozialamtContent> createState() => _BehordeSozialamtContentState();
}

class _BehordeSozialamtContentState extends State<BehordeSozialamtContent> {
  static const type = 'sozialamt';
  Map<String, Map<String, dynamic>> _dbData = {};
  List<Map<String, dynamic>> _antraege = [];
  List<Map<String, dynamic>> _bewilligungen = [];
  List<Map<String, dynamic>> _korrespondenz = [];
  bool _loaded = false;
  bool _saving = false;
  Set<String> _checkedDocsGlobal = {};

  @override
  void initState() {
    super.initState();
    _loadFromDB();
  }

  Future<void> _loadFromDB() async {
    if (widget.apiService == null || widget.userId == null) {
      setState(() => _loaded = true);
      return;
    }
    final r = await widget.apiService!.getSozialamtData(widget.userId!);
    if (!mounted) return;
    if (r['success'] == true && r['data'] is Map) {
      final raw = r['data'] as Map;
      _dbData = {};
      for (final entry in raw.entries) {
        final map = Map<String, dynamic>.from(entry.value as Map);
        // Parse JSON strings back to lists/maps (stored as JSON in DB)
        for (final k in map.keys.toList()) {
          final v = map[k];
          if (v is String && v.startsWith('[')) {
            try { map[k] = jsonDecode(v); } catch (_) {}
          } else if (v is String && v.startsWith('{')) {
            try { map[k] = jsonDecode(v); } catch (_) {}
          }
        }
        _dbData[entry.key.toString()] = map;
      }
    }
    // Load from dedicated tables
    if (widget.apiService != null && widget.userId != null) {
      final aR = await widget.apiService!.listSozialamtAntraege(widget.userId!);
      if (aR['success'] == true && aR['data'] is List) _antraege = (aR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final bR = await widget.apiService!.listSozialamtBewilligungen(widget.userId!);
      if (bR['success'] == true && bR['data'] is List) _bewilligungen = (bR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final kR = await widget.apiService!.listSozialamtKorrespondenz(widget.userId!);
      if (kR['success'] == true && kR['data'] is List) _korrespondenz = (kR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    // Load checked docs from DB (stored in sozialamt_data bereich='checked_docs')
    final cd = _dbData['checked_docs'];
    if (cd != null && cd['list'] is List) {
      _checkedDocsGlobal = Set<String>.from((cd['list'] as List).map((e) => e.toString()));
    } else if (cd != null && cd['list'] is String) {
      try { _checkedDocsGlobal = Set<String>.from(jsonDecode(cd['list'] as String)); } catch (_) {}
    }
    setState(() => _loaded = true);
  }

  Future<void> _save() async {
    if (widget.apiService == null || widget.userId == null) return;
    setState(() => _saving = true);
    await widget.apiService!.saveSozialamtData(widget.userId!, _dbData);
    if (mounted) setState(() => _saving = false);
  }

  Map<String, dynamic> _b(String key) {
    _dbData[key] ??= {};
    return _dbData[key]!;
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());

    return DefaultTabController(
      length: 5,
      child: Column(children: [
        TabBar(
          labelColor: Colors.indigo.shade700,
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: Colors.indigo.shade700,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.account_balance, size: 16), text: 'Zuständige Behörde'),
            Tab(icon: Icon(Icons.person, size: 16), text: 'Mitarbeiter/in'),
            Tab(icon: Icon(Icons.description, size: 16), text: 'Anträge'),
            Tab(icon: Icon(Icons.check_circle, size: 16), text: 'Bewilligung'),
            Tab(icon: Icon(Icons.mail, size: 16), text: 'Korrespondenz'),
          ],
        ),
        Expanded(child: TabBarView(children: [
          _buildBehoerdeTab(),
          _buildMitarbeiterTab(),
          _buildAntraegeTab(),
          _buildBewilligungTab(),
          _buildKorrespondenzTab(),
        ])),
      ]),
    );
  }

  Widget _buildBehoerdeTab() {
    final d = _b('behoerde');
    final selected = d['name']?.toString() ?? '';
    final sel = _sozialamtListe.where((s) => s['name'] == selected).firstOrNull;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.account_balance, size: 20, color: Colors.indigo.shade700),
          const SizedBox(width: 8),
          Expanded(child: Text('Zuständiges Sozialamt', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo.shade700))),
          OutlinedButton.icon(
            icon: const Icon(Icons.search, size: 16),
            label: Text(selected.isEmpty ? 'Auswählen' : 'Ändern', style: const TextStyle(fontSize: 12)),
            onPressed: () => _showBehoerdeSelectDialog(d),
          ),
        ]),
        const SizedBox(height: 12),
        if (selected.isEmpty)
          Container(
            width: double.infinity, padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
            child: Column(children: [
              Icon(Icons.search, size: 40, color: Colors.grey.shade400),
              const SizedBox(height: 8),
              Text('Kein Sozialamt ausgewählt', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              const SizedBox(height: 4),
              Text('Tippen Sie auf "Auswählen" um das zuständige Amt zu suchen.', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ]),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.indigo.shade300)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(selected, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo.shade900)),
              if (sel != null) ...[
                const SizedBox(height: 6),
                _infoRow(Icons.location_on, '${sel['adresse']}, ${sel['plz_ort']}'),
                _infoRow(Icons.phone, sel['telefon'] ?? ''),
                _infoRow(Icons.access_time, sel['oeffnungszeiten'] ?? ''),
                _infoRow(Icons.info, sel['zustaendigkeit'] ?? ''),
              ],
            ]),
          ),
      ]),
    );
  }

  void _showBehoerdeSelectDialog(Map<String, dynamic> d) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(children: [
          Icon(Icons.search, color: Colors.indigo.shade700),
          const SizedBox(width: 8),
          const Text('Sozialamt auswählen'),
        ]),
        content: SizedBox(
          width: 500, height: 400,
          child: ListView(children: _sozialamtListe.map((s) {
            return InkWell(
              onTap: () {
                setState(() { d['name'] = s['name']; d['adresse'] = s['adresse']; d['plz_ort'] = s['plz_ort']; d['telefon'] = s['telefon']; d['oeffnungszeiten'] = s['oeffnungszeiten']; });
                _save();
                Navigator.pop(ctx);
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
                child: Row(children: [
                  Icon(Icons.account_balance, size: 20, color: Colors.indigo.shade600),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s['name']!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade900)),
                    Text('${s['adresse']}, ${s['plz_ort']}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    Text(s['zustaendigkeit']!, style: TextStyle(fontSize: 10, color: Colors.indigo.shade400, fontStyle: FontStyle.italic)),
                  ])),
                ]),
              ),
            );
          }).toList()),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen'))],
      ),
    );
  }

  bool _mitarbeiterEditing = false;

  Widget _buildMitarbeiterTab() {
    final d = _b('mitarbeiter');
    final hasData = (d['name']?.toString() ?? '').isNotEmpty;
    final readOnly = hasData && !_mitarbeiterEditing;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.person, size: 20, color: Colors.indigo.shade700),
          const SizedBox(width: 8),
          Expanded(child: Text('Zuständige/r Sachbearbeiter/in', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo.shade700))),
          if (hasData)
            IconButton(
              icon: Icon(_mitarbeiterEditing ? Icons.check : Icons.edit, size: 20, color: Colors.indigo.shade700),
              tooltip: _mitarbeiterEditing ? 'Fertig' : 'Bearbeiten',
              onPressed: () {
                if (_mitarbeiterEditing) _save();
                setState(() => _mitarbeiterEditing = !_mitarbeiterEditing);
              },
            ),
        ]),
        const SizedBox(height: 12),
        if (readOnly) ...[
          _readOnlyRow(Icons.person, 'Anrede', d['anrede']),
          _readOnlyRow(Icons.badge, 'Name', d['name']),
          _readOnlyRow(Icons.phone, 'Telefon', d['telefon']),
          _readOnlyRow(Icons.email, 'E-Mail', d['email']),
          _readOnlyRow(Icons.room, 'Zimmer', d['zimmer']),
          _readOnlyRow(Icons.access_time, 'Sprechzeiten', d['sprechzeiten']),
          _readOnlyRow(Icons.note, 'Notizen', d['notizen']),
        ] else ...[
          _field(d, 'anrede', 'Anrede', Icons.person, hint: 'Frau / Herr'),
          _field(d, 'name', 'Name', Icons.badge),
          _field(d, 'telefon', 'Telefon (direkt)', Icons.phone),
          _field(d, 'email', 'E-Mail', Icons.email),
          _field(d, 'zimmer', 'Zimmer / Raum', Icons.room),
          _field(d, 'sprechzeiten', 'Sprechzeiten', Icons.access_time),
          _field(d, 'notizen', 'Notizen', Icons.note, maxLines: 3),
          _saveBtn(),
        ],
      ]),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Icon(icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
      ]),
    );
  }

  Widget _readOnlyRow(IconData icon, String label, dynamic value) {
    final s = value?.toString() ?? '';
    if (s.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        SizedBox(width: 100, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600))),
        Expanded(child: Text(s, style: const TextStyle(fontSize: 13))),
      ]),
    );
  }

  Widget _buildAntraegeTab() {
    final list = _antraege;
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Row(children: [
        Icon(Icons.description, size: 20, color: Colors.indigo.shade700), const SizedBox(width: 8),
        Expanded(child: Text('Anträge (${list.length})', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo.shade700))),
        ElevatedButton.icon(onPressed: () => _showAntragDialog(), icon: const Icon(Icons.add, size: 16), label: const Text('Neuer Antrag', style: TextStyle(fontSize: 12)), style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white)),
      ])),
      Expanded(child: list.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.description, size: 48, color: Colors.grey.shade300), const SizedBox(height: 8), Text('Keine Anträge', style: TextStyle(color: Colors.grey.shade500))]))
          : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: list.length, itemBuilder: (_, i) {
              final a = list[i];
              return Card(child: ListTile(
                leading: Icon(Icons.description, color: Colors.indigo.shade600),
                title: Text(a['leistung']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text('${a['datum'] ?? ''} • ${a['methode'] ?? ''} • ${a['status'] ?? ''}', style: const TextStyle(fontSize: 11)),
                onTap: () {
                  final aid = int.tryParse(a['id']?.toString() ?? '');
                  if (aid != null) _showAntragDetailDialog(aid, a);
                },
                trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
              ));
            })),
    ]);
  }

  Widget _buildBewilligungTab() {
    final list = _bewilligungen;
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Row(children: [
        Icon(Icons.check_circle, size: 20, color: Colors.green.shade700), const SizedBox(width: 8),
        Expanded(child: Text('Bewilligungen (${list.length})', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green.shade700))),
        ElevatedButton.icon(onPressed: () => _showBewilligungDialog(), icon: const Icon(Icons.add, size: 16), label: const Text('Neu', style: TextStyle(fontSize: 12)), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white)),
      ])),
      Expanded(child: list.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.check_circle_outline, size: 48, color: Colors.grey.shade300), const SizedBox(height: 8), Text('Keine Bewilligungen', style: TextStyle(color: Colors.grey.shade500))]))
          : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: list.length, itemBuilder: (_, i) {
              final b = list[i];
              final ok = b['bewilligt'] == true || b['bewilligt'] == 'true' || b['bewilligt'] == 1 || b['bewilligt'] == '1';
              final ausz = b['auszahlung']?.toString() ?? '';
              final az = b['aktenzeichen']?.toString() ?? '';
              final zeitraum = (b['zeitraum_von']?.toString() ?? '').isNotEmpty ? '${b['zeitraum_von']} – ${b['zeitraum_bis'] ?? ''}' : '';
              return Card(child: ListTile(
                leading: Icon(ok ? Icons.check_circle : Icons.cancel, color: ok ? Colors.green : Colors.red, size: 28),
                title: Text(b['leistung']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${ok ? 'Bewilligt' : 'Abgelehnt'} • Bescheid: ${b['bescheid_datum'] ?? b['datum'] ?? ''}', style: TextStyle(fontSize: 11, color: ok ? Colors.green.shade700 : Colors.red.shade700)),
                  if (az.isNotEmpty) Text('Az.: $az', style: TextStyle(fontSize: 10, color: Colors.indigo.shade600, fontWeight: FontWeight.w600)),
                  if ((b['erhalten_am']?.toString() ?? '').isNotEmpty) Text('Erhalten per Post: ${b['erhalten_am']}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  if (zeitraum.isNotEmpty) Text('Zeitraum: $zeitraum', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  if (ausz.isNotEmpty) Text('Auszahlung: $ausz €/Monat', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                  if (b['widerspruch'] == true || b['widerspruch'] == 'true' || b['widerspruch'] == 1 || b['widerspruch'] == '1') Text('Widerspruch eingelegt${(b['widerspruch_datum']?.toString() ?? '').isNotEmpty ? ' am ${b['widerspruch_datum']}' : ''}', style: TextStyle(fontSize: 10, color: Colors.orange.shade700)),
                ]),
                isThreeLine: true,
                onTap: () => _showBewilligungDetailDialog(b),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400), tooltip: 'Löschen', onPressed: () async {
                    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                      title: const Text('Bewilligung löschen?'),
                      content: Text('${b['leistung'] ?? ''} vom ${b['bescheid_datum'] ?? ''} wirklich löschen?'),
                      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')), FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('Löschen'))],
                    ));
                    if (confirm == true) {
                      final bid = int.tryParse(b['id']?.toString() ?? '');
                      if (bid != null && widget.apiService != null) await widget.apiService!.deleteSozialamtBewilligung(bid);
                      _loadFromDB();
                    }
                  }),
                  Icon(Icons.chevron_right, color: Colors.grey.shade400),
                ]),
              ));
            })),
    ]);
  }

  Widget _buildKorrespondenzTab() {
    final list = _korrespondenz;
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Expanded(child: Text('${list.length} Einträge', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
        FilledButton.icon(icon: const Icon(Icons.call_received, size: 14), label: const Text('Eingang', style: TextStyle(fontSize: 11)), style: FilledButton.styleFrom(backgroundColor: Colors.green.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero), onPressed: () => _showKorrDialog('eingang')),
        const SizedBox(width: 6),
        FilledButton.icon(icon: const Icon(Icons.call_made, size: 14), label: const Text('Ausgang', style: TextStyle(fontSize: 11)), style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero), onPressed: () => _showKorrDialog('ausgang')),
      ])),
      Expanded(child: list.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.mail_outline, size: 48, color: Colors.grey.shade300), const SizedBox(height: 6), Text('Keine Korrespondenz', style: TextStyle(fontSize: 12, color: Colors.grey.shade500))]))
          : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: list.length, itemBuilder: (_, i) {
              final k = list[i]; final isEin = k['richtung'] == 'eingang';
              return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: isEin ? Colors.green.shade200 : Colors.blue.shade200)),
                child: Row(children: [
                  Icon(isEin ? Icons.call_received : Icons.call_made, size: 18, color: isEin ? Colors.green.shade700 : Colors.blue.shade700), const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(k['betreff']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isEin ? Colors.green.shade800 : Colors.blue.shade800)),
                    Text(k['datum']?.toString() ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  ])),
                  IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), onPressed: () async {
                    final kid = int.tryParse(k['id']?.toString() ?? '');
                    if (kid != null && widget.apiService != null) await widget.apiService!.deleteSozialamtKorrespondenz(kid);
                    _loadFromDB();
                  }, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28)),
                ]),
              );
            })),
    ]);
  }

  void _showAntragDialog({int? editIndex}) {
    final ex = editIndex != null ? _antraege[editIndex] : null;
    final datumC = TextEditingController(text: ex?['datum']?.toString() ?? '');
    final notizC = TextEditingController(text: ex?['notiz']?.toString() ?? '');
    String leistung = ex?['leistung']?.toString() ?? '';
    String methode = ex?['methode']?.toString() ?? '';
    String status = ex?['status']?.toString() ?? 'eingereicht';
    final leistungen = ['Grundsicherung im Alter', 'Grundsicherung bei Erwerbsminderung', 'Hilfe zum Lebensunterhalt', 'Eingliederungshilfe', 'Hilfe zur Pflege', 'Bildung und Teilhabe', 'Bestattungskosten', 'Blindengeld', 'Sonstige'];
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) => AlertDialog(
      title: Text(editIndex != null ? 'Antrag bearbeiten' : 'Neuer Antrag'),
      content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(value: leistungen.contains(leistung) ? leistung : null, decoration: InputDecoration(labelText: 'Leistung *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), items: leistungen.map((l) => DropdownMenuItem(value: l, child: Text(l, style: const TextStyle(fontSize: 12)))).toList(), onChanged: (v) => setD(() => leistung = v ?? '')),
        const SizedBox(height: 8),
        TextField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onTap: () async { final p = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de')); if (p != null) setD(() => datumC.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}'); }),
        const SizedBox(height: 8),
        Wrap(spacing: 6, children: [('online', 'Online'), ('persoenlich', 'Persönlich'), ('postalisch', 'Postalisch'), ('email', 'E-Mail')].map((m) => ChoiceChip(label: Text(m.$2, style: TextStyle(fontSize: 11, color: methode == m.$1 ? Colors.white : Colors.black87)), selected: methode == m.$1, selectedColor: Colors.indigo, onSelected: (_) => setD(() => methode = m.$1))).toList()),
        const SizedBox(height: 8),
        Wrap(spacing: 6, children: [('eingereicht', 'Eingereicht'), ('in_bearbeitung', 'In Bearbeitung'), ('bewilligt', 'Bewilligt'), ('abgelehnt', 'Abgelehnt'), ('widerspruch', 'Widerspruch')].map((s) => ChoiceChip(label: Text(s.$2, style: TextStyle(fontSize: 11, color: status == s.$1 ? Colors.white : Colors.black87)), selected: status == s.$1, selectedColor: Colors.teal, onSelected: (_) => setD(() => status = s.$1))).toList()),
        const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          if (leistung.isEmpty || datumC.text.isEmpty) return;
          if (widget.apiService != null && widget.userId != null) {
            await widget.apiService!.saveSozialamtAntrag(widget.userId!, {
              if (ex != null) 'id': ex['id'],
              'leistung': leistung, 'datum': datumC.text, 'methode': methode, 'status': status, 'notiz': notizC.text,
            });
          }
          if (ctx.mounted) Navigator.pop(ctx);
          _loadFromDB();
        }, child: Text(editIndex != null ? 'Speichern' : 'Hinzufügen')),
      ],
    )));
  }

  void _showBewilligungDialog({Map<String, dynamic>? existing}) {
    final isEdit = existing != null;
    String leistung = existing?['leistung']?.toString() ?? '';
    final aktenzeichenC = TextEditingController(text: existing?['aktenzeichen']?.toString() ?? '');
    final bescheidDatumC = TextEditingController(text: existing?['bescheid_datum']?.toString() ?? '');
    final erhaltenAmC = TextEditingController(text: existing?['erhalten_am']?.toString() ?? '');
    final zeitraumVonC = TextEditingController(text: existing?['zeitraum_von']?.toString() ?? '');
    final zeitraumBisC = TextEditingController(text: existing?['zeitraum_bis']?.toString() ?? '');
    final regelbedarfC = TextEditingController(text: existing?['regelbedarf']?.toString() ?? '');
    final mehrbedarfC = TextEditingController(text: existing?['mehrbedarf']?.toString() ?? '');
    final kaltmieteC = TextEditingController(text: existing?['kaltmiete']?.toString() ?? '');
    final nebenkostenC = TextEditingController(text: existing?['nebenkosten']?.toString() ?? '');
    final heizkostenC = TextEditingController(text: existing?['heizkosten']?.toString() ?? '');
    final einkommenC = TextEditingController(text: existing?['einkommen']?.toString() ?? '');
    final auszahlungC = TextEditingController(text: existing?['auszahlung']?.toString() ?? '');
    final notizC = TextEditingController(text: existing?['notiz']?.toString() ?? '');
    bool bewilligt = existing?['bewilligt'] == true || existing?['bewilligt'] == 'true' || existing?['bewilligt'] == 1 || existing?['bewilligt'] == '1' || (existing == null);
    bool widerspruch = existing?['widerspruch'] == true || existing?['widerspruch'] == 'true' || existing?['widerspruch'] == 1 || existing?['widerspruch'] == '1';
    final widerspruchDatumC = TextEditingController(text: existing?['widerspruch_datum']?.toString() ?? '');
    final leistungen = ['Grundsicherung im Alter', 'Grundsicherung bei Erwerbsminderung', 'Hilfe zum Lebensunterhalt', 'Eingliederungshilfe', 'Hilfe zur Pflege', 'Bildung und Teilhabe', 'Blindengeld', 'Sonstige'];

    Future<void> pickDate(BuildContext ctx, TextEditingController c) async {
      final p = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
      if (p != null) c.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}';
    }

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(isEdit ? 'Bewilligungsbescheid bearbeiten' : 'Bewilligungsbescheid erfassen'),
      content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        DropdownButtonFormField<String>(value: leistungen.contains(leistung) ? leistung : null, decoration: InputDecoration(labelText: 'Leistungsart *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), items: leistungen.map((l) => DropdownMenuItem(value: l, child: Text(l, style: const TextStyle(fontSize: 12)))).toList(), onChanged: (v) => setD(() => leistung = v ?? '')),
        const SizedBox(height: 8),
        TextField(controller: aktenzeichenC, decoration: InputDecoration(labelText: 'Aktenzeichen', prefixIcon: const Icon(Icons.numbers, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 8),
        Row(children: [
          ChoiceChip(avatar: Icon(Icons.check_circle, size: 14, color: bewilligt ? Colors.white : Colors.green), label: Text('Bewilligt', style: TextStyle(fontSize: 11, color: bewilligt ? Colors.white : Colors.black87)), selected: bewilligt, selectedColor: Colors.green, onSelected: (_) => setD(() => bewilligt = true)),
          const SizedBox(width: 8),
          ChoiceChip(avatar: Icon(Icons.cancel, size: 14, color: !bewilligt ? Colors.white : Colors.red), label: Text('Abgelehnt', style: TextStyle(fontSize: 11, color: !bewilligt ? Colors.white : Colors.black87)), selected: !bewilligt, selectedColor: Colors.red, onSelected: (_) => setD(() => bewilligt = false)),
        ]),
        const SizedBox(height: 8),
        TextField(controller: bescheidDatumC, readOnly: true, decoration: InputDecoration(labelText: 'Bescheid-Datum *', prefixIcon: const Icon(Icons.calendar_today, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onTap: () async { await pickDate(ctx2, bescheidDatumC); setD(() {}); }),
        const SizedBox(height: 8),
        TextField(controller: erhaltenAmC, readOnly: true, decoration: InputDecoration(labelText: 'Erhalten per Post am', prefixIcon: const Icon(Icons.local_post_office, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), helperText: 'Wichtig für Widerspruchsfrist (1 Monat ab Zugang)'), onTap: () async { await pickDate(ctx2, erhaltenAmC); setD(() {}); }),
        const SizedBox(height: 8),
        Text('Bewilligungszeitraum', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: TextField(controller: zeitraumVonC, readOnly: true, decoration: InputDecoration(labelText: 'Von', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onTap: () async { await pickDate(ctx2, zeitraumVonC); setD(() {}); })),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: zeitraumBisC, readOnly: true, decoration: InputDecoration(labelText: 'Bis', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onTap: () async { await pickDate(ctx2, zeitraumBisC); setD(() {}); })),
        ]),
        if (bewilligt) ...[
          const SizedBox(height: 12),
          Text('Berechnungsbogen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: TextField(controller: regelbedarfC, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Regelbedarf €', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: mehrbedarfC, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Mehrbedarf €', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
          ]),
          const SizedBox(height: 8),
          Text('Kosten der Unterkunft (KdU)', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: TextField(controller: kaltmieteC, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Kaltmiete €', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
            const SizedBox(width: 6),
            Expanded(child: TextField(controller: nebenkostenC, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Nebenkosten €', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
            const SizedBox(width: 6),
            Expanded(child: TextField(controller: heizkostenC, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Heizkosten €', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: einkommenC, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Anrechenb. Einkommen €', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: auszahlungC, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Auszahlung €/Monat', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade800))),
          ]),
        ],
        const SizedBox(height: 8),
        Row(children: [
          Checkbox(value: widerspruch, onChanged: (v) => setD(() => widerspruch = v ?? false)),
          const Text('Widerspruch eingelegt', style: TextStyle(fontSize: 12)),
        ]),
        if (widerspruch)
          TextField(controller: widerspruchDatumC, readOnly: true, decoration: InputDecoration(labelText: 'Widerspruch am', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onTap: () async { await pickDate(ctx2, widerspruchDatumC); setD(() {}); }),
        const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notizen', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          if (leistung.isEmpty || bescheidDatumC.text.isEmpty) {
            ScaffoldMessenger.of(ctx2).showSnackBar(SnackBar(content: Text('Bitte Leistungsart und Bescheid-Datum ausfüllen'), backgroundColor: Colors.red));
            return;
          }
          if (widget.apiService != null && widget.userId != null) {
            final res = await widget.apiService!.saveSozialamtBewilligung(widget.userId!, {
              if (isEdit) 'id': existing['id'],
              'leistung': leistung, 'aktenzeichen': aktenzeichenC.text.trim(), 'bewilligt': bewilligt, 'bescheid_datum': bescheidDatumC.text, 'erhalten_am': erhaltenAmC.text,
              'zeitraum_von': zeitraumVonC.text, 'zeitraum_bis': zeitraumBisC.text,
              'regelbedarf': double.tryParse(regelbedarfC.text), 'mehrbedarf': double.tryParse(mehrbedarfC.text),
              'kaltmiete': double.tryParse(kaltmieteC.text), 'nebenkosten': double.tryParse(nebenkostenC.text), 'heizkosten': double.tryParse(heizkostenC.text),
              'einkommen': double.tryParse(einkommenC.text), 'auszahlung': double.tryParse(auszahlungC.text),
              'widerspruch': widerspruch, 'widerspruch_datum': widerspruchDatumC.text, 'notiz': notizC.text,
            });
            if (res['success'] != true) {
              if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Fehler: ${res['message'] ?? 'Speichern fehlgeschlagen'}'), backgroundColor: Colors.red));
              return;
            }
          } else {
            if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Fehler: API nicht verfügbar'), backgroundColor: Colors.red));
            return;
          }
          if (ctx.mounted) Navigator.pop(ctx);
          _loadFromDB();
        }, child: Text(isEdit ? 'Speichern' : 'Hinzufügen')),
      ],
    )));
  }

  void _showBewilligungDetailDialog(Map<String, dynamic> bewilligung) {
    final bid = int.tryParse(bewilligung['id']?.toString() ?? '');
    if (bid == null || widget.apiService == null) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(width: 600, height: 580, child: _BewilligungDetailView(
          apiService: widget.apiService!,
          bewilligungId: bid,
          bewilligung: bewilligung,
          onEdit: () { Navigator.pop(ctx); _showBewilligungDialog(existing: bewilligung); },
          onChanged: () => _loadFromDB(),
        )),
      ),
    );
  }

  void _showKorrDialog(String richtung) {
    final betreffC = TextEditingController(); final datumC = TextEditingController(text: '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}'); final notizC = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text(richtung == 'eingang' ? 'Eingang' : 'Ausgang'),
      content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: datumC, decoration: const InputDecoration(labelText: 'Datum', isDense: true, border: OutlineInputBorder())), const SizedBox(height: 8),
        TextField(controller: betreffC, decoration: const InputDecoration(labelText: 'Betreff', isDense: true, border: OutlineInputBorder())), const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 3, decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder())),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          if (widget.apiService != null && widget.userId != null) {
            await widget.apiService!.saveSozialamtKorrespondenz(widget.userId!, {'richtung': richtung, 'datum': datumC.text.trim(), 'betreff': betreffC.text.trim(), 'notiz': notizC.text.trim()});
          }
          if (ctx.mounted) Navigator.pop(ctx);
          _loadFromDB();
        }, child: const Text('Speichern')),
      ],
    ));
  }

  // ============ ANTRAG DETAIL MODAL ============
  void _showAntragDetailDialog(int antragId, Map<String, dynamic> antrag) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(width: 580, height: 560, child: _AntragDetailView(apiService: widget.apiService!, antragId: antragId, antrag: antrag, checkedDocs: _checkedDocsGlobal, onCheckedChanged: (docs) { _checkedDocsGlobal = docs; _dbData['checked_docs'] = {'list': docs.toList()}; _save(); })),
      ),
    );
  }

  static const _sozialamtListe = [
    {'name': 'Landratsamt Neu-Ulm — Soziale Leistungen', 'adresse': 'Albrecht-Berblinger-Str. 6', 'plz_ort': '89231 Neu-Ulm', 'telefon': '0731 7040-52020', 'oeffnungszeiten': 'Mo–Mi 07:30–12:30, Do 07:30–17:30, Fr 07:30–12:30', 'zustaendigkeit': 'Sozialhilfe, Grundsicherung, Blindengeld'},
    {'name': 'LRA Neu-Ulm — Außenstelle Illertissen', 'adresse': 'Ulmer Straße 20', 'plz_ort': '89257 Illertissen', 'telefon': '07303 9006-0', 'oeffnungszeiten': 'Mo–Mi 07:30–12:30, Do 07:30–17:30, Fr 07:30–12:30', 'zustaendigkeit': 'Südlicher Landkreis'},
    {'name': 'Stadt Ulm — Soziales', 'adresse': 'Zeitblomstraße 28', 'plz_ort': '89073 Ulm', 'telefon': '0731 161-5101', 'oeffnungszeiten': 'Mo–Fr 08:00–12:00, Di+Do 14:00–16:00', 'zustaendigkeit': 'Sozialhilfe, Grundsicherung, Wohngeld, BuT'},
  ];

  Widget _field(Map<String, dynamic> map, String key, String label, IconData icon, {String hint = '', int maxLines = 1}) {
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: TextField(
      controller: TextEditingController(text: map[key]?.toString() ?? ''), maxLines: maxLines, onChanged: (v) => map[key] = v,
      decoration: InputDecoration(labelText: label, hintText: hint, prefixIcon: Icon(icon, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
      style: const TextStyle(fontSize: 13),
    ));
  }

  Widget _saveBtn() {
    return Align(alignment: Alignment.centerRight, child: ElevatedButton.icon(
      onPressed: _saving ? null : _save,
      icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 16),
      label: const Text('Speichern'),
      style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
    ));
  }
}

// ═══════════════════════════════════════════════════════
// ANTRAG DETAIL (Details / Verlauf / Korrespondenz)
// ═══════════════════════════════════════════════════════
class _AntragDetailView extends StatefulWidget {
  final ApiService apiService;
  final int antragId;
  final Map<String, dynamic> antrag;
  final Set<String> checkedDocs;
  final ValueChanged<Set<String>> onCheckedChanged;
  const _AntragDetailView({required this.apiService, required this.antragId, required this.antrag, required this.checkedDocs, required this.onCheckedChanged});
  @override
  State<_AntragDetailView> createState() => _AntragDetailViewState();
}

class _AntragDetailViewState extends State<_AntragDetailView> {
  List<Map<String, dynamic>> _verlauf = [];
  List<Map<String, dynamic>> _korr = [];
  List<Map<String, dynamic>> _docs = [];
  bool _loaded = false;

  static const Map<String, List<(String, String, IconData)>> _requiredDocs = {
    'Grundsicherung im Alter': [
      ('personalausweis', 'Personalausweis / Reisepass', Icons.badge),
      ('rentenbescheid', 'Rentenbescheid', Icons.description),
      ('kontoauszuege', 'Kontoauszüge (3 Monate, alle Konten)', Icons.account_balance),
      ('mietvertrag', 'Mietvertrag', Icons.home),
      ('nebenkostenabrechnung', 'Nebenkostenabrechnung', Icons.receipt),
      ('heizkostenabrechnung', 'Heizkostenabrechnung', Icons.thermostat),
      ('krankenversicherung', 'Krankenversicherungsnachweis', Icons.local_hospital),
      ('einkommensnachweis', 'Einkommensnachweise', Icons.euro),
      ('vermoegensnachweis', 'Vermögensnachweise (Sparbücher etc.)', Icons.savings),
      ('antrag_formular', 'Ausgefüllter Antrag (unterschrieben)', Icons.edit_document),
    ],
    'Grundsicherung bei Erwerbsminderung': [
      ('personalausweis', 'Personalausweis / Reisepass', Icons.badge),
      ('em_bescheid', 'EM-Rentenbescheid / Gutachten Erwerbsminderung', Icons.medical_information),
      ('rentenbescheid', 'Rentenbescheid', Icons.description),
      ('kontoauszuege', 'Kontoauszüge (3 Monate, alle Konten)', Icons.account_balance),
      ('mietvertrag', 'Mietvertrag', Icons.home),
      ('nebenkostenabrechnung', 'Nebenkostenabrechnung', Icons.receipt),
      ('heizkostenabrechnung', 'Heizkostenabrechnung', Icons.thermostat),
      ('krankenversicherung', 'Krankenversicherungsnachweis', Icons.local_hospital),
      ('schwerbehindertenausweis', 'Schwerbehindertenausweis (falls vorhanden)', Icons.accessible),
      ('einkommensnachweis', 'Einkommensnachweise', Icons.euro),
      ('vermoegensnachweis', 'Vermögensnachweise', Icons.savings),
      ('antrag_formular', 'Ausgefüllter Antrag (unterschrieben)', Icons.edit_document),
    ],
    'Hilfe zur Pflege': [
      ('personalausweis', 'Personalausweis / Reisepass', Icons.badge),
      ('pflegegrad_bescheid', 'Pflegegrad-Bescheid / MDK-Gutachten', Icons.medical_information),
      ('krankenversicherung', 'Kranken- und Pflegeversicherungsnachweis', Icons.local_hospital),
      ('kontoauszuege', 'Kontoauszüge (3 Monate)', Icons.account_balance),
      ('mietvertrag', 'Mietvertrag', Icons.home),
      ('einkommensnachweis', 'Einkommensnachweise', Icons.euro),
      ('vermoegensnachweis', 'Vermögensnachweise', Icons.savings),
      ('pflegekosten', 'Nachweise über Pflegekosten', Icons.receipt_long),
      ('antrag_formular', 'Ausgefüllter Antrag (unterschrieben)', Icons.edit_document),
    ],
    'Eingliederungshilfe': [
      ('personalausweis', 'Personalausweis / Reisepass', Icons.badge),
      ('aerztliches_gutachten', 'Ärztliches Gutachten / Diagnose', Icons.medical_information),
      ('schwerbehindertenausweis', 'Schwerbehindertenausweis', Icons.accessible),
      ('kontoauszuege', 'Kontoauszüge (3 Monate)', Icons.account_balance),
      ('einkommensnachweis', 'Einkommensnachweise', Icons.euro),
      ('vermoegensnachweis', 'Vermögensnachweise', Icons.savings),
      ('antrag_formular', 'Ausgefüllter Antrag (unterschrieben)', Icons.edit_document),
    ],
  };

  static const _defaultDocs = [
    ('personalausweis', 'Personalausweis / Reisepass', Icons.badge),
    ('kontoauszuege', 'Kontoauszüge (3 Monate)', Icons.account_balance),
    ('mietvertrag', 'Mietvertrag', Icons.home),
    ('einkommensnachweis', 'Einkommensnachweise', Icons.euro),
    ('antrag_formular', 'Ausgefüllter Antrag (unterschrieben)', Icons.edit_document),
    ('sonstiges', 'Sonstiges Dokument', Icons.attach_file),
  ];

  @override
  void initState() { super.initState(); _checkedDocs = Set<String>.from(widget.checkedDocs); _load(); }

  Future<void> _load() async {
    final vR = await widget.apiService.listAntragVerlauf(widget.antragId);
    final kR = await widget.apiService.listAntragKorrespondenz(widget.antragId);
    final dR = await widget.apiService.listAntragDocs(widget.antragId);
    if (!mounted) return;
    setState(() {
      if (vR['success'] == true && vR['data'] is List) _verlauf = (vR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (kR['success'] == true && kR['data'] is List) _korr = (kR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (dR['success'] == true && dR['data'] is List) _docs = (dR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.antrag;
    return DefaultTabController(length: 4, child: Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: Colors.indigo.shade700, borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
        child: Row(children: [
          const Icon(Icons.description, color: Colors.white, size: 22), const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a['leistung']?.toString() ?? '', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            Text('${a['datum'] ?? ''} • ${a['status'] ?? ''}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ])),
          IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
        ]),
      ),
      TabBar(labelColor: Colors.indigo.shade700, indicatorColor: Colors.indigo.shade700, isScrollable: true, tabs: const [
        Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Details'),
        Tab(icon: Icon(Icons.folder, size: 18), text: 'Dokumente'),
        Tab(icon: Icon(Icons.timeline, size: 18), text: 'Verlauf'),
        Tab(icon: Icon(Icons.mail, size: 18), text: 'Korrespondenz'),
      ]),
      Expanded(child: !_loaded ? const Center(child: CircularProgressIndicator()) : TabBarView(children: [
        _buildDetails(a),
        _buildDokumente(a),
        _buildVerlauf(),
        _buildKorr(),
      ])),
    ]));
  }

  Widget _buildDetails(Map<String, dynamic> a) {
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _row(Icons.description, 'Leistung', a['leistung']),
      _row(Icons.calendar_today, 'Datum', a['datum']),
      _row(Icons.send, 'Methode', a['methode']),
      _row(Icons.flag, 'Status', a['status']),
      if ((a['notiz']?.toString() ?? '').isNotEmpty) ...[
        const SizedBox(height: 8),
        Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.yellow.shade50, borderRadius: BorderRadius.circular(8)),
          child: Text(a['notiz'].toString(), style: const TextStyle(fontSize: 12))),
      ],
    ]));
  }

  late Set<String> _checkedDocs;

  Widget _buildDokumente(Map<String, dynamic> a) {
    final leistung = a['leistung']?.toString() ?? '';
    final checklist = _requiredDocs[leistung] ?? _defaultDocs;
    final uploadedTypes = _docs.map((d) => d['doc_typ']?.toString() ?? '').toSet();
    final doneCount = checklist.where((c) => uploadedTypes.contains(c.$1) || _checkedDocs.contains(c.$1)).length;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.checklist, size: 20, color: Colors.indigo.shade700),
          const SizedBox(width: 8),
          Expanded(child: Text('Unterlagen-Checkliste', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade700))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: doneCount == checklist.length ? Colors.green.shade100 : Colors.orange.shade100, borderRadius: BorderRadius.circular(8)),
            child: Text('$doneCount / ${checklist.length}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: doneCount == checklist.length ? Colors.green.shade800 : Colors.orange.shade800)),
          ),
        ]),
        const SizedBox(height: 4),
        Text('Checkbox = als erledigt markieren (auch ohne Upload). Upload = Dokument hochladen.', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
        if (doneCount == checklist.length)
          Container(
            width: double.infinity, margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green.shade300)),
            child: Row(children: [
              Icon(Icons.check_circle, size: 18, color: Colors.green.shade700),
              const SizedBox(width: 8),
              Text('Alle Unterlagen vollständig!', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
            ]),
          ),
        const SizedBox(height: 12),
        ...checklist.map((c) {
          final docTyp = c.$1;
          final label = c.$2;
          final icon = c.$3;
          final hasUpload = uploadedTypes.contains(docTyp);
          final isChecked = hasUpload || _checkedDocs.contains(docTyp);
          final uploadedDocs = _docs.where((d) => d['doc_typ'] == docTyp).toList();
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: isChecked ? Colors.green.shade50 : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isChecked ? Colors.green.shade300 : Colors.grey.shade300),
            ),
            child: Column(children: [
              Row(children: [
                Checkbox(
                  value: isChecked,
                  activeColor: Colors.green.shade700,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) _checkedDocs.add(docTyp);
                      else _checkedDocs.remove(docTyp);
                    });
                    widget.onCheckedChanged(_checkedDocs);
                  },
                ),
                Icon(icon, size: 18, color: isChecked ? Colors.green.shade700 : Colors.grey.shade500),
                const SizedBox(width: 8),
                Expanded(child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isChecked ? Colors.green.shade900 : Colors.black87, decoration: isChecked ? TextDecoration.lineThrough : null))),
                IconButton(
                  icon: Icon(Icons.upload_file, size: 18, color: Colors.indigo.shade600),
                  tooltip: 'Dokument hochladen',
                  onPressed: () => _uploadDoc(docTyp, label),
                ),
              ]),
              if (uploadedDocs.isNotEmpty)
                ...uploadedDocs.map((d) => Padding(
                  padding: const EdgeInsets.fromLTRB(48, 0, 16, 8),
                  child: Row(children: [
                    Icon(Icons.attach_file, size: 12, color: Colors.green.shade600),
                    const SizedBox(width: 4),
                    Expanded(child: Text(d['datei_name']?.toString() ?? '', style: TextStyle(fontSize: 11, color: Colors.green.shade800))),
                    InkWell(onTap: () async {
                      try {
                        final resp = await widget.apiService.downloadAntragDoc(d['id'] as int);
                        if (resp.statusCode == 200 && mounted) {
                          final dir = await getTemporaryDirectory();
                          final file = File('${dir.path}/${d['datei_name']}');
                          await file.writeAsBytes(resp.bodyBytes);
                          if (mounted) await FileViewerDialog.show(context, file.path, d['datei_name']?.toString() ?? '');
                        }
                      } catch (_) {}
                    }, child: Icon(Icons.visibility, size: 14, color: Colors.indigo.shade600)),
                    const SizedBox(width: 8),
                    InkWell(onTap: () async {
                      await widget.apiService.deleteAntragDoc(d['id'] as int);
                      _load();
                    }, child: Icon(Icons.delete_outline, size: 14, color: Colors.red.shade400)),
                  ]),
                )),
            ]),
          );
        }),
      ]),
    );
  }

  Future<void> _uploadDoc(String docTyp, String label) async {
    final result = await FilePickerHelper.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
    if (result == null || result.files.isEmpty || result.files.first.path == null) return;
    final file = result.files.first;
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wird hochgeladen...'), duration: Duration(seconds: 1)));
    await widget.apiService.uploadAntragDoc(antragId: widget.antragId, docTyp: docTyp, filePath: file.path!, fileName: file.name, notiz: label);
    _load();
  }

  Widget _buildVerlauf() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Expanded(child: Text('${_verlauf.length} Einträge', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
        FilledButton.icon(icon: const Icon(Icons.add, size: 14), label: const Text('Neuer Eintrag', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.indigo, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: () { final datumC = TextEditingController(text: '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}'); final notizC = TextEditingController(); String status = '';
            showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (_, setD) => AlertDialog(title: const Text('Verlauf-Eintrag'),
              content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: datumC, decoration: const InputDecoration(labelText: 'Datum', isDense: true, border: OutlineInputBorder())), const SizedBox(height: 8),
                Wrap(spacing: 6, children: ['Eingereicht', 'In Bearbeitung', 'Nachforderung', 'Anhörung', 'Bewilligt', 'Abgelehnt', 'Widerspruch'].map((s) => ChoiceChip(label: Text(s, style: TextStyle(fontSize: 10, color: status == s ? Colors.white : Colors.black87)), selected: status == s, selectedColor: Colors.indigo, onSelected: (_) => setD(() => status = s))).toList()), const SizedBox(height: 8),
                TextField(controller: notizC, maxLines: 3, decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder())),
              ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
                FilledButton(onPressed: () async { await widget.apiService.addAntragVerlauf(widget.antragId, {'datum': datumC.text, 'status': status, 'notiz': notizC.text}); if (ctx.mounted) Navigator.pop(ctx); _load(); }, child: const Text('Hinzufügen'))],
            ))); }),
      ])),
      Expanded(child: _verlauf.isEmpty ? Center(child: Text('Kein Verlauf', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _verlauf.length, itemBuilder: (_, i) { final v = _verlauf[i];
          return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.indigo.shade200)),
            child: Row(children: [
              Icon(Icons.circle, size: 10, color: Colors.indigo.shade400), const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Text(v['datum']?.toString() ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)), if ((v['status']?.toString() ?? '').isNotEmpty) ...[const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: Colors.indigo.shade100, borderRadius: BorderRadius.circular(6)), child: Text(v['status'].toString(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)))]]),
                if ((v['notiz']?.toString() ?? '').isNotEmpty) Text(v['notiz'].toString(), style: const TextStyle(fontSize: 12)),
              ])),
              IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), onPressed: () async { await widget.apiService.deleteAntragVerlauf(v['id'] as int); _load(); }, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24)),
            ]));
        })),
    ]);
  }

  Widget _buildKorr() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Expanded(child: Text('${_korr.length} Einträge', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
        FilledButton.icon(icon: const Icon(Icons.call_received, size: 14), label: const Text('Eingang', style: TextStyle(fontSize: 11)), style: FilledButton.styleFrom(backgroundColor: Colors.green.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _addKorr('eingang')), const SizedBox(width: 6),
        FilledButton.icon(icon: const Icon(Icons.call_made, size: 14), label: const Text('Ausgang', style: TextStyle(fontSize: 11)), style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _addKorr('ausgang')),
      ])),
      Expanded(child: _korr.isEmpty ? Center(child: Text('Keine Korrespondenz', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _korr.length, itemBuilder: (_, i) { final k = _korr[i]; final isEin = k['richtung'] == 'eingang';
          return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: isEin ? Colors.green.shade200 : Colors.blue.shade200)),
            child: Row(children: [
              Icon(isEin ? Icons.call_received : Icons.call_made, size: 18, color: isEin ? Colors.green.shade700 : Colors.blue.shade700), const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(k['betreff']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isEin ? Colors.green.shade800 : Colors.blue.shade800)),
                Text(k['datum']?.toString() ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
              ])),
              IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), onPressed: () async { await widget.apiService.deleteAntragKorrespondenz(k['id'] as int); _load(); }, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24)),
            ]));
        })),
    ]);
  }

  void _addKorr(String richtung) {
    final betreffC = TextEditingController(); final datumC = TextEditingController(text: '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}'); final notizC = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(title: Text(richtung == 'eingang' ? 'Eingang' : 'Ausgang'),
      content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: datumC, decoration: const InputDecoration(labelText: 'Datum', isDense: true, border: OutlineInputBorder())), const SizedBox(height: 8),
        TextField(controller: betreffC, decoration: const InputDecoration(labelText: 'Betreff', isDense: true, border: OutlineInputBorder())), const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 3, decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder())),
      ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async { await widget.apiService.addAntragKorrespondenz(widget.antragId, {'richtung': richtung, 'datum': datumC.text.trim(), 'betreff': betreffC.text.trim(), 'notiz': notizC.text.trim()}); if (ctx.mounted) Navigator.pop(ctx); _load(); }, child: const Text('Speichern'))],
    ));
  }

  Widget _row(IconData icon, String label, dynamic value) {
    final s = value?.toString() ?? ''; if (s.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
      Icon(icon, size: 14, color: Colors.grey.shade600), const SizedBox(width: 8),
      SizedBox(width: 100, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600))),
      Expanded(child: Text(s, style: const TextStyle(fontSize: 13))),
    ]));
  }
}

// ═══════════════════════════════════════════════════════
// BEWILLIGUNG DETAIL (Details / Unterlagen / Korrespondenz)
// ═══════════════════════════════════════════════════════
class _BewilligungDetailView extends StatefulWidget {
  final ApiService apiService;
  final int bewilligungId;
  final Map<String, dynamic> bewilligung;
  final VoidCallback onEdit;
  final VoidCallback onChanged;
  const _BewilligungDetailView({required this.apiService, required this.bewilligungId, required this.bewilligung, required this.onEdit, required this.onChanged});
  @override
  State<_BewilligungDetailView> createState() => _BewilligungDetailViewState();
}

class _BewilligungDetailViewState extends State<_BewilligungDetailView> {
  List<Map<String, dynamic>> _docs = [];
  List<Map<String, dynamic>> _korr = [];
  bool _loaded = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final dR = await widget.apiService.listBewilligungDocs(widget.bewilligungId);
    final kR = await widget.apiService.listBewilligungKorr(widget.bewilligungId);
    if (!mounted) return;
    setState(() {
      if (dR['success'] == true && dR['data'] is List) _docs = (dR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (kR['success'] == true && kR['data'] is List) _korr = (kR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.bewilligung;
    final ok = b['bewilligt'] == true || b['bewilligt'] == 'true' || b['bewilligt'] == 1 || b['bewilligt'] == '1';
    return DefaultTabController(length: 3, child: Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: ok ? Colors.green.shade700 : Colors.red.shade700, borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
        child: Row(children: [
          Icon(ok ? Icons.check_circle : Icons.cancel, color: Colors.white, size: 22), const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(b['leistung']?.toString() ?? '', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            Text('${ok ? 'Bewilligt' : 'Abgelehnt'} • ${b['bescheid_datum'] ?? ''}${(b['aktenzeichen']?.toString() ?? '').isNotEmpty ? ' • Az. ${b['aktenzeichen']}' : ''}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ])),
          IconButton(icon: const Icon(Icons.edit, color: Colors.white, size: 20), tooltip: 'Bearbeiten', onPressed: widget.onEdit),
          IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
        ]),
      ),
      TabBar(labelColor: Colors.green.shade700, indicatorColor: Colors.green.shade700, tabs: const [
        Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Details'),
        Tab(icon: Icon(Icons.folder, size: 18), text: 'Unterlagen'),
        Tab(icon: Icon(Icons.mail, size: 18), text: 'Korrespondenz'),
      ]),
      Expanded(child: !_loaded ? const Center(child: CircularProgressIndicator()) : TabBarView(children: [
        _buildDetails(b),
        _buildUnterlagen(),
        _buildKorrespondenz(),
      ])),
    ]));
  }

  Widget _buildDetails(Map<String, dynamic> b) {
    final ok = b['bewilligt'] == true || b['bewilligt'] == 'true' || b['bewilligt'] == 1 || b['bewilligt'] == '1';
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dRow(Icons.description, 'Leistungsart', b['leistung']),
      _dRow(Icons.numbers, 'Aktenzeichen', b['aktenzeichen']),
      _dRow(ok ? Icons.check_circle : Icons.cancel, 'Status', ok ? 'Bewilligt' : 'Abgelehnt'),
      _dRow(Icons.calendar_today, 'Bescheid-Datum', b['bescheid_datum']),
      _dRow(Icons.local_post_office, 'Erhalten per Post', b['erhalten_am']),
      const SizedBox(height: 8),
      if ((b['zeitraum_von']?.toString() ?? '').isNotEmpty) ...[
        Text('Bewilligungszeitraum', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        _dRow(Icons.date_range, 'Von – Bis', '${b['zeitraum_von']} – ${b['zeitraum_bis'] ?? ''}'),
      ],
      if (ok) ...[
        const SizedBox(height: 8),
        Text('Berechnungsbogen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        _dRow(Icons.euro, 'Regelbedarf', _eur(b['regelbedarf'])),
        _dRow(Icons.euro, 'Mehrbedarf', _eur(b['mehrbedarf'])),
        const SizedBox(height: 4),
        Text('Kosten der Unterkunft (KdU)', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        _dRow(Icons.home, 'Kaltmiete', _eur(b['kaltmiete'])),
        _dRow(Icons.water_drop, 'Nebenkosten', _eur(b['nebenkosten'])),
        _dRow(Icons.thermostat, 'Heizkosten', _eur(b['heizkosten'])),
        const Divider(height: 16),
        _dRow(Icons.remove_circle_outline, 'Anrechenb. Einkommen', _eur(b['einkommen'])),
        Container(
          margin: const EdgeInsets.only(top: 4), padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green.shade300)),
          child: Row(children: [
            Icon(Icons.payments, size: 18, color: Colors.green.shade800), const SizedBox(width: 8),
            Text('Auszahlung: ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.green.shade800)),
            Text('${_eur(b['auszahlung'])} /Monat', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green.shade900)),
          ]),
        ),
      ],
      if (b['widerspruch'] == true || b['widerspruch'] == 'true' || b['widerspruch'] == 1 || b['widerspruch'] == '1') ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade300)),
          child: Row(children: [
            Icon(Icons.warning, size: 18, color: Colors.orange.shade800), const SizedBox(width: 8),
            Expanded(child: Text('Widerspruch eingelegt${(b['widerspruch_datum']?.toString() ?? '').isNotEmpty ? ' am ${b['widerspruch_datum']}' : ''}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange.shade800))),
          ]),
        ),
      ],
      if ((b['notiz']?.toString() ?? '').isNotEmpty) ...[
        const SizedBox(height: 8),
        Container(
          width: double.infinity, padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.yellow.shade50, borderRadius: BorderRadius.circular(8)),
          child: Text(b['notiz'].toString(), style: const TextStyle(fontSize: 12)),
        ),
      ],
    ]));
  }

  String _eur(dynamic v) {
    final s = v?.toString() ?? '';
    if (s.isEmpty || s == 'null' || s == '0' || s == '0.00') return '';
    return '$s €';
  }

  Widget _dRow(IconData icon, String label, dynamic value) {
    final s = value?.toString() ?? ''; if (s.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
      Icon(icon, size: 14, color: Colors.grey.shade600), const SizedBox(width: 8),
      SizedBox(width: 130, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600))),
      Expanded(child: Text(s, style: const TextStyle(fontSize: 13))),
    ]));
  }

  Widget _buildUnterlagen() {
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Row(children: [
        Icon(Icons.folder, size: 20, color: Colors.green.shade700), const SizedBox(width: 8),
        Expanded(child: Text('Unterlagen (${_docs.length})', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green.shade700))),
        ElevatedButton.icon(
          onPressed: _uploadDoc,
          icon: const Icon(Icons.upload_file, size: 16), label: const Text('Hochladen', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
        ),
      ])),
      Expanded(child: _docs.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.cloud_upload, size: 48, color: Colors.grey.shade300), const SizedBox(height: 8),
              Text('Keine Unterlagen', style: TextStyle(color: Colors.grey.shade500)),
              const SizedBox(height: 4),
              Text('Bewilligungsbescheid, Berechnungsbogen etc. hochladen', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
            ]))
          : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: _docs.length, itemBuilder: (_, i) {
              final d = _docs[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green.shade200)),
                child: Row(children: [
                  Icon(Icons.attach_file, size: 18, color: Colors.green.shade700), const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(d['datei_name']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                    if ((d['created_at']?.toString() ?? '').isNotEmpty) Text(d['created_at'].toString(), style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  ])),
                  InkWell(onTap: () async {
                    try {
                      final resp = await widget.apiService.downloadBewilligungDoc(d['id'] as int);
                      if (resp.statusCode == 200 && mounted) {
                        final dir = await getTemporaryDirectory();
                        final file = File('${dir.path}/${d['datei_name']}');
                        await file.writeAsBytes(resp.bodyBytes);
                        if (mounted) await FileViewerDialog.show(context, file.path, d['datei_name']?.toString() ?? '');
                      }
                    } catch (_) {}
                  }, child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.visibility, size: 18, color: Colors.indigo.shade600))),
                  const SizedBox(width: 4),
                  InkWell(onTap: () async {
                    await widget.apiService.deleteBewilligungDoc(d['id'] as int);
                    _load();
                  }, child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400))),
                ]),
              );
            })),
    ]);
  }

  Future<void> _uploadDoc() async {
    final result = await FilePickerHelper.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
    if (result == null || result.files.isEmpty || result.files.first.path == null) return;
    final file = result.files.first;
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wird hochgeladen...'), duration: Duration(seconds: 1)));
    await widget.apiService.uploadBewilligungDoc(bewilligungId: widget.bewilligungId, filePath: file.path!, fileName: file.name);
    _load();
  }

  Widget _buildKorrespondenz() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Expanded(child: Text('${_korr.length} Einträge', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
        FilledButton.icon(icon: const Icon(Icons.call_received, size: 14), label: const Text('Eingang', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.green.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _addKorr('eingang')),
        const SizedBox(width: 6),
        FilledButton.icon(icon: const Icon(Icons.call_made, size: 14), label: const Text('Ausgang', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _addKorr('ausgang')),
      ])),
      Expanded(child: _korr.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.mail_outline, size: 48, color: Colors.grey.shade300), const SizedBox(height: 6),
              Text('Keine Korrespondenz', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ]))
          : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _korr.length, itemBuilder: (_, i) {
              final k = _korr[i]; final isEin = k['richtung'] == 'eingang';
              return Container(
                margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: isEin ? Colors.green.shade200 : Colors.blue.shade200)),
                child: Row(children: [
                  Icon(isEin ? Icons.call_received : Icons.call_made, size: 18, color: isEin ? Colors.green.shade700 : Colors.blue.shade700), const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(k['betreff']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isEin ? Colors.green.shade800 : Colors.blue.shade800)),
                    Text(k['datum']?.toString() ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                    if ((k['notiz']?.toString() ?? '').isNotEmpty) Text(k['notiz'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                  ])),
                  IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), onPressed: () async {
                    final kid = int.tryParse(k['id']?.toString() ?? '');
                    if (kid != null) await widget.apiService.deleteBewilligungKorr(kid);
                    _load();
                  }, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28)),
                ]),
              );
            })),
    ]);
  }

  void _addKorr(String richtung) {
    final betreffC = TextEditingController();
    final datumC = TextEditingController(text: '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}');
    final notizC = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text(richtung == 'eingang' ? 'Eingang' : 'Ausgang'),
      content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: datumC, decoration: const InputDecoration(labelText: 'Datum', isDense: true, border: OutlineInputBorder())), const SizedBox(height: 8),
        TextField(controller: betreffC, decoration: const InputDecoration(labelText: 'Betreff', isDense: true, border: OutlineInputBorder())), const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 3, decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder())),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          await widget.apiService.saveBewilligungKorr(widget.bewilligungId, {'richtung': richtung, 'datum': datumC.text.trim(), 'betreff': betreffC.text.trim(), 'notiz': notizC.text.trim()});
          if (ctx.mounted) Navigator.pop(ctx);
          _load();
        }, child: const Text('Speichern')),
      ],
    ));
  }
}
