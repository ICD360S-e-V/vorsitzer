import 'package:flutter/material.dart';
import '../services/api_service.dart';

class DeoTab extends StatelessWidget {
  final ApiService apiService;
  const DeoTab({super.key, required this.apiService});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 1,
      child: Column(children: [
        TabBar(
          labelColor: Colors.purple.shade800,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.purple.shade700,
          tabs: const [
            Tab(text: 'Roll-on Deo'),
          ],
        ),
        const Expanded(child: TabBarView(children: [
          _RollOnDeoView(),
        ])),
      ]),
    );
  }
}

class _RollOnDeoView extends StatelessWidget {
  const _RollOnDeoView();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Roll-on Deo Empfehlungen', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.purple.shade800)),
        const SizedBox(height: 16),

        // Triple Dry
        _buildProductCard(
          name: 'Triple Dry Antitranspirant Deo Roll-on Classic',
          menge: '50 ml',
          preis: 'ca. 3,50 €',
          beschreibung: 'Bekämpft extrem starke Transpiration mit 3-fach Wirkformel. '
              'Bis zu 72 Stunden extra starken Schutz vor Schweiß und Körpergeruch. '
              'Antibakterieller Wirkstoff gegen Geruchsentstehung. '
              'Geeignet für alle Hauttypen, einschließlich empfindlicher Haut.',
          inhaltsstoffe: 'Aqua, Aluminum Zirconium Tetrachlorohydrex Gly, Glycerin, '
              'PPG-15 Stearyl Ether, Steareth-2, Cyclopentasiloxane, Steareth-21, '
              'Aluminum Sesquichlorohydrate',
          bezugsquelle: 'dm, Rossmann, Amazon',
          website: 'www.triple-dry.com',
          color: Colors.purple,
          icon: Icons.shield,
          highlights: ['72h Schutz', 'Antibakteriell', 'Für empfindliche Haut', 'Parfümfrei erhältlich'],
        ),
      ]),
    );
  }

  Widget _buildProductCard({
    required String name,
    required String menge,
    required String preis,
    required String beschreibung,
    required String inhaltsstoffe,
    required String bezugsquelle,
    required String website,
    required MaterialColor color,
    required IconData icon,
    required List<String> highlights,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.shade200),
        boxShadow: [BoxShadow(color: color.shade50, blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [color.shade600, color.shade800]),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Row(children: [
            Icon(icon, size: 28, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
              Text('$menge • $preis', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8))),
            ])),
          ]),
        ),

        Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Highlights
          Wrap(spacing: 8, runSpacing: 6, children: highlights.map((h) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: color.shade200)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check_circle, size: 14, color: color.shade600),
              const SizedBox(width: 4),
              Text(h, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color.shade800)),
            ]),
          )).toList()),
          const SizedBox(height: 12),

          // Beschreibung
          Text('Beschreibung', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          Text(beschreibung, style: TextStyle(fontSize: 12, color: Colors.grey.shade800, height: 1.4)),
          const SizedBox(height: 12),

          // Inhaltsstoffe
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Inhaltsstoffe', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
            children: [Text(inhaltsstoffe, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, height: 1.4))],
          ),

          // Bezugsquelle
          Row(children: [
            Icon(Icons.shopping_cart, size: 14, color: color.shade600),
            const SizedBox(width: 6),
            Text('Erhältlich bei: ', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            Text(bezugsquelle, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color.shade700)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.language, size: 14, color: color.shade600),
            const SizedBox(width: 6),
            Text(website, style: TextStyle(fontSize: 11, color: color.shade600)),
          ]),
        ])),
      ]),
    );
  }
}
