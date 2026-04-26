import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import '../services/termin_service.dart';
import '../utils/file_picker_helper.dart';
import 'korrespondenz_attachments_widget.dart';

class BehordeKindergartenContent extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  const BehordeKindergartenContent({super.key, required this.apiService, required this.userId});
  @override
  State<BehordeKindergartenContent> createState() => _State();
}

class _State extends State<BehordeKindergartenContent> with TickerProviderStateMixin {
  late final TabController _tabCtrl;
  bool _loaded = false, _loading = false, _saving = false;
  Map<String, dynamic> _data = {};
  List<Map<String, dynamic>> _kinder = [];

  @override
  void initState() { super.initState(); _tabCtrl = TabController(length: 2, vsync: this); _load(); }
  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  String _v(String f) => _data[f]?.toString() ?? '';

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final res = await widget.apiService.getKindergartenData(widget.userId);
      if (res['success'] == true && mounted) {
        final raw = res['data'];
        if (raw is Map) { _data = {}; for (final e in raw.entries) { final p = e.key.toString().split('.'); _data[p.length == 2 ? p[1] : e.key.toString()] = e.value; } }
        _kinder = (res['kinder'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    if (mounted) setState(() { _loading = false; _loaded = true; });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded && !_loading) _load();
    if (_loading || !_loaded) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      TabBar(controller: _tabCtrl, labelColor: Colors.pink.shade700, unselectedLabelColor: Colors.grey.shade500, indicatorColor: Colors.pink.shade700,
        tabs: const [Tab(icon: Icon(Icons.child_care, size: 16), text: 'Zuständiger Kindergarten'), Tab(icon: Icon(Icons.people, size: 16), text: 'Kinder')]),
      Expanded(child: TabBarView(controller: _tabCtrl, children: [_buildKigaTab(), _buildKinderTab()])),
    ]);
  }

  Future<void> _searchKiga() async {
    final standorte = await widget.apiService.getBehoerdenStandorte(typ: 'kindergarten');
    if (!mounted || standorte.isEmpty) return;
    final selected = await showDialog<Map<String, dynamic>>(context: context, builder: (sCtx) {
      String search = '';
      List<Map<String, dynamic>> results = standorte;
      return StatefulBuilder(builder: (sCtx, setS) => AlertDialog(
        title: Row(children: [Icon(Icons.child_care, size: 18, color: Colors.pink.shade700), const SizedBox(width: 8), const Text('Kindergarten suchen', style: TextStyle(fontSize: 14))]),
        content: SizedBox(width: 450, height: 400, child: Column(children: [
          TextField(autofocus: true, decoration: InputDecoration(hintText: 'Name oder Ort eingeben...', prefixIcon: const Icon(Icons.search, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
            onChanged: (v) => setS(() { search = v.toLowerCase(); results = standorte.where((s) => (s['name']?.toString() ?? '').toLowerCase().contains(search) || (s['plz_ort']?.toString() ?? '').toLowerCase().contains(search)).toList(); })),
          const SizedBox(height: 8),
          Expanded(child: results.isEmpty ? Center(child: Text('Keine Ergebnisse', style: TextStyle(color: Colors.grey.shade500)))
            : ListView.builder(itemCount: results.length, itemBuilder: (_, i) {
                final s = results[i];
                return ListTile(dense: true, leading: Icon(Icons.child_care, size: 18, color: Colors.pink.shade400),
                  title: Text(s['name']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text([s['strasse'], s['plz_ort']].where((v) => v != null && v.toString().isNotEmpty).join(', '), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  onTap: () => Navigator.pop(sCtx, s));
              })),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(sCtx), child: const Text('Abbrechen'))],
      ));
    });
    if (selected != null) {
      final str = selected['strasse']?.toString() ?? '';
      final plz = selected['plz_ort']?.toString() ?? '';
      final m = <String, dynamic>{
        'stammdaten.name': selected['name']?.toString() ?? '',
        'stammdaten.adresse': [str, plz].where((v) => v.isNotEmpty).join(', '),
        'stammdaten.telefon': selected['telefon']?.toString() ?? '',
        'stammdaten.email': selected['email']?.toString() ?? '',
        'stammdaten.oeffnungszeiten': selected['oeffnungszeiten']?.toString() ?? '',
      };
      await widget.apiService.saveKindergartenData(widget.userId, m);
      for (final e in m.entries) { _data[e.key.split('.').last] = e.value; }
      if (mounted) setState(() {});
    }
  }

  Widget _buildKigaTab() {
    final hasKiga = _v('name').isNotEmpty;
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.child_care, size: 20, color: Colors.pink.shade700), const SizedBox(width: 8),
        Text('Zuständiger Kindergarten', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.pink.shade700)),
        const Spacer(),
        FilledButton.icon(icon: const Icon(Icons.search, size: 16), label: Text(hasKiga ? 'Ändern' : 'Suchen', style: const TextStyle(fontSize: 12)),
          style: FilledButton.styleFrom(backgroundColor: Colors.pink.shade600, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero),
          onPressed: _searchKiga),
      ]),
      const SizedBox(height: 16),
      if (!hasKiga)
        Container(width: double.infinity, padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
          child: Column(children: [
            Icon(Icons.search, size: 48, color: Colors.grey.shade300), const SizedBox(height: 8),
            Text('Kein Kindergarten ausgewählt', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
            const SizedBox(height: 4),
            Text('Klicken Sie auf "Suchen" um einen Kindergarten auszuwählen', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
          ]))
      else
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.pink.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.pink.shade200)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(radius: 22, backgroundColor: Colors.pink.shade100, child: Icon(Icons.child_care, size: 24, color: Colors.pink.shade700)),
              const SizedBox(width: 12),
              Expanded(child: Text(_v('name'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.pink.shade800))),
              IconButton(icon: Icon(Icons.close, size: 18, color: Colors.red.shade400), tooltip: 'Entfernen', onPressed: () async {
                await widget.apiService.saveKindergartenData(widget.userId, {'stammdaten.name': '', 'stammdaten.adresse': '', 'stammdaten.telefon': '', 'stammdaten.email': '', 'stammdaten.oeffnungszeiten': ''});
                _data.clear(); if (mounted) setState(() {});
              }),
            ]),
            const Divider(height: 20),
            if (_v('adresse').isNotEmpty) _infoRow(Icons.location_on, _v('adresse'), Colors.pink),
            if (_v('telefon').isNotEmpty) _infoRow(Icons.phone, _v('telefon'), Colors.blue),
            if (_v('email').isNotEmpty) _infoRow(Icons.email, _v('email'), Colors.teal),
            if (_v('oeffnungszeiten').isNotEmpty) _infoRow(Icons.schedule, _v('oeffnungszeiten'), Colors.orange),
            if (_v('leiterin').isNotEmpty) _infoRow(Icons.person, 'Leitung: ${_v('leiterin')}', Colors.purple),
          ])),
    ]));
  }

  Widget _infoRow(IconData icon, String text, MaterialColor c) {
    return Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [
      Icon(icon, size: 16, color: c.shade600), const SizedBox(width: 10),
      Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: Colors.grey.shade800))),
    ]));
  }

  Widget _buildKinderTab() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Icon(Icons.people, size: 18, color: Colors.pink.shade700), const SizedBox(width: 8),
        Text('${_kinder.length} Kind(er)', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const Spacer(),
        FilledButton.icon(icon: const Icon(Icons.add, size: 16), label: const Text('Kind hinzufügen', style: TextStyle(fontSize: 12)),
          style: FilledButton.styleFrom(backgroundColor: Colors.pink.shade600, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero),
          onPressed: _addKind),
      ])),
      Expanded(child: _kinder.isEmpty
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.child_care, size: 48, color: Colors.grey.shade300), const SizedBox(height: 8), Text('Keine Kinder', style: TextStyle(fontSize: 12, color: Colors.grey.shade500))]))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _kinder.length, itemBuilder: (_, i) {
            final k = _kinder[i];
            final status = k['status']?.toString() ?? 'aktiv';
            final sc = status == 'aktiv' ? Colors.green : Colors.grey;
            return Container(margin: const EdgeInsets.only(bottom: 8), child: InkWell(borderRadius: BorderRadius.circular(8),
              onTap: () => _showKindDetail(k),
              child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.pink.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.pink.shade200)),
                child: Row(children: [
                  CircleAvatar(radius: 18, backgroundColor: Colors.pink.shade100, child: Icon(Icons.child_care, size: 20, color: Colors.pink.shade700)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text('${k['vorname'] ?? ''} ${k['nachname'] ?? ''}'.trim(), style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.pink.shade800))),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: sc.shade100, borderRadius: BorderRadius.circular(6)),
                        child: Text(status == 'aktiv' ? 'Aktiv' : 'Ausgetreten', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: sc.shade800))),
                    ]),
                    Row(children: [
                      if ((k['geburtsdatum']?.toString() ?? '').isNotEmpty) ...[Icon(Icons.cake, size: 11, color: Colors.grey.shade500), const SizedBox(width: 4), Text(k['geburtsdatum'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)), const SizedBox(width: 8)],
                      if ((k['gruppe']?.toString() ?? '').isNotEmpty) ...[Icon(Icons.group, size: 11, color: Colors.grey.shade500), const SizedBox(width: 4), Text(k['gruppe'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade600))],
                    ]),
                  ])),
                  IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: () async { await widget.apiService.deleteKindergartenKind(widget.userId, k['id'] is int ? k['id'] : int.parse(k['id'].toString())); _load(); }),
                ]))));
          })),
    ]);
  }

  void _addKind() {
    final vnC = TextEditingController(); final nnC = TextEditingController(); final gebC = TextEditingController(); final gruppeC = TextEditingController(); final eintrittC = TextEditingController(); final notizC = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Row(children: [Icon(Icons.child_care, size: 18, color: Colors.pink.shade700), const SizedBox(width: 8), const Text('Kind hinzufügen', style: TextStyle(fontSize: 14))]),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [Expanded(child: _tf('Vorname', vnC, Icons.person)), const SizedBox(width: 8), Expanded(child: _tf('Nachname', nnC, Icons.person_outline))]),
        const SizedBox(height: 10), _df('Geburtsdatum', gebC, ctx),
        const SizedBox(height: 10), _tf('Gruppe', gruppeC, Icons.group),
        const SizedBox(height: 10), _df('Eintritt', eintrittC, ctx),
        const SizedBox(height: 10), _tf('Notiz', notizC, Icons.notes, maxLines: 2),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          await widget.apiService.saveKindergartenKind(widget.userId, {'vorname': vnC.text.trim(), 'nachname': nnC.text.trim(), 'geburtsdatum': gebC.text.trim(), 'gruppe': gruppeC.text.trim(), 'eintritt': eintrittC.text.trim(), 'notiz': notizC.text.trim()});
          if (ctx.mounted) Navigator.pop(ctx); _load();
        }, child: const Text('Speichern')),
      ],
    ));
  }

  void _showKindDetail(Map<String, dynamic> k) {
    final kid = k['id'] is int ? k['id'] as int : int.parse(k['id'].toString());
    showDialog(context: context, builder: (ctx) => Dialog(
      child: SizedBox(width: 600, height: 550, child: _KindDetail(apiService: widget.apiService, userId: widget.userId, kindId: kid, kind: k, onChanged: _load, kindergartenName: _v('name')))));
  }

  Widget _tf(String label, TextEditingController c, IconData icon, {int maxLines = 1}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)), const SizedBox(height: 4),
    TextField(controller: c, maxLines: maxLines, decoration: InputDecoration(hintText: label, prefixIcon: Icon(icon, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)), style: const TextStyle(fontSize: 13))]);

  Widget _df(String label, TextEditingController c, BuildContext ctx) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)), const SizedBox(height: 4),
    TextField(controller: c, readOnly: true, decoration: InputDecoration(hintText: 'TT.MM.JJJJ', prefixIcon: const Icon(Icons.calendar_today, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
      onTap: () async { final p = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (p != null) c.text = '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}'; })]);
}

class _KindDetail extends StatefulWidget {
  final ApiService apiService;
  final int userId, kindId;
  final Map<String, dynamic> kind;
  final String kindergartenName;
  final VoidCallback onChanged;
  const _KindDetail({required this.apiService, required this.userId, required this.kindId, required this.kind, required this.onChanged, this.kindergartenName = ''});
  @override
  State<_KindDetail> createState() => _KindDetailState();
}

class _KindDetailState extends State<_KindDetail> {
  List<Map<String, dynamic>> _termine = [], _korr = [], _notizen = [];
  bool _loaded = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final res = await widget.apiService.getKindergartenKindDetail(widget.userId, widget.kindId);
      if (res['success'] == true && mounted) {
        _termine = (res['termine'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _korr = (res['korrespondenz'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _notizen = (res['notizen'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.kind;
    return DefaultTabController(length: 4, child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 8, 0), child: Row(children: [
        Icon(Icons.child_care, size: 18, color: Colors.pink.shade700), const SizedBox(width: 8),
        Expanded(child: Text('${k['vorname'] ?? ''} ${k['nachname'] ?? ''}'.trim(), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.pink.shade800))),
        IconButton(icon: Icon(Icons.edit, size: 16, color: Colors.pink.shade400), tooltip: 'Bearbeiten', onPressed: () => _editKind()),
        IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.pop(context)),
      ])),
      TabBar(labelColor: Colors.pink.shade700, unselectedLabelColor: Colors.grey.shade500, indicatorColor: Colors.pink.shade700, isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
        const Tab(icon: Icon(Icons.info_outline, size: 16), text: 'Details'),
        Tab(icon: const Icon(Icons.email, size: 16), text: 'Korrespondenz (${_korr.length})'),
        Tab(icon: const Icon(Icons.event, size: 16), text: 'Termine (${_termine.length})'),
        Tab(icon: const Icon(Icons.notes, size: 16), text: 'Notizen (${_notizen.length})'),
      ]),
      Expanded(child: !_loaded ? const Center(child: CircularProgressIndicator()) : TabBarView(children: [
        _buildDetails(),
        _buildKorr(),
        _buildTermine(),
        _buildNotizen(),
      ])),
    ]));
  }

  Widget _buildNotizen() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Icon(Icons.notes, size: 18, color: Colors.pink.shade700), const SizedBox(width: 8),
        Text('${_notizen.length} Notizen', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const Spacer(),
        FilledButton.icon(icon: const Icon(Icons.add, size: 14), label: const Text('Neue Notiz', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.pink.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: _addNotiz),
      ])),
      Expanded(child: _notizen.isEmpty ? Center(child: Text('Keine Notizen', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _notizen.length, itemBuilder: (_, i) {
            final n = _notizen[i];
            return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade200)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.sticky_note_2, size: 18, color: Colors.amber.shade700), const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if ((n['datum']?.toString() ?? '').isNotEmpty) Text(n['datum'].toString(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber.shade800)),
                  const SizedBox(height: 4),
                  Text(n['text']?.toString() ?? '', style: const TextStyle(fontSize: 13)),
                ])),
                IconButton(icon: Icon(Icons.delete_outline, size: 14, color: Colors.red.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: () async { await widget.apiService.deleteKindergartenNotiz(widget.userId, n['id'] is int ? n['id'] : int.parse(n['id'].toString())); _load(); }),
              ]));
          })),
    ]);
  }

  void _addNotiz() {
    final textC = TextEditingController();
    final now = DateTime.now();
    final datumStr = '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Row(children: [Icon(Icons.sticky_note_2, size: 18, color: Colors.amber.shade700), const SizedBox(width: 8), const Text('Neue Notiz', style: TextStyle(fontSize: 14))]),
      content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
          child: Row(children: [Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade600), const SizedBox(width: 6), Text(datumStr, style: TextStyle(fontSize: 12, color: Colors.grey.shade700))])),
        const SizedBox(height: 12),
        TextField(controller: textC, maxLines: 5, autofocus: true, decoration: InputDecoration(hintText: 'Notiz schreiben...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.all(12)), style: const TextStyle(fontSize: 13)),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          if (textC.text.trim().isEmpty) return;
          Navigator.pop(ctx);
          await widget.apiService.saveKindergartenNotiz(widget.userId, widget.kindId, {'datum': datumStr, 'text': textC.text.trim()});
          await _load();
        }, child: const Text('Speichern')),
      ],
    ));
  }

  void _editKind() {
    final k = widget.kind;
    final vnC = TextEditingController(text: k['vorname']?.toString() ?? '');
    final nnC = TextEditingController(text: k['nachname']?.toString() ?? '');
    final gebC = TextEditingController(text: k['geburtsdatum']?.toString() ?? '');
    final gruppeC = TextEditingController(text: k['gruppe']?.toString() ?? '');
    final eintrittC = TextEditingController(text: k['eintritt']?.toString() ?? '');
    final austrittC = TextEditingController(text: k['austritt']?.toString() ?? '');
    final notizC = TextEditingController(text: k['notiz']?.toString() ?? '');
    String status = k['status']?.toString() ?? 'aktiv';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) => AlertDialog(
      title: Row(children: [Icon(Icons.edit, size: 18, color: Colors.pink.shade700), const SizedBox(width: 8), const Text('Kind bearbeiten', style: TextStyle(fontSize: 14))]),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: TextField(controller: vnC, decoration: InputDecoration(labelText: 'Vorname', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: nnC, decoration: InputDecoration(labelText: 'Nachname', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
        ]),
        const SizedBox(height: 10),
        TextFormField(controller: gebC, readOnly: true, decoration: InputDecoration(labelText: 'Geburtsdatum', prefixIcon: const Icon(Icons.cake, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async { final p = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (p != null) gebC.text = '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}'; }))),
        const SizedBox(height: 10),
        TextField(controller: gruppeC, decoration: InputDecoration(labelText: 'Gruppe', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextFormField(controller: eintrittC, readOnly: true, decoration: InputDecoration(labelText: 'Eintritt', prefixIcon: const Icon(Icons.login, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async { final p = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (p != null) eintrittC.text = '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}'; })))),
          const SizedBox(width: 8),
          Expanded(child: TextFormField(controller: austrittC, readOnly: true, decoration: InputDecoration(labelText: 'Austritt', prefixIcon: const Icon(Icons.logout, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async { final p = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (p != null) austrittC.text = '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}'; })))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          ChoiceChip(label: const Text('Aktiv', style: TextStyle(fontSize: 12)), selected: status == 'aktiv', selectedColor: Colors.green.shade100, onSelected: (_) => setDlg(() => status = 'aktiv')),
          const SizedBox(width: 8),
          ChoiceChip(label: const Text('Ausgetreten', style: TextStyle(fontSize: 12)), selected: status == 'ausgetreten', selectedColor: Colors.grey.shade300, onSelected: (_) => setDlg(() => status = 'ausgetreten')),
        ]),
        const SizedBox(height: 10),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          k['vorname'] = vnC.text.trim(); k['nachname'] = nnC.text.trim(); k['geburtsdatum'] = gebC.text.trim();
          k['gruppe'] = gruppeC.text.trim(); k['eintritt'] = eintrittC.text.trim(); k['austritt'] = austrittC.text.trim();
          k['status'] = status; k['notiz'] = notizC.text.trim();
          await widget.apiService.saveKindergartenKind(widget.userId, k);
          widget.onChanged(); if (ctx.mounted) Navigator.pop(ctx); setState(() {});
        }, child: const Text('Speichern')),
      ],
    )));
  }

  Widget _buildDetails() {
    final k = widget.kind;
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _row(Icons.person, 'Vorname', k['vorname']),
      _row(Icons.person_outline, 'Nachname', k['nachname']),
      _row(Icons.cake, 'Geburtsdatum', k['geburtsdatum']),
      _row(Icons.group, 'Gruppe', k['gruppe']),
      _row(Icons.login, 'Eintritt', k['eintritt']),
      _row(Icons.logout, 'Austritt', k['austritt']),
      _row(Icons.flag, 'Status', k['status']),
      if ((k['notiz']?.toString() ?? '').isNotEmpty) ...[const SizedBox(height: 10),
        Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
          child: Text(k['notiz'].toString(), style: const TextStyle(fontSize: 12)))],
    ]));
  }

  Widget _row(IconData icon, String label, dynamic value) {
    final v = value?.toString() ?? '';
    if (v.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [
      Icon(icon, size: 14, color: Colors.pink.shade600), const SizedBox(width: 8),
      Text('$label: ', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      Expanded(child: Text(v, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
    ]));
  }

  Widget _buildKorr() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [const Spacer(),
        FilledButton.icon(icon: const Icon(Icons.call_received, size: 14), label: const Text('Eingang', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.green.shade600, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _addKorr('eingang')),
        const SizedBox(width: 6),
        FilledButton.icon(icon: const Icon(Icons.call_made, size: 14), label: const Text('Ausgang', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade600, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _addKorr('ausgang')),
      ])),
      Expanded(child: _korr.isEmpty ? Center(child: Text('Keine Korrespondenz', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _korr.length, itemBuilder: (_, i) {
            final k = _korr[i]; final isEin = k['richtung'] == 'eingang'; final c = isEin ? Colors.green : Colors.blue;
            const mL = {'email': 'E-Mail', 'post': 'Post', 'online': 'Online', 'persoenlich': 'Persönlich', 'fax': 'Fax'};
            final kId = k['id'] is int ? k['id'] as int : int.parse(k['id'].toString());
            return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: c.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: c.shade200)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(isEin ? Icons.call_received : Icons.call_made, size: 14, color: c.shade700), const SizedBox(width: 6),
                  Expanded(child: Text(k['betreff']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c.shade800))),
                  if ((k['methode']?.toString() ?? '').isNotEmpty) Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: c.shade100, borderRadius: BorderRadius.circular(4)),
                    child: Text(mL[k['methode']] ?? k['methode'].toString(), style: TextStyle(fontSize: 9, color: c.shade700))),
                  const SizedBox(width: 4),
                  IconButton(icon: Icon(Icons.delete_outline, size: 14, color: Colors.red.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: () async { await widget.apiService.deleteKindergartenKorr(widget.userId, kId); _load(); }),
                ]),
                if ((k['datum']?.toString() ?? '').isNotEmpty) Text(k['datum'].toString(), style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                Padding(padding: const EdgeInsets.only(top: 4), child: KorrAttachmentsWidget(apiService: widget.apiService, modul: 'kindergarten', korrespondenzId: kId)),
              ]));
          })),
    ]);
  }

  void _addKorr(String richtung) {
    final datumC = TextEditingController(); final betreffC = TextEditingController(); final notizC = TextEditingController();
    String methode = richtung == 'eingang' ? 'post' : 'email';
    List<PlatformFile> files = [];
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) => AlertDialog(
      title: Row(children: [Icon(richtung == 'eingang' ? Icons.call_received : Icons.call_made, size: 18, color: richtung == 'eingang' ? Colors.green.shade700 : Colors.blue.shade700), const SizedBox(width: 8), Text(richtung == 'eingang' ? 'Eingang' : 'Ausgang', style: const TextStyle(fontSize: 14))]),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Wrap(spacing: 6, runSpacing: 4, children: [for (final m in [('email', 'E-Mail', Icons.email), ('post', 'Post', Icons.mail), ('online', 'Online', Icons.language), ('persoenlich', 'Persönlich', Icons.person), ('fax', 'Fax', Icons.fax)])
          ChoiceChip(label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(m.$3, size: 13, color: methode == m.$1 ? Colors.white : Colors.grey.shade700), const SizedBox(width: 4), Text(m.$2, style: TextStyle(fontSize: 10, color: methode == m.$1 ? Colors.white : Colors.grey.shade700))]),
            selected: methode == m.$1, selectedColor: Colors.indigo.shade600, onSelected: (_) => setDlg(() => methode = m.$1))]),
        const SizedBox(height: 12),
        TextFormField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', prefixIcon: const Icon(Icons.calendar_today, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async { final p = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de')); if (p != null) setDlg(() => datumC.text = '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}'); }))),
        const SizedBox(height: 8),
        TextField(controller: betreffC, decoration: InputDecoration(labelText: 'Betreff *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 12),
        OutlinedButton.icon(icon: Icon(Icons.attach_file, size: 16, color: Colors.teal.shade600),
          label: Text(files.isEmpty ? 'Dokumente anhängen' : '${files.length} Datei(en)', style: TextStyle(fontSize: 12, color: Colors.teal.shade700)),
          style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.teal.shade300)),
          onPressed: () async { final r = await FilePickerHelper.pickFiles(allowMultiple: true, type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']); if (r != null) setDlg(() { files.addAll(r.files); if (files.length > 20) files = files.sublist(0, 20); }); }),
        if (files.isNotEmpty) ...files.asMap().entries.map((e) => Padding(padding: const EdgeInsets.only(top: 3), child: Row(children: [
          Icon(Icons.description, size: 13, color: Colors.grey.shade500), const SizedBox(width: 6),
          Expanded(child: Text(e.value.name, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
          IconButton(icon: Icon(Icons.close, size: 14, color: Colors.red.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24), onPressed: () => setDlg(() => files.removeAt(e.key))),
        ]))),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          if (betreffC.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Betreff angeben'), backgroundColor: Colors.orange)); return; }
          final res = await widget.apiService.saveKindergartenKorr(widget.userId, widget.kindId, {'richtung': richtung, 'methode': methode, 'datum': datumC.text.trim(), 'betreff': betreffC.text.trim(), 'notiz': notizC.text.trim()});
          final korrId = res['id'];
          if (korrId != null && files.isNotEmpty) { for (final f in files) { if (f.path == null) continue; await widget.apiService.uploadKorrAttachment(modul: 'kindergarten', korrespondenzId: korrId is int ? korrId : int.parse(korrId.toString()), filePath: f.path!, fileName: f.name); } }
          if (ctx.mounted) Navigator.pop(ctx); _load();
        }, child: const Text('Speichern')),
      ],
    )));
  }

  Widget _buildTermine() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [const Spacer(),
        FilledButton.icon(icon: const Icon(Icons.add, size: 14), label: const Text('Neuer Termin', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.pink.shade600, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero),
          onPressed: _addTermin),
      ])),
      Expanded(child: _termine.isEmpty ? Center(child: Text('Keine Termine', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _termine.length, itemBuilder: (_, i) {
            final t = _termine[i];
            return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.purple.shade200)),
              child: Row(children: [
                Icon(Icons.event, size: 16, color: Colors.purple.shade700), const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${t['datum'] ?? ''} ${t['uhrzeit'] ?? ''}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.purple.shade800)),
                  if ((t['typ']?.toString() ?? '').isNotEmpty) Text(t['typ'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  if ((t['notiz']?.toString() ?? '').isNotEmpty) Text(t['notiz'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                ])),
                IconButton(icon: Icon(Icons.delete_outline, size: 14, color: Colors.red.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: () async { await widget.apiService.deleteKindergartenTermin(widget.userId, t['id'] is int ? t['id'] : int.parse(t['id'].toString())); _load(); }),
              ]));
          })),
    ]);
  }

  void _addTermin() {
    final datumC = TextEditingController(); final uhrzeitC = TextEditingController(); final typC = TextEditingController(); final notizC = TextEditingController();
    DateTime? pickedDate;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Neuer Termin', style: TextStyle(fontSize: 14)),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', prefixIcon: const Icon(Icons.calendar_today, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async { final p = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de')); if (p != null) { pickedDate = p; datumC.text = '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}'; } }))),
        const SizedBox(height: 8),
        TextField(controller: uhrzeitC, decoration: InputDecoration(labelText: 'Uhrzeit (z.B. 09:00)', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 8),
        TextField(controller: typC, decoration: InputDecoration(labelText: 'Typ (z.B. Elternabend, Eingewöhnung)', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          await widget.apiService.saveKindergartenTermin(widget.userId, widget.kindId, {'datum': datumC.text.trim(), 'uhrzeit': uhrzeitC.text.trim(), 'typ': typC.text.trim(), 'notiz': notizC.text.trim()});
          if (pickedDate != null) {
            final kindName = '${widget.kind['vorname'] ?? ''} ${widget.kind['nachname'] ?? ''}'.trim();
            final kigaName = widget.kindergartenName;
            int hour = 9, minute = 0;
            final timeParts = uhrzeitC.text.trim().split(':');
            if (timeParts.length == 2) { hour = int.tryParse(timeParts[0]) ?? 9; minute = int.tryParse(timeParts[1]) ?? 0; }
            final terminDateTime = DateTime(pickedDate!.year, pickedDate!.month, pickedDate!.day, hour, minute);
            try {
              await TerminService().createTermin(
                title: '${typC.text.trim().isNotEmpty ? typC.text.trim() : "Kindergarten"} — $kindName',
                category: 'kindergarten',
                description: '${typC.text.trim()}\n$kindName\n${kigaName.isNotEmpty ? kigaName : "Kindergarten"}\n${notizC.text.trim()}',
                terminDate: terminDateTime,
                durationMinutes: 60,
                location: kigaName,
                participantIds: [widget.userId],
              );
            } catch (_) {}
          }
          if (ctx.mounted) Navigator.pop(ctx); _load();
        }, child: const Text('Speichern')),
      ],
    ));
  }
}
