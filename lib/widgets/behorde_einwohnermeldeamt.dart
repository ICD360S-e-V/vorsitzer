import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';
import 'korrespondenz_attachments_widget.dart';

class BehordeEinwohnermeldeamtContent extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final Map<String, dynamic> Function(String type) getData;
  final bool Function(String type) isLoading;
  final bool Function(String type) isSaving;
  final void Function(String type) loadData;
  final void Function(String type, Map<String, dynamic> data) saveData;
  final Widget Function(String type, TextEditingController controller) dienststelleBuilder;

  const BehordeEinwohnermeldeamtContent({
    super.key,
    required this.apiService,
    required this.userId,
    required this.getData,
    required this.isLoading,
    required this.isSaving,
    required this.loadData,
    required this.saveData,
    required this.dienststelleBuilder,
  });

  @override
  State<BehordeEinwohnermeldeamtContent> createState() => _State();
}

class _State extends State<BehordeEinwohnermeldeamtContent> with TickerProviderStateMixin {
  late final TabController _tabCtrl;
  bool _loaded = false, _loading = false, _saving = false;
  Map<String, dynamic> _data = {};
  List<Map<String, dynamic>> _vorfaelle = [];

  static const _vorfallTypen = [
    'Anmeldung (Wohnsitz)',
    'Ummeldung (Wohnsitz)',
    'Abmeldung (Wohnsitz)',
    'Personalausweis beantragen',
    'Reisepass beantragen',
    'Kinderreisepass beantragen',
    'Meldebescheinigung',
    'Führungszeugnis',
    'Gewerbeanmeldung',
    'Beglaubigung',
    'Wohnungsgeberbestätigung',
    'Steuerliche Lebensbescheinigung',
    'Sonstiges',
  ];

  static const _buergeraemter = [
    {'name': 'Bürgerbüro Neu-Ulm', 'adresse': 'Petrusplatz 15, 89231 Neu-Ulm', 'telefon': '0731 7050-7340', 'fax': '0731 7050-7349', 'email': 'buergerbuero@neu-ulm.de', 'oeffnungszeiten': 'Mo-Di 08:00-17:00, Mi 08:00-13:00, Do 08:00-18:00, Fr 08:00-13:00, Sa 09:00-12:00'},
    {'name': 'Bürgerdienste Ulm', 'adresse': 'Olgastraße 66, 89073 Ulm', 'telefon': '0731 161-3322', 'fax': '0731 161-1615', 'oeffnungszeiten': 'Mo-Di 07:30-16:00, Mi 07:30-12:30, Do 07:30-17:30, Fr 07:30-12:30'},
    {'name': 'Bürgerbüro Senden', 'adresse': 'Hauptstraße 55, 89250 Senden', 'telefon': '07307 945-100', 'oeffnungszeiten': 'Mo-Fr 08:00-12:00, Do 14:00-18:00'},
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  String _v(String f) => _data[f]?.toString() ?? '';

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final res = await widget.apiService.getBuergeramtData(widget.userId);
      if (res['success'] == true && mounted) {
        final raw = res['data'];
        if (raw is Map) { _data = {}; for (final e in raw.entries) { final parts = e.key.toString().split('.'); _data[parts.length == 2 ? parts[1] : e.key.toString()] = e.value; } }
        _vorfaelle = (res['vorfaelle'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    if (mounted) setState(() { _loading = false; _loaded = true; });
  }

  Future<void> _saveFields(Map<String, dynamic> fields) async {
    setState(() => _saving = true);
    try {
      final mapped = <String, dynamic>{};
      for (final e in fields.entries) mapped['stammdaten.${e.key}'] = e.value?.toString() ?? '';
      await widget.apiService.saveBuergeramtData(widget.userId, mapped);
      for (final e in fields.entries) _data[e.key] = e.value;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gespeichert'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded && !_loading) _load();
    if (_loading || !_loaded) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      TabBar(controller: _tabCtrl, labelColor: Colors.teal.shade700, unselectedLabelColor: Colors.grey.shade500, indicatorColor: Colors.teal.shade700,
        tabs: const [Tab(icon: Icon(Icons.account_balance, size: 16), text: 'Zuständiges Bürgeramt'), Tab(icon: Icon(Icons.assignment, size: 16), text: 'Vorfall')]),
      Expanded(child: TabBarView(controller: _tabCtrl, children: [_buildAmtTab(), _buildVorfallTab()])),
    ]);
  }

  Widget _buildAmtTab() {
    final dienststelleC = TextEditingController(text: _v('dienststelle'));
    final anmeldedatumC = TextEditingController(text: _v('anmeldedatum'));
    final meldeadresseC = TextEditingController(text: _v('meldeadresse'));
    final nebenwohnsitzC = TextEditingController(text: _v('nebenwohnsitz'));
    final meldebeschNrC = TextEditingController(text: _v('meldebescheinigung_nr'));
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Bürgeramt auswählen', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
      const SizedBox(height: 8),
      ..._buergeraemter.map((b) => Container(margin: const EdgeInsets.only(bottom: 6), child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() { _data['dienststelle'] = b['name']; dienststelleC.text = b['name']!; }),
        child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: _v('dienststelle') == b['name'] ? Colors.teal.shade50 : Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: _v('dienststelle') == b['name'] ? Colors.teal.shade400 : Colors.grey.shade200, width: _v('dienststelle') == b['name'] ? 2 : 1)),
          child: Row(children: [
            Icon(Icons.account_balance, size: 18, color: _v('dienststelle') == b['name'] ? Colors.teal.shade700 : Colors.grey.shade500),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(b['name']!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _v('dienststelle') == b['name'] ? Colors.teal.shade800 : Colors.grey.shade800)),
              Text(b['adresse']!, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              if (b['telefon'] != null) Text('Tel: ${b['telefon']}', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
              if (b['oeffnungszeiten'] != null) Text(b['oeffnungszeiten']!, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            ])),
            if (_v('dienststelle') == b['name']) Icon(Icons.check_circle, size: 20, color: Colors.teal.shade600),
          ]))))),
      const SizedBox(height: 16),
      _dateField('Anmeldedatum', anmeldedatumC, context),
      const SizedBox(height: 12),
      _textField('Meldeadresse (Hauptwohnsitz)', meldeadresseC, hint: 'Straße Nr, PLZ Ort', icon: Icons.location_on, maxLines: 2),
      const SizedBox(height: 12),
      _textField('Nebenwohnsitz', nebenwohnsitzC, hint: 'Falls vorhanden', icon: Icons.home_work),
      const SizedBox(height: 12),
      _textField('Meldebescheinigung-Nr.', meldebeschNrC, hint: 'Nummer', icon: Icons.description),
      const SizedBox(height: 16),
      Align(alignment: Alignment.centerRight, child: ElevatedButton.icon(
        onPressed: _saving ? null : () => _saveFields({'dienststelle': dienststelleC.text.trim(), 'anmeldedatum': anmeldedatumC.text.trim(), 'meldeadresse': meldeadresseC.text.trim(), 'nebenwohnsitz': nebenwohnsitzC.text.trim(), 'meldebescheinigung_nr': meldebeschNrC.text.trim()}),
        icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 18),
        label: const Text('Speichern'), style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white))),
    ]));
  }

  Widget _buildVorfallTab() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Icon(Icons.assignment, size: 18, color: Colors.teal.shade700), const SizedBox(width: 8),
        Text('${_vorfaelle.length} Vorfälle', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const Spacer(),
        FilledButton.icon(icon: const Icon(Icons.add, size: 16), label: const Text('Neuer Vorfall', style: TextStyle(fontSize: 12)),
          style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade600, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero),
          onPressed: () => _showNewVorfallDialog()),
      ])),
      Expanded(child: _vorfaelle.isEmpty
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.assignment_late, size: 48, color: Colors.grey.shade300), const SizedBox(height: 8), Text('Keine Vorfälle', style: TextStyle(fontSize: 12, color: Colors.grey.shade500))]))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _vorfaelle.length, itemBuilder: (_, i) {
            final v = _vorfaelle[i];
            final status = v['status']?.toString() ?? 'offen';
            final sc = status == 'erledigt' ? Colors.green : status == 'in_bearbeitung' ? Colors.orange : Colors.blue;
            return Container(margin: const EdgeInsets.only(bottom: 8), child: InkWell(borderRadius: BorderRadius.circular(8),
              onTap: () => _showVorfallDetailDialog(v),
              child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.teal.shade200)),
                child: Row(children: [
                  Icon(Icons.assignment, size: 18, color: Colors.teal.shade700), const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(v['titel']?.toString() ?? v['typ']?.toString() ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.teal.shade800))),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: sc.shade100, borderRadius: BorderRadius.circular(6)),
                        child: Text(status == 'erledigt' ? 'Erledigt' : status == 'in_bearbeitung' ? 'In Bearbeitung' : 'Offen', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: sc.shade800))),
                    ]),
                    if ((v['datum']?.toString() ?? '').isNotEmpty) Text(v['datum'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    if ((v['typ']?.toString() ?? '').isNotEmpty && v['typ'] != v['titel']) Text(v['typ'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  ])),
                  const SizedBox(width: 4),
                  IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: () async { await widget.apiService.deleteBuergeramtVorfall(widget.userId, v['id'] is int ? v['id'] : int.parse(v['id'].toString())); await _load(); }),
                ]))));
          })),
    ]);
  }

  void _showNewVorfallDialog() {
    final datumC = TextEditingController();
    final titelC = TextEditingController();
    final notizC = TextEditingController();
    String typ = '';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) => AlertDialog(
      title: Row(children: [Icon(Icons.add_circle, size: 18, color: Colors.teal.shade700), const SizedBox(width: 8), const Text('Neuer Vorfall', style: TextStyle(fontSize: 14))]),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(isExpanded: true, value: typ.isEmpty ? null : typ,
          decoration: InputDecoration(labelText: 'Dienstleistung', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          items: _vorfallTypen.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 13)))).toList(),
          onChanged: (v) => setDlg(() { typ = v ?? ''; if (titelC.text.isEmpty) titelC.text = typ; })),
        const SizedBox(height: 12),
        TextField(controller: titelC, decoration: InputDecoration(labelText: 'Titel', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 12),
        _dateField('Datum', datumC, ctx),
        const SizedBox(height: 12),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          await widget.apiService.saveBuergeramtVorfall(widget.userId, {'typ': typ, 'titel': titelC.text.trim(), 'datum': datumC.text.trim(), 'notiz': notizC.text.trim()});
          if (ctx.mounted) Navigator.pop(ctx); await _load();
        }, child: const Text('Speichern')),
      ],
    )));
  }

  void _showVorfallDetailDialog(Map<String, dynamic> v) {
    final vid = v['id'] is int ? v['id'] as int : int.parse(v['id'].toString());
    showDialog(context: context, builder: (ctx) => Dialog(
      child: SizedBox(width: 600, height: 550, child: _BuergeramtVorfallDetail(apiService: widget.apiService, userId: widget.userId, vorfallId: vid, vorfall: v, onChanged: () { _load(); }))));
  }

  Widget _textField(String label, TextEditingController c, {String hint = '', IconData icon = Icons.edit, int maxLines = 1}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)), const SizedBox(height: 4),
      TextField(controller: c, maxLines: maxLines, decoration: InputDecoration(hintText: hint, prefixIcon: Icon(icon, size: 20), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)), style: const TextStyle(fontSize: 14)),
    ]);
  }

  Widget _dateField(String label, TextEditingController c, BuildContext ctx) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)), const SizedBox(height: 4),
      TextField(controller: c, readOnly: true, decoration: InputDecoration(hintText: 'TT.MM.JJJJ', prefixIcon: const Icon(Icons.calendar_today, size: 20), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
        onTap: () async { final p = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (p != null) c.text = '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}'; }),
    ]);
  }
}

class _BuergeramtVorfallDetail extends StatefulWidget {
  final ApiService apiService;
  final int userId, vorfallId;
  final Map<String, dynamic> vorfall;
  final VoidCallback onChanged;
  const _BuergeramtVorfallDetail({required this.apiService, required this.userId, required this.vorfallId, required this.vorfall, required this.onChanged});
  @override
  State<_BuergeramtVorfallDetail> createState() => _BuergeramtVorfallDetailState();
}

class _BuergeramtVorfallDetailState extends State<_BuergeramtVorfallDetail> {
  List<Map<String, dynamic>> _termine = [], _korr = [], _verlauf = [];
  bool _loaded = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final res = await widget.apiService.getBuergeramtVorfallDetail(widget.userId, widget.vorfallId);
      if (res['success'] == true && mounted) {
        _termine = (res['termine'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _korr = (res['korrespondenz'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _verlauf = (res['verlauf'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vorfall;
    final status = v['status']?.toString() ?? 'offen';
    final sc = status == 'erledigt' ? Colors.green : status == 'in_bearbeitung' ? Colors.orange : Colors.blue;
    return DefaultTabController(length: 4, child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 8, 0), child: Row(children: [
        Icon(Icons.assignment, size: 18, color: Colors.teal.shade700), const SizedBox(width: 8),
        Expanded(child: Text(v['titel']?.toString() ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal.shade800), overflow: TextOverflow.ellipsis)),
        Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: sc.shade100, borderRadius: BorderRadius.circular(6)),
          child: Text(status == 'erledigt' ? 'Erledigt' : status == 'in_bearbeitung' ? 'In Bearbeitung' : 'Offen', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: sc.shade800))),
        const SizedBox(width: 4),
        PopupMenuButton<String>(icon: const Icon(Icons.more_vert, size: 18), itemBuilder: (_) => [
          const PopupMenuItem(value: 'offen', child: Text('Offen', style: TextStyle(fontSize: 12))),
          const PopupMenuItem(value: 'in_bearbeitung', child: Text('In Bearbeitung', style: TextStyle(fontSize: 12))),
          const PopupMenuItem(value: 'erledigt', child: Text('Erledigt', style: TextStyle(fontSize: 12))),
        ], onSelected: (s) async {
          await widget.apiService.saveBuergeramtVorfall(widget.userId, {... v, 'status': s});
          v['status'] = s; widget.onChanged(); setState(() {});
        }),
        IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.pop(context)),
      ])),
      TabBar(labelColor: Colors.teal.shade700, unselectedLabelColor: Colors.grey.shade500, indicatorColor: Colors.teal.shade700, tabs: [
        const Tab(icon: Icon(Icons.info_outline, size: 16), text: 'Details'),
        Tab(icon: const Icon(Icons.email, size: 16), text: 'Korrespondenz (${_korr.length})'),
        const Tab(icon: Icon(Icons.timeline, size: 16), text: 'Verlauf'),
        Tab(icon: const Icon(Icons.event, size: 16), text: 'Termine (${_termine.length})'),
      ]),
      Expanded(child: !_loaded ? const Center(child: CircularProgressIndicator()) : TabBarView(children: [
        _buildDetails(v),
        _buildKorr(),
        _buildVerlauf(),
        _buildTermine(),
      ])),
    ]));
  }

  Widget _buildDetails(Map<String, dynamic> v) {
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _infoRow(Icons.category, 'Typ', v['typ']),
      _infoRow(Icons.title, 'Titel', v['titel']),
      _infoRow(Icons.calendar_today, 'Datum', v['datum']),
      _infoRow(Icons.folder, 'Aktenzeichen', v['aktenzeichen']),
      _infoRow(Icons.flag, 'Status', v['status']),
      if ((v['notiz']?.toString() ?? '').isNotEmpty) ...[
        const SizedBox(height: 10),
        Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
          child: Text(v['notiz'].toString(), style: const TextStyle(fontSize: 12))),
      ],
    ]));
  }

  Widget _infoRow(IconData icon, String label, dynamic value) {
    final val = value?.toString() ?? '';
    if (val.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [
      Icon(icon, size: 14, color: Colors.teal.shade600), const SizedBox(width: 8),
      Text('$label: ', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      Expanded(child: Text(val, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
    ]));
  }

  Widget _buildKorr() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        const Spacer(),
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
            const mL = {'email': 'E-Mail', 'post': 'Post', 'online': 'Online', 'persoenlich': 'Persönlich', 'fax': 'Fax', 'telefon': 'Telefon'};
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
                    onPressed: () async { await widget.apiService.deleteBuergeramtKorr(widget.userId, kId); _load(); }),
                ]),
                if ((k['datum']?.toString() ?? '').isNotEmpty) Text(k['datum'].toString(), style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                if ((k['notiz']?.toString() ?? '').isNotEmpty) Text(k['notiz'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                Padding(padding: const EdgeInsets.only(top: 4), child: KorrAttachmentsWidget(apiService: widget.apiService, modul: 'buergeramt', korrespondenzId: kId)),
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
          final res = await widget.apiService.saveBuergeramtKorr(widget.userId, widget.vorfallId, {'richtung': richtung, 'methode': methode, 'datum': datumC.text.trim(), 'betreff': betreffC.text.trim(), 'notiz': notizC.text.trim()});
          final korrId = res['id'];
          if (korrId != null && files.isNotEmpty) { for (final f in files) { if (f.path == null) continue; await widget.apiService.uploadKorrAttachment(modul: 'buergeramt', korrespondenzId: korrId is int ? korrId : int.parse(korrId.toString()), filePath: f.path!, fileName: f.name); } }
          if (ctx.mounted) Navigator.pop(ctx); _load();
        }, child: const Text('Speichern')),
      ],
    )));
  }

  Widget _buildVerlauf() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [const Spacer(),
        FilledButton.icon(icon: const Icon(Icons.add, size: 14), label: const Text('Eintrag', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade600, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _addVerlauf()),
      ])),
      Expanded(child: _verlauf.isEmpty ? Center(child: Text('Noch keine Einträge', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _verlauf.length, itemBuilder: (_, i) {
            final e = _verlauf[i];
            return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Icon(Icons.circle, size: 8, color: Colors.teal.shade400), const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e['aktion']?.toString() ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  if ((e['datum']?.toString() ?? '').isNotEmpty) Text(e['datum'].toString(), style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  if ((e['notiz']?.toString() ?? '').isNotEmpty) Text(e['notiz'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                ])),
              ]));
          })),
    ]);
  }

  void _addVerlauf() {
    final datumC = TextEditingController(); final aktionC = TextEditingController(); final notizC = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Verlauf-Eintrag', style: TextStyle(fontSize: 14)),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', prefixIcon: const Icon(Icons.calendar_today, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async { final p = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de')); if (p != null) datumC.text = '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}'; }))),
        const SizedBox(height: 8),
        TextField(controller: aktionC, decoration: InputDecoration(labelText: 'Aktion *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          await widget.apiService.saveBuergeramtVerlauf(widget.userId, widget.vorfallId, {'datum': datumC.text.trim(), 'aktion': aktionC.text.trim(), 'notiz': notizC.text.trim()});
          if (ctx.mounted) Navigator.pop(ctx); _load();
        }, child: const Text('Speichern')),
      ],
    ));
  }

  Widget _buildTermine() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [const Spacer(),
        FilledButton.icon(icon: const Icon(Icons.add, size: 14), label: const Text('Neuer Termin', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade600, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _addTermin()),
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
                  onPressed: () async { await widget.apiService.deleteBuergeramtTermin(widget.userId, t['id'] is int ? t['id'] : int.parse(t['id'].toString())); _load(); }),
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
          await widget.apiService.saveBuergeramtTermin(widget.userId, widget.vorfallId, {'datum': datumC.text.trim(), 'uhrzeit': uhrzeitC.text.trim(), 'ort': ortC.text.trim(), 'notiz': notizC.text.trim()});
          if (ctx.mounted) Navigator.pop(ctx); _load();
        }, child: const Text('Speichern')),
      ],
    ));
  }
}
