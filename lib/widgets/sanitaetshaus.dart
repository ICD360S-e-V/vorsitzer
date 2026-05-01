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

class _SanitaetshausContentState extends State<SanitaetshausContent> {
  List<Map<String, dynamic>> _userSanitaetshaeuser = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final res = await widget.apiService.sanitaetshausAction(widget.userId, {'action': 'list_user_sanitaetshaus'});
    if (mounted && res['success'] == true) {
      setState(() {
        _userSanitaetshaeuser = List<Map<String, dynamic>>.from(res['sanitaetshaeuser'] ?? []);
        _isLoading = false;
      });
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Icon(Icons.local_pharmacy, color: Colors.teal.shade700),
          const SizedBox(width: 8),
          Text('Sanitätshäuser (${_userSanitaetshaeuser.length})', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _addSanitaetshaus,
            icon: const Icon(Icons.add),
            label: const Text('Hinzufügen'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white),
          ),
        ]),
      ),
      Expanded(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _userSanitaetshaeuser.isEmpty
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.local_pharmacy, size: 48, color: Colors.grey.shade300),
                    const SizedBox(height: 8),
                    Text('Kein Sanitätshaus hinzugefügt', style: TextStyle(color: Colors.grey.shade500)),
                  ]))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _userSanitaetshaeuser.length,
                    itemBuilder: (_, i) => _buildSanitaetshausCard(_userSanitaetshaeuser[i]),
                  ),
      ),
    ]);
  }

  Widget _buildSanitaetshausCard(Map<String, dynamic> s) {
    final name = s['sanitaetshaus_name'] ?? s['db_name'] ?? '';
    final adresse = [s['strasse'], s['plz'], s['ort']].where((e) => e != null && e.toString().isNotEmpty).join(', ');
    final kundennummer = s['kundennummer'] ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: Colors.teal.shade50, child: Icon(Icons.local_pharmacy, color: Colors.teal.shade700)),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (adresse.isNotEmpty) Text(adresse, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          if (kundennummer.isNotEmpty) Text('Kd-Nr: $kundennummer', style: TextStyle(fontSize: 11, color: Colors.teal.shade600)),
        ]),
        trailing: IconButton(
          icon: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 20),
          onPressed: () async {
            final confirm = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
              title: const Text('Löschen?'), content: Text('$name und alle Vorfälle löschen?'),
              actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
                TextButton(onPressed: () => Navigator.pop(c, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Löschen'))],
            ));
            if (confirm != true) return;
            final id = s['id'] is int ? s['id'] : int.parse(s['id'].toString());
            await widget.apiService.sanitaetshausAction(widget.userId, {'action': 'delete_user_sanitaetshaus', 'user_sanitaetshaus_id': id});
            _load();
          },
        ),
        onTap: () => _showVorfaelleDialog(s),
      ),
    );
  }

  Future<void> _addSanitaetshaus() async {
    List<Map<String, dynamic>> results = [];
    bool searching = false;
    final searchC = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: Row(children: [Icon(Icons.search, color: Colors.teal.shade700), const SizedBox(width: 8), const Text('Sanitätshaus suchen')]),
          content: SizedBox(
            width: 500, height: 400,
            child: Column(children: [
              TextField(
                controller: searchC,
                decoration: InputDecoration(labelText: 'Name oder Ort...', border: const OutlineInputBorder(), suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () async {
                    if (searchC.text.trim().isEmpty) return;
                    setDlgState(() => searching = true);
                    final res = await widget.apiService.sanitaetshausAction(widget.userId, {'action': 'search', 'query': searchC.text.trim()});
                    setDlgState(() { results = List<Map<String, dynamic>>.from(res['results'] ?? []); searching = false; });
                  },
                )),
                onSubmitted: (_) async {
                  if (searchC.text.trim().isEmpty) return;
                  setDlgState(() => searching = true);
                  final res = await widget.apiService.sanitaetshausAction(widget.userId, {'action': 'search', 'query': searchC.text.trim()});
                  setDlgState(() { results = List<Map<String, dynamic>>.from(res['results'] ?? []); searching = false; });
                },
              ),
              const SizedBox(height: 12),
              Expanded(
                child: searching
                    ? const Center(child: CircularProgressIndicator())
                    : results.isEmpty
                        ? Center(child: Text('Suche starten...', style: TextStyle(color: Colors.grey.shade500)))
                        : ListView.builder(
                            itemCount: results.length,
                            itemBuilder: (_, i) {
                              final r = results[i];
                              return ListTile(
                                title: Text(r['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                subtitle: Text('${r['strasse'] ?? ''}, ${r['plz'] ?? ''} ${r['ort'] ?? ''}', style: const TextStyle(fontSize: 11)),
                                onTap: () async {
                                  final id = r['id'] is int ? r['id'] : int.parse(r['id'].toString());
                                  await widget.apiService.sanitaetshausAction(widget.userId, {
                                    'action': 'add_user_sanitaetshaus',
                                    'sanitaetshaus_id': id,
                                    'sanitaetshaus_name': r['name'] ?? '',
                                  });
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  _load();
                                },
                              );
                            },
                          ),
              ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen'))],
        ),
      ),
    );
    searchC.dispose();
  }

  Future<void> _showVorfaelleDialog(Map<String, dynamic> sanitaetshaus) async {
    final usId = sanitaetshaus['id'] is int ? sanitaetshaus['id'] : int.parse(sanitaetshaus['id'].toString());
    final name = sanitaetshaus['sanitaetshaus_name'] ?? sanitaetshaus['db_name'] ?? '';

    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: 700,
          height: MediaQuery.of(context).size.height * 0.8,
          child: _SanitaetshausVorfaelleView(
            apiService: widget.apiService,
            userId: widget.userId,
            userSanitaetshausId: usId,
            name: name,
            onClose: () => Navigator.pop(ctx),
          ),
        ),
      ),
    );
  }
}

class _SanitaetshausVorfaelleView extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int userSanitaetshausId;
  final String name;
  final VoidCallback onClose;

  const _SanitaetshausVorfaelleView({required this.apiService, required this.userId, required this.userSanitaetshausId, required this.name, required this.onClose});

  @override
  State<_SanitaetshausVorfaelleView> createState() => _SanitaetshausVorfaelleViewState();
}

class _SanitaetshausVorfaelleViewState extends State<_SanitaetshausVorfaelleView> {
  List<Map<String, dynamic>> _vorfaelle = [];
  bool _isLoading = true;

  @override
  void initState() { super.initState(); _loadVorfaelle(); }

  Future<void> _loadVorfaelle() async {
    final res = await widget.apiService.sanitaetshausAction(widget.userId, {'action': 'list_vorfaelle_by_sanitaetshaus', 'user_sanitaetshaus_id': widget.userSanitaetshausId});
    if (mounted && res['success'] == true) {
      setState(() { _vorfaelle = List<Map<String, dynamic>>.from(res['vorfaelle'] ?? []); _isLoading = false; });
    } else if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.teal.shade700, borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16))),
        child: Row(children: [
          const Icon(Icons.local_pharmacy, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(child: Text(widget.name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
          IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: widget.onClose),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Text('Vorfälle (${_vorfaelle.length})', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () => _addVorfall(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Neuer Vorfall'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white),
          ),
        ]),
      ),
      Expanded(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _vorfaelle.isEmpty
                ? Center(child: Text('Keine Vorfälle', style: TextStyle(color: Colors.grey.shade500)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _vorfaelle.length,
                    itemBuilder: (_, i) {
                      final v = _vorfaelle[i];
                      final status = v['status'] ?? 'offen';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(
                            status == 'erledigt' ? Icons.check_circle : status == 'offen' ? Icons.radio_button_unchecked : Icons.hourglass_top,
                            color: status == 'erledigt' ? Colors.green : status == 'offen' ? Colors.orange : Colors.blue,
                          ),
                          title: Text(v['titel'] ?? v['typ'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${v['datum'] ?? ''} • ${v['typ'] ?? ''}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                          onTap: () => _openVorfallDetail(v),
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }

  Future<void> _addVorfall() async {
    final typList = ['Hilfsmittelversorgung', 'Reparatur', 'Rezept einlösen', 'Beratung', 'Reklamation', 'Rückgabe', 'Anpassung', 'Nachversorgung', 'Sonstiges'];
    final titelC = TextEditingController();
    final datumC = TextEditingController(text: DateTime.now().toString().substring(0, 10));
    final notizC = TextEditingController();
    String typ = typList.first;
    String status = 'offen';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: const Text('Neuer Vorfall'),
          content: SizedBox(width: 450, child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(value: typ, decoration: const InputDecoration(labelText: 'Art', border: OutlineInputBorder()),
              items: typList.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(), onChanged: (v) => setD(() => typ = v!)),
            const SizedBox(height: 12),
            TextField(controller: titelC, decoration: const InputDecoration(labelText: 'Titel/Produkt', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: datumC, decoration: const InputDecoration(labelText: 'Datum', border: OutlineInputBorder()), readOnly: true,
              onTap: () async { final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040)); if (d != null) datumC.text = d.toString().substring(0, 10); }),
            const SizedBox(height: 12),
            Wrap(spacing: 6, children: [('offen', 'Offen', Colors.orange), ('in_bearbeitung', 'In Bearbeitung', Colors.blue), ('erledigt', 'Erledigt', Colors.green)].map((s) =>
              ChoiceChip(label: Text(s.$2, style: TextStyle(fontSize: 11, color: status == s.$1 ? Colors.white : null)), selected: status == s.$1, selectedColor: s.$3, onSelected: (_) => setD(() => status = s.$1))).toList()),
            const SizedBox(height: 12),
            TextField(controller: notizC, decoration: const InputDecoration(labelText: 'Notiz', border: OutlineInputBorder()), maxLines: 2),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            ElevatedButton(onPressed: () async {
              await widget.apiService.sanitaetshausAction(widget.userId, {
                'action': 'save_vorfall_multi',
                'user_sanitaetshaus_id': widget.userSanitaetshausId,
                'vorfall': {'typ': typ, 'titel': titelC.text.trim(), 'datum': datumC.text, 'status': status, 'notiz': notizC.text.trim()},
              });
              if (ctx.mounted) Navigator.pop(ctx);
              _loadVorfaelle();
            }, child: const Text('Erstellen')),
          ],
        ),
      ),
    );
    titelC.dispose(); datumC.dispose(); notizC.dispose();
  }

  void _openVorfallDetail(Map<String, dynamic> v) {
    // Use existing _VorfallDetailDialog pattern
    showDialog(
      context: context,
      builder: (ctx) => _VorfallDetailModal(vorfall: v, apiService: widget.apiService, userId: widget.userId, onReload: _loadVorfaelle),
    );
  }
}

class _VorfallDetailModal extends StatelessWidget {
  final Map<String, dynamic> vorfall;
  final ApiService apiService;
  final int userId;
  final dynamic onReload;

  const _VorfallDetailModal({required this.vorfall, required this.apiService, required this.userId, required this.onReload});

  @override
  Widget build(BuildContext context) {
    final vorfallId = vorfall['id'] is int ? vorfall['id'] : int.parse(vorfall['id'].toString());
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 650,
        height: MediaQuery.of(context).size.height * 0.75,
        child: DefaultTabController(
          length: 3,
          child: Column(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.teal.shade700, borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16))),
              child: Row(children: [
                const Icon(Icons.report_problem, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text(vorfall['titel'] ?? vorfall['typ'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
                IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
              ]),
            ),
            TabBar(labelColor: Colors.teal.shade700, tabs: const [
              Tab(text: 'Details'), Tab(text: 'Korrespondenz'), Tab(text: 'Termine'),
            ]),
            Expanded(child: TabBarView(children: [
              SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _row('Art', vorfall['typ'] ?? ''),
                _row('Titel', vorfall['titel'] ?? ''),
                _row('Datum', vorfall['datum'] ?? ''),
                _row('Status', vorfall['status'] ?? ''),
                _row('Aktenzeichen', vorfall['aktenzeichen'] ?? ''),
                if (vorfall['notiz']?.toString().isNotEmpty == true) _row('Notiz', vorfall['notiz']),
              ])),
              _KorrListView(apiService: apiService, userId: userId, vorfallId: vorfallId),
              _TerminListView(apiService: apiService, userId: userId, vorfallId: vorfallId),
            ])),
          ]),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 120, child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey.shade600, fontSize: 13))),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
    ]));
  }
}

// ==================== TAB 1: Zuständiges Sanitätshaus ====================

class _StammdatenTab extends StatefulWidget {
  final Map<String, dynamic> data;
  final ApiService apiService;
  final int userId;
  const _StammdatenTab({required this.data, required this.apiService, required this.userId});
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



// ==================== KORRESPONDENZ LIST (for multi-sanitaetshaus modal) ====================

class _KorrListView extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int vorfallId;
  const _KorrListView({required this.apiService, required this.userId, required this.vorfallId});
  @override
  State<_KorrListView> createState() => _KorrListViewState();
}

class _KorrListViewState extends State<_KorrListView> {
  List<Map<String, dynamic>> _korr = [];
  bool _isLoading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final res = await widget.apiService.sanitaetshausAction(widget.userId, {'action': 'list_korr', 'vorfall_id': widget.vorfallId});
    if (mounted) setState(() { _korr = List<Map<String, dynamic>>.from(res['korrespondenz'] ?? []); _isLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Padding(padding: const EdgeInsets.all(8), child: Row(children: [const Spacer(),
        ElevatedButton.icon(icon: const Icon(Icons.add, size: 16), label: const Text('Neu'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white),
          onPressed: () async {
            final betreffC = TextEditingController();
            final notizC = TextEditingController();
            await showDialog(context: context, builder: (ctx) => AlertDialog(
              title: const Text('Neue Korrespondenz'),
              content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: betreffC, decoration: const InputDecoration(labelText: 'Betreff', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: notizC, decoration: const InputDecoration(labelText: 'Notiz', border: OutlineInputBorder()), maxLines: 3),
              ])),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
                ElevatedButton(onPressed: () async {
                  await widget.apiService.sanitaetshausAction(widget.userId, {'action': 'save_korr', 'vorfall_id': widget.vorfallId, 'korr': {'betreff': betreffC.text, 'notiz': notizC.text, 'datum': DateTime.now().toString().substring(0, 10), 'richtung': 'ausgehend', 'methode': 'Brief'}});
                  if (ctx.mounted) Navigator.pop(ctx);
                  _load();
                }, child: const Text('Speichern')),
              ],
            ));
            betreffC.dispose(); notizC.dispose();
          }),
      ])),
      Expanded(child: _korr.isEmpty
        ? Center(child: Text('Keine Korrespondenz', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(itemCount: _korr.length, itemBuilder: (_, i) {
            final k = _korr[i];
            final kId = k['id'] is int ? k['id'] : int.parse(k['id'].toString());
            return Card(margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: ExpansionTile(
              leading: Icon(k['richtung'] == 'eingehend' ? Icons.call_received : Icons.call_made, color: k['richtung'] == 'eingehend' ? Colors.blue : Colors.green),
              title: Text(k['betreff'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: Text('${k['datum'] ?? ''}', style: const TextStyle(fontSize: 11)),
              children: [
                if (k['notiz']?.toString().isNotEmpty == true) Padding(padding: const EdgeInsets.all(12), child: Text(k['notiz'])),
                Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 12), child: KorrAttachmentsWidget(apiService: widget.apiService, modul: 'sanitaetshaus_korr', korrespondenzId: kId)),
              ],
            ));
          })),
    ]);
  }
}

// ==================== TERMINE LIST (for multi-sanitaetshaus modal) ====================

class _TerminListView extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int vorfallId;
  const _TerminListView({required this.apiService, required this.userId, required this.vorfallId});
  @override
  State<_TerminListView> createState() => _TerminListViewState();
}

class _TerminListViewState extends State<_TerminListView> {
  List<Map<String, dynamic>> _termine = [];
  bool _isLoading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final res = await widget.apiService.sanitaetshausAction(widget.userId, {'action': 'list_termine', 'vorfall_id': widget.vorfallId});
    if (mounted) setState(() { _termine = List<Map<String, dynamic>>.from(res['termine'] ?? []); _isLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Padding(padding: const EdgeInsets.all(8), child: Row(children: [const Spacer(),
        ElevatedButton.icon(icon: const Icon(Icons.add, size: 16), label: const Text('Neu'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white),
          onPressed: () async {
            final datumC = TextEditingController(text: DateTime.now().toString().substring(0, 10));
            final uhrzeitC = TextEditingController();
            final ortC = TextEditingController();
            final notizC = TextEditingController();
            await showDialog(context: context, builder: (ctx) => AlertDialog(
              title: const Text('Neuer Termin'),
              content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: datumC, decoration: const InputDecoration(labelText: 'Datum', border: OutlineInputBorder()), readOnly: true,
                  onTap: () async { final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040)); if (d != null) datumC.text = d.toString().substring(0, 10); }),
                const SizedBox(height: 12),
                TextField(controller: uhrzeitC, decoration: const InputDecoration(labelText: 'Uhrzeit', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: ortC, decoration: const InputDecoration(labelText: 'Ort', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: notizC, decoration: const InputDecoration(labelText: 'Notiz', border: OutlineInputBorder()), maxLines: 2),
              ])),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
                ElevatedButton(onPressed: () async {
                  await widget.apiService.sanitaetshausAction(widget.userId, {'action': 'save_termin', 'vorfall_id': widget.vorfallId, 'termin': {'datum': datumC.text, 'uhrzeit': uhrzeitC.text, 'ort': ortC.text, 'notiz': notizC.text}});
                  if (ctx.mounted) Navigator.pop(ctx);
                  _load();
                }, child: const Text('Speichern')),
              ],
            ));
            datumC.dispose(); uhrzeitC.dispose(); ortC.dispose(); notizC.dispose();
          }),
      ])),
      Expanded(child: _termine.isEmpty
        ? Center(child: Text('Keine Termine', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(itemCount: _termine.length, itemBuilder: (_, i) {
            final t = _termine[i];
            return Card(margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: ListTile(
              leading: Icon(Icons.event, color: Colors.teal.shade700),
              title: Text('${t['datum'] ?? ''} ${t['uhrzeit'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: Text('${t['ort'] ?? ''}${t['notiz']?.toString().isNotEmpty == true ? ' • ${t['notiz']}' : ''}', style: const TextStyle(fontSize: 11)),
            ));
          })),
    ]);
  }
}
