import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import '../services/api_service.dart';
import 'file_viewer_dialog.dart';
import '../utils/file_picker_helper.dart';

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
  List<Map<String, dynamic>> _dbMeldungen = [];
  List<Map<String, dynamic>> _dbAntraege = [];
  List<Map<String, dynamic>> _dbTermine = [];
  List<Map<String, dynamic>> _dbBegutachtungen = [];
  List<Map<String, dynamic>> _dbVorschlaege = [];

  static const _tabs = [
    (Icons.account_balance, 'BAA'),
    (Icons.person_pin, 'Vermittler'),
    (Icons.person_off, 'Meldung'),
    (Icons.assignment, 'Anträge'),
    (Icons.description, 'Bescheid'),
    (Icons.block, 'Sperrzeit'),
    (Icons.handshake, 'EGV'),
    (Icons.school, 'BGS'),
    (Icons.work_outline, 'Vorschläge'),
    (Icons.cloud, 'Online'),
    (Icons.medical_services, 'Med.Gutachten'),
    (Icons.event, 'Termine'),
    (Icons.email, 'Korrespondenz'),
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
        _dbMeldungen = (res['meldungen'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
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
      if (['arbeitssuchend_datum','arbeitslos_datum','letzter_arbeitstag','kuendigungsart'].contains(e.key)) bereich = 'arbeitsmeldung';
      else if (['bescheid_von','bescheid_bis','leistungssatz_betrag','leistungssatz_typ','bemessungsentgelt','anspruchsdauer','restanspruch'].contains(e.key)) bereich = 'bescheid';
      else if (e.key.startsWith('sperrzeit') || e.key == 'has_sperrzeit') bereich = 'sperrzeit';
      else if (e.key.startsWith('egv') || e.key == 'has_egv') bereich = 'egv';
      else if (e.key.startsWith('bgs') || e.key == 'has_bgs') bereich = 'bildungsgutschein';
      else if (['has_online_account','online_email','has_passkey','passkey_access'].contains(e.key)) bereich = 'online';
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
        tabs: _tabs.map((t) => Tab(icon: Icon(t.$1, size: 16), text: t.$2)).toList()),
      Expanded(child: TabBarView(controller: _tabCtrl, children: [
        _buildBAATab(),
        _buildVermittlerTab(),
        _buildMeldungTab(),
        _buildAntraegeTab(),
        _buildBescheidTab(),
        _buildSperrzeitTab(),
        _buildEgvTab(),
        _buildBgsTab(),
        _buildVorschlaegeTab(),
        _buildOnlineTab(),
        _buildBegutachtungTab(),
        _buildTermineTab(),
        SingleChildScrollView(padding: const EdgeInsets.all(16), child: _AAKorrespondenzSection(apiService: widget.apiService, userId: widget.userId)),
      ])),
    ]);
  }

  // ──── TAB: Zuständige BAA ────
  Widget _buildBAATab() {
    final dienststelleC = TextEditingController(text: _v('dienststelle'));
    final kundennummerC = TextEditingController(text: _v('kundennummer'));
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      widget.dienststelleBuilder(type, dienststelleC),
      const SizedBox(height: 16),
      _sectionHeader(Icons.badge, 'Stammdaten', Colors.indigo),
      const SizedBox(height: 8),
      _textField('Kundennummer', kundennummerC, hint: 'z.B. 123A456789 (10-stellig)', icon: Icons.badge),
      _saveBtn(() => _saveTab({'dienststelle': dienststelleC.text.trim(), 'kundennummer': kundennummerC.text.trim()})),
    ]));
  }

  // ──── TAB: Mein Arbeitsvermittler ────
  Widget _buildVermittlerTab() {
    final nameC = TextEditingController(text: _v('arbeitsvermittler'));
    final telC = TextEditingController(text: _v('arbeitsvermittler_tel'));
    final emailC = TextEditingController(text: _v('arbeitsvermittler_email'));
    String anrede = _v('arbeitsvermittler_anrede');
    return StatefulBuilder(builder: (ctx, setLocal) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader(Icons.person_pin, 'Mein Arbeitsvermittler', const Color(0xFF003F7D)),
      const SizedBox(height: 12),
      Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.shade200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Anrede', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          Row(children: [
            ChoiceChip(label: const Text('Frau', style: TextStyle(fontSize: 12)), selected: anrede == 'Frau', selectedColor: Colors.pink.shade100, onSelected: (_) => setLocal(() => anrede = 'Frau')),
            const SizedBox(width: 8),
            ChoiceChip(label: const Text('Herr', style: TextStyle(fontSize: 12)), selected: anrede == 'Herr', selectedColor: Colors.blue.shade100, onSelected: (_) => setLocal(() => anrede = 'Herr')),
          ]),
          const SizedBox(height: 12),
          _textField('Name', nameC, hint: 'Vor- und Nachname', icon: Icons.person),
          const SizedBox(height: 12),
          _textField('Telefon', telC, hint: 'Durchwahl', icon: Icons.phone),
          const SizedBox(height: 12),
          _textField('E-Mail', emailC, hint: 'E-Mail-Adresse', icon: Icons.email),
        ])),
      _saveBtn(() => _saveTab({'arbeitsvermittler_anrede': anrede, 'arbeitsvermittler': nameC.text.trim(), 'arbeitsvermittler_tel': telC.text.trim(), 'arbeitsvermittler_email': emailC.text.trim()})),
    ])));
  }

  // ──── TAB: Arbeitssuchendmeldung ────
  Widget _buildMeldungTab() {
    final suchendC = TextEditingController(text: _v('arbeitssuchend_datum'));
    final losC = TextEditingController(text: _v('arbeitslos_datum'));
    final letzterC = TextEditingController(text: _v('letzter_arbeitstag'));
    String kuendigungsart = _v('kuendigungsart');
    List<Map<String, dynamic>> meldungen = List<Map<String, dynamic>>.from(_dbMeldungen.map((e) => Map<String, dynamic>.from(e)));
    return StatefulBuilder(builder: (ctx, setLocal) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.brown.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.brown.shade200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: _dateField('Arbeitssuchend gemeldet am', suchendC, ctx)),
            const SizedBox(width: 12),
            Expanded(child: _dateField('Arbeitslos gemeldet am', losC, ctx)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _dateField('Letzter Arbeitstag', letzterC, ctx)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Kündigungsart', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(initialValue: kuendigungsart.isEmpty ? null : kuendigungsart, isExpanded: true,
                decoration: InputDecoration(isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                hint: const Text('Auswählen...', style: TextStyle(fontSize: 13)),
                items: const [
                  DropdownMenuItem(value: 'arbeitgeber', child: Text('Arbeitgeberkündigung', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 'eigen', child: Text('Eigenkündigung', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 'aufhebung', child: Text('Aufhebungsvertrag', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 'befristung', child: Text('Befristung ausgelaufen', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 'insolvenz', child: Text('Insolvenz', style: TextStyle(fontSize: 13))),
                ], onChanged: (v) => setLocal(() => kuendigungsart = v ?? '')),
            ])),
          ]),
        ])),
      _saveBtn(() => _saveTab({'arbeitssuchend_datum': suchendC.text.trim(), 'arbeitslos_datum': losC.text.trim(), 'letzter_arbeitstag': letzterC.text.trim(), 'kuendigungsart': kuendigungsart})),
      const SizedBox(height: 16),
      widget.meldungenBuilder(meldungen: meldungen, onChanged: (u) { setLocal(() => meldungen = u); _syncMeldungenToDB(u); }, context: ctx),
    ])));
  }

  // ──── TAB: Anträge ────
  Widget _buildAntraegeTab() {
    List<Map<String, dynamic>> antraege = List<Map<String, dynamic>>.from(_dbAntraege.map((e) => Map<String, dynamic>.from(e)));
    return StatefulBuilder(builder: (ctx, setLocal) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: widget.antraegeBuilder(
      behoerdeType: type, antraege: antraege,
      artItems: const [
        DropdownMenuItem(value: 'erstantrag', child: Text('Erstantrag ALG I', style: TextStyle(fontSize: 13))),
        DropdownMenuItem(value: 'weiterbewilligung', child: Text('Weiterbewilligungsantrag', style: TextStyle(fontSize: 13))),
        DropdownMenuItem(value: 'wiederholung', child: Text('Wiederholungsantrag', style: TextStyle(fontSize: 13))),
        DropdownMenuItem(value: 'insolvenzantrag', child: Text('Insolvenzantrag', style: TextStyle(fontSize: 13))),
      ],
      statusItems: const [
        DropdownMenuItem(value: 'neu', child: Text('Neu', style: TextStyle(fontSize: 13))),
        DropdownMenuItem(value: 'geplant', child: Text('Geplant', style: TextStyle(fontSize: 13))),
        DropdownMenuItem(value: 'eingereicht', child: Text('Eingereicht', style: TextStyle(fontSize: 13))),
        DropdownMenuItem(value: 'in_bearbeitung', child: Text('In Bearbeitung', style: TextStyle(fontSize: 13))),
        DropdownMenuItem(value: 'unterlagen_fehlen', child: Text('Unterlagen nachgefordert', style: TextStyle(fontSize: 13))),
        DropdownMenuItem(value: 'bewilligt', child: Text('Bewilligt', style: TextStyle(fontSize: 13))),
        DropdownMenuItem(value: 'abgelehnt', child: Text('Abgelehnt', style: TextStyle(fontSize: 13))),
        DropdownMenuItem(value: 'zurueckgezogen', child: Text('Zurückgezogen', style: TextStyle(fontSize: 13))),
        DropdownMenuItem(value: 'verweigerung', child: Text('Verweigerung durch Mitglied', style: TextStyle(fontSize: 13))),
      ],
      onChanged: (u) { setLocal(() => antraege = u); _syncAntraegeToDB(u); }, context: ctx)));
  }

  // ──── TAB: Bewilligungsbescheid ────
  Widget _buildBescheidTab() {
    final vonC = TextEditingController(text: _v('bescheid_von'));
    final bisC = TextEditingController(text: _v('bescheid_bis'));
    final leistungC = TextEditingController(text: _v('leistungssatz_betrag'));
    final bemessungC = TextEditingController(text: _v('bemessungsentgelt'));
    final anspruchC = TextEditingController(text: _v('anspruchsdauer'));
    final restC = TextEditingController(text: _v('restanspruch'));
    String leistungTyp = _v('leistungssatz_typ');
    return StatefulBuilder(builder: (ctx, setLocal) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader(Icons.description, 'Bewilligungsbescheid (ALG I)', Colors.green.shade700),
      const SizedBox(height: 8),
      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green.shade200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: _dateField('Bewilligungszeitraum von', vonC, ctx)), const SizedBox(width: 12), Expanded(child: _dateField('Bewilligungszeitraum bis', bisC, ctx))]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _textField('Täglicher Leistungssatz (EUR)', leistungC, hint: 'z.B. 38.50', icon: Icons.euro)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Leistungssatz', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(initialValue: leistungTyp.isEmpty ? null : leistungTyp, isExpanded: true,
                decoration: InputDecoration(isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                hint: const Text('Auswählen...', style: TextStyle(fontSize: 13)),
                items: const [
                  DropdownMenuItem(value: '60', child: Text('60% (allgemein)', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: '67', child: Text('67% (mit Kind)', style: TextStyle(fontSize: 13))),
                ], onChanged: (v) => setLocal(() => leistungTyp = v ?? '')),
            ])),
          ]),
          const SizedBox(height: 12),
          _textField('Bemessungsentgelt (EUR/Tag)', bemessungC, hint: 'Tägliches Bemessungsentgelt', icon: Icons.account_balance_wallet),
          const SizedBox(height: 12),
          Row(children: [Expanded(child: _textField('Anspruchsdauer (Tage)', anspruchC, hint: 'z.B. 360', icon: Icons.timer)), const SizedBox(width: 12), Expanded(child: _textField('Restanspruch (Tage)', restC, hint: 'Verbleibende Tage', icon: Icons.hourglass_bottom))]),
        ])),
      _saveBtn(() => _saveTab({'bescheid_von': vonC.text.trim(), 'bescheid_bis': bisC.text.trim(), 'leistungssatz_betrag': leistungC.text.trim(), 'leistungssatz_typ': leistungTyp, 'bemessungsentgelt': bemessungC.text.trim(), 'anspruchsdauer': anspruchC.text.trim(), 'restanspruch': restC.text.trim()})),
    ])));
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
    final passkeyC = TextEditingController(text: _v('passkey_access'));
    return StatefulBuilder(builder: (ctx, setLocal) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.cloud, size: 18, color: Colors.blue.shade700), const SizedBox(width: 8), Text('Online-Konto (arbeitsagentur.de)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue.shade700)), const Spacer(), Switch(value: has, onChanged: (v) => setLocal(() => has = v), activeThumbColor: Colors.blue)]),
          if (has) ...[
            const SizedBox(height: 12),
            _textField('E-Mail', emailC, hint: 'E-Mail des Online-Kontos', icon: Icons.email),
            const SizedBox(height: 12),
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade200)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Icon(Icons.key, size: 18, color: Colors.orange.shade700), const SizedBox(width: 8), Text('Passkey aktiviert', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.orange.shade700)), const Spacer(), Switch(value: hasPasskey, onChanged: (v) => setLocal(() => hasPasskey = v), activeThumbColor: Colors.orange)]),
                if (hasPasskey) ...[const SizedBox(height: 12), _textField('Wer hat Zugang?', passkeyC, hint: 'Name / Rolle', icon: Icons.person_pin)],
              ])),
          ],
        ])),
      _saveBtn(() => _saveTab({'has_online_account': has, 'online_email': emailC.text.trim(), 'has_passkey': hasPasskey, 'passkey_access': passkeyC.text.trim()})),
    ])));
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

  Widget _buildArbeitgeberSearch(TextEditingController arbeitgeberC, TextEditingController ortC, StateSetter setDlg) {
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
                final selTel = selected['niederlassung_telefon']?.toString() ?? selected['hauptzentrale_telefon']?.toString() ?? '';
                final selEmail = selected['niederlassung_email']?.toString() ?? selected['hauptzentrale_email']?.toString() ?? '';
                if (selTel.isNotEmpty && apTelC.text.isEmpty) apTelC.text = selTel;
                if (selEmail.isNotEmpty && apEmailC.text.isEmpty) apEmailC.text = selEmail;
              });
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
              child: InkWell(borderRadius: BorderRadius.circular(8), onTap: () => _showVorschlagDialog(ctx, v, (updated) async {
                await widget.apiService.saveArbeitsagenturVorschlag(widget.userId, updated);
                await _loadFromDB();
                if (mounted) setState(() {});
              }),
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
        _buildArbeitgeberSearch(arbeitgeberC, ortC, setDlg),
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
        _textField('Stelle / Position', stelleC, hint: 'z.B. Lagerhelfer', icon: Icons.work),
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

  Future<void> _syncMeldungenToDB(List<Map<String, dynamic>> updated) async {
    final existingIds = _dbMeldungen.map((m) => m['id'] as int?).where((id) => id != null).toSet();
    final updatedIds = <int>{};
    for (final mel in updated) {
      final id = mel['id'] is int ? mel['id'] as int : 0;
      if (id > 0) updatedIds.add(id);
      await widget.apiService.saveArbeitsagenturMeldung(widget.userId, mel);
    }
    for (final oldId in existingIds) {
      if (!updatedIds.contains(oldId)) {
        await widget.apiService.deleteArbeitsagenturMeldung(widget.userId, oldId!);
      }
    }
    await _loadFromDB();
  }

  Future<void> _syncAntraegeToDB(List<Map<String, dynamic>> updated) async {
    final existingIds = _dbAntraege.map((a) => a['id'] as int?).where((id) => id != null).toSet();
    final updatedIds = <int>{};
    for (final antrag in updated) {
      final id = antrag['id'] is int ? antrag['id'] as int : 0;
      if (id > 0) updatedIds.add(id);
      await widget.apiService.saveArbeitsagenturAntrag(widget.userId, antrag);
    }
    for (final oldId in existingIds) {
      if (!updatedIds.contains(oldId)) {
        await widget.apiService.deleteArbeitsagenturAntrag(widget.userId, oldId!);
      }
    }
    await _loadFromDB();
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
