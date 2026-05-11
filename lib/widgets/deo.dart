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
  List<Map<String, dynamic>> _produkte = [];
  Map<String, dynamic>? _selected;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final res = await widget.apiService.deoAction({'action': 'list'});
      if (res['success'] == true && res['produkte'] is List) {
        _produkte = List<Map<String, dynamic>>.from((res['produkte'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      }
      if (widget.userId != null) {
        final sel = await widget.apiService.deoAction({'action': 'get_user', 'user_id': widget.userId});
        if (sel['success'] == true && sel['deo'] != null) _selected = Map<String, dynamic>.from(sel['deo'] as Map);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (widget.userId != null) ...[
        Row(children: [
          Icon(Icons.shield, color: Colors.purple.shade700),
          const SizedBox(width: 8),
          Text('Ausgewähltes Deo', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.purple.shade800)),
          const Spacer(),
          FilledButton.icon(onPressed: _showSelect, icon: const Icon(Icons.search, size: 14), label: Text(_selected != null ? 'Ändern' : 'Auswählen', style: const TextStyle(fontSize: 11)),
            style: FilledButton.styleFrom(backgroundColor: Colors.purple.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero)),
        ]),
        const SizedBox(height: 12),
        if (_selected != null)
          _buildProductCard(_selected!, selected: true)
        else
          Container(width: double.infinity, padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
            child: Column(children: [
              Icon(Icons.shield, size: 40, color: Colors.grey.shade300), const SizedBox(height: 8),
              Text('Kein Deo ausgewählt', style: TextStyle(color: Colors.grey.shade500)),
            ])),
        const Divider(height: 32),
      ],
      Text('Alle Produkte (${_produkte.length})', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
      const SizedBox(height: 12),
      ..._produkte.map((p) => _buildProductCard(p)),
    ]));
  }

  Widget _buildProductCard(Map<String, dynamic> p, {bool selected = false}) {
    final color = selected ? Colors.purple : Colors.brown;
    final besonderheiten = (p['besonderheiten']?.toString() ?? '').split(',').where((s) => s.trim().isNotEmpty).toList();
    return Container(
      width: double.infinity, margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: selected ? color.shade400 : color.shade200, width: selected ? 2 : 1),
        boxShadow: selected ? [BoxShadow(color: color.shade100, blurRadius: 8)] : null),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(gradient: LinearGradient(colors: [color.shade600, color.shade800]), borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
          child: Row(children: [
            Icon(p['art'] == 'spray' ? Icons.air : Icons.shield, size: 24, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${p['marke'] ?? ''} — ${p['name'] ?? ''}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
              Text('${p['art'] ?? ''} • ${p['menge'] ?? ''} • ${p['preis'] ?? ''}', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.8))),
            ])),
            if (p['schutz']?.toString().isNotEmpty == true) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
              child: Text(p['schutz'].toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white))),
          ]),
        ),
        Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (besonderheiten.isNotEmpty) ...[
            Wrap(spacing: 6, runSpacing: 4, children: besonderheiten.map((h) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: color.shade200)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.check_circle, size: 12, color: color.shade600), const SizedBox(width: 3),
                Text(h.trim(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color.shade800))]),
            )).toList()),
            const SizedBox(height: 8),
          ],
          Text(p['beschreibung']?.toString() ?? '', style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.3)),
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.shopping_cart, size: 12, color: Colors.grey.shade500), const SizedBox(width: 4),
            Text(p['bezugsquelle']?.toString() ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
          ]),
        ])),
      ]),
    );
  }

  void _showSelect() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Row(children: [Icon(Icons.shield, size: 18, color: Colors.purple.shade700), const SizedBox(width: 8), const Text('Deo auswählen', style: TextStyle(fontSize: 15))]),
      content: SizedBox(width: 450, height: 400, child: ListView.builder(
        itemCount: _produkte.length, itemBuilder: (_, i) {
          final p = _produkte[i];
          final isSel = _selected != null && _selected!['id'] == p['id'];
          return Card(color: isSel ? Colors.purple.shade50 : null, child: ListTile(
            onTap: () async {
              await widget.apiService.deoAction({'action': 'save_user', 'user_id': widget.userId, 'deo_id': p['id']});
              setState(() => _selected = p);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            leading: CircleAvatar(backgroundColor: isSel ? Colors.purple.shade100 : Colors.brown.shade50,
              child: Icon(p['art'] == 'spray' ? Icons.air : Icons.shield, color: isSel ? Colors.purple.shade700 : Colors.brown.shade600, size: 20)),
            title: Text('${p['marke']} ${p['name']}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isSel ? Colors.purple.shade800 : null)),
            subtitle: Text('${p['art']} • ${p['menge']} • ${p['schutz']}', style: const TextStyle(fontSize: 10)),
            trailing: isSel ? Icon(Icons.check_circle, color: Colors.purple.shade600) : null,
          ));
        },
      )),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen'))],
    ));
  }
}
