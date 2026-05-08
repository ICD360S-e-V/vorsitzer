import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'korrespondenz_attachments_widget.dart';

class BehordeJobcenterContent extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  const BehordeJobcenterContent({super.key, required this.apiService, required this.userId});
  @override
  State<BehordeJobcenterContent> createState() => _BehordeJobcenterContentState();
}

class _BehordeJobcenterContentState extends State<BehordeJobcenterContent> with TickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic> _data = {};
  List<Map<String, dynamic>> _antraege = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final res = await widget.apiService.getJobcenterData(widget.userId);
      if (res['success'] == true) {
        _data = Map<String, dynamic>.from(res['data'] ?? {});
        _antraege = (res['antraege'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      }
    } catch (e) {
      debugPrint('[Jobcenter] load error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveData(Map<String, String> fields) async {
    try {
      await widget.apiService.jobcenterAction(widget.userId, {'action': 'save_data', 'data': fields});
      setState(() { for (final e in fields.entries) { _data[e.key] = e.value; } });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      TabBar(controller: _tabController, labelColor: Colors.red.shade800, unselectedLabelColor: Colors.grey, indicatorColor: Colors.red.shade700, isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: (_data['stammdaten.selected_amt_name'] ?? '').isNotEmpty ? Colors.green : Colors.red), const SizedBox(width: 5), const Text('Zuständiges Jobcenter')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: _antraege.isNotEmpty ? Colors.green : Colors.red), const SizedBox(width: 5), const Text('Antrag')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: (_data['stammdaten.kundennummer'] ?? '').isNotEmpty ? Colors.green : Colors.red), const SizedBox(width: 5), const Text('Stammdaten')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: (_data['vermittler.name'] ?? '').isNotEmpty ? Colors.green : Colors.red), const SizedBox(width: 5), const Text('Arbeitsvermittler')])),
      ]),
      Expanded(child: TabBarView(controller: _tabController, children: [
        _JobcenterStammdatenTab(data: _data, apiService: widget.apiService, userId: widget.userId, onSave: _saveData),
        _JobcenterAntragTab(antraege: _antraege, apiService: widget.apiService, userId: widget.userId, onReload: _load),
        _JobcenterStammdatenFieldsTab(data: _data, apiService: widget.apiService, userId: widget.userId, onSave: _saveData),
        _JobcenterArbeitsvermittlerTab(data: _data, apiService: widget.apiService, userId: widget.userId, onSave: _saveData),
      ])),
    ]);
  }
}

// ==================== TAB 1: Zuständiges Jobcenter ====================

class _JobcenterStammdatenTab extends StatefulWidget {
  final Map<String, dynamic> data;
  final ApiService apiService;
  final int userId;
  final Future<void> Function(Map<String, String>) onSave;
  const _JobcenterStammdatenTab({required this.data, required this.apiService, required this.userId, required this.onSave});
  @override
  State<_JobcenterStammdatenTab> createState() => _JobcenterStammdatenTabState();
}

class _JobcenterStammdatenTabState extends State<_JobcenterStammdatenTab> {
  Map<String, dynamic>? _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    final selName = d['stammdaten.selected_amt_name'] ?? '';
    if (selName.isNotEmpty) _selected = {'name': selName, 'strasse': d['stammdaten.selected_amt_adresse'] ?? '', 'ort': d['stammdaten.selected_amt_ort'] ?? '', 'telefon': d['stammdaten.selected_amt_telefon'] ?? '', 'fax': d['stammdaten.selected_amt_fax'] ?? '', 'email': d['stammdaten.selected_amt_email'] ?? '', 'website': d['stammdaten.selected_amt_website'] ?? '', 'oeffnungszeiten': d['stammdaten.selected_amt_oeffnungszeiten'] ?? ''};
  }

  @override
  void dispose() { super.dispose(); }

  void _openSearch() {
    final searchC = TextEditingController();
    List<Map<String, dynamic>> all = [];
    List<Map<String, dynamic>> filtered = [];
    bool loading = true;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) {
      if (loading && all.isEmpty) {
        widget.apiService.searchJobcenterDatenbank('').then((res) {
          if (res['success'] == true) all = (res['results'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
          filtered = List.from(all);
          setDlg(() => loading = false);
        }).catchError((_) => setDlg(() => loading = false));
      }
      void filterList(String q) {
        if (q.isEmpty) { setDlg(() => filtered = List.from(all)); return; }
        final lower = q.toLowerCase();
        setDlg(() => filtered = all.where((s) => (s['name']?.toString() ?? '').toLowerCase().contains(lower) || (s['ort']?.toString() ?? '').toLowerCase().contains(lower)).toList());
      }
      return AlertDialog(
        title: Row(children: [Icon(Icons.search, color: Colors.red.shade700), const SizedBox(width: 8), const Text('Jobcenter auswählen', style: TextStyle(fontSize: 16))]),
        content: SizedBox(width: 500, height: 400, child: Column(children: [
          TextField(controller: searchC, autofocus: true, decoration: InputDecoration(hintText: 'Filter...', prefixIcon: const Icon(Icons.search), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onChanged: filterList),
          const SizedBox(height: 12),
          if (loading) const LinearProgressIndicator(),
          Expanded(child: filtered.isEmpty
            ? Center(child: Text(loading ? '' : 'Keine Jobcenter gefunden', style: TextStyle(color: Colors.grey.shade400)))
            : ListView.builder(itemCount: filtered.length, itemBuilder: (_, i) {
                final s = filtered[i];
                return Card(margin: const EdgeInsets.only(bottom: 6), child: ListTile(
                  leading: CircleAvatar(backgroundColor: Colors.red.shade100, child: Icon(Icons.business_center, color: Colors.red.shade700, size: 20)),
                  title: Text(s['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text('${s['strasse'] ?? ''}, ${s['plz'] ?? ''} ${s['ort'] ?? ''}', style: const TextStyle(fontSize: 11)),
                  trailing: Icon(Icons.check_circle_outline, color: Colors.red.shade400),
                  onTap: () { Navigator.pop(ctx); _selectAndSave(s); },
                ));
              })),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen'))],
      );
    }));
  }

  Future<void> _selectAndSave(Map<String, dynamic> s) async {
    setState(() { _selected = s; _saving = true; });
    await widget.onSave({
      'stammdaten.selected_amt_name': s['name']?.toString() ?? '',
      'stammdaten.selected_amt_adresse': s['strasse']?.toString() ?? '',
      'stammdaten.selected_amt_ort': '${s['plz'] ?? ''} ${s['ort'] ?? ''}'.trim(),
      'stammdaten.selected_amt_telefon': s['telefon']?.toString() ?? '',
      'stammdaten.selected_amt_fax': s['fax']?.toString() ?? '',
      'stammdaten.selected_amt_email': s['email']?.toString() ?? '',
      'stammdaten.selected_amt_website': s['website']?.toString() ?? '',
      'stammdaten.selected_amt_oeffnungszeiten': s['oeffnungszeiten']?.toString() ?? '',
    });
    if (mounted) setState(() => _saving = false);
  }

  Widget _infoRow(IconData icon, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [
      Icon(icon, size: 16, color: Colors.red.shade400),
      const SizedBox(width: 8),
      SizedBox(width: 70, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    if (_selected == null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.business_center, size: 64, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        Text('Kein Jobcenter ausgewählt', style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
        const SizedBox(height: 16),
        ElevatedButton.icon(onPressed: _openSearch, icon: const Icon(Icons.search, size: 20), label: const Text('Jobcenter suchen'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12))),
      ]));
    }
    final s = _selected!;
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Zuständiges Jobcenter', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
        const Spacer(),
        TextButton.icon(icon: const Icon(Icons.swap_horiz, size: 16), label: const Text('Ändern', style: TextStyle(fontSize: 12)), onPressed: _openSearch),
      ]),
      const SizedBox(height: 12),
      Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.shade200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 48, height: 48, decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.business_center, color: Colors.red.shade700, size: 28)),
            const SizedBox(width: 14),
            Expanded(child: Text(s['name']?.toString() ?? '', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red.shade800))),
            IconButton(icon: Icon(Icons.close, color: Colors.red.shade400), onPressed: () => setState(() => _selected = null)),
          ]),
          const Divider(height: 20),
          _infoRow(Icons.location_on, 'Adresse', '${s['strasse'] ?? ''}, ${s['ort'] ?? ''}'.trim()),
          _infoRow(Icons.phone, 'Telefon', s['telefon']?.toString() ?? ''),
          _infoRow(Icons.fax, 'Fax', s['fax']?.toString() ?? ''),
          _infoRow(Icons.email, 'E-Mail', s['email']?.toString() ?? ''),
          _infoRow(Icons.language, 'Website', s['website']?.toString() ?? ''),
          if ((s['oeffnungszeiten']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.shade100)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.access_time, size: 16, color: Colors.red.shade400),
                const SizedBox(width: 8),
                Expanded(child: Text(s['oeffnungszeiten'].toString(), style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
              ])),
          ],
        ]),
      ),
    ]));
  }
}

// ==================== TAB 2: Antrag ====================

class _JobcenterAntragTab extends StatefulWidget {
  final List<Map<String, dynamic>> antraege;
  final ApiService apiService;
  final int userId;
  final Future<void> Function() onReload;
  const _JobcenterAntragTab({required this.antraege, required this.apiService, required this.userId, required this.onReload});
  @override
  State<_JobcenterAntragTab> createState() => _JobcenterAntragTabState();
}

class _JobcenterAntragTabState extends State<_JobcenterAntragTab> {
  late List<Map<String, dynamic>> _antraege;

  @override
  void initState() {
    super.initState();
    _antraege = List.from(widget.antraege);
  }

  @override
  void didUpdateWidget(covariant _JobcenterAntragTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _antraege = List.from(widget.antraege);
  }

  static const _artLabels = {
    'erstantrag': 'Erstantrag',
    'weiterbewilligung': 'Weiterbewilligungsantrag (WBA)',
    'aenderungsantrag': 'Änderungsantrag',
    'mehrbedarf': 'Antrag auf Mehrbedarf',
    'erstausstattung': 'Antrag auf Erstausstattung',
    'umzugskosten': 'Antrag auf Umzugskosten',
    'but': 'Bildung und Teilhabe (BuT)',
    'ueberpruefung': 'Überprüfungsantrag (§44 SGB X)',
  };

  static const _statusLabels = {
    'eingereicht': 'Eingereicht',
    'in_bearbeitung': 'In Bearbeitung',
    'unterlagen_nachgefordert': 'Unterlagen nachgefordert',
    'bewilligt': 'Bewilligt',
    'teilweise_bewilligt': 'Teilweise bewilligt',
    'abgelehnt': 'Abgelehnt',
    'widerspruch': 'Widerspruch eingelegt',
    'klage': 'Klage beim Sozialgericht',
    'zurueckgezogen': 'Zurückgezogen',
  };

  static const _statusColors = {
    'eingereicht': Colors.blue,
    'in_bearbeitung': Colors.orange,
    'unterlagen_nachgefordert': Colors.amber,
    'bewilligt': Colors.green,
    'teilweise_bewilligt': Colors.teal,
    'abgelehnt': Colors.red,
    'widerspruch': Colors.purple,
    'klage': Colors.deepPurple,
    'zurueckgezogen': Colors.grey,
  };

  void _addAntrag() {
    String art = 'erstantrag';
    String status = 'eingereicht';
    final datumC = TextEditingController();
    final aktenzeichenC = TextEditingController();
    final notizC = TextEditingController();
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) => AlertDialog(
      title: Row(children: [Icon(Icons.add_circle, size: 18, color: Colors.red.shade700), const SizedBox(width: 8), const Text('Neuer Antrag', style: TextStyle(fontSize: 15))]),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(value: art, decoration: InputDecoration(labelText: 'Art', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          items: _artLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (v) => setDlg(() => art = v ?? art)),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(value: status, decoration: InputDecoration(labelText: 'Status', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          items: _statusLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (v) => setDlg(() => status = v ?? status)),
        const SizedBox(height: 10),
        TextField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', isDense: true, prefixIcon: const Icon(Icons.calendar_today, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          onTap: () async { final d = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (d != null) datumC.text = '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}'; }),
        const SizedBox(height: 10),
        TextField(controller: aktenzeichenC, decoration: InputDecoration(labelText: 'Aktenzeichen', isDense: true, prefixIcon: const Icon(Icons.bookmark, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 10),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () async {
          Navigator.pop(ctx);
          await widget.apiService.jobcenterAction(widget.userId, {'action': 'save_antrag', 'antrag': {'art': art, 'status': status, 'datum': datumC.text, 'aktenzeichen': aktenzeichenC.text, 'notiz': notizC.text}});
          await widget.onReload();
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white), child: const Text('Hinzufügen')),
      ],
    )));
  }

  void _openDetail(Map<String, dynamic> antrag) {
    showDialog(context: context, barrierDismissible: false, builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: SizedBox(width: 700, height: 550, child: _AntragDetailModal(antrag: antrag, apiService: widget.apiService, userId: widget.userId, onReload: widget.onReload)),
    ));
  }

  Future<void> _delete(Map<String, dynamic> a) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Antrag löschen?', style: TextStyle(fontSize: 15)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('Löschen'))],
    ));
    if (ok != true) return;
    await widget.apiService.jobcenterAction(widget.userId, {'action': 'delete_antrag', 'id': a['id']});
    await widget.onReload();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Icon(Icons.description, color: Colors.red.shade700),
        const SizedBox(width: 8),
        Text('Anträge (${_antraege.length})', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.red.shade800)),
        const Spacer(),
        ElevatedButton.icon(onPressed: _addAntrag, icon: const Icon(Icons.add, size: 16), label: const Text('Neuer Antrag', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white)),
      ])),
      Expanded(child: _antraege.isEmpty
        ? Center(child: Text('Keine Anträge vorhanden', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _antraege.length, itemBuilder: (ctx, i) {
            final a = _antraege[i];
            final art = a['art']?.toString() ?? '';
            final status = a['status']?.toString() ?? '';
            final color = _statusColors[status] ?? Colors.grey;
            return Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(
              onTap: () => _openDetail(a),
              leading: CircleAvatar(backgroundColor: color.shade100, child: Icon(Icons.description, color: color.shade700, size: 20)),
              title: Text(_artLabels[art] ?? art, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: Text('${a['datum'] ?? ''} · ${a['aktenzeichen'] ?? ''}', style: const TextStyle(fontSize: 11)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: color.shade100, borderRadius: BorderRadius.circular(12)),
                  child: Text(_statusLabels[status] ?? status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color.shade800))),
                const SizedBox(width: 4),
                IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade300), onPressed: () => _delete(a)),
              ]),
            ));
          })),
    ]);
  }
}

// ==================== ANTRAG DETAIL MODAL ====================

class _AntragDetailModal extends StatefulWidget {
  final Map<String, dynamic> antrag;
  final ApiService apiService;
  final int userId;
  final Future<void> Function() onReload;
  const _AntragDetailModal({required this.antrag, required this.apiService, required this.userId, required this.onReload});
  @override
  State<_AntragDetailModal> createState() => _AntragDetailModalState();
}

class _AntragDetailModalState extends State<_AntragDetailModal> with TickerProviderStateMixin {
  late TabController _tabC;

  @override
  void initState() {
    super.initState();
    _tabC = TabController(length: 7, vsync: this);
  }

  @override
  void dispose() {
    _tabC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final art = _JobcenterAntragTabState._artLabels[widget.antrag['art']] ?? widget.antrag['art']?.toString() ?? '';
    return Column(children: [
      Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
        child: Row(children: [
          Icon(Icons.description, color: Colors.red.shade700),
          const SizedBox(width: 8),
          Expanded(child: Text(art, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.red.shade800), overflow: TextOverflow.ellipsis)),
          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        ])),
      TabBar(controller: _tabC, labelColor: Colors.red.shade800, unselectedLabelColor: Colors.grey, indicatorColor: Colors.red.shade700, isScrollable: true, tabAlignment: TabAlignment.start, tabs: const [
        Tab(text: 'Details'),
        Tab(text: 'Korrespondenz'),
        Tab(text: 'Terminen'),
        Tab(text: 'Bewilligungsbescheid'),
        Tab(text: 'EGV'),
        Tab(text: 'Sanktionen'),
        Tab(text: 'Begutachtung'),
      ]),
      Expanded(child: TabBarView(controller: _tabC, children: [
        _AntragDetailsTab(antrag: widget.antrag, apiService: widget.apiService, userId: widget.userId, onReload: widget.onReload),
        _AntragKorrTab(antragId: widget.antrag['id'] as int, apiService: widget.apiService, userId: widget.userId),
        _AntragTerminTab(antragId: widget.antrag['id'] as int, apiService: widget.apiService, userId: widget.userId),
        _AntragBescheidTab(antrag: widget.antrag, apiService: widget.apiService, userId: widget.userId, onReload: widget.onReload),
        _AntragEgvTab(antrag: widget.antrag, apiService: widget.apiService, userId: widget.userId, onReload: widget.onReload),
        _AntragSanktionenTab(antrag: widget.antrag, apiService: widget.apiService, userId: widget.userId, onReload: widget.onReload),
        _AntragBegutachtungTab(antrag: widget.antrag, apiService: widget.apiService, userId: widget.userId, onReload: widget.onReload),
      ])),
    ]);
  }
}

// ==================== ANTRAG DETAILS TAB ====================

class _AntragDetailsTab extends StatefulWidget {
  final Map<String, dynamic> antrag;
  final ApiService apiService;
  final int userId;
  final Future<void> Function() onReload;
  const _AntragDetailsTab({required this.antrag, required this.apiService, required this.userId, required this.onReload});
  @override
  State<_AntragDetailsTab> createState() => _AntragDetailsTabState();
}

class _AntragDetailsTabState extends State<_AntragDetailsTab> {
  late String _art, _status;
  late TextEditingController _datumC, _aktenzeichenC, _notizC;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final a = widget.antrag;
    _art = a['art']?.toString() ?? 'erstantrag';
    _status = a['status']?.toString() ?? 'eingereicht';
    _datumC = TextEditingController(text: a['datum']?.toString() ?? '');
    _aktenzeichenC = TextEditingController(text: a['aktenzeichen']?.toString() ?? '');
    _notizC = TextEditingController(text: a['notiz']?.toString() ?? '');
    // Bewilligungsbescheid, EGV, Sanktionen, Begutachtung moved to own tabs
  }

  @override
  @override
  void dispose() { _datumC.dispose(); _aktenzeichenC.dispose(); _notizC.dispose(); super.dispose(); }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.apiService.jobcenterAction(widget.userId, {
      'action': 'save_antrag',
      'antrag': {
        ...widget.antrag,
        'art': _art, 'status': _status, 'datum': _datumC.text, 'aktenzeichen': _aktenzeichenC.text, 'notiz': _notizC.text,
      },
    });
    await widget.onReload();
    if (mounted) { setState(() => _saving = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Gespeichert'), backgroundColor: Colors.green.shade600)); }
  }

  Widget _field(String label, TextEditingController c, {IconData icon = Icons.edit, int maxLines = 1}) {
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: TextField(controller: c, maxLines: maxLines, decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)), style: const TextStyle(fontSize: 13)));
  }

  Widget _dateField(String label, TextEditingController c) {
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: TextField(controller: c, readOnly: true, decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.calendar_today, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)), style: const TextStyle(fontSize: 13),
      onTap: () async { final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (d != null) c.text = '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}'; }));
  }

  Widget _section(IconData icon, String title, Color color, List<Widget> children) {
    return Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, size: 18, color: color), const SizedBox(width: 6), Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color))]),
        const SizedBox(height: 8),
        ...children,
      ]));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Art & Status
      Row(children: [
        Expanded(child: DropdownButtonFormField<String>(value: _art, decoration: InputDecoration(labelText: 'Art', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          items: _JobcenterAntragTabState._artLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 11)))).toList(),
          onChanged: (v) => setState(() => _art = v ?? _art))),
        const SizedBox(width: 8),
        Expanded(child: DropdownButtonFormField<String>(value: _status, decoration: InputDecoration(labelText: 'Status', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          items: _JobcenterAntragTabState._statusLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 11)))).toList(),
          onChanged: (v) => setState(() => _status = v ?? _status))),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _dateField('Datum', _datumC)),
        const SizedBox(width: 8),
        Expanded(child: _field('Aktenzeichen', _aktenzeichenC, icon: Icons.bookmark)),
      ]),
      _field('Notiz', _notizC, icon: Icons.notes, maxLines: 2),

      const SizedBox(height: 8),
      Align(alignment: Alignment.centerRight, child: ElevatedButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 16),
        label: const Text('Speichern'),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
      )),
    ]));
  }
}

// ==================== BEWILLIGUNGSBESCHEID TAB ====================
class _AntragBescheidTab extends StatefulWidget {
  final Map<String, dynamic> antrag;
  final ApiService apiService;
  final int userId;
  final Future<void> Function() onReload;
  const _AntragBescheidTab({required this.antrag, required this.apiService, required this.userId, required this.onReload});
  @override
  State<_AntragBescheidTab> createState() => _AntragBescheidTabState();
}
class _AntragBescheidTabState extends State<_AntragBescheidTab> {
  late TextEditingController _bescheidVonC, _bescheidBisC, _bescheidBetragC, _regelsatzC, _kduC, _heizkostenC, _mehrbedarfC, _mehrbedarfGrundC;
  bool _saving = false;
  @override
  void initState() { super.initState(); final a = widget.antrag;
    _bescheidVonC = TextEditingController(text: a['bescheid_von']?.toString() ?? ''); _bescheidBisC = TextEditingController(text: a['bescheid_bis']?.toString() ?? '');
    _bescheidBetragC = TextEditingController(text: a['bescheid_betrag']?.toString() ?? ''); _regelsatzC = TextEditingController(text: a['regelsatz']?.toString() ?? '');
    _kduC = TextEditingController(text: a['kdu']?.toString() ?? ''); _heizkostenC = TextEditingController(text: a['heizkosten']?.toString() ?? '');
    _mehrbedarfC = TextEditingController(text: a['mehrbedarf']?.toString() ?? ''); _mehrbedarfGrundC = TextEditingController(text: a['mehrbedarf_grund']?.toString() ?? ''); }
  @override
  void dispose() { _bescheidVonC.dispose(); _bescheidBisC.dispose(); _bescheidBetragC.dispose(); _regelsatzC.dispose(); _kduC.dispose(); _heizkostenC.dispose(); _mehrbedarfC.dispose(); _mehrbedarfGrundC.dispose(); super.dispose(); }
  Widget _field(String label, TextEditingController c, {IconData icon = Icons.edit}) => Padding(padding: const EdgeInsets.only(bottom: 8), child: TextField(controller: c, decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)), style: const TextStyle(fontSize: 13)));
  Widget _dateField(String label, TextEditingController c) => Padding(padding: const EdgeInsets.only(bottom: 8), child: TextField(controller: c, readOnly: true, decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.calendar_today, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)), style: const TextStyle(fontSize: 13), onTap: () async { final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (d != null) c.text = '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}'; }));
  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.apiService.jobcenterAction(widget.userId, {'action': 'save_antrag', 'antrag': {...widget.antrag, 'bescheid_von': _bescheidVonC.text, 'bescheid_bis': _bescheidBisC.text, 'bescheid_betrag': _bescheidBetragC.text, 'regelsatz': _regelsatzC.text, 'kdu': _kduC.text, 'heizkosten': _heizkostenC.text, 'mehrbedarf': _mehrbedarfC.text, 'mehrbedarf_grund': _mehrbedarfGrundC.text}});
    await widget.onReload();
    if (mounted) { setState(() => _saving = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Gespeichert'), backgroundColor: Colors.green.shade600)); }
  }
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Bewilligungsbescheid', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
      const SizedBox(height: 12),
        Row(children: [Expanded(child: _dateField('Von', _bescheidVonC)), const SizedBox(width: 8), Expanded(child: _dateField('Bis', _bescheidBisC))]),
        Row(children: [Expanded(child: _field('Gesamtbetrag €/Mo', _bescheidBetragC, icon: Icons.euro)), const SizedBox(width: 8), Expanded(child: _field('Regelsatz €', _regelsatzC, icon: Icons.account_balance_wallet))]),
        Row(children: [Expanded(child: _field('KdU Miete €', _kduC, icon: Icons.home)), const SizedBox(width: 8), Expanded(child: _field('Heizkosten €', _heizkostenC, icon: Icons.local_fire_department))]),
        Row(children: [Expanded(child: _field('Mehrbedarf €', _mehrbedarfC, icon: Icons.add_circle)), const SizedBox(width: 8), Expanded(child: _field('Mehrbedarf Grund', _mehrbedarfGrundC, icon: Icons.info))]),
      Align(alignment: Alignment.centerRight, child: ElevatedButton.icon(onPressed: _saving ? null : _save,
        icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 16),
        label: const Text('Speichern'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white))),
    ]));
  }
}

// ==================== EGV TAB (with Maßnahme) ====================
class _AntragEgvTab extends StatefulWidget {
  final Map<String, dynamic> antrag; final ApiService apiService; final int userId; final Future<void> Function() onReload;
  const _AntragEgvTab({required this.antrag, required this.apiService, required this.userId, required this.onReload});
  @override State<_AntragEgvTab> createState() => _AntragEgvTabState();
}
class _AntragEgvTabState extends State<_AntragEgvTab> {
  late TextEditingController _egvVonC, _egvBisC, _egvPflichtenC, _massnahmeNameC, _massnahmeVonC, _massnahmeBisC, _massnahmeTraegerC;
  late String _massnahmeArt, _massnahmeStatus;
  bool _hasEgv = false, _hasMassnahme = false, _saving = false;
  @override void initState() { super.initState(); final a = widget.antrag;
    _egvVonC = TextEditingController(text: a['egv_von']?.toString() ?? ''); _egvBisC = TextEditingController(text: a['egv_bis']?.toString() ?? '');
    _egvPflichtenC = TextEditingController(text: a['egv_pflichten']?.toString() ?? '');
    _massnahmeNameC = TextEditingController(text: a['massnahme_name']?.toString() ?? ''); _massnahmeVonC = TextEditingController(text: a['massnahme_von']?.toString() ?? '');
    _massnahmeBisC = TextEditingController(text: a['massnahme_bis']?.toString() ?? ''); _massnahmeTraegerC = TextEditingController(text: a['massnahme_traeger']?.toString() ?? '');
    _massnahmeArt = a['massnahme_art']?.toString() ?? ''; _massnahmeStatus = a['massnahme_status']?.toString() ?? '';
    _hasEgv = a['has_egv']?.toString() == 'true'; _hasMassnahme = a['has_massnahme']?.toString() == 'true'; }
  @override void dispose() { _egvVonC.dispose(); _egvBisC.dispose(); _egvPflichtenC.dispose(); _massnahmeNameC.dispose(); _massnahmeVonC.dispose(); _massnahmeBisC.dispose(); _massnahmeTraegerC.dispose(); super.dispose(); }
  Widget _field(String label, TextEditingController c, {IconData icon = Icons.edit, int maxLines = 1}) => Padding(padding: const EdgeInsets.only(bottom: 8), child: TextField(controller: c, maxLines: maxLines, decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), style: const TextStyle(fontSize: 13)));
  Widget _dateField(String label, TextEditingController c) => Padding(padding: const EdgeInsets.only(bottom: 8), child: TextField(controller: c, readOnly: true, decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.calendar_today, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), style: const TextStyle(fontSize: 13), onTap: () async { final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (d != null) c.text = '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}'; }));
  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.apiService.jobcenterAction(widget.userId, {'action': 'save_antrag', 'antrag': {...widget.antrag, 'has_egv': _hasEgv.toString(), 'egv_von': _egvVonC.text, 'egv_bis': _egvBisC.text, 'egv_pflichten': _egvPflichtenC.text, 'has_massnahme': _hasMassnahme.toString(), 'massnahme_art': _massnahmeArt, 'massnahme_status': _massnahmeStatus, 'massnahme_name': _massnahmeNameC.text, 'massnahme_traeger': _massnahmeTraegerC.text, 'massnahme_von': _massnahmeVonC.text, 'massnahme_bis': _massnahmeBisC.text}});
    await widget.onReload();
    if (mounted) { setState(() => _saving = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Gespeichert'), backgroundColor: Colors.green.shade600)); }
  }
  @override Widget build(BuildContext context) {
    return SingleChildScrollView(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(Icons.handshake, size: 20, color: Colors.purple.shade700), const SizedBox(width: 8), Text('EGV / Kooperationsplan', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.purple.shade800)),
        const Spacer(), Switch(value: _hasEgv, onChanged: (v) => setState(() => _hasEgv = v), activeThumbColor: Colors.purple)]),
      if (_hasEgv) ...[const SizedBox(height: 12),
        Row(children: [Expanded(child: _dateField('Von', _egvVonC)), const SizedBox(width: 8), Expanded(child: _dateField('Bis', _egvBisC))]),
        _field('Pflichten / Eigenbemühungen', _egvPflichtenC, icon: Icons.checklist, maxLines: 3),
      ],
      const Divider(height: 24),
      Row(children: [Icon(Icons.school, size: 20, color: Colors.cyan.shade700), const SizedBox(width: 8), Text('Maßnahme / Programm', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.cyan.shade800)),
        const Spacer(), Switch(value: _hasMassnahme, onChanged: (v) => setState(() => _hasMassnahme = v), activeThumbColor: Colors.cyan.shade700)]),
      if (_hasMassnahme) ...[const SizedBox(height: 12),
        Row(children: [
          Expanded(child: DropdownButtonFormField<String>(value: _massnahmeArt.isEmpty ? null : _massnahmeArt, decoration: InputDecoration(labelText: 'Art', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: const [DropdownMenuItem(value: 'bewerbungstraining', child: Text('Bewerbungstraining', style: TextStyle(fontSize: 11))), DropdownMenuItem(value: 'aktivierung', child: Text('Aktivierungsmaßnahme', style: TextStyle(fontSize: 11))), DropdownMenuItem(value: 'agh', child: Text('Arbeitsgelegenheit', style: TextStyle(fontSize: 11))), DropdownMenuItem(value: 'umschulung', child: Text('Umschulung', style: TextStyle(fontSize: 11))), DropdownMenuItem(value: 'weiterbildung', child: Text('Weiterbildung (FbW)', style: TextStyle(fontSize: 11))), DropdownMenuItem(value: 'sprachkurs', child: Text('Sprachkurs', style: TextStyle(fontSize: 11))), DropdownMenuItem(value: 'praktikum', child: Text('Praktikum', style: TextStyle(fontSize: 11))), DropdownMenuItem(value: 'coaching', child: Text('Coaching (AVGS)', style: TextStyle(fontSize: 11))), DropdownMenuItem(value: 'sonstiges', child: Text('Sonstiges', style: TextStyle(fontSize: 11)))],
            onChanged: (v) => setState(() => _massnahmeArt = v ?? ''))),
          const SizedBox(width: 8),
          Expanded(child: DropdownButtonFormField<String>(value: _massnahmeStatus.isEmpty ? null : _massnahmeStatus, decoration: InputDecoration(labelText: 'Status', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: const [DropdownMenuItem(value: 'zugewiesen', child: Text('Zugewiesen', style: TextStyle(fontSize: 11))), DropdownMenuItem(value: 'aktiv', child: Text('Aktiv', style: TextStyle(fontSize: 11))), DropdownMenuItem(value: 'abgeschlossen', child: Text('Abgeschlossen', style: TextStyle(fontSize: 11))), DropdownMenuItem(value: 'abgebrochen', child: Text('Abgebrochen', style: TextStyle(fontSize: 11)))],
            onChanged: (v) => setState(() => _massnahmeStatus = v ?? ''))),
        ]),
        const SizedBox(height: 8), _field('Bezeichnung', _massnahmeNameC, icon: Icons.label), _field('Träger', _massnahmeTraegerC, icon: Icons.business),
        Row(children: [Expanded(child: _dateField('Beginn', _massnahmeVonC)), const SizedBox(width: 8), Expanded(child: _dateField('Ende', _massnahmeBisC))]),
      ],
      const SizedBox(height: 12),
      Align(alignment: Alignment.centerRight, child: ElevatedButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save, size: 16), label: const Text('Speichern'), style: ElevatedButton.styleFrom(backgroundColor: Colors.purple.shade700, foregroundColor: Colors.white))),
    ]));
  }
}

// ==================== SANKTIONEN TAB ====================
class _AntragSanktionenTab extends StatefulWidget {
  final Map<String, dynamic> antrag; final ApiService apiService; final int userId; final Future<void> Function() onReload;
  const _AntragSanktionenTab({required this.antrag, required this.apiService, required this.userId, required this.onReload});
  @override State<_AntragSanktionenTab> createState() => _AntragSanktionenTabState();
}
class _AntragSanktionenTabState extends State<_AntragSanktionenTab> {
  late TextEditingController _sanktionNotizC;
  bool _hasSanktion = false, _saving = false;
  @override void initState() { super.initState(); _sanktionNotizC = TextEditingController(text: widget.antrag['sanktion_notiz']?.toString() ?? ''); _hasSanktion = widget.antrag['has_sanktion']?.toString() == 'true'; }
  @override void dispose() { _sanktionNotizC.dispose(); super.dispose(); }
  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.apiService.jobcenterAction(widget.userId, {'action': 'save_antrag', 'antrag': {...widget.antrag, 'has_sanktion': _hasSanktion.toString(), 'sanktion_notiz': _sanktionNotizC.text}});
    await widget.onReload();
    if (mounted) { setState(() => _saving = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Gespeichert'), backgroundColor: Colors.green.shade600)); }
  }
  @override Widget build(BuildContext context) {
    return SingleChildScrollView(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(Icons.warning_amber, size: 22, color: Colors.red.shade700), const SizedBox(width: 8), Text('Sanktionen / Leistungsminderung', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
        const Spacer(), Switch(value: _hasSanktion, onChanged: (v) => setState(() => _hasSanktion = v), activeThumbColor: Colors.red)]),
      if (_hasSanktion) ...[const SizedBox(height: 12),
        TextField(controller: _sanktionNotizC, maxLines: 5, decoration: InputDecoration(labelText: 'Details zur Sanktion (Grund, Minderung %, Zeitraum, Widerspruch...)', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 12),
        Align(alignment: Alignment.centerRight, child: ElevatedButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save, size: 16), label: const Text('Speichern'), style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white))),
      ],
    ]));
  }
}

// ==================== BEGUTACHTUNG / ÄRZTLICHER DIENST TAB ====================
class _AntragBegutachtungTab extends StatefulWidget {
  final Map<String, dynamic> antrag; final ApiService apiService; final int userId; final Future<void> Function() onReload;
  const _AntragBegutachtungTab({required this.antrag, required this.apiService, required this.userId, required this.onReload});
  @override State<_AntragBegutachtungTab> createState() => _AntragBegutachtungTabState();
}
class _AntragBegutachtungTabState extends State<_AntragBegutachtungTab> {
  late TextEditingController _datumC, _ortC, _gutachterC, _ergebnisC, _notizC;
  bool _saving = false;
  @override void initState() { super.initState(); final a = widget.antrag;
    _datumC = TextEditingController(text: a['begutachtung_datum']?.toString() ?? ''); _ortC = TextEditingController(text: a['begutachtung_ort']?.toString() ?? '');
    _gutachterC = TextEditingController(text: a['begutachtung_gutachter']?.toString() ?? ''); _ergebnisC = TextEditingController(text: a['begutachtung_ergebnis']?.toString() ?? '');
    _notizC = TextEditingController(text: a['begutachtung_notiz']?.toString() ?? ''); }
  @override void dispose() { _datumC.dispose(); _ortC.dispose(); _gutachterC.dispose(); _ergebnisC.dispose(); _notizC.dispose(); super.dispose(); }
  Widget _field(String label, TextEditingController c, {IconData icon = Icons.edit, int maxLines = 1}) => Padding(padding: const EdgeInsets.only(bottom: 10), child: TextField(controller: c, maxLines: maxLines, decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), style: const TextStyle(fontSize: 13)));
  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.apiService.jobcenterAction(widget.userId, {'action': 'save_antrag', 'antrag': {...widget.antrag, 'begutachtung_datum': _datumC.text, 'begutachtung_ort': _ortC.text, 'begutachtung_gutachter': _gutachterC.text, 'begutachtung_ergebnis': _ergebnisC.text, 'begutachtung_notiz': _notizC.text}});
    await widget.onReload();
    if (mounted) { setState(() => _saving = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Gespeichert'), backgroundColor: Colors.green.shade600)); }
  }
  @override Widget build(BuildContext context) {
    return SingleChildScrollView(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(Icons.medical_services, size: 22, color: Colors.indigo.shade700), const SizedBox(width: 8), Text('Begutachtung / Ärztlicher Dienst', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.indigo.shade800))]),
      const SizedBox(height: 16),
      TextField(controller: _datumC, readOnly: true, decoration: InputDecoration(labelText: 'Termin-Datum', prefixIcon: const Icon(Icons.calendar_today, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
        onTap: () async { final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (d != null) _datumC.text = '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}'; }),
      const SizedBox(height: 10),
      _field('Ort / Adresse', _ortC, icon: Icons.location_on),
      _field('Gutachter / Arzt', _gutachterC, icon: Icons.person),
      _field('Ergebnis', _ergebnisC, icon: Icons.assignment, maxLines: 2),
      _field('Notizen', _notizC, icon: Icons.notes, maxLines: 3),
      const SizedBox(height: 8),
      Align(alignment: Alignment.centerRight, child: ElevatedButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save, size: 16), label: const Text('Speichern'), style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade700, foregroundColor: Colors.white))),
    ]));
  }
}

// ==================== ANTRAG KORRESPONDENZ TAB ====================

class _AntragKorrTab extends StatefulWidget {
  final int antragId;
  final ApiService apiService;
  final int userId;
  const _AntragKorrTab({required this.antragId, required this.apiService, required this.userId});
  @override
  State<_AntragKorrTab> createState() => _AntragKorrTabState();
}

class _AntragKorrTabState extends State<_AntragKorrTab> {
  List<Map<String, dynamic>> _korr = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final res = await widget.apiService.getJobcenterAntragDetail(widget.userId, widget.antragId);
      if (res['success'] == true) {
        _korr = (res['korrespondenz'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  void _add() {
    String richtung = 'eingang';
    String methode = 'Brief';
    final datumC = TextEditingController();
    final betreffC = TextEditingController();
    final notizC = TextEditingController();
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) => AlertDialog(
      title: const Text('Neue Korrespondenz', style: TextStyle(fontSize: 15)),
      content: SizedBox(width: 400, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          ChoiceChip(label: const Text('Eingang'), selected: richtung == 'eingang', onSelected: (_) => setDlg(() => richtung = 'eingang')),
          const SizedBox(width: 8),
          ChoiceChip(label: const Text('Ausgang'), selected: richtung == 'ausgang', onSelected: (_) => setDlg(() => richtung = 'ausgang')),
        ]),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(value: methode, decoration: InputDecoration(labelText: 'Methode', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          items: const [
            DropdownMenuItem(value: 'Brief', child: Text('Brief')),
            DropdownMenuItem(value: 'E-Mail', child: Text('E-Mail')),
            DropdownMenuItem(value: 'Fax', child: Text('Fax')),
            DropdownMenuItem(value: 'Telefon', child: Text('Telefon')),
            DropdownMenuItem(value: 'Online', child: Text('Online')),
            DropdownMenuItem(value: 'Persönlich', child: Text('Persönlich')),
          ], onChanged: (v) => setDlg(() => methode = v ?? methode)),
        const SizedBox(height: 10),
        TextField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', isDense: true, prefixIcon: const Icon(Icons.calendar_today, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          onTap: () async { final d = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (d != null) datumC.text = '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}'; }),
        const SizedBox(height: 10),
        TextField(controller: betreffC, decoration: InputDecoration(labelText: 'Betreff', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 10),
        TextField(controller: notizC, maxLines: 3, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () async {
          Navigator.pop(ctx);
          await widget.apiService.jobcenterAction(widget.userId, {'action': 'save_korr', 'antrag_id': widget.antragId, 'korr': {'richtung': richtung, 'methode': methode, 'datum': datumC.text, 'betreff': betreffC.text, 'notiz': notizC.text}});
          await _load();
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white), child: const Text('Hinzufügen')),
      ],
    )));
  }

  Future<void> _delete(int id) async {
    await widget.apiService.jobcenterAction(widget.userId, {'action': 'delete_korr', 'id': id});
    await _load();
  }

  void _openDetail(Map<String, dynamic> k) {
    showDialog(context: context, builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(28),
      child: ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(
        width: MediaQuery.of(ctx).size.width * 0.75,
        height: MediaQuery.of(ctx).size.height * 0.75,
        child: _KorrDetailModal(k: k, apiService: widget.apiService, userId: widget.userId, onSaved: _load),
      )),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Padding(padding: const EdgeInsets.all(8), child: Row(children: [
        Text('Korrespondenz (${_korr.length})', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red.shade800)),
        const Spacer(),
        ElevatedButton.icon(onPressed: _add, icon: const Icon(Icons.add, size: 14), label: const Text('Neu', style: TextStyle(fontSize: 11)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4))),
      ])),
      Expanded(child: _korr.isEmpty
        ? Center(child: Text('Keine Korrespondenz', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(itemCount: _korr.length, itemBuilder: (ctx, i) {
            final k = _korr[i];
            final isEin = k['richtung'] == 'eingang';
            final kId = int.tryParse(k['id'].toString()) ?? 0;
            return Card(margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), child: InkWell(
              onTap: () => _openDetail(k),
              borderRadius: BorderRadius.circular(8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(dense: true,
                  leading: Icon(isEin ? Icons.call_received : Icons.call_made, color: isEin ? Colors.blue : Colors.orange, size: 20),
                  title: Text(k['betreff']?.toString() ?? '(kein Betreff)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  subtitle: Text('${k['datum'] ?? ''} · ${k['methode'] ?? ''}', style: const TextStyle(fontSize: 10)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
                    IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade300), onPressed: () => _delete(k['id'] as int)),
                  ]),
                ),
              ]),
            ));
          })),
    ]);
  }
}

// ==================== ANTRAG TERMIN TAB ====================

class _AntragTerminTab extends StatefulWidget {
  final int antragId;
  final ApiService apiService;
  final int userId;
  const _AntragTerminTab({required this.antragId, required this.apiService, required this.userId});
  @override
  State<_AntragTerminTab> createState() => _AntragTerminTabState();
}

class _AntragTerminTabState extends State<_AntragTerminTab> {
  List<Map<String, dynamic>> _termine = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final res = await widget.apiService.getJobcenterAntragDetail(widget.userId, widget.antragId);
      if (res['success'] == true) {
        _termine = (res['termine'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  void _add() {
    final datumC = TextEditingController();
    final uhrzeitC = TextEditingController();
    final ortC = TextEditingController();
    final notizC = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Neuer Termin', style: TextStyle(fontSize: 15)),
      content: SizedBox(width: 400, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', isDense: true, prefixIcon: const Icon(Icons.calendar_today, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          onTap: () async { final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (d != null) datumC.text = '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}'; }),
        const SizedBox(height: 10),
        TextField(controller: uhrzeitC, decoration: InputDecoration(labelText: 'Uhrzeit', isDense: true, hintText: 'z.B. 09:00', prefixIcon: const Icon(Icons.access_time, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 10),
        TextField(controller: ortC, decoration: InputDecoration(labelText: 'Ort', isDense: true, prefixIcon: const Icon(Icons.location_on, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 10),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () async {
          Navigator.pop(ctx);
          await widget.apiService.jobcenterAction(widget.userId, {'action': 'save_termin', 'antrag_id': widget.antragId, 'termin': {'datum': datumC.text, 'uhrzeit': uhrzeitC.text, 'ort': ortC.text, 'notiz': notizC.text}});
          await _load();
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white), child: const Text('Hinzufügen')),
      ],
    ));
  }

  Future<void> _delete(int id) async {
    await widget.apiService.jobcenterAction(widget.userId, {'action': 'delete_termin', 'id': id});
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Padding(padding: const EdgeInsets.all(8), child: Row(children: [
        Text('Termine (${_termine.length})', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red.shade800)),
        const Spacer(),
        ElevatedButton.icon(onPressed: _add, icon: const Icon(Icons.add, size: 14), label: const Text('Neu', style: TextStyle(fontSize: 11)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4))),
      ])),
      Expanded(child: _termine.isEmpty
        ? Center(child: Text('Keine Termine', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(itemCount: _termine.length, itemBuilder: (ctx, i) {
            final t = _termine[i];
            return Card(margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), child: ListTile(dense: true,
              leading: Icon(Icons.event, color: Colors.red.shade600, size: 20),
              title: Text('${t['datum'] ?? ''} ${t['uhrzeit'] ?? ''}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              subtitle: Text(t['ort']?.toString() ?? '', style: const TextStyle(fontSize: 10)),
              trailing: IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade300), onPressed: () => _delete(t['id'] as int)),
            ));
          })),
    ]);
  }
}

// ==================== TAB 3: Stammdaten (readonly) ====================

class _JobcenterStammdatenFieldsTab extends StatefulWidget {
  final Map<String, dynamic> data;
  final ApiService apiService;
  final int userId;
  final Future<void> Function(Map<String, String>) onSave;
  const _JobcenterStammdatenFieldsTab({required this.data, required this.apiService, required this.userId, required this.onSave});
  @override
  State<_JobcenterStammdatenFieldsTab> createState() => _JobcenterStammdatenFieldsTabState();
}
class _JobcenterStammdatenFieldsTabState extends State<_JobcenterStammdatenFieldsTab> {
  late TextEditingController _kundennummerC, _bgNummerC;
  bool _editing = false, _saving = false;
  @override
  void initState() { super.initState(); _kundennummerC = TextEditingController(text: widget.data['stammdaten.kundennummer'] ?? ''); _bgNummerC = TextEditingController(text: widget.data['stammdaten.bg_nummer'] ?? ''); }
  @override
  void dispose() { _kundennummerC.dispose(); _bgNummerC.dispose(); super.dispose(); }
  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.onSave({'stammdaten.kundennummer': _kundennummerC.text.trim(), 'stammdaten.bg_nummer': _bgNummerC.text.trim()});
    if (mounted) { setState(() { _saving = false; _editing = false; }); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Gespeichert'), backgroundColor: Colors.green.shade600)); }
  }
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Stammdaten', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
        const Spacer(),
        TextButton.icon(icon: Icon(_editing ? Icons.lock : Icons.edit, size: 16), label: Text(_editing ? 'Sperren' : 'Bearbeiten', style: const TextStyle(fontSize: 12)), onPressed: () => setState(() => _editing = !_editing)),
      ]),
      const SizedBox(height: 16),
      TextField(controller: _kundennummerC, readOnly: !_editing, decoration: InputDecoration(labelText: 'Kundennummer', prefixIcon: const Icon(Icons.badge, size: 20), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), filled: !_editing, fillColor: !_editing ? Colors.grey.shade100 : null)),
      const SizedBox(height: 12),
      TextField(controller: _bgNummerC, readOnly: !_editing, decoration: InputDecoration(labelText: 'BG-Nummer', prefixIcon: const Icon(Icons.numbers, size: 20), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), filled: !_editing, fillColor: !_editing ? Colors.grey.shade100 : null)),
      if (_editing) ...[const SizedBox(height: 16), Align(alignment: Alignment.centerRight, child: ElevatedButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 18),
        label: const Text('Speichern'), style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white)))],
    ]));
  }
}

// ==================== TAB 4: Arbeitsvermittler (readonly) ====================

class _JobcenterArbeitsvermittlerTab extends StatefulWidget {
  final Map<String, dynamic> data;
  final ApiService apiService;
  final int userId;
  final Future<void> Function(Map<String, String>) onSave;
  const _JobcenterArbeitsvermittlerTab({required this.data, required this.apiService, required this.userId, required this.onSave});
  @override
  State<_JobcenterArbeitsvermittlerTab> createState() => _JobcenterArbeitsvermittlerTabState();
}
class _JobcenterArbeitsvermittlerTabState extends State<_JobcenterArbeitsvermittlerTab> {
  late TextEditingController _vornameC, _nameC, _telefonC, _emailC, _zimmerC;
  bool _editing = false, _saving = false;
  @override
  void initState() {
    super.initState();
    _vornameC = TextEditingController(text: widget.data['stammdaten.arbeitsvermittler_vorname'] ?? '');
    _nameC = TextEditingController(text: widget.data['stammdaten.arbeitsvermittler'] ?? '');
    _telefonC = TextEditingController(text: widget.data['stammdaten.arbeitsvermittler_tel'] ?? '');
    _emailC = TextEditingController(text: widget.data['stammdaten.arbeitsvermittler_email'] ?? '');
    _zimmerC = TextEditingController(text: widget.data['stammdaten.arbeitsvermittler_zimmer'] ?? '');
  }
  @override
  void dispose() { _vornameC.dispose(); _nameC.dispose(); _telefonC.dispose(); _emailC.dispose(); _zimmerC.dispose(); super.dispose(); }
  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.onSave({
      'stammdaten.arbeitsvermittler_vorname': _vornameC.text.trim(), 'stammdaten.arbeitsvermittler': _nameC.text.trim(),
      'stammdaten.arbeitsvermittler_tel': _telefonC.text.trim(), 'stammdaten.arbeitsvermittler_email': _emailC.text.trim(),
      'stammdaten.arbeitsvermittler_zimmer': _zimmerC.text.trim(),
    });
    if (mounted) { setState(() { _saving = false; _editing = false; }); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Gespeichert'), backgroundColor: Colors.green.shade600)); }
  }
  Widget _f(String label, TextEditingController c, IconData icon) =>
    Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(controller: c, readOnly: !_editing, decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 20), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), filled: !_editing, fillColor: !_editing ? Colors.grey.shade100 : null)));
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.support_agent, size: 22, color: Colors.teal.shade700),
        const SizedBox(width: 8),
        Text('Arbeitsvermittler / pAp', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
        const Spacer(),
        TextButton.icon(icon: Icon(_editing ? Icons.lock : Icons.edit, size: 16), label: Text(_editing ? 'Sperren' : 'Bearbeiten', style: const TextStyle(fontSize: 12)), onPressed: () => setState(() => _editing = !_editing)),
      ]),
      const SizedBox(height: 16),
      Row(children: [Expanded(child: _f('Vorname', _vornameC, Icons.person)), const SizedBox(width: 12), Expanded(child: _f('Nachname', _nameC, Icons.person))]),
      _f('Telefon / Durchwahl', _telefonC, Icons.phone),
      _f('E-Mail', _emailC, Icons.email),
      _f('Zimmernummer', _zimmerC, Icons.meeting_room),
      if (_editing) ...[const SizedBox(height: 8), Align(alignment: Alignment.centerRight, child: ElevatedButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 18),
        label: const Text('Speichern'), style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white)))],
    ]));
  }
}

// ===== KORRESPONDENZ DETAIL MODAL (Details + Antwort) =====
class _KorrDetailModal extends StatefulWidget {
  final Map<String, dynamic> k;
  final ApiService apiService;
  final int userId;
  final VoidCallback onSaved;
  const _KorrDetailModal({required this.k, required this.apiService, required this.userId, required this.onSaved});
  @override
  State<_KorrDetailModal> createState() => _KorrDetailModalState();
}

class _KorrDetailModalState extends State<_KorrDetailModal> {
  late final TextEditingController _erstelltAmC, _empfangenAmC, _fristDatumC, _fristNotizC;
  late final TextEditingController _sachbearbeiterNameC, _meinZeichenC;
  late String _sachbearbeiterAnrede;
  late final TextEditingController _antwortDatumC, _antwortInhaltC;
  late String _antwortMethode, _antwortStatus;
  bool _saving = false;
  bool _detailsLocked = false;
  bool _detailsEditing = false;
  bool _antwortLocked = false;

  int get _kId => int.tryParse(widget.k['id'].toString()) ?? 0;
  bool get _isEin => widget.k['richtung'] == 'eingang';

  @override
  void initState() {
    super.initState();
    _erstelltAmC = TextEditingController(text: widget.k['erstellt_am']?.toString() ?? '');
    _empfangenAmC = TextEditingController(text: widget.k['empfangen_am']?.toString() ?? '');
    _fristDatumC = TextEditingController(text: widget.k['frist_datum']?.toString() ?? '');
    _fristNotizC = TextEditingController(text: widget.k['frist_notiz']?.toString() ?? '');
    _sachbearbeiterNameC = TextEditingController(text: widget.k['sachbearbeiter_name']?.toString() ?? '');
    _meinZeichenC = TextEditingController(text: widget.k['mein_zeichen']?.toString() ?? '');
    _sachbearbeiterAnrede = widget.k['sachbearbeiter_anrede']?.toString() ?? '';
    _antwortDatumC = TextEditingController(text: widget.k['antwort_datum']?.toString() ?? '');
    _antwortInhaltC = TextEditingController(text: widget.k['antwort_inhalt']?.toString() ?? '');
    _antwortMethode = widget.k['antwort_methode']?.toString() ?? '';
    _antwortStatus = widget.k['antwort_status']?.toString() ?? '';
    _detailsLocked = _erstelltAmC.text.isNotEmpty && _empfangenAmC.text.isNotEmpty;
    _antwortLocked = _antwortMethode.isNotEmpty && _antwortInhaltC.text.isNotEmpty;
  }

  @override
  void dispose() {
    _erstelltAmC.dispose(); _empfangenAmC.dispose(); _fristDatumC.dispose(); _fristNotizC.dispose();
    _sachbearbeiterNameC.dispose(); _meinZeichenC.dispose();
    _antwortDatumC.dispose(); _antwortInhaltC.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.apiService.jobcenterAction(widget.userId, {
      'action': 'update_korr', 'korr_id': _kId,
      'korr': {
        'erstellt_am': _erstelltAmC.text.trim(), 'empfangen_am': _empfangenAmC.text.trim(),
        'frist_datum': _fristDatumC.text.trim(), 'frist_notiz': _fristNotizC.text.trim(),
        'sachbearbeiter_anrede': _sachbearbeiterAnrede, 'sachbearbeiter_name': _sachbearbeiterNameC.text.trim(),
        'mein_zeichen': _meinZeichenC.text.trim(),
        'antwort_methode': _antwortMethode, 'antwort_datum': _antwortDatumC.text.trim(),
        'antwort_inhalt': _antwortInhaltC.text.trim(), 'antwort_status': _antwortStatus,
      },
    });
    widget.onSaved();
    if (mounted) {
      setState(() {
        _saving = false;
        if (_erstelltAmC.text.isNotEmpty && _empfangenAmC.text.isNotEmpty) _detailsLocked = true;
        if (_antwortMethode.isNotEmpty && _antwortInhaltC.text.isNotEmpty) _antwortLocked = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gespeichert'), backgroundColor: Colors.green, duration: Duration(seconds: 1)));
    }
  }

  Future<void> _pickDate(TextEditingController c) async {
    final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de'));
    if (d != null) c.text = '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final color = _isEin ? Colors.blue : Colors.orange;
    return DefaultTabController(length: 3, child: Column(children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: color.shade50),
        child: Row(children: [
          Icon(_isEin ? Icons.call_received : Icons.call_made, size: 22, color: color.shade700),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.k['betreff']?.toString() ?? '(kein Betreff)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color.shade800)),
            Row(children: [
              Text('${widget.k['datum'] ?? ''} • ${widget.k['methode'] ?? ''}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              if (_fristDatumC.text.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(6)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.timer, size: 12, color: Colors.red.shade700),
                    const SizedBox(width: 3),
                    Text('Frist: ${_fristDatumC.text}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
                  ])),
              ],
            ]),
          ])),
          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        ]),
      ),
      TabBar(labelColor: Colors.red.shade800, unselectedLabelColor: Colors.grey.shade500, indicatorColor: Colors.red.shade700, tabs: const [
        Tab(icon: Icon(Icons.info, size: 16), text: 'Details'),
        Tab(icon: Icon(Icons.reply, size: 16), text: 'Antwort'),
        Tab(icon: Icon(Icons.attach_file, size: 16), text: 'Dokumente'),
      ]),
      Expanded(child: TabBarView(children: [_buildDetailsTab(), _buildAntwortTab(), _buildDokumenteTab()])),
    ]));
  }

  // ===== DETAILS TAB =====
  Widget _buildDetailsTab() {
    if (_detailsLocked && !_detailsEditing) {
      return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.lock, size: 16, color: Colors.green.shade700),
          const SizedBox(width: 6),
          Text('Schreiben erfasst', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
          const Spacer(),
          TextButton.icon(
            icon: Icon(Icons.edit, size: 16, color: Colors.grey.shade600),
            label: Text('Bearbeiten', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            onPressed: () => setState(() => _detailsEditing = true),
          ),
        ]),
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_sachbearbeiterAnrede.isNotEmpty || _sachbearbeiterNameC.text.isNotEmpty)
              _readonlyRow(Icons.person, 'Sachbearbeiter', '${_sachbearbeiterAnrede.isNotEmpty ? '$_sachbearbeiterAnrede ' : ''}${_sachbearbeiterNameC.text}'),
            if (_meinZeichenC.text.isNotEmpty)
              _readonlyRow(Icons.tag, 'Mein Zeichen', _meinZeichenC.text),
            _readonlyRow(Icons.edit_calendar, 'Erstellt am', _erstelltAmC.text),
            _readonlyRow(Icons.markunread_mailbox, 'Empfangen am', _empfangenAmC.text),
          ]),
        ),
        if (_fristDatumC.text.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.shade200)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Icon(Icons.timer, size: 16, color: Colors.red.shade700), const SizedBox(width: 6),
                Text('Frist: ${_fristDatumC.text}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red.shade800))]),
              if (_fristNotizC.text.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(_fristNotizC.text, style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
              ],
            ]),
          ),
        ],
        if ((widget.k['notiz']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Notiz', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
            child: SelectableText(widget.k['notiz'].toString(), style: const TextStyle(fontSize: 13))),
        ],
      ]));
    }

    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Schreiben-Details', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
      const SizedBox(height: 12),
      Text('Sachbearbeiter', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
      const SizedBox(height: 6),
      Row(children: [
        ChoiceChip(label: const Text('Frau'), selected: _sachbearbeiterAnrede == 'Frau', selectedColor: Colors.red.shade100, onSelected: (_) => setState(() => _sachbearbeiterAnrede = 'Frau')),
        const SizedBox(width: 8),
        ChoiceChip(label: const Text('Herr'), selected: _sachbearbeiterAnrede == 'Herr', selectedColor: Colors.red.shade100, onSelected: (_) => setState(() => _sachbearbeiterAnrede = 'Herr')),
      ]),
      const SizedBox(height: 8),
      TextField(controller: _sachbearbeiterNameC, decoration: InputDecoration(labelText: 'Name', hintText: 'Name des Sachbearbeiters', isDense: true, prefixIcon: const Icon(Icons.person, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      const SizedBox(height: 10),
      TextField(controller: _meinZeichenC, decoration: InputDecoration(labelText: 'Mein Zeichen', hintText: 'Aktenzeichen des Sachbearbeiters', isDense: true, prefixIcon: const Icon(Icons.tag, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      const SizedBox(height: 14),
      _dateField('Erstellt am (Jobcenter)', _erstelltAmC, Icons.edit_calendar, 'Wann wurde das Schreiben vom Jobcenter erstellt?'),
      const SizedBox(height: 10),
      _dateField('Empfangen am (Mitglied)', _empfangenAmC, Icons.markunread_mailbox, 'Wann hat das Mitglied den Brief erhalten?'),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.shade200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.timer, size: 16, color: Colors.red.shade700), const SizedBox(width: 6),
            Text('Frist', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red.shade800))]),
          const SizedBox(height: 8),
          _dateField('Frist bis', _fristDatumC, Icons.event_busy, 'Bis wann muss reagiert werden?'),
          const SizedBox(height: 8),
          TextField(controller: _fristNotizC, maxLines: 2, decoration: InputDecoration(labelText: 'Frist-Hinweis', hintText: 'z.B. Unterlagen nachreichen, Widerspruch einlegen...', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        ]),
      ),
      if ((widget.k['notiz']?.toString() ?? '').isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Notiz', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
          child: SelectableText(widget.k['notiz'].toString(), style: const TextStyle(fontSize: 13))),
      ],
      const SizedBox(height: 16),
      Align(alignment: Alignment.centerRight, child: FilledButton.icon(
        onPressed: _saving ? null : _save,
        icon: Icon(_saving ? Icons.hourglass_top : Icons.save, size: 16),
        label: Text(_saving ? 'Speichern...' : 'Speichern', style: const TextStyle(fontSize: 12)),
        style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
      )),
    ]));
  }

  Widget _readonlyRow(IconData icon, String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
      Icon(icon, size: 16, color: Colors.grey.shade600), const SizedBox(width: 8),
      Text('$label: ', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
    ]));
  }

  Widget _dateField(String label, TextEditingController c, IconData icon, String hint) {
    return TextField(controller: c, readOnly: true, decoration: InputDecoration(labelText: label, hintText: hint, isDense: true, prefixIcon: Icon(icon, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
      onTap: () => _pickDate(c));
  }

  // ===== ANTWORT TAB =====
  Widget _buildAntwortTab() {
    if (_antwortLocked) {
      return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.lock, size: 16, color: Colors.green.shade700),
          const SizedBox(width: 6),
          Text('Antwort gesendet', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
        ]),
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.green.shade200)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(_methodeIcon(_antwortMethode), size: 14, color: Colors.purple.shade700), const SizedBox(width: 4), Text(_antwortMethode, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.purple.shade700))])),
              const SizedBox(width: 8),
              if (_antwortDatumC.text.isNotEmpty) Text('am ${_antwortDatumC.text}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              const Spacer(),
              if (_antwortStatus.isNotEmpty) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: _antwortStatus == 'bestätigt' ? Colors.green.shade100 : (_antwortStatus == 'abgelehnt' ? Colors.red.shade100 : Colors.blue.shade100), borderRadius: BorderRadius.circular(8)),
                child: Text(_antwortStatus[0].toUpperCase() + _antwortStatus.substring(1), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _antwortStatus == 'bestätigt' ? Colors.green.shade800 : (_antwortStatus == 'abgelehnt' ? Colors.red.shade800 : Colors.blue.shade800)))),
            ]),
            if (_antwortInhaltC.text.isNotEmpty) ...[
              const Divider(height: 20),
              SelectableText(_antwortInhaltC.text, style: const TextStyle(fontSize: 13, height: 1.5)),
            ],
          ]),
        ),
      ]));
    }

    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Antwort auf das Schreiben', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
      const SizedBox(height: 12),
      Text('Versandart', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _methodeChip('Online', Icons.language),
        _methodeChip('Postalisch', Icons.local_post_office),
        _methodeChip('Fax', Icons.fax),
        _methodeChip('Persönlich', Icons.person),
        _methodeChip('E-Mail', Icons.email),
        _methodeChip('Telefon', Icons.phone),
      ]),
      const SizedBox(height: 14),
      _dateField('Antwort gesendet am', _antwortDatumC, Icons.send, 'Wann wurde die Antwort abgeschickt?'),
      const SizedBox(height: 14),
      Text('Status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, children: [
        _statusChip('offen', Colors.orange),
        _statusChip('gesendet', Colors.blue),
        _statusChip('bestätigt', Colors.green),
        _statusChip('abgelehnt', Colors.red),
      ]),
      const SizedBox(height: 14),
      TextField(controller: _antwortInhaltC, maxLines: 8, decoration: InputDecoration(labelText: 'Inhalt der Antwort', hintText: 'Den Antworttext hier einfügen oder beschreiben...', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      const SizedBox(height: 16),
      Align(alignment: Alignment.centerRight, child: FilledButton.icon(
        onPressed: _saving ? null : _save,
        icon: Icon(_saving ? Icons.hourglass_top : Icons.save, size: 16),
        label: Text(_saving ? 'Speichern...' : 'Speichern', style: const TextStyle(fontSize: 12)),
        style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
      )),
    ]));
  }

  IconData _methodeIcon(String m) {
    switch (m) {
      case 'Online': return Icons.language;
      case 'Postalisch': return Icons.local_post_office;
      case 'Fax': return Icons.fax;
      case 'Persönlich': return Icons.person;
      case 'E-Mail': return Icons.email;
      case 'Telefon': return Icons.phone;
      default: return Icons.send;
    }
  }

  Widget _methodeChip(String label, IconData icon) {
    final sel = _antwortMethode == label;
    return ChoiceChip(
      avatar: Icon(icon, size: 16), label: Text(label),
      selected: sel, selectedColor: Colors.red.shade100,
      onSelected: (_) => setState(() => _antwortMethode = label),
    );
  }

  Widget _statusChip(String label, MaterialColor color) {
    final sel = _antwortStatus == label;
    return ChoiceChip(
      label: Text(label[0].toUpperCase() + label.substring(1)),
      selected: sel, selectedColor: color.shade100,
      onSelected: (_) => setState(() => _antwortStatus = label),
    );
  }

  // ===== DOKUMENTE TAB =====
  Widget _buildDokumenteTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: KorrAttachmentsWidget(apiService: widget.apiService, modul: 'jobcenter_korr', korrespondenzId: _kId),
    );
  }
}
