import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';
import 'korrespondenz_attachments_widget.dart';

class BehordeKonsulatContent extends StatefulWidget {
  final ApiService apiService;
  final int userId;

  const BehordeKonsulatContent({super.key, required this.apiService, required this.userId});
  @override
  State<BehordeKonsulatContent> createState() => _State();
}

class _State extends State<BehordeKonsulatContent> with TickerProviderStateMixin {
  late final TabController _tabCtrl;
  bool _loaded = false, _loading = false, _saving = false;
  Map<String, dynamic> _data = {};
  List<Map<String, dynamic>> _vorfaelle = [];

  static const _konsulate = [
    {'name': 'Generalkonsulat von Rumänien — Stuttgart', 'adresse': 'Hauptstätter Straße 70, 70178 Stuttgart', 'telefon': '0711 6648600', 'fax': '0711 6648622', 'email': 'stuttgart@mae.ro', 'website': 'https://stuttgart.mae.ro', 'oeffnungszeiten': 'Mo-Fr 09:00-15:00 (nur mit Termin)', 'konsul': 'Radu-Dumitru Florea'},
    {'name': 'Generalkonsulat von Rumänien — München', 'adresse': 'Richard-Strauss-Straße 149, 81679 München', 'telefon': '089 5529953', 'email': 'munchen@mae.ro', 'website': 'https://munchen.mae.ro', 'oeffnungszeiten': 'Mo-Fr 09:00-17:00 (nur mit Termin)'},
    {'name': 'Botschaft von Rumänien — Berlin', 'adresse': 'Dorotheenstraße 62-66, 10117 Berlin', 'telefon': '030 21239202', 'email': 'berlin@mae.ro', 'website': 'https://berlin.mae.ro', 'oeffnungszeiten': 'Mo-Fr 09:00-17:00'},
  ];

  static const _vorfallTypen = [
    'Reisepass beantragen / verlängern',
    'Personalausweis (Carte de Identitate)',
    'Geburtsurkunde beantragen',
    'Heiratsurkunde beantragen',
    'Sterbeurkunde beantragen',
    'Vollmacht (Procura)',
    'Notarielle Beglaubigung',
    'Apostille',
    'Führungszeugnis (Cazier judiciar)',
    'Staatsbürgerschaft',
    'Rentenunterlagen Rumänien',
    'Militärstatus',
    'Legalisierung von Dokumenten',
    'Konsularische Hilfe / Beistand',
    'Sonstiges',
  ];

  @override
  void initState() { super.initState(); _tabCtrl = TabController(length: 3, vsync: this); _load(); }
  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  String _v(String f) => _data[f]?.toString() ?? '';

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final res = await widget.apiService.getKonsulatData(widget.userId);
      if (res['success'] == true && mounted) {
        final raw = res['data'];
        if (raw is Map) { _data = {}; for (final e in raw.entries) { final p = e.key.toString().split('.'); _data[p.length == 2 ? p[1] : e.key.toString()] = e.value; } }
        _vorfaelle = (res['vorfaelle'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    if (mounted) setState(() { _loading = false; _loaded = true; });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded && !_loading) _load();
    if (_loading || !_loaded) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      TabBar(controller: _tabCtrl, labelColor: Colors.indigo.shade700, unselectedLabelColor: Colors.grey.shade500, indicatorColor: Colors.indigo.shade700,
        tabs: const [Tab(icon: Icon(Icons.account_balance, size: 16), text: 'Zuständiges Konsulat'), Tab(icon: Icon(Icons.assignment, size: 16), text: 'Vorfall'), Tab(icon: Icon(Icons.cloud, size: 16), text: 'Online-Konto')]),
      Expanded(child: TabBarView(controller: _tabCtrl, children: [_buildKonsulatTab(), _buildVorfallTab(), _buildOnlineTab()])),
    ]);
  }

  // ──── TAB 1: Zuständiges Konsulat ────
  Widget _buildKonsulatTab() {
    final hasK = _v('name').isNotEmpty;
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.account_balance, size: 20, color: Colors.indigo.shade700), const SizedBox(width: 8),
        Text('Zuständiges Konsulat', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
        const Spacer(),
        FilledButton.icon(icon: const Icon(Icons.search, size: 16), label: Text(hasK ? 'Ändern' : 'Suchen', style: const TextStyle(fontSize: 12)),
          style: FilledButton.styleFrom(backgroundColor: Colors.indigo.shade600, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero),
          onPressed: () async {
            final selected = await showDialog<Map<String, String>>(context: context, builder: (sCtx) {
              return AlertDialog(
                title: Row(children: [Icon(Icons.account_balance, size: 18, color: Colors.indigo.shade700), const SizedBox(width: 8), const Text('Konsulat auswählen', style: TextStyle(fontSize: 14))]),
                content: SizedBox(width: 450, child: Column(mainAxisSize: MainAxisSize.min, children: _konsulate.map((k) =>
                  Container(margin: const EdgeInsets.only(bottom: 8), child: InkWell(borderRadius: BorderRadius.circular(8), onTap: () => Navigator.pop(sCtx, k),
                    child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.indigo.shade200)),
                      child: Row(children: [Icon(Icons.flag, size: 18, color: Colors.indigo.shade600), const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(k['name']!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
                          Text(k['adresse']!, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        ]))]))))).toList())),
                actions: [TextButton(onPressed: () => Navigator.pop(sCtx), child: const Text('Abbrechen'))],
              );
            });
            if (selected != null) {
              final m = <String, dynamic>{};
              for (final e in selected.entries) m['stammdaten.${e.key}'] = e.value;
              await widget.apiService.saveKonsulatData(widget.userId, m);
              for (final e in selected.entries) _data[e.key] = e.value;
              if (mounted) setState(() {});
            }
          }),
      ]),
      const SizedBox(height: 16),
      if (!hasK)
        Container(width: double.infinity, padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
          child: Column(children: [Icon(Icons.search, size: 48, color: Colors.grey.shade300), const SizedBox(height: 8), Text('Kein Konsulat ausgewählt', style: TextStyle(fontSize: 13, color: Colors.grey.shade500))]))
      else
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.indigo.shade200)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [CircleAvatar(radius: 22, backgroundColor: Colors.indigo.shade100, child: Icon(Icons.flag, size: 24, color: Colors.indigo.shade700)), const SizedBox(width: 12),
              Expanded(child: Text(_v('name'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.indigo.shade800))),
              IconButton(icon: Icon(Icons.close, size: 18, color: Colors.red.shade400), onPressed: () async {
                await widget.apiService.saveKonsulatData(widget.userId, {'stammdaten.name': ''}); _data.clear(); if (mounted) setState(() {}); }),
            ]),
            const Divider(height: 20),
            if (_v('adresse').isNotEmpty) _infoRow(Icons.location_on, _v('adresse'), Colors.indigo),
            if (_v('telefon').isNotEmpty) _infoRow(Icons.phone, _v('telefon'), Colors.blue),
            if (_v('email').isNotEmpty) _infoRow(Icons.email, _v('email'), Colors.teal),
            if (_v('oeffnungszeiten').isNotEmpty) _infoRow(Icons.schedule, _v('oeffnungszeiten'), Colors.orange),
            if (_v('konsul').isNotEmpty) _infoRow(Icons.person, 'Konsul: ${_v('konsul')}', Colors.purple),
          ])),
    ]));
  }

  Widget _infoRow(IconData icon, String text, MaterialColor c) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [
    Icon(icon, size: 16, color: c.shade600), const SizedBox(width: 10), Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: Colors.grey.shade800)))]));

  // ──── TAB 2: Vorfall ────
  Widget _buildVorfallTab() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Icon(Icons.assignment, size: 18, color: Colors.indigo.shade700), const SizedBox(width: 8),
        Text('${_vorfaelle.length} Vorfälle', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const Spacer(),
        FilledButton.icon(icon: const Icon(Icons.add, size: 16), label: const Text('Neuer Vorfall', style: TextStyle(fontSize: 12)),
          style: FilledButton.styleFrom(backgroundColor: Colors.indigo.shade600, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero),
          onPressed: _addVorfall),
      ])),
      Expanded(child: _vorfaelle.isEmpty
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.assignment_late, size: 48, color: Colors.grey.shade300), const SizedBox(height: 8), Text('Keine Vorfälle', style: TextStyle(fontSize: 12, color: Colors.grey.shade500))]))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _vorfaelle.length, itemBuilder: (_, i) {
            final v = _vorfaelle[i];
            final status = v['status']?.toString() ?? 'offen';
            final sc = status == 'erledigt' ? Colors.green : status == 'in_bearbeitung' ? Colors.orange : Colors.blue;
            return Container(margin: const EdgeInsets.only(bottom: 8), child: InkWell(borderRadius: BorderRadius.circular(8),
              onTap: () => _showVorfallDetail(v),
              child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.indigo.shade200)),
                child: Row(children: [
                  Icon(Icons.assignment, size: 18, color: Colors.indigo.shade700), const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(v['titel']?.toString() ?? v['typ']?.toString() ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade800))),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: sc.shade100, borderRadius: BorderRadius.circular(6)),
                        child: Text(status == 'erledigt' ? 'Erledigt' : status == 'in_bearbeitung' ? 'In Bearbeitung' : 'Offen', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: sc.shade800))),
                    ]),
                    if ((v['datum']?.toString() ?? '').isNotEmpty) Text(v['datum'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  ])),
                  IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: () async { await widget.apiService.deleteKonsulatVorfall(widget.userId, v['id'] is int ? v['id'] : int.parse(v['id'].toString())); _load(); }),
                ]))));
          })),
    ]);
  }

  void _addVorfall() {
    final datumC = TextEditingController(); final titelC = TextEditingController(); final notizC = TextEditingController();
    String typ = '';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) => AlertDialog(
      title: Row(children: [Icon(Icons.add_circle, size: 18, color: Colors.indigo.shade700), const SizedBox(width: 8), const Text('Neuer Vorfall', style: TextStyle(fontSize: 14))]),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(isExpanded: true, value: typ.isEmpty ? null : typ,
          decoration: InputDecoration(labelText: 'Dienstleistung', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          items: _vorfallTypen.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 13)))).toList(),
          onChanged: (v) => setDlg(() { typ = v ?? ''; if (titelC.text.isEmpty) titelC.text = typ; })),
        const SizedBox(height: 12),
        TextField(controller: titelC, decoration: InputDecoration(labelText: 'Titel', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 12),
        _df('Datum', datumC, ctx),
        const SizedBox(height: 12),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          await widget.apiService.saveKonsulatVorfall(widget.userId, {'typ': typ, 'titel': titelC.text.trim(), 'datum': datumC.text.trim(), 'notiz': notizC.text.trim()});
          if (ctx.mounted) Navigator.pop(ctx); _load();
        }, child: const Text('Speichern')),
      ],
    )));
  }

  void _showVorfallDetail(Map<String, dynamic> v) {
    final vid = v['id'] is int ? v['id'] as int : int.parse(v['id'].toString());
    showDialog(context: context, builder: (ctx) => Dialog(
      child: SizedBox(width: 600, height: 550, child: _KonsulatVorfallDetail(apiService: widget.apiService, userId: widget.userId, vorfallId: vid, vorfall: v, onChanged: _load))));
  }

  // ──── TAB 3: Online-Konto ────
  Widget _buildOnlineTab() {
    final emailC = TextEditingController(text: _v('online_email'));
    final passC = TextEditingController(text: _v('online_passwort_hint'));
    bool hasAccount = _v('has_online_account') == 'true';
    return StatefulBuilder(builder: (ctx, setLocal) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.cloud, size: 18, color: Colors.blue.shade700), const SizedBox(width: 8), Text('Online-Konto (eConsulat)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue.shade700)), const Spacer(), Switch(value: hasAccount, onChanged: (v) => setLocal(() => hasAccount = v), activeThumbColor: Colors.blue)]),
          if (hasAccount) ...[
            const SizedBox(height: 12),
            _tf('E-Mail', emailC, Icons.email),
            const SizedBox(height: 10),
            _tf('Passwort-Hinweis', passC, Icons.key),
          ],
        ])),
      const SizedBox(height: 16),
      Align(alignment: Alignment.centerRight, child: ElevatedButton.icon(
        onPressed: _saving ? null : () async {
          setState(() => _saving = true);
          await widget.apiService.saveKonsulatData(widget.userId, {'online.has_online_account': hasAccount.toString(), 'online.online_email': emailC.text.trim(), 'online.online_passwort_hint': passC.text.trim()});
          _data['has_online_account'] = hasAccount.toString(); _data['online_email'] = emailC.text.trim(); _data['online_passwort_hint'] = passC.text.trim();
          if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gespeichert'), backgroundColor: Colors.green)); setState(() => _saving = false); }
        },
        icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 18),
        label: const Text('Speichern'), style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white))),
    ])));
  }

  Widget _tf(String label, TextEditingController c, IconData icon, {int maxLines = 1}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)), const SizedBox(height: 4),
    TextField(controller: c, maxLines: maxLines, decoration: InputDecoration(hintText: label, prefixIcon: Icon(icon, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)), style: const TextStyle(fontSize: 13))]);

  Widget _df(String label, TextEditingController c, BuildContext ctx) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)), const SizedBox(height: 4),
    TextField(controller: c, readOnly: true, decoration: InputDecoration(hintText: 'TT.MM.JJJJ', prefixIcon: const Icon(Icons.calendar_today, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
      onTap: () async { final p = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (p != null) c.text = '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}'; })]);
}

// ═══════════════════════════════════════════════════════
// VORFALL DETAIL (Details / Korrespondenz / Termine)
// ═══════════════════════════════════════════════════════
class _KonsulatVorfallDetail extends StatefulWidget {
  final ApiService apiService;
  final int userId, vorfallId;
  final Map<String, dynamic> vorfall;
  final VoidCallback onChanged;
  const _KonsulatVorfallDetail({required this.apiService, required this.userId, required this.vorfallId, required this.vorfall, required this.onChanged});
  @override
  State<_KonsulatVorfallDetail> createState() => _KonsulatVorfallDetailState();
}

class _KonsulatVorfallDetailState extends State<_KonsulatVorfallDetail> {
  List<Map<String, dynamic>> _termine = [], _korr = [];
  bool _loaded = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final res = await widget.apiService.getKonsulatVorfallDetail(widget.userId, widget.vorfallId);
      if (res['success'] == true && mounted) {
        _termine = (res['termine'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _korr = (res['korrespondenz'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vorfall;
    final status = v['status']?.toString() ?? 'offen';
    final sc = status == 'erledigt' ? Colors.green : status == 'in_bearbeitung' ? Colors.orange : Colors.blue;
    return DefaultTabController(length: 3, child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 8, 0), child: Row(children: [
        Icon(Icons.assignment, size: 18, color: Colors.indigo.shade700), const SizedBox(width: 8),
        Expanded(child: Text(v['titel']?.toString() ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo.shade800), overflow: TextOverflow.ellipsis)),
        Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: sc.shade100, borderRadius: BorderRadius.circular(6)),
          child: Text(status == 'erledigt' ? 'Erledigt' : status == 'in_bearbeitung' ? 'In Bearbeitung' : 'Offen', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: sc.shade800))),
        PopupMenuButton<String>(icon: const Icon(Icons.more_vert, size: 18), itemBuilder: (_) => [
          const PopupMenuItem(value: 'offen', child: Text('Offen', style: TextStyle(fontSize: 12))),
          const PopupMenuItem(value: 'in_bearbeitung', child: Text('In Bearbeitung', style: TextStyle(fontSize: 12))),
          const PopupMenuItem(value: 'erledigt', child: Text('Erledigt', style: TextStyle(fontSize: 12))),
        ], onSelected: (s) async {
          await widget.apiService.saveKonsulatVorfall(widget.userId, {...v, 'status': s});
          v['status'] = s; widget.onChanged(); setState(() {});
        }),
        IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.pop(context)),
      ])),
      TabBar(labelColor: Colors.indigo.shade700, unselectedLabelColor: Colors.grey.shade500, indicatorColor: Colors.indigo.shade700, tabs: [
        const Tab(icon: Icon(Icons.info_outline, size: 16), text: 'Details'),
        Tab(icon: const Icon(Icons.email, size: 16), text: 'Korrespondenz (${_korr.length})'),
        Tab(icon: const Icon(Icons.event, size: 16), text: 'Termine (${_termine.length})'),
      ]),
      Expanded(child: !_loaded ? const Center(child: CircularProgressIndicator()) : TabBarView(children: [
        _buildDetails(v),
        _buildKorr(),
        _buildTermine(),
      ])),
    ]));
  }

  Widget _buildDetails(Map<String, dynamic> v) {
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _row(Icons.category, 'Typ', v['typ']), _row(Icons.title, 'Titel', v['titel']), _row(Icons.calendar_today, 'Datum', v['datum']),
      _row(Icons.folder, 'Aktenzeichen', v['aktenzeichen']), _row(Icons.flag, 'Status', v['status']),
      if ((v['notiz']?.toString() ?? '').isNotEmpty) ...[const SizedBox(height: 10),
        Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
          child: Text(v['notiz'].toString(), style: const TextStyle(fontSize: 12)))],
    ]));
  }

  Widget _row(IconData icon, String label, dynamic value) {
    final val = value?.toString() ?? ''; if (val.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [
      Icon(icon, size: 14, color: Colors.indigo.shade600), const SizedBox(width: 8),
      Text('$label: ', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      Expanded(child: Text(val, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)))]));
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
                Row(children: [Icon(isEin ? Icons.call_received : Icons.call_made, size: 14, color: c.shade700), const SizedBox(width: 6),
                  Expanded(child: Text(k['betreff']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c.shade800))),
                  if ((k['methode']?.toString() ?? '').isNotEmpty) Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: c.shade100, borderRadius: BorderRadius.circular(4)),
                    child: Text(mL[k['methode']] ?? k['methode'].toString(), style: TextStyle(fontSize: 9, color: c.shade700))),
                  const SizedBox(width: 4),
                  IconButton(icon: Icon(Icons.delete_outline, size: 14, color: Colors.red.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: () async { await widget.apiService.deleteKonsulatKorr(widget.userId, kId); _load(); }),
                ]),
                if ((k['datum']?.toString() ?? '').isNotEmpty) Text(k['datum'].toString(), style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                Padding(padding: const EdgeInsets.only(top: 4), child: KorrAttachmentsWidget(apiService: widget.apiService, modul: 'konsulat', korrespondenzId: kId)),
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
          final res = await widget.apiService.saveKonsulatKorr(widget.userId, widget.vorfallId, {'richtung': richtung, 'methode': methode, 'datum': datumC.text.trim(), 'betreff': betreffC.text.trim(), 'notiz': notizC.text.trim()});
          final korrId = res['id'];
          if (korrId != null && files.isNotEmpty) { for (final f in files) { if (f.path == null) continue; await widget.apiService.uploadKorrAttachment(modul: 'konsulat', korrespondenzId: korrId is int ? korrId : int.parse(korrId.toString()), filePath: f.path!, fileName: f.name); } }
          if (ctx.mounted) Navigator.pop(ctx); _load();
        }, child: const Text('Speichern')),
      ],
    )));
  }

  Widget _buildTermine() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [const Spacer(),
        FilledButton.icon(icon: const Icon(Icons.add, size: 14), label: const Text('Neuer Termin', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.indigo.shade600, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero),
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
                  if ((t['ort']?.toString() ?? '').isNotEmpty) Text(t['ort'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  if ((t['notiz']?.toString() ?? '').isNotEmpty) Text(t['notiz'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                ])),
                IconButton(icon: Icon(Icons.delete_outline, size: 14, color: Colors.red.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: () async { await widget.apiService.deleteKonsulatTermin(widget.userId, t['id'] is int ? t['id'] : int.parse(t['id'].toString())); _load(); }),
              ]));
          })),
    ]);
  }

  void _addTermin() {
    final datumC = TextEditingController(); final uhrzeitC = TextEditingController(); final ortC = TextEditingController(); final notizC = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Neuer Termin', style: TextStyle(fontSize: 14)),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', prefixIcon: const Icon(Icons.calendar_today, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async { final p = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de')); if (p != null) datumC.text = '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}'; }))),
        const SizedBox(height: 8),
        TextField(controller: uhrzeitC, decoration: InputDecoration(labelText: 'Uhrzeit', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 8),
        TextField(controller: ortC, decoration: InputDecoration(labelText: 'Ort', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          await widget.apiService.saveKonsulatTermin(widget.userId, widget.vorfallId, {'datum': datumC.text.trim(), 'uhrzeit': uhrzeitC.text.trim(), 'ort': ortC.text.trim(), 'notiz': notizC.text.trim()});
          if (ctx.mounted) Navigator.pop(ctx); _load();
        }, child: const Text('Speichern')),
      ],
    ));
  }
}
