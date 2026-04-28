import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'korrespondenz_attachments_widget.dart';

class BehordeDeutschlandticketContent extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  const BehordeDeutschlandticketContent({super.key, required this.apiService, required this.userId});
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
        _FirmaTab(data: _data, apiService: widget.apiService, userId: widget.userId),
        _VertragTab(vertraege: _vertraege, apiService: widget.apiService, userId: widget.userId, onReload: _load),
      ])),
    ]);
  }
}

// ==================== ZUSTÄNDIGE FIRMA ====================
class _FirmaTab extends StatefulWidget {
  final Map<String, dynamic> data; final ApiService apiService; final int userId;
  const _FirmaTab({required this.data, required this.apiService, required this.userId});
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
  final List<Map<String, dynamic>> vertraege; final ApiService apiService; final int userId; final Future<void> Function() onReload;
  const _VertragTab({required this.vertraege, required this.apiService, required this.userId, required this.onReload});
  @override State<_VertragTab> createState() => _VertragTabState();
}
class _VertragTabState extends State<_VertragTab> {
  void _add([Map<String, dynamic>? e]) {
    final isEdit = e != null;
    final anbieterC = TextEditingController(text: e?['anbieter'] ?? ''); final aboC = TextEditingController(text: e?['abo_nr'] ?? '');
    final preisC = TextEditingController(text: e?['preis'] ?? '49,00'); final ibanC = TextEditingController(text: e?['iban'] ?? '');
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
      child: SizedBox(width: double.infinity, height: MediaQuery.of(context).size.height * 0.8, child: _VertragDetailModal(vertrag: v, apiService: widget.apiService, userId: widget.userId, onReload: widget.onReload)),
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
              title: Text('${v['anbieter'] ?? 'Deutschlandticket'} · ${v['preis'] ?? '49'} €/Mo', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
  final Map<String, dynamic> vertrag; final ApiService apiService; final int userId; final Future<void> Function() onReload;
  const _VertragDetailModal({required this.vertrag, required this.apiService, required this.userId, required this.onReload});
  @override State<_VertragDetailModal> createState() => _VertragDetailModalState();
}
class _VertragDetailModalState extends State<_VertragDetailModal> with TickerProviderStateMixin {
  late TabController _tabC;
  List<Map<String, dynamic>> _korr = [];
  bool _loading = true;

  @override void initState() { super.initState(); _tabC = TabController(length: 3, vsync: this); _loadDetail(); }
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
      TabBar(controller: _tabC, labelColor: Colors.red.shade800, unselectedLabelColor: Colors.grey, indicatorColor: Colors.red.shade700, tabs: const [
        Tab(text: 'Details'), Tab(text: 'Korrespondenz'), Tab(text: 'Dokumente'),
      ]),
      Expanded(child: _loading ? const Center(child: CircularProgressIndicator()) : TabBarView(controller: _tabC, children: [
        _buildDetails(v), _buildKorr(), _buildDoks(v),
      ])),
    ]);
  }

  Widget _buildDetails(Map<String, dynamic> v) {
    Widget r(IconData icon, String label, String value) { if (value.isEmpty) return const SizedBox.shrink();
      return Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [Icon(icon, size: 16, color: Colors.red.shade400), const SizedBox(width: 8), SizedBox(width: 100, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))), Expanded(child: Text(value, style: const TextStyle(fontSize: 13)))])); }
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      r(Icons.business, 'Anbieter', v['anbieter']?.toString() ?? ''), r(Icons.confirmation_number, 'Abo-Nr.', v['abo_nr']?.toString() ?? ''),
      r(Icons.euro, 'Preis', '${v['preis'] ?? '49'} €/Monat'), r(Icons.payment, 'Zahlungsart', v['zahlungsart']?.toString() ?? ''),
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

  Widget _buildDoks(Map<String, dynamic> v) {
    final vId = int.tryParse(v['id'].toString()) ?? 0;
    return DefaultTabController(length: 2, child: Column(children: [
      const TabBar(labelColor: Colors.indigo, indicatorColor: Colors.indigo, tabs: [Tab(text: 'Vertrag'), Tab(text: 'Karte')]),
      Expanded(child: TabBarView(children: [
        Padding(padding: const EdgeInsets.all(12), child: KorrAttachmentsWidget(apiService: widget.apiService, modul: 'dticket_vertrag', korrespondenzId: vId)),
        Padding(padding: const EdgeInsets.all(12), child: KorrAttachmentsWidget(apiService: widget.apiService, modul: 'dticket_karte', korrespondenzId: vId)),
      ])),
    ]));
  }
}
