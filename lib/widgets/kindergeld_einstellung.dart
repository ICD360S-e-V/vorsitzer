import 'package:flutter/material.dart';
import '../services/api_service.dart';

class KindergeldEinstellungWidget extends StatefulWidget {
  final ApiService apiService;
  const KindergeldEinstellungWidget({super.key, required this.apiService});
  @override
  State<KindergeldEinstellungWidget> createState() => _KindergeldEinstellungWidgetState();
}

class _KindergeldEinstellungWidgetState extends State<KindergeldEinstellungWidget> {
  List<Map<String, dynamic>> _alle = [];
  Map<String, dynamic>? _aktuell;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final result = await widget.apiService.getKindergeldSaetze();
      if (result['success'] == true) {
        if (result['alle'] is List) {
          _alle = (result['alle'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
        if (result['aktuell'] is Map) {
          _aktuell = Map<String, dynamic>.from(result['aktuell'] as Map);
        }
      }
    } catch (e) {
      debugPrint('[Kindergeld] load error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  String _fmtEuro(dynamic val) {
    final d = double.tryParse(val?.toString() ?? '0') ?? 0;
    return '${d.toStringAsFixed(0)} €';
  }

  void _showAddEditDialog([Map<String, dynamic>? existing]) {
    final jahrC = TextEditingController(text: existing?['jahr']?.toString() ?? '${DateTime.now().year}');
    final betragC = TextEditingController(text: existing?['betrag_pro_kind']?.toString() ?? '');
    final zuschlagC = TextEditingController(text: existing?['kinderzuschlag_max']?.toString() ?? '');
    final freibetragC = TextEditingController(text: existing?['kinderfreibetrag']?.toString() ?? '');
    final quelleC = TextEditingController(text: existing?['quelle']?.toString() ?? 'BKGG');
    final isEdit = existing != null;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.child_friendly, size: 18, color: Colors.green.shade700),
          const SizedBox(width: 8),
          Text(isEdit ? 'Kindergeld bearbeiten' : 'Neues Kindergeld Jahr', style: const TextStyle(fontSize: 15)),
        ]),
        content: SizedBox(width: 400, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: jahrC,
            decoration: InputDecoration(labelText: 'Jahr', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: betragC,
            decoration: InputDecoration(labelText: 'Kindergeld pro Kind / Monat', suffixText: '€', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                hintText: 'z.B. 259'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: zuschlagC,
            decoration: InputDecoration(labelText: 'Kinderzuschlag max. / Monat', suffixText: '€', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                hintText: 'z.B. 297'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: freibetragC,
            decoration: InputDecoration(labelText: 'Kinderfreibetrag / Jahr', suffixText: '€', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                hintText: 'z.B. 9756'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: quelleC,
            decoration: InputDecoration(labelText: 'Quelle', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Icon(Icons.info_outline, size: 16, color: Colors.green.shade700),
              const SizedBox(width: 6),
              Expanded(child: Text('Kindergeld ist seit 2023 einheitlich pro Kind (kein gestaffelter Betrag mehr). Änderung jährlich zum 01.01. (BKGG).',
                  style: TextStyle(fontSize: 10, color: Colors.green.shade800))),
            ]),
          ),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          ElevatedButton.icon(
            onPressed: () async {
              final jahr = int.tryParse(jahrC.text.trim());
              final betrag = double.tryParse(betragC.text.trim());
              if (jahr == null || betrag == null) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Jahr und Betrag erforderlich'), backgroundColor: Colors.red));
                return;
              }
              Navigator.pop(ctx);
              try {
                final res = await widget.apiService.saveKindergeldSatz(
                  id: isEdit ? int.tryParse(existing['id']?.toString() ?? '') : null,
                  jahr: jahr, betragProKind: betrag,
                  kinderzuschlagMax: double.tryParse(zuschlagC.text.trim()),
                  kinderfreibetrag: double.tryParse(freibetragC.text.trim()),
                  quelle: quelleC.text.trim());
                if (res['success'] == true) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Gespeichert'), backgroundColor: Colors.green.shade600));
                  await _load();
                }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
              }
            },
            icon: const Icon(Icons.save, size: 16),
            label: Text(isEdit ? 'Speichern' : 'Hinzufügen'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
          ),
        ],
      ),
    ).then((_) {
      jahrC.dispose();
      betragC.dispose();
      zuschlagC.dispose();
      freibetragC.dispose();
      quelleC.dispose();
    });
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Eintrag löschen?', style: TextStyle(fontSize: 16)),
      content: Text('Kindergeld ${item['jahr']} löschen?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('Löschen')),
      ],
    ));
    if (confirmed != true) return;
    final id = int.tryParse(item['id']?.toString() ?? '');
    if (id == null) return;
    try {
      await widget.apiService.deleteKindergeldSatz(id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Gelöscht'), backgroundColor: Colors.green.shade600));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final currentYear = DateTime.now().year;
    final hasCurrentYear = _aktuell != null;
    final betrag = double.tryParse(_aktuell?['betrag_pro_kind']?.toString() ?? '0') ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Icon(Icons.child_friendly, size: 24, color: Colors.green.shade700),
          const SizedBox(width: 10),
          Text('Kindergeld', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _showAddEditDialog,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Neu', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
          ),
        ]),
        const SizedBox(height: 4),
        Text('Einheitlich pro Kind — Änderung jährlich zum 01.01. (BKGG)', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 16),

        // Warning
        if (!hasCurrentYear)
          Container(
            width: double.infinity, padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade300)),
            child: Row(children: [
              Icon(Icons.warning_amber, size: 22, color: Colors.red.shade700),
              const SizedBox(width: 10),
              Expanded(child: Text('Kindergeld $currentYear fehlt!', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red.shade800))),
              ElevatedButton(onPressed: _showAddEditDialog, style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
                child: const Text('Eintragen', style: TextStyle(fontSize: 11))),
            ]),
          ),

        // Current year — calculation table
        if (hasCurrentYear) ...[
          Container(
            width: double.infinity, padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.green.shade50, Colors.green.shade100]),
              borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.shade300)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.child_friendly, size: 22, color: Colors.green.shade700),
                const SizedBox(width: 8),
                Text('Kindergeld $currentYear', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: Colors.green.shade700, borderRadius: BorderRadius.circular(20)),
                  child: Text('${betrag.toStringAsFixed(0)} € / Kind / Monat', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ]),
              const SizedBox(height: 12),
              // Table: 1-10 children
              Table(
                border: TableBorder.all(color: Colors.green.shade200, borderRadius: BorderRadius.circular(8)),
                columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(2), 2: FlexColumnWidth(2)},
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: Colors.green.shade600, borderRadius: const BorderRadius.vertical(top: Radius.circular(8))),
                    children: const [
                      Padding(padding: EdgeInsets.all(8), child: Text('Anzahl Kinder', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center)),
                      Padding(padding: EdgeInsets.all(8), child: Text('Pro Monat', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center)),
                      Padding(padding: EdgeInsets.all(8), child: Text('Pro Jahr', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center)),
                    ],
                  ),
                  ...List.generate(10, (i) {
                    final n = i + 1;
                    final monat = betrag * n;
                    final jahr = monat * 12;
                    return TableRow(
                      decoration: BoxDecoration(color: i.isEven ? Colors.white : Colors.green.shade50),
                      children: [
                        Padding(padding: const EdgeInsets.all(8), child: Text('$n ${n == 1 ? 'Kind' : 'Kinder'}', style: const TextStyle(fontSize: 12), textAlign: TextAlign.center)),
                        Padding(padding: const EdgeInsets.all(8), child: Text('${monat.toStringAsFixed(0)} €', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                        Padding(padding: const EdgeInsets.all(8), child: Text('${jahr.toStringAsFixed(0)} €', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                      ],
                    );
                  }),
                ],
              ),
              const SizedBox(height: 10),
              if (_aktuell!['kinderzuschlag_max'] != null)
                Text('Kinderzuschlag max.: ${_fmtEuro(_aktuell!['kinderzuschlag_max'])} / Monat', style: TextStyle(fontSize: 12, color: Colors.green.shade700)),
              if (_aktuell!['kinderfreibetrag'] != null)
                Text('Kinderfreibetrag: ${_fmtEuro(_aktuell!['kinderfreibetrag'])} / Jahr', style: TextStyle(fontSize: 12, color: Colors.green.shade700)),
              const SizedBox(height: 4),
              Text('Änderung: jährlich zum 01.01. (${_aktuell!['quelle'] ?? 'BKGG'})', style: TextStyle(fontSize: 11, color: Colors.green.shade500, fontStyle: FontStyle.italic)),
            ]),
          ),
          const SizedBox(height: 20),
        ],

        // History
        Text('Verlauf', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
        const SizedBox(height: 8),
        ..._alle.map((item) => Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
          child: Row(children: [
            SizedBox(width: 50, child: Text('${item['jahr']}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700))),
            Expanded(child: Text('${_fmtEuro(item['betrag_pro_kind'])}/Kind/Mo · KiZu: ${_fmtEuro(item['kinderzuschlag_max'])} · Freibetrag: ${_fmtEuro(item['kinderfreibetrag'])}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
            IconButton(icon: Icon(Icons.edit, size: 16, color: Colors.blueGrey.shade400), onPressed: () => _showAddEditDialog(item),
                padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 30, minHeight: 30)),
            IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), onPressed: () => _delete(item),
                padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 30, minHeight: 30)),
          ]),
        )),
      ]),
    );
  }
}
