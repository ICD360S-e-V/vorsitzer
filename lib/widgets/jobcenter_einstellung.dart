import 'package:flutter/material.dart';
import '../services/api_service.dart';

class JobcenterEinstellungWidget extends StatefulWidget {
  final ApiService apiService;
  const JobcenterEinstellungWidget({super.key, required this.apiService});
  @override
  State<JobcenterEinstellungWidget> createState() => _JobcenterEinstellungWidgetState();
}

class _JobcenterEinstellungWidgetState extends State<JobcenterEinstellungWidget> {
  List<Map<String, dynamic>> _alle = [];
  List<Map<String, dynamic>> _aktuell = [];
  bool _isLoading = true;

  static const _stufeIcons = {
    'RS1': Icons.person,
    'RS2': Icons.people,
    'RS3': Icons.house,
    'RS4': Icons.school,
    'RS5': Icons.child_care,
    'RS6': Icons.baby_changing_station,
  };

  static const _stufeColors = {
    'RS1': Colors.blue,
    'RS2': Colors.purple,
    'RS3': Colors.brown,
    'RS4': Colors.teal,
    'RS5': Colors.orange,
    'RS6': Colors.pink,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final result = await widget.apiService.getJobcenterRegelsaetze();
      if (result['success'] == true) {
        if (result['alle'] is List) {
          _alle = (result['alle'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
        if (result['aktuell'] is List) {
          _aktuell = (result['aktuell'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
    } catch (e) {
      debugPrint('[Jobcenter] load error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  String _fmtEuro(dynamic val) {
    final d = double.tryParse(val?.toString() ?? '0') ?? 0;
    return '${d.toStringAsFixed(0)} €';
  }

  /// Get unique years sorted desc
  List<int> _getYears() {
    final years = _alle.map((e) => int.tryParse(e['jahr']?.toString() ?? '0') ?? 0).toSet().toList();
    years.sort((a, b) => b.compareTo(a));
    return years;
  }

  List<Map<String, dynamic>> _getForYear(int year) {
    return _alle.where((e) => int.tryParse(e['jahr']?.toString() ?? '0') == year).toList();
  }

  void _showAddEditDialog([Map<String, dynamic>? existing]) {
    final jahrC = TextEditingController(text: existing?['jahr']?.toString() ?? '${DateTime.now().year}');
    final stufeC = TextEditingController(text: existing?['regelbedarfsstufe']?.toString() ?? '');
    final beschreibungC = TextEditingController(text: existing?['beschreibung']?.toString() ?? '');
    final betragC = TextEditingController(text: existing?['betrag']?.toString() ?? '');
    final quelleC = TextEditingController(text: existing?['quelle']?.toString() ?? 'SGB II §20');
    final isEdit = existing != null;

    String selectedStufe = existing?['regelbedarfsstufe']?.toString() ?? 'RS1';
    final stufen = {
      'RS1': 'Alleinstehende / Alleinerziehende',
      'RS2': 'Paare / Bedarfsgemeinschaft (je Partner)',
      'RS3': 'Erwachsene in Einrichtungen',
      'RS4': 'Jugendliche 14-17 Jahre',
      'RS5': 'Kinder 6-13 Jahre',
      'RS6': 'Kinder 0-5 Jahre',
    };

    if (!isEdit) {
      beschreibungC.text = stufen[selectedStufe] ?? '';
      stufeC.text = selectedStufe;
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) => AlertDialog(
        title: Row(children: [
          Icon(Icons.account_balance_wallet, size: 18, color: Colors.orange.shade700),
          const SizedBox(width: 8),
          Text(isEdit ? 'Regelsatz bearbeiten' : 'Neuen Regelsatz hinzufügen', style: const TextStyle(fontSize: 15)),
        ]),
        content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            SizedBox(width: 100, child: TextField(
              controller: jahrC,
              decoration: InputDecoration(labelText: 'Jahr', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              keyboardType: TextInputType.number,
            )),
            const SizedBox(width: 10),
            Expanded(child: DropdownButtonFormField<String>(
              initialValue: selectedStufe,
              decoration: InputDecoration(labelText: 'Regelbedarfsstufe', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              items: stufen.entries.map((e) => DropdownMenuItem(value: e.key, child: Text('${e.key}: ${e.value}', style: const TextStyle(fontSize: 11)))).toList(),
              onChanged: (v) {
                if (v != null) {
                  setDlg(() {
                    selectedStufe = v;
                    stufeC.text = v;
                    beschreibungC.text = stufen[v] ?? '';
                  });
                }
              },
            )),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: beschreibungC,
            decoration: InputDecoration(labelText: 'Beschreibung', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: betragC,
            decoration: InputDecoration(labelText: 'Regelsatz pro Monat', suffixText: '€', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
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
            decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Icon(Icons.info_outline, size: 16, color: Colors.amber.shade700),
              const SizedBox(width: 6),
              Expanded(child: Text('Bürgergeld / Grundsicherung Regelsätze werden jährlich zum 01.01. angepasst (SGB II §20). Ab 01.07.2026 Umbenennung in "Grundsicherung".',
                  style: TextStyle(fontSize: 10, color: Colors.amber.shade800))),
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
                final res = await widget.apiService.saveJobcenterRegelsatz(
                  id: isEdit ? int.tryParse(existing['id']?.toString() ?? '') : null,
                  jahr: jahr, regelbedarfsstufe: stufeC.text.trim(),
                  beschreibung: beschreibungC.text.trim(), betrag: betrag, quelle: quelleC.text.trim());
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white),
          ),
        ],
      )),
    ).then((_) {
      jahrC.dispose();
      stufeC.dispose();
      beschreibungC.dispose();
      betragC.dispose();
      quelleC.dispose();
    });
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Regelsatz löschen?', style: TextStyle(fontSize: 16)),
      content: Text('${item['beschreibung']} (${item['jahr']}) löschen?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('Löschen')),
      ],
    ));
    if (confirmed != true) return;
    final id = int.tryParse(item['id']?.toString() ?? '');
    if (id == null) return;
    try {
      await widget.apiService.deleteJobcenterRegelsatz(id);
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
    final years = _getYears();
    final hasCurrentYear = years.contains(currentYear);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Icon(Icons.account_balance_wallet, size: 24, color: Colors.orange.shade700),
          const SizedBox(width: 10),
          Text('Jobcenter – Bürgergeld / Grundsicherung', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _showAddEditDialog,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Neu', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white),
          ),
        ]),
        const SizedBox(height: 4),
        Text('Regelsätze nach SGB II §20 — Änderung jährlich zum 01.01.', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 16),

        // Warning
        if (!hasCurrentYear)
          Container(
            width: double.infinity, padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade300)),
            child: Row(children: [
              Icon(Icons.warning_amber, size: 22, color: Colors.red.shade700),
              const SizedBox(width: 10),
              Expanded(child: Text('Regelsätze $currentYear fehlen!', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red.shade800))),
              ElevatedButton(onPressed: _showAddEditDialog, style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
                child: const Text('Eintragen', style: TextStyle(fontSize: 11))),
            ]),
          ),

        // Current year cards
        if (_aktuell.isNotEmpty) ...[
          Text('Aktuell: $currentYear', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10, runSpacing: 10,
            children: _aktuell.map((item) {
              final stufe = item['regelbedarfsstufe']?.toString() ?? '';
              final color = _stufeColors[stufe] ?? Colors.grey;
              final icon = _stufeIcons[stufe] ?? Icons.person;
              return Container(
                width: 220, padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [color.shade50, color.shade100]),
                  borderRadius: BorderRadius.circular(10), border: Border.all(color: color.shade300)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(icon, size: 20, color: color.shade700),
                    const SizedBox(width: 6),
                    Expanded(child: Text(stufe, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color.shade700))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: color.shade700, borderRadius: BorderRadius.circular(12)),
                      child: Text(_fmtEuro(item['betrag']), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Text(item['beschreibung']?.toString() ?? '', style: TextStyle(fontSize: 12, color: color.shade800)),
                  Text('${_fmtEuro(item['betrag'])} / Monat · ${_fmtEuro((double.tryParse(item['betrag']?.toString() ?? '0') ?? 0) * 12)} / Jahr',
                      style: TextStyle(fontSize: 10, color: color.shade600)),
                ]),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
        ],

        // History by year
        ...years.map((year) {
          final items = _getForYear(year);
          final isCurrent = year == currentYear;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!isCurrent) ...[
              Text('$year', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
              const SizedBox(height: 6),
            ],
            if (!isCurrent)
              ...items.map((item) => Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
                child: Row(children: [
                  SizedBox(width: 40, child: Text(item['regelbedarfsstufe']?.toString() ?? '', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade600))),
                  Expanded(child: Text('${item['beschreibung']} — ${_fmtEuro(item['betrag'])}/Mo', style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
                  IconButton(icon: Icon(Icons.edit, size: 16, color: Colors.blueGrey.shade400), onPressed: () => _showAddEditDialog(item),
                      padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 30, minHeight: 30)),
                  IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), onPressed: () => _delete(item),
                      padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 30, minHeight: 30)),
                ]),
              )),
            if (!isCurrent) const SizedBox(height: 12),
          ]);
        }),
      ]),
    );
  }
}
