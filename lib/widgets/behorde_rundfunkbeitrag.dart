import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';
import 'file_viewer_dialog.dart';

class BehordeRundfunkbeitragContent extends StatefulWidget {
  final ApiService? apiService;
  final int? userId;
  final Map<String, dynamic> Function(String type) getData;
  final bool Function(String type) isLoading;
  final bool Function(String type) isSaving;
  final void Function(String type) loadData;
  final void Function(String type, Map<String, dynamic> data) saveData;

  const BehordeRundfunkbeitragContent({
    super.key,
    this.apiService,
    this.userId,
    required this.getData,
    required this.isLoading,
    required this.isSaving,
    required this.loadData,
    required this.saveData,
  });

  @override
  State<BehordeRundfunkbeitragContent> createState() => _BehordeRundfunkbeitragContentState();
}

class _BehordeRundfunkbeitragContentState extends State<BehordeRundfunkbeitragContent> {
  Map<String, Map<String, dynamic>> _dbData = {};
  List<Map<String, dynamic>> _antraege = [];
  List<Map<String, dynamic>> _korrespondenz = [];
  bool _loaded = false;
  bool _saving = false;
  bool _behoerdeEditing = false;

  @override
  void initState() {
    super.initState();
    _loadFromDB();
  }

  Future<void> _loadFromDB() async {
    if (widget.apiService == null || widget.userId == null) return;
    final res = await widget.apiService!.getRundfunkbeitragData(widget.userId!);
    final aRes = await widget.apiService!.listRundfunkbeitragAntraege(widget.userId!);
    final kRes = await widget.apiService!.listRundfunkbeitragKorrespondenz(widget.userId!);
    if (!mounted) return;
    setState(() {
      if (res['success'] == true && res['data'] is Map) {
        final raw = res['data'] as Map;
        _dbData = {};
        raw.forEach((k, v) {
          if (v is Map) _dbData[k.toString()] = Map<String, dynamic>.from(v);
        });
      }
      if (aRes['success'] == true && aRes['data'] is List) _antraege = (aRes['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (kRes['success'] == true && kRes['data'] is List) _korrespondenz = (kRes['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _loaded = true;
    });
  }

  Future<void> _save() async {
    if (widget.apiService == null || widget.userId == null) return;
    setState(() => _saving = true);
    await widget.apiService!.saveRundfunkbeitragData(widget.userId!, _dbData);
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
      length: 3,
      child: Column(children: [
        TabBar(
          labelColor: Colors.indigo.shade700,
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: Colors.indigo.shade700,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.account_balance, size: 16), text: 'Zuständige Behörde'),
            Tab(icon: Icon(Icons.description, size: 16), text: 'Anträge'),
            Tab(icon: Icon(Icons.mail, size: 16), text: 'Korrespondenz'),
          ],
        ),
        Expanded(child: TabBarView(children: [
          _buildBehoerdeTab(),
          _buildAntraegeTab(),
          _buildKorrespondenzTab(),
        ])),
      ]),
    );
  }

  // ============ TAB 1: ZUSTÄNDIGE BEHÖRDE ============

  Widget _buildBehoerdeTab() {
    final d = _b('behoerde');
    final hasData = (d['beitragsnummer']?.toString() ?? '').isNotEmpty;
    final readOnly = hasData && !_behoerdeEditing;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Institution info card
        Container(
          width: double.infinity, padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.indigo.shade200)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.radio, size: 22, color: Colors.indigo.shade700), const SizedBox(width: 10),
              Expanded(child: Text('ARD ZDF Deutschlandradio', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.indigo.shade800))),
            ]),
            const SizedBox(height: 8),
            _infoRow(Icons.business, 'Beitragsservice von ARD, ZDF und Deutschlandradio'),
            _infoRow(Icons.location_on, '50656 Köln'),
            _infoRow(Icons.phone, '01806 999 555 10 (20 Ct/Anruf)'),
            _infoRow(Icons.language, 'www.rundfunkbeitrag.de'),
            _infoRow(Icons.euro, 'Beitrag: 18,36 €/Monat (220,32 €/Jahr)'),
          ]),
        ),
        const SizedBox(height: 16),
        // Beitragsdaten
        Row(children: [
          Icon(Icons.assignment, size: 20, color: Colors.indigo.shade700), const SizedBox(width: 8),
          Expanded(child: Text('Beitragsdaten', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo.shade700))),
          if (hasData)
            IconButton(
              icon: Icon(_behoerdeEditing ? Icons.check : Icons.edit, size: 20, color: Colors.indigo.shade700),
              tooltip: _behoerdeEditing ? 'Fertig' : 'Bearbeiten',
              onPressed: () {
                if (_behoerdeEditing) _save();
                setState(() => _behoerdeEditing = !_behoerdeEditing);
              },
            ),
        ]),
        const SizedBox(height: 12),
        if (readOnly) ...[
          _readOnlyRow(Icons.numbers, 'Beitragsnummer', d['beitragsnummer']),
          _readOnlyRow(Icons.person, 'Kontoinhaber', d['kontoinhaber']),
          _readOnlyRow(Icons.calendar_today, 'Angemeldet seit', d['angemeldet_seit']),
          _readOnlyRow(Icons.payments, 'Zahlungsart', d['zahlungsart']),
          _readOnlyRow(Icons.account_balance, 'IBAN', d['iban']),
          _readOnlyRow(Icons.check_circle, 'Status', d['status']),
          _readOnlyRow(Icons.note, 'Notizen', d['notizen']),
        ] else ...[
          _field(d, 'beitragsnummer', 'Beitragsnummer (9-stellig)', Icons.numbers, hint: 'z.B. 123 456 789'),
          _field(d, 'kontoinhaber', 'Kontoinhaber', Icons.person),
          _field(d, 'angemeldet_seit', 'Angemeldet seit', Icons.calendar_today, hint: 'YYYY-MM-DD'),
          _dropdownField(d, 'zahlungsart', 'Zahlungsart', Icons.payments, ['Lastschrift', 'Überweisung', 'Dauerauftrag']),
          _field(d, 'iban', 'IBAN (für Lastschrift)', Icons.account_balance),
          _dropdownField(d, 'status', 'Status', Icons.check_circle, ['Aktiv', 'Befreit', 'Ermäßigt', 'Abgemeldet', 'Rückstand']),
          _field(d, 'notizen', 'Notizen', Icons.note, maxLines: 3),
          _saveBtn(),
        ],
      ]),
    );
  }

  // ============ TAB 2: ANTRÄGE (BEFREIUNG) ============

  static const _befreiungsgruende = [
    (key: 'buergergeld', label: 'Bürgergeld (SGB II)', icon: Icons.account_balance_wallet, beschreibung: 'Empfänger von Bürgergeld (ehem. ALG II / Sozialgeld)'),
    (key: 'grundsicherung_alter', label: 'Grundsicherung im Alter (SGB XII)', icon: Icons.elderly, beschreibung: 'Empfänger von Grundsicherung im Alter und bei Erwerbsminderung'),
    (key: 'hilfe_lebensunterhalt', label: 'Hilfe zum Lebensunterhalt (SGB XII)', icon: Icons.volunteer_activism, beschreibung: 'Empfänger von Hilfe zum Lebensunterhalt nach dem SGB XII'),
    (key: 'asylbewerber', label: 'Asylbewerberleistungen', icon: Icons.public, beschreibung: 'Empfänger von Leistungen nach dem Asylbewerberleistungsgesetz'),
    (key: 'bafoeg', label: 'BAföG', icon: Icons.school, beschreibung: 'Studierende/Schüler mit BAföG (nicht bei den Eltern wohnend)'),
    (key: 'bab', label: 'Berufsausbildungsbeihilfe (BAB)', icon: Icons.work, beschreibung: 'Empfänger von Berufsausbildungsbeihilfe'),
    (key: 'ausbildungsgeld', label: 'Ausbildungsgeld', icon: Icons.work_outline, beschreibung: 'Empfänger von Ausbildungsgeld nach SGB III'),
    (key: 'pflegegeld', label: 'Hilfe zur Pflege (SGB XII)', icon: Icons.local_hospital, beschreibung: 'Empfänger von Hilfe zur Pflege nach dem SGB XII'),
    (key: 'haertefall', label: 'Härtefall (§ 4 Abs. 6 RBStV)', icon: Icons.warning, beschreibung: 'Einkommen übersteigt den Bedarf um weniger als 18,36 €'),
    (key: 'ermaessigung_rf', label: 'Ermäßigung: RF-Merkzeichen', icon: Icons.accessible, beschreibung: 'Ermäßigung auf 6,12 €/Monat bei Merkzeichen RF im Schwerbehindertenausweis'),
    (key: 'ermaessigung_blind', label: 'Ermäßigung: Blind/Gehörlos', icon: Icons.visibility_off, beschreibung: 'Blinde/stark Sehbehinderte (GdB 60+) oder Gehörlose'),
  ];

  Widget _buildAntraegeTab() {
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Row(children: [
        Icon(Icons.description, size: 20, color: Colors.indigo.shade700), const SizedBox(width: 8),
        Expanded(child: Text('Anträge Befreiung/Ermäßigung (${_antraege.length})', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo.shade700))),
        ElevatedButton.icon(
          onPressed: () => _showAntragDialog(),
          icon: const Icon(Icons.add, size: 16), label: const Text('Neuer Antrag', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
        ),
      ])),
      Expanded(child: _antraege.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.description, size: 48, color: Colors.grey.shade300), const SizedBox(height: 8),
              Text('Keine Anträge', style: TextStyle(color: Colors.grey.shade500)),
              const SizedBox(height: 4),
              Text('Antrag auf Befreiung oder Ermäßigung stellen', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
            ]))
          : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: _antraege.length, itemBuilder: (_, i) {
              final a = _antraege[i];
              final status = a['status']?.toString() ?? '';
              final isBefreit = status == 'bewilligt';
              final isAbgelehnt = status == 'abgelehnt';
              final grund = _befreiungsgruende.where((g) => g.key == a['befreiungsgrund']?.toString()).firstOrNull;
              return Card(
                child: ListTile(
                  leading: Icon(
                    isBefreit ? Icons.check_circle : isAbgelehnt ? Icons.cancel : Icons.hourglass_top,
                    color: isBefreit ? Colors.green : isAbgelehnt ? Colors.red : Colors.orange,
                    size: 28,
                  ),
                  title: Text(grund?.label ?? a['befreiungsgrund']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${a['antrag_datum'] ?? ''} • ${_statusLabel(status)}', style: TextStyle(fontSize: 11, color: isBefreit ? Colors.green.shade700 : isAbgelehnt ? Colors.red.shade700 : Colors.orange.shade700)),
                    if ((a['zeitraum_von']?.toString() ?? '').isNotEmpty)
                      Text('Zeitraum: ${a['zeitraum_von']} – ${a['zeitraum_bis'] ?? ''}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                    if ((a['aktenzeichen']?.toString() ?? '').isNotEmpty)
                      Text('Az.: ${a['aktenzeichen']}', style: TextStyle(fontSize: 10, color: Colors.indigo.shade600, fontWeight: FontWeight.w600)),
                  ]),
                  isThreeLine: true,
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(icon: Icon(Icons.edit, size: 18, color: Colors.indigo.shade400), tooltip: 'Bearbeiten', onPressed: () => _showAntragDialog(existing: a)),
                    IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400), tooltip: 'Löschen', onPressed: () async {
                      final id = int.tryParse(a['id']?.toString() ?? '');
                      if (id != null) await widget.apiService!.deleteRundfunkbeitragAntrag(id);
                      _loadFromDB();
                    }),
                  ]),
                ),
              );
            })),
    ]);
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'eingereicht': return 'Eingereicht';
      case 'in_bearbeitung': return 'In Bearbeitung';
      case 'bewilligt': return 'Bewilligt';
      case 'abgelehnt': return 'Abgelehnt';
      case 'widerspruch': return 'Widerspruch';
      default: return s;
    }
  }

  void _showAntragDialog({Map<String, dynamic>? existing}) {
    final isEdit = existing != null;
    String befreiungsgrund = existing?['befreiungsgrund']?.toString() ?? '';
    String status = existing?['status']?.toString() ?? 'eingereicht';
    final datumC = TextEditingController(text: existing?['antrag_datum']?.toString() ?? '');
    final aktenzeichenC = TextEditingController(text: existing?['aktenzeichen']?.toString() ?? '');
    final zeitraumVonC = TextEditingController(text: existing?['zeitraum_von']?.toString() ?? '');
    final zeitraumBisC = TextEditingController(text: existing?['zeitraum_bis']?.toString() ?? '');
    final notizC = TextEditingController(text: existing?['notiz']?.toString() ?? '');

    Future<void> pickDate(BuildContext ctx, TextEditingController c) async {
      final p = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
      if (p != null) c.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}';
    }

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(isEdit ? 'Antrag bearbeiten' : 'Neuer Antrag auf Befreiung/Ermäßigung'),
      content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Befreiungsgrund *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        ..._befreiungsgruende.map((g) => RadioListTile<String>(
          value: g.key, groupValue: befreiungsgrund, dense: true, contentPadding: EdgeInsets.zero,
          title: Row(children: [
            Icon(g.icon, size: 16, color: g.key.startsWith('ermaessigung') ? Colors.orange.shade700 : Colors.indigo.shade600), const SizedBox(width: 8),
            Expanded(child: Text(g.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
          ]),
          subtitle: Text(g.beschreibung, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          onChanged: (v) => setD(() => befreiungsgrund = v ?? ''),
        )),
        const SizedBox(height: 8),
        TextField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Antragsdatum *', prefixIcon: const Icon(Icons.calendar_today, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onTap: () async { await pickDate(ctx2, datumC); setD(() {}); }),
        const SizedBox(height: 8),
        TextField(controller: aktenzeichenC, decoration: InputDecoration(labelText: 'Aktenzeichen', prefixIcon: const Icon(Icons.numbers, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 8),
        Text('Bewilligungszeitraum', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: TextField(controller: zeitraumVonC, readOnly: true, decoration: InputDecoration(labelText: 'Von', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onTap: () async { await pickDate(ctx2, zeitraumVonC); setD(() {}); })),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: zeitraumBisC, readOnly: true, decoration: InputDecoration(labelText: 'Bis', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onTap: () async { await pickDate(ctx2, zeitraumBisC); setD(() {}); })),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, children: ['eingereicht', 'in_bearbeitung', 'bewilligt', 'abgelehnt', 'widerspruch'].map((s) => ChoiceChip(
          label: Text(_statusLabel(s), style: TextStyle(fontSize: 11, color: status == s ? Colors.white : Colors.black87)),
          selected: status == s, selectedColor: s == 'bewilligt' ? Colors.green : s == 'abgelehnt' ? Colors.red : Colors.indigo,
          onSelected: (_) => setD(() => status = s),
        )).toList()),
        const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notizen', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 8),
        // Benötigte Unterlagen hint
        if (befreiungsgrund.isNotEmpty)
          Container(
            width: double.infinity, padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade200)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Benötigte Unterlagen:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber.shade800)),
              const SizedBox(height: 4),
              Text(_getRequiredDocs(befreiungsgrund), style: TextStyle(fontSize: 10, color: Colors.amber.shade900)),
            ]),
          ),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          if (befreiungsgrund.isEmpty || datumC.text.isEmpty) {
            ScaffoldMessenger.of(ctx2).showSnackBar(const SnackBar(content: Text('Bitte Befreiungsgrund und Datum ausfüllen'), backgroundColor: Colors.red));
            return;
          }
          if (widget.apiService != null && widget.userId != null) {
            final res = await widget.apiService!.saveRundfunkbeitragAntrag(widget.userId!, {
              if (isEdit) 'id': existing['id'],
              'befreiungsgrund': befreiungsgrund, 'antrag_datum': datumC.text, 'aktenzeichen': aktenzeichenC.text.trim(),
              'zeitraum_von': zeitraumVonC.text, 'zeitraum_bis': zeitraumBisC.text,
              'status': status, 'notiz': notizC.text.trim(),
            });
            if (res['success'] != true && ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Fehler: ${res['message'] ?? 'Speichern fehlgeschlagen'}'), backgroundColor: Colors.red));
              return;
            }
          }
          if (ctx.mounted) Navigator.pop(ctx);
          _loadFromDB();
        }, child: Text(isEdit ? 'Speichern' : 'Hinzufügen')),
      ],
    )));
  }

  String _getRequiredDocs(String grund) {
    switch (grund) {
      case 'buergergeld': return '• Aktueller Bürgergeld-Bescheid (beglaubigte Kopie)\n• Personalausweis';
      case 'grundsicherung_alter': return '• Grundsicherungsbescheid (beglaubigte Kopie)\n• Personalausweis';
      case 'hilfe_lebensunterhalt': return '• Bescheid über Hilfe zum Lebensunterhalt\n• Personalausweis';
      case 'asylbewerber': return '• Bescheid nach AsylbLG (beglaubigte Kopie)\n• Aufenthaltsgestattung';
      case 'bafoeg': return '• BAföG-Bescheid (beglaubigte Kopie)\n• Immatrikulationsbescheinigung\n• Meldebescheinigung (nicht bei Eltern wohnend)';
      case 'bab': return '• BAB-Bescheid der Agentur für Arbeit\n• Personalausweis';
      case 'ausbildungsgeld': return '• Bescheid über Ausbildungsgeld\n• Personalausweis';
      case 'pflegegeld': return '• Bescheid über Hilfe zur Pflege (SGB XII)\n• Personalausweis';
      case 'haertefall': return '• Ablehnungsbescheid des Sozialleistungsträgers\n• Einkommensnachweise\n• Nachweis: Einkommen übersteigt Bedarf um weniger als 18,36 €';
      case 'ermaessigung_rf': return '• Schwerbehindertenausweis mit Merkzeichen RF (beglaubigte Kopie)\n• Personalausweis';
      case 'ermaessigung_blind': return '• Nachweis der Blindheit/Gehörlosigkeit\n• Ärztliches Attest oder Schwerbehindertenausweis\n• Personalausweis';
      default: return '• Entsprechender Leistungsbescheid (beglaubigte Kopie)\n• Personalausweis';
    }
  }

  // ============ TAB 3: KORRESPONDENZ ============

  Widget _buildKorrespondenzTab() {
    final list = _korrespondenz;
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Expanded(child: Text('${list.length} Einträge', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
        FilledButton.icon(icon: const Icon(Icons.call_received, size: 14), label: const Text('Eingang', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.green.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _showKorrDialog('eingang')),
        const SizedBox(width: 6),
        FilledButton.icon(icon: const Icon(Icons.call_made, size: 14), label: const Text('Ausgang', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _showKorrDialog('ausgang')),
      ])),
      Expanded(child: list.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.mail_outline, size: 48, color: Colors.grey.shade300), const SizedBox(height: 6), Text('Keine Korrespondenz', style: TextStyle(fontSize: 12, color: Colors.grey.shade500))]))
          : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: list.length, itemBuilder: (_, i) {
              final k = list[i]; final isEin = k['richtung'] == 'eingang';
              return Container(
                margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: isEin ? Colors.green.shade200 : Colors.blue.shade200)),
                child: Row(children: [
                  Icon(isEin ? Icons.call_received : Icons.call_made, size: 18, color: isEin ? Colors.green.shade700 : Colors.blue.shade700), const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(k['betreff']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isEin ? Colors.green.shade800 : Colors.blue.shade800)),
                    Text(k['datum']?.toString() ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                    if ((k['notiz']?.toString() ?? '').isNotEmpty) Text(k['notiz'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                  ])),
                  IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), onPressed: () async {
                    final kid = int.tryParse(k['id']?.toString() ?? '');
                    if (kid != null && widget.apiService != null) await widget.apiService!.deleteRundfunkbeitragKorrespondenz(kid);
                    _loadFromDB();
                  }, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28)),
                ]),
              );
            })),
    ]);
  }

  void _showKorrDialog(String richtung) {
    final betreffC = TextEditingController();
    final datumC = TextEditingController(text: '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}');
    final notizC = TextEditingController();
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
            await widget.apiService!.saveRundfunkbeitragKorrespondenz(widget.userId!, {'richtung': richtung, 'datum': datumC.text.trim(), 'betreff': betreffC.text.trim(), 'notiz': notizC.text.trim()});
          }
          if (ctx.mounted) Navigator.pop(ctx);
          _loadFromDB();
        }, child: const Text('Speichern')),
      ],
    ));
  }

  // ============ HELPERS ============

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Icon(icon, size: 14, color: Colors.indigo.shade400), const SizedBox(width: 6),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: Colors.indigo.shade700))),
      ]),
    );
  }

  Widget _readOnlyRow(IconData icon, String label, dynamic value) {
    final s = value?.toString() ?? '';
    if (s.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 14, color: Colors.grey.shade600), const SizedBox(width: 8),
        SizedBox(width: 120, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600))),
        Expanded(child: Text(s, style: const TextStyle(fontSize: 13))),
      ]),
    );
  }

  Widget _field(Map<String, dynamic> map, String key, String label, IconData icon, {String hint = '', int maxLines = 1}) {
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: TextField(
      controller: TextEditingController(text: map[key]?.toString() ?? ''), maxLines: maxLines, onChanged: (v) => map[key] = v,
      decoration: InputDecoration(labelText: label, hintText: hint, prefixIcon: Icon(icon, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
      style: const TextStyle(fontSize: 13),
    ));
  }

  Widget _dropdownField(Map<String, dynamic> map, String key, String label, IconData icon, List<String> options) {
    final current = map[key]?.toString() ?? '';
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: DropdownButtonFormField<String>(
      value: options.contains(current) ? current : null,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
      items: options.map((o) => DropdownMenuItem(value: o, child: Text(o, style: const TextStyle(fontSize: 13)))).toList(),
      onChanged: (v) => setState(() => map[key] = v ?? ''),
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
