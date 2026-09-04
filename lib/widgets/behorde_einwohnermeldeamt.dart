import 'dart:async';
import 'package:flutter/material.dart';
import 'phone_link.dart';
import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';
import 'korrespondenz_attachments_widget.dart';
import '../utils/cloud_picker_helper.dart';
import '../widgets/responsive_layout.dart';
import '../utils/app_farben.dart';
import '../utils/buergeramt_dokument.dart';
import 'file_viewer_dialog.dart';
String _deFmt(DateTime p) => '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}';

class BehordeEinwohnermeldeamtContent extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final Map<String, dynamic> Function(String type) getData;
  final bool Function(String type) isLoading;
  final bool Function(String type) isSaving;
  final void Function(String type) loadData;
  final void Function(String type, Map<String, dynamic> data) saveData;
  final Widget Function(String type, TextEditingController controller) dienststelleBuilder;

  const BehordeEinwohnermeldeamtContent({
    super.key,
    required this.apiService,
    required this.userId,
    required this.getData,
    required this.isLoading,
    required this.isSaving,
    required this.loadData,
    required this.saveData,
    required this.dienststelleBuilder,
  });

  @override
  State<BehordeEinwohnermeldeamtContent> createState() => _State();
}

class _State extends State<BehordeEinwohnermeldeamtContent> with TickerProviderStateMixin {
  late final TabController _tabCtrl;
  bool _loaded = false, _loading = false;
  Map<String, dynamic> _data = {};
  List<Map<String, dynamic>> _vorfaelle = [];

  static const _lobbyCardTyp = 'Tafelladen-Kundenkarte (LobbyCard)';
  static const _lobbyGruende = [
    'Bürgergeld (SGB II)',
    'Sozialhilfe (SGB XII)',
    'Grundsicherung',
    'Wohngeld',
    'Geringes Einkommen',
    'Sonstiges',
  ];

  static const _vorfallTypen = [
    'Anmeldung (Wohnsitz)',
    'Ummeldung (Wohnsitz)',
    'Abmeldung (Wohnsitz)',
    'Personalausweis beantragen',
    'Reisepass beantragen',
    'Kinderreisepass beantragen',
    'Meldebescheinigung',
    'Führungszeugnis',
    'Gewerbeanmeldung',
    'Beglaubigung',
    'Wohnungsgeberbestätigung',
    'Steuerliche Lebensbescheinigung',
    _lobbyCardTyp,
    'Sonstiges',
  ];

  static const _buergeraemter = [
    {'name': 'Bürgerbüro Neu-Ulm', 'adresse': 'Petrusplatz 15, 89231 Neu-Ulm', 'telefon': '0731 7050-7340', 'fax': '0731 7050-7349', 'email': 'buergerbuero@neu-ulm.de', 'oeffnungszeiten': 'Mo-Di 08:00-17:00, Mi 08:00-13:00, Do 08:00-18:00, Fr 08:00-13:00, Sa 09:00-12:00'},
    {'name': 'Bürgerdienste Ulm', 'adresse': 'Olgastraße 66, 89073 Ulm', 'telefon': '0731 161-3322', 'fax': '0731 161-1615', 'oeffnungszeiten': 'Mo-Di 07:30-16:00, Mi 07:30-12:30, Do 07:30-17:30, Fr 07:30-12:30'},
    {'name': 'Bürgerbüro Senden', 'adresse': 'Hauptstraße 55, 89250 Senden', 'telefon': '07307 945-100', 'oeffnungszeiten': 'Mo-Fr 08:00-12:00, Do 14:00-18:00'},
  ];

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
      final res = await widget.apiService.getBuergeramtData(widget.userId);
      if (res['success'] == true && mounted) {
        final raw = res['data'];
        if (raw is Map) { _data = {}; for (final e in raw.entries) { final parts = e.key.toString().split('.'); _data[parts.length == 2 ? parts[1] : e.key.toString()] = e.value; } }
        _vorfaelle = (res['vorfaelle'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    if (mounted) setState(() { _loading = false; _loaded = true; });
  }

  Future<void> _saveFields(Map<String, dynamic> fields) async {
    try {
      final mapped = <String, dynamic>{};
      for (final e in fields.entries) {
        mapped['stammdaten.${e.key}'] = e.value?.toString() ?? '';
      }
      await widget.apiService.saveBuergeramtData(widget.userId, mapped);
      for (final e in fields.entries) {
        _data[e.key] = e.value;
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gespeichert'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded && !_loading) _load();
    if (_loading || !_loaded) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      TabBar(controller: _tabCtrl, labelColor: F.h(Colors.teal, 700), unselectedLabelColor: F.h(Colors.grey, 500), indicatorColor: Colors.teal.shade700,
        tabs: [Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: (_data['name']?.toString() ?? '').isNotEmpty || (_data['dienststelle']?.toString() ?? '').isNotEmpty ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.account_balance, size: 16), const SizedBox(width: 4), const Flexible(child: Text('Zuständiges Bürgeramt', overflow: TextOverflow.ellipsis))])), Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: _vorfaelle.isNotEmpty ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.assignment, size: 16), const SizedBox(width: 4), const Flexible(child: Text('Vorfall', overflow: TextOverflow.ellipsis))]))]),
      Expanded(child: TabBarView(controller: _tabCtrl, children: [_buildAmtTab(), _buildVorfallTab()])),
    ]);
  }

  Widget _buildAmtTab() {
    final selected = _buergeraemter.firstWhere((b) => b['name'] == _v('dienststelle'), orElse: () => <String, String>{});
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Zuständiges Bürgeramt', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: F.h(Colors.teal, 700))),
      const SizedBox(height: 8),
      // Search field — type or select from dropdown of known Bürgerämter.
      Autocomplete<Map<String, String>>(
        initialValue: TextEditingValue(text: _v('dienststelle')),
        displayStringForOption: (b) => b['name'] ?? '',
        optionsBuilder: (textEditingValue) {
          final q = textEditingValue.text.trim().toLowerCase();
          if (q.isEmpty) return _buergeraemter;
          return _buergeraemter.where((b) => (b['name'] ?? '').toLowerCase().contains(q) || (b['adresse'] ?? '').toLowerCase().contains(q));
        },
        fieldViewBuilder: (ctx, controller, focusNode, onFieldSubmitted) {
          return TextField(
            controller: controller,
            focusNode: focusNode,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () { controller.clear(); setState(() { _data['dienststelle'] = ''; }); _saveFields({'dienststelle': ''}); },
                    )
                  : null,
              hintText: 'Bürgeramt suchen…',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            onSubmitted: (val) {
              setState(() { _data['dienststelle'] = val.trim(); });
              _saveFields({'dienststelle': val.trim()});
              onFieldSubmitted();
            },
          );
        },
        optionsViewBuilder: (ctx, onSelected, options) {
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280, maxWidth: 480),
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: options.map((b) => InkWell(
                    onTap: () => onSelected(b),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(b['name'] ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        Text(b['adresse'] ?? '', style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
                      ]),
                    ),
                  )).toList(),
                ),
              ),
            ),
          );
        },
        onSelected: (b) {
          setState(() { _data['dienststelle'] = b['name']; });
          _saveFields({'dienststelle': b['name'] ?? ''});
        },
      ),
      const SizedBox(height: 16),
      // Selected Bürgeramt details card (only shown when something is selected).
      if (_v('dienststelle').isNotEmpty) Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: F.h(Colors.teal, 50), borderRadius: BorderRadius.circular(8), border: Border.all(color: F.h(Colors.teal, 300))),
        child: Row(children: [
          Icon(Icons.account_balance, size: 24, color: F.h(Colors.teal, 700)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_v('dienststelle'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: F.h(Colors.teal, 800))),
            if (selected.isNotEmpty) ...[
              if ((selected['adresse'] ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [Icon(Icons.location_on, size: 12, color: F.h(Colors.grey, 600)), const SizedBox(width: 4), Expanded(child: Text(selected['adresse']!, style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700))))])),
              if ((selected['telefon'] ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: PhoneTapTarget(number: selected['telefon'], label: _v('dienststelle'), child: Row(children: [Icon(Icons.phone, size: 12, color: F.h(Colors.grey, 600)), const SizedBox(width: 4), Text(selected['telefon']!, style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700)))]))),
              if ((selected['email'] ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Row(children: [Icon(Icons.email, size: 12, color: F.h(Colors.grey, 600)), const SizedBox(width: 4), Text(selected['email']!, style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700)))])),
              if ((selected['oeffnungszeiten'] ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.schedule, size: 12, color: F.h(Colors.grey, 600)), const SizedBox(width: 4), Expanded(child: Text(selected['oeffnungszeiten']!, style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))))])),
            ] else
              Padding(padding: const EdgeInsets.only(top: 4), child: Text('Manuell eingegeben', style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600), fontStyle: FontStyle.italic))),
          ])),
        ]),
      ),
      const SizedBox(height: 12),
      // Hint about where the registration data is now stored.
      Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [
        Icon(Icons.info_outline, size: 14, color: F.h(Colors.grey, 500)), const SizedBox(width: 6),
        Expanded(child: Text('Einzugsdatum, Meldeadresse, Nebenwohnsitz & Meldebescheinigung-Nr. werden pro Vorfall erfasst.', style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600), fontStyle: FontStyle.italic))),
      ])),
    ]));
  }

  Widget _buildVorfallTab() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Icon(Icons.assignment, size: 18, color: F.h(Colors.teal, 700)), const SizedBox(width: 8),
        Text('${_vorfaelle.length} Vorfälle', style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600))),
        const Spacer(),
        FilledButton.icon(icon: const Icon(Icons.add, size: 16), label: const Text('Neuer Vorfall', style: TextStyle(fontSize: 12)),
          style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade600, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero),
          onPressed: () => _showNewVorfallDialog()),
      ])),
      Expanded(child: _vorfaelle.isEmpty
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.assignment_late, size: 48, color: F.h(Colors.grey, 300)), const SizedBox(height: 8), Text('Keine Vorfälle', style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 500)))]))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _vorfaelle.length, itemBuilder: (_, i) {
            final v = _vorfaelle[i];
            final status = v['status']?.toString() ?? 'offen';
            final sc = status == 'erledigt' ? Colors.green : status == 'in_bearbeitung' ? Colors.orange : Colors.blue;
            return Container(margin: const EdgeInsets.only(bottom: 8), child: InkWell(borderRadius: BorderRadius.circular(8),
              onTap: () => _showVorfallDetailDialog(v),
              child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: F.h(Colors.teal, 50), borderRadius: BorderRadius.circular(8), border: Border.all(color: F.h(Colors.teal, 200))),
                child: Row(children: [
                  Icon(Icons.assignment, size: 18, color: F.h(Colors.teal, 700)), const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(v['titel']?.toString() ?? v['typ']?.toString() ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: F.h(Colors.teal, 800)))),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: F.h(sc, 100), borderRadius: BorderRadius.circular(6)),
                        child: Text(status == 'erledigt' ? 'Erledigt' : status == 'in_bearbeitung' ? 'In Bearbeitung' : 'Offen', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: F.h(sc, 800)))),
                    ]),
                    if ((v['datum']?.toString() ?? '').isNotEmpty) Text(v['datum'].toString(), style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
                    if ((v['typ']?.toString() ?? '').isNotEmpty && v['typ'] != v['titel']) Text(v['typ'].toString(), style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 500))),
                  ])),
                  const SizedBox(width: 4),
                  IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: () async { await widget.apiService.deleteBuergeramtVorfall(widget.userId, v['id'] is int ? v['id'] : int.parse(v['id'].toString())); await _load(); }),
                ]))));
          })),
    ]);
  }

  void _showNewVorfallDialog() {
    final datumC = TextEditingController();
    final titelC = TextEditingController();
    final notizC = TextEditingController();
    final einzugsdatumC = TextEditingController();
    final meldeadresseC = TextEditingController();
    final nebenwohnsitzC = TextEditingController();
    final meldebescheinigungNrC = TextEditingController();
    final ausgestelltC = TextEditingController();
    final gueltigC = TextEditingController();
    String typ = '';
    String lobbyGrund = '';
    bool lcNachweis = false, lcPassbild = false;
    // Auto-Erkennung der Nachweise (nur bei LobbyCard):
    //  · Einkommensnachweis  ← Bewilligungsbescheid im Jobcenter (status=bewilligt oder bescheid_von)
    //  · Passbild            ← hochgeladenes eGK-Lichtbild in der Krankenkasse-Korrespondenz
    bool detectStarted = false, dlgOpen = true;
    bool hasBewilligung = false, hasLichtbild = false;
    void runLobbyDetect(StateSetter setDlg) {
      if (detectStarted) return;
      detectStarted = true;
      unawaited(() async {
        try {
          final res = await Future.wait([
            widget.apiService.getJobcenterData(widget.userId),
            widget.apiService.getKKKorrespondenz(widget.userId),
          ]);
          final antraege = (res[0]['antraege'] as List?) ?? const [];
          hasBewilligung = antraege.any((a) { final m = a as Map; return m['status'] == 'bewilligt'; });
          final korr = (res[1]['data'] as List?) ?? const [];
          hasLichtbild = korr.any((k) { final m = k as Map; return (m['titel']?.toString() ?? '').contains('eGK-Lichtbild') && m['dokumente'] is List && (m['dokumente'] as List).isNotEmpty; });
        } catch (_) {}
        if (dlgOpen) {
          setDlg(() {
          lcPassbild = hasLichtbild;
          lcNachweis = lobbyGrund.startsWith('Bürgergeld') && hasBewilligung;
        });
        }
      }());
    }
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) => AlertDialog(
      title: Row(children: [Icon(Icons.add_circle, size: 18, color: F.h(Colors.teal, 700)), const SizedBox(width: 8), const Text('Neuer Vorfall', style: TextStyle(fontSize: 14))]),
      content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(isExpanded: true, initialValue: typ.isEmpty ? null : typ,
          decoration: InputDecoration(labelText: 'Dienstleistung', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          items: _vorfallTypen.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 13)))).toList(),
          onChanged: (v) {
            setDlg(() {
              typ = v ?? '';
              if (titelC.text.isEmpty) titelC.text = typ;
              if (typ == _lobbyCardTyp) { lcPassbild = hasLichtbild; lcNachweis = lobbyGrund.startsWith('Bürgergeld') && hasBewilligung; }
            });
            if (typ == _lobbyCardTyp) runLobbyDetect(setDlg);
          }),
        const SizedBox(height: 12),
        TextField(controller: titelC, decoration: InputDecoration(labelText: 'Titel', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 12),
        _dateField('Datum', datumC, ctx),
        if (typ != _lobbyCardTyp) ...[
          const SizedBox(height: 12),
          TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        ],
        const SizedBox(height: 16),
        if (typ == _lobbyCardTyp) ...[
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(children: [
            Icon(Icons.card_membership, size: 14, color: F.h(Colors.teal, 600)), const SizedBox(width: 6),
            Text('Tafelladen-Kundenkarte (LobbyCard)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: F.h(Colors.teal, 700))),
          ]),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(isExpanded: true, initialValue: lobbyGrund.isEmpty ? null : lobbyGrund,
            decoration: InputDecoration(labelText: 'Berechtigungsgrund', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: _lobbyGruende.map((g) => DropdownMenuItem(value: g, child: Text(g, style: const TextStyle(fontSize: 13)))).toList(),
            onChanged: (g) => setDlg(() { lobbyGrund = g ?? ''; lcNachweis = lobbyGrund.startsWith('Bürgergeld') && hasBewilligung; })),
          const SizedBox(height: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Ausgestellt am', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: F.h(Colors.grey, 700))), const SizedBox(height: 4),
            TextField(controller: ausgestelltC, readOnly: true, decoration: InputDecoration(hintText: 'TT.MM.JJJJ', prefixIcon: const Icon(Icons.event_available, size: 20), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
              onTap: () async { final p = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (p != null) setDlg(() { ausgestelltC.text = _deFmt(p); gueltigC.text = _deFmt(DateTime(p.year + 1, p.month, p.day)); }); }),
          ]),
          const SizedBox(height: 10),
          _dateField('Gültig bis', gueltigC, ctx),
          const SizedBox(height: 4),
          CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading,
            value: lcNachweis, onChanged: (val) => setDlg(() => lcNachweis = val ?? false),
            title: const Text('Einkommensnachweis vorgelegt', style: TextStyle(fontSize: 12)),
            subtitle: lobbyGrund.startsWith('Bürgergeld') && hasBewilligung
              ? Row(children: [Icon(Icons.auto_awesome, size: 11, color: F.h(Colors.green, 600)), const SizedBox(width: 4), Expanded(child: Text('Automatisch: Bewilligungsbescheid im Jobcenter vorhanden', style: TextStyle(fontSize: 10, color: F.h(Colors.green, 700))))])
              : null),
          CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading,
            value: lcPassbild, onChanged: (val) => setDlg(() => lcPassbild = val ?? false),
            title: const Text('Passbild vorgelegt', style: TextStyle(fontSize: 12)),
            subtitle: hasLichtbild
              ? Row(children: [Icon(Icons.auto_awesome, size: 11, color: F.h(Colors.green, 600)), const SizedBox(width: 4), Expanded(child: Text('Automatisch: eGK-Lichtbild in Krankenkasse vorhanden', style: TextStyle(fontSize: 10, color: F.h(Colors.green, 700))))])
              : null),
          const SizedBox(height: 4),
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: F.h(Colors.amber, 50), borderRadius: BorderRadius.circular(6), border: Border.all(color: F.h(Colors.amber, 200))),
            child: Row(children: [
              Icon(Icons.notifications_active, size: 14, color: F.h(Colors.amber, 800)), const SizedBox(width: 6),
              Expanded(child: Text('Erinnerungs-Ticket wird automatisch 2 Wochen vor Ablauf erstellt (Verlängerung im Bürgerbüro Neu-Ulm).', style: TextStyle(fontSize: 10, color: F.h(Colors.amber, 900)))),
            ])),
        ] else ...[
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(children: [
            Icon(Icons.home, size: 14, color: F.h(Colors.teal, 600)), const SizedBox(width: 6),
            Text('Meldedaten (optional)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: F.h(Colors.teal, 700))),
          ]),
          const SizedBox(height: 8),
          _dateField('Einzugsdatum', einzugsdatumC, ctx),
          const SizedBox(height: 10),
          TextField(controller: meldeadresseC, maxLines: 2, decoration: InputDecoration(labelText: 'Meldeadresse (Hauptwohnsitz)', hintText: 'Straße Nr, PLZ Ort', prefixIcon: const Icon(Icons.location_on, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 10),
          TextField(controller: nebenwohnsitzC, decoration: InputDecoration(labelText: 'Nebenwohnsitz', hintText: 'Falls vorhanden', prefixIcon: const Icon(Icons.home_work, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 10),
          TextField(controller: meldebescheinigungNrC, decoration: InputDecoration(labelText: 'Meldebescheinigung-Nr.', prefixIcon: const Icon(Icons.description, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        ],
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          await widget.apiService.saveBuergeramtVorfall(widget.userId, {
            'typ': typ,
            'titel': titelC.text.trim(),
            'datum': datumC.text.trim(),
            'notiz': notizC.text.trim(),
            'einzugsdatum': einzugsdatumC.text.trim(),
            'meldeadresse': meldeadresseC.text.trim(),
            'nebenwohnsitz': nebenwohnsitzC.text.trim(),
            'meldebescheinigung_nr': meldebescheinigungNrC.text.trim(),
            'lobbycard_grund': lobbyGrund,
            'lobbycard_nachweis': lcNachweis,
            'lobbycard_passbild': lcPassbild,
            'lobbycard_ausgestellt': ausgestelltC.text.trim(),
            'lobbycard_gueltig_bis': gueltigC.text.trim(),
          });
          if (ctx.mounted) Navigator.pop(ctx); await _load();
        }, child: const Text('Speichern')),
      ],
    ))).then((_) => dlgOpen = false);
  }

  void _showVorfallDetailDialog(Map<String, dynamic> v) {
    final vid = v['id'] is int ? v['id'] as int : int.parse(v['id'].toString());
    showDialog(context: context, builder: (ctx) => Dialog(
      child: SizedBox(width: 600, height: 550, child: _BuergeramtVorfallDetail(apiService: widget.apiService, userId: widget.userId, vorfallId: vid, vorfall: v, onChanged: () { _load(); }))));
  }

  Widget _dateField(String label, TextEditingController c, BuildContext ctx) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: F.h(Colors.grey, 700))), const SizedBox(height: 4),
      TextField(controller: c, readOnly: true, decoration: InputDecoration(hintText: 'TT.MM.JJJJ', prefixIcon: const Icon(Icons.calendar_today, size: 20), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
        onTap: () async { final p = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (p != null) c.text = '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}'; }),
    ]);
  }
}

class _BuergeramtVorfallDetail extends StatefulWidget {
  final ApiService apiService;
  final int userId, vorfallId;
  final Map<String, dynamic> vorfall;
  final VoidCallback onChanged;
  const _BuergeramtVorfallDetail({required this.apiService, required this.userId, required this.vorfallId, required this.vorfall, required this.onChanged});
  @override
  State<_BuergeramtVorfallDetail> createState() => _BuergeramtVorfallDetailState();
}

class _BuergeramtVorfallDetailState extends State<_BuergeramtVorfallDetail> {
  List<Map<String, dynamic>> _termine = [], _korr = [], _verlauf = [];
  Map<String, dynamic>? _dokument;
  bool _loaded = false, _dokLaeuft = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final res = await widget.apiService.getBuergeramtVorfallDetail(widget.userId, widget.vorfallId);
      if (res['success'] == true && mounted) {
        _termine = (res['termine'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _korr = (res['korrespondenz'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _verlauf = (res['verlauf'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        // ⚠️ `null` heißt „noch keine Bestätigung erfasst" und muss auch
        // beim Neuladen wieder auf null gehen — sonst bliebe eine gerade
        // gelöschte Bestätigung auf dem Schirm stehen.
        final dRes = res['dokument'];
        _dokument = dRes is Map ? Map<String, dynamic>.from(dRes) : null;
      }
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vorfall;
    final status = v['status']?.toString() ?? 'offen';
    final sc = status == 'erledigt' ? Colors.green : status == 'in_bearbeitung' ? Colors.orange : Colors.blue;
    // Nur An-, Um- und Abmeldung tragen eine Bestätigung; zu einem
    // Personalausweis gibt es keine, dort fehlt der Reiter.
    final dokTitel = buergeramtDokTitel(v['typ']?.toString());
    return DefaultTabController(length: dokTitel == null ? 4 : 5, child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 8, 0), child: Row(children: [
        Icon(Icons.assignment, size: 18, color: F.h(Colors.teal, 700)), const SizedBox(width: 8),
        Expanded(child: Text(v['titel']?.toString() ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: F.h(Colors.teal, 800)), overflow: TextOverflow.ellipsis)),
        Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: F.h(sc, 100), borderRadius: BorderRadius.circular(6)),
          child: Text(status == 'erledigt' ? 'Erledigt' : status == 'in_bearbeitung' ? 'In Bearbeitung' : 'Offen', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: F.h(sc, 800)))),
        const SizedBox(width: 4),
        PopupMenuButton<String>(icon: const Icon(Icons.more_vert, size: 18), itemBuilder: (_) => [
          const PopupMenuItem(value: 'offen', child: Text('Offen', style: TextStyle(fontSize: 12))),
          const PopupMenuItem(value: 'in_bearbeitung', child: Text('In Bearbeitung', style: TextStyle(fontSize: 12))),
          const PopupMenuItem(value: 'erledigt', child: Text('Erledigt', style: TextStyle(fontSize: 12))),
        ], onSelected: (s) async {
          await widget.apiService.saveBuergeramtVorfall(widget.userId, {... v, 'status': s});
          v['status'] = s; widget.onChanged(); setState(() {});
        }),
        IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.pop(context)),
      ])),
      TabBar(
        // Auf Telefonbreite sind 4 Reiter je rund 112 dp breit — die
        // Beschriftungen werden abgeschnitten. Scrollbar statt gestaucht.
        isScrollable: ResponsiveLayout.istTelefon(context),labelColor: F.h(Colors.teal, 700), unselectedLabelColor: F.h(Colors.grey, 500), indicatorColor: Colors.teal.shade700, tabs: [
        const Tab(icon: Icon(Icons.info_outline, size: 16), text: 'Details'),
        if (dokTitel != null)
          Tab(icon: Icon(_dokument == null ? Icons.upload_file : Icons.task_alt, size: 16), text: dokTitel),
        Tab(icon: const Icon(Icons.email, size: 16), text: 'Korrespondenz (${_korr.length})'),
        const Tab(icon: Icon(Icons.timeline, size: 16), text: 'Verlauf'),
        Tab(icon: const Icon(Icons.event, size: 16), text: 'Termine (${_termine.length})'),
      ]),
      Expanded(child: !_loaded ? const Center(child: CircularProgressIndicator()) : TabBarView(children: [
        _buildDetails(v),
        if (dokTitel != null) _buildDokument(v, dokTitel),
        _buildKorr(),
        _buildVerlauf(),
        _buildTermine(),
      ])),
    ]));
  }

  Widget _buildDetails(Map<String, dynamic> v) {
    final hasMeldedaten = ['einzugsdatum', 'meldeadresse', 'nebenwohnsitz', 'meldebescheinigung_nr']
        .any((k) => (v[k]?.toString() ?? '').isNotEmpty);
    final isLobby = (v['typ']?.toString() ?? '').contains('LobbyCard') || (v['lobbycard_gueltig_bis']?.toString() ?? '').isNotEmpty;
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _infoRow(Icons.category, 'Typ', v['typ']),
      _infoRow(Icons.title, 'Titel', v['titel']),
      _infoRow(Icons.calendar_today, 'Datum', v['datum']),
      _infoRow(Icons.folder, 'Aktenzeichen', v['aktenzeichen']),
      _infoRow(Icons.flag, 'Status', v['status']),
      if (isLobby) ...[
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 8),
        Row(children: [Icon(Icons.card_membership, size: 13, color: F.h(Colors.teal, 600)), const SizedBox(width: 6), Text('Tafelladen-Kundenkarte (LobbyCard)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: F.h(Colors.teal, 700)))]),
        const SizedBox(height: 6),
        _infoRow(Icons.verified_user, 'Berechtigungsgrund', v['lobbycard_grund']),
        _infoRow(Icons.event_available, 'Ausgestellt am', v['lobbycard_ausgestellt']),
        _infoRow(Icons.event_busy, 'Gültig bis', v['lobbycard_gueltig_bis']),
        _lcBoolRow('Einkommensnachweis vorgelegt', (v['lobbycard_nachweis'] ?? 0).toString() == '1'),
        _lcBoolRow('Passbild vorgelegt', (v['lobbycard_passbild'] ?? 0).toString() == '1'),
        if (v['lobbycard_ticket_id'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [
          Icon(Icons.notifications_active, size: 14, color: F.h(Colors.amber, 800)), const SizedBox(width: 8),
          Expanded(child: Text('Erinnerungs-Ticket #${v['lobbycard_ticket_id']} aktiv — 2 Wochen vor Ablauf', style: TextStyle(fontSize: 11, color: F.h(Colors.amber, 900)))),
        ])),
        const SizedBox(height: 10),
        Align(alignment: Alignment.centerLeft, child: FilledButton.icon(icon: const Icon(Icons.autorenew, size: 16), label: const Text('Karte verlängert (+1 Jahr)', style: TextStyle(fontSize: 12)),
          style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade600, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero),
          onPressed: () async {
            final now = DateTime.now();
            final ausg = _deFmt(now), gueltig = _deFmt(DateTime(now.year + 1, now.month, now.day));
            await widget.apiService.saveBuergeramtVorfall(widget.userId, {...v, 'lobbycard_ausgestellt': ausg, 'lobbycard_gueltig_bis': gueltig});
            v['lobbycard_ausgestellt'] = ausg; v['lobbycard_gueltig_bis'] = gueltig; v['lobbycard_ticket_id'] = null;
            widget.onChanged();
            if (mounted) { setState(() {}); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Karte verlängert — neues Erinnerungs-Ticket geplant'))); }
          })),
      ],
      if (hasMeldedaten) ...[
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 8),
        Row(children: [Icon(Icons.home, size: 13, color: F.h(Colors.teal, 600)), const SizedBox(width: 6), Text('Meldedaten', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: F.h(Colors.teal, 700)))]),
        const SizedBox(height: 6),
        _infoRow(Icons.event_available, 'Einzugsdatum', v['einzugsdatum']),
        _infoRow(Icons.location_on, 'Meldeadresse', v['meldeadresse']),
        _infoRow(Icons.home_work, 'Nebenwohnsitz', v['nebenwohnsitz']),
        _infoRow(Icons.description, 'Meldebescheinigung-Nr.', v['meldebescheinigung_nr']),
      ],
      if ((v['notiz']?.toString() ?? '').isNotEmpty) ...[
        const SizedBox(height: 10),
        Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: F.h(Colors.grey, 50), borderRadius: BorderRadius.circular(8)),
          child: Text(v['notiz'].toString(), style: const TextStyle(fontSize: 12))),
      ],
    ]));
  }

  Widget _infoRow(IconData icon, String label, dynamic value) {
    final val = value?.toString() ?? '';
    if (val.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [
      Icon(icon, size: 14, color: F.h(Colors.teal, 600)), const SizedBox(width: 8),
      Text('$label: ', style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
      Expanded(child: Text(val, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
    ]));
  }

  Widget _lcBoolRow(String label, bool ok) {
    return Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [
      Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked, size: 14, color: ok ? F.h(Colors.green, 600) : F.h(Colors.grey, 400)), const SizedBox(width: 8),
      Text(label, style: TextStyle(fontSize: 12, color: ok ? F.h(Colors.grey, 800) : F.h(Colors.grey, 500))),
    ]));
  }

  /// Die Meldebestätigung: genau EINE je Vorfall.
  ///
  /// ⚠️ Eine neue Datei ersetzt die alte, statt sie abzulehnen. Ein schiefer
  /// Scan ließe sich sonst nur durch Löschen-und-neu-Hochladen korrigieren —
  /// zwei Schritte für den Regelfall. Der Austausch geschieht auf dem Server
  /// in einer Transaktion, damit nie beides gleichzeitig weg ist.
  Widget _buildDokument(Map<String, dynamic> v, String titel) {
    final d = _dokument;
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.description, size: 14, color: F.h(Colors.teal, 600)), const SizedBox(width: 6),
        Expanded(child: Text(titel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: F.h(Colors.teal, 700)))),
      ]),
      const SizedBox(height: 4),
      Text(buergeramtDokHinweis(v['typ']?.toString()), style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
      const SizedBox(height: 12),
      if (d == null)
        Container(width: double.infinity, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: F.h(Colors.grey, 50), borderRadius: BorderRadius.circular(8), border: Border.all(color: F.h(Colors.grey, 300))),
          child: Column(children: [
            Icon(Icons.upload_file, size: 28, color: F.h(Colors.grey, 400)), const SizedBox(height: 6),
            Text('Noch keine $titel hinterlegt', style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600))),
          ]))
      else
        Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: F.h(Colors.teal, 50), borderRadius: BorderRadius.circular(8), border: Border.all(color: F.h(Colors.teal, 200))),
          child: Row(children: [
            Icon((d['mime']?.toString() ?? '').contains('pdf') ? Icons.picture_as_pdf : Icons.image, size: 20, color: F.h(Colors.teal, 700)),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d['original_name']?.toString() ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
              Text(_groesse((d['groesse'] as num?)?.toInt() ?? 0), style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
            ])),
            IconButton(icon: Icon(Icons.visibility, size: 18, color: F.h(Colors.teal, 700)), tooltip: 'Ansehen', onPressed: () => _dokAnsehen(d)),
            IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400), tooltip: 'Löschen', onPressed: () => _dokLoeschen(d)),
          ])),
      const SizedBox(height: 12),
      Row(children: [
        FilledButton.icon(
          icon: _dokLaeuft
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.attach_file, size: 16),
          label: Text(d == null ? '$titel hochladen' : 'Ersetzen', style: const TextStyle(fontSize: 12)),
          style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade600),
          onPressed: _dokLaeuft ? null : _dokHochladen),
      ]),
      const SizedBox(height: 8),
      Text('PDF, JPG oder JPEG · höchstens 20 MB · eine Datei', style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 500), fontStyle: FontStyle.italic)),
    ]));
  }

  String _groesse(int b) => b >= 1024 * 1024
      ? '${(b / 1024 / 1024).toStringAsFixed(1)} MB'
      : '${(b / 1024).toStringAsFixed(0)} kB';

  void _sagen(String text, {bool fehler = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: fehler ? Colors.red.shade700 : null,
    ));
  }

  Future<void> _dokHochladen() async {
    final auswahl = await FilePickerHelper.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: kBuergeramtDokEndungen,
    );
    final datei = (auswahl?.files ?? []).firstOrNull;
    if (datei == null) return;
    // ⚠️ Der Dateiwähler lässt sich auf manchen Plattformen umgehen („alle
    // Dateien"); die Endung wird deshalb hier NOCH einmal geprüft und auf
    // dem Server ein drittes Mal gegen den Inhalt.
    final grund = buergeramtDokAblehnung(datei.name, datei.size);
    if (grund != null) { _sagen(grund, fehler: true); return; }
    if (datei.path == null) { _sagen('Diese Datei lässt sich hier nicht lesen.', fehler: true); return; }

    setState(() => _dokLaeuft = true);
    final r = await widget.apiService.uploadBuergeramtDokument(
      userId: widget.userId, vorfallId: widget.vorfallId,
      pfad: datei.path!, dateiname: datei.name);
    if (!mounted) return;
    setState(() => _dokLaeuft = false);
    if (r['success'] == true) {
      _sagen('Bestätigung gespeichert');
      await _load();
    } else {
      // ⚠️ Den Grund des Servers zeigen. Ein stilles Zurücksetzen ist für den
      // Nutzer nicht von „ich habe danebengetippt" zu unterscheiden.
      _sagen('Nicht hochgeladen: ${r['message'] ?? 'unbekannter Fehler'}', fehler: true);
    }
  }

  /// Zeigt die Bestätigung IM PROGRAMM, aus dem Arbeitsspeicher.
  ///
  /// ⚠️ Nicht auf die Platte und nicht an ein fremdes Programm: eine
  /// Meldebestätigung trägt Name und Anschrift eines Mitglieds. Auf dem
  /// Server liegt sie mit einigem Aufwand verschlüsselt — sie hier
  /// entschlüsselt abzulegen gäbe das wieder her, und ein fremder Betrachter
  /// behielte sie ohnehin (eigener Verlauf, eigene Wolkensicherung).
  Future<void> _dokAnsehen(Map<String, dynamic> d) async {
    final id = d['id'] is int ? d['id'] as int : int.tryParse(d['id'].toString()) ?? 0;
    final r = await widget.apiService.downloadBuergeramtDokument(widget.userId, id);
    if (!mounted) return;
    if (r.statusCode != 200 || r.bodyBytes.isEmpty) {
      _sagen('Bestätigung nicht abrufbar (HTTP ${r.statusCode}).', fehler: true);
      return;
    }
    final name = d['original_name']?.toString() ?? 'bestaetigung.pdf';
    final gezeigt = await FileViewerDialog.showFromBytes(context, r.bodyBytes, name);
    if (!gezeigt && mounted) {
      _sagen('Dieser Dateityp lässt sich hier nicht anzeigen: $name', fehler: true);
    }
  }

  Future<void> _dokLoeschen(Map<String, dynamic> d) async {
    final sicher = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Bestätigung löschen?', style: TextStyle(fontSize: 15)),
      content: Text('„${d['original_name'] ?? ''}" wird endgültig entfernt.', style: const TextStyle(fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
          onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
      ]));
    if (sicher != true) return;
    final id = d['id'] is int ? d['id'] as int : int.tryParse(d['id'].toString()) ?? 0;
    final r = await widget.apiService.deleteBuergeramtDokument(widget.userId, id);
    if (!mounted) return;
    if (r['success'] == true) { _sagen('Bestätigung gelöscht'); await _load(); }
    else { _sagen('Nicht gelöscht: ${r['message'] ?? 'unbekannter Fehler'}', fehler: true); }
  }

  Widget _buildKorr() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        const Spacer(),
        FilledButton.icon(icon: const Icon(Icons.call_received, size: 14), label: const Text('Eingang', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.green.shade600, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _addKorr('eingang')),
        const SizedBox(width: 6),
        FilledButton.icon(icon: const Icon(Icons.call_made, size: 14), label: const Text('Ausgang', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade600, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _addKorr('ausgang')),
      ])),
      Expanded(child: _korr.isEmpty ? Center(child: Text('Keine Korrespondenz', style: TextStyle(color: F.h(Colors.grey, 500))))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _korr.length, itemBuilder: (_, i) {
            final k = _korr[i]; final isEin = k['richtung'] == 'eingang'; final c = isEin ? Colors.green : Colors.blue;
            const mL = {'email': 'E-Mail', 'post': 'Post', 'online': 'Online', 'persoenlich': 'Persönlich', 'fax': 'Fax', 'telefon': 'Telefon'};
            final kId = k['id'] is int ? k['id'] as int : int.parse(k['id'].toString());
            return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: F.h(c, 50), borderRadius: BorderRadius.circular(8), border: Border.all(color: F.h(c, 200))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(isEin ? Icons.call_received : Icons.call_made, size: 14, color: F.h(c, 700)), const SizedBox(width: 6),
                  Expanded(child: Text(k['betreff']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: F.h(c, 800)))),
                  if ((k['methode']?.toString() ?? '').isNotEmpty) Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: F.h(c, 100), borderRadius: BorderRadius.circular(4)),
                    child: Text(mL[k['methode']] ?? k['methode'].toString(), style: TextStyle(fontSize: 9, color: F.h(c, 700)))),
                  const SizedBox(width: 4),
                  IconButton(icon: Icon(Icons.delete_outline, size: 14, color: Colors.red.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: () async { await widget.apiService.deleteBuergeramtKorr(widget.userId, kId); _load(); }),
                ]),
                if ((k['datum']?.toString() ?? '').isNotEmpty) Text(k['datum'].toString(), style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
                if ((k['notiz']?.toString() ?? '').isNotEmpty) Text(k['notiz'].toString(), style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 500))),
                Padding(padding: const EdgeInsets.only(top: 4), child: KorrAttachmentsWidget(apiService: widget.apiService, modul: 'buergeramt', korrespondenzId: kId, memberId: widget.userId)),
              ]));
          })),
    ]);
  }

  void _addKorr(String richtung) {
    final datumC = TextEditingController(); final betreffC = TextEditingController(); final notizC = TextEditingController();
    String methode = richtung == 'eingang' ? 'post' : 'email';
    List<PlatformFile> files = [];
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) => AlertDialog(
      title: Row(children: [Icon(richtung == 'eingang' ? Icons.call_received : Icons.call_made, size: 18, color: richtung == 'eingang' ? F.h(Colors.green, 700) : F.h(Colors.blue, 700)), const SizedBox(width: 8), Text(richtung == 'eingang' ? 'Eingang' : 'Ausgang', style: const TextStyle(fontSize: 14))]),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Wrap(spacing: 6, runSpacing: 4, children: [for (final m in [('email', 'E-Mail', Icons.email), ('post', 'Post', Icons.mail), ('online', 'Online', Icons.language), ('persoenlich', 'Persönlich', Icons.person), ('fax', 'Fax', Icons.fax)])
          ChoiceChip(label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(m.$3, size: 13, color: methode == m.$1 ? Colors.white : F.h(Colors.grey, 700)), const SizedBox(width: 4), Text(m.$2, style: TextStyle(fontSize: 10, color: methode == m.$1 ? Colors.white : F.h(Colors.grey, 700)))]),
            selected: methode == m.$1, selectedColor: Colors.indigo.shade600, onSelected: (_) => setDlg(() => methode = m.$1))]),
        const SizedBox(height: 12),
        TextFormField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', prefixIcon: const Icon(Icons.calendar_today, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async { final p = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de')); if (p != null) setDlg(() => datumC.text = '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}'); }))),
        const SizedBox(height: 8),
        TextField(controller: betreffC, decoration: InputDecoration(labelText: 'Betreff *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 12),
        OutlinedButton.icon(icon: Icon(Icons.attach_file, size: 16, color: F.h(Colors.teal, 600)),
          label: Text(files.isEmpty ? 'Dokumente anhängen' : '${files.length} Datei(en)', style: TextStyle(fontSize: 12, color: F.h(Colors.teal, 700))),
          style: OutlinedButton.styleFrom(side: BorderSide(color: F.h(Colors.teal, 300))),
          onPressed: () async { final r = await FilePickerHelper.pickFiles(allowMultiple: true, type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']); if (r != null) setDlg(() { files.addAll(r.files); if (files.length > 20) files = files.sublist(0, 20); }); }),
        const SizedBox(height: 6),
        Align(alignment: Alignment.centerLeft, child: CloudPickButton(
          memberId: widget.userId,
          apiService: widget.apiService,
          allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
          maxFiles: 20,
          kompakt: true,
          onPicked: (r) => setDlg(() { files.addAll(r.files); if (files.length > 20) files = files.sublist(0, 20); }),
        )),
        if (files.isNotEmpty) ...files.asMap().entries.map((e) => Padding(padding: const EdgeInsets.only(top: 3), child: Row(children: [
          Icon(Icons.description, size: 13, color: F.h(Colors.grey, 500)), const SizedBox(width: 6),
          Expanded(child: Text(e.value.name, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
          IconButton(icon: Icon(Icons.close, size: 14, color: Colors.red.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24), onPressed: () => setDlg(() => files.removeAt(e.key))),
        ]))),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          if (betreffC.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Betreff angeben'), backgroundColor: Colors.orange)); return; }
          final res = await widget.apiService.saveBuergeramtKorr(widget.userId, widget.vorfallId, {'richtung': richtung, 'methode': methode, 'datum': datumC.text.trim(), 'betreff': betreffC.text.trim(), 'notiz': notizC.text.trim()});
          final korrId = res['id'];
          if (korrId != null && files.isNotEmpty) { for (final f in files) { if (f.path == null) continue; await widget.apiService.uploadKorrAttachment(modul: 'buergeramt', korrespondenzId: korrId is int ? korrId : int.parse(korrId.toString()), filePath: f.path!, fileName: f.name); } }
          if (ctx.mounted) Navigator.pop(ctx); _load();
        }, child: const Text('Speichern')),
      ],
    )));
  }

  Widget _buildVerlauf() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [const Spacer(),
        FilledButton.icon(icon: const Icon(Icons.add, size: 14), label: const Text('Eintrag', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade600, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _addVerlauf()),
      ])),
      Expanded(child: _verlauf.isEmpty ? Center(child: Text('Noch keine Einträge', style: TextStyle(color: F.h(Colors.grey, 500))))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _verlauf.length, itemBuilder: (_, i) {
            final e = _verlauf[i];
            return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: F.h(Colors.grey, 50), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Icon(Icons.circle, size: 8, color: Colors.teal.shade400), const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e['aktion']?.toString() ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  if ((e['datum']?.toString() ?? '').isNotEmpty) Text(e['datum'].toString(), style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
                  if ((e['notiz']?.toString() ?? '').isNotEmpty) Text(e['notiz'].toString(), style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 500))),
                ])),
              ]));
          })),
    ]);
  }

  void _addVerlauf() {
    final datumC = TextEditingController(); final aktionC = TextEditingController(); final notizC = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Verlauf-Eintrag', style: TextStyle(fontSize: 14)),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', prefixIcon: const Icon(Icons.calendar_today, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async { final p = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de')); if (p != null) datumC.text = '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}'; }))),
        const SizedBox(height: 8),
        TextField(controller: aktionC, decoration: InputDecoration(labelText: 'Aktion *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          await widget.apiService.saveBuergeramtVerlauf(widget.userId, widget.vorfallId, {'datum': datumC.text.trim(), 'aktion': aktionC.text.trim(), 'notiz': notizC.text.trim()});
          if (ctx.mounted) Navigator.pop(ctx); _load();
        }, child: const Text('Speichern')),
      ],
    ));
  }

  Widget _buildTermine() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [const Spacer(),
        FilledButton.icon(icon: const Icon(Icons.add, size: 14), label: const Text('Neuer Termin', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade600, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _addTermin()),
      ])),
      Expanded(child: _termine.isEmpty ? Center(child: Text('Keine Termine', style: TextStyle(color: F.h(Colors.grey, 500))))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _termine.length, itemBuilder: (_, i) {
            final t = _termine[i];
            return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: F.h(Colors.purple, 50), borderRadius: BorderRadius.circular(8), border: Border.all(color: F.h(Colors.purple, 200))),
              child: Row(children: [
                Icon(Icons.event, size: 16, color: F.h(Colors.purple, 700)), const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${t['datum'] ?? ''} ${t['uhrzeit'] ?? ''}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: F.h(Colors.purple, 800))),
                  if ((t['ort']?.toString() ?? '').isNotEmpty) Text(t['ort'].toString(), style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
                  if ((t['notiz']?.toString() ?? '').isNotEmpty) Text(t['notiz'].toString(), style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 500))),
                ])),
                IconButton(icon: Icon(Icons.delete_outline, size: 14, color: Colors.red.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: () async { await widget.apiService.deleteBuergeramtTermin(widget.userId, t['id'] is int ? t['id'] : int.parse(t['id'].toString())); _load(); }),
              ]));
          })),
    ]);
  }

  void _addTermin() {
    final datumC = TextEditingController(); final uhrzeitC = TextEditingController(); final ortC = TextEditingController(); final notizC = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Neuer Termin', style: TextStyle(fontSize: 14)),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', prefixIcon: const Icon(Icons.calendar_today, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async { final p = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de')); if (p != null) datumC.text = '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}'; }))),
        const SizedBox(height: 8),
        TextField(controller: uhrzeitC, decoration: InputDecoration(labelText: 'Uhrzeit', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 8),
        TextField(controller: ortC, decoration: InputDecoration(labelText: 'Ort', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          await widget.apiService.saveBuergeramtTermin(widget.userId, widget.vorfallId, {'datum': datumC.text.trim(), 'uhrzeit': uhrzeitC.text.trim(), 'ort': ortC.text.trim(), 'notiz': notizC.text.trim()});
          if (ctx.mounted) Navigator.pop(ctx); _load();
        }, child: const Text('Speichern')),
      ],
    ));
  }
}
