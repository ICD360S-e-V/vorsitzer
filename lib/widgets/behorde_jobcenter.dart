import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';
import 'file_viewer_dialog.dart';
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
    _tabController = TabController(length: 5, vsync: this);
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
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.assignment_ind, size: 14, color: Colors.red), const SizedBox(width: 5), const Text('Vollmacht')])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: (_data['vermittler.name'] ?? '').isNotEmpty ? Colors.green : Colors.red), const SizedBox(width: 5), const Text('Arbeitsvermittler')])),
      ]),
      Expanded(child: TabBarView(controller: _tabController, children: [
        _JobcenterStammdatenTab(data: _data, apiService: widget.apiService, userId: widget.userId, onSave: _saveData),
        _JobcenterAntragTab(antraege: _antraege, apiService: widget.apiService, userId: widget.userId, onReload: _load),
        _JobcenterStammdatenFieldsTab(data: _data, apiService: widget.apiService, userId: widget.userId, onSave: _saveData),
        _JCVollmachtSection(apiService: widget.apiService, userId: widget.userId),
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
        }).catchError((Object _) {
          setDlg(() => loading = false);
          return null;
        });
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
    setState(() { _selected = s; });
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
    if (mounted) setState(() {});
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
  int? _yearFilter; // null = alle Jahre

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

  int? _antragYear(Map<String, dynamic> a) {
    // Datum is "DD.MM.YYYY" format from the date picker
    final datum = (a['datum'] ?? '').toString();
    final m = RegExp(r'^\d{1,2}\.\d{1,2}\.(\d{4})$').firstMatch(datum);
    if (m != null) return int.tryParse(m.group(1)!);
    // Fallback: try bescheid_von year if no datum
    final bv = (a['bescheid_von'] ?? '').toString();
    final m2 = RegExp(r'^\d{1,2}\.\d{1,2}\.(\d{4})$').firstMatch(bv);
    if (m2 != null) return int.tryParse(m2.group(1)!);
    return null;
  }

  List<int> get _availableYears {
    final years = <int>{};
    for (final a in _antraege) {
      final y = _antragYear(a);
      if (y != null && y >= 2025) years.add(y);
    }
    return years.toList()..sort((a, b) => b.compareTo(a));
  }

  List<Map<String, dynamic>> get _filtered {
    if (_yearFilter == null) return _antraege;
    return _antraege.where((a) => _antragYear(a) == _yearFilter).toList();
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
        DropdownButtonFormField<String>(initialValue: art, decoration: InputDecoration(labelText: 'Art', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          items: _artLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (v) => setDlg(() => art = v ?? art)),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(initialValue: status, decoration: InputDecoration(labelText: 'Status', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
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
    final years = _availableYears;
    final filtered = _filtered;
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Icon(Icons.description, color: Colors.red.shade700),
        const SizedBox(width: 8),
        Text('Anträge (${filtered.length}${_yearFilter != null ? '/${_antraege.length}' : ''})', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.red.shade800)),
        const SizedBox(width: 12),
        if (years.isNotEmpty) DropdownButton<int?>(
          value: _yearFilter,
          isDense: true,
          hint: const Text('Jahr', style: TextStyle(fontSize: 12)),
          underline: const SizedBox.shrink(),
          icon: Icon(Icons.calendar_today, size: 14, color: Colors.red.shade700),
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.red.shade800),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('Alle Jahre', style: TextStyle(fontSize: 12))),
            ...years.map((y) => DropdownMenuItem<int?>(value: y, child: Text('$y', style: const TextStyle(fontSize: 12)))),
          ],
          onChanged: (v) => setState(() => _yearFilter = v),
        ),
        const Spacer(),
        ElevatedButton.icon(onPressed: _addAntrag, icon: const Icon(Icons.add, size: 16), label: const Text('Neuer Antrag', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white)),
      ])),
      Expanded(child: filtered.isEmpty
        ? Center(child: Text(_yearFilter != null ? 'Keine Anträge für $_yearFilter' : 'Keine Anträge vorhanden', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: filtered.length, itemBuilder: (ctx, i) {
            final a = filtered[i];
            final art = a['art']?.toString() ?? '';
            final status = a['status']?.toString() ?? '';
            final color = _statusColors[status] ?? Colors.grey;
            final yr = _antragYear(a);
            return Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(
              onTap: () => _openDetail(a),
              leading: CircleAvatar(backgroundColor: color.shade100, child: Icon(Icons.description, color: color.shade700, size: 20)),
              title: Row(children: [
                Expanded(child: Text(_artLabels[art] ?? art, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis)),
                if (yr != null) Container(margin: const EdgeInsets.only(left: 6), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.shade200)), child: Text('$yr', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red.shade700))),
              ]),
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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Art & Status
      Row(children: [
        Expanded(child: DropdownButtonFormField<String>(initialValue: _art, decoration: InputDecoration(labelText: 'Art', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          items: _JobcenterAntragTabState._artLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 11)))).toList(),
          onChanged: (v) => setState(() => _art = v ?? _art))),
        const SizedBox(width: 8),
        Expanded(child: DropdownButtonFormField<String>(initialValue: _status, decoration: InputDecoration(labelText: 'Status', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
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
class _AntragBescheidTabState extends State<_AntragBescheidTab> with AutomaticKeepAliveClientMixin {
  late TextEditingController _bescheidVonC, _bescheidBisC, _bescheidBetragC, _regelsatzC, _kduC, _nebenkostenC, _heizkostenC, _mehrbedarfC, _mehrbedarfGrundC;
  bool _saving = false;
  List<Map<String, dynamic>> _docs = [];
  bool _docsLoading = false, _uploading = false;
  Map<String, dynamic>? _wbaTicket;
  String? _wbaAction; // 'created' | 'existing' | 'updated' (only set after a save in this session)
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() { super.initState(); final a = widget.antrag;
    _bescheidVonC = TextEditingController(text: a['bescheid_von']?.toString() ?? ''); _bescheidBisC = TextEditingController(text: a['bescheid_bis']?.toString() ?? '');
    _bescheidBetragC = TextEditingController(text: a['bescheid_betrag']?.toString() ?? '');
    // Bürgergeld Regelbedarfsstufe 1 = 563 € (SGB II, BMAS Fortschreibung 2026 — Nullrunde).
    final rs = a['regelsatz']?.toString() ?? '';
    _regelsatzC = TextEditingController(text: rs.isEmpty ? '563' : rs);
    _kduC = TextEditingController(text: a['kdu']?.toString() ?? '');
    _nebenkostenC = TextEditingController(text: a['nebenkosten']?.toString() ?? '');
    _heizkostenC = TextEditingController(text: a['heizkosten']?.toString() ?? '');
    _mehrbedarfC = TextEditingController(text: a['mehrbedarf']?.toString() ?? ''); _mehrbedarfGrundC = TextEditingController(text: a['mehrbedarf_grund']?.toString() ?? '');
    // Hydrate WBA-ticket info from the antrag payload so the proof-card shows on first open, not only after save
    final wba = a['wba_ticket'];
    if (wba is Map) _wbaTicket = Map<String, dynamic>.from(wba);
    _loadDocs();
  }
  @override
  void dispose() { _bescheidVonC.dispose(); _bescheidBisC.dispose(); _bescheidBetragC.dispose(); _regelsatzC.dispose(); _kduC.dispose(); _nebenkostenC.dispose(); _heizkostenC.dispose(); _mehrbedarfC.dispose(); _mehrbedarfGrundC.dispose(); super.dispose(); }
  Widget _field(String label, TextEditingController c, {IconData icon = Icons.edit}) => Padding(padding: const EdgeInsets.only(bottom: 8), child: TextField(controller: c, decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)), style: const TextStyle(fontSize: 13)));
  Widget _dateField(String label, TextEditingController c) => Padding(padding: const EdgeInsets.only(bottom: 8), child: TextField(controller: c, readOnly: true, decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.calendar_today, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)), style: const TextStyle(fontSize: 13), onTap: () async { final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (d != null) c.text = '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}'; }));
  Future<void> _save() async {
    setState(() => _saving = true);
    final payload = {'bescheid_von': _bescheidVonC.text, 'bescheid_bis': _bescheidBisC.text, 'bescheid_betrag': _bescheidBetragC.text, 'regelsatz': _regelsatzC.text, 'kdu': _kduC.text, 'nebenkosten': _nebenkostenC.text, 'heizkosten': _heizkostenC.text, 'mehrbedarf': _mehrbedarfC.text, 'mehrbedarf_grund': _mehrbedarfGrundC.text};
    final resp = await widget.apiService.jobcenterAction(widget.userId, {'action': 'save_antrag', 'antrag': {...widget.antrag, ...payload}});
    widget.antrag.addAll(payload);
    final wba = resp['wba_ticket'];
    final wbaAction = resp['wba_action']?.toString() ?? 'skipped';
    await widget.onReload();
    if (!mounted) return;
    setState(() {
      _saving = false;
      _wbaTicket = wba is Map ? Map<String, dynamic>.from(wba) : null;
      _wbaAction = wbaAction;
    });
    final ticketId = _wbaTicket?['ticket_id'];
    final (msg, color, secs) = switch (wbaAction) {
      'created'  => ('Gespeichert · WBA-Ticket #$ticketId neu erstellt', Colors.indigo.shade700, 4),
      'updated'  => ('Gespeichert · Bis-Datum geändert — neues WBA-Ticket #$ticketId angelegt, altes geschlossen', Colors.orange.shade700, 5),
      'existing' => ('Gespeichert · WBA-Ticket #$ticketId ist bereits angelegt — kein Duplikat erstellt', Colors.teal.shade700, 4),
      _          => ('Gespeichert', Colors.green.shade600, 2),
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      duration: Duration(seconds: secs),
    ));
  }

  String get _antragId => widget.antrag['id']?.toString() ?? '';

  Future<void> _loadDocs() async {
    if (_antragId.isEmpty) return;
    setState(() => _docsLoading = true);
    final r = await widget.apiService.getAntragDokumente(userId: widget.userId, behoerdeType: 'jobcenter', antragId: _antragId);
    if (!mounted) return;
    final list = (r['data']?['dokumente'] ?? r['dokumente'] ?? []) as List;
    setState(() {
      _docs = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _docsLoading = false;
    });
  }

  Future<void> _uploadDoc() async {
    if (_antragId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte zuerst Antrag speichern')));
      return;
    }
    final result = await FilePickerHelper.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'tiff', 'bmp'], allowMultiple: true);
    if (result == null || result.files.isEmpty) return;
    setState(() => _uploading = true);
    int ok = 0; String? lastErr;
    for (final f in result.files.where((f) => f.path != null)) {
      try {
        final res = await widget.apiService.uploadAntragDokument(userId: widget.userId, behoerdeType: 'jobcenter', antragId: _antragId, filePath: f.path!, fileName: f.name);
        if (res['success'] == true) { ok++; } else { lastErr = res['message']?.toString() ?? 'Upload fehlgeschlagen'; }
      } catch (e) { lastErr = e.toString(); }
    }
    if (!mounted) return;
    setState(() => _uploading = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lastErr == null ? '$ok Datei(en) hochgeladen' : 'Fehler: $lastErr'), backgroundColor: lastErr == null ? Colors.green.shade600 : Colors.red.shade600));
    await _loadDocs();
  }

  Future<void> _viewDoc(Map<String, dynamic> doc) async {
    try {
      final resp = await widget.apiService.downloadAntragDokument(doc['id'] as int);
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
      if (!mounted) return;
      final name = doc['filename']?.toString() ?? 'dokument';
      final shown = await FileViewerDialog.showFromBytes(context, resp.bodyBytes, name);
      if (!shown && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Format nicht unterstützt: $name')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Öffnen fehlgeschlagen: $e')));
    }
  }

  Future<void> _deleteDoc(Map<String, dynamic> doc) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Dokument löschen?', style: TextStyle(fontSize: 15)),
      content: Text(doc['filename']?.toString() ?? '', style: const TextStyle(fontSize: 12)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('Löschen')),
      ],
    ));
    if (ok != true) return;
    await widget.apiService.deleteAntragDokument(doc['id'] as int);
    await _loadDocs();
  }

  String _fmtSize(dynamic bytes) {
    final n = bytes is int ? bytes : int.tryParse(bytes?.toString() ?? '0') ?? 0;
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Formats a scheduled_date string "2026-10-31 09:00:00" to "31.10.2026 um 09:00"
  String _formatWbaSchedule(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    try {
      final dt = DateTime.parse(raw.replaceFirst(' ', 'T'));
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} um ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) { return raw; }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SingleChildScrollView(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Bewilligungsbescheid', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
      const SizedBox(height: 12),
        Row(children: [Expanded(child: _dateField('Von', _bescheidVonC)), const SizedBox(width: 8), Expanded(child: _dateField('Bis', _bescheidBisC))]),
        Row(children: [Expanded(child: _field('Gesamtbetrag €/Mo', _bescheidBetragC, icon: Icons.euro)), const SizedBox(width: 8), Expanded(child: _field('Regelsatz €', _regelsatzC, icon: Icons.account_balance_wallet))]),
        Row(children: [Expanded(child: _field('KdU Miete €', _kduC, icon: Icons.home)), const SizedBox(width: 8), Expanded(child: _field('Nebenkosten €', _nebenkostenC, icon: Icons.receipt_long))]),
        Row(children: [Expanded(child: _field('Heizkosten €', _heizkostenC, icon: Icons.local_fire_department)), const SizedBox(width: 8), Expanded(child: _field('Mehrbedarf €', _mehrbedarfC, icon: Icons.add_circle))]),
        _field('Mehrbedarf Grund', _mehrbedarfGrundC, icon: Icons.info),
      Align(alignment: Alignment.centerRight, child: ElevatedButton.icon(onPressed: _saving ? null : _save,
        icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 16),
        label: const Text('Speichern'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white))),
      if (_wbaTicket != null) ...[
        const SizedBox(height: 10),
        Builder(builder: (ctx) {
          // Tint by action: existing=teal (no-op), created/load=indigo, updated=orange.
          final (chipColor, chipText, chipIcon, cardColor, cardBorder, headline) = switch (_wbaAction) {
            'updated'  => (Colors.orange.shade100, 'Aktualisiert',     Icons.swap_horiz,     Colors.orange.shade50, Colors.orange.shade300, 'WBA-Ticket aktualisiert'),
            'existing' => (Colors.teal.shade100,   'Bereits angelegt', Icons.verified,       Colors.teal.shade50,   Colors.teal.shade300,   'WBA-Ticket ist bereits gesetzt'),
            'created'  => (Colors.green.shade100,  'Neu erstellt',     Icons.check_circle,   Colors.indigo.shade50, Colors.indigo.shade300, 'WBA-Erinnerungsticket erstellt'),
            _          => (Colors.blue.shade100,   'Aktiv',            Icons.event_note,     Colors.indigo.shade50, Colors.indigo.shade300, 'WBA-Erinnerungsticket geplant'),
          };
          final textColor = switch (_wbaAction) { 'updated' => Colors.orange.shade800, 'existing' => Colors.teal.shade800, _ => Colors.indigo.shade800 };
          final iconColor = switch (_wbaAction) { 'updated' => Colors.orange.shade700, 'existing' => Colors.teal.shade700, _ => Colors.indigo.shade700 };
          final subTextColor = switch (_wbaAction) { 'updated' => Colors.orange.shade700, 'existing' => Colors.teal.shade700, _ => Colors.indigo.shade600 };
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(8), border: Border.all(color: cardBorder, width: 1.5)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.event_available, color: iconColor, size: 22),
                const SizedBox(width: 8),
                Expanded(child: Text(headline, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textColor))),
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: chipColor, borderRadius: BorderRadius.circular(10)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(chipIcon, size: 12, color: textColor), const SizedBox(width: 3), Text(chipText, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor))])),
              ]),
              const SizedBox(height: 8),
              Text('Ticket #${_wbaTicket!['ticket_id']}', style: const TextStyle(fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(_wbaTicket!['subject']?.toString() ?? '', style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 6),
              Row(children: [
                Icon(Icons.calendar_today, size: 14, color: subTextColor),
                const SizedBox(width: 4),
                Text('Geplant für: ', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                Text(_formatWbaSchedule(_wbaTicket!['scheduled_date']?.toString()), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor)),
                const Spacer(),
                Text('Bewilligung bis ${_wbaTicket!['bescheid_bis']}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
              ]),
              const SizedBox(height: 4),
              if (_wbaAction == 'existing')
                Text('→ Es existiert bereits ein offenes WBA-Ticket für diesen Antrag mit demselben Bis-Datum. Es wurde KEIN Duplikat angelegt.', style: TextStyle(fontSize: 10, color: subTextColor, fontStyle: FontStyle.italic))
              else if (_wbaAction == 'updated')
                Text('→ Das Bis-Datum hat sich geändert. Das alte Ticket wurde geschlossen und ein neues mit dem aktualisierten Termin angelegt.', style: TextStyle(fontSize: 10, color: subTextColor, fontStyle: FontStyle.italic))
              else
                Text('→ Wird in der Ticketverwaltung 2 Monate vor dem Bewilligungsende angezeigt, damit der Weiterbewilligungsantrag rechtzeitig eingereicht wird.', style: TextStyle(fontSize: 10, color: Colors.grey.shade700, fontStyle: FontStyle.italic)),
            ]),
          );
        }),
      ],
      const Divider(height: 24),
      Row(children: [
        Icon(Icons.folder_open, size: 18, color: Colors.green.shade700),
        const SizedBox(width: 6),
        Text('Bescheid-Dokumente${_docs.isEmpty ? '' : ' (${_docs.length})'}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: _uploading ? null : _uploadDoc,
          icon: _uploading ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.upload_file, size: 16),
          label: const Text('Hochladen', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade600, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
        ),
      ]),
      const SizedBox(height: 6),
      if (_docsLoading)
        const Padding(padding: EdgeInsets.all(8), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))))
      else if (_docs.isEmpty)
        Padding(padding: const EdgeInsets.all(8), child: Text('Keine Dokumente hochgeladen', style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic)))
      else
        ..._docs.map((d) => Card(
          margin: const EdgeInsets.only(bottom: 4),
          child: ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: Icon((d['mime_type']?.toString().contains('pdf') ?? false) ? Icons.picture_as_pdf : Icons.image, size: 20, color: Colors.green.shade700),
            title: Text(d['filename']?.toString() ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
            subtitle: Text('${_fmtSize(d['file_size'])} · ${d['uploaded_at']?.toString().substring(0, 16) ?? ''}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: Icon(Icons.visibility, size: 18, color: Colors.blue.shade700), tooltip: 'Öffnen', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: () => _viewDoc(d)),
              IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400), tooltip: 'Löschen', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: () => _deleteDoc(d)),
            ]),
          ),
        )),
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
          Expanded(child: DropdownButtonFormField<String>(initialValue: _massnahmeArt.isEmpty ? null : _massnahmeArt, decoration: InputDecoration(labelText: 'Art', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: const [DropdownMenuItem(value: 'bewerbungstraining', child: Text('Bewerbungstraining', style: TextStyle(fontSize: 11))), DropdownMenuItem(value: 'aktivierung', child: Text('Aktivierungsmaßnahme', style: TextStyle(fontSize: 11))), DropdownMenuItem(value: 'agh', child: Text('Arbeitsgelegenheit', style: TextStyle(fontSize: 11))), DropdownMenuItem(value: 'umschulung', child: Text('Umschulung', style: TextStyle(fontSize: 11))), DropdownMenuItem(value: 'weiterbildung', child: Text('Weiterbildung (FbW)', style: TextStyle(fontSize: 11))), DropdownMenuItem(value: 'sprachkurs', child: Text('Sprachkurs', style: TextStyle(fontSize: 11))), DropdownMenuItem(value: 'praktikum', child: Text('Praktikum', style: TextStyle(fontSize: 11))), DropdownMenuItem(value: 'coaching', child: Text('Coaching (AVGS)', style: TextStyle(fontSize: 11))), DropdownMenuItem(value: 'sonstiges', child: Text('Sonstiges', style: TextStyle(fontSize: 11)))],
            onChanged: (v) => setState(() => _massnahmeArt = v ?? ''))),
          const SizedBox(width: 8),
          Expanded(child: DropdownButtonFormField<String>(initialValue: _massnahmeStatus.isEmpty ? null : _massnahmeStatus, decoration: InputDecoration(labelText: 'Status', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
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
        DropdownButtonFormField<String>(initialValue: methode, decoration: InputDecoration(labelText: 'Methode', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
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

// ═════════════════════════════════════════════════════════════════════════
//  VOLLMACHT section — Jobcenter (SGB II / Grundsicherung).
//  Clone of _AAVollmachtSection (Arbeitsagentur), adapted for Jobcenter.
//  Backend endpoints are shared (parameter behoerde=jobcenter).
// ═════════════════════════════════════════════════════════════════════════

class _JCVollmachtSection extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  const _JCVollmachtSection({required this.apiService, required this.userId});

  @override
  State<_JCVollmachtSection> createState() => _JCVollmachtSectionState();
}

class _JCVollmachtSectionState extends State<_JCVollmachtSection> with SingleTickerProviderStateMixin {
  late TabController _subTab;
  Map<String, dynamic>? _previewData;
  List<Map<String, dynamic>> _vollmachten = [];
  bool _loading = true;
  bool _generating = false;

  // Manager state
  int? _managerId;
  DateTime? _submitDate;
  String? _submitMethod;
  final _refCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _savingSubmit = false;
  bool _uploadingMember = false;
  bool _uploadingVorstand = false;
  bool _uploadingReceipt = false;

  // Options state (default: all enabled)
  final Map<String, bool> _umfang = {
    'antraege': true, 'bescheide': true, 'widerspruch': true, 'klage': true,
    'akteneinsicht': true, 'termine': true, 'egv': true, 'erklaerungen': true, 'online': true,
  };
  final Map<String, bool> _digital = {
    'konto_zugriff': true, 'antraege_online': true, 'postfach': true, 'veraenderungen': true,
  };
  final Map<String, bool> _zugang = {
    'verein_to_member': true, 'member_to_verein': true,
  };
  DateTime _validFrom = DateTime.now();
  DateTime? _validUntil;

  @override
  void initState() {
    super.initState();
    _subTab = TabController(length: 3, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _subTab.dispose();
    _refCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final dataRes = await widget.apiService.getVollmachtData(widget.userId, 'jobcenter');
    final listRes = await widget.apiService.listVollmachten(widget.userId, 'jobcenter');
    if (!mounted) return;
    setState(() {
      _loading = false;
      // jsonResponse() in PHP spreads data into the root via array_merge,
      // so user/vorsitzer/verein/vollmachten are top-level fields, not under 'data'.
      if (dataRes['success'] == true) {
        _previewData = {
          'user':          Map<String, dynamic>.from(dataRes['user']          ?? {}),
          'user_behoerde': Map<String, dynamic>.from(dataRes['user_behoerde'] ?? {}),
          'vorsitzer':     Map<String, dynamic>.from(dataRes['vorsitzer']     ?? {}),
          'verein':        Map<String, dynamic>.from(dataRes['verein']        ?? {}),
        };
      }
      if (listRes['success'] == true) {
        _vollmachten = List<Map<String, dynamic>>.from(listRes['vollmachten'] ?? []);
      }
    });
  }

  Future<void> _generate() async {
    setState(() => _generating = true);
    final res = await widget.apiService.createVollmacht({
      'user_id': widget.userId,
      'behoerde': 'jobcenter',
      'valid_from': _validFrom.toIso8601String().substring(0, 10),
      'valid_until': _validUntil?.toIso8601String().substring(0, 10),
      'options': {'umfang': _umfang, 'digital': _digital, 'zugang': _zugang},
    });
    if (!mounted) return;
    setState(() => _generating = false);
    final ok = res['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Vollmacht erstellt (ID ${res['id']})' : (res['message'] ?? 'Fehler')),
      backgroundColor: ok ? Colors.green : Colors.red,
    ));
    if (ok) _loadAll();
  }

  Future<void> _revoke(int id) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vollmacht widerrufen'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Diese Vollmacht wird als widerrufen markiert. Die Zugangsdaten zum BA-Konto muss das Mitglied eigenverantwortlich ändern.', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(controller: reasonCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Grund (optional)', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('Widerrufen')),
        ],
      ),
    );
    if (confirmed != true) return;
    final res = await widget.apiService.revokeVollmacht(id, reason: reasonCtrl.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(res['success'] == true ? 'Vollmacht widerrufen' : (res['message'] ?? 'Fehler')),
      backgroundColor: res['success'] == true ? Colors.orange : Colors.red,
    ));
    if (res['success'] == true) _loadAll();
  }

  Future<void> _openPdf(int id, String filename, {String type = 'pdf'}) async {
    try {
      final response = await widget.apiService.downloadVollmachtPdf(id, type: type);
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        if (mounted) FileViewerDialog.showFromBytes(context, response.bodyBytes, filename);
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler (${response.statusCode})'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final user = _previewData?['user'] as Map<String, dynamic>? ?? {};
    final vorsitzer = _previewData?['vorsitzer'] as Map<String, dynamic>? ?? {};
    final verein = _previewData?['verein'] as Map<String, dynamic>? ?? {};

    return Column(children: [
      TabBar(
        controller: _subTab,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        tabs: const [
          Tab(icon: Icon(Icons.add_circle, size: 16), text: 'Generation'),
          Tab(icon: Icon(Icons.history, size: 16), text: 'Historie'),
          Tab(icon: Icon(Icons.manage_accounts, size: 16), text: 'Manager'),
        ],
      ),
      Expanded(child: TabBarView(controller: _subTab, children: [
        _buildGenerationTab(user, vorsitzer, verein),
        _buildHistorieTab(),
        _buildManagerTab(user, vorsitzer),
      ])),
    ]);
  }

  Widget _buildGenerationTab(Map<String, dynamic> user, Map<String, dynamic> vorsitzer, Map<String, dynamic> verein) {
    final missing = <String>[];
    if ((user['vorname'] ?? '').toString().isEmpty || (user['nachname'] ?? '').toString().isEmpty) missing.add('Name (Stufe 1)');
    if ((user['geburtsdatum'] ?? '').toString().isEmpty) missing.add('Geburtsdatum');
    if ((user['strasse'] ?? '').toString().isEmpty || (user['plz'] ?? '').toString().isEmpty) missing.add('Anschrift');
    if ((vorsitzer['vorname'] ?? '').toString().isEmpty) missing.add('Vorsitzender');
    if ((verein['vereinsname'] ?? '').toString().isEmpty) missing.add('Vereinsdaten');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Vollmacht — Jobcenter', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
        const SizedBox(height: 4),
        const Text('§ 13 SGB X i.V.m. § 38 SGB II — generiert nach den unten gewählten Optionen.', style: TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 12),

        // Preview header — partile auto-completate din DB
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.indigo.shade200)),
          child: Builder(builder: (_) {
            final ub = (_previewData?['user_behoerde'] as Map?) ?? const {};
            final knr = (ub['kundennummer'] ?? '').toString();
            final dst = (ub['dienststelle'] ?? '').toString();
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _kv('Mitglied', '${user['vorname'] ?? ''} ${user['nachname'] ?? ''} — geb. ${user['geburtsdatum'] ?? '?'} in ${user['geburtsort'] ?? '?'}'),
              _kv('Anschrift', '${user['strasse'] ?? ''} ${user['hausnummer'] ?? ''}, ${user['plz'] ?? ''} ${user['ort'] ?? ''}'),
              _kv('Kundennummer BA', knr.isEmpty ? '?' : knr),
              _kv('Zust. Agentur', dst.isEmpty ? '?' : dst),
              _kv('Vorsitzender', '${vorsitzer['vorname'] ?? ''} ${vorsitzer['nachname'] ?? ''}'),
              _kv('Verein', '${verein['vereinsname'] ?? ''} — VR ${verein['registernummer'] ?? ''} (${verein['registergericht'] ?? ''})'),
            ]);
          }),
        ),
        if (missing.isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.red.shade50, border: Border.all(color: Colors.red.shade300)),
            child: Row(children: [
              Icon(Icons.warning, color: Colors.red.shade700, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text('Fehlende Pflichtdaten in Verifizierung Stufe 1: ${missing.join(", ")}', style: TextStyle(fontSize: 12, color: Colors.red.shade900))),
            ]),
          ),
        ),

        const SizedBox(height: 18),
        _sectionTitle(Icons.checklist, 'Umfang der Vollmacht'),
        ..._buildCheckboxes(_umfang, const {
          'antraege': 'Anträge stellen, ändern, zurücknehmen (ALG I, Bildungsgutschein, Reha, EGL)',
          'bescheide': 'Bescheide und sämtliche Korrespondenz empfangen',
          'widerspruch': 'Unterstützung bei Widersprüchen (Hilfestellung, kein RDG)',
          'klage': 'Unterstützung bei Klage vor Sozialgericht (§ 73 SGG, keine anwaltliche Vertretung)',
          'akteneinsicht': 'Akteneinsicht und Auskünfte',
          'termine': 'Teilnahme an Beratungs- / Vermittlungsgesprächen',
          'egv': 'Eingliederungsvereinbarung (EGV) abschließen / ändern / aufheben',
          'erklaerungen': 'Erklärungen zur Arbeitssuche, Verfügbarkeit, Mitwirkung',
          'online': 'Nutzung der Online-Angebote der BA',
        }),

        const SizedBox(height: 14),
        _sectionTitle(Icons.cloud, 'Digitale Vertretung (Online-Handeln)'),
        ..._buildCheckboxes(_digital, const {
          'konto_zugriff': 'Online-Zugriff auf das BA-Kundenkonto',
          'antraege_online': 'Online-Anträge stellen / ändern / zurücknehmen',
          'postfach': 'Postfachnachrichten lesen / senden',
          'veraenderungen': 'Veränderungsmeldungen online',
        }),

        const SizedBox(height: 14),
        _sectionTitle(Icons.swap_horiz, 'Wechselseitige Zugangsgewährung'),
        ..._buildCheckboxes(_zugang, const {
          'verein_to_member': 'Verein → Mitglied: voller Zugang zur Vorsitzer-Plattform (E-Mail + Passwort + 2FA / KeyAccess)',
          'member_to_verein': 'Mitglied → Verein: voller Zugang zum BA-Kundenkonto (Login-Daten oder eVollmacht)',
        }),

        const SizedBox(height: 14),
        _sectionTitle(Icons.event, 'Gültigkeit'),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Row(children: [
          Expanded(child: ListTile(
            dense: true,
            title: const Text('Gültig ab', style: TextStyle(fontSize: 12)),
            subtitle: Text(DateFormat('dd.MM.yyyy').format(_validFrom), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            trailing: const Icon(Icons.calendar_today, size: 16),
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: _validFrom, firstDate: DateTime(2020), lastDate: DateTime(2099));
              if (d != null) setState(() => _validFrom = d);
            },
          )),
          Expanded(child: ListTile(
            dense: true,
            title: const Text('Gültig bis (optional)', style: TextStyle(fontSize: 12)),
            subtitle: Text(_validUntil != null ? DateFormat('dd.MM.yyyy').format(_validUntil!) : 'auf Widerruf', style: const TextStyle(fontSize: 13)),
            trailing: _validUntil != null
                ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () => setState(() => _validUntil = null))
                : const Icon(Icons.calendar_today, size: 16),
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: _validUntil ?? _validFrom.add(const Duration(days: 365)), firstDate: _validFrom, lastDate: DateTime(2099));
              if (d != null) setState(() => _validUntil = d);
            },
          )),
        ])),

        const SizedBox(height: 20),
        Center(child: ElevatedButton.icon(
          icon: _generating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.picture_as_pdf),
          label: Text(_generating ? 'Generiere…' : 'PDF generieren & speichern'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
          onPressed: (_generating || missing.isNotEmpty) ? null : _generate,
        )),
      ]),
    );
  }

  Widget _buildHistorieTab() {
    if (_vollmachten.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Noch keine Vollmacht generiert.', style: TextStyle(color: Colors.grey))));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _vollmachten.length,
      itemBuilder: (_, i) {
        final v = _vollmachten[i];
        final status = (v['status'] ?? '').toString();
        final color = switch (status) {
          'active' => Colors.green, 'draft' => Colors.blue, 'revoked' => Colors.red, 'expired' => Colors.grey, _ => Colors.grey,
        };
        final filename = (v['pdf_filename'] ?? 'vollmacht_${v['id']}.pdf').toString();
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(Icons.picture_as_pdf, color: color),
            title: Text('Vollmacht #${v['id']} — ${status.toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Erstellt: ${v['generated_at'] ?? ''}', style: const TextStyle(fontSize: 11)),
              Text('Gültig: ${v['valid_from'] ?? ''} → ${v['valid_until'] ?? 'auf Widerruf'}', style: const TextStyle(fontSize: 11)),
              if (status == 'revoked') Text('Widerrufen: ${v['revoked_at'] ?? ''}', style: TextStyle(fontSize: 11, color: Colors.red.shade700)),
              const SizedBox(height: 2),
              const Text('Tippen zum Öffnen', style: TextStyle(fontSize: 10, color: Colors.blueGrey, fontStyle: FontStyle.italic)),
            ]),
            trailing: status != 'revoked'
                ? IconButton(icon: const Icon(Icons.cancel, size: 20, color: Colors.red), tooltip: 'Widerrufen', onPressed: () => _revoke(v['id']))
                : null,
            onTap: () => _openPdf(v['id'], filename),
          ),
        );
      },
    );
  }

  Widget _kv(String k, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 1), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    SizedBox(width: 90, child: Text(k, style: const TextStyle(fontSize: 11, color: Colors.grey))),
    Expanded(child: Text(v, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
  ]));

  Widget _sectionTitle(IconData icon, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Icon(icon, size: 16, color: Colors.indigo.shade700), const SizedBox(width: 6),
      Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
    ]),
  );

  List<Widget> _buildCheckboxes(Map<String, bool> state, Map<String, String> labels) {
    return labels.entries.map((e) => CheckboxListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(e.value, style: const TextStyle(fontSize: 12)),
      value: state[e.key] ?? false,
      onChanged: (v) => setState(() => state[e.key] = v ?? false),
    )).toList();
  }

  // ═══════════════════════════════════════════════════════════════════
  //  Manager tab
  // ═══════════════════════════════════════════════════════════════════

  Map<String, dynamic>? _selectedManager() {
    if (_vollmachten.isEmpty) return null;
    final id = _managerId ?? (_vollmachten.first['id'] as int);
    return _vollmachten.firstWhere((v) => v['id'] == id, orElse: () => _vollmachten.first);
  }

  Widget _buildManagerTab(Map<String, dynamic> user, Map<String, dynamic> vorsitzer) {
    if (_vollmachten.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(24),
        child: Text('Noch keine Vollmacht generiert. Bitte zuerst eine Vollmacht generieren.', style: TextStyle(color: Colors.grey), textAlign: TextAlign.center)));
    }
    final v = _selectedManager()!;
    // Sync local controllers / pickers with selected vollmacht — only on first build per selection
    if (_managerId != v['id']) {
      _managerId = v['id'] as int;
      _submitDate = (v['submitted_at'] != null && (v['submitted_at'] as String).isNotEmpty)
          ? DateTime.tryParse(v['submitted_at']) : null;
      _submitMethod = v['submitted_method'];
      _refCtrl.text = (v['submitted_reference'] ?? '').toString();
      _notesCtrl.text = (v['submitted_notes'] ?? '').toString();
    }

    final status = (v['status'] ?? '').toString();
    final hasMemberSig = (v['signature_member_filename'] ?? '').toString().isNotEmpty;
    final hasVorstandSig = (v['signature_vorstand_filename'] ?? '').toString().isNotEmpty;
    final hasReceipt = (v['submitted_receipt_filename'] ?? '').toString().isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Selector
        DropdownButtonFormField<int>(
          initialValue: _managerId,
          decoration: const InputDecoration(labelText: 'Aktive Vollmacht', isDense: true, border: OutlineInputBorder()),
          items: _vollmachten.map((vv) {
            return DropdownMenuItem<int>(
              value: vv['id'] as int,
              child: Text('#${vv['id']} — ${vv['valid_from']} — ${(vv['status'] ?? '').toString().toUpperCase()}', style: const TextStyle(fontSize: 13)),
            );
          }).toList(),
          onChanged: (id) {
            if (id == null) return;
            setState(() {
              _managerId = id;
              final vv = _vollmachten.firstWhere((x) => x['id'] == id);
              _submitDate = (vv['submitted_at'] != null && (vv['submitted_at'] as String).isNotEmpty)
                  ? DateTime.tryParse(vv['submitted_at']) : null;
              _submitMethod = vv['submitted_method'];
              _refCtrl.text = (vv['submitted_reference'] ?? '').toString();
              _notesCtrl.text = (vv['submitted_notes'] ?? '').toString();
            });
          },
        ),
        const SizedBox(height: 16),

        // STATUS
        _managerBlock('Status der Vollmacht', Icons.info_outline, Column(children: [
          _kv('Generiert', (v['generated_at'] ?? '').toString()),
          _kv('Gültig ab', (v['valid_from'] ?? '').toString()),
          _kv('Gültig bis', (v['valid_until'] ?? 'auf Widerruf').toString()),
          Row(children: [
            const SizedBox(width: 90, child: Text('Status', style: TextStyle(fontSize: 11, color: Colors.grey))),
            _statusBadge(status),
          ]),
        ])),

        const SizedBox(height: 12),

        // UNTERSCHRIFTEN
        _managerBlock('Unterschriften (eigenhändig)', Icons.draw, Column(children: [
          Padding(padding: const EdgeInsets.only(bottom: 8),
            child: Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.amber.shade50, border: Border.all(color: Colors.amber.shade300)),
              child: Row(children: [
                Icon(Icons.info, color: Colors.amber.shade800, size: 18), const SizedBox(width: 6),
                const Expanded(child: Text('Procedure: PDF ausdrucken → eigenhändig unterschreiben → einscannen → hier hochladen (PDF, JPG oder PNG, max 10 MB)', style: TextStyle(fontSize: 11))),
              ]))),
          Row(children: [
            Expanded(child: _signatureCard(
              label: 'Vollmachtgeber (Mitglied)',
              name: '${user['vorname'] ?? ''} ${user['nachname'] ?? ''}',
              has: hasMemberSig,
              uploadedAt: v['signature_member_uploaded_at'],
              uploading: _uploadingMember,
              vollmachtId: v['id'],
              signer: 'member',
            )),
            const SizedBox(width: 8),
            Expanded(child: _signatureCard(
              label: '1. Vorsitzender',
              name: '${vorsitzer['vorname'] ?? ''} ${vorsitzer['nachname'] ?? ''}',
              has: hasVorstandSig,
              uploadedAt: v['signature_vorstand_uploaded_at'],
              uploading: _uploadingVorstand,
              vollmachtId: v['id'],
              signer: 'vorstand',
            )),
          ]),
        ])),

        const SizedBox(height: 12),

        // EINREICHUNG
        _managerBlock('Einreichung bei der Agentur für Arbeit', Icons.send, Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Eingereicht am', style: TextStyle(fontSize: 12)),
            subtitle: Text(_submitDate != null ? DateFormat('dd.MM.yyyy').format(_submitDate!) : '— noch nicht eingereicht —', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_submitDate != null) IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => setState(() => _submitDate = null)),
              IconButton(icon: const Icon(Icons.calendar_today, size: 18), onPressed: () async {
                final d = await showDatePicker(context: context, initialDate: _submitDate ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2099));
                if (d != null) setState(() => _submitDate = d);
              }),
            ]),
          ),
          const Divider(height: 8),
          const Padding(padding: EdgeInsets.only(top: 4, bottom: 4), child: Text('Methode', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
          ..._methodOptions(),
          const SizedBox(height: 8),
          TextField(controller: _refCtrl, decoration: const InputDecoration(labelText: 'Aktenzeichen / Sendungsnummer (optional)', isDense: true, border: OutlineInputBorder()), style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          // Receipt upload
          Row(children: [
            Icon(hasReceipt ? Icons.check_circle : Icons.attach_file, size: 18, color: hasReceipt ? Colors.green : Colors.grey),
            const SizedBox(width: 6),
            Expanded(child: Text(hasReceipt ? 'Empfangsbeleg vorhanden' : 'Empfangsbeleg (optional)', style: const TextStyle(fontSize: 12))),
            if (_uploadingReceipt) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            else TextButton.icon(icon: const Icon(Icons.upload_file, size: 16), label: const Text('Upload', style: TextStyle(fontSize: 11)), onPressed: () => _pickAndUpload(v['id'], 'receipt')),
            if (hasReceipt) IconButton(icon: const Icon(Icons.visibility, size: 18), onPressed: () => _openPdf(v['id'], 'empfangsbeleg.pdf', type: 'receipt')),
          ]),
          const SizedBox(height: 8),
          TextField(controller: _notesCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Notizen (optional)', isDense: true, border: OutlineInputBorder()), style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            ElevatedButton.icon(
              icon: _savingSubmit ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save),
              label: const Text('Speichern'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
              onPressed: _savingSubmit ? null : () => _saveSubmission(v['id']),
            ),
          ]),
        ])),

        const SizedBox(height: 12),

        // LIFECYCLE TIMELINE
        _managerBlock('Zusammenfassung', Icons.timeline, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _timelineRow(true,  'Generiert',     v['generated_at']),
          _timelineRow(hasMemberSig,   'Mitglied-Unterschrift',  v['signature_member_uploaded_at']),
          _timelineRow(hasVorstandSig, 'Vorstand-Unterschrift',  v['signature_vorstand_uploaded_at']),
          _timelineRow(_submitDate != null, 'Eingereicht', _submitDate != null ? DateFormat('yyyy-MM-dd').format(_submitDate!) : null),
          _timelineRow(status == 'aktiv', 'Aktiv', null),
        ])),
      ]),
    );
  }

  Widget _managerBlock(String title, IconData icon, Widget child) => Card(
    margin: EdgeInsets.zero,
    elevation: 1,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 18, color: Colors.indigo.shade700), const SizedBox(width: 6),
          Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
        ]),
        const Divider(height: 12),
        child,
      ]),
    ),
  );

  Widget _statusBadge(String status) {
    final (color, label) = switch (status) {
      'draft'                  => (Colors.blue,    'DRAFT'),
      'wartet_unterschriften'  => (Colors.orange,  'WARTET AUF UNTERSCHRIFTEN'),
      'unterzeichnet'          => (Colors.lightGreen, 'UNTERZEICHNET'),
      'eingereicht'            => (Colors.green,   'EINGEREICHT'),
      'aktiv'                  => (Colors.green,   'AKTIV'),
      'revoked'                => (Colors.red,     'WIDERRUFEN'),
      'expired'                => (Colors.grey,    'ABGELAUFEN'),
      _                        => (Colors.grey,    status.toUpperCase()),
    };
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10), border: Border.all(color: color)),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)));
  }

  Widget _signatureCard({required String label, required String name, required bool has, required dynamic uploadedAt,
                         required bool uploading, required int vollmachtId, required String signer}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: has ? Colors.green.shade50 : Colors.grey.shade50,
        border: Border.all(color: has ? Colors.green.shade400 : Colors.grey.shade400),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(has ? Icons.check_circle : Icons.pending, size: 16, color: has ? Colors.green : Colors.orange),
          const SizedBox(width: 4),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
        ]),
        Text(name, style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis),
        const SizedBox(height: 6),
        if (has) ...[
          Text('Hochgeladen: $uploadedAt', style: const TextStyle(fontSize: 9, color: Colors.grey)),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.visibility, size: 14), label: const Text('Ansehen', style: TextStyle(fontSize: 10)),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4)),
              onPressed: () => _openPdf(vollmachtId, '${signer}_signature.pdf', type: 'signature_$signer'))),
            const SizedBox(width: 4),
            IconButton(icon: const Icon(Icons.delete, size: 16, color: Colors.red), tooltip: 'Entfernen',
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28), padding: EdgeInsets.zero,
              onPressed: () => _deleteSignature(vollmachtId, signer)),
          ]),
        ] else ...[
          if (uploading) const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)))
          else SizedBox(width: double.infinity, child: ElevatedButton.icon(
            icon: const Icon(Icons.upload_file, size: 14),
            label: const Text('Datei hochladen', style: TextStyle(fontSize: 10)),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 6)),
            onPressed: () => _pickAndUpload(vollmachtId, signer),
          )),
        ],
      ]),
    );
  }

  List<Widget> _methodOptions() {
    const opts = [('online', Icons.cloud, 'Online (eVollmacht / BA-Portal)'),
                  ('fax', Icons.print, 'Fax'),
                  ('persoenlich', Icons.person, 'Persönlich vor Ort'),
                  ('post', Icons.local_post_office, 'Post')];
    return opts.map((o) => RadioListTile<String>(
      dense: true,
      contentPadding: EdgeInsets.zero,
      value: o.$1,
      groupValue: _submitMethod,
      title: Row(children: [Icon(o.$2, size: 16, color: Colors.indigo.shade600), const SizedBox(width: 6), Text(o.$3, style: const TextStyle(fontSize: 12))]),
      onChanged: (v) => setState(() => _submitMethod = v),
    )).toList();
  }

  Widget _timelineRow(bool done, String label, dynamic when) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, size: 16, color: done ? Colors.green : Colors.grey),
      const SizedBox(width: 6),
      SizedBox(width: 170, child: Text(label, style: TextStyle(fontSize: 12, fontWeight: done ? FontWeight.w600 : FontWeight.normal))),
      Expanded(child: Text(when?.toString() ?? '—', style: TextStyle(fontSize: 11, color: done ? Colors.black87 : Colors.grey))),
    ]),
  );

  Future<void> _pickAndUpload(int vollmachtId, String signer) async {
    final result = await FilePickerHelper.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || result.files.single.bytes == null) return;
    final f = result.files.single;
    setState(() {
      if (signer == 'member') _uploadingMember = true;
      else if (signer == 'vorstand') _uploadingVorstand = true;
      else if (signer == 'receipt') _uploadingReceipt = true;
    });
    final res = await widget.apiService.uploadVollmachtSignature(
      vollmachtId: vollmachtId, signer: signer, bytes: f.bytes!, filename: f.name,
    );
    if (!mounted) return;
    setState(() {
      _uploadingMember = false; _uploadingVorstand = false; _uploadingReceipt = false;
    });
    final ok = res['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Hochgeladen' : (res['message'] ?? 'Fehler')),
      backgroundColor: ok ? Colors.green : Colors.red,
    ));
    if (ok) _loadAll();
  }

  Future<void> _deleteSignature(int vollmachtId, String signer) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Unterschrift entfernen?'),
      content: const Text('Die hochgeladene Datei wird gelöscht.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('Entfernen')),
      ],
    ));
    if (ok != true) return;
    final res = await widget.apiService.deleteVollmachtSignature(vollmachtId: vollmachtId, signer: signer);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(res['success'] == true ? 'Gelöscht' : (res['message'] ?? 'Fehler')),
      backgroundColor: res['success'] == true ? Colors.orange : Colors.red,
    ));
    if (res['success'] == true) _loadAll();
  }

  Future<void> _saveSubmission(int vollmachtId) async {
    setState(() => _savingSubmit = true);
    final res = await widget.apiService.submitVollmacht(
      vollmachtId: vollmachtId,
      submittedAt: _submitDate != null ? DateFormat('yyyy-MM-dd').format(_submitDate!) : null,
      method: _submitMethod,
      reference: _refCtrl.text.trim(),
      notes: _notesCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _savingSubmit = false);
    final ok = res['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Eingereicht-Status gespeichert' : (res['message'] ?? 'Fehler')),
      backgroundColor: ok ? Colors.green : Colors.red,
    ));
    if (ok) _loadAll();
  }
}
