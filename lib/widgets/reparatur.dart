import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

class ReparaturContent extends StatefulWidget {
  final ApiService apiService;
  final int userId;

  const ReparaturContent({super.key, required this.apiService, required this.userId});

  @override
  State<ReparaturContent> createState() => _ReparaturContentState();
}

class _ReparaturContentState extends State<ReparaturContent> {
  List<Map<String, dynamic>> _vorfaelle = [];
  bool _isLoading = true;

  static const _geraetTypen = [
    'Uhr', 'Laptop', 'Telefon', 'Tablet', 'PC', 'Drucker',
    'Fernseher', 'Kopfhörer', 'Kamera', 'Spielkonsole', 'Sonstiges',
  ];

  static const _statusMap = {
    'eingegangen': ('Eingegangen', Colors.blue),
    'in_bearbeitung': ('In Bearbeitung', Colors.orange),
    'warte_auf_teil': ('Warte auf Ersatzteil', Colors.amber),
    'repariert': ('Repariert', Colors.green),
    'nicht_reparierbar': ('Nicht reparierbar', Colors.red),
    'abgeholt': ('Abgeholt', Colors.grey),
  };

  static const _uebergabeMap = {
    'persoenlich': 'Persönlich abgegeben',
    'abgeholt': 'Wurde abgeholt',
    'versendet': 'Per Post versendet',
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final result = await widget.apiService.getReparaturVorfaelle(widget.userId);
    if (mounted && result['success'] == true) {
      setState(() {
        _vorfaelle = List<Map<String, dynamic>>.from(result['vorfaelle'] ?? []);
        _isLoading = false;
      });
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 1,
      child: Column(
        children: [
          const TabBar(
            labelColor: Colors.deepOrange,
            tabs: [Tab(icon: Icon(Icons.build_circle), text: 'Vorfall')],
          ),
          Expanded(
            child: TabBarView(
              children: [_buildVorfallTab()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVorfallTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.build, color: Colors.deepOrange.shade700),
              const SizedBox(width: 8),
              Text('Reparaturen', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepOrange.shade700)),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => _showVorfallDialog(null),
                icon: const Icon(Icons.add),
                label: const Text('Neue Reparatur'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange.shade700, foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _vorfaelle.isEmpty
                  ? Center(child: Text('Keine Reparaturen', style: TextStyle(color: Colors.grey.shade500)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _vorfaelle.length,
                      itemBuilder: (_, i) => _buildVorfallCard(_vorfaelle[i]),
                    ),
        ),
      ],
    );
  }

  Widget _buildVorfallCard(Map<String, dynamic> v) {
    final status = v['status'] ?? 'eingegangen';
    final (statusLabel, statusColor) = _statusMap[status] ?? ('Unbekannt', Colors.grey);
    final geraet = v['geraet'] ?? '';
    final marke = v['marke'] ?? '';
    final modell = v['modell'] ?? '';
    final eingangsdatum = v['eingangsdatum'] ?? '';
    final kostenlos = v['kostenlos'].toString() == '1';
    final uebergabe = _uebergabeMap[v['uebergabe']] ?? v['uebergabe'] ?? '';

    IconData geraetIcon;
    switch (geraet.toLowerCase()) {
      case 'uhr': geraetIcon = Icons.watch; break;
      case 'laptop': geraetIcon = Icons.laptop; break;
      case 'telefon': geraetIcon = Icons.phone_android; break;
      case 'tablet': geraetIcon = Icons.tablet; break;
      case 'pc': geraetIcon = Icons.computer; break;
      case 'drucker': geraetIcon = Icons.print; break;
      case 'fernseher': geraetIcon = Icons.tv; break;
      case 'kopfhörer': geraetIcon = Icons.headphones; break;
      case 'kamera': geraetIcon = Icons.camera_alt; break;
      case 'spielkonsole': geraetIcon = Icons.videogame_asset; break;
      default: geraetIcon = Icons.build;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.15),
          child: Icon(geraetIcon, color: statusColor),
        ),
        title: Row(
          children: [
            Text('$geraet${marke.isNotEmpty ? ' — $marke' : ''}${modell.isNotEmpty ? ' $modell' : ''}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Text(statusLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor)),
            ),
            if (kostenlos) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                child: Text('Kostenlos', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.green.shade700)),
              ),
            ],
          ],
        ),
        subtitle: Text('$eingangsdatum • $uebergabe', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _showVorfallDialog(v)),
            IconButton(icon: Icon(Icons.delete, size: 20, color: Colors.red.shade400), onPressed: () => _deleteVorfall(v)),
          ],
        ),
        onTap: () => _showVorfallDialog(v),
      ),
    );
  }

  Future<void> _deleteVorfall(Map<String, dynamic> v) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reparatur löschen?'),
        content: Text('${v['geraet']} wirklich löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Löschen')),
        ],
      ),
    );
    if (confirm != true) return;
    final id = v['id'] is int ? v['id'] : int.parse(v['id'].toString());
    await widget.apiService.reparaturAction(widget.userId, 'delete', {'vorfall_id': id});
    _loadData();
  }

  Future<void> _showVorfallDialog(Map<String, dynamic>? existing) async {
    final isEdit = existing != null;
    final geraetCtrl = TextEditingController(text: existing?['geraet'] ?? '');
    final markeCtrl = TextEditingController(text: existing?['marke'] ?? '');
    final modellCtrl = TextEditingController(text: existing?['modell'] ?? '');
    final snCtrl = TextEditingController(text: existing?['seriennummer'] ?? '');
    final beschreibungCtrl = TextEditingController(text: existing?['beschreibung'] ?? '');
    final kostenCtrl = TextEditingController(text: existing?['kosten'] ?? '');
    final notizenCtrl = TextEditingController(text: existing?['notizen'] ?? '');

    String geraet = existing?['geraet'] ?? 'Telefon';
    String uebergabe = existing?['uebergabe'] ?? 'persoenlich';
    bool kostenlos = (existing?['kostenlos']?.toString() ?? '1') == '1';
    String status = existing?['status'] ?? 'eingegangen';
    DateTime eingangsdatum = DateTime.tryParse(existing?['eingangsdatum'] ?? '') ?? DateTime.now();
    DateTime? fertigdatum = existing?['fertigdatum'] != null ? DateTime.tryParse(existing!['fertigdatum']) : null;
    DateTime? abgeholtDatum = existing?['abgeholt_datum'] != null ? DateTime.tryParse(existing!['abgeholt_datum']) : null;

    if (!_geraetTypen.contains(geraet)) geraet = 'Sonstiges';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.build_circle, color: Colors.deepOrange.shade700),
              const SizedBox(width: 8),
              Text(isEdit ? 'Reparatur bearbeiten' : 'Neue Reparatur'),
            ],
          ),
          content: SizedBox(
            width: 550,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: geraet,
                    decoration: const InputDecoration(labelText: 'Gerät *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.devices)),
                    items: _geraetTypen.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                    onChanged: (val) => setDlgState(() => geraet = val!),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: markeCtrl, decoration: const InputDecoration(labelText: 'Marke', border: OutlineInputBorder()))),
                      const SizedBox(width: 12),
                      Expanded(child: TextField(controller: modellCtrl, decoration: const InputDecoration(labelText: 'Modell', border: OutlineInputBorder()))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: snCtrl, decoration: const InputDecoration(labelText: 'Seriennummer', border: OutlineInputBorder(), prefixIcon: Icon(Icons.qr_code))),
                  const SizedBox(height: 12),
                  TextField(controller: beschreibungCtrl, decoration: const InputDecoration(labelText: 'Fehlerbeschreibung', border: OutlineInputBorder(), prefixIcon: Icon(Icons.description)), maxLines: 3),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final d = await showDatePicker(context: context, initialDate: eingangsdatum, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)));
                            if (d != null) setDlgState(() => eingangsdatum = d);
                          },
                          icon: const Icon(Icons.calendar_today),
                          label: Text('Eingang: ${DateFormat('dd.MM.yyyy').format(eingangsdatum)}'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: uebergabe,
                          decoration: const InputDecoration(labelText: 'Übergabe', border: OutlineInputBorder()),
                          items: _uebergabeMap.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                          onChanged: (val) => setDlgState(() => uebergabe = val!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: status,
                          decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
                          items: _statusMap.entries.map((e) => DropdownMenuItem(
                            value: e.key,
                            child: Row(children: [
                              Container(width: 10, height: 10, decoration: BoxDecoration(color: e.value.$2, shape: BoxShape.circle)),
                              const SizedBox(width: 8),
                              Text(e.value.$1),
                            ]),
                          )).toList(),
                          onChanged: (val) => setDlgState(() => status = val!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SwitchListTile(
                          value: kostenlos,
                          onChanged: (val) => setDlgState(() => kostenlos = val),
                          title: const Text('Kostenlos'),
                          activeColor: Colors.green,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                  if (!kostenlos) ...[
                    const SizedBox(height: 12),
                    TextField(controller: kostenCtrl, decoration: const InputDecoration(labelText: 'Kosten (€)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.euro))),
                  ],
                  if (isEdit) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final d = await showDatePicker(context: context, initialDate: fertigdatum ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)));
                              if (d != null) setDlgState(() => fertigdatum = d);
                            },
                            icon: const Icon(Icons.check_circle_outline),
                            label: Text(fertigdatum != null ? 'Fertig: ${DateFormat('dd.MM.yyyy').format(fertigdatum!)}' : 'Fertigdatum'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final d = await showDatePicker(context: context, initialDate: abgeholtDatum ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)));
                              if (d != null) setDlgState(() => abgeholtDatum = d);
                            },
                            icon: const Icon(Icons.inventory),
                            label: Text(abgeholtDatum != null ? 'Abgeholt: ${DateFormat('dd.MM.yyyy').format(abgeholtDatum!)}' : 'Abholdatum'),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(controller: notizenCtrl, decoration: const InputDecoration(labelText: 'Notizen', border: OutlineInputBorder(), prefixIcon: Icon(Icons.note)), maxLines: 2),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            ElevatedButton.icon(
              onPressed: () async {
                final data = {
                  'geraet': geraet == 'Sonstiges' && geraetCtrl.text.isNotEmpty ? geraetCtrl.text : geraet,
                  'marke': markeCtrl.text.trim(),
                  'modell': modellCtrl.text.trim(),
                  'seriennummer': snCtrl.text.trim(),
                  'beschreibung': beschreibungCtrl.text.trim(),
                  'uebergabe': uebergabe,
                  'kostenlos': kostenlos ? 1 : 0,
                  'kosten': kostenCtrl.text.trim(),
                  'status': status,
                  'eingangsdatum': DateFormat('yyyy-MM-dd').format(eingangsdatum),
                  'fertigdatum': fertigdatum != null ? DateFormat('yyyy-MM-dd').format(fertigdatum!) : null,
                  'abgeholt_datum': abgeholtDatum != null ? DateFormat('yyyy-MM-dd').format(abgeholtDatum!) : null,
                  'notizen': notizenCtrl.text.trim(),
                };
                if (isEdit) {
                  final id = existing['id'] is int ? existing['id'] : int.parse(existing['id'].toString());
                  data['vorfall_id'] = id;
                }
                await widget.apiService.reparaturAction(widget.userId, isEdit ? 'update' : 'create', data);
                if (ctx.mounted) Navigator.pop(ctx);
                _loadData();
              },
              icon: const Icon(Icons.check),
              label: Text(isEdit ? 'Speichern' : 'Erstellen'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange.shade700, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );

    geraetCtrl.dispose();
    markeCtrl.dispose();
    modellCtrl.dispose();
    snCtrl.dispose();
    beschreibungCtrl.dispose();
    kostenCtrl.dispose();
    notizenCtrl.dispose();
  }
}
