import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../utils/brief_pdf_generator.dart';
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
    'betriebskosten_nachforderung': 'Betriebskosten-Nachforderung KdU (§22 SGB II)',
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
        DropdownButtonFormField<String>(
          initialValue: art, isExpanded: true,
          decoration: InputDecoration(labelText: 'Art', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          selectedItemBuilder: (ctx) => _artLabels.entries.map((e) => Align(alignment: Alignment.centerLeft, child: Text(e.value, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis, maxLines: 1))).toList(),
          items: _artLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (v) => setDlg(() => art = v ?? art),
        ),
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

  bool get _isBetriebskosten => widget.antrag['art']?.toString() == 'betriebskosten_nachforderung';

  @override
  void initState() {
    super.initState();
    // Betriebskosten-Nachforderung uses a reduced 5-tab modal with a PDF-Generator tab.
    // All other Antrag types keep the full 7-tab layout (Bewilligungsbescheid, EGV, Sanktionen, Begutachtung).
    _tabC = TabController(length: _isBetriebskosten ? 5 : 7, vsync: this);
  }

  @override
  void dispose() {
    _tabC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final art = _JobcenterAntragTabState._artLabels[widget.antrag['art']] ?? widget.antrag['art']?.toString() ?? '';
    final tabs = _isBetriebskosten
        ? const [
            Tab(text: 'Details'),
            Tab(text: 'Korrespondenz'),
            Tab(text: 'Terminen'),
            Tab(text: 'Bescheid'),
            Tab(text: 'Brief-Generator', icon: Icon(Icons.picture_as_pdf, size: 16)),
          ]
        : const [
            Tab(text: 'Details'),
            Tab(text: 'Korrespondenz'),
            Tab(text: 'Terminen'),
            Tab(text: 'Bewilligungsbescheid'),
            Tab(text: 'EGV'),
            Tab(text: 'Sanktionen'),
            Tab(text: 'Begutachtung'),
          ];
    final views = _isBetriebskosten
        ? [
            _AntragDetailsTab(antrag: widget.antrag, apiService: widget.apiService, userId: widget.userId, onReload: widget.onReload),
            _AntragKorrTab(antragId: widget.antrag['id'] as int, apiService: widget.apiService, userId: widget.userId),
            _AntragTerminTab(antragId: widget.antrag['id'] as int, apiService: widget.apiService, userId: widget.userId),
            _AntragBescheidTab(antrag: widget.antrag, apiService: widget.apiService, userId: widget.userId, onReload: widget.onReload),
            _BetriebskostenBriefGeneratorTab(antrag: widget.antrag, apiService: widget.apiService, userId: widget.userId),
          ]
        : [
            _AntragDetailsTab(antrag: widget.antrag, apiService: widget.apiService, userId: widget.userId, onReload: widget.onReload),
            _AntragKorrTab(antragId: widget.antrag['id'] as int, apiService: widget.apiService, userId: widget.userId),
            _AntragTerminTab(antragId: widget.antrag['id'] as int, apiService: widget.apiService, userId: widget.userId),
            _AntragBescheidTab(antrag: widget.antrag, apiService: widget.apiService, userId: widget.userId, onReload: widget.onReload),
            _AntragEgvTab(antrag: widget.antrag, apiService: widget.apiService, userId: widget.userId, onReload: widget.onReload),
            _AntragSanktionenTab(antrag: widget.antrag, apiService: widget.apiService, userId: widget.userId, onReload: widget.onReload),
            _AntragBegutachtungTab(antrag: widget.antrag, apiService: widget.apiService, userId: widget.userId, onReload: widget.onReload),
          ];
    return Column(children: [
      Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
        child: Row(children: [
          Icon(Icons.description, color: Colors.red.shade700),
          const SizedBox(width: 8),
          Expanded(child: Text(art, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.red.shade800), overflow: TextOverflow.ellipsis)),
          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        ])),
      TabBar(controller: _tabC, labelColor: Colors.red.shade800, unselectedLabelColor: Colors.grey, indicatorColor: Colors.red.shade700, isScrollable: true, tabAlignment: TabAlignment.start, tabs: tabs),
      Expanded(child: TabBarView(controller: _tabC, children: views)),
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
        Expanded(child: DropdownButtonFormField<String>(
          initialValue: _art, isExpanded: true,
          decoration: InputDecoration(labelText: 'Art', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          selectedItemBuilder: (ctx) => _JobcenterAntragTabState._artLabels.entries.map((e) => Align(alignment: Alignment.centerLeft, child: Text(e.value, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis, maxLines: 1))).toList(),
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

// ==================== SANKTIONEN TAB (LIST + MODAL DETAILS/KORRESPONDENZ/WIDERSPRUCH) ====================
class _AntragSanktionenTab extends StatefulWidget {
  final Map<String, dynamic> antrag; final ApiService apiService; final int userId; final Future<void> Function() onReload;
  const _AntragSanktionenTab({required this.antrag, required this.apiService, required this.userId, required this.onReload});
  @override State<_AntragSanktionenTab> createState() => _AntragSanktionenTabState();
}

class _AntragSanktionenTabState extends State<_AntragSanktionenTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  int get _antragId => int.tryParse(widget.antrag['id'].toString()) ?? 0;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await widget.apiService.jobcenterSanktionAction({'action': 'list', 'antrag_id': _antragId});
      final list = (res['data']?['sanktionen'] as List?) ?? (res['sanktionen'] as List?) ?? [];
      _items = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _add() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _AddEditSanktionDialog(apiService: widget.apiService, antragId: _antragId, userId: widget.userId));
    if (ok == true) await _load();
  }

  Future<void> _openDetail(Map<String, dynamic> s) async {
    await showDialog(context: context, barrierDismissible: true, builder: (_) => Dialog(insetPadding: const EdgeInsets.all(10), child: SizedBox(width: MediaQuery.of(context).size.width * 0.95, height: MediaQuery.of(context).size.height * 0.9, child: _SanktionDetailModal(apiService: widget.apiService, userId: widget.userId, sanktion: s))));
    await _load();
  }

  Future<void> _delete(int id) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Sanktion löschen?'), content: const Text('Diese Aktion löscht auch alle Anhänge, Korrespondenz und Widerspruch-Daten. Fortfahren?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')), ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Löschen', style: TextStyle(color: Colors.white)))]));
    if (ok != true) return;
    final res = await widget.apiService.jobcenterSanktionAction({'action': 'delete', 'id': id});
    if (res['success'] == true) { await _load(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Gelöscht'), backgroundColor: Colors.green.shade600)); }
  }

  Color _statusColor(String s) => switch (s) {
    'offen' => Colors.orange,
    'widerspruch_eingelegt' => Colors.blue,
    'akteneinsicht' => Colors.purple,
    'widerspruchsbescheid' => Colors.indigo,
    'klage' => Colors.deepOrange,
    'abgeschlossen' => Colors.green,
    _ => Colors.grey,
  };
  String _statusLabel(String s) => switch (s) {
    'offen' => 'Offen',
    'widerspruch_eingelegt' => 'Widerspruch eingelegt',
    'akteneinsicht' => 'Akteneinsicht',
    'widerspruchsbescheid' => 'Widerspruchsbescheid',
    'klage' => 'Klage anhängig',
    'abgeschlossen' => 'Abgeschlossen',
    _ => s,
  };

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
    return Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.warning_amber, size: 22, color: Colors.red.shade700),
        const SizedBox(width: 8),
        Text('Sanktionen / Leistungsminderung', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
        const Spacer(),
        ElevatedButton.icon(onPressed: _add, icon: const Icon(Icons.add, size: 16), label: const Text('Sanktion hinzufügen'), style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6))),
      ]),
      const SizedBox(height: 12),
      if (_items.isEmpty)
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
          child: const Row(children: [Icon(Icons.info_outline, size: 18, color: Colors.grey), SizedBox(width: 8), Expanded(child: Text('Keine Sanktionen erfasst. Klicken Sie auf "Sanktion hinzufügen" um eine neue Sanktion / Leistungsminderung anzulegen.', style: TextStyle(fontSize: 12, color: Colors.grey)))])),
      Expanded(child: ListView.separated(itemCount: _items.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (_, i) {
        final s = _items[i];
        final st = (s['status'] ?? 'offen').toString();
        final akt = (s['aktenzeichen'] ?? '').toString();
        final paragraf = (s['paragraf'] ?? '').toString();
        final prozent = (s['prozent'] ?? '').toString();
        final betrag = (s['betrag'] ?? '').toString();
        final bd = (s['bescheid_datum'] ?? '').toString();
        final zk = (s['zugang_klient_datum'] ?? '').toString();
        final frist = (s['widerspruchsfrist'] ?? '').toString();
        final id = int.tryParse(s['id'].toString()) ?? 0;
        return Material(color: Colors.white, borderRadius: BorderRadius.circular(8), elevation: 1, child: InkWell(borderRadius: BorderRadius.circular(8), onTap: () => _openDetail(s), child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.shade200)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: _statusColor(st).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)), child: Text(_statusLabel(st), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _statusColor(st)))),
              const SizedBox(width: 8),
              if (prozent.isNotEmpty) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.red.shade300)), child: Text('$prozent %', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red.shade700))),
              const Spacer(),
              IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red), tooltip: 'Löschen', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28), onPressed: () => _delete(id)),
            ]),
            const SizedBox(height: 6),
            if (akt.isNotEmpty) Text('Az.: $akt', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            if (paragraf.isNotEmpty) Text(paragraf, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
            if (betrag.isNotEmpty) Text('Minderungsbetrag: $betrag €', style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 4),
            Wrap(spacing: 12, runSpacing: 2, children: [
              if (bd.isNotEmpty) Text('Bescheid: $bd', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
              if (zk.isNotEmpty) Text('Zugang Klient: $zk', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
              if (frist.isNotEmpty) Text('Frist Widerspruch: $frist', style: const TextStyle(fontSize: 10, color: Colors.deepOrange, fontWeight: FontWeight.bold)),
            ]),
          ]),
        )));
      })),
    ]));
  }
}

// -------- Add/Edit Sanktion Dialog --------
class _AddEditSanktionDialog extends StatefulWidget {
  final ApiService apiService; final int antragId; final int userId;
  final Map<String, dynamic>? existing;
  const _AddEditSanktionDialog({required this.apiService, required this.antragId, required this.userId, this.existing});
  @override State<_AddEditSanktionDialog> createState() => _AddEditSanktionDialogState();
}

class _AddEditSanktionDialogState extends State<_AddEditSanktionDialog> {
  late TextEditingController _aktC, _grundC, _paraC, _prozC, _betragC, _zvC, _zbC, _bdC, _vdC, _zkC, _zuC, _notizC;
  String _status = 'offen';
  bool _saving = false;

  @override void initState() {
    super.initState();
    final e = widget.existing ?? {};
    _aktC = TextEditingController(text: e['aktenzeichen']?.toString() ?? '');
    _grundC = TextEditingController(text: e['grund']?.toString() ?? '');
    _paraC = TextEditingController(text: e['paragraf']?.toString() ?? '');
    _prozC = TextEditingController(text: e['prozent']?.toString() ?? '');
    _betragC = TextEditingController(text: e['betrag']?.toString() ?? '');
    _zvC = TextEditingController(text: e['zeitraum_von']?.toString() ?? '');
    _zbC = TextEditingController(text: e['zeitraum_bis']?.toString() ?? '');
    _bdC = TextEditingController(text: e['bescheid_datum']?.toString() ?? '');
    _vdC = TextEditingController(text: e['versand_datum']?.toString() ?? '');
    _zkC = TextEditingController(text: e['zugang_klient_datum']?.toString() ?? '');
    _zuC = TextEditingController(text: e['zugang_uns_datum']?.toString() ?? '');
    _notizC = TextEditingController(text: e['notiz']?.toString() ?? '');
    _status = e['status']?.toString() ?? 'offen';
  }
  @override void dispose() { for (final c in [_aktC,_grundC,_paraC,_prozC,_betragC,_zvC,_zbC,_bdC,_vdC,_zkC,_zuC,_notizC]) { c.dispose(); } super.dispose(); }

  Future<void> _pickDate(TextEditingController c) async {
    DateTime? init;
    if (c.text.isNotEmpty) { try { final p = c.text.split('.'); if (p.length == 3) init = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0])); } catch (_) {} }
    final d = await showDatePicker(context: context, initialDate: init ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
    if (d != null) c.text = '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}';
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final payload = {
      'aktenzeichen': _aktC.text.trim(),
      'grund': _grundC.text.trim(),
      'paragraf': _paraC.text.trim(),
      'prozent': _prozC.text.trim(),
      'betrag': _betragC.text.trim(),
      'zeitraum_von': _zvC.text.trim(),
      'zeitraum_bis': _zbC.text.trim(),
      'bescheid_datum': _bdC.text.trim(),
      'versand_datum': _vdC.text.trim(),
      'zugang_klient_datum': _zkC.text.trim(),
      'zugang_uns_datum': _zuC.text.trim(),
      'notiz': _notizC.text.trim(),
      'status': _status,
    };
    final res = widget.existing == null
        ? await widget.apiService.jobcenterSanktionAction({'action': 'create', 'antrag_id': widget.antragId, 'user_id': widget.userId, 'sanktion': payload})
        : await widget.apiService.jobcenterSanktionAction({'action': 'update', 'id': widget.existing!['id'], 'sanktion': payload});
    if (mounted) {
      if (res['success'] == true) Navigator.pop(context, true);
      else { setState(() => _saving = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: ${res['message'] ?? 'Unbekannt'}'), backgroundColor: Colors.red)); }
    }
  }

  Widget _f(String label, TextEditingController c, {int maxLines = 1, IconData? icon, String? hint}) => Padding(padding: const EdgeInsets.only(bottom: 8), child: TextField(controller: c, maxLines: maxLines, decoration: InputDecoration(labelText: label, hintText: hint, prefixIcon: icon != null ? Icon(icon, size: 18) : null, isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), style: const TextStyle(fontSize: 12)));
  Widget _dt(String label, TextEditingController c) => Padding(padding: const EdgeInsets.only(bottom: 8), child: TextField(controller: c, readOnly: true, onTap: () => _pickDate(c), decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.calendar_today, size: 16), suffixIcon: c.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () => setState(() => c.clear())) : null, isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), style: const TextStyle(fontSize: 12)));

  @override Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Neue Sanktion' : 'Sanktion bearbeiten', style: const TextStyle(fontSize: 16)),
      content: SizedBox(width: 600, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _f('Aktenzeichen Bescheid', _aktC, icon: Icons.numbers),
        _f('Paragraf', _paraC, icon: Icons.gavel, hint: 'z.B. § 31a Abs. 1 SGB II'),
        Row(children: [
          Expanded(child: _f('Minderung (%)', _prozC, icon: Icons.percent, hint: '10/20/30/100')),
          const SizedBox(width: 8),
          Expanded(child: _f('Betrag (€)', _betragC, icon: Icons.euro, hint: '0.00')),
        ]),
        Row(children: [Expanded(child: _dt('Zeitraum von', _zvC)), const SizedBox(width: 8), Expanded(child: _dt('Zeitraum bis', _zbC))]),
        _f('Grund der Sanktion', _grundC, maxLines: 2, icon: Icons.description),
        const Divider(height: 18),
        Text('Zustellung', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
        const SizedBox(height: 6),
        Row(children: [Expanded(child: _dt('Bescheid-Datum (auf Brief)', _bdC)), const SizedBox(width: 8), Expanded(child: _dt('Versand (Plicul generiert)', _vdC))]),
        Row(children: [Expanded(child: _dt('Zugang beim Klienten', _zkC)), const SizedBox(width: 8), Expanded(child: _dt('Zugang bei uns (Verein)', _zuC))]),
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.amber.shade300)), child: const Row(children: [Icon(Icons.info_outline, size: 14, color: Colors.amber), SizedBox(width: 6), Expanded(child: Text('Widerspruchsfrist = Zugang Klient + 1 Monat (§ 84 SGG). Wird automatisch berechnet.', style: TextStyle(fontSize: 10, color: Colors.brown)))])),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(initialValue: _status, decoration: InputDecoration(labelText: 'Status', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), items: const [
          DropdownMenuItem(value: 'offen', child: Text('Offen')),
          DropdownMenuItem(value: 'widerspruch_eingelegt', child: Text('Widerspruch eingelegt')),
          DropdownMenuItem(value: 'akteneinsicht', child: Text('Akteneinsicht')),
          DropdownMenuItem(value: 'widerspruchsbescheid', child: Text('Widerspruchsbescheid erhalten')),
          DropdownMenuItem(value: 'klage', child: Text('Klage anhängig')),
          DropdownMenuItem(value: 'abgeschlossen', child: Text('Abgeschlossen')),
        ], onChanged: (v) => setState(() => _status = v ?? 'offen')),
        const SizedBox(height: 8),
        _f('Notizen', _notizC, maxLines: 3, icon: Icons.notes),
      ]))),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Abbrechen')),
        ElevatedButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save, size: 16), label: const Text('Speichern'), style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white)),
      ],
    );
  }
}

// -------- Sanktion Detail Modal (Details/Korrespondenz/Widerspruch) --------
class _SanktionDetailModal extends StatefulWidget {
  final ApiService apiService; final int userId; final Map<String, dynamic> sanktion;
  const _SanktionDetailModal({required this.apiService, required this.userId, required this.sanktion});
  @override State<_SanktionDetailModal> createState() => _SanktionDetailModalState();
}

class _SanktionDetailModalState extends State<_SanktionDetailModal> with SingleTickerProviderStateMixin {
  late TabController _tabC;
  late Map<String, dynamic> _s;
  int get _sId => int.tryParse(_s['id'].toString()) ?? 0;

  @override void initState() { super.initState(); _tabC = TabController(length: 3, vsync: this); _s = Map<String, dynamic>.from(widget.sanktion); }
  @override void dispose() { _tabC.dispose(); super.dispose(); }

  Future<void> _reload() async {
    final res = await widget.apiService.jobcenterSanktionAction({'action': 'list', 'antrag_id': _s['antrag_id']});
    final list = (res['data']?['sanktionen'] as List?) ?? (res['sanktionen'] as List?) ?? [];
    for (final e in list) {
      final m = Map<String, dynamic>.from(e as Map);
      if (m['id'].toString() == _s['id'].toString()) { if (mounted) setState(() => _s = m); return; }
    }
  }

  @override Widget build(BuildContext context) {
    final akt = (_s['aktenzeichen'] ?? '').toString();
    return Column(children: [
      Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
        child: Row(children: [Icon(Icons.warning_amber, color: Colors.red.shade700), const SizedBox(width: 8), Expanded(child: Text('Sanktion${akt.isNotEmpty ? " — Az. $akt" : ""}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.red.shade800), overflow: TextOverflow.ellipsis)), IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))])),
      TabBar(controller: _tabC, labelColor: Colors.red.shade800, unselectedLabelColor: Colors.grey, indicatorColor: Colors.red.shade700, tabs: const [Tab(text: 'Details', icon: Icon(Icons.info_outline, size: 16)), Tab(text: 'Korrespondenz', icon: Icon(Icons.forum, size: 16)), Tab(text: 'Widerspruch', icon: Icon(Icons.gavel, size: 16))]),
      Expanded(child: TabBarView(controller: _tabC, children: [
        _SanktionDetailsTab(apiService: widget.apiService, sanktion: _s, onReload: _reload),
        _SanktionKorrTab(apiService: widget.apiService, sanktionId: _sId),
        _SanktionWiderspruchTab(apiService: widget.apiService, sanktion: _s, onReload: _reload),
      ])),
    ]);
  }
}

// -------- Sanktion Details Tab (edit + files) --------
class _SanktionDetailsTab extends StatefulWidget {
  final ApiService apiService; final Map<String, dynamic> sanktion; final Future<void> Function() onReload;
  const _SanktionDetailsTab({required this.apiService, required this.sanktion, required this.onReload});
  @override State<_SanktionDetailsTab> createState() => _SanktionDetailsTabState();
}

class _SanktionDetailsTabState extends State<_SanktionDetailsTab> {
  bool _uploading = false;
  int get _sId => int.tryParse(widget.sanktion['id'].toString()) ?? 0;

  Future<void> _edit() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _AddEditSanktionDialog(apiService: widget.apiService, antragId: int.tryParse(widget.sanktion['antrag_id'].toString()) ?? 0, userId: int.tryParse(widget.sanktion['user_id'].toString()) ?? 0, existing: widget.sanktion));
    if (ok == true) await widget.onReload();
  }

  Future<void> _pickAndUpload() async {
    final res = await FilePickerHelper.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf','jpg','jpeg','png','heic','heif'], withData: true, allowMultiple: true);
    if (res == null || res.files.isEmpty) return;
    setState(() => _uploading = true);
    int ok = 0;
    for (final f in res.files) {
      if (f.bytes == null) continue;
      final r = await widget.apiService.uploadJobcenterSanktionFile(sanktionId: _sId, bytes: f.bytes!, filename: f.name);
      if (r['success'] == true) ok++;
    }
    if (mounted) setState(() => _uploading = false);
    await widget.onReload();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$ok / ${res.files.length} hochgeladen'), backgroundColor: ok > 0 ? Colors.green.shade600 : Colors.red));
  }

  Future<void> _viewFile(int fileId, String name) async {
    final r = await widget.apiService.downloadJobcenterSanktionFile(fileId);
    if (r.statusCode == 200 && mounted) await FileViewerDialog.showFromBytes(context, r.bodyBytes, name);
    else if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Konnte Datei nicht laden')));
  }

  Future<void> _deleteFile(int fileId) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Datei löschen?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')), ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Löschen', style: TextStyle(color: Colors.white)))]));
    if (ok != true) return;
    final r = await widget.apiService.jobcenterSanktionAction({'action': 'delete_file', 'file_id': fileId});
    if (r['success'] == true) await widget.onReload();
  }

  Widget _row(String label, String? value, {IconData? icon, Color? color}) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (icon != null) Icon(icon, size: 14, color: color ?? Colors.grey.shade600),
      if (icon != null) const SizedBox(width: 6),
      SizedBox(width: 150, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade700))),
      Expanded(child: Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color ?? Colors.black87))),
    ]));
  }

  @override Widget build(BuildContext context) {
    final s = widget.sanktion;
    final files = (s['files'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
    return SingleChildScrollView(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Sanktion-Details', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
        const Spacer(),
        TextButton.icon(onPressed: _edit, icon: const Icon(Icons.edit, size: 16), label: const Text('Bearbeiten')),
      ]),
      const Divider(),
      _row('Aktenzeichen:', s['aktenzeichen']?.toString(), icon: Icons.numbers),
      _row('Paragraf:', s['paragraf']?.toString(), icon: Icons.gavel),
      _row('Minderung %:', s['prozent']?.toString(), icon: Icons.percent, color: Colors.red),
      _row('Betrag (€):', s['betrag']?.toString(), icon: Icons.euro),
      _row('Zeitraum von:', s['zeitraum_von']?.toString(), icon: Icons.event),
      _row('Zeitraum bis:', s['zeitraum_bis']?.toString(), icon: Icons.event),
      _row('Grund:', s['grund']?.toString(), icon: Icons.description),
      const SizedBox(height: 8),
      Text('Zustellung', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
      const Divider(),
      _row('Bescheid-Datum:', s['bescheid_datum']?.toString(), icon: Icons.calendar_today),
      _row('Versand (Plicul):', s['versand_datum']?.toString(), icon: Icons.outbox),
      _row('Zugang Klient:', s['zugang_klient_datum']?.toString(), icon: Icons.person, color: Colors.blue),
      _row('Zugang bei uns:', s['zugang_uns_datum']?.toString(), icon: Icons.home_work),
      _row('Widerspruchsfrist:', s['widerspruchsfrist']?.toString(), icon: Icons.alarm, color: Colors.deepOrange),
      const SizedBox(height: 12),
      // ---- Files ----
      Row(children: [
        Text('Anhänge (Bescheid)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
        const Spacer(),
        TextButton.icon(onPressed: _uploading ? null : _pickAndUpload, icon: const Icon(Icons.upload_file, size: 16), label: Text(_uploading ? 'Lädt...' : 'Dateien hochladen')),
      ]),
      const Divider(),
      if (files.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Noch keine Datei hochgeladen.', style: TextStyle(fontSize: 11, color: Colors.grey))),
      ...files.map((f) {
        final fn = (f['filename'] ?? '').toString();
        final orig = (f['original_name'] ?? '').toString();
        final shown = orig.isNotEmpty ? orig : fn;
        final fid = int.tryParse(f['id'].toString()) ?? 0;
        final size = int.tryParse(f['size_bytes']?.toString() ?? '0') ?? 0;
        final sizeKb = (size / 1024).toStringAsFixed(1);
        return Container(margin: const EdgeInsets.only(bottom: 4), padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey.shade300)),
          child: Row(children: [
            const Icon(Icons.attach_file, size: 16, color: Colors.indigo),
            const SizedBox(width: 6),
            Expanded(child: Text(shown, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
            Text('${sizeKb} KB', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
            const SizedBox(width: 6),
            IconButton(icon: const Icon(Icons.visibility, size: 16), tooltip: 'Ansehen', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28), onPressed: () => _viewFile(fid, shown)),
            IconButton(icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red), tooltip: 'Löschen', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28), onPressed: () => _deleteFile(fid)),
          ]));
      }),
    ]));
  }
}

// -------- Sanktion Korrespondenz Tab --------
class _SanktionKorrTab extends StatefulWidget {
  final ApiService apiService; final int sanktionId;
  const _SanktionKorrTab({required this.apiService, required this.sanktionId});
  @override State<_SanktionKorrTab> createState() => _SanktionKorrTabState();
}

class _SanktionKorrTabState extends State<_SanktionKorrTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await widget.apiService.jobcenterSanktionAction({'action': 'korr_list', 'sanktion_id': widget.sanktionId});
    final list = (r['data']?['korrespondenz'] as List?) ?? (r['korrespondenz'] as List?) ?? [];
    _items = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addOrEdit({Map<String, dynamic>? existing}) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _SanktionKorrDialog(apiService: widget.apiService, sanktionId: widget.sanktionId, existing: existing));
    if (ok == true) await _load();
  }

  Future<void> _delete(int kid) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Korrespondenz löschen?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')), ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Löschen', style: TextStyle(color: Colors.white)))]));
    if (ok != true) return;
    final r = await widget.apiService.jobcenterSanktionAction({'action': 'korr_delete', 'id': kid});
    if (r['success'] == true) await _load();
  }

  Future<void> _viewAnhang(int aid, String name) async {
    final r = await widget.apiService.downloadJobcenterSanktionKorrAnhang(aid);
    if (r.statusCode == 200 && mounted) await FileViewerDialog.showFromBytes(context, r.bodyBytes, name);
  }

  @override Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Korrespondenz zur Sanktion', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
        const Spacer(),
        ElevatedButton.icon(onPressed: () => _addOrEdit(), icon: const Icon(Icons.add, size: 16), label: const Text('Hinzufügen'), style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6))),
      ]),
      const Divider(),
      Expanded(child: _items.isEmpty
          ? const Center(child: Text('Keine Korrespondenz erfasst.', style: TextStyle(color: Colors.grey, fontSize: 12)))
          : ListView.separated(itemCount: _items.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (_, i) {
              final k = _items[i];
              final rich = (k['richtung'] ?? 'eingang').toString();
              final isE = rich == 'eingang';
              final met = (k['methode'] ?? '').toString();
              final dat = (k['datum'] ?? '').toString();
              final subj = (k['subject'] ?? '').toString();
              final nach = (k['nachricht'] ?? '').toString();
              final anh = (k['anhaenge'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
              final kid = int.tryParse(k['id'].toString()) ?? 0;
              final MaterialColor mc = isE ? Colors.blue : Colors.green;
              return Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: mc.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8), border: Border.all(color: mc.shade200)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(isE ? Icons.call_received : Icons.call_made, size: 14, color: isE ? Colors.blue : Colors.green),
                    const SizedBox(width: 4),
                    Text(isE ? 'Eingang' : 'Ausgang', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isE ? Colors.blue : Colors.green)),
                    const SizedBox(width: 8),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(3)), child: Text(met, style: const TextStyle(fontSize: 10))),
                    const Spacer(),
                    Text(dat, style: const TextStyle(fontSize: 10)),
                    IconButton(icon: const Icon(Icons.edit, size: 14), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 26, minHeight: 26), onPressed: () => _addOrEdit(existing: k)),
                    IconButton(icon: const Icon(Icons.delete_outline, size: 14, color: Colors.red), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 26, minHeight: 26), onPressed: () => _delete(kid)),
                  ]),
                  if (subj.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(subj, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                  if (nach.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(nach, style: const TextStyle(fontSize: 11))),
                  if (anh.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Wrap(spacing: 4, runSpacing: 4, children: anh.map((a) {
                    final n = (a['original_name'] ?? a['filename'] ?? 'datei').toString();
                    final aid = int.tryParse(a['id'].toString()) ?? 0;
                    return ActionChip(label: Text(n, style: const TextStyle(fontSize: 10)), avatar: const Icon(Icons.attach_file, size: 12), onPressed: () => _viewAnhang(aid, n), visualDensity: VisualDensity.compact, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap);
                  }).toList())),
                ]));
            })),
    ]));
  }
}

// -------- Korrespondenz Add/Edit Dialog --------
class _SanktionKorrDialog extends StatefulWidget {
  final ApiService apiService; final int sanktionId; final Map<String, dynamic>? existing;
  const _SanktionKorrDialog({required this.apiService, required this.sanktionId, this.existing});
  @override State<_SanktionKorrDialog> createState() => _SanktionKorrDialogState();
}

class _SanktionKorrDialogState extends State<_SanktionKorrDialog> {
  late TextEditingController _datumC, _subjC, _nachC;
  String _rich = 'eingang', _met = 'post';
  bool _saving = false;
  List<PlatformFile> _pendingFiles = [];

  @override void initState() {
    super.initState();
    final e = widget.existing ?? {};
    _datumC = TextEditingController(text: e['datum']?.toString() ?? '');
    _subjC = TextEditingController(text: e['subject']?.toString() ?? '');
    _nachC = TextEditingController(text: e['nachricht']?.toString() ?? '');
    _rich = e['richtung']?.toString() ?? 'eingang';
    _met = e['methode']?.toString() ?? 'post';
  }
  @override void dispose() { _datumC.dispose(); _subjC.dispose(); _nachC.dispose(); super.dispose(); }

  Future<void> _pickFiles() async {
    final res = await FilePickerHelper.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf','jpg','jpeg','png','heic','heif'], withData: true, allowMultiple: true);
    if (res != null && res.files.isNotEmpty) setState(() => _pendingFiles = res.files);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final payload = {'richtung': _rich, 'methode': _met, 'datum': _datumC.text.trim(), 'subject': _subjC.text.trim(), 'nachricht': _nachC.text.trim()};
    int kid = int.tryParse(widget.existing?['id']?.toString() ?? '0') ?? 0;
    if (kid == 0) {
      final r = await widget.apiService.jobcenterSanktionAction({'action': 'korr_create', 'sanktion_id': widget.sanktionId, 'korrespondenz': payload});
      if (r['success'] == true) kid = int.tryParse(r['data']?['id']?.toString() ?? r['id']?.toString() ?? '0') ?? 0;
    } else {
      await widget.apiService.jobcenterSanktionAction({'action': 'korr_update', 'id': kid, 'korrespondenz': payload});
    }
    // upload pending files
    for (final f in _pendingFiles) {
      if (f.bytes != null && kid > 0) {
        await widget.apiService.uploadJobcenterSanktionKorrAnhang(korrId: kid, bytes: f.bytes!, filename: f.name);
      }
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Neue Korrespondenz' : 'Korrespondenz bearbeiten', style: const TextStyle(fontSize: 15)),
      content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          ChoiceChip(label: const Text('Eingang'), selected: _rich == 'eingang', onSelected: (_) => setState(() => _rich = 'eingang')),
          const SizedBox(width: 6),
          ChoiceChip(label: const Text('Ausgang'), selected: _rich == 'ausgang', onSelected: (_) => setState(() => _rich = 'ausgang')),
        ]),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(initialValue: _met, decoration: const InputDecoration(labelText: 'Methode', isDense: true, border: OutlineInputBorder()), items: const [
          DropdownMenuItem(value: 'post', child: Text('Post')),
          DropdownMenuItem(value: 'fax', child: Text('Fax')),
          DropdownMenuItem(value: 'email', child: Text('E-Mail')),
          DropdownMenuItem(value: 'online', child: Text('Online')),
          DropdownMenuItem(value: 'persoenlich', child: Text('Persönlich')),
          DropdownMenuItem(value: 'telefon', child: Text('Telefon')),
        ], onChanged: (v) => setState(() => _met = v ?? 'post')),
        const SizedBox(height: 8),
        TextField(controller: _datumC, readOnly: true, decoration: const InputDecoration(labelText: 'Datum', prefixIcon: Icon(Icons.calendar_today, size: 16), isDense: true, border: OutlineInputBorder()),
          onTap: () async { final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de')); if (d != null) _datumC.text = '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}'; }),
        const SizedBox(height: 8),
        TextField(controller: _subjC, decoration: const InputDecoration(labelText: 'Betreff', isDense: true, border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: _nachC, maxLines: 4, decoration: const InputDecoration(labelText: 'Nachricht', isDense: true, border: OutlineInputBorder())),
        const SizedBox(height: 8),
        Row(children: [
          ElevatedButton.icon(onPressed: _pickFiles, icon: const Icon(Icons.attach_file, size: 14), label: Text(_pendingFiles.isEmpty ? 'Anhänge wählen' : '${_pendingFiles.length} Datei(en)')),
        ]),
      ]))),
      actions: [TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Abbrechen')), ElevatedButton(onPressed: _saving ? null : _save, style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white), child: const Text('Speichern'))],
    );
  }
}

// -------- Sanktion Widerspruch Tab --------
class _SanktionWiderspruchTab extends StatefulWidget {
  final ApiService apiService; final Map<String, dynamic> sanktion; final Future<void> Function() onReload;
  const _SanktionWiderspruchTab({required this.apiService, required this.sanktion, required this.onReload});
  @override State<_SanktionWiderspruchTab> createState() => _SanktionWiderspruchTabState();
}

class _SanktionWiderspruchTabState extends State<_SanktionWiderspruchTab> {
  Map<String, dynamic> _w = {};
  bool _loading = true, _saving = false;

  late TextEditingController _eingelegtAmC, _akteEinBeantC, _akteEinGewC, _begDateC, _begTextC, _berDateC, _amtsgC, _berAktC, _anwNameC, _anwDateC, _wbDateC, _klageDateC, _klageAktC, _utDateC, _notizC;
  late bool _eingelegt, _fristwahrend, _akteneinsicht, _begEingereicht, _berBeantragt, _berErhalten, _anwaltKons, _wbEingegangen, _klageEing, _utEing;
  String _eingMet = 'post', _wbErgebnis = '';

  int get _sId => int.tryParse(widget.sanktion['id'].toString()) ?? 0;

  @override void initState() { super.initState();
    _eingelegtAmC = TextEditingController();
    _akteEinBeantC = TextEditingController();
    _akteEinGewC = TextEditingController();
    _begDateC = TextEditingController();
    _begTextC = TextEditingController();
    _berDateC = TextEditingController();
    _amtsgC = TextEditingController();
    _berAktC = TextEditingController();
    _anwNameC = TextEditingController();
    _anwDateC = TextEditingController();
    _wbDateC = TextEditingController();
    _klageDateC = TextEditingController();
    _klageAktC = TextEditingController();
    _utDateC = TextEditingController();
    _notizC = TextEditingController();
    _eingelegt = false; _fristwahrend = true; _akteneinsicht = false; _begEingereicht = false;
    _berBeantragt = false; _berErhalten = false; _anwaltKons = false; _wbEingegangen = false; _klageEing = false; _utEing = false;
    _load();
  }

  @override void dispose() { for (final c in [_eingelegtAmC,_akteEinBeantC,_akteEinGewC,_begDateC,_begTextC,_berDateC,_amtsgC,_berAktC,_anwNameC,_anwDateC,_wbDateC,_klageDateC,_klageAktC,_utDateC,_notizC]) { c.dispose(); } super.dispose(); }

  Future<void> _load() async {
    final r = await widget.apiService.jobcenterSanktionAction({'action': 'widerspruch_get', 'sanktion_id': _sId});
    final w = (r['data']?['widerspruch'] as Map?) ?? (r['widerspruch'] as Map?) ?? {};
    _w = Map<String, dynamic>.from(w);
    _eingelegt = _w['eingelegt'].toString() == '1' || _w['eingelegt'] == true;
    _fristwahrend = _w['eingelegt_fristwahrend'].toString() == '1' || _w['eingelegt_fristwahrend'] == true;
    _akteneinsicht = _w['akteneinsicht_beantragt'].toString() == '1' || _w['akteneinsicht_beantragt'] == true;
    _begEingereicht = _w['begruendung_eingereicht'].toString() == '1' || _w['begruendung_eingereicht'] == true;
    _berBeantragt = _w['beratungsschein_beantragt'].toString() == '1' || _w['beratungsschein_beantragt'] == true;
    _berErhalten = _w['beratungsschein_erhalten'].toString() == '1' || _w['beratungsschein_erhalten'] == true;
    _anwaltKons = _w['anwalt_konsultiert'].toString() == '1' || _w['anwalt_konsultiert'] == true;
    _wbEingegangen = _w['widerspruchsbescheid_eingegangen'].toString() == '1' || _w['widerspruchsbescheid_eingegangen'] == true;
    _klageEing = _w['klage_eingereicht'].toString() == '1' || _w['klage_eingereicht'] == true;
    _utEing = _w['untaetigkeitsklage_eingereicht'].toString() == '1' || _w['untaetigkeitsklage_eingereicht'] == true;
    _eingMet = (_w['eingelegt_methode'] ?? 'post').toString();
    _wbErgebnis = (_w['widerspruchsbescheid_ergebnis'] ?? '').toString();
    _eingelegtAmC.text = (_w['eingelegt_am'] ?? '').toString();
    _akteEinBeantC.text = (_w['akteneinsicht_beantragt_am'] ?? '').toString();
    _akteEinGewC.text = (_w['akteneinsicht_gewaehrt_am'] ?? '').toString();
    _begDateC.text = (_w['begruendung_datum'] ?? '').toString();
    _begTextC.text = (_w['begruendung_text'] ?? '').toString();
    _berDateC.text = (_w['beratungsschein_datum'] ?? '').toString();
    _amtsgC.text = (_w['amtsgericht'] ?? '').toString();
    _berAktC.text = (_w['beratungsschein_aktenz'] ?? '').toString();
    _anwNameC.text = (_w['anwalt_name'] ?? '').toString();
    _anwDateC.text = (_w['anwalt_datum'] ?? '').toString();
    _wbDateC.text = (_w['widerspruchsbescheid_datum'] ?? '').toString();
    _klageDateC.text = (_w['klage_datum'] ?? '').toString();
    _klageAktC.text = (_w['klage_aktenz'] ?? '').toString();
    _utDateC.text = (_w['untaetigkeitsklage_datum'] ?? '').toString();
    _notizC.text = (_w['notiz'] ?? '').toString();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final payload = {
      'eingelegt': _eingelegt,
      'eingelegt_am': _eingelegtAmC.text.trim(),
      'eingelegt_methode': _eingMet,
      'eingelegt_fristwahrend': _fristwahrend,
      'akteneinsicht_beantragt': _akteneinsicht,
      'akteneinsicht_beantragt_am': _akteEinBeantC.text.trim(),
      'akteneinsicht_gewaehrt_am': _akteEinGewC.text.trim(),
      'begruendung_eingereicht': _begEingereicht,
      'begruendung_datum': _begDateC.text.trim(),
      'begruendung_text': _begTextC.text.trim(),
      'beratungsschein_beantragt': _berBeantragt,
      'beratungsschein_datum': _berDateC.text.trim(),
      'amtsgericht': _amtsgC.text.trim(),
      'beratungsschein_erhalten': _berErhalten,
      'beratungsschein_aktenz': _berAktC.text.trim(),
      'anwalt_konsultiert': _anwaltKons,
      'anwalt_name': _anwNameC.text.trim(),
      'anwalt_datum': _anwDateC.text.trim(),
      'widerspruchsbescheid_eingegangen': _wbEingegangen,
      'widerspruchsbescheid_datum': _wbDateC.text.trim(),
      'widerspruchsbescheid_ergebnis': _wbErgebnis,
      'klage_eingereicht': _klageEing,
      'klage_datum': _klageDateC.text.trim(),
      'klage_aktenz': _klageAktC.text.trim(),
      'untaetigkeitsklage_eingereicht': _utEing,
      'untaetigkeitsklage_datum': _utDateC.text.trim(),
      'notiz': _notizC.text.trim(),
    };
    final r = await widget.apiService.jobcenterSanktionAction({'action': 'widerspruch_save', 'sanktion_id': _sId, 'widerspruch': payload});
    if (mounted) {
      setState(() => _saving = false);
      if (r['success'] == true) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Gespeichert'), backgroundColor: Colors.green.shade600)); await _load(); }
    }
  }

  Future<void> _generatePdf() async {
    final r = await widget.apiService.downloadJobcenterSanktionWiderspruchPdf(_sId);
    if (r.statusCode == 200 && mounted) {
      await FileViewerDialog.showFromBytes(context, r.bodyBytes, 'widerspruch_sanktion_${_sId}.pdf');
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Konnte PDF nicht laden (${r.statusCode})')));
    }
  }

  Future<void> _pickDate(TextEditingController c) async {
    final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
    if (d != null) setState(() => c.text = '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}');
  }

  Widget _dateField(String label, TextEditingController c) => TextField(controller: c, readOnly: true, onTap: () => _pickDate(c), decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.calendar_today, size: 14), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), style: const TextStyle(fontSize: 12));
  Widget _textField(String label, TextEditingController c, {int maxLines = 1}) => TextField(controller: c, maxLines: maxLines, decoration: InputDecoration(labelText: label, isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), style: const TextStyle(fontSize: 12));
  Widget _section(String title, IconData icon, Color color) => Padding(padding: const EdgeInsets.only(top: 12, bottom: 6), child: Row(children: [Icon(icon, size: 16, color: color), const SizedBox(width: 6), Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color))]));

  @override Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final frist = (widget.sanktion['widerspruchsfrist'] ?? '').toString();
    return SingleChildScrollView(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Info banner
      Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.blue.shade200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.gavel, size: 16, color: Colors.blue.shade700), const SizedBox(width: 6), Text('Widerspruchsverfahren — Übersicht', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade800))]),
          const SizedBox(height: 4),
          Text('• Widerspruchsfrist: 1 Monat ab Zugang (§ 84 SGG)${frist.isNotEmpty ? " — bis $frist" : ""}', style: const TextStyle(fontSize: 10)),
          const Text('• Strategie: fristwahrend einlegen → Akteneinsicht § 25 SGB X → Begründung nachreichen → Beratungshilfeschein Amtsgericht (§ 1 BerHG) → ggf. Anwalt', style: TextStyle(fontSize: 10)),
          const Text('• Behörde muss in 3 Mon. entscheiden (§ 88 SGG) — sonst Untätigkeitsklage. Klagefrist 1 Mon. ab Widerspruchsbescheid (§ 87 SGG)', style: TextStyle(fontSize: 10)),
        ])),

      _section('1. Widerspruch einlegen', Icons.send, Colors.red.shade700),
      SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Widerspruch eingelegt', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)), value: _eingelegt, onChanged: (v) => setState(() => _eingelegt = v)),
      if (_eingelegt) Column(children: [
        Row(children: [Expanded(child: _dateField('Eingelegt am', _eingelegtAmC)), const SizedBox(width: 8), Expanded(child: DropdownButtonFormField<String>(initialValue: _eingMet, decoration: const InputDecoration(labelText: 'Methode', isDense: true, border: OutlineInputBorder()), items: const [
          DropdownMenuItem(value: 'post', child: Text('Post (Einschreiben)')),
          DropdownMenuItem(value: 'fax', child: Text('Fax')),
          DropdownMenuItem(value: 'email', child: Text('E-Mail')),
          DropdownMenuItem(value: 'online', child: Text('Online-Portal')),
          DropdownMenuItem(value: 'persoenlich', child: Text('Persönlich')),
        ], onChanged: (v) => setState(() => _eingMet = v ?? 'post')))]),
        const SizedBox(height: 6),
        SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Fristwahrend (Begründung folgt)', style: TextStyle(fontSize: 11)), subtitle: const Text('Empfohlen: zuerst fristwahrend, dann Akteneinsicht und Begründung nachreichen', style: TextStyle(fontSize: 9)), value: _fristwahrend, onChanged: (v) => setState(() => _fristwahrend = v)),
      ]),

      _section('2. Akteneinsicht (§ 25 SGB X)', Icons.folder_open, Colors.purple.shade700),
      SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Akteneinsicht beantragt', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)), value: _akteneinsicht, onChanged: (v) => setState(() => _akteneinsicht = v)),
      if (_akteneinsicht) Row(children: [Expanded(child: _dateField('Beantragt am', _akteEinBeantC)), const SizedBox(width: 8), Expanded(child: _dateField('Gewährt am', _akteEinGewC))]),

      _section('3. Begründung nachgereicht', Icons.edit_note, Colors.orange.shade700),
      SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Begründung eingereicht', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)), value: _begEingereicht, onChanged: (v) => setState(() => _begEingereicht = v)),
      if (_begEingereicht) Column(children: [
        _dateField('Datum Begründung', _begDateC),
        const SizedBox(height: 6),
        _textField('Begründung-Text', _begTextC, maxLines: 4),
      ]),

      _section('4. Beratungshilfe (§ 1 BerHG)', Icons.account_balance, Colors.indigo.shade700),
      SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Beratungsschein beantragt', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)), subtitle: const Text('Amtsgericht des Wohnorts — Rechtsantragsstelle', style: TextStyle(fontSize: 10)), value: _berBeantragt, onChanged: (v) => setState(() => _berBeantragt = v)),
      if (_berBeantragt) Column(children: [
        Row(children: [Expanded(child: _dateField('Beantragt am', _berDateC)), const SizedBox(width: 8), Expanded(child: _textField('Amtsgericht', _amtsgC))]),
        const SizedBox(height: 6),
        SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Beratungsschein erhalten', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)), value: _berErhalten, onChanged: (v) => setState(() => _berErhalten = v)),
        if (_berErhalten) _textField('Az. Beratungsschein', _berAktC),
      ]),

      _section('5. Anwaltliche Vertretung', Icons.support_agent, Colors.teal.shade700),
      SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Anwalt konsultiert', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)), value: _anwaltKons, onChanged: (v) => setState(() => _anwaltKons = v)),
      if (_anwaltKons) Row(children: [Expanded(child: _textField('Anwalt-Name', _anwNameC)), const SizedBox(width: 8), Expanded(child: _dateField('Beauftragt am', _anwDateC))]),

      _section('6. Widerspruchsbescheid', Icons.mark_email_read, Colors.brown.shade700),
      SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Widerspruchsbescheid eingegangen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)), value: _wbEingegangen, onChanged: (v) => setState(() => _wbEingegangen = v)),
      if (_wbEingegangen) Column(children: [
        Row(children: [Expanded(child: _dateField('Datum', _wbDateC)), const SizedBox(width: 8), Expanded(child: DropdownButtonFormField<String>(initialValue: _wbErgebnis.isEmpty ? null : _wbErgebnis, decoration: const InputDecoration(labelText: 'Ergebnis', isDense: true, border: OutlineInputBorder()), items: const [
          DropdownMenuItem(value: 'stattgegeben', child: Text('Stattgegeben')),
          DropdownMenuItem(value: 'teilweise', child: Text('Teilweise stattgegeben')),
          DropdownMenuItem(value: 'zurueckgewiesen', child: Text('Zurückgewiesen')),
        ], onChanged: (v) => setState(() => _wbErgebnis = v ?? '')))]),
      ]),

      _section('7. Klage / Untätigkeitsklage', Icons.balance, Colors.deepOrange.shade700),
      SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Klage beim Sozialgericht eingereicht', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)), subtitle: const Text('Frist: 1 Mon. ab Widerspruchsbescheid (§ 87 SGG)', style: TextStyle(fontSize: 10)), value: _klageEing, onChanged: (v) => setState(() => _klageEing = v)),
      if (_klageEing) Row(children: [Expanded(child: _dateField('Klage-Datum', _klageDateC)), const SizedBox(width: 8), Expanded(child: _textField('Aktenzeichen Sozialgericht', _klageAktC))]),
      const SizedBox(height: 6),
      SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Untätigkeitsklage eingereicht', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)), subtitle: const Text('Möglich nach 3 Mon. ohne Entscheidung (§ 88 SGG)', style: TextStyle(fontSize: 10)), value: _utEing, onChanged: (v) => setState(() => _utEing = v)),
      if (_utEing) _dateField('Untätigkeitsklage-Datum', _utDateC),

      _section('Notizen', Icons.notes, Colors.grey.shade700),
      _textField('Notizen', _notizC, maxLines: 3),

      const SizedBox(height: 16),
      Row(children: [
        ElevatedButton.icon(onPressed: _generatePdf, icon: const Icon(Icons.picture_as_pdf, size: 16), label: const Text('Widerspruch PDF generieren'), style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade700, foregroundColor: Colors.white)),
        const Spacer(),
        ElevatedButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save, size: 16), label: const Text('Speichern'), style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white)),
      ]),
      const SizedBox(height: 10),
      Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.green.shade200)), child: const Text(
        'Die PDF-Vorlage zieht automatisch:\n• Klientendaten aus Verifizierung Stufe 1 (Name, Adresse, Geb.-Datum)\n• Jobcenter-Stammdaten (Adresse, Kundennummer, BG-Nummer)\n• Sanktion-Daten (Az., Paragraf, %, Zeitraum)\n\nEnthält: Fristwahrender Widerspruch + § 25 SGB X Akteneinsicht + § 1 BerHG Beratungshilfe + § 86b SGG aufschiebende Wirkung + § 88/§ 87 SGG Klagefristen.', style: TextStyle(fontSize: 10, color: Colors.green))),
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

// ==================== TAB 4: Arbeitsvermittler (multi-AV, pool per JC) ====================

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
  List<Map<String, dynamic>> _avList = [];
  bool _loading = true;

  String get _selectedJcName => (widget.data['stammdaten.selected_amt_name'] ?? '').toString().trim();
  String get _selectedJcOrt  => (widget.data['stammdaten.selected_amt_ort']  ?? '').toString().trim();

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await widget.apiService.jobcenterAvAction({'action': 'list_user_av', 'user_id': widget.userId});
    if (!mounted) return;
    setState(() {
      _avList = List<Map<String, dynamic>>.from(res['av_list'] ?? []);
      _loading = false;
    });
  }

  Future<void> _openAddDialog() async {
    final addedId = await showDialog<int>(
      context: context,
      builder: (_) => _AddAvDialog(
        apiService: widget.apiService,
        userId: widget.userId,
        jobcenterName: _selectedJcName,
        jobcenterOrt: _selectedJcOrt,
        existingPersonalIds: _avList.map((e) => e['personal_id'] as int).toSet(),
      ),
    );
    if (addedId != null) _load();
  }

  Future<void> _openAvModal(Map<String, dynamic> av) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AvDetailModal(apiService: widget.apiService, userId: widget.userId, userAv: av),
    );
    if (changed == true) _load();
  }

  Future<void> _unassign(int userAvId) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Arbeitsvermittler entfernen?'),
      content: const Text('Die Zuordnung wird gelöscht. Termine und Einladungen bleiben in der Historie. Der Mitarbeiter bleibt im Pool des Jobcenters.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Entfernen', style: TextStyle(color: Colors.red))),
      ],
    ));
    if (ok != true) return;
    await widget.apiService.jobcenterAvAction({'action': 'unassign_user_av', 'user_av_id': userAvId});
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: Colors.teal.shade50, border: Border(bottom: BorderSide(color: Colors.teal.shade200))),
        child: Row(children: [
          Icon(Icons.support_agent, size: 20, color: Colors.teal.shade800),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Zuständige Arbeitsvermittler', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal.shade900)),
            if (_selectedJcName.isNotEmpty) Text('@ $_selectedJcName${_selectedJcOrt.isNotEmpty ? " — $_selectedJcOrt" : ""}', style: TextStyle(fontSize: 11, color: Colors.teal.shade700)),
          ])),
          ElevatedButton.icon(
            onPressed: _openAddDialog,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Neuer Arbeitsvermittler', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
          ),
        ]),
      ),
      Expanded(child: _avList.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.person_off, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text('Noch kein Arbeitsvermittler zugeordnet', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              if (_selectedJcName.isEmpty) Text('Erst Zuständiges Jobcenter setzen', style: TextStyle(fontSize: 11, color: Colors.orange.shade700))
              else TextButton.icon(onPressed: _openAddDialog, icon: const Icon(Icons.add, size: 14), label: const Text('Hinzufügen', style: TextStyle(fontSize: 12))),
            ]))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _avList.length,
              itemBuilder: (_, i) {
                final av = _avList[i];
                final pos = av['position'] as int? ?? (i + 1);
                final rolle = (av['rolle'] ?? 'sonstige').toString();
                final termCount = av['termine_count'] as int? ?? 0;
                final einlCount = av['einladungen_count'] as int? ?? 0;
                final tel = (av['telefon'] ?? '').toString();
                final email = (av['email'] ?? '').toString();
                final zimmer = (av['zimmer'] ?? '').toString();
                final jcCached = (av['jobcenter_name'] ?? '').toString();
                final seit = (av['zustaendig_seit'] ?? '').toString();
                final bis  = (av['zustaendig_bis']  ?? '').toString();
                final aktiv = bis.isEmpty;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  elevation: 2,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => _openAvModal(av),
                    child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: Colors.teal.shade700, borderRadius: BorderRadius.circular(10)),
                          child: Text('$pos.', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text('${av['vorname'] ?? ''} ${av['nachname'] ?? ''}'.trim(), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: aktiv ? Colors.green.shade100 : Colors.grey.shade300, borderRadius: BorderRadius.circular(8)),
                          child: Text(aktiv ? 'Aktiv' : 'Inaktiv', style: TextStyle(fontSize: 10, color: aktiv ? Colors.green.shade900 : Colors.grey.shade700)),
                        ),
                        IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red), tooltip: 'Zuordnung entfernen', onPressed: () => _unassign(av['id'])),
                      ]),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(4)),
                        child: Text(rolle, style: TextStyle(fontSize: 11, color: Colors.indigo.shade800, fontWeight: FontWeight.w600)),
                      ),
                      if (jcCached.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [
                        Icon(Icons.business, size: 12, color: Colors.grey.shade600), const SizedBox(width: 4),
                        Expanded(child: Text(jcCached, style: TextStyle(fontSize: 11, color: Colors.grey.shade700))),
                      ])),
                      if (tel.isNotEmpty || email.isNotEmpty || zimmer.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Wrap(spacing: 10, children: [
                        if (tel.isNotEmpty) Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.phone, size: 11), const SizedBox(width: 2), Text(tel, style: const TextStyle(fontSize: 11))]),
                        if (email.isNotEmpty) Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.email, size: 11), const SizedBox(width: 2), Text(email, style: const TextStyle(fontSize: 11))]),
                        if (zimmer.isNotEmpty) Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.meeting_room, size: 11), const SizedBox(width: 2), Text('Zi. $zimmer', style: const TextStyle(fontSize: 11))]),
                      ])),
                      const SizedBox(height: 6),
                      Row(children: [
                        Icon(Icons.mail_outline, size: 14, color: Colors.orange.shade700), const SizedBox(width: 3),
                        Text('$einlCount Einladungen', style: const TextStyle(fontSize: 11)),
                        const SizedBox(width: 12),
                        Icon(Icons.event, size: 14, color: Colors.indigo.shade700), const SizedBox(width: 3),
                        Text('$termCount Termine', style: const TextStyle(fontSize: 11)),
                        const Spacer(),
                        if (seit.isNotEmpty) Text('seit $seit', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                      ]),
                      const SizedBox(height: 4),
                      const Text('Tippen zum Öffnen →', style: TextStyle(fontSize: 10, color: Colors.blueGrey, fontStyle: FontStyle.italic)),
                    ])),
                  ),
                );
              },
            )),
    ]);
  }
}

// ==================== Add AV dialog (pick from pool or create new) ====================

class _AddAvDialog extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final String jobcenterName;
  final String jobcenterOrt;
  final Set<int> existingPersonalIds;
  const _AddAvDialog({required this.apiService, required this.userId, required this.jobcenterName, required this.jobcenterOrt, required this.existingPersonalIds});
  @override
  State<_AddAvDialog> createState() => _AddAvDialogState();
}

class _AddAvDialogState extends State<_AddAvDialog> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<Map<String, dynamic>> _pool = [];
  bool _loadingPool = true;

  // New AV form
  final _vornameC = TextEditingController();
  final _nachnameC = TextEditingController();
  final _telC = TextEditingController();
  final _emC = TextEditingController();
  final _ziC = TextEditingController();
  String _rolle = 'pAp';
  bool _saving = false;

  static const _rollen = ['pAp', 'SB_Leistung', 'Fallmanager', 'SB_Reha', 'Berufsberater', 'Teamleiter', 'Eingangszone', 'sonstige'];

  @override
  void initState() { super.initState(); _tab = TabController(length: 2, vsync: this); _loadPool(); }
  @override
  void dispose() { _tab.dispose(); _vornameC.dispose(); _nachnameC.dispose(); _telC.dispose(); _emC.dispose(); _ziC.dispose(); super.dispose(); }

  Future<void> _loadPool() async {
    final res = await widget.apiService.jobcenterAvAction({'action': 'list_personal', 'jobcenter_name': widget.jobcenterName});
    if (!mounted) return;
    setState(() {
      _pool = List<Map<String, dynamic>>.from(res['personal'] ?? []);
      _loadingPool = false;
    });
  }

  Future<void> _assign(int personalId) async {
    setState(() => _saving = true);
    final res = await widget.apiService.jobcenterAvAction({
      'action': 'assign_user_av', 'user_id': widget.userId, 'personal_id': personalId,
      'zustaendig_seit': DateTime.now().toIso8601String().substring(0, 10),
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['success'] == true) Navigator.pop(context, res['user_av_id'] as int?);
    else ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Fehler'), backgroundColor: Colors.red));
  }

  Future<void> _createAndAssign() async {
    if (_vornameC.text.trim().isEmpty && _nachnameC.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name erforderlich'), backgroundColor: Colors.red));
      return;
    }
    setState(() => _saving = true);
    final createRes = await widget.apiService.jobcenterAvAction({
      'action': 'create_personal',
      'personal': {
        'jobcenter_name': widget.jobcenterName,
        'jobcenter_ort': widget.jobcenterOrt,
        'vorname': _vornameC.text.trim(),
        'nachname': _nachnameC.text.trim(),
        'rolle': _rolle,
        'telefon': _telC.text.trim(),
        'email': _emC.text.trim(),
        'zimmer': _ziC.text.trim(),
      },
    });
    if (!mounted) return;
    if (createRes['success'] != true) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(createRes['message'] ?? 'Fehler'), backgroundColor: Colors.red));
      return;
    }
    final personalId = createRes['id'] as int;
    await _assign(personalId);
  }

  Widget _poolList() {
    if (_loadingPool) return const Center(child: CircularProgressIndicator());
    final filtered = _pool.where((p) => !widget.existingPersonalIds.contains(p['id'])).toList();
    if (filtered.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.person_search, size: 48, color: Colors.grey.shade400),
      const SizedBox(height: 12),
      Text(widget.jobcenterName.isEmpty ? 'Bitte erst Jobcenter wählen' : 'Noch keine Mitarbeiter im Pool für ${widget.jobcenterName}', style: TextStyle(color: Colors.grey.shade600), textAlign: TextAlign.center),
      const SizedBox(height: 8),
      const Text('→ Tab "Neu anlegen" verwenden', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
    ])));
    return ListView.builder(itemCount: filtered.length, itemBuilder: (_, i) {
      final p = filtered[i];
      return ListTile(
        dense: true,
        leading: CircleAvatar(backgroundColor: Colors.teal.shade100, child: Text(((p['vorname'] ?? '?') as String).isNotEmpty ? (p['vorname'] as String)[0] : '?', style: TextStyle(color: Colors.teal.shade900, fontSize: 14))),
        title: Text('${p['vorname'] ?? ''} ${p['nachname'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${p['rolle'] ?? ''}${p['zimmer'] != null && (p['zimmer'] as String).isNotEmpty ? " • Zi. ${p['zimmer']}" : ""}'),
        trailing: ElevatedButton(
          onPressed: _saving ? null : () => _assign(p['id']),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white, minimumSize: const Size(0, 32)),
          child: const Text('Zuordnen', style: TextStyle(fontSize: 12)),
        ),
      );
    });
  }

  Widget _newForm() => SingleChildScrollView(padding: const EdgeInsets.all(12), child: Column(children: [
    Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.amber.shade200)), child: Row(children: [
      Icon(Icons.info_outline, size: 16, color: Colors.amber.shade800), const SizedBox(width: 6),
      Expanded(child: Text('Wird im Pool des Jobcenters ${widget.jobcenterName.isEmpty ? "(?)" : widget.jobcenterName} angelegt und allen Mitgliedern dort sichtbar.', style: const TextStyle(fontSize: 11))),
    ])),
    const SizedBox(height: 12),
    Row(children: [
      Expanded(child: TextField(controller: _vornameC, decoration: const InputDecoration(labelText: 'Vorname', isDense: true, border: OutlineInputBorder()))),
      const SizedBox(width: 8),
      Expanded(child: TextField(controller: _nachnameC, decoration: const InputDecoration(labelText: 'Nachname', isDense: true, border: OutlineInputBorder()))),
    ]),
    const SizedBox(height: 10),
    DropdownButtonFormField<String>(
      initialValue: _rolle,
      decoration: const InputDecoration(labelText: 'Rolle', isDense: true, border: OutlineInputBorder()),
      items: _rollen.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
      onChanged: (v) => setState(() => _rolle = v ?? 'sonstige'),
    ),
    const SizedBox(height: 10),
    TextField(controller: _telC, decoration: const InputDecoration(labelText: 'Telefon / Durchwahl', isDense: true, border: OutlineInputBorder())),
    const SizedBox(height: 10),
    TextField(controller: _emC, decoration: const InputDecoration(labelText: 'E-Mail', isDense: true, border: OutlineInputBorder())),
    const SizedBox(height: 10),
    TextField(controller: _ziC, decoration: const InputDecoration(labelText: 'Zimmer', isDense: true, border: OutlineInputBorder())),
    const SizedBox(height: 16),
    Align(alignment: Alignment.centerRight, child: ElevatedButton.icon(
      onPressed: _saving ? null : _createAndAssign,
      icon: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.add, size: 16),
      label: const Text('Anlegen + Zuordnen'),
      style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white),
    )),
  ]));

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(24),
    child: SizedBox(width: 600, height: 520, child: Column(children: [
      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.teal.shade700, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))), child: Row(children: [
        const Icon(Icons.person_add, color: Colors.white), const SizedBox(width: 8),
        const Expanded(child: Text('Arbeitsvermittler hinzufügen', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))),
        IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
      ])),
      TabBar(controller: _tab, labelColor: Colors.teal, tabs: const [Tab(icon: Icon(Icons.group, size: 18), text: 'Aus Pool wählen'), Tab(icon: Icon(Icons.person_add, size: 18), text: 'Neu anlegen')]),
      Expanded(child: TabBarView(controller: _tab, children: [_poolList(), _newForm()])),
    ])),
  );
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
    final tLang = (res['translation_language'] ?? '').toString();
    final msg = ok
        ? (tLang.isNotEmpty
            ? 'Vollmacht erstellt (ID ${res['id']}) — DE + Übersetzung ${tLang.toUpperCase()}'
            : 'Vollmacht erstellt (ID ${res['id']}) — nur DE')
        : (res['message'] ?? 'Fehler');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
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
        final tLang = (v['translation_language'] ?? '').toString();
        final tFile = (v['pdf_translation_filename'] ?? '').toString();
        final hasTrans = tLang.isNotEmpty && tFile.isNotEmpty;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(Icons.picture_as_pdf, color: color),
            title: Row(children: [
              Expanded(child: Text('Vollmacht #${v['id']} — ${status.toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.bold))),
              if (hasTrans) Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade700)),
                child: Text('🌍 ${tLang.toUpperCase()}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
              ),
            ]),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Erstellt: ${v['generated_at'] ?? ''}', style: const TextStyle(fontSize: 11)),
              Text('Gültig: ${v['valid_from'] ?? ''} → ${v['valid_until'] ?? 'auf Widerruf'}', style: const TextStyle(fontSize: 11)),
              if (status == 'revoked') Text('Widerrufen: ${v['revoked_at'] ?? ''}', style: TextStyle(fontSize: 11, color: Colors.red.shade700)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf, size: 14),
                  label: const Text('DE (Original)', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0), minimumSize: const Size(0, 28), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  onPressed: () => _openPdf(v['id'], filename),
                ),
                if (hasTrans) OutlinedButton.icon(
                  icon: const Icon(Icons.translate, size: 14),
                  label: Text('Übersetzung ${tLang.toUpperCase()}', style: const TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0), minimumSize: const Size(0, 28), tapTargetSize: MaterialTapTargetSize.shrinkWrap, foregroundColor: Colors.amber.shade900, side: BorderSide(color: Colors.amber.shade700)),
                  onPressed: () => _openPdf(v['id'], tFile, type: 'translation'),
                ),
              ]),
            ]),
            trailing: status != 'revoked'
                ? IconButton(icon: const Icon(Icons.cancel, size: 20, color: Colors.red), tooltip: 'Widerrufen', onPressed: () => _revoke(v['id']))
                : null,
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
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _signatureCard(
              label: 'Vollmachtgeber (Mitglied)',
              name: '${user['vorname'] ?? ''} ${user['nachname'] ?? ''}',
              has: hasMemberSig,
              uploadedAt: v['signature_member_uploaded_at'],
              uploading: _uploadingMember,
              vollmachtId: v['id'],
              signer: 'member',
              pages: v['signatures_member'] is List
                  ? List<Map<String, dynamic>>.from((v['signatures_member'] as List).map((e) => Map<String, dynamic>.from(e as Map)))
                  : const [],
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
              pages: v['signatures_vorstand'] is List
                  ? List<Map<String, dynamic>>.from((v['signatures_vorstand'] as List).map((e) => Map<String, dynamic>.from(e as Map)))
                  : const [],
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
                         required bool uploading, required int vollmachtId, required String signer,
                         List<Map<String, dynamic>>? pages}) {
    final pageList = pages ?? const <Map<String, dynamic>>[];
    final hasAny = has || pageList.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: hasAny ? Colors.green.shade50 : Colors.grey.shade50,
        border: Border.all(color: hasAny ? Colors.green.shade400 : Colors.grey.shade400),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(hasAny ? Icons.check_circle : Icons.pending, size: 16, color: hasAny ? Colors.green : Colors.orange),
          const SizedBox(width: 4),
          Expanded(child: Text('$label  (${pageList.length})', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
        ]),
        Text(name, style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis),
        const SizedBox(height: 6),
        if (pageList.isEmpty)
          Text('Noch keine Seite hochgeladen', style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontStyle: FontStyle.italic))
        else ...pageList.map((p) {
          final pid = (p['id'] as num).toInt();
          final fn = (p['filename'] ?? '').toString();
          final at = (p['uploaded_at'] ?? '').toString();
          final mime = (p['mime_type'] ?? '').toString();
          final isImg = mime.startsWith('image/') || RegExp(r'\.(jpg|jpeg|png|heic|heif)$', caseSensitive: false).hasMatch(fn);
          return Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.green.shade200)),
            child: Row(children: [
              Icon(isImg ? Icons.image : Icons.picture_as_pdf, size: 14, color: Colors.green.shade800),
              const SizedBox(width: 4),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(fn, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (at.isNotEmpty) Text(at, style: TextStyle(fontSize: 8, color: Colors.grey.shade700)),
              ])),
              SizedBox(width: 24, height: 24, child: IconButton(icon: const Icon(Icons.visibility, size: 14), padding: EdgeInsets.zero, tooltip: 'Ansehen', onPressed: () => _openSignaturePage(pid, fn))),
              SizedBox(width: 24, height: 24, child: IconButton(icon: const Icon(Icons.delete, size: 14, color: Colors.red), padding: EdgeInsets.zero, tooltip: 'Löschen', onPressed: () => _deleteSignaturePage(vollmachtId, signer, pid, fn))),
            ]),
          );
        }),
        const SizedBox(height: 6),
        if (uploading) const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)))
        else SizedBox(width: double.infinity, child: ElevatedButton.icon(
          icon: const Icon(Icons.add_photo_alternate, size: 14),
          label: Text(pageList.isEmpty ? 'Seite(n) hochladen' : 'Weitere Seite hinzufügen', style: const TextStyle(fontSize: 10)),
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 6)),
          onPressed: () => _pickAndUpload(vollmachtId, signer),
        )),
      ]),
    );
  }

  Future<void> _openSignaturePage(int signatureId, String filename) async {
    final res = await widget.apiService.downloadVollmachtSignatureFile(signatureId);
    if (!mounted) return;
    if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
      FileViewerDialog.showFromBytes(context, res.bodyBytes, filename);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler (${res.statusCode})'), backgroundColor: Colors.red));
    }
  }

  Future<void> _deleteSignaturePage(int vollmachtId, String signer, int signatureId, String filename) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Seite löschen?'),
      content: Text(filename),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Löschen', style: TextStyle(color: Colors.red))),
      ],
    ));
    if (ok != true) return;
    final res = await widget.apiService.deleteVollmachtSignatureById(vollmachtId: vollmachtId, signer: signer, signatureId: signatureId);
    if (!mounted) return;
    if (res['success'] == true) _loadAll();
    else ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Fehler'), backgroundColor: Colors.red));
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
    final allowMulti = signer == 'member' || signer == 'vorstand';
    final result = await FilePickerHelper.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'heic', 'heif'],
      withData: true,
      allowMultiple: allowMulti,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() {
      if (signer == 'member') _uploadingMember = true;
      else if (signer == 'vorstand') _uploadingVorstand = true;
      else if (signer == 'receipt') _uploadingReceipt = true;
    });
    int ok = 0, fail = 0;
    for (final f in result.files) {
      if (f.bytes == null) { fail++; continue; }
      final res = await widget.apiService.uploadVollmachtSignature(
        vollmachtId: vollmachtId, signer: signer, bytes: f.bytes!, filename: f.name,
      );
      if (res['success'] == true) ok++; else fail++;
    }
    if (!mounted) return;
    setState(() {
      _uploadingMember = false; _uploadingVorstand = false; _uploadingReceipt = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$ok hochgeladen' + (fail > 0 ? ', $fail fehlgeschlagen' : '')),
      backgroundColor: fail > 0 ? Colors.orange : Colors.green,
    ));
    if (ok > 0) _loadAll();
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

// ==================== BETRIEBSKOSTEN-NACHFORDERUNG: BRIEF-GENERATOR TAB ====================
class _BetriebskostenBriefGeneratorTab extends StatefulWidget {
  final Map<String, dynamic> antrag;
  final ApiService apiService;
  final int userId;
  const _BetriebskostenBriefGeneratorTab({required this.antrag, required this.apiService, required this.userId});
  @override
  State<_BetriebskostenBriefGeneratorTab> createState() => _BetriebskostenBriefGeneratorTabState();
}

class _BetriebskostenBriefGeneratorTabState extends State<_BetriebskostenBriefGeneratorTab> {
  bool _loading = true;
  String? _loadError;

  // Form controllers (editable, prefilled from various sources)
  final _absVornameC = TextEditingController();
  final _absNachnameC = TextEditingController();
  final _absStrasseC = TextEditingController();
  final _absHausnummerC = TextEditingController();
  final _absPlzC = TextEditingController();
  final _absOrtC = TextEditingController();
  final _absTelC = TextEditingController();

  final _jcDienststelleC = TextEditingController();
  final _jcAnsprechC = TextEditingController();
  final _jcStrasseC = TextEditingController();
  final _jcHausnrC = TextEditingController();
  final _jcPlzC = TextEditingController();
  final _jcOrtC = TextEditingController();

  final _kundennummerC = TextEditingController();
  final _bgNummerC = TextEditingController();

  final _wohnStrasseC = TextEditingController();
  final _wohnHausnrC = TextEditingController();
  final _wohnPlzC = TextEditingController();
  final _wohnOrtC = TextEditingController();

  final _zVonC = TextEditingController();
  final _zBisC = TextEditingController();
  final _betragC = TextEditingController();

  final _ortC = TextEditingController();
  final _datumC = TextEditingController();

  List<Map<String, dynamic>> _mietvertraege = [];
  int? _selectedMietvertragId;
  List<Map<String, dynamic>> _nkaDocs = []; // for selected mietvertrag
  int? _selectedJahr;
  List<String> _anlagen = [];

  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _datumC.text = DateFormat('dd.MM.yyyy').format(DateTime.now());
    _selectedJahr = DateTime.now().year - 1;
    _loadAll();
  }

  @override
  void dispose() {
    for (final c in [
      _absVornameC, _absNachnameC, _absStrasseC, _absHausnummerC, _absPlzC, _absOrtC, _absTelC,
      _jcDienststelleC, _jcAnsprechC, _jcStrasseC, _jcHausnrC, _jcPlzC, _jcOrtC,
      _kundennummerC, _bgNummerC,
      _wohnStrasseC, _wohnHausnrC, _wohnPlzC, _wohnOrtC,
      _zVonC, _zBisC, _betragC, _ortC, _datumC,
    ]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      // Parallel fetches
      final uFuture = widget.apiService.getUserDetails(widget.userId);
      final jFuture = widget.apiService.getJobcenterData(widget.userId);
      final vFuture = widget.apiService.getVermieterData(widget.userId);
      final results = await Future.wait([uFuture, jFuture, vFuture]);

      // --- 1) User (member) details — top-left Absender ---
      final u = (results[0]['user'] ?? results[0]['data'] ?? results[0]) as Map<String, dynamic>?;
      if (u != null) {
        _absVornameC.text = (u['vorname'] ?? '').toString();
        _absNachnameC.text = (u['nachname'] ?? u['name'] ?? '').toString();
        _absStrasseC.text = (u['strasse'] ?? '').toString();
        _absHausnummerC.text = (u['hausnummer'] ?? '').toString();
        _absPlzC.text = (u['plz'] ?? '').toString();
        _absOrtC.text = (u['ort'] ?? '').toString();
        _absTelC.text = (u['telefon'] ?? u['mobile'] ?? '').toString();
        if (_ortC.text.isEmpty) _ortC.text = _absOrtC.text;
      }

      // --- 2) Jobcenter — pulled from "Zuständige Jobcenter" the user already
      //    picked in Behörde → Jobcenter (jobcenter_data.stammdaten.selected_amt_*).
      //    That data already comes from jobcenter_datenbank, so no second lookup is needed.
      final jcData = results[1]['data'] as Map<String, dynamic>?;
      if (jcData != null) {
        _jcDienststelleC.text = (jcData['stammdaten.selected_amt_name'] ?? jcData['stammdaten.dienststelle'] ?? '').toString();
        _jcAnsprechC.text = (jcData['stammdaten.arbeitsvermittler'] ?? '').toString();
        _kundennummerC.text = (jcData['stammdaten.kundennummer'] ?? '').toString();
        _bgNummerC.text = (jcData['stammdaten.bg_nummer'] ?? '').toString();

        // selected_amt_adresse stores "Straße Hausnummer" — split off the trailing house number
        final addr = (jcData['stammdaten.selected_amt_adresse'] ?? '').toString().trim();
        if (addr.isNotEmpty) {
          final m = RegExp(r'^(.*?)\s+(\d+\s*[a-zA-Z\-]*)\s*$').firstMatch(addr);
          if (m != null) {
            _jcStrasseC.text = m.group(1)!.trim();
            _jcHausnrC.text = m.group(2)!.trim();
          } else {
            _jcStrasseC.text = addr;
          }
        }

        // selected_amt_ort stores "PLZ Stadt"
        final ortField = (jcData['stammdaten.selected_amt_ort'] ?? '').toString().trim();
        if (ortField.isNotEmpty) {
          final m = RegExp(r'^(\d{4,5})\s+(.+)$').firstMatch(ortField);
          if (m != null) {
            _jcPlzC.text = m.group(1)!;
            _jcOrtC.text = m.group(2)!.trim();
          } else {
            _jcOrtC.text = ortField;
          }
        }
      }

      // --- 3) Vermieter — Wohnung address (member's rented flat) ---
      final mvs = (results[2]['mietvertraege'] as List? ?? []).cast<Map<String, dynamic>>();
      _mietvertraege = mvs;
      final activeMv = mvs.firstWhere((m) => (m['status'] ?? '') == 'aktiv', orElse: () => mvs.isNotEmpty ? mvs.first : <String, dynamic>{});
      if (activeMv.isNotEmpty) {
        _selectedMietvertragId = activeMv['id'] as int?;
        _wohnStrasseC.text = (activeMv['strasse'] ?? '').toString();
        _wohnHausnrC.text = (activeMv['hausnummer'] ?? '').toString();
        _wohnPlzC.text = (activeMv['plz'] ?? '').toString();
        _wohnOrtC.text = (activeMv['ort'] ?? '').toString();
        await _loadNkaForMietvertrag(_selectedMietvertragId!);
      }

      setState(() { _loading = false; _loadError = null; });
    } catch (e) {
      setState(() { _loading = false; _loadError = e.toString(); });
    }
  }

  Future<void> _loadNkaForMietvertrag(int mvId) async {
    final r = await widget.apiService.listVermieterDokumente(userId: widget.userId, mietvertragId: mvId);
    final list = ((r['dokumente'] as List?) ?? []).cast<Map<String, dynamic>>().where((d) => d['dokument_typ'] == 'nebenkostenabrechnung').toList();
    setState(() => _nkaDocs = list);
    _applyNkaForYear(_selectedJahr);
  }

  void _applyNkaForYear(int? jahr) {
    if (jahr == null) return;
    final matches = _nkaDocs.where((d) => d['jahr'] == jahr).toList();
    if (matches.isEmpty) {
      // Default to "01.01.<jahr> – 31.12.<jahr>" if nothing on file
      _zVonC.text = '01.01.$jahr';
      _zBisC.text = '31.12.$jahr';
      _betragC.text = '';
      _anlagen = [];
    } else {
      // Take the first matching NKA — prefer Nachzahlung over Guthaben if both present
      final nz = matches.firstWhere((d) => d['nka_typ'] == 'nachzahlung', orElse: () => matches.first);
      _zVonC.text = (nz['zeitraum_von'] ?? '01.01.$jahr').toString();
      _zBisC.text = (nz['zeitraum_bis'] ?? '31.12.$jahr').toString();
      _betragC.text = (nz['betrag'] ?? '').toString();
      _anlagen = matches.map((d) => (d['filename'] ?? '').toString()).where((s) => s.isNotEmpty).toList();
    }
    setState(() {});
  }

  BetriebskostenBriefData _buildData() => BetriebskostenBriefData(
    absVorname: _absVornameC.text,
    absNachname: _absNachnameC.text,
    absStrasse: _absStrasseC.text,
    absHausnummer: _absHausnummerC.text,
    absPlz: _absPlzC.text,
    absOrt: _absOrtC.text,
    absTelefon: _absTelC.text,
    jcDienststelle: _jcDienststelleC.text,
    jcAnsprechpartner: _jcAnsprechC.text,
    jcStrasse: _jcStrasseC.text,
    jcHausnummer: _jcHausnrC.text,
    jcPlz: _jcPlzC.text,
    jcOrt: _jcOrtC.text,
    kundennummer: _kundennummerC.text,
    bgNummer: _bgNummerC.text,
    wohnungStrasse: _wohnStrasseC.text,
    wohnungHausnummer: _wohnHausnrC.text,
    wohnungPlz: _wohnPlzC.text,
    wohnungOrt: _wohnOrtC.text,
    abrechnungsjahr: '${_selectedJahr ?? ''}',
    zeitraumVon: _zVonC.text,
    zeitraumBis: _zBisC.text,
    nachzahlungBetrag: _betragC.text,
    anlagen: _anlagen.isEmpty ? ['Nebenkostenabrechnung ${_selectedJahr ?? ''}'] : _anlagen,
    briefOrt: _ortC.text,
    briefDatum: _datumC.text,
  );

  Future<void> _preview() async {
    setState(() => _generating = true);
    try {
      final bytes = await generateBetriebskostenAntragPdf(_buildData());
      if (!mounted) return;
      await FileViewerDialog.showFromBytes(context, bytes, 'Antrag_Betriebskosten_${_selectedJahr ?? 'Vorschau'}.pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF-Vorschau fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _saveAs() async {
    setState(() => _generating = true);
    try {
      final bytes = await generateBetriebskostenAntragPdf(_buildData());
      final filename = 'Antrag_Betriebskosten_KdU_${_absNachnameC.text}_${_selectedJahr ?? ''}.pdf';
      final path = await FilePickerHelper.saveFile(
        dialogTitle: 'Antrag-PDF speichern',
        fileName: filename,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (path == null) {
        if (mounted) setState(() => _generating = false);
        return;
      }
      await File(path).writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF gespeichert: $path'), backgroundColor: Colors.green.shade600));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Widget _field(String label, TextEditingController c, {IconData? icon, double width = 0}) {
    final tf = TextField(
      controller: c,
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        labelText: label, isDense: true,
        prefixIcon: icon != null ? Icon(icon, size: 16) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
    );
    return width > 0 ? SizedBox(width: width, child: tf) : tf;
  }

  Widget _section(String title, IconData icon, Color color, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
        ]),
        const SizedBox(height: 6),
        ...children,
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) return Center(child: Text('Fehler: $_loadError', style: const TextStyle(color: Colors.red)));

    final years = List.generate(8, (i) => DateTime.now().year + 1 - i);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
          child: Row(children: [
            Icon(Icons.info_outline, size: 18, color: Colors.blue.shade700),
            const SizedBox(width: 8),
            Expanded(child: Text(
              'Daten wurden aus Stufe-1-Verifizierung, Jobcenter-Stammdaten und Mietvertrag automatisch übernommen. Bei Bedarf anpassen, dann PDF generieren. Format: DIN 5008. Keine Unterschrift erforderlich (§ 9 SGB X).',
              style: TextStyle(fontSize: 11, color: Colors.blue.shade900),
            )),
          ]),
        ),

        _section('Absender (Mitglied)', Icons.person, Colors.deepPurple, [
          Row(children: [
            Expanded(child: _field('Vorname', _absVornameC, icon: Icons.person_outline)),
            const SizedBox(width: 8),
            Expanded(child: _field('Nachname', _absNachnameC, icon: Icons.person_outline)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(flex: 3, child: _field('Straße', _absStrasseC, icon: Icons.location_on_outlined)),
            const SizedBox(width: 8),
            Expanded(child: _field('Nr.', _absHausnummerC)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: _field('PLZ', _absPlzC)),
            const SizedBox(width: 8),
            Expanded(flex: 3, child: _field('Ort', _absOrtC)),
          ]),
          const SizedBox(height: 6),
          _field('Telefon (optional)', _absTelC, icon: Icons.phone),
        ]),

        _section('Empfänger (Jobcenter)', Icons.account_balance, Colors.indigo, [
          _field('Dienststelle', _jcDienststelleC, icon: Icons.business),
          const SizedBox(height: 6),
          _field('Ansprechpartner / z. Hd.', _jcAnsprechC, icon: Icons.person_pin),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(flex: 3, child: _field('Straße', _jcStrasseC, icon: Icons.location_on_outlined)),
            const SizedBox(width: 8),
            Expanded(child: _field('Nr.', _jcHausnrC)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: _field('PLZ', _jcPlzC)),
            const SizedBox(width: 8),
            Expanded(flex: 3, child: _field('Ort', _jcOrtC)),
          ]),
        ]),

        _section('Bezugsdaten', Icons.tag, Colors.teal, [
          Row(children: [
            Expanded(child: _field('Kundennummer', _kundennummerC, icon: Icons.badge)),
            const SizedBox(width: 8),
            Expanded(child: _field('BG-Nummer', _bgNummerC, icon: Icons.group)),
          ]),
        ]),

        _section('Mietobjekt (Wohnung des Mitglieds)', Icons.home, Colors.brown, [
          if (_mietvertraege.length > 1) ...[
            DropdownButtonFormField<int>(
              initialValue: _selectedMietvertragId,
              isExpanded: true,
              decoration: InputDecoration(labelText: 'Mietvertrag wählen', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              items: _mietvertraege.map((m) => DropdownMenuItem(value: m['id'] as int?, child: Text('${m['strasse'] ?? ''} ${m['hausnummer'] ?? ''}, ${m['ort'] ?? ''} — ${m['status'] ?? ''}', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) async {
                if (v == null) return;
                final mv = _mietvertraege.firstWhere((m) => m['id'] == v);
                setState(() {
                  _selectedMietvertragId = v;
                  _wohnStrasseC.text = (mv['strasse'] ?? '').toString();
                  _wohnHausnrC.text = (mv['hausnummer'] ?? '').toString();
                  _wohnPlzC.text = (mv['plz'] ?? '').toString();
                  _wohnOrtC.text = (mv['ort'] ?? '').toString();
                });
                await _loadNkaForMietvertrag(v);
              },
            ),
            const SizedBox(height: 6),
          ],
          Row(children: [
            Expanded(flex: 3, child: _field('Straße', _wohnStrasseC, icon: Icons.location_on_outlined)),
            const SizedBox(width: 8),
            Expanded(child: _field('Nr.', _wohnHausnrC)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: _field('PLZ', _wohnPlzC)),
            const SizedBox(width: 8),
            Expanded(flex: 3, child: _field('Ort', _wohnOrtC)),
          ]),
        ]),

        _section('Nebenkostenabrechnung', Icons.receipt_long, Colors.deepOrange, [
          Row(children: [
            Expanded(child: DropdownButtonFormField<int>(
              initialValue: _selectedJahr,
              isExpanded: true,
              decoration: InputDecoration(labelText: 'Abrechnungsjahr', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              items: years.map((y) => DropdownMenuItem(value: y, child: Text('$y', style: const TextStyle(fontSize: 12)))).toList(),
              onChanged: (v) { setState(() => _selectedJahr = v); _applyNkaForYear(v); },
            )),
            const SizedBox(width: 8),
            Expanded(child: _field('Betrag (Nachzahlung €)', _betragC, icon: Icons.euro)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: _field('Zeitraum von', _zVonC, icon: Icons.calendar_today)),
            const SizedBox(width: 8),
            Expanded(child: _field('Zeitraum bis', _zBisC, icon: Icons.calendar_today)),
          ]),
          if (_anlagen.isNotEmpty) Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.attach_file, size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Expanded(child: Text('Anlagen (autom.): ${_anlagen.join(', ')}', style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontStyle: FontStyle.italic), overflow: TextOverflow.ellipsis, maxLines: 2)),
            ]),
          ),
        ]),

        _section('Datum / Ort (Briefkopf)', Icons.event, Colors.grey, [
          Row(children: [
            Expanded(child: _field('Ort', _ortC)),
            const SizedBox(width: 8),
            Expanded(child: _field('Datum', _datumC)),
          ]),
        ]),

        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: _generating ? null : _preview,
            icon: _generating ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.visibility, size: 16),
            label: const Text('Vorschau'),
          )),
          const SizedBox(width: 8),
          Expanded(child: ElevatedButton.icon(
            onPressed: _generating ? null : _saveAs,
            icon: const Icon(Icons.picture_as_pdf, size: 16),
            label: const Text('PDF speichern'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
          )),
        ]),
        const SizedBox(height: 10),
      ]),
    );
  }
}

// ==================== AV Detail Modal (Details / Einladung / Termin) ====================

class _AvDetailModal extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final Map<String, dynamic> userAv;
  const _AvDetailModal({required this.apiService, required this.userId, required this.userAv});
  @override
  State<_AvDetailModal> createState() => _AvDetailModalState();
}

class _AvDetailModalState extends State<_AvDetailModal> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<Map<String, dynamic>> _einladungen = [];
  List<Map<String, dynamic>> _termine = [];
  bool _loadingEinl = true, _loadingTerm = true;
  bool _changed = false;

  int get _userAvId => widget.userAv['id'] as int;
  int get _personalId => widget.userAv['personal_id'] as int;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _loadEinladungen();
    _loadTermine();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _loadEinladungen() async {
    final res = await widget.apiService.jobcenterAvAction({'action': 'list_einladungen', 'user_av_id': _userAvId});
    if (!mounted) return;
    setState(() { _einladungen = List<Map<String, dynamic>>.from(res['einladungen'] ?? []); _loadingEinl = false; });
  }

  Future<void> _loadTermine() async {
    final res = await widget.apiService.jobcenterAvAction({'action': 'list_termine', 'user_av_id': _userAvId});
    if (!mounted) return;
    setState(() { _termine = List<Map<String, dynamic>>.from(res['termine'] ?? []); _loadingTerm = false; });
  }

  @override
  Widget build(BuildContext context) {
    final av = widget.userAv;
    final name = '${av['vorname'] ?? ''} ${av['nachname'] ?? ''}'.trim();
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(width: 720, height: 600, child: Column(children: [
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.teal.shade700, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
          child: Row(children: [
            const Icon(Icons.support_agent, color: Colors.white), const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              Text('${av['rolle'] ?? ""} @ ${av['jobcenter_name'] ?? "?"}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ])),
            IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context, _changed)),
          ])),
        TabBar(controller: _tab, labelColor: Colors.teal, tabs: const [
          Tab(icon: Icon(Icons.info, size: 18), text: 'Details'),
          Tab(icon: Icon(Icons.mail, size: 18), text: 'Einladung'),
          Tab(icon: Icon(Icons.event, size: 18), text: 'Termin'),
        ]),
        Expanded(child: TabBarView(controller: _tab, children: [
          _AvDetailsTab(apiService: widget.apiService, personal: av, userAv: av, onChanged: () { _changed = true; }),
          _AvEinladungenTab(apiService: widget.apiService, userId: widget.userId, userAvId: _userAvId, einladungen: _einladungen, loading: _loadingEinl, onChanged: () { _changed = true; _loadEinladungen(); }),
          _AvTermineTab(apiService: widget.apiService, userId: widget.userId, userAvId: _userAvId, einladungen: _einladungen, termine: _termine, loading: _loadingTerm, onChanged: () { _changed = true; _loadTermine(); }),
        ])),
      ])),
    );
  }
}

class _AvDetailsTab extends StatefulWidget {
  final ApiService apiService;
  final Map<String, dynamic> personal;
  final Map<String, dynamic> userAv;
  final VoidCallback onChanged;
  const _AvDetailsTab({required this.apiService, required this.personal, required this.userAv, required this.onChanged});
  @override State<_AvDetailsTab> createState() => _AvDetailsTabState();
}
class _AvDetailsTabState extends State<_AvDetailsTab> {
  late TextEditingController _vornameC, _nachnameC, _telC, _emC, _ziC, _notizC, _seitC, _bisC, _linkNotizC;
  late String _rolle;
  bool _editing = false, _saving = false;
  static const _rollen = ['pAp','SB_Leistung','Fallmanager','SB_Reha','Berufsberater','Teamleiter','Eingangszone','sonstige'];

  @override
  void initState() {
    super.initState();
    _vornameC  = TextEditingController(text: widget.personal['vorname']  ?? '');
    _nachnameC = TextEditingController(text: widget.personal['nachname'] ?? '');
    _telC      = TextEditingController(text: widget.personal['telefon'] ?? '');
    _emC       = TextEditingController(text: widget.personal['email']   ?? '');
    _ziC       = TextEditingController(text: widget.personal['zimmer']  ?? '');
    _notizC    = TextEditingController(text: widget.personal['personal_notiz']  ?? widget.personal['notiz'] ?? '');
    _seitC     = TextEditingController(text: widget.userAv['zustaendig_seit']  ?? '');
    _bisC      = TextEditingController(text: widget.userAv['zustaendig_bis']   ?? '');
    _linkNotizC= TextEditingController(text: widget.userAv['link_notiz'] ?? '');
    _rolle = (widget.personal['rolle'] ?? 'sonstige').toString();
  }

  @override
  void dispose() { _vornameC.dispose(); _nachnameC.dispose(); _telC.dispose(); _emC.dispose(); _ziC.dispose(); _notizC.dispose(); _seitC.dispose(); _bisC.dispose(); _linkNotizC.dispose(); super.dispose(); }

  Future<void> _save() async {
    setState(() => _saving = true);
    final personalRes = await widget.apiService.jobcenterAvAction({
      'action': 'update_personal', 'personal_id': widget.personal['personal_id'],
      'personal': {
        'vorname': _vornameC.text.trim(), 'nachname': _nachnameC.text.trim(),
        'rolle': _rolle, 'telefon': _telC.text.trim(), 'email': _emC.text.trim(),
        'zimmer': _ziC.text.trim(), 'notiz': _notizC.text.trim(), 'aktiv': true,
      },
    });
    await widget.apiService.jobcenterAvAction({
      'action': 'update_user_av', 'user_av_id': widget.userAv['id'],
      'position': widget.userAv['position'] ?? 1,
      'zustaendig_seit': _seitC.text.trim().isEmpty ? null : _seitC.text.trim(),
      'zustaendig_bis':  _bisC.text.trim().isEmpty  ? null : _bisC.text.trim(),
      'notiz': _linkNotizC.text.trim(),
    });
    if (!mounted) return;
    setState(() { _saving = false; _editing = false; });
    if (personalRes['success'] == true) {
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Gespeichert'), backgroundColor: Colors.green.shade600));
    }
  }

  Widget _f(String label, TextEditingController c, {IconData? icon}) => Padding(padding: const EdgeInsets.only(bottom: 10), child: TextField(
    controller: c, readOnly: !_editing,
    decoration: InputDecoration(labelText: label, prefixIcon: icon != null ? Icon(icon, size: 18) : null, isDense: true, border: const OutlineInputBorder(), filled: !_editing, fillColor: !_editing ? Colors.grey.shade100 : null),
  ));

  @override
  Widget build(BuildContext context) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      Expanded(child: Text('Stammdaten (Pool)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade800))),
      TextButton.icon(icon: Icon(_editing ? Icons.lock : Icons.edit, size: 14), label: Text(_editing ? 'Sperren' : 'Bearbeiten', style: const TextStyle(fontSize: 12)), onPressed: () => setState(() => _editing = !_editing)),
    ]),
    const SizedBox(height: 8),
    Row(children: [Expanded(child: _f('Vorname', _vornameC, icon: Icons.person)), const SizedBox(width: 8), Expanded(child: _f('Nachname', _nachnameC, icon: Icons.person))]),
    DropdownButtonFormField<String>(
      initialValue: _rolle,
      decoration: const InputDecoration(labelText: 'Rolle', isDense: true, border: OutlineInputBorder()),
      items: _rollen.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
      onChanged: _editing ? (v) => setState(() => _rolle = v ?? 'sonstige') : null,
    ),
    const SizedBox(height: 10),
    _f('Telefon / Durchwahl', _telC, icon: Icons.phone),
    _f('E-Mail', _emC, icon: Icons.email),
    _f('Zimmernummer', _ziC, icon: Icons.meeting_room),
    _f('Notiz (Pool — für alle Mitglieder sichtbar)', _notizC, icon: Icons.note),
    const Divider(height: 24),
    Text('Zuordnung zu diesem Mitglied', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
    const SizedBox(height: 8),
    Row(children: [Expanded(child: _f('Zuständig seit (YYYY-MM-DD)', _seitC, icon: Icons.calendar_today)), const SizedBox(width: 8), Expanded(child: _f('Zuständig bis (YYYY-MM-DD, leer=aktiv)', _bisC, icon: Icons.event_busy))]),
    _f('Private Notiz (nur dieses Mitglied)', _linkNotizC, icon: Icons.note_alt),
    if (_editing) ...[const SizedBox(height: 12), Align(alignment: Alignment.centerRight, child: ElevatedButton.icon(
      onPressed: _saving ? null : _save,
      icon: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 16),
      label: const Text('Speichern'), style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white),
    ))],
  ]));
}

class _AvEinladungenTab extends StatelessWidget {
  final ApiService apiService;
  final int userId, userAvId;
  final List<Map<String, dynamic>> einladungen;
  final bool loading;
  final VoidCallback onChanged;
  const _AvEinladungenTab({required this.apiService, required this.userId, required this.userAvId, required this.einladungen, required this.loading, required this.onChanged});

  Future<void> _openDialog(BuildContext context, [Map<String, dynamic>? existing]) async {
    final changed = await showDialog<bool>(context: context, builder: (_) => _EinladungEditDialog(apiService: apiService, userId: userId, userAvId: userAvId, existing: existing));
    if (changed == true) onChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Container(padding: const EdgeInsets.all(10), child: Row(children: [
        Expanded(child: Text('${einladungen.length} Einladung(en) von diesem Arbeitsvermittler', style: const TextStyle(fontSize: 12, color: Colors.grey))),
        ElevatedButton.icon(onPressed: () => _openDialog(context), icon: const Icon(Icons.add, size: 14), label: const Text('Neue Einladung'), style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white, minimumSize: const Size(0, 32))),
      ])),
      Expanded(child: einladungen.isEmpty
          ? Center(child: Text('Keine Einladungen', style: TextStyle(color: Colors.grey.shade500)))
          : ListView.builder(itemCount: einladungen.length, itemBuilder: (_, i) {
              final e = einladungen[i];
              final dt = (e['einladung_datum_termin'] ?? '').toString();
              final ein = (e['einladung_eingegangen_am'] ?? '').toString();
              final versandDt = (e['versand_datum'] ?? '').toString();
              final fingiert = (e['zugang_fingiert_am'] ?? '').toString();
              final methode = (e['versand_methode'] ?? 'post').toString();
              final gap = e['frist_zwischen_eingang_und_termin'];
              const methodIcon = {'post': Icons.local_post_office, 'email': Icons.email, 'fax': Icons.fax, 'online_portal': Icons.web, 'persoenlich': Icons.person, 'sonstige': Icons.help_outline};
              return Card(margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: InkWell(
                onTap: () => _openDialog(context, e),
                child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(methodIcon[methode] ?? Icons.mail, size: 16, color: Colors.orange.shade700),
                    const SizedBox(width: 6),
                    Expanded(child: Text(dt.isNotEmpty ? 'Termin: $dt' : 'Termin: ?', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                    if ((e['mit_meldepflicht'] ?? 1) == 1) Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(4)), child: const Text('⚠ Meldepflicht', style: TextStyle(fontSize: 9, color: Colors.red, fontWeight: FontWeight.bold))),
                  ]),
                  const SizedBox(height: 4),
                  if (versandDt.isNotEmpty || fingiert.isNotEmpty || ein.isNotEmpty) Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (versandDt.isNotEmpty) Row(children: [const Icon(Icons.send, size: 11, color: Colors.orange), const SizedBox(width: 3), Text('Versand: $versandDt', style: const TextStyle(fontSize: 10))]),
                      if (fingiert.isNotEmpty) Row(children: [const Icon(Icons.gavel, size: 11, color: Colors.blue), const SizedBox(width: 3), Text('Zugangsfiktion: $fingiert (§ 37 SGB X)', style: const TextStyle(fontSize: 10, color: Colors.blue))]),
                      if (ein.isNotEmpty) Row(children: [const Icon(Icons.mark_email_read, size: 11, color: Colors.green), const SizedBox(width: 3), Text('Eingegangen: $ein', style: const TextStyle(fontSize: 10, color: Colors.green))]),
                      if (gap != null) Padding(padding: const EdgeInsets.only(top: 2), child: Row(children: [
                        Icon((gap as int) < 7 ? Icons.warning : Icons.check_circle, size: 11, color: gap < 7 ? Colors.red : Colors.green),
                        const SizedBox(width: 3),
                        Text(gap < 0 ? 'Termin vergangen ($gap Tage)' : gap < 7 ? 'Nur $gap Tage Frist (< 7 BSG-Min.)' : '$gap Tage Frist (OK)', style: TextStyle(fontSize: 10, color: gap < 7 ? Colors.red : Colors.green, fontWeight: FontWeight.bold)),
                      ])),
                    ]),
                  ),
                  if ((e['thema'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Thema: ${e['thema']}', style: const TextStyle(fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis)),
                ])),
              ));
            })),
    ]);
  }
}

class _EinladungEditDialog extends StatefulWidget {
  final ApiService apiService;
  final int userId, userAvId;
  final Map<String, dynamic>? existing;
  const _EinladungEditDialog({required this.apiService, required this.userId, required this.userAvId, this.existing});
  @override State<_EinladungEditDialog> createState() => _EinladungEditDialogState();
}
class _EinladungEditDialogState extends State<_EinladungEditDialog> {
  late TextEditingController _versandC, _eingangC, _terminC, _themaC, _fristC, _notizC;
  String _methode = 'post';
  bool _meldepflicht = true, _saving = false;

  static const _methoden = {
    'post': 'Brief / Post (Zugangsfiktion +4 Tage)',
    'email': 'E-Mail (Zugangsfiktion +4 Tage)',
    'online_portal': 'jobcenter.digital Portal',
    'fax': 'Fax (sofort)',
    'persoenlich': 'Persönlich übergeben',
    'sonstige': 'Sonstige',
  };

  @override
  void initState() {
    super.initState();
    final e = widget.existing ?? const {};
    _versandC = TextEditingController(text: e['versand_datum']?.toString() ?? '');
    _eingangC = TextEditingController(text: e['einladung_eingegangen_am']?.toString() ?? '');
    _terminC  = TextEditingController(text: e['einladung_datum_termin']?.toString() ?? '');
    _themaC   = TextEditingController(text: e['thema']?.toString() ?? '');
    _fristC   = TextEditingController(text: e['frist_datum']?.toString() ?? '');
    _notizC   = TextEditingController(text: e['notiz']?.toString() ?? '');
    _meldepflicht = (e['mit_meldepflicht'] ?? 1) == 1;
    _methode = (e['versand_methode'] ?? 'post').toString();
  }
  @override
  void dispose() { _versandC.dispose(); _eingangC.dispose(); _terminC.dispose(); _themaC.dispose(); _fristC.dispose(); _notizC.dispose(); super.dispose(); }

  /// Calculate Zugangsfiktion locally for preview (§ 37 Abs. 2 SGB X).
  /// Post/Email/Portal: +4 Tage. Fax/Persoenlich: same day.
  String? _calcFingiert() {
    if (_versandC.text.trim().isEmpty) return null;
    try {
      final d = DateTime.parse(_versandC.text.trim());
      if (_methode == 'fax' || _methode == 'persoenlich') return _versandC.text.trim();
      return d.add(const Duration(days: 4)).toIso8601String().substring(0, 10);
    } catch (_) { return null; }
  }

  int? _calcFristGap() {
    if (_eingangC.text.trim().isEmpty || _terminC.text.trim().isEmpty) return null;
    try {
      final e = DateTime.parse(_eingangC.text.trim());
      final t = DateTime.parse(_terminC.text.trim().substring(0, 10));
      return t.difference(e).inDays;
    } catch (_) { return null; }
  }

  Future<void> _pickDate(TextEditingController c, {bool withTime = false}) async {
    final init = DateTime.tryParse(c.text.trim()) ?? DateTime.now();
    final d = await showDatePicker(context: context, initialDate: init, firstDate: DateTime(2020), lastDate: DateTime(2099));
    if (d == null) return;
    if (withTime) {
      final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: init.hour, minute: init.minute));
      final hh = (t?.hour ?? 9).toString().padLeft(2, '0');
      final mm = (t?.minute ?? 0).toString().padLeft(2, '0');
      setState(() => c.text = '${d.toIso8601String().substring(0, 10)} $hh:$mm');
    } else {
      setState(() => c.text = d.toIso8601String().substring(0, 10));
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final body = {
      'einladung': {
        'versand_methode':  _methode,
        'versand_datum':    _versandC.text.trim().isEmpty ? null : _versandC.text.trim(),
        'eingegangen_am':   _eingangC.text.trim().isEmpty ? null : _eingangC.text.trim(),
        'datum_termin':     _terminC.text.trim().isEmpty  ? null : _terminC.text.trim(),
        'thema':            _themaC.text.trim(),
        'frist_datum':      _fristC.text.trim().isEmpty   ? null : _fristC.text.trim(),
        'mit_meldepflicht': _meldepflicht,
        'notiz':            _notizC.text.trim(),
      },
    };
    final res = widget.existing == null
        ? await widget.apiService.jobcenterAvAction({...body, 'action': 'create_einladung', 'user_id': widget.userId, 'user_av_id': widget.userAvId})
        : await widget.apiService.jobcenterAvAction({...body, 'action': 'update_einladung', 'einladung_id': widget.existing!['id']});
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['success'] == true) Navigator.pop(context, true);
    else ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Fehler'), backgroundColor: Colors.red));
  }

  Future<void> _delete() async {
    if (widget.existing == null) return;
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Einladung löschen?'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')), TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Löschen', style: TextStyle(color: Colors.red)))],
    ));
    if (ok != true) return;
    await widget.apiService.jobcenterAvAction({'action': 'delete_einladung', 'einladung_id': widget.existing!['id']});
    if (mounted) Navigator.pop(context, true);
  }

  Widget _dateField(TextEditingController c, String label, {IconData? icon, bool withTime = false}) => TextField(
    controller: c, readOnly: true, onTap: () => _pickDate(c, withTime: withTime),
    decoration: InputDecoration(labelText: label, prefixIcon: icon != null ? Icon(icon, size: 18) : null, suffixIcon: const Icon(Icons.calendar_today, size: 16), isDense: true, border: const OutlineInputBorder()),
  );

  @override
  Widget build(BuildContext context) {
    final fingiert = _calcFingiert();
    final gap = _calcFristGap();
    final eingangSpaeter = (fingiert != null && _eingangC.text.trim().isNotEmpty)
        ? (DateTime.tryParse(_eingangC.text.trim())?.isAfter(DateTime.parse(fingiert)) ?? false)
        : false;
    return Dialog(insetPadding: const EdgeInsets.all(16), child: SizedBox(width: 580, height: 640, child: Column(children: [
      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.orange.shade700, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))), child: Row(children: [
        const Icon(Icons.mail, color: Colors.white), const SizedBox(width: 8),
        Expanded(child: Text(widget.existing == null ? 'Neue Einladung' : 'Einladung bearbeiten', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
        IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
      ])),
      Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(12), child: Column(children: [
        // ── Versand ─────────────────────────────────────────────
        Card(color: Colors.orange.shade50, child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Icon(Icons.send, size: 16, color: Colors.orange), const SizedBox(width: 6), Text('Versand', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade900))]),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _methode,
            decoration: const InputDecoration(labelText: 'Versand-Methode', isDense: true, border: OutlineInputBorder(), prefixIcon: Icon(Icons.send, size: 18)),
            items: _methoden.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12)))).toList(),
            onChanged: (v) => setState(() => _methode = v ?? 'post'),
          ),
          const SizedBox(height: 8),
          _dateField(_versandC, 'Versand-Datum (Datum auf dem Brief)', icon: Icons.event_note),
          if (fingiert != null) Padding(padding: const EdgeInsets.only(top: 6), child: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)), child: Row(children: [
            const Icon(Icons.gavel, size: 14, color: Colors.blue), const SizedBox(width: 4),
            Expanded(child: Text('Zugangsfiktion: $fingiert (§ 37 Abs. 2 SGB X)', style: TextStyle(fontSize: 11, color: Colors.blue.shade900, fontWeight: FontWeight.w600))),
          ]))),
        ]))),
        const SizedBox(height: 10),
        // ── Eingang beim Mitglied ───────────────────────────────
        Card(color: Colors.green.shade50, child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Icon(Icons.mark_email_read, size: 16, color: Colors.green), const SizedBox(width: 6), Text('Eingang beim Mitglied', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade900))]),
          const SizedBox(height: 8),
          _dateField(_eingangC, 'Tatsächlich eingegangen am', icon: Icons.event_available),
          if (eingangSpaeter) Padding(padding: const EdgeInsets.only(top: 6), child: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.amber.shade400)), child: Row(children: const [
            Icon(Icons.info_outline, size: 14, color: Colors.amber), SizedBox(width: 4),
            Expanded(child: Text('Brief ist NACH der gesetzlichen Zugangsfiktion eingegangen. Beweisstück aufbewahren (Umschlag mit Poststempel) — falls später eine Sanktion wg. Versäumnis droht, kann der Spätzugang in der Anhörung / im Widerspruch gegen den Sanktionsbescheid (§§ 24, 33 SGB X i.V.m. § 37 Abs. 2 S. 3 SGB X) vorgetragen werden.', style: TextStyle(fontSize: 11, color: Colors.brown, fontWeight: FontWeight.w600))),
          ]))),
        ]))),
        const SizedBox(height: 10),
        // ── Termin ──────────────────────────────────────────────
        Card(color: Colors.indigo.shade50, child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Icon(Icons.event, size: 16, color: Colors.indigo), const SizedBox(width: 6), Text('Termin', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo.shade900))]),
          const SizedBox(height: 8),
          _dateField(_terminC, 'Termin-Datum (YYYY-MM-DD HH:MM)', icon: Icons.calendar_today, withTime: true),
          const SizedBox(height: 8),
          _dateField(_fristC, 'Antwort-Frist (optional)', icon: Icons.timer),
          if (gap != null) Padding(padding: const EdgeInsets.only(top: 6), child: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: gap < 7 ? Colors.amber.shade50 : Colors.green.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: gap < 7 ? Colors.amber.shade400 : Colors.green.shade300)), child: Row(children: [
            Icon(gap < 7 ? Icons.info_outline : Icons.check_circle, size: 14, color: gap < 7 ? Colors.amber : Colors.green), const SizedBox(width: 4),
            Expanded(child: Text(
              gap < 0 ? 'Termin liegt VOR dem Eingang ($gap Tage) — Daten prüfen.' :
              gap < 1 ? 'Termin am selben Tag wie Eingang — Mitglied sollte sofort Kontakt mit Jobcenter aufnehmen (Verschiebungsantrag).' :
              gap < 7 ? 'Nur $gap Tage zwischen Eingang und Termin (< 7 Tage). Hinweis: Bei einem späteren Sanktionsbescheid wg. Versäumnis kann die unzureichende Vorbereitungszeit (BSG-Linie 7 Tage Mindestvorlauf) als Argument im Widerspruchsverfahren gegen den Sanktionsbescheid dienen.' :
              'OK: $gap Tage zwischen Eingang und Termin (≥7 Tage Vorlauf eingehalten).',
              style: TextStyle(fontSize: 11, color: gap < 7 ? Colors.brown : Colors.green.shade900, fontWeight: FontWeight.w600),
            )),
          ]))),
        ]))),
        const SizedBox(height: 10),
        TextField(controller: _themaC, decoration: const InputDecoration(labelText: 'Thema (laut Einladung)', isDense: true, border: OutlineInputBorder(), prefixIcon: Icon(Icons.topic, size: 18)), maxLines: 2),
        const SizedBox(height: 8),
        SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Mit Meldepflicht (§ 32 SGB II)', style: TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text('Bei Versäumnis: 10% Sanktion (1. Mal seit 01.07.2026 ohne Sanktion)', style: TextStyle(fontSize: 11, color: Colors.red)), value: _meldepflicht, onChanged: (v) => setState(() => _meldepflicht = v)),
        const SizedBox(height: 4),
        TextField(controller: _notizC, decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder()), maxLines: 2),
      ]))),
      Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade300))), child: Row(children: [
        if (widget.existing != null) TextButton.icon(onPressed: _saving ? null : _delete, icon: const Icon(Icons.delete, color: Colors.red, size: 16), label: const Text('Löschen', style: TextStyle(color: Colors.red))),
        const Spacer(),
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Abbrechen')),
        const SizedBox(width: 8),
        ElevatedButton(onPressed: _saving ? null : _save, style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white), child: Text(_saving ? '...' : 'Speichern')),
      ])),
    ])));
  }
}

class _AvTermineTab extends StatelessWidget {
  final ApiService apiService;
  final int userId, userAvId;
  final List<Map<String, dynamic>> einladungen, termine;
  final bool loading;
  final VoidCallback onChanged;
  const _AvTermineTab({required this.apiService, required this.userId, required this.userAvId, required this.einladungen, required this.termine, required this.loading, required this.onChanged});

  Future<void> _openDialog(BuildContext context, [Map<String, dynamic>? existing]) async {
    final changed = await showDialog<bool>(context: context, builder: (_) => _TerminEditDialog(apiService: apiService, userId: userId, userAvId: userAvId, einladungen: einladungen, existing: existing));
    if (changed == true) onChanged();
  }

  static const _statusColors = {
    'geplant': Colors.blue, 'durchgefuehrt': Colors.green, 'versaeumt': Colors.red,
    'abgesagt_kunde': Colors.orange, 'abgesagt_jobcenter': Colors.purple, 'verschoben': Colors.grey,
  };
  static const _statusLabels = {
    'geplant': 'Geplant', 'durchgefuehrt': 'Durchgeführt', 'versaeumt': '⚠️ Versäumt',
    'abgesagt_kunde': 'Abgesagt v. Kunde', 'abgesagt_jobcenter': 'Abgesagt v. JC', 'verschoben': 'Verschoben',
  };
  static const _typLabels = {
    'erstgespraech': 'Erstgespräch', 'folgegespraech': 'Folgegespräch', 'vermittlung': 'Vermittlung',
    'kooperationsplan': 'Kooperationsplan (§15)', 'meldetermin': 'Meldetermin', 'anhoerung': 'Anhörung (Sanktion)',
    'vorsprache': 'Vorsprache', 'reha': 'Reha-Beratung', 'sonstige': 'Sonstige',
  };
  static const _initiatorLabels = {'jobcenter': 'Jobcenter', 'kunde': 'Kunde', 'verein': 'Verein', 'sonstige': 'Sonstige'};
  static const _initiatorIcons = {'jobcenter': Icons.business, 'kunde': Icons.person, 'verein': Icons.groups, 'sonstige': Icons.help_outline};

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Container(padding: const EdgeInsets.all(10), child: Row(children: [
        Expanded(child: Text('${termine.length} Termin(e)', style: const TextStyle(fontSize: 12, color: Colors.grey))),
        ElevatedButton.icon(onPressed: () => _openDialog(context), icon: const Icon(Icons.add, size: 14), label: const Text('Neuer Termin'), style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade700, foregroundColor: Colors.white, minimumSize: const Size(0, 32))),
      ])),
      Expanded(child: termine.isEmpty
          ? Center(child: Text('Keine Termine', style: TextStyle(color: Colors.grey.shade500)))
          : ListView.builder(itemCount: termine.length, itemBuilder: (_, i) {
              final t = termine[i];
              final st = (t['status'] ?? 'geplant').toString();
              final typ = (t['termin_typ'] ?? 'sonstige').toString();
              final init = (t['initiator'] ?? 'jobcenter').toString();
              final stColor = _statusColors[st] ?? Colors.grey;
              return Card(margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: InkWell(
                onTap: () => _openDialog(context, t),
                child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(_initiatorIcons[init] ?? Icons.help_outline, size: 16, color: Colors.indigo.shade700),
                    const SizedBox(width: 6),
                    Expanded(child: Text(t['termin_datum']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: stColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8), border: Border.all(color: stColor)), child: Text(_statusLabels[st] ?? st, style: TextStyle(fontSize: 10, color: stColor, fontWeight: FontWeight.bold))),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(4)), child: Text(_typLabels[typ] ?? typ, style: TextStyle(fontSize: 10, color: Colors.indigo.shade900))),
                    const SizedBox(width: 6),
                    Text('initiiert v. ${_initiatorLabels[init]}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ]),
                  if ((t['verlauf'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Verlauf: ${t['verlauf']}', style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic), maxLines: 2, overflow: TextOverflow.ellipsis)),
                  if ((t['sanktion_drohend'] ?? 0) == 1) Padding(padding: const EdgeInsets.only(top: 4), child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.red.shade300)), child: Row(children: [const Icon(Icons.warning, size: 12, color: Colors.red), const SizedBox(width: 4), Expanded(child: Text('Sanktion drohend${(t['sanktion_paragraf'] ?? '').toString().isNotEmpty ? " (${t['sanktion_paragraf']})" : ""}', style: const TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold)))]))),
                ])),
              ));
            })),
    ]);
  }
}

class _TerminEditDialog extends StatefulWidget {
  final ApiService apiService;
  final int userId, userAvId;
  final List<Map<String, dynamic>> einladungen;
  final Map<String, dynamic>? existing;
  const _TerminEditDialog({required this.apiService, required this.userId, required this.userAvId, required this.einladungen, this.existing});
  @override State<_TerminEditDialog> createState() => _TerminEditDialogState();
}
class _TerminEditDialogState extends State<_TerminEditDialog> {
  late TextEditingController _datumC, _ortC, _themaC, _verlaufC, _ergebnisC, _sanktionParaC, _notizC;
  String _typ = 'folgegespraech', _initiator = 'jobcenter', _modus = 'persoenlich', _status = 'geplant';
  int? _einladungId;
  bool _anwMit = true, _anwVor = false, _anwDol = false, _sanktion = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing ?? const {};
    _datumC = TextEditingController(text: e['termin_datum']?.toString() ?? DateTime.now().toIso8601String().substring(0, 16).replaceFirst('T', ' '));
    _ortC = TextEditingController(text: e['ort']?.toString() ?? '');
    _themaC = TextEditingController(text: e['thema']?.toString() ?? '');
    _verlaufC = TextEditingController(text: e['verlauf']?.toString() ?? '');
    _ergebnisC = TextEditingController(text: e['ergebnis']?.toString() ?? '');
    _sanktionParaC = TextEditingController(text: e['sanktion_paragraf']?.toString() ?? '');
    _notizC = TextEditingController(text: e['notiz']?.toString() ?? '');
    _typ = (e['termin_typ'] ?? 'folgegespraech').toString();
    _initiator = (e['initiator'] ?? 'jobcenter').toString();
    _modus = (e['modus'] ?? 'persoenlich').toString();
    _status = (e['status'] ?? 'geplant').toString();
    _einladungId = e['einladung_id'] != null ? (e['einladung_id'] as num).toInt() : null;
    _anwMit = (e['anwesend_mitglied'] ?? 1) == 1;
    _anwVor = (e['anwesend_vorsitzer'] ?? 0) == 1;
    _anwDol = (e['anwesend_dolmetscher'] ?? 0) == 1;
    _sanktion = (e['sanktion_drohend'] ?? 0) == 1;
  }
  @override
  void dispose() { _datumC.dispose(); _ortC.dispose(); _themaC.dispose(); _verlaufC.dispose(); _ergebnisC.dispose(); _sanktionParaC.dispose(); _notizC.dispose(); super.dispose(); }

  Future<void> _save() async {
    setState(() => _saving = true);
    final body = {
      'termin': {
        'einladung_id': _einladungId,
        'termin_datum': _datumC.text.trim(),
        'termin_typ': _typ, 'initiator': _initiator, 'modus': _modus, 'status': _status,
        'ort': _ortC.text.trim(),
        'anwesend_mitglied': _anwMit, 'anwesend_vorsitzer': _anwVor, 'anwesend_dolmetscher': _anwDol,
        'thema': _themaC.text.trim(),
        'verlauf': _verlaufC.text.trim(),
        'ergebnis': _ergebnisC.text.trim(),
        'sanktion_drohend': _sanktion,
        'sanktion_paragraf': _sanktionParaC.text.trim(),
        'notiz': _notizC.text.trim(),
      },
    };
    final res = widget.existing == null
        ? await widget.apiService.jobcenterAvAction({...body, 'action': 'create_termin', 'user_id': widget.userId, 'user_av_id': widget.userAvId})
        : await widget.apiService.jobcenterAvAction({...body, 'action': 'update_termin', 'termin_id': widget.existing!['id']});
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['success'] == true) Navigator.pop(context, true);
    else ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Fehler'), backgroundColor: Colors.red));
  }

  Future<void> _delete() async {
    if (widget.existing == null) return;
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Termin löschen?'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')), TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Löschen', style: TextStyle(color: Colors.red)))],
    ));
    if (ok != true) return;
    await widget.apiService.jobcenterAvAction({'action': 'delete_termin', 'termin_id': widget.existing!['id']});
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Dialog(insetPadding: const EdgeInsets.all(16), child: SizedBox(width: 600, height: 620, child: Column(children: [
    Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.indigo.shade700, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))), child: Row(children: [
      const Icon(Icons.event, color: Colors.white), const SizedBox(width: 8),
      Expanded(child: Text(widget.existing == null ? 'Neuer Termin' : 'Termin bearbeiten', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
      IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
    ])),
    Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(12), child: Column(children: [
      TextField(controller: _datumC, decoration: const InputDecoration(labelText: 'Termin-Datum (YYYY-MM-DD HH:MM)', isDense: true, border: OutlineInputBorder(), prefixIcon: Icon(Icons.calendar_today, size: 18))),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: DropdownButtonFormField<String>(initialValue: _typ, decoration: const InputDecoration(labelText: 'Typ', isDense: true, border: OutlineInputBorder()), items: const [
          DropdownMenuItem(value: 'erstgespraech', child: Text('Erstgespräch')), DropdownMenuItem(value: 'folgegespraech', child: Text('Folgegespräch')),
          DropdownMenuItem(value: 'vermittlung', child: Text('Vermittlung')), DropdownMenuItem(value: 'kooperationsplan', child: Text('Kooperationsplan (§15)')),
          DropdownMenuItem(value: 'meldetermin', child: Text('Meldetermin')), DropdownMenuItem(value: 'anhoerung', child: Text('Anhörung (Sanktion)')),
          DropdownMenuItem(value: 'vorsprache', child: Text('Vorsprache')), DropdownMenuItem(value: 'reha', child: Text('Reha-Beratung')), DropdownMenuItem(value: 'sonstige', child: Text('Sonstige')),
        ], onChanged: (v) => setState(() => _typ = v ?? 'folgegespraech'))),
        const SizedBox(width: 8),
        Expanded(child: DropdownButtonFormField<String>(initialValue: _initiator, decoration: const InputDecoration(labelText: 'Initiiert von', isDense: true, border: OutlineInputBorder()), items: const [
          DropdownMenuItem(value: 'jobcenter', child: Text('Jobcenter')), DropdownMenuItem(value: 'kunde', child: Text('Kunde')),
          DropdownMenuItem(value: 'verein', child: Text('Verein')), DropdownMenuItem(value: 'sonstige', child: Text('Sonstige')),
        ], onChanged: (v) => setState(() => _initiator = v ?? 'jobcenter'))),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: DropdownButtonFormField<String>(initialValue: _modus, decoration: const InputDecoration(labelText: 'Modus', isDense: true, border: OutlineInputBorder()), items: const [
          DropdownMenuItem(value: 'persoenlich', child: Text('Persönlich')), DropdownMenuItem(value: 'telefonisch', child: Text('Telefonisch')),
          DropdownMenuItem(value: 'video', child: Text('Video')), DropdownMenuItem(value: 'schriftlich', child: Text('Schriftlich')),
        ], onChanged: (v) => setState(() => _modus = v ?? 'persoenlich'))),
        const SizedBox(width: 8),
        Expanded(child: DropdownButtonFormField<String>(initialValue: _status, decoration: const InputDecoration(labelText: 'Status', isDense: true, border: OutlineInputBorder()), items: const [
          DropdownMenuItem(value: 'geplant', child: Text('Geplant')), DropdownMenuItem(value: 'durchgefuehrt', child: Text('Durchgeführt')),
          DropdownMenuItem(value: 'versaeumt', child: Text('Versäumt')), DropdownMenuItem(value: 'abgesagt_kunde', child: Text('Abgesagt v. Kunde')),
          DropdownMenuItem(value: 'abgesagt_jobcenter', child: Text('Abgesagt v. JC')), DropdownMenuItem(value: 'verschoben', child: Text('Verschoben')),
        ], onChanged: (v) => setState(() => _status = v ?? 'geplant'))),
      ]),
      const SizedBox(height: 8),
      TextField(controller: _ortC, decoration: const InputDecoration(labelText: 'Ort (z.B. Zimmer 203 / online / telefonisch)', isDense: true, border: OutlineInputBorder())),
      if (widget.einladungen.isNotEmpty) ...[
        const SizedBox(height: 8),
        DropdownButtonFormField<int?>(initialValue: _einladungId, decoration: const InputDecoration(labelText: 'Aus Einladung (optional)', isDense: true, border: OutlineInputBorder(), prefixIcon: Icon(Icons.link, size: 18)), items: [
          const DropdownMenuItem(value: null, child: Text('— keine —')),
          ...widget.einladungen.map((e) => DropdownMenuItem(value: e['id'] as int, child: Text('${e['einladung_datum_termin'] ?? "?"} — ${e['thema'] ?? "?"}', overflow: TextOverflow.ellipsis))),
        ], onChanged: (v) => setState(() => _einladungId = v)),
      ],
      const SizedBox(height: 12),
      Card(color: Colors.indigo.shade50, child: Padding(padding: const EdgeInsets.all(8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Anwesend', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.indigo.shade800)),
        Row(children: [
          Expanded(child: CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, title: const Text('Mitglied', style: TextStyle(fontSize: 11)), value: _anwMit, onChanged: (v) => setState(() => _anwMit = v ?? false))),
          Expanded(child: CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, title: const Text('Vorsitzer', style: TextStyle(fontSize: 11)), value: _anwVor, onChanged: (v) => setState(() => _anwVor = v ?? false))),
          Expanded(child: CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, title: const Text('Dolmetscher', style: TextStyle(fontSize: 11)), value: _anwDol, onChanged: (v) => setState(() => _anwDol = v ?? false))),
        ]),
      ]))),
      const SizedBox(height: 8),
      TextField(controller: _themaC, decoration: const InputDecoration(labelText: 'Thema (was war geplant?)', isDense: true, border: OutlineInputBorder()), maxLines: 2),
      const SizedBox(height: 8),
      TextField(controller: _verlaufC, decoration: const InputDecoration(labelText: 'Verlauf — was ist passiert?', isDense: true, border: OutlineInputBorder(), prefixIcon: Icon(Icons.history_edu, size: 18)), maxLines: 4),
      const SizedBox(height: 8),
      TextField(controller: _ergebnisC, decoration: const InputDecoration(labelText: 'Ergebnis / Vereinbarungen', isDense: true, border: OutlineInputBorder()), maxLines: 3),
      const SizedBox(height: 8),
      if (_status == 'versaeumt') Card(color: Colors.red.shade50, child: Padding(padding: const EdgeInsets.all(8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Sanktion drohend?', style: TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text('§ 31a SGB II (Pflichtverletzung) / § 32 SGB II (Meldeversäumnis)', style: TextStyle(fontSize: 10)), value: _sanktion, onChanged: (v) => setState(() => _sanktion = v)),
        if (_sanktion) TextField(controller: _sanktionParaC, decoration: const InputDecoration(labelText: 'Paragraf (z.B. § 32 SGB II)', isDense: true, border: OutlineInputBorder()), style: const TextStyle(fontSize: 12)),
      ]))),
      const SizedBox(height: 8),
      TextField(controller: _notizC, decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder()), maxLines: 2),
    ]))),
    Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade300))), child: Row(children: [
      if (widget.existing != null) TextButton.icon(onPressed: _saving ? null : _delete, icon: const Icon(Icons.delete, color: Colors.red, size: 16), label: const Text('Löschen', style: TextStyle(color: Colors.red))),
      const Spacer(),
      TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Abbrechen')),
      const SizedBox(width: 8),
      ElevatedButton.icon(onPressed: _saving ? null : _save, icon: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 16), label: const Text('Speichern'), style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade700, foregroundColor: Colors.white)),
    ])),
  ])));
}
