import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// WBS — Wohnberechtigungsschein
///
/// Two sub-tabs (Bürgeramt pattern):
///   • "Zuständige für WBS" — search the wbs_datenbank with a magnifier,
///     selected institution shown as a card.
///   • "Antrag" — list of WBS-related Anträge for this user. The first
///     supported type is "Antrag auf Erteilung eines Wohnberechtigungs-
///     scheins nach § 15 LWoFG" (Baden-Württemberg).
class BehordeWbsContent extends StatefulWidget {
  final ApiService apiService;
  final int userId;

  const BehordeWbsContent({super.key, required this.apiService, required this.userId});

  @override
  State<BehordeWbsContent> createState() => _State();
}

class _State extends State<BehordeWbsContent> with TickerProviderStateMixin {
  late final TabController _tabCtrl;
  bool _loaded = false, _loading = false, _saving = false;

  Map<String, dynamic> _data = {};
  List<Map<String, dynamic>> _vorfaelle = [];
  List<Map<String, dynamic>> _institutionen = [];

  static const _antragTypen = [
    'Antrag auf Erteilung eines Wohnberechtigungsscheins nach § 15 LWoFG',
    'Verlängerung des Wohnberechtigungsscheins',
    'Änderung des Wohnberechtigungsscheins (z.B. Haushaltsgröße)',
    'Wohnungssuche (Vermittlung)',
    'Sonstiges',
  ];

  static const _dringlichkeit = ['normal', 'dringlich', 'besonders dringlich'];

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
      final res = await widget.apiService.getWbsData(widget.userId);
      if (res['success'] == true && mounted) {
        final raw = res['data'];
        if (raw is Map) {
          _data = {};
          for (final e in raw.entries) {
            final parts = e.key.toString().split('.');
            _data[parts.length == 2 ? parts[1] : e.key.toString()] = e.value;
          }
        }
        _vorfaelle = (res['vorfaelle'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      final inst = await widget.apiService.listWbsInstitutionen();
      if (inst['success'] == true && mounted) {
        _institutionen = (inst['institutionen'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    if (mounted) setState(() { _loading = false; _loaded = true; });
  }

  Future<void> _saveFields(Map<String, dynamic> fields) async {
    setState(() => _saving = true);
    try {
      final mapped = <String, dynamic>{};
      for (final e in fields.entries) {
        mapped['stammdaten.${e.key}'] = e.value?.toString() ?? '';
      }
      await widget.apiService.saveWbsData(widget.userId, mapped);
      for (final e in fields.entries) { _data[e.key] = e.value; }
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
      TabBar(
        controller: _tabCtrl,
        labelColor: Colors.indigo.shade700,
        unselectedLabelColor: Colors.grey.shade500,
        indicatorColor: Colors.indigo.shade700,
        tabs: [
          Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, size: 8, color: _v('institution_id').isNotEmpty ? Colors.green : Colors.red),
            const SizedBox(width: 4), const Icon(Icons.account_balance, size: 16),
            const SizedBox(width: 4), const Text('Zuständige für WBS'),
          ])),
          Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, size: 8, color: _vorfaelle.isNotEmpty ? Colors.green : Colors.red),
            const SizedBox(width: 4), const Icon(Icons.assignment, size: 16),
            const SizedBox(width: 4), const Text('Antrag'),
          ])),
        ],
      ),
      Expanded(child: TabBarView(controller: _tabCtrl, children: [_buildInstitutionTab(), _buildAntragTab()])),
    ]);
  }

  // ────────────────────────── Tab 1: Zuständige WBS ──────────────────────────
  Widget _buildInstitutionTab() {
    final selId = int.tryParse(_v('institution_id'));
    final selected = selId == null ? null : _institutionen.firstWhere(
      (i) => (i['id'] as int?) == selId || int.tryParse(i['id'].toString()) == selId,
      orElse: () => {},
    );

    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Zuständige Behörde für WBS', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
      const SizedBox(height: 8),
      Autocomplete<Map<String, dynamic>>(
        initialValue: TextEditingValue(text: _v('institution_name')),
        displayStringForOption: (i) => i['name']?.toString() ?? '',
        optionsBuilder: (txt) {
          final q = txt.text.trim().toLowerCase();
          if (q.isEmpty) return _institutionen;
          return _institutionen.where((i) =>
            (i['name']?.toString() ?? '').toLowerCase().contains(q) ||
            (i['abteilung']?.toString() ?? '').toLowerCase().contains(q) ||
            (i['ort']?.toString() ?? '').toLowerCase().contains(q) ||
            (i['plz']?.toString() ?? '').toLowerCase().contains(q));
        },
        fieldViewBuilder: (ctx, controller, focusNode, onSubmit) => TextField(
          controller: controller, focusNode: focusNode,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: controller.text.isNotEmpty
                ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () {
                    controller.clear();
                    _saveFields({'institution_id': '', 'institution_name': ''});
                  })
                : null,
            hintText: 'Behörde suchen (z.B. „Ulm" oder „Wohnen")…',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
        optionsViewBuilder: (ctx, onSel, options) => Align(
          alignment: Alignment.topLeft,
          child: Material(elevation: 4, borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320, maxWidth: 520),
              child: ListView(padding: EdgeInsets.zero, shrinkWrap: true,
                children: options.map((i) => InkWell(
                  onTap: () => onSel(i),
                  child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(i['name']?.toString() ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    if ((i['abteilung']?.toString() ?? '').isNotEmpty)
                      Text(i['abteilung'].toString(), style: TextStyle(fontSize: 11, color: Colors.indigo.shade600)),
                    Text('${i['strasse'] ?? ''}, ${i['plz'] ?? ''} ${i['ort'] ?? ''}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  ])),
                )).toList(),
              ),
            ),
          ),
        ),
        onSelected: (i) {
          _saveFields({
            'institution_id': i['id']?.toString() ?? '',
            'institution_name': i['name']?.toString() ?? '',
          });
        },
      ),
      const SizedBox(height: 16),
      if (selected != null && selected.isNotEmpty) _buildInstitutionCard(selected),
      const SizedBox(height: 12),
      Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [
        Icon(Icons.info_outline, size: 14, color: Colors.grey.shade500), const SizedBox(width: 6),
        Expanded(child: Text(
          'Haushaltsgröße, Einkommen & Dringlichkeit werden pro Antrag erfasst (Tab "Antrag").',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic))),
      ])),
    ]));
  }

  Widget _buildInstitutionCard(Map<String, dynamic> inst) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.indigo.shade300),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.account_balance, size: 28, color: Colors.indigo.shade700),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(inst['name']?.toString() ?? '', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.indigo.shade900)),
          if ((inst['abteilung']?.toString() ?? '').isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 2),
              child: Text(inst['abteilung'].toString(), style: TextStyle(fontSize: 12, color: Colors.indigo.shade700, fontWeight: FontWeight.w500))),
          const SizedBox(height: 6),
          _iconRow(Icons.location_on, '${inst['strasse'] ?? ''}, ${inst['plz'] ?? ''} ${inst['ort'] ?? ''}'),
          if ((inst['telefon']?.toString() ?? '').isNotEmpty) _iconRow(Icons.phone, inst['telefon'].toString()),
          if ((inst['telefon_alt']?.toString() ?? '').isNotEmpty) _iconRow(Icons.phone_in_talk, inst['telefon_alt'].toString()),
          if ((inst['fax']?.toString() ?? '').isNotEmpty) _iconRow(Icons.fax, 'Fax: ${inst['fax']}'),
          if ((inst['email']?.toString() ?? '').isNotEmpty) _iconRow(Icons.email, inst['email'].toString()),
          if ((inst['website']?.toString() ?? '').isNotEmpty) _iconRow(Icons.language, inst['website'].toString()),
          if ((inst['oeffnungszeiten']?.toString() ?? '').isNotEmpty) _iconRow(Icons.schedule, inst['oeffnungszeiten'].toString()),
          if ((inst['zustaendig_fuer']?.toString() ?? '').isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 6),
              child: Text(inst['zustaendig_fuer'].toString(),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontStyle: FontStyle.italic))),
        ])),
      ]),
    );
  }

  Widget _iconRow(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 14, color: Colors.grey.shade600),
      const SizedBox(width: 6),
      Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade800))),
    ]),
  );

  // ────────────────────────── Tab 2: Antrag ──────────────────────────
  Widget _buildAntragTab() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Icon(Icons.assignment, size: 18, color: Colors.indigo.shade700), const SizedBox(width: 8),
        Text('${_vorfaelle.length} Anträge', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const Spacer(),
        FilledButton.icon(
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Neuer Antrag', style: TextStyle(fontSize: 12)),
          style: FilledButton.styleFrom(backgroundColor: Colors.indigo.shade600, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero),
          onPressed: () => _showVorfallDialog(),
        ),
      ])),
      Expanded(child: _vorfaelle.isEmpty
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.assignment_late, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text('Keine Anträge', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ]))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _vorfaelle.length, itemBuilder: (_, i) {
            final v = _vorfaelle[i];
            final status = v['status']?.toString() ?? 'offen';
            final sc = status == 'erledigt' ? Colors.green : status == 'in_bearbeitung' ? Colors.orange : Colors.blue;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(backgroundColor: sc.shade50, child: Icon(Icons.description, size: 18, color: sc.shade700)),
                title: Text(v['typ']?.toString() ?? '—', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if ((v['datum']?.toString() ?? '').isNotEmpty) Text('Datum: ${v['datum']}', style: const TextStyle(fontSize: 11)),
                  if ((v['aktenzeichen']?.toString() ?? '').isNotEmpty) Text('Aktenzeichen: ${v['aktenzeichen']}', style: const TextStyle(fontSize: 11)),
                  if ((v['haushaltsgroesse']?.toString() ?? '').isNotEmpty) Text('Haushalt: ${v['haushaltsgroesse']} Personen', style: const TextStyle(fontSize: 11)),
                  Text('Status: $status', style: TextStyle(fontSize: 11, color: sc.shade700, fontWeight: FontWeight.w500)),
                ]),
                trailing: PopupMenuButton<String>(
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 16), SizedBox(width: 8), Text('Bearbeiten')])),
                    const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 16, color: Colors.red), SizedBox(width: 8), Text('Löschen', style: TextStyle(color: Colors.red))])),
                  ],
                  onSelected: (a) {
                    if (a == 'edit') _showVorfallDialog(existing: v);
                    if (a == 'delete') _deleteVorfall(v);
                  },
                ),
                onTap: () => _showVorfallDialog(existing: v),
              ),
            );
          })),
    ]);
  }

  Future<void> _deleteVorfall(Map<String, dynamic> v) async {
    final c = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      title: const Text('Antrag löschen?'),
      content: Text(v['typ']?.toString() ?? ''),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Abbrechen')),
        TextButton(onPressed: () => Navigator.pop(d, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Löschen')),
      ],
    ));
    if (c != true) return;
    await widget.apiService.deleteWbsVorfall(widget.userId, int.tryParse(v['id'].toString()) ?? 0);
    _load();
  }

  void _showVorfallDialog({Map<String, dynamic>? existing}) {
    final isEdit = existing != null;
    String typ = existing?['typ']?.toString() ?? _antragTypen.first;
    String status = existing?['status']?.toString() ?? 'offen';
    String dringlichkeit = existing?['dringlichkeitsstufe']?.toString() ?? 'normal';
    final datumC = TextEditingController(text: existing?['datum']?.toString() ?? '');
    final aktenC = TextEditingController(text: existing?['aktenzeichen']?.toString() ?? '');
    final haushaltC = TextEditingController(text: existing?['haushaltsgroesse']?.toString() ?? '');
    final brutto = TextEditingController(text: existing?['einkommen_brutto']?.toString() ?? '');
    final netto = TextEditingController(text: existing?['einkommen_netto']?.toString() ?? '');
    final wohnflaeche = TextEditingController(text: existing?['gewuenschte_wohnflaeche']?.toString() ?? '');
    final zimmer = TextEditingController(text: existing?['gewuenschte_zimmerzahl']?.toString() ?? '');
    final notizC = TextEditingController(text: existing?['notiz']?.toString() ?? '');

    Future<void> pickDate() async {
      final p = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
      if (p != null) datumC.text = '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}';
    }

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(isEdit ? 'Antrag bearbeiten' : 'Neuer WBS-Antrag'),
      content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Antragstyp *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: typ,
          isExpanded: true,
          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
          items: _antragTypen.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) => setD(() => typ = v ?? _antragTypen.first),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: datumC, readOnly: true, onTap: pickDate, decoration: const InputDecoration(labelText: 'Antragsdatum', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today, size: 16)))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: aktenC, decoration: const InputDecoration(labelText: 'Aktenzeichen', isDense: true, border: OutlineInputBorder()))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: haushaltC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Haushaltsgröße (Pers.)', isDense: true, border: OutlineInputBorder()))),
          const SizedBox(width: 10),
          Expanded(child: DropdownButtonFormField<String>(
            initialValue: dringlichkeit,
            decoration: const InputDecoration(labelText: 'Dringlichkeit', isDense: true, border: OutlineInputBorder()),
            items: _dringlichkeit.map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 12)))).toList(),
            onChanged: (v) => setD(() => dringlichkeit = v ?? 'normal'),
          )),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: brutto, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Bruttoeinkommen €/Mt', isDense: true, border: OutlineInputBorder()))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: netto, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Nettoeinkommen €/Mt', isDense: true, border: OutlineInputBorder()))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: wohnflaeche, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Gewünschte Wohnfläche (m²)', isDense: true, border: OutlineInputBorder()))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: zimmer, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Zimmerzahl', isDense: true, border: OutlineInputBorder()))),
        ]),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: status,
          decoration: const InputDecoration(labelText: 'Status', isDense: true, border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'offen', child: Text('offen', style: TextStyle(fontSize: 12))),
            DropdownMenuItem(value: 'in_bearbeitung', child: Text('in Bearbeitung', style: TextStyle(fontSize: 12))),
            DropdownMenuItem(value: 'erledigt', child: Text('erledigt', style: TextStyle(fontSize: 12))),
            DropdownMenuItem(value: 'abgelehnt', child: Text('abgelehnt', style: TextStyle(fontSize: 12))),
          ],
          onChanged: (v) => setD(() => status = v ?? 'offen'),
        ),
        const SizedBox(height: 12),
        TextField(controller: notizC, maxLines: 3, decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder())),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.indigo.shade600),
          onPressed: _saving ? null : () async {
            setD(() => _saving = true);
            try {
              await widget.apiService.saveWbsVorfall(widget.userId, {
                if (isEdit) 'id': existing['id'],
                'typ': typ,
                'titel': typ,
                'status': status,
                'datum': datumC.text.trim(),
                'aktenzeichen': aktenC.text.trim(),
                'haushaltsgroesse': haushaltC.text.trim(),
                'einkommen_brutto': brutto.text.trim(),
                'einkommen_netto': netto.text.trim(),
                'dringlichkeitsstufe': dringlichkeit,
                'gewuenschte_wohnflaeche': wohnflaeche.text.trim(),
                'gewuenschte_zimmerzahl': zimmer.text.trim(),
                'notiz': notizC.text.trim(),
              });
              if (mounted) Navigator.pop(ctx);
              _load();
            } catch (e) {
              if (mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
            }
            setD(() => _saving = false);
          },
          child: Text(isEdit ? 'Speichern' : 'Anlegen'),
        ),
      ],
    )));
  }
}
