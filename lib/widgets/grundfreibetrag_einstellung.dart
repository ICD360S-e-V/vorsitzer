import 'package:flutter/material.dart';
import '../services/api_service.dart';

class GrundfreibetragEinstellungWidget extends StatefulWidget {
  final ApiService apiService;
  const GrundfreibetragEinstellungWidget({super.key, required this.apiService});
  @override
  State<GrundfreibetragEinstellungWidget> createState() => _GrundfreibetragEinstellungWidgetState();
}

class _GrundfreibetragEinstellungWidgetState extends State<GrundfreibetragEinstellungWidget> {
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
      final result = await widget.apiService.getGrundfreibetrag();
      if (result['success'] == true) {
        _aktuell = result['aktuell'] != null ? Map<String, dynamic>.from(result['aktuell'] as Map) : null;
        if (result['alle'] is List) {
          _alle = (result['alle'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
    } catch (e) {
      debugPrint('[Grundfreibetrag] load error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  String _fmtEuro(dynamic val) {
    final d = double.tryParse(val?.toString() ?? '0') ?? 0;
    final str = d.toStringAsFixed(0);
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buffer.write('.');
      buffer.write(str[i]);
    }
    return '$buffer €';
  }

  void _showAddEditDialog([Map<String, dynamic>? existing]) {
    final jahrC = TextEditingController(text: existing?['jahr']?.toString() ?? '${DateTime.now().year + 1}');
    final betragC = TextEditingController(text: existing?['betrag']?.toString() ?? '');
    final verhC = TextEditingController(text: existing?['verheiratet_betrag']?.toString() ?? '');
    final quelleC = TextEditingController(text: existing?['quelle']?.toString() ?? 'EStG');
    final isEdit = existing != null;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.account_balance, size: 18, color: Colors.teal.shade700),
          const SizedBox(width: 8),
          Text(isEdit ? 'Grundfreibetrag bearbeiten' : 'Neuen Grundfreibetrag hinzufügen', style: const TextStyle(fontSize: 15)),
        ]),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: jahrC,
              decoration: InputDecoration(labelText: 'Jahr', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: betragC,
              decoration: InputDecoration(labelText: 'Grundfreibetrag (Einzelveranlagung)', suffixText: '€', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (v) {
                final d = double.tryParse(v) ?? 0;
                if (d > 0 && verhC.text.isEmpty) {
                  verhC.text = (d * 2).toStringAsFixed(0);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: verhC,
              decoration: InputDecoration(labelText: 'Zusammenveranlagung (Ehepartner)', suffixText: '€', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                hintText: 'Automatisch: 2× Einzelbetrag'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: quelleC,
              decoration: InputDecoration(labelText: 'Quelle', hintText: 'z.B. EStG, BGBl.', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Icon(Icons.info_outline, size: 16, color: Colors.amber.shade700),
                const SizedBox(width: 6),
                Expanded(child: Text('Der Grundfreibetrag wird jährlich zum 01.01. angepasst. Neue Werte werden i.d.R. im Herbst des Vorjahres veröffentlicht.',
                    style: TextStyle(fontSize: 10, color: Colors.amber.shade800))),
              ]),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          ElevatedButton.icon(
            onPressed: () async {
              final jahr = int.tryParse(jahrC.text.trim());
              final betrag = double.tryParse(betragC.text.trim());
              if (jahr == null || betrag == null || betrag <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Jahr und Betrag erforderlich'), backgroundColor: Colors.red));
                return;
              }
              final verh = double.tryParse(verhC.text.trim()) ?? betrag * 2;
              Navigator.pop(ctx);
              try {
                final res = await widget.apiService.saveGrundfreibetrag(
                  id: isEdit ? int.tryParse(existing['id']?.toString() ?? '') : null,
                  jahr: jahr, betrag: betrag, verheiratatBetrag: verh,
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
          ),
        ],
      ),
    ).then((_) {
      jahrC.dispose();
      betragC.dispose();
      verhC.dispose();
      quelleC.dispose();
    });
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Grundfreibetrag löschen?', style: TextStyle(fontSize: 16)),
        content: Text('Jahr ${item['jahr']} wirklich löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('Löschen')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final id = int.tryParse(item['id']?.toString() ?? '');
      if (id == null) return;
      final res = await widget.apiService.deleteGrundfreibetrag(id);
      if (res['success'] == true) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Gelöscht'), backgroundColor: Colors.green.shade600));
        await _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final currentYear = DateTime.now().year;
    final needsUpdate = _aktuell == null || int.tryParse(_aktuell!['jahr']?.toString() ?? '0') != currentYear;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Icon(Icons.account_balance, size: 24, color: Colors.teal.shade700),
          const SizedBox(width: 10),
          Text('Grundfreibetrag', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _showAddEditDialog,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Neues Jahr', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
          ),
        ]),
        const SizedBox(height: 4),
        Text('Steuerlicher Grundfreibetrag nach § 32a EStG — wird jährlich zum 01.01. angepasst.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 16),

        // Warning if current year missing
        if (needsUpdate)
          Container(
            width: double.infinity, padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade300)),
            child: Row(children: [
              Icon(Icons.warning_amber, size: 22, color: Colors.red.shade700),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Grundfreibetrag $currentYear fehlt!', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
                const SizedBox(height: 2),
                Text('Bitte den aktuellen Wert für $currentYear eintragen.', style: TextStyle(fontSize: 11, color: Colors.red.shade600)),
              ])),
              ElevatedButton(
                onPressed: _showAddEditDialog,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
                child: const Text('Eintragen', style: TextStyle(fontSize: 11)),
              ),
            ]),
          ),

        // Current year card
        if (_aktuell != null)
          Container(
            width: double.infinity, padding: const EdgeInsets.all(16), margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.teal.shade50, Colors.teal.shade100]),
              borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.teal.shade300)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('Aktuell: ${_aktuell!['jahr']}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.teal.shade700, borderRadius: BorderRadius.circular(20)),
                  child: Text(_fmtEuro(_aktuell!['betrag']), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                ),
              ]),
              const SizedBox(height: 8),
              Text('Einzelveranlagung: ${_fmtEuro(_aktuell!['betrag'])}', style: TextStyle(fontSize: 13, color: Colors.teal.shade700)),
              Text('Zusammenveranlagung: ${_fmtEuro(_aktuell!['verheiratet_betrag'])}', style: TextStyle(fontSize: 13, color: Colors.teal.shade700)),
              const SizedBox(height: 4),
              Text('Änderung: jährlich zum 01.01. (EStG § 32a)', style: TextStyle(fontSize: 11, color: Colors.teal.shade500, fontStyle: FontStyle.italic)),
              if (_aktuell!['quelle']?.toString().isNotEmpty == true)
                Text('Quelle: ${_aktuell!['quelle']}', style: TextStyle(fontSize: 11, color: Colors.teal.shade500, fontStyle: FontStyle.italic)),
            ]),
          ),

        // History table
        Text('Verlauf', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
        const SizedBox(height: 8),
        ..._alle.map((item) {
          final jahr = int.tryParse(item['jahr']?.toString() ?? '0') ?? 0;
          final isCurrent = jahr == currentYear;
          return Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isCurrent ? Colors.teal.shade50 : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isCurrent ? Colors.teal.shade300 : Colors.grey.shade200),
            ),
            child: Row(children: [
              SizedBox(width: 50, child: Text('$jahr', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isCurrent ? Colors.teal.shade800 : Colors.grey.shade700))),
              const SizedBox(width: 12),
              Expanded(child: Text('Einzel: ${_fmtEuro(item['betrag'])}  ·  Zusammen: ${_fmtEuro(item['verheiratet_betrag'])}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
              IconButton(icon: Icon(Icons.edit, size: 16, color: Colors.blueGrey.shade400), onPressed: () => _showAddEditDialog(item),
                  padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 30, minHeight: 30), tooltip: 'Bearbeiten'),
              IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), onPressed: () => _delete(item),
                  padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 30, minHeight: 30), tooltip: 'Löschen'),
            ]),
          );
        }),
      ]),
    );
  }
}
