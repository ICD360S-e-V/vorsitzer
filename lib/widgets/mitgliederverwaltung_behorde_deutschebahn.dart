import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/clipboard_helper.dart';

/// Deutsche Bahn — Mobilitätsservice-Zentrale (MSZ)
///
/// Two sub-tabs:
///   • "Zuständige Deutsche Bahn" — MSZ contact card + optional selection
///   • "Vorfall" — list of Hilfeleistung-Anmeldungen (Ein-/Aus-/Umsteigehilfe)
///     with journey details (Reiseverbindung: von/nach, Datum, Uhrzeit, Zug).
class MitgliederverwaltungBehordeDeutscheBahn extends StatefulWidget {
  final ApiService apiService;
  final int userId;

  const MitgliederverwaltungBehordeDeutscheBahn({
    super.key,
    required this.apiService,
    required this.userId,
  });

  @override
  State<MitgliederverwaltungBehordeDeutscheBahn> createState() => _State();
}

class _State extends State<MitgliederverwaltungBehordeDeutscheBahn> with TickerProviderStateMixin {
  late final TabController _tabCtrl;
  bool _loaded = false, _loading = false, _saving = false;

  Map<String, dynamic> _data = {};
  List<Map<String, dynamic>> _vorfaelle = [];
  List<Map<String, dynamic>> _institutionen = [];

  static const _hilfeTypen = [
    'Einsteigehilfe',
    'Aussteigehilfe',
    'Umsteigehilfe',
    'Ein-, Um- und Aussteigehilfe (kombiniert)',
    'Nur Beratung / Auskunft',
    'Sonstiges',
  ];

  static const _zugTypen = ['ICE', 'IC/EC', 'RE/RB', 'S-Bahn', 'Sonstiges'];

  static const _hilfsmittel = [
    'Keine',
    'Rollstuhl (manuell)',
    'Rollstuhl (elektrisch)',
    'Rollator',
    'Blindenstock',
    'Blindenführhund',
    'Sonstige',
  ];

  static const _statusList = ['angemeldet', 'bestätigt', 'wahrgenommen', 'nicht wahrgenommen', 'storniert', 'abgelehnt'];

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
      final res = await widget.apiService.getDeutscheBahnData(widget.userId);
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
      final inst = await widget.apiService.listDeutscheBahnInstitutionen();
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
      await widget.apiService.saveDeutscheBahnData(widget.userId, mapped);
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
        labelColor: Colors.red.shade700,
        unselectedLabelColor: Colors.grey.shade500,
        indicatorColor: Colors.red.shade700,
        tabs: [
          Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, size: 8, color: _v('institution_id').isNotEmpty ? Colors.green : Colors.red),
            const SizedBox(width: 4), const Icon(Icons.train, size: 16),
            const SizedBox(width: 4), const Text('Zuständige Deutsche Bahn'),
          ])),
          Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, size: 8, color: _vorfaelle.isNotEmpty ? Colors.green : Colors.red),
            const SizedBox(width: 4), const Icon(Icons.accessible, size: 16),
            const SizedBox(width: 4), const Text('Vorfall'),
          ])),
        ],
      ),
      Expanded(child: TabBarView(controller: _tabCtrl, children: [_buildInstitutionTab(), _buildVorfallTab()])),
    ]);
  }

  // ────────────────────────── Tab 1: Zuständige Deutsche Bahn ──────────────────────────
  Widget _buildInstitutionTab() {
    final selId = int.tryParse(_v('institution_id'));
    Map<String, dynamic>? selected;
    if (selId != null) {
      selected = _institutionen.firstWhere(
        (i) => (i['id'] as int?) == selId || int.tryParse(i['id'].toString()) == selId,
        orElse: () => {},
      );
    }
    // Auto-select MSZ (only entry today) — nothing to search for.
    if (selected == null && _institutionen.length == 1) {
      final auto = _institutionen.first;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_v('institution_id').isEmpty) {
          _saveFields({
            'institution_id': auto['id']?.toString() ?? '',
            'institution_name': auto['name']?.toString() ?? '',
          });
        }
      });
      selected = auto;
    }

    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Zuständige Stelle für Mobilitätshilfe', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
      const SizedBox(height: 4),
      Text('Die Mobilitätsservice-Zentrale (MSZ) der Deutschen Bahn organisiert '
           'Ein-, Aus- und Umsteigehilfen an ca. 300 Bahnhöfen bundesweit.',
           style: TextStyle(fontSize: 11, color: Colors.grey.shade700, height: 1.4)),
      const SizedBox(height: 12),
      if (selected != null && selected.isNotEmpty) _buildInstitutionCard(selected),
      const SizedBox(height: 12),
      Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [
        Icon(Icons.info_outline, size: 14, color: Colors.grey.shade500), const SizedBox(width: 6),
        Expanded(child: Text(
          'Anmeldung bis spätestens 20 Uhr am Vortag der Reise. Bei Auslandsreisen 24 Stunden Vorlauf.',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic))),
      ])),
    ]));
  }

  Widget _buildInstitutionCard(Map<String, dynamic> inst) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade300),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.train, size: 28, color: Colors.red.shade700),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(inst['name']?.toString() ?? '', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.red.shade900)),
          if ((inst['abteilung']?.toString() ?? '').isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 2),
              child: Text(inst['abteilung'].toString(), style: TextStyle(fontSize: 12, color: Colors.red.shade700, fontWeight: FontWeight.w500))),
          const SizedBox(height: 8),
          if ((inst['telefon']?.toString() ?? '').isNotEmpty)
            _infoRow(Icons.phone, 'Telefon', inst['telefon'].toString(), copyable: true),
          if ((inst['email']?.toString() ?? '').isNotEmpty)
            _infoRow(Icons.email, 'E-Mail', inst['email'].toString(), copyable: true, copyLabel: 'E-Mail'),
          if ((inst['website']?.toString() ?? '').isNotEmpty)
            _infoRow(Icons.language, 'Website', inst['website'].toString(), copyable: true),
          if ((inst['oeffnungszeiten']?.toString() ?? '').isNotEmpty)
            _infoRow(Icons.schedule, 'Öffnungszeiten', inst['oeffnungszeiten'].toString()),
          if ((inst['zustaendig_fuer']?.toString() ?? '').isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 8),
              child: Text(inst['zustaendig_fuer'].toString(),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontStyle: FontStyle.italic))),
          if ((inst['notiz']?.toString() ?? '').isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 6),
              child: Text(inst['notiz'].toString(),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
        ])),
      ]),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, {bool copyable = false, String? copyLabel}) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Icon(icon, size: 14, color: Colors.grey.shade600), const SizedBox(width: 8),
      SizedBox(width: 110, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600))),
      Expanded(child: SelectableText(value, style: const TextStyle(fontSize: 11))),
      if (copyable) InkWell(
        onTap: () => ClipboardHelper.copy(context, value, copyLabel ?? label),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(Icons.copy, size: 14, color: Colors.blue.shade600),
        ),
      ),
    ]));
  }

  // ────────────────────────── Tab 2: Vorfall / Hilfeleistung ──────────────────────────
  Widget _buildVorfallTab() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Icon(Icons.accessible, size: 18, color: Colors.red.shade700), const SizedBox(width: 8),
        Text('${_vorfaelle.length} Hilfeleistungen', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const Spacer(),
        FilledButton.icon(
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Neue Hilfeleistung', style: TextStyle(fontSize: 12)),
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero),
          onPressed: () => _showVorfallDialog(),
        ),
      ])),
      Expanded(child: _vorfaelle.isEmpty
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.accessible, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text('Keine Hilfeleistungen erfasst', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            const SizedBox(height: 4),
            Text('(Ein-/Aus-/Umsteigehilfe im Zug)', style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
          ]))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _vorfaelle.length, itemBuilder: (_, i) {
            final v = _vorfaelle[i];
            final status = v['status']?.toString() ?? 'angemeldet';
            final sc = status == 'wahrgenommen' ? Colors.green
                : status == 'bestätigt' ? Colors.blue
                : status == 'storniert' || status == 'abgelehnt' || status == 'nicht wahrgenommen' ? Colors.red
                : Colors.orange;
            final von = v['von_bahnhof']?.toString() ?? '';
            final nach = v['nach_bahnhof']?.toString() ?? '';
            final route = [von, nach].where((s) => s.isNotEmpty).join(' → ');
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(backgroundColor: sc.shade50, child: Icon(Icons.accessible, size: 18, color: sc.shade700)),
                title: Text(v['hilfe_typ']?.toString().isNotEmpty == true ? v['hilfe_typ'].toString() : (v['typ']?.toString() ?? '—'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (route.isNotEmpty) Text(route, style: const TextStyle(fontSize: 11)),
                  if ((v['reise_datum']?.toString() ?? '').isNotEmpty || (v['reise_uhrzeit']?.toString() ?? '').isNotEmpty)
                    Text('Reise: ${v['reise_datum'] ?? ''} ${v['reise_uhrzeit'] ?? ''}'.trim(), style: const TextStyle(fontSize: 11)),
                  if ((v['zug_typ']?.toString() ?? '').isNotEmpty || (v['zug_nummer']?.toString() ?? '').isNotEmpty)
                    Text('Zug: ${v['zug_typ'] ?? ''} ${v['zug_nummer'] ?? ''}'.trim(), style: const TextStyle(fontSize: 11)),
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
      title: const Text('Hilfeleistung löschen?'),
      content: Text(v['hilfe_typ']?.toString() ?? v['typ']?.toString() ?? ''),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Abbrechen')),
        TextButton(onPressed: () => Navigator.pop(d, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Löschen')),
      ],
    ));
    if (c != true) return;
    await widget.apiService.deleteDeutscheBahnVorfall(widget.userId, int.tryParse(v['id'].toString()) ?? 0);
    _load();
  }

  void _showVorfallDialog({Map<String, dynamic>? existing}) {
    final isEdit = existing != null;
    String hilfeTyp = existing?['hilfe_typ']?.toString().isNotEmpty == true ? existing!['hilfe_typ'].toString() : _hilfeTypen.first;
    String status = existing?['status']?.toString().isNotEmpty == true ? existing!['status'].toString() : 'angemeldet';
    String zugTyp = existing?['zug_typ']?.toString().isNotEmpty == true ? existing!['zug_typ'].toString() : _zugTypen.first;
    String hilfsmittel = existing?['hilfsmittel']?.toString().isNotEmpty == true ? existing!['hilfsmittel'].toString() : _hilfsmittel.first;
    String begleit = existing?['begleitperson']?.toString().isNotEmpty == true ? existing!['begleitperson'].toString() : 'nein';
    final datumC = TextEditingController(text: existing?['reise_datum']?.toString() ?? '');
    final uhrzeitC = TextEditingController(text: existing?['reise_uhrzeit']?.toString() ?? '');
    final vonC = TextEditingController(text: existing?['von_bahnhof']?.toString() ?? '');
    final nachC = TextEditingController(text: existing?['nach_bahnhof']?.toString() ?? '');
    final zugNrC = TextEditingController(text: existing?['zug_nummer']?.toString() ?? '');
    final begleitAnzC = TextEditingController(text: existing?['begleitperson_anzahl']?.toString() ?? '');
    final buchungC = TextEditingController(text: existing?['buchungsnummer']?.toString() ?? '');
    final bahnbonusC = TextEditingController(text: existing?['bahnbonus_nummer']?.toString() ?? '');
    final aktenC = TextEditingController(text: existing?['aktenzeichen']?.toString() ?? '');
    final notizC = TextEditingController(text: existing?['notiz']?.toString() ?? '');

    Future<void> pickDate() async {
      final p = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now().subtract(const Duration(days: 30)), lastDate: DateTime(2040), locale: const Locale('de'));
      if (p != null) datumC.text = '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}';
    }
    Future<void> pickTime() async {
      final p = await showTimePicker(context: context, initialTime: TimeOfDay.now());
      if (p != null) uhrzeitC.text = '${p.hour.toString().padLeft(2, '0')}:${p.minute.toString().padLeft(2, '0')}';
    }

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(isEdit ? 'Hilfeleistung bearbeiten' : 'Neue Hilfeleistung — MSZ'),
      content: SizedBox(width: 560, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Art der Hilfe *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: hilfeTyp,
          isExpanded: true,
          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
          items: _hilfeTypen.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) => setD(() => hilfeTyp = v ?? _hilfeTypen.first),
        ),
        const SizedBox(height: 12),
        const Text('Reiseverbindung', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: TextField(controller: vonC, decoration: const InputDecoration(labelText: 'Von (Bahnhof)', isDense: true, border: OutlineInputBorder(), prefixIcon: Icon(Icons.train, size: 16)))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: nachC, decoration: const InputDecoration(labelText: 'Nach (Bahnhof)', isDense: true, border: OutlineInputBorder(), prefixIcon: Icon(Icons.flag, size: 16)))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: datumC, readOnly: true, onTap: pickDate, decoration: const InputDecoration(labelText: 'Reisedatum', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today, size: 16)))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: uhrzeitC, readOnly: true, onTap: pickTime, decoration: const InputDecoration(labelText: 'Uhrzeit', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.schedule, size: 16)))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(flex: 2, child: DropdownButtonFormField<String>(
            initialValue: zugTyp,
            decoration: const InputDecoration(labelText: 'Zugart', isDense: true, border: OutlineInputBorder()),
            items: _zugTypen.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12)))).toList(),
            onChanged: (v) => setD(() => zugTyp = v ?? _zugTypen.first),
          )),
          const SizedBox(width: 10),
          Expanded(flex: 3, child: TextField(controller: zugNrC, decoration: const InputDecoration(labelText: 'Zug-Nr. (z.B. ICE 599)', isDense: true, border: OutlineInputBorder()))),
        ]),
        const SizedBox(height: 14),
        const Text('Hilfsmittel & Begleitung', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: hilfsmittel,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Hilfsmittel', isDense: true, border: OutlineInputBorder()),
          items: _hilfsmittel.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (v) => setD(() => hilfsmittel = v ?? _hilfsmittel.first),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(flex: 2, child: DropdownButtonFormField<String>(
            initialValue: begleit,
            decoration: const InputDecoration(labelText: 'Begleitperson', isDense: true, border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'nein', child: Text('nein', style: TextStyle(fontSize: 12))),
              DropdownMenuItem(value: 'ja', child: Text('ja', style: TextStyle(fontSize: 12))),
            ],
            onChanged: (v) => setD(() => begleit = v ?? 'nein'),
          )),
          const SizedBox(width: 10),
          Expanded(flex: 3, child: TextField(
            controller: begleitAnzC,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Anzahl Begleitpersonen', isDense: true, border: OutlineInputBorder()),
          )),
        ]),
        const SizedBox(height: 14),
        const Text('Buchung & Referenzen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: TextField(controller: buchungC, decoration: const InputDecoration(labelText: 'Buchungsnummer', isDense: true, border: OutlineInputBorder()))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: bahnbonusC, decoration: const InputDecoration(labelText: 'BahnBonus-Nr.', isDense: true, border: OutlineInputBorder()))),
        ]),
        const SizedBox(height: 10),
        TextField(controller: aktenC, decoration: const InputDecoration(labelText: 'MSZ-Aktenzeichen (falls vergeben)', isDense: true, border: OutlineInputBorder())),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: status,
          decoration: const InputDecoration(labelText: 'Status', isDense: true, border: OutlineInputBorder()),
          items: _statusList.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (v) => setD(() => status = v ?? 'angemeldet'),
        ),
        const SizedBox(height: 10),
        TextField(controller: notizC, maxLines: 3, decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder())),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
          onPressed: _saving ? null : () async {
            setD(() => _saving = true);
            try {
              await widget.apiService.saveDeutscheBahnVorfall(widget.userId, {
                if (isEdit) 'id': existing['id'],
                'typ': hilfeTyp,
                'titel': hilfeTyp,
                'status': status,
                'reise_datum': datumC.text.trim(),
                'reise_uhrzeit': uhrzeitC.text.trim(),
                'von_bahnhof': vonC.text.trim(),
                'nach_bahnhof': nachC.text.trim(),
                'zug_typ': zugTyp,
                'zug_nummer': zugNrC.text.trim(),
                'hilfe_typ': hilfeTyp,
                'hilfsmittel': hilfsmittel,
                'begleitperson': begleit,
                'begleitperson_anzahl': begleitAnzC.text.trim(),
                'buchungsnummer': buchungC.text.trim(),
                'bahnbonus_nummer': bahnbonusC.text.trim(),
                'aktenzeichen': aktenC.text.trim(),
                'notiz': notizC.text.trim(),
              });
              if (ctx.mounted) Navigator.pop(ctx);
              _load();
            } catch (e) {
              if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
            }
            setD(() => _saving = false);
          },
          child: Text(isEdit ? 'Speichern' : 'Anmelden'),
        ),
      ],
    )));
  }
}
