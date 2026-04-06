import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/user.dart';

class FreizeitTabContent extends StatefulWidget {
  final ApiService apiService;
  final User user;

  const FreizeitTabContent({super.key, required this.apiService, required this.user});

  @override
  State<FreizeitTabContent> createState() => _FreizeitTabContentState();
}

class _FreizeitTabContentState extends State<FreizeitTabContent> {
  // Freizeit data per member (encrypted in behoerde_data)
  final Map<String, Map<String, dynamic>> _freizeitData = {};
  bool _isLoading = true;

  static const _kategorien = [
    {'key': 'kino', 'label': 'Kino', 'icon': Icons.movie},
    {'key': 'fitnessstudio', 'label': 'Fitnessstudio', 'icon': Icons.fitness_center},
    {'key': 'schwimmbad', 'label': 'Schwimmbad', 'icon': Icons.pool},
    {'key': 'verein', 'label': 'Sportverein', 'icon': Icons.sports_soccer},
    {'key': 'bibliothek', 'label': 'Bibliothek', 'icon': Icons.menu_book},
    {'key': 'museum', 'label': 'Museum', 'icon': Icons.museum},
    {'key': 'theater', 'label': 'Theater', 'icon': Icons.theater_comedy},
    {'key': 'sonstiges', 'label': 'Sonstiges', 'icon': Icons.category},
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final result = await widget.apiService.getFreizeitData(widget.user.id);
      if (result['success'] == true && result['data'] is Map) {
        final data = Map<String, dynamic>.from(result['data'] as Map);
        for (final k in data.keys) {
          if (data[k] is Map) {
            _freizeitData[k] = Map<String, dynamic>.from(data[k] as Map);
          }
        }
      }
    } catch (e) {
      debugPrint('[Freizeit] load error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveFreizeit(String key, Map<String, dynamic>? data) async {
    try {
      await widget.apiService.saveFreizeitData(widget.user.id, key, data);
    } catch (e) {
      debugPrint('[Freizeit] save error: $e');
    }
  }

  void _selectFromDB(String kategorie, StateSetter setTabState) async {
    final dbKat = kategorie == 'kino' ? 'Kino'
        : kategorie == 'fitnessstudio' ? 'Fitnessstudio'
        : kategorie == 'schwimmbad' ? 'Schwimmbad'
        : kategorie == 'bibliothek' ? 'Bibliothek'
        : kategorie == 'museum' ? 'Museum'
        : kategorie == 'theater' ? 'Theater'
        : kategorie;

    final items = await widget.apiService.getFreizeitDatenbank(kategorie: dbKat);

    if (!mounted) return;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Keine Einträge für $dbKat in der Datenbank'), backgroundColor: Colors.orange),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.list, size: 18, color: Colors.deepPurple.shade700),
          const SizedBox(width: 8),
          Text('$dbKat auswählen', style: const TextStyle(fontSize: 15)),
        ]),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450, maxHeight: 400),
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (_, i) {
              final item = items[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: InkWell(
                  onTap: () {
                    Navigator.pop(ctx);
                    setTabState(() {
                      _freizeitData[kategorie] = {
                        'name': item['name'] ?? '',
                        'firma': item['firma'] ?? '',
                        'strasse': item['strasse'] ?? '',
                        'plz_ort': item['plz_ort'] ?? '',
                        'telefon': item['telefon'] ?? '',
                        'email': item['email'] ?? '',
                        'website': item['website'] ?? '',
                      };
                    });
                    _saveFreizeit(kategorie, _freizeitData[kategorie]);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(item['name']?.toString() ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade800)),
                      if ((item['firma']?.toString() ?? '').isNotEmpty)
                        Text(item['firma'], style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      if ((item['strasse']?.toString() ?? '').isNotEmpty || (item['plz_ort']?.toString() ?? '').isNotEmpty)
                        Text('${item['strasse'] ?? ''}, ${item['plz_ort'] ?? ''}', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return DefaultTabController(
      length: _kategorien.length,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: Colors.deepPurple.shade700,
            indicatorColor: Colors.deepPurple.shade700,
            tabs: _kategorien.map((k) => Tab(
              icon: Icon(k['icon'] as IconData, size: 18),
              text: k['label'] as String,
            )).toList(),
          ),
          Expanded(
            child: TabBarView(
              children: _kategorien.map((k) {
                final key = k['key'] as String;
                final label = k['label'] as String;
                final icon = k['icon'] as IconData;
                return _buildKategorieTab(key, label, icon);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKategorieTab(String key, String label, IconData icon) {
    final data = _freizeitData[key] ?? {};
    final hasSelection = (data['name']?.toString() ?? '').isNotEmpty;

    return StatefulBuilder(builder: (ctx, setTabState) => SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.deepPurple.shade600, Colors.deepPurple.shade400]),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Icon(icon, size: 32, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              Text('Freizeit des Mitglieds', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8))),
            ])),
          ]),
        ),
        const SizedBox(height: 20),

        if (!hasSelection) ...[
          // Select from DB
          ElevatedButton.icon(
            icon: const Icon(Icons.search, size: 18),
            label: Text('$label aus Datenbank auswählen'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple.shade600, foregroundColor: Colors.white),
            onPressed: () => _selectFromDB(key, setTabState),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity, padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
            child: Column(children: [
              Icon(icon, size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 8),
              Text('Kein $label ausgewählt', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
            ]),
          ),
        ] else ...[
          // Selected card
          Container(
            width: double.infinity, padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.deepPurple.shade200),
              boxShadow: [BoxShadow(color: Colors.deepPurple.shade50, blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.deepPurple.shade50, borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, size: 28, color: Colors.deepPurple.shade700),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(data['name']?.toString() ?? '', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade800)),
                  if ((data['firma']?.toString() ?? '').isNotEmpty)
                    Text(data['firma'], style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ])),
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 20, color: Colors.red.shade400),
                  tooltip: 'Entfernen',
                  onPressed: () {
                    setTabState(() => _freizeitData.remove(key));
                    _saveFreizeit(key, _freizeitData[key]);
                  },
                ),
              ]),
              const SizedBox(height: 12),
              if ((data['strasse']?.toString() ?? '').isNotEmpty || (data['plz_ort']?.toString() ?? '').isNotEmpty)
                _infoRow(Icons.location_on, 'Adresse', '${data['strasse'] ?? ''}${(data['plz_ort']?.toString() ?? '').isNotEmpty ? ', ${data['plz_ort']}' : ''}'),
              if ((data['telefon']?.toString() ?? '').isNotEmpty)
                _infoRow(Icons.phone, 'Telefon', data['telefon']),
              if ((data['email']?.toString() ?? '').isNotEmpty)
                _infoRow(Icons.email, 'E-Mail', data['email']),
              if ((data['website']?.toString() ?? '').isNotEmpty)
                _infoRow(Icons.language, 'Website', data['website']),
            ]),
          ),
        ],
      ]),
    ));
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Icon(icon, size: 16, color: Colors.deepPurple.shade400),
        const SizedBox(width: 8),
        Text('$label: ', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}
