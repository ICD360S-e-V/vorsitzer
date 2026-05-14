import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'wasser_trinken_filter.dart';

class WasserTrinkenTab extends StatefulWidget {
  final ApiService apiService;
  const WasserTrinkenTab({super.key, required this.apiService});
  @override
  State<WasserTrinkenTab> createState() => _WasserTrinkenTabState();
}

class _WasserTrinkenTabState extends State<WasserTrinkenTab> with TickerProviderStateMixin {
  late TabController _tabC;

  @override
  void initState() { super.initState(); _tabC = TabController(length: 1, vsync: this); }
  @override
  void dispose() { _tabC.dispose(); super.dispose(); }

  Widget _infoCard(IconData icon, String title, MaterialColor color, List<String> points) {
    return Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: color.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 20, color: color.shade700),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color.shade800)),
        ]),
        const SizedBox(height: 6),
        ...points.map((p) => Padding(padding: const EdgeInsets.only(bottom: 3), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 4), child: Icon(Icons.circle, size: 5, color: color.shade400)),
          const SizedBox(width: 6),
          Expanded(child: Text(p, style: TextStyle(fontSize: 11, color: Colors.grey.shade800, height: 1.3))),
        ]))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
          _miniInfo(Icons.water_drop, 'Min. 2L/Tag', Colors.blue),
          const SizedBox(width: 8),
          _miniInfo(Icons.schedule, 'Regelmäßig trinken', Colors.teal),
          const SizedBox(width: 8),
          _miniInfo(Icons.warning_amber, 'Dehydration vermeiden', Colors.orange),
          const SizedBox(width: 8),
          _miniInfo(Icons.filter_alt, 'Gefiltertes Wasser', Colors.indigo),
        ])),
      ),
      TabBar(controller: _tabC, labelColor: Colors.blue.shade800, unselectedLabelColor: Colors.grey, indicatorColor: Colors.blue.shade700,
        tabs: const [
          Tab(icon: Icon(Icons.filter_alt, size: 16), text: 'Filter'),
        ]),
      Expanded(child: TabBarView(controller: _tabC, children: [
        WasserTrinkenFilterTab(apiService: widget.apiService),
      ])),
    ]);
  }

  Widget _miniInfo(IconData icon, String text, MaterialColor color) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(20), border: Border.all(color: color.shade200)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color.shade700),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color.shade800)),
      ]),
    );
  }
}
