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
    _tabC = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() { _tabC.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _apiService.telekomAction({'action': 'get_data'}),
      _apiService.telekomAction({'action': 'list_vertraege'}),
    ]);
    if (mounted) {
      setState(() {
        if (results[0]['success'] == true) _firmaData = Map<String, dynamic>.from(results[0]['data'] ?? {});
        if (results[1]['success'] == true) _vertraege = List<Map<String, dynamic>>.from(results[1]['vertraege'] ?? []);
        _isLoading = false;
      });
    }
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
          Tab(icon: Icon(Icons.receipt_long), text: 'Verträge'),
        ]),
        Expanded(child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(controller: _tabC, children: [
              _buildFirmaTab(),
              _buildVertraegeTab(),
            ])),
      ]),
    ));
  }

  Widget _buildFirmaTab() {
    final d = _firmaData;
    if (!_firmaEditing) {
      return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Spacer(), OutlinedButton.icon(icon: const Icon(Icons.edit, size: 16), label: const Text('Bearbeiten'), onPressed: () => setState(() => _firmaEditing = true))]),
        const SizedBox(height: 8),
        _infoCard('Filiale', d['firma.filiale'] ?? ''),
        _infoCard('Adresse', d['firma.adresse'] ?? ''),
        _infoCard('Telefon', d['firma.telefon'] ?? ''),
        _infoCard('E-Mail', d['firma.email'] ?? ''),
        _infoCard('Kundennummer', d['firma.kundennummer'] ?? ''),
        _infoCard('Ansprechpartner', d['firma.ansprechpartner'] ?? ''),
        _infoCard('Öffnungszeiten', d['firma.oeffnungszeiten'] ?? ''),
      ]));
    }

    final filialeC = TextEditingController(text: d['firma.filiale'] ?? '');
    final adresseC = TextEditingController(text: d['firma.adresse'] ?? '');
    final telefonC = TextEditingController(text: d['firma.telefon'] ?? '');
    final emailC = TextEditingController(text: d['firma.email'] ?? '');
    final kdnrC = TextEditingController(text: d['firma.kundennummer'] ?? '');
    final ansprechC = TextEditingController(text: d['firma.ansprechpartner'] ?? '');
    final oeffnungC = TextEditingController(text: d['firma.oeffnungszeiten'] ?? '');

    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(children: [
      _field('Filiale / Standort', filialeC, Icons.business),
      _field('Adresse', adresseC, Icons.location_on),
      _field('Telefon', telefonC, Icons.phone),
      _field('E-Mail', emailC, Icons.email),
      _field('Kundennummer', kdnrC, Icons.numbers),
      _field('Ansprechpartner', ansprechC, Icons.person),
      _field('Öffnungszeiten', oeffnungC, Icons.access_time),
      const SizedBox(height: 16),
      Row(children: [
        TextButton(onPressed: () => setState(() => _firmaEditing = false), child: const Text('Abbrechen')),
        const Spacer(),
        ElevatedButton.icon(icon: const Icon(Icons.check), label: const Text('Speichern'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.pink.shade700, foregroundColor: Colors.white),
          onPressed: () async {
            await _apiService.telekomAction({'action': 'save_data', 'data': {
              'firma.filiale': filialeC.text.trim(), 'firma.adresse': adresseC.text.trim(),
              'firma.telefon': telefonC.text.trim(), 'firma.email': emailC.text.trim(),
              'firma.kundennummer': kdnrC.text.trim(), 'firma.ansprechpartner': ansprechC.text.trim(),
              'firma.oeffnungszeiten': oeffnungC.text.trim(),
            }});
            _firmaEditing = false;
            _load();
          }),
      ]),
    ]));
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
              onTap: () => _showVertragDialog(v),
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
}
