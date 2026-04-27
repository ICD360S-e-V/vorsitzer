import 'package:flutter/material.dart';
import '../services/api_service.dart';

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
    _tabController = TabController(length: 2, vsync: this);
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
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      TabBar(controller: _tabController, labelColor: Colors.red.shade800, unselectedLabelColor: Colors.grey, indicatorColor: Colors.red.shade700, tabs: const [
        Tab(text: 'Zuständiges Jobcenter'),
        Tab(text: 'Antrag'),
      ]),
      Expanded(child: TabBarView(controller: _tabController, children: [
        _JobcenterStammdatenTab(data: _data, apiService: widget.apiService, userId: widget.userId, onSave: _saveData),
        _JobcenterAntragTab(antraege: _antraege, apiService: widget.apiService, userId: widget.userId, onReload: _load),
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
  List<Map<String, dynamic>> _standorte = [];
  Map<String, dynamic>? _selectedAmt;
  bool _searching = false;
  final _searchC = TextEditingController();
  late TextEditingController _kundennummerC, _bgNummerC, _arbeitsvermittlerC, _arbeitsvermittlerTelC, _arbeitsvermittlerEmailC, _emailC, _passkeyC;
  bool _hasOnline = false;
  bool _hasPasskey = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    _kundennummerC = TextEditingController(text: d['stammdaten.kundennummer'] ?? '');
    _bgNummerC = TextEditingController(text: d['stammdaten.bg_nummer'] ?? '');
    _arbeitsvermittlerC = TextEditingController(text: d['stammdaten.arbeitsvermittler'] ?? '');
    _arbeitsvermittlerTelC = TextEditingController(text: d['stammdaten.arbeitsvermittler_tel'] ?? '');
    _arbeitsvermittlerEmailC = TextEditingController(text: d['stammdaten.arbeitsvermittler_email'] ?? '');
    _emailC = TextEditingController(text: d['stammdaten.online_email'] ?? '');
    _passkeyC = TextEditingController(text: d['stammdaten.passkey_access'] ?? '');
    _hasOnline = d['stammdaten.has_online_account'] == 'true';
    _hasPasskey = d['stammdaten.has_passkey'] == 'true';
    if (d['stammdaten.selected_amt'] != null) {
      try { _selectedAmt = Map<String, dynamic>.from(d['stammdaten.selected_amt'] is Map ? d['stammdaten.selected_amt'] : {}); } catch (_) {}
    }
    final amtName = d['stammdaten.selected_amt_name'] ?? '';
    if (amtName.isNotEmpty && _selectedAmt == null) {
      _selectedAmt = {'name': amtName};
    }
  }

  @override
  void dispose() {
    _searchC.dispose(); _kundennummerC.dispose(); _bgNummerC.dispose();
    _arbeitsvermittlerC.dispose(); _arbeitsvermittlerTelC.dispose(); _arbeitsvermittlerEmailC.dispose();
    _emailC.dispose(); _passkeyC.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.length < 2) return;
    setState(() => _searching = true);
    try {
      _standorte = await widget.apiService.getBehoerdenStandorte(typ: 'jobcenter');
      _standorte = _standorte.where((s) => (s['name']?.toString() ?? '').toLowerCase().contains(q.toLowerCase()) || (s['ort']?.toString() ?? '').toLowerCase().contains(q.toLowerCase())).toList();
    } catch (_) {}
    if (mounted) setState(() => _searching = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final fields = <String, String>{
      'stammdaten.kundennummer': _kundennummerC.text.trim(),
      'stammdaten.bg_nummer': _bgNummerC.text.trim(),
      'stammdaten.arbeitsvermittler': _arbeitsvermittlerC.text.trim(),
      'stammdaten.arbeitsvermittler_tel': _arbeitsvermittlerTelC.text.trim(),
      'stammdaten.arbeitsvermittler_email': _arbeitsvermittlerEmailC.text.trim(),
      'stammdaten.online_email': _emailC.text.trim(),
      'stammdaten.passkey_access': _passkeyC.text.trim(),
      'stammdaten.has_online_account': _hasOnline.toString(),
      'stammdaten.has_passkey': _hasPasskey.toString(),
    };
    if (_selectedAmt != null) {
      fields['stammdaten.selected_amt_name'] = _selectedAmt!['name']?.toString() ?? '';
      fields['stammdaten.selected_amt_adresse'] = _selectedAmt!['adresse']?.toString() ?? '';
      fields['stammdaten.selected_amt_ort'] = _selectedAmt!['ort']?.toString() ?? '';
      fields['stammdaten.selected_amt_telefon'] = _selectedAmt!['telefon']?.toString() ?? '';
    }
    await widget.onSave(fields);
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Gespeichert'), backgroundColor: Colors.green.shade600));
    }
  }

  Widget _field(String label, TextEditingController c, {IconData icon = Icons.edit, int maxLines = 1}) {
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: TextField(controller: c, maxLines: maxLines, decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 20), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Search Jobcenter
      Text('Zuständiges Jobcenter suchen', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: TextField(controller: _searchC, decoration: InputDecoration(hintText: 'Name oder Ort...', prefixIcon: const Icon(Icons.search, size: 20), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          onSubmitted: _search)),
        const SizedBox(width: 8),
        ElevatedButton(onPressed: () => _search(_searchC.text), style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white), child: const Text('Suchen')),
      ]),
      if (_searching) const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
      if (_standorte.isNotEmpty) Container(
        margin: const EdgeInsets.only(top: 8), constraints: const BoxConstraints(maxHeight: 200),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
        child: ListView.builder(shrinkWrap: true, itemCount: _standorte.length, itemBuilder: (ctx, i) {
          final s = _standorte[i];
          return ListTile(dense: true, title: Text(s['name'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            subtitle: Text('${s['adresse'] ?? ''}, ${s['plz'] ?? ''} ${s['ort'] ?? ''}', style: const TextStyle(fontSize: 11)),
            trailing: const Icon(Icons.check_circle_outline, size: 20),
            onTap: () => setState(() { _selectedAmt = s; _standorte = []; }));
        }),
      ),
      if (_selectedAmt != null) Container(
        margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade200)),
        child: Row(children: [
          Icon(Icons.business, color: Colors.red.shade700, size: 24),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_selectedAmt!['name'] ?? '', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.red.shade800)),
            if (_selectedAmt!['adresse'] != null) Text('${_selectedAmt!['adresse']}, ${_selectedAmt!['plz'] ?? ''} ${_selectedAmt!['ort'] ?? ''}', style: const TextStyle(fontSize: 12)),
            if (_selectedAmt!['telefon'] != null) Text('Tel: ${_selectedAmt!['telefon']}', style: const TextStyle(fontSize: 11)),
          ])),
          IconButton(icon: Icon(Icons.close, color: Colors.red.shade400), onPressed: () => setState(() => _selectedAmt = null)),
        ]),
      ),
      const Divider(height: 24),

      // Stammdaten
      Text('Stammdaten', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _field('Kundennummer', _kundennummerC, icon: Icons.badge)),
        const SizedBox(width: 12),
        Expanded(child: _field('BG-Nummer', _bgNummerC, icon: Icons.numbers)),
      ]),
      const Divider(height: 16),

      // Sachbearbeiter
      Text('Sachbearbeiter / Arbeitsvermittler', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
      const SizedBox(height: 8),
      _field('Arbeitsvermittler/in (pAp)', _arbeitsvermittlerC, icon: Icons.support_agent),
      Row(children: [
        Expanded(child: _field('Telefon', _arbeitsvermittlerTelC, icon: Icons.phone)),
        const SizedBox(width: 12),
        Expanded(child: _field('E-Mail', _arbeitsvermittlerEmailC, icon: Icons.email)),
      ]),
      const Divider(height: 16),

      // Online-Konto
      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.cloud, size: 18, color: Colors.blue.shade700),
            const SizedBox(width: 8),
            Text('Online-Konto (jobcenter.digital)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue.shade700)),
            const Spacer(),
            Switch(value: _hasOnline, onChanged: (v) => setState(() => _hasOnline = v), activeThumbColor: Colors.blue),
          ]),
          if (_hasOnline) ...[
            const SizedBox(height: 12),
            _field('E-Mail', _emailC, icon: Icons.email),
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade200)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.key, size: 18, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Text('Passkey aktiviert', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.orange.shade700)),
                  const Spacer(),
                  Switch(value: _hasPasskey, onChanged: (v) => setState(() => _hasPasskey = v), activeThumbColor: Colors.orange),
                ]),
                if (_hasPasskey) _field('Zugang zum Passkey', _passkeyC, icon: Icons.person_pin),
              ]),
            ),
          ],
        ]),
      ),
      const SizedBox(height: 20),

      Align(alignment: Alignment.centerRight, child: ElevatedButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 18),
        label: const Text('Speichern'),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
      )),
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
    _tabC = TabController(length: 3, vsync: this);
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
      TabBar(controller: _tabC, labelColor: Colors.red.shade800, unselectedLabelColor: Colors.grey, indicatorColor: Colors.red.shade700, tabs: const [
        Tab(text: 'Details'),
        Tab(text: 'Korrespondenz'),
        Tab(text: 'Termin'),
      ]),
      Expanded(child: TabBarView(controller: _tabC, children: [
        _AntragDetailsTab(antrag: widget.antrag, apiService: widget.apiService, userId: widget.userId, onReload: widget.onReload),
        _AntragKorrTab(antragId: widget.antrag['id'] as int, apiService: widget.apiService, userId: widget.userId),
        _AntragTerminTab(antragId: widget.antrag['id'] as int, apiService: widget.apiService, userId: widget.userId),
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
  late TextEditingController _bescheidVonC, _bescheidBisC, _bescheidBetragC, _regelsatzC, _kduC, _heizkostenC, _mehrbedarfC, _mehrbedarfGrundC;
  late TextEditingController _egvVonC, _egvBisC, _egvPflichtenC;
  late TextEditingController _massnahmeNameC, _massnahmeVonC, _massnahmeBisC, _massnahmeTraegerC;
  late TextEditingController _sanktionNotizC;
  late String _massnahmeArt, _massnahmeStatus;
  bool _hasEgv = false, _hasMassnahme = false, _hasSanktion = false;
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
    _bescheidVonC = TextEditingController(text: a['bescheid_von']?.toString() ?? '');
    _bescheidBisC = TextEditingController(text: a['bescheid_bis']?.toString() ?? '');
    _bescheidBetragC = TextEditingController(text: a['bescheid_betrag']?.toString() ?? '');
    _regelsatzC = TextEditingController(text: a['regelsatz']?.toString() ?? '');
    _kduC = TextEditingController(text: a['kdu']?.toString() ?? '');
    _heizkostenC = TextEditingController(text: a['heizkosten']?.toString() ?? '');
    _mehrbedarfC = TextEditingController(text: a['mehrbedarf']?.toString() ?? '');
    _mehrbedarfGrundC = TextEditingController(text: a['mehrbedarf_grund']?.toString() ?? '');
    _egvVonC = TextEditingController(text: a['egv_von']?.toString() ?? '');
    _egvBisC = TextEditingController(text: a['egv_bis']?.toString() ?? '');
    _egvPflichtenC = TextEditingController(text: a['egv_pflichten']?.toString() ?? '');
    _massnahmeNameC = TextEditingController(text: a['massnahme_name']?.toString() ?? '');
    _massnahmeVonC = TextEditingController(text: a['massnahme_von']?.toString() ?? '');
    _massnahmeBisC = TextEditingController(text: a['massnahme_bis']?.toString() ?? '');
    _massnahmeTraegerC = TextEditingController(text: a['massnahme_traeger']?.toString() ?? '');
    _sanktionNotizC = TextEditingController(text: a['sanktion_notiz']?.toString() ?? '');
    _massnahmeArt = a['massnahme_art']?.toString() ?? '';
    _massnahmeStatus = a['massnahme_status']?.toString() ?? '';
    _hasEgv = a['has_egv']?.toString() == 'true';
    _hasMassnahme = a['has_massnahme']?.toString() == 'true';
    _hasSanktion = a['has_sanktion']?.toString() == 'true';
  }

  @override
  void dispose() {
    _datumC.dispose(); _aktenzeichenC.dispose(); _notizC.dispose();
    _bescheidVonC.dispose(); _bescheidBisC.dispose(); _bescheidBetragC.dispose();
    _regelsatzC.dispose(); _kduC.dispose(); _heizkostenC.dispose();
    _mehrbedarfC.dispose(); _mehrbedarfGrundC.dispose();
    _egvVonC.dispose(); _egvBisC.dispose(); _egvPflichtenC.dispose();
    _massnahmeNameC.dispose(); _massnahmeVonC.dispose(); _massnahmeBisC.dispose(); _massnahmeTraegerC.dispose();
    _sanktionNotizC.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.apiService.jobcenterAction(widget.userId, {
      'action': 'save_antrag',
      'antrag': {
        'id': widget.antrag['id'],
        'art': _art, 'status': _status, 'datum': _datumC.text, 'aktenzeichen': _aktenzeichenC.text, 'notiz': _notizC.text,
        'bescheid_von': _bescheidVonC.text, 'bescheid_bis': _bescheidBisC.text, 'bescheid_betrag': _bescheidBetragC.text,
        'regelsatz': _regelsatzC.text, 'kdu': _kduC.text, 'heizkosten': _heizkostenC.text,
        'mehrbedarf': _mehrbedarfC.text, 'mehrbedarf_grund': _mehrbedarfGrundC.text,
        'has_egv': _hasEgv.toString(), 'egv_von': _egvVonC.text, 'egv_bis': _egvBisC.text, 'egv_pflichten': _egvPflichtenC.text,
        'has_massnahme': _hasMassnahme.toString(), 'massnahme_art': _massnahmeArt, 'massnahme_status': _massnahmeStatus,
        'massnahme_name': _massnahmeNameC.text, 'massnahme_traeger': _massnahmeTraegerC.text,
        'massnahme_von': _massnahmeVonC.text, 'massnahme_bis': _massnahmeBisC.text,
        'has_sanktion': _hasSanktion.toString(), 'sanktion_notiz': _sanktionNotizC.text,
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

      // Bewilligungsbescheid
      _section(Icons.description, 'Bewilligungsbescheid', Colors.green.shade700, [
        Row(children: [Expanded(child: _dateField('Von', _bescheidVonC)), const SizedBox(width: 8), Expanded(child: _dateField('Bis', _bescheidBisC))]),
        Row(children: [Expanded(child: _field('Gesamtbetrag €/Mo', _bescheidBetragC, icon: Icons.euro)), const SizedBox(width: 8), Expanded(child: _field('Regelsatz €', _regelsatzC, icon: Icons.account_balance_wallet))]),
        Row(children: [Expanded(child: _field('KdU Miete €', _kduC, icon: Icons.home)), const SizedBox(width: 8), Expanded(child: _field('Heizkosten €', _heizkostenC, icon: Icons.local_fire_department))]),
        Row(children: [Expanded(child: _field('Mehrbedarf €', _mehrbedarfC, icon: Icons.add_circle)), const SizedBox(width: 8), Expanded(child: _field('Mehrbedarf Grund', _mehrbedarfGrundC, icon: Icons.info))]),
      ]),

      // EGV
      _section(Icons.handshake, 'EGV / Kooperationsplan', Colors.purple.shade700, [
        Row(children: [
          Text('Vorhanden', style: TextStyle(fontSize: 12, color: Colors.purple.shade700)),
          const Spacer(),
          Switch(value: _hasEgv, onChanged: (v) => setState(() => _hasEgv = v), activeThumbColor: Colors.purple),
        ]),
        if (_hasEgv) ...[
          Row(children: [Expanded(child: _dateField('Von', _egvVonC)), const SizedBox(width: 8), Expanded(child: _dateField('Bis', _egvBisC))]),
          _field('Pflichten / Eigenbemühungen', _egvPflichtenC, icon: Icons.checklist, maxLines: 2),
        ],
      ]),

      // Maßnahme
      _section(Icons.school, 'Maßnahme / Programm', Colors.cyan.shade700, [
        Row(children: [
          Text('Aktiv', style: TextStyle(fontSize: 12, color: Colors.cyan.shade700)),
          const Spacer(),
          Switch(value: _hasMassnahme, onChanged: (v) => setState(() => _hasMassnahme = v), activeThumbColor: Colors.cyan.shade700),
        ]),
        if (_hasMassnahme) ...[
          Row(children: [
            Expanded(child: DropdownButtonFormField<String>(value: _massnahmeArt.isEmpty ? null : _massnahmeArt, decoration: InputDecoration(labelText: 'Art', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              items: const [
                DropdownMenuItem(value: 'bewerbungstraining', child: Text('Bewerbungstraining', style: TextStyle(fontSize: 11))),
                DropdownMenuItem(value: 'aktivierung', child: Text('Aktivierungsmaßnahme', style: TextStyle(fontSize: 11))),
                DropdownMenuItem(value: 'agh', child: Text('Arbeitsgelegenheit (1€-Job)', style: TextStyle(fontSize: 11))),
                DropdownMenuItem(value: 'umschulung', child: Text('Umschulung', style: TextStyle(fontSize: 11))),
                DropdownMenuItem(value: 'weiterbildung', child: Text('Weiterbildung (FbW)', style: TextStyle(fontSize: 11))),
                DropdownMenuItem(value: 'sprachkurs', child: Text('Sprachkurs', style: TextStyle(fontSize: 11))),
                DropdownMenuItem(value: 'praktikum', child: Text('Praktikum', style: TextStyle(fontSize: 11))),
                DropdownMenuItem(value: 'coaching', child: Text('Coaching (AVGS)', style: TextStyle(fontSize: 11))),
                DropdownMenuItem(value: 'sonstiges', child: Text('Sonstiges', style: TextStyle(fontSize: 11))),
              ],
              onChanged: (v) => setState(() => _massnahmeArt = v ?? ''))),
            const SizedBox(width: 8),
            Expanded(child: DropdownButtonFormField<String>(value: _massnahmeStatus.isEmpty ? null : _massnahmeStatus, decoration: InputDecoration(labelText: 'Status', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              items: const [
                DropdownMenuItem(value: 'zugewiesen', child: Text('Zugewiesen', style: TextStyle(fontSize: 11))),
                DropdownMenuItem(value: 'aktiv', child: Text('Aktiv', style: TextStyle(fontSize: 11))),
                DropdownMenuItem(value: 'abgeschlossen', child: Text('Abgeschlossen', style: TextStyle(fontSize: 11))),
                DropdownMenuItem(value: 'abgebrochen', child: Text('Abgebrochen', style: TextStyle(fontSize: 11))),
              ],
              onChanged: (v) => setState(() => _massnahmeStatus = v ?? ''))),
          ]),
          const SizedBox(height: 8),
          _field('Bezeichnung', _massnahmeNameC, icon: Icons.label),
          _field('Träger', _massnahmeTraegerC, icon: Icons.business),
          Row(children: [Expanded(child: _dateField('Beginn', _massnahmeVonC)), const SizedBox(width: 8), Expanded(child: _dateField('Ende', _massnahmeBisC))]),
        ],
      ]),

      // Sanktion
      _section(Icons.warning_amber, 'Sanktionen', Colors.red.shade700, [
        Row(children: [
          Text('Aktiv', style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
          const Spacer(),
          Switch(value: _hasSanktion, onChanged: (v) => setState(() => _hasSanktion = v), activeThumbColor: Colors.red),
        ]),
        if (_hasSanktion) _field('Details', _sanktionNotizC, icon: Icons.notes, maxLines: 2),
      ]),

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
      final res = await widget.apiService.getJobcenterAntragDetail(widget.antragId);
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
            return Card(margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), child: ListTile(dense: true,
              leading: Icon(isEin ? Icons.call_received : Icons.call_made, color: isEin ? Colors.blue : Colors.orange, size: 20),
              title: Text(k['betreff']?.toString() ?? '(kein Betreff)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              subtitle: Text('${k['datum'] ?? ''} · ${k['methode'] ?? ''}', style: const TextStyle(fontSize: 10)),
              trailing: IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade300), onPressed: () => _delete(k['id'] as int)),
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
      final res = await widget.apiService.getJobcenterAntragDetail(widget.antragId);
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
