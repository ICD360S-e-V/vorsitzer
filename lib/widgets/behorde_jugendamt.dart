import 'dart:io';
import 'package:flutter/material.dart';
import 'cloud_file_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';
import 'file_viewer_dialog.dart';

/// Jugendamt: 2 Tabs
///  1. Zuständiges Jugendamt — Auswahl aus geteilter Datenbank
///     (jugendaemter_datenbank) + Hinweis, dass Az./Korrespondenz pro Antrag laufen
///  2. Anträge — Liste mit "+" Button; pro Antrag ein Detail-Modal mit
///     Details / Unterlagen / Korrespondenz (eigene DB-Tabellen, verschlüsselt).
///     Jeder Antrag hat eine Art (Unterhaltsvorschuss, Beistandschaft, …).
class BehordeJugendamtContent extends StatefulWidget {
  final ApiService apiService;
  final int userId;

  const BehordeJugendamtContent({
    super.key,
    required this.apiService,
    required this.userId,
  });

  static const type = 'jugendamt';

  @override
  State<BehordeJugendamtContent> createState() => _BehordeJugendamtContentState();
}

/// Antrags-/Leistungsarten des Jugendamts (recherchiert, SGB VIII / UhVorschG / BGB).
const List<String> _jaArten = [
  'Unterhaltsvorschuss (UVG)',
  'Beistandschaft',
  'Beurkundung (Vaterschaft/Sorge/Unterhalt)',
  'Hilfe zur Erziehung (§§ 27–35 SGB VIII)',
  'Eingliederungshilfe (§ 35a SGB VIII)',
  'Kindertagesbetreuung / wirtschaftl. Jugendhilfe',
  'Pflegekinderdienst / Vollzeitpflege',
  'Adoptionsvermittlung',
  'Amtsvormundschaft / -pflegschaft',
  'Kinderschutz / Inobhutnahme',
  'Sonstiges',
];

IconData _jaArtIcon(String? art) {
  switch (art) {
    case 'Unterhaltsvorschuss (UVG)': return Icons.euro;
    case 'Beistandschaft': return Icons.support_agent;
    case 'Beurkundung (Vaterschaft/Sorge/Unterhalt)': return Icons.assignment_ind;
    case 'Hilfe zur Erziehung (§§ 27–35 SGB VIII)': return Icons.family_restroom;
    case 'Eingliederungshilfe (§ 35a SGB VIII)': return Icons.accessible;
    case 'Kindertagesbetreuung / wirtschaftl. Jugendhilfe': return Icons.child_care;
    case 'Pflegekinderdienst / Vollzeitpflege': return Icons.volunteer_activism;
    case 'Adoptionsvermittlung': return Icons.escalator_warning;
    case 'Amtsvormundschaft / -pflegschaft': return Icons.gavel;
    case 'Kinderschutz / Inobhutnahme': return Icons.shield;
    default: return Icons.description;
  }
}

/// Einreichungswege für Anträge (online / persönlich / fax / email / post).
const Map<String, (String, IconData)> _jaMethoden = {
  'online': ('Online', Icons.language),
  'persoenlich': ('Persönlich', Icons.person),
  'fax': ('Fax', Icons.fax),
  'email': ('Per E-Mail', Icons.email),
  'post': ('Per Post', Icons.local_post_office),
};

String _jaMethodeLabel(String? m) => _jaMethoden[m ?? '']?.$1 ?? (m ?? '');

const Map<String, (String, MaterialColor)> _jaStatus = {
  'geplant': ('Geplant', Colors.blueGrey),
  'eingereicht': ('Eingereicht', Colors.orange),
  'in_bearbeitung': ('In Bearbeitung', Colors.blue),
  'unterlagen_fehlen': ('Unterlagen nachgefordert', Colors.amber),
  'bewilligt': ('Bewilligt', Colors.green),
  'abgelehnt': ('Abgelehnt', Colors.red),
  'widerspruch': ('Widerspruch', Colors.purple),
};

String _jaStatusLabel(String? s) => _jaStatus[s ?? '']?.$1 ?? ((s ?? '').replaceAll('_', ' '));
MaterialColor _jaStatusColor(String? s) => _jaStatus[s ?? '']?.$2 ?? Colors.grey;

class _BehordeJugendamtContentState extends State<BehordeJugendamtContent> {
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
      final r = await widget.apiService.getJugendamtData(widget.userId);
      if (!mounted) return;
      if (r['success'] == true && r['data'] is Map) {
        _dbData = {};
        (r['data'] as Map).forEach((k, v) { if (v is Map) _dbData[k.toString()] = Map<String, dynamic>.from(v); });
      }
    } catch (e) {
      debugPrint('[Jugendamt] Load error: $e');
    }
    if (!mounted) return;
    setState(() => _dbLoaded = true);
  }

  Future<void> _saveDbData() async {
    await widget.apiService.saveJugendamtData(widget.userId, _dbData);
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
            labelColor: Colors.teal.shade700,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: Colors.teal.shade700,
            tabs: [
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, size: 8, color: hatAmt ? Colors.green : Colors.red),
                const SizedBox(width: 4), const Icon(Icons.family_restroom, size: 16),
                const SizedBox(width: 4), const Flexible(child: Text('Zuständiges Jugendamt', overflow: TextOverflow.ellipsis)),
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

  // ============ TAB 1: ZUSTÄNDIGES JUGENDAMT ============

  Widget _buildAmtTab(Map<String, dynamic> amt) {
    final hatAmt = (amt['name']?.toString() ?? '').isNotEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.family_restroom, size: 20, color: Colors.teal.shade700),
          const SizedBox(width: 8),
          Text('Zuständiges Jugendamt', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
          const Spacer(),
          TextButton.icon(
            onPressed: _pickJugendamt,
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
              Text('Kein Jugendamt ausgewählt', style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _pickJugendamt,
                icon: const Icon(Icons.search, size: 16),
                label: const Text('Aus Datenbank wählen'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
              ),
            ]),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.teal.shade200)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(amt['name']?.toString() ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
              if ((amt['strasse']?.toString() ?? '').isNotEmpty) ...[const SizedBox(height: 4), _amtRow(Icons.location_on, '${amt['strasse']}, ${amt['plz_ort'] ?? ''}')],
              if ((amt['telefon']?.toString() ?? '').isNotEmpty) _amtRow(Icons.phone, amt['telefon'].toString()),
              if ((amt['email']?.toString() ?? '').isNotEmpty) _amtRow(Icons.email, amt['email'].toString()),
              if ((amt['website']?.toString() ?? '').isNotEmpty) _amtRow(Icons.language, amt['website'].toString()),
              if ((amt['oeffnungszeiten']?.toString() ?? '').isNotEmpty) _amtRow(Icons.schedule, amt['oeffnungszeiten'].toString()),
              if ((amt['zustaendig_fuer']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Zuständig für:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.teal.shade700)),
                const SizedBox(height: 2),
                Text(amt['zustaendig_fuer'].toString(), style: TextStyle(fontSize: 11, color: Colors.teal.shade600)),
              ],
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

  Future<void> _pickJugendamt() async {
    final searchC = TextEditingController();
    List<Map<String, dynamic>> results = [];
    bool loading = true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) {
        Future<void> doSearch() async {
          setD(() => loading = true);
          final r = await widget.apiService.searchJugendaemter(search: searchC.text.trim());
          final list = (r['jugendaemter'] as List?) ?? (r['data'] as List?) ?? [];
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
          title: const Text('Jugendamt auswählen', style: TextStyle(fontSize: 16)),
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
                        ? const Center(child: Text('Keine Jugendämter gefunden'))
                        : ListView.builder(
                            itemCount: results.length,
                            itemBuilder: (_, i) {
                              final a = results[i];
                              return Card(
                                child: ListTile(
                                  leading: Icon(Icons.account_balance, color: Colors.teal.shade700),
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
                                    amt['zustaendig_fuer'] = a['zustaendig_fuer']?.toString() ?? '';
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
    final r = await widget.apiService.listJugendamtAntraege(widget.userId);
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
          Icon(Icons.description, size: 20, color: Colors.teal.shade700),
          const SizedBox(width: 8),
          Text('Anträge (${_antraege.length})', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _showNewAntragDialog,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Neuer Antrag'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
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
                  final statusColor = _jaStatusColor(status);
                  final art = a['art']?.toString() ?? '';
                  final az = a['aktenzeichen']?.toString() ?? '';
                  return Card(
                    child: ListTile(
                      leading: Icon(_jaArtIcon(art), color: statusColor, size: 28),
                      title: Text(art.isEmpty ? '(ohne Art)' : art, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2, bottom: 4),
                          child: Text('${a['datum'] ?? ''} — ${_jaMethodeLabel(a['methode']?.toString())}${az.isNotEmpty ? '  •  Az: $az' : ''}', style: const TextStyle(fontSize: 11)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: statusColor.shade100, borderRadius: BorderRadius.circular(8)),
                          child: Text(_jaStatusLabel(status).toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor.shade800)),
                        ),
                      ]),
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
                            if (ok == true) { await widget.apiService.deleteJugendamtAntrag(aid); _loadAntraege(); }
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
    String? art;
    String methode = '';
    String status = 'eingereicht';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Text('Neuer Antrag', style: TextStyle(fontSize: 16)),
      content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Art des Antrags *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: art,
          isExpanded: true,
          decoration: InputDecoration(hintText: 'Art wählen', prefixIcon: const Icon(Icons.category, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          items: _jaArten.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) => setD(() => art = v),
        ),
        const SizedBox(height: 12),
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
        Wrap(spacing: 6, runSpacing: 6, children: _jaMethoden.entries.map((m) {
          final sel = methode == m.key;
          return ChoiceChip(
            label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(m.value.$2, size: 14, color: sel ? Colors.white : Colors.grey.shade700), const SizedBox(width: 4), Text(m.value.$1, style: TextStyle(fontSize: 11, color: sel ? Colors.white : Colors.black87))]),
            selected: sel, selectedColor: Colors.teal.shade600,
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
          items: _jaStatus.entries.map((s) => DropdownMenuItem(value: s.key, child: Text(s.value.$1, style: const TextStyle(fontSize: 13)))).toList(),
          onChanged: (v) => setD(() => status = v ?? 'eingereicht'),
        ),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(
          onPressed: () async {
            if (art == null || datumC.text.isEmpty || methode.isEmpty) return;
            await widget.apiService.saveJugendamtAntrag(widget.userId, {
              'art': art,
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
          child: _JaAntragDetailView(
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

class _JaAntragDetailView extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int antragId;
  final Map<String, dynamic> antrag;
  final VoidCallback onChanged;
  const _JaAntragDetailView({required this.apiService, required this.userId, required this.antragId, required this.antrag, required this.onChanged});

  @override
  State<_JaAntragDetailView> createState() => _JaAntragDetailViewState();
}

class _JaAntragDetailViewState extends State<_JaAntragDetailView> {
  List<Map<String, dynamic>> _docs = [];
  List<Map<String, dynamic>> _korr = [];
  List<Map<String, dynamic>> _termine = [];
  Map<String, dynamic>? _bewilligung;
  bool _loaded = false;
  late Map<String, dynamic> _antrag;

  @override
  void initState() {
    super.initState();
    _antrag = Map<String, dynamic>.from(widget.antrag);
    _load();
  }

  Future<void> _load() async {
    final dR = await widget.apiService.listJaAntragDocs(widget.antragId);
    final kR = await widget.apiService.listJaAntragKorr(widget.antragId);
    final tR = await widget.apiService.listJaAntragTermine(widget.antragId);
    final bR = await widget.apiService.getJaBewilligung(widget.antragId);
    if (!mounted) return;
    setState(() {
      if (dR['success'] == true && dR['data'] is List) _docs = (dR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (kR['success'] == true && kR['data'] is List) _korr = (kR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (tR['success'] == true && tR['data'] is List) _termine = (tR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _bewilligung = (bR['success'] == true && bR['data'] is Map) ? Map<String, dynamic>.from(bR['data'] as Map) : null;
      _loaded = true;
    });
  }

  Future<void> _persistAntrag() async {
    await widget.apiService.saveJugendamtAntrag(widget.userId, {
      'id': widget.antragId,
      'art': _antrag['art'],
      'datum': _antrag['datum'],
      'methode': _antrag['methode'],
      'status': _antrag['status'],
      'aktenzeichen': _antrag['aktenzeichen'],
      'notiz': _antrag['notiz'],
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final status = _antrag['status']?.toString() ?? 'eingereicht';
    final isOk = status == 'bewilligt';
    final art = _antrag['art']?.toString() ?? '';
    final hatBew = _bewilligung != null;
    return DefaultTabController(length: 5, child: Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: isOk ? Colors.green.shade700 : Colors.teal.shade700, borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
        child: Row(children: [
          Icon(_jaArtIcon(art), color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(art.isEmpty ? 'Antrag' : art, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            Text('${_antrag['datum'] ?? ''} • ${_jaMethodeLabel(_antrag['methode']?.toString())} • ${_jaStatusLabel(status).toUpperCase()}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ])),
          IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
        ]),
      ),
      TabBar(labelColor: Colors.teal.shade700, unselectedLabelColor: Colors.grey.shade600, indicatorColor: Colors.teal.shade700, isScrollable: true, tabs: [
        const Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Details'),
        Tab(icon: const Icon(Icons.folder, size: 18), text: 'Unterlagen (${_docs.length})'),
        Tab(icon: const Icon(Icons.mail, size: 18), text: 'Korrespondenz (${_korr.length})'),
        Tab(icon: const Icon(Icons.event, size: 18), text: 'Termine (${_termine.length})'),
        Tab(icon: Icon(hatBew ? Icons.verified : Icons.verified_outlined, size: 18), text: 'Bewilligung'),
      ]),
      Expanded(child: !_loaded ? const Center(child: CircularProgressIndicator()) : TabBarView(children: [
        _buildDetails(),
        _buildDokumente(),
        _buildKorrespondenz(),
        _buildTermine(),
        _buildBewilligung(),
      ])),
    ]));
  }

  // ---- Details ----
  Widget _buildDetails() {
    final a = _antrag;
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Antrag', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
      const SizedBox(height: 8),
      Text('Art', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
      const SizedBox(height: 4),
      DropdownButtonFormField<String>(
        initialValue: _jaArten.contains(a['art']) ? a['art'].toString() : null,
        isExpanded: true,
        decoration: InputDecoration(isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
        items: _jaArten.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))).toList(),
        onChanged: (v) async {
          if (v == null) return;
          setState(() => _antrag['art'] = v);
          await _persistAntrag();
        },
      ),
      const SizedBox(height: 12),
      _dRow(Icons.calendar_today, 'Antragsdatum', a['datum']?.toString()),
      _dRow(Icons.send, 'Einreichungsweg', _jaMethodeLabel(a['methode']?.toString())),
      if ((a['aktenzeichen']?.toString() ?? '').isNotEmpty) _dRow(Icons.folder, 'Aktenzeichen', a['aktenzeichen'].toString()),
      const SizedBox(height: 12),
      Text('Status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
      const SizedBox(height: 4),
      DropdownButtonFormField<String>(
        initialValue: _jaStatus.containsKey(a['status']) ? a['status'].toString() : 'eingereicht',
        isExpanded: true,
        decoration: InputDecoration(isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
        items: _jaStatus.entries.map((s) => DropdownMenuItem(value: s.key, child: Text(s.value.$1, style: const TextStyle(fontSize: 13)))).toList(),
        onChanged: (v) async {
          if (v == null) return;
          setState(() => _antrag['status'] = v);
          await _persistAntrag();
        },
      ),
      const SizedBox(height: 16),
      Text('Notiz', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
      const SizedBox(height: 4),
      _NotizEditor(
        initial: a['notiz']?.toString() ?? '',
        onSave: (txt) async {
          setState(() => _antrag['notiz'] = txt);
          await _persistAntrag();
        },
      ),
    ]));
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
        OutlinedButton.icon(
          onPressed: () async {
            final res = await pickAndAttachFromCloud(context, apiService: widget.apiService, memberId: widget.userId,
                attach: (id) => widget.apiService.attachJaAntragDocFromCloud(antragId: widget.antragId, cloudFileId: id));
            if (res != null && mounted) { _load(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${res.ok} von ${res.total} aus Cloud übernommen'), backgroundColor: res.ok == res.total ? Colors.green : Colors.orange)); }
          },
          icon: const Icon(Icons.cloud_download, size: 16), label: const Text('Aus Cloud', style: TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.blue.shade700)),
        const SizedBox(width: 6),
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
                  IconButton(icon: Icon(Icons.visibility, size: 18, color: Colors.teal.shade600), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: () => _viewDoc(d, external: false)),
                  IconButton(icon: Icon(Icons.download, size: 18, color: Colors.green.shade700), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: () => _viewDoc(d, external: true)),
                  IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: () async { await widget.apiService.deleteJaAntragDoc(d['id'] as int); _load(); }),
                ]));
            })),
    ]);
  }

  Future<void> _viewDoc(Map<String, dynamic> d, {required bool external}) async {
    try {
      final resp = await widget.apiService.downloadJaAntragDoc(d['id'] as int);
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
      await widget.apiService.uploadJaAntragDoc(antragId: widget.antragId, filePath: file.path!, fileName: file.name);
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
                        Text(_jaMethodeLabel(k['methode']?.toString()), style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                      ],
                    ]),
                  ])),
                  Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
                  IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () async { await widget.apiService.deleteJaAntragKorr(k['id'] as int); _load(); }),
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
              child: Text(_jaMethodeLabel(k['methode']?.toString()), style: TextStyle(fontSize: 11, color: Colors.purple.shade700))),
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
        Wrap(spacing: 6, runSpacing: 6, children: _jaMethoden.entries.map((m) => ChoiceChip(
          label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(m.value.$2, size: 14, color: methode == m.key ? Colors.white : Colors.grey.shade700), const SizedBox(width: 4), Text(m.value.$1, style: TextStyle(fontSize: 11, color: methode == m.key ? Colors.white : Colors.black87))]),
          selected: methode == m.key, selectedColor: Colors.teal, onSelected: (_) => setD(() => methode = m.key),
        )).toList()),
        const SizedBox(height: 8),
        TextField(controller: betreffC, decoration: const InputDecoration(labelText: 'Betreff', isDense: true, border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 3, decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder())),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          await widget.apiService.saveJaAntragKorr(widget.antragId, {'richtung': richtung, 'methode': methode, 'datum': datumC.text.trim(), 'betreff': betreffC.text.trim(), 'notiz': notizC.text.trim()});
          if (ctx.mounted) Navigator.pop(ctx);
          _load();
        }, child: const Text('Speichern')),
      ],
    )));
  }

  // ---- Termine (Sync Terminverwaltung) ----
  Widget _buildTermine() {
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 4), child: Row(children: [
        Icon(Icons.event, size: 18, color: Colors.teal.shade700),
        const SizedBox(width: 6),
        Expanded(child: Text('Termine', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.teal.shade700))),
        ElevatedButton.icon(onPressed: _addTermin, icon: const Icon(Icons.add, size: 14), label: const Text('Neuer Termin', style: TextStyle(fontSize: 11)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10))),
      ])),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.blue.shade200)),
        child: Row(children: [
          Icon(Icons.info_outline, size: 14, color: Colors.blue.shade700),
          const SizedBox(width: 6),
          Expanded(child: Text('Termine werden automatisch in die zentrale Terminverwaltung übernommen.', style: TextStyle(fontSize: 10, color: Colors.blue.shade900))),
        ]),
      )),
      Expanded(child: _termine.isEmpty
          ? Center(child: Text('Keine Termine', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)))
          : ListView.builder(padding: const EdgeInsets.fromLTRB(12, 8, 12, 12), itemCount: _termine.length, itemBuilder: (_, i) {
              final t = _termine[i];
              final hasGlobal = (t['termin_id']?.toString() ?? '').isNotEmpty && t['termin_id'] != null;
              return Card(margin: const EdgeInsets.only(bottom: 6), child: ListTile(
                dense: true,
                leading: Icon(Icons.event, color: Colors.teal.shade700, size: 22),
                title: Text('${t['datum'] ?? ''}${(t['uhrzeit']?.toString() ?? '').isNotEmpty ? '  ·  ${t['uhrzeit']}' : ''}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if ((t['ort']?.toString() ?? '').isNotEmpty) Text('Ort: ${t['ort']}', style: const TextStyle(fontSize: 11)),
                  if ((t['notiz']?.toString() ?? '').isNotEmpty) Text(t['notiz'].toString(), style: const TextStyle(fontSize: 11)),
                  if (hasGlobal) Padding(padding: const EdgeInsets.only(top: 2), child: Row(children: [
                    Icon(Icons.check_circle, size: 10, color: Colors.green.shade600),
                    const SizedBox(width: 3),
                    Text('In Terminverwaltung übernommen', style: TextStyle(fontSize: 9, color: Colors.green.shade700, fontWeight: FontWeight.w600)),
                  ])),
                ]),
                trailing: IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400), onPressed: () async {
                  final id = int.tryParse(t['id']?.toString() ?? '');
                  if (id != null) { await widget.apiService.deleteJaAntragTermin(id); await _load(); }
                }),
              ));
            })),
    ]);
  }

  Future<void> _addTermin() async {
    final datumC = TextEditingController();
    final uhrzeitC = TextEditingController();
    final ortC = TextEditingController();
    final notizC = TextEditingController();
    bool submitting = false;
    if (!mounted) return;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Neuer Termin'),
        content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: TextField(controller: datumC, readOnly: true,
              decoration: InputDecoration(labelText: 'Datum *', prefixIcon: const Icon(Icons.calendar_today, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              onTap: () async {
                final p = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
                if (p != null) setD(() => datumC.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}');
              })),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: uhrzeitC, readOnly: true,
              decoration: InputDecoration(labelText: 'Uhrzeit *', prefixIcon: const Icon(Icons.access_time, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              onTap: () async {
                final t = await showTimePicker(context: ctx2, initialTime: const TimeOfDay(hour: 9, minute: 0));
                if (t != null) setD(() => uhrzeitC.text = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
              })),
          ]),
          const SizedBox(height: 8),
          TextField(controller: ortC, decoration: InputDecoration(labelText: 'Ort', prefixIcon: const Icon(Icons.place, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 8),
          TextField(controller: notizC, maxLines: 3, decoration: InputDecoration(labelText: 'Notiz / Anlass', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.blue.shade200)),
            child: Row(children: [
              Icon(Icons.info_outline, size: 14, color: Colors.blue.shade700),
              const SizedBox(width: 6),
              Expanded(child: Text('Termin wird automatisch in der Terminverwaltung erstellt (Institution & Az. aus diesem Antrag).', style: TextStyle(fontSize: 10, color: Colors.blue.shade900))),
            ])),
        ]))),
        actions: [
          TextButton(onPressed: submitting ? null : () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: submitting ? null : () async {
            if (datumC.text.trim().isEmpty || uhrzeitC.text.trim().isEmpty) return;
            setD(() => submitting = true);
            await widget.apiService.saveJaAntragTermin(widget.antragId, widget.userId, {
              'datum': datumC.text.trim(), 'uhrzeit': uhrzeitC.text.trim(), 'ort': ortC.text.trim(), 'notiz': notizC.text.trim(),
            });
            if (ctx.mounted) Navigator.pop(ctx, true);
          }, child: submitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Speichern')),
        ],
      );
    }));
    if (ok == true) await _load();
  }

  // ---- Bewilligung (1:1 pro Antrag) ----
  Widget _buildBewilligung() {
    return _JaBewilligungForm(
      apiService: widget.apiService,
      userId: widget.userId,
      antragId: widget.antragId,
      initial: _bewilligung,
      onSaved: _load,
    );
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

/// Bewilligungsformular (1:1 pro Antrag). Erfasst Bescheid, Zeitraum, Beträge,
/// Widerspruch. Auto-Weiterbewilligung-Erinnerung serverseitig (2 Mon. vor Ablauf).
class _JaBewilligungForm extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int antragId;
  final Map<String, dynamic>? initial;
  final VoidCallback onSaved;
  const _JaBewilligungForm({required this.apiService, required this.userId, required this.antragId, required this.initial, required this.onSaved});

  @override
  State<_JaBewilligungForm> createState() => _JaBewilligungFormState();
}

class _JaBewilligungFormState extends State<_JaBewilligungForm> {
  late bool _bewilligt;
  late bool _widerspruch;
  late TextEditingController _bescheidC, _vonC, _bisC, _wsDatumC, _monatlichC, _einmalC, _aktenC, _notizC;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final b = widget.initial ?? {};
    _bewilligt = (b['bewilligt']?.toString() ?? '1') != '0';
    _widerspruch = (b['widerspruch']?.toString() ?? '0') == '1';
    _bescheidC = TextEditingController(text: b['bescheid_datum']?.toString() ?? '');
    _vonC = TextEditingController(text: b['zeitraum_von']?.toString() ?? '');
    _bisC = TextEditingController(text: b['zeitraum_bis']?.toString() ?? '');
    _wsDatumC = TextEditingController(text: b['widerspruch_datum']?.toString() ?? '');
    _monatlichC = TextEditingController(text: _fmtNum(b['betrag_monatlich']));
    _einmalC = TextEditingController(text: _fmtNum(b['einmalbetrag']));
    _aktenC = TextEditingController(text: b['aktenzeichen']?.toString() ?? '');
    _notizC = TextEditingController(text: b['notiz']?.toString() ?? '');
  }

  String _fmtNum(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
  }

  @override
  void dispose() {
    for (final c in [_bescheidC, _vonC, _bisC, _wsDatumC, _monatlichC, _einmalC, _aktenC, _notizC]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _pickDate(TextEditingController c) async {
    final p = await showDatePicker(context: context, initialDate: DateTime.tryParse(c.text) ?? DateTime.now(), firstDate: DateTime(2015), lastDate: DateTime(2045), locale: const Locale('de'));
    if (p != null) setState(() => c.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}');
  }

  Widget _dateField(String label, TextEditingController c, IconData icon) => TextField(
        controller: c, readOnly: true,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          suffixIcon: c.text.isEmpty ? null : IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () => setState(() => c.clear()))),
        onTap: () => _pickDate(c),
      );

  Future<void> _save() async {
    setState(() => _saving = true);
    final r = await widget.apiService.saveJaBewilligung(widget.userId, {
      if (widget.initial?['id'] != null) 'id': widget.initial!['id'],
      'antrag_id': widget.antragId,
      'bewilligt': _bewilligt,
      'bescheid_datum': _bescheidC.text.trim(),
      'zeitraum_von': _vonC.text.trim(),
      'zeitraum_bis': _bisC.text.trim(),
      'betrag_monatlich': _monatlichC.text.trim().replaceAll(',', '.'),
      'einmalbetrag': _einmalC.text.trim().replaceAll(',', '.'),
      'aktenzeichen': _aktenC.text.trim(),
      'widerspruch': _widerspruch,
      'widerspruch_datum': _wsDatumC.text.trim(),
      'notiz': _notizC.text.trim(),
    });
    if (!mounted) return;
    setState(() => _saving = false);
    final wba = r['wba_action']?.toString();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r['success'] == true
          ? 'Bewilligung gespeichert${(wba == 'created' || wba == 'updated') ? ' · Weiterbewilligung-Erinnerung angelegt' : ''}'
          : 'Fehler beim Speichern'),
      backgroundColor: r['success'] == true ? Colors.green.shade700 : Colors.red,
    ));
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final wba = widget.initial?['wba_ticket'];
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.verified, size: 18, color: Colors.teal.shade700),
        const SizedBox(width: 6),
        Text('Bewilligung / Bescheid', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
        const Spacer(),
        if (widget.initial?['id'] != null)
          IconButton(icon: Icon(Icons.delete_outline, size: 20, color: Colors.red.shade400), tooltip: 'Bewilligung löschen', onPressed: () async {
            final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
              title: const Text('Bewilligung löschen?'),
              content: const Text('Der Bescheid-Datensatz wird gelöscht. Eine offene Weiterbewilligung-Erinnerung wird geschlossen.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
                FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(c, true), child: const Text('Löschen')),
              ],
            ));
            if (ok == true) { await widget.apiService.deleteJaBewilligung(widget.initial!['id'] as int); widget.onSaved(); }
          }),
      ]),
      const SizedBox(height: 10),
      // Bewilligt / Abgelehnt
      Row(children: [
        Expanded(child: ChoiceChip(
          label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.check_circle, size: 15, color: _bewilligt ? Colors.white : Colors.green.shade600), const SizedBox(width: 4), Text('Bewilligt', style: TextStyle(fontSize: 12, color: _bewilligt ? Colors.white : Colors.black87))]),
          selected: _bewilligt, selectedColor: Colors.green.shade600, onSelected: (_) => setState(() => _bewilligt = true))),
        const SizedBox(width: 8),
        Expanded(child: ChoiceChip(
          label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.cancel, size: 15, color: !_bewilligt ? Colors.white : Colors.red.shade600), const SizedBox(width: 4), Text('Abgelehnt', style: TextStyle(fontSize: 12, color: !_bewilligt ? Colors.white : Colors.black87))]),
          selected: !_bewilligt, selectedColor: Colors.red.shade600, onSelected: (_) => setState(() => _bewilligt = false))),
      ]),
      const SizedBox(height: 12),
      _dateField('Bescheid-Datum', _bescheidC, Icons.event_note),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _dateField('Zeitraum von', _vonC, Icons.play_arrow)),
        const SizedBox(width: 8),
        Expanded(child: _dateField('Zeitraum bis', _bisC, Icons.flag)),
      ]),
      const SizedBox(height: 4),
      Padding(padding: const EdgeInsets.only(left: 4), child: Text('„Zeitraum bis" steuert die automatische Weiterbewilligung-Erinnerung (2 Monate vorher).', style: TextStyle(fontSize: 10, color: Colors.grey.shade500))),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: TextField(controller: _monatlichC, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Betrag mtl. (€)', prefixIcon: const Icon(Icons.euro, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
        const SizedBox(width: 8),
        Expanded(child: TextField(controller: _einmalC, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Einmalbetrag (€)', prefixIcon: const Icon(Icons.payments, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
      ]),
      const SizedBox(height: 10),
      TextField(controller: _aktenC, decoration: InputDecoration(labelText: 'Aktenzeichen / Bescheid-Nr.', prefixIcon: const Icon(Icons.folder, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      const SizedBox(height: 12),
      Container(
        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
        child: Column(children: [
          SwitchListTile(
            dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            title: const Text('Widerspruch eingelegt', style: TextStyle(fontSize: 13)),
            value: _widerspruch, activeThumbColor: Colors.purple, onChanged: (v) => setState(() => _widerspruch = v)),
          if (_widerspruch) Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 10), child: _dateField('Widerspruch-Datum', _wsDatumC, Icons.gavel)),
        ]),
      ),
      const SizedBox(height: 12),
      TextField(controller: _notizC, maxLines: 3, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      if (wba is Map) ...[
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade300)),
          child: Row(children: [
            Icon(Icons.notifications_active, size: 18, color: Colors.amber.shade800),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Weiterbewilligung-Erinnerung aktiv', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
              Text('Ticket #${wba['ticket_id']} · fällig ${(wba['scheduled_date']?.toString() ?? '').split(' ').first} · Bewilligung bis ${wba['bis'] ?? ''}', style: TextStyle(fontSize: 11, color: Colors.amber.shade900)),
            ])),
          ])),
      ],
      const SizedBox(height: 16),
      SizedBox(width: double.infinity, child: FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: Colors.teal),
        icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 18),
        label: Text(widget.initial?['id'] != null ? 'Bewilligung aktualisieren' : 'Bewilligung speichern'),
        onPressed: _saving ? null : _save,
      )),
    ]));
  }
}
