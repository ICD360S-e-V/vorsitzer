import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import 'korrespondenz_attachments_widget.dart';

class ReziprozitaetContent extends StatefulWidget {
  final ApiService apiService;
  final int userId;

  const ReziprozitaetContent({super.key, required this.apiService, required this.userId});

  @override
  State<ReziprozitaetContent> createState() => _ReziprozitaetContentState();
}

class _ReziprozitaetContentState extends State<ReziprozitaetContent> with TickerProviderStateMixin {
  late TabController _tabCtrl;
  List<Map<String, dynamic>> _gegeben = [];
  List<Map<String, dynamic>> _erhalten = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      widget.apiService.getReziprozitaet(widget.userId, typ: 'gegeben'),
      widget.apiService.getReziprozitaet(widget.userId, typ: 'erhalten'),
    ]);
    if (mounted) {
      setState(() {
        _gegeben = results[0]['success'] == true ? List<Map<String, dynamic>>.from(results[0]['eintraege'] ?? []) : [];
        _erhalten = results[1]['success'] == true ? List<Map<String, dynamic>>.from(results[1]['eintraege'] ?? []) : [];
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildBilanzHeader(),
        TabBar(
          controller: _tabCtrl,
          tabs: [
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.card_giftcard, color: Colors.red.shade700),
                const SizedBox(width: 6),
                Text('+ Gegeben (${_sumPunkte(_gegeben).toStringAsFixed(0)} Pkt.)', style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold)),
              ]),
            ),
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.volunteer_activism, color: Colors.green.shade700),
                const SizedBox(width: 6),
                Text('- Erhalten (${_sumPunkte(_erhalten).toStringAsFixed(0)} Pkt.)', style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold)),
              ]),
            ),
          ],
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _buildList(_gegeben, 'gegeben'),
                    _buildList(_erhalten, 'erhalten'),
                  ],
                ),
        ),
      ],
    );
  }

  double _sumPunkte(List<Map<String, dynamic>> items) {
    double total = 0;
    for (final item in items) {
      final kosten = double.tryParse(item['kosten']?.toString().replaceAll(',', '.') ?? '0') ?? 0;
      total += kosten;
    }
    return total;
  }

  Widget _buildBilanzHeader() {
    final gegebenPunkte = _sumPunkte(_gegeben);
    final erhaltenPunkte = _sumPunkte(_erhalten);
    final diff = gegebenPunkte - erhaltenPunkte;
    Color balanceColor;
    String balanceText;
    if (diff > 2) {
      balanceColor = Colors.red.shade700;
      balanceText = 'Du gibst ${diff.toStringAsFixed(0)} Pkt. mehr';
    } else if (diff < -2) {
      balanceColor = Colors.green.shade700;
      balanceText = 'Du erhältst ${diff.abs().toStringAsFixed(0)} Pkt. mehr';
    } else {
      balanceColor = Colors.blue.shade700;
      balanceText = 'Ausgeglichen';
    }

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: balanceColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: balanceColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.balance, color: balanceColor),
          const SizedBox(width: 12),
          Text('Bilanz: ', style: TextStyle(fontWeight: FontWeight.bold, color: balanceColor)),
          Text(balanceText, style: TextStyle(color: balanceColor)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
            child: Text('${gegebenPunkte.toStringAsFixed(0)} Pkt.', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade700, fontSize: 13)),
          ),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text(':', style: TextStyle(fontWeight: FontWeight.bold))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
            child: Text('${erhaltenPunkte.toStringAsFixed(0)} Pkt.', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade700, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> items, String typ) {
    final isGegeben = typ == 'gegeben';
    final color = isGegeben ? Colors.red.shade700 : Colors.green.shade700;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => _showEntryDialog(null, typ),
                icon: const Icon(Icons.add),
                label: Text(isGegeben ? 'Geschenk hinzufügen' : 'Erhaltenes hinzufügen'),
                style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(child: Text(isGegeben ? 'Noch nichts gegeben' : 'Noch nichts erhalten', style: TextStyle(color: Colors.grey.shade500)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _buildEntryCard(items[i], typ),
                ),
        ),
      ],
    );
  }

  Widget _buildEntryCard(Map<String, dynamic> entry, String typ) {
    final isGegeben = typ == 'gegeben';
    final color = isGegeben ? Colors.red : Colors.green;
    final datum = entry['datum'] ?? '';
    final kosten = entry['kosten'] ?? '';
    final gekauftBei = entry['gekauft_bei'] ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              backgroundColor: color.shade50,
              radius: 16,
              child: Icon(isGegeben ? Icons.card_giftcard : Icons.volunteer_activism, color: color.shade700, size: 16),
            ),
            if (kosten.isNotEmpty)
              Text('${double.tryParse(kosten.replaceAll(',', '.'))?.toStringAsFixed(0) ?? kosten} P', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color.shade700)),
          ],
        ),
        title: Text(entry['bezeichnung'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Row(
          children: [
            Text(datum, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            if (kosten.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(6)),
                child: Text('$kosten €', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.amber.shade800)),
              ),
            ],
            if (gekauftBei.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text('• $gekauftBei', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _showEntryDialog(entry, typ)),
            IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400), onPressed: () => _deleteEntry(entry)),
          ],
        ),
        children: [
          if (entry['beschreibung']?.toString().isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(alignment: Alignment.centerLeft, child: Text(entry['beschreibung'], style: const TextStyle(fontSize: 13))),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: KorrAttachmentsWidget(
              apiService: widget.apiService,
              modul: 'reziprozitaet',
              korrespondenzId: entry['id'] is int ? entry['id'] : int.parse(entry['id'].toString()),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteEntry(Map<String, dynamic> entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Löschen?'),
        content: Text('${entry['bezeichnung']} wirklich löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Löschen')),
        ],
      ),
    );
    if (confirm != true) return;
    final id = entry['id'] is int ? entry['id'] : int.parse(entry['id'].toString());
    await widget.apiService.reziprozitaetAction(widget.userId, 'delete', {'id': id});
    _loadData();
  }

  Future<void> _showEntryDialog(Map<String, dynamic>? existing, String typ) async {
    final isEdit = existing != null;
    final bezeichnungCtrl = TextEditingController(text: existing?['bezeichnung'] ?? '');
    final beschreibungCtrl = TextEditingController(text: existing?['beschreibung'] ?? '');
    final kostenCtrl = TextEditingController(text: existing?['kosten'] ?? '');
    final gekauftBeiCtrl = TextEditingController(text: existing?['gekauft_bei'] ?? '');
    DateTime datum = DateTime.tryParse(existing?['datum'] ?? '') ?? DateTime.now();
    final isGegeben = typ == 'gegeben';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: Row(children: [
            Icon(isGegeben ? Icons.card_giftcard : Icons.volunteer_activism, color: isGegeben ? Colors.red.shade700 : Colors.green.shade700),
            const SizedBox(width: 8),
            Text(isEdit ? 'Bearbeiten' : (isGegeben ? 'Geschenk hinzufügen' : 'Erhaltenes hinzufügen')),
          ]),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: bezeichnungCtrl, autofocus: true, decoration: InputDecoration(
                  labelText: isGegeben ? 'Was hast du gegeben? *' : 'Was hast du erhalten? *', border: const OutlineInputBorder(), prefixIcon: const Icon(Icons.label))),
                const SizedBox(height: 12),
                TextField(controller: beschreibungCtrl, decoration: const InputDecoration(labelText: 'Beschreibung', border: OutlineInputBorder()), maxLines: 3),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: TextField(controller: kostenCtrl, decoration: InputDecoration(labelText: isGegeben ? 'Kosten (€) = Punkte' : 'Wert (€) = Punkte', border: const OutlineInputBorder(), prefixIcon: const Icon(Icons.euro)), keyboardType: TextInputType.number)),
                  if (isGegeben) ...[
                    const SizedBox(width: 12),
                    Expanded(child: TextField(controller: gekauftBeiCtrl, decoration: const InputDecoration(labelText: 'Gekauft bei', border: OutlineInputBorder(), prefixIcon: Icon(Icons.store)))),
                  ],
                ]),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(context: context, initialDate: datum, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)));
                    if (d != null) setDlgState(() => datum = d);
                  },
                  icon: const Icon(Icons.calendar_today),
                  label: Text('Datum: ${DateFormat('dd.MM.yyyy').format(datum)}'),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            ElevatedButton.icon(
              onPressed: () async {
                if (bezeichnungCtrl.text.trim().isEmpty) return;
                final data = {
                  'typ': typ,
                  'bezeichnung': bezeichnungCtrl.text.trim(),
                  'beschreibung': beschreibungCtrl.text.trim(),
                  'kosten': kostenCtrl.text.trim(),
                  'gekauft_bei': gekauftBeiCtrl.text.trim(),
                  'datum': DateFormat('yyyy-MM-dd').format(datum),
                };
                if (isEdit) {
                  data['id'] = existing['id'] is int ? existing['id'] : int.parse(existing['id'].toString());
                  await widget.apiService.reziprozitaetAction(widget.userId, 'update', data);
                } else {
                  await widget.apiService.reziprozitaetAction(widget.userId, 'create', data);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                _loadData();
              },
              icon: const Icon(Icons.check),
              label: Text(isEdit ? 'Speichern' : 'Hinzufügen'),
              style: ElevatedButton.styleFrom(
                backgroundColor: isGegeben ? Colors.red.shade700 : Colors.green.shade700, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
    bezeichnungCtrl.dispose(); beschreibungCtrl.dispose(); kostenCtrl.dispose(); gekauftBeiCtrl.dispose();
  }
}
