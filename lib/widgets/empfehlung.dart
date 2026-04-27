import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'wasser.dart';

class EmpfehlungContent extends StatefulWidget {
  final ApiService apiService;
  const EmpfehlungContent({super.key, required this.apiService});
  @override
  State<EmpfehlungContent> createState() => _EmpfehlungContentState();
}

class _EmpfehlungContentState extends State<EmpfehlungContent> with TickerProviderStateMixin {
  late TabController _tabC;

  @override
  void initState() {
    super.initState();
    _tabC = TabController(length: 1, vsync: this);
  }

  @override
  void dispose() { _tabC.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TabBar(controller: _tabC, labelColor: Colors.blue.shade800, unselectedLabelColor: Colors.grey, indicatorColor: Colors.blue.shade700,
        tabs: const [
          Tab(icon: Icon(Icons.water_drop, size: 18), text: 'Wasser'),
        ]),
      Expanded(child: TabBarView(controller: _tabC, children: [
        WasserTab(apiService: widget.apiService),
      ])),
    ]);
  }
}
