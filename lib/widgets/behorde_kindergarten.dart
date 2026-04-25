import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
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

  Widget _buildKigaTab() {
    final nameC = TextEditingController(text: _v('name'));
    final adresseC = TextEditingController(text: _v('adresse'));
    final telefonC = TextEditingController(text: _v('telefon'));
    final emailC = TextEditingController(text: _v('email'));
    final leiterinC = TextEditingController(text: _v('leiterin'));
    final oeffnungsC = TextEditingController(text: _v('oeffnungszeiten'));
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(Icons.child_care, size: 20, color: Colors.pink.shade700), const SizedBox(width: 8), Text('Kindergarten', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.pink.shade700))]),
      const SizedBox(height: 12),
      _tf('Name', nameC, Icons.child_care), const SizedBox(height: 10),
      _tf('Adresse', adresseC, Icons.location_on), const SizedBox(height: 10),
      Row(children: [Expanded(child: _tf('Telefon', telefonC, Icons.phone)), const SizedBox(width: 8), Expanded(child: _tf('E-Mail', emailC, Icons.email))]),
      const SizedBox(height: 10),
      _tf('Leitung', leiterinC, Icons.person), const SizedBox(height: 10),
      _tf('Öffnungszeiten', oeffnungsC, Icons.schedule, maxLines: 2),
      const SizedBox(height: 16),
      Align(alignment: Alignment.centerRight, child: ElevatedButton.icon(
        onPressed: _saving ? null : () async {
          setState(() => _saving = true);
          final m = <String, dynamic>{}; for (final e in {'name': nameC, 'adresse': adresseC, 'telefon': telefonC, 'email': emailC, 'leiterin': leiterinC, 'oeffnungszeiten': oeffnungsC}.entries) { m['stammdaten.${e.key}'] = e.value.text.trim(); _data[e.key] = e.value.text.trim(); }
          await widget.apiService.saveKindergartenData(widget.userId, m);
          if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gespeichert'), backgroundColor: Colors.green)); setState(() => _saving = false); }
        },
        icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 18),
        label: const Text('Speichern'), style: ElevatedButton.styleFrom(backgroundColor: Colors.pink, foregroundColor: Colors.white))),
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
      child: SizedBox(width: 600, height: 550, child: _KindDetail(apiService: widget.apiService, userId: widget.userId, kindId: kid, kind: k, onChanged: _load))));
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
  final VoidCallback onChanged;
  const _KindDetail({required this.apiService, required this.userId, required this.kindId, required this.kind, required this.onChanged});
  @override
  State<_KindDetail> createState() => _KindDetailState();
}

class _KindDetailState extends State<_KindDetail> {
  List<Map<String, dynamic>> _termine = [], _korr = [];
  bool _loaded = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final res = await widget.apiService.getKindergartenKindDetail(widget.userId, widget.kindId);
      if (res['success'] == true && mounted) {
        _termine = (res['termine'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _korr = (res['korrespondenz'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.kind;
    return DefaultTabController(length: 3, child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 8, 0), child: Row(children: [
        Icon(Icons.child_care, size: 18, color: Colors.pink.shade700), const SizedBox(width: 8),
        Expanded(child: Text('${k['vorname'] ?? ''} ${k['nachname'] ?? ''}'.trim(), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.pink.shade800))),
        IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.pop(context)),
      ])),
      TabBar(labelColor: Colors.pink.shade700, unselectedLabelColor: Colors.grey.shade500, indicatorColor: Colors.pink.shade700, tabs: [
        const Tab(icon: Icon(Icons.info_outline, size: 16), text: 'Details'),
        Tab(icon: const Icon(Icons.email, size: 16), text: 'Korrespondenz (${_korr.length})'),
        Tab(icon: const Icon(Icons.event, size: 16), text: 'Termine (${_termine.length})'),
      ]),
      Expanded(child: !_loaded ? const Center(child: CircularProgressIndicator()) : TabBarView(children: [
        _buildDetails(),
        _buildKorr(),
        _buildTermine(),
      ])),
    ]));
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
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Neuer Termin', style: TextStyle(fontSize: 14)),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', prefixIcon: const Icon(Icons.calendar_today, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async { final p = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de')); if (p != null) datumC.text = '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}'; }))),
        const SizedBox(height: 8),
        TextField(controller: uhrzeitC, decoration: InputDecoration(labelText: 'Uhrzeit', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 8),
        TextField(controller: typC, decoration: InputDecoration(labelText: 'Typ (z.B. Elternabend, Eingewöhnung)', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          await widget.apiService.saveKindergartenTermin(widget.userId, widget.kindId, {'datum': datumC.text.trim(), 'uhrzeit': uhrzeitC.text.trim(), 'typ': typC.text.trim(), 'notiz': notizC.text.trim()});
          if (ctx.mounted) Navigator.pop(ctx); _load();
        }, child: const Text('Speichern')),
      ],
    ));
  }
}
