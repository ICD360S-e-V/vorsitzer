import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../models/user.dart';
import '../screens/webview_screen.dart';
import 'korrespondenz_attachments_widget.dart';
import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';
import 'file_viewer_dialog.dart';

class BehordeRundfunkbeitragContent extends StatefulWidget {
  final ApiService? apiService;
  final int? userId;
  final User? user;
  final Map<String, dynamic> Function(String type) getData;
  final bool Function(String type) isLoading;
  final bool Function(String type) isSaving;
  final void Function(String type) loadData;
  final void Function(String type, Map<String, dynamic> data) saveData;

  const BehordeRundfunkbeitragContent({
    super.key,
    this.apiService,
    this.userId,
    this.user,
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
  Timer? _autoSaveTimer;

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

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    for (final c in _bnrControllers) { c.dispose(); }
    for (final f in _bnrFocusNodes) { f.dispose(); }
    super.dispose();
  }

  Future<void> _save() async {
    if (widget.apiService == null || widget.userId == null) return;
    _b('beitrag')['beitragsnummer'] = _getBeitragsnummer();
    setState(() => _saving = true);
    await widget.apiService!.saveRundfunkbeitragData(widget.userId!, _dbData);
    if (mounted) setState(() => _saving = false);
  }

  void _autoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 800), () => _save());
  }

  Map<String, dynamic> _b(String key) {
    _dbData[key] ??= {};
    return _dbData[key]!;
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());

    return DefaultTabController(
      length: 4,
      child: Column(children: [
        TabBar(
          labelColor: Colors.indigo.shade700,
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: Colors.indigo.shade700,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.account_balance, size: 16), text: 'Zuständige Behörde'),
            Tab(icon: Icon(Icons.euro, size: 16), text: 'Beitrag'),
            Tab(icon: Icon(Icons.description, size: 16), text: 'Anträge'),
            Tab(icon: Icon(Icons.mail, size: 16), text: 'Korrespondenz'),
          ],
        ),
        Expanded(child: TabBarView(children: [
          _buildBehoerdeTab(),
          _buildBeitragTab(),
          _buildAntraegeTab(),
          _buildKorrespondenzTab(),
        ])),
      ]),
    );
  }

  // ============ TAB 1: ZUSTÄNDIGE BEHÖRDE (nur Info) ============

  Widget _buildBehoerdeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: double.infinity, padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.indigo.shade200)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.radio, size: 22, color: Colors.indigo.shade700), const SizedBox(width: 10),
              Expanded(child: Text('ARD ZDF Deutschlandradio', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.indigo.shade800))),
            ]),
            const SizedBox(height: 12),
            _infoRow(Icons.business, 'Beitragsservice von ARD, ZDF und Deutschlandradio'),
            _infoRow(Icons.location_on, '50656 Köln'),
            _infoRow(Icons.phone, '01806 999 555 10 (20 Ct/Anruf)'),
            _infoRow(Icons.fax, 'Fax: 01806 999 555 01'),
            _infoRow(Icons.language, 'www.rundfunkbeitrag.de'),
            _infoRow(Icons.email, 'info@rundfunkbeitrag.de'),
          ]),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity, padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.shade200)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Rundfunkbeitrag', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
            const SizedBox(height: 8),
            _infoRow(Icons.euro, '18,36 €/Monat (seit 2021)'),
            _infoRow(Icons.calendar_month, '55,08 € vierteljährlich'),
            _infoRow(Icons.date_range, '110,16 € halbjährlich'),
            _infoRow(Icons.event, '220,32 € jährlich'),
            const SizedBox(height: 8),
            Text('Ermäßigung bei RF-Merkzeichen: 6,12 €/Monat', style: TextStyle(fontSize: 11, color: Colors.orange.shade700, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity, padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.amber.shade200)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.info, size: 18, color: Colors.amber.shade700), const SizedBox(width: 8),
              Text('Hinweise', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.amber.shade800)),
            ]),
            const SizedBox(height: 6),
            Text('• Pro Wohnung wird nur ein Beitrag fällig', style: TextStyle(fontSize: 11, color: Colors.amber.shade900)),
            Text('• Befreiung muss aktiv beantragt werden', style: TextStyle(fontSize: 11, color: Colors.amber.shade900)),
            Text('• Befreiung kann bis zu 3 Jahre rückwirkend beantragt werden', style: TextStyle(fontSize: 11, color: Colors.amber.shade900)),
            Text('• Antrag per Post an: Beitragsservice, 50656 Köln', style: TextStyle(fontSize: 11, color: Colors.amber.shade900)),
          ]),
        ),
      ]),
    );
  }

  // ============ TAB 2: BEITRAG ============

  // Beitragsnummer 3x3 controllers
  final List<TextEditingController> _bnrControllers = List.generate(3, (_) => TextEditingController());
  final List<FocusNode> _bnrFocusNodes = List.generate(3, (_) => FocusNode());

  String _getBeitragsnummer() => _bnrControllers.map((c) => c.text.trim()).join('');

  void _initBnrFromData(String? bnr) {
    final s = bnr?.replaceAll(' ', '') ?? '';
    for (int i = 0; i < 3; i++) {
      final start = i * 3;
      _bnrControllers[i].text = start < s.length ? s.substring(start, (start + 3).clamp(0, s.length)) : '';
    }
  }

  Widget _buildBeitragTab() {
    final d = _b('beitrag');
    final bnr = d['beitragsnummer']?.toString() ?? '';
    final hasData = bnr.isNotEmpty;
    final readOnly = hasData && !_behoerdeEditing;
    final status = d['status']?.toString() ?? '';
    final isBefreit = status == 'Befreit';
    final zahlungsart = d['zahlungsart']?.toString() ?? '';
    final isSepa = zahlungsart == 'SEPA-Lastschrift';
    final interval = d['zahlungsintervall']?.toString() ?? '';

    // Init BNR boxes
    if (bnr.isNotEmpty && _bnrControllers[0].text.isEmpty) _initBnrFromData(bnr);

    // SEPA-Daten aus Finanzen/Deutschlandticket übernehmen
    final dtData = widget.getData('deutschlandticket');
    final sepaIban = dtData['sepa_iban']?.toString() ?? '';
    final sepaKontoinhaber = dtData['sepa_kontoinhaber']?.toString() ?? '';

    // Betrag berechnen
    String betrag = '';
    switch (interval) {
      case 'monatlich': betrag = '18,36 €';
      case 'vierteljährlich': betrag = '55,08 €';
      case 'halbjährlich': betrag = '110,16 €';
      case 'jährlich': betrag = '220,32 €';
    }

    // Format BNR for display: 123 456 789
    String fmtBnr(String s) {
      final clean = s.replaceAll(' ', '');
      if (clean.length <= 3) return clean;
      if (clean.length <= 6) return '${clean.substring(0, 3)} ${clean.substring(3)}';
      return '${clean.substring(0, 3)} ${clean.substring(3, 6)} ${clean.substring(6)}';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.euro, size: 20, color: Colors.indigo.shade700), const SizedBox(width: 8),
          Expanded(child: Text('Beitragsdaten', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo.shade700))),
          if (hasData)
            IconButton(
              icon: Icon(_behoerdeEditing ? Icons.check : Icons.edit, size: 20, color: Colors.indigo.shade700),
              tooltip: _behoerdeEditing ? 'Fertig' : 'Bearbeiten',
              onPressed: () {
                if (_behoerdeEditing) {
                  d['beitragsnummer'] = _getBeitragsnummer();
                  _save();
                }
                setState(() => _behoerdeEditing = !_behoerdeEditing);
              },
            ),
        ]),
        const SizedBox(height: 12),
        if (readOnly) ...[
          _readOnlyRow(Icons.numbers, 'Beitragsnummer', fmtBnr(bnr)),
          _readOnlyRow(Icons.check_circle, 'Status', d['status']),
          if (!isBefreit) ...[
            _readOnlyRow(Icons.payments, 'Zahlungsart', d['zahlungsart']),
            _readOnlyRow(Icons.calendar_month, 'Intervall', d['zahlungsintervall']),
            if (betrag.isNotEmpty) _readOnlyRow(Icons.euro, 'Betrag', betrag),
            if (isSepa) ...[
              _readOnlyRow(Icons.account_balance, 'IBAN', d['iban']),
              _readOnlyRow(Icons.person, 'Kontoinhaber', d['kontoinhaber']),
            ],
          ],
          _readOnlyRow(Icons.calendar_today, 'Angemeldet seit', d['angemeldet_seit']),
          _readOnlyRow(Icons.note, 'Notizen', d['notizen']),
        ] else ...[
          // Beitragsnummer 3x3 boxes
          Text('Beitragsnummer', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          Row(children: [
            for (int i = 0; i < 3; i++) ...[
              if (i > 0) Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(' – ', style: TextStyle(fontSize: 16, color: Colors.grey.shade400))),
              SizedBox(width: 80, child: TextField(
                controller: _bnrControllers[i], focusNode: _bnrFocusNodes[i],
                textAlign: TextAlign.center, maxLength: 3,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 4),
                decoration: InputDecoration(counterText: '', hintText: '000', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(vertical: 12)),
                onChanged: (v) {
                  if (v.length == 3 && i < 2) _bnrFocusNodes[i + 1].requestFocus();
                  d['beitragsnummer'] = _getBeitragsnummer();
                  _autoSave();
                },
              )),
            ],
          ]),
          const SizedBox(height: 12),
          _dropdownFieldAuto(d, 'status', 'Status', Icons.check_circle, ['Aktiv', 'Befreit', 'Ermäßigt', 'Abgemeldet', 'Rückstand']),
          if (!isBefreit) ...[
            const SizedBox(height: 4),
            Text('Zahlungsart', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
            const SizedBox(height: 4),
            Wrap(spacing: 8, children: ['SEPA-Lastschrift', 'Überweisung'].map((z) => ChoiceChip(
              label: Text(z, style: TextStyle(fontSize: 12, color: zahlungsart == z ? Colors.white : Colors.black87)),
              selected: zahlungsart == z, selectedColor: Colors.indigo,
              onSelected: (_) { setState(() => d['zahlungsart'] = z); _autoSave(); },
            )).toList()),
            const SizedBox(height: 12),
            Text('Zahlungsintervall', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
            const SizedBox(height: 4),
            Wrap(spacing: 8, children: [
              ('monatlich', '18,36 €'), ('vierteljährlich', '55,08 €'), ('halbjährlich', '110,16 €'), ('jährlich', '220,32 €'),
            ].map((z) => ChoiceChip(
              label: Text('${z.$1}\n${z.$2}', style: TextStyle(fontSize: 11, color: interval == z.$1 ? Colors.white : Colors.black87), textAlign: TextAlign.center),
              selected: interval == z.$1, selectedColor: Colors.green,
              onSelected: (_) { setState(() => d['zahlungsintervall'] = z.$1); _autoSave(); },
            )).toList()),
            const SizedBox(height: 12),
            if (isSepa) ...[
              Text('SEPA-Lastschrift', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              if (sepaIban.isNotEmpty && (d['iban']?.toString() ?? '').isEmpty)
                Container(
                  width: double.infinity, margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
                  child: Row(children: [
                    Icon(Icons.sync, size: 16, color: Colors.blue.shade700), const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('SEPA-Daten aus Finanzen übernehmen?', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                      Text('IBAN: $sepaIban${sepaKontoinhaber.isNotEmpty ? ' • $sepaKontoinhaber' : ''}', style: TextStyle(fontSize: 10, color: Colors.blue.shade700)),
                    ])),
                    TextButton(
                      onPressed: () { setState(() {
                        d['iban'] = sepaIban;
                        if (sepaKontoinhaber.isNotEmpty) d['kontoinhaber'] = sepaKontoinhaber;
                      }); _autoSave(); },
                      child: const Text('Übernehmen', style: TextStyle(fontSize: 11)),
                    ),
                  ]),
                ),
              _fieldAuto(d, 'iban', 'IBAN', Icons.account_balance),
              _fieldAuto(d, 'kontoinhaber', 'Kontoinhaber', Icons.person),
            ],
          ],
          _fieldAuto(d, 'angemeldet_seit', 'Angemeldet seit', Icons.calendar_today, hint: 'YYYY-MM-DD'),
          _fieldAuto(d, 'notizen', 'Notizen', Icons.note, maxLines: 3),
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
        Expanded(child: Text('Anträge (${_antraege.length})', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo.shade700))),
        if (_antraege.isNotEmpty)
          ElevatedButton.icon(
            onPressed: () {
              if (_antraege.length == 1) {
                _openAntragOnline(_antraege.first);
              } else {
                showDialog(context: context, builder: (ctx) => SimpleDialog(
                  title: const Text('Welchen Antrag online einreichen?'),
                  children: _antraege.map((a) {
                    final grund = _befreiungsgruende.where((g) => g.key == a['befreiungsgrund']?.toString()).firstOrNull;
                    return SimpleDialogOption(
                      onPressed: () { Navigator.pop(ctx); _openAntragOnline(a); },
                      child: Text(grund?.label ?? a['befreiungsgrund']?.toString() ?? '', style: const TextStyle(fontSize: 13)),
                    );
                  }).toList(),
                ));
              }
            },
            icon: const Icon(Icons.language, size: 16), label: const Text('Antrag Online', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
          ),
        const SizedBox(width: 6),
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
              final status = a['status']?.toString() ?? 'eingereicht';
              final isBefreit = status == 'bewilligt';
              final isAbgelehnt = status == 'abgelehnt';
              final grund = _befreiungsgruende.where((g) => g.key == a['befreiungsgrund']?.toString()).firstOrNull;
              final methodeLabel = {'online': 'Online', 'email': 'E-Mail', 'persoenlich': 'Persönlich', 'postalisch': 'Postalisch'}[a['methode']?.toString() ?? ''] ?? '';
              return Card(child: ListTile(
                leading: Icon(
                  isBefreit ? Icons.check_circle : isAbgelehnt ? Icons.cancel : Icons.hourglass_top,
                  color: isBefreit ? Colors.green : isAbgelehnt ? Colors.red : Colors.orange, size: 28,
                ),
                title: Text(grund?.label ?? a['befreiungsgrund']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text('${a['antrag_datum'] ?? ''} • ${_statusLabel(status)}${methodeLabel.isNotEmpty ? ' • $methodeLabel' : ''}', style: TextStyle(fontSize: 11, color: isBefreit ? Colors.green.shade700 : isAbgelehnt ? Colors.red.shade700 : Colors.orange.shade700)),
                onTap: () => _showAntragDetailDialog(a),
                trailing: PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: Colors.grey.shade600),
                  onSelected: (action) {
                    if (action == 'edit') { _showAntragDetailDialog(a); }
                    else if (action == 'status') { _quickStatusChange(a); }
                    else if (action == 'delete') { _deleteAntrag(a); }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Bearbeiten')])),
                    const PopupMenuItem(value: 'status', child: Row(children: [Icon(Icons.flag, size: 18), SizedBox(width: 8), Text('Status ändern')])),
                    PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.red.shade400), const SizedBox(width: 8), Text('Löschen', style: TextStyle(color: Colors.red.shade400))])),
                  ],
                ),
              ));
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

  String _befreiungText(String grundKey) {
    switch (grundKey) {
      case 'buergergeld': return 'als Empfänger/in von Bürgergeld nach dem SGB II';
      case 'grundsicherung_alter': return 'als Empfänger/in von Grundsicherung im Alter und bei Erwerbsminderung nach dem SGB XII';
      case 'hilfe_lebensunterhalt': return 'als Empfänger/in von Hilfe zum Lebensunterhalt nach dem SGB XII';
      case 'asylbewerber': return 'als Empfänger/in von Leistungen nach dem Asylbewerberleistungsgesetz';
      case 'bafoeg': return 'als BAföG-Empfänger/in (nicht bei den Eltern wohnend)';
      case 'bab': return 'als Empfänger/in von Berufsausbildungsbeihilfe (BAB)';
      case 'ausbildungsgeld': return 'als Empfänger/in von Ausbildungsgeld nach dem SGB III';
      case 'pflegegeld': return 'als Empfänger/in von Hilfe zur Pflege nach dem SGB XII';
      case 'haertefall': return 'aufgrund eines besonderen Härtefalls gemäß § 4 Abs. 6 RBStV (Einkommen übersteigt den sozialhilferechtlichen Bedarf um weniger als 18,36 €)';
      case 'ermaessigung_rf': return 'auf Ermäßigung des Rundfunkbeitrags aufgrund des Merkzeichens RF in meinem Schwerbehindertenausweis';
      case 'ermaessigung_blind': return 'auf Ermäßigung des Rundfunkbeitrags aufgrund von Blindheit/Gehörlosigkeit';
      default: return 'als Empfänger/in von Sozialleistungen';
    }
  }

  void _quickStatusChange(Map<String, dynamic> a) {
    final aid = int.tryParse(a['id']?.toString() ?? '');
    if (aid == null) return;
    String status = a['status']?.toString() ?? 'eingereicht';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (_, setD) => AlertDialog(
      title: const Text('Status ändern'),
      content: Wrap(spacing: 6, runSpacing: 6, children: ['eingereicht', 'in_bearbeitung', 'bewilligt', 'abgelehnt', 'widerspruch'].map((s) => ChoiceChip(
        label: Text(_statusLabel(s), style: TextStyle(fontSize: 11, color: status == s ? Colors.white : Colors.black87)),
        selected: status == s, selectedColor: s == 'bewilligt' ? Colors.green : s == 'abgelehnt' ? Colors.red : Colors.indigo,
        onSelected: (_) => setD(() => status = s),
      )).toList()),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          await widget.apiService!.saveRundfunkbeitragAntrag(widget.userId!, {'id': aid, 'status': status});
          await widget.apiService!.addRfbAntragVerlauf(aid, {'datum': '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}', 'status': status, 'notiz': 'Status geändert auf ${_statusLabel(status)}'});
          if (ctx.mounted) Navigator.pop(ctx);
          _loadFromDB();
        }, child: const Text('Speichern')),
      ],
    )));
  }

  void _deleteAntrag(Map<String, dynamic> a) async {
    final aid = int.tryParse(a['id']?.toString() ?? '');
    if (aid == null) return;
    final confirm = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Antrag löschen?'), content: const Text('Alle zugehörigen Dokumente und Verlaufseinträge werden gelöscht.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
        TextButton(onPressed: () => Navigator.pop(c, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Löschen'))],
    ));
    if (confirm != true) return;
    await widget.apiService!.deleteRundfunkbeitragAntrag(aid);
    _loadFromDB();
  }

  void _openAntragOnline(Map<String, dynamic> antrag) {
    final u = widget.user;
    final beitragsnr = _b('beitrag')['beitragsnummer']?.toString() ?? '';
    final grundKey = antrag['befreiungsgrund']?.toString() ?? '';
    final grundText = _befreiungText(grundKey);
    final isErmaessigung = grundKey.startsWith('ermaessigung');
    final befreiungOderErmaessigung = isErmaessigung ? 'Ermäßigung' : 'Befreiung';
    final anrede = (u?.geschlecht ?? '').toLowerCase();
    // Map geschlecht to form value
    String anredeVal = 'keine Angabe';
    if (anrede == 'männlich' || anrede == 'm' || anrede == 'herr') anredeVal = 'Herr';
    if (anrede == 'weiblich' || anrede == 'w' || anrede == 'frau') anredeVal = 'Frau';

    final vorname = (u?.vorname ?? '').replaceAll("'", "\\'");
    final nachname = (u?.nachname ?? '').replaceAll("'", "\\'");
    final plz = (u?.plz ?? '').replaceAll("'", "\\'");
    final ort = (u?.ort ?? '').replaceAll("'", "\\'");
    final strasse = (u?.strasse ?? '').replaceAll("'", "\\'");
    final hausnr = (u?.hausnummer ?? '').replaceAll("'", "\\'");
    final email = u?.email.replaceAll("'", "\\'") ?? '';
    final telefon = (u?.telefonMobil ?? u?.telefonFix ?? '').replaceAll("'", "\\'");
    // Split telefon into Vorwahl + Nummer
    String vorwahl = '';
    String telNummer = telefon;
    if (telefon.startsWith('0') && telefon.length > 4) {
      vorwahl = telefon.substring(0, 4);
      telNummer = telefon.substring(4).trim();
    }

    final js = '''
(function() {
  var attempts = 0;
  function tryFill() {
    attempts++;
    if (attempts > 15) return;

    function setVal(el, val) {
      if (!el || !val) return false;
      var setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value');
      if (setter && setter.set) setter.set.call(el, val);
      else el.value = val;
      el.dispatchEvent(new Event('input', {bubbles: true}));
      el.dispatchEvent(new Event('change', {bubbles: true}));
      el.dispatchEvent(new Event('blur', {bubbles: true}));
      return true;
    }
    function setTextarea(el, val) {
      if (!el || !val) return false;
      var setter = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value');
      if (setter && setter.set) setter.set.call(el, val);
      else el.value = val;
      el.dispatchEvent(new Event('input', {bubbles: true}));
      el.dispatchEvent(new Event('change', {bubbles: true}));
      return true;
    }
    function clickRadio(name, val) {
      var radios = document.querySelectorAll('input[type="radio"]');
      for (var r of radios) {
        var lbl = r.parentElement ? r.parentElement.textContent.trim() : '';
        if (lbl.indexOf(val) >= 0 || (r.value && r.value.indexOf(val) >= 0)) {
          r.checked = true;
          r.dispatchEvent(new Event('change', {bubbles: true}));
          r.dispatchEvent(new Event('click', {bubbles: true}));
          return true;
        }
      }
      return false;
    }

    var inputs = document.querySelectorAll('input, select, textarea');
    if (inputs.length < 3) { setTimeout(tryFill, 1000); return; }

    var filled = 0;
    // Anrede radio
    clickRadio('anrede', '$anredeVal');

    for (var el of inputs) {
      var nm = (el.name || '').toLowerCase();
      var id = (el.id || '').toLowerCase();
      var ph = (el.placeholder || '').toLowerCase();
      var lbl = '';
      if (el.id) { var l = document.querySelector('label[for="' + el.id + '"]'); if (l) lbl = l.textContent.toLowerCase().trim(); }
      // Also check aria-label and nearby labels
      var ariaLabel = (el.getAttribute('aria-label') || '').toLowerCase();
      var combined = nm + ' ' + id + ' ' + ph + ' ' + lbl + ' ' + ariaLabel;

      if (el.tagName === 'TEXTAREA' && (combined.indexOf('nachricht') >= 0 || combined.indexOf('message') >= 0 || combined.indexOf('mitteilung') >= 0 || nm === 'message' || nm === 'nachricht' || (el.rows && el.rows > 2))) {
        var msg = 'Sehr geehrte Damen und Herren,\\n\\nhiermit beantrage ich die $befreiungOderErmaessigung von der Rundfunkbeitragspflicht gemäß § 4 Abs. 1 RBStV $grundText.\\n\\nMeine Beitragsnummer: $beitragsnr\\n\\nDen entsprechenden Bewilligungsbescheid bzw. Nachweis füge ich diesem Schreiben als Anlage bei.\\n\\nIch bitte um schriftliche Bestätigung der $befreiungOderErmaessigung.\\n\\nMit freundlichen Grüßen\\n$vorname $nachname';
        setTextarea(el, msg);
        filled++;
        continue;
      }
      if (el.tagName === 'TEXTAREA') continue;

      if (combined.indexOf('vorname') >= 0 && combined.indexOf('nachname') < 0) {
        if (setVal(el, '$vorname')) filled++;
      } else if (combined.indexOf('nachname') >= 0 || combined.indexOf('familienname') >= 0) {
        if (setVal(el, '$nachname')) filled++;
      } else if (combined.indexOf('plz') >= 0 || combined.indexOf('postleitzahl') >= 0) {
        if (setVal(el, '$plz')) filled++;
      } else if (combined.indexOf('ort') >= 0 && combined.indexOf('geburt') < 0 && combined.indexOf('sort') < 0) {
        if (setVal(el, '$ort')) filled++;
      } else if (combined.indexOf('straße') >= 0 || combined.indexOf('strasse') >= 0 || combined.indexOf('str.') >= 0) {
        if (setVal(el, '$strasse')) filled++;
      } else if (combined.indexOf('hausnummer') >= 0 || combined.indexOf('hausnr') >= 0 || combined.indexOf('hnr') >= 0) {
        if (setVal(el, '$hausnr')) filled++;
      } else if (combined.indexOf('beitragsnummer') >= 0) {
        if (setVal(el, '$beitragsnr')) filled++;
      } else if (combined.indexOf('e-mail') >= 0 || combined.indexOf('email') >= 0 || el.type === 'email') {
        if (setVal(el, '$email')) filled++;
      } else if (combined.indexOf('vorwahl') >= 0) {
        if (setVal(el, '$vorwahl')) filled++;
      } else if (combined.indexOf('telefon') >= 0 && combined.indexOf('vorwahl') < 0) {
        if (setVal(el, '$telNummer')) filled++;
      }
    }

    if (filled < 3) setTimeout(tryFill, 1500);
  }
  setTimeout(tryFill, 2000);
})();
''';

    Navigator.of(context).push(MaterialPageRoute(builder: (_) => WebViewScreen(
      url: 'https://www.rundfunkbeitrag.de/buergerinnen-und-buerger/formulare/kontakt#step_personendaten',
      title: 'Rundfunkbeitrag — Antrag Online',
      customJs: js,
    )));
  }

  void _showAntragDialog() {
    String befreiungsgrund = '';
    String methode = '';
    final datumC = TextEditingController();
    final beitragsnr = _b('beitrag')['beitragsnummer']?.toString() ?? '';

    Future<void> pickDate(BuildContext ctx, TextEditingController c) async {
      final p = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
      if (p != null) c.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}';
    }

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Text('Neuer Antrag auf Befreiung/Ermäßigung'),
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
        Text('Methode *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        Wrap(spacing: 6, children: [('online', 'Online'), ('email', 'E-Mail'), ('persoenlich', 'Persönlich'), ('postalisch', 'Postalisch')].map((m) => ChoiceChip(
          label: Text(m.$2, style: TextStyle(fontSize: 11, color: methode == m.$1 ? Colors.white : Colors.black87)),
          selected: methode == m.$1, selectedColor: Colors.teal,
          onSelected: (_) => setD(() => methode = m.$1),
        )).toList()),
        const SizedBox(height: 8),
        if (befreiungsgrund.isNotEmpty)
          Container(
            width: double.infinity, padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade200)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Benötigte Unterlagen:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber.shade800)),
              const SizedBox(height: 4),
              Text(_getRequiredDocs(befreiungsgrund, methode), style: TextStyle(fontSize: 10, color: Colors.amber.shade900)),
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
              'befreiungsgrund': befreiungsgrund, 'antrag_datum': datumC.text,
              'aktenzeichen': beitragsnr, 'methode': methode, 'status': 'eingereicht',
            });
            if (res['success'] != true && ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Fehler: ${res['message'] ?? 'Speichern fehlgeschlagen'}'), backgroundColor: Colors.red));
              return;
            }
            final newId = res['id'];
            if (newId != null) {
              await widget.apiService!.addRfbAntragVerlauf(newId is int ? newId : int.parse(newId.toString()), {'datum': datumC.text, 'status': 'eingereicht', 'notiz': 'Antrag erstellt (${methode == 'online' ? 'Online' : methode == 'email' ? 'E-Mail' : methode == 'postalisch' ? 'Postalisch' : 'Persönlich'})'});
            }
          }
          if (ctx.mounted) Navigator.pop(ctx);
          _loadFromDB();
        }, child: const Text('Antrag stellen')),
      ],
    )));
  }

  void _showAntragDetailDialog(Map<String, dynamic> antrag) {
    final aid = int.tryParse(antrag['id']?.toString() ?? '');
    if (aid == null || widget.apiService == null) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(width: 600, height: 560, child: _RfbAntragDetailView(
          apiService: widget.apiService!, antragId: aid, antrag: antrag,
          onChanged: () => _loadFromDB(),
          befreiungsgruende: _befreiungsgruende,
          userId: widget.userId!,
        )),
      ),
    );
  }

  String _getRequiredDocs(String grund, String methode) {
    final isOnline = methode == 'online' || methode == 'email';
    String docs;
    switch (grund) {
      case 'buergergeld': docs = '• Aktueller Bürgergeld-Bescheid (Kopie)';
      case 'grundsicherung_alter': docs = '• Grundsicherungsbescheid (Kopie)';
      case 'hilfe_lebensunterhalt': docs = '• Bescheid über Hilfe zum Lebensunterhalt (Kopie)';
      case 'asylbewerber': docs = '• Bescheid nach AsylbLG (Kopie)\n• Aufenthaltsgestattung';
      case 'bafoeg': docs = '• BAföG-Bescheid (Kopie)\n• Immatrikulationsbescheinigung\n• Meldebescheinigung (nicht bei Eltern wohnend)';
      case 'bab': docs = '• BAB-Bescheid der Agentur für Arbeit';
      case 'ausbildungsgeld': docs = '• Bescheid über Ausbildungsgeld';
      case 'pflegegeld': docs = '• Bescheid über Hilfe zur Pflege (SGB XII)';
      case 'haertefall': docs = '• Ablehnungsbescheid des Sozialleistungsträgers\n• Einkommensnachweise\n• Nachweis: Einkommen übersteigt Bedarf um weniger als 18,36 €';
      case 'ermaessigung_rf': docs = '• Schwerbehindertenausweis mit Merkzeichen RF (Kopie)';
      case 'ermaessigung_blind': docs = '• Nachweis der Blindheit/Gehörlosigkeit\n• Ärztliches Attest oder Schwerbehindertenausweis';
      default: docs = '• Entsprechender Leistungsbescheid (Kopie)';
    }
    if (isOnline) {
      docs += '\n\nOnline: Bescheid als Scan/Foto hochladen';
    } else {
      docs += '\n• Personalausweis (beglaubigte Kopie)';
    }
    return docs;
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
                    if (k['id'] != null && widget.apiService != null) Padding(padding: const EdgeInsets.only(top: 4),
                      child: KorrAttachmentsWidget(apiService: widget.apiService!, modul: 'rundfunkbeitrag', korrespondenzId: int.tryParse(k['id'].toString()) ?? 0)),
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

  Widget _fieldAuto(Map<String, dynamic> map, String key, String label, IconData icon, {String hint = '', int maxLines = 1}) {
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: TextField(
      controller: TextEditingController(text: map[key]?.toString() ?? ''), maxLines: maxLines, onChanged: (v) { map[key] = v; _autoSave(); },
      decoration: InputDecoration(labelText: label, hintText: hint, prefixIcon: Icon(icon, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
      style: const TextStyle(fontSize: 13),
    ));
  }

  Widget _dropdownFieldAuto(Map<String, dynamic> map, String key, String label, IconData icon, List<String> options) {
    final current = map[key]?.toString() ?? '';
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: DropdownButtonFormField<String>(
      value: options.contains(current) ? current : null,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
      items: options.map((o) => DropdownMenuItem(value: o, child: Text(o, style: const TextStyle(fontSize: 13)))).toList(),
      onChanged: (v) { setState(() => map[key] = v ?? ''); _autoSave(); },
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

// ═══════════════════════════════════════════════════════
// ANTRAG DETAIL (Details / Verlauf / Unterlagen / Korrespondenz)
// ═══════════════════════════════════════════════════════
class _RfbAntragDetailView extends StatefulWidget {
  final ApiService apiService;
  final int antragId;
  final Map<String, dynamic> antrag;
  final VoidCallback onChanged;
  final List<({String key, String label, IconData icon, String beschreibung})> befreiungsgruende;
  final int userId;
  const _RfbAntragDetailView({required this.apiService, required this.antragId, required this.antrag, required this.onChanged, required this.befreiungsgruende, required this.userId});
  @override
  State<_RfbAntragDetailView> createState() => _RfbAntragDetailViewState();
}

class _RfbAntragDetailViewState extends State<_RfbAntragDetailView> {
  List<Map<String, dynamic>> _verlauf = [];
  List<Map<String, dynamic>> _docs = [];
  List<Map<String, dynamic>> _korr = [];
  bool _loaded = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final vR = await widget.apiService.listRfbAntragVerlauf(widget.antragId);
    final dR = await widget.apiService.listRfbAntragDocs(widget.antragId);
    final kR = await widget.apiService.listRfbAntragKorr(widget.antragId);
    if (!mounted) return;
    setState(() {
      if (vR['success'] == true && vR['data'] is List) _verlauf = (vR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (dR['success'] == true && dR['data'] is List) _docs = (dR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (kR['success'] == true && kR['data'] is List) _korr = (kR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.antrag;
    final status = a['status']?.toString() ?? 'eingereicht';
    final grund = widget.befreiungsgruende.where((g) => g.key == a['befreiungsgrund']?.toString()).firstOrNull;
    final isBefreit = status == 'bewilligt';
    return DefaultTabController(length: 4, child: Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: isBefreit ? Colors.green.shade700 : Colors.indigo.shade700, borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
        child: Row(children: [
          Icon(grund?.icon ?? Icons.description, color: Colors.white, size: 22), const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(grund?.label ?? a['befreiungsgrund']?.toString() ?? '', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            Text('${a['antrag_datum'] ?? ''} • ${{'online': 'Online', 'email': 'E-Mail', 'persoenlich': 'Persönlich', 'postalisch': 'Postalisch'}[a['methode']?.toString() ?? ''] ?? ''}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ])),
          IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
        ]),
      ),
      TabBar(labelColor: Colors.indigo.shade700, indicatorColor: Colors.indigo.shade700, isScrollable: true, tabs: const [
        Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Details'),
        Tab(icon: Icon(Icons.timeline, size: 18), text: 'Verlauf'),
        Tab(icon: Icon(Icons.folder, size: 18), text: 'Unterlagen'),
        Tab(icon: Icon(Icons.mail, size: 18), text: 'Korrespondenz'),
      ]),
      Expanded(child: !_loaded ? const Center(child: CircularProgressIndicator()) : TabBarView(children: [
        _buildDetails(a),
        _buildVerlauf(),
        _buildUnterlagen(),
        _buildKorrespondenz(),
      ])),
    ]));
  }

  Widget _buildDetails(Map<String, dynamic> a) {
    final grund = widget.befreiungsgruende.where((g) => g.key == a['befreiungsgrund']?.toString()).firstOrNull;
    final methodeLabel = {'online': 'Online', 'email': 'E-Mail', 'persoenlich': 'Persönlich', 'postalisch': 'Postalisch'}[a['methode']?.toString() ?? ''] ?? '';
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Spacer(),
        OutlinedButton.icon(icon: const Icon(Icons.edit, size: 16), label: const Text('Bearbeiten', style: TextStyle(fontSize: 12)),
          onPressed: () => _editAntrag(a)),
      ]),
      const SizedBox(height: 8),
      _dRow(Icons.description, 'Befreiungsgrund', grund?.label ?? a['befreiungsgrund']?.toString()),
      if (grund != null) Padding(padding: const EdgeInsets.only(left: 22, bottom: 8), child: Text(grund.beschreibung, style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontStyle: FontStyle.italic))),
      _dRow(Icons.calendar_today, 'Antragsdatum', a['antrag_datum']),
      _dRow(Icons.send, 'Methode', methodeLabel),
      _dRow(Icons.numbers, 'Beitragsnummer', a['aktenzeichen']),
      _dRow(Icons.flag, 'Status', _statusLabel(a['status']?.toString() ?? '')),
      if ((a['zeitraum_von']?.toString() ?? '').isNotEmpty)
        _dRow(Icons.date_range, 'Bewilligungszeitraum', '${a['zeitraum_von']} – ${a['zeitraum_bis'] ?? ''}'),
      if ((a['notiz']?.toString() ?? '').isNotEmpty) ...[
        const SizedBox(height: 8),
        Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.yellow.shade50, borderRadius: BorderRadius.circular(8)),
          child: Text(a['notiz'].toString(), style: const TextStyle(fontSize: 12))),
      ],
    ]));
  }

  void _editAntrag(Map<String, dynamic> a) {
    String befreiungsgrund = a['befreiungsgrund']?.toString() ?? '';
    String methode = a['methode']?.toString() ?? '';
    String status = a['status']?.toString() ?? 'eingereicht';
    final datumC = TextEditingController(text: a['antrag_datum']?.toString() ?? '');
    final aktenzeichenC = TextEditingController(text: a['aktenzeichen']?.toString() ?? '');
    final zeitraumVonC = TextEditingController(text: a['zeitraum_von']?.toString() ?? '');
    final zeitraumBisC = TextEditingController(text: a['zeitraum_bis']?.toString() ?? '');
    final notizC = TextEditingController(text: a['notiz']?.toString() ?? '');

    Future<void> pickDate(BuildContext ctx, TextEditingController c) async {
      final d = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
      if (d != null) c.text = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) => AlertDialog(
      title: const Text('Antrag bearbeiten'),
      content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(value: befreiungsgrund.isEmpty ? null : befreiungsgrund,
          decoration: const InputDecoration(labelText: 'Befreiungsgrund', isDense: true, border: OutlineInputBorder()),
          items: widget.befreiungsgruende.map((g) => DropdownMenuItem(value: g.key, child: Text(g.label, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (v) => setD(() => befreiungsgrund = v ?? '')),
        const SizedBox(height: 10),
        TextField(controller: datumC, readOnly: true, decoration: const InputDecoration(labelText: 'Antragsdatum', isDense: true, prefixIcon: Icon(Icons.calendar_today, size: 18), border: OutlineInputBorder()),
          onTap: () async { await pickDate(ctx2, datumC); setD(() {}); }),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(value: methode.isEmpty ? null : methode,
          decoration: const InputDecoration(labelText: 'Methode', isDense: true, border: OutlineInputBorder()),
          items: const [DropdownMenuItem(value: 'online', child: Text('Online')), DropdownMenuItem(value: 'email', child: Text('E-Mail')), DropdownMenuItem(value: 'persoenlich', child: Text('Persönlich')), DropdownMenuItem(value: 'postalisch', child: Text('Postalisch'))],
          onChanged: (v) => setD(() => methode = v ?? '')),
        const SizedBox(height: 10),
        TextField(controller: aktenzeichenC, decoration: const InputDecoration(labelText: 'Beitragsnummer / Aktenzeichen', isDense: true, border: OutlineInputBorder())),
        const SizedBox(height: 10),
        Wrap(spacing: 6, children: ['eingereicht', 'in_bearbeitung', 'bewilligt', 'abgelehnt', 'widerspruch'].map((s) => ChoiceChip(
          label: Text(_statusLabel(s), style: TextStyle(fontSize: 10, color: status == s ? Colors.white : Colors.black87)),
          selected: status == s, selectedColor: s == 'bewilligt' ? Colors.green : s == 'abgelehnt' ? Colors.red : Colors.indigo,
          onSelected: (_) => setD(() => status = s),
        )).toList()),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: zeitraumVonC, readOnly: true, decoration: const InputDecoration(labelText: 'Zeitraum von', isDense: true, border: OutlineInputBorder()),
            onTap: () async { await pickDate(ctx2, zeitraumVonC); setD(() {}); })),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: zeitraumBisC, readOnly: true, decoration: const InputDecoration(labelText: 'Zeitraum bis', isDense: true, border: OutlineInputBorder()),
            onTap: () async { await pickDate(ctx2, zeitraumBisC); setD(() {}); })),
        ]),
        const SizedBox(height: 10),
        TextField(controller: notizC, maxLines: 3, decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder())),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          await widget.apiService.saveRundfunkbeitragAntrag(widget.userId, {
            'id': widget.antragId,
            'befreiungsgrund': befreiungsgrund,
            'antrag_datum': datumC.text,
            'aktenzeichen': aktenzeichenC.text,
            'methode': methode,
            'status': status,
            'zeitraum_von': zeitraumVonC.text,
            'zeitraum_bis': zeitraumBisC.text,
            'notiz': notizC.text,
          });
          if (ctx.mounted) Navigator.pop(ctx);
          _load(); widget.onChanged();
        }, child: const Text('Speichern')),
      ],
    )));
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

  Widget _dRow(IconData icon, String label, dynamic value) {
    final s = value?.toString() ?? ''; if (s.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
      Icon(icon, size: 14, color: Colors.grey.shade600), const SizedBox(width: 8),
      SizedBox(width: 130, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600))),
      Expanded(child: Text(s, style: const TextStyle(fontSize: 13))),
    ]));
  }

  Widget _buildVerlauf() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Expanded(child: Text('${_verlauf.length} Einträge', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
        FilledButton.icon(icon: const Icon(Icons.add, size: 14), label: const Text('Neuer Eintrag', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.indigo, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: _addVerlauf),
      ])),
      Expanded(child: _verlauf.isEmpty ? Center(child: Text('Kein Verlauf', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _verlauf.length, itemBuilder: (_, i) {
            final v = _verlauf[i];
            return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.indigo.shade200)),
              child: Row(children: [
                Icon(Icons.circle, size: 10, color: Colors.indigo.shade400), const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(v['datum']?.toString() ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                    if ((v['status']?.toString() ?? '').isNotEmpty) ...[const SizedBox(width: 6),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: Colors.indigo.shade100, borderRadius: BorderRadius.circular(6)),
                        child: Text(_statusLabel(v['status'].toString()), style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)))],
                  ]),
                  if ((v['notiz']?.toString() ?? '').isNotEmpty) Text(v['notiz'].toString(), style: const TextStyle(fontSize: 12)),
                ])),
                IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), onPressed: () async {
                  await widget.apiService.deleteRfbAntragVerlauf(v['id'] as int); _load(); widget.onChanged();
                }, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24)),
              ]));
          })),
    ]);
  }

  void _addVerlauf() {
    final datumC = TextEditingController(text: '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}');
    final notizC = TextEditingController();
    String status = '';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (_, setD) => AlertDialog(title: const Text('Verlauf-Eintrag'),
      content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: datumC, decoration: const InputDecoration(labelText: 'Datum', isDense: true, border: OutlineInputBorder())), const SizedBox(height: 8),
        Wrap(spacing: 6, children: ['eingereicht', 'in_bearbeitung', 'bewilligt', 'abgelehnt', 'widerspruch'].map((s) => ChoiceChip(
          label: Text(_statusLabel(s), style: TextStyle(fontSize: 10, color: status == s ? Colors.white : Colors.black87)),
          selected: status == s, selectedColor: s == 'bewilligt' ? Colors.green : s == 'abgelehnt' ? Colors.red : Colors.indigo,
          onSelected: (_) => setD(() => status = s),
        )).toList()), const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 3, decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder())),
      ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          await widget.apiService.addRfbAntragVerlauf(widget.antragId, {'datum': datumC.text, 'status': status, 'notiz': notizC.text});
          if (status.isNotEmpty) {
            await widget.apiService.saveRundfunkbeitragAntrag(widget.userId, {'id': widget.antragId, 'status': status});
          }
          if (ctx.mounted) Navigator.pop(ctx); _load(); widget.onChanged();
        }, child: const Text('Hinzufügen'))],
    )));
  }

  bool _hasDocsFor(String kat) => _docs.any((d) => (d['kategorie']?.toString() ?? '') == kat);

  Widget _buildUnterlagen() {
    return DefaultTabController(
      length: 3,
      child: Column(children: [
        TabBar(
          labelColor: Colors.green,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.green,
          tabs: [
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [if (_hasDocsFor('brief')) Icon(Icons.check_circle, size: 14, color: Colors.green.shade600), if (_hasDocsFor('brief')) const SizedBox(width: 4), const Text('Brief')])),
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [if (_hasDocsFor('antrag')) Icon(Icons.check_circle, size: 14, color: Colors.green.shade600), if (_hasDocsFor('antrag')) const SizedBox(width: 4), const Text('Antrag')])),
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [if (_hasDocsFor('bewilligung')) Icon(Icons.check_circle, size: 14, color: Colors.green.shade600), if (_hasDocsFor('bewilligung')) const SizedBox(width: 4), const Text('Bewilligung')])),
          ],
        ),
        Expanded(child: TabBarView(children: [
          _buildDocSubTab('brief', 'Briefe (Schriftverkehr)'),
          _buildDocSubTab('antrag', 'Antragsunterlagen'),
          _buildDocSubTab('bewilligung', 'Bewilligungsbescheid'),
        ])),
      ]),
    );
  }

  Widget _buildDocSubTab(String kategorie, String title) {
    final filtered = _docs.where((d) => (d['kategorie']?.toString() ?? '') == kategorie).toList();
    final hasAny = filtered.isNotEmpty;
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Row(children: [
        Icon(hasAny ? Icons.check_circle : Icons.folder_open, size: 20, color: hasAny ? Colors.green.shade700 : Colors.grey.shade400), const SizedBox(width: 8),
        Expanded(child: Text('$title (${filtered.length})', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: hasAny ? Colors.green.shade700 : Colors.grey.shade600))),
        ElevatedButton.icon(onPressed: () => _uploadDoc(kategorie: kategorie), icon: const Icon(Icons.upload_file, size: 16), label: const Text('Hochladen', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white)),
      ])),
      Expanded(child: filtered.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.cloud_upload, size: 40, color: Colors.grey.shade300), const SizedBox(height: 8),
              Text('Keine Dokumente', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
            ]))
          : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: filtered.length, itemBuilder: (_, i) {
              final d = filtered[i];
              return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green.shade200)),
                child: Row(children: [
                  Icon(Icons.attach_file, size: 18, color: Colors.green.shade700), const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(d['datei_name']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                    if ((d['created_at']?.toString() ?? '').isNotEmpty) Text(d['created_at'].toString(), style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  ])),
                  IconButton(icon: Icon(Icons.visibility, size: 18, color: Colors.indigo.shade600), tooltip: 'Anzeigen', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: () async {
                    try {
                      final resp = await widget.apiService.downloadRfbAntragDoc(d['id'] as int);
                      if (resp.statusCode == 200 && mounted) {
                        final dir = await getTemporaryDirectory();
                        final file = File('${dir.path}/${d['datei_name']}');
                        await file.writeAsBytes(resp.bodyBytes);
                        if (mounted) await FileViewerDialog.show(context, file.path, d['datei_name']?.toString() ?? '');
                      }
                    } catch (_) {}
                  }),
                  IconButton(icon: Icon(Icons.download, size: 18, color: Colors.green.shade700), tooltip: 'Herunterladen', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: () async {
                    try {
                      final resp = await widget.apiService.downloadRfbAntragDoc(d['id'] as int);
                      if (resp.statusCode == 200 && mounted) {
                        final dir = await getTemporaryDirectory();
                        final file = File('${dir.path}/${d['datei_name']}');
                        await file.writeAsBytes(resp.bodyBytes);
                        await OpenFilex.open(file.path);
                      }
                    } catch (_) {}
                  }),
                  IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400), tooltip: 'Löschen', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: () async {
                    await widget.apiService.deleteRfbAntragDoc(d['id'] as int); _load();
                  }),
                ]),
              );
            })),
    ]);
  }

  Future<void> _uploadDoc({String kategorie = ''}) async {
    final result = await FilePickerHelper.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'], allowMultiple: true);
    if (result == null || result.files.isEmpty) return;
    final files = result.files.where((f) => f.path != null).toList();
    if (files.isEmpty) return;
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${files.length} Datei(en) werden hochgeladen...'), duration: const Duration(seconds: 2)));
    final katLabel = kategorie == 'brief' ? 'Brief' : kategorie == 'antrag' ? 'Antrag' : kategorie == 'bewilligung' ? 'Bewilligung' : 'Dokument';
    for (final file in files) {
      await widget.apiService.uploadRfbAntragDoc(antragId: widget.antragId, filePath: file.path!, fileName: file.name, kategorie: kategorie);
    }
    final today = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';
    await widget.apiService.addRfbAntragVerlauf(widget.antragId, {'datum': today, 'status': '', 'notiz': '${files.length} $katLabel-Dokument(e) hochgeladen: ${files.map((f) => f.name).join(', ')}'});
    _load();
  }

  Widget _buildKorrespondenz() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Expanded(child: Text('${_korr.length} Einträge', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
        FilledButton.icon(icon: const Icon(Icons.call_received, size: 14), label: const Text('Eingang', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.green.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _addKorr('eingang')),
        const SizedBox(width: 6),
        FilledButton.icon(icon: const Icon(Icons.call_made, size: 14), label: const Text('Ausgang', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _addKorr('ausgang')),
      ])),
      Expanded(child: _korr.isEmpty ? Center(child: Text('Keine Korrespondenz', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _korr.length, itemBuilder: (_, i) {
            final k = _korr[i]; final isEin = k['richtung'] == 'eingang';
            return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: isEin ? Colors.green.shade200 : Colors.blue.shade200)),
              child: Row(children: [
                Icon(isEin ? Icons.call_received : Icons.call_made, size: 18, color: isEin ? Colors.green.shade700 : Colors.blue.shade700), const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(k['betreff']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isEin ? Colors.green.shade800 : Colors.blue.shade800)),
                  Text(k['datum']?.toString() ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  if ((k['notiz']?.toString() ?? '').isNotEmpty) Text(k['notiz'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                  if (k['id'] != null) Padding(padding: const EdgeInsets.only(top: 4),
                    child: KorrAttachmentsWidget(apiService: widget.apiService, modul: 'rfb_antrag', korrespondenzId: k['id'] as int)),
                ])),
                IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), onPressed: () async {
                  await widget.apiService.deleteRfbAntragKorr(k['id'] as int); _load();
                }, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28)),
              ]));
          })),
    ]);
  }

  void _addKorr(String richtung) {
    final betreffC = TextEditingController();
    final datumC = TextEditingController(text: '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}');
    final notizC = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(title: Text(richtung == 'eingang' ? 'Eingang' : 'Ausgang'),
      content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: datumC, decoration: const InputDecoration(labelText: 'Datum', isDense: true, border: OutlineInputBorder())), const SizedBox(height: 8),
        TextField(controller: betreffC, decoration: const InputDecoration(labelText: 'Betreff', isDense: true, border: OutlineInputBorder())), const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 3, decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder())),
      ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          await widget.apiService.saveRfbAntragKorr(widget.antragId, {'richtung': richtung, 'datum': datumC.text.trim(), 'betreff': betreffC.text.trim(), 'notiz': notizC.text.trim()});
          if (ctx.mounted) Navigator.pop(ctx); _load();
        }, child: const Text('Speichern'))],
    ));
  }
}
