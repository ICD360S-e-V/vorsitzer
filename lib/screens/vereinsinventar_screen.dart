import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../widgets/eastern.dart';

class VereinsinventarScreen extends StatefulWidget {
  final VoidCallback onBack;

  const VereinsinventarScreen({super.key, required this.onBack});

  @override
  State<VereinsinventarScreen> createState() => _VereinsinventarScreenState();
}

class _VereinsinventarScreenState extends State<VereinsinventarScreen> {
  final _apiService = ApiService();
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;
  String _filterKategorie = 'Alle';

  static const _kategorien = [
    'Elektronik', 'Bürobedarf', 'Batterien', 'Kabel & Adapter',
    'Werkzeug', 'Möbel', 'Küche', 'Reinigung', 'IT-Hardware', 'Sonstiges',
  ];

  static const _aktionLabels = {
    'entnommen': ('Entnommen', Colors.orange, Icons.arrow_upward),
    'zurueck': ('Zurückgegeben', Colors.green, Icons.arrow_downward),
    'hinzugefuegt': ('Hinzugefügt', Colors.blue, Icons.add_circle),
    'entsorgt': ('Entsorgt', Colors.red, Icons.delete),
    'reparatur': ('In Reparatur', Colors.purple, Icons.build),
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final result = await _apiService.getInventar();
    if (mounted && result['success'] == true) {
      setState(() {
        _items = List<Map<String, dynamic>>.from(result['inventar'] ?? []);
        _isLoading = false;
      });
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredItems {
    if (_filterKategorie == 'Alle') return _items;
    return _items.where((i) => i['kategorie'] == _filterKategorie).toList();
  }

  @override
  Widget build(BuildContext context) {
    final kategorien = ['Alle', ..._items.map((i) => i['kategorie']?.toString() ?? '').toSet().toList()..sort()];

    return SeasonalBackground(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack, tooltip: 'Zurück'),
                const SizedBox(width: 8),
                Icon(Icons.inventory_2, size: 32, color: Colors.teal.shade700),
                const SizedBox(width: 12),
                const Text('Vereinsinventar', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.teal.shade200)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: kategorien.contains(_filterKategorie) ? _filterKategorie : 'Alle',
                      items: kategorien.map((k) => DropdownMenuItem(value: k, child: Text(k, style: const TextStyle(fontSize: 13)))).toList(),
                      onChanged: (val) => setState(() => _filterKategorie = val!),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => _showItemDialog(null),
                  icon: const Icon(Icons.add),
                  label: const Text('Neuer Gegenstand'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredItems.isEmpty
                      ? Center(child: Text('Keine Gegenstände', style: TextStyle(color: Colors.grey.shade500, fontSize: 16)))
                      : GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 2.2, crossAxisSpacing: 12, mainAxisSpacing: 12),
                          itemCount: _filteredItems.length,
                          itemBuilder: (_, i) => _buildItemCard(_filteredItems[i]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemCard(Map<String, dynamic> item) {
    final menge = int.tryParse(item['menge']?.toString() ?? '0') ?? 0;
    final verfuegbar = int.tryParse(item['verfuegbar']?.toString() ?? '0') ?? 0;
    final inUse = menge - verfuegbar;
    final isLow = verfuegbar == 0 && menge > 0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isLow ? BorderSide(color: Colors.red.shade300, width: 2) : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDetailDialog(item),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_getCategoryIcon(item['kategorie'] ?? ''), color: Colors.teal.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(item['bezeichnung'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15), overflow: TextOverflow.ellipsis),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Text(item['kategorie'] ?? '', style: TextStyle(fontSize: 11, color: Colors.teal.shade700)),
                  ),
                ],
              ),
              if (item['marke']?.toString().isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(item['marke'], style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ),
              if (item['notizen']?.toString().isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(item['notizen'], style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic), maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              const Spacer(),
              Row(
                children: [
                  _countBadge('$verfuegbar', 'verfügbar', verfuegbar > 0 ? Colors.green : Colors.red),
                  const SizedBox(width: 8),
                  if (inUse > 0) _countBadge('$inUse', 'in Nutzung', Colors.orange),
                  const Spacer(),
                  Text('Gesamt: $menge', style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _countBadge(String count, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(count, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 10, color: color)),
      ]),
    );
  }

  IconData _getCategoryIcon(String kategorie) {
    switch (kategorie) {
      case 'Elektronik': return Icons.electrical_services;
      case 'Bürobedarf': return Icons.edit_note;
      case 'Batterien': return Icons.battery_full;
      case 'Kabel & Adapter': return Icons.cable;
      case 'Werkzeug': return Icons.construction;
      case 'Möbel': return Icons.chair;
      case 'Küche': return Icons.kitchen;
      case 'Reinigung': return Icons.cleaning_services;
      case 'IT-Hardware': return Icons.computer;
      default: return Icons.inventory_2;
    }
  }

  Future<void> _showItemDialog(Map<String, dynamic>? existing) async {
    final isEdit = existing != null;
    final bezeichnungCtrl = TextEditingController(text: existing?['bezeichnung'] ?? '');
    final markeCtrl = TextEditingController(text: existing?['marke'] ?? '');
    final mengeCtrl = TextEditingController(text: existing?['menge']?.toString() ?? '1');
    final standortCtrl = TextEditingController(text: existing?['standort'] ?? '');
    final notizenCtrl = TextEditingController(text: existing?['notizen'] ?? '');
    String kategorie = existing?['kategorie'] ?? 'Sonstiges';
    DateTime? datum = existing?['anschaffungsdatum'] != null ? DateTime.tryParse(existing!['anschaffungsdatum']) : null;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: Row(children: [
            Icon(Icons.inventory_2, color: Colors.teal.shade700),
            const SizedBox(width: 8),
            Text(isEdit ? 'Gegenstand bearbeiten' : 'Neuer Gegenstand'),
          ]),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: bezeichnungCtrl, autofocus: true, decoration: const InputDecoration(labelText: 'Bezeichnung *', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(value: _kategorien.contains(kategorie) ? kategorie : 'Sonstiges',
                  decoration: const InputDecoration(labelText: 'Kategorie', border: OutlineInputBorder()),
                  items: _kategorien.map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
                  onChanged: (val) => setDlgState(() => kategorie = val!)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: TextField(controller: markeCtrl, decoration: const InputDecoration(labelText: 'Marke/Typ', border: OutlineInputBorder()))),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: mengeCtrl, decoration: const InputDecoration(labelText: 'Menge', border: OutlineInputBorder()), keyboardType: TextInputType.number)),
                ]),
                const SizedBox(height: 12),
                TextField(controller: standortCtrl, decoration: const InputDecoration(labelText: 'Standort/Lagerort', border: OutlineInputBorder(), prefixIcon: Icon(Icons.location_on))),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(context: context, initialDate: datum ?? DateTime.now(), firstDate: DateTime(2015), lastDate: DateTime.now().add(const Duration(days: 365)));
                    if (d != null) setDlgState(() => datum = d);
                  },
                  icon: const Icon(Icons.calendar_today),
                  label: Text(datum != null ? 'Anschaffung: ${DateFormat('dd.MM.yyyy').format(datum!)}' : 'Anschaffungsdatum'),
                ),
                const SizedBox(height: 12),
                TextField(controller: notizenCtrl, decoration: const InputDecoration(labelText: 'Notizen', border: OutlineInputBorder()), maxLines: 2),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            ElevatedButton.icon(
              onPressed: () async {
                if (bezeichnungCtrl.text.trim().isEmpty) return;
                final data = {
                  'bezeichnung': bezeichnungCtrl.text.trim(), 'kategorie': kategorie, 'marke': markeCtrl.text.trim(),
                  'menge': int.tryParse(mengeCtrl.text) ?? 1, 'standort': standortCtrl.text.trim(),
                  'notizen': notizenCtrl.text.trim(), 'anschaffungsdatum': datum != null ? DateFormat('yyyy-MM-dd').format(datum!) : null,
                };
                if (isEdit) {
                  data['id'] = existing['id'] is int ? existing['id'] : int.parse(existing['id'].toString());
                  data['verfuegbar'] = existing['verfuegbar'];
                  await _apiService.inventarAction('update', data);
                } else {
                  await _apiService.inventarAction('create', data);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                _loadData();
              },
              icon: const Icon(Icons.check),
              label: Text(isEdit ? 'Speichern' : 'Erstellen'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
    bezeichnungCtrl.dispose(); markeCtrl.dispose(); mengeCtrl.dispose(); standortCtrl.dispose(); notizenCtrl.dispose();
  }

  Future<void> _showDetailDialog(Map<String, dynamic> item) async {
    List<Map<String, dynamic>> verlauf = [];
    bool loadingVerlauf = true;
    final id = item['id'] is int ? item['id'] : int.parse(item['id'].toString());

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          if (loadingVerlauf) {
            _apiService.inventarAction('verlauf', {'id': id}).then((r) {
              if (r['success'] == true) setDlgState(() { verlauf = List<Map<String, dynamic>>.from(r['verlauf'] ?? []); loadingVerlauf = false; });
              else setDlgState(() => loadingVerlauf = false);
            });
          }

          final menge = int.tryParse(item['menge']?.toString() ?? '0') ?? 0;
          final verfuegbar = int.tryParse(item['verfuegbar']?.toString() ?? '0') ?? 0;

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: SizedBox(
              width: 650,
              height: MediaQuery.of(context).size.height * 0.8,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.teal.shade700, borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16))),
                    child: Row(children: [
                      Icon(_getCategoryIcon(item['kategorie'] ?? ''), color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(item['bezeichnung'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        Text('$verfuegbar / $menge verfügbar', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
                      ])),
                      IconButton(icon: const Icon(Icons.edit, color: Colors.white), tooltip: 'Bearbeiten', onPressed: () { Navigator.pop(ctx); _showItemDialog(item); }),
                      IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(ctx)),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Expanded(child: ElevatedButton.icon(
                        onPressed: verfuegbar > 0 ? () async {
                          Navigator.pop(ctx);
                          await _showEntnahmeDialog(item, 'entnehmen');
                        } : null,
                        icon: const Icon(Icons.arrow_upward),
                        label: const Text('Entnehmen'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: ElevatedButton.icon(
                        onPressed: verfuegbar < menge ? () async {
                          Navigator.pop(ctx);
                          await _showEntnahmeDialog(item, 'zurueck');
                        } : null,
                        icon: const Icon(Icons.arrow_downward),
                        label: const Text('Zurückgeben'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                      )),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(Icons.delete, color: Colors.red.shade400),
                        tooltip: 'Löschen',
                        onPressed: () async {
                          final confirm = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
                            title: const Text('Löschen?'), content: Text('${item['bezeichnung']} wirklich löschen?'),
                            actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
                              TextButton(onPressed: () => Navigator.pop(c, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Löschen'))],
                          ));
                          if (confirm != true) return;
                          await _apiService.inventarAction('delete', {'id': id});
                          if (ctx.mounted) Navigator.pop(ctx);
                          _loadData();
                        },
                      ),
                    ]),
                  ),
                  if (item['standort']?.toString().isNotEmpty == true || item['marke']?.toString().isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(children: [
                        if (item['marke']?.toString().isNotEmpty == true) ...[
                          Icon(Icons.label, size: 14, color: Colors.grey.shade500), const SizedBox(width: 4),
                          Text(item['marke'], style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                          const SizedBox(width: 16),
                        ],
                        if (item['standort']?.toString().isNotEmpty == true) ...[
                          Icon(Icons.location_on, size: 14, color: Colors.grey.shade500), const SizedBox(width: 4),
                          Text(item['standort'], style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        ],
                      ]),
                    ),
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(children: [
                      Icon(Icons.timeline, size: 16, color: Colors.teal.shade700),
                      const SizedBox(width: 8),
                      Text('Verlauf', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: loadingVerlauf
                        ? const Center(child: CircularProgressIndicator())
                        : verlauf.isEmpty
                            ? Center(child: Text('Keine Einträge', style: TextStyle(color: Colors.grey.shade500)))
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                itemCount: verlauf.length,
                                itemBuilder: (_, i) {
                                  final v = verlauf[i];
                                  final aktion = v['aktion'] ?? '';
                                  final (label, color, icon) = _aktionLabels[aktion] ?? ('?', Colors.grey, Icons.help);
                                  final dt = DateTime.tryParse(v['created_at'] ?? '');
                                  final zweck = v['zweck'] ?? '';
                                  final mitglied = v['mitglied'] ?? '';

                                  return ListTile(
                                    leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.15), radius: 16,
                                      child: Icon(icon, color: color, size: 18)),
                                    title: Row(children: [
                                      Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
                                      const SizedBox(width: 8),
                                      Text('×${v['menge']}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey.shade700)),
                                      if (mitglied.isNotEmpty) ...[const SizedBox(width: 8), Text('• $mitglied', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))],
                                    ]),
                                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      if (zweck.isNotEmpty) Text(zweck, style: const TextStyle(fontSize: 12)),
                                      if (dt != null) Text(DateFormat('dd.MM.yyyy HH:mm').format(dt), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                    ]),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showEntnahmeDialog(Map<String, dynamic> item, String aktion) async {
    final mengeCtrl = TextEditingController(text: '1');
    final mitgliedCtrl = TextEditingController();
    final zweckCtrl = TextEditingController();
    final id = item['id'] is int ? item['id'] : int.parse(item['id'].toString());
    final isEntnehmen = aktion == 'entnehmen';

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(isEntnehmen ? Icons.arrow_upward : Icons.arrow_downward, color: isEntnehmen ? Colors.orange : Colors.green),
          const SizedBox(width: 8),
          Text(isEntnehmen ? 'Entnehmen' : 'Zurückgeben'),
        ]),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(item['bezeichnung'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            TextField(controller: mengeCtrl, decoration: const InputDecoration(labelText: 'Menge', border: OutlineInputBorder()), keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            TextField(controller: mitgliedCtrl, decoration: const InputDecoration(labelText: 'Für wen / Mitglied', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person))),
            const SizedBox(height: 12),
            TextField(controller: zweckCtrl, decoration: const InputDecoration(labelText: 'Zweck / Verwendung', border: OutlineInputBorder(), prefixIcon: Icon(Icons.info_outline))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () async {
              await _apiService.inventarAction(aktion, {
                'id': id, 'menge': int.tryParse(mengeCtrl.text) ?? 1,
                'mitglied': mitgliedCtrl.text.trim(), 'zweck': zweckCtrl.text.trim(),
              });
              if (ctx.mounted) Navigator.pop(ctx);
              _loadData();
            },
            style: ElevatedButton.styleFrom(backgroundColor: isEntnehmen ? Colors.orange : Colors.green, foregroundColor: Colors.white),
            child: Text(isEntnehmen ? 'Entnehmen' : 'Zurückgeben'),
          ),
        ],
      ),
    );
    mengeCtrl.dispose(); mitgliedCtrl.dispose(); zweckCtrl.dispose();
  }
}
