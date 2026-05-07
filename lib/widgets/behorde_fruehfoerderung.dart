import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'korrespondenz_attachments_widget.dart';

class BehordeFruehfoerderungContent extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  const BehordeFruehfoerderungContent({super.key, required this.apiService, required this.userId});
  @override
  State<BehordeFruehfoerderungContent> createState() => _State();
}

class _State extends State<BehordeFruehfoerderungContent> {
  bool _loading = true;
  List<Map<String, dynamic>> _instances = [];
  int _selectedIdx = 0;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final res = await widget.apiService.fruehfoerderungAction({'action': 'get', 'user_id': widget.userId});
      if (res['success'] == true && res['instances'] is List) {
        _instances = List<Map<String, dynamic>>.from((res['instances'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      _buildInstanceBar(),
      Expanded(child: _instances.isEmpty
        ? _buildEmpty()
        : _buildStelleContent(_instances[_selectedIdx])),
    ]);
  }

  Widget _buildInstanceBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.teal.shade50, border: Border(bottom: BorderSide(color: Colors.teal.shade200))),
      child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
        for (int i = 0; i < _instances.length; i++) ...[
          Padding(padding: const EdgeInsets.only(right: 4), child: InkWell(
            onTap: () => setState(() => _selectedIdx = i),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _selectedIdx == i ? Colors.teal.shade600 : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                border: Border.all(color: _selectedIdx == i ? Colors.teal.shade600 : Colors.teal.shade200),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.psychology, size: 14, color: _selectedIdx == i ? Colors.white : Colors.teal.shade700),
                const SizedBox(width: 6),
                Text(
                  (_instances[i]['stelle_name']?.toString() ?? '').isNotEmpty ? _instances[i]['stelle_name'].toString() : 'Frühförderstelle ${i + 1}',
                  style: TextStyle(fontSize: 12, fontWeight: _selectedIdx == i ? FontWeight.bold : FontWeight.normal, color: _selectedIdx == i ? Colors.white : Colors.teal.shade700),
                ),
              ]),
            ),
          )),
        ],
        Padding(padding: const EdgeInsets.only(left: 4), child: InkWell(
          onTap: _addInstance,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Colors.teal.shade100, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.teal.shade300)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.add, size: 16, color: Colors.teal.shade700),
              const SizedBox(width: 4),
              Text('Weitere Stelle', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.teal.shade700)),
            ]),
          ),
        )),
      ])),
    );
  }

  Widget _buildEmpty() {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.psychology, size: 48, color: Colors.grey.shade300),
      const SizedBox(height: 12),
      Text('Keine Frühförderstelle zugewiesen', style: TextStyle(fontSize: 15, color: Colors.grey.shade500)),
      const SizedBox(height: 16),
      FilledButton.icon(onPressed: _addInstance, icon: const Icon(Icons.add, size: 18), label: const Text('Stelle hinzufügen'),
        style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade600)),
    ]));
  }

  void _addInstance() {
    final newNr = _instances.isEmpty ? 1 : (_instances.last['instance_nr'] as int? ?? _instances.length) + 1;
    _searchStelle(newNr);
  }

  Widget _buildStelleContent(Map<String, dynamic> inst) {
    final name = inst['stelle_name']?.toString() ?? '';
    final nr = inst['instance_nr'] as int? ?? 1;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (name.isEmpty) ...[
          Center(child: FilledButton.icon(onPressed: () => _searchStelle(nr), icon: const Icon(Icons.search, size: 16), label: const Text('Frühförderstelle suchen'),
            style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade600))),
        ] else ...[
          InkWell(
            onTap: () => _showStelleModal(inst),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity, padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.teal.shade200)),
              child: Row(children: [
                CircleAvatar(backgroundColor: Colors.teal.shade100, radius: 22, child: Icon(Icons.psychology, color: Colors.teal.shade700, size: 22)),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
                  if ((inst['stelle_strasse']?.toString() ?? '').isNotEmpty)
                    Text('${inst['stelle_strasse']}, ${inst['stelle_plz_ort'] ?? ''}', style: TextStyle(fontSize: 12, color: Colors.teal.shade700)),
                  if ((inst['stelle_telefon']?.toString() ?? '').isNotEmpty)
                    Text('Tel: ${inst['stelle_telefon']}', style: TextStyle(fontSize: 12, color: Colors.teal.shade600)),
                ])),
                Icon(Icons.chevron_right, color: Colors.teal.shade400),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Text('Klicken für Details, Anfragen & Vorfälle', style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
          const SizedBox(height: 16),
          Row(children: [
            FilledButton.icon(onPressed: () => _searchStelle(nr), icon: const Icon(Icons.swap_horiz, size: 16), label: const Text('Ändern', style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade600, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero)),
            if (nr > 1) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(onPressed: () async {
                await widget.apiService.fruehfoerderungAction({'action': 'delete_instance', 'user_id': widget.userId, 'instance_nr': nr});
                _selectedIdx = 0;
                _load();
              }, icon: Icon(Icons.delete, size: 16, color: Colors.red.shade400), label: Text('Entfernen', style: TextStyle(fontSize: 12, color: Colors.red.shade400))),
            ],
          ]),
        ],
      ]),
    );
  }

  void _showStelleModal(Map<String, dynamic> inst) {
    final nr = inst['instance_nr'] as int? ?? 1;
    showDialog(context: context, builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ClipRRect(borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: MediaQuery.of(ctx).size.width * 0.8,
          height: MediaQuery.of(ctx).size.height * 0.8,
          child: _StelleDetailModal(apiService: widget.apiService, userId: widget.userId, instanceNr: nr, inst: inst),
        )),
    ));
  }

  void _searchStelle(int instanceNr) async {
    final searchC = TextEditingController();
    List<Map<String, dynamic>> results = [];
    bool loading = false;
    final selected = await showDialog<Map<String, dynamic>>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) {
      Future<void> doSearch() async {
        setDlg(() => loading = true);
        try {
          final res = await widget.apiService.fruehfoerderungAction({'action': 'search_stellen', 'search': searchC.text.trim()});
          if (res['success'] == true && res['stellen'] is List) {
            results = List<Map<String, dynamic>>.from((res['stellen'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
          }
        } catch (_) {}
        setDlg(() => loading = false);
      }
      return AlertDialog(
        title: Row(children: [Icon(Icons.psychology, size: 20, color: Colors.teal.shade700), const SizedBox(width: 8), const Text('Frühförderstelle suchen', style: TextStyle(fontSize: 15))]),
        content: SizedBox(width: 500, height: 400, child: Column(children: [
          TextField(controller: searchC, autofocus: true,
            decoration: InputDecoration(hintText: 'Name oder Ort...', isDense: true, prefixIcon: const Icon(Icons.search, size: 18),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: doSearch)),
            onSubmitted: (_) => doSearch()),
          const SizedBox(height: 12),
          Expanded(child: loading
            ? const Center(child: CircularProgressIndicator())
            : results.isEmpty
              ? Center(child: Text(searchC.text.isEmpty ? 'Suchbegriff eingeben' : 'Keine Ergebnisse', style: TextStyle(color: Colors.grey.shade400)))
              : ListView.builder(itemCount: results.length, itemBuilder: (_, i) {
                  final s = results[i];
                  return Card(child: ListTile(
                    onTap: () => Navigator.pop(ctx, s),
                    leading: CircleAvatar(backgroundColor: Colors.teal.shade50, child: Icon(Icons.psychology, color: Colors.teal.shade700, size: 20)),
                    title: Text(s['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if ((s['strasse']?.toString() ?? '').isNotEmpty) Text('${s['strasse']}, ${s['plz_ort'] ?? ''}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      if ((s['telefon']?.toString() ?? '').isNotEmpty) Text('Tel: ${s['telefon']}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    ]),
                  ));
                })),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen'))],
      );
    }));
    if (selected != null && mounted) {
      await widget.apiService.fruehfoerderungAction({
        'action': 'save', 'user_id': widget.userId, 'instance_nr': instanceNr,
        'data': {
          'stelle_name': selected['name'] ?? '', 'stelle_strasse': selected['strasse'] ?? '',
          'stelle_plz_ort': selected['plz_ort'] ?? '', 'stelle_telefon': selected['telefon'] ?? '',
          'stelle_email': selected['email'] ?? '',
        },
      });
      await _load();
      setState(() => _selectedIdx = _instances.indexWhere((i) => i['instance_nr'] == instanceNr).clamp(0, _instances.length - 1));
    }
  }
}

// ===== STELLE DETAIL MODAL =====
class _StelleDetailModal extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int instanceNr;
  final Map<String, dynamic> inst;
  const _StelleDetailModal({required this.apiService, required this.userId, required this.instanceNr, required this.inst});
  @override
  State<_StelleDetailModal> createState() => _StelleDetailModalState();
}

class _StelleDetailModalState extends State<_StelleDetailModal> {
  List<Map<String, dynamic>> _anfragen = [];
  List<Map<String, dynamic>> _vorfaelle = [];
  bool _loadingA = true, _loadingV = true;

  @override
  void initState() { super.initState(); _loadAll(); }

  Future<void> _loadAll() async { _loadAnfragen(); _loadVorfaelle(); }

  Future<void> _loadAnfragen() async {
    try {
      final res = await widget.apiService.fruehfoerderungAction({'action': 'list_anfragen', 'user_id': widget.userId, 'instance_nr': widget.instanceNr});
      if (res['success'] == true && res['anfragen'] is List) _anfragen = List<Map<String, dynamic>>.from((res['anfragen'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
    } catch (_) {}
    if (mounted) setState(() => _loadingA = false);
  }

  Future<void> _loadVorfaelle() async {
    try {
      final res = await widget.apiService.fruehfoerderungAction({'action': 'list_vorfaelle', 'user_id': widget.userId, 'instance_nr': widget.instanceNr});
      if (res['success'] == true && res['vorfaelle'] is List) _vorfaelle = List<Map<String, dynamic>>.from((res['vorfaelle'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
    } catch (_) {}
    if (mounted) setState(() => _loadingV = false);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(length: 3, child: Column(children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.teal.shade600, Colors.teal.shade800])),
        child: Row(children: [
          const Icon(Icons.psychology, size: 24, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.inst['stelle_name']?.toString() ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            if ((widget.inst['stelle_plz_ort']?.toString() ?? '').isNotEmpty)
              Text(widget.inst['stelle_plz_ort'].toString(), style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8))),
          ])),
          IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
        ]),
      ),
      TabBar(labelColor: Colors.teal.shade700, unselectedLabelColor: Colors.grey.shade500, indicatorColor: Colors.teal.shade700, tabs: [
        const Tab(icon: Icon(Icons.info, size: 16), text: 'Details'),
        Tab(icon: const Icon(Icons.question_answer, size: 16), text: 'Anfragen (${_loadingA ? '...' : _anfragen.length})'),
        Tab(icon: const Icon(Icons.warning, size: 16), text: 'Vorfälle (${_loadingV ? '...' : _vorfaelle.length})'),
      ]),
      Expanded(child: TabBarView(children: [_buildDetailsTab(), _buildAnfragenTab(), _buildVorfaelleTab()])),
    ]));
  }

  Widget _buildDetailsTab() {
    final i = widget.inst;
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _detailRow(Icons.business, 'Name', i['stelle_name']?.toString() ?? ''),
      _detailRow(Icons.location_on, 'Adresse', '${i['stelle_strasse'] ?? ''}, ${i['stelle_plz_ort'] ?? ''}'),
      _detailRow(Icons.phone, 'Telefon', i['stelle_telefon']?.toString() ?? ''),
      _detailRow(Icons.email, 'E-Mail', i['stelle_email']?.toString() ?? ''),
      if ((i['ansprechpartner']?.toString() ?? '').isNotEmpty) _detailRow(Icons.person, 'Ansprechpartner', i['ansprechpartner'].toString()),
      if ((i['ansprechpartner_tel']?.toString() ?? '').isNotEmpty) _detailRow(Icons.phone_callback, 'Tel. Ansprechpartner', i['ansprechpartner_tel'].toString()),
      const SizedBox(height: 16),
      if ((i['kind_name']?.toString() ?? '').isNotEmpty) ...[
        Text('Förderung', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
        const SizedBox(height: 8),
        _detailRow(Icons.child_care, 'Kind', i['kind_name'].toString()),
        if ((i['diagnose']?.toString() ?? '').isNotEmpty) _detailRow(Icons.medical_information, 'Diagnose', i['diagnose'].toString()),
        if ((i['beginn_datum']?.toString() ?? '').isNotEmpty) _detailRow(Icons.calendar_today, 'Beginn', i['beginn_datum'].toString()),
        if ((i['frequenz']?.toString() ?? '').isNotEmpty) _detailRow(Icons.schedule, 'Frequenz', i['frequenz'].toString()),
        _detailRow(Icons.flag, 'Status', i['status']?.toString() ?? 'aktiv'),
      ],
      const SizedBox(height: 16),
      KorrAttachmentsWidget(apiService: widget.apiService, modul: 'fruehfoerderung', korrespondenzId: widget.userId * 10 + widget.instanceNr),
    ]));
  }

  Widget _detailRow(IconData icon, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
      Icon(icon, size: 16, color: Colors.teal.shade600), const SizedBox(width: 8),
      Text('$label: ', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
    ]));
  }

  // ===== ANFRAGEN TAB =====
  Widget _buildAnfragenTab() {
    if (_loadingA) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        const Spacer(),
        FilledButton.icon(onPressed: _addAnfrage, icon: const Icon(Icons.add, size: 16), label: const Text('Neue Anfrage', style: TextStyle(fontSize: 12)),
          style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade600, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero)),
      ])),
      Expanded(child: _anfragen.isEmpty
        ? Center(child: Text('Keine Anfragen', style: TextStyle(color: Colors.grey.shade400)))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _anfragen.length, itemBuilder: (_, i) {
            final a = _anfragen[i];
            final plaetze = a['plaetze_frei']?.toString() ?? 'unbekannt';
            final pColor = plaetze == 'ja' ? Colors.green : (plaetze == 'nein' ? Colors.red : Colors.orange);
            final ergebnis = a['ergebnis']?.toString() ?? 'offen';
            return Card(child: ListTile(
              leading: CircleAvatar(backgroundColor: pColor.shade50, child: Icon(plaetze == 'ja' ? Icons.check_circle : (plaetze == 'nein' ? Icons.cancel : Icons.help), color: pColor.shade700, size: 20)),
              title: Text('Anfrage — ${a['art'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: Row(children: [
                Text(a['datum']?.toString() ?? '', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                const SizedBox(width: 8),
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: pColor.shade100, borderRadius: BorderRadius.circular(6)),
                  child: Text('Plätze: $plaetze', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: pColor.shade800))),
                const SizedBox(width: 6),
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
                  child: Text(ergebnis, style: TextStyle(fontSize: 10, color: Colors.grey.shade700))),
              ]),
              trailing: IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade300), onPressed: () async {
                await widget.apiService.fruehfoerderungAction({'action': 'delete_anfrage', 'id': a['id']});
                _loadAnfragen();
              }),
            ));
          })),
    ]);
  }

  void _addAnfrage() {
    final notizC = TextEditingController();
    String art = 'telefonisch';
    String plaetze = 'unbekannt';
    String ergebnis = 'offen';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (_, setDlg) => AlertDialog(
      title: Row(children: [Icon(Icons.question_answer, size: 18, color: Colors.teal.shade700), const SizedBox(width: 8), const Text('Neue Anfrage', style: TextStyle(fontSize: 15))]),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Art der Anfrage', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        Wrap(spacing: 8, children: ['telefonisch', 'per E-Mail', 'persönlich', 'online'].map((s) => ChoiceChip(label: Text(s), selected: art == s, selectedColor: Colors.teal.shade100, onSelected: (_) => setDlg(() => art = s))).toList()),
        const SizedBox(height: 12),
        Text('Plätze frei?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        Wrap(spacing: 8, children: [
          ChoiceChip(label: const Text('Ja'), selected: plaetze == 'ja', selectedColor: Colors.green.shade100, onSelected: (_) => setDlg(() => plaetze = 'ja')),
          ChoiceChip(label: const Text('Nein'), selected: plaetze == 'nein', selectedColor: Colors.red.shade100, onSelected: (_) => setDlg(() => plaetze = 'nein')),
          ChoiceChip(label: const Text('Warteliste'), selected: plaetze == 'warteliste', selectedColor: Colors.orange.shade100, onSelected: (_) => setDlg(() => plaetze = 'warteliste')),
          ChoiceChip(label: const Text('Unbekannt'), selected: plaetze == 'unbekannt', selectedColor: Colors.grey.shade200, onSelected: (_) => setDlg(() => plaetze = 'unbekannt')),
        ]),
        const SizedBox(height: 12),
        Text('Ergebnis', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        Wrap(spacing: 8, children: ['offen', 'zugesagt', 'abgesagt', 'warteliste'].map((s) => ChoiceChip(label: Text(s[0].toUpperCase() + s.substring(1)), selected: ergebnis == s, selectedColor: Colors.teal.shade100, onSelected: (_) => setDlg(() => ergebnis = s))).toList()),
        const SizedBox(height: 12),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          final today = '${DateTime.now().day.toString().padLeft(2, '0')}.${DateTime.now().month.toString().padLeft(2, '0')}.${DateTime.now().year}';
          await widget.apiService.fruehfoerderungAction({
            'action': 'save_anfrage', 'user_id': widget.userId, 'instance_nr': widget.instanceNr,
            'anfrage': {'stelle_name': widget.inst['stelle_name'] ?? '', 'datum': today, 'art': art, 'ergebnis': ergebnis, 'plaetze_frei': plaetze, 'notiz': notizC.text.trim()},
          });
          if (ctx.mounted) Navigator.pop(ctx);
          _loadAnfragen();
        }, child: const Text('Speichern')),
      ],
    )));
  }

  // ===== VORFÄLLE TAB =====
  Widget _buildVorfaelleTab() {
    if (_loadingV) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        const Spacer(),
        FilledButton.icon(onPressed: _addVorfall, icon: const Icon(Icons.add, size: 16), label: const Text('Neuer Vorfall', style: TextStyle(fontSize: 12)),
          style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade600, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero)),
      ])),
      Expanded(child: _vorfaelle.isEmpty
        ? Center(child: Text('Keine Vorfälle', style: TextStyle(color: Colors.grey.shade400)))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _vorfaelle.length, itemBuilder: (_, i) {
            final v = _vorfaelle[i];
            final st = v['status']?.toString() ?? 'offen';
            final sColor = st == 'erledigt' ? Colors.green : (st == 'offen' ? Colors.orange : Colors.grey);
            return Card(child: ListTile(
              leading: CircleAvatar(backgroundColor: sColor.shade50, child: Icon(Icons.warning, color: sColor.shade700, size: 20)),
              title: Text(v['titel']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: Row(children: [
                Text(v['datum']?.toString() ?? '', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                const SizedBox(width: 8),
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: sColor.shade100, borderRadius: BorderRadius.circular(6)),
                  child: Text(st, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: sColor.shade800))),
              ]),
              trailing: IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade300), onPressed: () async {
                await widget.apiService.fruehfoerderungAction({'action': 'delete_vorfall', 'id': v['id']});
                _loadVorfaelle();
              }),
            ));
          })),
    ]);
  }

  void _addVorfall() {
    final titelC = TextEditingController();
    final notizC = TextEditingController();
    String status = 'offen';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (_, setDlg) => AlertDialog(
      title: Row(children: [Icon(Icons.warning, size: 18, color: Colors.orange.shade700), const SizedBox(width: 8), const Text('Neuer Vorfall', style: TextStyle(fontSize: 15))]),
      content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: titelC, decoration: InputDecoration(labelText: 'Titel', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: ['offen', 'in Bearbeitung', 'erledigt'].map((s) => ChoiceChip(label: Text(s[0].toUpperCase() + s.substring(1)), selected: status == s,
          selectedColor: s == 'erledigt' ? Colors.green.shade100 : (s == 'offen' ? Colors.orange.shade100 : Colors.blue.shade100),
          onSelected: (_) => setDlg(() => status = s))).toList()),
        const SizedBox(height: 10),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          final today = '${DateTime.now().day.toString().padLeft(2, '0')}.${DateTime.now().month.toString().padLeft(2, '0')}.${DateTime.now().year}';
          await widget.apiService.fruehfoerderungAction({
            'action': 'save_vorfall', 'user_id': widget.userId, 'instance_nr': widget.instanceNr,
            'vorfall': {'titel': titelC.text.trim(), 'datum': today, 'status': status, 'notiz': notizC.text.trim()},
          });
          if (ctx.mounted) Navigator.pop(ctx);
          _loadVorfaelle();
        }, child: const Text('Speichern')),
      ],
    )));
  }
}
