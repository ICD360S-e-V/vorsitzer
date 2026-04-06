import 'package:flutter/material.dart';
import '../services/api_service.dart';

class GerichtScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onBack;

  const GerichtScreen({
    super.key,
    required this.apiService,
    required this.onBack,
  });

  @override
  State<GerichtScreen> createState() => _GerichtScreenState();
}

class _GerichtScreenState extends State<GerichtScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
                tooltip: 'Zurück',
              ),
              const SizedBox(width: 8),
              Icon(Icons.gavel, size: 28, color: Colors.deepPurple.shade700),
              const SizedBox(width: 12),
              const Text('Gericht', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          // Tabs
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: TabBar(
              controller: _tabController,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 13),
              indicator: BoxDecoration(
                color: Colors.deepPurple.shade600,
                borderRadius: BorderRadius.circular(10),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.grey.shade700,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.family_restroom, size: 18),
                    SizedBox(width: 8),
                    Text('Betreuungsgericht'),
                  ]),
                ),
                Tab(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.work, size: 18),
                    SizedBox(width: 8),
                    Text('Arbeitsgericht'),
                  ]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _BetreuungsgerichtTab(apiService: widget.apiService),
                _ArbeitsgerichtTab(apiService: widget.apiService),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// BETREUUNGSGERICHT TAB
// ═══════════════════════════════════════════════════════════════
class _BetreuungsgerichtTab extends StatefulWidget {
  final ApiService apiService;
  const _BetreuungsgerichtTab({required this.apiService});

  @override
  State<_BetreuungsgerichtTab> createState() => _BetreuungsgerichtTabState();
}

class _BetreuungsgerichtTabState extends State<_BetreuungsgerichtTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info card
          Card(
            elevation: 0,
            color: Colors.deepPurple.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.family_restroom, size: 24, color: Colors.deepPurple.shade700),
                    const SizedBox(width: 10),
                    Text('Betreuungsgericht', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade700)),
                  ]),
                  const Divider(height: 24),
                  _infoRow(Icons.account_balance, 'Gericht', 'Amtsgericht Neu-Ulm'),
                  const SizedBox(height: 8),
                  _infoRow(Icons.location_on, 'Adresse', 'Augsburger Str. 14, 89231 Neu-Ulm'),
                  const SizedBox(height: 8),
                  _infoRow(Icons.phone, 'Telefon', '0731 / 7048-0'),
                  const SizedBox(height: 8),
                  _infoRow(Icons.fax, 'Fax', '0731 / 7048-200'),
                  const SizedBox(height: 8),
                  _infoRow(Icons.info_outline, 'Zuständigkeit', 'Betreuungsverfahren, Vormundschaft, Pflegschaft'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Placeholder for future content
          Card(
            elevation: 0,
            color: Colors.grey.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.construction, size: 40, color: Colors.grey.shade300),
                    const SizedBox(height: 10),
                    Text('Vorgänge und Dokumente werden hier verwaltet', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.deepPurple.shade400),
        const SizedBox(width: 10),
        SizedBox(
          width: 110,
          child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// ARBEITSGERICHT TAB
// ═══════════════════════════════════════════════════════════════
class _ArbeitsgerichtTab extends StatefulWidget {
  final ApiService apiService;
  const _ArbeitsgerichtTab({required this.apiService});

  @override
  State<_ArbeitsgerichtTab> createState() => _ArbeitsgerichtTabState();
}

class _ArbeitsgerichtTabState extends State<_ArbeitsgerichtTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info card
          Card(
            elevation: 0,
            color: Colors.orange.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.work, size: 24, color: Colors.orange.shade800),
                    const SizedBox(width: 10),
                    Text('Arbeitsgericht', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                  ]),
                  const Divider(height: 24),
                  _infoRow(Icons.account_balance, 'Gericht', 'Arbeitsgericht Ulm'),
                  const SizedBox(height: 8),
                  _infoRow(Icons.location_on, 'Adresse', 'Olgastraße 109, 89073 Ulm'),
                  const SizedBox(height: 8),
                  _infoRow(Icons.phone, 'Telefon', '0731 / 189-0'),
                  const SizedBox(height: 8),
                  _infoRow(Icons.fax, 'Fax', '0731 / 189-197'),
                  const SizedBox(height: 8),
                  _infoRow(Icons.info_outline, 'Zuständigkeit', 'Arbeitsrechtliche Streitigkeiten, Kündigungsschutz, Lohnklagen'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Placeholder for future content
          Card(
            elevation: 0,
            color: Colors.grey.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.construction, size: 40, color: Colors.grey.shade300),
                    const SizedBox(height: 10),
                    Text('Vorgänge und Dokumente werden hier verwaltet', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.orange.shade400),
        const SizedBox(width: 10),
        SizedBox(
          width: 110,
          child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
      ],
    );
  }
}
