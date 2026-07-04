import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// Pflegestufe / Anträge auf Pflegegrad
///
/// Liste der Anträge (Erstantrag, Höherstufung, Herabstufung, Eilantrag)
/// mit dem gesamten Verlauf pro Antrag:
///   • Antragstellung (Datum, Methode: online, persönlich, fax, post)
///   • MD-Begutachtung (Datum, Ort, Gutachter)
///   • Bescheid (Datum, Ergebnis, gültig ab)
///   • Widerspruch (Datum, Begründung, Zweitgutachten-Datum, Ergebnis)
///
/// Alle Felder werden serverseitig mit AES-256-CBC (ev()/dv()) einzeln
/// pro Spalte verschlüsselt — kein JSON-Blob.
///
/// Fristen (Stand 2026-01):
///   • Pflegekasse muss innerhalb 25 Arbeitstagen entscheiden
///   • MD hat zusätzlich 15 Tage
///   • Bei Fristüberschreitung: 70 € pro angebrochene Woche an Antragsteller
///   • Widerspruch: 1 Monat ab Bescheid-Zugang (1 Jahr ohne Rechtsbelehrung)
class MitgliederverwaltungBehordeKrankenkassePflegegrad extends StatefulWidget {
  final ApiService apiService;
  final int userId;

  const MitgliederverwaltungBehordeKrankenkassePflegegrad({
    super.key,
    required this.apiService,
    required this.userId,
  });

  @override
  State<MitgliederverwaltungBehordeKrankenkassePflegegrad> createState() => _State();
}

class _State extends State<MitgliederverwaltungBehordeKrankenkassePflegegrad> {
  bool _loading = false, _loaded = false, _saving = false;
  List<Map<String, dynamic>> _antraege = [];

  static const _antragTypen = [
    'Erstantrag',
    'Höherstufung',
    'Herabstufung (Widerspruch der Kasse)',
    'Wiederholungsantrag (nach Ablehnung)',
    'Eilantrag (verkürztes Verfahren)',
  ];

  static const _methoden = ['online', 'persönlich', 'fax', 'post', 'telefonisch'];

  static const _pflegegrade = [
    '',
    '1', '2', '3', '4', '5',
  ];

  static const _statusList = [
    'offen',
    'begutachtung',
    'bescheid_erhalten',
    'bewilligt',
    'abgelehnt',
    'widerspruch_eingelegt',
    'zweitgutachten',
    'widerspruch_bewilligt',
    'widerspruch_abgelehnt',
    'klage',
  ];

  static const _begutachtungsorte = [
    'Zuhause',
    'Stationär (Klinik/Pflegeheim)',
    'Telefonisch (Sonderregelung)',
    'Aktenlage (ohne Termin)',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final res = await widget.apiService.listPflegegradAntraege(widget.userId);
      if (res['success'] == true && mounted) {
        _antraege = (res['antraege'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    if (mounted) setState(() { _loading = false; _loaded = true; });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded && !_loading) _load();
    if (_loading || !_loaded) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      _buildHeader(),
      Expanded(child: _antraege.isEmpty ? _buildEmpty() : _buildList()),
    ]);
  }

  Widget _buildHeader() {
    return Padding(padding: const EdgeInsets.all(12), child: Row(children: [
      Icon(Icons.assignment, size: 18, color: Colors.purple.shade700),
      const SizedBox(width: 8),
      Text('${_antraege.length} Anträge auf Pflegegrad', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      const Spacer(),
      FilledButton.icon(
        icon: const Icon(Icons.add, size: 16),
        label: const Text('Antrag auf Pflegestufe', style: TextStyle(fontSize: 12)),
        style: FilledButton.styleFrom(backgroundColor: Colors.purple.shade600, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero),
        onPressed: () => _showAntragDialog(),
      ),
    ]));
  }

  Widget _buildEmpty() {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.elderly, size: 48, color: Colors.grey.shade300),
      const SizedBox(height: 8),
      Text('Keine Anträge auf Pflegegrad', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      const SizedBox(height: 4),
      Text('Klicken Sie oben auf „Antrag auf Pflegestufe" um einen neuen anzulegen',
           style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
    ]));
  }

  Widget _buildList() {
    return ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _antraege.length, itemBuilder: (_, i) {
      final a = _antraege[i];
      final status = a['status']?.toString() ?? 'offen';
      final sc = _statusColor(status);
      final ergebnis = a['bescheid_ergebnis']?.toString() ?? '';
      final ziel = a['pflegegrad_ziel']?.toString() ?? '';
      final wsp = (a['widerspruch_eingelegt']?.toString() ?? '').toLowerCase() == 'ja';
      final zg = a['widerspruch_zweitgutachten_datum']?.toString() ?? '';
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: CircleAvatar(backgroundColor: sc.shade50, child: Icon(Icons.elderly, size: 18, color: sc.shade700)),
          title: Row(children: [
            Expanded(child: Text(
              '${a['antrag_typ']?.toString() ?? '—'}${ziel.isNotEmpty ? " → PG $ziel" : ""}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            )),
            if (wsp) Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(4)),
              child: Text('Widerspruch', style: TextStyle(fontSize: 9, color: Colors.orange.shade900, fontWeight: FontWeight.w600)),
            ),
          ]),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if ((a['antrag_datum']?.toString() ?? '').isNotEmpty)
              Text('Antrag: ${a['antrag_datum']} (${a['antrag_methode'] ?? '—'})', style: const TextStyle(fontSize: 11)),
            if ((a['bescheid_datum']?.toString() ?? '').isNotEmpty)
              Text('Bescheid: ${a['bescheid_datum']}${ergebnis.isNotEmpty ? " — $ergebnis" : ""}', style: const TextStyle(fontSize: 11)),
            if (zg.isNotEmpty)
              Text('Zweitgutachten am: $zg', style: TextStyle(fontSize: 11, color: Colors.orange.shade800)),
            Text('Status: ${_prettyStatus(status)}', style: TextStyle(fontSize: 11, color: sc.shade700, fontWeight: FontWeight.w500)),
          ]),
          trailing: PopupMenuButton<String>(
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 16), SizedBox(width: 8), Text('Bearbeiten')])),
              const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 16, color: Colors.red), SizedBox(width: 8), Text('Löschen', style: TextStyle(color: Colors.red))])),
            ],
            onSelected: (act) {
              if (act == 'edit') _showAntragDialog(existing: a);
              if (act == 'delete') _deleteAntrag(a);
            },
          ),
          onTap: () => _showAntragDetailModal(a),
        ),
      );
    });
  }

  MaterialColor _statusColor(String s) {
    switch (s) {
      case 'bewilligt':
      case 'widerspruch_bewilligt':
        return Colors.green;
      case 'abgelehnt':
      case 'widerspruch_abgelehnt':
        return Colors.red;
      case 'widerspruch_eingelegt':
      case 'zweitgutachten':
      case 'klage':
        return Colors.orange;
      case 'begutachtung':
      case 'bescheid_erhalten':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _prettyStatus(String s) {
    switch (s) {
      case 'offen': return 'offen';
      case 'begutachtung': return 'in Begutachtung';
      case 'bescheid_erhalten': return 'Bescheid erhalten';
      case 'bewilligt': return 'bewilligt';
      case 'abgelehnt': return 'abgelehnt';
      case 'widerspruch_eingelegt': return 'Widerspruch eingelegt';
      case 'zweitgutachten': return 'Zweitgutachten läuft';
      case 'widerspruch_bewilligt': return 'Widerspruch bewilligt';
      case 'widerspruch_abgelehnt': return 'Widerspruch abgelehnt';
      case 'klage': return 'Klage (Sozialgericht)';
      default: return s;
    }
  }

  Future<void> _deleteAntrag(Map<String, dynamic> a) async {
    final c = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      title: const Text('Antrag löschen?'),
      content: Text('${a['antrag_typ'] ?? ''}${(a['antrag_datum']?.toString() ?? '').isNotEmpty ? " vom ${a['antrag_datum']}" : ""}'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Abbrechen')),
        TextButton(onPressed: () => Navigator.pop(d, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Löschen')),
      ],
    ));
    if (c != true) return;
    await widget.apiService.deletePflegegradAntrag(widget.userId, int.tryParse(a['id'].toString()) ?? 0);
    _load();
  }

  // ─── Anlage- / Bearbeiten-Dialog ──────────────────────────────────────
  void _showAntragDialog({Map<String, dynamic>? existing}) {
    final isEdit = existing != null;
    String typ = existing?['antrag_typ']?.toString().isNotEmpty == true ? existing!['antrag_typ'].toString() : _antragTypen.first;
    String methode = existing?['antrag_methode']?.toString().isNotEmpty == true ? existing!['antrag_methode'].toString() : _methoden.first;
    String pgZiel = existing?['pflegegrad_ziel']?.toString() ?? '';
    String pgBeantragt = existing?['pflegegrad_beantragt']?.toString() ?? '';
    String status = existing?['status']?.toString().isNotEmpty == true ? existing!['status'].toString() : 'offen';
    final datumC = TextEditingController(text: existing?['antrag_datum']?.toString() ?? '');
    final aktenC = TextEditingController(text: existing?['aktenzeichen']?.toString() ?? '');
    final notizC = TextEditingController(text: existing?['notiz']?.toString() ?? '');

    Future<void> pickDate() async {
      final p = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2015), lastDate: DateTime(2040), locale: const Locale('de'));
      if (p != null) datumC.text = '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}';
    }

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(isEdit ? 'Antrag bearbeiten' : 'Neuer Antrag auf Pflegestufe'),
      content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Antragstyp *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: typ, isExpanded: true,
          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
          items: _antragTypen.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) => setD(() => typ = v ?? _antragTypen.first),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: datumC, readOnly: true, onTap: pickDate, decoration: const InputDecoration(labelText: 'Antragsdatum *', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today, size: 16)))),
          const SizedBox(width: 10),
          Expanded(child: DropdownButtonFormField<String>(
            initialValue: methode,
            decoration: const InputDecoration(labelText: 'Wie eingereicht? *', isDense: true, border: OutlineInputBorder()),
            items: _methoden.map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 12)))).toList(),
            onChanged: (v) => setD(() => methode = v ?? _methoden.first),
          )),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: DropdownButtonFormField<String>(
            initialValue: _pflegegrade.contains(pgBeantragt) ? pgBeantragt : '',
            decoration: const InputDecoration(labelText: 'Aktueller Pflegegrad', isDense: true, border: OutlineInputBorder()),
            items: _pflegegrade.map((p) => DropdownMenuItem(value: p, child: Text(p.isEmpty ? 'Keiner' : 'PG $p', style: const TextStyle(fontSize: 12)))).toList(),
            onChanged: (v) => setD(() => pgBeantragt = v ?? ''),
          )),
          const SizedBox(width: 10),
          Expanded(child: DropdownButtonFormField<String>(
            initialValue: _pflegegrade.contains(pgZiel) ? pgZiel : '',
            decoration: const InputDecoration(labelText: 'Beantragter PG', isDense: true, border: OutlineInputBorder()),
            items: _pflegegrade.map((p) => DropdownMenuItem(value: p, child: Text(p.isEmpty ? '—' : 'PG $p', style: const TextStyle(fontSize: 12)))).toList(),
            onChanged: (v) => setD(() => pgZiel = v ?? ''),
          )),
        ]),
        const SizedBox(height: 12),
        TextField(controller: aktenC, decoration: const InputDecoration(labelText: 'Aktenzeichen', isDense: true, border: OutlineInputBorder())),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _statusList.contains(status) ? status : 'offen',
          decoration: const InputDecoration(labelText: 'Status', isDense: true, border: OutlineInputBorder()),
          items: _statusList.map((s) => DropdownMenuItem(value: s, child: Text(_prettyStatus(s), style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (v) => setD(() => status = v ?? 'offen'),
        ),
        const SizedBox(height: 12),
        TextField(controller: notizC, maxLines: 3, decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder())),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.blue.shade200)),
          child: Row(children: [
            Icon(Icons.info_outline, size: 14, color: Colors.blue.shade700),
            const SizedBox(width: 6),
            Expanded(child: Text(
              'Frist: Pflegekasse muss innerhalb 25 Arbeitstagen entscheiden. Bei Überschreitung 70 €/Woche.',
              style: TextStyle(fontSize: 10, color: Colors.blue.shade800),
            )),
          ]),
        ),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.purple.shade600),
          onPressed: _saving ? null : () async {
            if (datumC.text.trim().isEmpty) {
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Antragsdatum ist Pflicht'), backgroundColor: Colors.orange));
              return;
            }
            setD(() => _saving = true);
            try {
              await widget.apiService.savePflegegradAntrag(widget.userId, {
                if (isEdit) 'id': existing['id'],
                'antrag_typ': typ,
                'antrag_datum': datumC.text.trim(),
                'antrag_methode': methode,
                'pflegegrad_beantragt': pgBeantragt,
                'pflegegrad_ziel': pgZiel,
                'aktenzeichen': aktenC.text.trim(),
                'status': status,
                'notiz': notizC.text.trim(),
                // Preserve existing Bescheid/Widerspruch fields on edit
                if (isEdit) ...{
                  'begutachtung_datum': existing['begutachtung_datum'] ?? '',
                  'begutachtung_ort': existing['begutachtung_ort'] ?? '',
                  'gutachter_name': existing['gutachter_name'] ?? '',
                  'bescheid_datum': existing['bescheid_datum'] ?? '',
                  'bescheid_ergebnis': existing['bescheid_ergebnis'] ?? '',
                  'bescheid_gueltig_ab': existing['bescheid_gueltig_ab'] ?? '',
                  'widerspruch_eingelegt': existing['widerspruch_eingelegt'] ?? '',
                  'widerspruch_datum': existing['widerspruch_datum'] ?? '',
                  'widerspruch_begruendung': existing['widerspruch_begruendung'] ?? '',
                  'widerspruch_zweitgutachten_datum': existing['widerspruch_zweitgutachten_datum'] ?? '',
                  'widerspruch_ergebnis': existing['widerspruch_ergebnis'] ?? '',
                },
              });
              if (ctx.mounted) Navigator.pop(ctx);
              _load();
            } catch (e) {
              if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
            }
            setD(() => _saving = false);
          },
          child: Text(isEdit ? 'Speichern' : 'Anlegen'),
        ),
      ],
    )));
  }

  // ─── Detail Modal: Details / Bescheid / Widerspruch ───────────────────
  void _showAntragDetailModal(Map<String, dynamic> antrag) {
    showDialog(context: context, builder: (ctx) => _AntragDetailModal(
      apiService: widget.apiService,
      userId: widget.userId,
      antrag: antrag,
      antragTypen: _antragTypen,
      methoden: _methoden,
      pflegegrade: _pflegegrade,
      statusList: _statusList,
      begutachtungsorte: _begutachtungsorte,
      prettyStatus: _prettyStatus,
      onSaved: () => _load(),
      onEdit: () { Navigator.pop(ctx); _showAntragDialog(existing: antrag); },
    ));
  }
}

// ══════════════════════════ Antrag Detail Modal ══════════════════════════
class _AntragDetailModal extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final Map<String, dynamic> antrag;
  final List<String> antragTypen;
  final List<String> methoden;
  final List<String> pflegegrade;
  final List<String> statusList;
  final List<String> begutachtungsorte;
  final String Function(String) prettyStatus;
  final VoidCallback onSaved;
  final VoidCallback onEdit;

  const _AntragDetailModal({
    required this.apiService,
    required this.userId,
    required this.antrag,
    required this.antragTypen,
    required this.methoden,
    required this.pflegegrade,
    required this.statusList,
    required this.begutachtungsorte,
    required this.prettyStatus,
    required this.onSaved,
    required this.onEdit,
  });

  @override
  State<_AntragDetailModal> createState() => _AntragDetailModalState();
}

class _AntragDetailModalState extends State<_AntragDetailModal> {
  late Map<String, dynamic> _a;
  bool _saving = false;

  // Bescheid controllers
  late TextEditingController _bescheidDatumC;
  late TextEditingController _bescheidGueltigC;
  late TextEditingController _bescheidErgebnisC;
  late TextEditingController _begutachtungDatumC;
  late TextEditingController _gutachterC;
  String _begutachtungsort = '';

  // Widerspruch controllers
  late TextEditingController _widerspruchDatumC;
  late TextEditingController _widerspruchBegC;
  late TextEditingController _zweitgutachtenC;
  late TextEditingController _widerspruchErgC;
  String _widerspruchEingelegt = 'nein';

  @override
  void initState() {
    super.initState();
    _a = Map<String, dynamic>.from(widget.antrag);
    _bescheidDatumC = TextEditingController(text: _s('bescheid_datum'));
    _bescheidGueltigC = TextEditingController(text: _s('bescheid_gueltig_ab'));
    _bescheidErgebnisC = TextEditingController(text: _s('bescheid_ergebnis'));
    _begutachtungDatumC = TextEditingController(text: _s('begutachtung_datum'));
    _gutachterC = TextEditingController(text: _s('gutachter_name'));
    _begutachtungsort = _s('begutachtung_ort');
    _widerspruchDatumC = TextEditingController(text: _s('widerspruch_datum'));
    _widerspruchBegC = TextEditingController(text: _s('widerspruch_begruendung'));
    _zweitgutachtenC = TextEditingController(text: _s('widerspruch_zweitgutachten_datum'));
    _widerspruchErgC = TextEditingController(text: _s('widerspruch_ergebnis'));
    _widerspruchEingelegt = (_s('widerspruch_eingelegt').toLowerCase() == 'ja') ? 'ja' : 'nein';
  }

  String _s(String k) => _a[k]?.toString() ?? '';

  Future<void> _pickDate(TextEditingController c) async {
    final p = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime(2040),
      locale: const Locale('de'),
    );
    if (p != null) c.text = '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}';
  }

  Future<void> _save(String updatedStatus) async {
    setState(() => _saving = true);
    try {
      // Coerce id explicit to int — server expects (int).
      final id = _a['id'] is int ? _a['id'] as int : int.tryParse(_a['id']?.toString() ?? '') ?? 0;
      if (id <= 0) {
        throw Exception('Antrag-ID fehlt oder ungültig');
      }
      // Sync new form values back into local state so UI reflects saved
      // values immediately if user reopens without a fresh _load().
      final payload = <String, dynamic>{
        'id': id,
        'antrag_typ': _s('antrag_typ'),
        'antrag_datum': _s('antrag_datum'),
        'antrag_methode': _s('antrag_methode'),
        'pflegegrad_beantragt': _s('pflegegrad_beantragt'),
        'pflegegrad_ziel': _s('pflegegrad_ziel'),
        'aktenzeichen': _s('aktenzeichen'),
        'status': updatedStatus,
        'notiz': _s('notiz'),
        'begutachtung_datum': _begutachtungDatumC.text.trim(),
        'begutachtung_ort': _begutachtungsort,
        'gutachter_name': _gutachterC.text.trim(),
        'bescheid_datum': _bescheidDatumC.text.trim(),
        'bescheid_ergebnis': _bescheidErgebnisC.text.trim(),
        'bescheid_gueltig_ab': _bescheidGueltigC.text.trim(),
        'widerspruch_eingelegt': _widerspruchEingelegt,
        'widerspruch_datum': _widerspruchDatumC.text.trim(),
        'widerspruch_begruendung': _widerspruchBegC.text.trim(),
        'widerspruch_zweitgutachten_datum': _zweitgutachtenC.text.trim(),
        'widerspruch_ergebnis': _widerspruchErgC.text.trim(),
      };
      debugPrint('[PFG] save payload keys=${payload.keys.toList()} widerspruch_eingelegt=${payload['widerspruch_eingelegt']} widerspruch_datum=${payload['widerspruch_datum']} bescheid_datum=${payload['bescheid_datum']}');
      final res = await widget.apiService.savePflegegradAntrag(widget.userId, payload);
      debugPrint('[PFG] save response=$res');
      if (res['success'] != true) {
        throw Exception('Server-Fehler: ${res['message'] ?? res.toString()}');
      }
      // Update local _a so re-open of modal shows persisted values.
      _a.addAll(payload);
      widget.onSaved();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gespeichert'), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('[PFG] save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red, duration: const Duration(seconds: 6)));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: SizedBox(width: 780, height: 640, child: Column(children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
            child: Row(children: [
              Icon(Icons.elderly, color: Colors.purple.shade700),
              const SizedBox(width: 8),
              Expanded(child: Text(
                '${_s('antrag_typ').isNotEmpty ? _s('antrag_typ') : "Antrag auf Pflegegrad"}${_s('antrag_datum').isNotEmpty ? " — vom ${_s('antrag_datum')}" : ""}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              )),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          TabBar(
            labelColor: Colors.purple.shade700,
            unselectedLabelColor: Colors.grey.shade500,
            indicatorColor: Colors.purple.shade700,
            tabs: [
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, size: 8, color: _s('antrag_datum').isNotEmpty ? Colors.green : Colors.red),
                const SizedBox(width: 4), const Icon(Icons.info_outline, size: 16),
                const SizedBox(width: 4), const Text('Details'),
              ])),
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, size: 8, color: _s('bescheid_datum').isNotEmpty ? Colors.green : Colors.red),
                const SizedBox(width: 4), const Icon(Icons.assignment_turned_in, size: 16),
                const SizedBox(width: 4), const Text('Bescheid'),
              ])),
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, size: 8, color: _widerspruchEingelegt == 'ja' ? Colors.orange : Colors.grey),
                const SizedBox(width: 4), const Icon(Icons.gavel, size: 16),
                const SizedBox(width: 4), const Text('Widerspruch'),
              ])),
            ],
          ),
          Expanded(child: TabBarView(children: [
            _buildDetailsTab(),
            _buildBescheidTab(),
            _buildWiderspruchTab(),
          ])),
        ])),
      ),
    );
  }

  Widget _buildDetailsTab() {
    final rows = <(String, String)>[
      ('Antragstyp', _s('antrag_typ')),
      ('Antragsdatum', _s('antrag_datum')),
      ('Wie eingereicht', _s('antrag_methode')),
      ('Aktueller PG', _s('pflegegrad_beantragt').isEmpty ? '—' : 'PG ${_s('pflegegrad_beantragt')}'),
      ('Beantragter PG', _s('pflegegrad_ziel').isEmpty ? '—' : 'PG ${_s('pflegegrad_ziel')}'),
      ('Aktenzeichen', _s('aktenzeichen')),
      ('Status', widget.prettyStatus(_s('status').isEmpty ? 'offen' : _s('status'))),
    ];
    return SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ...rows.where((r) => r.$2.isNotEmpty).map((r) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 160, child: Text(r.$1, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500))),
        Expanded(child: SelectableText(r.$2, style: const TextStyle(fontSize: 12))),
      ]))),
      if (_s('notiz').isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Notiz', style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(6)), child: SelectableText(_s('notiz'), style: const TextStyle(fontSize: 12))),
      ],
      const SizedBox(height: 16),
      OutlinedButton.icon(icon: const Icon(Icons.edit, size: 16), label: const Text('Bearbeiten'), onPressed: widget.onEdit),
    ]));
  }

  Widget _buildBescheidTab() {
    return SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader(Icons.medical_information, 'MD-Begutachtung', Colors.blue),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: TextField(
          controller: _begutachtungDatumC, readOnly: true,
          onTap: () => _pickDate(_begutachtungDatumC),
          decoration: const InputDecoration(labelText: 'Begutachtungsdatum', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today, size: 16)),
        )),
        const SizedBox(width: 10),
        Expanded(child: DropdownButtonFormField<String>(
          initialValue: widget.begutachtungsorte.contains(_begutachtungsort) ? _begutachtungsort : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Wo?', isDense: true, border: OutlineInputBorder()),
          items: widget.begutachtungsorte.map((o) => DropdownMenuItem(value: o, child: Text(o, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) => setState(() => _begutachtungsort = v ?? ''),
        )),
      ]),
      const SizedBox(height: 10),
      TextField(controller: _gutachterC, decoration: const InputDecoration(labelText: 'Gutachter (Name / MDK-Nr.)', isDense: true, border: OutlineInputBorder())),

      const SizedBox(height: 20),
      _sectionHeader(Icons.assignment_turned_in, 'Bescheid der Pflegekasse', Colors.green),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: TextField(
          controller: _bescheidDatumC, readOnly: true,
          onTap: () => _pickDate(_bescheidDatumC),
          decoration: const InputDecoration(labelText: 'Bescheiddatum', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today, size: 16)),
        )),
        const SizedBox(width: 10),
        Expanded(child: TextField(
          controller: _bescheidGueltigC, readOnly: true,
          onTap: () => _pickDate(_bescheidGueltigC),
          decoration: const InputDecoration(labelText: 'Gültig ab', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today, size: 16)),
        )),
      ]),
      const SizedBox(height: 10),
      TextField(controller: _bescheidErgebnisC, decoration: const InputDecoration(labelText: 'Ergebnis (z.B. Pflegegrad 2 bewilligt / Antrag abgelehnt)', isDense: true, border: OutlineInputBorder())),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
        child: Row(children: [
          Icon(Icons.timer, size: 16, color: Colors.blue.shade700),
          const SizedBox(width: 6),
          Expanded(child: Text(
            'Frist: 1 Monat ab Zugang zur Einlegung eines Widerspruchs (1 Jahr, wenn Rechtsbelehrung fehlt).',
            style: TextStyle(fontSize: 11, color: Colors.blue.shade900),
          )),
        ]),
      ),
      const SizedBox(height: 16),
      _actionRow(
        primaryLabel: 'Bescheid speichern',
        primaryStatus: _bescheidErgebnisC.text.toLowerCase().contains('abgelehnt') ? 'abgelehnt' : (_bescheidErgebnisC.text.isNotEmpty ? 'bescheid_erhalten' : 'begutachtung'),
      ),
    ]));
  }

  Widget _buildWiderspruchTab() {
    return SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader(Icons.gavel, 'Widerspruch gegen Bescheid', Colors.orange),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade200)),
        child: Row(children: [
          Icon(Icons.info_outline, size: 16, color: Colors.orange.shade800),
          const SizedBox(width: 6),
          Expanded(child: Text(
            'Nach Widerspruch wird i.d.R. ein Zweitgutachten durch den Medizinischen Dienst veranlasst.',
            style: TextStyle(fontSize: 11, color: Colors.orange.shade900),
          )),
        ]),
      ),
      const SizedBox(height: 16),
      Row(children: [
        const Text('Widerspruch eingelegt?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(width: 12),
        ChoiceChip(
          label: const Text('ja', style: TextStyle(fontSize: 11)),
          selected: _widerspruchEingelegt == 'ja',
          selectedColor: Colors.orange.shade200,
          onSelected: (v) => setState(() => _widerspruchEingelegt = 'ja'),
        ),
        const SizedBox(width: 6),
        ChoiceChip(
          label: const Text('nein', style: TextStyle(fontSize: 11)),
          selected: _widerspruchEingelegt == 'nein',
          onSelected: (v) => setState(() => _widerspruchEingelegt = 'nein'),
        ),
      ]),
      if (_widerspruchEingelegt == 'ja') ...[
        const SizedBox(height: 14),
        TextField(
          controller: _widerspruchDatumC, readOnly: true,
          onTap: () => _pickDate(_widerspruchDatumC),
          decoration: const InputDecoration(labelText: 'Widerspruch eingelegt am *', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today, size: 16)),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _widerspruchBegC, maxLines: 4,
          decoration: const InputDecoration(labelText: 'Begründung des Widerspruchs', isDense: true, border: OutlineInputBorder(), alignLabelWithHint: true),
        ),
        const SizedBox(height: 14),
        _sectionHeader(Icons.assignment_ind, 'Zweitgutachten / neue Examinare', Colors.deepPurple),
        const SizedBox(height: 8),
        TextField(
          controller: _zweitgutachtenC, readOnly: true,
          onTap: () => _pickDate(_zweitgutachtenC),
          decoration: const InputDecoration(labelText: 'Zweitgutachten-Termin', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today, size: 16)),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _widerspruchErgC,
          decoration: const InputDecoration(labelText: 'Ergebnis des Widerspruchs (z.B. PG 3 anerkannt / abgelehnt)', isDense: true, border: OutlineInputBorder()),
        ),
      ],
      const SizedBox(height: 20),
      _actionRow(
        primaryLabel: 'Widerspruch speichern',
        primaryStatus: _widerspruchEingelegt != 'ja'
            ? (_s('status').isEmpty ? 'offen' : _s('status'))
            : (_widerspruchErgC.text.toLowerCase().contains('abgelehnt')
                ? 'widerspruch_abgelehnt'
                : (_widerspruchErgC.text.isNotEmpty
                    ? 'widerspruch_bewilligt'
                    : (_zweitgutachtenC.text.isNotEmpty ? 'zweitgutachten' : 'widerspruch_eingelegt'))),
      ),
    ]));
  }

  Widget _sectionHeader(IconData icon, String title, MaterialColor color) {
    return Row(children: [
      Icon(icon, size: 18, color: color.shade700),
      const SizedBox(width: 6),
      Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color.shade800)),
    ]);
  }

  Widget _actionRow({required String primaryLabel, required String primaryStatus}) {
    return Row(mainAxisAlignment: MainAxisAlignment.end, children: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Schließen')),
      const SizedBox(width: 8),
      FilledButton.icon(
        icon: _saving
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.save, size: 16),
        label: Text(_saving ? 'Speichert…' : primaryLabel),
        style: FilledButton.styleFrom(backgroundColor: Colors.purple.shade600),
        onPressed: _saving ? null : () => _save(primaryStatus),
      ),
    ]);
  }
}
