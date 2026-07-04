import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'korrespondenz_attachments_widget.dart';

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

  // Widerspruch state (simple flag — details live in _WiderspruchDetailModal)
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
        // Widerspruch-Detail-Felder werden im _WiderspruchDetailModal
        // separat gespeichert — hier nur den existierenden Wert erhalten.
        'widerspruch_datum': _s('widerspruch_datum'),
        'widerspruch_methode': _s('widerspruch_methode'),
        'widerspruch_anwalt': _s('widerspruch_anwalt'),
        'widerspruch_anwalt_name': _s('widerspruch_anwalt_name'),
        'widerspruch_begruendung': _s('widerspruch_begruendung'),
        'widerspruch_zweitgutachten_datum': _s('widerspruch_zweitgutachten_datum'),
        'widerspruch_bescheid_datum': _s('widerspruch_bescheid_datum'),
        'widerspruch_bescheid_ergebnis': _s('widerspruch_bescheid_ergebnis'),
        'widerspruch_bescheid_pflegegrad': _s('widerspruch_bescheid_pflegegrad'),
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
    if (_widerspruchEingelegt != 'ja') {
      return SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionHeader(Icons.gavel, 'Widerspruch gegen Bescheid', Colors.orange),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade200)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.info_outline, size: 16, color: Colors.orange.shade800),
              const SizedBox(width: 6),
              Text('Widerspruchsverfahren', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange.shade900)),
            ]),
            const SizedBox(height: 6),
            Text(
              'Wenn Sie mit dem Bescheid nicht einverstanden sind, können Sie innerhalb 1 Monats '
              '(1 Jahr, wenn Rechtsbelehrung fehlt) Widerspruch bei der Pflegekasse einlegen. '
              'Danach wird i.d.R. ein Zweitgutachten durch den Medizinischen Dienst veranlasst.',
              style: TextStyle(fontSize: 11, color: Colors.orange.shade900, height: 1.4),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        Center(child: FilledButton.icon(
          icon: const Icon(Icons.gavel, size: 18),
          label: const Text('Widerspruch einlegen'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.orange.shade700,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
          onPressed: _saving ? null : _showWiderspruchEinlegenDialog,
        )),
        const SizedBox(height: 20),
        Center(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Schließen'))),
      ]));
    }

    // Widerspruch bereits eingelegt → Zusammenfassungs-Card + „Details öffnen"-Button
    final wsDatum = _s('widerspruch_datum');
    final wsMethode = _s('widerspruch_methode');
    final wsAnwalt = _s('widerspruch_anwalt').toLowerCase() == 'ja';
    final wsAnwaltName = _s('widerspruch_anwalt_name');
    final zgDatum = _s('widerspruch_zweitgutachten_datum');
    final wsBescheid = _s('widerspruch_bescheid_datum');
    final wsBescheidErgebnis = _s('widerspruch_bescheid_ergebnis');
    return SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader(Icons.gavel, 'Widerspruch wurde eingelegt', Colors.orange),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange.shade300)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.check_circle, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            Text('Widerspruch eingelegt', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
          ]),
          const SizedBox(height: 10),
          if (wsDatum.isNotEmpty) _summaryRow(Icons.calendar_today, 'Datum', wsDatum),
          if (wsMethode.isNotEmpty) _summaryRow(Icons.send, 'Eingereicht per', wsMethode),
          _summaryRow(Icons.person, 'Anwalt', wsAnwalt ? (wsAnwaltName.isNotEmpty ? 'ja — $wsAnwaltName' : 'ja') : 'nein'),
          if (zgDatum.isNotEmpty) _summaryRow(Icons.assignment_ind, 'Zweitgutachten', zgDatum),
          if (wsBescheid.isNotEmpty) _summaryRow(Icons.assignment_turned_in, 'Widerspruchs-Bescheid', '$wsBescheid${wsBescheidErgebnis.isNotEmpty ? " — $wsBescheidErgebnis" : ""}'),
        ]),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700, minimumSize: const Size.fromHeight(46)),
        icon: const Icon(Icons.open_in_new, size: 18),
        label: const Text('Widerspruch-Details öffnen (Details / Zweitgutachten / Bescheid)'),
        onPressed: _openWiderspruchDetailModal,
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        icon: const Icon(Icons.undo, size: 16, color: Colors.red),
        label: const Text('Widerspruch zurückziehen', style: TextStyle(color: Colors.red)),
        style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red), minimumSize: const Size.fromHeight(40)),
        onPressed: _saving ? null : _confirmWiderspruchZurueckziehen,
      ),
    ]));
  }

  Widget _summaryRow(IconData icon, String label, String value) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 14, color: Colors.orange.shade700),
      const SizedBox(width: 8),
      SizedBox(width: 140, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w600))),
      Expanded(child: SelectableText(value, style: const TextStyle(fontSize: 12))),
    ]));
  }

  Future<void> _confirmWiderspruchZurueckziehen() async {
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      title: const Text('Widerspruch zurückziehen?'),
      content: const Text('Alle Widerspruchs-Daten (Datum, Methode, Anwalt, Begründung, Zweitgutachten, Widerspruchs-Bescheid) werden gelöscht.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Abbrechen')),
        TextButton(onPressed: () => Navigator.pop(d, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Zurückziehen')),
      ],
    ));
    if (ok != true) return;
    setState(() {
      _widerspruchEingelegt = 'nein';
      _a['widerspruch_eingelegt'] = 'nein';
      for (final k in const ['widerspruch_datum','widerspruch_methode','widerspruch_anwalt','widerspruch_anwalt_name','widerspruch_begruendung','widerspruch_zweitgutachten_datum','widerspruch_bescheid_datum','widerspruch_bescheid_ergebnis','widerspruch_bescheid_pflegegrad']) {
        _a[k] = '';
      }
    });
    await _save(_s('bescheid_datum').isNotEmpty ? 'bescheid_erhalten' : 'offen');
  }

  /// Dialog zum Einlegen eines Widerspruchs — Datum, Methode, Anwalt, Begründung.
  void _showWiderspruchEinlegenDialog() {
    final datumC = TextEditingController(text: '');
    String methode = 'schriftlich per Post';
    String anwalt = 'nein';
    final anwaltNameC = TextEditingController();
    final begC = TextEditingController();

    const methoden = ['schriftlich per Post', 'per Fax', 'per E-Mail (online)', 'persönlich beim Termin'];

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Text('Widerspruch einlegen'),
      content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Widerspruch gegen Bescheid vom ${_s('bescheid_datum').isEmpty ? "—" : _s('bescheid_datum')}',
             style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
        const SizedBox(height: 12),
        TextField(
          controller: datumC, readOnly: true,
          decoration: const InputDecoration(labelText: 'Widerspruch eingelegt am *', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today, size: 16)),
          onTap: () async {
            final p = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2015), lastDate: DateTime(2040), locale: const Locale('de'));
            if (p != null) datumC.text = '${p.day.toString().padLeft(2,'0')}.${p.month.toString().padLeft(2,'0')}.${p.year}';
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: methode,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Wie eingereicht? *', isDense: true, border: OutlineInputBorder()),
          items: methoden.map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (v) => setD(() => methode = v ?? methoden.first),
        ),
        const SizedBox(height: 12),
        const Text('Durch Anwalt eingereicht?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Row(children: [
          ChoiceChip(
            label: const Text('nein', style: TextStyle(fontSize: 11)),
            selected: anwalt == 'nein',
            onSelected: (_) => setD(() => anwalt = 'nein'),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('ja', style: TextStyle(fontSize: 11)),
            selected: anwalt == 'ja',
            selectedColor: Colors.orange.shade200,
            onSelected: (_) => setD(() => anwalt = 'ja'),
          ),
        ]),
        if (anwalt == 'ja') ...[
          const SizedBox(height: 10),
          TextField(controller: anwaltNameC, decoration: const InputDecoration(labelText: 'Kanzlei / Anwalt (Name, Adresse)', isDense: true, border: OutlineInputBorder())),
        ],
        const SizedBox(height: 12),
        TextField(controller: begC, maxLines: 4, decoration: const InputDecoration(labelText: 'Begründung des Widerspruchs', isDense: true, border: OutlineInputBorder(), alignLabelWithHint: true)),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700),
          onPressed: () async {
            if (datumC.text.trim().isEmpty) {
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Widerspruchsdatum ist Pflicht'), backgroundColor: Colors.orange));
              return;
            }
            // Update local state, then save.
            _a['widerspruch_eingelegt'] = 'ja';
            _a['widerspruch_datum'] = datumC.text.trim();
            _a['widerspruch_methode'] = methode;
            _a['widerspruch_anwalt'] = anwalt;
            _a['widerspruch_anwalt_name'] = anwaltNameC.text.trim();
            _a['widerspruch_begruendung'] = begC.text.trim();
            setState(() => _widerspruchEingelegt = 'ja');
            Navigator.pop(ctx);
            await _save('widerspruch_eingelegt');
            // Reopen der Detail-Modal ist der nächste natürliche Schritt für den User.
          },
          child: const Text('Widerspruch speichern'),
        ),
      ],
    )));
  }

  /// Öffnet das Detail-Modal für einen bereits eingelegten Widerspruch
  /// mit 3 Sub-Tabs: Details / Zweitgutachten / Bescheid.
  void _openWiderspruchDetailModal() {
    showDialog(context: context, builder: (ctx) => _WiderspruchDetailModal(
      apiService: widget.apiService,
      userId: widget.userId,
      antragId: (_a['id'] is int) ? _a['id'] as int : int.tryParse(_a['id'].toString()) ?? 0,
      antrag: _a,
      onSaved: (updated) {
        // Merge back into parent state so the summary card refreshes.
        setState(() => _a.addAll(updated));
        widget.onSaved();
      },
    ));
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

// ══════════════════════════ Widerspruch Detail Modal ══════════════════════════
// Erscheint nach dem Einlegen des Widerspruchs (Tab „Widerspruch" → Button
// „Details öffnen"). Enthält 3 Sub-Tabs:
//   • Details        — Datum, Methode, Anwalt, Begründung (bearbeitbar)
//   • Zweitgutachten — Termin + Upload des Termin-Briefs vom Med. Dienst
//                       (KorrAttachmentsWidget mit modul='pflegegrad_zweitgutachten')
//   • Bescheid       — Widerspruchs-Bescheid: Datum, Ergebnis, neuer PG
//
// Nach dem Speichern wird das übergeordnete Antrag-Modal via onSaved über
// die neuen Werte informiert, damit die Summary-Card sofort refreshed.
class _WiderspruchDetailModal extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int antragId;
  final Map<String, dynamic> antrag;
  final void Function(Map<String, dynamic> updated) onSaved;

  const _WiderspruchDetailModal({
    required this.apiService,
    required this.userId,
    required this.antragId,
    required this.antrag,
    required this.onSaved,
  });

  @override
  State<_WiderspruchDetailModal> createState() => _WiderspruchDetailModalState();
}

class _WiderspruchDetailModalState extends State<_WiderspruchDetailModal> {
  late Map<String, dynamic> _a;
  bool _saving = false;

  // Details
  late TextEditingController _datumC;
  late TextEditingController _anwaltNameC;
  late TextEditingController _begC;
  String _methode = 'schriftlich per Post';
  String _anwalt = 'nein';

  // Zweitgutachten
  late TextEditingController _zgDatumC;

  // Bescheid
  late TextEditingController _bescheidDatumC;
  late TextEditingController _bescheidErgebnisC;
  String _bescheidPg = '';

  // Medizinischer Dienst (Referenz auf medizinischer_dienst_datenbank)
  List<Map<String, dynamic>> _mdList = [];
  bool _mdLoaded = false;

  static const _methoden = ['schriftlich per Post', 'per Fax', 'per E-Mail (online)', 'persönlich beim Termin'];
  static const _pflegegrade = ['', '1', '2', '3', '4', '5'];

  String _s(String k) => _a[k]?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    _a = Map<String, dynamic>.from(widget.antrag);
    _datumC = TextEditingController(text: _s('widerspruch_datum'));
    _anwaltNameC = TextEditingController(text: _s('widerspruch_anwalt_name'));
    _begC = TextEditingController(text: _s('widerspruch_begruendung'));
    _methode = _methoden.contains(_s('widerspruch_methode')) ? _s('widerspruch_methode') : _methoden.first;
    _anwalt = _s('widerspruch_anwalt').toLowerCase() == 'ja' ? 'ja' : 'nein';
    _zgDatumC = TextEditingController(text: _s('widerspruch_zweitgutachten_datum'));
    _bescheidDatumC = TextEditingController(text: _s('widerspruch_bescheid_datum'));
    _bescheidErgebnisC = TextEditingController(text: _s('widerspruch_bescheid_ergebnis'));
    _bescheidPg = _pflegegrade.contains(_s('widerspruch_bescheid_pflegegrad')) ? _s('widerspruch_bescheid_pflegegrad') : '';
    _loadMdList();
  }

  Future<void> _loadMdList() async {
    try {
      final res = await widget.apiService.listMedizinischerDienst();
      if (res['success'] == true && mounted) {
        setState(() {
          _mdList = (res['md'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _mdLoaded = true;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadGutachterList(int mdId) async {
    if (_gutachterLoadedForMdId == mdId && _gutachterLoaded) return;
    _gutachterLoadedForMdId = mdId;
    try {
      final res = await widget.apiService.listMdGutachter(mdId);
      if (res['success'] == true && mounted) {
        setState(() {
          _gutachterList = (res['gutachter'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _gutachterLoaded = true;
        });
      }
    } catch (_) {}
  }

  void _showNeuerGutachterDialog(int mdId, String mdName) {
    final vornameC = TextEditingController();
    final nachnameC = TextEditingController();
    final notizC = TextEditingController();
    String qualifikation = 'Pflegefachperson';
    const qualifikationen = ['Pflegefachperson', 'Ärztin / Arzt', 'Sozialpädagoge/-in', 'Ergotherapeut/-in', 'Andere'];

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Text('Neuer Gutachter anlegen'),
      content: SizedBox(width: 460, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('für $mdName', style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: vornameC, decoration: const InputDecoration(labelText: 'Vorname *', isDense: true, border: OutlineInputBorder()))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: nachnameC, decoration: const InputDecoration(labelText: 'Nachname *', isDense: true, border: OutlineInputBorder()))),
        ]),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: qualifikation,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Qualifikation', isDense: true, border: OutlineInputBorder()),
          items: qualifikationen.map((q) => DropdownMenuItem(value: q, child: Text(q, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (v) => setD(() => qualifikation = v ?? 'Pflegefachperson'),
        ),
        const SizedBox(height: 12),
        TextField(controller: notizC, maxLines: 2, decoration: const InputDecoration(labelText: 'Notiz (optional, z.B. „Landkreis Ulm")', isDense: true, border: OutlineInputBorder())),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.deepPurple.shade700),
          onPressed: () async {
            if (vornameC.text.trim().isEmpty || nachnameC.text.trim().isEmpty) {
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Vorname und Nachname sind Pflicht'), backgroundColor: Colors.orange));
              return;
            }
            try {
              final res = await widget.apiService.saveMdGutachter(widget.userId, {
                'md_id': mdId,
                'vorname': vornameC.text.trim(),
                'nachname': nachnameC.text.trim(),
                'qualifikation': qualifikation,
                'notiz': notizC.text.trim(),
              });
              if (res['success'] != true) {
                throw Exception(res['message'] ?? 'Server-Fehler');
              }
              final newId = res['id'] as int?;
              final fullName = '${vornameC.text.trim()} ${nachnameC.text.trim()}';
              setState(() {
                _a['zweitgutachten_gutachter_id'] = newId?.toString() ?? '';
                _a['zweitgutachten_gutachter_name'] = fullName;
                _gutachterLoaded = false;
                _gutachterLoadedForMdId = null;
              });
              await _loadGutachterList(mdId);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gutachter „$fullName" angelegt und ausgewählt'), backgroundColor: Colors.green));
            } catch (e) {
              if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
            }
          },
          child: const Text('Anlegen'),
        ),
      ],
    )));
  }

  Future<void> _pick(TextEditingController c) async {
    final p = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2015), lastDate: DateTime(2040), locale: const Locale('de'));
    if (p != null) c.text = '${p.day.toString().padLeft(2,'0')}.${p.month.toString().padLeft(2,'0')}.${p.year}';
  }

  /// Compute an appropriate parent Antrag status based on Widerspruch state.
  String _computeStatus() {
    if (_bescheidErgebnisC.text.isNotEmpty || _bescheidDatumC.text.isNotEmpty) {
      return _bescheidErgebnisC.text.toLowerCase().contains('abgelehnt')
          ? 'widerspruch_abgelehnt'
          : 'widerspruch_bewilligt';
    }
    if (_zgDatumC.text.isNotEmpty) return 'zweitgutachten';
    return 'widerspruch_eingelegt';
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final payload = <String, dynamic>{
        'id': widget.antragId,
        // Preserve outer Antrag-fields verbatim so the UPDATE doesn't clear them.
        'antrag_typ': _s('antrag_typ'),
        'antrag_datum': _s('antrag_datum'),
        'antrag_methode': _s('antrag_methode'),
        'pflegegrad_beantragt': _s('pflegegrad_beantragt'),
        'pflegegrad_ziel': _s('pflegegrad_ziel'),
        'aktenzeichen': _s('aktenzeichen'),
        'status': _computeStatus(),
        'notiz': _s('notiz'),
        'begutachtung_datum': _s('begutachtung_datum'),
        'begutachtung_ort': _s('begutachtung_ort'),
        'gutachter_name': _s('gutachter_name'),
        'bescheid_datum': _s('bescheid_datum'),
        'bescheid_ergebnis': _s('bescheid_ergebnis'),
        'bescheid_gueltig_ab': _s('bescheid_gueltig_ab'),
        // Widerspruch-Felder aus diesem Modal:
        'widerspruch_eingelegt': 'ja',
        'widerspruch_datum': _datumC.text.trim(),
        'widerspruch_methode': _methode,
        'widerspruch_anwalt': _anwalt,
        'widerspruch_anwalt_name': _anwaltNameC.text.trim(),
        'widerspruch_begruendung': _begC.text.trim(),
        'widerspruch_zweitgutachten_datum': _zgDatumC.text.trim(),
        'zweitgutachten_md_id': _s('zweitgutachten_md_id'),
        'zweitgutachten_md_name': _s('zweitgutachten_md_name'),
        'zweitgutachten_gutachter_id': _s('zweitgutachten_gutachter_id'),
        'zweitgutachten_gutachter_name': _s('zweitgutachten_gutachter_name'),
        'widerspruch_bescheid_datum': _bescheidDatumC.text.trim(),
        'widerspruch_bescheid_ergebnis': _bescheidErgebnisC.text.trim(),
        'widerspruch_bescheid_pflegegrad': _bescheidPg,
      };
      final res = await widget.apiService.savePflegegradAntrag(widget.userId, payload);
      if (res['success'] != true) {
        throw Exception('Server-Fehler: ${res['message'] ?? res.toString()}');
      }
      _a.addAll(payload);
      widget.onSaved(payload);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Widerspruch-Daten gespeichert'), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } catch (e) {
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
              Icon(Icons.gavel, color: Colors.orange.shade700),
              const SizedBox(width: 8),
              const Expanded(child: Text('Widerspruch — Details', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          TabBar(
            labelColor: Colors.orange.shade700,
            unselectedLabelColor: Colors.grey.shade500,
            indicatorColor: Colors.orange.shade700,
            tabs: [
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, size: 8, color: _datumC.text.isNotEmpty ? Colors.green : Colors.red),
                const SizedBox(width: 4), const Icon(Icons.info_outline, size: 16),
                const SizedBox(width: 4), const Text('Details'),
              ])),
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, size: 8, color: _zgDatumC.text.isNotEmpty ? Colors.green : Colors.grey),
                const SizedBox(width: 4), const Icon(Icons.assignment_ind, size: 16),
                const SizedBox(width: 4), const Text('Zweitgutachten'),
              ])),
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, size: 8, color: _bescheidDatumC.text.isNotEmpty ? Colors.green : Colors.grey),
                const SizedBox(width: 4), const Icon(Icons.assignment_turned_in, size: 16),
                const SizedBox(width: 4), const Text('Bescheid'),
              ])),
            ],
          ),
          Expanded(child: TabBarView(children: [
            _buildDetailsTab(),
            _buildZweitgutachtenTab(),
            _buildBescheidTab(),
          ])),
          Padding(padding: const EdgeInsets.all(12), child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Schließen')),
            const SizedBox(width: 8),
            FilledButton.icon(
              icon: _saving
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save, size: 16),
              label: Text(_saving ? 'Speichert…' : 'Alle Widerspruch-Daten speichern'),
              style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700),
              onPressed: _saving ? null : _save,
            ),
          ])),
        ])),
      ),
    );
  }

  Widget _buildDetailsTab() {
    return SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.gavel, size: 18, color: Colors.orange.shade700),
        const SizedBox(width: 6),
        Text('Widerspruchsdaten', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
      ]),
      const SizedBox(height: 14),
      TextField(
        controller: _datumC, readOnly: true,
        onTap: () => _pick(_datumC),
        decoration: const InputDecoration(labelText: 'Widerspruch eingelegt am *', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today, size: 16)),
      ),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        initialValue: _methoden.contains(_methode) ? _methode : _methoden.first,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Wie eingereicht?', isDense: true, border: OutlineInputBorder()),
        items: _methoden.map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 12)))).toList(),
        onChanged: (v) => setState(() => _methode = v ?? _methoden.first),
      ),
      const SizedBox(height: 10),
      const Text('Durch Anwalt eingereicht?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Row(children: [
        ChoiceChip(label: const Text('nein', style: TextStyle(fontSize: 11)), selected: _anwalt == 'nein', onSelected: (_) => setState(() => _anwalt = 'nein')),
        const SizedBox(width: 8),
        ChoiceChip(label: const Text('ja', style: TextStyle(fontSize: 11)), selected: _anwalt == 'ja', selectedColor: Colors.orange.shade200, onSelected: (_) => setState(() => _anwalt = 'ja')),
      ]),
      if (_anwalt == 'ja') ...[
        const SizedBox(height: 10),
        TextField(controller: _anwaltNameC, decoration: const InputDecoration(labelText: 'Kanzlei / Anwalt (Name, Adresse)', isDense: true, border: OutlineInputBorder())),
      ],
      const SizedBox(height: 10),
      TextField(
        controller: _begC, maxLines: 5,
        decoration: const InputDecoration(labelText: 'Begründung des Widerspruchs', isDense: true, border: OutlineInputBorder(), alignLabelWithHint: true),
      ),
    ]));
  }

  Widget _buildZweitgutachtenTab() {
    final selMdId = int.tryParse(_s('zweitgutachten_md_id'));
    Map<String, dynamic>? selectedMd;
    if (selMdId != null) {
      selectedMd = _mdList.firstWhere(
        (m) => (m['id'] as int?) == selMdId || int.tryParse(m['id'].toString()) == selMdId,
        orElse: () => {},
      );
      if (selectedMd.isEmpty) selectedMd = null;
    }

    return SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.assignment_ind, size: 18, color: Colors.deepPurple.shade700),
        const SizedBox(width: 6),
        Text('Zweitgutachten durch Medizinischen Dienst', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade800)),
      ]),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.deepPurple.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.deepPurple.shade200)),
        child: Text(
          'Nach dem Widerspruch veranlasst die Pflegekasse i.d.R. ein Zweitgutachten '
          'durch den Medizinischen Dienst. Der Termin wird per Brief mitgeteilt — hier '
          'können Sie den Umschlag/den Brief als Beleg hochladen.',
          style: TextStyle(fontSize: 11, color: Colors.deepPurple.shade900, height: 1.4),
        ),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _zgDatumC, readOnly: true,
        onTap: () => _pick(_zgDatumC),
        decoration: const InputDecoration(labelText: 'Zweitgutachten-Termin', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today, size: 16)),
      ),

      // ─── Auswahl des zuständigen Medizinischen Dienstes ─────────────────
      const SizedBox(height: 16),
      Row(children: [
        Icon(Icons.local_hospital, size: 16, color: Colors.deepPurple.shade700),
        const SizedBox(width: 6),
        Text('Zuständiger Medizinischer Dienst', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.deepPurple.shade800)),
      ]),
      const SizedBox(height: 6),
      if (!_mdLoaded)
        const Padding(padding: EdgeInsets.all(8), child: Row(children: [
          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 8),
          Text('Lade Liste der Medizinischen Dienste…', style: TextStyle(fontSize: 11)),
        ]))
      else Autocomplete<Map<String, dynamic>>(
        initialValue: TextEditingValue(text: _s('zweitgutachten_md_name')),
        displayStringForOption: (m) => m['name']?.toString() ?? '',
        optionsBuilder: (txt) {
          final q = txt.text.trim().toLowerCase();
          if (q.isEmpty) return _mdList;
          return _mdList.where((m) =>
            (m['name']?.toString() ?? '').toLowerCase().contains(q) ||
            (m['kuerzel']?.toString() ?? '').toLowerCase().contains(q) ||
            (m['bundeslaender']?.toString() ?? '').toLowerCase().contains(q) ||
            (m['ort']?.toString() ?? '').toLowerCase().contains(q) ||
            (m['plz']?.toString() ?? '').toLowerCase().contains(q) ||
            (m['zustaendig_fuer']?.toString() ?? '').toLowerCase().contains(q));
        },
        fieldViewBuilder: (ctx, controller, focusNode, onSubmit) => TextField(
          controller: controller, focusNode: focusNode,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: controller.text.isNotEmpty
                ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () {
                    controller.clear();
                    setState(() {
                      _a['zweitgutachten_md_id'] = '';
                      _a['zweitgutachten_md_name'] = '';
                    });
                  })
                : null,
            hintText: 'MD suchen (z.B. „Baden-Württemberg", „Ulm", „BW")…',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
        optionsViewBuilder: (ctx, onSel, options) => Align(
          alignment: Alignment.topLeft,
          child: Material(elevation: 4, borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320, maxWidth: 640),
              child: ListView(padding: EdgeInsets.zero, shrinkWrap: true,
                children: options.map((m) => InkWell(
                  onTap: () => onSel(m),
                  child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(m['name']?.toString() ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                      if ((m['kuerzel']?.toString() ?? '').isNotEmpty)
                        Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.deepPurple.shade50, borderRadius: BorderRadius.circular(4)),
                          child: Text(m['kuerzel'].toString(), style: TextStyle(fontSize: 10, color: Colors.deepPurple.shade700, fontWeight: FontWeight.w600))),
                    ]),
                    if ((m['bundeslaender']?.toString() ?? '').isNotEmpty)
                      Text(m['bundeslaender'].toString(), style: TextStyle(fontSize: 11, color: Colors.deepPurple.shade600, fontStyle: FontStyle.italic)),
                    Text('${m['plz'] ?? ''} ${m['ort'] ?? ''} — ${m['strasse'] ?? ''}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  ])),
                )).toList(),
              ),
            ),
          ),
        ),
        onSelected: (m) {
          final mdId = int.tryParse(m['id']?.toString() ?? '');
          setState(() {
            _a['zweitgutachten_md_id'] = m['id']?.toString() ?? '';
            _a['zweitgutachten_md_name'] = m['name']?.toString() ?? '';
            // Ausgewählten Gutachter zurücksetzen — er gehört zum vorherigen MD.
            _a['zweitgutachten_gutachter_id'] = '';
            _a['zweitgutachten_gutachter_name'] = '';
            _gutachterLoaded = false;
            _gutachterLoadedForMdId = null;
          });
          if (mdId != null) _loadGutachterList(mdId);
        },
      ),
      if (selectedMd != null) ...[
        const SizedBox(height: 10),
        _buildMdCard(selectedMd),
        const SizedBox(height: 16),
        _buildGutachterSection(selectedMd),
      ],

      const SizedBox(height: 20),
      Row(children: [
        Icon(Icons.upload_file, size: 16, color: Colors.deepPurple.shade700),
        const SizedBox(width: 6),
        Text('Umschlag / Brief zum Termin hochladen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.deepPurple.shade800)),
      ]),
      const SizedBox(height: 8),
      SizedBox(
        height: 260,
        child: KorrAttachmentsWidget(
          apiService: widget.apiService,
          modul: 'pflegegrad_zweitgutachten',
          korrespondenzId: widget.antragId,
        ),
      ),
    ]));
  }

  Widget _buildMdCard(Map<String, dynamic> md) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.deepPurple.shade300),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.local_hospital, size: 22, color: Colors.deepPurple.shade700),
          const SizedBox(width: 8),
          Expanded(child: Text(md['name']?.toString() ?? '',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade900))),
        ]),
        const SizedBox(height: 6),
        if ((md['bundeslaender']?.toString() ?? '').isNotEmpty)
          _mdRow(Icons.map, md['bundeslaender'].toString()),
        _mdRow(Icons.location_on, '${md['strasse'] ?? ''}, ${md['plz'] ?? ''} ${md['ort'] ?? ''}'),
        if ((md['telefon']?.toString() ?? '').isNotEmpty)
          _mdRow(Icons.phone, md['telefon'].toString()),
        if ((md['email']?.toString() ?? '').isNotEmpty)
          _mdRow(Icons.email, md['email'].toString()),
        if ((md['website']?.toString() ?? '').isNotEmpty)
          _mdRow(Icons.language, md['website'].toString()),
        if ((md['zustaendig_fuer']?.toString() ?? '').isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 4),
            child: Text(md['zustaendig_fuer'].toString(),
              style: TextStyle(fontSize: 10, color: Colors.grey.shade700, fontStyle: FontStyle.italic))),
      ]),
    );
  }

  Widget _mdRow(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 13, color: Colors.grey.shade700),
      const SizedBox(width: 6),
      Expanded(child: SelectableText(text, style: TextStyle(fontSize: 11, color: Colors.grey.shade800))),
    ]),
  );

  Widget _buildGutachterSection(Map<String, dynamic> md) {
    final mdId = int.tryParse(md['id']?.toString() ?? '') ?? 0;
    // Autoload beim ersten Aufruf der Section.
    if (mdId > 0 && _gutachterLoadedForMdId != mdId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadGutachterList(mdId));
    }
    final selGutachterId = int.tryParse(_s('zweitgutachten_gutachter_id'));
    Map<String, dynamic>? selectedG;
    if (selGutachterId != null) {
      selectedG = _gutachterList.firstWhere(
        (g) => (g['id'] as int?) == selGutachterId || int.tryParse(g['id'].toString()) == selGutachterId,
        orElse: () => {},
      );
      if (selectedG.isEmpty) selectedG = null;
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.deepPurple.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.person_search, size: 16, color: Colors.deepPurple.shade700),
          const SizedBox(width: 6),
          Text('Gutachter (Person)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.deepPurple.shade800)),
          const Spacer(),
          if (_gutachterLoaded)
            Text('${_gutachterList.length} registriert für ${md['kuerzel'] ?? md['name']}',
                 style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
        ]),
        const SizedBox(height: 8),
        if (!_gutachterLoaded)
          const Padding(padding: EdgeInsets.all(8), child: Row(children: [
            SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 8),
            Text('Lade Gutachter…', style: TextStyle(fontSize: 11)),
          ]))
        else if (_gutachterList.isEmpty)
          Padding(padding: const EdgeInsets.all(4), child: Text(
            'Noch kein Gutachter für ${md['kuerzel'] ?? md['name']} registriert.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontStyle: FontStyle.italic),
          ))
        else Autocomplete<Map<String, dynamic>>(
          initialValue: TextEditingValue(text: _s('zweitgutachten_gutachter_name')),
          displayStringForOption: (g) => '${g['vorname'] ?? ''} ${g['nachname'] ?? ''}'.trim(),
          optionsBuilder: (txt) {
            final q = txt.text.trim().toLowerCase();
            if (q.isEmpty) return _gutachterList;
            return _gutachterList.where((g) =>
              (g['vorname']?.toString() ?? '').toLowerCase().contains(q) ||
              (g['nachname']?.toString() ?? '').toLowerCase().contains(q) ||
              (g['qualifikation']?.toString() ?? '').toLowerCase().contains(q) ||
              (g['notiz']?.toString() ?? '').toLowerCase().contains(q));
          },
          fieldViewBuilder: (ctx, controller, focusNode, onSubmit) => TextField(
            controller: controller, focusNode: focusNode,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: controller.text.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () {
                      controller.clear();
                      setState(() {
                        _a['zweitgutachten_gutachter_id'] = '';
                        _a['zweitgutachten_gutachter_name'] = '';
                      });
                    })
                  : null,
              hintText: 'Gutachter suchen (Vorname, Nachname, Qualifikation)…',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
          ),
          optionsViewBuilder: (ctx, onSel, options) => Align(
            alignment: Alignment.topLeft,
            child: Material(elevation: 4, borderRadius: BorderRadius.circular(6),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300, maxWidth: 560),
                child: ListView(padding: EdgeInsets.zero, shrinkWrap: true,
                  children: options.map((g) => InkWell(
                    onTap: () => onSel(g),
                    child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${g['vorname'] ?? ''} ${g['nachname'] ?? ''}'.trim(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      if ((g['qualifikation']?.toString() ?? '').isNotEmpty)
                        Text(g['qualifikation'].toString(), style: TextStyle(fontSize: 11, color: Colors.deepPurple.shade600)),
                      if ((g['notiz']?.toString() ?? '').isNotEmpty)
                        Text(g['notiz'].toString(), style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
                    ])),
                  )).toList(),
                ),
              ),
            ),
          ),
          onSelected: (g) {
            setState(() {
              _a['zweitgutachten_gutachter_id'] = g['id']?.toString() ?? '';
              _a['zweitgutachten_gutachter_name'] = '${g['vorname'] ?? ''} ${g['nachname'] ?? ''}'.trim();
            });
          },
        ),
        if (selectedG != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.deepPurple.shade400, width: 1.5)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.person, size: 22, color: Colors.deepPurple.shade700),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SelectableText('${selectedG['vorname'] ?? ''} ${selectedG['nachname'] ?? ''}'.trim(),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade900)),
                if ((selectedG['qualifikation']?.toString() ?? '').isNotEmpty)
                  Text(selectedG['qualifikation'].toString(), style: TextStyle(fontSize: 11, color: Colors.deepPurple.shade700)),
                if ((selectedG['notiz']?.toString() ?? '').isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 2),
                    child: Text(selectedG['notiz'].toString(), style: TextStyle(fontSize: 10, color: Colors.grey.shade700, fontStyle: FontStyle.italic))),
              ])),
            ]),
          ),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: Icon(Icons.person_add, size: 14, color: Colors.deepPurple.shade700),
          label: Text('Neuen Gutachter für ${md['kuerzel'] ?? md['name']} anlegen', style: TextStyle(fontSize: 11, color: Colors.deepPurple.shade700)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.deepPurple.shade400),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            minimumSize: Size.zero,
          ),
          onPressed: () => _showNeuerGutachterDialog(mdId, md['name']?.toString() ?? ''),
        ),
      ]),
    );
  }

  Widget _buildBescheidTab() {
    return SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.assignment_turned_in, size: 18, color: Colors.green.shade700),
        const SizedBox(width: 6),
        Text('Widerspruchs-Bescheid', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
      ]),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.green.shade200)),
        child: Text(
          'Nach dem Zweitgutachten entscheidet die Pflegekasse erneut über den Widerspruch. '
          'Hier tragen Sie Datum + Ergebnis + neuen (oder bestätigten) Pflegegrad ein.',
          style: TextStyle(fontSize: 11, color: Colors.green.shade900, height: 1.4),
        ),
      ),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: TextField(
          controller: _bescheidDatumC, readOnly: true,
          onTap: () => _pick(_bescheidDatumC),
          decoration: const InputDecoration(labelText: 'Bescheiddatum', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today, size: 16)),
        )),
        const SizedBox(width: 10),
        Expanded(child: DropdownButtonFormField<String>(
          initialValue: _pflegegrade.contains(_bescheidPg) ? _bescheidPg : '',
          decoration: const InputDecoration(labelText: 'Neuer PG', isDense: true, border: OutlineInputBorder()),
          items: _pflegegrade.map((p) => DropdownMenuItem(value: p, child: Text(p.isEmpty ? '—' : 'PG $p', style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (v) => setState(() => _bescheidPg = v ?? ''),
        )),
      ]),
      const SizedBox(height: 10),
      TextField(
        controller: _bescheidErgebnisC,
        decoration: const InputDecoration(labelText: 'Ergebnis (z.B. PG 3 anerkannt / Widerspruch abgelehnt)', isDense: true, border: OutlineInputBorder()),
      ),
    ]));
  }
}
