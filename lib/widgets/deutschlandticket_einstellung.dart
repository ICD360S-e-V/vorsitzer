import 'package:flutter/material.dart';
import '../services/api_service.dart';

class DeutschlandticketEinstellungWidget extends StatefulWidget {
  final ApiService apiService;
  const DeutschlandticketEinstellungWidget({super.key, required this.apiService});
  @override
  State<DeutschlandticketEinstellungWidget> createState() => _DeutschlandticketEinstellungWidgetState();
}

class _DeutschlandticketEinstellungWidgetState extends State<DeutschlandticketEinstellungWidget> {
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
      final result = await widget.apiService.getDeutschlandticketSaetze();
      if (result['success'] == true) {
        if (result['alle'] is List) {
          _alle = (result['alle'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
        if (result['aktuell'] is Map) {
          _aktuell = Map<String, dynamic>.from(result['aktuell'] as Map);
        }
      }
    } catch (e) {
      debugPrint('[Dticket] load error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  String _fmtEuro(dynamic val) {
    final d = double.tryParse(val?.toString() ?? '0') ?? 0;
    return d == d.roundToDouble() ? '${d.toStringAsFixed(0)} €' : '${d.toStringAsFixed(2)} €';
  }

  void _showAddEditDialog([Map<String, dynamic>? existing]) {
    final jahrC = TextEditingController(text: existing?['jahr']?.toString() ?? '${DateTime.now().year}');
    final preisC = TextEditingController(text: existing?['preis_monat']?.toString() ?? '');
    final fristC = TextEditingController(text: existing?['kuendigung_frist']?.toString() ?? 'Bis zum 10. des laufenden Monats');
    final einzugC = TextEditingController(text: existing?['sepa_einzug']?.toString() ?? '20.-26. des Vormonats');
    final glaeubigerC = TextEditingController(text: existing?['sepa_glaeubiger_id']?.toString() ?? 'DE90LPY00000046849');
    final anbieterC = TextEditingController(text: existing?['sepa_anbieter']?.toString() ?? 'LOGPAY Financial Services GmbH');
    final quelleC = TextEditingController(text: existing?['quelle']?.toString() ?? 'Deutschlandticket.de');
    final isEdit = existing != null;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.train, size: 18, color: Colors.red.shade700),
          const SizedBox(width: 8),
          Text(isEdit ? 'Preis bearbeiten' : 'Neues Jahr hinzufügen', style: const TextStyle(fontSize: 15)),
        ]),
        content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            SizedBox(width: 100, child: TextField(
              controller: jahrC,
              decoration: InputDecoration(labelText: 'Jahr', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              keyboardType: TextInputType.number,
            )),
            const SizedBox(width: 10),
            Expanded(child: TextField(
              controller: preisC,
              decoration: InputDecoration(labelText: 'Preis / Monat', suffixText: '€', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            )),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: fristC,
            decoration: InputDecoration(labelText: 'Kündigungsfrist', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: einzugC,
            decoration: InputDecoration(labelText: 'SEPA Einzug', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: glaeubigerC,
            decoration: InputDecoration(labelText: 'Gläubiger-ID', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: anbieterC,
            decoration: InputDecoration(labelText: 'SEPA Anbieter', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: quelleC,
            decoration: InputDecoration(labelText: 'Quelle', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          ),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          ElevatedButton.icon(
            onPressed: () async {
              final jahr = int.tryParse(jahrC.text.trim());
              final preis = double.tryParse(preisC.text.trim());
              if (jahr == null || preis == null) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Jahr und Preis erforderlich'), backgroundColor: Colors.red));
                return;
              }
              Navigator.pop(ctx);
              try {
                final res = await widget.apiService.saveDeutschlandticketSatz(
                  id: isEdit ? int.tryParse(existing['id']?.toString() ?? '') : null,
                  jahr: jahr, preisMonat: preis,
                  kuendigungFrist: fristC.text.trim(),
                  sepaEinzug: einzugC.text.trim(),
                  sepaGlaeubigerId: glaeubigerC.text.trim(),
                  sepaAnbieter: anbieterC.text.trim(),
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
          ),
        ],
      ),
    ).then((_) {
      jahrC.dispose();
      preisC.dispose();
      fristC.dispose();
      einzugC.dispose();
      glaeubigerC.dispose();
      anbieterC.dispose();
      quelleC.dispose();
    });
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Eintrag löschen?', style: TextStyle(fontSize: 16)),
      content: Text('Deutschlandticket ${item['jahr']} löschen?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('Löschen')),
      ],
    ));
    if (confirmed != true) return;
    final id = int.tryParse(item['id']?.toString() ?? '');
    if (id == null) return;
    try {
      await widget.apiService.deleteDeutschlandticketSatz(id);
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
    final preis = double.tryParse(_aktuell?['preis_monat']?.toString() ?? '0') ?? 0;
    final currentDay = DateTime.now().day;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Icon(Icons.train, size: 24, color: Colors.red.shade700),
          const SizedBox(width: 10),
          Text('Deutschlandticket', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _showAddEditDialog,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Neu', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
          ),
        ]),
        const SizedBox(height: 4),
        Text('49-Euro-Ticket → Preisänderung jährlich zum 01.01.', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 16),

        // Warning
        if (!hasCurrentYear)
          Container(
            width: double.infinity, padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade300)),
            child: Row(children: [
              Icon(Icons.warning_amber, size: 22, color: Colors.red.shade700),
              const SizedBox(width: 10),
              Expanded(child: Text('Deutschlandticket-Preis $currentYear fehlt!', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red.shade800))),
              ElevatedButton(onPressed: _showAddEditDialog, style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600, foregroundColor: Colors.white),
                child: const Text('Eintragen', style: TextStyle(fontSize: 11))),
            ]),
          ),

        // Current year card
        if (hasCurrentYear) ...[
          Container(
            width: double.infinity, padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.red.shade50, Colors.red.shade100]),
              borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.shade300)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.train, size: 28, color: Colors.red.shade700),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Deutschlandticket $currentYear', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
                  Text('Monatliches ÖPNV-Abo für ganz Deutschland', style: TextStyle(fontSize: 11, color: Colors.red.shade600)),
                ]),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: Colors.red.shade700, borderRadius: BorderRadius.circular(20)),
                  child: Text('${preis.toStringAsFixed(0)} € / Monat', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                ),
              ]),
              const SizedBox(height: 16),

              // Cost breakdown
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                child: Column(children: [
                  _infoLine(Icons.calendar_month, 'Pro Monat', _fmtEuro(preis)),
                  _infoLine(Icons.date_range, 'Pro Jahr (12 Monate)', _fmtEuro(preis * 12)),
                  const Divider(height: 16),
                  _infoLine(Icons.credit_card, 'Zahlung', 'SEPA-Lastschrift'),
                  _infoLine(Icons.business, 'Einzug durch', _aktuell!['sepa_anbieter']?.toString() ?? ''),
                  _infoLine(Icons.numbers, 'Gläubiger-ID', _aktuell!['sepa_glaeubiger_id']?.toString() ?? ''),
                  _infoLine(Icons.schedule, 'SEPA-Einzug', _aktuell!['sepa_einzug']?.toString() ?? ''),
                ]),
              ),
              const SizedBox(height: 12),

              // Kündigung info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: currentDay <= 10 ? Colors.amber.shade50 : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: currentDay <= 10 ? Colors.amber.shade400 : Colors.grey.shade300),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(currentDay <= 10 ? Icons.warning_amber : Icons.info_outline,
                      size: 20, color: currentDay <= 10 ? Colors.amber.shade700 : Colors.grey.shade600),
                  const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Kündigungsfrist', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                        color: currentDay <= 10 ? Colors.amber.shade800 : Colors.grey.shade700)),
                    const SizedBox(height: 4),
                    Text(_aktuell!['kuendigung_frist']?.toString() ?? 'Bis zum 10. des laufenden Monats',
                        style: TextStyle(fontSize: 12, color: currentDay <= 10 ? Colors.amber.shade700 : Colors.grey.shade600)),
                    if (currentDay <= 10)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('Noch ${10 - currentDay} Tag(e) bis zur Kündigungsfrist!',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber.shade800)),
                      ),
                  ])),
                ]),
              ),
              const SizedBox(height: 8),

              // Verification hint
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  Icon(Icons.account_balance, size: 16, color: Colors.blue.shade700),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Tipp: Überprüfen Sie den SEPA-Einzug über Ihr Online-Banking (Kontoauszug / Umsätze).',
                      style: TextStyle(fontSize: 10, color: Colors.blue.shade700))),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 20),
        ],

        // History
        Text('Preisverlauf', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
        const SizedBox(height: 8),
        ..._alle.map((item) {
          final p = double.tryParse(item['preis_monat']?.toString() ?? '0') ?? 0;
          return Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
            child: Row(children: [
              SizedBox(width: 50, child: Text('${item['jahr']}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(12)),
                child: Text(_fmtEuro(p), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
              ),
              const SizedBox(width: 8),
              Text('/ Monat · ${_fmtEuro(p * 12)} / Jahr', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              const Spacer(),
              Text(item['quelle']?.toString() ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
              IconButton(icon: Icon(Icons.edit, size: 16, color: Colors.blueGrey.shade400), onPressed: () => _showAddEditDialog(item),
                  padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 30, minHeight: 30)),
              IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), onPressed: () => _delete(item),
                  padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 30, minHeight: 30)),
            ]),
          );
        }),
      ]),
    );
  }

  Widget _infoLine(IconData icon, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Icon(icon, size: 16, color: Colors.red.shade400),
        const SizedBox(width: 8),
        SizedBox(width: 140, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}
