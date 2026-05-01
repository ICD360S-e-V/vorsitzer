import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'korrespondenz_attachments_widget.dart';

class SanitaetshausContent extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  const SanitaetshausContent({super.key, required this.apiService, required this.userId});
  @override
  State<SanitaetshausContent> createState() => _SanitaetshausContentState();
}

class _SanitaetshausContentState extends State<SanitaetshausContent> with TickerProviderStateMixin {
  late TabController _tabC;
  List<Map<String, dynamic>> _instances = [];
  int _selectedIdx = 0;
  bool _isLoading = true;

  Map<String, dynamic> _data = {};
  List<Map<String, dynamic>> _vorfaelle = [];

  @override
  void initState() {
    super.initState();
    _tabC = TabController(length: 2, vsync: this);
    _loadInstances();
  }

  @override
  void dispose() { _tabC.dispose(); super.dispose(); }

  Future<void> _loadInstances() async {
    setState(() => _isLoading = true);
    final res = await widget.apiService.sanitaetshausAction(widget.userId, {'action': 'list_user_sanitaetshaus'});
    if (mounted && res['success'] == true) {
      _instances = List<Map<String, dynamic>>.from(res['sanitaetshaeuser'] ?? []);
      if (_instances.isEmpty) {
        // Fallback: load old single-sanitaetshaus data
        final old = await widget.apiService.getSanitaetshausData(widget.userId);
        if (old['success'] == true) {
          _data = Map<String, dynamic>.from(old['data'] ?? {});
          _vorfaelle = (old['vorfaelle'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
        }
      } else {
        await _loadSelectedData();
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadSelectedData() async {
    if (_instances.isEmpty) return;
    final inst = _instances[_selectedIdx];
    final usId = inst['id'] is int ? inst['id'] : int.parse(inst['id'].toString());
    final res = await widget.apiService.sanitaetshausAction(widget.userId, {'action': 'list_vorfaelle_by_sanitaetshaus', 'user_sanitaetshaus_id': usId});
    if (mounted && res['success'] == true) {
      setState(() {
        _vorfaelle = List<Map<String, dynamic>>.from(res['vorfaelle'] ?? []);
        // Map to format expected by _StammdatenTab
        _data = {
          'stammdaten.selected_name': inst['sanitaetshaus_name'] ?? inst['db_name'] ?? '',
          'stammdaten.selected_strasse': inst['strasse'] ?? '',
          'stammdaten.selected_plz': inst['plz'] ?? '',
          'stammdaten.selected_ort': inst['ort'] ?? '',
          'stammdaten.selected_telefon': inst['db_telefon'] ?? '',
          'stammdaten.kundennummer': inst['kundennummer'] ?? '',
          'stammdaten.ansprechpartner': inst['ansprechpartner'] ?? '',
          'stammdaten.telefon': inst['telefon'] ?? '',
          'stammdaten.email': inst['email'] ?? '',
        };
      });
    }
  }

  Future<void> _addInstance() async {
    List<Map<String, dynamic>> allSani = [];
    List<Map<String, dynamic>> filtered = [];
    bool loading = true;
    final searchC = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          if (loading) {
            widget.apiService.sanitaetshausAction(widget.userId, {'action': 'search', 'query': ''}).then((res) {
              setDlgState(() {
                allSani = List<Map<String, dynamic>>.from(res['results'] ?? []);
                filtered = List.from(allSani);
                loading = false;
              });
            });
          }

          return AlertDialog(
            title: Row(children: [Icon(Icons.local_pharmacy, color: Colors.teal.shade700), const SizedBox(width: 8), const Text('Sanitätshaus auswählen')]),
            content: SizedBox(width: 500, height: 450, child: Column(children: [
              TextField(
                controller: searchC,
                decoration: const InputDecoration(labelText: 'Suchen...', border: OutlineInputBorder(), prefixIcon: Icon(Icons.search)),
                onChanged: (q) {
                  final lower = q.toLowerCase();
                  setDlgState(() {
                    filtered = lower.isEmpty ? List.from(allSani) : allSani.where((s) =>
                      (s['name']?.toString().toLowerCase() ?? '').contains(lower) ||
                      (s['ort']?.toString().toLowerCase() ?? '').contains(lower)
                    ).toList();
                  });
                },
              ),
              const SizedBox(height: 12),
              Expanded(child: loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                  ? Center(child: Text('Keine Ergebnisse', style: TextStyle(color: Colors.grey.shade500)))
                  : ListView.builder(itemCount: filtered.length, itemBuilder: (_, i) {
                      final r = filtered[i];
                      return ListTile(
                        leading: Icon(Icons.local_pharmacy, color: Colors.teal.shade600),
                        title: Text(r['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text('${r['strasse'] ?? ''}, ${r['plz'] ?? ''} ${r['ort'] ?? ''}', style: const TextStyle(fontSize: 11)),
                        onTap: () async {
                          final id = r['id'] is int ? r['id'] : int.parse(r['id'].toString());
                          await widget.apiService.sanitaetshausAction(widget.userId, {'action': 'add_user_sanitaetshaus', 'sanitaetshaus_id': id, 'sanitaetshaus_name': r['name'] ?? ''});
                          if (ctx.mounted) Navigator.pop(ctx);
                          _loadInstances();
                        },
                      );
                    })),
            ])),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen'))],
          );
        },
      ),
    );
    searchC.dispose();
  }

  Future<void> _removeInstance(int idx) async {
    final s = _instances[idx];
    final name = s['sanitaetshaus_name'] ?? s['db_name'] ?? 'Sanitätshaus';
    final confirm = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Entfernen?'), content: Text('$name und alle Vorfälle löschen?'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
        TextButton(onPressed: () => Navigator.pop(c, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Entfernen'))],
    ));
    if (confirm != true) return;
    final id = s['id'] is int ? s['id'] : int.parse(s['id'].toString());
    await widget.apiService.sanitaetshausAction(widget.userId, {'action': 'delete_user_sanitaetshaus', 'user_sanitaetshaus_id': id});
    _selectedIdx = 0;
    _loadInstances();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      // Multi-instance bar (like Hausarzt)
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: Colors.teal.shade50, border: Border(bottom: BorderSide(color: Colors.teal.shade200))),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (int i = 0; i < _instances.length; i++) ...[
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: InkWell(
                  onTap: () { setState(() => _selectedIdx = i); _loadSelectedData(); },
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: _selectedIdx == i ? Colors.teal.shade600 : Colors.white,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                      border: Border.all(color: _selectedIdx == i ? Colors.teal.shade600 : Colors.teal.shade200),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.local_pharmacy, size: 14, color: _selectedIdx == i ? Colors.white : Colors.teal.shade700),
                      const SizedBox(width: 6),
                      Text(
                        _instances[i]['sanitaetshaus_name'] ?? _instances[i]['db_name'] ?? 'Sanitätshaus ${i + 1}',
                        style: TextStyle(fontSize: 12, fontWeight: _selectedIdx == i ? FontWeight.bold : FontWeight.normal, color: _selectedIdx == i ? Colors.white : Colors.teal.shade700),
                      ),
                      if (i > 0 && _selectedIdx == i) ...[
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => _removeInstance(i),
                          child: Icon(Icons.close, size: 14, color: Colors.white.withValues(alpha: 0.8)),
                        ),
                      ],
                    ]),
                  ),
                ),
              ),
            ],
            // + Button
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: InkWell(
                onTap: _addInstance,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.teal.shade300)),
                  child: Icon(Icons.add, size: 16, color: Colors.teal.shade700),
                ),
              ),
            ),
          ]),
        ),
      ),
      // Tabs below
      TabBar(controller: _tabC, labelColor: Colors.teal.shade800, unselectedLabelColor: Colors.grey, indicatorColor: Colors.teal.shade700, tabs: const [
        Tab(text: 'Zuständiges Sanitätshaus'),
        Tab(text: 'Vorfall'),
      ]),
      Expanded(child: TabBarView(controller: _tabC, children: [
        _StammdatenTab(data: _data, apiService: widget.apiService, userId: widget.userId, onSaved: _loadInstances),
        _VorfallTab(vorfaelle: _vorfaelle, apiService: widget.apiService, userId: widget.userId, onReload: () async { await _loadSelectedData(); }),
      ])),
    ]);
  }
}

// ==================== TAB 1: Zuständiges Sanitätshaus ====================

class _StammdatenTab extends StatefulWidget {
  final Map<String, dynamic> data;
  final ApiService apiService;
  final int userId;
  final VoidCallback? onSaved;
  const _StammdatenTab({required this.data, required this.apiService, required this.userId, this.onSaved});
  @override
  State<_StammdatenTab> createState() => _StammdatenTabState();
}

class _StammdatenTabState extends State<_StammdatenTab> {
  List<Map<String, dynamic>> _results = [];
  Map<String, dynamic>? _selected;
  bool _searching = false;
  bool _saving = false;
  final _searchC = TextEditingController();
  late TextEditingController _kundennummerC, _ansprechpartnerC, _telefonC, _emailC;

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    _kundennummerC = TextEditingController(text: d['stammdaten.kundennummer'] ?? '');
    _ansprechpartnerC = TextEditingController(text: d['stammdaten.ansprechpartner'] ?? '');
    _telefonC = TextEditingController(text: d['stammdaten.telefon'] ?? '');
    _emailC = TextEditingController(text: d['stammdaten.email'] ?? '');
    final name = d['stammdaten.selected_name'] ?? '';
    if (name.isNotEmpty) _selected = {'name': name, 'strasse': d['stammdaten.selected_strasse'] ?? '', 'plz': d['stammdaten.selected_plz'] ?? '', 'ort': d['stammdaten.selected_ort'] ?? '', 'telefon': d['stammdaten.selected_telefon'] ?? ''};
  }

  @override
  void dispose() { _searchC.dispose(); _kundennummerC.dispose(); _ansprechpartnerC.dispose(); _telefonC.dispose(); _emailC.dispose(); super.dispose(); }

  Future<void> _search(String q) async {
    if (q.length < 2) return;
    setState(() => _searching = true);
    try {
      final res = await widget.apiService.searchSanitaetshausDatenbank(q);
      if (res['success'] == true) _results = (res['results'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
    } catch (_) {}
    if (mounted) setState(() => _searching = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final fields = <String, String>{
      'stammdaten.kundennummer': _kundennummerC.text.trim(),
      'stammdaten.ansprechpartner': _ansprechpartnerC.text.trim(),
      'stammdaten.telefon': _telefonC.text.trim(),
      'stammdaten.email': _emailC.text.trim(),
    };
    if (_selected != null) {
      fields['stammdaten.selected_name'] = _selected!['name']?.toString() ?? '';
      fields['stammdaten.selected_strasse'] = _selected!['strasse']?.toString() ?? '';
      fields['stammdaten.selected_plz'] = _selected!['plz']?.toString() ?? '';
      fields['stammdaten.selected_ort'] = _selected!['ort']?.toString() ?? '';
      fields['stammdaten.selected_telefon'] = _selected!['telefon']?.toString() ?? '';
    }
    await widget.apiService.sanitaetshausAction(widget.userId, {'action': 'save_data', 'data': fields});
    if (mounted) { setState(() => _saving = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Gespeichert'), backgroundColor: Colors.green.shade600)); }
    widget.onSaved?.call();
  }

  Widget _field(String label, TextEditingController c, {IconData icon = Icons.edit}) {
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: TextField(controller: c, decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 20), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Sanitätshaus suchen', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: TextField(controller: _searchC, decoration: InputDecoration(hintText: 'Name oder Ort...', prefixIcon: const Icon(Icons.search, size: 20), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onSubmitted: _search)),
        const SizedBox(width: 8),
        ElevatedButton(onPressed: () => _search(_searchC.text), style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white), child: const Text('Suchen')),
      ]),
      if (_searching) const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
      if (_results.isNotEmpty) Container(
        margin: const EdgeInsets.only(top: 8), constraints: const BoxConstraints(maxHeight: 200),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
        child: ListView.builder(shrinkWrap: true, itemCount: _results.length, itemBuilder: (ctx, i) {
          final s = _results[i];
          return ListTile(dense: true, title: Text(s['name'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            subtitle: Text('${s['strasse'] ?? ''}, ${s['plz'] ?? ''} ${s['ort'] ?? ''}', style: const TextStyle(fontSize: 11)),
            trailing: const Icon(Icons.check_circle_outline, size: 20),
            onTap: () => setState(() { _selected = s; _results = []; }));
        }),
      ),
      if (_selected != null) Container(
        margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.teal.shade200)),
        child: Row(children: [
          Icon(Icons.medical_services, color: Colors.teal.shade700, size: 24),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_selected!['name'] ?? '', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.teal.shade800)),
            if ((_selected!['strasse'] ?? '').isNotEmpty) Text('${_selected!['strasse']}, ${_selected!['plz'] ?? ''} ${_selected!['ort'] ?? ''}', style: const TextStyle(fontSize: 12)),
            if ((_selected!['telefon'] ?? '').isNotEmpty) Text('Tel: ${_selected!['telefon']}', style: const TextStyle(fontSize: 11)),
          ])),
          IconButton(icon: Icon(Icons.close, color: Colors.red.shade400), onPressed: () => setState(() => _selected = null)),
        ]),
      ),
      const Divider(height: 24),
      Text('Stammdaten', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
      const SizedBox(height: 8),
      _field('Kundennummer', _kundennummerC, icon: Icons.badge),
      _field('Ansprechpartner', _ansprechpartnerC, icon: Icons.person),
      Row(children: [
        Expanded(child: _field('Telefon', _telefonC, icon: Icons.phone)),
        const SizedBox(width: 12),
        Expanded(child: _field('E-Mail', _emailC, icon: Icons.email)),
      ]),
      const SizedBox(height: 12),
      Align(alignment: Alignment.centerRight, child: ElevatedButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 18),
        label: const Text('Speichern'),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white),
      )),
    ]));
  }
}

// ==================== TAB 2: Vorfall ====================

class _VorfallTab extends StatefulWidget {
  final List<Map<String, dynamic>> vorfaelle;
  final ApiService apiService;
  final int userId;
  final Future<void> Function() onReload;
  const _VorfallTab({required this.vorfaelle, required this.apiService, required this.userId, required this.onReload});
  @override
  State<_VorfallTab> createState() => _VorfallTabState();
}

class _VorfallTabState extends State<_VorfallTab> {
  static const _typLabels = {
    'hilfsmittel': 'Hilfsmittelversorgung',
    'reparatur': 'Reparatur',
    'anpassung': 'Anpassung / Nachbesserung',
    'rezept': 'Rezepteinlösung',
    'beratung': 'Beratung',
    'reklamation': 'Reklamation',
    'lieferung': 'Lieferung / Abholung',
    'kostenvoranschlag': 'Kostenvoranschlag',
    'sonstiges': 'Sonstiges',
  };

  static const _statusLabels = {
    'offen': ('Offen', Colors.orange),
    'in_bearbeitung': ('In Bearbeitung', Colors.blue),
    'warten_genehmigung': ('Warten auf Genehmigung', Colors.amber),
    'genehmigt': ('Genehmigt', Colors.green),
    'abgelehnt': ('Abgelehnt', Colors.red),
    'geliefert': ('Geliefert', Colors.teal),
    'abgeschlossen': ('Abgeschlossen', Colors.grey),
  };

  void _add() {
    String typ = 'hilfsmittel';
    String status = 'offen';
    final titelC = TextEditingController();
    final datumC = TextEditingController();
    final aktenzeichenC = TextEditingController();
    final notizC = TextEditingController();
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) => AlertDialog(
      title: Row(children: [Icon(Icons.add_circle, size: 18, color: Colors.teal.shade700), const SizedBox(width: 8), const Text('Neuer Vorfall', style: TextStyle(fontSize: 15))]),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(value: typ, decoration: InputDecoration(labelText: 'Typ', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          items: _typLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (v) => setDlg(() => typ = v ?? typ)),
        const SizedBox(height: 10),
        TextField(controller: titelC, decoration: InputDecoration(labelText: 'Titel', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(value: status, decoration: InputDecoration(labelText: 'Status', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          items: _statusLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value.$1, style: TextStyle(fontSize: 12, color: e.value.$2)))).toList(),
          onChanged: (v) => setDlg(() => status = v ?? status)),
        const SizedBox(height: 10),
        TextField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', isDense: true, prefixIcon: const Icon(Icons.calendar_today, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          onTap: () async { final d = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (d != null) datumC.text = '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}'; }),
        const SizedBox(height: 10),
        TextField(controller: aktenzeichenC, decoration: InputDecoration(labelText: 'Aktenzeichen / Vorgangsnr.', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 10),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () async {
          Navigator.pop(ctx);
          await widget.apiService.sanitaetshausAction(widget.userId, {'action': 'save_vorfall', 'vorfall': {'typ': typ, 'titel': titelC.text, 'status': status, 'datum': datumC.text, 'aktenzeichen': aktenzeichenC.text, 'notiz': notizC.text}});
          await widget.onReload();
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white), child: const Text('Hinzufügen')),
      ],
    )));
  }

  void _openDetail(Map<String, dynamic> v) {
    showDialog(context: context, barrierDismissible: false, builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: SizedBox(width: 700, height: 550, child: _VorfallDetailModal(vorfall: v, apiService: widget.apiService, userId: widget.userId, onReload: widget.onReload)),
    ));
  }

  Future<void> _delete(Map<String, dynamic> v) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Vorfall löschen?', style: TextStyle(fontSize: 15)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('Löschen'))],
    ));
    if (ok != true) return;
    await widget.apiService.sanitaetshausAction(widget.userId, {'action': 'delete_vorfall', 'id': v['id']});
    await widget.onReload();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Icon(Icons.medical_services, color: Colors.teal.shade700),
        const SizedBox(width: 8),
        Text('Vorfälle (${widget.vorfaelle.length})', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.teal.shade800)),
        const Spacer(),
        ElevatedButton.icon(onPressed: _add, icon: const Icon(Icons.add, size: 16), label: const Text('Neuer Vorfall', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white)),
      ])),
      Expanded(child: widget.vorfaelle.isEmpty
        ? Center(child: Text('Keine Vorfälle', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: widget.vorfaelle.length, itemBuilder: (ctx, i) {
            final v = widget.vorfaelle[i];
            final status = v['status']?.toString() ?? 'offen';
            final st = _statusLabels[status] ?? ('Offen', Colors.orange);
            return Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(
              onTap: () => _openDetail(v),
              leading: CircleAvatar(backgroundColor: st.$2.shade100, child: Icon(Icons.medical_services, color: st.$2.shade700, size: 20)),
              title: Text(v['titel']?.toString() ?? (_typLabels[v['typ']] ?? v['typ']?.toString() ?? ''), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: Text('${_typLabels[v['typ']] ?? ''} · ${v['datum'] ?? ''}', style: const TextStyle(fontSize: 11)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: st.$2.shade100, borderRadius: BorderRadius.circular(12)),
                  child: Text(st.$1, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: st.$2.shade800))),
                const SizedBox(width: 4),
                IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade300), onPressed: () => _delete(v)),
              ]),
            ));
          })),
    ]);
  }
}

// ==================== VORFALL DETAIL MODAL ====================

class _VorfallDetailModal extends StatefulWidget {
  final Map<String, dynamic> vorfall;
  final ApiService apiService;
  final int userId;
  final Future<void> Function() onReload;
  const _VorfallDetailModal({required this.vorfall, required this.apiService, required this.userId, required this.onReload});
  @override
  State<_VorfallDetailModal> createState() => _VorfallDetailModalState();
}

class _VorfallDetailModalState extends State<_VorfallDetailModal> with TickerProviderStateMixin {
  late TabController _tabC;
  List<Map<String, dynamic>> _termine = [];
  List<Map<String, dynamic>> _korr = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabC = TabController(length: 3, vsync: this);
    _loadDetail();
  }

  @override
  void dispose() { _tabC.dispose(); super.dispose(); }

  Future<void> _loadDetail() async {
    setState(() => _isLoading = true);
    try {
      final res = await widget.apiService.getSanitaetshausVorfallDetail(widget.userId, widget.vorfall['id'] as int);
      if (res['success'] == true) {
        _termine = (res['termine'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
        _korr = (res['korrespondenz'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final titel = widget.vorfall['titel']?.toString() ?? _VorfallTabState._typLabels[widget.vorfall['typ']] ?? '';
    return Column(children: [
      Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
        child: Row(children: [
          Icon(Icons.medical_services, color: Colors.teal.shade700),
          const SizedBox(width: 8),
          Expanded(child: Text(titel, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.teal.shade800), overflow: TextOverflow.ellipsis)),
          IconButton(icon: const Icon(Icons.close), onPressed: () { Navigator.pop(context); widget.onReload(); }),
        ])),
      TabBar(controller: _tabC, labelColor: Colors.teal.shade800, unselectedLabelColor: Colors.grey, indicatorColor: Colors.teal.shade700, tabs: const [
        Tab(text: 'Details'),
        Tab(text: 'Korrespondenz'),
        Tab(text: 'Termin'),
      ]),
      Expanded(child: _isLoading ? const Center(child: CircularProgressIndicator()) : TabBarView(controller: _tabC, children: [
        _buildDetailsTab(),
        _buildKorrTab(),
        _buildTerminTab(),
      ])),
    ]);
  }

  Widget _buildDetailsTab() {
    final v = widget.vorfall;
    final status = v['status']?.toString() ?? 'offen';
    final st = _VorfallTabState._statusLabels[status] ?? ('Offen', Colors.orange);
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: st.$2.shade100, borderRadius: BorderRadius.circular(12)),
          child: Text(st.$1, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: st.$2.shade800))),
        const Spacer(),
        if ((v['datum']?.toString() ?? '').isNotEmpty) Text(v['datum'].toString(), style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
      ]),
      const SizedBox(height: 12),
      _infoRow('Typ', _VorfallTabState._typLabels[v['typ']] ?? v['typ']?.toString() ?? ''),
      _infoRow('Titel', v['titel']?.toString() ?? ''),
      _infoRow('Aktenzeichen', v['aktenzeichen']?.toString() ?? ''),
      if ((v['notiz']?.toString() ?? '').isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Notiz', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
          child: Text(v['notiz'].toString(), style: const TextStyle(fontSize: 13))),
      ],
    ]));
  }

  Widget _infoRow(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [
      SizedBox(width: 120, child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600))),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
    ]));
  }

  // Korrespondenz tab
  Widget _buildKorrTab() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(8), child: Row(children: [
        Text('Korrespondenz (${_korr.length})', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.teal.shade800)),
        const Spacer(),
        ElevatedButton.icon(onPressed: _addKorr, icon: const Icon(Icons.add, size: 14), label: const Text('Neu', style: TextStyle(fontSize: 11)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4))),
      ])),
      Expanded(child: _korr.isEmpty
        ? Center(child: Text('Keine Korrespondenz', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(itemCount: _korr.length, itemBuilder: (ctx, i) {
            final k = _korr[i];
            final isEin = k['richtung'] == 'eingang';
            final kId = int.tryParse(k['id'].toString()) ?? 0;
            return Card(margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), child: InkWell(
              onTap: () => _openKorrDetail(k),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(dense: true,
                  leading: Icon(isEin ? Icons.call_received : Icons.call_made, color: isEin ? Colors.blue : Colors.orange, size: 20),
                  title: Text(k['betreff']?.toString() ?? '(kein Betreff)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  subtitle: Text('${k['datum'] ?? ''} · ${k['methode'] ?? ''}', style: const TextStyle(fontSize: 10)),
                  trailing: IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade300), onPressed: () async {
                    await widget.apiService.sanitaetshausAction(widget.userId, {'action': 'delete_korr', 'id': k['id']});
                    await _loadDetail();
                  }),
                ),
              ]),
            ));
          })),
    ]);
  }

  void _openKorrDetail(Map<String, dynamic> k) {
    final kId = int.tryParse(k['id'].toString()) ?? 0;
    final isEin = k['richtung'] == 'eingang';
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Row(children: [
        Icon(isEin ? Icons.call_received : Icons.call_made, size: 20, color: isEin ? Colors.blue : Colors.orange),
        const SizedBox(width: 8),
        Expanded(child: Text(k['betreff']?.toString() ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
      ]),
      content: SizedBox(width: 450, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: isEin ? Colors.blue.shade100 : Colors.orange.shade100, borderRadius: BorderRadius.circular(12)),
            child: Text(isEin ? 'Eingang' : 'Ausgang', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isEin ? Colors.blue.shade800 : Colors.orange.shade800))),
          const SizedBox(width: 8),
          if ((k['methode']?.toString() ?? '').isNotEmpty) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(12)),
            child: Text(k['methode'].toString(), style: TextStyle(fontSize: 11, color: Colors.purple.shade700))),
          const Spacer(),
          if ((k['datum']?.toString() ?? '').isNotEmpty) Text(k['datum'].toString(), style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        ]),
        if ((k['notiz']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Notiz', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
            child: Text(k['notiz'].toString(), style: const TextStyle(fontSize: 13))),
        ],
        const SizedBox(height: 16),
        KorrAttachmentsWidget(apiService: widget.apiService, modul: 'sanitaetshaus_korr', korrespondenzId: kId),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen'))],
    ));
  }

  void _addKorr() {
    String richtung = 'eingang';
    String methode = 'Brief';
    final datumC = TextEditingController();
    final betreffC = TextEditingController();
    final notizC = TextEditingController();
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) => AlertDialog(
      title: const Text('Neue Korrespondenz', style: TextStyle(fontSize: 15)),
      content: SizedBox(width: 400, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          ChoiceChip(label: const Text('Eingang'), selected: richtung == 'eingang', onSelected: (_) => setDlg(() => richtung = 'eingang')),
          const SizedBox(width: 8),
          ChoiceChip(label: const Text('Ausgang'), selected: richtung == 'ausgang', onSelected: (_) => setDlg(() => richtung = 'ausgang')),
        ]),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(value: methode, decoration: InputDecoration(labelText: 'Methode', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          items: const [DropdownMenuItem(value: 'Brief', child: Text('Brief')), DropdownMenuItem(value: 'E-Mail', child: Text('E-Mail')), DropdownMenuItem(value: 'Telefon', child: Text('Telefon')), DropdownMenuItem(value: 'Fax', child: Text('Fax')), DropdownMenuItem(value: 'Persönlich', child: Text('Persönlich'))],
          onChanged: (v) => setDlg(() => methode = v ?? methode)),
        const SizedBox(height: 10),
        TextField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', isDense: true, prefixIcon: const Icon(Icons.calendar_today, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          onTap: () async { final d = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (d != null) datumC.text = '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}'; }),
        const SizedBox(height: 10),
        TextField(controller: betreffC, decoration: InputDecoration(labelText: 'Betreff', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 10),
        TextField(controller: notizC, maxLines: 3, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () async {
          Navigator.pop(ctx);
          await widget.apiService.sanitaetshausAction(widget.userId, {'action': 'save_korr', 'vorfall_id': widget.vorfall['id'], 'korr': {'richtung': richtung, 'methode': methode, 'datum': datumC.text, 'betreff': betreffC.text, 'notiz': notizC.text}});
          await _loadDetail();
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white), child: const Text('Hinzufügen')),
      ],
    )));
  }

  // Termin tab
  Widget _buildTerminTab() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(8), child: Row(children: [
        Text('Termine (${_termine.length})', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.teal.shade800)),
        const Spacer(),
        ElevatedButton.icon(onPressed: _addTermin, icon: const Icon(Icons.add, size: 14), label: const Text('Neu', style: TextStyle(fontSize: 11)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4))),
      ])),
      Expanded(child: _termine.isEmpty
        ? Center(child: Text('Keine Termine', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(itemCount: _termine.length, itemBuilder: (ctx, i) {
            final t = _termine[i];
            return Card(margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), child: ListTile(dense: true,
              leading: Icon(Icons.event, color: Colors.teal.shade600, size: 20),
              title: Text('${t['datum'] ?? ''} ${t['uhrzeit'] ?? ''}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              subtitle: Text(t['ort']?.toString() ?? '', style: const TextStyle(fontSize: 10)),
              trailing: IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade300), onPressed: () async {
                await widget.apiService.sanitaetshausAction(widget.userId, {'action': 'delete_termin', 'id': t['id']});
                await _loadDetail();
              }),
            ));
          })),
    ]);
  }

  void _addTermin() {
    final datumC = TextEditingController();
    final uhrzeitC = TextEditingController();
    final ortC = TextEditingController();
    final notizC = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Neuer Termin', style: TextStyle(fontSize: 15)),
      content: SizedBox(width: 400, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', isDense: true, prefixIcon: const Icon(Icons.calendar_today, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          onTap: () async { final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (d != null) datumC.text = '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}'; }),
        const SizedBox(height: 10),
        TextField(controller: uhrzeitC, decoration: InputDecoration(labelText: 'Uhrzeit', isDense: true, hintText: '09:00', prefixIcon: const Icon(Icons.access_time, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 10),
        TextField(controller: ortC, decoration: InputDecoration(labelText: 'Ort', isDense: true, prefixIcon: const Icon(Icons.location_on, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 10),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () async {
          Navigator.pop(ctx);
          await widget.apiService.sanitaetshausAction(widget.userId, {'action': 'save_termin', 'vorfall_id': widget.vorfall['id'], 'termin': {'datum': datumC.text, 'uhrzeit': uhrzeitC.text, 'ort': ortC.text, 'notiz': notizC.text}});
          await _loadDetail();
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white), child: const Text('Hinzufügen')),
      ],
    ));
  }
}
