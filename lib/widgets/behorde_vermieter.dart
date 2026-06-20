import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';
import 'file_viewer_dialog.dart';
import 'korrespondenz_attachments_widget.dart';

class BehordeVermieterContent extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  const BehordeVermieterContent({super.key, required this.apiService, required this.userId});
  @override
  State<BehordeVermieterContent> createState() => _BehordeVermieterContentState();
}

class _BehordeVermieterContentState extends State<BehordeVermieterContent> with TickerProviderStateMixin {
  late TabController _tabC;
  Map<String, dynamic> _data = {};
  List<Map<String, dynamic>> _mietvertraege = [], _bescheinigungen = [], _zahlungen = [];
  bool _isLoading = true;

  @override
  void initState() { super.initState(); _tabC = TabController(length: 4, vsync: this); _load(); }
  @override
  void dispose() { _tabC.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final res = await widget.apiService.getVermieterData(widget.userId);
      if (res['success'] == true) {
        _data = Map<String, dynamic>.from(res['data'] ?? {});
        _mietvertraege = (res['mietvertraege'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
        _bescheinigungen = (res['bescheinigungen'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
        _zahlungen = (res['zahlungen'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      TabBar(controller: _tabC, labelColor: Colors.deepPurple.shade800, unselectedLabelColor: Colors.grey, indicatorColor: Colors.deepPurple, isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 8, color: (_data['stammdaten.selected_name'] ?? '').isNotEmpty ? Colors.green : Colors.red),
          const SizedBox(width: 6), const Text('Zuständiger Vermieter'),
        ])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 8, color: _mietvertraege.isNotEmpty ? Colors.green : Colors.red),
          const SizedBox(width: 6), const Text('Mietvertrag'),
        ])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 8, color: _bescheinigungen.isNotEmpty ? Colors.green : Colors.red),
          const SizedBox(width: 6), const Text('Mietbescheinigung'),
        ])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 8, color: _zahlungen.isNotEmpty ? Colors.green : Colors.red),
          const SizedBox(width: 6), const Text('Zahlungen'),
        ])),
      ]),
      Expanded(child: TabBarView(controller: _tabC, children: [
        _VermieterStammdatenTab(key: ValueKey(_data['stammdaten.selected_name'] ?? ''), data: _data, apiService: widget.apiService, userId: widget.userId, onSaved: _load),
        _MietvertragTab(mietvertraege: _mietvertraege, apiService: widget.apiService, userId: widget.userId, onReload: _load),
        _BescheinigungTab(bescheinigungen: _bescheinigungen, apiService: widget.apiService, userId: widget.userId, onReload: _load),
        _ZahlungenTab(zahlungen: _zahlungen, apiService: widget.apiService, userId: widget.userId, onReload: _load),
      ])),
    ]);
  }
}

// ==================== TAB 1: Zuständiger Vermieter ====================
class _VermieterStammdatenTab extends StatefulWidget {
  final Map<String, dynamic> data;
  final ApiService apiService;
  final int userId;
  final VoidCallback? onSaved;
  const _VermieterStammdatenTab({super.key, required this.data, required this.apiService, required this.userId, this.onSaved});
  @override
  State<_VermieterStammdatenTab> createState() => _VermieterStammdatenTabState();
}
class _VermieterStammdatenTabState extends State<_VermieterStammdatenTab> {
  Map<String, dynamic>? _selected;

  @override
  void initState() {
    super.initState();
    final selName = widget.data['stammdaten.selected_name'] ?? '';
    if (selName.isNotEmpty) {
      _selected = {
        'name': selName,
        'strasse': widget.data['stammdaten.selected_strasse'] ?? '',
        'plz': widget.data['stammdaten.selected_plz'] ?? '',
        'ort': widget.data['stammdaten.selected_ort'] ?? '',
        'telefon': widget.data['stammdaten.selected_telefon'] ?? '',
        'email': widget.data['stammdaten.selected_email'] ?? '',
        'website': widget.data['stammdaten.selected_website'] ?? '',
        'typ': widget.data['stammdaten.selected_typ'] ?? '',
        'notiz': widget.data['stammdaten.selected_notiz'] ?? '',
      };
    }
  }

  void _openSearch() {
    final searchC = TextEditingController();
    List<Map<String, dynamic>> all = [];
    List<Map<String, dynamic>> filtered = [];
    bool loading = true;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) {
      if (loading && all.isEmpty) {
        widget.apiService.searchVermieterDatenbank('').then((res) {
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
        title: Row(children: [
          Icon(Icons.apartment, color: Colors.deepPurple.shade700),
          const SizedBox(width: 8),
          const Text('Vermieter auswählen', style: TextStyle(fontSize: 16)),
        ]),
        content: SizedBox(width: 500, height: 400, child: Column(children: [
          TextField(controller: searchC, autofocus: true,
            decoration: InputDecoration(hintText: 'Filter...', prefixIcon: const Icon(Icons.search), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            onChanged: filterList),
          const SizedBox(height: 12),
          if (loading) const LinearProgressIndicator(),
          Expanded(child: filtered.isEmpty
            ? Center(child: Text(loading ? '' : 'Keine Vermieter gefunden', style: TextStyle(color: Colors.grey.shade400)))
            : ListView.builder(itemCount: filtered.length, itemBuilder: (_, i) {
                final s = filtered[i];
                return Card(margin: const EdgeInsets.only(bottom: 6), child: ListTile(
                  leading: CircleAvatar(backgroundColor: Colors.deepPurple.shade100, child: Icon(Icons.apartment, color: Colors.deepPurple.shade700, size: 20)),
                  title: Text(s['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${s['strasse'] ?? ''}, ${s['plz'] ?? ''} ${s['ort'] ?? ''}', style: const TextStyle(fontSize: 11)),
                    if ((s['telefon']?.toString() ?? '').isNotEmpty) Text('Tel: ${s['telefon']}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                    if ((s['typ']?.toString() ?? '').isNotEmpty) Text(s['typ'].toString(), style: TextStyle(fontSize: 10, color: Colors.deepPurple.shade400)),
                  ]),
                  trailing: Icon(Icons.check_circle_outline, color: Colors.deepPurple.shade400),
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
    await widget.apiService.vermieterAction(widget.userId, {'action': 'save_data', 'data': {
      'stammdaten.selected_name': s['name']?.toString() ?? '',
      'stammdaten.selected_strasse': s['strasse']?.toString() ?? '',
      'stammdaten.selected_plz': s['plz']?.toString() ?? '',
      'stammdaten.selected_ort': s['ort']?.toString() ?? '',
      'stammdaten.selected_telefon': s['telefon']?.toString() ?? '',
      'stammdaten.selected_email': s['email']?.toString() ?? '',
      'stammdaten.selected_website': s['website']?.toString() ?? '',
      'stammdaten.selected_typ': s['typ']?.toString() ?? '',
      'stammdaten.selected_notiz': s['notiz']?.toString() ?? '',
    }});
    if (mounted) { setState(() {}); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Vermieter gespeichert'), backgroundColor: Colors.green.shade600)); }
    widget.onSaved?.call();
  }

  Future<void> _clear() async {
    setState(() { _selected = null; });
    await widget.apiService.vermieterAction(widget.userId, {'action': 'save_data', 'data': {
      'stammdaten.selected_name': '', 'stammdaten.selected_strasse': '', 'stammdaten.selected_plz': '',
      'stammdaten.selected_ort': '', 'stammdaten.selected_telefon': '', 'stammdaten.selected_email': '',
      'stammdaten.selected_website': '', 'stammdaten.selected_typ': '', 'stammdaten.selected_notiz': '',
    }});
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_selected == null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.apartment, size: 64, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        Text('Kein Vermieter ausgewählt', style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _openSearch,
          icon: const Icon(Icons.search, size: 20),
          label: const Text('Vermieter suchen'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
        ),
      ]));
    }
    final s = _selected!;
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Zuständiger Vermieter', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade800)),
        const Spacer(),
        TextButton.icon(icon: const Icon(Icons.swap_horiz, size: 16), label: const Text('Ändern', style: TextStyle(fontSize: 12)), onPressed: _openSearch),
      ]),
      const SizedBox(height: 12),
      Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.deepPurple.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.deepPurple.shade200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 48, height: 48, decoration: BoxDecoration(color: Colors.deepPurple.shade100, borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.apartment, color: Colors.deepPurple.shade700, size: 28)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s['name']?.toString() ?? '', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade800)),
              if ((s['typ']?.toString() ?? '').isNotEmpty) Text(s['typ'].toString(), style: TextStyle(fontSize: 11, color: Colors.deepPurple.shade500)),
            ])),
            IconButton(icon: Icon(Icons.close, color: Colors.red.shade400), tooltip: 'Entfernen', onPressed: _clear),
          ]),
          const Divider(height: 20),
          _infoRow(Icons.location_on, 'Adresse', '${s['strasse'] ?? ''}, ${s['plz'] ?? ''} ${s['ort'] ?? ''}'.trim()),
          if ((s['telefon']?.toString() ?? '').isNotEmpty) _infoRow(Icons.phone, 'Telefon', s['telefon'].toString()),
          if ((s['email']?.toString() ?? '').isNotEmpty) _infoRow(Icons.email, 'E-Mail', s['email'].toString()),
          if ((s['website']?.toString() ?? '').isNotEmpty) _infoRow(Icons.language, 'Website', s['website'].toString()),
          if ((s['notiz']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.deepPurple.shade100)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline, size: 16, color: Colors.deepPurple.shade400),
                const SizedBox(width: 8),
                Expanded(child: Text(s['notiz'].toString(), style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
              ])),
          ],
        ]),
      ),
    ]));
  }

  Widget _infoRow(IconData icon, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [
      Icon(icon, size: 16, color: Colors.deepPurple.shade400),
      const SizedBox(width: 8),
      SizedBox(width: 70, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
    ]));
  }
}

// ==================== TAB 2: Mietvertrag ====================
class _MietvertragTab extends StatefulWidget {
  final List<Map<String, dynamic>> mietvertraege;
  final ApiService apiService;
  final int userId;
  final Future<void> Function() onReload;
  const _MietvertragTab({required this.mietvertraege, required this.apiService, required this.userId, required this.onReload});
  @override
  State<_MietvertragTab> createState() => _MietvertragTabState();
}
class _MietvertragTabState extends State<_MietvertragTab> {
  void _add([Map<String, dynamic>? e]) {
    final isEdit = e != null;
    final strasseC = TextEditingController(text: e?['strasse'] ?? '');
    final hausnrC = TextEditingController(text: e?['hausnummer'] ?? '');
    final plzC = TextEditingController(text: e?['plz'] ?? '');
    final ortC = TextEditingController(text: e?['ort'] ?? '');
    final kaltC = TextEditingController(text: e?['kaltmiete'] ?? '');
    final warmC = TextEditingController(text: e?['warmmiete'] ?? '');
    final nkC = TextEditingController(text: e?['nebenkosten'] ?? '');
    final kautionC = TextEditingController(text: e?['kaution'] ?? '');
    // Wohnfläche in m² — relevant für Beratungshilfe §6 BerHG D2 + WBS.
    final qmC = TextEditingController(text: e?['wohnflaeche_qm'] ?? '');
    final faelligC = TextEditingController(text: e?['faelligkeit'] ?? '');
    final beginnC = TextEditingController(text: e?['mietbeginn'] ?? '');
    final endeC = TextEditingController(text: e?['mietende'] ?? '');
    final kuendC = TextEditingController(text: e?['kuendigungsfrist'] ?? '');
    final notizC = TextEditingController(text: e?['notiz'] ?? '');
    String vertragsart = e?['vertragsart'] ?? 'unbefristet';
    String mietobjekt = e?['mietobjekt'] ?? 'wohnung';
    String zahlungsart = e?['zahlungsart'] ?? 'ueberweisung';
    String status = e?['status'] ?? 'aktiv';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) => AlertDialog(
      title: Text(isEdit ? 'Mietvertrag bearbeiten' : 'Neuer Mietvertrag', style: const TextStyle(fontSize: 15)),
      content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          ChoiceChip(label: const Text('Unbefristet'), selected: vertragsart == 'unbefristet', onSelected: (_) => setDlg(() => vertragsart = 'unbefristet')),
          const SizedBox(width: 8),
          ChoiceChip(label: const Text('Befristet'), selected: vertragsart == 'befristet', onSelected: (_) => setDlg(() => vertragsart = 'befristet')),
          const SizedBox(width: 16),
          for (final o in ['wohnung', 'haus', 'zimmer']) ...[ChoiceChip(label: Text(o[0].toUpperCase() + o.substring(1)), selected: mietobjekt == o, onSelected: (_) => setDlg(() => mietobjekt = o)), const SizedBox(width: 4)],
        ]),
        const SizedBox(height: 10),
        Row(children: [Expanded(flex: 3, child: TextField(controller: strasseC, decoration: InputDecoration(labelText: 'Straße', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
          const SizedBox(width: 8), SizedBox(width: 60, child: TextField(controller: hausnrC, decoration: InputDecoration(labelText: 'Nr.', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))))]),
        const SizedBox(height: 8),
        Row(children: [SizedBox(width: 80, child: TextField(controller: plzC, decoration: InputDecoration(labelText: 'PLZ', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
          const SizedBox(width: 8), Expanded(child: TextField(controller: ortC, decoration: InputDecoration(labelText: 'Ort', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))))]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(
            controller: kaltC,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Kaltmiete €', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            onChanged: (_) {
              final k = double.tryParse(kaltC.text.replaceAll(',', '.')) ?? 0;
              final n = double.tryParse(nkC.text.replaceAll(',', '.')) ?? 0;
              if (k > 0 || n > 0) warmC.text = (k + n).toStringAsFixed(2);
            },
          )),
          const SizedBox(width: 8),
          Expanded(child: TextField(
            controller: nkC,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Nebenkosten €', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            onChanged: (_) {
              final k = double.tryParse(kaltC.text.replaceAll(',', '.')) ?? 0;
              final n = double.tryParse(nkC.text.replaceAll(',', '.')) ?? 0;
              if (k > 0 || n > 0) warmC.text = (k + n).toStringAsFixed(2);
            },
          )),
          const SizedBox(width: 8),
          Expanded(child: TextField(
            controller: warmC,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Warmmiete € (= Kalt + NK)',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              suffixIcon: const Icon(Icons.functions, size: 16, color: Colors.grey),
            ),
          )),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: kautionC, decoration: InputDecoration(labelText: 'Kaution €', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
          const SizedBox(width: 8),
          SizedBox(width: 110, child: TextField(
            controller: qmC,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Wohnfläche',
              suffixText: 'm²',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          )),
          const SizedBox(width: 8),
          Expanded(child: DropdownButtonFormField<String>(
            initialValue: (() {
              final t = faelligC.text.trim();
              if (t.isEmpty) return null;
              final m = RegExp(r'(\d{1,2})').firstMatch(t);
              return m?.group(1);
            })(),
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Zahltag (Miete fällig am)',
              isDense: true,
              prefixIcon: const Icon(Icons.event, size: 16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            items: List.generate(31, (i) => (i + 1).toString())
                .map((d) => DropdownMenuItem(value: d, child: Text('$d. des Monats', style: const TextStyle(fontSize: 12))))
                .toList(),
            onChanged: (v) => setDlg(() { if (v != null) faelligC.text = '$v. des Monats'; }),
          )),
        ]),
        const SizedBox(height: 8),
        Row(children: [Expanded(child: TextField(controller: beginnC, readOnly: true, decoration: InputDecoration(labelText: 'Mietbeginn', isDense: true, prefixIcon: const Icon(Icons.calendar_today, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          onTap: () async { final d = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (d != null) beginnC.text = '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}'; })),
          const SizedBox(width: 8), Expanded(child: TextField(controller: endeC, readOnly: true, decoration: InputDecoration(labelText: 'Mietende', isDense: true, prefixIcon: const Icon(Icons.calendar_today, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          onTap: () async { final d = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (d != null) endeC.text = '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}'; }))]),
        const SizedBox(height: 8),
        Row(children: [
          for (final z in ['ueberweisung', 'sepa']) ...[ChoiceChip(label: Text(z == 'sepa' ? 'SEPA-Lastschrift' : 'Überweisung'), selected: zahlungsart == z, onSelected: (_) => setDlg(() => zahlungsart = z)), const SizedBox(width: 8)],
          const SizedBox(width: 16),
          for (final s in ['aktiv', 'gekuendigt', 'beendet']) ...[ChoiceChip(label: Text(s[0].toUpperCase() + s.substring(1)), selected: status == s, onSelected: (_) => setDlg(() => status = s)), const SizedBox(width: 4)],
        ]),
        const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () async {
          final body = {
            if (isEdit) 'id': e['id'], 'vertragsart': vertragsart, 'mietobjekt': mietobjekt, 'strasse': strasseC.text, 'hausnummer': hausnrC.text,
            'plz': plzC.text, 'ort': ortC.text, 'kaltmiete': kaltC.text, 'warmmiete': warmC.text, 'nebenkosten': nkC.text,
            'kaution': kautionC.text, 'wohnflaeche_qm': qmC.text, 'faelligkeit': faelligC.text, 'zahlungsart': zahlungsart, 'mietbeginn': beginnC.text,
            'mietende': endeC.text, 'kuendigungsfrist': kuendC.text, 'status': status, 'notiz': notizC.text,
          };
          final resp = await widget.apiService.vermieterAction(widget.userId, {'action': 'save_mietvertrag', 'mietvertrag': body});
          await widget.onReload();
          if (!ctx.mounted) return;
          Navigator.pop(ctx);
          final newId = resp['id'] is int ? resp['id'] as int : int.tryParse(resp['id']?.toString() ?? '');
          if (newId != null && newId > 0) {
            // Find updated mietvertrag from refreshed list and open detail modal
            final fresh = widget.mietvertraege.firstWhere((mv) => (mv['id'] as int?) == newId, orElse: () => {...body, 'id': newId});
            _openDetail(fresh);
          }
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white), child: Text(isEdit ? 'Speichern' : 'Hinzufügen'))],
    )));
  }

  void _openDetail(Map<String, dynamic> m) {
    showDialog(context: context, builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: SizedBox(
        width: 800, height: 620,
        child: _MietvertragDetailModal(
          mietvertrag: m,
          apiService: widget.apiService,
          userId: widget.userId,
          onEditDetails: () { Navigator.pop(ctx); _add(m); },
          onReload: widget.onReload,
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final statusColors = {'aktiv': Colors.green, 'gekuendigt': Colors.orange, 'beendet': Colors.grey};
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Text('Mietverträge (${widget.mietvertraege.length})', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.deepPurple.shade800)),
        const Spacer(),
        ElevatedButton.icon(onPressed: () => _add(), icon: const Icon(Icons.add, size: 16), label: const Text('Neu', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white)),
      ])),
      Expanded(child: widget.mietvertraege.isEmpty
        ? Center(child: Text('Keine Mietverträge', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: widget.mietvertraege.length, itemBuilder: (ctx, i) {
            final m = widget.mietvertraege[i];
            final st = m['status']?.toString() ?? 'aktiv';
            final color = statusColors[st] ?? Colors.grey;
            return Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(
              onTap: () => _openDetail(m),
              leading: CircleAvatar(backgroundColor: color.shade100, child: Icon(Icons.description, color: color.shade700, size: 20)),
              title: Text('${m['strasse'] ?? ''} ${m['hausnummer'] ?? ''}, ${m['plz'] ?? ''} ${m['ort'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: Text('${m['kaltmiete'] ?? ''} € kalt · ${m['warmmiete'] ?? ''} € warm · ${m['vertragsart'] ?? ''}', style: const TextStyle(fontSize: 11)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: color.shade100, borderRadius: BorderRadius.circular(12)),
                  child: Text(st[0].toUpperCase() + st.substring(1), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color.shade800))),
                IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade300), onPressed: () async {
                  await widget.apiService.vermieterAction(widget.userId, {'action': 'delete_mietvertrag', 'id': m['id']}); await widget.onReload();
                }),
              ]),
            ));
          })),
    ]);
  }
}

// ==================== TAB 3: Mietbescheinigung ====================
class _BescheinigungTab extends StatefulWidget {
  final List<Map<String, dynamic>> bescheinigungen;
  final ApiService apiService;
  final int userId;
  final Future<void> Function() onReload;
  const _BescheinigungTab({required this.bescheinigungen, required this.apiService, required this.userId, required this.onReload});
  @override
  State<_BescheinigungTab> createState() => _BescheinigungTabState();
}
class _BescheinigungTabState extends State<_BescheinigungTab> {
  static const _typLabels = {'wohnungsgeberbescheinigung': 'Wohnungsgeberbescheinigung', 'mietbescheinigung': 'Mietbescheinigung', 'vermieterbestaetigung': 'Vermieterbestätigung', 'nebenkostenabrechnung': 'Nebenkostenabrechnung', 'sonstiges': 'Sonstiges'};
  void _add([Map<String, dynamic>? e]) {
    final isEdit = e != null;
    String typ = e?['typ'] ?? 'mietbescheinigung';
    final datumC = TextEditingController(text: e?['datum'] ?? '');
    final gueltigC = TextEditingController(text: e?['gueltig_bis'] ?? '');
    final notizC = TextEditingController(text: e?['notiz'] ?? '');
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) => AlertDialog(
      title: Text(isEdit ? 'Bescheinigung bearbeiten' : 'Neue Bescheinigung', style: const TextStyle(fontSize: 15)),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(initialValue: typ, decoration: InputDecoration(labelText: 'Typ', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          items: _typLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (v) => setDlg(() => typ = v ?? typ)),
        const SizedBox(height: 10),
        TextField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', isDense: true, prefixIcon: const Icon(Icons.calendar_today, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          onTap: () async { final d = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (d != null) datumC.text = '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}'; }),
        const SizedBox(height: 10),
        TextField(controller: gueltigC, readOnly: true, decoration: InputDecoration(labelText: 'Gültig bis', isDense: true, prefixIcon: const Icon(Icons.event, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          onTap: () async { final d = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (d != null) gueltigC.text = '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}'; }),
        const SizedBox(height: 10),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () async { Navigator.pop(ctx);
          await widget.apiService.vermieterAction(widget.userId, {'action': 'save_bescheinigung', 'bescheinigung': {if (isEdit) 'id': e['id'], 'typ': typ, 'datum': datumC.text, 'gueltig_bis': gueltigC.text, 'notiz': notizC.text}});
          await widget.onReload();
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white), child: Text(isEdit ? 'Speichern' : 'Hinzufügen'))],
    )));
  }
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Text('Bescheinigungen (${widget.bescheinigungen.length})', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.deepPurple.shade800)),
        const Spacer(),
        ElevatedButton.icon(onPressed: () => _add(), icon: const Icon(Icons.add, size: 16), label: const Text('Neu', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white)),
      ])),
      Expanded(child: widget.bescheinigungen.isEmpty
        ? Center(child: Text('Keine Bescheinigungen', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: widget.bescheinigungen.length, itemBuilder: (ctx, i) {
            final b = widget.bescheinigungen[i];
            final bId = int.tryParse(b['id'].toString()) ?? 0;
            return Card(margin: const EdgeInsets.only(bottom: 8), child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(onTap: () => _add(b), dense: true,
                leading: Icon(Icons.verified, color: Colors.deepPurple.shade400, size: 22),
                title: Text(_typLabels[b['typ']] ?? b['typ']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text('${b['datum'] ?? ''}${(b['gueltig_bis']?.toString() ?? '').isNotEmpty ? ' · Gültig bis: ${b['gueltig_bis']}' : ''}', style: const TextStyle(fontSize: 11)),
                trailing: IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade300), onPressed: () async {
                  await widget.apiService.vermieterAction(widget.userId, {'action': 'delete_bescheinigung', 'id': b['id']}); await widget.onReload();
                })),
              Padding(padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8), child: KorrAttachmentsWidget(apiService: widget.apiService, modul: 'vermieter_bescheinigung', korrespondenzId: bId)),
            ]));
          })),
    ]);
  }
}

// ==================== TAB 4: Zahlungen ====================
class _ZahlungenTab extends StatefulWidget {
  final List<Map<String, dynamic>> zahlungen;
  final ApiService apiService;
  final int userId;
  final Future<void> Function() onReload;
  const _ZahlungenTab({required this.zahlungen, required this.apiService, required this.userId, required this.onReload});
  @override
  State<_ZahlungenTab> createState() => _ZahlungenTabState();
}
class _ZahlungenTabState extends State<_ZahlungenTab> {
  static const _statusLabels = {'bezahlt': ('Bezahlt', Colors.green), 'offen': ('Offen', Colors.orange), 'ueberfaellig': ('Überfällig', Colors.red), 'storniert': ('Storniert', Colors.grey)};
  void _add([Map<String, dynamic>? e]) {
    final isEdit = e != null;
    final monatC = TextEditingController(text: e?['monat'] ?? '');
    final betragC = TextEditingController(text: e?['betrag'] ?? '');
    final datumC = TextEditingController(text: e?['datum'] ?? '');
    final notizC = TextEditingController(text: e?['notiz'] ?? '');
    String zahlungsart = e?['zahlungsart'] ?? 'ueberweisung';
    String status = e?['status'] ?? 'bezahlt';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) => AlertDialog(
      title: Text(isEdit ? 'Zahlung bearbeiten' : 'Neue Zahlung', style: const TextStyle(fontSize: 15)),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: monatC, decoration: InputDecoration(labelText: 'Monat', hintText: 'z.B. April 2026', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 10),
        TextField(controller: betragC, decoration: InputDecoration(labelText: 'Betrag €', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        const SizedBox(height: 10),
        Row(children: [for (final z in ['ueberweisung', 'sepa', 'bar']) ...[ChoiceChip(label: Text(z == 'sepa' ? 'SEPA' : z == 'bar' ? 'Bar' : 'Überweisung', style: const TextStyle(fontSize: 11)), selected: zahlungsart == z, onSelected: (_) => setDlg(() => zahlungsart = z)), const SizedBox(width: 6)]]),
        const SizedBox(height: 10),
        TextField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Zahlungsdatum', isDense: true, prefixIcon: const Icon(Icons.calendar_today, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          onTap: () async { final d = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (d != null) datumC.text = '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}'; }),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(initialValue: status, decoration: InputDecoration(labelText: 'Status', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          items: _statusLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value.$1, style: TextStyle(fontSize: 12, color: e.value.$2)))).toList(),
          onChanged: (v) => setDlg(() => status = v ?? status)),
        const SizedBox(height: 10),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () async { Navigator.pop(ctx);
          await widget.apiService.vermieterAction(widget.userId, {'action': 'save_zahlung', 'zahlung': {if (isEdit) 'id': e['id'], 'monat': monatC.text, 'betrag': betragC.text, 'zahlungsart': zahlungsart, 'datum': datumC.text, 'status': status, 'notiz': notizC.text}});
          await widget.onReload();
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white), child: Text(isEdit ? 'Speichern' : 'Hinzufügen'))],
    )));
  }
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Text('Zahlungen (${widget.zahlungen.length})', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.deepPurple.shade800)),
        const Spacer(),
        ElevatedButton.icon(onPressed: () => _add(), icon: const Icon(Icons.add, size: 16), label: const Text('Neu', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white)),
      ])),
      Expanded(child: widget.zahlungen.isEmpty
        ? Center(child: Text('Keine Zahlungen', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: widget.zahlungen.length, itemBuilder: (ctx, i) {
            final z = widget.zahlungen[i];
            final st = z['status']?.toString() ?? 'offen';
            final stInfo = _statusLabels[st] ?? ('Offen', Colors.orange);
            return Card(margin: const EdgeInsets.only(bottom: 6), child: ListTile(onTap: () => _add(z), dense: true,
              leading: Icon(st == 'bezahlt' ? Icons.check_circle : Icons.pending, color: stInfo.$2, size: 22),
              title: Text('${z['monat'] ?? ''} — ${z['betrag'] ?? ''} €', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: Text('${z['datum'] ?? ''} · ${z['zahlungsart'] == 'sepa' ? 'SEPA' : z['zahlungsart'] == 'bar' ? 'Bar' : 'Überweisung'}', style: const TextStyle(fontSize: 11)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: stInfo.$2.shade100, borderRadius: BorderRadius.circular(12)),
                  child: Text(stInfo.$1, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: stInfo.$2.shade800))),
                IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade300), onPressed: () async {
                  await widget.apiService.vermieterAction(widget.userId, {'action': 'delete_zahlung', 'id': z['id']}); await widget.onReload();
                }),
              ]),
            ));
          })),
    ]);
  }
}

// ==================== MIETVERTRAG DETAIL MODAL ====================
// Three tabs: Details (read-only summary with "bearbeiten" button), Mietvertrag (upload contract),
// Nebenkostenabrechnung (per-year, with rechnungsdatum / Abrechnungszeitraum / Fälligkeit / Nachzahlung-Guthaben + amount + file).

class _MietvertragDetailModal extends StatefulWidget {
  final Map<String, dynamic> mietvertrag;
  final ApiService apiService;
  final int userId;
  final VoidCallback onEditDetails;
  final Future<void> Function() onReload;
  const _MietvertragDetailModal({
    required this.mietvertrag,
    required this.apiService,
    required this.userId,
    required this.onEditDetails,
    required this.onReload,
  });
  @override
  State<_MietvertragDetailModal> createState() => _MietvertragDetailModalState();
}

class _MietvertragDetailModalState extends State<_MietvertragDetailModal> with TickerProviderStateMixin {
  late TabController _tabC;
  List<Map<String, dynamic>> _docs = [];
  bool _loading = false;

  @override
  void initState() { super.initState(); _tabC = TabController(length: 3, vsync: this); _loadDocs(); }
  @override
  void dispose() { _tabC.dispose(); super.dispose(); }

  int get _mvId => widget.mietvertrag['id'] is int ? widget.mietvertrag['id'] as int : int.tryParse(widget.mietvertrag['id']?.toString() ?? '') ?? 0;

  Future<void> _loadDocs() async {
    if (_mvId <= 0) return;
    setState(() => _loading = true);
    final r = await widget.apiService.listVermieterDokumente(userId: widget.userId, mietvertragId: _mvId);
    if (!mounted) return;
    final list = (r['dokumente'] ?? []) as List;
    setState(() {
      _docs = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _loading = false;
    });
  }

  List<Map<String, dynamic>> get _mietvertragDocs => _docs.where((d) => d['dokument_typ'] == 'mietvertrag').toList();
  List<Map<String, dynamic>> get _nkaDocs => _docs.where((d) => d['dokument_typ'] == 'nebenkostenabrechnung').toList();

  @override
  Widget build(BuildContext context) {
    final m = widget.mietvertrag;
    final adresse = '${m['strasse'] ?? ''} ${m['hausnummer'] ?? ''}, ${m['plz'] ?? ''} ${m['ort'] ?? ''}'.trim();
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: Colors.deepPurple.shade50, borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
        child: Row(children: [
          Icon(Icons.home_work, color: Colors.deepPurple.shade700),
          const SizedBox(width: 8),
          Expanded(child: Text(adresse, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.deepPurple.shade800), overflow: TextOverflow.ellipsis)),
          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        ]),
      ),
      TabBar(
        controller: _tabC,
        labelColor: Colors.deepPurple.shade800,
        unselectedLabelColor: Colors.grey,
        indicatorColor: Colors.deepPurple.shade700,
        tabs: [
          const Tab(text: 'Details', icon: Icon(Icons.info_outline, size: 18)),
          Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.description, size: 18), const SizedBox(width: 6), Text('Mietvertrag${_mietvertragDocs.isEmpty ? '' : ' (${_mietvertragDocs.length})'}')])),
          Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.receipt_long, size: 18), const SizedBox(width: 6), Text('Nebenkostenabrechnung${_nkaDocs.isEmpty ? '' : ' (${_nkaDocs.length})'}')])),
        ],
      ),
      Expanded(child: TabBarView(controller: _tabC, children: [
        _detailsTab(m),
        _DokumenteTab(
          dokumentTyp: 'mietvertrag',
          mietvertragId: _mvId,
          userId: widget.userId,
          apiService: widget.apiService,
          docs: _mietvertragDocs,
          loading: _loading,
          onReload: _loadDocs,
        ),
        _NkaTab(
          mietvertragId: _mvId,
          userId: widget.userId,
          apiService: widget.apiService,
          docs: _nkaDocs,
          loading: _loading,
          onReload: _loadDocs,
        ),
      ])),
    ]);
  }

  Widget _detailsTab(Map<String, dynamic> m) {
    Widget row(String label, String value, {IconData? icon}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (icon != null) Padding(padding: const EdgeInsets.only(right: 8, top: 2), child: Icon(icon, size: 16, color: Colors.grey.shade600)),
        SizedBox(width: 140, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
        Expanded(child: Text(value.isEmpty ? '–' : value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
      ]),
    );
    String s(k) => (m[k] ?? '').toString();
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Stammdaten', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade800)),
        const Spacer(),
        OutlinedButton.icon(onPressed: widget.onEditDetails, icon: const Icon(Icons.edit, size: 14), label: const Text('Bearbeiten', style: TextStyle(fontSize: 12))),
      ]),
      const Divider(),
      row('Vertragsart', s('vertragsart'), icon: Icons.assignment),
      row('Mietobjekt', s('mietobjekt'), icon: Icons.home),
      row('Adresse', '${s('strasse')} ${s('hausnummer')}, ${s('plz')} ${s('ort')}', icon: Icons.location_on),
      row('Kaltmiete', '${s('kaltmiete')} €', icon: Icons.euro),
      row('Nebenkosten', '${s('nebenkosten')} €', icon: Icons.receipt_long),
      row('Warmmiete', '${s('warmmiete')} €', icon: Icons.functions),
      row('Kaution', '${s('kaution')} €', icon: Icons.savings),
      if (s('wohnflaeche_qm').isNotEmpty)
        row('Wohnfläche', '${s('wohnflaeche_qm')} m²', icon: Icons.square_foot),
      _zahltagRow(m),
      row('Zahlungsart', s('zahlungsart'), icon: Icons.payments),
      row('Mietbeginn', s('mietbeginn'), icon: Icons.event_available),
      row('Mietende', s('mietende'), icon: Icons.event_busy),
      row('Kündigungsfrist', s('kuendigungsfrist'), icon: Icons.timer),
      row('Status', s('status'), icon: Icons.flag),
      if (s('notiz').isNotEmpty) row('Notiz', s('notiz'), icon: Icons.notes),
    ]));
  }

  /// Inline-editable Zahltag row: dropdown 1..31, saves on selection.
  Widget _zahltagRow(Map<String, dynamic> m) {
    final current = (m['faelligkeit'] ?? '').toString();
    final m1 = RegExp(r'(\d{1,2})').firstMatch(current);
    final selected = m1?.group(1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Padding(padding: const EdgeInsets.only(right: 8), child: Icon(Icons.event, size: 16, color: Colors.grey.shade600)),
        SizedBox(width: 140, child: Text('Zahltag', style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: selected,
            isExpanded: true,
            isDense: true,
            decoration: InputDecoration(
              hintText: 'Tag im Monat wählen',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 12, color: Colors.black),
            items: List.generate(31, (i) => (i + 1).toString())
                .map((d) => DropdownMenuItem(value: d, child: Text('$d. des Monats', style: const TextStyle(fontSize: 12))))
                .toList(),
            onChanged: (v) async { if (v != null) await _saveZahltag(v); },
          ),
        ),
      ]),
    );
  }

  Future<void> _saveZahltag(String day) async {
    final newValue = '$day. des Monats';
    final m = widget.mietvertrag;
    // Optimistic update so the UI reflects the change immediately
    setState(() => m['faelligkeit'] = newValue);
    await widget.apiService.vermieterAction(widget.userId, {
      'action': 'save_mietvertrag',
      'mietvertrag': {
        'id': m['id'],
        'vertragsart': m['vertragsart'] ?? '', 'mietobjekt': m['mietobjekt'] ?? '',
        'strasse': m['strasse'] ?? '', 'hausnummer': m['hausnummer'] ?? '',
        'plz': m['plz'] ?? '', 'ort': m['ort'] ?? '',
        'kaltmiete': m['kaltmiete'] ?? '', 'warmmiete': m['warmmiete'] ?? '', 'nebenkosten': m['nebenkosten'] ?? '',
        'kaution': m['kaution'] ?? '', 'faelligkeit': newValue,
        'zahlungsart': m['zahlungsart'] ?? '', 'mietbeginn': m['mietbeginn'] ?? '', 'mietende': m['mietende'] ?? '',
        'kuendigungsfrist': m['kuendigungsfrist'] ?? '', 'status': m['status'] ?? '', 'notiz': m['notiz'] ?? '',
      },
    });
    await widget.onReload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Zahltag auf $newValue gesetzt'),
      backgroundColor: Colors.green.shade600,
      duration: const Duration(seconds: 2),
    ));
  }
}

// ==================== TAB: Mietvertrag-Dokumente (generic upload list) ====================
class _DokumenteTab extends StatelessWidget {
  final String dokumentTyp;
  final int mietvertragId;
  final int userId;
  final ApiService apiService;
  final List<Map<String, dynamic>> docs;
  final bool loading;
  final Future<void> Function() onReload;
  const _DokumenteTab({
    required this.dokumentTyp,
    required this.mietvertragId,
    required this.userId,
    required this.apiService,
    required this.docs,
    required this.loading,
    required this.onReload,
  });

  Future<void> _upload(BuildContext context) async {
    if (mietvertragId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte zuerst Mietvertrag speichern')));
      return;
    }
    final result = await FilePickerHelper.pickFiles(type: FileType.custom, allowedExtensions: ['pdf','jpg','jpeg','png','tiff','bmp'], allowMultiple: true);
    if (result == null || result.files.isEmpty) return;
    int ok = 0; String? lastErr;
    for (final f in result.files.where((f) => f.path != null)) {
      final r = await apiService.uploadVermieterDokument(
        userId: userId, mietvertragId: mietvertragId,
        dokumentTyp: dokumentTyp, filePath: f.path!, fileName: f.name,
      );
      if (r['success'] == true) { ok++; } else { lastErr = r['message']?.toString() ?? 'Upload fehlgeschlagen'; }
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(lastErr == null ? '$ok Datei(en) hochgeladen' : 'Fehler: $lastErr'),
      backgroundColor: lastErr == null ? Colors.green.shade600 : Colors.red.shade600,
    ));
    await onReload();
  }

  Future<void> _view(BuildContext context, Map<String, dynamic> d) async {
    try {
      final resp = await apiService.downloadVermieterDokument(userId: userId, dokumentId: d['id'] as int);
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
      if (!context.mounted) return;
      final shown = await FileViewerDialog.showFromBytes(context, resp.bodyBytes, d['filename']?.toString() ?? 'dokument');
      if (!shown && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Format nicht unterstützt: ${d['filename']}')));
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Öffnen fehlgeschlagen: $e')));
    }
  }

  Future<void> _delete(BuildContext context, Map<String, dynamic> d) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Dokument löschen?', style: TextStyle(fontSize: 15)),
      content: Text(d['filename']?.toString() ?? '', style: const TextStyle(fontSize: 12)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('Löschen')),
      ],
    ));
    if (ok != true) return;
    await apiService.deleteVermieterDokument(userId: userId, dokumentId: d['id'] as int);
    await onReload();
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Icon(Icons.folder_open, size: 20, color: Colors.deepPurple.shade700),
        const SizedBox(width: 8),
        Text('Mietvertrag-Dokumente', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.deepPurple.shade800)),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: () => _upload(context),
          icon: const Icon(Icons.upload_file, size: 16),
          label: const Text('Hochladen', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade600, foregroundColor: Colors.white),
        ),
      ])),
      Expanded(child: loading
        ? const Center(child: CircularProgressIndicator())
        : docs.isEmpty
          ? Center(child: Text('Noch keine Dokumente hochgeladen', style: TextStyle(color: Colors.grey.shade500, fontStyle: FontStyle.italic, fontSize: 12)))
          : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: docs.length, itemBuilder: (ctx, i) {
              final d = docs[i];
              final mime = (d['mime_type'] ?? '').toString();
              return Card(margin: const EdgeInsets.only(bottom: 6), child: ListTile(
                dense: true, visualDensity: VisualDensity.compact,
                leading: Icon(mime.contains('pdf') ? Icons.picture_as_pdf : Icons.image, color: Colors.deepPurple.shade700),
                title: Text(d['filename']?.toString() ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                subtitle: Text('${_fmtSize(d['file_size'] as int)} · ${(d['uploaded_at']?.toString() ?? '').substring(0, 16)}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: Icon(Icons.visibility, size: 18, color: Colors.blue.shade700), tooltip: 'Öffnen', onPressed: () => _view(context, d)),
                  IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400), tooltip: 'Löschen', onPressed: () => _delete(context, d)),
                ]),
              ));
            }),
      ),
    ]);
  }
}

// ==================== TAB: Nebenkostenabrechnung (year-grouped + meta fields) ====================
class _NkaTab extends StatelessWidget {
  final int mietvertragId;
  final int userId;
  final ApiService apiService;
  final List<Map<String, dynamic>> docs;
  final bool loading;
  final Future<void> Function() onReload;
  const _NkaTab({
    required this.mietvertragId,
    required this.userId,
    required this.apiService,
    required this.docs,
    required this.loading,
    required this.onReload,
  });

  /// Group docs by jahr (desc). Years with no docs are shown only if present in selectableYears via "+ Neue NKA".
  Map<int, List<Map<String, dynamic>>> get _byYear {
    final out = <int, List<Map<String, dynamic>>>{};
    for (final d in docs) {
      final j = d['jahr'] is int ? d['jahr'] as int : int.tryParse(d['jahr']?.toString() ?? '');
      if (j == null) continue;
      out.putIfAbsent(j, () => []).add(d);
    }
    return out;
  }

  Future<void> _addNkaDialog(BuildContext context) async {
    if (mietvertragId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte zuerst Mietvertrag speichern')));
      return;
    }
    final now = DateTime.now();
    int jahr = now.year - 1; // NKA covers previous year by default
    final rdC = TextEditingController(text: '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}');
    final vonC = TextEditingController(text: '01.01.${now.year - 1}');
    final bisC = TextEditingController(text: '31.12.${now.year - 1}');
    // Default Fälligkeit = today + 30 days
    final due = now.add(const Duration(days: 30));
    final fC = TextEditingController(text: '${due.day.toString().padLeft(2, '0')}.${due.month.toString().padLeft(2, '0')}.${due.year}');
    final betragC = TextEditingController();
    final notizC = TextEditingController();
    String typ = 'nachzahlung';
    final picked = <PlatformFile>[];

    await showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) => AlertDialog(
      title: Row(children: [Icon(Icons.receipt_long, size: 18, color: Colors.deepPurple.shade700), const SizedBox(width: 8), const Text('Neue Nebenkostenabrechnung', style: TextStyle(fontSize: 15))]),
      content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: DropdownButtonFormField<int>(
            initialValue: jahr,
            decoration: InputDecoration(labelText: 'Abrechnungsjahr', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: List.generate(now.year + 2 - 2025 + 1, (i) => 2025 + i).reversed.map((y) => DropdownMenuItem(value: y, child: Text('$y'))).toList(),
            onChanged: (v) {
              if (v == null) return;
              setDlg(() {
                jahr = v;
                vonC.text = '01.01.$jahr';
                bisC.text = '31.12.$jahr';
              });
            },
          )),
          const SizedBox(width: 8),
          Expanded(child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'nachzahlung', label: Text('Nachzahl.', style: TextStyle(fontSize: 11)), icon: Icon(Icons.arrow_upward, size: 14)),
              ButtonSegment(value: 'guthaben', label: Text('Guthaben', style: TextStyle(fontSize: 11)), icon: Icon(Icons.arrow_downward, size: 14)),
            ],
            selected: {typ},
            onSelectionChanged: (s) => setDlg(() => typ = s.first),
          )),
        ]),
        const SizedBox(height: 10),
        TextField(controller: rdC, readOnly: true, decoration: InputDecoration(labelText: 'Rechnungsdatum', isDense: true, prefixIcon: const Icon(Icons.calendar_today, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          onTap: () async { final d = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2099), locale: const Locale('de')); if (d != null) rdC.text = '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}'; }),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: vonC, readOnly: true, decoration: InputDecoration(labelText: 'Zeitraum von', isDense: true, prefixIcon: const Icon(Icons.event, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            onTap: () async { final d = await showDatePicker(context: ctx2, initialDate: DateTime(jahr, 1, 1), firstDate: DateTime(2000), lastDate: DateTime(2099), locale: const Locale('de')); if (d != null) vonC.text = '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}'; })),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: bisC, readOnly: true, decoration: InputDecoration(labelText: 'Zeitraum bis', isDense: true, prefixIcon: const Icon(Icons.event, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            onTap: () async { final d = await showDatePicker(context: ctx2, initialDate: DateTime(jahr, 12, 31), firstDate: DateTime(2000), lastDate: DateTime(2099), locale: const Locale('de')); if (d != null) bisC.text = '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}'; })),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: fC, readOnly: true, decoration: InputDecoration(labelText: 'Fälligkeit (Zahlungsfrist)', isDense: true, prefixIcon: const Icon(Icons.schedule, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            onTap: () async { final d = await showDatePicker(context: ctx2, initialDate: due, firstDate: DateTime(2020), lastDate: DateTime(2099), locale: const Locale('de')); if (d != null) fC.text = '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}'; })),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: betragC, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Betrag €', isDense: true, prefixIcon: const Icon(Icons.euro, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
        ]),
        const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz (optional)', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: () async {
              final r = await FilePickerHelper.pickFiles(type: FileType.custom, allowedExtensions: ['pdf','jpg','jpeg','png','tiff','bmp'], allowMultiple: true);
              if (r != null && r.files.isNotEmpty) {
                final keep = r.files.where((f) => f.path != null);
                setDlg(() {
                  final existingPaths = picked.map((p) => p.path).toSet();
                  for (final f in keep) { if (!existingPaths.contains(f.path)) picked.add(f); }
                });
              }
            },
            icon: Icon(picked.isEmpty ? Icons.attach_file : Icons.add, color: picked.isEmpty ? null : Colors.green),
            label: Text(picked.isEmpty ? 'Dateien auswählen (PDF/JPG, mehrere möglich)' : '${picked.length} Datei(en) ausgewählt — weitere hinzufügen', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
          )),
        ]),
        if (picked.isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: picked.asMap().entries.map((entry) => Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(children: [
              Icon(Icons.insert_drive_file, size: 14, color: Colors.deepPurple.shade400),
              const SizedBox(width: 4),
              Expanded(child: Text(entry.value.name, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
              InkWell(
                onTap: () => setDlg(() => picked.removeAt(entry.key)),
                child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.close, size: 14, color: Colors.red.shade400)),
              ),
            ]),
          )).toList()),
        ),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: picked.isEmpty ? null : () async {
          Navigator.pop(ctx);
          int ok = 0; String? lastErr;
          for (final f in picked) {
            if (f.path == null) continue;
            final r = await apiService.uploadVermieterDokument(
              userId: userId, mietvertragId: mietvertragId,
              dokumentTyp: 'nebenkostenabrechnung', jahr: jahr,
              rechnungsdatum: rdC.text, zeitraumVon: vonC.text, zeitraumBis: bisC.text,
              faelligkeit: fC.text, nkaTyp: typ, betrag: betragC.text, notiz: notizC.text,
              filePath: f.path!, fileName: f.name,
            );
            if (r['success'] == true) { ok++; } else { lastErr = r['message']?.toString() ?? 'Upload fehlgeschlagen'; }
          }
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(lastErr == null ? '$ok Nebenkostenabrechnung(en) gespeichert' : 'Fehler: $lastErr'),
            backgroundColor: lastErr == null ? Colors.green.shade700 : Colors.red.shade600,
          ));
          await onReload();
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white), child: const Text('Speichern')),
      ],
    )));
  }

  Future<void> _view(BuildContext context, Map<String, dynamic> d) async {
    try {
      final resp = await apiService.downloadVermieterDokument(userId: userId, dokumentId: d['id'] as int);
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
      if (!context.mounted) return;
      await FileViewerDialog.showFromBytes(context, resp.bodyBytes, d['filename']?.toString() ?? 'dokument');
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Öffnen fehlgeschlagen: $e')));
    }
  }

  Future<void> _delete(BuildContext context, Map<String, dynamic> d) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('NKA löschen?', style: TextStyle(fontSize: 15)),
      content: Text('Jahr ${d['jahr']} — ${d['filename']}', style: const TextStyle(fontSize: 12)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('Löschen')),
      ],
    ));
    if (ok != true) return;
    await apiService.deleteVermieterDokument(userId: userId, dokumentId: d['id'] as int);
    await onReload();
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _byYear;
    final years = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Icon(Icons.receipt_long, size: 20, color: Colors.deepPurple.shade700),
        const SizedBox(width: 8),
        Text('Nebenkostenabrechnung nach Jahr', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.deepPurple.shade800)),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: () => _addNkaDialog(context),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Neue NKA', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
        ),
      ])),
      Expanded(child: loading
        ? const Center(child: CircularProgressIndicator())
        : years.isEmpty
          ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.receipt_long, size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 8),
              Text('Noch keine Nebenkostenabrechnungen', style: TextStyle(color: Colors.grey.shade500, fontStyle: FontStyle.italic, fontSize: 13)),
              const SizedBox(height: 6),
              Text('Beim Hinzufügen wählen Sie das Abrechnungsjahr,\nRechnungsdatum, Zeitraum, Fälligkeit, Betrag und Typ.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
            ])))
          : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: years.length, itemBuilder: (ctx, i) {
              final y = years[i];
              final items = grouped[y]!;
              // All docs for the same Abrechnungsjahr belong to ONE NKA (a single
              // Abrechnung often comes with multiple PDFs / pages / annexes).
              // Show one card per year with the meta once and all files listed below.
              return _NkaYearCard(
                year: y,
                docs: items,
                initiallyExpanded: i == 0,
                onView: (d) => _view(context, d),
                onDelete: (d) => _delete(context, d),
              );
            }),
      ),
    ]);
  }
}

/// One NKA per Abrechnungsjahr — meta shown once, all attached files listed below.
class _NkaYearCard extends StatelessWidget {
  final int year;
  final List<Map<String, dynamic>> docs;
  final bool initiallyExpanded;
  final void Function(Map<String, dynamic>) onView;
  final void Function(Map<String, dynamic>) onDelete;
  const _NkaYearCard({
    required this.year,
    required this.docs,
    required this.initiallyExpanded,
    required this.onView,
    required this.onDelete,
  });

  /// Meta is taken from the first uploaded doc — they all share the same NKA
  /// (rechnungsdatum / zeitraum / fälligkeit / betrag / typ / notiz are written
  /// identically by the upload dialog for every file in the same submission).
  /// We prefer a doc that actually has meta filled in over an empty one.
  Map<String, dynamic> get _metaDoc {
    final withMeta = docs.firstWhere(
      (d) => (d['nka_typ'] ?? '').toString().isNotEmpty || (d['betrag'] ?? '').toString().isNotEmpty,
      orElse: () => docs.first,
    );
    return withMeta;
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final meta = _metaDoc;
    final typ = (meta['nka_typ'] ?? '').toString();
    final isNach = typ == 'nachzahlung';
    final typColor = typ.isEmpty ? Colors.grey : (isNach ? Colors.red : Colors.green);
    final betrag = (meta['betrag'] ?? '').toString();
    final rd = (meta['rechnungsdatum'] ?? '').toString();
    final zv = (meta['zeitraum_von'] ?? '').toString();
    final zb = (meta['zeitraum_bis'] ?? '').toString();
    final faellig = (meta['faelligkeit'] ?? '').toString();
    final notiz = (meta['notiz'] ?? '').toString();

    Widget metaRow(IconData icon, String label, String value) => Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 12, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        SizedBox(width: 110, child: Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade700))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500))),
      ]),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        leading: CircleAvatar(backgroundColor: Colors.deepPurple.shade100, child: Text('$year', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade800))),
        title: Row(children: [
          Expanded(child: Text('Abrechnungsjahr $year', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
          if (typ.isNotEmpty) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: typColor.shade100, borderRadius: BorderRadius.circular(10)), child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(isNach ? Icons.arrow_upward : Icons.arrow_downward, size: 11, color: typColor.shade800),
            const SizedBox(width: 2),
            Text(isNach ? 'Nachzahlung' : 'Guthaben', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: typColor.shade800)),
          ])),
        ]),
        subtitle: Row(children: [
          if (betrag.isNotEmpty) ...[
            Icon(Icons.euro, size: 12, color: typColor.shade700),
            const SizedBox(width: 2),
            Text('$betrag €', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: typColor.shade900)),
            const SizedBox(width: 8),
          ],
          Icon(Icons.folder_open, size: 12, color: Colors.grey.shade600),
          const SizedBox(width: 2),
          Text('${docs.length} Datei(en)', style: const TextStyle(fontSize: 11)),
        ]),
        childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        children: [
          // Meta block (once per NKA)
          if (rd.isNotEmpty || zv.isNotEmpty || zb.isNotEmpty || faellig.isNotEmpty || notiz.isNotEmpty) Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (rd.isNotEmpty) metaRow(Icons.calendar_today, 'Rechnungsdatum', rd),
              if (zv.isNotEmpty || zb.isNotEmpty) metaRow(Icons.event, 'Zeitraum', '${zv.isEmpty ? '?' : zv} – ${zb.isEmpty ? '?' : zb}'),
              if (faellig.isNotEmpty) metaRow(Icons.schedule, 'Fällig bis', faellig),
              if (notiz.isNotEmpty) metaRow(Icons.notes, 'Notiz', notiz),
            ]),
          ),
          const SizedBox(height: 8),
          // Files block
          Row(children: [
            Icon(Icons.attach_file, size: 14, color: Colors.grey.shade700),
            const SizedBox(width: 4),
            Text('Beigefügte Dateien:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          ]),
          const SizedBox(height: 4),
          ...docs.map((d) {
            final mime = (d['mime_type'] ?? '').toString();
            final filename = (d['filename'] ?? '').toString();
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey.shade200)),
                child: Row(children: [
                  Icon(mime.contains('pdf') ? Icons.picture_as_pdf : Icons.image, size: 16, color: Colors.deepPurple.shade700),
                  const SizedBox(width: 6),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(filename, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                    Text(_fmtSize(d['file_size'] as int), style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
                  ])),
                  IconButton(icon: Icon(Icons.visibility, size: 16, color: Colors.blue.shade700), tooltip: 'Öffnen', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28), onPressed: () => onView(d)),
                  IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), tooltip: 'Löschen', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28), onPressed: () => onDelete(d)),
                ]),
              ),
            );
          }),
        ],
      ),
    );
  }
}
