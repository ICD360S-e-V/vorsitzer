import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import 'korrespondenz_attachments_widget.dart';

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
                onTap: () => _showAntragDetailModal(v),
              ),
            );
          })),
    ]);
  }

  /// Modal with Details / Korrespondenz / Unterlagen / Generator tabs.
  void _showAntragDetailModal(Map<String, dynamic> vorfall) {
    showDialog(context: context, builder: (ctx) => _AntragDetailModal(
      apiService: widget.apiService,
      userId: widget.userId,
      vorfall: vorfall,
      onEdit: () { Navigator.pop(ctx); _showVorfallDialog(existing: vorfall); },
    ));
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

// ──────────────────────────── Antrag Detail Modal ────────────────────────────
class _AntragDetailModal extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final Map<String, dynamic> vorfall;
  final VoidCallback onEdit;
  const _AntragDetailModal({
    required this.apiService,
    required this.userId,
    required this.vorfall,
    required this.onEdit,
  });

  @override
  State<_AntragDetailModal> createState() => _AntragDetailModalState();
}

class _AntragDetailModalState extends State<_AntragDetailModal> {
  bool _generating = false;
  String? _lastGeneratedPath;
  String? _lastError;

  int get _vorfallId => int.tryParse(widget.vorfall['id'].toString()) ?? 0;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: SizedBox(width: 760, height: 600, child: Column(children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
            child: Row(children: [
              Icon(Icons.description, color: Colors.indigo.shade700),
              const SizedBox(width: 8),
              Expanded(child: Text(
                widget.vorfall['typ']?.toString() ?? 'WBS-Antrag',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              )),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          TabBar(
            labelColor: Colors.indigo.shade700,
            unselectedLabelColor: Colors.grey.shade500,
            indicatorColor: Colors.indigo.shade700,
            isScrollable: false,
            tabs: const [
              Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Details'),
              Tab(icon: Icon(Icons.mail_outline, size: 18), text: 'Korrespondenz'),
              Tab(icon: Icon(Icons.attach_file, size: 18), text: 'Unterlagen'),
              Tab(icon: Icon(Icons.picture_as_pdf, size: 18), text: 'Generator'),
            ],
          ),
          Expanded(child: TabBarView(children: [
            _buildDetails(),
            _buildKorrespondenz(),
            _buildUnterlagen(),
            _buildGenerator(),
          ])),
        ])),
      ),
    );
  }

  Widget _buildDetails() {
    final v = widget.vorfall;
    final rows = <(String, String)>[
      ('Antragstyp', v['typ']?.toString() ?? '—'),
      ('Status', v['status']?.toString() ?? 'offen'),
      ('Datum', v['datum']?.toString() ?? ''),
      ('Aktenzeichen', v['aktenzeichen']?.toString() ?? ''),
      ('Haushaltsgröße', v['haushaltsgroesse']?.toString() ?? ''),
      ('Brutto/Mt €', v['einkommen_brutto']?.toString() ?? ''),
      ('Netto/Mt €', v['einkommen_netto']?.toString() ?? ''),
      ('Dringlichkeit', v['dringlichkeitsstufe']?.toString() ?? ''),
      ('Wohnfläche (m²)', v['gewuenschte_wohnflaeche']?.toString() ?? ''),
      ('Zimmerzahl', v['gewuenschte_zimmerzahl']?.toString() ?? ''),
    ];
    return SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ...rows.where((r) => r.$2.isNotEmpty).map((r) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 140, child: Text(r.$1, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500))),
        Expanded(child: Text(r.$2, style: const TextStyle(fontSize: 12))),
      ]))),
      if ((v['notiz']?.toString() ?? '').isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Notiz', style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(6)), child: Text(v['notiz'].toString(), style: const TextStyle(fontSize: 12))),
      ],
      const SizedBox(height: 16),
      OutlinedButton.icon(
        icon: const Icon(Icons.edit, size: 16),
        label: const Text('Bearbeiten'),
        onPressed: widget.onEdit,
      ),
    ]));
  }

  Widget _buildKorrespondenz() {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.mail_outline, size: 48, color: Colors.grey.shade300),
      const SizedBox(height: 12),
      Text('Korrespondenz für WBS folgt', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
      const SizedBox(height: 4),
      Text('(eingehende/ausgehende Schreiben mit der Behörde)', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
    ]));
  }

  Widget _buildUnterlagen() {
    return Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(Icons.attach_file, size: 18, color: Colors.indigo.shade700),
        const SizedBox(width: 8),
        const Text('Unterlagen zum Antrag', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      ]),
      const SizedBox(height: 8),
      Text(
        'Hochgeladene Anhänge (Einkommensnachweise, Mietverträge, Bescheide etc.).',
        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
      ),
      const SizedBox(height: 12),
      Expanded(child: KorrAttachmentsWidget(
        apiService: widget.apiService,
        modul: 'wbs_vorfall',
        korrespondenzId: _vorfallId,
      )),
    ]));
  }

  Widget _buildGenerator() {
    return SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.picture_as_pdf, color: Colors.red.shade700),
        const SizedBox(width: 8),
        const Text('WBS Stadt Ulm — Antragsformular 2026', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      ]),
      const SizedBox(height: 10),
      Text(
        'Das offizielle Antragsformular von ulm.de wird mit den hinterlegten '
        'Mitgliedsdaten vorausgefüllt (Familienname, Vorname, Geburtsdatum, '
        'Adresse, Telefon, E-Mail, Staatsangehörigkeit, Familienstand). '
        'Anschließend prüfen, ergänzen, unterschreiben und per E-Mail an '
        'wbs@ulm.de senden oder ausdrucken.',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.4),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        icon: _generating
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.download, size: 18),
        label: Text(_generating ? 'Wird erstellt…' : 'PDF herunterladen'),
        style: FilledButton.styleFrom(backgroundColor: Colors.indigo.shade600),
        onPressed: _generating ? null : _onPdfDownload,
      ),
      if (_lastGeneratedPath != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.green.shade300)),
          child: Row(children: [
            Icon(Icons.check_circle, color: Colors.green.shade700, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(_lastGeneratedPath!, style: TextStyle(fontSize: 11, color: Colors.green.shade800), overflow: TextOverflow.ellipsis)),
            TextButton.icon(
              icon: const Icon(Icons.open_in_new, size: 14),
              label: const Text('Öffnen'),
              onPressed: () => OpenFilex.open(_lastGeneratedPath!),
            ),
          ]),
        ),
      ],
      if (_lastError != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.red.shade300)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.error_outline, color: Colors.red.shade700, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(_lastError!, style: TextStyle(fontSize: 11, color: Colors.red.shade800))),
          ]),
        ),
      ],
      const SizedBox(height: 20),
      Text('Hinweis: Sensible Angaben (Aufenthaltsstatus, Geburtsname) bleiben '
           'leer und müssen vom Mitglied vor Absendung ergänzt werden.',
           style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
    ]));
  }

  Future<void> _onPdfDownload() async {
    debugPrint('[WBS-PDF] click — calling generateWbsPdf(user=${widget.userId}, vorfall=$_vorfallId)');
    setState(() { _generating = true; _lastError = null; });
    try {
      final bytes = await widget.apiService.generateWbsPdf(userId: widget.userId, vorfallId: _vorfallId);
      debugPrint('[WBS-PDF] response — ${bytes?.length ?? 0} bytes');
      if (!mounted) return;
      if (bytes == null) {
        setState(() { _generating = false; _lastError = 'Server lieferte kein PDF zurück (Status != 200 oder ungültiger Inhalt). Prüfe Server-Logs.'; });
        return;
      }
      // Pick a writable directory. On Linux/Flatpak getDownloadsDirectory()
      // is null, so we walk through the path_provider fallbacks until one
      // works.
      Directory? dir;
      try { dir = await getDownloadsDirectory(); } catch (_) {}
      dir ??= await getApplicationDocumentsDirectory().catchError((_) => Directory.systemTemp);
      final filename = 'WBS_Antrag_${widget.userId}_$_vorfallId.pdf';
      final path = '${dir.path}${Platform.pathSeparator}$filename';
      final f = File(path);
      await f.writeAsBytes(bytes);
      debugPrint('[WBS-PDF] saved to $path');
      if (!mounted) return;
      setState(() { _generating = false; _lastGeneratedPath = path; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('PDF gespeichert: $path'),
        backgroundColor: Colors.green,
        action: SnackBarAction(label: 'Öffnen', textColor: Colors.white, onPressed: () => OpenFilex.open(path)),
      ));
    } catch (e, stack) {
      debugPrint('[WBS-PDF] error: $e\n$stack');
      if (!mounted) return;
      setState(() { _generating = false; _lastError = 'Fehler: $e'; });
    }
  }
}
