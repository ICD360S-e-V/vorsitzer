import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import 'package:open_filex/open_filex.dart';
import '../utils/file_picker_helper.dart';
import '../services/global_chat_service.dart';
import 'file_viewer_dialog.dart';
import 'cloud_file_picker.dart';

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
  Map<String, Map<String, dynamic>> _dbData = {};
  List<Map<String, dynamic>> _antraege = [];
  bool _loaded = false;
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
    await widget.apiService!.saveSozialamtData(widget.userId!, _dbData);
  }

  String _fmtIsoDate(String iso) {
    if (iso.isEmpty || iso == 'null') return '';
    final p = iso.split(' ').first.split('-');
    return p.length == 3 ? '${p[2]}.${p[1]}.${p[0]}' : iso;
  }

  Map<String, dynamic> _b(String key) {
    _dbData[key] ??= {};
    return _dbData[key]!;
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());

    return DefaultTabController(
      length: 2,
      child: Column(children: [
        TabBar(
          labelColor: Colors.indigo.shade700,
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: Colors.indigo.shade700,
          isScrollable: true,
          tabs: [
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: (_b('behoerde')['name']?.toString() ?? '').isNotEmpty ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.account_balance, size: 16), const SizedBox(width: 4), const Text('Zuständige Behörde')])),
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: _antraege.isNotEmpty ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.description, size: 16), const SizedBox(width: 4), const Text('Anträge')])),
          ],
        ),
        Expanded(child: TabBarView(children: [
          _buildBehoerdeTab(),
          _buildAntraegeTab(),
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
              final hatBew = a['hat_bewilligung'] == 1 || a['hat_bewilligung'] == '1';
              final bewOk = a['bew_bewilligt'] == 1 || a['bew_bewilligt'] == '1' || a['bew_bewilligt'] == true;
              final bewBis = _fmtIsoDate(a['bew_zeitraum_bis']?.toString() ?? '');
              final MaterialColor statusColor = hatBew ? (bewOk ? Colors.green : Colors.red) : Colors.grey;
              final statusText = hatBew ? (bewOk ? 'Bewilligt' : 'Abgelehnt') : (a['status']?.toString() ?? '');
              return Card(child: ListTile(
                leading: Icon(hatBew ? (bewOk ? Icons.check_circle : Icons.cancel) : Icons.description, color: hatBew ? (bewOk ? Colors.green.shade600 : Colors.red.shade600) : Colors.indigo.shade600),
                title: Text(a['leistung']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${a['datum'] ?? ''}${(a['methode']?.toString() ?? '').isNotEmpty ? ' • ${a['methode']}' : ''}', style: const TextStyle(fontSize: 11)),
                  const SizedBox(height: 3),
                  Row(children: [
                    Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: statusColor.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: statusColor.shade200)), child: Text(statusText, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor.shade700))),
                    if (hatBew && bewOk && bewBis.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.event, size: 11, color: Colors.grey.shade500),
                      const SizedBox(width: 2),
                      Flexible(child: Text('gültig bis $bewBis', style: TextStyle(fontSize: 10, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis)),
                    ],
                  ]),
                ]),
                isThreeLine: true,
                onTap: () {
                  final aid = int.tryParse(a['id']?.toString() ?? '');
                  if (aid != null) _showAntragDetailDialog(aid, a);
                },
                trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
              ));
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
        DropdownButtonFormField<String>(initialValue: leistungen.contains(leistung) ? leistung : null, decoration: InputDecoration(labelText: 'Leistung *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), items: leistungen.map((l) => DropdownMenuItem(value: l, child: Text(l, style: const TextStyle(fontSize: 12)))).toList(), onChanged: (v) => setD(() => leistung = v ?? '')),
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

  // ============ ANTRAG DETAIL MODAL ============
  void _showAntragDetailDialog(int antragId, Map<String, dynamic> antrag) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(width: 580, height: 560, child: _AntragDetailView(apiService: widget.apiService!, userId: widget.userId ?? 0, antragId: antragId, antrag: antrag, checkedDocs: _checkedDocsGlobal, onCheckedChanged: (docs) { _checkedDocsGlobal = docs; _dbData['checked_docs'] = {'list': docs.toList()}; _save(); })),
      ),
    );
  }

  static const _sozialamtListe = [
    {'name': 'Landratsamt Neu-Ulm — Soziale Leistungen', 'adresse': 'Albrecht-Berblinger-Str. 6', 'plz_ort': '89231 Neu-Ulm', 'telefon': '0731 7040-52020', 'oeffnungszeiten': 'Mo–Mi 07:30–12:30, Do 07:30–17:30, Fr 07:30–12:30', 'zustaendigkeit': 'Sozialhilfe, Grundsicherung, Blindengeld'},
    {'name': 'LRA Neu-Ulm — Außenstelle Illertissen', 'adresse': 'Ulmer Straße 20', 'plz_ort': '89257 Illertissen', 'telefon': '07303 9006-0', 'oeffnungszeiten': 'Mo–Mi 07:30–12:30, Do 07:30–17:30, Fr 07:30–12:30', 'zustaendigkeit': 'Südlicher Landkreis'},
    {'name': 'Stadt Ulm — Soziales', 'adresse': 'Zeitblomstraße 28', 'plz_ort': '89073 Ulm', 'telefon': '0731 161-5101', 'oeffnungszeiten': 'Mo–Fr 08:00–12:00, Di+Do 14:00–16:00', 'zustaendigkeit': 'Sozialhilfe, Grundsicherung, Wohngeld, BuT'},
  ];

}

// ═══════════════════════════════════════════════════════
// ANTRAG DETAIL (Details / Verlauf / Korrespondenz)
// ═══════════════════════════════════════════════════════
class _AntragDetailView extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int antragId;
  final Map<String, dynamic> antrag;
  final Set<String> checkedDocs;
  final ValueChanged<Set<String>> onCheckedChanged;
  const _AntragDetailView({required this.apiService, required this.userId, required this.antragId, required this.antrag, required this.checkedDocs, required this.onCheckedChanged});
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
    return DefaultTabController(length: 5, child: Column(children: [
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
        Tab(icon: Icon(Icons.verified, size: 18), text: 'Bewilligung'),
        Tab(icon: Icon(Icons.mail, size: 18), text: 'Korrespondenz'),
      ]),
      Expanded(child: !_loaded ? const Center(child: CircularProgressIndicator()) : TabBarView(children: [
        _buildDetails(a),
        _buildDokumente(a),
        _buildVerlauf(),
        _AntragBewilligungTab(apiService: widget.apiService, userId: widget.userId, antragId: widget.antragId),
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
                      if (v == true) {
                        _checkedDocs.add(docTyp);
                      } else {
                        _checkedDocs.remove(docTyp);
                      }
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
// BEWILLIGUNG als Tab im Antrag (1:1) — Bescheid / Widerspruch / Unterlagen
// ═══════════════════════════════════════════════════════
class _AntragBewilligungTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int antragId;
  const _AntragBewilligungTab({required this.apiService, required this.userId, required this.antragId});
  @override
  State<_AntragBewilligungTab> createState() => _AntragBewilligungTabState();
}

class _AntragBewilligungTabState extends State<_AntragBewilligungTab> {
  Map<String, dynamic>? _b;
  List<Map<String, dynamic>> _docs = [];
  Map<String, dynamic>? _wbaTicket;   // Weiterbewilligung-Erinnerungsticket (aus wba_ticket)
  String? _wbaAction;                 // 'created'|'existing'|'updated' — nur direkt nach einem Speichern
  bool _loaded = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final r = await widget.apiService.listSozialamtBewilligungByAntrag(widget.antragId);
    Map<String, dynamic>? b;
    if (r['success'] == true && r['data'] is List && (r['data'] as List).isNotEmpty) {
      b = Map<String, dynamic>.from((r['data'] as List).first as Map);
    }
    List<Map<String, dynamic>> docs = [];
    if (b != null) {
      final bid = int.tryParse(b['id']?.toString() ?? '');
      if (bid != null) {
        final dR = await widget.apiService.listBewilligungDocs(bid);
        if (dR['success'] == true && dR['data'] is List) {
          docs = (dR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _b = b;
      _docs = docs;
      _wbaTicket = (b != null && b['wba_ticket'] is Map) ? Map<String, dynamic>.from(b['wba_ticket'] as Map) : null;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    if (_b == null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.assignment_turned_in_outlined, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Text('Noch kein Bescheid erfasst', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          Text('Bewilligungs- oder Ablehnungsbescheid zu diesem Antrag erfassen.', style: TextStyle(fontSize: 12, color: Colors.grey.shade500), textAlign: TextAlign.center),
          const SizedBox(height: 14),
          ElevatedButton.icon(onPressed: () => _showForm(), icon: const Icon(Icons.add, size: 18), label: const Text('Bescheid erfassen'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white)),
        ]),
      ));
    }
    final b = _b!;
    final ok = b['bewilligt'] == true || b['bewilligt'] == 'true' || b['bewilligt'] == 1 || b['bewilligt'] == '1';
    final headColor = ok ? Colors.green : Colors.red;
    return DefaultTabController(length: 3, child: Column(children: [
      Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        color: headColor.shade50,
        child: Row(children: [
          Icon(ok ? Icons.check_circle : Icons.cancel, size: 18, color: headColor.shade700),
          const SizedBox(width: 8),
          Expanded(child: Text('${ok ? 'Bewilligt' : 'Abgelehnt'}${(b['bescheid_datum']?.toString() ?? '').isNotEmpty ? ' • ${b['bescheid_datum']}' : ''}${(b['aktenzeichen']?.toString() ?? '').isNotEmpty ? ' • Az. ${b['aktenzeichen']}' : ''}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: headColor.shade800))),
          IconButton(icon: Icon(Icons.edit, size: 18, color: Colors.grey.shade700), tooltip: 'Bearbeiten', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: () => _showForm(existing: b)),
          IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400), tooltip: 'Löschen', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: _delete),
        ]),
      ),
      TabBar(labelColor: Colors.green.shade700, unselectedLabelColor: Colors.grey.shade600, indicatorColor: Colors.green.shade700, isScrollable: true, tabs: const [
        Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Bescheid'),
        Tab(icon: Icon(Icons.gavel, size: 18), text: 'Widerspruch'),
        Tab(icon: Icon(Icons.folder, size: 18), text: 'Unterlagen'),
      ]),
      Expanded(child: TabBarView(children: [
        _buildDetails(b),
        _buildWiderspruch(b),
        _buildUnterlagen(),
      ])),
    ]));
  }

  Future<void> _delete() async {
    final b = _b; if (b == null) return;
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Bescheid löschen?'),
      content: const Text('Diesen Bescheid inkl. Unterlagen wirklich löschen?'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')), FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('Löschen'))],
    ));
    if (confirm == true) {
      final bid = int.tryParse(b['id']?.toString() ?? '');
      if (bid != null) await widget.apiService.deleteSozialamtBewilligung(bid);
      _load();
    }
  }

  void _showForm({Map<String, dynamic>? existing}) {
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
      title: Text(isEdit ? 'Bescheid bearbeiten' : 'Bescheid erfassen'),
      content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        DropdownButtonFormField<String>(initialValue: leistungen.contains(leistung) ? leistung : null, decoration: InputDecoration(labelText: 'Leistungsart *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), items: leistungen.map((l) => DropdownMenuItem(value: l, child: Text(l, style: const TextStyle(fontSize: 12)))).toList(), onChanged: (v) => setD(() => leistung = v ?? '')),
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
            ScaffoldMessenger.of(ctx2).showSnackBar(const SnackBar(content: Text('Bitte Leistungsart und Bescheid-Datum ausfüllen'), backgroundColor: Colors.red));
            return;
          }
          final res = await widget.apiService.saveSozialamtBewilligung(widget.userId, {
            if (isEdit) 'id': existing['id'],
            'antrag_id': widget.antragId,
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
          _wbaAction = res['wba_action']?.toString();
          final tid = res['wba_ticket'] is Map ? (res['wba_ticket'] as Map)['ticket_id'] : null;
          if (ctx.mounted) Navigator.pop(ctx);
          if (mounted && _wbaAction != null && _wbaAction != 'skipped' && tid != null) {
            final msg = switch (_wbaAction) {
              'created' => 'Gespeichert · Weiterbewilligung-Ticket #$tid neu erstellt',
              'updated' => 'Gespeichert · Bewilligungsende geändert — neues Ticket #$tid angelegt, altes geschlossen',
              'existing' => 'Gespeichert · Weiterbewilligung-Ticket #$tid bereits angelegt',
              _ => 'Gespeichert',
            };
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.indigo.shade600, duration: const Duration(seconds: 4)));
          }
          _load();
        }, child: Text(isEdit ? 'Speichern' : 'Hinzufügen')),
      ],
    )));
  }

  // ============ BESCHEID DETAILS ============
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
        if (_wbaTicket != null) ...[
          const SizedBox(height: 10),
          _buildWbaCard(),
        ],
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

  Widget _buildWbaCard() {
    final t = _wbaTicket!;
    final (Color chipColor, String chipText, Color cardColor, Color cardBorder, String headline) = switch (_wbaAction) {
      'updated'  => (Colors.orange.shade100, 'Aktualisiert',     Colors.orange.shade50, Colors.orange.shade300, 'Weiterbewilligung-Ticket aktualisiert'),
      'existing' => (Colors.teal.shade100,   'Bereits angelegt', Colors.teal.shade50,   Colors.teal.shade300,   'Weiterbewilligung-Ticket ist gesetzt'),
      'created'  => (Colors.green.shade100,  'Neu erstellt',     Colors.indigo.shade50, Colors.indigo.shade300, 'Weiterbewilligung-Ticket erstellt'),
      _          => (Colors.blue.shade100,   'Aktiv',            Colors.indigo.shade50, Colors.indigo.shade300, 'Weiterbewilligung-Erinnerung geplant'),
    };
    final textColor = switch (_wbaAction) { 'updated' => Colors.orange.shade800, 'existing' => Colors.teal.shade800, _ => Colors.indigo.shade800 };
    final iconColor = switch (_wbaAction) { 'updated' => Colors.orange.shade700, 'existing' => Colors.teal.shade700, _ => Colors.indigo.shade700 };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(8), border: Border.all(color: cardBorder, width: 1.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.event_available, color: iconColor, size: 22),
          const SizedBox(width: 8),
          Expanded(child: Text(headline, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textColor))),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: chipColor, borderRadius: BorderRadius.circular(10)), child: Text(chipText, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor))),
        ]),
        const SizedBox(height: 8),
        Text('Ticket #${t['ticket_id']}', style: const TextStyle(fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.w600)),
        if ((t['subject']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(t['subject'].toString(), style: const TextStyle(fontSize: 12)),
        ],
        const SizedBox(height: 6),
        Row(children: [
          Icon(Icons.calendar_today, size: 14, color: iconColor),
          const SizedBox(width: 4),
          Text('Geplant für: ', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
          Text(_fmtWbaDate(t['scheduled_date']?.toString()), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor)),
          const Spacer(),
          if ((t['bis']?.toString() ?? '').isNotEmpty) Text('Bewilligung bis ${t['bis']}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
        ]),
        const SizedBox(height: 4),
        Text('→ Erscheint in der Ticketverwaltung 2 Monate vor Bewilligungsende, damit der Weiterbewilligungsantrag rechtzeitig gestellt wird.', style: TextStyle(fontSize: 10, color: Colors.grey.shade700, fontStyle: FontStyle.italic)),
      ]),
    );
  }

  String _fmtWbaDate(String? s) {
    if (s == null || s.isEmpty) return '—';
    final datePart = s.split(' ').first;
    final p = datePart.split('-');
    return p.length == 3 ? '${p[2]}.${p[1]}.${p[0]}' : s;
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

  // ============ UNTERLAGEN ============
  Widget _buildUnterlagen() {
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Row(children: [
        Icon(Icons.folder, size: 20, color: Colors.green.shade700), const SizedBox(width: 8),
        Expanded(child: Text('Unterlagen (${_docs.length})', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green.shade700))),
        OutlinedButton.icon(
          onPressed: _pickFromCloud,
          icon: const Icon(Icons.cloud_download, size: 16), label: const Text('Aus Cloud', style: TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.blue.shade700),
        ),
        const SizedBox(width: 6),
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
                  IconButton(icon: Icon(Icons.visibility, size: 18, color: Colors.indigo.shade600), tooltip: 'Anzeigen', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: () async {
                    try {
                      final resp = await widget.apiService.downloadBewilligungDoc(d['id'] as int);
                      if (resp.statusCode == 200 && mounted) {
                        final dir = await getTemporaryDirectory();
                        final file = File('${dir.path}/${d['datei_name']}');
                        await file.writeAsBytes(resp.bodyBytes);
                        if (mounted) await FileViewerDialog.show(context, file.path, d['datei_name']?.toString() ?? '');
                      }
                    } catch (_) {}
                  }),
                  IconButton(icon: Icon(Icons.download, size: 18, color: Colors.green.shade700), tooltip: 'Herunterladen', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: () async {
                    try {
                      final resp = await widget.apiService.downloadBewilligungDoc(d['id'] as int);
                      if (resp.statusCode == 200 && mounted) {
                        final dir = await getTemporaryDirectory();
                        final file = File('${dir.path}/${d['datei_name']}');
                        await file.writeAsBytes(resp.bodyBytes);
                        await OpenFilex.open(file.path);
                      }
                    } catch (_) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download fehlgeschlagen'), backgroundColor: Colors.red));
                    }
                  }),
                  IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400), tooltip: 'Löschen', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: () async {
                    await widget.apiService.deleteBewilligungDoc(d['id'] as int);
                    _load();
                  }),
                ]),
              );
            })),
    ]);
  }

  Future<void> _uploadDoc() async {
    final bid = int.tryParse(_b?['id']?.toString() ?? '');
    if (bid == null) return;
    final result = await FilePickerHelper.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'], allowMultiple: true);
    if (result == null || result.files.isEmpty) return;
    final files = result.files.where((f) => f.path != null).toList();
    if (files.isEmpty) return;
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${files.length} Datei(en) werden hochgeladen...'), duration: const Duration(seconds: 2)));
    for (final file in files) {
      await widget.apiService.uploadBewilligungDoc(bewilligungId: bid, filePath: file.path!, fileName: file.name);
    }
    _load();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${files.length} Datei(en) hochgeladen'), backgroundColor: Colors.green));
  }

  /// Stage 2 "Aus Cloud": pick documents from the member's cloud and attach
  /// them to this Bewilligung server-side (they never touch the PC).
  Future<void> _pickFromCloud() async {
    final bid = int.tryParse(_b?['id']?.toString() ?? '');
    if (bid == null) return;
    final mnr = GlobalChatService().currentMitgliedernummer;
    if (mnr == null || mnr.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kein Admin angemeldet'), backgroundColor: Colors.red));
      return;
    }
    final picked = await showCloudFilePicker(context, apiService: widget.apiService, memberId: widget.userId, mitgliedernummer: mnr);
    if (picked == null || picked.isEmpty || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${picked.length} Datei(en) werden übernommen...'), duration: const Duration(seconds: 2)));
    int ok = 0;
    for (final cfId in picked) {
      final r = await widget.apiService.attachBewilligungDocFromCloud(bewilligungId: bid, cloudFileId: cfId);
      if (r['success'] == true) ok++;
    }
    if (!mounted) return;
    _load();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$ok von ${picked.length} aus Cloud übernommen'), backgroundColor: ok == picked.length ? Colors.green : Colors.orange));
  }

  // ============ WIDERSPRUCH ============

  DateTime? _parseDate(dynamic v) {
    final s = v?.toString() ?? '';
    if (s.isEmpty || s == 'null') return null;
    return DateTime.tryParse(s);
  }

  // § 37 Abs. 2 SGB X: Bekanntgabe = 3 Tage nach Aufgabe zur Post
  // § 84 SGG: Widerspruchsfrist = 1 Monat nach Bekanntgabe
  // Ohne Rechtsbehelfsbelehrung: 1 Jahr (§ 66 SGG)
  DateTime _addMonth(DateTime d, int months) {
    var y = d.year; var m = d.month + months;
    while (m > 12) { y++; m -= 12; }
    var day = d.day;
    final maxDay = DateTime(y, m + 1, 0).day;
    if (day > maxDay) day = maxDay;
    var result = DateTime(y, m, day);
    // Falls Fristende auf Wochenende/Feiertag → nächster Werktag
    while (result.weekday == DateTime.saturday || result.weekday == DateTime.sunday) {
      result = result.add(const Duration(days: 1));
    }
    return result;
  }

  Widget _buildWiderspruch(Map<String, dynamic> b) {
    final bescheidDatum = _parseDate(b['bescheid_datum']);
    final erhaltenAm = _parseDate(b['erhalten_am']);
    final hasWiderspruch = b['widerspruch'] == true || b['widerspruch'] == 'true' || b['widerspruch'] == 1 || b['widerspruch'] == '1';
    final widerspruchDatum = _parseDate(b['widerspruch_datum']);

    if (bescheidDatum == null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.warning, size: 48, color: Colors.orange.shade300),
          const SizedBox(height: 8),
          Text('Kein Bescheid-Datum vorhanden', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          Text('Bitte zuerst das Bescheid-Datum eintragen um die Fristen zu berechnen.', style: TextStyle(fontSize: 12, color: Colors.grey.shade500), textAlign: TextAlign.center),
        ]),
      ));
    }

    // Bekanntgabe: erhalten_am oder bescheid_datum + 3 Tage (Bekanntgabefiktion)
    final bekanntgabe = erhaltenAm ?? bescheidDatum.add(const Duration(days: 3));
    final fristEnde = _addMonth(bekanntgabe, 1);
    final fristOhneRHB = _addMonth(bekanntgabe, 12); // ohne Rechtsbehelfsbelehrung
    final heute = DateTime.now();
    final heute0 = DateTime(heute.year, heute.month, heute.day);
    final restTage = fristEnde.difference(heute0).inDays;
    final fristAbgelaufen = heute0.isAfter(fristEnde);
    final fristJahrAbgelaufen = heute0.isAfter(fristOhneRHB);
    final letzteWoche = !fristAbgelaufen && restTage <= 7;

    String fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

    final statusColor = hasWiderspruch
        ? Colors.blue
        : fristAbgelaufen
            ? Colors.red
            : letzteWoche
                ? Colors.orange
                : Colors.green;

    final statusText = hasWiderspruch
        ? 'Widerspruch eingelegt${widerspruchDatum != null ? ' am ${fmt(widerspruchDatum)}' : ''}'
        : fristAbgelaufen
            ? 'Frist abgelaufen seit ${-restTage} Tagen'
            : '$restTage Tage verbleibend';

    final statusIcon = hasWiderspruch
        ? Icons.check_circle
        : fristAbgelaufen
            ? Icons.cancel
            : letzteWoche
                ? Icons.warning
                : Icons.timer;

    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Status-Banner
      Container(
        width: double.infinity, padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: statusColor.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: statusColor.shade300, width: 2),
        ),
        child: Row(children: [
          Icon(statusIcon, size: 28, color: statusColor.shade700),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(statusText, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: statusColor.shade800)),
            if (!hasWiderspruch && !fristAbgelaufen)
              Text('Fristende: ${fmt(fristEnde)}', style: TextStyle(fontSize: 12, color: statusColor.shade700)),
          ])),
        ]),
      ),
      const SizedBox(height: 16),

      // Bescheid-Prüfung
      ..._buildBescheidPruefung(b, fristAbgelaufen),

      const SizedBox(height: 16),

      // Timeline
      Text('Fristenberechnung', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
      const SizedBox(height: 12),
      _timelineItem(Icons.description, 'Bescheid erstellt', fmt(bescheidDatum), Colors.indigo, true),
      if (erhaltenAm != null)
        _timelineItem(Icons.local_post_office, 'Per Post erhalten', fmt(erhaltenAm), Colors.teal, true)
      else
        _timelineItem(Icons.local_post_office, 'Bekanntgabe (Fiktion: +3 Tage)', fmt(bekanntgabe), Colors.teal.shade300, true, subtitle: '§ 37 Abs. 2 SGB X: Gilt als am 3. Tag nach Aufgabe zur Post zugestellt'),
      _timelineItem(
        fristAbgelaufen ? Icons.cancel : Icons.gavel,
        'Widerspruchsfrist endet',
        fmt(fristEnde),
        fristAbgelaufen ? Colors.red : letzteWoche ? Colors.orange : Colors.green,
        true,
        subtitle: '§ 84 SGG: 1 Monat nach Bekanntgabe',
      ),
      if (!fristAbgelaufen && !hasWiderspruch)
        _timelineItem(Icons.timer, 'Heute', fmt(heute0), Colors.blue, false, subtitle: '$restTage Tage verbleibend'),
      if (hasWiderspruch && widerspruchDatum != null)
        _timelineItem(Icons.check_circle, 'Widerspruch eingelegt', fmt(widerspruchDatum), Colors.blue, false),

      const SizedBox(height: 16),

      // Rechtsgrundlage
      Container(
        width: double.infinity, padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Rechtsgrundlage', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
          const SizedBox(height: 6),
          _lawRow('§ 84 SGG', 'Widerspruchsfrist: 1 Monat nach Bekanntgabe'),
          _lawRow('§ 37 Abs. 2 SGB X', 'Bekanntgabefiktion: 3 Tage nach Aufgabe zur Post'),
          _lawRow('§ 66 SGG', 'Ohne Rechtsbehelfsbelehrung: Frist verlängert auf 1 Jahr'),
          _lawRow('§ 84 Abs. 2 SGG', 'Fristende auf Wochenende/Feiertag: nächster Werktag'),
        ]),
      ),

      if (!fristJahrAbgelaufen && fristAbgelaufen) ...[
        const SizedBox(height: 12),
        Container(
          width: double.infinity, padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.amber.shade300)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.lightbulb, size: 20, color: Colors.amber.shade700), const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Hinweis: Fehlende Rechtsbehelfsbelehrung', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber.shade800)),
              const SizedBox(height: 4),
              Text('Falls der Bescheid keine korrekte Rechtsbehelfsbelehrung enthält, gilt eine Frist von 1 Jahr statt 1 Monat (§ 66 SGG). Prüfen Sie den Bescheid!', style: TextStyle(fontSize: 11, color: Colors.amber.shade900)),
              const SizedBox(height: 4),
              Text('Erweiterte Frist bis: ${fmt(fristOhneRHB)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber.shade800)),
            ])),
          ]),
        ),
      ],

      const SizedBox(height: 16),

      // Aktion
      if (!hasWiderspruch && !fristAbgelaufen)
        SizedBox(width: double.infinity, child: ElevatedButton.icon(
          icon: const Icon(Icons.gavel),
          label: const Text('Widerspruch einlegen'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: () => _showForm(existing: b),
        ))
      else if (!hasWiderspruch && fristAbgelaufen && !fristJahrAbgelaufen)
        SizedBox(width: double.infinity, child: OutlinedButton.icon(
          icon: const Icon(Icons.gavel, color: Colors.orange),
          label: const Text('Trotzdem Widerspruch einlegen (§ 66 SGG prüfen)'),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.orange, padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: () => _showForm(existing: b),
        )),
    ]));
  }

  // Regelbedarf 2025/2026 nach Regelbedarfsstufen (§ 20 SGB II / § 28 SGB XII)
  static const _regelbedarfMin = 563.0; // Stufe 1 Alleinstehend 2025

  List<Widget> _buildBescheidPruefung(Map<String, dynamic> b, bool fristAbgelaufen) {
    final ok = b['bewilligt'] == true || b['bewilligt'] == 'true' || b['bewilligt'] == 1 || b['bewilligt'] == '1';

    final regelbedarf = double.tryParse(b['regelbedarf']?.toString() ?? '') ?? 0;
    final mehrbedarf = double.tryParse(b['mehrbedarf']?.toString() ?? '') ?? 0;
    final kaltmiete = double.tryParse(b['kaltmiete']?.toString() ?? '') ?? 0;
    final nebenkosten = double.tryParse(b['nebenkosten']?.toString() ?? '') ?? 0;
    final heizkosten = double.tryParse(b['heizkosten']?.toString() ?? '') ?? 0;
    final einkommen = double.tryParse(b['einkommen']?.toString() ?? '') ?? 0;
    final auszahlung = double.tryParse(b['auszahlung']?.toString() ?? '') ?? 0;
    final zeitraumVon = _parseDate(b['zeitraum_von']);
    final zeitraumBis = _parseDate(b['zeitraum_bis']);
    final kdu = kaltmiete + nebenkosten + heizkosten;
    final bedarf = regelbedarf + mehrbedarf + kdu;
    final sollAuszahlung = bedarf - einkommen;

    final checks = <({String title, String detail, IconData icon, MaterialColor color, bool problem})>[];

    if (!ok) {
      // Abgelehnt — immer prüfen
      checks.add((
        title: 'Antrag wurde abgelehnt',
        detail: 'Prüfen Sie den Ablehnungsgrund. Bei unzureichender Begründung ist ein Widerspruch oft erfolgreich.',
        icon: Icons.cancel, color: Colors.red, problem: true,
      ));
    } else {
      // Regelbedarf prüfen
      if (regelbedarf > 0 && regelbedarf < _regelbedarfMin) {
        checks.add((
          title: 'Regelbedarf zu niedrig',
          detail: 'Bewilligt: ${regelbedarf.toStringAsFixed(0)} € — Minimum 2025 (Stufe 1): ${_regelbedarfMin.toStringAsFixed(0)} € (§ 20 SGB II). Differenz: ${(_regelbedarfMin - regelbedarf).toStringAsFixed(2)} €/Monat.',
          icon: Icons.warning, color: Colors.red, problem: true,
        ));
      } else if (regelbedarf >= _regelbedarfMin) {
        checks.add((
          title: 'Regelbedarf korrekt',
          detail: '${regelbedarf.toStringAsFixed(0)} € (min. ${_regelbedarfMin.toStringAsFixed(0)} € Stufe 1)',
          icon: Icons.check_circle, color: Colors.green, problem: false,
        ));
      } else if (regelbedarf == 0 && ok) {
        checks.add((
          title: 'Regelbedarf nicht eingetragen',
          detail: 'Bitte Regelbedarf aus dem Berechnungsbogen übertragen um die Prüfung durchzuführen.',
          icon: Icons.help_outline, color: Colors.grey, problem: false,
        ));
      }

      // KdU prüfen
      if (kdu > 0) {
        if (kaltmiete == 0) {
          checks.add((
            title: 'Kaltmiete fehlt im Bescheid',
            detail: 'KdU bewilligt, aber Kaltmiete ist 0 €. Mietvertrag prüfen und ggf. Widerspruch einlegen.',
            icon: Icons.warning, color: Colors.orange, problem: true,
          ));
        } else if (heizkosten == 0) {
          checks.add((
            title: 'Heizkosten fehlen',
            detail: 'Kaltmiete ${kaltmiete.toStringAsFixed(0)} € bewilligt, aber keine Heizkosten. Ggf. separat beantragt?',
            icon: Icons.warning, color: Colors.orange, problem: true,
          ));
        } else {
          checks.add((
            title: 'KdU vollständig',
            detail: 'Kaltmiete ${kaltmiete.toStringAsFixed(0)} € + NK ${nebenkosten.toStringAsFixed(0)} € + Heizung ${heizkosten.toStringAsFixed(0)} € = ${kdu.toStringAsFixed(0)} €',
            icon: Icons.check_circle, color: Colors.green, problem: false,
          ));
        }
      } else if (ok && regelbedarf > 0) {
        checks.add((
          title: 'Keine KdU bewilligt',
          detail: 'Kosten der Unterkunft (Miete, Nebenkosten, Heizung) wurden nicht bewilligt. Falls Mietwohnung vorhanden, unbedingt prüfen!',
          icon: Icons.warning, color: Colors.red, problem: true,
        ));
      }

      // Auszahlung prüfen
      if (bedarf > 0 && auszahlung > 0) {
        final diff = (sollAuszahlung - auszahlung).abs();
        if (diff > 1.0 && auszahlung < sollAuszahlung) {
          checks.add((
            title: 'Auszahlung weicht ab',
            detail: 'Bedarf ${bedarf.toStringAsFixed(2)} € − Einkommen ${einkommen.toStringAsFixed(2)} € = ${sollAuszahlung.toStringAsFixed(2)} €, aber nur ${auszahlung.toStringAsFixed(2)} € bewilligt. Differenz: ${(sollAuszahlung - auszahlung).toStringAsFixed(2)} €/Monat.',
            icon: Icons.warning, color: Colors.red, problem: true,
          ));
        } else {
          checks.add((
            title: 'Auszahlung stimmt überein',
            detail: '${auszahlung.toStringAsFixed(2)} €/Monat (Bedarf ${bedarf.toStringAsFixed(0)} € − Einkommen ${einkommen.toStringAsFixed(0)} €)',
            icon: Icons.check_circle, color: Colors.green, problem: false,
          ));
        }
      }

      // Bewilligungszeitraum prüfen
      if (zeitraumVon != null && zeitraumBis != null) {
        final monate = (zeitraumBis.year - zeitraumVon.year) * 12 + zeitraumBis.month - zeitraumVon.month;
        if (monate < 12) {
          checks.add((
            title: 'Bewilligungszeitraum nur $monate Monate',
            detail: 'Standard ist 12 Monate (§ 44 SGB XII). Ein kürzerer Zeitraum muss begründet sein.',
            icon: Icons.warning, color: Colors.orange, problem: true,
          ));
        } else {
          checks.add((
            title: 'Bewilligungszeitraum $monate Monate',
            detail: 'Standardzeitraum (12 Monate) eingehalten.',
            icon: Icons.check_circle, color: Colors.green, problem: false,
          ));
        }
      }
    }

    final problems = checks.where((c) => c.problem).length;
    final hasData = checks.any((c) => c.color != Colors.grey);

    final ({String text, MaterialColor color, IconData icon}) empfehlung = !hasData
        ? (text: 'Daten unvollständig — bitte Berechnungsbogen eintragen', color: Colors.grey, icon: Icons.help_outline)
        : problems == 0
            ? (text: 'Bescheid korrekt — Widerspruch nicht empfohlen', color: Colors.green, icon: Icons.verified)
            : problems == 1
                ? (text: '1 Auffälligkeit — Widerspruch prüfen', color: Colors.orange, icon: Icons.warning)
                : (text: '$problems Auffälligkeiten — Widerspruch empfohlen', color: Colors.red, icon: Icons.gavel);

    return [
      Text('Bescheid-Prüfung', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
      const SizedBox(height: 8),
      // Empfehlung Banner
      Container(
        width: double.infinity, padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: empfehlung.color.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: empfehlung.color.shade300, width: 1.5),
        ),
        child: Row(children: [
          Icon(empfehlung.icon, size: 24, color: empfehlung.color.shade700),
          const SizedBox(width: 10),
          Expanded(child: Text(empfehlung.text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: empfehlung.color.shade800))),
        ]),
      ),
      const SizedBox(height: 8),
      ...checks.map((c) => Container(
        margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: c.color.shade200)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(c.icon, size: 18, color: c.color.shade600), const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c.color.shade800)),
            const SizedBox(height: 2),
            Text(c.detail, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
          ])),
        ]),
      )),
    ];
  }

  Widget _timelineItem(IconData icon, String title, String date, Color color, bool hasLine, {String? subtitle}) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle, border: Border.all(color: color, width: 2)),
          child: Icon(icon, size: 16, color: color),
        ),
        if (hasLine) Container(width: 2, height: 28, color: Colors.grey.shade300),
      ]),
      const SizedBox(width: 12),
      Expanded(child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color))),
            Text(date, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
          ]),
          if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle, style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontStyle: FontStyle.italic))),
        ]),
      )),
    ]);
  }

  Widget _lawRow(String paragraph, String text) {
    return Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(4)),
        child: Text(paragraph, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: TextStyle(fontSize: 11, color: Colors.grey.shade700))),
    ]));
  }
}
