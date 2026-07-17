import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';
import 'file_viewer_dialog.dart';

/// Wohngeldstelle: 2 Tabs
///  1. Zuständige Wohngeldstelle — Auswahl aus geteilter Datenbank
///     (wohngeldstellen_datenbank) + Aktenzeichen / Sachbearbeiter / Notizen
///  2. Anträge — Liste mit "+" Button; pro Antrag ein Detail-Modal mit
///     Details / Unterlagen / Korrespondenz (eigene DB-Tabellen, verschlüsselt)
class BehordeWohngeldstelleContent extends StatefulWidget {
  final ApiService apiService;
  final int userId;

  const BehordeWohngeldstelleContent({
    super.key,
    required this.apiService,
    required this.userId,
  });

  static const type = 'wohngeldstelle';

  @override
  State<BehordeWohngeldstelleContent> createState() => _BehordeWohngeldstelleContentState();
}

/// Einreichungswege für Anträge (online / persönlich / fax / email / post).
const Map<String, (String, IconData)> _wgMethoden = {
  'online': ('Online', Icons.language),
  'persoenlich': ('Persönlich', Icons.person),
  'fax': ('Fax', Icons.fax),
  'email': ('Per E-Mail', Icons.email),
  'post': ('Per Post', Icons.local_post_office),
};

String _wgMethodeLabel(String? m) => _wgMethoden[m ?? '']?.$1 ?? (m ?? '');

const Map<String, (String, MaterialColor)> _wgStatus = {
  'geplant': ('Geplant', Colors.blueGrey),
  'eingereicht': ('Eingereicht', Colors.orange),
  'in_bearbeitung': ('In Bearbeitung', Colors.blue),
  'unterlagen_fehlen': ('Unterlagen nachgefordert', Colors.amber),
  'bewilligt': ('Bewilligt', Colors.green),
  'abgelehnt': ('Abgelehnt', Colors.red),
  'widerspruch': ('Widerspruch', Colors.purple),
};

String _wgStatusLabel(String? s) => _wgStatus[s ?? '']?.$1 ?? ((s ?? '').replaceAll('_', ' '));
MaterialColor _wgStatusColor(String? s) => _wgStatus[s ?? '']?.$2 ?? Colors.grey;

class _BehordeWohngeldstelleContentState extends State<BehordeWohngeldstelleContent> {
  // Per-user Stammdaten, bereich → feld → wert
  Map<String, Map<String, dynamic>> _dbData = {};
  bool _dbLoaded = false;

  List<Map<String, dynamic>> _antraege = [];
  bool _antraegeLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Map<String, dynamic> _db(String bereich) {
    _dbData[bereich] ??= {};
    return _dbData[bereich]!;
  }

  Future<void> _loadData() async {
    try {
      final r = await widget.apiService.getWohngeldstelleData(widget.userId);
      if (!mounted) return;
      if (r['success'] == true && r['data'] is Map) {
        _dbData = {};
        (r['data'] as Map).forEach((k, v) { if (v is Map) _dbData[k.toString()] = Map<String, dynamic>.from(v); });
      }
    } catch (e) {
      debugPrint('[Wohngeldstelle] Load error: $e');
    }
    if (!mounted) return;
    setState(() => _dbLoaded = true);
  }

  Future<void> _saveDbData() async {
    await widget.apiService.saveWohngeldstelleData(widget.userId, _dbData);
  }

  @override
  Widget build(BuildContext context) {
    if (!_dbLoaded) return const Center(child: CircularProgressIndicator());
    final amt = _dbData['amt'] ?? {};
    final hatAmt = (amt['name']?.toString() ?? '').isNotEmpty;
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            labelColor: Colors.indigo.shade700,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: Colors.indigo.shade700,
            tabs: [
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, size: 8, color: hatAmt ? Colors.green : Colors.red),
                const SizedBox(width: 4), const Icon(Icons.home_work, size: 16),
                const SizedBox(width: 4), const Flexible(child: Text('Zuständige Wohngeldstelle', overflow: TextOverflow.ellipsis)),
              ])),
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, size: 8, color: _antraege.isNotEmpty ? Colors.green : Colors.red),
                const SizedBox(width: 4), const Icon(Icons.description, size: 16),
                const SizedBox(width: 4), const Text('Anträge'),
              ])),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildAmtTab(amt),
                _buildAntragTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============ TAB 1: ZUSTÄNDIGE WOHNGELDSTELLE ============

  Widget _buildAmtTab(Map<String, dynamic> amt) {
    final hatAmt = (amt['name']?.toString() ?? '').isNotEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Amt-Auswahl
        Row(children: [
          Icon(Icons.home_work, size: 20, color: Colors.indigo.shade700),
          const SizedBox(width: 8),
          Text('Zuständige Wohngeldstelle', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
          const Spacer(),
          TextButton.icon(
            onPressed: _pickWohngeldstelle,
            icon: const Icon(Icons.search, size: 18),
            label: Text(hatAmt ? 'Ändern' : 'Auswählen', style: const TextStyle(fontSize: 12)),
          ),
        ]),
        const SizedBox(height: 8),
        if (!hatAmt)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
            child: Column(children: [
              Icon(Icons.account_balance, size: 40, color: Colors.grey.shade400),
              const SizedBox(height: 8),
              Text('Keine Wohngeldstelle ausgewählt', style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _pickWohngeldstelle,
                icon: const Icon(Icons.search, size: 16),
                label: const Text('Aus Datenbank wählen'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
              ),
            ]),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.indigo.shade200)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(amt['name']?.toString() ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
              if ((amt['strasse']?.toString() ?? '').isNotEmpty) ...[const SizedBox(height: 4), _amtRow(Icons.location_on, '${amt['strasse']}, ${amt['plz_ort'] ?? ''}')],
              if ((amt['telefon']?.toString() ?? '').isNotEmpty) _amtRow(Icons.phone, amt['telefon'].toString()),
              if ((amt['email']?.toString() ?? '').isNotEmpty) _amtRow(Icons.email, amt['email'].toString()),
              if ((amt['oeffnungszeiten']?.toString() ?? '').isNotEmpty) _amtRow(Icons.schedule, amt['oeffnungszeiten'].toString()),
            ]),
          ),
        const SizedBox(height: 12),
        Row(children: [
          Icon(Icons.info_outline, size: 14, color: Colors.grey.shade500),
          const SizedBox(width: 6),
          Expanded(child: Text('Aktenzeichen, Korrespondenz & Unterlagen werden pro Antrag im Tab „Anträge" verwaltet.', style: TextStyle(fontSize: 11, color: Colors.grey.shade500))),
        ]),
      ]),
    );
  }

  Widget _amtRow(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 14, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        ]),
      );

  Future<void> _pickWohngeldstelle() async {
    final searchC = TextEditingController();
    List<Map<String, dynamic>> results = [];
    bool loading = true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) {
        Future<void> doSearch() async {
          setD(() => loading = true);
          final r = await widget.apiService.searchWohngeldstellen(search: searchC.text.trim());
          final list = (r['wohngeldstellen'] as List?) ?? (r['data'] as List?) ?? [];
          if (!ctx2.mounted) return;
          setD(() {
            results = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
            loading = false;
          });
        }

        if (loading && results.isEmpty) {
          Future.microtask(doSearch);
        }

        return AlertDialog(
          title: const Text('Wohngeldstelle auswählen', style: TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 480,
            height: 440,
            child: Column(children: [
              TextField(
                controller: searchC,
                autofocus: true,
                onSubmitted: (_) => doSearch(),
                decoration: InputDecoration(
                  hintText: 'Suche (Name, Ort, PLZ)...',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: doSearch),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : results.isEmpty
                        ? const Center(child: Text('Keine Wohngeldstellen gefunden'))
                        : ListView.builder(
                            itemCount: results.length,
                            itemBuilder: (_, i) {
                              final a = results[i];
                              return Card(
                                child: ListTile(
                                  leading: Icon(Icons.account_balance, color: Colors.indigo.shade700),
                                  title: Text(a['name']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                  subtitle: Text('${a['strasse'] ?? ''}\n${a['plz_ort'] ?? ''}${(a['telefon']?.toString() ?? '').isNotEmpty ? '\nTel: ${a['telefon']}' : ''}', style: const TextStyle(fontSize: 11)),
                                  isThreeLine: true,
                                  onTap: () {
                                    final amt = _db('amt');
                                    amt['db_id'] = a['id']?.toString() ?? '';
                                    amt['name'] = a['name']?.toString() ?? '';
                                    amt['kurzname'] = a['kurzname']?.toString() ?? '';
                                    amt['strasse'] = a['strasse']?.toString() ?? '';
                                    amt['plz_ort'] = a['plz_ort']?.toString() ?? '';
                                    amt['telefon'] = a['telefon']?.toString() ?? '';
                                    amt['email'] = a['email']?.toString() ?? '';
                                    amt['website'] = a['website']?.toString() ?? '';
                                    amt['oeffnungszeiten'] = a['oeffnungszeiten']?.toString() ?? '';
                                    _saveDbData();
                                    setState(() {});
                                    Navigator.pop(ctx);
                                  },
                                ),
                              );
                            },
                          ),
              ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen'))],
        );
      }),
    );
  }

  // ============ TAB 2: ANTRÄGE ============

  Future<void> _loadAntraege() async {
    final r = await widget.apiService.listWohngeldstelleAntraege(widget.userId);
    if (!mounted) return;
    setState(() {
      if (r['success'] == true && r['data'] is List) {
        _antraege = (r['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      _antraegeLoaded = true;
    });
  }

  Widget _buildAntragTab() {
    if (!_antraegeLoaded) { _loadAntraege(); return const Center(child: CircularProgressIndicator()); }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          Icon(Icons.description, size: 20, color: Colors.indigo.shade700),
          const SizedBox(width: 8),
          Text('Anträge (${_antraege.length})', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _showNewAntragDialog,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Neuer Antrag'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
          ),
        ]),
      ),
      Expanded(
        child: _antraege.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.description_outlined, size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 8),
                Text('Keine Anträge vorhanden', style: TextStyle(color: Colors.grey.shade500)),
              ]))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _antraege.length,
                itemBuilder: (_, i) {
                  final a = _antraege[i];
                  final status = a['status']?.toString() ?? '';
                  final statusColor = _wgStatusColor(status);
                  final az = a['aktenzeichen']?.toString() ?? '';
                  return Card(
                    child: ListTile(
                      leading: Icon(status == 'bewilligt' ? Icons.check_circle : status == 'abgelehnt' ? Icons.cancel : Icons.hourglass_top, color: statusColor, size: 28),
                      title: Text('${a['datum'] ?? ''} — ${_wgMethodeLabel(a['methode']?.toString())}${az.isNotEmpty ? '  •  Az: $az' : ''}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: statusColor.shade100, borderRadius: BorderRadius.circular(8)),
                        child: Text(_wgStatusLabel(status).toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor.shade800)),
                      ),
                      onTap: () {
                        final aid = int.tryParse(a['id']?.toString() ?? '');
                        if (aid != null) _showAntragDetailDialog(aid, a);
                      },
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                          onPressed: () async {
                            final aid = int.tryParse(a['id']?.toString() ?? '');
                            if (aid == null) return;
                            final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
                              title: const Text('Antrag löschen?'),
                              content: const Text('Der Antrag und alle Unterlagen/Korrespondenz werden gelöscht.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
                                FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(c, true), child: const Text('Löschen')),
                              ],
                            ));
                            if (ok == true) { await widget.apiService.deleteWohngeldstelleAntrag(aid); _loadAntraege(); }
                          },
                        ),
                        Icon(Icons.chevron_right, color: Colors.grey.shade400),
                      ]),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  void _showNewAntragDialog() {
    final datumC = TextEditingController();
    final aktenzeichenC = TextEditingController();
    String methode = '';
    String status = 'eingereicht';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Text('Neuer Antrag', style: TextStyle(fontSize: 16)),
      content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Datum der Antragstellung *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        TextField(
          controller: datumC,
          readOnly: true,
          decoration: InputDecoration(
            hintText: 'Datum wählen',
            prefixIcon: const Icon(Icons.calendar_today, size: 18),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onTap: () async {
            final p = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
            if (p != null) setD(() => datumC.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}');
          },
        ),
        const SizedBox(height: 12),
        TextField(controller: aktenzeichenC, decoration: InputDecoration(labelText: 'Aktenzeichen', prefixIcon: const Icon(Icons.folder, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 12),
        Text('Einreichungsweg *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: _wgMethoden.entries.map((m) {
          final sel = methode == m.key;
          return ChoiceChip(
            label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(m.value.$2, size: 14, color: sel ? Colors.white : Colors.grey.shade700), const SizedBox(width: 4), Text(m.value.$1, style: TextStyle(fontSize: 11, color: sel ? Colors.white : Colors.black87))]),
            selected: sel, selectedColor: Colors.indigo.shade600,
            onSelected: (_) => setD(() => methode = m.key),
          );
        }).toList()),
        const SizedBox(height: 12),
        Text('Status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: status,
          isExpanded: true,
          decoration: InputDecoration(isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
          items: _wgStatus.entries.map((s) => DropdownMenuItem(value: s.key, child: Text(s.value.$1, style: const TextStyle(fontSize: 13)))).toList(),
          onChanged: (v) => setD(() => status = v ?? 'eingereicht'),
        ),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(
          onPressed: () async {
            if (datumC.text.isEmpty || methode.isEmpty) return;
            await widget.apiService.saveWohngeldstelleAntrag(widget.userId, {
              'datum': datumC.text,
              'aktenzeichen': aktenzeichenC.text.trim(),
              'methode': methode,
              'status': status,
            });
            if (ctx.mounted) Navigator.pop(ctx);
            _loadAntraege();
          },
          child: const Text('Antrag stellen'),
        ),
      ],
    )));
  }

  void _showAntragDetailDialog(int antragId, Map<String, dynamic> antrag) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.85,
          height: MediaQuery.of(context).size.height * 0.82,
          child: _WgAntragDetailView(
            apiService: widget.apiService,
            userId: widget.userId,
            antragId: antragId,
            antrag: antrag,
            onChanged: _loadAntraege,
          ),
        ),
      ),
    );
  }
}

// ============ ANTRAG DETAIL: Details / Unterlagen / Korrespondenz ============

class _WgAntragDetailView extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int antragId;
  final Map<String, dynamic> antrag;
  final VoidCallback onChanged;
  const _WgAntragDetailView({required this.apiService, required this.userId, required this.antragId, required this.antrag, required this.onChanged});

  @override
  State<_WgAntragDetailView> createState() => _WgAntragDetailViewState();
}

class _WgAntragDetailViewState extends State<_WgAntragDetailView> {
  List<Map<String, dynamic>> _docs = [];
  List<Map<String, dynamic>> _korr = [];
  bool _loaded = false;
  late Map<String, dynamic> _antrag;

  @override
  void initState() {
    super.initState();
    _antrag = Map<String, dynamic>.from(widget.antrag);
    _load();
  }

  Future<void> _load() async {
    final dR = await widget.apiService.listWgAntragDocs(widget.antragId);
    final kR = await widget.apiService.listWgAntragKorr(widget.antragId);
    if (!mounted) return;
    setState(() {
      if (dR['success'] == true && dR['data'] is List) _docs = (dR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (kR['success'] == true && kR['data'] is List) _korr = (kR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = _antrag['status']?.toString() ?? 'eingereicht';
    final isOk = status == 'bewilligt';
    return DefaultTabController(length: 3, child: Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: isOk ? Colors.green.shade700 : Colors.indigo.shade700, borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
        child: Row(children: [
          const Icon(Icons.description, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Antrag vom ${_antrag['datum'] ?? ''}', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            Text('${_wgMethodeLabel(_antrag['methode']?.toString())} • ${_wgStatusLabel(status).toUpperCase()}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ])),
          IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
        ]),
      ),
      TabBar(labelColor: Colors.indigo.shade700, unselectedLabelColor: Colors.grey.shade600, indicatorColor: Colors.indigo.shade700, tabs: [
        const Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Details'),
        Tab(icon: const Icon(Icons.folder, size: 18), text: 'Unterlagen (${_docs.length})'),
        Tab(icon: const Icon(Icons.mail, size: 18), text: 'Korrespondenz (${_korr.length})'),
      ]),
      Expanded(child: !_loaded ? const Center(child: CircularProgressIndicator()) : TabBarView(children: [
        _buildDetails(),
        _buildDokumente(),
        _buildKorrespondenz(),
      ])),
    ]));
  }

  // ---- Details ----
  Widget _buildDetails() {
    final a = _antrag;
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Antrag', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
      const SizedBox(height: 8),
      _dRow(Icons.calendar_today, 'Antragsdatum', a['datum']?.toString()),
      _dRow(Icons.send, 'Einreichungsweg', _wgMethodeLabel(a['methode']?.toString())),
      if ((a['aktenzeichen']?.toString() ?? '').isNotEmpty) _dRow(Icons.folder, 'Aktenzeichen', a['aktenzeichen'].toString()),
      const SizedBox(height: 12),
      Text('Status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
      const SizedBox(height: 4),
      DropdownButtonFormField<String>(
        initialValue: _wgStatus.containsKey(a['status']) ? a['status'].toString() : 'eingereicht',
        isExpanded: true,
        decoration: InputDecoration(isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
        items: _wgStatus.entries.map((s) => DropdownMenuItem(value: s.key, child: Text(s.value.$1, style: const TextStyle(fontSize: 13)))).toList(),
        onChanged: (v) async {
          if (v == null) return;
          setState(() => _antrag['status'] = v);
          await widget.apiService.saveWohngeldstelleAntrag(widget.userId, {
            'id': widget.antragId,
            'datum': a['datum'],
            'methode': a['methode'],
            'status': v,
            'bewilligt_von': a['bewilligt_von'],
            'bewilligt_bis': a['bewilligt_bis'],
            'aktenzeichen': a['aktenzeichen'],
            'notiz': a['notiz'],
          });
          widget.onChanged();
        },
      ),
      const SizedBox(height: 16),
      Text('Bewilligungszeitraum', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
      const SizedBox(height: 4),
      Row(children: [
        Expanded(child: _wgDateField('Bewilligt von', 'bewilligt_von')),
        const SizedBox(width: 8),
        Expanded(child: _wgDateField('Bewilligt bis', 'bewilligt_bis')),
      ]),
      const SizedBox(height: 16),
      Text('Notiz', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
      const SizedBox(height: 4),
      _NotizEditor(
        initial: a['notiz']?.toString() ?? '',
        onSave: (txt) async {
          setState(() => _antrag['notiz'] = txt);
          await widget.apiService.saveWohngeldstelleAntrag(widget.userId, {
            'id': widget.antragId,
            'datum': a['datum'],
            'methode': a['methode'],
            'status': a['status'],
            'bewilligt_von': a['bewilligt_von'],
            'bewilligt_bis': a['bewilligt_bis'],
            'aktenzeichen': a['aktenzeichen'],
            'notiz': txt,
          });
          widget.onChanged();
        },
      ),
    ]));
  }

  // Datumsfeld für den Bewilligungszeitraum (bewilligt_von / bewilligt_bis).
  // Read-only mit DatePicker + Clear-Button; speichert sofort und behält die
  // übrigen Antragsfelder bei. Wird vom WBA-Generator (Frage 20) ausgewertet:
  // fehlt bewilligt_bis, gilt die Leistung als laufend.
  Widget _wgDateField(String label, String key) {
    final val = _antrag[key]?.toString() ?? '';
    return TextField(
      readOnly: true,
      controller: TextEditingController(text: val),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        prefixIcon: const Icon(Icons.event, size: 18),
        suffixIcon: val.isEmpty ? null : IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () => _saveZeitraum(key, '')),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onTap: () async {
        final init = DateTime.tryParse(val) ?? DateTime.now();
        final p = await showDatePicker(context: context, initialDate: init, firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
        if (p != null) _saveZeitraum(key, '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}');
      },
    );
  }

  Future<void> _saveZeitraum(String key, String value) async {
    setState(() => _antrag[key] = value);
    final a = _antrag;
    await widget.apiService.saveWohngeldstelleAntrag(widget.userId, {
      'id': widget.antragId,
      'datum': a['datum'],
      'methode': a['methode'],
      'status': a['status'],
      'bewilligt_von': a['bewilligt_von'],
      'bewilligt_bis': a['bewilligt_bis'],
      'aktenzeichen': a['aktenzeichen'],
      'notiz': a['notiz'],
    });
    widget.onChanged();
  }

  Widget _dRow(IconData icon, String label, String? value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          SizedBox(width: 120, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
          Expanded(child: Text((value ?? '').isEmpty ? '—' : value!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        ]),
      );

  // ---- Unterlagen ----
  Widget _buildDokumente() {
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Row(children: [
        Icon(Icons.lock, size: 16, color: Colors.green.shade700),
        const SizedBox(width: 6),
        Expanded(child: Text('${_docs.length} Unterlagen · verschlüsselt', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
        ElevatedButton.icon(onPressed: _uploadDoc, icon: const Icon(Icons.upload_file, size: 16), label: const Text('Hochladen', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white)),
      ])),
      Expanded(child: _docs.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.cloud_upload, size: 48, color: Colors.grey.shade300), const SizedBox(height: 8), Text('Keine Unterlagen', style: TextStyle(color: Colors.grey.shade500))]))
          : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: _docs.length, itemBuilder: (_, i) {
              final d = _docs[i];
              return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green.shade200)),
                child: Row(children: [
                  Icon(Icons.attach_file, size: 18, color: Colors.green.shade700),
                  const SizedBox(width: 8),
                  Expanded(child: Text(d['datei_name']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade800))),
                  IconButton(icon: Icon(Icons.visibility, size: 18, color: Colors.indigo.shade600), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: () => _viewDoc(d, external: false)),
                  IconButton(icon: Icon(Icons.download, size: 18, color: Colors.green.shade700), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: () => _viewDoc(d, external: true)),
                  IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: () async { await widget.apiService.deleteWgAntragDoc(d['id'] as int); _load(); }),
                ]));
            })),
    ]);
  }

  Future<void> _viewDoc(Map<String, dynamic> d, {required bool external}) async {
    try {
      final resp = await widget.apiService.downloadWgAntragDoc(d['id'] as int);
      if (resp.statusCode != 200 || !mounted) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${d['datei_name']}');
      await file.writeAsBytes(resp.bodyBytes);
      if (external) {
        await OpenFilex.open(file.path);
      } else if (mounted) {
        await FileViewerDialog.show(context, file.path, d['datei_name']?.toString() ?? '');
      }
    } catch (_) {}
  }

  Future<void> _uploadDoc() async {
    final result = await FilePickerHelper.pickFiles(type: FileType.any, allowMultiple: true);
    if (result == null || result.files.isEmpty) return;
    for (final file in result.files.where((f) => f.path != null)) {
      await widget.apiService.uploadWgAntragDoc(antragId: widget.antragId, filePath: file.path!, fileName: file.name);
    }
    _load();
  }

  // ---- Korrespondenz ----
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
          ? Center(child: Text('Keine Korrespondenz', style: TextStyle(color: Colors.grey.shade500)))
          : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _korr.length, itemBuilder: (_, i) {
              final k = _korr[i];
              final isEin = k['richtung'] == 'eingang';
              final kColor = isEin ? Colors.green : Colors.blue;
              return Card(margin: const EdgeInsets.only(bottom: 6), child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _showKorrDetail(k),
                child: Padding(padding: const EdgeInsets.all(10), child: Row(children: [
                  Icon(isEin ? Icons.call_received : Icons.call_made, size: 18, color: kColor.shade700),
                  const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text((k['betreff']?.toString() ?? '').isEmpty ? '(kein Betreff)' : k['betreff'].toString(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kColor.shade800)),
                    Row(children: [
                      Text(k['datum']?.toString() ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                      if ((k['methode']?.toString() ?? '').isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(_wgMethodeLabel(k['methode']?.toString()), style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                      ],
                    ]),
                  ])),
                  Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
                  IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () async { await widget.apiService.deleteWgAntragKorr(k['id'] as int); _load(); }),
                ])),
              ));
            })),
    ]);
  }

  void _showKorrDetail(Map<String, dynamic> k) {
    final isEin = k['richtung'] == 'eingang';
    final color = isEin ? Colors.green : Colors.blue;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Row(children: [
        Icon(isEin ? Icons.call_received : Icons.call_made, size: 20, color: color.shade700),
        const SizedBox(width: 8),
        Expanded(child: Text((k['betreff']?.toString() ?? '').isEmpty ? '(kein Betreff)' : k['betreff'].toString(), style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color.shade800))),
      ]),
      content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: color.shade100, borderRadius: BorderRadius.circular(8)),
            child: Text(isEin ? 'Eingang' : 'Ausgang', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color.shade800))),
          if ((k['methode']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(8)),
              child: Text(_wgMethodeLabel(k['methode']?.toString()), style: TextStyle(fontSize: 11, color: Colors.purple.shade700))),
          ],
          const Spacer(),
          Text(k['datum']?.toString() ?? '', style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
        ]),
        if ((k['notiz']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Inhalt', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
            child: SelectableText(k['notiz'].toString(), style: const TextStyle(fontSize: 13, height: 1.4))),
        ],
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen'))],
    ));
  }

  void _addKorr(String richtung) {
    final betreffC = TextEditingController();
    final now = DateTime.now();
    final datumC = TextEditingController(text: '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}');
    final notizC = TextEditingController();
    String methode = '';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) => AlertDialog(
      title: Text(richtung == 'eingang' ? 'Eingang' : 'Ausgang', style: const TextStyle(fontSize: 16)),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', isDense: true, border: const OutlineInputBorder(), suffixIcon: IconButton(icon: const Icon(Icons.calendar_today, size: 18), onPressed: () async {
          final p = await showDatePicker(context: ctx2, initialDate: DateTime.tryParse(datumC.text) ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
          if (p != null) setD(() => datumC.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}');
        }))),
        const SizedBox(height: 8),
        Text('Kontaktart', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 6, children: _wgMethoden.entries.map((m) => ChoiceChip(
          label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(m.value.$2, size: 14, color: methode == m.key ? Colors.white : Colors.grey.shade700), const SizedBox(width: 4), Text(m.value.$1, style: TextStyle(fontSize: 11, color: methode == m.key ? Colors.white : Colors.black87))]),
          selected: methode == m.key, selectedColor: Colors.indigo, onSelected: (_) => setD(() => methode = m.key),
        )).toList()),
        const SizedBox(height: 8),
        TextField(controller: betreffC, decoration: const InputDecoration(labelText: 'Betreff', isDense: true, border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 3, decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder())),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          await widget.apiService.saveWgAntragKorr(widget.antragId, {'richtung': richtung, 'methode': methode, 'datum': datumC.text.trim(), 'betreff': betreffC.text.trim(), 'notiz': notizC.text.trim()});
          if (ctx.mounted) Navigator.pop(ctx);
          _load();
        }, child: const Text('Speichern')),
      ],
    )));
  }
}

/// Kleiner Inline-Editor für die Notiz mit Speichern-Button (nur sichtbar, wenn geändert).
class _NotizEditor extends StatefulWidget {
  final String initial;
  final Future<void> Function(String) onSave;
  const _NotizEditor({required this.initial, required this.onSave});
  @override
  State<_NotizEditor> createState() => _NotizEditorState();
}

class _NotizEditorState extends State<_NotizEditor> {
  late TextEditingController _c;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      TextField(
        controller: _c,
        maxLines: 4,
        onChanged: (v) => setState(() => _dirty = v != widget.initial),
        decoration: InputDecoration(hintText: 'z.B. fehlende Unterlagen, Fristen...', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
      ),
      if (_dirty) Padding(
        padding: const EdgeInsets.only(top: 6),
        child: FilledButton.icon(
          icon: const Icon(Icons.save, size: 16),
          label: const Text('Notiz speichern', style: TextStyle(fontSize: 12)),
          onPressed: () async { await widget.onSave(_c.text.trim()); if (mounted) setState(() => _dirty = false); },
        ),
      ),
    ]);
  }
}
