import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'korrespondenz_attachments_widget.dart';

class BehordeDeutschlandticketContent extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final String userName;
  final String userNachname;
  const BehordeDeutschlandticketContent({super.key, required this.apiService, required this.userId, this.userName = '', this.userNachname = ''});
  @override
  State<BehordeDeutschlandticketContent> createState() => _State();
}

class _State extends State<BehordeDeutschlandticketContent> with TickerProviderStateMixin {
  late TabController _tabC;
  Map<String, dynamic> _data = {};
  List<Map<String, dynamic>> _vertraege = [];
  bool _isLoading = true;

  @override
  void initState() { super.initState(); _tabC = TabController(length: 2, vsync: this); _load(); }
  @override
  void dispose() { _tabC.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final res = await widget.apiService.getDticketData(widget.userId);
      if (res['success'] == true) {
        _data = Map<String, dynamic>.from(res['data'] ?? {});
        _vertraege = (res['vertraege'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      TabBar(controller: _tabC, labelColor: Colors.red.shade800, unselectedLabelColor: Colors.grey, indicatorColor: Colors.red.shade700, tabs: const [
        Tab(text: 'Zuständige Firma'),
        Tab(text: 'Vertrag'),
      ]),
      Expanded(child: TabBarView(controller: _tabC, children: [
        _FirmaTab(data: _data, apiService: widget.apiService, userId: widget.userId, onReload: _load),
        _VertragTab(vertraege: _vertraege, apiService: widget.apiService, userId: widget.userId, onReload: _load, firmaData: _data, userName: widget.userName, userNachname: widget.userNachname),
      ])),
    ]);
  }
}

// ==================== ZUSTÄNDIGE FIRMA ====================
class _FirmaTab extends StatefulWidget {
  final Map<String, dynamic> data; final ApiService apiService; final int userId; final Future<void> Function() onReload;
  const _FirmaTab({required this.data, required this.apiService, required this.userId, required this.onReload});
  @override State<_FirmaTab> createState() => _FirmaTabState();
}
class _FirmaTabState extends State<_FirmaTab> {
  Map<String, dynamic>? _selected;

  @override
  void initState() { super.initState();
    final n = widget.data['stammdaten.selected_firma_name'] ?? '';
    if (n.isNotEmpty) _selected = {'name': n, 'strasse': widget.data['stammdaten.selected_firma_strasse'] ?? '', 'ort': widget.data['stammdaten.selected_firma_ort'] ?? '', 'telefon': widget.data['stammdaten.selected_firma_telefon'] ?? '', 'email': widget.data['stammdaten.selected_firma_email'] ?? '', 'website': widget.data['stammdaten.selected_firma_website'] ?? '', 'notiz': widget.data['stammdaten.selected_firma_notiz'] ?? ''};
  }

  void _openSearch() {
    final searchC = TextEditingController();
    List<Map<String, dynamic>> all = [], filtered = [];
    bool loading = true;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) {
      if (loading && all.isEmpty) {
        widget.apiService.searchDticketFirmen('').then((res) {
          if (res['success'] == true) all = (res['results'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
          filtered = List.from(all); setDlg(() => loading = false);
        }).catchError((_) => setDlg(() => loading = false));
      }
      void filter(String q) { if (q.isEmpty) { setDlg(() => filtered = List.from(all)); return; }
        final l = q.toLowerCase(); setDlg(() => filtered = all.where((s) => (s['name']?.toString() ?? '').toLowerCase().contains(l) || (s['ort']?.toString() ?? '').toLowerCase().contains(l)).toList()); }
      return AlertDialog(
        title: Row(children: [Icon(Icons.train, color: Colors.red.shade700), const SizedBox(width: 8), const Text('Firma auswählen', style: TextStyle(fontSize: 16))]),
        content: SizedBox(width: 500, height: 400, child: Column(children: [
          TextField(controller: searchC, autofocus: true, decoration: InputDecoration(hintText: 'Filter...', prefixIcon: const Icon(Icons.search), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onChanged: filter),
          const SizedBox(height: 12), if (loading) const LinearProgressIndicator(),
          Expanded(child: filtered.isEmpty ? Center(child: Text(loading ? '' : 'Keine Firmen', style: TextStyle(color: Colors.grey.shade400)))
            : ListView.builder(itemCount: filtered.length, itemBuilder: (_, i) { final s = filtered[i];
                return Card(margin: const EdgeInsets.only(bottom: 6), child: ListTile(
                  leading: CircleAvatar(backgroundColor: Colors.red.shade100, child: Icon(Icons.train, color: Colors.red.shade700, size: 20)),
                  title: Text(s['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text('${s['strasse'] ?? ''}, ${s['plz'] ?? ''} ${s['ort'] ?? ''}', style: const TextStyle(fontSize: 11)),
                  onTap: () { Navigator.pop(ctx); _selectAndSave(s); },
                )); })),
        ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen'))]);
    }));
  }

  Future<void> _selectAndSave(Map<String, dynamic> s) async {
    setState(() => _selected = s);
    await widget.apiService.dticketAction(widget.userId, {'action': 'save_data', 'data': {
      'stammdaten.selected_firma_name': s['name']?.toString() ?? '', 'stammdaten.selected_firma_strasse': s['strasse']?.toString() ?? '',
      'stammdaten.selected_firma_ort': '${s['plz'] ?? ''} ${s['ort'] ?? ''}'.trim(), 'stammdaten.selected_firma_telefon': s['telefon']?.toString() ?? '',
      'stammdaten.selected_firma_email': s['email']?.toString() ?? '', 'stammdaten.selected_firma_website': s['website']?.toString() ?? '', 'stammdaten.selected_firma_notiz': s['notiz']?.toString() ?? '',
    }});
    await widget.onReload();
  }

  Widget _row(IconData icon, String label, String value) { if (value.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [Icon(icon, size: 16, color: Colors.red.shade400), const SizedBox(width: 8), SizedBox(width: 70, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600))), Expanded(child: Text(value, style: const TextStyle(fontSize: 13)))])); }

  @override
  Widget build(BuildContext context) {
    if (_selected == null) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.train, size: 64, color: Colors.grey.shade300), const SizedBox(height: 16),
      Text('Keine Firma ausgewählt', style: TextStyle(fontSize: 16, color: Colors.grey.shade500)), const SizedBox(height: 16),
      ElevatedButton.icon(onPressed: _openSearch, icon: const Icon(Icons.search), label: const Text('Firma suchen'), style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white)),
    ]));
    final s = _selected!;
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Text('Zuständige Firma', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red.shade800)), const Spacer(),
        TextButton.icon(icon: const Icon(Icons.swap_horiz, size: 16), label: const Text('Ändern', style: TextStyle(fontSize: 12)), onPressed: _openSearch)]),
      const SizedBox(height: 12),
      Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.shade200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Container(width: 48, height: 48, decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(12)), child: Icon(Icons.train, color: Colors.red.shade700, size: 28)),
            const SizedBox(width: 14), Expanded(child: Text(s['name']?.toString() ?? '', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red.shade800))),
            IconButton(icon: Icon(Icons.close, color: Colors.red.shade400), onPressed: () => setState(() => _selected = null))]),
          const Divider(height: 20),
          _row(Icons.location_on, 'Adresse', '${s['strasse'] ?? ''}, ${s['ort'] ?? ''}'.trim()),
          _row(Icons.phone, 'Telefon', s['telefon']?.toString() ?? ''),
          _row(Icons.email, 'E-Mail', s['email']?.toString() ?? ''),
          _row(Icons.language, 'Website', s['website']?.toString() ?? ''),
          if ((s['notiz']?.toString() ?? '').isNotEmpty) ...[const SizedBox(height: 8),
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.shade100)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.info_outline, size: 16, color: Colors.red.shade400), const SizedBox(width: 8),
                Expanded(child: Text(s['notiz'].toString(), style: TextStyle(fontSize: 12, color: Colors.grey.shade700)))]))],
        ])),
    ]));
  }
}

// ==================== VERTRAG ====================
class _VertragTab extends StatefulWidget {
  final List<Map<String, dynamic>> vertraege; final ApiService apiService; final int userId; final Future<void> Function() onReload; final Map<String, dynamic> firmaData; final String userName; final String userNachname;
  const _VertragTab({required this.vertraege, required this.apiService, required this.userId, required this.onReload, required this.firmaData, this.userName = '', this.userNachname = ''});
  @override State<_VertragTab> createState() => _VertragTabState();
}
class _VertragTabState extends State<_VertragTab> {
  void _add([Map<String, dynamic>? e]) {
    final isEdit = e != null;
    final anbieterC = TextEditingController(text: e?['anbieter'] ?? ''); final aboC = TextEditingController(text: e?['abo_nr'] ?? '');
    final preisC = TextEditingController(text: e?['preis'] ?? '63,00'); final ibanC = TextEditingController(text: e?['iban'] ?? '');
    final abC = TextEditingController(text: e?['gueltig_ab'] ?? ''); final bisC = TextEditingController(text: e?['gueltig_bis'] ?? '');
    final notizC = TextEditingController(text: e?['notiz'] ?? '');
    String zahlungsart = e?['zahlungsart'] ?? 'Lastschrift'; String status = e?['status'] ?? 'aktiv';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) => AlertDialog(
      title: Text(isEdit ? 'Vertrag bearbeiten' : 'Neuer Vertrag', style: const TextStyle(fontSize: 15)),
      content: SizedBox(width: 450, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: anbieterC, decoration: InputDecoration(labelText: 'Anbieter', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 10),
        Row(children: [Expanded(child: TextField(controller: aboC, decoration: InputDecoration(labelText: 'Abo-Nr.', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
          const SizedBox(width: 8), Expanded(child: TextField(controller: preisC, decoration: InputDecoration(labelText: 'Preis €/Mo', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))))]),
        const SizedBox(height: 10),
        TextField(controller: ibanC, decoration: InputDecoration(labelText: 'IBAN', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 10),
        Row(children: [Expanded(child: TextField(controller: abC, readOnly: true, decoration: InputDecoration(labelText: 'Gültig ab', isDense: true, prefixIcon: const Icon(Icons.calendar_today, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          onTap: () async { final d = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (d != null) abC.text = '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}'; })),
          const SizedBox(width: 8), Expanded(child: TextField(controller: bisC, readOnly: true, decoration: InputDecoration(labelText: 'Gültig bis', isDense: true, prefixIcon: const Icon(Icons.calendar_today, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          onTap: () async { final d = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (d != null) bisC.text = '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}'; }))]),
        const SizedBox(height: 10),
        Row(children: [for (final z in ['Lastschrift', 'Überweisung']) ...[ChoiceChip(label: Text(z, style: const TextStyle(fontSize: 11)), selected: zahlungsart == z, onSelected: (_) => setDlg(() => zahlungsart = z)), const SizedBox(width: 6)],
          const SizedBox(width: 12), for (final s in ['aktiv', 'gekündigt']) ...[ChoiceChip(label: Text(s[0].toUpperCase() + s.substring(1), style: const TextStyle(fontSize: 11)), selected: status == s, onSelected: (_) => setDlg(() => status = s)), const SizedBox(width: 6)]]),
        const SizedBox(height: 10),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () async { Navigator.pop(ctx);
          await widget.apiService.dticketAction(widget.userId, {'action': 'save_vertrag', 'vertrag': {if (isEdit) 'id': e['id'], 'anbieter': anbieterC.text, 'abo_nr': aboC.text, 'preis': preisC.text, 'zahlungsart': zahlungsart, 'gueltig_ab': abC.text, 'gueltig_bis': bisC.text, 'iban': ibanC.text, 'status': status, 'notiz': notizC.text}});
          await widget.onReload();
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white), child: Text(isEdit ? 'Speichern' : 'Hinzufügen'))],
    )));
  }

  void _openDetail(Map<String, dynamic> v) {
    showDialog(context: context, barrierDismissible: false, builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: SizedBox(width: double.infinity, height: MediaQuery.of(context).size.height * 0.8, child: _VertragDetailModal(vertrag: v, apiService: widget.apiService, userId: widget.userId, onReload: widget.onReload, firmaData: widget.firmaData, userName: widget.userName, userNachname: widget.userNachname)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Text('Verträge (${widget.vertraege.length})', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.red.shade800)),
        const Spacer(),
        ElevatedButton.icon(onPressed: () => _add(), icon: const Icon(Icons.add, size: 16), label: const Text('Neuer Vertrag', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white)),
      ])),
      Expanded(child: widget.vertraege.isEmpty
        ? Center(child: Text('Keine Verträge', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: widget.vertraege.length, itemBuilder: (ctx, i) {
            final v = widget.vertraege[i];
            final aktiv = v['status'] != 'gekündigt';
            return Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(
              onTap: () => _openDetail(v),
              leading: CircleAvatar(backgroundColor: aktiv ? Colors.green.shade100 : Colors.grey.shade200, child: Icon(Icons.train, color: aktiv ? Colors.green.shade700 : Colors.grey, size: 20)),
              title: Text('${v['anbieter'] ?? 'Deutschlandticket'} · ${v['preis'] ?? '63'} €/Mo', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: Text('Abo-Nr: ${v['abo_nr'] ?? '—'} · ab ${v['gueltig_ab'] ?? '—'}', style: const TextStyle(fontSize: 11)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: aktiv ? Colors.green.shade100 : Colors.grey.shade200, borderRadius: BorderRadius.circular(12)),
                  child: Text(aktiv ? 'Aktiv' : 'Gekündigt', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: aktiv ? Colors.green.shade800 : Colors.grey.shade700))),
                IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade300), onPressed: () async {
                  await widget.apiService.dticketAction(widget.userId, {'action': 'delete_vertrag', 'id': v['id']}); await widget.onReload(); }),
              ]),
            ));
          })),
    ]);
  }
}

// ==================== VERTRAG DETAIL MODAL ====================
class _VertragDetailModal extends StatefulWidget {
  final Map<String, dynamic> vertrag; final ApiService apiService; final int userId; final Future<void> Function() onReload; final Map<String, dynamic> firmaData; final String userName; final String userNachname;
  const _VertragDetailModal({required this.vertrag, required this.apiService, required this.userId, required this.onReload, required this.firmaData, this.userName = '', this.userNachname = ''});
  @override State<_VertragDetailModal> createState() => _VertragDetailModalState();
}
class _VertragDetailModalState extends State<_VertragDetailModal> with TickerProviderStateMixin {
  late TabController _tabC;
  List<Map<String, dynamic>> _korr = [];
  bool _loading = true;

  @override void initState() { super.initState(); _tabC = TabController(length: 6, vsync: this); _loadDetail(); }
  @override void dispose() { _tabC.dispose(); super.dispose(); }

  Future<void> _loadDetail() async {
    setState(() => _loading = true);
    try { final res = await widget.apiService.getDticketVertragDetail(widget.userId, widget.vertrag['id'] as int);
      if (res['success'] == true) _korr = (res['korrespondenz'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override Widget build(BuildContext context) {
    final v = widget.vertrag;
    return Column(children: [
      Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
        child: Row(children: [Icon(Icons.train, color: Colors.red.shade700), const SizedBox(width: 8),
          Expanded(child: Text('${v['anbieter'] ?? 'Deutschlandticket'}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.red.shade800))),
          IconButton(icon: const Icon(Icons.close), onPressed: () { Navigator.pop(context); widget.onReload(); })])),
      TabBar(controller: _tabC, labelColor: Colors.red.shade800, unselectedLabelColor: Colors.grey, indicatorColor: Colors.red.shade700, isScrollable: true, tabAlignment: TabAlignment.start, tabs: const [
        Tab(text: 'Details'), Tab(text: 'Korrespondenz'), Tab(text: 'Dokumente'), Tab(text: 'Kündigung'), Tab(text: 'Stammdaten'), Tab(text: 'Chipkarte'),
      ]),
      Expanded(child: _loading ? const Center(child: CircularProgressIndicator()) : TabBarView(controller: _tabC, children: [
        _buildDetails(v), _buildKorr(), _buildDoks(v), _buildKuendigung(v), _StammdatenTab(vertrag: v, apiService: widget.apiService, userId: widget.userId, onReload: widget.onReload), _ChipkarteTab(vertrag: v, apiService: widget.apiService, userId: widget.userId, onReload: widget.onReload, firmaData: widget.firmaData, userName: widget.userName, userNachname: widget.userNachname),
      ])),
    ]);
  }

  Widget _buildDetails(Map<String, dynamic> v) {
    Widget r(IconData icon, String label, String value) { if (value.isEmpty) return const SizedBox.shrink();
      return Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [Icon(icon, size: 16, color: Colors.red.shade400), const SizedBox(width: 8), SizedBox(width: 100, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))), Expanded(child: Text(value, style: const TextStyle(fontSize: 13)))])); }
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      r(Icons.business, 'Anbieter', v['anbieter']?.toString() ?? ''), r(Icons.confirmation_number, 'Abo-Nr.', v['abo_nr']?.toString() ?? ''),
      r(Icons.euro, 'Preis', '${v['preis'] ?? '63'} €/Monat'), r(Icons.payment, 'Zahlungsart', v['zahlungsart']?.toString() ?? ''),
      r(Icons.calendar_today, 'Gültig ab', v['gueltig_ab']?.toString() ?? ''), r(Icons.event, 'Gültig bis', v['gueltig_bis']?.toString() ?? ''),
      r(Icons.account_balance, 'IBAN', v['iban']?.toString() ?? ''), r(Icons.flag, 'Status', v['status']?.toString() ?? ''),
      if ((v['notiz']?.toString() ?? '').isNotEmpty) ...[const SizedBox(height: 8), Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)), child: Text(v['notiz'].toString(), style: const TextStyle(fontSize: 13)))],
    ]));
  }

  Widget _buildKorr() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(8), child: Row(children: [
        Text('Korrespondenz (${_korr.length})', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red.shade800)),
        const Spacer(),
        ElevatedButton.icon(onPressed: _addKorr, icon: const Icon(Icons.add, size: 14), label: const Text('Neu', style: TextStyle(fontSize: 11)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4))),
      ])),
      Expanded(child: _korr.isEmpty ? Center(child: Text('Keine Korrespondenz', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(itemCount: _korr.length, itemBuilder: (ctx, i) { final k = _korr[i]; final isEin = k['richtung'] == 'eingang'; final kId = int.tryParse(k['id'].toString()) ?? 0;
            return Card(margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), child: InkWell(
              onTap: () => _openKorrDetail(k),
              child: ListTile(dense: true,
                leading: Icon(isEin ? Icons.call_received : Icons.call_made, color: isEin ? Colors.blue : Colors.orange, size: 20),
                title: Text(k['betreff']?.toString() ?? '(kein Betreff)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                subtitle: Text('${k['datum'] ?? ''} · ${k['methode'] ?? ''}', style: const TextStyle(fontSize: 10)),
                trailing: IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade300), onPressed: () async {
                  await widget.apiService.dticketAction(widget.userId, {'action': 'delete_korr', 'id': k['id']}); await _loadDetail(); }),
              ),
            )); })),
    ]);
  }

  void _openKorrDetail(Map<String, dynamic> k) {
    final kId = int.tryParse(k['id'].toString()) ?? 0; final isEin = k['richtung'] == 'eingang';
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Row(children: [Icon(isEin ? Icons.call_received : Icons.call_made, size: 20, color: isEin ? Colors.blue : Colors.orange), const SizedBox(width: 8),
        Expanded(child: Text(k['betreff']?.toString() ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)))]),
      content: SizedBox(width: 450, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: isEin ? Colors.blue.shade100 : Colors.orange.shade100, borderRadius: BorderRadius.circular(12)),
          child: Text(isEin ? 'Eingang' : 'Ausgang', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isEin ? Colors.blue.shade800 : Colors.orange.shade800))),
          const Spacer(), Text(k['datum']?.toString() ?? '', style: TextStyle(fontSize: 12, color: Colors.grey.shade700))]),
        if ((k['notiz']?.toString() ?? '').isNotEmpty) ...[const SizedBox(height: 12), Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
          child: Text(k['notiz'].toString(), style: const TextStyle(fontSize: 13)))],
        const SizedBox(height: 16), KorrAttachmentsWidget(apiService: widget.apiService, modul: 'dticket_korr', korrespondenzId: kId),
      ]))), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen'))]));
  }

  void _addKorr() {
    String richtung = 'eingang'; String methode = 'E-Mail';
    final datumC = TextEditingController(); final betreffC = TextEditingController(); final notizC = TextEditingController();
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) => AlertDialog(
      title: const Text('Neue Korrespondenz', style: TextStyle(fontSize: 15)),
      content: SizedBox(width: 400, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [ChoiceChip(label: const Text('Eingang'), selected: richtung == 'eingang', onSelected: (_) => setDlg(() => richtung = 'eingang')), const SizedBox(width: 8),
          ChoiceChip(label: const Text('Ausgang'), selected: richtung == 'ausgang', onSelected: (_) => setDlg(() => richtung = 'ausgang'))]),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(value: methode, decoration: InputDecoration(labelText: 'Methode', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          items: const [DropdownMenuItem(value: 'E-Mail', child: Text('E-Mail')), DropdownMenuItem(value: 'Brief', child: Text('Brief')), DropdownMenuItem(value: 'Telefon', child: Text('Telefon')), DropdownMenuItem(value: 'Online', child: Text('Online'))],
          onChanged: (v) => setDlg(() => methode = v ?? methode)),
        const SizedBox(height: 10),
        TextField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', isDense: true, prefixIcon: const Icon(Icons.calendar_today, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          onTap: () async { final d = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (d != null) datumC.text = '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}'; }),
        const SizedBox(height: 10), TextField(controller: betreffC, decoration: InputDecoration(labelText: 'Betreff', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 10), TextField(controller: notizC, maxLines: 3, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () async { Navigator.pop(ctx);
          await widget.apiService.dticketAction(widget.userId, {'action': 'save_korr', 'vertrag_id': widget.vertrag['id'], 'korr': {'richtung': richtung, 'methode': methode, 'datum': datumC.text, 'betreff': betreffC.text, 'notiz': notizC.text}});
          await _loadDetail();
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white), child: const Text('Hinzufügen'))],
    )));
  }

  Widget _buildKuendigung(Map<String, dynamic> v) {
    final gekuendigt = v['status'] == 'gekündigt';
    final now = DateTime.now();
    final deadlineDay = 10;
    final canCancelThisMonth = now.day <= deadlineDay;
    final effectiveMonth = canCancelThisMonth ? now : DateTime(now.year, now.month + 1);
    final effectiveEnd = DateTime(effectiveMonth.year, effectiveMonth.month + 1, 0);
    final deadlineStr = '${deadlineDay.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';
    final effectiveStr = '${effectiveEnd.day.toString().padLeft(2, '0')}.${effectiveEnd.month.toString().padLeft(2, '0')}.${effectiveEnd.year}';

    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (gekuendigt) Container(width: double.infinity, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
        child: Row(children: [Icon(Icons.check_circle, size: 22, color: Colors.grey.shade600), const SizedBox(width: 10),
          Expanded(child: Text('Dieser Vertrag wurde bereits gekündigt.', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade700)))]))
      else ...[
        Container(width: double.infinity, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: canCancelThisMonth ? Colors.green.shade50 : Colors.orange.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: canCancelThisMonth ? Colors.green.shade200 : Colors.orange.shade200)),
          child: Row(children: [
            Icon(canCancelThisMonth ? Icons.check_circle : Icons.warning_amber, size: 22, color: canCancelThisMonth ? Colors.green.shade700 : Colors.orange.shade700),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(canCancelThisMonth ? 'Kündigung noch möglich bis $deadlineStr' : 'Frist verpasst — nächste Kündigung zum ${effectiveEnd.month + 1}.${effectiveEnd.year}',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: canCancelThisMonth ? Colors.green.shade800 : Colors.orange.shade800)),
              Text('Wirksam zum: $effectiveStr', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ])),
          ])),
        const SizedBox(height: 12),
        ElevatedButton.icon(onPressed: () async {
          final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
            title: const Text('Deutschlandticket kündigen?', style: TextStyle(fontSize: 15)),
            content: Text('Die Kündigung wird zum $effectiveStr wirksam.\n\nMöchten Sie fortfahren?'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('Kündigen'))],
          ));
          if (ok != true) return;
          await widget.apiService.dticketAction(widget.userId, {'action': 'save_vertrag', 'vertrag': {...widget.vertrag, 'status': 'gekündigt', 'gueltig_bis': effectiveStr}});
          await widget.onReload();
          if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gekündigt zum $effectiveStr'), backgroundColor: Colors.green.shade600)); }
        }, icon: const Icon(Icons.cancel, size: 18), label: const Text('Jetzt kündigen'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white)),
      ],
      const Divider(height: 24),
      Text('Kündigungsregeln — Deutschlandticket', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
      const SizedBox(height: 12),
      _ruleCard(Icons.calendar_today, 'Kündigungsfrist', 'Bis zum 10. des Monats kündigen — Vertrag endet zum Monatsende.', Colors.blue),
      _ruleCard(Icons.warning_amber, 'Frist verpasst?', 'Nach dem 10. läuft der Vertrag automatisch einen weiteren Monat.', Colors.orange),
      _ruleCard(Icons.all_inclusive, 'Mindestlaufzeit', 'Keine — monatlich kündbar. Ausnahme: Abschluss nach dem 10. = 2 Monate Mindestlaufzeit.', Colors.green),
      _ruleCard(Icons.computer, 'Wie kündigen?', 'Online im Kundenportal (am schnellsten), per E-Mail oder per Post. Immer beim eigenen Anbieter!', Colors.teal),
      _ruleCard(Icons.euro, 'Aktueller Preis', '63 €/Monat (seit Januar 2026). Preisänderungen können Sonderkündigungsrecht auslösen — abhängig vom Anbieter.', Colors.purple),
    ]));
  }

  Widget _ruleCard(IconData icon, String title, String text, MaterialColor color) {
    return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: color.shade200)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: color.shade700),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color.shade800)),
          const SizedBox(height: 2),
          Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.4)),
        ])),
      ]));
  }

  Widget _buildDoks(Map<String, dynamic> v) {
    final vId = int.tryParse(v['id'].toString()) ?? 0;
    return _DticketDokSubTabs(apiService: widget.apiService, vertragId: vId);
  }
}

// ==================== DOKUMENTE SUB-TABS WITH CHECKMARKS ====================
class _DticketDokSubTabs extends StatefulWidget {
  final ApiService apiService; final int vertragId;
  const _DticketDokSubTabs({required this.apiService, required this.vertragId});
  @override State<_DticketDokSubTabs> createState() => _DticketDokSubTabsState();
}
class _DticketDokSubTabsState extends State<_DticketDokSubTabs> with TickerProviderStateMixin {
  late TabController _tabC;
  static const _tabs = [('dticket_vertrag', 'Vertrag'), ('dticket_karte', 'Karte'), ('dticket_bestelschein', 'Bestelschein'), ('dticket_datenschutz', 'Datenschutz'), ('dticket_widerrufsrecht', 'Widerrufsrecht')];
  final Map<String, bool> _hasDocs = {};

  @override void initState() { super.initState(); _tabC = TabController(length: _tabs.length, vsync: this); _loadCounts(); }
  @override void dispose() { _tabC.dispose(); super.dispose(); }

  Future<void> _loadCounts() async {
    for (final t in _tabs) {
      try {
        final res = await widget.apiService.listKorrAttachments(t.$1, widget.vertragId);
        if (res['success'] == true && res['data'] is List && (res['data'] as List).isNotEmpty) {
          if (mounted) setState(() => _hasDocs[t.$1] = true);
        }
      } catch (_) {}
    }
  }

  @override Widget build(BuildContext context) {
    return Column(children: [
      TabBar(controller: _tabC, isScrollable: true, tabAlignment: TabAlignment.start, labelColor: Colors.indigo.shade700, unselectedLabelColor: Colors.grey, indicatorColor: Colors.indigo,
        labelStyle: const TextStyle(fontSize: 11),
        tabs: _tabs.map((t) => Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(t.$2),
          if (_hasDocs[t.$1] == true) ...[const SizedBox(width: 4), Icon(Icons.check_circle, size: 14, color: Colors.green.shade600)],
        ]))).toList()),
      Expanded(child: TabBarView(controller: _tabC, children: _tabs.map((t) =>
        Padding(padding: const EdgeInsets.all(12), child: KorrAttachmentsWidget(apiService: widget.apiService, modul: t.$1, korrespondenzId: widget.vertragId)),
      ).toList())),
    ]);
  }
}

// ==================== STAMMDATEN TAB ====================
class _StammdatenTab extends StatefulWidget {
  final Map<String, dynamic> vertrag; final ApiService apiService; final int userId; final Future<void> Function() onReload;
  const _StammdatenTab({required this.vertrag, required this.apiService, required this.userId, required this.onReload});
  @override State<_StammdatenTab> createState() => _StammdatenTabState();
}
class _StammdatenTabState extends State<_StammdatenTab> {
  late TextEditingController _kundennrC, _codeC;
  bool _editing = false, _saving = false;
  @override
  void initState() { super.initState(); _kundennrC = TextEditingController(text: widget.vertrag['abo_nr']?.toString() ?? ''); _codeC = TextEditingController(text: widget.vertrag['chipkarte_code']?.toString() ?? ''); }
  @override
  void dispose() { _kundennrC.dispose(); _codeC.dispose(); super.dispose(); }
  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.apiService.dticketAction(widget.userId, {'action': 'save_vertrag', 'vertrag': {...widget.vertrag, 'abo_nr': _kundennrC.text.trim(), 'chipkarte_code': _codeC.text.trim()}});
    await widget.onReload();
    if (mounted) { setState(() { _saving = false; _editing = false; }); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Gespeichert'), backgroundColor: Colors.green.shade600)); }
  }
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Stammdaten', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
        const Spacer(),
        TextButton.icon(icon: Icon(_editing ? Icons.lock : Icons.edit, size: 16), label: Text(_editing ? 'Sperren' : 'Bearbeiten', style: const TextStyle(fontSize: 12)), onPressed: () => setState(() => _editing = !_editing)),
      ]),
      const SizedBox(height: 16),
      TextField(controller: _kundennrC, readOnly: !_editing, decoration: InputDecoration(labelText: 'Kundennummer (9 Ziffern)', prefixIcon: const Icon(Icons.badge, size: 20), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), filled: !_editing, fillColor: !_editing ? Colors.grey.shade100 : null), keyboardType: TextInputType.number),
      const SizedBox(height: 12),
      TextField(controller: _codeC, readOnly: !_editing, decoration: InputDecoration(labelText: 'Code (z.B. 1234-56.789.012-3)', prefixIcon: const Icon(Icons.qr_code, size: 20), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), filled: !_editing, fillColor: !_editing ? Colors.grey.shade100 : null)),
      if (_editing) ...[const SizedBox(height: 16), Align(alignment: Alignment.centerRight, child: ElevatedButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 16),
        label: const Text('Speichern'), style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white)))],
    ]));
  }
}

// ==================== CHIPKARTE TAB ====================
class _ChipkarteTab extends StatefulWidget {
  final Map<String, dynamic> vertrag;
  final ApiService apiService;
  final int userId;
  final Future<void> Function() onReload;
  final Map<String, dynamic> firmaData;
  final String userName;
  final String userNachname;
  const _ChipkarteTab({required this.vertrag, required this.apiService, required this.userId, required this.onReload, required this.firmaData, this.userName = '', this.userNachname = ''});
  @override
  State<_ChipkarteTab> createState() => _ChipkarteTabState();
}

class _ChipkarteTabState extends State<_ChipkarteTab> {
  bool _showBack = false;
  late TextEditingController _kundennrC, _codeC;
  String _gueltigMonat = '';
  String _gueltigJahr = '';
  String _vorname = '';
  String _nachname = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final v = widget.vertrag;
    _kundennrC = TextEditingController(text: v['abo_nr']?.toString() ?? '');
    _codeC = TextEditingController(text: v['chipkarte_code']?.toString() ?? '');
    _vorname = v['chipkarte_vorname']?.toString() ?? '';
    _nachname = v['chipkarte_nachname']?.toString() ?? '';
    if (_vorname.isEmpty) _vorname = widget.userName;
    if (_nachname.isEmpty) _nachname = widget.userNachname;
    _gueltigMonat = v['chipkarte_gueltig_monat']?.toString() ?? '';
    _gueltigJahr = v['chipkarte_gueltig_jahr']?.toString() ?? '';
  }

  @override
  void dispose() { _kundennrC.dispose(); _codeC.dispose(); super.dispose(); }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.apiService.dticketAction(widget.userId, {'action': 'save_vertrag', 'vertrag': {
      ...widget.vertrag,
      'chipkarte_vorname': _vorname, 'chipkarte_nachname': _nachname,
      'chipkarte_gueltig_monat': _gueltigMonat, 'chipkarte_gueltig_jahr': _gueltigJahr,
      'chipkarte_code': _codeC.text.trim(), 'abo_nr': _kundennrC.text.trim(),
    }});
    await widget.onReload();
    if (mounted) { setState(() => _saving = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Chipkarte gespeichert'), backgroundColor: Colors.green.shade600)); }
  }

  String _firmaName() => widget.firmaData['stammdaten.selected_firma_name']?.toString() ?? '';
  String _firmaAdresse() { final s = widget.firmaData['stammdaten.selected_firma_strasse']?.toString() ?? ''; final o = widget.firmaData['stammdaten.selected_firma_ort']?.toString() ?? ''; return '$s, $o'.trim(); }
  String _firmaTelefon() => widget.firmaData['stammdaten.selected_firma_telefon']?.toString() ?? '';
  String _firmaKurz() { final n = _firmaName(); if (n.isEmpty) return '?'; final parts = n.split(' '); if (parts.first.length <= 5) return parts.first; return n.substring(0, 3).toUpperCase(); }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(children: [
      // Card with flip
      GestureDetector(
        onTap: () => setState(() => _showBack = !_showBack),
        child: AnimatedSwitcher(duration: const Duration(milliseconds: 400), child: _showBack ? _buildBack() : _buildFront()),
      ),
      const SizedBox(height: 8),
      Text('Tippen zum Umdrehen', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      const SizedBox(height: 16),

      // Edit: only Gültig bis (month/year) — Kundennummer + Code are in Stammdaten tab
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('Gültig bis: ', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
        const SizedBox(width: 8),
        SizedBox(width: 80, child: DropdownButtonFormField<String>(
          value: _gueltigMonat.isEmpty ? null : _gueltigMonat,
          decoration: InputDecoration(labelText: 'Monat', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          items: List.generate(12, (i) => DropdownMenuItem(value: (i + 1).toString().padLeft(2, '0'), child: Text((i + 1).toString().padLeft(2, '0'), style: const TextStyle(fontSize: 13)))),
          onChanged: (v) { setState(() => _gueltigMonat = v ?? ''); _save(); },
        )),
        const SizedBox(width: 8),
        SizedBox(width: 90, child: DropdownButtonFormField<String>(
          value: _gueltigJahr.isEmpty ? null : _gueltigJahr,
          decoration: InputDecoration(labelText: 'Jahr', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          items: List.generate(10, (i) => DropdownMenuItem(value: (2025 + i).toString(), child: Text((2025 + i).toString(), style: const TextStyle(fontSize: 13)))),
          onChanged: (v) { setState(() => _gueltigJahr = v ?? ''); _save(); },
        )),
      ]),
    ]));
  }

  Widget _buildFront() {
    final gueltig = (_gueltigMonat.isNotEmpty && _gueltigJahr.isNotEmpty) ? '$_gueltigMonat/$_gueltigJahr' : '—/—';
    return Container(key: const ValueKey('front'), height: 220, width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(colors: [Color(0xFF1a1a2e), Color(0xFF16213e), Color(0xFF0f3460)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 6))],
      ),
      child: Stack(children: [
        // D-Ticket stripe top
        Positioned(top: 0, left: 0, right: 0, child: Container(height: 44, decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          gradient: LinearGradient(colors: [Colors.red.shade700, Colors.red.shade500, Colors.amber.shade600])),
          child: Row(children: [
            const SizedBox(width: 16),
            // German flag
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(width: 28, height: 6, color: Colors.black),
              Container(width: 28, height: 6, color: Colors.red.shade700),
              Container(width: 28, height: 6, color: Colors.amber.shade600),
            ]),
            const SizedBox(width: 10),
            const Text('D', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1)),
            const Text('-Ticket', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            const Spacer(),
            Text('Deutschlandticket', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.7))),
            const SizedBox(width: 16),
          ]),
        )),
        // Chip
        Positioned(left: 20, top: 56, child: Container(width: 42, height: 32,
          decoration: BoxDecoration(color: Colors.amber.shade300, borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.amber.shade600, width: 1)),
          child: Center(child: Icon(Icons.memory, size: 18, color: Colors.amber.shade800)))),
        // Name
        Positioned(left: 20, bottom: 50, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_vorname.isEmpty ? 'VORNAME' : _vorname.toUpperCase(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.5)),
          Text(_nachname.isEmpty ? 'NACHNAME' : _nachname.toUpperCase(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 2)),
        ])),
        // Kundennummer
        Positioned(left: 20, bottom: 16, child: Text('Nr. ${_kundennrC.text.isEmpty ? '000000000' : _kundennrC.text}',
          style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.7), fontFamily: 'monospace', letterSpacing: 1))),
        // Gültig bis
        Positioned(right: 20, bottom: 16, child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('GÜLTIG BIS', style: TextStyle(fontSize: 8, color: Colors.white.withValues(alpha: 0.5), letterSpacing: 1)),
          Text(gueltig, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'monospace')),
        ])),
        // Contactless icon
        Positioned(right: 20, top: 56, child: Icon(Icons.contactless, size: 28, color: Colors.white.withValues(alpha: 0.5))),
      ]),
    );
  }

  Widget _buildBack() {
    return Container(key: const ValueKey('back'), height: 220, width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(colors: [Color(0xFF0f3460), Color(0xFF16213e), Color(0xFF1a1a2e)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 6))],
      ),
      child: Stack(children: [
        // Magnetic stripe
        Positioned(top: 16, left: 0, right: 0, child: Container(height: 36, color: const Color(0xFF2d2d2d))),
        // Firma from selected Zuständige Firma
        Positioned(top: 60, left: 20, right: 20, child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
            child: Center(child: Text(_firmaKurz(), style: TextStyle(fontSize: _firmaKurz().length > 4 ? 10 : 14, fontWeight: FontWeight.w900, color: Colors.red.shade700)))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_firmaName(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
            Text(_firmaAdresse(), style: TextStyle(fontSize: 9, color: Colors.white.withValues(alpha: 0.6))),
            if (_firmaTelefon().isNotEmpty) Text('Tel: ${_firmaTelefon()}', style: TextStyle(fontSize: 9, color: Colors.white.withValues(alpha: 0.6))),
          ])),
        ])),
        // Unterschrift
        Positioned(top: 116, left: 20, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('UNTERSCHRIFT', style: TextStyle(fontSize: 7, color: Colors.white.withValues(alpha: 0.4), letterSpacing: 1)),
          const SizedBox(height: 2),
          Container(width: 160, height: 28, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.white.withValues(alpha: 0.2)))),
        ])),
        // QR Code placeholder
        Positioned(bottom: 14, left: 20, child: Container(width: 44, height: 44,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
          child: const Center(child: Icon(Icons.qr_code_2, size: 36, color: Colors.black87)))),
        // Code
        Positioned(bottom: 28, left: 74, child: Text(_codeC.text.isEmpty ? '0000-00.000.000-0' : _codeC.text,
          style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.white.withValues(alpha: 0.7), letterSpacing: 0.5))),
        // DING info
        Positioned(bottom: 14, left: 74, child: Text('Es gilt der DING Gemeinschaftstarif  www.ding.eu',
          style: TextStyle(fontSize: 7, color: Colors.white.withValues(alpha: 0.4)))),
        // D-Ticket badge bottom right
        Positioned(bottom: 14, right: 16, child: Row(children: [
          Column(mainAxisSize: MainAxisSize.min, children: [Container(width: 16, height: 4, color: Colors.black), Container(width: 16, height: 4, color: Colors.red.shade700), Container(width: 16, height: 4, color: Colors.amber.shade600)]),
          const SizedBox(width: 4),
          const Text('D-Ticket', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
        ])),
      ]),
    );
  }
}
