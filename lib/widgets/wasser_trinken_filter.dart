import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../screens/webview_screen.dart';

class WasserTrinkenFilterTab extends StatefulWidget {
  final ApiService apiService;
  const WasserTrinkenFilterTab({super.key, required this.apiService});
  @override
  State<WasserTrinkenFilterTab> createState() => _WasserTrinkenFilterTabState();
}

class _WasserTrinkenFilterTabState extends State<WasserTrinkenFilterTab> {
  List<Map<String, dynamic>> _produkte = [];
  bool _isLoading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final res = await widget.apiService.getEmpfehlungProdukte('wasser');
      if (res['success'] == true) {
        _produkte = (res['produkte'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  MaterialColor _getColor(String typ) {
    if (typ.toLowerCase().contains('umkehrosmose')) return Colors.blue;
    if (typ.toLowerCase().contains('aktivkohle')) return Colors.green;
    return Colors.teal;
  }

  IconData _getIcon(String typ) {
    if (typ.toLowerCase().contains('umkehrosmose')) return Icons.water_drop;
    if (typ.toLowerCase().contains('aktivkohle')) return Icons.filter_alt;
    return Icons.water;
  }

  void _openDetail(Map<String, dynamic> p) {
    final color = _getColor(p['typ']?.toString() ?? '');
    showDialog(context: context, builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(width: 550, child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(_getIcon(p['typ']?.toString() ?? ''), size: 28, color: color),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p['name']?.toString() ?? '', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color.shade800)),
            Text(p['marke']?.toString() ?? '', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ])),
          Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: color.shade100, borderRadius: BorderRadius.circular(20)),
            child: Text(p['preis']?.toString() ?? '', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color.shade800))),
          const SizedBox(width: 8),
          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
        ]),
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(8)),
          child: Text(p['typ']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color.shade700))),
        const SizedBox(height: 12),
        Text(p['beschreibung']?.toString() ?? '', style: const TextStyle(fontSize: 13, height: 1.5)),
        if ((p['vorteile']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Vorteile', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
          const SizedBox(height: 4),
          ...((p['vorteile']?.toString() ?? '').split(',').map((v) => Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.check_circle, size: 14, color: Colors.green.shade600),
              const SizedBox(width: 6),
              Expanded(child: Text(v.trim(), style: const TextStyle(fontSize: 12))),
            ]),
          ))),
        ],
        if ((p['nachteile']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Nachteile', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
          const SizedBox(height: 4),
          ...((p['nachteile']?.toString() ?? '').split(',').map((v) => Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.cancel, size: 14, color: Colors.red.shade400),
              const SizedBox(width: 6),
              Expanded(child: Text(v.trim(), style: const TextStyle(fontSize: 12))),
            ]),
          ))),
        ],
        const SizedBox(height: 16),
        if ((p['website']?.toString() ?? '').isNotEmpty)
          ElevatedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WebViewScreen(title: p['marke']?.toString() ?? 'Produkt', url: p['website'].toString()))),
            icon: const Icon(Icons.open_in_browser, size: 18),
            label: const Text('Website öffnen'),
            style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
          ),
      ]))),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.shade200)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.filter_alt, size: 28, color: Colors.blue.shade700),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Wasserfilter für zu Hause', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
            const SizedBox(height: 4),
            Text('Leitungswasser enthält oft Mikroplastik, Medikamentenrückstände, Schwermetalle und PFAS. '
                 'Mit einer Umkehrosmose-Anlage (0.0001 µm) wird das Wasser auf molekularer Ebene gereinigt — '
                 'sauberer als jedes Flaschenwasser.',
                style: TextStyle(fontSize: 12, color: Colors.blue.shade900, height: 1.4)),
          ])),
        ]),
      )),
      Expanded(child: _produkte.isEmpty
        ? Center(child: Text('Keine Empfehlungen', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(padding: const EdgeInsets.all(12), itemCount: _produkte.length, itemBuilder: (ctx, i) {
            final p = _produkte[i];
            final color = _getColor(p['typ']?.toString() ?? '');
            final bewertung = p['bewertung']?.toString() ?? '';
            return Card(margin: const EdgeInsets.only(bottom: 10), elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: InkWell(onTap: () => _openDetail(p), borderRadius: BorderRadius.circular(12),
                child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
                  Container(width: 50, height: 50, decoration: BoxDecoration(color: color.shade100, borderRadius: BorderRadius.circular(12)),
                    child: Icon(_getIcon(p['typ']?.toString() ?? ''), size: 28, color: color.shade700)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p['name']?.toString() ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color.shade800)),
                    Text(p['marke']?.toString() ?? '', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    const SizedBox(height: 4),
                    Row(children: [
                      Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(6)),
                        child: Text(p['typ']?.toString() ?? '', style: TextStyle(fontSize: 9, color: color.shade700, fontWeight: FontWeight.w600))),
                      if (bewertung.isNotEmpty) ...[const SizedBox(width: 8), Text(bewertung, style: const TextStyle(fontSize: 11))],
                    ]),
                  ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(p['preis']?.toString() ?? '', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color.shade800)),
                    const SizedBox(height: 4),
                    Icon(Icons.chevron_right, size: 20, color: Colors.grey.shade400),
                  ]),
                ])),
              ),
            );
          })),
    ]);
  }
}
