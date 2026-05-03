import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/eastern.dart';
import '../widgets/korrespondenz_attachments_widget.dart';

class TelekomScreen extends StatefulWidget {
  final VoidCallback onBack;
  const TelekomScreen({super.key, required this.onBack});

  @override
  State<TelekomScreen> createState() => _TelekomScreenState();
}

class _TelekomScreenState extends State<TelekomScreen> with TickerProviderStateMixin {
  final _apiService = ApiService();
  late TabController _tabC;
  Map<String, dynamic> _firmaData = {};
  List<Map<String, dynamic>> _vertraege = [];
  bool _isLoading = true;
  bool _firmaEditing = false;

  @override
  void initState() {
    super.initState();
    _tabC = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() { _tabC.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _apiService.telekomAction({'action': 'get_data'}),
        _apiService.telekomAction({'action': 'list_vertraege'}),
      ]);
      if (mounted) {
        _firmaData = results[0]['success'] == true ? Map<String, dynamic>.from(results[0]['data'] ?? {}) : {};
        _vertraege = results[1]['success'] == true ? List<Map<String, dynamic>>.from(results[1]['vertraege'] ?? []) : [];
      }
    } catch (e) {
      debugPrint('[Telekom] load error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return SeasonalBackground(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        Row(children: [
          IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
          const SizedBox(width: 8),
          Icon(Icons.phone_android, size: 32, color: Colors.pink.shade700),
          const SizedBox(width: 12),
          const Text('Telekom', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 16),
        TabBar(controller: _tabC, labelColor: Colors.pink.shade700, indicatorColor: Colors.pink.shade700, tabs: const [
          Tab(icon: Icon(Icons.business), text: 'Firma'),
          Tab(icon: Icon(Icons.badge), text: 'Stammdaten'),
          Tab(icon: Icon(Icons.receipt_long), text: 'Verträge'),
        ]),
        Expanded(child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(controller: _tabC, children: [
              _buildFirmaTab(),
              _buildStammdatenTab(),
              _buildVertraegeTab(),
            ])),
      ]),
    ));
  }

  Widget _buildFirmaTab() {
    final d = _firmaData;
    final selectedName = d['firma.filiale'] ?? '';

    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.store, size: 20, color: Colors.pink.shade700),
        const SizedBox(width: 8),
        Expanded(child: Text('Zuständige Filiale', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.pink.shade700))),
        OutlinedButton.icon(
          icon: const Icon(Icons.search, size: 16),
          label: Text(selectedName.isEmpty ? 'Auswählen' : 'Ändern', style: const TextStyle(fontSize: 12)),
          onPressed: _showFilialeSearchDialog,
        ),
      ]),
      const SizedBox(height: 12),
      if (selectedName.isEmpty)
        Container(
          width: double.infinity, padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
          child: Column(children: [
            Icon(Icons.search, size: 40, color: Colors.grey.shade400), const SizedBox(height: 8),
            Text('Keine Filiale ausgewählt', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ]),
        )
      else ...[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.pink.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.pink.shade200)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(selectedName, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.pink.shade900)),
            const SizedBox(height: 6),
            _infoCard('Adresse', d['firma.adresse'] ?? ''),
            _infoCard('Telefon', d['firma.telefon'] ?? ''),
            _infoCard('E-Mail', d['firma.email'] ?? ''),
            _infoCard('Öffnungszeiten', d['firma.oeffnungszeiten'] ?? ''),
            _infoCard('Kundennummer', d['firma.kundennummer'] ?? ''),
            _infoCard('Ansprechpartner', d['firma.ansprechpartner'] ?? ''),
          ]),
        ),
      ],
    ]));
  }

  Widget _buildStammdatenTab() {
    final d = _firmaData;
    final kdnr = d['stammdaten.kundennummer'] ?? '';
    final loginId = d['stammdaten.login_id'] ?? '';
    final ansprechpartner = d['stammdaten.ansprechpartner'] ?? '';
    final telefon = d['stammdaten.telefon'] ?? '';
    final email = d['stammdaten.email'] ?? '';

    return StatefulBuilder(builder: (context, setLocalState) {
      bool editing = false;
      return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.badge, size: 20, color: Colors.pink.shade700),
          const SizedBox(width: 8),
          Text('Kundenstammdaten', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.pink.shade700)),
          const Spacer(),
          OutlinedButton.icon(icon: const Icon(Icons.edit, size: 16), label: const Text('Bearbeiten', style: TextStyle(fontSize: 12)),
            onPressed: () => _editStammdaten()),
        ]),
        const SizedBox(height: 16),
        Container(
          width: double.infinity, padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.pink.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.pink.shade200)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _infoCard('Kundennummer', kdnr),
            _infoCard('Login-ID / Benutzername', loginId),
            _infoCard('Ansprechpartner', ansprechpartner),
            _infoCard('Telefon (Kontakt)', telefon),
            _infoCard('E-Mail', email),
            if (kdnr.isEmpty && loginId.isEmpty && ansprechpartner.isEmpty)
              Text('Noch keine Stammdaten hinterlegt', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          ]),
        ),
      ]));
    });
  }

  void _editStammdaten() {
    final d = _firmaData;
    final kdnrC = TextEditingController(text: d['stammdaten.kundennummer'] ?? '');
    final loginC = TextEditingController(text: d['stammdaten.login_id'] ?? '');
    final ansprechC = TextEditingController(text: d['stammdaten.ansprechpartner'] ?? '');
    final telC = TextEditingController(text: d['stammdaten.telefon'] ?? '');
    final emailC = TextEditingController(text: d['stammdaten.email'] ?? '');

    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Stammdaten bearbeiten'),
      content: SizedBox(width: 450, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: kdnrC, decoration: const InputDecoration(labelText: 'Kundennummer', isDense: true, prefixIcon: Icon(Icons.numbers, size: 18), border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: loginC, decoration: const InputDecoration(labelText: 'Login-ID / Benutzername', isDense: true, prefixIcon: Icon(Icons.person, size: 18), border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: ansprechC, decoration: const InputDecoration(labelText: 'Ansprechpartner', isDense: true, prefixIcon: Icon(Icons.contact_phone, size: 18), border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: telC, decoration: const InputDecoration(labelText: 'Telefon (Kontakt)', isDense: true, prefixIcon: Icon(Icons.phone, size: 18), border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: emailC, decoration: const InputDecoration(labelText: 'E-Mail', isDense: true, prefixIcon: Icon(Icons.email, size: 18), border: OutlineInputBorder())),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        ElevatedButton.icon(icon: const Icon(Icons.check), label: const Text('Speichern'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.pink.shade700, foregroundColor: Colors.white),
          onPressed: () async {
            await _apiService.telekomAction({'action': 'save_data', 'data': {
              'stammdaten.kundennummer': kdnrC.text.trim(),
              'stammdaten.login_id': loginC.text.trim(),
              'stammdaten.ansprechpartner': ansprechC.text.trim(),
              'stammdaten.telefon': telC.text.trim(),
              'stammdaten.email': emailC.text.trim(),
            }});
            if (ctx.mounted) Navigator.pop(ctx);
            _load();
          }),
      ],
    ));
  }

  void _showFilialeSearchDialog() async {
    List<Map<String, dynamic>> filialen = [];
    List<Map<String, dynamic>> filtered = [];
    bool loading = true;
    final searchC = TextEditingController();

    await showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (_, setDlgState) {
      if (loading) {
        _apiService.telekomAction({'action': 'search_filialen', 'query': ''}).then((res) {
          setDlgState(() { filialen = List<Map<String, dynamic>>.from(res['filialen'] ?? []); filtered = List.from(filialen); loading = false; });
        });
      }
      return AlertDialog(
        title: Row(children: [Icon(Icons.search, color: Colors.pink.shade700), const SizedBox(width: 8), const Text('Telekom Filiale auswählen')]),
        content: SizedBox(width: 500, height: 400, child: Column(children: [
          TextField(controller: searchC, decoration: const InputDecoration(labelText: 'Suchen...', border: OutlineInputBorder(), prefixIcon: Icon(Icons.search)),
            onChanged: (q) { final lower = q.toLowerCase(); setDlgState(() { filtered = lower.isEmpty ? List.from(filialen) : filialen.where((f) =>
              (f['name']?.toString().toLowerCase() ?? '').contains(lower) || (f['ort']?.toString().toLowerCase() ?? '').contains(lower)).toList(); }); }),
          const SizedBox(height: 12),
          Expanded(child: loading ? const Center(child: CircularProgressIndicator())
            : filtered.isEmpty ? Center(child: Text('Keine Ergebnisse', style: TextStyle(color: Colors.grey.shade500)))
            : ListView.builder(itemCount: filtered.length, itemBuilder: (_, i) {
                final f = filtered[i];
                return ListTile(
                  leading: Icon(Icons.store, color: Colors.pink.shade600),
                  title: Text(f['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text('${f['strasse'] ?? ''}, ${f['plz'] ?? ''} ${f['ort'] ?? ''} • ${f['oeffnungszeiten'] ?? ''}', style: const TextStyle(fontSize: 11)),
                  onTap: () async {
                    await _apiService.telekomAction({'action': 'save_data', 'data': {
                      'firma.filiale': f['name'] ?? '', 'firma.adresse': '${f['strasse'] ?? ''}, ${f['plz'] ?? ''} ${f['ort'] ?? ''}',
                      'firma.telefon': f['telefon'] ?? '', 'firma.email': f['email'] ?? '', 'firma.oeffnungszeiten': f['oeffnungszeiten'] ?? '',
                    }});
                    if (ctx.mounted) Navigator.pop(ctx);
                    _load();
                  },
                );
              })),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen'))],
      );
    }));
    searchC.dispose();
  }

  Widget _field(String label, TextEditingController c, IconData icon) {
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: TextField(controller: c,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 20), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))));
  }

  Widget _infoCard(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
      SizedBox(width: 140, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600))),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
    ]));
  }

  Widget _buildVertraegeTab() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Text('Verträge (${_vertraege.length})', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.pink.shade700)),
        const Spacer(),
        ElevatedButton.icon(icon: const Icon(Icons.add), label: const Text('Neuer Vertrag'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.pink.shade700, foregroundColor: Colors.white),
          onPressed: () => _showVertragDialog(null)),
      ])),
      Expanded(child: _vertraege.isEmpty
        ? Center(child: Text('Keine Verträge', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _vertraege.length, itemBuilder: (_, i) {
            final v = _vertraege[i];
            final status = v['status'] ?? 'aktiv';
            final statusColor = status == 'aktiv' ? Colors.green : status == 'gekuendigt' ? Colors.red : Colors.grey;
            return Card(child: ListTile(
              leading: Icon(Icons.sim_card, color: statusColor),
              title: Text('${v['vertragsart'] ?? ''} — ${v['tarifname'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${v['rufnummer'] ?? ''} • ${v['monatliche_kosten']?.toString().isNotEmpty == true ? '${v['monatliche_kosten']} €/Monat' : ''} • ${status == 'aktiv' ? 'Aktiv' : status == 'gekuendigt' ? 'Gekündigt' : 'Ausgelaufen'}',
                style: TextStyle(fontSize: 11, color: statusColor)),
              trailing: PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: Colors.grey.shade600),
                onSelected: (action) {
                  if (action == 'edit') _showVertragDialog(v);
                  else if (action == 'delete') _deleteVertrag(v);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Bearbeiten')])),
                  PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.red.shade400), const SizedBox(width: 8), Text('Löschen', style: TextStyle(color: Colors.red.shade400))])),
                ],
              ),
              onTap: () => _showVertragDetailModal(v),
            ));
          })),
    ]);
  }

  Future<void> _deleteVertrag(Map<String, dynamic> v) async {
    final confirm = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Vertrag löschen?'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
        TextButton(onPressed: () => Navigator.pop(c, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Löschen'))],
    ));
    if (confirm != true) return;
    await _apiService.telekomAction({'action': 'delete_vertrag', 'id': v['id']});
    _load();
  }

  void _showVertragDialog(Map<String, dynamic>? existing) {
    final isEdit = existing != null;
    final artC = TextEditingController(text: existing?['vertragsart'] ?? '');
    final nrC = TextEditingController(text: existing?['vertragsnummer'] ?? '');
    final tarifC = TextEditingController(text: existing?['tarifname'] ?? '');
    final rufC = TextEditingController(text: existing?['rufnummer'] ?? '');
    final beginnC = TextEditingController(text: existing?['vertragsbeginn'] ?? '');
    final endeC = TextEditingController(text: existing?['vertragsende'] ?? '');
    final kuendC = TextEditingController(text: existing?['kuendigungsfrist'] ?? '');
    final kostenC = TextEditingController(text: existing?['monatliche_kosten'] ?? '');
    final notizC = TextEditingController(text: existing?['notiz'] ?? '');
    String status = existing?['status'] ?? 'aktiv';

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (_, setD) => AlertDialog(
      title: Text(isEdit ? 'Vertrag bearbeiten' : 'Neuer Vertrag'),
      content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: artC, decoration: const InputDecoration(labelText: 'Vertragsart (Mobilfunk, Festnetz, DSL...)', isDense: true, border: OutlineInputBorder())),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: tarifC, decoration: const InputDecoration(labelText: 'Tarifname', isDense: true, border: OutlineInputBorder()))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: rufC, decoration: const InputDecoration(labelText: 'Rufnummer', isDense: true, border: OutlineInputBorder()))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: nrC, decoration: const InputDecoration(labelText: 'Vertragsnummer', isDense: true, border: OutlineInputBorder()))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: kostenC, decoration: const InputDecoration(labelText: 'Monatl. Kosten (€)', isDense: true, border: OutlineInputBorder()), keyboardType: TextInputType.number)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: beginnC, decoration: const InputDecoration(labelText: 'Vertragsbeginn', isDense: true, border: OutlineInputBorder()))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: endeC, decoration: const InputDecoration(labelText: 'Vertragsende', isDense: true, border: OutlineInputBorder()))),
        ]),
        const SizedBox(height: 10),
        TextField(controller: kuendC, decoration: const InputDecoration(labelText: 'Kündigungsfrist', isDense: true, border: OutlineInputBorder())),
        const SizedBox(height: 10),
        Wrap(spacing: 6, children: [('aktiv', 'Aktiv', Colors.green), ('gekuendigt', 'Gekündigt', Colors.red), ('ausgelaufen', 'Ausgelaufen', Colors.grey)].map((s) =>
          ChoiceChip(label: Text(s.$2, style: TextStyle(fontSize: 11, color: status == s.$1 ? Colors.white : null)), selected: status == s.$1, selectedColor: s.$3, onSelected: (_) => setD(() => status = s.$1))).toList()),
        const SizedBox(height: 10),
        TextField(controller: notizC, maxLines: 2, decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder())),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () async {
          final data = {'vertragsart': artC.text.trim(), 'vertragsnummer': nrC.text.trim(), 'tarifname': tarifC.text.trim(),
            'rufnummer': rufC.text.trim(), 'vertragsbeginn': beginnC.text.trim(), 'vertragsende': endeC.text.trim(),
            'kuendigungsfrist': kuendC.text.trim(), 'monatliche_kosten': kostenC.text.trim(), 'status': status, 'notiz': notizC.text.trim()};
          if (isEdit) data['id'] = existing['id'];
          await _apiService.telekomAction({'action': 'save_vertrag', 'vertrag': data});
          if (ctx.mounted) Navigator.pop(ctx);
          _load();
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.pink.shade700, foregroundColor: Colors.white),
          child: Text(isEdit ? 'Speichern' : 'Erstellen')),
      ],
    )));
  }

  void _showVertragDetailModal(Map<String, dynamic> vertrag) {
    final vid = vertrag['id'] is int ? vertrag['id'] : int.parse(vertrag['id'].toString());
    showDialog(context: context, builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(width: 750, height: MediaQuery.of(context).size.height * 0.85,
        child: _TelekomVertragDetail(apiService: _apiService, vertrag: vertrag, vertragId: vid, onChanged: _load)),
    ));
  }
}

class _TelekomVertragDetail extends StatefulWidget {
  final ApiService apiService;
  final Map<String, dynamic> vertrag;
  final int vertragId;
  final VoidCallback onChanged;
  const _TelekomVertragDetail({required this.apiService, required this.vertrag, required this.vertragId, required this.onChanged});
  @override
  State<_TelekomVertragDetail> createState() => _TelekomVertragDetailState();
}

class _TelekomVertragDetailState extends State<_TelekomVertragDetail> with TickerProviderStateMixin {
  late TabController _tabC;
  List<Map<String, dynamic>> _verlauf = [];
  List<Map<String, dynamic>> _korr = [];
  List<Map<String, dynamic>> _rechnungen = [];
  List<Map<String, dynamic>> _vorfaelle = [];
  bool _isLoading = true;

  @override
  void initState() { super.initState(); _tabC = TabController(length: 6, vsync: this); _loadDetail(); }
  @override
  void dispose() { _tabC.dispose(); super.dispose(); }

  Future<void> _loadDetail() async {
    try {
      final res = await widget.apiService.telekomAction({'action': 'vertrag_detail', 'vertrag_id': widget.vertragId});
      if (mounted && res['success'] == true) {
        setState(() {
          _verlauf = List<Map<String, dynamic>>.from(res['verlauf'] ?? []);
          _korr = List<Map<String, dynamic>>.from(res['korrespondenz'] ?? []);
          _rechnungen = List<Map<String, dynamic>>.from(res['rechnungen'] ?? []);
          _vorfaelle = List<Map<String, dynamic>>.from(res['vorfaelle'] ?? []);
          _isLoading = false;
        });
      }
    } catch (_) {}
    if (mounted && _isLoading) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vertrag;
    return Column(children: [
      Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.pink.shade700, borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16))),
        child: Row(children: [
          const Icon(Icons.sim_card, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${v['vertragsart'] ?? ''} — ${v['tarifname'] ?? ''}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            if (v['rufnummer']?.toString().isNotEmpty == true) Text(v['rufnummer'], style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ])),
          IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () { Navigator.pop(context); widget.onChanged(); }),
        ])),
      TabBar(controller: _tabC, labelColor: Colors.pink.shade700, isScrollable: true, tabs: const [
        Tab(text: 'Verlauf'), Tab(text: 'Details'), Tab(text: 'Dokumente'), Tab(text: 'Rechnungen'), Tab(text: 'Korrespondenz'), Tab(text: 'Vorfall'),
      ]),
      Expanded(child: _isLoading ? const Center(child: CircularProgressIndicator()) : TabBarView(controller: _tabC, children: [
        _buildVerlaufTab(), _buildDetailsTab(), _buildDokumenteTab(), _buildRechnungenTab(), _buildKorrTab(), _buildVorfallTab(),
      ])),
    ]);
  }

  Widget _buildVerlaufTab() {
    final eintragC = TextEditingController();
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Expanded(child: TextField(controller: eintragC, decoration: const InputDecoration(hintText: 'Neuer Eintrag...', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)))),
        const SizedBox(width: 8),
        IconButton(icon: Icon(Icons.add_circle, color: Colors.green.shade700, size: 32), onPressed: () async {
          if (eintragC.text.trim().isEmpty) return;
          final today = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';
          await widget.apiService.telekomAction({'action': 'add_verlauf', 'vertrag_id': widget.vertragId, 'datum': today, 'eintrag': eintragC.text.trim()});
          eintragC.clear(); _loadDetail();
        }),
      ])),
      Expanded(child: _verlauf.isEmpty ? Center(child: Text('Keine Einträge', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _verlauf.length, itemBuilder: (_, i) {
            final e = _verlauf[i];
            return ListTile(
              leading: Icon(Icons.circle, size: 10, color: Colors.pink.shade300),
              title: Text(e['eintrag'] ?? '', style: const TextStyle(fontSize: 13)),
              subtitle: Text(e['datum'] ?? e['created_at'] ?? '', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              trailing: IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade300), onPressed: () async {
                await widget.apiService.telekomAction({'action': 'delete_verlauf', 'id': e['id']}); _loadDetail();
              }),
            );
          })),
    ]);
  }

  Widget _buildDetailsTab() {
    final v = widget.vertrag;
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dRow('Vertragsart', v['vertragsart']), _dRow('Tarifname', v['tarifname']), _dRow('Rufnummer', v['rufnummer']),
      _dRow('Vertragsnummer', v['vertragsnummer']), _dRow('Monatl. Kosten', v['monatliche_kosten']?.toString().isNotEmpty == true ? '${v['monatliche_kosten']} €' : ''),
      _dRow('Vertragsbeginn', v['vertragsbeginn']), _dRow('Vertragsende', v['vertragsende']), _dRow('Kündigungsfrist', v['kuendigungsfrist']),
      _dRow('Status', v['status'] == 'aktiv' ? 'Aktiv' : v['status'] == 'gekuendigt' ? 'Gekündigt' : 'Ausgelaufen'),
      if (v['notiz']?.toString().isNotEmpty == true) ...[const SizedBox(height: 8), Text(v['notiz'], style: const TextStyle(fontSize: 12))],
    ]));
  }

  Widget _dRow(String label, dynamic value) {
    final s = value?.toString() ?? ''; if (s.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
      SizedBox(width: 140, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600))),
      Expanded(child: Text(s, style: const TextStyle(fontSize: 13))),
    ]));
  }

  Widget _buildDokumenteTab() {
    return Center(child: KorrAttachmentsWidget(apiService: widget.apiService, modul: 'telekom_vertrag', korrespondenzId: widget.vertragId));
  }

  Widget _buildRechnungenTab() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [const Spacer(),
        ElevatedButton.icon(icon: const Icon(Icons.add, size: 16), label: const Text('Neue Rechnung'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.pink.shade700, foregroundColor: Colors.white),
          onPressed: () async {
            final nrC = TextEditingController(); final betragC = TextEditingController(); final notizC = TextEditingController();
            await showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('Neue Rechnung'),
              content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: nrC, decoration: const InputDecoration(labelText: 'Rechnungsnr.', isDense: true, border: OutlineInputBorder())), const SizedBox(height: 10),
                TextField(controller: betragC, decoration: const InputDecoration(labelText: 'Betrag (€)', isDense: true, border: OutlineInputBorder()), keyboardType: TextInputType.number), const SizedBox(height: 10),
                TextField(controller: notizC, decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder())),
              ])),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
                ElevatedButton(onPressed: () async {
                  final today = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';
                  await widget.apiService.telekomAction({'action': 'save_rechnung', 'vertrag_id': widget.vertragId, 'rechnung': {'rechnungsnummer': nrC.text, 'betrag': betragC.text, 'datum': today, 'status': 'offen', 'notiz': notizC.text}});
                  if (ctx.mounted) Navigator.pop(ctx); _loadDetail();
                }, child: const Text('Speichern'))],
            ));
          }),
      ])),
      Expanded(child: _rechnungen.isEmpty ? Center(child: Text('Keine Rechnungen', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(itemCount: _rechnungen.length, itemBuilder: (_, i) {
            final r = _rechnungen[i]; final sc = r['status'] == 'bezahlt' ? Colors.green : r['status'] == 'ueberfaellig' ? Colors.red : Colors.orange;
            return ListTile(leading: Icon(Icons.receipt, color: sc), title: Text('${r['rechnungsnummer'] ?? 'Rechnung'} — ${r['betrag'] ?? ''} €'),
              subtitle: Text('${r['datum'] ?? ''} • ${r['status'] == 'bezahlt' ? 'Bezahlt' : r['status'] == 'ueberfaellig' ? 'Überfällig' : 'Offen'}', style: TextStyle(fontSize: 11, color: sc)),
              trailing: IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade300), onPressed: () async { await widget.apiService.telekomAction({'action': 'delete_rechnung', 'id': r['id']}); _loadDetail(); }));
          })),
    ]);
  }

  Widget _buildKorrTab() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [const Spacer(),
        ElevatedButton.icon(icon: const Icon(Icons.add, size: 16), label: const Text('Neu'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.pink.shade700, foregroundColor: Colors.white),
          onPressed: () async {
            final betreffC = TextEditingController(); final notizC = TextEditingController();
            await showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('Neue Korrespondenz'),
              content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: betreffC, decoration: const InputDecoration(labelText: 'Betreff', isDense: true, border: OutlineInputBorder())), const SizedBox(height: 10),
                TextField(controller: notizC, maxLines: 3, decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder())),
              ])),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
                ElevatedButton(onPressed: () async {
                  final today = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';
                  await widget.apiService.telekomAction({'action': 'save_korr', 'vertrag_id': widget.vertragId, 'korr': {'betreff': betreffC.text, 'notiz': notizC.text, 'datum': today, 'richtung': 'ausgehend'}});
                  if (ctx.mounted) Navigator.pop(ctx); _loadDetail();
                }, child: const Text('Speichern'))],
            ));
          }),
      ])),
      Expanded(child: _korr.isEmpty ? Center(child: Text('Keine Korrespondenz', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(itemCount: _korr.length, itemBuilder: (_, i) {
            final k = _korr[i]; final isEin = k['richtung'] == 'eingehend';
            return ListTile(leading: Icon(isEin ? Icons.call_received : Icons.call_made, color: isEin ? Colors.blue : Colors.green),
              title: Text(k['betreff'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: Text('${k['datum'] ?? ''} • ${isEin ? 'Eingehend' : 'Ausgehend'}', style: const TextStyle(fontSize: 11)),
              trailing: IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade300), onPressed: () async { await widget.apiService.telekomAction({'action': 'delete_korr', 'id': k['id']}); _loadDetail(); }));
          })),
    ]);
  }

  Widget _buildVorfallTab() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [const Spacer(),
        ElevatedButton.icon(icon: const Icon(Icons.add, size: 16), label: const Text('Neuer Vorfall'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.pink.shade700, foregroundColor: Colors.white),
          onPressed: () async {
            final titelC = TextEditingController(); final notizC = TextEditingController();
            String typ = 'Störung';
            await showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (_, setD) => AlertDialog(title: const Text('Neuer Vorfall'),
              content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(value: typ, decoration: const InputDecoration(labelText: 'Art', isDense: true, border: OutlineInputBorder()),
                  items: ['Störung', 'Reklamation', 'Tarifwechsel', 'Kündigung', 'Vertragsverlängerung', 'Sonstiges'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => setD(() => typ = v!)), const SizedBox(height: 10),
                TextField(controller: titelC, decoration: const InputDecoration(labelText: 'Titel', isDense: true, border: OutlineInputBorder())), const SizedBox(height: 10),
                TextField(controller: notizC, maxLines: 2, decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder())),
              ])),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
                ElevatedButton(onPressed: () async {
                  final today = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';
                  await widget.apiService.telekomAction({'action': 'save_vorfall', 'vertrag_id': widget.vertragId, 'vorfall': {'typ': typ, 'titel': titelC.text, 'datum': today, 'status': 'offen', 'notiz': notizC.text}});
                  if (ctx.mounted) Navigator.pop(ctx); _loadDetail();
                }, child: const Text('Speichern'))],
            )));
          }),
      ])),
      Expanded(child: _vorfaelle.isEmpty ? Center(child: Text('Keine Vorfälle', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(itemCount: _vorfaelle.length, itemBuilder: (_, i) {
            final v = _vorfaelle[i]; final sc = v['status'] == 'erledigt' ? Colors.green : Colors.orange;
            return ListTile(leading: Icon(Icons.report_problem, color: sc),
              title: Text('${v['typ'] ?? ''} — ${v['titel'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: Text('${v['datum'] ?? ''} • ${v['status'] == 'erledigt' ? 'Erledigt' : 'Offen'}', style: TextStyle(fontSize: 11, color: sc)),
              trailing: IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade300), onPressed: () async { await widget.apiService.telekomAction({'action': 'delete_vorfall', 'id': v['id']}); _loadDetail(); }));
          })),
    ]);
  }
}
