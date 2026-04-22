import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class BehordeSozialamtContent extends StatefulWidget {
  final ApiService? apiService;
  final int? userId;
  final Map<String, dynamic> Function(String type) getData;
  final bool Function(String type) isLoading;
  final bool Function(String type) isSaving;
  final void Function(String type) loadData;
  final void Function(String type, Map<String, dynamic> data) saveData;
  final Widget Function(String type, TextEditingController controller) dienststelleBuilder;

  const BehordeSozialamtContent({
    super.key,
    this.apiService,
    this.userId,
    required this.getData,
    required this.isLoading,
    required this.isSaving,
    required this.loadData,
    required this.saveData,
    required this.dienststelleBuilder,
  });

  static const type = 'sozialamt';

  @override
  State<BehordeSozialamtContent> createState() => _BehordeSozialamtContentState();
}

class _BehordeSozialamtContentState extends State<BehordeSozialamtContent> {
  static const type = 'sozialamt';
  Map<String, Map<String, dynamic>> _dbData = {};
  List<Map<String, dynamic>> _antraege = [];
  List<Map<String, dynamic>> _bewilligungen = [];
  List<Map<String, dynamic>> _korrespondenz = [];
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadFromDB();
  }

  Future<void> _loadFromDB() async {
    if (widget.apiService == null || widget.userId == null) {
      setState(() => _loaded = true);
      return;
    }
    final r = await widget.apiService!.getSozialamtData(widget.userId!);
    if (!mounted) return;
    if (r['success'] == true && r['data'] is Map) {
      final raw = r['data'] as Map;
      _dbData = {};
      for (final entry in raw.entries) {
        final map = Map<String, dynamic>.from(entry.value as Map);
        // Parse JSON strings back to lists/maps (stored as JSON in DB)
        for (final k in map.keys.toList()) {
          final v = map[k];
          if (v is String && v.startsWith('[')) {
            try { map[k] = jsonDecode(v); } catch (_) {}
          } else if (v is String && v.startsWith('{')) {
            try { map[k] = jsonDecode(v); } catch (_) {}
          }
        }
        _dbData[entry.key.toString()] = map;
      }
    }
    // Load from dedicated tables
    if (widget.apiService != null && widget.userId != null) {
      final aR = await widget.apiService!.listSozialamtAntraege(widget.userId!);
      if (aR['success'] == true && aR['data'] is List) _antraege = (aR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final bR = await widget.apiService!.listSozialamtBewilligungen(widget.userId!);
      if (bR['success'] == true && bR['data'] is List) _bewilligungen = (bR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final kR = await widget.apiService!.listSozialamtKorrespondenz(widget.userId!);
      if (kR['success'] == true && kR['data'] is List) _korrespondenz = (kR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    setState(() => _loaded = true);
  }

  Future<void> _save() async {
    if (widget.apiService == null || widget.userId == null) return;
    setState(() => _saving = true);
    await widget.apiService!.saveSozialamtData(widget.userId!, _dbData);
    if (mounted) setState(() => _saving = false);
  }

  Map<String, dynamic> _b(String key) {
    _dbData[key] ??= {};
    return _dbData[key]!;
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());

    return DefaultTabController(
      length: 5,
      child: Column(children: [
        TabBar(
          labelColor: Colors.indigo.shade700,
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: Colors.indigo.shade700,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.account_balance, size: 16), text: 'Zuständige Behörde'),
            Tab(icon: Icon(Icons.person, size: 16), text: 'Mitarbeiter/in'),
            Tab(icon: Icon(Icons.description, size: 16), text: 'Anträge'),
            Tab(icon: Icon(Icons.check_circle, size: 16), text: 'Bewilligung'),
            Tab(icon: Icon(Icons.mail, size: 16), text: 'Korrespondenz'),
          ],
        ),
        Expanded(child: TabBarView(children: [
          _buildBehoerdeTab(),
          _buildMitarbeiterTab(),
          _buildAntraegeTab(),
          _buildBewilligungTab(),
          _buildKorrespondenzTab(),
        ])),
      ]),
    );
  }

  Widget _buildBehoerdeTab() {
    final d = _b('behoerde');
    final selected = d['name']?.toString() ?? '';
    final sel = _sozialamtListe.where((s) => s['name'] == selected).firstOrNull;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.account_balance, size: 20, color: Colors.indigo.shade700),
          const SizedBox(width: 8),
          Expanded(child: Text('Zuständiges Sozialamt', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo.shade700))),
          OutlinedButton.icon(
            icon: const Icon(Icons.search, size: 16),
            label: Text(selected.isEmpty ? 'Auswählen' : 'Ändern', style: const TextStyle(fontSize: 12)),
            onPressed: () => _showBehoerdeSelectDialog(d),
          ),
        ]),
        const SizedBox(height: 12),
        if (selected.isEmpty)
          Container(
            width: double.infinity, padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
            child: Column(children: [
              Icon(Icons.search, size: 40, color: Colors.grey.shade400),
              const SizedBox(height: 8),
              Text('Kein Sozialamt ausgewählt', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              const SizedBox(height: 4),
              Text('Tippen Sie auf "Auswählen" um das zuständige Amt zu suchen.', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ]),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.indigo.shade300)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(selected, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo.shade900)),
              if (sel != null) ...[
                const SizedBox(height: 6),
                _infoRow(Icons.location_on, '${sel['adresse']}, ${sel['plz_ort']}'),
                _infoRow(Icons.phone, sel['telefon'] ?? ''),
                _infoRow(Icons.access_time, sel['oeffnungszeiten'] ?? ''),
                _infoRow(Icons.info, sel['zustaendigkeit'] ?? ''),
              ],
            ]),
          ),
      ]),
    );
  }

  void _showBehoerdeSelectDialog(Map<String, dynamic> d) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(children: [
          Icon(Icons.search, color: Colors.indigo.shade700),
          const SizedBox(width: 8),
          const Text('Sozialamt auswählen'),
        ]),
        content: SizedBox(
          width: 500, height: 400,
          child: ListView(children: _sozialamtListe.map((s) {
            return InkWell(
              onTap: () {
                setState(() { d['name'] = s['name']; d['adresse'] = s['adresse']; d['plz_ort'] = s['plz_ort']; d['telefon'] = s['telefon']; d['oeffnungszeiten'] = s['oeffnungszeiten']; });
                _save();
                Navigator.pop(ctx);
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
                child: Row(children: [
                  Icon(Icons.account_balance, size: 20, color: Colors.indigo.shade600),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s['name']!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade900)),
                    Text('${s['adresse']}, ${s['plz_ort']}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    Text(s['zustaendigkeit']!, style: TextStyle(fontSize: 10, color: Colors.indigo.shade400, fontStyle: FontStyle.italic)),
                  ])),
                ]),
              ),
            );
          }).toList()),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen'))],
      ),
    );
  }

  bool _mitarbeiterEditing = false;

  Widget _buildMitarbeiterTab() {
    final d = _b('mitarbeiter');
    final hasData = (d['name']?.toString() ?? '').isNotEmpty;
    final readOnly = hasData && !_mitarbeiterEditing;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.person, size: 20, color: Colors.indigo.shade700),
          const SizedBox(width: 8),
          Expanded(child: Text('Zuständige/r Sachbearbeiter/in', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo.shade700))),
          if (hasData)
            IconButton(
              icon: Icon(_mitarbeiterEditing ? Icons.check : Icons.edit, size: 20, color: Colors.indigo.shade700),
              tooltip: _mitarbeiterEditing ? 'Fertig' : 'Bearbeiten',
              onPressed: () {
                if (_mitarbeiterEditing) _save();
                setState(() => _mitarbeiterEditing = !_mitarbeiterEditing);
              },
            ),
        ]),
        const SizedBox(height: 12),
        if (readOnly) ...[
          _readOnlyRow(Icons.person, 'Anrede', d['anrede']),
          _readOnlyRow(Icons.badge, 'Name', d['name']),
          _readOnlyRow(Icons.phone, 'Telefon', d['telefon']),
          _readOnlyRow(Icons.email, 'E-Mail', d['email']),
          _readOnlyRow(Icons.room, 'Zimmer', d['zimmer']),
          _readOnlyRow(Icons.access_time, 'Sprechzeiten', d['sprechzeiten']),
          _readOnlyRow(Icons.note, 'Notizen', d['notizen']),
        ] else ...[
          _field(d, 'anrede', 'Anrede', Icons.person, hint: 'Frau / Herr'),
          _field(d, 'name', 'Name', Icons.badge),
          _field(d, 'telefon', 'Telefon (direkt)', Icons.phone),
          _field(d, 'email', 'E-Mail', Icons.email),
          _field(d, 'zimmer', 'Zimmer / Raum', Icons.room),
          _field(d, 'sprechzeiten', 'Sprechzeiten', Icons.access_time),
          _field(d, 'notizen', 'Notizen', Icons.note, maxLines: 3),
          _saveBtn(),
        ],
      ]),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Icon(icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
      ]),
    );
  }

  Widget _readOnlyRow(IconData icon, String label, dynamic value) {
    final s = value?.toString() ?? '';
    if (s.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        SizedBox(width: 100, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600))),
        Expanded(child: Text(s, style: const TextStyle(fontSize: 13))),
      ]),
    );
  }

  Widget _buildAntraegeTab() {
    final list = _antraege;
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Row(children: [
        Icon(Icons.description, size: 20, color: Colors.indigo.shade700), const SizedBox(width: 8),
        Expanded(child: Text('Anträge (${list.length})', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo.shade700))),
        ElevatedButton.icon(onPressed: () => _showAntragDialog(), icon: const Icon(Icons.add, size: 16), label: const Text('Neuer Antrag', style: TextStyle(fontSize: 12)), style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white)),
      ])),
      Expanded(child: list.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.description, size: 48, color: Colors.grey.shade300), const SizedBox(height: 8), Text('Keine Anträge', style: TextStyle(color: Colors.grey.shade500))]))
          : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: list.length, itemBuilder: (_, i) {
              final a = list[i];
              return Card(child: ListTile(
                leading: Icon(Icons.description, color: Colors.indigo.shade600),
                title: Text(a['leistung']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text('${a['datum'] ?? ''} • ${a['methode'] ?? ''} • ${a['status'] ?? ''}', style: const TextStyle(fontSize: 11)),
                trailing: IconButton(icon: Icon(Icons.delete, size: 18, color: Colors.red.shade400), onPressed: () async {
                  final aid = int.tryParse(a['id']?.toString() ?? '');
                  if (aid != null && widget.apiService != null) await widget.apiService!.deleteSozialamtAntrag(aid);
                  _loadFromDB();
                }),
              ));
            })),
    ]);
  }

  Widget _buildBewilligungTab() {
    final list = _bewilligungen;
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Row(children: [
        Icon(Icons.check_circle, size: 20, color: Colors.green.shade700), const SizedBox(width: 8),
        Expanded(child: Text('Bewilligungen (${list.length})', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green.shade700))),
        ElevatedButton.icon(onPressed: () => _showBewilligungDialog(), icon: const Icon(Icons.add, size: 16), label: const Text('Neu', style: TextStyle(fontSize: 12)), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white)),
      ])),
      Expanded(child: list.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.check_circle_outline, size: 48, color: Colors.grey.shade300), const SizedBox(height: 8), Text('Keine Bewilligungen', style: TextStyle(color: Colors.grey.shade500))]))
          : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: list.length, itemBuilder: (_, i) {
              final b = list[i];
              final ok = b['bewilligt'] == true || b['bewilligt'] == 'true';
              final ausz = b['auszahlung']?.toString() ?? '';
              final zeitraum = (b['zeitraum_von']?.toString() ?? '').isNotEmpty ? '${b['zeitraum_von']} – ${b['zeitraum_bis'] ?? ''}' : '';
              return Card(child: ListTile(
                leading: Icon(ok ? Icons.check_circle : Icons.cancel, color: ok ? Colors.green : Colors.red, size: 28),
                title: Text(b['leistung']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${ok ? 'Bewilligt' : 'Abgelehnt'} • Bescheid: ${b['bescheid_datum'] ?? b['datum'] ?? ''}', style: TextStyle(fontSize: 11, color: ok ? Colors.green.shade700 : Colors.red.shade700)),
                  if ((b['erhalten_am']?.toString() ?? '').isNotEmpty) Text('📬 Erhalten per Post: ${b['erhalten_am']}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  if (zeitraum.isNotEmpty) Text('Zeitraum: $zeitraum', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  if (ausz.isNotEmpty) Text('Auszahlung: $ausz €/Monat', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                  if (b['widerspruch'] == true) Text('⚠ Widerspruch eingelegt${b['widerspruch_datum'] != null ? ' am ${b['widerspruch_datum']}' : ''}', style: TextStyle(fontSize: 10, color: Colors.orange.shade700)),
                ]),
                isThreeLine: true,
                trailing: IconButton(icon: Icon(Icons.delete, size: 18, color: Colors.red.shade400), onPressed: () async {
                  final bid = int.tryParse(b['id']?.toString() ?? '');
                  if (bid != null && widget.apiService != null) await widget.apiService!.deleteSozialamtBewilligung(bid);
                  _loadFromDB();
                }),
              ));
            })),
    ]);
  }

  Widget _buildKorrespondenzTab() {
    final list = _korrespondenz;
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Expanded(child: Text('${list.length} Einträge', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
        FilledButton.icon(icon: const Icon(Icons.call_received, size: 14), label: const Text('Eingang', style: TextStyle(fontSize: 11)), style: FilledButton.styleFrom(backgroundColor: Colors.green.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero), onPressed: () => _showKorrDialog('eingang')),
        const SizedBox(width: 6),
        FilledButton.icon(icon: const Icon(Icons.call_made, size: 14), label: const Text('Ausgang', style: TextStyle(fontSize: 11)), style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero), onPressed: () => _showKorrDialog('ausgang')),
      ])),
      Expanded(child: list.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.mail_outline, size: 48, color: Colors.grey.shade300), const SizedBox(height: 6), Text('Keine Korrespondenz', style: TextStyle(fontSize: 12, color: Colors.grey.shade500))]))
          : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: list.length, itemBuilder: (_, i) {
              final k = list[i]; final isEin = k['richtung'] == 'eingang';
              return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: isEin ? Colors.green.shade200 : Colors.blue.shade200)),
                child: Row(children: [
                  Icon(isEin ? Icons.call_received : Icons.call_made, size: 18, color: isEin ? Colors.green.shade700 : Colors.blue.shade700), const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(k['betreff']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isEin ? Colors.green.shade800 : Colors.blue.shade800)),
                    Text(k['datum']?.toString() ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  ])),
                  IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), onPressed: () async {
                    final kid = int.tryParse(k['id']?.toString() ?? '');
                    if (kid != null && widget.apiService != null) await widget.apiService!.deleteSozialamtKorrespondenz(kid);
                    _loadFromDB();
                  }, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28)),
                ]),
              );
            })),
    ]);
  }

  void _showAntragDialog({int? editIndex}) {
    final ex = editIndex != null ? _antraege[editIndex] : null;
    final datumC = TextEditingController(text: ex?['datum']?.toString() ?? '');
    final notizC = TextEditingController(text: ex?['notiz']?.toString() ?? '');
    String leistung = ex?['leistung']?.toString() ?? '';
    String methode = ex?['methode']?.toString() ?? '';
    String status = ex?['status']?.toString() ?? 'eingereicht';
    final leistungen = ['Grundsicherung im Alter', 'Grundsicherung bei Erwerbsminderung', 'Hilfe zum Lebensunterhalt', 'Eingliederungshilfe', 'Hilfe zur Pflege', 'Bildung und Teilhabe', 'Bestattungskosten', 'Blindengeld', 'Sonstige'];
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) => AlertDialog(
      title: Text(editIndex != null ? 'Antrag bearbeiten' : 'Neuer Antrag'),
      content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(value: leistungen.contains(leistung) ? leistung : null, decoration: InputDecoration(labelText: 'Leistung *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), items: leistungen.map((l) => DropdownMenuItem(value: l, child: Text(l, style: const TextStyle(fontSize: 12)))).toList(), onChanged: (v) => setD(() => leistung = v ?? '')),
        const SizedBox(height: 8),
        TextField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onTap: () async { final p = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de')); if (p != null) setD(() => datumC.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}'); }),
        const SizedBox(height: 8),
        Wrap(spacing: 6, children: [('online', 'Online'), ('persoenlich', 'Persönlich'), ('postalisch', 'Postalisch'), ('email', 'E-Mail')].map((m) => ChoiceChip(label: Text(m.$2, style: TextStyle(fontSize: 11, color: methode == m.$1 ? Colors.white : Colors.black87)), selected: methode == m.$1, selectedColor: Colors.indigo, onSelected: (_) => setD(() => methode = m.$1))).toList()),
        const SizedBox(height: 8),
        Wrap(spacing: 6, children: [('eingereicht', 'Eingereicht'), ('in_bearbeitung', 'In Bearbeitung'), ('bewilligt', 'Bewilligt'), ('abgelehnt', 'Abgelehnt'), ('widerspruch', 'Widerspruch')].map((s) => ChoiceChip(label: Text(s.$2, style: TextStyle(fontSize: 11, color: status == s.$1 ? Colors.white : Colors.black87)), selected: status == s.$1, selectedColor: Colors.teal, onSelected: (_) => setD(() => status = s.$1))).toList()),
        const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          if (leistung.isEmpty || datumC.text.isEmpty) return;
          if (widget.apiService != null && widget.userId != null) {
            await widget.apiService!.saveSozialamtAntrag(widget.userId!, {
              if (ex != null) 'id': ex['id'],
              'leistung': leistung, 'datum': datumC.text, 'methode': methode, 'status': status, 'notiz': notizC.text,
            });
          }
          if (ctx.mounted) Navigator.pop(ctx);
          _loadFromDB();
        }, child: Text(editIndex != null ? 'Speichern' : 'Hinzufügen')),
      ],
    )));
  }

  void _showBewilligungDialog() {
    String leistung = '';
    final bescheidDatumC = TextEditingController();
    final erhaltenAmC = TextEditingController();
    final zeitraumVonC = TextEditingController();
    final zeitraumBisC = TextEditingController();
    final regelbedarfC = TextEditingController();
    final mehrbedarfC = TextEditingController();
    final kaltmieteC = TextEditingController();
    final nebenkostenC = TextEditingController();
    final heizkostenC = TextEditingController();
    final einkommenC = TextEditingController();
    final auszahlungC = TextEditingController();
    final notizC = TextEditingController();
    bool bewilligt = true;
    bool widerspruch = false;
    final widerspruchDatumC = TextEditingController();
    final leistungen = ['Grundsicherung im Alter', 'Grundsicherung bei Erwerbsminderung', 'Hilfe zum Lebensunterhalt', 'Eingliederungshilfe', 'Hilfe zur Pflege', 'Bildung und Teilhabe', 'Blindengeld', 'Sonstige'];

    Future<void> pickDate(BuildContext ctx, TextEditingController c) async {
      final p = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
      if (p != null) c.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}';
    }

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Text('Bewilligungsbescheid erfassen'),
      content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        DropdownButtonFormField<String>(value: leistungen.contains(leistung) ? leistung : null, decoration: InputDecoration(labelText: 'Leistungsart *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), items: leistungen.map((l) => DropdownMenuItem(value: l, child: Text(l, style: const TextStyle(fontSize: 12)))).toList(), onChanged: (v) => setD(() => leistung = v ?? '')),
        const SizedBox(height: 8),
        Row(children: [
          ChoiceChip(avatar: Icon(Icons.check_circle, size: 14, color: bewilligt ? Colors.white : Colors.green), label: Text('Bewilligt', style: TextStyle(fontSize: 11, color: bewilligt ? Colors.white : Colors.black87)), selected: bewilligt, selectedColor: Colors.green, onSelected: (_) => setD(() => bewilligt = true)),
          const SizedBox(width: 8),
          ChoiceChip(avatar: Icon(Icons.cancel, size: 14, color: !bewilligt ? Colors.white : Colors.red), label: Text('Abgelehnt', style: TextStyle(fontSize: 11, color: !bewilligt ? Colors.white : Colors.black87)), selected: !bewilligt, selectedColor: Colors.red, onSelected: (_) => setD(() => bewilligt = false)),
        ]),
        const SizedBox(height: 8),
        TextField(controller: bescheidDatumC, readOnly: true, decoration: InputDecoration(labelText: 'Bescheid-Datum *', prefixIcon: const Icon(Icons.calendar_today, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onTap: () async { await pickDate(ctx2, bescheidDatumC); setD(() {}); }),
        const SizedBox(height: 8),
        TextField(controller: erhaltenAmC, readOnly: true, decoration: InputDecoration(labelText: 'Erhalten per Post am', prefixIcon: const Icon(Icons.local_post_office, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), helperText: 'Wichtig für Widerspruchsfrist (1 Monat ab Zugang)'), onTap: () async { await pickDate(ctx2, erhaltenAmC); setD(() {}); }),
        const SizedBox(height: 8),
        Text('Bewilligungszeitraum', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: TextField(controller: zeitraumVonC, readOnly: true, decoration: InputDecoration(labelText: 'Von', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onTap: () async { await pickDate(ctx2, zeitraumVonC); setD(() {}); })),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: zeitraumBisC, readOnly: true, decoration: InputDecoration(labelText: 'Bis', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onTap: () async { await pickDate(ctx2, zeitraumBisC); setD(() {}); })),
        ]),
        if (bewilligt) ...[
          const SizedBox(height: 12),
          Text('Berechnungsbogen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: TextField(controller: regelbedarfC, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Regelbedarf €', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: mehrbedarfC, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Mehrbedarf €', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
          ]),
          const SizedBox(height: 8),
          Text('Kosten der Unterkunft (KdU)', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: TextField(controller: kaltmieteC, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Kaltmiete €', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
            const SizedBox(width: 6),
            Expanded(child: TextField(controller: nebenkostenC, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Nebenkosten €', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
            const SizedBox(width: 6),
            Expanded(child: TextField(controller: heizkostenC, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Heizkosten €', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: einkommenC, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Anrechenb. Einkommen €', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: auszahlungC, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Auszahlung €/Monat', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade800))),
          ]),
        ],
        const SizedBox(height: 8),
        Row(children: [
          Checkbox(value: widerspruch, onChanged: (v) => setD(() => widerspruch = v ?? false)),
          const Text('Widerspruch eingelegt', style: TextStyle(fontSize: 12)),
        ]),
        if (widerspruch)
          TextField(controller: widerspruchDatumC, readOnly: true, decoration: InputDecoration(labelText: 'Widerspruch am', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onTap: () async { await pickDate(ctx2, widerspruchDatumC); setD(() {}); }),
        const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notizen', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () {
          if (leistung.isEmpty || bescheidDatumC.text.isEmpty) return;
          setState(() { list.insert(0, {
            'leistung': leistung, 'bewilligt': bewilligt, 'bescheid_datum': bescheidDatumC.text, 'erhalten_am': erhaltenAmC.text,
            'zeitraum_von': zeitraumVonC.text, 'zeitraum_bis': zeitraumBisC.text,
            'regelbedarf': regelbedarfC.text, 'mehrbedarf': mehrbedarfC.text,
            'kaltmiete': kaltmieteC.text, 'nebenkosten': nebenkostenC.text, 'heizkosten': heizkostenC.text,
            'einkommen': einkommenC.text, 'auszahlung': auszahlungC.text,
            'widerspruch': widerspruch, 'widerspruch_datum': widerspruchDatumC.text,
            'notiz': notizC.text,
          });
          if (widget.apiService != null && widget.userId != null) {
            await widget.apiService!.saveSozialamtBewilligung(widget.userId!, {
              'leistung': leistung, 'bewilligt': bewilligt, 'bescheid_datum': bescheidDatumC.text, 'erhalten_am': erhaltenAmC.text,
              'zeitraum_von': zeitraumVonC.text, 'zeitraum_bis': zeitraumBisC.text,
              'regelbedarf': double.tryParse(regelbedarfC.text), 'mehrbedarf': double.tryParse(mehrbedarfC.text),
              'kaltmiete': double.tryParse(kaltmieteC.text), 'nebenkosten': double.tryParse(nebenkostenC.text), 'heizkosten': double.tryParse(heizkostenC.text),
              'einkommen': double.tryParse(einkommenC.text), 'auszahlung': double.tryParse(auszahlungC.text),
              'widerspruch': widerspruch, 'widerspruch_datum': widerspruchDatumC.text, 'notiz': notizC.text,
            });
          }
          if (ctx.mounted) Navigator.pop(ctx);
          _loadFromDB();
        }, child: const Text('Hinzufügen')),
      ],
    )));
  }

  void _showKorrDialog(String richtung) {
    final betreffC = TextEditingController(); final datumC = TextEditingController(text: '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}'); final notizC = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text(richtung == 'eingang' ? 'Eingang' : 'Ausgang'),
      content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: datumC, decoration: const InputDecoration(labelText: 'Datum', isDense: true, border: OutlineInputBorder())), const SizedBox(height: 8),
        TextField(controller: betreffC, decoration: const InputDecoration(labelText: 'Betreff', isDense: true, border: OutlineInputBorder())), const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 3, decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder())),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          if (widget.apiService != null && widget.userId != null) {
            await widget.apiService!.saveSozialamtKorrespondenz(widget.userId!, {'richtung': richtung, 'datum': datumC.text.trim(), 'betreff': betreffC.text.trim(), 'notiz': notizC.text.trim()});
          }
          if (ctx.mounted) Navigator.pop(ctx);
          _loadFromDB();
        }, child: const Text('Speichern')),
      ],
    ));
  }

  static const _sozialamtListe = [
    {'name': 'Landratsamt Neu-Ulm — Soziale Leistungen', 'adresse': 'Albrecht-Berblinger-Str. 6', 'plz_ort': '89231 Neu-Ulm', 'telefon': '0731 7040-52020', 'oeffnungszeiten': 'Mo–Mi 07:30–12:30, Do 07:30–17:30, Fr 07:30–12:30', 'zustaendigkeit': 'Sozialhilfe, Grundsicherung, Blindengeld'},
    {'name': 'LRA Neu-Ulm — Außenstelle Illertissen', 'adresse': 'Ulmer Straße 20', 'plz_ort': '89257 Illertissen', 'telefon': '07303 9006-0', 'oeffnungszeiten': 'Mo–Mi 07:30–12:30, Do 07:30–17:30, Fr 07:30–12:30', 'zustaendigkeit': 'Südlicher Landkreis'},
    {'name': 'Stadt Ulm — Soziales', 'adresse': 'Zeitblomstraße 28', 'plz_ort': '89073 Ulm', 'telefon': '0731 161-5101', 'oeffnungszeiten': 'Mo–Fr 08:00–12:00, Di+Do 14:00–16:00', 'zustaendigkeit': 'Sozialhilfe, Grundsicherung, Wohngeld, BuT'},
  ];

  Widget _field(Map<String, dynamic> map, String key, String label, IconData icon, {String hint = '', int maxLines = 1}) {
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: TextField(
      controller: TextEditingController(text: map[key]?.toString() ?? ''), maxLines: maxLines, onChanged: (v) => map[key] = v,
      decoration: InputDecoration(labelText: label, hintText: hint, prefixIcon: Icon(icon, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
      style: const TextStyle(fontSize: 13),
    ));
  }

  Widget _saveBtn() {
    return Align(alignment: Alignment.centerRight, child: ElevatedButton.icon(
      onPressed: _saving ? null : _save,
      icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 16),
      label: const Text('Speichern'),
      style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
    ));
  }
}
