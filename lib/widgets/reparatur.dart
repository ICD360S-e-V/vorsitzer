import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import 'korrespondenz_attachments_widget.dart';

class ReparaturContent extends StatefulWidget {
  final ApiService apiService;
  final int userId;

  const ReparaturContent({super.key, required this.apiService, required this.userId});

  @override
  State<ReparaturContent> createState() => _ReparaturContentState();
}

class _ReparaturContentState extends State<ReparaturContent> {
  List<Map<String, dynamic>> _vorfaelle = [];
  bool _isLoading = true;

  static const _geraetTypen = [
    'Uhr', 'Laptop', 'Telefon', 'Tablet', 'PC', 'Drucker',
    'Fernseher', 'Kopfhörer', 'Kamera', 'Spielkonsole', 'Sonstiges',
  ];

  static const _statusMap = {
    'eingegangen': ('Eingegangen', Colors.blue),
    'in_bearbeitung': ('In Bearbeitung', Colors.orange),
    'warte_auf_teil': ('Warte auf Ersatzteil', Colors.amber),
    'repariert': ('Repariert', Colors.green),
    'nicht_reparierbar': ('Nicht reparierbar', Colors.red),
    'abgeholt': ('Abgeholt', Colors.grey),
  };

  static const _uebergabeMap = {
    'persoenlich': 'Persönlich abgegeben',
    'abgeholt': 'Wurde abgeholt',
    'versendet': 'Per Post versendet',
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final result = await widget.apiService.getReparaturVorfaelle(widget.userId);
    if (mounted && result['success'] == true) {
      setState(() {
        _vorfaelle = List<Map<String, dynamic>>.from(result['vorfaelle'] ?? []);
        _isLoading = false;
      });
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  static IconData geraetIcon(String geraet) {
    switch (geraet.toLowerCase()) {
      case 'uhr': return Icons.watch;
      case 'laptop': return Icons.laptop;
      case 'telefon': return Icons.phone_android;
      case 'tablet': return Icons.tablet;
      case 'pc': return Icons.computer;
      case 'drucker': return Icons.print;
      case 'fernseher': return Icons.tv;
      case 'kopfhörer': return Icons.headphones;
      case 'kamera': return Icons.camera_alt;
      case 'spielkonsole': return Icons.videogame_asset;
      default: return Icons.build;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 1,
      child: Column(
        children: [
          const TabBar(labelColor: Colors.deepOrange, tabs: [Tab(icon: Icon(Icons.build_circle), text: 'Vorfall')]),
          Expanded(child: TabBarView(children: [_buildVorfallTab()])),
        ],
      ),
    );
  }

  Widget _buildVorfallTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.build, color: Colors.deepOrange.shade700),
              const SizedBox(width: 8),
              Text('Reparaturen', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepOrange.shade700)),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => _showCreateDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Neue Reparatur'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange.shade700, foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _vorfaelle.isEmpty
                  ? Center(child: Text('Keine Reparaturen', style: TextStyle(color: Colors.grey.shade500)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _vorfaelle.length,
                      itemBuilder: (_, i) => _buildVorfallCard(_vorfaelle[i]),
                    ),
        ),
      ],
    );
  }

  Widget _buildVorfallCard(Map<String, dynamic> v) {
    final status = v['status'] ?? 'eingegangen';
    final (statusLabel, statusColor) = _statusMap[status] ?? ('Unbekannt', Colors.grey);
    final geraet = v['geraet'] ?? '';
    final marke = v['marke'] ?? '';
    final modell = v['modell'] ?? '';
    final eingangsdatum = v['eingangsdatum'] ?? '';
    final kostenlos = v['kostenlos'].toString() == '1';
    final uebergabe = _uebergabeMap[v['uebergabe']] ?? v['uebergabe'] ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.15),
          child: Icon(geraetIcon(geraet), color: statusColor),
        ),
        title: Row(
          children: [
            Text('$geraet${marke.isNotEmpty ? ' — $marke' : ''}${modell.isNotEmpty ? ' $modell' : ''}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Text(statusLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor)),
            ),
            if (kostenlos) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                child: Text('Kostenlos', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.green.shade700)),
              ),
            ],
          ],
        ),
        subtitle: Text('$eingangsdatum • $uebergabe', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        onTap: () => _showVorfallDetailDialog(v),
      ),
    );
  }

  Future<void> _showCreateDialog() async {
    String geraet = 'Telefon';
    String uebergabe = 'persoenlich';
    bool kostenlos = true;
    DateTime eingangsdatum = DateTime.now();
    final markeCtrl = TextEditingController();
    final modellCtrl = TextEditingController();
    final snCtrl = TextEditingController();
    final beschreibungCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: Row(children: [Icon(Icons.build_circle, color: Colors.deepOrange.shade700), const SizedBox(width: 8), const Text('Neue Reparatur')]),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(value: geraet, decoration: const InputDecoration(labelText: 'Gerät *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.devices)),
                  items: _geraetTypen.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(), onChanged: (val) => setDlgState(() => geraet = val!)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: TextField(controller: markeCtrl, decoration: const InputDecoration(labelText: 'Marke', border: OutlineInputBorder()))),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: modellCtrl, decoration: const InputDecoration(labelText: 'Modell', border: OutlineInputBorder()))),
                ]),
                const SizedBox(height: 12),
                TextField(controller: snCtrl, decoration: const InputDecoration(labelText: 'Seriennummer', border: OutlineInputBorder(), prefixIcon: Icon(Icons.qr_code))),
                const SizedBox(height: 12),
                TextField(controller: beschreibungCtrl, decoration: const InputDecoration(labelText: 'Fehlerbeschreibung', border: OutlineInputBorder()), maxLines: 3),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: OutlinedButton.icon(
                    onPressed: () async { final d = await showDatePicker(context: context, initialDate: eingangsdatum, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365))); if (d != null) setDlgState(() => eingangsdatum = d); },
                    icon: const Icon(Icons.calendar_today), label: Text('Eingang: ${DateFormat('dd.MM.yyyy').format(eingangsdatum)}'))),
                  const SizedBox(width: 12),
                  Expanded(child: DropdownButtonFormField<String>(value: uebergabe, decoration: const InputDecoration(labelText: 'Übergabe', border: OutlineInputBorder()),
                    items: _uebergabeMap.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(), onChanged: (val) => setDlgState(() => uebergabe = val!))),
                ]),
                const SizedBox(height: 12),
                SwitchListTile(value: kostenlos, onChanged: (val) => setDlgState(() => kostenlos = val), title: const Text('Kostenlos'), activeColor: Colors.green, contentPadding: EdgeInsets.zero),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            ElevatedButton.icon(
              onPressed: () async {
                await widget.apiService.reparaturAction(widget.userId, 'create', {
                  'geraet': geraet, 'marke': markeCtrl.text.trim(), 'modell': modellCtrl.text.trim(),
                  'seriennummer': snCtrl.text.trim(), 'beschreibung': beschreibungCtrl.text.trim(),
                  'uebergabe': uebergabe, 'kostenlos': kostenlos ? 1 : 0, 'eingangsdatum': DateFormat('yyyy-MM-dd').format(eingangsdatum),
                });
                if (ctx.mounted) Navigator.pop(ctx);
                _loadData();
              },
              icon: const Icon(Icons.check), label: const Text('Erstellen'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange.shade700, foregroundColor: Colors.white)),
          ],
        ),
      ),
    );
    markeCtrl.dispose(); modellCtrl.dispose(); snCtrl.dispose(); beschreibungCtrl.dispose();
  }

  Future<void> _showVorfallDetailDialog(Map<String, dynamic> vorfall) async {
    await showDialog(
      context: context,
      builder: (ctx) => _VorfallDetailDialog(
        apiService: widget.apiService,
        userId: widget.userId,
        vorfall: vorfall,
        onChanged: _loadData,
      ),
    );
  }
}

class _VorfallDetailDialog extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final Map<String, dynamic> vorfall;
  final VoidCallback onChanged;

  const _VorfallDetailDialog({required this.apiService, required this.userId, required this.vorfall, required this.onChanged});

  @override
  State<_VorfallDetailDialog> createState() => _VorfallDetailDialogState();
}

class _VorfallDetailDialogState extends State<_VorfallDetailDialog> with TickerProviderStateMixin {
  late TabController _tabCtrl;
  late Map<String, dynamic> _data;
  List<Map<String, dynamic>> _verlauf = [];
  List<Map<String, dynamic>> _korr = [];
  bool _isLoadingVerlauf = true;
  bool _isLoadingKorr = true;
  bool _isEditing = false;

  static const _statusMap = _ReparaturContentState._statusMap;
  static const _uebergabeMap = _ReparaturContentState._uebergabeMap;
  static const _geraetTypen = _ReparaturContentState._geraetTypen;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _data = Map<String, dynamic>.from(widget.vorfall);
    _loadVerlauf();
    _loadKorr();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadVerlauf() async {
    final id = _data['id'] is int ? _data['id'] : int.parse(_data['id'].toString());
    final result = await widget.apiService.reparaturAction(widget.userId, 'verlauf_list', {'vorfall_id': id});
    if (mounted && result['success'] == true) {
      setState(() { _verlauf = List<Map<String, dynamic>>.from(result['verlauf'] ?? []); _isLoadingVerlauf = false; });
    } else if (mounted) setState(() => _isLoadingVerlauf = false);
  }

  Future<void> _loadKorr() async {
    final id = _data['id'] is int ? _data['id'] : int.parse(_data['id'].toString());
    final result = await widget.apiService.reparaturAction(widget.userId, 'korr_list', {'vorfall_id': id});
    if (mounted && result['success'] == true) {
      setState(() { _korr = List<Map<String, dynamic>>.from(result['korrespondenz'] ?? []); _isLoadingKorr = false; });
    } else if (mounted) setState(() => _isLoadingKorr = false);
  }

  @override
  Widget build(BuildContext context) {
    final status = _data['status'] ?? 'eingegangen';
    final (statusLabel, statusColor) = _statusMap[status] ?? ('Unbekannt', Colors.grey);
    final geraet = _data['geraet'] ?? '';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 750,
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.deepOrange.shade700, borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16))),
              child: Row(children: [
                Icon(_ReparaturContentState.geraetIcon(geraet), color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('$geraet${_data['marke']?.toString().isNotEmpty == true ? ' — ${_data['marke']}' : ''}',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                  child: Text(statusLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
                ),
                const SizedBox(width: 8),
                IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
              ]),
            ),
            TabBar(
              controller: _tabCtrl,
              labelColor: Colors.deepOrange.shade700,
              tabs: const [
                Tab(icon: Icon(Icons.info_outline), text: 'Details'),
                Tab(icon: Icon(Icons.timeline), text: 'Verlauf'),
                Tab(icon: Icon(Icons.mail_outline), text: 'Korrespondenz'),
                Tab(icon: Icon(Icons.inventory_2), text: 'Produkt'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [_buildDetailsTab(), _buildVerlaufTab(), _buildKorrTab(), _buildProduktTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsTab() {
    if (!_isEditing) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Spacer(),
            OutlinedButton.icon(icon: const Icon(Icons.edit, size: 18), label: const Text('Bearbeiten'),
              onPressed: () => setState(() => _isEditing = true)),
            const SizedBox(width: 8),
            OutlinedButton.icon(icon: Icon(Icons.delete, size: 18, color: Colors.red.shade400), label: Text('Löschen', style: TextStyle(color: Colors.red.shade400)),
              onPressed: () async {
                final confirm = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
                  title: const Text('Löschen?'), actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
                    TextButton(onPressed: () => Navigator.pop(c, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Löschen')),
                  ]));
                if (confirm != true) return;
                final id = _data['id'] is int ? _data['id'] : int.parse(_data['id'].toString());
                await widget.apiService.reparaturAction(widget.userId, 'delete', {'vorfall_id': id});
                widget.onChanged();
                if (mounted) Navigator.pop(context);
              }),
          ]),
          const SizedBox(height: 8),
          _infoRow('Status', _statusMap[_data['status']]?.$1 ?? _data['status'] ?? ''),
          _infoRow('Eingangsdatum', _data['eingangsdatum'] ?? ''),
          _infoRow('Übergabe', _uebergabeMap[_data['uebergabe']] ?? ''),
          _infoRow('Kostenlos', _data['kostenlos'].toString() == '1' ? 'Ja' : 'Nein'),
          if (_data['kosten']?.toString().isNotEmpty == true) _infoRow('Kosten', '${_data['kosten']} €'),
          if (_data['beschreibung']?.toString().isNotEmpty == true) _infoRow('Fehlerbeschreibung', _data['beschreibung']),
          if (_data['fertigdatum'] != null) _infoRow('Fertigdatum', _data['fertigdatum']),
          if (_data['abgeholt_datum'] != null) _infoRow('Abgeholt am', _data['abgeholt_datum']),
          if (_data['notizen']?.toString().isNotEmpty == true) _infoRow('Notizen', _data['notizen']),
        ]),
      );
    }

    return _DetailsEditForm(data: _data, apiService: widget.apiService, userId: widget.userId, onSaved: (updated) {
      setState(() { _data = updated; _isEditing = false; });
      widget.onChanged();
      _loadVerlauf();
    }, onCancel: () => setState(() => _isEditing = false));
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 140, child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.w600))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
      ]),
    );
  }

  Widget _buildVerlaufTab() {
    final eintragCtrl = TextEditingController();
    return StatefulBuilder(
      builder: (context, setTabState) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(child: TextField(controller: eintragCtrl, decoration: const InputDecoration(hintText: 'Neuer Eintrag...', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)))),
              const SizedBox(width: 8),
              IconButton(icon: Icon(Icons.add_circle, color: Colors.green.shade700, size: 32), onPressed: () async {
                final text = eintragCtrl.text.trim();
                if (text.isEmpty) return;
                final id = _data['id'] is int ? _data['id'] : int.parse(_data['id'].toString());
                await widget.apiService.reparaturAction(widget.userId, 'verlauf_add', {'vorfall_id': id, 'eintrag': text});
                eintragCtrl.clear();
                _loadVerlauf();
              }),
            ]),
          ),
          Expanded(
            child: _isLoadingVerlauf
                ? const Center(child: CircularProgressIndicator())
                : _verlauf.isEmpty
                    ? Center(child: Text('Keine Einträge', style: TextStyle(color: Colors.grey.shade500)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _verlauf.length,
                        itemBuilder: (_, i) {
                          final v = _verlauf[i];
                          final dt = DateTime.tryParse(v['created_at'] ?? '');
                          return ListTile(
                            leading: Icon(Icons.circle, size: 10, color: Colors.deepOrange.shade300),
                            title: Text(v['eintrag'] ?? ''),
                            subtitle: dt != null ? Text(DateFormat('dd.MM.yyyy HH:mm').format(dt), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)) : null,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildKorrTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () => _addKorrespondenz(),
              icon: const Icon(Icons.add), label: const Text('Neue Korrespondenz'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange.shade700, foregroundColor: Colors.white)),
          ]),
        ),
        Expanded(
          child: _isLoadingKorr
              ? const Center(child: CircularProgressIndicator())
              : _korr.isEmpty
                  ? Center(child: Text('Keine Korrespondenz', style: TextStyle(color: Colors.grey.shade500)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _korr.length,
                      itemBuilder: (_, i) {
                        final k = _korr[i];
                        final isEingehend = k['typ'] == 'eingehend';
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ExpansionTile(
                            leading: Icon(isEingehend ? Icons.call_received : Icons.call_made, color: isEingehend ? Colors.blue : Colors.green),
                            title: Text(k['betreff'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('${k['datum'] ?? ''} • ${isEingehend ? 'Eingehend' : 'Ausgehend'}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            trailing: IconButton(
                              icon: Icon(Icons.delete_outline, size: 20, color: Colors.red.shade400),
                              onPressed: () async {
                                final kid = k['id'] is int ? k['id'] : int.parse(k['id'].toString());
                                await widget.apiService.reparaturAction(widget.userId, 'korr_delete', {'korr_id': kid});
                                _loadKorr();
                              },
                            ),
                            children: [
                              if (k['inhalt']?.toString().isNotEmpty == true)
                                Padding(padding: const EdgeInsets.all(16), child: Text(k['inhalt'])),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                child: KorrAttachmentsWidget(
                                  apiService: widget.apiService,
                                  korrespondenzId: k['id'] is int ? k['id'] : int.parse(k['id'].toString()),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Future<void> _addKorrespondenz() async {
    final betreffCtrl = TextEditingController();
    final inhaltCtrl = TextEditingController();
    String typ = 'ausgehend';
    DateTime datum = DateTime.now();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Text('Neue Korrespondenz'),
          content: SizedBox(
            width: 450,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: betreffCtrl, decoration: const InputDecoration(labelText: 'Betreff *', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: inhaltCtrl, decoration: const InputDecoration(labelText: 'Inhalt', border: OutlineInputBorder()), maxLines: 4),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: OutlinedButton.icon(
                  onPressed: () async { final d = await showDatePicker(context: context, initialDate: datum, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365))); if (d != null) setDlgState(() => datum = d); },
                  icon: const Icon(Icons.calendar_today), label: Text(DateFormat('dd.MM.yyyy').format(datum)))),
                const SizedBox(width: 12),
                Expanded(child: DropdownButtonFormField<String>(value: typ, decoration: const InputDecoration(labelText: 'Typ', border: OutlineInputBorder()),
                  items: const [DropdownMenuItem(value: 'eingehend', child: Text('Eingehend')), DropdownMenuItem(value: 'ausgehend', child: Text('Ausgehend'))],
                  onChanged: (val) => setDlgState(() => typ = val!))),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            ElevatedButton(onPressed: () async {
              if (betreffCtrl.text.trim().isEmpty) return;
              final id = _data['id'] is int ? _data['id'] : int.parse(_data['id'].toString());
              await widget.apiService.reparaturAction(widget.userId, 'korr_add', {
                'vorfall_id': id, 'betreff': betreffCtrl.text.trim(), 'inhalt': inhaltCtrl.text.trim(),
                'datum': DateFormat('yyyy-MM-dd').format(datum), 'typ': typ,
              });
              if (ctx.mounted) Navigator.pop(ctx);
              _loadKorr();
            }, child: const Text('Speichern')),
          ],
        ),
      ),
    );
    betreffCtrl.dispose(); inhaltCtrl.dispose();
  }

  Widget _buildProduktTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(_ReparaturContentState.geraetIcon(_data['geraet'] ?? ''), size: 48, color: Colors.deepOrange.shade700),
                const SizedBox(width: 16),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_data['geraet'] ?? '', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  if (_data['marke']?.toString().isNotEmpty == true || _data['modell']?.toString().isNotEmpty == true)
                    Text('${_data['marke'] ?? ''} ${_data['modell'] ?? ''}'.trim(), style: TextStyle(fontSize: 16, color: Colors.grey.shade700)),
                ]),
              ]),
              const Divider(height: 24),
              if (_data['seriennummer']?.toString().isNotEmpty == true) _infoRow('Seriennummer', _data['seriennummer']),
              _infoRow('Übergabe', _uebergabeMap[_data['uebergabe']] ?? ''),
              _infoRow('Eingangsdatum', _data['eingangsdatum'] ?? ''),
              _infoRow('Kostenlos', _data['kostenlos'].toString() == '1' ? 'Ja' : 'Nein'),
              if (_data['kosten']?.toString().isNotEmpty == true) _infoRow('Kosten', '${_data['kosten']} €'),
              if (_data['beschreibung']?.toString().isNotEmpty == true) ...[
                const Divider(height: 24),
                Text('Fehlerbeschreibung', style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(_data['beschreibung'] ?? '', style: const TextStyle(fontSize: 14)),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

class _DetailsEditForm extends StatefulWidget {
  final Map<String, dynamic> data;
  final ApiService apiService;
  final int userId;
  final Function(Map<String, dynamic>) onSaved;
  final VoidCallback onCancel;

  const _DetailsEditForm({required this.data, required this.apiService, required this.userId, required this.onSaved, required this.onCancel});

  @override
  State<_DetailsEditForm> createState() => _DetailsEditFormState();
}

class _DetailsEditFormState extends State<_DetailsEditForm> {
  late String _geraet, _uebergabe, _status;
  late bool _kostenlos;
  late DateTime _eingangsdatum;
  DateTime? _fertigdatum, _abgeholtDatum;
  late TextEditingController _markeCtrl, _modellCtrl, _snCtrl, _beschreibungCtrl, _kostenCtrl, _notizenCtrl;

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    _geraet = _ReparaturContentState._geraetTypen.contains(d['geraet']) ? d['geraet'] : 'Sonstiges';
    _uebergabe = d['uebergabe'] ?? 'persoenlich';
    _status = d['status'] ?? 'eingegangen';
    _kostenlos = d['kostenlos'].toString() == '1';
    _eingangsdatum = DateTime.tryParse(d['eingangsdatum'] ?? '') ?? DateTime.now();
    _fertigdatum = d['fertigdatum'] != null ? DateTime.tryParse(d['fertigdatum']) : null;
    _abgeholtDatum = d['abgeholt_datum'] != null ? DateTime.tryParse(d['abgeholt_datum']) : null;
    _markeCtrl = TextEditingController(text: d['marke'] ?? '');
    _modellCtrl = TextEditingController(text: d['modell'] ?? '');
    _snCtrl = TextEditingController(text: d['seriennummer'] ?? '');
    _beschreibungCtrl = TextEditingController(text: d['beschreibung'] ?? '');
    _kostenCtrl = TextEditingController(text: d['kosten'] ?? '');
    _notizenCtrl = TextEditingController(text: d['notizen'] ?? '');
  }

  @override
  void dispose() {
    _markeCtrl.dispose(); _modellCtrl.dispose(); _snCtrl.dispose();
    _beschreibungCtrl.dispose(); _kostenCtrl.dispose(); _notizenCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        DropdownButtonFormField<String>(value: _status, decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
          items: _ReparaturContentState._statusMap.entries.map((e) => DropdownMenuItem(value: e.key,
            child: Row(children: [Container(width: 10, height: 10, decoration: BoxDecoration(color: e.value.$2, shape: BoxShape.circle)), const SizedBox(width: 8), Text(e.value.$1)]))).toList(),
          onChanged: (val) => setState(() => _status = val!)),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(value: _geraet, decoration: const InputDecoration(labelText: 'Gerät', border: OutlineInputBorder()),
          items: _ReparaturContentState._geraetTypen.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(), onChanged: (val) => setState(() => _geraet = val!)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: _markeCtrl, decoration: const InputDecoration(labelText: 'Marke', border: OutlineInputBorder()))),
          const SizedBox(width: 12),
          Expanded(child: TextField(controller: _modellCtrl, decoration: const InputDecoration(labelText: 'Modell', border: OutlineInputBorder()))),
        ]),
        const SizedBox(height: 12),
        TextField(controller: _snCtrl, decoration: const InputDecoration(labelText: 'Seriennummer', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: _beschreibungCtrl, decoration: const InputDecoration(labelText: 'Fehlerbeschreibung', border: OutlineInputBorder()), maxLines: 3),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: () async { final d = await showDatePicker(context: context, initialDate: _eingangsdatum, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365))); if (d != null) setState(() => _eingangsdatum = d); },
            icon: const Icon(Icons.calendar_today), label: Text('Eingang: ${DateFormat('dd.MM.yyyy').format(_eingangsdatum)}'))),
          const SizedBox(width: 12),
          Expanded(child: DropdownButtonFormField<String>(value: _uebergabe, decoration: const InputDecoration(labelText: 'Übergabe', border: OutlineInputBorder()),
            items: _ReparaturContentState._uebergabeMap.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(), onChanged: (val) => setState(() => _uebergabe = val!))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: () async { final d = await showDatePicker(context: context, initialDate: _fertigdatum ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365))); if (d != null) setState(() => _fertigdatum = d); },
            icon: const Icon(Icons.check_circle_outline), label: Text(_fertigdatum != null ? 'Fertig: ${DateFormat('dd.MM.yyyy').format(_fertigdatum!)}' : 'Fertigdatum'))),
          const SizedBox(width: 12),
          Expanded(child: OutlinedButton.icon(
            onPressed: () async { final d = await showDatePicker(context: context, initialDate: _abgeholtDatum ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365))); if (d != null) setState(() => _abgeholtDatum = d); },
            icon: const Icon(Icons.inventory), label: Text(_abgeholtDatum != null ? 'Abgeholt: ${DateFormat('dd.MM.yyyy').format(_abgeholtDatum!)}' : 'Abholdatum'))),
        ]),
        const SizedBox(height: 12),
        SwitchListTile(value: _kostenlos, onChanged: (val) => setState(() => _kostenlos = val), title: const Text('Kostenlos'), activeColor: Colors.green, contentPadding: EdgeInsets.zero),
        if (!_kostenlos) ...[const SizedBox(height: 12), TextField(controller: _kostenCtrl, decoration: const InputDecoration(labelText: 'Kosten (€)', border: OutlineInputBorder()))],
        const SizedBox(height: 12),
        TextField(controller: _notizenCtrl, decoration: const InputDecoration(labelText: 'Notizen', border: OutlineInputBorder()), maxLines: 2),
        const SizedBox(height: 16),
        Row(children: [
          TextButton(onPressed: widget.onCancel, child: const Text('Abbrechen')),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () async {
              final id = widget.data['id'] is int ? widget.data['id'] : int.parse(widget.data['id'].toString());
              final updated = {
                'vorfall_id': id, 'geraet': _geraet, 'marke': _markeCtrl.text.trim(), 'modell': _modellCtrl.text.trim(),
                'seriennummer': _snCtrl.text.trim(), 'beschreibung': _beschreibungCtrl.text.trim(), 'uebergabe': _uebergabe,
                'kostenlos': _kostenlos ? 1 : 0, 'kosten': _kostenCtrl.text.trim(), 'status': _status,
                'eingangsdatum': DateFormat('yyyy-MM-dd').format(_eingangsdatum),
                'fertigdatum': _fertigdatum != null ? DateFormat('yyyy-MM-dd').format(_fertigdatum!) : null,
                'abgeholt_datum': _abgeholtDatum != null ? DateFormat('yyyy-MM-dd').format(_abgeholtDatum!) : null,
                'notizen': _notizenCtrl.text.trim(),
              };
              await widget.apiService.reparaturAction(widget.userId, 'update', updated);
              final refreshed = await widget.apiService.reparaturAction(widget.userId, 'detail', {'vorfall_id': id});
              if (refreshed['success'] == true) {
                widget.onSaved(Map<String, dynamic>.from(refreshed['vorfall']));
              }
            },
            icon: const Icon(Icons.check), label: const Text('Speichern'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange.shade700, foregroundColor: Colors.white)),
        ]),
      ]),
    );
  }
}
