import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import 'korrespondenz_attachments_widget.dart';

/// Tab-ul "Hilfsmittel" din pagina Arzt (între Rezept și Heilmittel).
/// Tracking pentru toate Hilfsmittel (Schuheinlagen PG 08, Bandagen PG 05,
/// Hörgeräte PG 13 etc.) eliberate de un Sanitätshaus.
///
/// Backend: `/api/admin/rezept_manage.php` + tabele `mitglied_rezepte` /
/// `mitglied_rezept_status`. Când userul setează un Abholung-Termin
/// (Datum + Uhrzeit), serverul auto-creează un rând în `termine` (cu
/// `rezept_id` set), deci terminul apare și în Terminverwaltung.
/// Routet Rezept-Aktionen: für Augenarzt auf den eigenen, entkoppelten Endpunkt
/// (augenarzt_hilfsmittel), außer die geteilte Sanitätshaus-Katalogsuche.
Future<Map<String, dynamic>> _rezeptRoute(ApiService api, bool augenarzt, bool hno, Map<String, dynamic> data) =>
    (data['action'] == 'sanitaetshaus_list')
        ? api.rezeptAction(data)
        : hno
            ? api.hnoRezeptAction(data)
            : augenarzt
                ? api.augenarztRezeptAction(data)
                : api.rezeptAction(data);

class HilfsmittelTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final String arztType;
  final String arztTitle;
  final String? arztName;
  /// true = eigene augenarzt_hilfsmittel-Speicherung (entkoppelt).
  final bool augenarzt;
  final bool hno;

  const HilfsmittelTab({
    super.key,
    required this.apiService,
    required this.userId,
    required this.arztType,
    required this.arztTitle,
    this.arztName,
    this.augenarzt = false,
    this.hno = false,
  });

  @override
  State<HilfsmittelTab> createState() => _HilfsmittelTabState();
}

class _HilfsmittelTabState extends State<HilfsmittelTab> {
  List<Map<String, dynamic>> _rezepte = [];
  List<Map<String, dynamic>> _sanitaetshaeuser = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await _rezeptRoute(widget.apiService, widget.augenarzt, widget.hno, {
      'action': 'list',
      'user_id': widget.userId,
      'arzt_type': widget.arztType,
    });
    final s = await _rezeptRoute(widget.apiService, widget.augenarzt, widget.hno, {'action': 'sanitaetshaus_list'});
    if (!mounted) return;
    setState(() {
      _rezepte = (r['rezepte'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      _sanitaetshaeuser = (s['sanitaetshaeuser'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Intro / legal banner
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.teal.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.teal.shade200),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline, color: Colors.teal.shade800, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: TextStyle(fontSize: 11.5, color: Colors.teal.shade900, height: 1.4),
                  children: const [
                    TextSpan(text: 'Hilfsmittel ', style: TextStyle(fontWeight: FontWeight.bold)),
                    TextSpan(text: 'sind körpernahe Hilfen, die beim Patienten verbleiben (Schuheinlagen PG 08, Bandagen PG 05, Hörgeräte PG 13, Sehhilfen PG 25 etc.). Verordnung erfolgt per Muster 16 — Einlösung beim Sanitätshaus. GKV-Zuzahlung: 10 %, mind. 5 €, max. 10 € pro Stück. Wiederversorgung Schuheinlagen frühestens nach 6 Monaten.'),
                  ],
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: Text(
              'Hilfsmittel-Rezepte (${_rezepte.length})',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
          FilledButton.icon(
            onPressed: _showNewRezeptDialog,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Neues Rezept'),
            style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade700),
          ),
        ]),
        const SizedBox(height: 10),
        if (_loading)
          const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
        else if (_rezepte.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(children: [
              Icon(Icons.healing, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 8),
              Text('Keine Hilfsmittel-Rezepte vorhanden',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
              const SizedBox(height: 4),
              Text('Über „Neues Rezept" anlegen (z. B. Schuheinlagen).',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ]),
          )
        else
          ..._rezepte.map(_rezeptCard),
      ]),
    );
  }

  Widget _rezeptCard(Map<String, dynamic> r) {
    final timeline = (r['status_timeline'] as List?) ?? const [];
    final lastStep = timeline.isNotEmpty ? timeline.last : null;
    final completedSteps = timeline.where((s) => s['erledigt_am'] != null).length;
    const totalSteps = 6;
    final progress = completedSteps / totalSteps;
    Color statusColor = Colors.grey.shade400;
    String statusLabel = 'Neu';
    if (lastStep != null) {
      final s = (lastStep as Map)['schritt']?.toString() ?? '';
      final done = lastStep['erledigt_am'] != null;
      if (s == 'zuzahlung' && done) {
        statusColor = Colors.green; statusLabel = 'Abgeschlossen';
      } else if (s == 'abholung') {
        statusColor = Colors.orange; statusLabel = done ? 'Abgeholt' : 'Termin geplant';
      } else if (s == 'bestellt') {
        statusColor = Colors.blue; statusLabel = 'Bestellt';
      } else if (s == 'eingeloest') {
        statusColor = Colors.blue.shade300; statusLabel = 'Eingelöst';
      } else if (s == 'abgeholt') {
        statusColor = Colors.purple; statusLabel = 'Rezept abgeholt';
      } else {
        statusColor = Colors.grey.shade600; statusLabel = 'Ausgestellt';
      }
    }

    return InkWell(
      onTap: () => _showRezeptDetailDialog(r),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(Icons.healing, size: 22, color: statusColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r['hilfsmittel']?.toString() ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Row(children: [
                if ((r['diagnose_label'] ?? '').toString().isNotEmpty)
                  Expanded(child: Text(
                    '${r['diagnose_label']}${(r['diagnose_icd10'] ?? '').toString().isNotEmpty ? ' · ${r['diagnose_icd10']}' : ''}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    overflow: TextOverflow.ellipsis,
                  )),
                Text(_fmtDate(r['datum_ausstellung']?.toString()),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                  child: Text(statusLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress, minHeight: 5,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text('$completedSteps/$totalSteps', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
              ]),
            ]),
          ),
          const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
        ]),
      ),
    );
  }

  String _fmtDate(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try { return DateFormat('dd.MM.yyyy').format(DateTime.parse(raw)); } catch (_) { return raw; }
  }

  // ──────────────────────── NEW REZEPT DIALOG ────────────────────────
  static const _diagnosen = [
    {'icd10': 'M21.4', 'label': 'Senk-/Spreiz-/Knickfuß'},
    {'icd10': 'M20.1', 'label': 'Hallux valgus'},
    {'icd10': 'M72.2', 'label': 'Plantarfasziitis (Fersensporn)'},
    {'icd10': 'E10/E11', 'label': 'Diabetes — Diabetiker-Einlagen'},
    {'icd10': 'M41/M21.7', 'label': 'Skoliose / Beinlängendifferenz'},
  ];

  Future<void> _showNewRezeptDialog() async {
    final hilfsC = TextEditingController(text: 'Orthopädische Einlagen');
    final datumC = TextEditingController(text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
    final arztNameC = TextEditingController(text: widget.arztName ?? '');
    final freitextC = TextEditingController();
    final begruendungC = TextEditingController();
    final notizenC = TextEditingController();
    String selectedIcd = '';
    String selectedLabel = '';
    int anzahlPaare = 1;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Row(children: [
            Icon(Icons.medical_services, color: Colors.teal.shade700),
            const SizedBox(width: 8),
            const Text('Neues Hilfsmittel-Rezept', style: TextStyle(fontSize: 16)),
          ]),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(
                  controller: hilfsC,
                  decoration: InputDecoration(
                    labelText: 'Verordnetes Hilfsmittel',
                    isDense: true,
                    prefixIcon: const Icon(Icons.healing, size: 18),
                    hintText: 'z. B. Orthopädische Einlagen, Bandage, Hörgerät',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(
                    controller: datumC,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Ausstellungsdatum',
                      isDense: true,
                      prefixIcon: const Icon(Icons.calendar_today, size: 18),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.event, size: 18),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx, initialDate: DateTime.tryParse(datumC.text) ?? DateTime.now(),
                            firstDate: DateTime(2020), lastDate: DateTime(2099),
                          );
                          if (picked != null) setDlg(() => datumC.text = DateFormat('yyyy-MM-dd').format(picked));
                        },
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(
                    controller: arztNameC,
                    decoration: InputDecoration(
                      labelText: 'Ausstellender Arzt',
                      isDense: true,
                      prefixIcon: const Icon(Icons.person, size: 18),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  )),
                ]),
                const SizedBox(height: 14),
                Text('Diagnose / Indikation (ICD-10):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                const SizedBox(height: 6),
                ..._diagnosen.map((d) => RadioListTile<String>(
                  value: d['icd10']!,
                  groupValue: selectedIcd,
                  onChanged: (v) => setDlg(() {
                    selectedIcd = v ?? '';
                    selectedLabel = d['label']!;
                  }),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  visualDensity: const VisualDensity(vertical: -3),
                  title: Text(d['label']!, style: const TextStyle(fontSize: 12)),
                  subtitle: Text(d['icd10']!, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                )),
                RadioListTile<String>(
                  value: 'andere',
                  groupValue: selectedIcd,
                  onChanged: (v) => setDlg(() {
                    selectedIcd = 'andere';
                    selectedLabel = 'Andere';
                  }),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  visualDensity: const VisualDensity(vertical: -3),
                  title: const Text('Andere — freier Text', style: TextStyle(fontSize: 12)),
                ),
                if (selectedIcd == 'andere')
                  Padding(
                    padding: const EdgeInsets.only(left: 32, top: 4, bottom: 4),
                    child: TextField(
                      controller: freitextC,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'Diagnose beschreiben',
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Text('Anzahl Paare:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                Row(children: [
                  Radio<int>(value: 1, groupValue: anzahlPaare, onChanged: (v) => setDlg(() => anzahlPaare = v ?? 1)),
                  const Text('1 Paar', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 16),
                  Radio<int>(value: 2, groupValue: anzahlPaare, onChanged: (v) => setDlg(() => anzahlPaare = v ?? 2)),
                  const Text('2 Paare (Wechselversorgung)', style: TextStyle(fontSize: 12)),
                ]),
                if (anzahlPaare == 2)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: TextField(
                      controller: begruendungC,
                      decoration: InputDecoration(
                        labelText: 'Begründung Wechselpaar (z. B. „aus hygienischen Gründen")',
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                TextField(
                  controller: notizenC,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Notizen (optional)',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            FilledButton(
              onPressed: () async {
                if (hilfsC.text.trim().isEmpty || datumC.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Hilfsmittel und Datum sind Pflicht'), backgroundColor: Colors.red),
                  );
                  return;
                }
                final r = await _rezeptRoute(widget.apiService, widget.augenarzt, widget.hno, {
                  'action': 'create',
                  'user_id': widget.userId,
                  'arzt_type': widget.arztType,
                  'hilfsmittel': hilfsC.text.trim(),
                  'diagnose_icd10': selectedIcd == 'andere' ? null : selectedIcd,
                  'diagnose_label': selectedIcd == 'andere' ? 'Andere' : selectedLabel,
                  'diagnose_freitext': selectedIcd == 'andere' ? freitextC.text.trim() : null,
                  'anzahl_paare': anzahlPaare,
                  'begruendung_wechselpaar': anzahlPaare == 2 ? begruendungC.text.trim() : null,
                  'datum_ausstellung': datumC.text,
                  'arzt_name': arztNameC.text.trim(),
                  'notizen': notizenC.text.trim(),
                });
                if (r['success'] == true) {
                  if (mounted) Navigator.pop(ctx);
                  await _load();
                } else {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Fehler: ${r['message'] ?? ''}'), backgroundColor: Colors.red),
                  );
                }
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────── DETAIL / TIMELINE MODAL ────────────────────────
  Future<void> _showRezeptDetailDialog(Map<String, dynamic> rezept) async {
    await showDialog(
      context: context,
      builder: (ctx) => _RezeptDetailDialog(
        apiService: widget.apiService,
        rezept: rezept,
        sanitaetshaeuser: _sanitaetshaeuser,
        onChanged: _load,
        augenarzt: widget.augenarzt,
      hno: widget.hno,
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//                  DETAIL DIALOG WITH 6-STEP TIMELINE
// ════════════════════════════════════════════════════════════════════
class _RezeptDetailDialog extends StatefulWidget {
  final ApiService apiService;
  final Map<String, dynamic> rezept;
  final List<Map<String, dynamic>> sanitaetshaeuser;
  final VoidCallback onChanged;
  final bool augenarzt;
  final bool hno;

  const _RezeptDetailDialog({
    required this.apiService,
    required this.rezept,
    required this.sanitaetshaeuser,
    required this.onChanged,
    this.augenarzt = false,
    this.hno = false,
  });

  @override
  State<_RezeptDetailDialog> createState() => _RezeptDetailDialogState();
}

class _RezeptDetailDialogState extends State<_RezeptDetailDialog> {
  late Map<String, dynamic> _rezept;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _rezept = Map<String, dynamic>.from(widget.rezept);
  }

  static const _steps = [
    {'key': 'ausgestellt',  'label': 'Rezept ausgestellt',         'icon': Icons.assignment},
    {'key': 'abgeholt',     'label': 'Rezept abgeholt (Mitglied)', 'icon': Icons.local_shipping},
    {'key': 'eingeloest',   'label': 'Rezept eingelöst (Sanitätshaus)', 'icon': Icons.store},
    {'key': 'bestellt',     'label': 'Bestellung aufgegeben',      'icon': Icons.shopping_bag},
    {'key': 'abholung',     'label': 'Abholung beim Sanitätshaus', 'icon': Icons.event_available},
    {'key': 'zuzahlung',    'label': 'Zuzahlung geleistet',        'icon': Icons.euro},
  ];

  Map<String, dynamic>? _statusFor(String key) {
    final list = (_rezept['status_timeline'] as List?) ?? const [];
    for (final s in list) {
      if (s is Map && s['schritt']?.toString() == key) return Map<String, dynamic>.from(s);
    }
    return null;
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    final r = await _rezeptRoute(widget.apiService, widget.augenarzt, widget.hno, {
      'action': 'detail',
      'rezept_id': _rezept['id'],
    });
    if (r['success'] == true && r['rezept'] != null) {
      setState(() {
        _rezept = Map<String, dynamic>.from(r['rezept']);
        _busy = false;
      });
    } else {
      setState(() => _busy = false);
    }
    widget.onChanged();
  }

  String _fmtDate(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try { return DateFormat('dd.MM.yyyy').format(DateTime.parse(raw)); } catch (_) { return raw; }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 700),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Header
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.teal.shade700,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            ),
            child: Row(children: [
              const Icon(Icons.medical_services, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(child: Text(
                'Rezept #${_rezept['id']} — ${_rezept['hilfsmittel']}',
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              )),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.white, size: 20),
                tooltip: 'Rezept löschen',
                onPressed: _confirmDelete,
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ]),
          ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _detailsBlock(),
                const SizedBox(height: 14),
                Text('⏱  Chronologie', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                const Divider(height: 12),
                ..._steps.map((s) => _stepRow(s['key'] as String, s['label'] as String, s['icon'] as IconData)),
                const SizedBox(height: 14),
                if (_rezept['wiederversorgung_ab'] != null) Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.event_repeat, size: 18, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                        'Wiederversorgung möglich ab: ${_fmtDate(_rezept['wiederversorgung_ab']?.toString())} (≈ 6 Monate)',
                        style: TextStyle(fontSize: 12, color: Colors.blue.shade900, fontWeight: FontWeight.w600),
                      )),
                    ]),
                    if (_rezept['wiederversorgung_ticket_id'] != null) ...[
                      const SizedBox(height: 6),
                      Row(children: [
                        Icon(Icons.notifications_active, size: 14, color: Colors.blue.shade600),
                        const SizedBox(width: 6),
                        Expanded(child: Text(
                          'Erinnerungs-Ticket #${_rezept['wiederversorgung_ticket_id']} wird zum Stichtag automatisch beim Mitglied geöffnet.',
                          style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
                        )),
                      ]),
                    ],
                  ]),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _detailsBlock() {
    String t(String k) => (_rezept[k] ?? '').toString();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _detailRow('Hilfsmittel', t('hilfsmittel')),
        _detailRow('Diagnose', '${t('diagnose_label')}${t('diagnose_icd10').isNotEmpty ? ' (${t('diagnose_icd10')})' : ''}'),
        if (t('diagnose_freitext').isNotEmpty) _detailRow('Freier Text', t('diagnose_freitext')),
        _detailRow('Anzahl Paare', t('anzahl_paare')),
        if (t('begruendung_wechselpaar').isNotEmpty) _detailRow('Begründung', t('begruendung_wechselpaar')),
        _detailRow('Ausstellungsdatum', _fmtDate(t('datum_ausstellung'))),
        if (t('arzt_name').isNotEmpty) _detailRow('Arzt', t('arzt_name')),
        if (t('notizen').isNotEmpty) _detailRow('Notizen', t('notizen')),
      ]),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 130, child: Text('$label:', style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
        Expanded(child: Text(value.isEmpty ? '—' : value, style: const TextStyle(fontSize: 12))),
      ]),
    );
  }

  Widget _stepRow(String key, String label, IconData icon) {
    final status = _statusFor(key);
    final isDone = status != null && status['erledigt_am'] != null;
    final isScheduled = status != null && status['datum'] != null;
    final color = isDone ? Colors.green : (isScheduled ? Colors.orange : Colors.grey);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: (isDone ? Colors.green : (isScheduled ? Colors.orange : Colors.grey)).shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.shade300),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(isDone ? Icons.check_circle : (isScheduled ? Icons.schedule : Icons.radio_button_unchecked), color: color.shade700, size: 18),
          const SizedBox(width: 8),
          Icon(icon, size: 16, color: color.shade600),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color.shade900))),
          IconButton(
            icon: const Icon(Icons.edit, size: 16),
            tooltip: 'Schritt bearbeiten',
            onPressed: () => _editStep(key, label, status),
          ),
        ]),
        if (status != null) ...[
          const SizedBox(height: 4),
          if (status['datum'] != null) Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Text(
              key == 'abholung'
                ? 'Termin: ${_fmtDate(status['datum'])} um ${_fmtTime(status['uhrzeit'])}'
                : 'Datum: ${_fmtDate(status['datum'])}',
              style: TextStyle(fontSize: 11, color: color.shade800),
            ),
          ),
          if (status['erledigt_am'] != null) Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Text('✓ Erledigt am: ${_fmtDate(status['erledigt_am'])}',
              style: TextStyle(fontSize: 11, color: Colors.green.shade800, fontWeight: FontWeight.w600)),
          ),
          if (status['sanitaetshaus'] != null) _sanitCard(Map<String, dynamic>.from(status['sanitaetshaus'])),
          if ((status['bestellt_text'] ?? '').toString().isNotEmpty) Padding(
            padding: const EdgeInsets.only(left: 26, top: 4),
            child: Text('• Bestellt: ${status['bestellt_text']}', style: TextStyle(fontSize: 11, color: color.shade800)),
          ),
          if (status['voraussichtl_lieferung'] != null) Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Text('• Lieferung: ${_fmtDate(status['voraussichtl_lieferung'])}',
              style: TextStyle(fontSize: 11, color: color.shade800)),
          ),
          if (status['zuzahlung_betrag'] != null) Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Text('• Betrag: ${status['zuzahlung_betrag']} €${(status['zuzahlung_befreit'] == 1 || status['zuzahlung_befreit'] == '1') ? '  (befreit)' : ''}',
              style: TextStyle(fontSize: 11, color: color.shade800)),
          ),
          // Zahlungsbelege — Rechnung / Kassenzettel als Nachweis der
          // Zuzahlung. Nur anzeigen wenn der Zuzahlungs-Status-Row schon
          // existiert (sonst kein korrespondenz_id) UND der Mitglied nicht
          // von der Zuzahlung befreit ist (befreit → kein Beleg nötig).
          if (key == 'zuzahlung'
              && status['id'] != null
              && !(status['zuzahlung_befreit'] == 1 || status['zuzahlung_befreit'] == '1'))
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 6, right: 6),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: color.shade200),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.receipt_long, size: 14, color: color.shade700),
                    const SizedBox(width: 6),
                    Text('Rechnung / Kassenzettel',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color.shade900)),
                  ]),
                  const SizedBox(height: 4),
                  KorrAttachmentsWidget(
                    apiService: widget.apiService,
                    modul: 'rezept_zuzahlung',
                    korrespondenzId: int.tryParse(status['id'].toString()) ?? 0,
                  ),
                ]),
              ),
            ),
          if (key == 'abholung' && status['datum'] != null && status['erledigt_am'] == null) Padding(
            padding: const EdgeInsets.only(left: 26, top: 6),
            child: ElevatedButton.icon(
              onPressed: () => _markErledigt(key),
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Als erledigt markieren', style: TextStyle(fontSize: 11)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade600, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
            ),
          ),
        ] else Padding(
          padding: const EdgeInsets.only(left: 26, top: 2),
          child: Text('⏳ ausstehend', style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
        ),
      ]),
    );
  }

  Widget _sanitCard(Map<String, dynamic> s) {
    return Container(
      margin: const EdgeInsets.only(top: 6, left: 26),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.teal.shade300)),
      child: Row(children: [
        Icon(Icons.local_pharmacy, color: Colors.teal.shade700, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s['name']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal.shade900)),
          if ((s['strasse'] ?? '').toString().isNotEmpty || (s['plz'] ?? '').toString().isNotEmpty)
            Text('${s['strasse'] ?? ''}, ${s['plz'] ?? ''} ${s['ort'] ?? ''}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          if ((s['telefon'] ?? '').toString().isNotEmpty)
            Text('☎ ${s['telefon']}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
        ])),
      ]),
    );
  }

  String _fmtTime(dynamic raw) {
    final s = raw?.toString() ?? '';
    if (s.length >= 5) return s.substring(0, 5);
    return s;
  }

  // ──────────── Edit step dialog ────────────
  Future<void> _editStep(String key, String label, Map<String, dynamic>? existing) async {
    final datumC = TextEditingController(text: existing?['datum']?.toString() ?? '');
    final uhrzeitC = TextEditingController(text: _fmtTime(existing?['uhrzeit']));
    final erledigtC = TextEditingController(text: existing?['erledigt_am']?.toString() ?? '');
    final bestelltC = TextEditingController(text: existing?['bestellt_text']?.toString() ?? '');
    final lieferungC = TextEditingController(text: existing?['voraussichtl_lieferung']?.toString() ?? '');
    final betragC = TextEditingController(text: existing?['zuzahlung_betrag']?.toString() ?? '');
    final notizC = TextEditingController(text: existing?['notiz']?.toString() ?? '');
    bool befreit = existing?['zuzahlung_befreit'] == 1 || existing?['zuzahlung_befreit'] == '1';
    int? sanitId = existing?['sanitaetshaus_id'] != null ? int.tryParse(existing!['sanitaetshaus_id'].toString()) : null;

    final showSanit = key == 'eingeloest' || key == 'bestellt' || key == 'abholung';
    final showBestellung = key == 'bestellt';
    final showZuzahlung = key == 'zuzahlung';
    final showUhrzeit = key == 'abholung';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(label, style: const TextStyle(fontSize: 15)),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: TextField(
                    controller: datumC,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: key == 'abholung' ? 'Termin-Datum' : 'Datum',
                      isDense: true,
                      prefixIcon: const Icon(Icons.calendar_today, size: 18),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.event, size: 18),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx, initialDate: DateTime.tryParse(datumC.text) ?? DateTime.now(),
                            firstDate: DateTime(2020), lastDate: DateTime(2099),
                          );
                          if (picked != null) setDlg(() => datumC.text = DateFormat('yyyy-MM-dd').format(picked));
                        },
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  )),
                  if (showUhrzeit) ...[
                    const SizedBox(width: 8),
                    Expanded(child: TextField(
                      controller: uhrzeitC,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'Uhrzeit',
                        isDense: true,
                        prefixIcon: const Icon(Icons.access_time, size: 18),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.schedule, size: 18),
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: ctx,
                              initialTime: TimeOfDay.now(),
                            );
                            if (picked != null) {
                              setDlg(() => uhrzeitC.text = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
                            }
                          },
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    )),
                  ],
                ]),
                if (showSanit) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int?>(
                    initialValue: sanitId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Sanitätshaus',
                      isDense: true,
                      prefixIcon: const Icon(Icons.local_pharmacy, size: 18),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('— auswählen —', style: TextStyle(fontSize: 12))),
                      ...widget.sanitaetshaeuser.map((s) => DropdownMenuItem<int?>(
                        value: int.tryParse(s['id'].toString()),
                        child: Text('${s['name']} · ${s['ort'] ?? ''}', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                      )),
                    ],
                    onChanged: (v) => setDlg(() => sanitId = v),
                  ),
                ],
                if (showBestellung) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: bestelltC,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Bestellt (z. B. „Maßeinlagen 1 Paar, Anpassung 1×")',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: lieferungC,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Voraussichtliche Lieferung',
                      isDense: true,
                      prefixIcon: const Icon(Icons.local_shipping, size: 18),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.event, size: 18),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx, initialDate: DateTime.tryParse(lieferungC.text) ?? DateTime.now().add(const Duration(days: 14)),
                            firstDate: DateTime.now(), lastDate: DateTime(2099),
                          );
                          if (picked != null) setDlg(() => lieferungC.text = DateFormat('yyyy-MM-dd').format(picked));
                        },
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
                if (showZuzahlung) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: TextField(
                      controller: betragC,
                      enabled: !befreit,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Betrag (€)',
                        isDense: true,
                        prefixIcon: const Icon(Icons.euro, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    )),
                    const SizedBox(width: 12),
                    Row(children: [
                      Checkbox(value: befreit, onChanged: (v) => setDlg(() => befreit = v ?? false)),
                      const Text('Befreit', style: TextStyle(fontSize: 12)),
                    ]),
                  ]),
                ],
                const SizedBox(height: 10),
                TextField(
                  controller: erledigtC,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Erledigt am (optional)',
                    isDense: true,
                    prefixIcon: const Icon(Icons.check_circle, size: 18),
                    suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (erledigtC.text.isNotEmpty)
                        IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => setDlg(() => erledigtC.text = '')),
                      IconButton(
                        icon: const Icon(Icons.event, size: 18),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx, initialDate: DateTime.tryParse(erledigtC.text) ?? DateTime.now(),
                            firstDate: DateTime(2020), lastDate: DateTime(2099),
                          );
                          if (picked != null) setDlg(() => erledigtC.text = DateFormat('yyyy-MM-dd').format(picked));
                        },
                      ),
                    ]),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notizC,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Notiz',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            FilledButton(
              onPressed: () async {
                final payload = <String, dynamic>{
                  'action': 'set_status',
                  'rezept_id': _rezept['id'],
                  'schritt': key,
                  'datum': datumC.text.isEmpty ? null : datumC.text,
                  'uhrzeit': showUhrzeit && uhrzeitC.text.isNotEmpty ? uhrzeitC.text : null,
                  'erledigt_am': erledigtC.text.isEmpty ? null : erledigtC.text,
                  'sanitaetshaus_id': showSanit ? sanitId : null,
                  'bestellt_text': showBestellung ? bestelltC.text.trim() : null,
                  'voraussichtl_lieferung': showBestellung && lieferungC.text.isNotEmpty ? lieferungC.text : null,
                  'zuzahlung_betrag': showZuzahlung && !befreit && betragC.text.isNotEmpty ? double.tryParse(betragC.text.replaceAll(',', '.')) : null,
                  'zuzahlung_befreit': showZuzahlung && befreit,
                  'notiz': notizC.text.trim(),
                };
                final r = await _rezeptRoute(widget.apiService, widget.augenarzt, widget.hno, payload);
                if (r['success'] == true) {
                  if (mounted) Navigator.pop(ctx);
                  await _refresh();
                } else {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Fehler: ${r['message'] ?? ''}'), backgroundColor: Colors.red),
                  );
                }
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markErledigt(String schritt) async {
    final r = await _rezeptRoute(widget.apiService, widget.augenarzt, widget.hno, {
      'action': 'mark_erledigt',
      'rezept_id': _rezept['id'],
      'schritt': schritt,
      'erledigt_am': DateFormat('yyyy-MM-dd').format(DateTime.now()),
    });
    if (r['success'] == true) {
      await _refresh();
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rezept löschen?'),
        content: Text('Rezept #${_rezept['id']} "${_rezept['hilfsmittel']}" inkl. aller Status-Schritte und ggf. zukünftige Termine werden entfernt.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final r = await _rezeptRoute(widget.apiService, widget.augenarzt, widget.hno, {'action': 'delete', 'rezept_id': _rezept['id']});
    if (r['success'] == true) {
      if (mounted) Navigator.pop(context);
      widget.onChanged();
    }
  }
}
