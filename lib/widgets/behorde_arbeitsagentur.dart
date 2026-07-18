import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../services/api_service.dart';
import '../services/aa_auto_login_service.dart';
import '../services/ticket_service.dart';
import 'file_viewer_dialog.dart';
import '../utils/file_picker_helper.dart';
import 'korrespondenz_attachments_widget.dart';

class BehordeArbeitsagenturContent extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final Map<String, dynamic> Function(String type) getData;
  final bool Function(String type) isLoading;
  final bool Function(String type) isSaving;
  final void Function(String type) loadData;
  final void Function(String type, Map<String, dynamic> data) saveData;
  final Widget Function(String type, TextEditingController controller) dienststelleBuilder;
  final Widget Function({required String type, required TextEditingController arbeitsvermittlerController, required TextEditingController arbeitsvermittlerTelController, required TextEditingController arbeitsvermittlerEmailController, required Map<String, dynamic> data, required StateSetter setLocalState}) arbeitsvermittlerBuilder;
  final Widget Function({required String behoerdeType, required List<Map<String, dynamic>> antraege, required List<DropdownMenuItem<String>> artItems, required List<DropdownMenuItem<String>> statusItems, required void Function(List<Map<String, dynamic>>) onChanged, required BuildContext context}) antraegeBuilder;
  final Widget Function({required List<Map<String, dynamic>> meldungen, required void Function(List<Map<String, dynamic>>) onChanged, required BuildContext context}) meldungenBuilder;
  final Widget Function({required String behoerdeType, required String behoerdeLabel, required List<Map<String, dynamic>> begutachtungen, required Map<String, dynamic> data, required void Function(List<Map<String, dynamic>>) onChanged, required StateSetter setLocalState}) begutachtungBuilder;
  final Widget Function({required String behoerdeType, required String behoerdeLabel, required List<Map<String, dynamic>> termine, required Map<String, dynamic> data, required void Function(List<Map<String, dynamic>>) onChanged, required StateSetter setLocalState}) termineBuilder;
  final Future<void> Function(String type, String field, dynamic value) autoSaveField;
  final List<Map<String, dynamic>> Function(Map<String, dynamic> data) getTermineListe;
  final List<Map<String, dynamic>> Function(Map<String, dynamic> data) getBegutachtungen;
  final List<Map<String, dynamic>> Function(Map<String, dynamic> data) getMeldungen;
  final List<Map<String, dynamic>> Function(Map<String, dynamic> data) getAntraege;
  final TicketService? ticketService;
  final String adminMitgliedernummer;
  final String memberMitgliedernummer;
  final String memberName;

  const BehordeArbeitsagenturContent({
    super.key,
    required this.apiService,
    required this.userId,
    required this.getData,
    required this.isLoading,
    required this.isSaving,
    required this.loadData,
    required this.saveData,
    required this.dienststelleBuilder,
    required this.arbeitsvermittlerBuilder,
    required this.antraegeBuilder,
    required this.meldungenBuilder,
    required this.begutachtungBuilder,
    required this.termineBuilder,
    required this.autoSaveField,
    required this.getTermineListe,
    required this.getBegutachtungen,
    required this.getMeldungen,
    required this.getAntraege,
    this.ticketService,
    this.adminMitgliedernummer = '',
    this.memberMitgliedernummer = '',
    this.memberName = '',
  });

  @override
  State<BehordeArbeitsagenturContent> createState() => _State();
}

class _State extends State<BehordeArbeitsagenturContent> with TickerProviderStateMixin {
  static const type = 'bundesagentur';
  late final TabController _tabCtrl;
  bool _dbLoaded = false;
  bool _dbLoading = false;
  bool _dbSaving = false;
  Map<String, dynamic> _dbData = {};
  List<Map<String, dynamic>> _dbAntraege = [];
  List<Map<String, dynamic>> _dbTermine = [];
  List<Map<String, dynamic>> _dbBegutachtungen = [];
  List<Map<String, dynamic>> _dbVorschlaege = [];
  // Auto-Login button vizibil DOAR când TOTP e configurat + email + parolă există.
  // Statusul TOTP e ținut LOCAL în _buildOnlineTab (setLocal), NU pe State-ul
  // părinte — un setState pe părinte re-construiește _buildOnlineTab și ar
  // reseta comutatorul „Online-Konto" + câmpurile la valorile din _dbData.

  static const _tabs = [
    (Icons.account_balance, 'Zuständige Arbeitsagentur'),
    (Icons.person_pin, 'Vermittler'),
    (Icons.badge, 'Stammdaten'),
    (Icons.assignment, 'Anträge'),
    (Icons.block, 'Sperrzeit'),
    (Icons.handshake, 'EGV'),
    (Icons.school, 'BGS'),
    (Icons.work_outline, 'Vorschläge'),
    (Icons.cloud, 'Online'),
    (Icons.medical_services, 'Med.Gutachten'),
    (Icons.event, 'Termine'),
    (Icons.email, 'Korrespondenz'),
    (Icons.assignment_ind, 'Vollmacht'),
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
    _loadFromDB();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  String _v(String field) => _dbData[field]?.toString() ?? '';
  bool _bv(String field) => _dbData[field] == true || _dbData[field] == 'true' || _dbData[field] == '1' || _dbData[field] == 1;

  Widget _cTab(IconData icon, String label, bool hasData) {
    return Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.circle, size: 8, color: hasData ? Colors.green : Colors.red),
      const SizedBox(width: 4),
      Icon(icon, size: 14),
      const SizedBox(width: 4),
      Text(label),
    ]));
  }

  Future<void> _loadFromDB() async {
    if (_dbLoading) return;
    setState(() => _dbLoading = true);
    try {
      final res = await widget.apiService.getArbeitsagenturData(widget.userId);
      if (res['success'] == true && mounted) {
        final rawData = res['data'];
        if (rawData is Map) {
          _dbData = {};
          for (final e in rawData.entries) {
            final key = e.key.toString();
            final parts = key.split('.');
            if (parts.length == 2) {
              _dbData[parts[1]] = e.value;
            } else {
              _dbData[key] = e.value;
            }
          }
        }
        _dbAntraege = (res['antraege'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _dbTermine = (res['termine'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _dbBegutachtungen = (res['begutachtungen'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _dbVorschlaege = (res['vorschlaege'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      debugPrint('[AA] DB load error: $e');
    }
    if (mounted) setState(() { _dbLoading = false; _dbLoaded = true; });
  }

  Future<void> _saveScalarToDB(Map<String, dynamic> fields) async {
    final mapped = <String, dynamic>{};
    for (final e in fields.entries) {
      String bereich = 'stammdaten';
      if (['arbeitssuchend_datum','arbeitslos_datum','letzter_arbeitstag','kuendigungsart'].contains(e.key)) {
        bereich = 'arbeitsmeldung';
      } else if (['bescheid_von','bescheid_bis','leistungssatz_betrag','leistungssatz_typ','bemessungsentgelt','anspruchsdauer','restanspruch'].contains(e.key)) {
        bereich = 'bescheid';
      } else if (e.key.startsWith('sperrzeit') || e.key == 'has_sperrzeit') {
        bereich = 'sperrzeit';
      } else if (e.key.startsWith('egv') || e.key == 'has_egv') {
        bereich = 'egv';
      } else if (e.key.startsWith('bgs') || e.key == 'has_bgs') {
        bereich = 'bildungsgutschein';
      } else if (['has_online_account','online_email','online_password','has_passkey','passkey_access'].contains(e.key)) {
        bereich = 'online';
      }
      final val = e.value is bool ? (e.value ? 'true' : 'false') : e.value?.toString() ?? '';
      mapped['$bereich.${e.key}'] = val;
    }
    await widget.apiService.saveArbeitsagenturData(widget.userId, mapped);
  }

  Widget _sectionHeader(IconData icon, String title, Color color) {
    return Padding(padding: const EdgeInsets.only(top: 8, bottom: 4), child: Row(children: [
      Icon(icon, size: 20, color: color), const SizedBox(width: 8),
      Expanded(child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color))),
      Expanded(child: Divider(color: color.withValues(alpha: 0.3), thickness: 1)),
    ]));
  }

  Widget _textField(String label, TextEditingController controller, {String hint = '', IconData icon = Icons.edit, int maxLines = 1}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
      const SizedBox(height: 4),
      TextField(controller: controller, maxLines: maxLines, decoration: InputDecoration(hintText: hint, prefixIcon: Icon(icon, size: 20), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)), style: const TextStyle(fontSize: 14)),
    ]);
  }

  Widget _dateField(String label, TextEditingController controller, BuildContext ctx) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
      const SizedBox(height: 4),
      TextField(controller: controller, readOnly: true, decoration: InputDecoration(hintText: 'TT.MM.JJJJ', prefixIcon: const Icon(Icons.calendar_today, size: 20), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
        onTap: () async {
          final picked = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de'));
          if (picked != null) controller.text = '${picked.day.toString().padLeft(2, '0')}.${picked.month.toString().padLeft(2, '0')}.${picked.year}';
        }),
    ]);
  }


  Future<void> _saveTab(Map<String, dynamic> fields) async {
    setState(() => _dbSaving = true);
    try {
      await _saveScalarToDB(fields);
      for (final e in fields.entries) { _dbData[e.key] = e.value is bool ? e.value.toString() : e.value; }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gespeichert'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    }
    if (mounted) setState(() => _dbSaving = false);
  }

  Widget _saveBtn(VoidCallback onSave) => Padding(padding: const EdgeInsets.only(top: 16), child: Align(alignment: Alignment.centerRight, child: ElevatedButton.icon(
    onPressed: _dbSaving ? null : onSave,
    icon: _dbSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 18),
    label: const Text('Speichern'), style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white))));

  @override
  Widget build(BuildContext context) {
    if (!_dbLoaded && !_dbLoading) _loadFromDB();
    if (widget.getData('rentenversicherung').isEmpty && !widget.isLoading('rentenversicherung')) widget.loadData('rentenversicherung');
    if (_dbLoading || !_dbLoaded) return const Center(child: CircularProgressIndicator());

    return Column(children: [
      TabBar(controller: _tabCtrl, isScrollable: true, labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold), unselectedLabelStyle: const TextStyle(fontSize: 11),
        labelColor: const Color(0xFF003F7D), unselectedLabelColor: Colors.grey.shade500, indicatorColor: const Color(0xFF003F7D), tabAlignment: TabAlignment.start,
        tabs: [
          _cTab(Icons.account_balance, 'Zuständige Arbeitsagentur', (_dbData['dienststelle']?.toString() ?? '').isNotEmpty),
          _cTab(Icons.person_pin, 'Vermittler', (_dbData['vermittler_name']?.toString() ?? '').isNotEmpty),
          _cTab(Icons.badge, 'Stammdaten', (_dbData['kundennummer']?.toString() ?? '').isNotEmpty),
          _cTab(Icons.assignment, 'Anträge', _dbAntraege.isNotEmpty),
          _cTab(Icons.block, 'Sperrzeit', _bv('has_sperrzeit')),
          _cTab(Icons.handshake, 'EGV', _bv('has_egv')),
          _cTab(Icons.school, 'BGS', _bv('has_bgs')),
          _cTab(Icons.work_outline, 'Vorschläge', _dbVorschlaege.isNotEmpty),
          _cTab(Icons.cloud, 'Online', (_dbData['online_url']?.toString() ?? '').isNotEmpty),
          _cTab(Icons.medical_services, 'Med.Gutachten', _dbBegutachtungen.isNotEmpty),
          _cTab(Icons.event, 'Termine', _dbTermine.isNotEmpty),
          _cTab(Icons.email, 'Korrespondenz', false),
          _cTab(Icons.assignment_ind, 'Vollmacht', false),
        ]),
      Expanded(child: TabBarView(controller: _tabCtrl, children: [
        _buildZustaendigeAgenturTab(),
        _buildVermittlerTab(),
        _buildStammdatenTab(),
        _buildAntraegeTab(),
        _buildSperrzeitTab(),
        _buildEgvTab(),
        _buildBgsTab(),
        _buildVorschlaegeTab(),
        _buildOnlineTab(),
        _buildBegutachtungTab(),
        _buildTermineTab(),
        SingleChildScrollView(padding: const EdgeInsets.all(16), child: _AAKorrespondenzSection(apiService: widget.apiService, userId: widget.userId)),
        _AAVollmachtSection(apiService: widget.apiService, userId: widget.userId),
      ])),
    ]);
  }

  // ──── TAB: Zuständige Arbeitsagentur (eigene Datenbank arbeitsagenturen_datenbank) ────
  static const _aaBrand = Color(0xFF003F7D);

  Widget _buildZustaendigeAgenturTab() {
    final name = _dbData['dienststelle']?.toString() ?? '';
    final strasse = _dbData['agentur_strasse']?.toString() ?? '';
    final plzOrt = _dbData['agentur_plz_ort']?.toString() ?? '';
    final telefon = _dbData['agentur_telefon']?.toString() ?? '';
    final website = _dbData['agentur_website']?.toString() ?? '';
    final aan = _dbData['arbeitsamtsnummer']?.toString() ?? '';
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.account_balance, size: 16, color: _aaBrand),
        const SizedBox(width: 6),
        const Text('Zuständige Agentur für Arbeit', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _aaBrand)),
      ]),
      const SizedBox(height: 12),
      if (name.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
          child: Column(children: [
            Icon(Icons.account_balance_outlined, size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text('Keine Arbeitsagentur ausgewählt', style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            ElevatedButton.icon(onPressed: _pickArbeitsagentur, icon: const Icon(Icons.search, size: 18), label: const Text('Arbeitsagentur auswählen'),
              style: ElevatedButton.styleFrom(backgroundColor: _aaBrand, foregroundColor: Colors.white)),
          ]),
        )
      else
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [_aaBrand.withValues(alpha: 0.05), _aaBrand.withValues(alpha: 0.12)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(12), border: Border.all(color: _aaBrand.withValues(alpha: 0.3))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 42, height: 42, decoration: BoxDecoration(color: _aaBrand, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.account_balance, color: Colors.white, size: 24)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _aaBrand)),
                Text('Agentur für Arbeit', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
              ])),
              TextButton.icon(onPressed: _pickArbeitsagentur, icon: const Icon(Icons.edit, size: 16), label: const Text('Ändern')),
            ]),
            if (aan.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: _aaBrand.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                child: Text('Arbeitsamt-Nr: $aan', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _aaBrand))),
            ],
            if (strasse.isNotEmpty || plzOrt.isNotEmpty) ...[
              const SizedBox(height: 10),
              _infoRow(Icons.location_on, [strasse, plzOrt].where((s) => s.isNotEmpty).join(', ')),
            ],
            if (telefon.isNotEmpty) _infoRow(Icons.phone, telefon),
            if (website.isNotEmpty) _infoRow(Icons.language, website),
          ]),
        ),
    ]));
  }

  Widget _infoRow(IconData icon, String text) => Padding(padding: const EdgeInsets.only(top: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(icon, size: 15, color: Colors.grey.shade600), const SizedBox(width: 6),
    Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
  ]));

  Future<void> _selectAgentur(Map<String, dynamic> a) async {
    await _saveTab({
      'dienststelle': a['name']?.toString() ?? '',
      'agentur_db_id': a['id']?.toString() ?? '',
      'agentur_strasse': a['strasse']?.toString() ?? '',
      'agentur_plz_ort': a['plz_ort']?.toString() ?? '',
      'agentur_telefon': a['telefon']?.toString() ?? '',
      'agentur_email': a['email']?.toString() ?? '',
      'agentur_website': a['website']?.toString() ?? '',
      'arbeitsamtsnummer': a['arbeitsamtsnummer']?.toString() ?? '',
    });
    if (mounted) setState(() {});
  }

  Future<void> _pickArbeitsagentur() async {
    final searchC = TextEditingController();
    List<Map<String, dynamic>> results = [];
    bool loading = true;
    await showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) {
      Future<void> doSearch() async {
        setD(() => loading = true);
        final r = await widget.apiService.searchArbeitsagenturen(search: searchC.text.trim());
        final list = (r['arbeitsagenturen'] as List?) ?? (r['data'] as List?) ?? [];
        if (!ctx2.mounted) return;
        setD(() { results = list.map((e) => Map<String, dynamic>.from(e as Map)).toList(); loading = false; });
      }
      if (loading && results.isEmpty) Future.microtask(doSearch);
      return AlertDialog(
        title: Row(children: [
          const Expanded(child: Text('Arbeitsagentur auswählen', style: TextStyle(fontSize: 16))),
          TextButton.icon(onPressed: () => _showNewAgenturForm(ctx, onCreated: (a) { Navigator.pop(ctx); _selectAgentur(a); }),
            icon: const Icon(Icons.add, size: 18), label: const Text('Neu')),
        ]),
        content: SizedBox(width: 480, height: 440, child: Column(children: [
          TextField(controller: searchC, autofocus: true, onSubmitted: (_) => doSearch(),
            decoration: InputDecoration(hintText: 'Suche (Name, Ort, PLZ, Arbeitsamt-Nr)...', isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: doSearch))),
          const SizedBox(height: 8),
          Expanded(child: loading
            ? const Center(child: CircularProgressIndicator())
            : results.isEmpty
              ? const Center(child: Text('Keine Arbeitsagenturen gefunden'))
              : ListView.builder(itemCount: results.length, itemBuilder: (_, i) {
                  final a = results[i];
                  final aan = a['arbeitsamtsnummer']?.toString() ?? '';
                  return Card(child: ListTile(
                    leading: const Icon(Icons.account_balance, color: _aaBrand),
                    title: Text(a['name']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text('${a['strasse'] ?? ''}\n${a['plz_ort'] ?? ''}${aan.isNotEmpty ? '\nArbeitsamt-Nr: $aan' : ''}', style: const TextStyle(fontSize: 11)),
                    isThreeLine: true,
                    onTap: () { Navigator.pop(ctx); _selectAgentur(a); },
                  ));
                })),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen'))],
      );
    }));
  }

  Future<void> _showNewAgenturForm(BuildContext parentCtx, {required void Function(Map<String, dynamic>) onCreated}) async {
    final nameC = TextEditingController();
    final aanC = TextEditingController();
    final strasseC = TextEditingController();
    final plzOrtC = TextEditingController();
    final telC = TextEditingController();
    final websiteC = TextEditingController();
    bool saving = false;
    Widget f(String label, TextEditingController c, String hint, {IconData icon = Icons.edit}) =>
      Padding(padding: const EdgeInsets.only(bottom: 10), child: _textField(label, c, hint: hint, icon: icon));
    await showDialog(context: parentCtx, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) => AlertDialog(
      title: const Text('Neue Arbeitsagentur anlegen', style: TextStyle(fontSize: 16)),
      content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        f('Name *', nameC, 'z.B. Agentur für Arbeit Ulm', icon: Icons.account_balance),
        f('Arbeitsamtsnummer', aanC, 'z.B. 123A (3 Ziffern + Buchstabe)', icon: Icons.badge),
        f('Straße', strasseC, '', icon: Icons.location_on),
        f('PLZ / Ort', plzOrtC, '89073 Ulm', icon: Icons.markunread_mailbox),
        f('Telefon', telC, '', icon: Icons.phone),
        f('Website', websiteC, 'https://www.arbeitsagentur.de/...', icon: Icons.language),
      ]))),
      actions: [
        TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        ElevatedButton(
          onPressed: saving ? null : () async {
            if (nameC.text.trim().isEmpty) return;
            setD(() => saving = true);
            final r = await widget.apiService.createArbeitsagentur({
              'name': nameC.text.trim(),
              'arbeitsamtsnummer': aanC.text.trim(),
              'strasse': strasseC.text.trim(),
              'plz_ort': plzOrtC.text.trim(),
              'telefon': telC.text.trim(),
              'website': websiteC.text.trim(),
            });
            if (!ctx2.mounted) return;
            setD(() => saving = false);
            if (r['success'] == true && r['arbeitsagentur'] != null) {
              Navigator.pop(ctx);
              onCreated(Map<String, dynamic>.from(r['arbeitsagentur'] as Map));
            } else {
              ScaffoldMessenger.of(ctx2).showSnackBar(SnackBar(content: Text(r['message']?.toString() ?? 'Fehler beim Anlegen')));
            }
          },
          child: saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Anlegen'),
        ),
      ],
    )));
  }

  // ──── TAB: Stammdaten (Kundennummer) ────
  Widget _buildStammdatenTab() {
    final kundennummerC = TextEditingController(text: _v('kundennummer'));
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader(Icons.badge, 'Stammdaten', Colors.indigo),
      const SizedBox(height: 8),
      _textField('Kundennummer', kundennummerC, hint: 'z.B. 123A456789 (10-stellig)', icon: Icons.badge),
      Padding(padding: const EdgeInsets.only(top: 6), child: Text(
        'Format: 10-stellig — Arbeitsamtsnummer (3 Ziffern + 1 Buchstabe) + 6 Ziffern Ordnungsnummer, z.B. 123A456789.',
        style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
      _saveBtn(() => _saveTab({'kundennummer': kundennummerC.text.trim()})),
    ]));
  }

  // ──── TAB: Arbeitsvermittler — JC-style multi-AV pool ────
  // Replaced the old single-AV form with a per-Dienststelle pool +
  // per-user assignment (mirrors the Jobcenter UX). Pool entries live
  // in arbeitsagentur_personal; assignments in arbeitsagentur_user_av.
  Widget _buildVermittlerTab() {
    return _ArbeitsagenturArbeitsvermittlerTab(
      apiService: widget.apiService,
      userId: widget.userId,
      arbeitsagenturName: _dbData['dienststelle']?.toString() ?? '',
      arbeitsagenturOrt: '',
    );
  }

  // ──── TAB: Anträge (antrag-zentrisch) ────
  // Ein Antrag = ein Arbeitslosigkeits-Fall, der die Stufen Arbeitssuchend-/
  // Arbeitslosenmeldung → ALG-Antrag → Bewilligungsbescheid durchläuft.
  // Formulare/Unterlagen/Korrespondenz liegen im Detail-Modal (_AaAntragDetailView).
  Widget _buildAntraegeTab() {
    final antraege = _dbAntraege;
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Row(children: [
        const Icon(Icons.assignment, size: 20, color: _aaBrand),
        const SizedBox(width: 8),
        Text('Anträge (${antraege.length})', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _aaBrand)),
        const Spacer(),
        ElevatedButton.icon(onPressed: _showNewAntragDialog, icon: const Icon(Icons.add, size: 18), label: const Text('Neuer Antrag'),
          style: ElevatedButton.styleFrom(backgroundColor: _aaBrand, foregroundColor: Colors.white)),
      ])),
      Expanded(child: antraege.isEmpty
        ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.assignment_outlined, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text('Keine Anträge vorhanden', style: TextStyle(color: Colors.grey.shade500)),
            const SizedBox(height: 4),
            Text('„Neuer Antrag" beginnt mit der Arbeitssuchendmeldung', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
          ]))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: antraege.length, itemBuilder: (_, i) {
            final a = antraege[i];
            final status = a['status']?.toString() ?? '';
            final sc = aaStatusColor(status);
            final datum = a['datum']?.toString() ?? '';
            return Card(child: ListTile(
              leading: Icon(status == 'bewilligt' ? Icons.check_circle : status == 'abgelehnt' ? Icons.cancel : Icons.assignment, color: sc, size: 28),
              title: Text('${aaArtLabel(a['art']?.toString() ?? '')}${datum.isNotEmpty ? '  •  $datum' : ''}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Container(margin: const EdgeInsets.only(top: 4), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: sc.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                child: Text(aaStatusLabel(status).toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: sc))),
              onTap: () { final aid = int.tryParse(a['id']?.toString() ?? ''); if (aid != null) _showAaAntragDetailDialog(aid, a); },
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400), tooltip: 'Löschen', onPressed: () => _deleteAntrag(a)),
                Icon(Icons.chevron_right, color: Colors.grey.shade400),
              ]),
            ));
          })),
    ]);
  }

  Future<void> _deleteAntrag(Map<String, dynamic> a) async {
    final aid = int.tryParse(a['id']?.toString() ?? '');
    if (aid == null) return;
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Antrag löschen?'),
      content: const Text('Der Antrag und alle Formulardaten, Unterlagen und Korrespondenz werden gelöscht.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(c, true), child: const Text('Löschen')),
      ]));
    if (ok != true) return;
    await widget.apiService.deleteArbeitsagenturAntrag(widget.userId, aid);
    await _loadFromDB();
  }

  // Neuer Antrag → beginnt mit der Arbeitssuchendmeldung (§ 38 SGB III).
  void _showNewAntragDialog() {
    final suchendC = TextEditingController();
    final letzterC = TextEditingController();
    final taetigkeitC = TextEditingController();
    final svC = TextEditingController();
    bool saving = false;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) => AlertDialog(
      title: const Text('Neuer Antrag — Arbeitssuchendmeldung', style: TextStyle(fontSize: 16)),
      content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('§ 38 SGB III — Meldung als arbeitssuchend', style: TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 12),
        _dateField('Arbeitssuchend gemeldet am *', suchendC, ctx2),
        const SizedBox(height: 10),
        _dateField('Letzter Arbeitstag', letzterC, ctx2),
        const SizedBox(height: 10),
        _textField('Letzte Tätigkeit', taetigkeitC, hint: 'z.B. Lagerarbeiter', icon: Icons.work),
        const SizedBox(height: 10),
        _textField('SV-Nummer', svC, hint: 'Sozialversicherungsnummer', icon: Icons.badge),
      ]))),
      actions: [
        TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        ElevatedButton(
          onPressed: saving ? null : () async {
            if (suchendC.text.trim().isEmpty) return;
            setD(() => saving = true);
            final r = await widget.apiService.saveArbeitsagenturAntrag(widget.userId, {
              'art': 'arbeitslosigkeit', 'status': 'arbeitssuchend', 'datum': suchendC.text.trim(), 'notiz': '',
            });
            final aid = int.tryParse(r['id']?.toString() ?? '');
            if (aid != null) {
              await widget.apiService.saveAaAntragData(aid, {
                'arbeitssuchendmeldung.arbeitssuchend_datum': suchendC.text.trim(),
                'arbeitssuchendmeldung.letzter_arbeitstag': letzterC.text.trim(),
                'arbeitssuchendmeldung.letzte_taetigkeit': taetigkeitC.text.trim(),
                'arbeitssuchendmeldung.sv_nummer': svC.text.trim(),
              });
            }
            if (!ctx2.mounted) return;
            Navigator.pop(ctx);
            await _loadFromDB();
            if (aid != null && mounted) {
              final a = _dbAntraege.firstWhere((x) => x['id'].toString() == aid.toString(),
                orElse: () => {'id': aid, 'art': 'arbeitslosigkeit', 'status': 'arbeitssuchend', 'datum': suchendC.text.trim()});
              _showAaAntragDetailDialog(aid, a);
            }
          },
          child: saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Anlegen'),
        ),
      ],
    )));
  }

  void _showAaAntragDetailDialog(int antragId, Map<String, dynamic> antrag) {
    showDialog(context: context, builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: SizedBox(
        width: MediaQuery.of(ctx).size.width * 0.9,
        height: MediaQuery.of(ctx).size.height * 0.86,
        child: _AaAntragDetailView(
          apiService: widget.apiService,
          userId: widget.userId,
          antragId: antragId,
          antrag: antrag,
          onChanged: _loadFromDB,
          onClose: () => Navigator.pop(ctx),
        ),
      ),
    ));
  }

  // ──── TAB: Sperrzeit ────
  Widget _buildSperrzeitTab() {
    bool has = _bv('has_sperrzeit');
    String typ = _v('sperrzeit_typ');
    final vonC = TextEditingController(text: _v('sperrzeit_von'));
    final bisC = TextEditingController(text: _v('sperrzeit_bis'));
    String widerspruch = _v('sperrzeit_widerspruch');
    final notizC = TextEditingController(text: _v('sperrzeit_notiz'));
    return StatefulBuilder(builder: (ctx, setLocal) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.shade200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.block, size: 18, color: Colors.red.shade700), const SizedBox(width: 8), Text('Sperrzeit vorhanden', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red.shade700)), const Spacer(), Switch(value: has, onChanged: (v) => setLocal(() => has = v), activeThumbColor: Colors.red)]),
          if (has) ...[
            const SizedBox(height: 12),
            Text('Sperrzeit-Grund', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(initialValue: typ.isEmpty ? null : typ, isExpanded: true,
              decoration: InputDecoration(isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
              hint: const Text('Auswählen...', style: TextStyle(fontSize: 13)),
              items: const [
                DropdownMenuItem(value: 'eigenkuendigung', child: Text('Eigenkündigung (12 Wochen)', style: TextStyle(fontSize: 13))),
                DropdownMenuItem(value: 'aufhebungsvertrag', child: Text('Aufhebungsvertrag (12 Wochen)', style: TextStyle(fontSize: 13))),
                DropdownMenuItem(value: 'arbeitsablehnung', child: Text('Arbeitsablehnung (3-12 Wochen)', style: TextStyle(fontSize: 13))),
                DropdownMenuItem(value: 'meldeversaeumnis', child: Text('Meldeversäumnis (1 Woche)', style: TextStyle(fontSize: 13))),
                DropdownMenuItem(value: 'massnahmeabbruch', child: Text('Maßnahmeabbruch (3-12 Wochen)', style: TextStyle(fontSize: 13))),
                DropdownMenuItem(value: 'verspaetete_meldung', child: Text('Verspätete Meldung (1 Woche)', style: TextStyle(fontSize: 13))),
                DropdownMenuItem(value: 'eigenbemuehungen', child: Text('Unzureichende Eigenbemühungen (2 Wochen)', style: TextStyle(fontSize: 13))),
              ], onChanged: (v) => setLocal(() => typ = v ?? '')),
            const SizedBox(height: 12),
            Row(children: [Expanded(child: _dateField('Sperrzeit von', vonC, ctx)), const SizedBox(width: 12), Expanded(child: _dateField('Sperrzeit bis', bisC, ctx))]),
            const SizedBox(height: 12),
            Text('Widerspruch', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(initialValue: widerspruch.isEmpty ? null : widerspruch, isExpanded: true,
              decoration: InputDecoration(isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
              hint: const Text('Kein Widerspruch', style: TextStyle(fontSize: 13)),
              items: const [
                DropdownMenuItem(value: 'kein', child: Text('Kein Widerspruch', style: TextStyle(fontSize: 13))),
                DropdownMenuItem(value: 'eingelegt', child: Text('Widerspruch eingelegt', style: TextStyle(fontSize: 13))),
                DropdownMenuItem(value: 'stattgegeben', child: Text('Stattgegeben', style: TextStyle(fontSize: 13))),
                DropdownMenuItem(value: 'abgelehnt', child: Text('Zurückgewiesen', style: TextStyle(fontSize: 13))),
                DropdownMenuItem(value: 'klage', child: Text('Klage beim Sozialgericht', style: TextStyle(fontSize: 13))),
              ], onChanged: (v) => setLocal(() => widerspruch = v ?? '')),
            const SizedBox(height: 8),
            _textField('Notizen zur Sperrzeit', notizC, hint: 'Details, Begründung, Fristen...', icon: Icons.notes, maxLines: 2),
          ],
        ])),
      _saveBtn(() => _saveTab({'has_sperrzeit': has, 'sperrzeit_typ': typ, 'sperrzeit_von': vonC.text.trim(), 'sperrzeit_bis': bisC.text.trim(), 'sperrzeit_widerspruch': widerspruch, 'sperrzeit_notiz': notizC.text.trim()})),
    ])));
  }

  // ──── TAB: EGV ────
  Widget _buildEgvTab() {
    bool has = _bv('has_egv');
    final vonC = TextEditingController(text: _v('egv_von'));
    final bisC = TextEditingController(text: _v('egv_bis'));
    final pflichtenC = TextEditingController(text: _v('egv_pflichten'));
    return StatefulBuilder(builder: (ctx, setLocal) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.purple.shade200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.handshake, size: 18, color: Colors.purple.shade700), const SizedBox(width: 8), Text('EGV vorhanden', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.purple.shade700)), const Spacer(), Switch(value: has, onChanged: (v) => setLocal(() => has = v), activeThumbColor: Colors.purple)]),
          if (has) ...[
            const SizedBox(height: 12),
            Row(children: [Expanded(child: _dateField('Gültig von', vonC, ctx)), const SizedBox(width: 12), Expanded(child: _dateField('Gültig bis', bisC, ctx))]),
            const SizedBox(height: 8),
            _textField('Pflichten / Eigenbemühungen', pflichtenC, hint: 'z.B. 10 Bewerbungen/Monat...', icon: Icons.checklist, maxLines: 3),
          ],
        ])),
      _saveBtn(() => _saveTab({'has_egv': has, 'egv_von': vonC.text.trim(), 'egv_bis': bisC.text.trim(), 'egv_pflichten': pflichtenC.text.trim()})),
    ])));
  }

  // ──── TAB: Bildungsgutschein ────
  Widget _buildBgsTab() {
    bool has = _bv('has_bgs');
    String typ = _v('bgs_typ'), status = _v('bgs_status');
    final nameC = TextEditingController(text: _v('bgs_name'));
    final traegerC = TextEditingController(text: _v('bgs_traeger'));
    final vonC = TextEditingController(text: _v('bgs_von'));
    final bisC = TextEditingController(text: _v('bgs_bis'));
    return StatefulBuilder(builder: (ctx, setLocal) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.cyan.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.cyan.shade200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.school, size: 18, color: Colors.cyan.shade700), const SizedBox(width: 8), Text('Bildungsgutschein / AVGS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.cyan.shade700)), const Spacer(), Switch(value: has, onChanged: (v) => setLocal(() => has = v), activeThumbColor: Colors.cyan.shade700)]),
          if (has) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Art', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)), const SizedBox(height: 4),
                DropdownButtonFormField<String>(initialValue: typ.isEmpty ? null : typ, isExpanded: true, decoration: InputDecoration(isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                  hint: const Text('Auswählen...', style: TextStyle(fontSize: 13)),
                  items: const [DropdownMenuItem(value: 'bildungsgutschein', child: Text('BGS', style: TextStyle(fontSize: 13))), DropdownMenuItem(value: 'avgs_mat', child: Text('AVGS MAT', style: TextStyle(fontSize: 13))), DropdownMenuItem(value: 'avgs_mpav', child: Text('AVGS MPAV', style: TextStyle(fontSize: 13))), DropdownMenuItem(value: 'avgs_mag', child: Text('AVGS MAG', style: TextStyle(fontSize: 13)))],
                  onChanged: (v) => setLocal(() => typ = v ?? '')),
              ])),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)), const SizedBox(height: 4),
                DropdownButtonFormField<String>(initialValue: status.isEmpty ? null : status, isExpanded: true, decoration: InputDecoration(isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                  hint: const Text('Status...', style: TextStyle(fontSize: 13)),
                  items: const [DropdownMenuItem(value: 'beantragt', child: Text('Beantragt', style: TextStyle(fontSize: 13))), DropdownMenuItem(value: 'bewilligt', child: Text('Bewilligt', style: TextStyle(fontSize: 13))), DropdownMenuItem(value: 'abgelehnt', child: Text('Abgelehnt', style: TextStyle(fontSize: 13))), DropdownMenuItem(value: 'laufend', child: Text('Laufend', style: TextStyle(fontSize: 13))), DropdownMenuItem(value: 'abgeschlossen', child: Text('Abgeschlossen', style: TextStyle(fontSize: 13))), DropdownMenuItem(value: 'abgebrochen', child: Text('Abgebrochen', style: TextStyle(fontSize: 13)))],
                  onChanged: (v) => setLocal(() => status = v ?? '')),
              ])),
            ]),
            const SizedBox(height: 12),
            _textField('Maßnahme / Qualifikation', nameC, hint: 'Name der Weiterbildung', icon: Icons.label),
            const SizedBox(height: 8),
            _textField('Bildungsträger', traegerC, hint: 'z.B. WBS, GFN, Comcave...', icon: Icons.business),
            const SizedBox(height: 8),
            Row(children: [Expanded(child: _dateField('Beginn', vonC, ctx)), const SizedBox(width: 12), Expanded(child: _dateField('Ende', bisC, ctx))]),
          ],
        ])),
      _saveBtn(() => _saveTab({'has_bgs': has, 'bgs_typ': typ, 'bgs_status': status, 'bgs_name': nameC.text.trim(), 'bgs_traeger': traegerC.text.trim(), 'bgs_von': vonC.text.trim(), 'bgs_bis': bisC.text.trim()})),
    ])));
  }

  // ──── TAB: Online-Konto ────
  Widget _buildOnlineTab() {
    bool has = _bv('has_online_account'), hasPasskey = _bv('has_passkey');
    final emailC = TextEditingController(text: _v('online_email'));
    final passwordC = TextEditingController(text: _v('online_password'));
    final passkeyC = TextEditingController(text: _v('passkey_access'));
    // Edit-mode flags: when a value is already saved, render as read-only with
    // pencil; pencil click switches to edit mode. New (empty) values open
    // directly in edit mode.
    bool emailEdit = emailC.text.isEmpty;
    bool passwordEdit = passwordC.text.isEmpty;
    bool passwordVisible = false;
    bool busyLogin = false;
    // TOTP-Status local (setLocal) — vezi comentariul de la câmpul de State șters.
    bool totpConfigured = false;
    return StatefulBuilder(builder: (ctx, setLocal) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.cloud, size: 18, color: Colors.blue.shade700), const SizedBox(width: 8), Text('Online-Konto (arbeitsagentur.de)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue.shade700)), const Spacer(), Switch(value: has, onChanged: (v) => setLocal(() => has = v), activeThumbColor: Colors.blue)]),
          if (has) ...[
            const SizedBox(height: 12),
            // E-Mail — read-only with pencil after save
            _credentialField(
              label: 'E-Mail',
              icon: Icons.email,
              hint: 'E-Mail des Online-Kontos',
              controller: emailC,
              editMode: emailEdit,
              isSecret: false,
              onEdit: () => setLocal(() => emailEdit = true),
            ),
            const SizedBox(height: 12),
            // Passwort — masked with eye toggle, read-only with pencil after save
            _credentialField(
              label: 'Passwort',
              icon: Icons.lock,
              hint: 'Passwort des Online-Kontos',
              controller: passwordC,
              editMode: passwordEdit,
              isSecret: true,
              visible: passwordVisible,
              onToggleVisible: () => setLocal(() => passwordVisible = !passwordVisible),
              onEdit: () => setLocal(() => passwordEdit = true),
            ),
            const SizedBox(height: 12),
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade200)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Icon(Icons.key, size: 18, color: Colors.orange.shade700), const SizedBox(width: 8), Text('Passkey aktiviert', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.orange.shade700)), const Spacer(), Switch(value: hasPasskey, onChanged: (v) => setLocal(() => hasPasskey = v), activeThumbColor: Colors.orange)]),
                if (hasPasskey) ...[const SizedBox(height: 12), _textField('Wer hat Zugang?', passkeyC, hint: 'Name / Rolle', icon: Icons.person_pin)],
              ])),
            const SizedBox(height: 12),
            // 2FA / TOTP Section — server-side encrypted (AES-256-GCM).
            // Statusul „configurat" e ținut LOCAL (totpConfigured) prin setLocal.
            _AaTotp2FAWidget(
              apiService: widget.apiService,
              userId: widget.userId,
              // setLocal (nu setState pe părinte): altfel încărcarea statusului TOTP
              // ar re-construi _buildOnlineTab și ar reseta comutatorul la inactiv.
              onConfiguredChange: (c) {
                if (mounted) setLocal(() => totpConfigured = c);
              },
            ),
            // Auto-Login Online — VIZIBIL DOAR cand email + parolă + TOTP toate setate.
            // (Nu apare deloc dacă lipsește vreun element — păstrăm UI curat.)
            if (emailC.text.trim().isNotEmpty && passwordC.text.isNotEmpty && totpConfigured) ...[
              const SizedBox(height: 12),
              Builder(builder: (btnCtx) => SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: busyLogin ? null : () async {
                    setLocal(() => busyLogin = true);
                    try {
                      final err = await AaAutoLoginService.autoLogin(
                        apiService: widget.apiService,
                        userId: widget.userId,
                      );
                      if (!mounted) return;
                      if (err == null) {
                        ScaffoldMessenger.of(btnCtx).showSnackBar(const SnackBar(
                          content: Text('Chromium gestartet — Auto-Login läuft im Hintergrund'),
                          backgroundColor: Colors.green,
                          duration: Duration(seconds: 4),
                        ));
                      } else {
                        ScaffoldMessenger.of(btnCtx).showSnackBar(SnackBar(
                          content: Text(err),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 6),
                        ));
                      }
                    } finally {
                      if (mounted) setLocal(() => busyLogin = false);
                    }
                  },
                  icon: busyLogin
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.rocket_launch, size: 18),
                  label: Text(busyLogin ? 'Login läuft…' : 'Auto-Login Online'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              )),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.amber.shade800),
                  const SizedBox(width: 8),
                  Expanded(child: RichText(
                    text: TextSpan(
                      style: TextStyle(fontSize: 11, color: Colors.amber.shade900, height: 1.4),
                      children: const [
                        TextSpan(
                          text: 'Hinweis: ',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextSpan(
                          text: 'Beim Auto-Login wird der aktuell gültige 2FA-Code (TOTP) automatisch '
                                'in die Zwischenablage kopiert und alle 5 Sekunden aktualisiert. '
                                'Sollte die automatische Eingabe des 6-stelligen Codes auf der '
                                'Anmeldeseite nicht erfolgen, einfach in das Code-Feld klicken und ',
                        ),
                        TextSpan(
                          text: 'Strg + V',
                          style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                        ),
                        TextSpan(
                          text: ' drücken, um den Code einzufügen.',
                        ),
                      ],
                    ),
                  )),
                ]),
              ),
            ],
          ],
        ])),
      _saveBtn(() async {
        await _saveTab({
          'has_online_account': has,
          'online_email': emailC.text.trim(),
          'online_password': passwordC.text,
          'has_passkey': hasPasskey,
          'passkey_access': passkeyC.text.trim(),
        });
        // After save, switch back to read-only for both credential fields
        if (mounted) setLocal(() {
          if (emailC.text.isNotEmpty) emailEdit = false;
          if (passwordC.text.isNotEmpty) { passwordEdit = false; passwordVisible = false; }
        });
      }),
    ])));
  }

  /// Renders a credential field with two modes:
  /// - read-only: shows label + value (or "••••••••" for secrets) + pencil icon
  /// - edit: shows label + TextField (+ eye toggle for secrets) — no pencil
  Widget _credentialField({
    required String label,
    required IconData icon,
    required String hint,
    required TextEditingController controller,
    required bool editMode,
    required bool isSecret,
    bool visible = false,
    VoidCallback? onToggleVisible,
    required VoidCallback onEdit,
  }) {
    if (editMode) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          obscureText: isSecret && !visible,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, size: 20),
            suffixIcon: isSecret
                ? IconButton(
                    icon: Icon(visible ? Icons.visibility_off : Icons.visibility, size: 18),
                    onPressed: onToggleVisible,
                    tooltip: visible ? 'Verbergen' : 'Anzeigen',
                  )
                : null,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          style: const TextStyle(fontSize: 14),
        ),
      ]);
    }
    final shown = isSecret ? '•' * (controller.text.isEmpty ? 0 : 8) : controller.text;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
      const SizedBox(height: 4),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
          color: Colors.grey.shade50,
        ),
        child: Row(children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(child: Text(
            shown.isEmpty ? '— nicht gesetzt —' : shown,
            style: TextStyle(fontSize: 14, color: shown.isEmpty ? Colors.grey.shade400 : Colors.black87),
            overflow: TextOverflow.ellipsis,
          )),
          IconButton(
            icon: Icon(Icons.edit, size: 18, color: Colors.blue.shade600),
            onPressed: onEdit,
            tooltip: 'Bearbeiten',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ]),
      ),
    ]);
  }

  // ──── TAB: Med. Begutachtung ────
  Widget _buildBegutachtungTab() {
    List<Map<String, dynamic>> beg = List<Map<String, dynamic>>.from(_dbBegutachtungen.map((e) => Map<String, dynamic>.from(e)));
    return StatefulBuilder(builder: (ctx, setLocal) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: widget.begutachtungBuilder(
      behoerdeType: type, behoerdeLabel: 'Arbeitsagentur', begutachtungen: beg, data: _dbData,
      onChanged: (u) { setLocal(() => beg = u); _syncBegutachtungenToDB(u); }, setLocalState: setLocal)));
  }

  // ──── TAB: Termine ────
  Widget _buildTermineTab() {
    List<Map<String, dynamic>> termine = List<Map<String, dynamic>>.from(_dbTermine.map((e) => Map<String, dynamic>.from(e)));
    return StatefulBuilder(builder: (ctx, setLocal) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: widget.termineBuilder(
      behoerdeType: type, behoerdeLabel: 'Arbeitsagentur', termine: termine, data: _dbData,
      onChanged: (u) { setLocal(() => termine = u); _syncTermineToDB(u); }, setLocalState: setLocal)));
  }

  Widget _buildArbeitgeberSearch(TextEditingController arbeitgeberC, TextEditingController ortC, StateSetter setDlg, {String Function()? getApAnrede, void Function(String)? setApAnrede, TextEditingController? apNameC, TextEditingController? apTelC, TextEditingController? apEmailC}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Arbeitgeber', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
      const SizedBox(height: 4),
      TextField(controller: arbeitgeberC, decoration: InputDecoration(
        hintText: 'Firmenname eingeben oder suchen...', prefixIcon: const Icon(Icons.business, size: 20), isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        suffixIcon: IconButton(icon: Icon(Icons.search, size: 20, color: Colors.indigo.shade600), tooltip: 'In Datenbank suchen',
          onPressed: () async {
            final res = await widget.apiService.getArbeitgeberStammdaten();
            if (res['success'] != true) return;
            final all = (res['data'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
            final query = arbeitgeberC.text.trim().toLowerCase();
            final filtered = query.isEmpty ? all : all.where((a) => (a['firma_name']?.toString() ?? '').toLowerCase().contains(query)).toList();
            if (!mounted) return;
            final selected = await showDialog<Map<String, dynamic>>(context: context, builder: (sCtx) {
              String search = query;
              List<Map<String, dynamic>> results = filtered;
              return StatefulBuilder(builder: (sCtx, setS) => AlertDialog(
                title: Row(children: [Icon(Icons.business, size: 18, color: Colors.indigo.shade700), const SizedBox(width: 8), const Text('Arbeitgeber auswählen', style: TextStyle(fontSize: 14))]),
                content: SizedBox(width: 450, height: 400, child: Column(children: [
                  TextField(autofocus: true, decoration: InputDecoration(hintText: 'Suchen...', prefixIcon: const Icon(Icons.search, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                    onChanged: (v) => setS(() { search = v.toLowerCase(); results = all.where((a) => (a['firma_name']?.toString() ?? '').toLowerCase().contains(search)).toList(); })),
                  const SizedBox(height: 8),
                  Expanded(child: results.isEmpty
                    ? Center(child: Text('Keine Ergebnisse', style: TextStyle(color: Colors.grey.shade500)))
                    : ListView.builder(itemCount: results.length, itemBuilder: (_, i) {
                        final a = results[i];
                        final name = a['firma_name']?.toString() ?? '';
                        final ort = a['niederlassung_ort']?.toString() ?? a['hauptzentrale_ort']?.toString() ?? '';
                        final branche = a['branche']?.toString() ?? '';
                        return ListTile(dense: true, leading: Icon(Icons.business, size: 18, color: Colors.indigo.shade400),
                          title: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: Text([if (ort.isNotEmpty) ort, if (branche.isNotEmpty) branche].join(' · '), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          onTap: () => Navigator.pop(sCtx, a));
                      })),
                ])),
                actions: [TextButton(onPressed: () => Navigator.pop(sCtx), child: const Text('Abbrechen'))],
              ));
            });
            if (selected != null) {
              setDlg(() {
                arbeitgeberC.text = selected['firma_name']?.toString() ?? '';
                final selOrt = selected['niederlassung_ort']?.toString() ?? selected['hauptzentrale_ort']?.toString() ?? '';
                if (selOrt.isNotEmpty && ortC.text.isEmpty) ortC.text = selOrt;
                final selAnrede = selected['ansprechpartner_anrede']?.toString() ?? '';
                final selName = selected['ansprechpartner_name']?.toString() ?? '';
                if (selAnrede.isNotEmpty && (getApAnrede?.call() ?? '').isEmpty) setApAnrede?.call(selAnrede);
                if (selName.isNotEmpty && (apNameC?.text ?? '').isEmpty) apNameC?.text = selName;
                final selTel = selected['niederlassung_telefon']?.toString() ?? selected['hauptzentrale_telefon']?.toString() ?? '';
                final selEmail = selected['niederlassung_email']?.toString() ?? selected['hauptzentrale_email']?.toString() ?? '';
                if (selTel.isNotEmpty && (apTelC?.text ?? '').isEmpty) apTelC?.text = selTel;
                if (selEmail.isNotEmpty && (apEmailC?.text ?? '').isEmpty) apEmailC?.text = selEmail;
              });
            }
          }),
      ), style: const TextStyle(fontSize: 14)),
    ]);
  }

  Widget _buildStelleSearch(TextEditingController stelleC, StateSetter setDlg) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Stelle / Position', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
      const SizedBox(height: 4),
      TextField(controller: stelleC, decoration: InputDecoration(
        hintText: 'Position eingeben oder suchen...', prefixIcon: const Icon(Icons.work, size: 20), isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        suffixIcon: IconButton(icon: Icon(Icons.search, size: 20, color: Colors.indigo.shade600), tooltip: 'In Datenbank suchen',
          onPressed: () async {
            final res = await widget.apiService.getBerufsbezeichnungen();
            if (res['success'] != true) return;
            final all = (res['data'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
            final query = stelleC.text.trim().toLowerCase();
            if (!mounted) return;
            final selected = await showDialog<Map<String, dynamic>>(context: context, builder: (sCtx) {
              String search = query;
              String filterKat = '';
              final kategorien = all.map((e) => e['kategorie']?.toString() ?? '').toSet().toList()..sort();
              List<Map<String, dynamic>> results = query.isEmpty ? all : all.where((b) => (b['bezeichnung']?.toString() ?? '').toLowerCase().contains(query)).toList();
              return StatefulBuilder(builder: (sCtx, setS) => AlertDialog(
                title: Row(children: [Icon(Icons.work, size: 18, color: Colors.indigo.shade700), const SizedBox(width: 8), const Text('Stelle auswählen', style: TextStyle(fontSize: 14))]),
                content: SizedBox(width: 450, height: 450, child: Column(children: [
                  TextField(autofocus: true, decoration: InputDecoration(hintText: 'Suchen...', prefixIcon: const Icon(Icons.search, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                    onChanged: (v) => setS(() { search = v.toLowerCase(); results = all.where((b) { final match = (b['bezeichnung']?.toString() ?? '').toLowerCase().contains(search); return match && (filterKat.isEmpty || b['kategorie'] == filterKat); }).toList(); })),
                  const SizedBox(height: 8),
                  SizedBox(height: 32, child: ListView(scrollDirection: Axis.horizontal, children: [
                    Padding(padding: const EdgeInsets.only(right: 4), child: ChoiceChip(label: const Text('Alle', style: TextStyle(fontSize: 10)), selected: filterKat.isEmpty, selectedColor: Colors.indigo.shade200, visualDensity: VisualDensity.compact,
                      onSelected: (_) => setS(() { filterKat = ''; results = search.isEmpty ? all : all.where((b) => (b['bezeichnung']?.toString() ?? '').toLowerCase().contains(search)).toList(); }))),
                    ...kategorien.map((k) => Padding(padding: const EdgeInsets.only(right: 4), child: ChoiceChip(label: Text(k, style: const TextStyle(fontSize: 10)), selected: filterKat == k, selectedColor: Colors.indigo.shade200, visualDensity: VisualDensity.compact,
                      onSelected: (_) => setS(() { filterKat = k; results = all.where((b) { final match = search.isEmpty || (b['bezeichnung']?.toString() ?? '').toLowerCase().contains(search); return match && b['kategorie'] == k; }).toList(); })))),
                  ])),
                  const SizedBox(height: 8),
                  Expanded(child: results.isEmpty
                    ? Center(child: Text('Keine Ergebnisse', style: TextStyle(color: Colors.grey.shade500)))
                    : ListView.builder(itemCount: results.length, itemBuilder: (_, i) {
                        final b = results[i];
                        return ListTile(dense: true, leading: Icon(Icons.work_outline, size: 16, color: Colors.indigo.shade400),
                          title: Text(b['bezeichnung']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: Text(b['kategorie']?.toString() ?? '', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          onTap: () => Navigator.pop(sCtx, b));
                      })),
                ])),
                actions: [TextButton(onPressed: () => Navigator.pop(sCtx), child: const Text('Abbrechen'))],
              ));
            });
            if (selected != null) {
              setDlg(() => stelleC.text = selected['bezeichnung']?.toString() ?? '');
            }
          }),
      ), style: const TextStyle(fontSize: 14)),
    ]);
  }

  // ──── TAB: Vermittlungsvorschläge ────
  Widget _buildVorschlaegeTab() {
    return StatefulBuilder(builder: (ctx, setLocal) {
      List<Map<String, dynamic>> vorschlaege = List<Map<String, dynamic>>.from(_dbVorschlaege.map((e) => Map<String, dynamic>.from(e)));
      return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.work_outline, size: 20, color: Colors.indigo.shade700), const SizedBox(width: 8),
          Text('Vermittlungsvorschläge', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
          const Spacer(),
          FilledButton.icon(icon: const Icon(Icons.add, size: 16), label: const Text('Neuer Vorschlag', style: TextStyle(fontSize: 12)),
            style: FilledButton.styleFrom(backgroundColor: Colors.indigo.shade600, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero),
            onPressed: () => _showVorschlagDialog(ctx, null, (v) async {
              await widget.apiService.saveArbeitsagenturVorschlag(widget.userId, v);
              await _loadFromDB();
              if (mounted) setState(() {});
            })),
        ]),
        const SizedBox(height: 12),
        if (vorschlaege.isEmpty)
          Container(width: double.infinity, padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
            child: Column(children: [Icon(Icons.work_off, size: 36, color: Colors.grey.shade400), const SizedBox(height: 8), Text('Keine Vermittlungsvorschläge', style: TextStyle(fontSize: 12, color: Colors.grey.shade500))]))
        else
          ...vorschlaege.map((v) {
            final status = v['status']?.toString() ?? '';
            final statusColor = status == 'beworben' ? Colors.blue : status == 'eingeladen' ? Colors.orange : status == 'abgelehnt' ? Colors.red : status == 'eingestellt' ? Colors.green : Colors.grey;
            final frist = v['frist']?.toString() ?? '';
            int? fristTage;
            if (frist.isNotEmpty) { try { final p = frist.split('.'); final d = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0])); fristTage = d.difference(DateTime.now()).inDays; } catch (_) {} }
            return Container(margin: const EdgeInsets.only(bottom: 8), decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.indigo.shade200)),
              child: InkWell(borderRadius: BorderRadius.circular(8), onTap: () => _showVorschlagDetailModal(ctx, v),
                child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(v['stelle']?.toString() ?? 'Ohne Bezeichnung', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade800))),
                    if (status.isNotEmpty) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: statusColor.shade100, borderRadius: BorderRadius.circular(8)),
                      child: Text(status[0].toUpperCase() + status.substring(1), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor.shade800))),
                    const SizedBox(width: 4),
                    IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      onPressed: () async { await widget.apiService.deleteArbeitsagenturVorschlag(widget.userId, v['id'] is int ? v['id'] : int.parse(v['id'].toString())); await _loadFromDB(); if (mounted) setState(() {}); }),
                  ]),
                  if ((v['arbeitgeber']?.toString() ?? '').isNotEmpty) Text(v['arbeitgeber'].toString(), style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                  if ((v['ansprechpartner_name']?.toString() ?? '').isNotEmpty) Text('${v['ansprechpartner_anrede'] ?? ''} ${v['ansprechpartner_name']}'.trim(), style: TextStyle(fontSize: 11, color: Colors.indigo.shade400)),
                  Row(children: [
                    if ((v['datum']?.toString() ?? '').isNotEmpty) ...[Icon(Icons.edit_calendar, size: 11, color: Colors.grey.shade500), const SizedBox(width: 4), Text(v['datum'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)), const SizedBox(width: 8)],
                    if ((v['datum_erhalten']?.toString() ?? '').isNotEmpty) ...[Icon(Icons.markunread_mailbox, size: 11, color: Colors.blue.shade400), const SizedBox(width: 4), Text(v['datum_erhalten'].toString(), style: TextStyle(fontSize: 11, color: Colors.blue.shade600)), const SizedBox(width: 8)],
                    if ((v['ort']?.toString() ?? '').isNotEmpty) ...[Icon(Icons.location_on, size: 11, color: Colors.grey.shade500), const SizedBox(width: 4), Text(v['ort'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade600))],
                    if (fristTage != null) ...[const Spacer(), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: fristTage < 0 ? Colors.red.shade100 : fristTage <= 3 ? Colors.orange.shade100 : Colors.green.shade100, borderRadius: BorderRadius.circular(4)),
                      child: Text(fristTage < 0 ? 'Frist abgelaufen' : '$fristTage Tage', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: fristTage < 0 ? Colors.red.shade800 : fristTage <= 3 ? Colors.orange.shade800 : Colors.green.shade800)))],
                  ]),
                ]))));
          }),
      ]));
    });
  }

  void _showVorschlagDetailModal(BuildContext ctx, Map<String, dynamic> v) {
    final color = Colors.indigo;
    showDialog(context: ctx, builder: (dlgCtx) => DefaultTabController(length: 3, child: StatefulBuilder(builder: (dlgCtx, setDlg) {
      final status = v['status']?.toString() ?? '';
      final statusColor = status == 'beworben' ? Colors.blue : status == 'eingeladen' ? Colors.orange : status == 'abgelehnt' ? Colors.red : status == 'eingestellt' ? Colors.green : Colors.grey;
      return AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
        contentPadding: EdgeInsets.zero,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.work_outline, size: 18, color: color.shade700), const SizedBox(width: 8),
            Expanded(child: Text(v['stelle']?.toString() ?? 'Vermittlungsvorschlag', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color.shade800), overflow: TextOverflow.ellipsis)),
            if (status.isNotEmpty) Container(margin: const EdgeInsets.only(right: 4), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: statusColor.shade100, borderRadius: BorderRadius.circular(8)),
              child: Text(status[0].toUpperCase() + status.substring(1), style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: statusColor.shade800))),
            IconButton(icon: Icon(Icons.edit, size: 16, color: color.shade400), tooltip: 'Bearbeiten', onPressed: () {
              Navigator.pop(dlgCtx);
              _showVorschlagDialog(ctx, v, (updated) async {
                await widget.apiService.saveArbeitsagenturVorschlag(widget.userId, updated);
                await _loadFromDB();
                if (mounted) setState(() {});
              });
            }),
            IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.pop(dlgCtx)),
          ]),
          const SizedBox(height: 4),
          TabBar(labelColor: color.shade700, unselectedLabelColor: Colors.grey.shade500, indicatorColor: color.shade700, tabs: const [
            Tab(icon: Icon(Icons.info_outline, size: 16), text: 'Details'),
            Tab(icon: Icon(Icons.timeline, size: 16), text: 'Verlauf'),
            Tab(icon: Icon(Icons.email, size: 16), text: 'Korrespondenz'),
          ]),
        ]),
        content: SizedBox(width: 550, height: 450, child: TabBarView(children: [
          // ═══ TAB 1: Details ═══
          SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _vdSection(Icons.business, 'Arbeitgeber', color, [
              _vdRow('Firma', v['arbeitgeber'], Icons.business),
              _vdRow('Ort', v['ort'], Icons.location_on),
            ]),
            if ((v['ansprechpartner_name']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              _vdSection(Icons.person, 'Ansprechpartner', Colors.teal, [
                _vdRow('Name', '${v['ansprechpartner_anrede'] ?? ''} ${v['ansprechpartner_name'] ?? ''}'.trim(), Icons.person),
                if ((v['ansprechpartner_tel']?.toString() ?? '').isNotEmpty) _vdRow('Telefon', v['ansprechpartner_tel'], Icons.phone),
                if ((v['ansprechpartner_email']?.toString() ?? '').isNotEmpty) _vdRow('E-Mail', v['ansprechpartner_email'], Icons.email),
              ]),
            ],
            const SizedBox(height: 10),
            _vdSection(Icons.work, 'Stelle', Colors.blue, [
              _vdRow('Position', v['stelle'], Icons.work),
              _vdRow('Status', status.isNotEmpty ? status[0].toUpperCase() + status.substring(1) : '—', Icons.flag),
            ]),
            if ((v['frist']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              Builder(builder: (_) {
                final frist = v['frist'].toString();
                int? left; try { final p = frist.split('.'); final d = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0])); left = d.difference(DateTime.now()).inDays; } catch (_) {}
                return Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: (left != null && left < 0) ? Colors.red.shade50 : Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: (left != null && left < 0) ? Colors.red.shade200 : Colors.orange.shade200)),
                  child: Row(children: [
                    Icon(Icons.timer, size: 16, color: Colors.orange.shade700), const SizedBox(width: 8),
                    Text('Frist: $frist', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                    if (left != null) ...[const SizedBox(width: 8), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: left < 0 ? Colors.red.shade100 : left <= 1 ? Colors.orange.shade100 : Colors.green.shade100, borderRadius: BorderRadius.circular(4)),
                      child: Text(left < 0 ? 'Abgelaufen!' : left == 0 ? 'Heute!' : '$left Tage', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: left < 0 ? Colors.red.shade800 : left <= 1 ? Colors.orange.shade800 : Colors.green.shade800)))],
                  ]));
              }),
            ],
            if ((v['bewerbung_datum']?.toString() ?? '').isNotEmpty || (v['bewerbung_art']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              _vdSection(Icons.send, 'Bewerbung', Colors.green, [
                if ((v['bewerbung_datum']?.toString() ?? '').isNotEmpty) _vdRow('Datum', v['bewerbung_datum'], Icons.calendar_today),
                if ((v['bewerbung_art']?.toString() ?? '').isNotEmpty) _vdRow('Art', v['bewerbung_art'], Icons.send),
                if ((v['ergebnis']?.toString() ?? '').isNotEmpty) _vdRow('Ergebnis', v['ergebnis'], Icons.flag),
              ]),
            ],
            if ((v['notiz']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Notiz', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
                  const SizedBox(height: 4),
                  Text(v['notiz'].toString(), style: const TextStyle(fontSize: 12)),
                ])),
            ],
          ])),
          // ═══ TAB 2: Verlauf ═══
          _VorschlagVerlaufTab(apiService: widget.apiService, userId: widget.userId, vorschlag: v, ticketService: widget.ticketService, adminMnr: widget.adminMitgliedernummer, memberMnr: widget.memberMitgliedernummer, memberName: widget.memberName),
          // ═══ TAB 3: Korrespondenz ═══
          _VorschlagKorrTab(apiService: widget.apiService, userId: widget.userId, vorschlagId: v['id'] is int ? v['id'] : int.parse(v['id'].toString())),
        ])),
      );
    })));
  }

  Widget _vdSection(IconData icon, String title, MaterialColor c, List<Widget> children) {
    return Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: c.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: c.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, size: 14, color: c.shade700), const SizedBox(width: 6), Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.shade700))]),
        const SizedBox(height: 6),
        ...children,
      ]));
  }

  Widget _vdRow(String label, dynamic value, IconData icon) {
    final val = value?.toString() ?? '';
    if (val.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: 3), child: Row(children: [
      Icon(icon, size: 12, color: Colors.grey.shade500), const SizedBox(width: 6),
      Text('$label: ', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      Expanded(child: Text(val, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
    ]));
  }

  void _showVorschlagDialog(BuildContext ctx, Map<String, dynamic>? existing, Future<void> Function(Map<String, dynamic>) onSave) {
    final isEdit = existing != null;
    final datumC = TextEditingController(text: existing?['datum']?.toString() ?? '');
    final erhaltenC = TextEditingController(text: existing?['datum_erhalten']?.toString() ?? '');
    final fristC = TextEditingController(text: existing?['frist']?.toString() ?? '');
    final arbeitgeberC = TextEditingController(text: existing?['arbeitgeber']?.toString() ?? '');
    final stelleC = TextEditingController(text: existing?['stelle']?.toString() ?? '');
    final ortC = TextEditingController(text: existing?['ort']?.toString() ?? '');
    String apAnrede = existing?['ansprechpartner_anrede']?.toString() ?? '';
    final apNameC = TextEditingController(text: existing?['ansprechpartner_name']?.toString() ?? '');
    final apTelC = TextEditingController(text: existing?['ansprechpartner_tel']?.toString() ?? '');
    final apEmailC = TextEditingController(text: existing?['ansprechpartner_email']?.toString() ?? '');
    final bewDatumC = TextEditingController(text: existing?['bewerbung_datum']?.toString() ?? '');
    final notizC = TextEditingController(text: existing?['notiz']?.toString() ?? '');
    String status = existing?['status']?.toString() ?? 'offen';
    String bewArt = existing?['bewerbung_art']?.toString() ?? '';
    String ergebnis = existing?['ergebnis']?.toString() ?? '';

    void calcFrist(StateSetter setDlg) {
      if (erhaltenC.text.isNotEmpty) {
        try {
          final p = erhaltenC.text.split('.');
          final d = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
          final frist = d.add(const Duration(days: 3));
          setDlg(() => fristC.text = '${frist.day.toString().padLeft(2, '0')}.${frist.month.toString().padLeft(2, '0')}.${frist.year}');
        } catch (_) {}
      }
    }

    showDialog(context: ctx, builder: (dlgCtx) => StatefulBuilder(builder: (dlgCtx, setDlg) => AlertDialog(
      title: Row(children: [Icon(Icons.work_outline, size: 18, color: Colors.indigo.shade700), const SizedBox(width: 8), Text(isEdit ? 'Vorschlag bearbeiten' : 'Neuer Vermittlungsvorschlag', style: const TextStyle(fontSize: 14))]),
      content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _dateField('Datum erstellt (auf dem Schreiben)', datumC, dlgCtx),
        const SizedBox(height: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Datum erhalten (Post)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          TextField(controller: erhaltenC, readOnly: true, decoration: InputDecoration(hintText: 'TT.MM.JJJJ', prefixIcon: const Icon(Icons.markunread_mailbox, size: 20), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
            onTap: () async {
              final picked = await showDatePicker(context: dlgCtx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de'));
              if (picked != null) { erhaltenC.text = '${picked.day.toString().padLeft(2, '0')}.${picked.month.toString().padLeft(2, '0')}.${picked.year}'; calcFrist(setDlg); }
            }),
        ]),
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade200)),
          child: Row(children: [
            Icon(Icons.timer, size: 16, color: Colors.orange.shade700), const SizedBox(width: 8),
            Text('Frist (3 Tage): ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange.shade700)),
            Text(fristC.text.isNotEmpty ? fristC.text : '—', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
            if (fristC.text.isNotEmpty) ...[const SizedBox(width: 8),
              Builder(builder: (_) { try { final p = fristC.text.split('.'); final d = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0])); final left = d.difference(DateTime.now()).inDays; return Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: left < 0 ? Colors.red.shade100 : left <= 1 ? Colors.orange.shade100 : Colors.green.shade100, borderRadius: BorderRadius.circular(4)),
                child: Text(left < 0 ? 'Abgelaufen!' : left == 0 ? 'Heute!' : '$left Tage', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: left < 0 ? Colors.red.shade800 : left <= 1 ? Colors.orange.shade800 : Colors.green.shade800))); } catch (_) { return const SizedBox.shrink(); } }),
            ],
          ])),
        const SizedBox(height: 12),
        const SizedBox(height: 12),
        _buildArbeitgeberSearch(arbeitgeberC, ortC, setDlg, getApAnrede: () => apAnrede, setApAnrede: (v) => apAnrede = v, apNameC: apNameC, apTelC: apTelC, apEmailC: apEmailC),
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Ansprechpartner', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            Row(children: [
              ChoiceChip(label: const Text('Frau', style: TextStyle(fontSize: 11)), selected: apAnrede == 'Frau', selectedColor: Colors.pink.shade100, onSelected: (_) => setDlg(() => apAnrede = 'Frau')),
              const SizedBox(width: 6),
              ChoiceChip(label: const Text('Herr', style: TextStyle(fontSize: 11)), selected: apAnrede == 'Herr', selectedColor: Colors.blue.shade100, onSelected: (_) => setDlg(() => apAnrede = 'Herr')),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: apNameC, decoration: InputDecoration(hintText: 'Name', prefixIcon: const Icon(Icons.person, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)), style: const TextStyle(fontSize: 13))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: apTelC, decoration: InputDecoration(hintText: 'Telefon', prefixIcon: const Icon(Icons.phone, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)), style: const TextStyle(fontSize: 13))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: apEmailC, decoration: InputDecoration(hintText: 'E-Mail', prefixIcon: const Icon(Icons.email, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)), style: const TextStyle(fontSize: 13))),
            ]),
          ])),
        const SizedBox(height: 12),
        _buildStelleSearch(stelleC, setDlg),
        const SizedBox(height: 12),
        _textField('Ort', ortC, hint: 'z.B. Ulm', icon: Icons.location_on),
        const SizedBox(height: 12),
        Text('Status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(initialValue: status, isExpanded: true,
          decoration: InputDecoration(isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
          items: const [
            DropdownMenuItem(value: 'offen', child: Text('Offen', style: TextStyle(fontSize: 13))),
            DropdownMenuItem(value: 'beworben', child: Text('Beworben', style: TextStyle(fontSize: 13))),
            DropdownMenuItem(value: 'eingeladen', child: Text('Eingeladen (Vorstellungsgespräch)', style: TextStyle(fontSize: 13))),
            DropdownMenuItem(value: 'abgelehnt', child: Text('Abgelehnt', style: TextStyle(fontSize: 13))),
            DropdownMenuItem(value: 'absage_ag', child: Text('Absage vom Arbeitgeber', style: TextStyle(fontSize: 13))),
            DropdownMenuItem(value: 'eingestellt', child: Text('Eingestellt', style: TextStyle(fontSize: 13))),
            DropdownMenuItem(value: 'nicht_beworben', child: Text('Nicht beworben', style: TextStyle(fontSize: 13))),
          ], onChanged: (v) => setDlg(() => status = v ?? 'offen')),
        if (status == 'beworben' || status == 'eingeladen' || status == 'eingestellt') ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _dateField('Bewerbung am', bewDatumC, dlgCtx)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Bewerbungsart', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(initialValue: bewArt.isEmpty ? null : bewArt, isExpanded: true,
                decoration: InputDecoration(isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                hint: const Text('Auswählen...', style: TextStyle(fontSize: 13)),
                items: const [
                  DropdownMenuItem(value: 'online', child: Text('Online', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 'email', child: Text('E-Mail', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 'post', child: Text('Post', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 'persoenlich', child: Text('Persönlich', style: TextStyle(fontSize: 13))),
                ], onChanged: (v) => setDlg(() => bewArt = v ?? '')),
            ])),
          ]),
        ],
        if (status == 'abgelehnt' || status == 'absage_ag' || status == 'eingestellt') ...[
          const SizedBox(height: 12),
          Text('Ergebnis', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(initialValue: ergebnis.isEmpty ? null : ergebnis, isExpanded: true,
            decoration: InputDecoration(isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
            hint: const Text('Auswählen...', style: TextStyle(fontSize: 13)),
            items: const [
              DropdownMenuItem(value: 'nicht_passend', child: Text('Stelle nicht passend', style: TextStyle(fontSize: 13))),
              DropdownMenuItem(value: 'gesundheitlich', child: Text('Gesundheitliche Gründe', style: TextStyle(fontSize: 13))),
              DropdownMenuItem(value: 'entfernung', child: Text('Zu weit entfernt', style: TextStyle(fontSize: 13))),
              DropdownMenuItem(value: 'qualifikation', child: Text('Qualifikation fehlt', style: TextStyle(fontSize: 13))),
              DropdownMenuItem(value: 'absage_ag', child: Text('Absage vom Arbeitgeber', style: TextStyle(fontSize: 13))),
              DropdownMenuItem(value: 'eingestellt', child: Text('Eingestellt', style: TextStyle(fontSize: 13))),
              DropdownMenuItem(value: 'sonstiges', child: Text('Sonstiges', style: TextStyle(fontSize: 13))),
            ], onChanged: (v) => setDlg(() => ergebnis = v ?? '')),
        ],
        const SizedBox(height: 12),
        _textField('Notiz', notizC, hint: 'Bemerkungen...', icon: Icons.notes, maxLines: 2),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          Navigator.pop(dlgCtx);
          final data = <String, dynamic>{
            if (isEdit) 'id': existing['id'],
            'datum': datumC.text.trim(), 'datum_erhalten': erhaltenC.text.trim(), 'arbeitgeber': arbeitgeberC.text.trim(),
            'ansprechpartner_anrede': apAnrede, 'ansprechpartner_name': apNameC.text.trim(), 'ansprechpartner_tel': apTelC.text.trim(), 'ansprechpartner_email': apEmailC.text.trim(),
            'stelle': stelleC.text.trim(), 'ort': ortC.text.trim(),
            'frist': fristC.text.trim(), 'status': status, 'bewerbung_datum': bewDatumC.text.trim(), 'bewerbung_art': bewArt, 'ergebnis': ergebnis, 'notiz': notizC.text.trim(),
          };
          await onSave(data);
        }, child: const Text('Speichern')),
      ],
    )));
  }

  Future<void> _syncTermineToDB(List<Map<String, dynamic>> updated) async {
    final existingIds = _dbTermine.map((t) => t['id'] as int?).where((id) => id != null).toSet();
    final updatedIds = <int>{};
    for (final termin in updated) {
      final id = termin['id'] is int ? termin['id'] as int : 0;
      if (id > 0) updatedIds.add(id);
      await widget.apiService.saveArbeitsagenturTermin(widget.userId, termin);
    }
    for (final oldId in existingIds) {
      if (!updatedIds.contains(oldId)) {
        await widget.apiService.deleteArbeitsagenturTermin(widget.userId, oldId!);
      }
    }
    await _loadFromDB();
  }

  Future<void> _syncBegutachtungenToDB(List<Map<String, dynamic>> updated) async {
    final existingIds = _dbBegutachtungen.map((b) => b['id'] as int?).where((id) => id != null).toSet();
    final updatedIds = <int>{};
    for (final beg in updated) {
      final id = beg['id'] is int ? beg['id'] as int : 0;
      if (id > 0) updatedIds.add(id);
      await widget.apiService.saveArbeitsagenturBegutachtung(widget.userId, beg);
    }
    for (final oldId in existingIds) {
      if (!updatedIds.contains(oldId)) {
        await widget.apiService.deleteArbeitsagenturBegutachtung(widget.userId, oldId!);
      }
    }
    await _loadFromDB();
  }
}

// ═══════════════════════════════════════════════════════
// ARBEITSAGENTUR KORRESPONDENZ (Eingang / Ausgang)
// ═══════════════════════════════════════════════════════
class _AAKorrespondenzSection extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  const _AAKorrespondenzSection({required this.apiService, required this.userId});
  @override
  State<_AAKorrespondenzSection> createState() => _AAKorrespondenzState();
}

class _AAKorrespondenzState extends State<_AAKorrespondenzSection> {
  List<Map<String, dynamic>> _docs = [];
  bool _isLoading = true;
  String _filter = 'alle';

  @override
  void initState() {
    super.initState();
    _loadDocs();
  }

  Future<void> _loadDocs() async {
    setState(() => _isLoading = true);
    try {
      final res = await widget.apiService.getAAKorrespondenz(widget.userId);
      if (res['success'] == true && res['data'] is List) {
        _docs = (res['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      debugPrint('[AAKorr] load error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _addKorrespondenz(String richtung) async {
    final datumErstelltC = TextEditingController();
    final datumKundeC = TextEditingController();
    final datumWirC = TextEditingController(text: DateFormat('dd.MM.yyyy').format(DateTime.now()));
    final betreffC = TextEditingController();
    final notizC = TextEditingController();
    String methode = richtung == 'eingang' ? 'post' : 'email';
    List<PlatformFile> selectedFiles = [];

    final confirmed = await showDialog<bool>(context: context, builder: (dlgCtx) => StatefulBuilder(
      builder: (dlgCtx, setDlg) => AlertDialog(
        title: Row(children: [
          Icon(richtung == 'eingang' ? Icons.call_received : Icons.call_made, size: 18, color: richtung == 'eingang' ? Colors.green.shade700 : Colors.blue.shade700),
          const SizedBox(width: 8),
          Text(richtung == 'eingang' ? 'Eingang hinzufügen' : 'Ausgang hinzufügen', style: const TextStyle(fontSize: 14)),
        ]),
        content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final m in [('email', 'E-Mail', Icons.email), ('post', 'Post', Icons.mail), ('telefon', 'Telefon', Icons.phone), ('fax', 'Fax', Icons.fax), ('online', 'Online-Portal', Icons.language)])
              ChoiceChip(
                label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(m.$3, size: 13, color: methode == m.$1 ? Colors.white : Colors.grey.shade700), const SizedBox(width: 4), Text(m.$2, style: TextStyle(fontSize: 10, color: methode == m.$1 ? Colors.white : Colors.grey.shade700))]),
                selected: methode == m.$1, selectedColor: Colors.indigo.shade600,
                onSelected: (_) => setDlg(() => methode = m.$1),
              ),
          ]),
          const SizedBox(height: 12),
          TextFormField(controller: datumErstelltC, readOnly: true, decoration: InputDecoration(labelText: 'Datum Bescheid erstellt', prefixIcon: Icon(Icons.edit_calendar, size: 16, color: Colors.blue.shade600), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async {
              final p = await showDatePicker(context: dlgCtx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de'));
              if (p != null) setDlg(() => datumErstelltC.text = DateFormat('dd.MM.yyyy').format(p));
            }))),
          const SizedBox(height: 10),
          TextFormField(controller: datumKundeC, readOnly: true, decoration: InputDecoration(labelText: 'Datum Kunde erhalten', prefixIcon: Icon(Icons.person, size: 16, color: Colors.orange.shade600), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async {
              final p = await showDatePicker(context: dlgCtx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de'));
              if (p != null) setDlg(() => datumKundeC.text = DateFormat('dd.MM.yyyy').format(p));
            }))),
          const SizedBox(height: 10),
          TextFormField(controller: datumWirC, readOnly: true, decoration: InputDecoration(labelText: 'Datum wir erhalten', prefixIcon: Icon(Icons.business, size: 16, color: Colors.teal.shade600), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async {
              final p = await showDatePicker(context: dlgCtx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de'));
              if (p != null) setDlg(() => datumWirC.text = DateFormat('dd.MM.yyyy').format(p));
            }))),
          const SizedBox(height: 10),
          TextFormField(controller: betreffC, decoration: InputDecoration(labelText: 'Betreff / Titel *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 10),
          TextFormField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: Icon(Icons.attach_file, size: 16, color: Colors.teal.shade600),
            label: Text(selectedFiles.isEmpty ? 'Dokumente anhängen (max. 20)' : '${selectedFiles.length} Datei${selectedFiles.length > 1 ? 'en' : ''} ausgewählt', style: TextStyle(fontSize: 12, color: Colors.teal.shade700)),
            style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.teal.shade300)),
            onPressed: () async {
              final result = await FilePickerHelper.pickFiles(allowMultiple: true, type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
              if (result != null) {
                setDlg(() {
                  selectedFiles.addAll(result.files);
                  if (selectedFiles.length > 20) selectedFiles = selectedFiles.sublist(0, 20);
                });
              }
            },
          ),
          if (selectedFiles.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...selectedFiles.asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Icon(Icons.description, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Expanded(child: Text(e.value.name, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
                Text('${(e.value.size / 1024).toStringAsFixed(0)} KB', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                IconButton(icon: Icon(Icons.close, size: 14, color: Colors.red.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: () => setDlg(() => selectedFiles.removeAt(e.key))),
              ]),
            )),
          ],
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () {
            if (betreffC.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Betreff angeben'), backgroundColor: Colors.orange));
              return;
            }
            Navigator.pop(dlgCtx, true);
          }, child: const Text('Speichern')),
        ],
      ),
    ));

    if (confirmed != true) return;

    try {
      int ok = 0, fail = 0;
      final gId = const Uuid().v4();
      if (selectedFiles.isEmpty) {
        final res = await widget.apiService.uploadAAKorrespondenz(userId: widget.userId, richtung: richtung, titel: betreffC.text.trim(), datum: datumErstelltC.text, datumErstellt: datumErstelltC.text, datumKundeErhalten: datumKundeC.text, datumWirErhalten: datumWirC.text, betreff: betreffC.text.trim(), notiz: notizC.text.trim(), methode: methode, gruppeId: gId);
        if (res['success'] == true) { ok++; } else { fail++; }
      } else {
        for (final f in selectedFiles) {
          if (f.path == null) continue;
          final res = await widget.apiService.uploadAAKorrespondenz(userId: widget.userId, richtung: richtung, titel: betreffC.text.trim(), datum: datumErstelltC.text, datumErstellt: datumErstelltC.text, datumKundeErhalten: datumKundeC.text, datumWirErhalten: datumWirC.text, betreff: betreffC.text.trim(), notiz: notizC.text.trim(), methode: methode, gruppeId: gId, filePath: f.path!, fileName: f.name);
          if (res['success'] == true) { ok++; } else { fail++; }
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(fail > 0 ? '$ok gespeichert, $fail fehlgeschlagen' : '${ok > 1 ? '$ok Dokumente' : 'Korrespondenz'} gespeichert'), backgroundColor: fail > 0 ? Colors.orange : Colors.green));
      }
      _loadDocs();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    }
  }

  void _showKorrDetailDialog(List<Map<String, dynamic>> docGroup, Map<String, dynamic> first, List<Map<String, dynamic>> files) {
    final isEingang = first['richtung'] == 'eingang';
    final color = isEingang ? Colors.green : Colors.blue;
    final gruppeId = first['gruppe_id']?.toString();
    const mLabels = {'email': 'E-Mail', 'post': 'Post', 'telefon': 'Telefon', 'fax': 'Fax', 'online': 'Portal'};
    final m = first['methode']?.toString() ?? 'post';
    // Search date fields on any record in group (not just first)
    String dErstellt = '', dKunde = '', dWir = '';
    for (final d in docGroup) {
      if (dErstellt.isEmpty && (d['datum_erstellt']?.toString() ?? '').isNotEmpty) dErstellt = d['datum_erstellt'].toString();
      if (dKunde.isEmpty && (d['datum_kunde_erhalten']?.toString() ?? '').isNotEmpty) dKunde = d['datum_kunde_erhalten'].toString();
      if (dWir.isEmpty && (d['datum_wir_erhalten']?.toString() ?? '').isNotEmpty) dWir = d['datum_wir_erhalten'].toString();
    }
    String wFrist = '';
    if (dKunde.isNotEmpty) { try { DateTime k; if (dKunde.contains('.')) { final p = dKunde.split('.'); k = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0])); } else { k = DateTime.parse(dKunde); } wFrist = DateFormat('dd.MM.yyyy').format(DateTime(k.year, k.month + 1, k.day)); } catch (_) {} }
    Map<String, dynamic> wData = {};
    // Search widerspruch_data on ANY record in the group
    for (final d in docGroup) {
      try {
        final raw = d['widerspruch_data'];
        if (raw is String && raw.isNotEmpty) {
          wData = Map<String, dynamic>.from(jsonDecode(raw) as Map);
          break;
        } else if (raw is Map && raw.isNotEmpty) {
          wData = Map<String, dynamic>.from(raw);
          break;
        }
      } catch (_) {}
    }
    final hasW = wData.isNotEmpty;
    final kFiles = docGroup.where((d) => (d['file_name']?.toString() ?? '').isNotEmpty && (d['doc_type']?.toString() ?? 'korrespondenz') == 'korrespondenz').toList();
    final wFiles = docGroup.where((d) => d['doc_type'] == 'widerspruch' && (d['file_name']?.toString() ?? '').isNotEmpty).toList();
    final ebFiles = docGroup.where((d) => d['doc_type'] == 'eingangsbestaetigung' && (d['file_name']?.toString() ?? '').isNotEmpty).toList();

    showDialog(context: context, builder: (dlgCtx) => DefaultTabController(length: 3, child: AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      contentPadding: EdgeInsets.zero,
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(isEingang ? Icons.call_received : Icons.call_made, size: 18, color: color.shade700),
          const SizedBox(width: 8),
          Expanded(child: Text(first['betreff']?.toString() ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color.shade800), overflow: TextOverflow.ellipsis)),
          if (hasW) Container(margin: const EdgeInsets.only(right: 4), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.gavel, size: 10, color: Colors.red.shade700), const SizedBox(width: 3), Text('W', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.red.shade700))])),
          IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400), tooltip: 'Löschen', onPressed: () async { Navigator.pop(dlgCtx); for (final d in docGroup) { await widget.apiService.deleteAAKorrespondenz(d['id'] is int ? d['id'] : int.parse(d['id'].toString())); } _loadDocs(); }),
          IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.pop(dlgCtx)),
        ]),
        const SizedBox(height: 4),
        TabBar(labelColor: color.shade700, unselectedLabelColor: Colors.grey.shade500, indicatorColor: color.shade700, tabs: [
          const Tab(icon: Icon(Icons.info_outline, size: 16), text: 'Details'),
          Tab(icon: const Icon(Icons.folder_open, size: 16), text: 'Unterlagen (${kFiles.length})'),
          Tab(icon: Icon(Icons.gavel, size: 16, color: hasW ? Colors.red.shade600 : null), text: 'Widerspruch'),
        ]),
      ]),
      content: SizedBox(width: 550, height: 450, child: TabBarView(children: [
        // ═══ TAB 1: Details ═══
        SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _korrInfoRow(isEingang ? Icons.call_received : Icons.call_made, 'Richtung', isEingang ? 'Eingang' : 'Ausgang', isEingang ? Colors.green : Colors.blue),
            _korrInfoRow(Icons.mail, 'Methode', mLabels[m] ?? m, Colors.indigo),
            if (dErstellt.isNotEmpty) _korrInfoRow(Icons.edit_calendar, 'Bescheid erstellt', dErstellt, Colors.blue),
            if (dKunde.isNotEmpty) _korrInfoRow(Icons.person, 'Kunde erhalten', dKunde, Colors.orange),
            if (dWir.isNotEmpty) _korrInfoRow(Icons.business, 'Wir erhalten', dWir, Colors.teal),
            if (wFrist.isNotEmpty) ...[
              const Divider(height: 12),
              Row(children: [
                Icon(Icons.gavel, size: 14, color: Colors.red.shade600), const SizedBox(width: 8),
                Text('Widerspruchsfrist: ', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                Text(wFrist, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
                const SizedBox(width: 6),
                Builder(builder: (_) { try { final p = wFrist.split('.'); final d = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0])); final left = d.difference(DateTime.now()).inDays; final exp = left < 0; return Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: exp ? Colors.red.shade100 : (left <= 7 ? Colors.orange.shade100 : Colors.green.shade100), borderRadius: BorderRadius.circular(4)), child: Text(exp ? 'Abgelaufen!' : '$left Tage', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: exp ? Colors.red.shade800 : (left <= 7 ? Colors.orange.shade800 : Colors.green.shade800)))); } catch (_) { return const SizedBox.shrink(); } }),
              ]),
            ],
          ])),
          if ((first['notiz']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
              child: Text(first['notiz'].toString(), style: const TextStyle(fontSize: 12))),
          ],
        ])),

        // ═══ TAB 2: Unterlagen ═══
        SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.folder_open, size: 16, color: Colors.teal.shade700), const SizedBox(width: 6),
            Text('Unterlagen', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
            const Spacer(),
            OutlinedButton.icon(icon: Icon(Icons.upload_file, size: 14, color: Colors.teal.shade600), label: Text('Hinzufügen', style: TextStyle(fontSize: 11, color: Colors.teal.shade600)),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero, side: BorderSide(color: Colors.teal.shade300)),
              onPressed: () async {
                final result = await FilePickerHelper.pickFiles(allowMultiple: true, type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
                if (result == null || result.files.isEmpty) return;
                final gId = gruppeId ?? const Uuid().v4();
                for (final f in result.files) { if (f.path == null) continue; await widget.apiService.uploadAAKorrespondenz(userId: widget.userId, richtung: first['richtung']?.toString() ?? 'eingang', titel: first['titel']?.toString() ?? '', datum: first['datum']?.toString() ?? '', betreff: first['betreff']?.toString() ?? '', notiz: '', methode: m, gruppeId: gId, filePath: f.path!, fileName: f.name); }
                _loadDocs(); if (dlgCtx.mounted) Navigator.pop(dlgCtx);
              }),
          ]),
          const SizedBox(height: 10),
          if (kFiles.isEmpty) Container(width: double.infinity, padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)), child: Text('Keine Unterlagen', style: TextStyle(fontSize: 12, color: Colors.grey.shade400), textAlign: TextAlign.center))
          else ...kFiles.map((f) => Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
            child: Row(children: [
              Icon(Icons.description, size: 16, color: Colors.grey.shade500), const SizedBox(width: 8),
              Expanded(child: Text(f['file_name'].toString(), style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
              IconButton(icon: Icon(Icons.visibility, size: 16, color: Colors.indigo.shade500), tooltip: 'Ansehen', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28), onPressed: () => _viewDoc(f['id'] is int ? f['id'] : int.parse(f['id'].toString()), f['file_name'].toString())),
              IconButton(icon: Icon(Icons.download, size: 16, color: Colors.teal.shade600), tooltip: 'Download', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28), onPressed: () => _downloadDoc(f['id'] is int ? f['id'] : int.parse(f['id'].toString()), f['file_name'].toString())),
            ]))),
        ])),

        // ═══ TAB 3: Widerspruch ═══
        SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (hasW) ...[
            // ── Schritt 1: Vorbereitet ──
            _wStep(Icons.description, '1. Widerspruch vorbereitet', Colors.red, true, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if ((wData['datum']?.toString() ?? '').isNotEmpty) _korrInfoRow(Icons.calendar_today, 'Datum', wData['datum'].toString(), Colors.red),
              if ((wData['frist']?.toString() ?? '').isNotEmpty) _korrInfoRow(Icons.timer, 'Frist', wData['frist'].toString(), Colors.orange),
              if ((wData['grund']?.toString() ?? '').isNotEmpty) ...[const SizedBox(height: 4), Text('Begründung: ${wData['grund']}', style: TextStyle(fontSize: 11, color: Colors.grey.shade700))],
              if (wFiles.isNotEmpty) ...[const SizedBox(height: 6),
                ...wFiles.map((f) => Padding(padding: const EdgeInsets.only(bottom: 3), child: Row(children: [
                  Icon(Icons.description, size: 14, color: Colors.red.shade400), const SizedBox(width: 6),
                  Expanded(child: Text(f['file_name'].toString(), style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
                  IconButton(icon: Icon(Icons.visibility, size: 14, color: Colors.indigo.shade500), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24), onPressed: () => _viewDoc(f['id'] is int ? f['id'] : int.parse(f['id'].toString()), f['file_name'].toString())),
                  IconButton(icon: Icon(Icons.download, size: 14, color: Colors.teal.shade600), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24), onPressed: () => _downloadDoc(f['id'] is int ? f['id'] : int.parse(f['id'].toString()), f['file_name'].toString())),
                ]))),
              ],
            ])),
            const SizedBox(height: 8),
            // ── Schritt 2: Gedruckt? ──
            _wStep(Icons.print, '2. Gedruckt?', Colors.blue, wData['gedruckt'] == true, Row(children: [
              Icon(wData['gedruckt'] == true ? Icons.check_circle : Icons.cancel, size: 16, color: wData['gedruckt'] == true ? Colors.green.shade700 : Colors.grey.shade400),
              const SizedBox(width: 6),
              Text(wData['gedruckt'] == true ? 'Ja${(wData['gedruckt_datum']?.toString() ?? '').isNotEmpty ? ' – ${wData['gedruckt_datum']}' : ''}' : 'Noch nicht gedruckt', style: TextStyle(fontSize: 12, color: wData['gedruckt'] == true ? Colors.green.shade700 : Colors.grey.shade500)),
            ])),
            const SizedBox(height: 8),
            // ── Schritt 3: Unterschrieben? ──
            _wStep(Icons.draw, '3. Kunde unterschrieben?', Colors.purple, wData['unterschrieben'] == true, Row(children: [
              Icon(wData['unterschrieben'] == true ? Icons.check_circle : Icons.cancel, size: 16, color: wData['unterschrieben'] == true ? Colors.green.shade700 : Colors.grey.shade400),
              const SizedBox(width: 6),
              Text(wData['unterschrieben'] == true ? 'Ja${(wData['unterschrieben_datum']?.toString() ?? '').isNotEmpty ? ' – ${wData['unterschrieben_datum']}' : ''}' : 'Noch nicht unterschrieben', style: TextStyle(fontSize: 12, color: wData['unterschrieben'] == true ? Colors.green.shade700 : Colors.grey.shade500)),
            ])),
            const SizedBox(height: 8),
            // ── Schritt 4: Versendet ──
            _wStep(Icons.send, '4. Versendet / Abgegeben', Colors.indigo, (wData['versandart']?.toString() ?? '').isNotEmpty, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if ((wData['versandart']?.toString() ?? '').isNotEmpty) _korrInfoRow(Icons.send, 'Versandart', wData['versandart'].toString(), Colors.indigo),
              if ((wData['abgabe_datum']?.toString() ?? '').isNotEmpty) _korrInfoRow(Icons.calendar_today, 'Versanddatum', wData['abgabe_datum'].toString(), Colors.indigo),
              if ((wData['versandart']?.toString() ?? '').isEmpty) Text('Noch nicht versendet', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ])),
            const SizedBox(height: 8),
            // ── Schritt 5: Eingangsbestätigung ──
            _wStep(Icons.verified, '5. Eingangsbestätigung', Colors.green, wData['eingangsbestaetigung'] == true, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(wData['eingangsbestaetigung'] == true ? Icons.check_circle : Icons.cancel, size: 16, color: wData['eingangsbestaetigung'] == true ? Colors.green.shade700 : Colors.grey.shade400),
                const SizedBox(width: 6),
                Text(wData['eingangsbestaetigung'] == true ? 'Erhalten' : 'Noch nicht erhalten', style: TextStyle(fontSize: 12, color: wData['eingangsbestaetigung'] == true ? Colors.green.shade700 : Colors.grey.shade500)),
              ]),
              if (ebFiles.isNotEmpty) ...[const SizedBox(height: 6),
                ...ebFiles.map((f) => Padding(padding: const EdgeInsets.only(bottom: 3), child: Row(children: [
                  Icon(Icons.description, size: 14, color: Colors.green.shade400), const SizedBox(width: 6),
                  Expanded(child: Text(f['file_name'].toString(), style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
                  IconButton(icon: Icon(Icons.visibility, size: 14, color: Colors.indigo.shade500), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24), onPressed: () => _viewDoc(f['id'] is int ? f['id'] : int.parse(f['id'].toString()), f['file_name'].toString())),
                  IconButton(icon: Icon(Icons.download, size: 14, color: Colors.teal.shade600), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24), onPressed: () => _downloadDoc(f['id'] is int ? f['id'] : int.parse(f['id'].toString()), f['file_name'].toString())),
                ]))),
              ],
            ])),
            const SizedBox(height: 12),
          ],
          // Create/Edit Widerspruch button
          OutlinedButton.icon(icon: Icon(hasW ? Icons.edit : Icons.add, size: 14, color: Colors.red.shade600),
            label: Text(hasW ? 'Widerspruch bearbeiten' : 'Widerspruch erstellen', style: TextStyle(fontSize: 11, color: Colors.red.shade600)),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero, side: BorderSide(color: Colors.red.shade300)),
            onPressed: () {
              final wDatumC = TextEditingController(text: wData['datum']?.toString() ?? DateFormat('dd.MM.yyyy').format(DateTime.now()));
              final wFristC = TextEditingController(text: wData['frist']?.toString() ?? wFrist);
              final wGrundC = TextEditingController(text: wData['grund']?.toString() ?? '');
              bool wGedruckt = wData['gedruckt'] == true;
              final wGedrucktDatumC = TextEditingController(text: wData['gedruckt_datum']?.toString() ?? '');
              bool wUnterschrieben = wData['unterschrieben'] == true;
              final wUnterschriebenDatumC = TextEditingController(text: wData['unterschrieben_datum']?.toString() ?? '');
              String wVersandart = ''; List<PlatformFile> newWDocs = []; List<PlatformFile> newEbDocs = [];
              final wAbgabeC = TextEditingController(text: wData['abgabe_datum']?.toString() ?? '');
              bool wEb = wData['eingangsbestaetigung'] == true;
              if ((wData['versandart']?.toString() ?? '').isNotEmpty) { const rev = {'Online': 'online', 'Post': 'post', 'Persönlich': 'persoenlich', 'Fax': 'fax'}; wVersandart = rev[wData['versandart']] ?? ''; }

              showDialog(context: dlgCtx, builder: (wCtx) => StatefulBuilder(builder: (wCtx, setW) => AlertDialog(
                title: Row(children: [Icon(Icons.gavel, size: 18, color: Colors.red.shade700), const SizedBox(width: 8), const Expanded(child: Text('Widerspruch', style: TextStyle(fontSize: 14)))]),
                content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Step 1
                  Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade200)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [Icon(Icons.description, size: 16, color: Colors.red.shade700), const SizedBox(width: 6), Text('1. Widerspruch vorbereiten', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red.shade700))]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(child: TextFormField(controller: wDatumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', prefixIcon: const Icon(Icons.calendar_today, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async { final p = await showDatePicker(context: wCtx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de')); if (p != null) wDatumC.text = DateFormat('dd.MM.yyyy').format(p); })))),
                        const SizedBox(width: 8),
                        Expanded(child: TextFormField(controller: wFristC, readOnly: true, decoration: InputDecoration(labelText: 'Frist bis', prefixIcon: Icon(Icons.timer, size: 16, color: Colors.orange.shade600), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async { final p = await showDatePicker(context: wCtx, initialDate: DateTime.now().add(const Duration(days: 30)), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de')); if (p != null) wFristC.text = DateFormat('dd.MM.yyyy').format(p); })))),
                      ]),
                      const SizedBox(height: 10),
                      TextFormField(controller: wGrundC, maxLines: 3, decoration: InputDecoration(labelText: 'Begründung', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(icon: Icon(Icons.upload_file, size: 14, color: Colors.red.shade600), label: Text(newWDocs.isEmpty ? 'Widerspruch-Dokumente' : '${newWDocs.length} Dok.', style: TextStyle(fontSize: 11, color: Colors.red.shade700)), style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.red.shade300)),
                        onPressed: () async { final r = await FilePickerHelper.pickFiles(allowMultiple: true, type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']); if (r != null) setW(() { newWDocs.addAll(r.files); }); }),
                      ...newWDocs.asMap().entries.map((e) => Padding(padding: const EdgeInsets.only(top: 3), child: Row(children: [Icon(Icons.description, size: 13, color: Colors.red.shade400), const SizedBox(width: 6), Expanded(child: Text(e.value.name, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)), IconButton(icon: Icon(Icons.close, size: 14, color: Colors.red.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24), onPressed: () => setW(() => newWDocs.removeAt(e.key)))]))),
                    ])),
                  const SizedBox(height: 10),
                  // Step 2: Gedruckt
                  InkWell(onTap: () => setW(() => wGedruckt = !wGedruckt), borderRadius: BorderRadius.circular(8),
                    child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(color: wGedruckt ? Colors.blue.shade50 : Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: wGedruckt ? Colors.blue.shade300 : Colors.grey.shade200)),
                      child: Row(children: [
                        Icon(wGedruckt ? Icons.check_box : Icons.check_box_outline_blank, size: 18, color: wGedruckt ? Colors.blue.shade700 : Colors.grey.shade400), const SizedBox(width: 8),
                        Text('2. Gedruckt', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: wGedruckt ? Colors.blue.shade800 : Colors.grey.shade600)),
                        if (wGedruckt) ...[const Spacer(), SizedBox(width: 130, height: 32, child: TextFormField(controller: wGedrucktDatumC, readOnly: true, style: const TextStyle(fontSize: 11), decoration: InputDecoration(hintText: 'Datum', isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                          suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 12), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24), onPressed: () async { final p = await showDatePicker(context: wCtx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de')); if (p != null) setW(() => wGedrucktDatumC.text = DateFormat('dd.MM.yyyy').format(p)); }))))],
                      ]))),
                  const SizedBox(height: 8),
                  // Step 3: Unterschrieben
                  InkWell(onTap: () => setW(() => wUnterschrieben = !wUnterschrieben), borderRadius: BorderRadius.circular(8),
                    child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(color: wUnterschrieben ? Colors.purple.shade50 : Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: wUnterschrieben ? Colors.purple.shade300 : Colors.grey.shade200)),
                      child: Row(children: [
                        Icon(wUnterschrieben ? Icons.check_box : Icons.check_box_outline_blank, size: 18, color: wUnterschrieben ? Colors.purple.shade700 : Colors.grey.shade400), const SizedBox(width: 8),
                        Text('3. Kunde unterschrieben', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: wUnterschrieben ? Colors.purple.shade800 : Colors.grey.shade600)),
                        if (wUnterschrieben) ...[const Spacer(), SizedBox(width: 130, height: 32, child: TextFormField(controller: wUnterschriebenDatumC, readOnly: true, style: const TextStyle(fontSize: 11), decoration: InputDecoration(hintText: 'Datum', isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                          suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 12), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24), onPressed: () async { final p = await showDatePicker(context: wCtx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de')); if (p != null) setW(() => wUnterschriebenDatumC.text = DateFormat('dd.MM.yyyy').format(p)); }))))],
                      ]))),
                  const SizedBox(height: 10),
                  // Step 4: Versand
                  Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.indigo.shade200)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [Icon(Icons.send, size: 16, color: Colors.indigo.shade700), const SizedBox(width: 6), Text('2. Versand', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)), const Spacer(), Text('(optional)', style: TextStyle(fontSize: 9, color: Colors.grey.shade500))]),
                      const SizedBox(height: 10),
                      Wrap(spacing: 6, runSpacing: 4, children: [for (final v in <(String, String, IconData, MaterialColor)>[('online', 'Online', Icons.language, Colors.blue), ('post', 'Post', Icons.mail, Colors.brown), ('persoenlich', 'Persönlich', Icons.person, Colors.green), ('fax', 'Fax', Icons.fax, Colors.grey)])
                        ChoiceChip(label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(v.$3, size: 13, color: wVersandart == v.$1 ? Colors.white : v.$4.shade700), const SizedBox(width: 4), Text(v.$2, style: TextStyle(fontSize: 10, color: wVersandart == v.$1 ? Colors.white : v.$4.shade700))]), selected: wVersandart == v.$1, selectedColor: v.$4.shade600, onSelected: (_) => setW(() => wVersandart = wVersandart == v.$1 ? '' : v.$1))]),
                      const SizedBox(height: 10),
                      TextFormField(controller: wAbgabeC, readOnly: true, decoration: InputDecoration(labelText: 'Abgabe / Versand', prefixIcon: Icon(Icons.send, size: 16, color: Colors.indigo.shade600), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async { final p = await showDatePicker(context: wCtx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de')); if (p != null) wAbgabeC.text = DateFormat('dd.MM.yyyy').format(p); }))),
                      const SizedBox(height: 10),
                      InkWell(onTap: () => setW(() => wEb = !wEb), borderRadius: BorderRadius.circular(8), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(color: wEb ? Colors.green.shade50 : Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: wEb ? Colors.green.shade300 : Colors.grey.shade200)),
                        child: Row(children: [Icon(wEb ? Icons.check_box : Icons.check_box_outline_blank, size: 18, color: wEb ? Colors.green.shade700 : Colors.grey.shade400), const SizedBox(width: 8), Expanded(child: Text('Eingangsbestätigung erhalten', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: wEb ? Colors.green.shade800 : Colors.grey.shade700)))]))),
                      if (wEb) ...[const SizedBox(height: 8),
                        OutlinedButton.icon(icon: Icon(Icons.attach_file, size: 14, color: Colors.green.shade600), label: Text(newEbDocs.isEmpty ? 'EB anhängen' : '${newEbDocs.length} Datei(en)', style: TextStyle(fontSize: 11, color: Colors.green.shade700)), style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.green.shade300)),
                          onPressed: () async { final r = await FilePickerHelper.pickFiles(allowMultiple: true, type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']); if (r != null) setW(() { newEbDocs.addAll(r.files); }); }),
                        ...newEbDocs.asMap().entries.map((e) => Padding(padding: const EdgeInsets.only(top: 3), child: Row(children: [Icon(Icons.description, size: 13, color: Colors.green.shade500), const SizedBox(width: 6), Expanded(child: Text(e.value.name, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)), IconButton(icon: Icon(Icons.close, size: 14, color: Colors.red.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24), onPressed: () => setW(() => newEbDocs.removeAt(e.key)))]))),
                      ],
                    ])),
                ]))),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(wCtx), child: const Text('Abbrechen')),
                  FilledButton.icon(icon: const Icon(Icons.gavel, size: 14), label: const Text('Speichern'), style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
                    onPressed: () async {
                      Navigator.pop(wCtx);
                      final fId = first['id'] is int ? first['id'] : int.parse(first['id'].toString());
                      final gId = gruppeId ?? const Uuid().v4();
                      const vLabels = {'online': 'Online', 'post': 'Post', 'persoenlich': 'Persönlich', 'fax': 'Fax'};
                      await widget.apiService.updateAAWiderspruch(fId, {'datum': wDatumC.text, 'frist': wFristC.text, 'grund': wGrundC.text.trim(), 'gedruckt': wGedruckt, 'gedruckt_datum': wGedrucktDatumC.text, 'unterschrieben': wUnterschrieben, 'unterschrieben_datum': wUnterschriebenDatumC.text, 'versandart': wVersandart.isNotEmpty ? (vLabels[wVersandart] ?? wVersandart) : '', 'abgabe_datum': wAbgabeC.text, 'eingangsbestaetigung': wEb});
                      for (final f in newWDocs) { if (f.path == null) continue; await widget.apiService.uploadAAKorrespondenz(userId: widget.userId, richtung: first['richtung']?.toString() ?? 'eingang', titel: first['titel']?.toString() ?? '', datum: first['datum']?.toString() ?? '', betreff: first['betreff']?.toString() ?? '', notiz: '', methode: m, gruppeId: gId, docType: 'widerspruch', filePath: f.path!, fileName: f.name); }
                      for (final f in newEbDocs) { if (f.path == null) continue; await widget.apiService.uploadAAKorrespondenz(userId: widget.userId, richtung: first['richtung']?.toString() ?? 'eingang', titel: first['titel']?.toString() ?? '', datum: first['datum']?.toString() ?? '', betreff: first['betreff']?.toString() ?? '', notiz: '', methode: m, gruppeId: gId, docType: 'eingangsbestaetigung', filePath: f.path!, fileName: f.name); }
                      _loadDocs(); if (dlgCtx.mounted) { ScaffoldMessenger.of(dlgCtx).showSnackBar(const SnackBar(content: Text('Widerspruch gespeichert'), backgroundColor: Colors.green)); Navigator.pop(dlgCtx); }
                    }),
                ],
              )));
            }),
          const SizedBox(height: 10),
          Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.shade100)),
            child: Row(children: [Icon(Icons.info_outline, size: 14, color: Colors.red.shade400), const SizedBox(width: 8), Expanded(child: Text('Widerspruchsfrist: In der Regel 1 Monat nach Zustellung.', style: TextStyle(fontSize: 11, color: Colors.red.shade700)))])),
        ])),
      ])),
    )));
  }

  Future<void> _viewDoc(int docId, String fileName) async {
    try {
      final response = await widget.apiService.downloadAAKorrespondenzDoc(docId);
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        if (mounted) FileViewerDialog.showFromBytes(context, response.bodyBytes, fileName);
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler (${response.statusCode})'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _downloadDoc(int docId, String fileName) async {
    try {
      final response = await widget.apiService.downloadAAKorrespondenzDoc(docId);
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        final String downloadsPath;
        if (Platform.isMacOS) {
          downloadsPath = '${Platform.environment['HOME']}/Downloads';
        } else if (Platform.isWindows) {
          downloadsPath = '${Platform.environment['USERPROFILE']}\\Downloads';
        } else {
          downloadsPath = Directory.systemTemp.path;
        }
        var destFile = File('$downloadsPath${Platform.pathSeparator}$fileName');
        int counter = 1;
        while (destFile.existsSync()) {
          final ext = fileName.contains('.') ? '.${fileName.split('.').last}' : '';
          final base = fileName.contains('.') ? fileName.substring(0, fileName.lastIndexOf('.')) : fileName;
          destFile = File('$downloadsPath${Platform.pathSeparator}${base}_($counter)$ext');
          counter++;
        }
        await destFile.writeAsBytes(response.bodyBytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$fileName gespeichert'), backgroundColor: Colors.green, duration: const Duration(seconds: 3),
            action: SnackBarAction(label: 'Öffnen', textColor: Colors.white, onPressed: () { Process.run('open', [destFile.path]); })));
        }
        Process.run('open', [destFile.path]);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    }
  }

  Widget _wStep(IconData icon, String title, MaterialColor c, bool done, Widget content) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: done ? c.shade50 : Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: done ? c.shade300 : Colors.grey.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: done ? c.shade700 : Colors.grey.shade400),
          const SizedBox(width: 6),
          Expanded(child: Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: done ? c.shade700 : Colors.grey.shade500))),
          Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, size: 16, color: done ? Colors.green.shade600 : Colors.grey.shade300),
        ]),
        const SizedBox(height: 6),
        content,
      ]),
    );
  }

  Widget _korrInfoRow(IconData icon, String label, String value, MaterialColor c) {
    return Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(children: [
      Icon(icon, size: 14, color: c.shade600), const SizedBox(width: 8),
      Text('$label: ', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.shade800)),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));

    // Group docs by gruppe_id
    final filteredRaw = _filter == 'alle' ? _docs : _docs.where((d) => d['richtung'] == _filter).toList();
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final doc in filteredRaw) {
      final gId = doc['gruppe_id']?.toString() ?? 'single_${doc['id']}';
      grouped.putIfAbsent(gId, () => []).add(doc);
    }
    final groups = grouped.values.toList();
    final eingangCount = grouped.values.where((g) => g.first['richtung'] == 'eingang').length;
    final ausgangCount = grouped.values.where((g) => g.first['richtung'] == 'ausgang').length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 8),
      Row(children: [
        Icon(Icons.email, size: 20, color: Colors.teal.shade700),
        const SizedBox(width: 8),
        Text('Korrespondenz', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
        const Spacer(),
        FilledButton.icon(
          icon: const Icon(Icons.call_received, size: 14),
          label: const Text('Eingang', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.green.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _addKorrespondenz('eingang'),
        ),
        const SizedBox(width: 6),
        FilledButton.icon(
          icon: const Icon(Icons.call_made, size: 14),
          label: const Text('Ausgang', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _addKorrespondenz('ausgang'),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        ChoiceChip(label: Text('Alle (${_docs.length})', style: TextStyle(fontSize: 10, color: _filter == 'alle' ? Colors.white : Colors.grey.shade700)), selected: _filter == 'alle', selectedColor: Colors.teal.shade600, onSelected: (_) => setState(() => _filter = 'alle')),
        const SizedBox(width: 6),
        ChoiceChip(label: Text('Eingang ($eingangCount)', style: TextStyle(fontSize: 10, color: _filter == 'eingang' ? Colors.white : Colors.green.shade700)), selected: _filter == 'eingang', selectedColor: Colors.green.shade600, onSelected: (_) => setState(() => _filter = 'eingang')),
        const SizedBox(width: 6),
        ChoiceChip(label: Text('Ausgang ($ausgangCount)', style: TextStyle(fontSize: 10, color: _filter == 'ausgang' ? Colors.white : Colors.blue.shade700)), selected: _filter == 'ausgang', selectedColor: Colors.blue.shade600, onSelected: (_) => setState(() => _filter = 'ausgang')),
      ]),
      const SizedBox(height: 10),

      if (groups.isEmpty)
        Container(
          width: double.infinity, padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
          child: Column(children: [
            Icon(Icons.email_outlined, size: 36, color: Colors.grey.shade300),
            const SizedBox(height: 6),
            Text('Keine Korrespondenz vorhanden', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
          ]),
        )
      else
        ...groups.map((docGroup) {
          final first = docGroup.first;
          final isEingang = first['richtung'] == 'eingang';
          final color = isEingang ? Colors.green : Colors.blue;
          const methodeIcons = {'email': Icons.email, 'post': Icons.mail, 'telefon': Icons.phone, 'fax': Icons.fax, 'online': Icons.language};
          const methodeLabels = {'email': 'E-Mail', 'post': 'Post', 'telefon': 'Telefon', 'fax': 'Fax', 'online': 'Portal'};
          final m = first['methode']?.toString() ?? 'post';
          final datumStr = first['datum']?.toString() ?? '';
          final datumFmt = datumStr.isNotEmpty ? (() { try { return DateFormat('dd.MM.yyyy').format(DateTime.parse(datumStr)); } catch (_) { return datumStr; } })() : '';
          final files = docGroup.where((d) => (d['file_name']?.toString() ?? '').isNotEmpty).toList();

          return InkWell(
            onTap: () => _showKorrDetailDialog(docGroup, first, files),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: color.shade200)),
              child: Row(children: [
                Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: color.shade100, borderRadius: BorderRadius.circular(8)),
                  child: Icon(isEingang ? Icons.call_received : Icons.call_made, size: 18, color: color.shade700)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(first['betreff']?.toString() ?? first['titel']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color.shade800), overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 8),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: color.shade100, borderRadius: BorderRadius.circular(4)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(methodeIcons[m] ?? Icons.mail, size: 10, color: color.shade700), const SizedBox(width: 3), Text(methodeLabels[m] ?? m, style: TextStyle(fontSize: 9, color: color.shade700))])),
                    if (files.isNotEmpty) ...[const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.attach_file, size: 10, color: Colors.grey.shade600), const SizedBox(width: 2), Text('${files.length}', style: TextStyle(fontSize: 9, color: Colors.grey.shade700))]))],
                  ]),
                  Text(datumFmt, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ])),
                Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
              ]),
            ),
          );
        }),
    ]);
  }
}

// ═══════════════════════════════════════════════════════
// VORSCHLAG VERLAUF TAB (loads korrespondenz for timeline)
// ═══════════════════════════════════════════════════════
class _VorschlagVerlaufTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final Map<String, dynamic> vorschlag;
  final TicketService? ticketService;
  final String adminMnr;
  final String memberMnr;
  final String memberName;
  const _VorschlagVerlaufTab({required this.apiService, required this.userId, required this.vorschlag, this.ticketService, this.adminMnr = '', this.memberMnr = '', this.memberName = ''});
  @override
  State<_VorschlagVerlaufTab> createState() => _VorschlagVerlaufTabState();
}

class _VorschlagVerlaufTabState extends State<_VorschlagVerlaufTab> {
  List<Map<String, dynamic>> _korr = [];
  bool _loaded = false;
  bool _wartenAbgelaufen = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final vid = widget.vorschlag['id'] is int ? widget.vorschlag['id'] : int.parse(widget.vorschlag['id'].toString());
      final res = await widget.apiService.getArbeitsagenturVorschlagKorr(widget.userId, vid);
      if (res['success'] == true && res['data'] is List) {
        _korr = (res['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
    _checkAutoTicket();
  }

  Future<void> _checkAutoTicket() async {
    final v = widget.vorschlag;
    final status = v['status']?.toString() ?? '';
    if (['eingestellt', 'abgelehnt', 'absage_ag'].contains(status)) return;
    final existingTicket = v['erinnerung_ticket_id']?.toString() ?? '';

    DateTime? lastAusgang;
    for (final k in _korr) {
      if (k['richtung'] == 'ausgang' && (k['datum']?.toString() ?? '').isNotEmpty) {
        try { final p = k['datum'].toString().split('.'); final d = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0])); if (lastAusgang == null || d.isAfter(lastAusgang)) lastAusgang = d; } catch (_) {}
      }
    }
    if (lastAusgang == null) return;
    final frist = lastAusgang.add(const Duration(days: 14));
    if (!frist.isBefore(DateTime.now())) return;
    if (existingTicket.isNotEmpty) return;

    final ts = widget.ticketService;
    if (ts == null || widget.adminMnr.isEmpty || widget.memberMnr.isEmpty) return;
    final stelle = v['stelle']?.toString() ?? 'Vermittlungsvorschlag';
    final ag = v['arbeitgeber']?.toString() ?? '';
    try {
      final result = await ts.createTicketForMember(
        adminMitgliedernummer: widget.adminMnr,
        memberMitgliedernummer: widget.memberMnr,
        subject: 'Erinnerung: Keine Antwort von $ag ($stelle)',
        message: 'Die 14-Tage-Frist für den Vermittlungsvorschlag "$stelle" bei $ag ist abgelaufen.\n\nBitte Arbeitgeber erneut kontaktieren und Rückmeldung anfordern.\n\nMitglied: ${widget.memberName}',
        priority: 'high',
        scheduledDate: '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}',
        systemAuto: true,
      );
      if (result.containsKey('ticket')) {
        final vid = v['id'] is int ? v['id'] as int : int.parse(v['id'].toString());
        await widget.apiService.setArbeitsagenturErinnerungTicket(widget.userId, vid, 'auto');
        v['erinnerung_ticket_id'] = 'auto';
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final v = widget.vorschlag;
    final events = <(String date, IconData icon, String title, String subtitle, MaterialColor color)>[];
    final datum = v['datum']?.toString() ?? '';
    final erhalten = v['datum_erhalten']?.toString() ?? '';
    final frist = v['frist']?.toString() ?? '';
    final status = v['status']?.toString() ?? '';
    final ergebnis = v['ergebnis']?.toString() ?? '';
    const mLabels = {'email': 'E-Mail', 'post': 'Post', 'online': 'Online', 'persoenlich': 'Persönlich', 'fax': 'Fax', 'telefon': 'Telefon'};

    DateTime? parseDate(String d) { if (d.isEmpty) return null; try { final p = d.split('.'); return DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0])); } catch (_) { return null; } }

    if (datum.isNotEmpty) events.add((datum, Icons.edit_calendar, 'Vermittlungsvorschlag erstellt', 'Datum auf dem Schreiben', Colors.grey));
    if (erhalten.isNotEmpty) events.add((erhalten, Icons.markunread_mailbox, 'Per Post erhalten', 'Eingang beim Mitglied', Colors.blue));

    final hasKorr = _korr.isNotEmpty;
    if (frist.isNotEmpty) {
      if (hasKorr) {
        events.add((frist, Icons.check_circle, 'Bewerbungsfrist eingehalten', 'Frist wurde eingehalten', Colors.green));
      } else {
        int? left; try { final d = parseDate(frist); left = d?.difference(DateTime.now()).inDays; } catch (_) {}
        events.add((frist, Icons.timer, 'Bewerbungsfrist (3 Tage)', left != null && left < 0 ? 'Abgelaufen!' : left != null ? 'Noch $left Tage' : '', Colors.orange));
      }
    }

    DateTime? lastAusgangDate;
    final sortedKorr = List<Map<String, dynamic>>.from(_korr)..sort((a, b) {
      final da = parseDate(a['datum']?.toString() ?? '');
      final db = parseDate(b['datum']?.toString() ?? '');
      if (da == null && db == null) return (a['id'] as int? ?? 0).compareTo(b['id'] as int? ?? 0);
      if (da == null) return 1;
      if (db == null) return -1;
      final cmp = da.compareTo(db);
      return cmp != 0 ? cmp : (a['id'] as int? ?? 0).compareTo(b['id'] as int? ?? 0);
    });
    for (final k in sortedKorr) {
      final kDatum = k['datum']?.toString() ?? '';
      final kRichtung = k['richtung']?.toString() ?? '';
      final kMethode = k['methode']?.toString() ?? '';
      final kBetreff = k['betreff']?.toString() ?? '';
      final isAusgang = kRichtung == 'ausgang';
      events.add((kDatum, isAusgang ? Icons.call_made : Icons.call_received, '${isAusgang ? "Ausgang" : "Eingang"}: $kBetreff', kMethode.isNotEmpty ? 'per ${mLabels[kMethode] ?? kMethode}' : '', isAusgang ? Colors.blue : Colors.green));
      if (isAusgang && kDatum.isNotEmpty) {
        final d = parseDate(kDatum);
        if (d != null && (lastAusgangDate == null || d.isAfter(lastAusgangDate))) lastAusgangDate = d;
      }
    }

    if (lastAusgangDate != null && status != 'eingestellt' && status != 'abgelehnt' && status != 'absage_ag') {
      final wartenBis = lastAusgangDate.add(const Duration(days: 14));
      final wartenStr = '${wartenBis.day.toString().padLeft(2, '0')}.${wartenBis.month.toString().padLeft(2, '0')}.${wartenBis.year}';
      final left = wartenBis.difference(DateTime.now()).inDays;
      final sub = left < 0 ? 'Frist abgelaufen — Erinnerung an Arbeitgeber senden!' : 'Noch $left Tage (14-Tage-Frist)';
      events.add((wartenStr, Icons.hourglass_top, 'Warten auf Antwort vom Arbeitgeber', sub, left < 0 ? Colors.red : Colors.purple));
    }
    _wartenAbgelaufen = lastAusgangDate != null && status != 'eingestellt' && status != 'abgelehnt' && status != 'absage_ag' && lastAusgangDate.add(const Duration(days: 14)).isBefore(DateTime.now());

    final vgDatum = v['vorstellungsgespraech_datum']?.toString() ?? '';
    final eDatum = v['eingestellt_datum']?.toString() ?? '';
    final aDatum = v['abgelehnt_datum']?.toString() ?? '';
    final aaDatum = v['absage_ag_datum']?.toString() ?? '';
    if (vgDatum.isNotEmpty || status == 'eingeladen') events.add((vgDatum, Icons.event, 'Vorstellungsgespräch', 'Einladung erhalten', Colors.purple));
    if (eDatum.isNotEmpty || status == 'eingestellt') events.add((eDatum, Icons.check_circle, 'Eingestellt', ergebnis.isNotEmpty ? ergebnis : 'Stelle angenommen', Colors.green));
    if (aDatum.isNotEmpty || status == 'abgelehnt') events.add((aDatum, Icons.cancel, 'Abgelehnt', ergebnis.isNotEmpty ? ergebnis : '', Colors.red));
    if (aaDatum.isNotEmpty || status == 'absage_ag') events.add((aaDatum, Icons.block, 'Absage vom Arbeitgeber', ergebnis.isNotEmpty ? ergebnis : '', Colors.red));
    if (status == 'nicht_beworben') events.add(('', Icons.do_not_disturb, 'Nicht beworben', ergebnis.isNotEmpty ? ergebnis : '', Colors.grey));

    events.sort((a, b) { final da = parseDate(a.$1); final db = parseDate(b.$1); if (da == null && db == null) return 0; if (da == null) return 1; if (db == null) return -1; return da.compareTo(db); });

    if (events.isEmpty) return Center(child: Text('Noch keine Einträge', style: TextStyle(color: Colors.grey.shade500)));

    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Chronologischer Verlauf', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
        const Spacer(),
        FilledButton.icon(icon: const Icon(Icons.add, size: 14), label: const Text('Ereignis', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.indigo.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _addStatusEvent(v)),
      ]),
      const SizedBox(height: 12),
      ...events.asMap().entries.map((entry) {
        final i = entry.key;
        final e = entry.value;
        final isLast = i == events.length - 1;
        return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 30, child: Column(children: [
            Container(width: 24, height: 24, decoration: BoxDecoration(color: e.$5.shade100, shape: BoxShape.circle, border: Border.all(color: e.$5.shade400, width: 2)),
              child: Icon(e.$2, size: 12, color: e.$5.shade700)),
            if (!isLast) Expanded(child: Container(width: 2, color: Colors.grey.shade300)),
          ])),
          const SizedBox(width: 10),
          Expanded(child: Container(margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: e.$5.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: e.$5.shade200)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(e.$3, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: e.$5.shade800))),
                if (e.$1.isNotEmpty) Text(e.$1, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: e.$5.shade600)),
              ]),
              if (e.$4.isNotEmpty) Text(e.$4, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ]))),
        ]));
      }),
      if (_wartenAbgelaufen) ...[
        const SizedBox(height: 8),
        Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.shade300)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(Icons.warning_amber, size: 18, color: Colors.red.shade700), const SizedBox(width: 8),
              Expanded(child: Text('14-Tage-Frist abgelaufen — Erinnerung an Arbeitgeber senden', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red.shade800)))]),
            const SizedBox(height: 8),
            Text('Neuen Ausgang in Korrespondenz erstellen um den Arbeitgeber zu erinnern. Danach beginnt eine neue 14-Tage-Frist.', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
          ])),
      ],
    ]));
  }

  Future<void> _addStatusEvent(Map<String, dynamic> v) async {
    final vid = v['id'] is int ? v['id'] as int : int.parse(v['id'].toString());
    String selectedEvent = '';
    final datumC = TextEditingController();

    final ok = await showDialog<bool>(context: context, builder: (dlgCtx) => StatefulBuilder(builder: (dlgCtx, setDlg) => AlertDialog(
      title: Row(children: [Icon(Icons.flag, size: 18, color: Colors.indigo.shade700), const SizedBox(width: 8), const Text('Ereignis hinzufügen', style: TextStyle(fontSize: 14))]),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Was ist passiert?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 8),
        ...[ ('eingeladen', 'Vorstellungsgespräch', Icons.event, Colors.purple),
             ('eingestellt', 'Eingestellt', Icons.check_circle, Colors.green),
             ('abgelehnt', 'Abgelehnt (von uns)', Icons.cancel, Colors.red),
             ('absage_ag', 'Absage vom Arbeitgeber', Icons.block, Colors.red),
        ].map((e) => Padding(padding: const EdgeInsets.only(bottom: 4), child: InkWell(
          onTap: () => setDlg(() => selectedEvent = e.$1),
          borderRadius: BorderRadius.circular(8),
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: selectedEvent == e.$1 ? (e.$4 as Color).withValues(alpha: 0.1) : Colors.grey.shade50, borderRadius: BorderRadius.circular(8),
              border: Border.all(color: selectedEvent == e.$1 ? (e.$4 as Color).withValues(alpha: 0.5) : Colors.grey.shade200, width: selectedEvent == e.$1 ? 2 : 1)),
            child: Row(children: [Icon(e.$3, size: 18, color: e.$4 as Color), const SizedBox(width: 10), Text(e.$2, style: TextStyle(fontSize: 13, fontWeight: selectedEvent == e.$1 ? FontWeight.bold : FontWeight.normal))]))))),
        const SizedBox(height: 12),
        Text('Datum', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        TextField(controller: datumC, readOnly: true, decoration: InputDecoration(hintText: 'TT.MM.JJJJ', prefixIcon: const Icon(Icons.calendar_today, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
          onTap: () async {
            final p = await showDatePicker(context: dlgCtx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de'));
            if (p != null) datumC.text = '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}';
          }),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: const Text('Abbrechen')),
        FilledButton(onPressed: () {
          if (selectedEvent.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Ereignis auswählen'), backgroundColor: Colors.orange)); return; }
          Navigator.pop(dlgCtx, true);
        }, child: const Text('Speichern')),
      ],
    )));

    if (ok != true) return;
    const fieldMap = {'eingeladen': 'vorstellungsgespraech_datum', 'eingestellt': 'eingestellt_datum', 'abgelehnt': 'abgelehnt_datum', 'absage_ag': 'absage_ag_datum'};
    await widget.apiService.updateArbeitsagenturVorschlagStatus(widget.userId, vid, selectedEvent, dateField: fieldMap[selectedEvent] ?? '', eventDatum: datumC.text.trim());
    v['status'] = selectedEvent;
    if (fieldMap.containsKey(selectedEvent)) v[fieldMap[selectedEvent]!] = datumC.text.trim();
    await _load();
  }
}

// ═══════════════════════════════════════════════════════
// VORSCHLAG KORRESPONDENZ TAB
// ═══════════════════════════════════════════════════════
class _VorschlagKorrTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int vorschlagId;
  const _VorschlagKorrTab({required this.apiService, required this.userId, required this.vorschlagId});
  @override
  State<_VorschlagKorrTab> createState() => _VorschlagKorrTabState();
}

class _VorschlagKorrTabState extends State<_VorschlagKorrTab> {
  List<Map<String, dynamic>> _korr = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await widget.apiService.getArbeitsagenturVorschlagKorr(widget.userId, widget.vorschlagId);
      if (res['success'] == true && res['data'] is List) {
        _korr = (res['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addKorr(String richtung) async {
    final datumC = TextEditingController();
    final betreffC = TextEditingController();
    final notizC = TextEditingController();
    String methode = 'email';
    List<PlatformFile> files = [];

    final ok = await showDialog<bool>(context: context, builder: (dlgCtx) => StatefulBuilder(builder: (dlgCtx, setDlg) => AlertDialog(
      title: Row(children: [
        Icon(richtung == 'eingang' ? Icons.call_received : Icons.call_made, size: 18, color: richtung == 'eingang' ? Colors.green.shade700 : Colors.blue.shade700),
        const SizedBox(width: 8),
        Text(richtung == 'eingang' ? 'Eingang' : 'Ausgang', style: const TextStyle(fontSize: 14)),
      ]),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final m in [('email', 'E-Mail', Icons.email), ('post', 'Post', Icons.mail), ('online', 'Online', Icons.language), ('persoenlich', 'Persönlich', Icons.person), ('fax', 'Fax', Icons.fax), ('telefon', 'Telefon', Icons.phone)])
            ChoiceChip(label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(m.$3, size: 13, color: methode == m.$1 ? Colors.white : Colors.grey.shade700), const SizedBox(width: 4), Text(m.$2, style: TextStyle(fontSize: 10, color: methode == m.$1 ? Colors.white : Colors.grey.shade700))]),
              selected: methode == m.$1, selectedColor: Colors.indigo.shade600, onSelected: (_) => setDlg(() => methode = m.$1)),
        ]),
        const SizedBox(height: 12),
        TextFormField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', prefixIcon: const Icon(Icons.calendar_today, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async {
            final p = await showDatePicker(context: dlgCtx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de'));
            if (p != null) setDlg(() => datumC.text = '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}');
          }))),
        const SizedBox(height: 10),
        TextFormField(controller: betreffC, decoration: InputDecoration(labelText: 'Betreff *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 10),
        TextFormField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 12),
        OutlinedButton.icon(icon: Icon(Icons.attach_file, size: 16, color: Colors.teal.shade600),
          label: Text(files.isEmpty ? 'Dokumente anhängen' : '${files.length} Datei(en)', style: TextStyle(fontSize: 12, color: Colors.teal.shade700)),
          style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.teal.shade300)),
          onPressed: () async {
            final r = await FilePickerHelper.pickFiles(allowMultiple: true, type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
            if (r != null) setDlg(() { files.addAll(r.files); if (files.length > 20) files = files.sublist(0, 20); });
          }),
        if (files.isNotEmpty) ...files.asMap().entries.map((e) => Padding(padding: const EdgeInsets.only(top: 3), child: Row(children: [
          Icon(Icons.description, size: 13, color: Colors.grey.shade500), const SizedBox(width: 6),
          Expanded(child: Text(e.value.name, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
          IconButton(icon: Icon(Icons.close, size: 14, color: Colors.red.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24), onPressed: () => setDlg(() => files.removeAt(e.key))),
        ]))),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: const Text('Abbrechen')),
        FilledButton(onPressed: () {
          if (betreffC.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Betreff angeben'), backgroundColor: Colors.orange)); return; }
          Navigator.pop(dlgCtx, true);
        }, child: const Text('Speichern')),
      ],
    )));

    if (ok != true) return;
    try {
      final res = await widget.apiService.saveArbeitsagenturVorschlagKorr(widget.userId, widget.vorschlagId, {'richtung': richtung, 'methode': methode, 'datum': datumC.text.trim(), 'betreff': betreffC.text.trim(), 'notiz': notizC.text.trim()});
      final korrId = res['id'];
      if (korrId != null && files.isNotEmpty) {
        for (final f in files) {
          if (f.path == null) continue;
          await widget.apiService.uploadKorrAttachment(modul: 'aa_vorschlag', korrespondenzId: korrId is int ? korrId : int.parse(korrId.toString()), filePath: f.path!, fileName: f.name);
        }
      }
      if (richtung == 'ausgang') {
        await widget.apiService.setArbeitsagenturErinnerungTicket(widget.userId, widget.vorschlagId, '');
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gespeichert'), backgroundColor: Colors.green));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.email, size: 18, color: Colors.teal.shade700), const SizedBox(width: 8),
        Text('Korrespondenz', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
        const Spacer(),
        FilledButton.icon(icon: const Icon(Icons.call_received, size: 14), label: const Text('Eingang', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.green.shade600, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _addKorr('eingang')),
        const SizedBox(width: 6),
        FilledButton.icon(icon: const Icon(Icons.call_made, size: 14), label: const Text('Ausgang', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade600, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _addKorr('ausgang')),
      ]),
      const SizedBox(height: 12),
      if (_korr.isEmpty)
        Container(width: double.infinity, padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
          child: Text('Keine Korrespondenz', style: TextStyle(fontSize: 12, color: Colors.grey.shade400), textAlign: TextAlign.center))
      else
        ..._korr.map((k) {
          final isEin = k['richtung'] == 'eingang';
          final c = isEin ? Colors.green : Colors.blue;
          const mLabels = {'email': 'E-Mail', 'post': 'Post', 'online': 'Online', 'persoenlich': 'Persönlich', 'fax': 'Fax', 'telefon': 'Telefon'};
          const mIcons = {'email': Icons.email, 'post': Icons.mail, 'online': Icons.language, 'persoenlich': Icons.person, 'fax': Icons.fax, 'telefon': Icons.phone};
          final m = k['methode']?.toString() ?? '';
          final kId = k['id'] is int ? k['id'] as int : int.parse(k['id'].toString());
          return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: c.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: c.shade200)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(isEin ? Icons.call_received : Icons.call_made, size: 14, color: c.shade700), const SizedBox(width: 6),
                Expanded(child: Text(k['betreff']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c.shade800))),
                if (m.isNotEmpty) Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: c.shade100, borderRadius: BorderRadius.circular(4)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(mIcons[m] ?? Icons.mail, size: 10, color: c.shade700), const SizedBox(width: 3), Text(mLabels[m] ?? m, style: TextStyle(fontSize: 9, color: c.shade700))])),
                const SizedBox(width: 4),
                IconButton(icon: Icon(Icons.delete_outline, size: 14, color: Colors.red.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: () async { await widget.apiService.deleteArbeitsagenturVorschlagKorr(widget.userId, kId); _load(); }),
              ]),
              if ((k['datum']?.toString() ?? '').isNotEmpty) Text(k['datum'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              if ((k['notiz']?.toString() ?? '').isNotEmpty) Text(k['notiz'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              const SizedBox(height: 4),
              KorrAttachmentsWidget(apiService: widget.apiService, modul: 'aa_vorschlag', korrespondenzId: kId),
            ]));
        }),
    ]));
  }
}

// ═════════════════════════════════════════════════════════════════════════
//  VOLLMACHT section — generate, store and revoke procuri Arbeitsagentur
// ═════════════════════════════════════════════════════════════════════════

class _AAVollmachtSection extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  const _AAVollmachtSection({required this.apiService, required this.userId});

  @override
  State<_AAVollmachtSection> createState() => _AAVollmachtSectionState();
}

class _AAVollmachtSectionState extends State<_AAVollmachtSection> with SingleTickerProviderStateMixin {
  late TabController _subTab;
  Map<String, dynamic>? _previewData;
  List<Map<String, dynamic>> _vollmachten = [];
  bool _loading = true;
  bool _generating = false;

  // Manager state
  int? _managerId;
  DateTime? _submitDate;
  String? _submitMethod;
  final _refCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _savingSubmit = false;
  bool _uploadingMember = false;
  bool _uploadingVorstand = false;
  bool _uploadingReceipt = false;

  // Options state (default: all enabled)
  final Map<String, bool> _umfang = {
    'antraege': true, 'bescheide': true, 'widerspruch': true, 'klage': true,
    'akteneinsicht': true, 'termine': true, 'egv': true, 'erklaerungen': true, 'online': true,
  };
  final Map<String, bool> _digital = {
    'konto_zugriff': true, 'antraege_online': true, 'postfach': true, 'veraenderungen': true,
  };
  final Map<String, bool> _zugang = {
    'verein_to_member': true, 'member_to_verein': true,
  };
  DateTime _validFrom = DateTime.now();
  DateTime? _validUntil;

  @override
  void initState() {
    super.initState();
    _subTab = TabController(length: 3, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _subTab.dispose();
    _refCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final dataRes = await widget.apiService.getVollmachtData(widget.userId, 'arbeitsagentur');
    final listRes = await widget.apiService.listVollmachten(widget.userId, 'arbeitsagentur');
    if (!mounted) return;
    setState(() {
      _loading = false;
      // jsonResponse() in PHP spreads data into the root via array_merge,
      // so user/vorsitzer/verein/vollmachten are top-level fields, not under 'data'.
      if (dataRes['success'] == true) {
        _previewData = {
          'user':          Map<String, dynamic>.from(dataRes['user']          ?? {}),
          'user_behoerde': Map<String, dynamic>.from(dataRes['user_behoerde'] ?? {}),
          'vorsitzer':     Map<String, dynamic>.from(dataRes['vorsitzer']     ?? {}),
          'verein':        Map<String, dynamic>.from(dataRes['verein']        ?? {}),
        };
      }
      if (listRes['success'] == true) {
        _vollmachten = List<Map<String, dynamic>>.from(listRes['vollmachten'] ?? []);
      }
    });
  }

  Future<void> _generate() async {
    setState(() => _generating = true);
    final res = await widget.apiService.createVollmacht({
      'user_id': widget.userId,
      'behoerde': 'arbeitsagentur',
      'valid_from': _validFrom.toIso8601String().substring(0, 10),
      'valid_until': _validUntil?.toIso8601String().substring(0, 10),
      'options': {'umfang': _umfang, 'digital': _digital, 'zugang': _zugang},
    });
    if (!mounted) return;
    setState(() => _generating = false);
    final ok = res['success'] == true;
    final tLang = (res['translation_language'] ?? '').toString();
    final msg = ok
        ? (tLang.isNotEmpty
            ? 'Vollmacht erstellt (ID ${res['id']}) — DE + Übersetzung ${tLang.toUpperCase()}'
            : 'Vollmacht erstellt (ID ${res['id']}) — nur DE')
        : (res['message'] ?? 'Fehler');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: ok ? Colors.green : Colors.red,
    ));
    if (ok) _loadAll();
  }

  Future<void> _revoke(int id) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vollmacht widerrufen'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Diese Vollmacht wird als widerrufen markiert. Die Zugangsdaten zum BA-Konto muss das Mitglied eigenverantwortlich ändern.', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(controller: reasonCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Grund (optional)', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('Widerrufen')),
        ],
      ),
    );
    if (confirmed != true) return;
    final res = await widget.apiService.revokeVollmacht(id, reason: reasonCtrl.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(res['success'] == true ? 'Vollmacht widerrufen' : (res['message'] ?? 'Fehler')),
      backgroundColor: res['success'] == true ? Colors.orange : Colors.red,
    ));
    if (res['success'] == true) _loadAll();
  }

  Future<void> _openPdf(int id, String filename, {String type = 'pdf'}) async {
    try {
      final response = await widget.apiService.downloadVollmachtPdf(id, type: type);
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        if (mounted) FileViewerDialog.showFromBytes(context, response.bodyBytes, filename);
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler (${response.statusCode})'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final user = _previewData?['user'] as Map<String, dynamic>? ?? {};
    final vorsitzer = _previewData?['vorsitzer'] as Map<String, dynamic>? ?? {};
    final verein = _previewData?['verein'] as Map<String, dynamic>? ?? {};

    return Column(children: [
      TabBar(
        controller: _subTab,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        tabs: const [
          Tab(icon: Icon(Icons.add_circle, size: 16), text: 'Generation'),
          Tab(icon: Icon(Icons.history, size: 16), text: 'Historie'),
          Tab(icon: Icon(Icons.manage_accounts, size: 16), text: 'Manager'),
        ],
      ),
      Expanded(child: TabBarView(controller: _subTab, children: [
        _buildGenerationTab(user, vorsitzer, verein),
        _buildHistorieTab(),
        _buildManagerTab(user, vorsitzer),
      ])),
    ]);
  }

  Widget _buildGenerationTab(Map<String, dynamic> user, Map<String, dynamic> vorsitzer, Map<String, dynamic> verein) {
    final missing = <String>[];
    if ((user['vorname'] ?? '').toString().isEmpty || (user['nachname'] ?? '').toString().isEmpty) missing.add('Name (Stufe 1)');
    if ((user['geburtsdatum'] ?? '').toString().isEmpty) missing.add('Geburtsdatum');
    if ((user['strasse'] ?? '').toString().isEmpty || (user['plz'] ?? '').toString().isEmpty) missing.add('Anschrift');
    if ((vorsitzer['vorname'] ?? '').toString().isEmpty) missing.add('Vorsitzender');
    if ((verein['vereinsname'] ?? '').toString().isEmpty) missing.add('Vereinsdaten');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Vollmacht — Arbeitsagentur', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
        const SizedBox(height: 4),
        const Text('§ 13 SGB X i.V.m. § 38 SGB III — generiert nach den unten gewählten Optionen.', style: TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 12),

        // Preview header — partile auto-completate din DB
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.indigo.shade200)),
          child: Builder(builder: (_) {
            final ub = (_previewData?['user_behoerde'] as Map?) ?? const {};
            final knr = (ub['kundennummer'] ?? '').toString();
            final dst = (ub['dienststelle'] ?? '').toString();
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _kv('Mitglied', '${user['vorname'] ?? ''} ${user['nachname'] ?? ''} — geb. ${user['geburtsdatum'] ?? '?'} in ${user['geburtsort'] ?? '?'}'),
              _kv('Anschrift', '${user['strasse'] ?? ''} ${user['hausnummer'] ?? ''}, ${user['plz'] ?? ''} ${user['ort'] ?? ''}'),
              _kv('Kundennummer BA', knr.isEmpty ? '?' : knr),
              _kv('Zust. Agentur', dst.isEmpty ? '?' : dst),
              _kv('Vorsitzender', '${vorsitzer['vorname'] ?? ''} ${vorsitzer['nachname'] ?? ''}'),
              _kv('Verein', '${verein['vereinsname'] ?? ''} — VR ${verein['registernummer'] ?? ''} (${verein['registergericht'] ?? ''})'),
            ]);
          }),
        ),
        if (missing.isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.red.shade50, border: Border.all(color: Colors.red.shade300)),
            child: Row(children: [
              Icon(Icons.warning, color: Colors.red.shade700, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text('Fehlende Pflichtdaten in Verifizierung Stufe 1: ${missing.join(", ")}', style: TextStyle(fontSize: 12, color: Colors.red.shade900))),
            ]),
          ),
        ),

        const SizedBox(height: 18),
        _sectionTitle(Icons.checklist, 'Umfang der Vollmacht'),
        ..._buildCheckboxes(_umfang, const {
          'antraege': 'Anträge stellen, ändern, zurücknehmen (ALG I, Bildungsgutschein, Reha, EGL)',
          'bescheide': 'Bescheide und sämtliche Korrespondenz empfangen',
          'widerspruch': 'Unterstützung bei Widersprüchen (Hilfestellung, kein RDG)',
          'klage': 'Unterstützung bei Klage vor Sozialgericht (§ 73 SGG, keine anwaltliche Vertretung)',
          'akteneinsicht': 'Akteneinsicht und Auskünfte',
          'termine': 'Teilnahme an Beratungs- / Vermittlungsgesprächen',
          'egv': 'Eingliederungsvereinbarung (EGV) abschließen / ändern / aufheben',
          'erklaerungen': 'Erklärungen zur Arbeitssuche, Verfügbarkeit, Mitwirkung',
          'online': 'Nutzung der Online-Angebote der BA',
        }),

        const SizedBox(height: 14),
        _sectionTitle(Icons.cloud, 'Digitale Vertretung (Online-Handeln)'),
        ..._buildCheckboxes(_digital, const {
          'konto_zugriff': 'Online-Zugriff auf das BA-Kundenkonto',
          'antraege_online': 'Online-Anträge stellen / ändern / zurücknehmen',
          'postfach': 'Postfachnachrichten lesen / senden',
          'veraenderungen': 'Veränderungsmeldungen online',
        }),

        const SizedBox(height: 14),
        _sectionTitle(Icons.swap_horiz, 'Wechselseitige Zugangsgewährung'),
        ..._buildCheckboxes(_zugang, const {
          'verein_to_member': 'Verein → Mitglied: voller Zugang zur Vorsitzer-Plattform (E-Mail + Passwort + 2FA / KeyAccess)',
          'member_to_verein': 'Mitglied → Verein: voller Zugang zum BA-Kundenkonto (Login-Daten oder eVollmacht)',
        }),

        const SizedBox(height: 14),
        _sectionTitle(Icons.event, 'Gültigkeit'),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Row(children: [
          Expanded(child: ListTile(
            dense: true,
            title: const Text('Gültig ab', style: TextStyle(fontSize: 12)),
            subtitle: Text(DateFormat('dd.MM.yyyy').format(_validFrom), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            trailing: const Icon(Icons.calendar_today, size: 16),
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: _validFrom, firstDate: DateTime(2020), lastDate: DateTime(2099));
              if (d != null) setState(() => _validFrom = d);
            },
          )),
          Expanded(child: ListTile(
            dense: true,
            title: const Text('Gültig bis (optional)', style: TextStyle(fontSize: 12)),
            subtitle: Text(_validUntil != null ? DateFormat('dd.MM.yyyy').format(_validUntil!) : 'auf Widerruf', style: const TextStyle(fontSize: 13)),
            trailing: _validUntil != null
                ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () => setState(() => _validUntil = null))
                : const Icon(Icons.calendar_today, size: 16),
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: _validUntil ?? _validFrom.add(const Duration(days: 365)), firstDate: _validFrom, lastDate: DateTime(2099));
              if (d != null) setState(() => _validUntil = d);
            },
          )),
        ])),

        const SizedBox(height: 20),
        Center(child: ElevatedButton.icon(
          icon: _generating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.picture_as_pdf),
          label: Text(_generating ? 'Generiere…' : 'PDF generieren & speichern'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
          onPressed: (_generating || missing.isNotEmpty) ? null : _generate,
        )),
      ]),
    );
  }

  Widget _buildHistorieTab() {
    if (_vollmachten.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Noch keine Vollmacht generiert.', style: TextStyle(color: Colors.grey))));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _vollmachten.length,
      itemBuilder: (_, i) {
        final v = _vollmachten[i];
        final status = (v['status'] ?? '').toString();
        final color = switch (status) {
          'active' => Colors.green, 'draft' => Colors.blue, 'revoked' => Colors.red, 'expired' => Colors.grey, _ => Colors.grey,
        };
        final filename = (v['pdf_filename'] ?? 'vollmacht_${v['id']}.pdf').toString();
        final tLang = (v['translation_language'] ?? '').toString();
        final tFile = (v['pdf_translation_filename'] ?? '').toString();
        final hasTrans = tLang.isNotEmpty && tFile.isNotEmpty;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(Icons.picture_as_pdf, color: color),
            title: Row(children: [
              Expanded(child: Text('Vollmacht #${v['id']} — ${status.toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.bold))),
              if (hasTrans) Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade700)),
                child: Text('🌍 ${tLang.toUpperCase()}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
              ),
            ]),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Erstellt: ${v['generated_at'] ?? ''}', style: const TextStyle(fontSize: 11)),
              Text('Gültig: ${v['valid_from'] ?? ''} → ${v['valid_until'] ?? 'auf Widerruf'}', style: const TextStyle(fontSize: 11)),
              if (status == 'revoked') Text('Widerrufen: ${v['revoked_at'] ?? ''}', style: TextStyle(fontSize: 11, color: Colors.red.shade700)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf, size: 14),
                  label: const Text('DE (Original)', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0), minimumSize: const Size(0, 28), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  onPressed: () => _openPdf(v['id'], filename),
                ),
                if (hasTrans) OutlinedButton.icon(
                  icon: const Icon(Icons.translate, size: 14),
                  label: Text('Übersetzung ${tLang.toUpperCase()}', style: const TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0), minimumSize: const Size(0, 28), tapTargetSize: MaterialTapTargetSize.shrinkWrap, foregroundColor: Colors.amber.shade900, side: BorderSide(color: Colors.amber.shade700)),
                  onPressed: () => _openPdf(v['id'], tFile, type: 'translation'),
                ),
              ]),
            ]),
            trailing: status != 'revoked'
                ? IconButton(icon: const Icon(Icons.cancel, size: 20, color: Colors.red), tooltip: 'Widerrufen', onPressed: () => _revoke(v['id']))
                : null,
          ),
        );
      },
    );
  }

  Widget _kv(String k, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 1), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    SizedBox(width: 90, child: Text(k, style: const TextStyle(fontSize: 11, color: Colors.grey))),
    Expanded(child: Text(v, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
  ]));

  Widget _sectionTitle(IconData icon, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Icon(icon, size: 16, color: Colors.indigo.shade700), const SizedBox(width: 6),
      Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
    ]),
  );

  List<Widget> _buildCheckboxes(Map<String, bool> state, Map<String, String> labels) {
    return labels.entries.map((e) => CheckboxListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(e.value, style: const TextStyle(fontSize: 12)),
      value: state[e.key] ?? false,
      onChanged: (v) => setState(() => state[e.key] = v ?? false),
    )).toList();
  }

  // ═══════════════════════════════════════════════════════════════════
  //  Manager tab
  // ═══════════════════════════════════════════════════════════════════

  Map<String, dynamic>? _selectedManager() {
    if (_vollmachten.isEmpty) return null;
    final id = _managerId ?? (_vollmachten.first['id'] as int);
    return _vollmachten.firstWhere((v) => v['id'] == id, orElse: () => _vollmachten.first);
  }

  Widget _buildManagerTab(Map<String, dynamic> user, Map<String, dynamic> vorsitzer) {
    if (_vollmachten.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(24),
        child: Text('Noch keine Vollmacht generiert. Bitte zuerst eine Vollmacht generieren.', style: TextStyle(color: Colors.grey), textAlign: TextAlign.center)));
    }
    final v = _selectedManager()!;
    // Sync local controllers / pickers with selected vollmacht — only on first build per selection
    if (_managerId != v['id']) {
      _managerId = v['id'] as int;
      _submitDate = (v['submitted_at'] != null && (v['submitted_at'] as String).isNotEmpty)
          ? DateTime.tryParse(v['submitted_at']) : null;
      _submitMethod = v['submitted_method'];
      _refCtrl.text = (v['submitted_reference'] ?? '').toString();
      _notesCtrl.text = (v['submitted_notes'] ?? '').toString();
    }

    final status = (v['status'] ?? '').toString();
    final hasMemberSig = (v['signature_member_filename'] ?? '').toString().isNotEmpty;
    final hasVorstandSig = (v['signature_vorstand_filename'] ?? '').toString().isNotEmpty;
    final hasReceipt = (v['submitted_receipt_filename'] ?? '').toString().isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Selector
        DropdownButtonFormField<int>(
          initialValue: _managerId,
          decoration: const InputDecoration(labelText: 'Aktive Vollmacht', isDense: true, border: OutlineInputBorder()),
          items: _vollmachten.map((vv) {
            return DropdownMenuItem<int>(
              value: vv['id'] as int,
              child: Text('#${vv['id']} — ${vv['valid_from']} — ${(vv['status'] ?? '').toString().toUpperCase()}', style: const TextStyle(fontSize: 13)),
            );
          }).toList(),
          onChanged: (id) {
            if (id == null) return;
            setState(() {
              _managerId = id;
              final vv = _vollmachten.firstWhere((x) => x['id'] == id);
              _submitDate = (vv['submitted_at'] != null && (vv['submitted_at'] as String).isNotEmpty)
                  ? DateTime.tryParse(vv['submitted_at']) : null;
              _submitMethod = vv['submitted_method'];
              _refCtrl.text = (vv['submitted_reference'] ?? '').toString();
              _notesCtrl.text = (vv['submitted_notes'] ?? '').toString();
            });
          },
        ),
        const SizedBox(height: 16),

        // STATUS
        _managerBlock('Status der Vollmacht', Icons.info_outline, Column(children: [
          _kv('Generiert', (v['generated_at'] ?? '').toString()),
          _kv('Gültig ab', (v['valid_from'] ?? '').toString()),
          _kv('Gültig bis', (v['valid_until'] ?? 'auf Widerruf').toString()),
          Row(children: [
            const SizedBox(width: 90, child: Text('Status', style: TextStyle(fontSize: 11, color: Colors.grey))),
            _statusBadge(status),
          ]),
        ])),

        const SizedBox(height: 12),

        // UNTERSCHRIFTEN
        _managerBlock('Unterschriften (eigenhändig)', Icons.draw, Column(children: [
          Padding(padding: const EdgeInsets.only(bottom: 8),
            child: Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.amber.shade50, border: Border.all(color: Colors.amber.shade300)),
              child: Row(children: [
                Icon(Icons.info, color: Colors.amber.shade800, size: 18), const SizedBox(width: 6),
                const Expanded(child: Text('Procedure: PDF ausdrucken → eigenhändig unterschreiben → einscannen → hier hochladen (PDF, JPG oder PNG, max 10 MB)', style: TextStyle(fontSize: 11))),
              ]))),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _signatureCard(
              label: 'Vollmachtgeber (Mitglied)',
              name: '${user['vorname'] ?? ''} ${user['nachname'] ?? ''}',
              has: hasMemberSig,
              uploadedAt: v['signature_member_uploaded_at'],
              uploading: _uploadingMember,
              vollmachtId: v['id'],
              signer: 'member',
              pages: v['signatures_member'] is List
                  ? List<Map<String, dynamic>>.from((v['signatures_member'] as List).map((e) => Map<String, dynamic>.from(e as Map)))
                  : const [],
            )),
            const SizedBox(width: 8),
            Expanded(child: _signatureCard(
              label: '1. Vorsitzender',
              name: '${vorsitzer['vorname'] ?? ''} ${vorsitzer['nachname'] ?? ''}',
              has: hasVorstandSig,
              uploadedAt: v['signature_vorstand_uploaded_at'],
              uploading: _uploadingVorstand,
              vollmachtId: v['id'],
              signer: 'vorstand',
              pages: v['signatures_vorstand'] is List
                  ? List<Map<String, dynamic>>.from((v['signatures_vorstand'] as List).map((e) => Map<String, dynamic>.from(e as Map)))
                  : const [],
            )),
          ]),
        ])),

        const SizedBox(height: 12),

        // EINREICHUNG
        _managerBlock('Einreichung bei der Agentur für Arbeit', Icons.send, Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Eingereicht am', style: TextStyle(fontSize: 12)),
            subtitle: Text(_submitDate != null ? DateFormat('dd.MM.yyyy').format(_submitDate!) : '— noch nicht eingereicht —', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_submitDate != null) IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => setState(() => _submitDate = null)),
              IconButton(icon: const Icon(Icons.calendar_today, size: 18), onPressed: () async {
                final d = await showDatePicker(context: context, initialDate: _submitDate ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2099));
                if (d != null) setState(() => _submitDate = d);
              }),
            ]),
          ),
          const Divider(height: 8),
          const Padding(padding: EdgeInsets.only(top: 4, bottom: 4), child: Text('Methode', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
          RadioGroup<String>(
            groupValue: _submitMethod,
            onChanged: (v) => setState(() => _submitMethod = v),
            child: Column(children: _methodOptions()),
          ),
          const SizedBox(height: 8),
          TextField(controller: _refCtrl, decoration: const InputDecoration(labelText: 'Aktenzeichen / Sendungsnummer (optional)', isDense: true, border: OutlineInputBorder()), style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          // Receipt upload
          Row(children: [
            Icon(hasReceipt ? Icons.check_circle : Icons.attach_file, size: 18, color: hasReceipt ? Colors.green : Colors.grey),
            const SizedBox(width: 6),
            Expanded(child: Text(hasReceipt ? 'Empfangsbeleg vorhanden' : 'Empfangsbeleg (optional)', style: const TextStyle(fontSize: 12))),
            if (_uploadingReceipt) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            else TextButton.icon(icon: const Icon(Icons.upload_file, size: 16), label: const Text('Upload', style: TextStyle(fontSize: 11)), onPressed: () => _pickAndUpload(v['id'], 'receipt')),
            if (hasReceipt) IconButton(icon: const Icon(Icons.visibility, size: 18), onPressed: () => _openPdf(v['id'], 'empfangsbeleg.pdf', type: 'receipt')),
          ]),
          const SizedBox(height: 8),
          TextField(controller: _notesCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Notizen (optional)', isDense: true, border: OutlineInputBorder()), style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            ElevatedButton.icon(
              icon: _savingSubmit ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save),
              label: const Text('Speichern'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
              onPressed: _savingSubmit ? null : () => _saveSubmission(v['id']),
            ),
          ]),
        ])),

        const SizedBox(height: 12),

        // LIFECYCLE TIMELINE
        _managerBlock('Zusammenfassung', Icons.timeline, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _timelineRow(true,  'Generiert',     v['generated_at']),
          _timelineRow(hasMemberSig,   'Mitglied-Unterschrift',  v['signature_member_uploaded_at']),
          _timelineRow(hasVorstandSig, 'Vorstand-Unterschrift',  v['signature_vorstand_uploaded_at']),
          _timelineRow(_submitDate != null, 'Eingereicht', _submitDate != null ? DateFormat('yyyy-MM-dd').format(_submitDate!) : null),
          _timelineRow(status == 'aktiv', 'Aktiv', null),
        ])),
      ]),
    );
  }

  Widget _managerBlock(String title, IconData icon, Widget child) => Card(
    margin: EdgeInsets.zero,
    elevation: 1,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 18, color: Colors.indigo.shade700), const SizedBox(width: 6),
          Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
        ]),
        const Divider(height: 12),
        child,
      ]),
    ),
  );

  Widget _statusBadge(String status) {
    final (color, label) = switch (status) {
      'draft'                  => (Colors.blue,    'DRAFT'),
      'wartet_unterschriften'  => (Colors.orange,  'WARTET AUF UNTERSCHRIFTEN'),
      'unterzeichnet'          => (Colors.lightGreen, 'UNTERZEICHNET'),
      'eingereicht'            => (Colors.green,   'EINGEREICHT'),
      'aktiv'                  => (Colors.green,   'AKTIV'),
      'revoked'                => (Colors.red,     'WIDERRUFEN'),
      'expired'                => (Colors.grey,    'ABGELAUFEN'),
      _                        => (Colors.grey,    status.toUpperCase()),
    };
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10), border: Border.all(color: color)),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)));
  }

  Widget _signatureCard({required String label, required String name, required bool has, required dynamic uploadedAt,
                         required bool uploading, required int vollmachtId, required String signer,
                         List<Map<String, dynamic>>? pages}) {
    final pageList = pages ?? const <Map<String, dynamic>>[];
    final hasAny = has || pageList.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: hasAny ? Colors.green.shade50 : Colors.grey.shade50,
        border: Border.all(color: hasAny ? Colors.green.shade400 : Colors.grey.shade400),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(hasAny ? Icons.check_circle : Icons.pending, size: 16, color: hasAny ? Colors.green : Colors.orange),
          const SizedBox(width: 4),
          Expanded(child: Text('$label  (${pageList.length})', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
        ]),
        Text(name, style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis),
        const SizedBox(height: 6),
        if (pageList.isEmpty)
          Text('Noch keine Seite hochgeladen', style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontStyle: FontStyle.italic))
        else ...pageList.map((p) {
          final pid = (p['id'] as num).toInt();
          final fn = (p['filename'] ?? '').toString();
          final at = (p['uploaded_at'] ?? '').toString();
          final mime = (p['mime_type'] ?? '').toString();
          final isImg = mime.startsWith('image/') || RegExp(r'\.(jpg|jpeg|png|heic|heif)$', caseSensitive: false).hasMatch(fn);
          return Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.green.shade200)),
            child: Row(children: [
              Icon(isImg ? Icons.image : Icons.picture_as_pdf, size: 14, color: Colors.green.shade800),
              const SizedBox(width: 4),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(fn, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (at.isNotEmpty) Text(at, style: TextStyle(fontSize: 8, color: Colors.grey.shade700)),
              ])),
              SizedBox(width: 24, height: 24, child: IconButton(icon: const Icon(Icons.visibility, size: 14), padding: EdgeInsets.zero, tooltip: 'Ansehen', onPressed: () => _openSignaturePage(pid, fn))),
              SizedBox(width: 24, height: 24, child: IconButton(icon: const Icon(Icons.delete, size: 14, color: Colors.red), padding: EdgeInsets.zero, tooltip: 'Löschen', onPressed: () => _deleteSignaturePage(vollmachtId, signer, pid, fn))),
            ]),
          );
        }),
        const SizedBox(height: 6),
        if (uploading) const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)))
        else SizedBox(width: double.infinity, child: ElevatedButton.icon(
          icon: const Icon(Icons.add_photo_alternate, size: 14),
          label: Text(pageList.isEmpty ? 'Seite(n) hochladen' : 'Weitere Seite hinzufügen', style: const TextStyle(fontSize: 10)),
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 6)),
          onPressed: () => _pickAndUpload(vollmachtId, signer),
        )),
      ]),
    );
  }

  Future<void> _openSignaturePage(int signatureId, String filename) async {
    final res = await widget.apiService.downloadVollmachtSignatureFile(signatureId);
    if (!mounted) return;
    if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
      FileViewerDialog.showFromBytes(context, res.bodyBytes, filename);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler (${res.statusCode})'), backgroundColor: Colors.red));
    }
  }

  Future<void> _deleteSignaturePage(int vollmachtId, String signer, int signatureId, String filename) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Seite löschen?'),
      content: Text(filename),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Löschen', style: TextStyle(color: Colors.red))),
      ],
    ));
    if (ok != true) return;
    final res = await widget.apiService.deleteVollmachtSignatureById(vollmachtId: vollmachtId, signer: signer, signatureId: signatureId);
    if (!mounted) return;
    if (res['success'] == true) {
      _loadAll();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Fehler'), backgroundColor: Colors.red));
    }
  }

  List<Widget> _methodOptions() {
    const opts = [('online', Icons.cloud, 'Online (eVollmacht / BA-Portal)'),
                  ('fax', Icons.print, 'Fax'),
                  ('persoenlich', Icons.person, 'Persönlich vor Ort'),
                  ('post', Icons.local_post_office, 'Post')];
    return opts.map((o) => RadioListTile<String>(
      dense: true,
      contentPadding: EdgeInsets.zero,
      value: o.$1,
      title: Row(children: [Icon(o.$2, size: 16, color: Colors.indigo.shade600), const SizedBox(width: 6), Text(o.$3, style: const TextStyle(fontSize: 12))]),
    )).toList();
  }

  Widget _timelineRow(bool done, String label, dynamic when) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, size: 16, color: done ? Colors.green : Colors.grey),
      const SizedBox(width: 6),
      SizedBox(width: 170, child: Text(label, style: TextStyle(fontSize: 12, fontWeight: done ? FontWeight.w600 : FontWeight.normal))),
      Expanded(child: Text(when?.toString() ?? '—', style: TextStyle(fontSize: 11, color: done ? Colors.black87 : Colors.grey))),
    ]),
  );

  Future<void> _pickAndUpload(int vollmachtId, String signer) async {
    final allowMulti = signer == 'member' || signer == 'vorstand';
    final result = await FilePickerHelper.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'heic', 'heif'],
      withData: true,
      allowMultiple: allowMulti,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() {
      if (signer == 'member') {
        _uploadingMember = true;
      } else if (signer == 'vorstand') {
        _uploadingVorstand = true;
      } else if (signer == 'receipt') {
        _uploadingReceipt = true;
      }
    });
    int ok = 0, fail = 0;
    for (final f in result.files) {
      if (f.bytes == null) { fail++; continue; }
      final res = await widget.apiService.uploadVollmachtSignature(
        vollmachtId: vollmachtId, signer: signer, bytes: f.bytes!, filename: f.name,
      );
      if (res['success'] == true) {
        ok++;
      } else {
        fail++;
      }
    }
    if (!mounted) return;
    setState(() {
      _uploadingMember = false; _uploadingVorstand = false; _uploadingReceipt = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$ok hochgeladen${fail > 0 ? ', $fail fehlgeschlagen' : ''}'),
      backgroundColor: fail > 0 ? Colors.orange : Colors.green,
    ));
    if (ok > 0) _loadAll();
  }

  Future<void> _saveSubmission(int vollmachtId) async {
    setState(() => _savingSubmit = true);
    final res = await widget.apiService.submitVollmacht(
      vollmachtId: vollmachtId,
      submittedAt: _submitDate != null ? DateFormat('yyyy-MM-dd').format(_submitDate!) : null,
      method: _submitMethod,
      reference: _refCtrl.text.trim(),
      notes: _notesCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _savingSubmit = false);
    final ok = res['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Eingereicht-Status gespeichert' : (res['message'] ?? 'Fehler')),
      backgroundColor: ok ? Colors.green : Colors.red,
    ));
    if (ok) _loadAll();
  }
}

// ═══════════════════════════════════════════════════════════════════
// 2FA / TOTP widget for arbeitsagentur.de Online-Konto
// Secret stored encrypted (AES-256-GCM) server-side. Code generated server-side.
// ═══════════════════════════════════════════════════════════════════

class _AaTotp2FAWidget extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  /// Notifică parinte (Online tab) când statusul TOTP se schimbă — folosit
  /// pentru a arăta sau ascunde butonul Auto-Login Online.
  final ValueChanged<bool>? onConfiguredChange;
  const _AaTotp2FAWidget({required this.apiService, required this.userId, this.onConfiguredChange});

  @override
  State<_AaTotp2FAWidget> createState() => _AaTotp2FAWidgetState();
}

class _AaTotp2FAWidgetState extends State<_AaTotp2FAWidget> {
  bool _loading = true;
  bool _configured = false;
  String? _label;
  String? _currentCode;
  int _secondsRemaining = 30;
  int _period = 30;
  Timer? _refreshTimer;
  bool _showSecretInput = false;
  final _secretCtrl = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _secretCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    setState(() => _loading = true);
    final res = await widget.apiService.getArbeitsagenturTotpStatus(widget.userId);
    if (!mounted) return;
    final data = res['data'] as Map<String, dynamic>? ?? res;
    final configured = data['configured'] == true;
    setState(() {
      _loading = false;
      _configured = configured;
      _label = data['label'] as String?;
      _period = (data['period'] as int?) ?? 30;
    });
    widget.onConfiguredChange?.call(configured);
    if (configured) _startCodeRefresh();
  }

  Future<void> _fetchCode() async {
    final res = await widget.apiService.getArbeitsagenturTotpCode(widget.userId);
    if (!mounted) return;
    if (res['success'] != true) return;
    final data = res['data'] as Map<String, dynamic>? ?? res;
    setState(() {
      _currentCode = data['code'] as String?;
      _secondsRemaining = (data['seconds_remaining'] as int?) ?? 30;
      _period = (data['period'] as int?) ?? 30;
    });
  }

  void _startCodeRefresh() {
    _refreshTimer?.cancel();
    _fetchCode();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _secondsRemaining = _secondsRemaining > 1 ? _secondsRemaining - 1 : _period;
      });
      // Re-fetch when window expires
      if (_secondsRemaining == _period) _fetchCode();
    });
  }

  Future<void> _saveSecret() async {
    final raw = _secretCtrl.text.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (raw.length < 16) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Geheimnis zu kurz (mind. 16 Zeichen Base32)'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    setState(() => _busy = true);
    final res = await widget.apiService.saveArbeitsagenturTotp(widget.userId, raw);
    if (!mounted) return;
    setState(() => _busy = false);
    final ok = res['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? '2FA-Geheimnis gespeichert (verschlüsselt)' : (res['message'] ?? 'Fehler')),
      backgroundColor: ok ? Colors.green : Colors.red,
    ));
    if (ok) {
      _secretCtrl.clear();
      setState(() => _showSecretInput = false);
      await _loadStatus();
    }
  }

  Future<void> _deleteSecret() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('2FA entfernen?'),
        content: const Text('Das gespeicherte TOTP-Geheimnis wird gelöscht.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Entfernen', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _busy = true);
    final res = await widget.apiService.deleteArbeitsagenturTotp(widget.userId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['success'] == true) {
      _refreshTimer?.cancel();
      setState(() {
        _configured = false;
        _currentCode = null;
      });
      widget.onConfiguredChange?.call(false);
    }
  }


  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.purple.shade200)),
        child: const Row(children: [SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 12), Text('2FA Status laden...')]),
      );
    }

    final progress = _secondsRemaining / _period;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.purple.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.security, size: 18, color: Colors.purple.shade700),
          const SizedBox(width: 8),
          Text('2FA / Authenticator', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.purple.shade700)),
          const Spacer(),
          if (_configured) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(12)),
              child: Text('Aktiv', style: TextStyle(fontSize: 11, color: Colors.green.shade800, fontWeight: FontWeight.w600)),
            ),
            IconButton(icon: const Icon(Icons.delete_outline, size: 18), color: Colors.red.shade400, tooltip: '2FA entfernen', onPressed: _busy ? null : _deleteSecret),
          ] else
            TextButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Einrichten'),
              onPressed: _busy ? null : () => setState(() => _showSecretInput = !_showSecretInput),
            ),
        ]),
        if (_configured && _currentCode != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.purple.shade300)),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(
                    _currentCode!.replaceAllMapped(RegExp(r'.{3}'), (m) => '${m[0]} ').trim(),
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, fontFamily: 'monospace', color: Colors.purple.shade900, letterSpacing: 3),
                  ),
                  Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    SizedBox(
                      width: 32, height: 32,
                      child: Stack(alignment: Alignment.center, children: [
                        CircularProgressIndicator(value: progress, strokeWidth: 3, backgroundColor: Colors.grey.shade200, valueColor: AlwaysStoppedAnimation(progress < 0.25 ? Colors.red : Colors.purple)),
                        Text('$_secondsRemaining', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ]),
                    ),
                  ]),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.copy, size: 20),
              tooltip: 'Code kopieren',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _currentCode!));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code kopiert'), duration: Duration(seconds: 1)));
              },
            ),
          ]),
          if (_label != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_label!, style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
        ],
        if (_showSecretInput && !_configured) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _secretCtrl,
            decoration: InputDecoration(
              labelText: 'Geheimer Schlüssel (Base32)',
              hintText: 'JBSWY3DPEHPK3PXP...',
              prefixIcon: const Icon(Icons.vpn_key),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              helperText: 'Aus Authenticator-App (16+ Zeichen, A-Z 2-7)',
            ),
            textCapitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: _busy ? null : () => setState(() { _showSecretInput = false; _secretCtrl.clear(); }), child: const Text('Abbrechen')),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              icon: _busy ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 16),
              label: const Text('Speichern (verschlüsselt)'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple.shade600, foregroundColor: Colors.white),
              onPressed: _busy ? null : _saveSecret,
            ),
          ]),
        ],
      ]),
    );
  }
}

// ==================== Arbeitsvermittler — multi-AV, pool per AA ====================
// Mirrors _JobcenterArbeitsvermittlerTab from behorde_jobcenter.dart but
// hits the arbeitsagentur_av_manage endpoint. Pool entries live in
// arbeitsagentur_personal; assignments in arbeitsagentur_user_av.

class _ArbeitsagenturArbeitsvermittlerTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final String arbeitsagenturName;
  final String arbeitsagenturOrt;
  const _ArbeitsagenturArbeitsvermittlerTab({
    required this.apiService,
    required this.userId,
    required this.arbeitsagenturName,
    required this.arbeitsagenturOrt,
  });
  @override
  State<_ArbeitsagenturArbeitsvermittlerTab> createState() => _ArbeitsagenturArbeitsvermittlerTabState();
}

class _ArbeitsagenturArbeitsvermittlerTabState extends State<_ArbeitsagenturArbeitsvermittlerTab> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _avList = [];
  bool _loading = true;
  late TabController _subTab;

  List<Map<String, dynamic>> get _aktivAv => _avList.where((e) => ((e['zustaendig_bis'] ?? '').toString().trim().isEmpty)).toList();
  List<Map<String, dynamic>> get _historieAv => _avList.where((e) => ((e['zustaendig_bis'] ?? '').toString().trim().isNotEmpty)).toList();

  @override
  void initState() { super.initState(); _subTab = TabController(length: 2, vsync: this); _load(); }

  @override
  void dispose() { _subTab.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await widget.apiService.arbeitsagenturAvAction({'action': 'list_user_av', 'user_id': widget.userId});
    if (!mounted) return;
    setState(() {
      _avList = List<Map<String, dynamic>>.from(res['av_list'] ?? []);
      _loading = false;
    });
  }

  Future<void> _openAddDialog() async {
    final addedId = await showDialog<int>(
      context: context,
      builder: (_) => _AaAddAvDialog(
        apiService: widget.apiService,
        userId: widget.userId,
        arbeitsagenturName: widget.arbeitsagenturName,
        arbeitsagenturOrt: widget.arbeitsagenturOrt,
        existingPersonalIds: _avList.map((e) => e['personal_id'] as int).toSet(),
      ),
    );
    if (addedId != null) _load();
  }

  Future<void> _openAvModal(Map<String, dynamic> av) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AaAvDetailModal(apiService: widget.apiService, userAv: av),
    );
    if (changed == true) _load();
  }

  Future<void> _unassign(int userAvId) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Arbeitsvermittler entfernen?'),
      content: const Text('Die Zuordnung wird gelöscht. Der Mitarbeiter bleibt im Pool der Arbeitsagentur.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Entfernen', style: TextStyle(color: Colors.red))),
      ],
    ));
    if (ok != true) return;
    await widget.apiService.arbeitsagenturAvAction({'action': 'unassign_user_av', 'user_av_id': userAvId});
    _load();
  }

  Widget _avCard(Map<String, dynamic> av, int displayIndex) {
    final pos = av['position'] as int? ?? (displayIndex + 1);
    final rolle = (av['rolle'] ?? 'sonstige').toString();
    final tel = (av['telefon'] ?? '').toString();
    final email = (av['email'] ?? '').toString();
    final zimmer = (av['zimmer'] ?? '').toString();
    final aaCached = (av['arbeitsagentur_name'] ?? '').toString();
    final seit = (av['zustaendig_seit'] ?? '').toString();
    final bis  = (av['zustaendig_bis']  ?? '').toString();
    final aktiv = bis.isEmpty;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => _openAvModal(av),
        child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFF003F7D), borderRadius: BorderRadius.circular(10)),
              child: Text('$pos.', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text('${av['vorname'] ?? ''} ${av['nachname'] ?? ''}'.trim(), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: aktiv ? Colors.green.shade100 : Colors.grey.shade300, borderRadius: BorderRadius.circular(8)),
              child: Text(aktiv ? 'Aktiv' : 'Inaktiv', style: TextStyle(fontSize: 10, color: aktiv ? Colors.green.shade900 : Colors.grey.shade700)),
            ),
            IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red), tooltip: 'Zuordnung entfernen', onPressed: () => _unassign(av['id'])),
          ]),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(4)),
            child: Text(rolle, style: TextStyle(fontSize: 11, color: Colors.indigo.shade800, fontWeight: FontWeight.w600)),
          ),
          if (aaCached.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [
            Icon(Icons.business, size: 12, color: Colors.grey.shade600), const SizedBox(width: 4),
            Expanded(child: Text(aaCached, style: TextStyle(fontSize: 11, color: Colors.grey.shade700))),
          ])),
          if (tel.isNotEmpty || email.isNotEmpty || zimmer.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Wrap(spacing: 10, children: [
            if (tel.isNotEmpty) Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.phone, size: 11), const SizedBox(width: 2), Text(tel, style: const TextStyle(fontSize: 11))]),
            if (email.isNotEmpty) Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.email, size: 11), const SizedBox(width: 2), Text(email, style: const TextStyle(fontSize: 11))]),
            if (zimmer.isNotEmpty) Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.meeting_room, size: 11), const SizedBox(width: 2), Text('Zi. $zimmer', style: const TextStyle(fontSize: 11))]),
          ])),
          if (seit.isNotEmpty || bis.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Row(children: [
            if (seit.isNotEmpty) Text('seit $seit', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
            if (!aktiv && bis.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 8), child: Text('bis $bis', style: TextStyle(fontSize: 10, color: Colors.grey.shade600))),
          ])),
          const SizedBox(height: 4),
          const Text('Tippen zum Öffnen →', style: TextStyle(fontSize: 10, color: Colors.blueGrey, fontStyle: FontStyle.italic)),
        ])),
      ),
    );
  }

  Widget _avListView(List<Map<String, dynamic>> list, {required String emptyMsg, required bool showAddBtn}) {
    if (list.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.person_off, size: 64, color: Colors.grey.shade400),
        const SizedBox(height: 16),
        Text(emptyMsg, style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
        const SizedBox(height: 8),
        if (showAddBtn) ...[
          if (widget.arbeitsagenturName.isEmpty)
            Text('Erst Zuständige Arbeitsagentur setzen (Tab Zuständige Arbeitsagentur)', style: TextStyle(fontSize: 11, color: Colors.orange.shade700))
          else
            TextButton.icon(onPressed: _openAddDialog, icon: const Icon(Icons.add, size: 14), label: const Text('Hinzufügen', style: TextStyle(fontSize: 12))),
        ],
      ]));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: list.length,
      itemBuilder: (_, i) => _avCard(list[i], i),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: Colors.blue.shade50, border: Border(bottom: BorderSide(color: Colors.blue.shade200))),
        child: Row(children: [
          Icon(Icons.support_agent, size: 20, color: Colors.blue.shade800),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Arbeitsvermittler', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
            if (widget.arbeitsagenturName.isNotEmpty) Text('@ ${widget.arbeitsagenturName}', style: TextStyle(fontSize: 11, color: Colors.blue.shade700)),
          ])),
        ]),
      ),
      TabBar(
        controller: _subTab,
        labelColor: Colors.blue.shade800,
        unselectedLabelColor: Colors.grey.shade600,
        indicatorColor: Colors.blue.shade700,
        tabs: [
          Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.support_agent, size: 16),
            const SizedBox(width: 6),
            Text('Zuständige Arbeitsvermittler${_aktivAv.isNotEmpty ? " (${_aktivAv.length})" : ""}', style: const TextStyle(fontSize: 12)),
          ])),
          Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.history, size: 16),
            const SizedBox(width: 6),
            Text('Historie${_historieAv.isNotEmpty ? " (${_historieAv.length})" : ""}', style: const TextStyle(fontSize: 12)),
          ])),
        ],
      ),
      Expanded(child: TabBarView(controller: _subTab, children: [
        Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.blue.shade50.withValues(alpha: 0.5),
            child: Row(children: [
              Expanded(child: Text('Aktuell zugeordnete Arbeitsvermittler', style: TextStyle(fontSize: 11, color: Colors.blue.shade700))),
              ElevatedButton.icon(
                onPressed: _openAddDialog,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Neuer Arbeitsvermittler', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              ),
            ]),
          ),
          Expanded(child: _avListView(_aktivAv, emptyMsg: 'Noch kein Arbeitsvermittler zugeordnet', showAddBtn: true)),
        ]),
        _avListView(_historieAv, emptyMsg: 'Keine früheren Arbeitsvermittler', showAddBtn: false),
      ])),
    ]);
  }
}

// ==================== Add AV dialog (pick from pool or create new) ====================

class _AaAddAvDialog extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final String arbeitsagenturName;
  final String arbeitsagenturOrt;
  final Set<int> existingPersonalIds;
  const _AaAddAvDialog({
    required this.apiService,
    required this.userId,
    required this.arbeitsagenturName,
    required this.arbeitsagenturOrt,
    required this.existingPersonalIds,
  });
  @override
  State<_AaAddAvDialog> createState() => _AaAddAvDialogState();
}

class _AaAddAvDialogState extends State<_AaAddAvDialog> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<Map<String, dynamic>> _pool = [];
  bool _loadingPool = true;

  final _vornameC = TextEditingController();
  final _nachnameC = TextEditingController();
  final _telC = TextEditingController();
  final _emC = TextEditingController();
  final _ziC = TextEditingController();
  String _rolle = 'Arbeitsvermittler';
  bool _saving = false;

  // Matches arbeitsagentur_personal.rolle ENUM in DB.
  static const _rollen = [
    'Arbeitsvermittler', 'Berufsberater', 'Reha_SB', 'SB_Leistung',
    'SB_Geldleistung', 'Teamleiter', 'Eingangszone', 'sonstige',
  ];

  @override
  void initState() { super.initState(); _tab = TabController(length: 2, vsync: this); _loadPool(); }
  @override
  void dispose() { _tab.dispose(); _vornameC.dispose(); _nachnameC.dispose(); _telC.dispose(); _emC.dispose(); _ziC.dispose(); super.dispose(); }

  Future<void> _loadPool() async {
    final res = await widget.apiService.arbeitsagenturAvAction({'action': 'list_personal', 'arbeitsagentur_name': widget.arbeitsagenturName});
    if (!mounted) return;
    setState(() {
      _pool = List<Map<String, dynamic>>.from(res['personal'] ?? []);
      _loadingPool = false;
    });
  }

  Future<void> _assign(int personalId) async {
    setState(() => _saving = true);
    final res = await widget.apiService.arbeitsagenturAvAction({
      'action': 'assign_user_av', 'user_id': widget.userId, 'personal_id': personalId,
      'zustaendig_seit': DateTime.now().toIso8601String().substring(0, 10),
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['success'] == true) {
      Navigator.pop(context, res['user_av_id'] as int?);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Fehler'), backgroundColor: Colors.red));
    }
  }

  Future<void> _createAndAssign() async {
    if (_vornameC.text.trim().isEmpty && _nachnameC.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name erforderlich'), backgroundColor: Colors.red));
      return;
    }
    setState(() => _saving = true);
    final createRes = await widget.apiService.arbeitsagenturAvAction({
      'action': 'create_personal',
      'personal': {
        'arbeitsagentur_name': widget.arbeitsagenturName,
        'arbeitsagentur_ort': widget.arbeitsagenturOrt,
        'vorname': _vornameC.text.trim(),
        'nachname': _nachnameC.text.trim(),
        'rolle': _rolle,
        'telefon': _telC.text.trim(),
        'email': _emC.text.trim(),
        'zimmer': _ziC.text.trim(),
      },
    });
    if (!mounted) return;
    if (createRes['success'] != true) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(createRes['message'] ?? 'Fehler'), backgroundColor: Colors.red));
      return;
    }
    final personalId = createRes['id'] as int;
    await _assign(personalId);
  }

  Widget _poolList() {
    if (_loadingPool) return const Center(child: CircularProgressIndicator());
    final filtered = _pool.where((p) => !widget.existingPersonalIds.contains(p['id'])).toList();
    if (filtered.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.person_search, size: 48, color: Colors.grey.shade400),
        const SizedBox(height: 12),
        Text(widget.arbeitsagenturName.isEmpty
            ? 'Bitte erst Dienststelle wählen'
            : 'Noch keine Mitarbeiter im Pool für ${widget.arbeitsagenturName}',
          style: TextStyle(color: Colors.grey.shade600), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        const Text('→ Tab "Neu anlegen" verwenden', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
      ])));
    }
    return ListView.builder(itemCount: filtered.length, itemBuilder: (_, i) {
      final p = filtered[i];
      final vor = (p['vorname'] ?? '?').toString();
      return ListTile(
        dense: true,
        leading: CircleAvatar(backgroundColor: Colors.blue.shade100, child: Text(vor.isNotEmpty ? vor[0] : '?', style: TextStyle(color: Colors.blue.shade900, fontSize: 14))),
        title: Text('${p['vorname'] ?? ''} ${p['nachname'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${p['rolle'] ?? ''}${(p['zimmer']?.toString() ?? '').isNotEmpty ? " • Zi. ${p['zimmer']}" : ""}'),
        trailing: ElevatedButton(
          onPressed: _saving ? null : () => _assign(p['id']),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white, minimumSize: const Size(0, 32)),
          child: const Text('Zuordnen', style: TextStyle(fontSize: 12)),
        ),
      );
    });
  }

  Widget _newForm() => SingleChildScrollView(padding: const EdgeInsets.all(12), child: Column(children: [
    Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.amber.shade200)),
      child: Row(children: [
        Icon(Icons.info_outline, size: 16, color: Colors.amber.shade800), const SizedBox(width: 6),
        Expanded(child: Text(
          'Wird im Pool der Arbeitsagentur ${widget.arbeitsagenturName.isEmpty ? "(?)" : widget.arbeitsagenturName} angelegt und allen Mitgliedern dort sichtbar.',
          style: const TextStyle(fontSize: 11),
        )),
      ]),
    ),
    const SizedBox(height: 12),
    Row(children: [
      Expanded(child: TextField(controller: _vornameC, decoration: const InputDecoration(labelText: 'Vorname', isDense: true, border: OutlineInputBorder()))),
      const SizedBox(width: 8),
      Expanded(child: TextField(controller: _nachnameC, decoration: const InputDecoration(labelText: 'Nachname', isDense: true, border: OutlineInputBorder()))),
    ]),
    const SizedBox(height: 10),
    DropdownButtonFormField<String>(
      initialValue: _rolle,
      decoration: const InputDecoration(labelText: 'Rolle', isDense: true, border: OutlineInputBorder()),
      items: _rollen.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
      onChanged: (v) => setState(() => _rolle = v ?? 'sonstige'),
    ),
    const SizedBox(height: 10),
    TextField(controller: _telC, decoration: const InputDecoration(labelText: 'Telefon / Durchwahl', isDense: true, border: OutlineInputBorder())),
    const SizedBox(height: 10),
    TextField(controller: _emC, decoration: const InputDecoration(labelText: 'E-Mail', isDense: true, border: OutlineInputBorder())),
    const SizedBox(height: 10),
    TextField(controller: _ziC, decoration: const InputDecoration(labelText: 'Zimmer', isDense: true, border: OutlineInputBorder())),
    const SizedBox(height: 16),
    Align(alignment: Alignment.centerRight, child: ElevatedButton.icon(
      onPressed: _saving ? null : _createAndAssign,
      icon: _saving
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.add, size: 16),
      label: const Text('Anlegen + Zuordnen'),
      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
    )),
  ]));

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(24),
    child: SizedBox(width: 600, height: 520, child: Column(children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.blue.shade700, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
        child: Row(children: [
          const Icon(Icons.person_add, color: Colors.white), const SizedBox(width: 8),
          const Expanded(child: Text('Arbeitsvermittler hinzufügen', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))),
          IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
        ]),
      ),
      TabBar(controller: _tab, labelColor: Colors.blue, tabs: const [
        Tab(icon: Icon(Icons.group, size: 18), text: 'Aus Pool wählen'),
        Tab(icon: Icon(Icons.person_add, size: 18), text: 'Neu anlegen'),
      ]),
      Expanded(child: TabBarView(controller: _tab, children: [_poolList(), _newForm()])),
    ])),
  );
}

// ==================== AV detail modal (edit stammdaten + assignment) ====================

class _AaAvDetailModal extends StatefulWidget {
  final ApiService apiService;
  final Map<String, dynamic> userAv;
  const _AaAvDetailModal({required this.apiService, required this.userAv});
  @override
  State<_AaAvDetailModal> createState() => _AaAvDetailModalState();
}

class _AaAvDetailModalState extends State<_AaAvDetailModal> with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _dataChanged = false; // tracks if anything in any sub-tab changed

  @override
  void initState() { super.initState(); _tab = TabController(length: 3, vsync: this); }
  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  void _markChanged() { if (!_dataChanged) _dataChanged = true; }

  @override
  Widget build(BuildContext context) {
    final av = widget.userAv;
    final aaName = (av['arbeitsagentur_name'] ?? '').toString();
    final fullName = '${av['vorname'] ?? ''} ${av['nachname'] ?? ''}'.trim();
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(width: 680, height: 700, child: Column(children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.blue.shade700, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
          child: Row(children: [
            const Icon(Icons.support_agent, color: Colors.white), const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(fullName.isEmpty ? 'Arbeitsvermittler' : fullName,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              if (aaName.isNotEmpty) Text(aaName, style: TextStyle(color: Colors.blue.shade100, fontSize: 11)),
            ])),
            IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context, _dataChanged)),
          ]),
        ),
        Container(
          color: Colors.blue.shade50,
          child: TabBar(
            controller: _tab,
            labelColor: Colors.blue.shade800,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: Colors.blue.shade700,
            tabs: const [
              Tab(icon: Icon(Icons.person, size: 18), text: 'Details'),
              Tab(icon: Icon(Icons.event, size: 18), text: 'Termine'),
              Tab(icon: Icon(Icons.work_history, size: 18), text: 'Eigenbemühungen'),
            ],
          ),
        ),
        Expanded(child: TabBarView(controller: _tab, children: [
          _AaAvDetailsTab(apiService: widget.apiService, userAv: widget.userAv, onChanged: _markChanged),
          _AaAvTermineTab(apiService: widget.apiService, userAv: widget.userAv, onChanged: _markChanged),
          _AaAvEigenbemTab(apiService: widget.apiService, userAv: widget.userAv, onChanged: _markChanged),
        ])),
      ])),
    );
  }
}

// ─────────────── Details sub-tab (Stammdaten + Zuordnung) ───────────────

class _AaAvDetailsTab extends StatefulWidget {
  final ApiService apiService;
  final Map<String, dynamic> userAv;
  final VoidCallback onChanged;
  const _AaAvDetailsTab({required this.apiService, required this.userAv, required this.onChanged});
  @override
  State<_AaAvDetailsTab> createState() => _AaAvDetailsTabState();
}

class _AaAvDetailsTabState extends State<_AaAvDetailsTab> {
  late TextEditingController _vornameC, _nachnameC, _telC, _emC, _ziC, _personalNotizC, _linkNotizC, _seitC, _bisC;
  late String _rolle;
  bool _saving = false, _dirty = false;

  static const _rollen = [
    'Arbeitsvermittler', 'Berufsberater', 'Reha_SB', 'SB_Leistung',
    'SB_Geldleistung', 'Teamleiter', 'Eingangszone', 'sonstige',
  ];

  @override
  void initState() {
    super.initState();
    final av = widget.userAv;
    _vornameC  = TextEditingController(text: av['vorname']?.toString() ?? '');
    _nachnameC = TextEditingController(text: av['nachname']?.toString() ?? '');
    _telC      = TextEditingController(text: av['telefon']?.toString() ?? '');
    _emC       = TextEditingController(text: av['email']?.toString() ?? '');
    _ziC       = TextEditingController(text: av['zimmer']?.toString() ?? '');
    _personalNotizC = TextEditingController(text: av['personal_notiz']?.toString() ?? '');
    _linkNotizC     = TextEditingController(text: av['link_notiz']?.toString() ?? '');
    _seitC = TextEditingController(text: av['zustaendig_seit']?.toString() ?? '');
    _bisC  = TextEditingController(text: av['zustaendig_bis']?.toString()  ?? '');
    final r = (av['rolle'] ?? 'sonstige').toString();
    _rolle = _rollen.contains(r) ? r : 'sonstige';
    for (final c in [_vornameC, _nachnameC, _telC, _emC, _ziC, _personalNotizC, _linkNotizC, _seitC, _bisC]) {
      c.addListener(() { if (!_dirty) setState(() => _dirty = true); });
    }
  }

  @override
  void dispose() {
    for (final c in [_vornameC, _nachnameC, _telC, _emC, _ziC, _personalNotizC, _linkNotizC, _seitC, _bisC]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate(TextEditingController c) async {
    final init = DateTime.tryParse(c.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime(2010),
      lastDate: DateTime(2050),
      locale: const Locale('de'),
    );
    if (picked != null) {
      c.text = picked.toIso8601String().substring(0, 10);
      setState(() => _dirty = true);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final personalId = (widget.userAv['personal_id'] as num).toInt();
    final userAvId   = (widget.userAv['id'] as num).toInt();
    final pRes = await widget.apiService.arbeitsagenturAvAction({
      'action': 'update_personal',
      'personal_id': personalId,
      'personal': {
        'vorname': _vornameC.text.trim(),
        'nachname': _nachnameC.text.trim(),
        'rolle': _rolle,
        'telefon': _telC.text.trim(),
        'email': _emC.text.trim(),
        'zimmer': _ziC.text.trim(),
        'notiz': _personalNotizC.text.trim(),
      },
    });
    if (!mounted) return;
    if (pRes['success'] != true) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(pRes['message'] ?? 'Pool-Update fehlgeschlagen'), backgroundColor: Colors.red));
      return;
    }
    final uRes = await widget.apiService.arbeitsagenturAvAction({
      'action': 'update_user_av',
      'user_av_id': userAvId,
      'position': widget.userAv['position'] ?? 1,
      'zustaendig_seit': _seitC.text.trim().isEmpty ? null : _seitC.text.trim(),
      'zustaendig_bis':  _bisC.text.trim().isEmpty  ? null : _bisC.text.trim(),
      'notiz': _linkNotizC.text.trim(),
    });
    if (!mounted) return;
    setState(() { _saving = false; _dirty = false; });
    if (uRes['success'] == true) {
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gespeichert'), backgroundColor: Colors.green));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(uRes['message'] ?? 'Zuordnung-Update fehlgeschlagen'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Stammdaten (Pool)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: _vornameC, decoration: const InputDecoration(labelText: 'Vorname', isDense: true, border: OutlineInputBorder()))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _nachnameC, decoration: const InputDecoration(labelText: 'Nachname', isDense: true, border: OutlineInputBorder()))),
        ]),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _rolle,
          decoration: const InputDecoration(labelText: 'Rolle', isDense: true, border: OutlineInputBorder()),
          items: _rollen.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
          onChanged: (v) => setState(() { _rolle = v ?? 'sonstige'; _dirty = true; }),
        ),
        const SizedBox(height: 10),
        TextField(controller: _telC, decoration: const InputDecoration(labelText: 'Telefon', isDense: true, border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: _emC, decoration: const InputDecoration(labelText: 'E-Mail', isDense: true, border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: _ziC, decoration: const InputDecoration(labelText: 'Zimmer', isDense: true, border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: _personalNotizC, maxLines: 2, decoration: const InputDecoration(labelText: 'Notiz zur Person (Pool)', isDense: true, border: OutlineInputBorder())),
        const SizedBox(height: 20),
        Divider(color: Colors.blue.shade100),
        const SizedBox(height: 8),
        Text('Zuordnung zu diesem Mitglied', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(
            controller: _seitC, readOnly: true,
            decoration: InputDecoration(
              labelText: 'Zuständig seit', isDense: true, border: const OutlineInputBorder(),
              suffixIcon: IconButton(icon: const Icon(Icons.calendar_today, size: 16), onPressed: () => _pickDate(_seitC)),
            ),
          )),
          const SizedBox(width: 8),
          Expanded(child: TextField(
            controller: _bisC, readOnly: true,
            decoration: InputDecoration(
              labelText: 'Zuständig bis (leer = aktiv)', isDense: true, border: const OutlineInputBorder(),
              suffixIcon: IconButton(icon: const Icon(Icons.calendar_today, size: 16), onPressed: () => _pickDate(_bisC)),
            ),
          )),
        ]),
        const SizedBox(height: 10),
        TextField(controller: _linkNotizC, maxLines: 2, decoration: const InputDecoration(labelText: 'Notiz zur Zuordnung', isDense: true, border: OutlineInputBorder())),
      ]))),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.grey.shade100, border: Border(top: BorderSide(color: Colors.grey.shade300))),
        child: Row(children: [
          const Spacer(),
          ElevatedButton.icon(
            onPressed: (_saving || !_dirty) ? null : _save,
            icon: _saving
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save, size: 16),
            label: const Text('Speichern'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
          ),
        ]),
      ),
    ]);
  }
}

// ─────────────── Termine sub-tab (per-AV termine list + add/edit) ───────────────

class _AaAvTermineTab extends StatefulWidget {
  final ApiService apiService;
  final Map<String, dynamic> userAv;
  final VoidCallback onChanged;
  const _AaAvTermineTab({required this.apiService, required this.userAv, required this.onChanged});
  @override
  State<_AaAvTermineTab> createState() => _AaAvTermineTabState();
}

class _AaAvTermineTabState extends State<_AaAvTermineTab> {
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;

  static const _typLabel = {
    'erstgespraech': 'Erstgespräch',
    'folgegespraech': 'Folgegespräch',
    'vermittlung': 'Vermittlung',
    'beratung': 'Beratung',
    'meldetermin': 'Meldetermin',
    'reha': 'Reha',
    'sonstige': 'Sonstige',
  };
  static const _statusLabel = {
    'geplant': 'Geplant',
    'durchgefuehrt': 'Durchgeführt',
    'versaeumt': 'Versäumt',
    'abgesagt_kunde': 'Abgesagt (Kunde)',
    'abgesagt_aa':    'Abgesagt (AA)',
    'verschoben': 'Verschoben',
  };
  static const _statusColor = {
    'geplant': Colors.amber,
    'durchgefuehrt': Colors.green,
    'versaeumt': Colors.red,
    'abgesagt_kunde': Colors.grey,
    'abgesagt_aa': Colors.grey,
    'verschoben': Colors.orange,
  };

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await widget.apiService.arbeitsagenturAvAction({
      'action': 'list_av_termine', 'user_av_id': widget.userAv['id'],
    });
    if (!mounted) return;
    setState(() {
      _list = List<Map<String, dynamic>>.from(res['termine'] ?? []);
      _loading = false;
    });
  }

  Future<void> _openEdit({Map<String, dynamic>? existing}) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _AaAvTerminEditDialog(
        apiService: widget.apiService,
        userId: (widget.userAv['user_id'] as num).toInt(),
        userAvId: (widget.userAv['id'] as num).toInt(),
        existing: existing,
      ),
    );
    if (changed == true) {
      widget.onChanged();
      _load();
    }
  }

  Future<void> _delete(int id) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Termin löschen?'),
      content: const Text('Der Eintrag wird unwiderruflich entfernt.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Löschen', style: TextStyle(color: Colors.red))),
      ],
    ));
    if (ok != true) return;
    final res = await widget.apiService.arbeitsagenturAvAction({'action': 'delete_av_termin', 'termin_id': id});
    if (res['success'] == true) { widget.onChanged(); _load(); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: Colors.blue.shade50,
        child: Row(children: [
          Expanded(child: Text('${_list.length} Termin(e)', style: TextStyle(fontSize: 12, color: Colors.blue.shade700))),
          ElevatedButton.icon(
            onPressed: () => _openEdit(),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Neuer Termin', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
          ),
        ]),
      ),
      Expanded(child: _list.isEmpty
        ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.event_busy, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 10),
            Text('Noch keine Termine mit diesem Vermittler', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ]))
        : ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: _list.length,
            itemBuilder: (_, i) {
              final t = _list[i];
              final status = (t['status'] ?? 'geplant').toString();
              final col = _statusColor[status] ?? Colors.grey;
              final dt = DateTime.tryParse(t['termin_datum']?.toString() ?? '');
              final dtStr = dt != null ? '${dt.day.toString().padLeft(2,'0')}.${dt.month.toString().padLeft(2,'0')}.${dt.year} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}' : '?';
              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                elevation: 1,
                child: InkWell(
                  onTap: () => _openEdit(existing: t),
                  child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.event, size: 14, color: col.shade700), const SizedBox(width: 6),
                      Expanded(child: Text(dtStr, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: col.shade600, borderRadius: BorderRadius.circular(8)),
                        child: Text(_statusLabel[status] ?? status, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                      ),
                      IconButton(icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28), onPressed: () => _delete((t['id'] as num).toInt())),
                    ]),
                    const SizedBox(height: 4),
                    Row(children: [
                      Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(3)),
                        child: Text(_typLabel[(t['termin_typ'] ?? 'sonstige').toString()] ?? (t['termin_typ'] ?? '').toString(), style: TextStyle(fontSize: 10, color: Colors.indigo.shade800))),
                      const SizedBox(width: 6),
                      Text((t['modus'] ?? '').toString(), style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                    ]),
                    if ((t['thema'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text((t['thema']).toString(), style: const TextStyle(fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis)),
                    if ((t['ergebnis'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text('→ ${t['ergebnis']}', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.green.shade800), maxLines: 2, overflow: TextOverflow.ellipsis)),
                  ])),
                ),
              );
            },
          )),
    ]);
  }
}

class _AaAvTerminEditDialog extends StatefulWidget {
  final ApiService apiService;
  final int userId, userAvId;
  final Map<String, dynamic>? existing;
  const _AaAvTerminEditDialog({required this.apiService, required this.userId, required this.userAvId, this.existing});
  @override
  State<_AaAvTerminEditDialog> createState() => _AaAvTerminEditDialogState();
}

class _AaAvTerminEditDialogState extends State<_AaAvTerminEditDialog> {
  late TextEditingController _datumC, _zeitC, _ortC, _themaC, _verlaufC, _ergebnisC, _notizC;
  String _typ = 'folgegespraech', _initiator = 'arbeitsagentur', _modus = 'persoenlich', _status = 'geplant';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final dt = e != null ? DateTime.tryParse(e['termin_datum']?.toString() ?? '') : null;
    _datumC = TextEditingController(text: dt != null ? dt.toIso8601String().substring(0, 10) : '');
    _zeitC  = TextEditingController(text: dt != null ? '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}' : '');
    _ortC      = TextEditingController(text: e?['ort']?.toString() ?? '');
    _themaC    = TextEditingController(text: e?['thema']?.toString() ?? '');
    _verlaufC  = TextEditingController(text: e?['verlauf']?.toString() ?? '');
    _ergebnisC = TextEditingController(text: e?['ergebnis']?.toString() ?? '');
    _notizC    = TextEditingController(text: e?['notiz']?.toString() ?? '');
    if (e != null) {
      _typ       = e['termin_typ']?.toString() ?? 'folgegespraech';
      _initiator = e['initiator']?.toString()  ?? 'arbeitsagentur';
      _modus     = e['modus']?.toString()      ?? 'persoenlich';
      _status    = e['status']?.toString()     ?? 'geplant';
    }
  }

  @override
  void dispose() {
    for (final c in [_datumC, _zeitC, _ortC, _themaC, _verlaufC, _ergebnisC, _notizC]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _save() async {
    if (_datumC.text.isEmpty || _zeitC.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Datum + Uhrzeit erforderlich'), backgroundColor: Colors.red));
      return;
    }
    setState(() => _saving = true);
    final terminPayload = {
      'user_av_id': widget.userAvId,
      'termin_datum': '${_datumC.text} ${_zeitC.text}:00',
      'termin_typ': _typ,
      'initiator': _initiator,
      'modus': _modus,
      'ort': _ortC.text.trim(),
      'status': _status,
      'thema': _themaC.text.trim(),
      'verlauf': _verlaufC.text.trim(),
      'ergebnis': _ergebnisC.text.trim(),
      'notiz': _notizC.text.trim(),
    };
    final res = widget.existing == null
      ? await widget.apiService.arbeitsagenturAvAction({'action': 'create_av_termin', 'user_id': widget.userId, 'termin': terminPayload})
      : await widget.apiService.arbeitsagenturAvAction({'action': 'update_av_termin', 'termin_id': widget.existing!['id'], 'termin': terminPayload});
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['success'] == true) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Fehler'), backgroundColor: Colors.red));
    }
  }

  Future<void> _pickDate() async {
    final init = DateTime.tryParse(_datumC.text) ?? DateTime.now();
    final p = await showDatePicker(context: context, initialDate: init, firstDate: DateTime(2010), lastDate: DateTime(2050), locale: const Locale('de'));
    if (p != null) setState(() => _datumC.text = p.toIso8601String().substring(0, 10));
  }

  Future<void> _pickTime() async {
    final parts = _zeitC.text.split(':');
    final init = parts.length == 2 ? TimeOfDay(hour: int.tryParse(parts[0]) ?? 9, minute: int.tryParse(parts[1]) ?? 0) : const TimeOfDay(hour: 9, minute: 0);
    final p = await showTimePicker(context: context, initialTime: init);
    if (p != null) setState(() => _zeitC.text = '${p.hour.toString().padLeft(2,'0')}:${p.minute.toString().padLeft(2,'0')}');
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? 'Neuer Termin' : 'Termin bearbeiten'),
    content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(child: TextField(controller: _datumC, readOnly: true, onTap: _pickDate, decoration: const InputDecoration(labelText: 'Datum', suffixIcon: Icon(Icons.calendar_today, size: 16), isDense: true, border: OutlineInputBorder()))),
        const SizedBox(width: 8),
        Expanded(child: TextField(controller: _zeitC, readOnly: true, onTap: _pickTime, decoration: const InputDecoration(labelText: 'Uhrzeit', suffixIcon: Icon(Icons.access_time, size: 16), isDense: true, border: OutlineInputBorder()))),
      ]),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        initialValue: _typ,
        decoration: const InputDecoration(labelText: 'Termin-Typ', isDense: true, border: OutlineInputBorder()),
        items: const ['erstgespraech','folgegespraech','vermittlung','beratung','meldetermin','reha','sonstige'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
        onChanged: (v) => setState(() => _typ = v ?? 'folgegespraech'),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: DropdownButtonFormField<String>(
          initialValue: _initiator,
          decoration: const InputDecoration(labelText: 'Initiator', isDense: true, border: OutlineInputBorder()),
          items: const ['arbeitsagentur','kunde','verein','sonstige'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
          onChanged: (v) => setState(() => _initiator = v ?? 'arbeitsagentur'),
        )),
        const SizedBox(width: 8),
        Expanded(child: DropdownButtonFormField<String>(
          initialValue: _modus,
          decoration: const InputDecoration(labelText: 'Modus', isDense: true, border: OutlineInputBorder()),
          items: const ['persoenlich','telefonisch','video','schriftlich'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
          onChanged: (v) => setState(() => _modus = v ?? 'persoenlich'),
        )),
      ]),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        initialValue: _status,
        decoration: const InputDecoration(labelText: 'Status', isDense: true, border: OutlineInputBorder()),
        items: const ['geplant','durchgefuehrt','versaeumt','abgesagt_kunde','abgesagt_aa','verschoben'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
        onChanged: (v) => setState(() => _status = v ?? 'geplant'),
      ),
      const SizedBox(height: 10),
      TextField(controller: _ortC, decoration: const InputDecoration(labelText: 'Ort', isDense: true, border: OutlineInputBorder())),
      const SizedBox(height: 10),
      TextField(controller: _themaC, maxLines: 2, decoration: const InputDecoration(labelText: 'Thema', isDense: true, border: OutlineInputBorder())),
      const SizedBox(height: 10),
      TextField(controller: _verlaufC, maxLines: 3, decoration: const InputDecoration(labelText: 'Verlauf', isDense: true, border: OutlineInputBorder())),
      const SizedBox(height: 10),
      TextField(controller: _ergebnisC, maxLines: 2, decoration: const InputDecoration(labelText: 'Ergebnis', isDense: true, border: OutlineInputBorder())),
      const SizedBox(height: 10),
      TextField(controller: _notizC, maxLines: 2, decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder())),
    ]))),
    actions: [
      TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Abbrechen')),
      ElevatedButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 16),
        label: const Text('Speichern'),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
      ),
    ],
  );
}

// ─────────────── Eigenbemühungen sub-tab ───────────────

class _AaAvEigenbemTab extends StatefulWidget {
  final ApiService apiService;
  final Map<String, dynamic> userAv;
  final VoidCallback onChanged;
  const _AaAvEigenbemTab({required this.apiService, required this.userAv, required this.onChanged});
  @override
  State<_AaAvEigenbemTab> createState() => _AaAvEigenbemTabState();
}

class _AaAvEigenbemTabState extends State<_AaAvEigenbemTab> {
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;

  static const _artLabel = {
    'stellenangebot_ba': 'Stellenangebot BA',
    'initiativbewerbung': 'Initiativbewerbung',
    'online_portal': 'Online-Portal',
    'zeitung': 'Zeitung',
    'vermittlung': 'Vermittlung',
    'sonstige': 'Sonstige',
  };
  static const _ergebnisColor = {
    'offen': Colors.amber,
    'laeuft': Colors.blue,
    'absage': Colors.red,
    'vorstellungsgespraech': Colors.purple,
    'einstellung': Colors.green,
    'keine_rueckmeldung': Colors.grey,
  };
  static const _ergebnisLabel = {
    'offen': 'Offen',
    'laeuft': 'Läuft',
    'absage': 'Absage',
    'vorstellungsgespraech': 'Vorstellungsgespräch',
    'einstellung': 'Einstellung',
    'keine_rueckmeldung': 'Keine Rückmeldung',
  };

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await widget.apiService.arbeitsagenturAvAction({
      'action': 'list_av_eigenbem', 'user_av_id': widget.userAv['id'],
    });
    if (!mounted) return;
    setState(() {
      _list = List<Map<String, dynamic>>.from(res['eigenbem'] ?? []);
      _loading = false;
    });
  }

  Future<void> _openEdit({Map<String, dynamic>? existing}) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _AaAvEigenbemEditDialog(
        apiService: widget.apiService,
        userId: (widget.userAv['user_id'] as num).toInt(),
        userAvId: (widget.userAv['id'] as num).toInt(),
        existing: existing,
      ),
    );
    if (changed == true) {
      widget.onChanged();
      _load();
    }
  }

  Future<void> _delete(int id) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Eintrag löschen?'),
      content: const Text('Der Eintrag wird unwiderruflich entfernt.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Löschen', style: TextStyle(color: Colors.red))),
      ],
    ));
    if (ok != true) return;
    final res = await widget.apiService.arbeitsagenturAvAction({'action': 'delete_av_eigenbem', 'eigenbem_id': id});
    if (res['success'] == true) { widget.onChanged(); _load(); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    // Group by month for visual sectioning.
    final byMonat = <String, List<Map<String, dynamic>>>{};
    for (final e in _list) {
      final m = (e['monat'] ?? '').toString();
      (byMonat[m] ??= []).add(e);
    }
    final monate = byMonat.keys.toList()..sort((a, b) => b.compareTo(a));
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: Colors.blue.shade50,
        child: Row(children: [
          Expanded(child: Text('${_list.length} Bewerbung(en) insgesamt', style: TextStyle(fontSize: 12, color: Colors.blue.shade700))),
          ElevatedButton.icon(
            onPressed: () => _openEdit(),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Neue Bewerbung', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
          ),
        ]),
      ),
      Expanded(child: _list.isEmpty
        ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.work_off, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 10),
            Text('Noch keine Eigenbemühungen erfasst', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ]))
        : ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: monate.length,
            itemBuilder: (_, mi) {
              final monat = monate[mi];
              final entries = byMonat[monat]!;
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.fromLTRB(4, 8, 4, 4), child: Text('📅 $monat (${entries.length})',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade800))),
                ...entries.map((e) {
                  final erg = (e['ergebnis'] ?? 'offen').toString();
                  final col = _ergebnisColor[erg] ?? Colors.grey;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 4),
                    elevation: 1,
                    child: InkWell(
                      onTap: () => _openEdit(existing: e),
                      child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text((e['arbeitgeber'] ?? '').toString(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: col.shade600, borderRadius: BorderRadius.circular(8)),
                            child: Text(_ergebnisLabel[erg] ?? erg, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700))),
                          IconButton(icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28), onPressed: () => _delete((e['id'] as num).toInt())),
                        ]),
                        if ((e['taetigkeit'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text((e['taetigkeit']).toString(), style: const TextStyle(fontSize: 11))),
                        Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [
                          Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(3)),
                            child: Text(_artLabel[(e['art'] ?? 'sonstige').toString()] ?? (e['art'] ?? '').toString(), style: TextStyle(fontSize: 10, color: Colors.indigo.shade800))),
                          const SizedBox(width: 6),
                          if ((e['datum_bewerbung'] ?? '').toString().isNotEmpty) Text((e['datum_bewerbung']).toString(), style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                        ])),
                      ])),
                    ),
                  );
                }),
              ]);
            },
          )),
    ]);
  }
}

class _AaAvEigenbemEditDialog extends StatefulWidget {
  final ApiService apiService;
  final int userId, userAvId;
  final Map<String, dynamic>? existing;
  const _AaAvEigenbemEditDialog({required this.apiService, required this.userId, required this.userAvId, this.existing});
  @override
  State<_AaAvEigenbemEditDialog> createState() => _AaAvEigenbemEditDialogState();
}

class _AaAvEigenbemEditDialogState extends State<_AaAvEigenbemEditDialog> {
  late TextEditingController _monatC, _arbeitgeberC, _taetigkeitC, _adresseC, _datumBewC, _notizC;
  String _art = 'sonstige', _ergebnis = 'offen';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final now = DateTime.now();
    _monatC = TextEditingController(text: e?['monat']?.toString() ?? '${now.year}-${now.month.toString().padLeft(2,'0')}');
    _arbeitgeberC = TextEditingController(text: e?['arbeitgeber']?.toString() ?? '');
    _taetigkeitC  = TextEditingController(text: e?['taetigkeit']?.toString() ?? '');
    _adresseC     = TextEditingController(text: e?['adresse']?.toString() ?? '');
    _datumBewC    = TextEditingController(text: e?['datum_bewerbung']?.toString() ?? '');
    _notizC       = TextEditingController(text: e?['notiz']?.toString() ?? '');
    if (e != null) {
      _art      = e['art']?.toString()      ?? 'sonstige';
      _ergebnis = e['ergebnis']?.toString() ?? 'offen';
    }
  }

  @override
  void dispose() {
    for (final c in [_monatC, _arbeitgeberC, _taetigkeitC, _adresseC, _datumBewC, _notizC]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _pickMonth() async {
    final now = DateTime.tryParse('${_monatC.text}-01') ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2010), lastDate: DateTime(2050),
      locale: const Locale('de'),
      helpText: 'Monat wählen (Tag wird ignoriert)',
    );
    if (picked != null) setState(() => _monatC.text = '${picked.year}-${picked.month.toString().padLeft(2,'0')}');
  }

  Future<void> _pickBewDate() async {
    final init = DateTime.tryParse(_datumBewC.text) ?? DateTime.now();
    final p = await showDatePicker(context: context, initialDate: init, firstDate: DateTime(2010), lastDate: DateTime(2050), locale: const Locale('de'));
    if (p != null) setState(() => _datumBewC.text = p.toIso8601String().substring(0, 10));
  }

  Future<void> _save() async {
    if (_arbeitgeberC.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Arbeitgeber erforderlich'), backgroundColor: Colors.red));
      return;
    }
    if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(_monatC.text)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Monat im Format YYYY-MM angeben'), backgroundColor: Colors.red));
      return;
    }
    setState(() => _saving = true);
    final payload = {
      'user_av_id': widget.userAvId,
      'monat': _monatC.text.trim(),
      'arbeitgeber': _arbeitgeberC.text.trim(),
      'taetigkeit': _taetigkeitC.text.trim(),
      'adresse': _adresseC.text.trim(),
      'datum_bewerbung': _datumBewC.text.trim().isEmpty ? null : _datumBewC.text.trim(),
      'art': _art,
      'ergebnis': _ergebnis,
      'notiz': _notizC.text.trim(),
    };
    final res = widget.existing == null
      ? await widget.apiService.arbeitsagenturAvAction({'action': 'create_av_eigenbem', 'user_id': widget.userId, 'eigenbem': payload})
      : await widget.apiService.arbeitsagenturAvAction({'action': 'update_av_eigenbem', 'eigenbem_id': widget.existing!['id'], 'eigenbem': payload});
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['success'] == true) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Fehler'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? 'Neue Eigenbemühung' : 'Eigenbemühung bearbeiten'),
    content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(child: TextField(controller: _monatC, readOnly: true, onTap: _pickMonth, decoration: const InputDecoration(labelText: 'Monat (YYYY-MM)', suffixIcon: Icon(Icons.calendar_month, size: 16), isDense: true, border: OutlineInputBorder()))),
        const SizedBox(width: 8),
        Expanded(child: TextField(controller: _datumBewC, readOnly: true, onTap: _pickBewDate, decoration: const InputDecoration(labelText: 'Datum Bewerbung', suffixIcon: Icon(Icons.calendar_today, size: 16), isDense: true, border: OutlineInputBorder()))),
      ]),
      const SizedBox(height: 10),
      TextField(controller: _arbeitgeberC, decoration: const InputDecoration(labelText: 'Arbeitgeber *', isDense: true, border: OutlineInputBorder())),
      const SizedBox(height: 10),
      TextField(controller: _taetigkeitC, maxLines: 2, decoration: const InputDecoration(labelText: 'Tätigkeit / Stelle', isDense: true, border: OutlineInputBorder())),
      const SizedBox(height: 10),
      TextField(controller: _adresseC, maxLines: 2, decoration: const InputDecoration(labelText: 'Adresse', isDense: true, border: OutlineInputBorder())),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        initialValue: _art,
        decoration: const InputDecoration(labelText: 'Art', isDense: true, border: OutlineInputBorder()),
        items: const ['stellenangebot_ba','initiativbewerbung','online_portal','zeitung','vermittlung','sonstige'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
        onChanged: (v) => setState(() => _art = v ?? 'sonstige'),
      ),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        initialValue: _ergebnis,
        decoration: const InputDecoration(labelText: 'Ergebnis', isDense: true, border: OutlineInputBorder()),
        items: const ['offen','laeuft','absage','vorstellungsgespraech','einstellung','keine_rueckmeldung'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
        onChanged: (v) => setState(() => _ergebnis = v ?? 'offen'),
      ),
      const SizedBox(height: 10),
      TextField(controller: _notizC, maxLines: 2, decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder())),
    ]))),
    actions: [
      TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Abbrechen')),
      ElevatedButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 16),
        label: const Text('Speichern'),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
      ),
    ],
  );
}

// ============================================================================
// Antrag-zentrisches Detail-Modal für Arbeitsagentur.
// Ein Antrag durchläuft die Stufen Arbeitssuchend- → Arbeitslosenmeldung →
// ALG-Antrag → Bewilligungsbescheid, plus Korrespondenz. Formulardaten liegen
// pro bereich in arbeitsagentur_antrag_data, Unterlagen inline pro bereich in
// arbeitsagentur_antrag_docs, Korrespondenz in arbeitsagentur_antrag_korr.
// ============================================================================

const Color _aaBrandC = Color(0xFF003F7D);

String aaArtLabel(String v) {
  switch (v) {
    case 'arbeitslosigkeit': return 'Arbeitslosigkeit (ALG I)';
    case 'arbeitsuchend_meldung': return 'Arbeitsuchendmeldung';
    case 'weiterbewilligung': return 'Weiterbewilligungsantrag';
    case 'wiederholung': return 'Wiederholungsantrag';
    case 'insolvenzantrag': return 'Insolvenzgeld-Antrag';
    default: return v.isEmpty ? 'Antrag' : v;
  }
}

String aaStatusLabel(String v) {
  switch (v) {
    case 'neu': return 'Neu';
    case 'arbeitssuchend': return 'Arbeitssuchend gemeldet';
    case 'arbeitslos': return 'Arbeitslos gemeldet';
    case 'antrag_gestellt': return 'ALG-Antrag gestellt';
    case 'in_bearbeitung': return 'In Bearbeitung';
    case 'bewilligt': return 'Bewilligt';
    case 'abgelehnt': return 'Abgelehnt';
    case 'zurueckgezogen': return 'Zurückgezogen';
    default: return v.isEmpty ? 'Neu' : v;
  }
}

Color aaStatusColor(String v) {
  switch (v) {
    case 'bewilligt': return Colors.green.shade600;
    case 'abgelehnt': return Colors.red.shade600;
    case 'in_bearbeitung':
    case 'antrag_gestellt': return Colors.orange.shade700;
    case 'zurueckgezogen': return Colors.grey.shade600;
    default: return _aaBrandC;
  }
}

const List<DropdownMenuItem<String>> _aaArtItems = [
  DropdownMenuItem(value: 'arbeitslosigkeit', child: Text('Arbeitslosigkeit (ALG I)', style: TextStyle(fontSize: 13))),
  DropdownMenuItem(value: 'arbeitsuchend_meldung', child: Text('Arbeitsuchendmeldung (§ 38 SGB III)', style: TextStyle(fontSize: 13))),
  DropdownMenuItem(value: 'weiterbewilligung', child: Text('Weiterbewilligungsantrag', style: TextStyle(fontSize: 13))),
  DropdownMenuItem(value: 'wiederholung', child: Text('Wiederholungsantrag', style: TextStyle(fontSize: 13))),
  DropdownMenuItem(value: 'insolvenzantrag', child: Text('Insolvenzgeld-Antrag', style: TextStyle(fontSize: 13))),
];
const List<DropdownMenuItem<String>> _aaStatusItems = [
  DropdownMenuItem(value: 'neu', child: Text('Neu', style: TextStyle(fontSize: 13))),
  DropdownMenuItem(value: 'arbeitssuchend', child: Text('Arbeitssuchend gemeldet', style: TextStyle(fontSize: 13))),
  DropdownMenuItem(value: 'arbeitslos', child: Text('Arbeitslos gemeldet', style: TextStyle(fontSize: 13))),
  DropdownMenuItem(value: 'antrag_gestellt', child: Text('ALG-Antrag gestellt', style: TextStyle(fontSize: 13))),
  DropdownMenuItem(value: 'in_bearbeitung', child: Text('In Bearbeitung', style: TextStyle(fontSize: 13))),
  DropdownMenuItem(value: 'bewilligt', child: Text('Bewilligt', style: TextStyle(fontSize: 13))),
  DropdownMenuItem(value: 'abgelehnt', child: Text('Abgelehnt', style: TextStyle(fontSize: 13))),
  DropdownMenuItem(value: 'zurueckgezogen', child: Text('Zurückgezogen', style: TextStyle(fontSize: 13))),
];
const List<DropdownMenuItem<String>> _aaJaNein = [
  DropdownMenuItem(value: 'ja', child: Text('Ja', style: TextStyle(fontSize: 13))),
  DropdownMenuItem(value: 'nein', child: Text('Nein', style: TextStyle(fontSize: 13))),
];
const List<DropdownMenuItem<String>> _aaKuendigungsartItems = [
  DropdownMenuItem(value: 'arbeitgeber', child: Text('Arbeitgeberkündigung', style: TextStyle(fontSize: 13))),
  DropdownMenuItem(value: 'eigen', child: Text('Eigenkündigung', style: TextStyle(fontSize: 13))),
  DropdownMenuItem(value: 'aufhebung', child: Text('Aufhebungsvertrag', style: TextStyle(fontSize: 13))),
  DropdownMenuItem(value: 'befristung', child: Text('Befristung ausgelaufen', style: TextStyle(fontSize: 13))),
  DropdownMenuItem(value: 'insolvenz', child: Text('Insolvenz', style: TextStyle(fontSize: 13))),
];
const List<DropdownMenuItem<String>> _aaAlgArtItems = [
  DropdownMenuItem(value: 'erstantrag', child: Text('Erstantrag ALG I', style: TextStyle(fontSize: 13))),
  DropdownMenuItem(value: 'weiterbewilligung', child: Text('Weiterbewilligungsantrag', style: TextStyle(fontSize: 13))),
  DropdownMenuItem(value: 'wiederholung', child: Text('Wiederholungsantrag', style: TextStyle(fontSize: 13))),
];
const List<DropdownMenuItem<String>> _aaLeistungssatzItems = [
  DropdownMenuItem(value: '60', child: Text('60% (allgemein)', style: TextStyle(fontSize: 13))),
  DropdownMenuItem(value: '67', child: Text('67% (mit Kind)', style: TextStyle(fontSize: 13))),
];
const List<DropdownMenuItem<String>> _aaBewilligtItems = [
  DropdownMenuItem(value: 'ja', child: Text('Bewilligt', style: TextStyle(fontSize: 13))),
  DropdownMenuItem(value: 'teilweise', child: Text('Teilweise bewilligt', style: TextStyle(fontSize: 13))),
  DropdownMenuItem(value: 'nein', child: Text('Abgelehnt', style: TextStyle(fontSize: 13))),
];

class _AaAntragDetailView extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int antragId;
  final Map<String, dynamic> antrag;
  final VoidCallback onChanged;
  final VoidCallback onClose;
  const _AaAntragDetailView({required this.apiService, required this.userId, required this.antragId, required this.antrag, required this.onChanged, required this.onClose});
  @override
  State<_AaAntragDetailView> createState() => _AaAntragDetailViewState();
}

class _AaAntragDetailViewState extends State<_AaAntragDetailView> {
  Map<String, dynamic> _data = {};
  late Map<String, dynamic> _antrag;
  bool _loaded = false, _savingDetails = false;

  @override
  void initState() { super.initState(); _antrag = Map<String, dynamic>.from(widget.antrag); _load(); }

  Future<void> _load() async {
    final r = await widget.apiService.getAaAntragData(widget.antragId);
    if (!mounted) return;
    setState(() {
      _data = (r['success'] == true && r['data'] is Map) ? Map<String, dynamic>.from(r['data'] as Map) : {};
      _loaded = true;
    });
  }

  String _v(String key) => _data[key]?.toString() ?? '';

  Future<void> _saveBereich(String bereich, Map<String, String> fields) async {
    final payload = <String, dynamic>{};
    fields.forEach((k, val) => payload['$bereich.$k'] = val);
    final r = await widget.apiService.saveAaAntragData(widget.antragId, payload);
    if (!mounted) return;
    if (r['success'] == true) {
      fields.forEach((k, val) => _data['$bereich.$k'] = val);
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gespeichert'), backgroundColor: Colors.green));
      widget.onChanged();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fehler beim Speichern'), backgroundColor: Colors.red));
    }
  }

  Future<void> _saveDetails(String art, String status, String datum, String notiz) async {
    setState(() => _savingDetails = true);
    final r = await widget.apiService.saveArbeitsagenturAntrag(widget.userId, {
      'id': widget.antragId, 'art': art, 'status': status, 'datum': datum, 'notiz': notiz,
    });
    if (!mounted) return;
    setState(() {
      _savingDetails = false;
      if (r['success'] == true) { _antrag['art'] = art; _antrag['status'] = status; _antrag['datum'] = datum; _antrag['notiz'] = notiz; }
    });
    if (r['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gespeichert'), backgroundColor: Colors.green));
      widget.onChanged();
    }
  }

  Widget _tf(String label, TextEditingController c, {String hint = '', IconData icon = Icons.edit, int maxLines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
      const SizedBox(height: 4),
      TextField(controller: c, maxLines: maxLines, decoration: InputDecoration(hintText: hint, prefixIcon: Icon(icon, size: 20), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)), style: const TextStyle(fontSize: 14)),
    ]),
  );

  Widget _df(String label, TextEditingController c) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
      const SizedBox(height: 4),
      TextField(controller: c, readOnly: true, decoration: InputDecoration(hintText: 'TT.MM.JJJJ', prefixIcon: const Icon(Icons.calendar_today, size: 20), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
        onTap: () async {
          final picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de'));
          if (picked != null) c.text = '${picked.day.toString().padLeft(2, '0')}.${picked.month.toString().padLeft(2, '0')}.${picked.year}';
        }),
    ]),
  );

  Widget _dd(String label, String value, List<DropdownMenuItem<String>> items, ValueChanged<String> onChanged) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
      const SizedBox(height: 4),
      DropdownButtonFormField<String>(initialValue: value.isEmpty ? null : value, isExpanded: true,
        decoration: InputDecoration(isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
        hint: const Text('Auswählen...', style: TextStyle(fontSize: 13)), items: items, onChanged: (v) => onChanged(v ?? '')),
    ]),
  );

  Widget _saveBar(VoidCallback onSave) => Align(alignment: Alignment.centerRight, child: Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 8),
    child: ElevatedButton.icon(onPressed: onSave, icon: const Icon(Icons.save, size: 18), label: const Text('Speichern'),
      style: ElevatedButton.styleFrom(backgroundColor: _aaBrandC, foregroundColor: Colors.white)),
  ));

  @override
  Widget build(BuildContext context) {
    final status = _antrag['status']?.toString() ?? '';
    return Column(children: [
      Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        decoration: BoxDecoration(color: aaStatusColor(status).withValues(alpha: 0.12), border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
        child: Row(children: [
          Icon(Icons.assignment, color: aaStatusColor(status)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(aaArtLabel(_antrag['art']?.toString() ?? ''), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            Text(aaStatusLabel(status), style: TextStyle(fontSize: 12, color: aaStatusColor(status), fontWeight: FontWeight.w600)),
          ])),
          IconButton(icon: const Icon(Icons.close), tooltip: 'Schließen', onPressed: widget.onClose),
        ]),
      ),
      Expanded(child: !_loaded
        ? const Center(child: CircularProgressIndicator())
        : DefaultTabController(length: 6, child: Column(children: [
            Material(color: Colors.white, child: TabBar(isScrollable: true, tabAlignment: TabAlignment.start,
              labelColor: _aaBrandC, unselectedLabelColor: Colors.grey, indicatorColor: _aaBrandC,
              labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold), unselectedLabelStyle: const TextStyle(fontSize: 11),
              tabs: const [
                Tab(icon: Icon(Icons.info_outline, size: 16), text: 'Details'),
                Tab(icon: Icon(Icons.person_search, size: 16), text: 'Arbeitssuchend'),
                Tab(icon: Icon(Icons.person_off, size: 16), text: 'Arbeitslos'),
                Tab(icon: Icon(Icons.request_page, size: 16), text: 'ALG-Antrag'),
                Tab(icon: Icon(Icons.verified, size: 16), text: 'Bescheid'),
                Tab(icon: Icon(Icons.mail, size: 16), text: 'Korrespondenz'),
              ])),
            Expanded(child: TabBarView(children: [
              _buildDetailsTab(),
              _buildArbeitssuchendTab(),
              _buildArbeitslosTab(),
              _buildAlgAntragTab(),
              _buildBescheidTab(),
              _AaAntragKorrSection(apiService: widget.apiService, antragId: widget.antragId),
            ])),
          ])),
      ),
    ]);
  }

  Widget _buildDetailsTab() {
    String art = (_antrag['art']?.toString() ?? '').isEmpty ? 'arbeitslosigkeit' : _antrag['art'].toString();
    String status = (_antrag['status']?.toString() ?? '').isEmpty ? 'neu' : _antrag['status'].toString();
    final datumC = TextEditingController(text: _antrag['datum']?.toString() ?? '');
    final notizC = TextEditingController(text: _antrag['notiz']?.toString() ?? '');
    return StatefulBuilder(builder: (ctx, setLocal) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dd('Art des Antrags', art, _aaArtItems, (v) => setLocal(() => art = v)),
      _dd('Status', status, _aaStatusItems, (v) => setLocal(() => status = v)),
      _df('Datum', datumC),
      _tf('Notiz', notizC, hint: 'Interne Notiz', icon: Icons.sticky_note_2, maxLines: 3),
      _savingDetails
        ? const Align(alignment: Alignment.centerRight, child: Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
        : _saveBar(() => _saveDetails(art, status, datumC.text.trim(), notizC.text.trim())),
    ])));
  }

  Widget _buildArbeitssuchendTab() {
    final suchendC = TextEditingController(text: _v('arbeitssuchendmeldung.arbeitssuchend_datum'));
    final letzterC = TextEditingController(text: _v('arbeitssuchendmeldung.letzter_arbeitstag'));
    final taetigkeitC = TextEditingController(text: _v('arbeitssuchendmeldung.letzte_taetigkeit'));
    final endeC = TextEditingController(text: _v('arbeitssuchendmeldung.taetigkeit_ende_datum'));
    final svC = TextEditingController(text: _v('arbeitssuchendmeldung.sv_nummer'));
    String faehig = _v('arbeitssuchendmeldung.gesundheitlich_faehig');
    final notizC = TextEditingController(text: _v('arbeitssuchendmeldung.notiz'));
    return StatefulBuilder(builder: (ctx, setLocal) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(Icons.person_search, size: 18, color: Colors.blue.shade700), const SizedBox(width: 8), Text('Arbeitssuchendmeldung (§ 38 SGB III)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue.shade700))]),
      const SizedBox(height: 12),
      _df('Arbeitssuchend gemeldet am', suchendC),
      _df('Letzter Arbeitstag', letzterC),
      _tf('Letzte Tätigkeit', taetigkeitC, hint: 'z.B. Lagerarbeiter', icon: Icons.work),
      _df('Tätigkeit beendet am', endeC),
      _tf('SV-Nummer', svC, hint: 'Sozialversicherungsnummer', icon: Icons.badge),
      _dd('Gesundheitlich arbeitsfähig?', faehig, _aaJaNein, (v) => setLocal(() => faehig = v)),
      _tf('Notiz', notizC, hint: '', icon: Icons.sticky_note_2, maxLines: 2),
      _saveBar(() => _saveBereich('arbeitssuchendmeldung', {
        'arbeitssuchend_datum': suchendC.text.trim(), 'letzter_arbeitstag': letzterC.text.trim(),
        'letzte_taetigkeit': taetigkeitC.text.trim(), 'taetigkeit_ende_datum': endeC.text.trim(),
        'sv_nummer': svC.text.trim(), 'gesundheitlich_faehig': faehig, 'notiz': notizC.text.trim(),
      })),
      const Divider(height: 28),
      _AaAntragDocsSection(apiService: widget.apiService, antragId: widget.antragId, bereich: 'arbeitssuchendmeldung'),
    ])));
  }

  Widget _buildArbeitslosTab() {
    final losC = TextEditingController(text: _v('arbeitslosenmeldung.arbeitslos_datum'));
    String kuendigungsart = _v('arbeitslosenmeldung.kuendigungsart');
    String schwerbeh = _v('arbeitslosenmeldung.has_schwerbehinderung');
    final erreichbarC = TextEditingController(text: _v('arbeitslosenmeldung.erreichbarkeit'));
    final krankengeldC = TextEditingController(text: _v('arbeitslosenmeldung.krankengeld_ende'));
    String datenschutz = _v('arbeitslosenmeldung.datenschutz_kenntnisnahme');
    final notizC = TextEditingController(text: _v('arbeitslosenmeldung.notiz'));
    return StatefulBuilder(builder: (ctx, setLocal) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(Icons.person_off, size: 18, color: Colors.brown.shade700), const SizedBox(width: 8), Text('Arbeitslosenmeldung (§ 141 SGB III)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.brown.shade700))]),
      const SizedBox(height: 12),
      _df('Arbeitslos gemeldet am', losC),
      _dd('Kündigungsart', kuendigungsart, _aaKuendigungsartItems, (v) => setLocal(() => kuendigungsart = v)),
      _dd('Schwerbehinderung?', schwerbeh, _aaJaNein, (v) => setLocal(() => schwerbeh = v)),
      _tf('Erreichbarkeit', erreichbarC, hint: 'z.B. Telefon / E-Mail', icon: Icons.contact_phone),
      _df('Krankengeld-Ende', krankengeldC),
      _dd('Datenschutz zur Kenntnis genommen?', datenschutz, _aaJaNein, (v) => setLocal(() => datenschutz = v)),
      _tf('Notiz', notizC, hint: '', icon: Icons.sticky_note_2, maxLines: 2),
      _saveBar(() => _saveBereich('arbeitslosenmeldung', {
        'arbeitslos_datum': losC.text.trim(), 'kuendigungsart': kuendigungsart,
        'has_schwerbehinderung': schwerbeh, 'erreichbarkeit': erreichbarC.text.trim(),
        'krankengeld_ende': krankengeldC.text.trim(), 'datenschutz_kenntnisnahme': datenschutz, 'notiz': notizC.text.trim(),
      })),
      const Divider(height: 28),
      _AaAntragDocsSection(apiService: widget.apiService, antragId: widget.antragId, bereich: 'arbeitslosenmeldung'),
    ])));
  }

  Widget _buildAlgAntragTab() {
    final datumC = TextEditingController(text: _v('alg_antrag.antrag_datum'));
    String algArt = _v('alg_antrag.antrag_art');
    String online = _v('alg_antrag.online_eingereicht');
    final azC = TextEditingController(text: _v('alg_antrag.aktenzeichen'));
    final notizC = TextEditingController(text: _v('alg_antrag.notiz'));
    return StatefulBuilder(builder: (ctx, setLocal) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(Icons.request_page, size: 18, color: Colors.indigo.shade700), const SizedBox(width: 8), Text('Arbeitslosengeld-Antrag (ALG I)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo.shade700))]),
      const SizedBox(height: 12),
      _df('Antrag gestellt am', datumC),
      _dd('Antragsart', algArt, _aaAlgArtItems, (v) => setLocal(() => algArt = v)),
      _dd('Online eingereicht?', online, _aaJaNein, (v) => setLocal(() => online = v)),
      _tf('Aktenzeichen', azC, hint: 'Aktenzeichen der Agentur', icon: Icons.tag),
      _tf('Notiz', notizC, hint: '', icon: Icons.sticky_note_2, maxLines: 2),
      _saveBar(() => _saveBereich('alg_antrag', {
        'antrag_datum': datumC.text.trim(), 'antrag_art': algArt, 'online_eingereicht': online,
        'aktenzeichen': azC.text.trim(), 'notiz': notizC.text.trim(),
      })),
      const Divider(height: 28),
      _AaAntragDocsSection(apiService: widget.apiService, antragId: widget.antragId, bereich: 'alg_antrag'),
    ])));
  }

  Widget _buildBescheidTab() {
    final datumC = TextEditingController(text: _v('bescheid.bescheid_datum'));
    String bewilligt = _v('bescheid.bewilligt');
    final vonC = TextEditingController(text: _v('bescheid.zeitraum_von'));
    final bisC = TextEditingController(text: _v('bescheid.zeitraum_bis'));
    final leistungC = TextEditingController(text: _v('bescheid.leistungssatz_betrag'));
    String leistungTyp = _v('bescheid.leistungssatz_typ');
    final bemessungC = TextEditingController(text: _v('bescheid.bemessungsentgelt'));
    final anspruchC = TextEditingController(text: _v('bescheid.anspruchsdauer'));
    final restC = TextEditingController(text: _v('bescheid.restanspruch'));
    final notizC = TextEditingController(text: _v('bescheid.notiz'));
    return StatefulBuilder(builder: (ctx, setLocal) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(Icons.verified, size: 18, color: Colors.green.shade700), const SizedBox(width: 8), Text('Bewilligungsbescheid (ALG I)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green.shade700))]),
      const SizedBox(height: 12),
      _df('Bescheiddatum', datumC),
      _dd('Ergebnis', bewilligt, _aaBewilligtItems, (v) => setLocal(() => bewilligt = v)),
      Row(children: [Expanded(child: _df('Bewilligung von', vonC)), const SizedBox(width: 12), Expanded(child: _df('Bewilligung bis', bisC))]),
      Row(children: [
        Expanded(child: _tf('Täglicher Leistungssatz (EUR)', leistungC, hint: 'z.B. 38.50', icon: Icons.euro)),
        const SizedBox(width: 12),
        Expanded(child: _dd('Leistungssatz', leistungTyp, _aaLeistungssatzItems, (v) => setLocal(() => leistungTyp = v))),
      ]),
      _tf('Bemessungsentgelt (EUR/Tag)', bemessungC, hint: 'Tägliches Bemessungsentgelt', icon: Icons.account_balance_wallet),
      Row(children: [
        Expanded(child: _tf('Anspruchsdauer (Tage)', anspruchC, hint: 'z.B. 360', icon: Icons.timer)),
        const SizedBox(width: 12),
        Expanded(child: _tf('Restanspruch (Tage)', restC, hint: 'Verbleibende Tage', icon: Icons.hourglass_bottom)),
      ]),
      _tf('Notiz', notizC, hint: '', icon: Icons.sticky_note_2, maxLines: 2),
      _saveBar(() => _saveBereich('bescheid', {
        'bescheid_datum': datumC.text.trim(), 'bewilligt': bewilligt,
        'zeitraum_von': vonC.text.trim(), 'zeitraum_bis': bisC.text.trim(),
        'leistungssatz_betrag': leistungC.text.trim(), 'leistungssatz_typ': leistungTyp,
        'bemessungsentgelt': bemessungC.text.trim(), 'anspruchsdauer': anspruchC.text.trim(),
        'restanspruch': restC.text.trim(), 'notiz': notizC.text.trim(),
      })),
      const Divider(height: 28),
      _AaAntragDocsSection(apiService: widget.apiService, antragId: widget.antragId, bereich: 'bescheid'),
    ])));
  }
}

// ---- Unterlagen pro Antrag-Bereich (verschlüsselt) ----
class _AaAntragDocsSection extends StatefulWidget {
  final ApiService apiService;
  final int antragId;
  final String bereich;
  const _AaAntragDocsSection({required this.apiService, required this.antragId, required this.bereich});
  @override
  State<_AaAntragDocsSection> createState() => _AaAntragDocsSectionState();
}

class _AaAntragDocsSectionState extends State<_AaAntragDocsSection> {
  List<Map<String, dynamic>> _docs = [];
  bool _loaded = false, _busy = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final r = await widget.apiService.listAaAntragDocs(widget.antragId, bereich: widget.bereich);
    if (!mounted) return;
    setState(() {
      _docs = (r['success'] == true && r['data'] is List) ? (r['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList() : [];
      _loaded = true;
    });
  }

  void _snack(String m) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m))); }

  Future<void> _upload() async {
    final result = await FilePickerHelper.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'], allowMultiple: true);
    if (result == null || result.files.isEmpty) return;
    setState(() => _busy = true);
    for (final f in result.files.where((f) => f.path != null)) {
      final res = await widget.apiService.uploadAaAntragDoc(antragId: widget.antragId, bereich: widget.bereich, filePath: f.path!, fileName: f.name);
      if (res['success'] != true) _snack('Upload fehlgeschlagen: ${f.name}');
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _load();
  }

  Future<File?> _fetch(Map<String, dynamic> d) async {
    final resp = await widget.apiService.downloadAaAntragDoc(d['id'] as int);
    if (resp.statusCode != 200) return null;
    final dir = await getTemporaryDirectory();
    final name = (d['datei_name'] ?? 'dokument').toString();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(resp.bodyBytes);
    return file;
  }

  Future<void> _view(Map<String, dynamic> d) async {
    final f = await _fetch(d);
    if (f != null && mounted) await FileViewerDialog.show(context, f.path, (d['datei_name'] ?? '').toString());
  }

  Future<void> _openExtern(Map<String, dynamic> d) async {
    final f = await _fetch(d);
    if (f != null) await OpenFilex.open(f.path);
  }

  Future<void> _delete(Map<String, dynamic> d) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Dokument löschen?'),
      content: Text((d['datei_name'] ?? '').toString()),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Löschen', style: TextStyle(color: Colors.red))),
      ],
    ));
    if (ok != true) return;
    await widget.apiService.deleteAaAntragDoc(d['id'] as int);
    _load();
  }

  IconData _iconFor(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (n.endsWith('.jpg') || n.endsWith('.jpeg') || n.endsWith('.png')) return Icons.image;
    return Icons.insert_drive_file;
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.folder, size: 16, color: Colors.grey.shade600), const SizedBox(width: 6),
        Text('Unterlagen (${_docs.length})', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const Spacer(),
        TextButton.icon(
          onPressed: _busy ? null : _upload,
          icon: _busy ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.upload_file, size: 16),
          label: const Text('Hochladen', style: TextStyle(fontSize: 12)),
        ),
      ]),
      if (!_loaded)
        const Padding(padding: EdgeInsets.all(8), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))))
      else if (_docs.isEmpty)
        Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Keine Unterlagen', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)))
      else
        ..._docs.map((d) {
          final name = (d['datei_name'] ?? '').toString();
          return Card(margin: const EdgeInsets.symmetric(vertical: 3), child: ListTile(
            dense: true,
            leading: Icon(_iconFor(name), color: _aaBrandC, size: 20),
            title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: Icon(Icons.visibility, size: 18, color: Colors.indigo.shade600), tooltip: 'Ansehen', onPressed: () => _view(d)),
              IconButton(icon: Icon(Icons.open_in_new, size: 18, color: Colors.green.shade700), tooltip: 'Öffnen', onPressed: () => _openExtern(d)),
              IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400), tooltip: 'Löschen', onPressed: () => _delete(d)),
            ]),
          ));
        }),
    ]);
  }
}

// ---- Korrespondenz pro Antrag ----
class _AaAntragKorrSection extends StatefulWidget {
  final ApiService apiService;
  final int antragId;
  const _AaAntragKorrSection({required this.apiService, required this.antragId});
  @override
  State<_AaAntragKorrSection> createState() => _AaAntragKorrSectionState();
}

class _AaAntragKorrSectionState extends State<_AaAntragKorrSection> {
  List<Map<String, dynamic>> _korr = [];
  bool _loaded = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final r = await widget.apiService.listAaAntragKorr(widget.antragId);
    if (!mounted) return;
    setState(() {
      _korr = (r['success'] == true && r['data'] is List) ? (r['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList() : [];
      _loaded = true;
    });
  }

  Future<void> _add(String richtung) async {
    final datumC = TextEditingController();
    final betreffC = TextEditingController();
    final notizC = TextEditingController();
    String methode = 'brief';
    bool saving = false;
    await showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) => AlertDialog(
      title: Text(richtung == 'eingang' ? 'Eingang erfassen' : 'Ausgang erfassen', style: const TextStyle(fontSize: 16)),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(controller: datumC, readOnly: true, decoration: const InputDecoration(labelText: 'Datum', hintText: 'TT.MM.JJJJ', isDense: true, border: OutlineInputBorder()),
          onTap: () async {
            final picked = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de'));
            if (picked != null) datumC.text = '${picked.day.toString().padLeft(2, '0')}.${picked.month.toString().padLeft(2, '0')}.${picked.year}';
          }),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(initialValue: methode, decoration: const InputDecoration(labelText: 'Kontaktart', isDense: true, border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'brief', child: Text('Brief')),
            DropdownMenuItem(value: 'email', child: Text('E-Mail')),
            DropdownMenuItem(value: 'telefon', child: Text('Telefon')),
            DropdownMenuItem(value: 'persoenlich', child: Text('Persönlich')),
            DropdownMenuItem(value: 'online', child: Text('Online-Portal')),
          ], onChanged: (v) => setD(() => methode = v ?? 'brief')),
        const SizedBox(height: 10),
        TextField(controller: betreffC, decoration: const InputDecoration(labelText: 'Betreff', isDense: true, border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: notizC, maxLines: 3, decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder())),
      ]))),
      actions: [
        TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: saving ? null : () async {
          setD(() => saving = true);
          await widget.apiService.saveAaAntragKorr(widget.antragId, {
            'richtung': richtung, 'datum': datumC.text.trim(), 'methode': methode,
            'betreff': betreffC.text.trim(), 'notiz': notizC.text.trim(),
          });
          if (!ctx2.mounted) return;
          Navigator.pop(ctx);
          _load();
        }, child: saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Speichern')),
      ],
    )));
  }

  Future<void> _delete(int id) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Eintrag löschen?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
        TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Löschen', style: TextStyle(color: Colors.red))),
      ],
    ));
    if (ok != true) return;
    await widget.apiService.deleteAaAntragKorr(id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Row(children: [
        Icon(Icons.mail, size: 18, color: _aaBrandC), const SizedBox(width: 8),
        Text('Korrespondenz (${_korr.length})', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _aaBrandC)),
        const Spacer(),
        OutlinedButton.icon(onPressed: () => _add('eingang'), icon: const Icon(Icons.call_received, size: 16), label: const Text('Eingang', style: TextStyle(fontSize: 12))),
        const SizedBox(width: 6),
        OutlinedButton.icon(onPressed: () => _add('ausgang'), icon: const Icon(Icons.call_made, size: 16), label: const Text('Ausgang', style: TextStyle(fontSize: 12))),
      ])),
      Expanded(child: _korr.isEmpty
        ? Center(child: Text('Keine Korrespondenz', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _korr.length, itemBuilder: (_, i) {
            final k = _korr[i];
            final eingang = (k['richtung']?.toString() ?? 'eingang') == 'eingang';
            return Card(child: ListTile(
              dense: true,
              leading: Icon(eingang ? Icons.call_received : Icons.call_made, color: eingang ? Colors.green.shade700 : Colors.blue.shade700),
              title: Text((k['betreff']?.toString() ?? '').isEmpty ? '(ohne Betreff)' : k['betreff'].toString(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text('${k['datum'] ?? ''}  •  ${k['methode'] ?? ''}${(k['notiz']?.toString() ?? '').isNotEmpty ? '\n${k['notiz']}' : ''}', style: const TextStyle(fontSize: 11)),
              isThreeLine: (k['notiz']?.toString() ?? '').isNotEmpty,
              trailing: IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400), onPressed: () => _delete(k['id'] as int)),
            ));
          })),
    ]);
  }
}
