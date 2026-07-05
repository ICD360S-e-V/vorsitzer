import 'package:flutter/material.dart';
import '../models/user.dart';
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
  /// Mitglied (für Auto-Preselect des zuständigen MD anhand des Bundeslands).
  final User? member;

  const MitgliederverwaltungBehordeKrankenkassePflegegrad({
    super.key,
    required this.apiService,
    required this.userId,
    this.member,
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
      memberBundesland: widget.member?.bundesland,
      member: widget.member,
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
  final String? memberBundesland;
  /// Volles User-Objekt für Adresse (Zuhause-Termine) — optional.
  final User? member;
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
    this.memberBundesland,
    this.member,
    required this.onSaved,
    required this.onEdit,
  });

  @override
  State<_AntragDetailModal> createState() => _AntragDetailModalState();
}

class _AntragDetailModalState extends State<_AntragDetailModal> {
  late Map<String, dynamic> _a;
  bool _saving = false;

  // Tab 2: Begutachtung
  late TextEditingController _begutachtungDatumC;
  late TextEditingController _begutachtungUhrzeitC;
  late TextEditingController _begutachtungDauerC;
  late TextEditingController _gutachterC;
  String _begutachtungsort = '';

  // Tab 3: Erst-Bescheid
  late TextEditingController _bescheidDatumC;
  late TextEditingController _bescheidGueltigC;
  late TextEditingController _bescheidErgebnisC;

  // Tab 4: Widerspruch
  String _widerspruchEingelegt = 'nein';
  late TextEditingController _wsDatumC;
  late TextEditingController _wsAnwaltNameC;
  late TextEditingController _wsBegC;
  late TextEditingController _wsZgDatumC;
  late TextEditingController _wsZgUhrzeitC;
  late TextEditingController _wsZgDauerC;
  String _wsZgOrt = '';
  String _wsMethode = 'schriftlich per Post';
  String _wsAnwalt = 'nein';

  // Tab 5: Widerspruchs-Bescheid
  late TextEditingController _wsBescheidDatumC;
  late TextEditingController _wsBescheidErgebnisC;
  String _wsBescheidPg = '';

  // Tab 7: Klage
  String _klageEingelegt = 'nein';
  late TextEditingController _klageDatumC;
  late TextEditingController _klageGerichtC;
  late TextEditingController _klageAktenC;
  late TextEditingController _klageAnwaltNameC;
  late TextEditingController _klageBegC;
  late TextEditingController _klageVerhandlungC;
  String _klageAnwalt = 'nein';

  // Tab 8: Drittgutachten (durch das Sozialgericht bestellt)
  late TextEditingController _dgDatumC;
  late TextEditingController _dgUhrzeitC;
  late TextEditingController _dgDauerC;
  String _dgOrt = '';

  // Tab 9: Urteil (Klage-Bescheid)
  late TextEditingController _klageUrteilDatumC;
  late TextEditingController _klageUrteilErgC;
  String _klageUrteilPg = '';

  // MD + Gutachter (für Widerspruch → Zweitgutachten)
  List<Map<String, dynamic>> _mdList = [];
  bool _mdLoaded = false;
  List<Map<String, dynamic>> _gutachterList = [];
  bool _gutachterLoaded = false;
  int? _gutachterLoadedForMdId;

  static const _wsMethoden = ['schriftlich per Post', 'per Fax', 'per E-Mail (online)', 'persönlich beim Termin'];
  static const _klageMethoden = _wsMethoden; // gleiche Optionen
  static const _pflegegrade = ['', '1', '2', '3', '4', '5'];

  @override
  void initState() {
    super.initState();
    _a = Map<String, dynamic>.from(widget.antrag);
    // Begutachtung
    _begutachtungDatumC = TextEditingController(text: _s('begutachtung_datum'));
    _begutachtungUhrzeitC = TextEditingController(text: _s('begutachtung_uhrzeit'));
    _begutachtungDauerC = TextEditingController(text: _s('begutachtung_dauer_stunden'));
    _gutachterC = TextEditingController(text: _s('gutachter_name'));
    _begutachtungsort = _s('begutachtung_ort');
    // Erst-Bescheid
    _bescheidDatumC = TextEditingController(text: _s('bescheid_datum'));
    _bescheidGueltigC = TextEditingController(text: _s('bescheid_gueltig_ab'));
    _bescheidErgebnisC = TextEditingController(text: _s('bescheid_ergebnis'));
    // Widerspruch
    _widerspruchEingelegt = (_s('widerspruch_eingelegt').toLowerCase() == 'ja') ? 'ja' : 'nein';
    _wsDatumC = TextEditingController(text: _s('widerspruch_datum'));
    _wsAnwaltNameC = TextEditingController(text: _s('widerspruch_anwalt_name'));
    _wsBegC = TextEditingController(text: _s('widerspruch_begruendung'));
    _wsZgDatumC = TextEditingController(text: _s('widerspruch_zweitgutachten_datum'));
    _wsZgUhrzeitC = TextEditingController(text: _s('widerspruch_zweitgutachten_uhrzeit'));
    _wsZgDauerC = TextEditingController(text: _s('widerspruch_zweitgutachten_dauer_stunden'));
    _wsZgOrt = _s('widerspruch_zweitgutachten_ort');
    _wsMethode = _wsMethoden.contains(_s('widerspruch_methode')) ? _s('widerspruch_methode') : _wsMethoden.first;
    _wsAnwalt = _s('widerspruch_anwalt').toLowerCase() == 'ja' ? 'ja' : 'nein';
    // Widerspruchs-Bescheid
    _wsBescheidDatumC = TextEditingController(text: _s('widerspruch_bescheid_datum'));
    _wsBescheidErgebnisC = TextEditingController(text: _s('widerspruch_bescheid_ergebnis'));
    _wsBescheidPg = _pflegegrade.contains(_s('widerspruch_bescheid_pflegegrad')) ? _s('widerspruch_bescheid_pflegegrad') : '';
    // Klage
    _klageEingelegt = (_s('klage_eingelegt').toLowerCase() == 'ja') ? 'ja' : 'nein';
    _klageDatumC = TextEditingController(text: _s('klage_datum'));
    _klageGerichtC = TextEditingController(text: _s('klage_gericht'));
    _klageAktenC = TextEditingController(text: _s('klage_aktenzeichen'));
    _klageAnwaltNameC = TextEditingController(text: _s('klage_anwalt_name'));
    _klageBegC = TextEditingController(text: _s('klage_begruendung'));
    _klageVerhandlungC = TextEditingController(text: _s('klage_verhandlung_datum'));
    _klageAnwalt = _s('klage_anwalt').toLowerCase() == 'ja' ? 'ja' : 'nein';
    // Drittgutachten
    _dgDatumC = TextEditingController(text: _s('drittgutachten_datum'));
    _dgUhrzeitC = TextEditingController(text: _s('drittgutachten_uhrzeit'));
    _dgDauerC = TextEditingController(text: _s('drittgutachten_dauer_stunden'));
    _dgOrt = _s('drittgutachten_ort');
    // Urteil
    _klageUrteilDatumC = TextEditingController(text: _s('klage_urteil_datum'));
    _klageUrteilErgC = TextEditingController(text: _s('klage_urteil_ergebnis'));
    _klageUrteilPg = _pflegegrade.contains(_s('klage_urteil_pflegegrad')) ? _s('klage_urteil_pflegegrad') : '';
    // MD + Gutachter (lazy load)
    _loadMdList();
  }

  String _s(String k) => _a[k]?.toString() ?? '';

  Future<void> _loadMdList() async {
    try {
      final res = await widget.apiService.listMedizinischerDienst();
      if (res['success'] == true && mounted) {
        setState(() {
          _mdList = (res['md'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _mdLoaded = true;
        });
        // Auto-Preselect MD anhand des Bundeslands wenn im Widerspruch-Kontext.
        if (_s('zweitgutachten_md_id').isEmpty && widget.memberBundesland != null && widget.memberBundesland!.trim().isNotEmpty) {
          final auto = _findMdForBundesland(widget.memberBundesland!);
          if (auto != null && mounted) {
            final mdId = int.tryParse(auto['id']?.toString() ?? '') ?? 0;
            setState(() {
              _a['zweitgutachten_md_id'] = auto['id']?.toString() ?? '';
              _a['zweitgutachten_md_name'] = auto['name']?.toString() ?? '';
            });
            if (mdId > 0) _loadGutachterList(mdId);
          }
        } else {
          final existingMd = int.tryParse(_s('zweitgutachten_md_id'));
          if (existingMd != null) _loadGutachterList(existingMd);
        }
      }
    } catch (_) {}
  }

  Map<String, dynamic>? _findMdForBundesland(String bl) {
    final needle = bl.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final md in _mdList) {
      final blCol = (md['bundeslaender']?.toString() ?? '').toLowerCase();
      if (blCol.contains(needle)) return md;
    }
    final aliases = <String, String>{
      'nrw': 'nordrhein-westfalen', 'sh': 'schleswig-holstein', 'mv': 'mecklenburg-vorpommern',
      'bw': 'baden-württemberg', 'ba-wü': 'baden-württemberg', 'rlp': 'rheinland-pfalz',
    };
    final alias = aliases[needle];
    if (alias != null) {
      for (final md in _mdList) {
        final blCol = (md['bundeslaender']?.toString() ?? '').toLowerCase();
        if (blCol.contains(alias)) return md;
      }
    }
    return null;
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

  /// Auto-compute status entlang des gesamten Prozess-Flusses.
  String _computeStatus() {
    if (_klageUrteilErgC.text.isNotEmpty || _klageUrteilDatumC.text.isNotEmpty) {
      return _klageUrteilErgC.text.toLowerCase().contains('abgelehnt') ? 'klage_abgelehnt' : 'klage_bewilligt';
    }
    if (_klageEingelegt == 'ja') return 'klage';
    if (_wsBescheidErgebnisC.text.isNotEmpty || _wsBescheidDatumC.text.isNotEmpty) {
      return _wsBescheidErgebnisC.text.toLowerCase().contains('abgelehnt') ? 'widerspruch_abgelehnt' : 'widerspruch_bewilligt';
    }
    if (_wsZgDatumC.text.isNotEmpty) return 'zweitgutachten';
    if (_widerspruchEingelegt == 'ja') return 'widerspruch_eingelegt';
    if (_bescheidErgebnisC.text.isNotEmpty || _bescheidDatumC.text.isNotEmpty) {
      return _bescheidErgebnisC.text.toLowerCase().contains('abgelehnt') ? 'abgelehnt' : 'bescheid_erhalten';
    }
    if (_begutachtungDatumC.text.isNotEmpty) return 'begutachtung';
    return _s('status').isEmpty ? 'offen' : _s('status');
  }

  /// Baut die Adresse des Mitglieds für „Zuhause"-Termine aus dem User-Objekt.
  String _memberHomeAddress() {
    final u = widget.member;
    if (u == null) return 'Zuhause';
    final parts = <String>[];
    final strasse = (u.strasse ?? '').trim();
    final hnr = (u.hausnummer ?? '').trim();
    if (strasse.isNotEmpty) parts.add(strasse + (hnr.isNotEmpty ? ' $hnr' : ''));
    final plz = (u.plz ?? '').trim();
    final ort = (u.ort ?? '').trim();
    if (plz.isNotEmpty || ort.isNotEmpty) parts.add('${plz.isNotEmpty ? '$plz ' : ''}$ort'.trim());
    return parts.isEmpty ? 'Zuhause' : 'Zuhause: ${parts.join(', ')}';
  }

  /// Parst dd.mm.yyyy + HH:MM zu DateTime.
  DateTime? _parseDateTime(String datum, String uhrzeit) {
    if (datum.isEmpty) return null;
    final dm = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})$').firstMatch(datum);
    if (dm == null) return null;
    final day = int.parse(dm.group(1)!);
    final mon = int.parse(dm.group(2)!);
    final year = int.parse(dm.group(3)!);
    int hour = 9, minute = 0;
    if (uhrzeit.isNotEmpty) {
      final um = RegExp(r'^(\d{1,2}):(\d{1,2})').firstMatch(uhrzeit);
      if (um != null) { hour = int.parse(um.group(1)!); minute = int.parse(um.group(2)!); }
    }
    try { return DateTime(year, mon, day, hour, minute); } catch (_) { return null; }
  }

  int _stundenToMinutes(String s) {
    if (s.trim().isEmpty) return 60;
    final n = double.tryParse(s.trim().replaceAll(',', '.'));
    if (n == null || n <= 0) return 60;
    return (n * 60).round();
  }

  /// Location: falls Ort „Zuhause" ist → Adresse des Mitglieds, sonst
  /// der ausgewählte Name oder MD-Name.
  String _terminLocation(String ort, String? mdName) {
    final l = ort.toLowerCase();
    if (l.contains('zuhause')) return _memberHomeAddress();
    if (mdName != null && mdName.isNotEmpty) return '$ort — $mdName';
    return ort.isEmpty ? 'MD-Termin' : ort;
  }

  /// Legt für jede Begutachtung (Erst/Zweit/Dritt) mit gesetztem Datum
  /// automatisch einen Termin in der Terminverwaltung an. Bereits vorhandene
  /// Termine werden nicht erneut erzeugt (Marker in _a).
  Future<List<String>> _createBegutachtungsTermine() async {
    final msgs = <String>[];
    final specs = [
      {
        'flag': '_termin_created_erst',
        'title': 'MD-Erstbegutachtung',
        'category': 'begutachtung',
        'datum': _begutachtungDatumC.text.trim(),
        'uhrzeit': _begutachtungUhrzeitC.text.trim(),
        'dauer': _begutachtungDauerC.text.trim(),
        'ort': _begutachtungsort,
        'md_name': null,
        'label': 'Erstbegutachtung',
      },
      {
        'flag': '_termin_created_zweit',
        'title': 'MD-Zweitgutachten (Widerspruch)',
        'category': 'begutachtung',
        'datum': _wsZgDatumC.text.trim(),
        'uhrzeit': _wsZgUhrzeitC.text.trim(),
        'dauer': _wsZgDauerC.text.trim(),
        'ort': _wsZgOrt,
        'md_name': _s('zweitgutachten_md_name'),
        'label': 'Zweitgutachten',
      },
      {
        'flag': '_termin_created_dritt',
        'title': 'MD-Drittgutachten (Sozialgericht)',
        'category': 'begutachtung',
        'datum': _dgDatumC.text.trim(),
        'uhrzeit': _dgUhrzeitC.text.trim(),
        'dauer': _dgDauerC.text.trim(),
        'ort': _dgOrt,
        'md_name': _s('drittgutachten_md_name'),
        'label': 'Drittgutachten',
      },
    ];
    for (final s in specs) {
      final datum = s['datum'] as String;
      if (datum.isEmpty) continue;
      // Simple Deduplication: track pro Antrag+Kategorie im _a-Blob.
      final marker = '${s['flag']}:${datum}_${s['uhrzeit']}';
      if (_a[s['flag']] == marker) continue;
      final dt = _parseDateTime(datum, s['uhrzeit'] as String);
      if (dt == null) continue;
      final loc = _terminLocation(s['ort'] as String, s['md_name'] as String?);
      try {
        final res = await widget.apiService.createTermin(
          title: s['title'] as String,
          category: s['category'] as String,
          description: 'Automatisch angelegt aus Pflegegrad-Antrag (${s['label']}).'
              '${(s['md_name'] ?? '').toString().isNotEmpty ? "\nMD: ${s['md_name']}" : ""}',
          terminDate: dt,
          durationMinutes: _stundenToMinutes(s['dauer'] as String),
          location: loc,
          participantIds: [widget.userId],
          brauchtMich: false,
        );
        if (res['success'] == true) {
          _a[s['flag'] as String] = marker;
          msgs.add('Termin „${s['label']}" angelegt');
        }
      } catch (_) {}
    }
    return msgs;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final id = _a['id'] is int ? _a['id'] as int : int.tryParse(_a['id']?.toString() ?? '') ?? 0;
      if (id <= 0) throw Exception('Antrag-ID fehlt oder ungültig');
      final payload = <String, dynamic>{
        'id': id,
        'antrag_typ': _s('antrag_typ'),
        'antrag_datum': _s('antrag_datum'),
        'antrag_methode': _s('antrag_methode'),
        'pflegegrad_beantragt': _s('pflegegrad_beantragt'),
        'pflegegrad_ziel': _s('pflegegrad_ziel'),
        'aktenzeichen': _s('aktenzeichen'),
        'status': _computeStatus(),
        'notiz': _s('notiz'),
        // Tab 2: Begutachtung
        'begutachtung_datum': _begutachtungDatumC.text.trim(),
        'begutachtung_uhrzeit': _begutachtungUhrzeitC.text.trim(),
        'begutachtung_dauer_stunden': _begutachtungDauerC.text.trim(),
        'begutachtung_ort': _begutachtungsort,
        'gutachter_name': _gutachterC.text.trim(),
        // Tab 3: Erst-Bescheid
        'bescheid_datum': _bescheidDatumC.text.trim(),
        'bescheid_ergebnis': _bescheidErgebnisC.text.trim(),
        'bescheid_gueltig_ab': _bescheidGueltigC.text.trim(),
        // Tab 4: Widerspruch
        'widerspruch_eingelegt': _widerspruchEingelegt,
        'widerspruch_datum': _wsDatumC.text.trim(),
        'widerspruch_methode': _wsMethode,
        'widerspruch_anwalt': _wsAnwalt,
        'widerspruch_anwalt_name': _wsAnwaltNameC.text.trim(),
        'widerspruch_begruendung': _wsBegC.text.trim(),
        'widerspruch_zweitgutachten_datum': _wsZgDatumC.text.trim(),
        'widerspruch_zweitgutachten_uhrzeit': _wsZgUhrzeitC.text.trim(),
        'widerspruch_zweitgutachten_dauer_stunden': _wsZgDauerC.text.trim(),
        'widerspruch_zweitgutachten_ort': _wsZgOrt,
        'zweitgutachten_md_id': _s('zweitgutachten_md_id'),
        'zweitgutachten_md_name': _s('zweitgutachten_md_name'),
        'zweitgutachten_gutachter_id': _s('zweitgutachten_gutachter_id'),
        'zweitgutachten_gutachter_name': _s('zweitgutachten_gutachter_name'),
        // Tab 5: Widerspruchs-Bescheid
        'widerspruch_bescheid_datum': _wsBescheidDatumC.text.trim(),
        'widerspruch_bescheid_ergebnis': _wsBescheidErgebnisC.text.trim(),
        'widerspruch_bescheid_pflegegrad': _wsBescheidPg,
        // Tab 6: Klage
        'klage_eingelegt': _klageEingelegt,
        'klage_datum': _klageDatumC.text.trim(),
        'klage_gericht': _klageGerichtC.text.trim(),
        'klage_aktenzeichen': _klageAktenC.text.trim(),
        'klage_anwalt': _klageAnwalt,
        'klage_anwalt_name': _klageAnwaltNameC.text.trim(),
        'klage_begruendung': _klageBegC.text.trim(),
        'klage_verhandlung_datum': _klageVerhandlungC.text.trim(),
        // Tab 8: Drittgutachten
        'drittgutachten_datum': _dgDatumC.text.trim(),
        'drittgutachten_uhrzeit': _dgUhrzeitC.text.trim(),
        'drittgutachten_dauer_stunden': _dgDauerC.text.trim(),
        'drittgutachten_ort': _dgOrt,
        'drittgutachten_md_id': _s('drittgutachten_md_id'),
        'drittgutachten_md_name': _s('drittgutachten_md_name'),
        'drittgutachten_gutachter_id': _s('drittgutachten_gutachter_id'),
        'drittgutachten_gutachter_name': _s('drittgutachten_gutachter_name'),
        // Tab 9: Urteil / Klage-Bescheid
        'klage_urteil_datum': _klageUrteilDatumC.text.trim(),
        'klage_urteil_ergebnis': _klageUrteilErgC.text.trim(),
        'klage_urteil_pflegegrad': _klageUrteilPg,
      };
      final res = await widget.apiService.savePflegegradAntrag(widget.userId, payload);
      if (res['success'] != true) throw Exception('Server-Fehler: ${res['message'] ?? res.toString()}');
      _a.addAll(payload);
      // Nach dem Speichern: Termine in Terminverwaltung erzeugen wo passend.
      final terminMsgs = await _createBegutachtungsTermine();
      if (terminMsgs.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(terminMsgs.join(' • ')),
          backgroundColor: Colors.blue.shade700,
          duration: const Duration(seconds: 5),
        ));
      }
      widget.onSaved();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gespeichert'), backgroundColor: Colors.green));
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
      length: 9,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: SizedBox(width: 900, height: 700, child: Column(children: [
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
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              _tabWithDot('Details', Icons.info_outline, _s('antrag_datum').isNotEmpty ? Colors.green : Colors.red),
              _tabWithDot('Begutachtung', Icons.medical_information, _begutachtungDatumC.text.isNotEmpty ? Colors.green : Colors.grey),
              _tabWithDot('Bescheid', Icons.assignment_turned_in, _bescheidDatumC.text.isNotEmpty ? Colors.green : Colors.grey),
              _tabWithDot('Widerspruch', Icons.gavel, _widerspruchEingelegt == 'ja' ? Colors.orange : Colors.grey),
              _tabWithDot('Zweitgutachten', Icons.assignment_ind, _wsZgDatumC.text.isNotEmpty ? Colors.deepPurple : Colors.grey),
              _tabWithDot('Bescheid', Icons.assignment_turned_in, _wsBescheidDatumC.text.isNotEmpty ? Colors.green : Colors.grey),
              _tabWithDot('Klage', Icons.account_balance, _klageEingelegt == 'ja' ? Colors.red : Colors.grey),
              _tabWithDot('Drittgutachten', Icons.assignment_ind, _dgDatumC.text.isNotEmpty ? Colors.deepPurple : Colors.grey),
              _tabWithDot('Bescheid', Icons.gavel_rounded, _klageUrteilDatumC.text.isNotEmpty ? Colors.green : Colors.grey),
            ],
          ),
          Expanded(child: TabBarView(children: [
            _buildDetailsTab(),
            _buildBegutachtungTab(),
            _buildBescheidTab(),
            _buildWiderspruchTab(),
            _buildZweitgutachtenTab(),
            _buildWiderspruchBescheidTab(),
            _buildKlageTab(),
            _buildDrittgutachtenTab(),
            _buildKlageBescheidTab(),
          ])),
          _buildBottomActionBar(),
        ])),
      ),
    );
  }

  Widget _tabWithDot(String label, IconData icon, Color dot) {
    return Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.circle, size: 8, color: dot),
      const SizedBox(width: 4), Icon(icon, size: 16),
      const SizedBox(width: 4), Text(label),
    ]));
  }

  Widget _buildBottomActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(color: Colors.grey.shade50, border: Border(top: BorderSide(color: Colors.grey.shade300))),
      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Schließen')),
        const SizedBox(width: 8),
        FilledButton.icon(
          icon: _saving
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save, size: 16),
          label: Text(_saving ? 'Speichert…' : 'Alle Änderungen speichern'),
          style: FilledButton.styleFrom(backgroundColor: Colors.purple.shade600),
          onPressed: _saving ? null : _save,
        ),
      ]),
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

  Widget _buildBegutachtungTab() {
    return SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader(Icons.medical_information, 'MD-Begutachtung', Colors.blue),
      const SizedBox(height: 8),
      Text(
        'Termin und Ort der Begutachtung durch den Medizinischen Dienst zum Erstantrag.',
        style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
      ),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(flex: 2, child: TextField(
          controller: _begutachtungDatumC, readOnly: true,
          onTap: () => _pickDate(_begutachtungDatumC),
          decoration: const InputDecoration(labelText: 'Datum', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today, size: 16)),
        )),
        const SizedBox(width: 10),
        Expanded(child: TextField(
          controller: _begutachtungUhrzeitC, readOnly: true,
          onTap: () => _pickTime(_begutachtungUhrzeitC),
          decoration: const InputDecoration(labelText: 'Uhrzeit', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.schedule, size: 16)),
        )),
        const SizedBox(width: 10),
        Expanded(child: TextField(
          controller: _begutachtungDauerC,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Dauer (Std.)', isDense: true, border: OutlineInputBorder(), hintText: 'z.B. 1,5'),
        )),
      ]),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        initialValue: widget.begutachtungsorte.contains(_begutachtungsort) ? _begutachtungsort : null,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Wo?', isDense: true, border: OutlineInputBorder(), prefixIcon: Icon(Icons.place, size: 18)),
        items: widget.begutachtungsorte.map((o) => DropdownMenuItem(value: o, child: Text(o, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))).toList(),
        onChanged: (v) => setState(() => _begutachtungsort = v ?? ''),
      ),
      if (_begutachtungsort.toLowerCase().contains('zuhause')) _homeAddressHint(),
      const SizedBox(height: 10),
      TextField(controller: _gutachterC, decoration: const InputDecoration(labelText: 'Gutachter (Name / MDK-Nr.)', isDense: true, border: OutlineInputBorder())),
      _autoTerminHint('Erstbegutachtung'),
    ]));
  }

  /// Info-Banner: zeigt die Adresse an, die für „Zuhause"-Termine verwendet wird.
  Widget _homeAddressHint() {
    return Padding(padding: const EdgeInsets.only(top: 6), child: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.blue.shade200)),
      child: Row(children: [
        Icon(Icons.home, size: 14, color: Colors.blue.shade700),
        const SizedBox(width: 6),
        Expanded(child: Text('Termin-Adresse: ${_memberHomeAddress()}',
          style: TextStyle(fontSize: 10, color: Colors.blue.shade900))),
      ]),
    ));
  }

  Widget _autoTerminHint(String label) {
    return Padding(padding: const EdgeInsets.only(top: 10), child: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey.shade300)),
      child: Row(children: [
        Icon(Icons.event_available, size: 14, color: Colors.grey.shade700),
        const SizedBox(width: 6),
        Expanded(child: Text('Bei „Alle Änderungen speichern" wird ein Termin für „$label" in der Terminverwaltung angelegt.',
          style: TextStyle(fontSize: 10, color: Colors.grey.shade700, fontStyle: FontStyle.italic))),
      ]),
    ));
  }

  Future<void> _pickTime(TextEditingController c) async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (t != null) c.text = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildBescheidTab() {
    final antragId = (widget.antrag['id'] is int)
        ? widget.antrag['id'] as int
        : int.tryParse(widget.antrag['id']?.toString() ?? '') ?? 0;
    return SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader(Icons.assignment_turned_in, 'Bescheid der Pflegekasse', Colors.green),
      const SizedBox(height: 8),
      Text(
        'Ergebnis der Erstbegutachtung — Datum, gültig ab, Ergebnistext. Ca. 1-2 Wochen nach der Begutachtung erhalten Sie den Bescheid.',
        style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
      ),
      const SizedBox(height: 14),
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
      const SizedBox(height: 20),
      Row(children: [
        Icon(Icons.upload_file, size: 16, color: Colors.green.shade700),
        const SizedBox(width: 6),
        Text('Bescheid hochladen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green.shade800)),
      ]),
      const SizedBox(height: 4),
      Text(
        'Bescheid der Pflegekasse (PDF/JPG/PNG). Mehrere Dateien können gleichzeitig hochgeladen werden.',
        style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 260,
        child: KorrAttachmentsWidget(
          apiService: widget.apiService,
          modul: 'pflegegrad_bescheid',
          korrespondenzId: antragId,
        ),
      ),
    ]));
  }

  // ── Tab 4: Widerspruch (inline: Datum, Methode, Anwalt, Begründung, Zweitgutachten + MD/Gutachter/Upload) ──
  Widget _buildWiderspruchTab() {
    return SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader(Icons.gavel, 'Widerspruch gegen Bescheid', Colors.orange),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.orange.shade200)),
        child: Text(
          'Frist: 1 Monat ab Zugang des Bescheids (1 Jahr, wenn Rechtsbelehrung fehlt).',
          style: TextStyle(fontSize: 11, color: Colors.orange.shade900),
        ),
      ),
      const SizedBox(height: 14),
      const Text('Widerspruch eingelegt?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Row(children: [
        ChoiceChip(label: const Text('nein', style: TextStyle(fontSize: 11)), selected: _widerspruchEingelegt == 'nein', onSelected: (_) => setState(() => _widerspruchEingelegt = 'nein')),
        const SizedBox(width: 8),
        ChoiceChip(label: const Text('ja', style: TextStyle(fontSize: 11)), selected: _widerspruchEingelegt == 'ja', selectedColor: Colors.orange.shade200, onSelected: (_) => setState(() => _widerspruchEingelegt = 'ja')),
      ]),
      if (_widerspruchEingelegt == 'ja') ...[
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: TextField(
            controller: _wsDatumC, readOnly: true, onTap: () => _pickDate(_wsDatumC),
            decoration: const InputDecoration(labelText: 'Widerspruch eingelegt am *', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today, size: 16)),
          )),
          const SizedBox(width: 10),
          Expanded(child: DropdownButtonFormField<String>(
            initialValue: _wsMethoden.contains(_wsMethode) ? _wsMethode : _wsMethoden.first,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Wie eingereicht?', isDense: true, border: OutlineInputBorder()),
            items: _wsMethoden.map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 12)))).toList(),
            onChanged: (v) => setState(() => _wsMethode = v ?? _wsMethoden.first),
          )),
        ]),
        const SizedBox(height: 10),
        const Text('Durch Anwalt eingereicht?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Row(children: [
          ChoiceChip(label: const Text('nein', style: TextStyle(fontSize: 11)), selected: _wsAnwalt == 'nein', onSelected: (_) => setState(() => _wsAnwalt = 'nein')),
          const SizedBox(width: 8),
          ChoiceChip(label: const Text('ja', style: TextStyle(fontSize: 11)), selected: _wsAnwalt == 'ja', selectedColor: Colors.orange.shade200, onSelected: (_) => setState(() => _wsAnwalt = 'ja')),
        ]),
        if (_wsAnwalt == 'ja') ...[
          const SizedBox(height: 10),
          TextField(controller: _wsAnwaltNameC, decoration: const InputDecoration(labelText: 'Kanzlei / Anwalt', isDense: true, border: OutlineInputBorder())),
        ],
        const SizedBox(height: 10),
        TextField(controller: _wsBegC, maxLines: 4, decoration: const InputDecoration(labelText: 'Begründung des Widerspruchs', isDense: true, border: OutlineInputBorder(), alignLabelWithHint: true)),
      ],
    ]));
  }

  // ── Tab 5: Zweitgutachten (nach Widerspruch, durch MD) ──
  Widget _buildZweitgutachtenTab() {
    final antragId = (widget.antrag['id'] is int)
        ? widget.antrag['id'] as int
        : int.tryParse(widget.antrag['id']?.toString() ?? '') ?? 0;
    return SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader(Icons.assignment_ind, 'Zweitgutachten durch Medizinischen Dienst', Colors.deepPurple),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.deepPurple.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.deepPurple.shade200)),
        child: Text(
          'Nach Widerspruch veranlasst die Pflegekasse i.d.R. ein Zweitgutachten durch den MD.',
          style: TextStyle(fontSize: 11, color: Colors.deepPurple.shade900),
        ),
      ),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(flex: 2, child: TextField(
          controller: _wsZgDatumC, readOnly: true, onTap: () => _pickDate(_wsZgDatumC),
          decoration: const InputDecoration(labelText: 'Datum', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today, size: 16)),
        )),
        const SizedBox(width: 10),
        Expanded(child: TextField(
          controller: _wsZgUhrzeitC, readOnly: true, onTap: () => _pickTime(_wsZgUhrzeitC),
          decoration: const InputDecoration(labelText: 'Uhrzeit', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.schedule, size: 16)),
        )),
        const SizedBox(width: 10),
        Expanded(child: TextField(
          controller: _wsZgDauerC,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Dauer (Std.)', isDense: true, border: OutlineInputBorder(), hintText: 'z.B. 1,5'),
        )),
      ]),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        initialValue: widget.begutachtungsorte.contains(_wsZgOrt) ? _wsZgOrt : null,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Wo?', isDense: true, border: OutlineInputBorder(), prefixIcon: Icon(Icons.place, size: 18)),
        items: widget.begutachtungsorte.map((o) => DropdownMenuItem(value: o, child: Text(o, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))).toList(),
        onChanged: (v) => setState(() => _wsZgOrt = v ?? ''),
      ),
      if (_wsZgOrt.toLowerCase().contains('zuhause')) _homeAddressHint(),
      const SizedBox(height: 12),
      _buildMdAutocomplete(prefix: 'zweitgutachten'),
      const SizedBox(height: 16),
      Row(children: [
        Icon(Icons.upload_file, size: 16, color: Colors.deepPurple.shade700),
        const SizedBox(width: 6),
        Text('Termin-Brief vom Med. Dienst hochladen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.deepPurple.shade800)),
      ]),
      const SizedBox(height: 8),
      SizedBox(
        height: 240,
        child: KorrAttachmentsWidget(
          apiService: widget.apiService,
          modul: 'pflegegrad_zweitgutachten',
          korrespondenzId: antragId,
        ),
      ),
      _autoTerminHint('Zweitgutachten'),
    ]));
  }

  // ── Tab 6: Bescheid nach Widerspruch ──
  Widget _buildWiderspruchBescheidTab() {
    final antragId = (widget.antrag['id'] is int)
        ? widget.antrag['id'] as int
        : int.tryParse(widget.antrag['id']?.toString() ?? '') ?? 0;
    return SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader(Icons.assignment_turned_in, 'Bescheid nach Widerspruch', Colors.green),
      const SizedBox(height: 8),
      Text(
        'Nach dem Zweitgutachten entscheidet die Pflegekasse erneut. Datum + Ergebnis + neuer (oder bestätigter) Pflegegrad.',
        style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
      ),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: TextField(
          controller: _wsBescheidDatumC, readOnly: true, onTap: () => _pickDate(_wsBescheidDatumC),
          decoration: const InputDecoration(labelText: 'Bescheiddatum', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today, size: 16)),
        )),
        const SizedBox(width: 10),
        Expanded(child: DropdownButtonFormField<String>(
          initialValue: _pflegegrade.contains(_wsBescheidPg) ? _wsBescheidPg : '',
          decoration: const InputDecoration(labelText: 'Neuer PG', isDense: true, border: OutlineInputBorder()),
          items: _pflegegrade.map((p) => DropdownMenuItem(value: p, child: Text(p.isEmpty ? '—' : 'PG $p', style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (v) => setState(() => _wsBescheidPg = v ?? ''),
        )),
      ]),
      const SizedBox(height: 10),
      TextField(controller: _wsBescheidErgebnisC, decoration: const InputDecoration(labelText: 'Ergebnis (z.B. PG 3 anerkannt / Widerspruch abgelehnt)', isDense: true, border: OutlineInputBorder())),
      const SizedBox(height: 20),
      Row(children: [
        Icon(Icons.upload_file, size: 16, color: Colors.green.shade700),
        const SizedBox(width: 6),
        Text('Widerspruchs-Bescheid hochladen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green.shade800)),
      ]),
      const SizedBox(height: 8),
      SizedBox(
        height: 260,
        child: KorrAttachmentsWidget(
          apiService: widget.apiService,
          modul: 'pflegegrad_widerspruch_bescheid',
          korrespondenzId: antragId,
        ),
      ),
    ]));
  }

  // ── Tab 6: Klage ──
  Widget _buildKlageTab() {
    final antragId = (widget.antrag['id'] is int)
        ? widget.antrag['id'] as int
        : int.tryParse(widget.antrag['id']?.toString() ?? '') ?? 0;
    return SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader(Icons.account_balance, 'Klage vor dem Sozialgericht', Colors.red),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.red.shade200)),
        child: Text(
          'Wenn auch nach dem Widerspruch der Bescheid unbefriedigend ist, kann innerhalb 1 Monats Klage beim Sozialgericht erhoben werden. Sozialgerichtsklagen sind gerichtsgebührenfrei (§ 183 SGG).',
          style: TextStyle(fontSize: 11, color: Colors.red.shade900, height: 1.4),
        ),
      ),
      const SizedBox(height: 14),
      const Text('Klage eingelegt?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Row(children: [
        ChoiceChip(label: const Text('nein', style: TextStyle(fontSize: 11)), selected: _klageEingelegt == 'nein', onSelected: (_) => setState(() => _klageEingelegt = 'nein')),
        const SizedBox(width: 8),
        ChoiceChip(label: const Text('ja', style: TextStyle(fontSize: 11)), selected: _klageEingelegt == 'ja', selectedColor: Colors.red.shade200, onSelected: (_) => setState(() => _klageEingelegt = 'ja')),
      ]),
      if (_klageEingelegt == 'ja') ...[
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: TextField(
            controller: _klageDatumC, readOnly: true, onTap: () => _pickDate(_klageDatumC),
            decoration: const InputDecoration(labelText: 'Klage eingereicht am *', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today, size: 16)),
          )),
          const SizedBox(width: 10),
          Expanded(child: TextField(
            controller: _klageAktenC,
            decoration: const InputDecoration(labelText: 'Aktenzeichen (SG …)', isDense: true, border: OutlineInputBorder()),
          )),
        ]),
        const SizedBox(height: 10),
        TextField(
          controller: _klageGerichtC,
          decoration: const InputDecoration(labelText: 'Zuständiges Sozialgericht (z.B. „Sozialgericht Ulm")', isDense: true, border: OutlineInputBorder(), prefixIcon: Icon(Icons.account_balance, size: 18)),
        ),
        const SizedBox(height: 10),
        const Text('Durch Anwalt vertreten?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Row(children: [
          ChoiceChip(label: const Text('nein', style: TextStyle(fontSize: 11)), selected: _klageAnwalt == 'nein', onSelected: (_) => setState(() => _klageAnwalt = 'nein')),
          const SizedBox(width: 8),
          ChoiceChip(label: const Text('ja', style: TextStyle(fontSize: 11)), selected: _klageAnwalt == 'ja', selectedColor: Colors.red.shade200, onSelected: (_) => setState(() => _klageAnwalt = 'ja')),
        ]),
        if (_klageAnwalt == 'ja') ...[
          const SizedBox(height: 10),
          TextField(controller: _klageAnwaltNameC, decoration: const InputDecoration(labelText: 'Kanzlei / Anwalt', isDense: true, border: OutlineInputBorder())),
        ],
        const SizedBox(height: 10),
        TextField(controller: _klageBegC, maxLines: 4, decoration: const InputDecoration(labelText: 'Klagebegründung', isDense: true, border: OutlineInputBorder(), alignLabelWithHint: true)),
        const SizedBox(height: 10),
        TextField(
          controller: _klageVerhandlungC, readOnly: true, onTap: () => _pickDate(_klageVerhandlungC),
          decoration: const InputDecoration(labelText: 'Verhandlungstermin', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today, size: 16)),
        ),
        const SizedBox(height: 20),
        Row(children: [
          Icon(Icons.upload_file, size: 16, color: Colors.red.shade700),
          const SizedBox(width: 6),
          Text('Klage-Unterlagen hochladen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.red.shade800)),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: 240,
          child: KorrAttachmentsWidget(
            apiService: widget.apiService,
            modul: 'pflegegrad_klage',
            korrespondenzId: antragId,
          ),
        ),
      ],
    ]));
  }

  // ── Tab 8: Drittgutachten (durch das Sozialgericht bestellt) ──
  Widget _buildDrittgutachtenTab() {
    final antragId = (widget.antrag['id'] is int)
        ? widget.antrag['id'] as int
        : int.tryParse(widget.antrag['id']?.toString() ?? '') ?? 0;
    return SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader(Icons.assignment_ind, 'Drittgutachten (Sozialgericht)', Colors.deepPurple),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.deepPurple.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.deepPurple.shade200)),
        child: Text(
          'Im Klageverfahren bestellt das Sozialgericht i.d.R. ein weiteres unabhängiges Gutachten (§ 106 SGG). '
          'Dieses überprüft die bisherigen MD-Gutachten und ist für das Urteil maßgeblich.',
          style: TextStyle(fontSize: 11, color: Colors.deepPurple.shade900, height: 1.4),
        ),
      ),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(flex: 2, child: TextField(
          controller: _dgDatumC, readOnly: true, onTap: () => _pickDate(_dgDatumC),
          decoration: const InputDecoration(labelText: 'Datum', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today, size: 16)),
        )),
        const SizedBox(width: 10),
        Expanded(child: TextField(
          controller: _dgUhrzeitC, readOnly: true, onTap: () => _pickTime(_dgUhrzeitC),
          decoration: const InputDecoration(labelText: 'Uhrzeit', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.schedule, size: 16)),
        )),
        const SizedBox(width: 10),
        Expanded(child: TextField(
          controller: _dgDauerC,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Dauer (Std.)', isDense: true, border: OutlineInputBorder(), hintText: 'z.B. 1,5'),
        )),
      ]),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        initialValue: widget.begutachtungsorte.contains(_dgOrt) ? _dgOrt : null,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Wo?', isDense: true, border: OutlineInputBorder(), prefixIcon: Icon(Icons.place, size: 18)),
        items: widget.begutachtungsorte.map((o) => DropdownMenuItem(value: o, child: Text(o, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))).toList(),
        onChanged: (v) => setState(() => _dgOrt = v ?? ''),
      ),
      if (_dgOrt.toLowerCase().contains('zuhause')) _homeAddressHint(),
      const SizedBox(height: 12),
      _buildMdAutocomplete(prefix: 'drittgutachten'),
      const SizedBox(height: 16),
      Row(children: [
        Icon(Icons.upload_file, size: 16, color: Colors.deepPurple.shade700),
        const SizedBox(width: 6),
        Text('Drittgutachten hochladen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.deepPurple.shade800)),
      ]),
      const SizedBox(height: 8),
      SizedBox(
        height: 240,
        child: KorrAttachmentsWidget(
          apiService: widget.apiService,
          modul: 'pflegegrad_drittgutachten',
          korrespondenzId: antragId,
        ),
      ),
      _autoTerminHint('Drittgutachten'),
    ]));
  }

  // ── Tab 9: Urteil (Bescheid nach Klage) ──
  Widget _buildKlageBescheidTab() {
    final antragId = (widget.antrag['id'] is int)
        ? widget.antrag['id'] as int
        : int.tryParse(widget.antrag['id']?.toString() ?? '') ?? 0;
    return SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader(Icons.gavel_rounded, 'Urteil / Bescheid nach Klage', Colors.teal),
      const SizedBox(height: 8),
      Text(
        'Ergebnis des Sozialgerichtsverfahrens — Urteil oder gerichtlicher Vergleich mit endgültigem Pflegegrad.',
        style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
      ),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: TextField(
          controller: _klageUrteilDatumC, readOnly: true, onTap: () => _pickDate(_klageUrteilDatumC),
          decoration: const InputDecoration(labelText: 'Urteilsdatum', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today, size: 16)),
        )),
        const SizedBox(width: 10),
        Expanded(child: DropdownButtonFormField<String>(
          initialValue: _pflegegrade.contains(_klageUrteilPg) ? _klageUrteilPg : '',
          decoration: const InputDecoration(labelText: 'Zugesprochener PG', isDense: true, border: OutlineInputBorder()),
          items: _pflegegrade.map((p) => DropdownMenuItem(value: p, child: Text(p.isEmpty ? '—' : 'PG $p', style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (v) => setState(() => _klageUrteilPg = v ?? ''),
        )),
      ]),
      const SizedBox(height: 10),
      TextField(controller: _klageUrteilErgC, maxLines: 3, decoration: const InputDecoration(labelText: 'Ergebnis (z.B. „PG 3 zugesprochen" / „Klage abgewiesen")', isDense: true, border: OutlineInputBorder(), alignLabelWithHint: true)),
      const SizedBox(height: 20),
      Row(children: [
        Icon(Icons.upload_file, size: 16, color: Colors.teal.shade700),
        const SizedBox(width: 6),
        Text('Urteil hochladen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.teal.shade800)),
      ]),
      const SizedBox(height: 8),
      SizedBox(
        height: 260,
        child: KorrAttachmentsWidget(
          apiService: widget.apiService,
          modul: 'pflegegrad_urteil',
          korrespondenzId: antragId,
        ),
      ),
    ]));
  }

  // ── Helpers: MD Autocomplete + Card + Gutachter Section + Neuer Gutachter Dialog ──
  /// [prefix] entscheidet, welche Antragsfelder gelesen/geschrieben werden:
  ///   'zweitgutachten' → zweitgutachten_md_id/_name/_gutachter_id/_gutachter_name (Widerspruchs-Verfahren)
  ///   'drittgutachten' → drittgutachten_md_id/_name/_gutachter_id/_gutachter_name (Klage-Verfahren)
  Widget _buildMdAutocomplete({String prefix = 'zweitgutachten'}) {
    final selMdId = int.tryParse(_s('${prefix}_md_id'));
    Map<String, dynamic>? selectedMd;
    if (selMdId != null) {
      selectedMd = _mdList.firstWhere(
        (m) => (m['id'] as int?) == selMdId || int.tryParse(m['id'].toString()) == selMdId,
        orElse: () => {},
      );
      if (selectedMd.isEmpty) selectedMd = null;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!_mdLoaded)
        const Padding(padding: EdgeInsets.all(8), child: Row(children: [
          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 8),
          Text('Lade Medizinische Dienste…', style: TextStyle(fontSize: 11)),
        ]))
      else Autocomplete<Map<String, dynamic>>(
        initialValue: TextEditingValue(text: _s('${prefix}_md_name')),
        displayStringForOption: (m) => m['name']?.toString() ?? '',
        optionsBuilder: (txt) {
          final q = txt.text.trim().toLowerCase();
          if (q.isEmpty) return _mdList;
          return _mdList.where((m) =>
            (m['name']?.toString() ?? '').toLowerCase().contains(q) ||
            (m['kuerzel']?.toString() ?? '').toLowerCase().contains(q) ||
            (m['bundeslaender']?.toString() ?? '').toLowerCase().contains(q) ||
            (m['ort']?.toString() ?? '').toLowerCase().contains(q));
        },
        fieldViewBuilder: (ctx, controller, focusNode, onSubmit) => TextField(
          controller: controller, focusNode: focusNode,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixIcon: controller.text.isNotEmpty
                ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () {
                    controller.clear();
                    setState(() {
                      _a['${prefix}_md_id'] = '';
                      _a['${prefix}_md_name'] = '';
                      _a['${prefix}_gutachter_id'] = '';
                      _a['${prefix}_gutachter_name'] = '';
                    });
                  })
                : null,
            hintText: 'Zuständiger MD (z.B. „BW", „Ulm")…',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
          ),
        ),
        optionsViewBuilder: (ctx, onSel, options) => Align(alignment: Alignment.topLeft, child: Material(elevation: 4, borderRadius: BorderRadius.circular(6),
          child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 300, maxWidth: 600),
            child: ListView(padding: EdgeInsets.zero, shrinkWrap: true, children: options.map((m) => InkWell(
              onTap: () => onSel(m),
              child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m['name']?.toString() ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                if ((m['bundeslaender']?.toString() ?? '').isNotEmpty)
                  Text(m['bundeslaender'].toString(), style: TextStyle(fontSize: 10, color: Colors.deepPurple.shade600, fontStyle: FontStyle.italic)),
                Text('${m['plz'] ?? ''} ${m['ort'] ?? ''}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
              ])),
            )).toList()),
          ),
        )),
        onSelected: (m) {
          final mdId = int.tryParse(m['id']?.toString() ?? '');
          setState(() {
            _a['${prefix}_md_id'] = m['id']?.toString() ?? '';
            _a['${prefix}_md_name'] = m['name']?.toString() ?? '';
            _a['${prefix}_gutachter_id'] = '';
            _a['${prefix}_gutachter_name'] = '';
            _gutachterLoaded = false;
            _gutachterLoadedForMdId = null;
          });
          if (mdId != null) _loadGutachterList(mdId);
        },
      ),
      if (selectedMd != null) ...[
        const SizedBox(height: 8),
        _buildGutachterSection(selectedMd, prefix: prefix),
      ],
    ]);
  }

  Widget _buildGutachterSection(Map<String, dynamic> md, {String prefix = 'zweitgutachten'}) {
    final mdId = int.tryParse(md['id']?.toString() ?? '') ?? 0;
    if (mdId > 0 && _gutachterLoadedForMdId != mdId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadGutachterList(mdId));
    }
    final selGId = int.tryParse(_s('${prefix}_gutachter_id'));
    Map<String, dynamic>? selG;
    if (selGId != null) {
      selG = _gutachterList.firstWhere(
        (g) => (g['id'] as int?) == selGId || int.tryParse(g['id'].toString()) == selGId,
        orElse: () => {},
      );
      if (selG.isEmpty) selG = null;
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.deepPurple.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.deepPurple.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.person_search, size: 14, color: Colors.deepPurple.shade700),
          const SizedBox(width: 4),
          Text('Gutachter (Person)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.deepPurple.shade800)),
          const Spacer(),
          if (_gutachterLoaded)
            Text('${_gutachterList.length} für ${md['kuerzel'] ?? md['name']}', style: TextStyle(fontSize: 9, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
        ]),
        const SizedBox(height: 6),
        if (!_gutachterLoaded)
          const Padding(padding: EdgeInsets.all(4), child: Text('Lade…', style: TextStyle(fontSize: 10)))
        else if (_gutachterList.isEmpty)
          Text('Noch keiner registriert für ${md['kuerzel'] ?? md['name']}', style: TextStyle(fontSize: 10, color: Colors.grey.shade700, fontStyle: FontStyle.italic))
        else Autocomplete<Map<String, dynamic>>(
          initialValue: TextEditingValue(text: _s('${prefix}_gutachter_name')),
          displayStringForOption: (g) => '${g['vorname'] ?? ''} ${g['nachname'] ?? ''}'.trim(),
          optionsBuilder: (txt) {
            final q = txt.text.trim().toLowerCase();
            if (q.isEmpty) return _gutachterList;
            return _gutachterList.where((g) =>
              (g['vorname']?.toString() ?? '').toLowerCase().contains(q) ||
              (g['nachname']?.toString() ?? '').toLowerCase().contains(q));
          },
          fieldViewBuilder: (ctx, controller, focusNode, onSubmit) => TextField(
            controller: controller, focusNode: focusNode,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, size: 16),
              hintText: 'Gutachter suchen…',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
          optionsViewBuilder: (ctx, onSel, options) => Align(alignment: Alignment.topLeft, child: Material(elevation: 4, borderRadius: BorderRadius.circular(6),
            child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 240, maxWidth: 500),
              child: ListView(padding: EdgeInsets.zero, shrinkWrap: true, children: options.map((g) => InkWell(
                onTap: () => onSel(g),
                child: Padding(padding: const EdgeInsets.all(8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${g['vorname'] ?? ''} ${g['nachname'] ?? ''}'.trim(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  if ((g['qualifikation']?.toString() ?? '').isNotEmpty)
                    Text(g['qualifikation'].toString(), style: TextStyle(fontSize: 10, color: Colors.deepPurple.shade600)),
                ])),
              )).toList()),
            ),
          )),
          onSelected: (g) => setState(() {
            _a['${prefix}_gutachter_id'] = g['id']?.toString() ?? '';
            _a['${prefix}_gutachter_name'] = '${g['vorname'] ?? ''} ${g['nachname'] ?? ''}'.trim();
          }),
        ),
        if (selG != null) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.deepPurple.shade400)),
            child: Row(children: [
              Icon(Icons.person, size: 16, color: Colors.deepPurple.shade700),
              const SizedBox(width: 6),
              Expanded(child: Text('${selG['vorname'] ?? ''} ${selG['nachname'] ?? ''}'.trim() + ((selG['qualifikation']?.toString() ?? '').isNotEmpty ? " — ${selG['qualifikation']}" : ""),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500))),
            ]),
          ),
        ],
        const SizedBox(height: 6),
        OutlinedButton.icon(
          icon: Icon(Icons.person_add, size: 12, color: Colors.deepPurple.shade700),
          label: Text('Neuer Gutachter für ${md['kuerzel'] ?? md['name']}', style: TextStyle(fontSize: 10, color: Colors.deepPurple.shade700)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.deepPurple.shade400),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), minimumSize: Size.zero,
          ),
          onPressed: () => _showNeuerGutachterDialog(mdId, md['name']?.toString() ?? '', prefix: prefix),
        ),
      ]),
    );
  }

  void _showNeuerGutachterDialog(int mdId, String mdName, {String prefix = 'zweitgutachten'}) {
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
          initialValue: qualifikation, isExpanded: true,
          decoration: const InputDecoration(labelText: 'Qualifikation', isDense: true, border: OutlineInputBorder()),
          items: qualifikationen.map((q) => DropdownMenuItem(value: q, child: Text(q, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (v) => setD(() => qualifikation = v ?? 'Pflegefachperson'),
        ),
        const SizedBox(height: 12),
        TextField(controller: notizC, maxLines: 2, decoration: const InputDecoration(labelText: 'Notiz (optional)', isDense: true, border: OutlineInputBorder())),
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
              if (res['success'] != true) throw Exception(res['message'] ?? 'Server-Fehler');
              final newId = res['id'] as int?;
              final fullName = '${vornameC.text.trim()} ${nachnameC.text.trim()}';
              setState(() {
                _a['${prefix}_gutachter_id'] = newId?.toString() ?? '';
                _a['${prefix}_gutachter_name'] = fullName;
                _gutachterLoaded = false;
                _gutachterLoadedForMdId = null;
              });
              await _loadGutachterList(mdId);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gutachter „$fullName" angelegt'), backgroundColor: Colors.green));
            } catch (e) {
              if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
            }
          },
          child: const Text('Anlegen'),
        ),
      ],
    )));
  }

  Widget _sectionHeader(IconData icon, String title, MaterialColor color) {
    return Row(children: [
      Icon(icon, size: 18, color: color.shade700),
      const SizedBox(width: 6),
      Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color.shade800)),
    ]);
  }
}

