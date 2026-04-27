import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'wasser_trinken.dart';

class WasserTab extends StatefulWidget {
  final ApiService apiService;
  const WasserTab({super.key, required this.apiService});
  @override
  State<WasserTab> createState() => _WasserTabState();
}

class _WasserTabState extends State<WasserTab> with TickerProviderStateMixin {
  late TabController _tabC;

  @override
  void initState() { super.initState(); _tabC = TabController(length: 1, vsync: this); }
  @override
  void dispose() { _tabC.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TabBar(controller: _tabC, labelColor: Colors.blue.shade800, unselectedLabelColor: Colors.grey, indicatorColor: Colors.blue.shade700,
        tabs: const [
          Tab(icon: Icon(Icons.local_drink, size: 16), text: 'Trinken'),
        ]),
      Expanded(child: TabBarView(controller: _tabC, children: [
        WasserTrinkenTab(apiService: widget.apiService),
      ])),
    ]);
  }
}
