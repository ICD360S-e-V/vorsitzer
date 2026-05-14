import 'package:flutter/material.dart';
import '../services/api_service.dart';

class DeoTab extends StatefulWidget {
  final ApiService apiService;
  final int? userId;
  const DeoTab({super.key, required this.apiService, this.userId});
  @override
  State<DeoTab> createState() => _DeoTabState();
}

class _DeoTabState extends State<DeoTab> {
  Map<String, dynamic>? _selected;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      if (widget.userId != null) {
        final sel = await widget.apiService.deoAction({'action': 'get_user', 'user_id': widget.userId});
        if (sel['success'] == true && sel['deo'] != null) _selected = Map<String, dynamic>.from(sel['deo'] as Map);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(length: 1, child: Column(children: [
      TabBar(labelColor: Colors.purple.shade800, unselectedLabelColor: Colors.grey, indicatorColor: Colors.purple.shade700,
        tabs: const [Tab(icon: Icon(Icons.shield, size: 16), text: 'Roll-on')]),
      Expanded(child: TabBarView(children: [
        _loading ? const Center(child: CircularProgressIndicator()) : _buildRollOnTab(),
      ])),
    ]));
  }

  Widget _buildRollOnTab() {
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.shield, color: Colors.purple.shade700),
        const SizedBox(width: 8),
        Text('Ausgewähltes Deo', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.purple.shade800)),
        const Spacer(),
        FilledButton.icon(onPressed: _showSelect, icon: const Icon(Icons.search, size: 14), label: Text(_selected != null ? 'Ändern' : 'Auswählen', style: const TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.purple.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero)),
      ]),
      const SizedBox(height: 16),
      if (_selected != null)
        _buildProductCard(_selected!)
      else
        Container(width: double.infinity, padding: const EdgeInsets.all(32), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
          child: Column(children: [
            Icon(Icons.shield, size: 48, color: Colors.grey.shade300), const SizedBox(height: 12),
            Text('Kein Deo ausgewählt', style: TextStyle(fontSize: 15, color: Colors.grey.shade500)),
            const SizedBox(height: 8),
            Text('Tippen Sie auf "Auswählen" um ein Roll-on Deo zuzuweisen', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
          ])),
    ]));
  }

  Widget _buildStars(double rating) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      ...List.generate(5, (i) {
        if (i < rating.floor()) return Icon(Icons.star, size: 16, color: Colors.amber.shade600);
        if (i < rating) return Icon(Icons.star_half, size: 16, color: Colors.amber.shade600);
        return Icon(Icons.star_border, size: 16, color: Colors.amber.shade300);
      }),
      const SizedBox(width: 4),
      Text(rating.toStringAsFixed(1), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber.shade800)),
    ]);
  }

  Widget _buildProductCard(Map<String, dynamic> p) {
    final besonderheiten = (p['besonderheiten']?.toString() ?? '').split(',').where((s) => s.trim().isNotEmpty).toList();
    final bewertung = double.tryParse(p['bewertung']?.toString() ?? '0') ?? 0.0;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.purple.shade300, width: 2),
        boxShadow: [BoxShadow(color: Colors.purple.shade50, blurRadius: 8)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.purple.shade600, Colors.purple.shade800]), borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
          child: Row(children: [
            const Icon(Icons.shield, size: 28, color: Colors.white), const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${p['marke'] ?? ''}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
              Text(p['name']?.toString() ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
            ])),
            if (p['schutz']?.toString().isNotEmpty == true) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
              child: Text(p['schutz'].toString(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white))),
          ]),
        ),
        Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (bewertung > 0) ...[_buildStars(bewertung), const SizedBox(width: 12)],
            Text('${p['menge'] ?? ''}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(width: 8),
            Text('${p['preis'] ?? ''}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.brown.shade700)),
          ]),
          const SizedBox(height: 10),
          if (besonderheiten.isNotEmpty) ...[
            Wrap(spacing: 6, runSpacing: 4, children: besonderheiten.map((h) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.purple.shade200)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.check_circle, size: 12, color: Colors.purple.shade600), const SizedBox(width: 3),
                Text(h.trim(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.purple.shade800))]),
            )).toList()),
            const SizedBox(height: 10),
          ],
          Text(p['beschreibung']?.toString() ?? '', style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.4)),
          if ((p['bezugsquelle']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(children: [Icon(Icons.shopping_cart, size: 12, color: Colors.grey.shade500), const SizedBox(width: 4),
              Text(p['bezugsquelle'].toString(), style: TextStyle(fontSize: 10, color: Colors.grey.shade500))]),
          ],
          const SizedBox(height: 10),
          Container(
            width: double.infinity, padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline, size: 14, color: Colors.blue.shade700),
              const SizedBox(width: 6),
              Expanded(child: Text.rich(TextSpan(style: TextStyle(fontSize: 10, color: Colors.blue.shade800, height: 1.4), children: [
                const TextSpan(text: 'Bewertung basiert auf 3 Kriterien:\n\n'),
                TextSpan(text: '1. Tests: ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
                const TextSpan(text: 'Öko-Test, Stiftung Warentest, Testberichte.de (Inhaltsstoffe, Schadstoffe, Wirksamkeit). Die Bewertung erfolgt unabhängig durch ICD360S e.V. Es besteht keine Partnerschaft oder Lizenzvereinbarung mit den genannten Testinstituten.\n\n'),
                TextSpan(text: '2. Kundenfeedback: ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
                const TextSpan(text: 'Aggregierte öffentlich zugängliche Kundenbewertungen großer Drogerie- und Online-Handelsplattformen sowie Codecheck.info (Erfahrungen, Geruch, Hautverträglichkeit).\n\n'),
                TextSpan(text: '3. Praxistest: ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
                const TextSpan(text: 'ICD360S e.V. Mitglieder-Erfahrungen.\n\n'),
                TextSpan(text: '⚠ Hinweis: ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                TextSpan(text: 'Diese Empfehlungen stellen keine medizinische oder gesundheitliche Beratung dar. Bei gesundheitlichen Beschwerden konsultieren Sie bitte Ihren Arzt oder Apotheker.', style: TextStyle(color: Colors.orange.shade800)),
              ]))),
            ]),
          ),
        ])),
      ]),
    );
  }

  void _showSelect() async {
    List<Map<String, dynamic>> produkte = [];
    final res = await widget.apiService.deoAction({'action': 'list'});
    if (res['success'] == true && res['produkte'] is List) {
      produkte = List<Map<String, dynamic>>.from((res['produkte'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
    }
    if (!mounted) return;
    final selected = await showDialog<Map<String, dynamic>>(context: context, builder: (ctx) {
      String search = '';
      return StatefulBuilder(builder: (_, setDlg) {
        final filtered = search.isEmpty ? produkte : produkte.where((p) => '${p['marke']} ${p['name']}'.toLowerCase().contains(search.toLowerCase())).toList();
        return AlertDialog(
          title: Row(children: [Icon(Icons.shield, size: 18, color: Colors.purple.shade700), const SizedBox(width: 8), const Text('Roll-on Deo auswählen', style: TextStyle(fontSize: 15))]),
          content: SizedBox(width: 500, height: 450, child: Column(children: [
            TextField(decoration: InputDecoration(hintText: 'Suchen...', isDense: true, prefixIcon: const Icon(Icons.search, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              onChanged: (v) => setDlg(() => search = v)),
            const SizedBox(height: 10),
            Expanded(child: ListView.builder(itemCount: filtered.length, itemBuilder: (_, i) {
              final p = filtered[i];
              final isSel = _selected != null && _selected!['id'] == p['id'];
              return Card(color: isSel ? Colors.purple.shade50 : null, child: ListTile(
                onTap: () => Navigator.pop(ctx, p),
                leading: CircleAvatar(backgroundColor: isSel ? Colors.purple.shade100 : Colors.brown.shade50,
                  child: Icon(Icons.shield, color: isSel ? Colors.purple.shade700 : Colors.brown.shade600, size: 18)),
                title: Text('${p['marke']} — ${p['name']}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isSel ? Colors.purple.shade800 : null)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    ...List.generate(5, (j) {
                      final bew = double.tryParse(p['bewertung']?.toString() ?? '0') ?? 0;
                      if (j < bew.floor()) return Icon(Icons.star, size: 12, color: Colors.amber.shade600);
                      if (j < bew) return Icon(Icons.star_half, size: 12, color: Colors.amber.shade600);
                      return Icon(Icons.star_border, size: 12, color: Colors.amber.shade300);
                    }),
                    const SizedBox(width: 3),
                    Text(p['bewertung']?.toString() ?? '', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber.shade800)),
                  ]),
                  Row(children: [
                    Text('${p['menge']} • ${p['preis']}', style: const TextStyle(fontSize: 10)),
                    const SizedBox(width: 6),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(4)),
                      child: Text(p['schutz']?.toString() ?? '', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.purple.shade700))),
                  ]),
                ]),
                trailing: isSel ? Icon(Icons.check_circle, color: Colors.purple.shade600, size: 18) : null,
              ));
            })),
          ])),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen'))],
        );
      });
    });
    if (selected != null && widget.userId != null) {
      await widget.apiService.deoAction({'action': 'save_user', 'user_id': widget.userId, 'deo_id': selected['id']});
      setState(() => _selected = selected);
    }
  }
}
