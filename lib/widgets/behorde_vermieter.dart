import 'package:flutter/material.dart';
import '../services/api_service.dart';
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
      TabBar(controller: _tabC, labelColor: Colors.deepPurple.shade800, unselectedLabelColor: Colors.grey, indicatorColor: Colors.deepPurple, isScrollable: true, tabAlignment: TabAlignment.start, tabs: const [
        Tab(text: 'Zuständiger Vermieter'),
        Tab(text: 'Mietvertrag'),
        Tab(text: 'Mietbescheinigung'),
        Tab(text: 'Zahlungen'),
      ]),
      Expanded(child: TabBarView(controller: _tabC, children: [
        _VermieterStammdatenTab(data: _data, apiService: widget.apiService, userId: widget.userId),
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
  const _VermieterStammdatenTab({required this.data, required this.apiService, required this.userId});
  @override
  State<_VermieterStammdatenTab> createState() => _VermieterStammdatenTabState();
}
class _VermieterStammdatenTabState extends State<_VermieterStammdatenTab> {
  Map<String, dynamic>? _selected;
  bool _saving = false;

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
        }).catchError((_) => setDlg(() => loading = false));
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
    setState(() { _selected = s; _saving = true; });
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
    if (mounted) { setState(() => _saving = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Vermieter gespeichert'), backgroundColor: Colors.green.shade600)); }
  }

  Future<void> _clear() async {
    setState(() { _selected = null; _saving = true; });
    await widget.apiService.vermieterAction(widget.userId, {'action': 'save_data', 'data': {
      'stammdaten.selected_name': '', 'stammdaten.selected_strasse': '', 'stammdaten.selected_plz': '',
      'stammdaten.selected_ort': '', 'stammdaten.selected_telefon': '', 'stammdaten.selected_email': '',
      'stammdaten.selected_website': '', 'stammdaten.selected_typ': '', 'stammdaten.selected_notiz': '',
    }});
    if (mounted) setState(() => _saving = false);
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
        Row(children: [Expanded(child: TextField(controller: kaltC, decoration: InputDecoration(labelText: 'Kaltmiete €', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
          const SizedBox(width: 8), Expanded(child: TextField(controller: warmC, decoration: InputDecoration(labelText: 'Warmmiete €', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
          const SizedBox(width: 8), Expanded(child: TextField(controller: nkC, decoration: InputDecoration(labelText: 'Nebenkosten €', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))))]),
        const SizedBox(height: 8),
        Row(children: [Expanded(child: TextField(controller: kautionC, decoration: InputDecoration(labelText: 'Kaution €', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
          const SizedBox(width: 8), Expanded(child: TextField(controller: faelligC, decoration: InputDecoration(labelText: 'Fälligkeit', hintText: 'z.B. 1. des Monats', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))))]),
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
        ElevatedButton(onPressed: () async { Navigator.pop(ctx);
          await widget.apiService.vermieterAction(widget.userId, {'action': 'save_mietvertrag', 'mietvertrag': {
            if (isEdit) 'id': e['id'], 'vertragsart': vertragsart, 'mietobjekt': mietobjekt, 'strasse': strasseC.text, 'hausnummer': hausnrC.text,
            'plz': plzC.text, 'ort': ortC.text, 'kaltmiete': kaltC.text, 'warmmiete': warmC.text, 'nebenkosten': nkC.text,
            'kaution': kautionC.text, 'faelligkeit': faelligC.text, 'zahlungsart': zahlungsart, 'mietbeginn': beginnC.text,
            'mietende': endeC.text, 'kuendigungsfrist': kuendC.text, 'status': status, 'notiz': notizC.text,
          }}); await widget.onReload();
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white), child: Text(isEdit ? 'Speichern' : 'Hinzufügen'))],
    )));
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
              onTap: () => _add(m),
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
        DropdownButtonFormField<String>(value: typ, decoration: InputDecoration(labelText: 'Typ', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
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
        DropdownButtonFormField<String>(value: status, decoration: InputDecoration(labelText: 'Status', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
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
