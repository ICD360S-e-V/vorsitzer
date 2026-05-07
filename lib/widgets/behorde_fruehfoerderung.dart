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

class _State extends State<BehordeFruehfoerderungContent> with TickerProviderStateMixin {
  late final TabController _tabCtrl;
  bool _loading = true, _saving = false;
  Map<String, dynamic> _data = {};

  final _ansprechpartnerC = TextEditingController();
  final _ansprechpartnerTelC = TextEditingController();
  final _kindNameC = TextEditingController();
  final _diagnoseC = TextEditingController();
  final _beginnC = TextEditingController();
  final _frequenzC = TextEditingController();
  final _notizenC = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _ansprechpartnerC.dispose();
    _ansprechpartnerTelC.dispose();
    _kindNameC.dispose();
    _diagnoseC.dispose();
    _beginnC.dispose();
    _frequenzC.dispose();
    _notizenC.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await widget.apiService.fruehfoerderungAction({'action': 'get', 'user_id': widget.userId});
      if (res['success'] == true && res['data'] != null && mounted) {
        _data = Map<String, dynamic>.from(res['data'] as Map);
        _ansprechpartnerC.text = _data['ansprechpartner']?.toString() ?? '';
        _ansprechpartnerTelC.text = _data['ansprechpartner_tel']?.toString() ?? '';
        _kindNameC.text = _data['kind_name']?.toString() ?? '';
        _diagnoseC.text = _data['diagnose']?.toString() ?? '';
        _beginnC.text = _data['beginn_datum']?.toString() ?? '';
        _frequenzC.text = _data['frequenz']?.toString() ?? '';
        _notizenC.text = _data['notizen']?.toString() ?? '';
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.apiService.fruehfoerderungAction({
      'action': 'save',
      'user_id': widget.userId,
      'data': {
        'stelle_name': _data['stelle_name'] ?? '',
        'stelle_strasse': _data['stelle_strasse'] ?? '',
        'stelle_plz_ort': _data['stelle_plz_ort'] ?? '',
        'stelle_telefon': _data['stelle_telefon'] ?? '',
        'stelle_email': _data['stelle_email'] ?? '',
        'ansprechpartner': _ansprechpartnerC.text.trim(),
        'ansprechpartner_tel': _ansprechpartnerTelC.text.trim(),
        'kind_name': _kindNameC.text.trim(),
        'diagnose': _diagnoseC.text.trim(),
        'beginn_datum': _beginnC.text.trim(),
        'frequenz': _frequenzC.text.trim(),
        'notizen': _notizenC.text.trim(),
        'status': _data['status'] ?? 'aktiv',
      },
    });
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gespeichert'), backgroundColor: Colors.green, duration: Duration(seconds: 1)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      TabBar(controller: _tabCtrl, labelColor: Colors.teal.shade700, unselectedLabelColor: Colors.grey.shade500, indicatorColor: Colors.teal.shade700,
        tabs: [
          Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, size: 8, color: (_data['stelle_name']?.toString() ?? '').isNotEmpty ? Colors.green : Colors.red),
            const SizedBox(width: 4), const Icon(Icons.psychology, size: 16), const SizedBox(width: 4), const Text('Frühförderstelle'),
          ])),
          Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, size: 8, color: _kindNameC.text.isNotEmpty ? Colors.green : Colors.red),
            const SizedBox(width: 4), const Icon(Icons.child_care, size: 16), const SizedBox(width: 4), const Text('Förderung'),
          ])),
          Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.folder, size: 16), const SizedBox(width: 4), const Text('Dokumente'),
          ])),
        ]),
      Expanded(child: TabBarView(controller: _tabCtrl, children: [
        _buildStelleTab(),
        _buildFoerderungTab(),
        _buildDokumenteTab(),
      ])),
    ]);
  }

  // ===== TAB 1: FRÜHFÖRDERSTELLE =====
  Widget _buildStelleTab() {
    final hasStelle = (_data['stelle_name']?.toString() ?? '').isNotEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.psychology, color: Colors.teal.shade700),
          const SizedBox(width: 8),
          Text('Zuständige Frühförderstelle', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
          const Spacer(),
          FilledButton.icon(
            onPressed: _searchStelle,
            icon: const Icon(Icons.search, size: 16),
            label: Text(hasStelle ? 'Ändern' : 'Suchen', style: const TextStyle(fontSize: 12)),
            style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade600, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero),
          ),
        ]),
        const SizedBox(height: 12),
        if (!hasStelle)
          Container(
            width: double.infinity, padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
            child: Column(children: [
              Icon(Icons.psychology, size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 8),
              Text('Keine Frühförderstelle zugewiesen', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
            ]),
          )
        else ...[
          Container(
            width: double.infinity, padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.teal.shade200)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_data['stelle_name']?.toString() ?? '', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
              if ((_data['stelle_strasse']?.toString() ?? '').isNotEmpty || (_data['stelle_plz_ort']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(children: [
                  Icon(Icons.location_on, size: 14, color: Colors.teal.shade600), const SizedBox(width: 4),
                  Text('${_data['stelle_strasse'] ?? ''}, ${_data['stelle_plz_ort'] ?? ''}', style: TextStyle(fontSize: 12, color: Colors.teal.shade700)),
                ]),
              ],
              if ((_data['stelle_telefon']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.phone, size: 14, color: Colors.teal.shade600), const SizedBox(width: 4),
                  Text(_data['stelle_telefon'].toString(), style: TextStyle(fontSize: 12, color: Colors.teal.shade700)),
                ]),
              ],
              if ((_data['stelle_email']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.email, size: 14, color: Colors.teal.shade600), const SizedBox(width: 4),
                  Text(_data['stelle_email'].toString(), style: TextStyle(fontSize: 12, color: Colors.teal.shade700)),
                ]),
              ],
            ]),
          ),
          const SizedBox(height: 16),
          Text('Ansprechpartner', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          TextField(controller: _ansprechpartnerC, decoration: InputDecoration(hintText: 'Name des Ansprechpartners', isDense: true, prefixIcon: const Icon(Icons.person, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 10),
          TextField(controller: _ansprechpartnerTelC, decoration: InputDecoration(hintText: 'Telefon Ansprechpartner', isDense: true, prefixIcon: const Icon(Icons.phone, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 16),
          Row(children: [
            FilledButton.icon(onPressed: _saving ? null : _save, icon: Icon(_saving ? Icons.hourglass_top : Icons.save, size: 16), label: Text(_saving ? 'Speichern...' : 'Speichern', style: const TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade600)),
          ]),
        ],
      ]),
    );
  }

  // ===== TAB 2: FÖRDERUNG =====
  Widget _buildFoerderungTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.child_care, color: Colors.teal.shade700),
          const SizedBox(width: 8),
          Text('Förderung', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
        ]),
        const SizedBox(height: 16),
        Text('Kind', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        TextField(controller: _kindNameC, decoration: InputDecoration(hintText: 'Name des Kindes', isDense: true, prefixIcon: const Icon(Icons.child_care, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 14),
        Text('Diagnose / Förderbedarf', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        TextField(controller: _diagnoseC, maxLines: 3, decoration: InputDecoration(hintText: 'z.B. Sprachentwicklungsverzögerung, motorische Förderung...', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Beginn der Förderung', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
            const SizedBox(height: 4),
            TextField(controller: _beginnC, readOnly: true, decoration: InputDecoration(hintText: 'Datum', isDense: true, prefixIcon: const Icon(Icons.calendar_today, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de'));
                if (d != null) _beginnC.text = '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
              }),
          ])),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Frequenz', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
            const SizedBox(height: 4),
            TextField(controller: _frequenzC, decoration: InputDecoration(hintText: 'z.B. 1x/Woche', isDense: true, prefixIcon: const Icon(Icons.schedule, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          ])),
        ]),
        const SizedBox(height: 14),
        Text('Status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        Wrap(spacing: 8, children: ['aktiv', 'pausiert', 'beendet'].map((s) => ChoiceChip(
          label: Text(s[0].toUpperCase() + s.substring(1)),
          selected: (_data['status'] ?? 'aktiv') == s,
          selectedColor: s == 'aktiv' ? Colors.green.shade100 : (s == 'pausiert' ? Colors.orange.shade100 : Colors.grey.shade200),
          onSelected: (_) => setState(() => _data['status'] = s),
        )).toList()),
        const SizedBox(height: 14),
        Text('Notizen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        TextField(controller: _notizenC, maxLines: 3, decoration: InputDecoration(hintText: 'Weitere Informationen...', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: _saving ? null : _save, icon: Icon(_saving ? Icons.hourglass_top : Icons.save, size: 16), label: Text(_saving ? 'Speichern...' : 'Speichern', style: const TextStyle(fontSize: 12)),
          style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade600)),
      ]),
    );
  }

  // ===== TAB 3: DOKUMENTE =====
  Widget _buildDokumenteTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: KorrAttachmentsWidget(apiService: widget.apiService, modul: 'fruehfoerderung', korrespondenzId: widget.userId),
    );
  }

  void _searchStelle() async {
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
        title: Row(children: [
          Icon(Icons.psychology, size: 20, color: Colors.teal.shade700),
          const SizedBox(width: 8),
          const Text('Frühförderstelle suchen', style: TextStyle(fontSize: 15)),
        ]),
        content: SizedBox(width: 500, height: 400, child: Column(children: [
          TextField(controller: searchC, autofocus: true,
            decoration: InputDecoration(hintText: 'Name oder Ort...', isDense: true, prefixIcon: const Icon(Icons.search, size: 18),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: doSearch)),
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
                      if ((s['strasse']?.toString() ?? '').isNotEmpty || (s['plz_ort']?.toString() ?? '').isNotEmpty)
                        Text('${s['strasse'] ?? ''}, ${s['plz_ort'] ?? ''}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      if ((s['telefon']?.toString() ?? '').isNotEmpty)
                        Text('Tel: ${s['telefon']}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    ]),
                  ));
                })),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen'))],
      );
    }));
    if (selected != null && mounted) {
      setState(() {
        _data['stelle_name'] = selected['name']?.toString() ?? '';
        _data['stelle_strasse'] = selected['strasse']?.toString() ?? '';
        _data['stelle_plz_ort'] = selected['plz_ort']?.toString() ?? '';
        _data['stelle_telefon'] = selected['telefon']?.toString() ?? '';
        _data['stelle_email'] = selected['email']?.toString() ?? '';
      });
      _save();
    }
  }
}
