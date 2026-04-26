import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';
import '../widgets/korrespondenz_attachments_widget.dart';

class ServdiscountScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onBack;
  const ServdiscountScreen({super.key, required this.apiService, required this.onBack});
  @override
  State<ServdiscountScreen> createState() => _State();
}

class _State extends State<ServdiscountScreen> with TickerProviderStateMixin {
  late final TabController _tab;
  bool _loaded = false;
  Map<String, dynamic> _data = {};
  List<Map<String, dynamic>> _servers = [], _vertraege = [], _korr = [], _verlauf = [];

  @override
  void initState() { super.initState(); _tab = TabController(length: 5, vsync: this); _load(); }
  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final r = await widget.apiService.getServdiscountData();
      debugPrint('[ServDiscount] load success=${r['success']}, korr=${(r['korrespondenz'] as List?)?.length ?? 0}');
      if (r['success'] == true && mounted) {
        setState(() {
          _data = Map<String, dynamic>.from(r['data'] ?? {});
          _servers = (r['servers'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _vertraege = (r['vertraege'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _korr = (r['korrespondenz'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _verlauf = (r['verlauf'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _loaded = true;
        });
        debugPrint('[ServDiscount] _korr.length=${_korr.length}');
        if (_korr.isNotEmpty && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_korr.length} Korrespondenz geladen'), duration: const Duration(seconds: 1), backgroundColor: Colors.green));
        return;
      }
    } catch (e) { debugPrint('[ServDiscount] load error: $e'); }
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _act(Map<String, dynamic> body) async { await widget.apiService.servdiscountAction(body); await _load(); }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: Row(children: [
        IconButton(icon: const Icon(Icons.arrow_back, size: 20), onPressed: widget.onBack),
        const SizedBox(width: 8),
        Icon(Icons.dns, size: 22, color: Colors.orange.shade700), const SizedBox(width: 8),
        Text('servdiscount.com', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
        const Spacer(),
        Text('myLoc managed IT AG', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      ])),
      TabBar(controller: _tab, isScrollable: true, tabAlignment: TabAlignment.start, labelColor: Colors.orange.shade700, unselectedLabelColor: Colors.grey.shade500, indicatorColor: Colors.orange.shade700,
        tabs: const [
          Tab(icon: Icon(Icons.business, size: 14), text: 'Firma'),
          Tab(icon: Icon(Icons.description, size: 14), text: 'Verträge'),
          Tab(icon: Icon(Icons.dns, size: 14), text: 'Server'),
          Tab(icon: Icon(Icons.email, size: 14), text: 'Korrespondenz'),
          Tab(icon: Icon(Icons.timeline, size: 14), text: 'Verlauf'),
        ]),
      Expanded(child: !_loaded ? const Center(child: CircularProgressIndicator()) : TabBarView(controller: _tab, children: [
        _buildFirma(),
        _buildVertraege(),
        _buildServers(),
        _ServdiscountKorrTab(apiService: widget.apiService),
        _buildVerlauf(),
      ])),
    ]);
  }

  // ──── FIRMA ────
  Widget _buildFirma() {
    final hasF = (_data['firma_name']?.toString() ?? '').isNotEmpty;
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.dns, size: 20, color: Colors.orange.shade700), const SizedBox(width: 8),
        Text('Zuständige Firma', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.orange.shade700)),
        const Spacer(),
        FilledButton.icon(icon: const Icon(Icons.search, size: 16), label: Text(hasF ? 'Ändern' : 'Suchen', style: const TextStyle(fontSize: 12)),
          style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade600, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero),
          onPressed: () async {
            final res = await widget.apiService.getArbeitgeberStammdaten();
            if (res['success'] != true || !mounted) return;
            final all = (res['data'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
            final sel = await showDialog<Map<String, dynamic>>(context: context, builder: (sCtx) {
              String search = '';
              List<Map<String, dynamic>> results = all;
              return StatefulBuilder(builder: (sCtx, setS) => AlertDialog(
                title: Row(children: [Icon(Icons.business, size: 18, color: Colors.orange.shade700), const SizedBox(width: 8), const Text('Firma auswählen', style: TextStyle(fontSize: 14))]),
                content: SizedBox(width: 450, height: 400, child: Column(children: [
                  TextField(autofocus: true, decoration: InputDecoration(hintText: 'Suchen...', prefixIcon: const Icon(Icons.search, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                    onChanged: (v) => setS(() { search = v.toLowerCase(); results = all.where((a) => (a['firma_name']?.toString() ?? '').toLowerCase().contains(search)).toList(); })),
                  const SizedBox(height: 8),
                  Expanded(child: results.isEmpty ? Center(child: Text('Keine Ergebnisse', style: TextStyle(color: Colors.grey.shade500)))
                    : ListView.builder(itemCount: results.length, itemBuilder: (_, i) {
                        final a = results[i];
                        return ListTile(dense: true, leading: Icon(Icons.business, size: 18, color: Colors.orange.shade400),
                          title: Text(a['firma_name']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: Text([a['branche'], a['hauptzentrale_ort']].where((v) => v != null && v.toString().isNotEmpty).join(' · '), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          onTap: () => Navigator.pop(sCtx, a));
                      })),
                ])),
                actions: [TextButton(onPressed: () => Navigator.pop(sCtx), child: const Text('Abbrechen'))],
              ));
            });
            if (sel != null) {
              final m = <String, dynamic>{};
              for (final k in ['firma_name', 'rechtsform', 'branche', 'hauptzentrale_strasse', 'hauptzentrale_plz', 'hauptzentrale_ort', 'hauptzentrale_telefon', 'hauptzentrale_email', 'geschaeftsfuehrer', 'registergericht', 'registernummer', 'ust_id', 'website']) {
                m[k] = sel[k]?.toString() ?? ''; _data[k] = sel[k]?.toString() ?? '';
              }
              await widget.apiService.servdiscountAction({'action': 'save_data', 'data': m});
              if (mounted) setState(() {});
            }
          }),
      ]),
      const SizedBox(height: 16),
      if (!hasF)
        Container(width: double.infinity, padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
          child: Column(children: [Icon(Icons.search, size: 48, color: Colors.grey.shade300), const SizedBox(height: 8), Text('Keine Firma ausgewählt', style: TextStyle(fontSize: 13, color: Colors.grey.shade500))]))
      else
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.shade200)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [CircleAvatar(radius: 22, backgroundColor: Colors.orange.shade100, child: Icon(Icons.dns, size: 24, color: Colors.orange.shade700)), const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_data['firma_name']?.toString() ?? '', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                if ((_data['branche']?.toString() ?? '').isNotEmpty) Text(_data['branche'].toString(), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ])),
              IconButton(icon: Icon(Icons.close, size: 18, color: Colors.red.shade400), onPressed: () async {
                await widget.apiService.servdiscountAction({'action': 'save_data', 'data': {'firma_name': ''}}); _data.clear(); if (mounted) setState(() {}); }),
            ]),
            const Divider(height: 20),
            if ((_data['hauptzentrale_strasse']?.toString() ?? '').isNotEmpty || (_data['hauptzentrale_ort']?.toString() ?? '').isNotEmpty)
              _ir(Icons.location_on, [_data['hauptzentrale_strasse'], '${_data['hauptzentrale_plz'] ?? ''} ${_data['hauptzentrale_ort'] ?? ''}'.trim()].where((s) => (s?.toString() ?? '').isNotEmpty).join(', ')),
            if ((_data['hauptzentrale_telefon']?.toString() ?? '').isNotEmpty) _ir(Icons.phone, _data['hauptzentrale_telefon'].toString()),
            if ((_data['hauptzentrale_email']?.toString() ?? '').isNotEmpty) _ir(Icons.email, _data['hauptzentrale_email'].toString()),
            if ((_data['website']?.toString() ?? '').isNotEmpty) _ir(Icons.language, _data['website'].toString()),
            if ((_data['geschaeftsfuehrer']?.toString() ?? '').isNotEmpty) _ir(Icons.person, 'Vorstand: ${_data['geschaeftsfuehrer']}'),
            if ((_data['registergericht']?.toString() ?? '').isNotEmpty) _ir(Icons.gavel, '${_data['registergericht']}, ${_data['registernummer'] ?? ''}'),
            if ((_data['ust_id']?.toString() ?? '').isNotEmpty) _ir(Icons.receipt, 'USt-ID: ${_data['ust_id']}'),
          ])),
    ]));
  }

  Widget _ir(IconData icon, String text) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [
    Icon(icon, size: 16, color: Colors.orange.shade600), const SizedBox(width: 10), Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: Colors.grey.shade800)))]));

  // ──── VERTRÄGE ────
  Widget _buildVertraege() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [Text('${_vertraege.length} Verträge', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)), const Spacer(),
        FilledButton.icon(icon: const Icon(Icons.add, size: 14), label: const Text('Neu', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _addVertrag())])),
      Expanded(child: _vertraege.isEmpty ? Center(child: Text('Keine Verträge', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _vertraege.length, itemBuilder: (_, i) {
            final v = _vertraege[i]; final aktiv = v['status'] == 'aktiv';
            return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade200)),
              child: Row(children: [Icon(Icons.description, size: 16, color: Colors.orange.shade700), const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Expanded(child: Text(v['name']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange.shade800))),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: aktiv ? Colors.green.shade100 : Colors.red.shade100, borderRadius: BorderRadius.circular(4)),
                      child: Text(aktiv ? 'Aktiv' : 'Gekündigt', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: aktiv ? Colors.green.shade800 : Colors.red.shade800)))]),
                  if ((v['kosten']?.toString() ?? '').isNotEmpty) Text('${v['kosten']} €/Monat', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ])),
                IconButton(icon: Icon(Icons.delete_outline, size: 14, color: Colors.red.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: () async { await _act({'action': 'delete_vertrag', 'id': v['id']}); }),
              ]));
          })),
    ]);
  }

  void _addVertrag() {
    final nameC = TextEditingController(); final typC = TextEditingController(); final kostenC = TextEditingController();
    final laufzeitC = TextEditingController(); final fristC = TextEditingController(); final beginnC = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Neuer Vertrag', style: TextStyle(fontSize: 14)),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameC, decoration: InputDecoration(labelText: 'Name *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))), const SizedBox(height: 8),
        TextField(controller: typC, decoration: InputDecoration(labelText: 'Typ (Dedicated, vServer, Hosting)', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))), const SizedBox(height: 8),
        TextField(controller: kostenC, decoration: InputDecoration(labelText: 'Kosten €/Monat', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))), const SizedBox(height: 8),
        Row(children: [Expanded(child: TextField(controller: laufzeitC, decoration: InputDecoration(labelText: 'Laufzeit', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
          const SizedBox(width: 8), Expanded(child: TextField(controller: fristC, decoration: InputDecoration(labelText: 'Kündigungsfrist', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))))]),
        const SizedBox(height: 8),
        TextFormField(controller: beginnC, readOnly: true, decoration: InputDecoration(labelText: 'Vertragsbeginn', prefixIcon: const Icon(Icons.calendar_today, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async { final p = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de')); if (p != null) beginnC.text = '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}'; }))),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async { Navigator.pop(ctx); await _act({'action': 'save_vertrag', 'vertrag': {'name': nameC.text.trim(), 'typ': typC.text.trim(), 'kosten': kostenC.text.trim(), 'laufzeit': laufzeitC.text.trim(), 'kuendigungsfrist': fristC.text.trim(), 'vertragsbeginn': beginnC.text.trim()}}); }, child: const Text('Speichern'))],
    ));
  }

  // ──── SERVERS ────
  Widget _buildServers() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [Text('${_servers.length} Server', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)), const Spacer(),
        FilledButton.icon(icon: const Icon(Icons.add, size: 14), label: const Text('Neu', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _addServer())])),
      Expanded(child: _servers.isEmpty ? Center(child: Text('Keine Server', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _servers.length, itemBuilder: (_, i) {
            final s = _servers[i]; final aktiv = s['status'] == 'aktiv';
            return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: aktiv ? Colors.green.shade50 : Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: aktiv ? Colors.green.shade200 : Colors.grey.shade200)),
              child: Row(children: [Icon(Icons.dns, size: 18, color: aktiv ? Colors.green.shade700 : Colors.grey.shade500), const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Expanded(child: Text(s['name']?.toString() ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: aktiv ? Colors.green.shade800 : Colors.grey.shade700))),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: aktiv ? Colors.green.shade100 : Colors.red.shade100, borderRadius: BorderRadius.circular(4)),
                      child: Text(aktiv ? 'Online' : 'Offline', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: aktiv ? Colors.green.shade800 : Colors.red.shade800)))]),
                  if ((s['ip']?.toString() ?? '').isNotEmpty) Text('IP: ${s['ip']}', style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.grey.shade600)),
                  Row(children: [
                    if ((s['typ']?.toString() ?? '').isNotEmpty) Text('${s['typ']} · ', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                    if ((s['ram']?.toString() ?? '').isNotEmpty) Text('${s['ram']} RAM · ', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                    if ((s['storage']?.toString() ?? '').isNotEmpty) Text(s['storage'].toString(), style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                  ]),
                  if ((s['monatliche_kosten']?.toString() ?? '').isNotEmpty) Text('${s['monatliche_kosten']} €/Monat', style: TextStyle(fontSize: 11, color: Colors.orange.shade700)),
                ])),
                IconButton(icon: Icon(Icons.delete_outline, size: 14, color: Colors.red.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: () async { await _act({'action': 'delete_server', 'id': s['id']}); }),
              ]));
          })),
    ]);
  }

  void _addServer() {
    final nameC = TextEditingController(); final ipC = TextEditingController(); final typC = TextEditingController(text: 'Dedicated');
    final osC = TextEditingController(); final ramC = TextEditingController(); final cpuC = TextEditingController();
    final storageC = TextEditingController(); final kostenC = TextEditingController(); final standortC = TextEditingController(text: 'Düsseldorf');
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Neuer Server', style: TextStyle(fontSize: 14)),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [Expanded(child: TextField(controller: nameC, decoration: InputDecoration(labelText: 'Name *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
          const SizedBox(width: 8), Expanded(child: TextField(controller: ipC, decoration: InputDecoration(labelText: 'IP-Adresse', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))))]), const SizedBox(height: 8),
        Row(children: [Expanded(child: TextField(controller: typC, decoration: InputDecoration(labelText: 'Typ', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
          const SizedBox(width: 8), Expanded(child: TextField(controller: standortC, decoration: InputDecoration(labelText: 'Standort', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))))]), const SizedBox(height: 8),
        TextField(controller: osC, decoration: InputDecoration(labelText: 'Betriebssystem', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))), const SizedBox(height: 8),
        Row(children: [Expanded(child: TextField(controller: ramC, decoration: InputDecoration(labelText: 'RAM', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
          const SizedBox(width: 8), Expanded(child: TextField(controller: cpuC, decoration: InputDecoration(labelText: 'CPU', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))))]), const SizedBox(height: 8),
        Row(children: [Expanded(child: TextField(controller: storageC, decoration: InputDecoration(labelText: 'Storage', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
          const SizedBox(width: 8), Expanded(child: TextField(controller: kostenC, decoration: InputDecoration(labelText: '€/Monat', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))))]),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async { Navigator.pop(ctx); await _act({'action': 'save_server', 'server': {'name': nameC.text.trim(), 'ip': ipC.text.trim(), 'typ': typC.text.trim(), 'standort': standortC.text.trim(), 'os': osC.text.trim(), 'ram': ramC.text.trim(), 'cpu': cpuC.text.trim(), 'storage': storageC.text.trim(), 'monatliche_kosten': kostenC.text.trim()}}); }, child: const Text('Speichern'))],
    ));
  }

  // ──── VERLAUF ────
  Widget _buildVerlauf() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [const Spacer(),
        FilledButton.icon(icon: const Icon(Icons.add, size: 14), label: const Text('Eintrag', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade600, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _addVerlauf())])),
      Expanded(child: _verlauf.isEmpty ? Center(child: Text('Noch keine Einträge', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _verlauf.length, itemBuilder: (_, i) {
            final e = _verlauf[i];
            return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
              child: Row(children: [Icon(Icons.circle, size: 8, color: Colors.orange.shade400), const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Expanded(child: Text(e['aktion']?.toString() ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                    if ((e['datum']?.toString() ?? '').isNotEmpty) Text(e['datum'].toString(), style: TextStyle(fontSize: 10, color: Colors.grey.shade600))]),
                  if ((e['notiz']?.toString() ?? '').isNotEmpty) Text(e['notiz'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                ])),
                IconButton(icon: Icon(Icons.delete_outline, size: 14, color: Colors.red.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: () async { await _act({'action': 'delete_verlauf', 'id': e['id']}); }),
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
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async { Navigator.pop(ctx); await _act({'action': 'save_verlauf', 'verlauf': {'datum': datumC.text.trim(), 'aktion': aktionC.text.trim(), 'notiz': notizC.text.trim()}}); }, child: const Text('Speichern'))],
    ));
  }
}

class _ServdiscountKorrTab extends StatefulWidget {
  final ApiService apiService;
  const _ServdiscountKorrTab({required this.apiService});
  @override
  State<_ServdiscountKorrTab> createState() => _ServdiscountKorrTabState();
}

class _ServdiscountKorrTabState extends State<_ServdiscountKorrTab> {
  List<Map<String, dynamic>> _korr = [];
  bool _loaded = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final r = await widget.apiService.getServdiscountData();
      if (r['success'] == true && mounted) {
        setState(() {
          _korr = (r['korrespondenz'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _loaded = true;
        });
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Text('${_korr.length} Einträge', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
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
            final kId = k['id'] is int ? k['id'] as int : int.parse(k['id'].toString());
            const mL = {'email': 'E-Mail', 'post': 'Post', 'online': 'Online/Ticket', 'persoenlich': 'Persönlich'};
            return InkWell(borderRadius: BorderRadius.circular(8), onTap: () => _showDetail(k),
              child: Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: c.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: c.shade200)),
                child: Row(children: [Icon(isEin ? Icons.call_received : Icons.call_made, size: 18, color: c.shade700), const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(k['betreff']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c.shade800)),
                    if ((k['datum']?.toString() ?? '').isNotEmpty) Text(k['datum'].toString(), style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  ])),
                  if ((k['methode']?.toString() ?? '').isNotEmpty) Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: c.shade100, borderRadius: BorderRadius.circular(4)),
                    child: Text(mL[k['methode']] ?? k['methode'].toString(), style: TextStyle(fontSize: 9, color: c.shade700))),
                  Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
                ])));
          })),
    ]);
  }

  void _showDetail(Map<String, dynamic> k) {
    final isEin = k['richtung'] == 'eingang'; final c = isEin ? Colors.green : Colors.blue;
    const mL = {'email': 'E-Mail', 'post': 'Post', 'online': 'Online/Ticket', 'persoenlich': 'Persönlich'};
    final kId = k['id'] is int ? k['id'] as int : int.parse(k['id'].toString());
    showDialog(context: context, builder: (ctx) => AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      title: Row(children: [Icon(isEin ? Icons.call_received : Icons.call_made, size: 18, color: c.shade700), const SizedBox(width: 8),
        Expanded(child: Text(k['betreff']?.toString() ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: c.shade800), overflow: TextOverflow.ellipsis)),
        IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), onPressed: () async {
          await widget.apiService.servdiscountAction({'action': 'delete_korr', 'id': kId}); await _load(); if (ctx.mounted) Navigator.pop(ctx); }),
        IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.pop(ctx))]),
      content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if ((k['methode']?.toString() ?? '').isNotEmpty) _r(Icons.send, 'Methode', mL[k['methode']] ?? k['methode'].toString()),
            if ((k['datum']?.toString() ?? '').isNotEmpty) _r(Icons.calendar_today, 'Datum', k['datum'].toString()),
            _r(Icons.subject, 'Betreff', k['betreff']?.toString() ?? ''),
          ])),
        if ((k['notiz']?.toString() ?? '').isNotEmpty) ...[const SizedBox(height: 12),
          Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Inhalt', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade600)), const SizedBox(height: 6), Text(k['notiz'].toString(), style: const TextStyle(fontSize: 13))]))],
        const SizedBox(height: 12),
        KorrAttachmentsWidget(apiService: widget.apiService, modul: 'servdiscount', korrespondenzId: kId),
      ]))),
    ));
  }

  Widget _r(IconData icon, String label, String val) => val.isEmpty ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(children: [
    Icon(icon, size: 12, color: Colors.grey.shade500), const SizedBox(width: 6), Text('$label: ', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)), Expanded(child: Text(val, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)))]));

  Future<void> _addKorr(String richtung) async {
    final datumC = TextEditingController(); final betreffC = TextEditingController(); final notizC = TextEditingController();
    String methode = 'email';
    List<PlatformFile> files = [];
    final ok = await showDialog<Map<String, dynamic>>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) => AlertDialog(
      title: Text(richtung == 'eingang' ? 'Eingang' : 'Ausgang', style: const TextStyle(fontSize: 14)),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Wrap(spacing: 6, runSpacing: 4, children: [for (final m in [('email', 'E-Mail', Icons.email), ('online', 'Online/Ticket', Icons.language), ('post', 'Post', Icons.mail)])
          ChoiceChip(label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(m.$3, size: 13, color: methode == m.$1 ? Colors.white : Colors.grey.shade700), const SizedBox(width: 4), Text(m.$2, style: TextStyle(fontSize: 10, color: methode == m.$1 ? Colors.white : Colors.grey.shade700))]),
            selected: methode == m.$1, selectedColor: Colors.orange.shade600, onSelected: (_) => setDlg(() => methode = m.$1))]),
        const SizedBox(height: 12),
        TextFormField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', prefixIcon: const Icon(Icons.calendar_today, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async { final p = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de')); if (p != null) setDlg(() => datumC.text = '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}'); }))),
        const SizedBox(height: 8),
        TextField(controller: betreffC, decoration: InputDecoration(labelText: 'Betreff *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 3, decoration: InputDecoration(labelText: 'Inhalt / Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 12),
        OutlinedButton.icon(icon: Icon(Icons.attach_file, size: 16, color: Colors.teal.shade600),
          label: Text(files.isEmpty ? 'Dokumente' : '${files.length} Datei(en)', style: TextStyle(fontSize: 12, color: Colors.teal.shade700)),
          style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.teal.shade300)),
          onPressed: () async { final r = await FilePickerHelper.pickFiles(allowMultiple: true, type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']); if (r != null) setDlg(() { files.addAll(r.files); }); }),
        if (files.isNotEmpty) ...files.asMap().entries.map((e) => Padding(padding: const EdgeInsets.only(top: 3), child: Row(children: [
          Icon(Icons.description, size: 13, color: Colors.grey.shade500), const SizedBox(width: 6),
          Expanded(child: Text(e.value.name, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
          IconButton(icon: Icon(Icons.close, size: 14, color: Colors.red.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24), onPressed: () => setDlg(() => files.removeAt(e.key)))]))),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () {
          if (betreffC.text.trim().isEmpty) return;
          Navigator.pop(ctx, {'richtung': richtung, 'methode': methode, 'datum': datumC.text.trim(), 'betreff': betreffC.text.trim(), 'notiz': notizC.text.trim()});
        }, child: const Text('Speichern'))],
    )));
    if (ok == null) return;
    final res = await widget.apiService.servdiscountAction({'action': 'save_korr', 'korr': ok});
    final korrId = res['id'];
    if (korrId != null && files.isNotEmpty) { for (final f in files) { if (f.path == null) continue; await widget.apiService.uploadKorrAttachment(modul: 'servdiscount', korrespondenzId: korrId is int ? korrId : int.parse(korrId.toString()), filePath: f.path!, fileName: f.name); } }
    await _load();
  }
}
