import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';
import 'file_viewer_dialog.dart';

class BehordeGerichtContent extends StatefulWidget {
  final User user;
  final ApiService apiService;
  final Map<String, dynamic> Function(String type) getData;
  final bool Function(String type) isLoading;
  final bool Function(String type) isSaving;
  final void Function(String type) loadData;
  final void Function(String type, Map<String, dynamic> data) saveData;

  const BehordeGerichtContent({
    super.key,
    required this.user,
    required this.apiService,
    required this.getData,
    required this.isLoading,
    required this.isSaving,
    required this.loadData,
    required this.saveData,
  });

  @override
  State<BehordeGerichtContent> createState() => _BehordeGerichtContentState();
}

class _BehordeGerichtContentState extends State<BehordeGerichtContent> {

  // DB per gericht_typ
  final Map<String, Map<String, Map<String, dynamic>>> _gerichtData = {};
  final Map<String, List<Map<String, dynamic>>> _vorfaelle = {};
  final Map<String, List<Map<String, dynamic>>> _termine = {};
  final Map<String, List<Map<String, dynamic>>> _korrespondenz = {};
  final Map<String, bool> _loaded = {};

  static const _gerichtTypen = [
    ('arbeitsgericht', 'Arbeitsgericht', Icons.work, Colors.orange),
    ('sozialgericht', 'Sozialgericht', Icons.balance, Colors.teal),
    ('betreuungsgericht', 'Betreuungsgericht', Icons.family_restroom, Colors.deepPurple),
  ];

  // Gerichte Datenbank
  static const Map<String, List<Map<String, String>>> _gerichtDB = {
    'arbeitsgericht': [
      {'name': 'Arbeitsgericht Ulm', 'adresse': 'Olgastraße 109, 89073 Ulm', 'telefon': '0731 / 189-0', 'fax': '0731 / 189-197', 'email': 'poststelle@agulm.justiz.bwl.de', 'oeffnungszeiten': 'Mo–Fr 08:30–12:00, Di+Do 13:00–15:30', 'zustaendigkeit': 'Arbeitsrechtliche Streitigkeiten Stadt Ulm, Alb-Donau-Kreis'},
      {'name': 'Arbeitsgericht Augsburg — Kammer Neu-Ulm', 'adresse': 'Meininger Allee 5, 89231 Neu-Ulm', 'telefon': '0821 / 3217-01', 'fax': '0821 / 3217-400', 'email': 'poststelle@arbg-a.bayern.de', 'oeffnungszeiten': 'Mo–Do 08:00–15:30, Fr 08:00–12:00', 'zustaendigkeit': 'Arbeitsrechtliche Streitigkeiten Landkreis Neu-Ulm, Schwaben'},
      {'name': 'Arbeitsgericht Kempten', 'adresse': 'Residenzplatz 4, 87435 Kempten', 'telefon': '0831 / 25277-0', 'fax': '0831 / 25277-79', 'email': 'poststelle@arbg-ke.bayern.de', 'oeffnungszeiten': 'Mo–Do 08:00–15:30, Fr 08:00–12:00', 'zustaendigkeit': 'Oberallgäu, Lindau, Kaufbeuren'},
      {'name': 'Arbeitsgericht Memmingen', 'adresse': 'Bodenseestraße 4, 87700 Memmingen', 'telefon': '08331 / 100-0', 'fax': '08331 / 100-299', 'email': 'poststelle@arbg-mm.bayern.de', 'oeffnungszeiten': 'Mo–Fr 08:00–12:00', 'zustaendigkeit': 'Unterallgäu, Memmingen'},
    ],
    'sozialgericht': [
      {'name': 'Sozialgericht Ulm', 'adresse': 'Olgastraße 109, 89073 Ulm', 'telefon': '0731 / 189-0', 'email': 'poststelle@sgulm.justiz.bwl.de', 'oeffnungszeiten': 'Mo–Fr 08:30–12:00', 'zustaendigkeit': 'Sozialrechtliche Streitigkeiten Stadt Ulm, Alb-Donau-Kreis'},
      {'name': 'Sozialgericht Augsburg', 'adresse': 'Am Alten Einlaß 1, 86150 Augsburg', 'telefon': '0821 / 3207-01', 'fax': '0821 / 3207-199', 'email': 'poststelle@sg-a.bayern.de', 'oeffnungszeiten': 'Mo–Do 08:00–15:30, Fr 08:00–12:00', 'zustaendigkeit': 'Sozialrechtliche Streitigkeiten Schwaben, Landkreis Neu-Ulm'},
      {'name': 'Sozialgericht München', 'adresse': 'Bayerstraße 32, 80335 München', 'telefon': '089 / 5597-7800', 'email': 'poststelle@sg-m.bayern.de', 'oeffnungszeiten': 'Mo–Fr 08:00–12:00', 'zustaendigkeit': 'Oberbayern'},
      {'name': 'Bayerisches Landessozialgericht', 'adresse': 'Ludwigstraße 15, 80539 München', 'telefon': '089 / 2160-0', 'email': 'poststelle@lsg.bayern.de', 'oeffnungszeiten': 'Mo–Fr 08:00–12:00', 'zustaendigkeit': 'Berufungsinstanz für alle Sozialgerichte in Bayern'},
    ],
    'betreuungsgericht': [
      {'name': 'Amtsgericht Neu-Ulm — Betreuungsgericht', 'adresse': 'Schützenstraße 60, 89231 Neu-Ulm', 'telefon': '0731 / 70793 -422, -424, -425', 'fax': '0731 / 70793-499', 'email': 'betreuungsgericht@ag-nu.bayern.de', 'oeffnungszeiten': 'Mo–Fr 08:00–12:00', 'zustaendigkeit': 'Betreuungsverfahren, Vormundschaft, Pflegschaft — Landkreis Neu-Ulm'},
      {'name': 'Amtsgericht Ulm — Betreuungsgericht', 'adresse': 'Olgastraße 109, 89073 Ulm', 'telefon': '0731 / 189-0', 'fax': '0731 / 189-197', 'email': 'poststelle@agulm.justiz.bwl.de', 'oeffnungszeiten': 'Mo–Fr 08:30–12:00, Di+Do 13:00–15:30', 'zustaendigkeit': 'Betreuungsverfahren — Stadt Ulm'},
      {'name': 'Amtsgericht Memmingen — Betreuungsgericht', 'adresse': 'Bodenseestraße 4, 87700 Memmingen', 'telefon': '08331 / 100-0', 'fax': '08331 / 100-299', 'email': 'poststelle@ag-mm.bayern.de', 'oeffnungszeiten': 'Mo–Fr 08:00–12:00', 'zustaendigkeit': 'Betreuungsverfahren, Vormundschaft — Memmingen, Unterallgäu'},
    ],
  };

  Future<void> _loadAll(String typ) async {
    if (_loaded[typ] == true) return;
    final uid = widget.user.id;
    final dR = await widget.apiService.getGerichtData(uid, typ);
    final vR = await widget.apiService.listGerichtVorfaelle(uid, typ);
    final tR = await widget.apiService.listGerichtTermineDB(uid, typ);
    final kR = await widget.apiService.listGerichtKorrespondenzDB(uid, typ);
    if (!mounted) return;
    setState(() {
      if (dR['success'] == true && dR['data'] is Map) {
        _gerichtData[typ] = {};
        (dR['data'] as Map).forEach((k, v) { if (v is Map) _gerichtData[typ]![k.toString()] = Map<String, dynamic>.from(v); });
      }
      if (vR['success'] == true && vR['data'] is List) _vorfaelle[typ] = (vR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (tR['success'] == true && tR['data'] is List) _termine[typ] = (tR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (kR['success'] == true && kR['data'] is List) _korrespondenz[typ] = (kR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _loaded[typ] = true;
    });
  }

  Map<String, dynamic> _d(String typ, String bereich) {
    _gerichtData[typ] ??= {};
    _gerichtData[typ]![bereich] ??= {};
    return _gerichtData[typ]![bereich]!;
  }

  Future<void> _saveData(String typ) async {
    await widget.apiService.saveGerichtData(widget.user.id, typ, _gerichtData[typ] ?? {});
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(children: [
        TabBar(
          labelColor: Colors.indigo.shade700,
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: Colors.indigo.shade700,
          tabs: _gerichtTypen.map((g) => Tab(icon: Icon(g.$3, size: 16), text: g.$2)).toList(),
        ),
        Expanded(child: TabBarView(
          children: _gerichtTypen.map((g) => _buildGerichtContent(g.$1, g.$2, g.$4)).toList(),
        )),
      ]),
    );
  }

  Widget _buildGerichtContent(String typ, String label, MaterialColor color) {
    if (_loaded[typ] != true) {
      _loadAll(typ);
      return const Center(child: CircularProgressIndicator());
    }
    return DefaultTabController(
      length: 4,
      child: Column(children: [
        TabBar(
          labelColor: color.shade700, unselectedLabelColor: Colors.grey.shade600, indicatorColor: color.shade700, isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.account_balance, size: 14), text: 'Zuständiges Gericht'),
            Tab(icon: Icon(Icons.report_problem, size: 14), text: 'Vorfall'),
            Tab(icon: Icon(Icons.calendar_month, size: 14), text: 'Termine'),
            Tab(icon: Icon(Icons.mail, size: 14), text: 'Korrespondenz'),
          ],
        ),
        Expanded(child: TabBarView(children: [
          _buildGerichtTab(typ, color),
          _buildVorfallTab(typ, label, color),
          _buildTermineTab(typ, color),
          _buildKorrespondenzTab(typ, color),
        ])),
      ]),
    );
  }

  // ============ TAB 1: ZUSTÄNDIGES GERICHT ============

  Widget _buildGerichtTab(String typ, MaterialColor color) {
    final d = _d(typ, 'gericht');
    final selectedName = d['name']?.toString() ?? '';
    final gerichte = _gerichtDB[typ] ?? [];
    final selected = gerichte.where((g) => g['name'] == selectedName).firstOrNull;

    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Zuständiges Gericht wählen', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color.shade800)),
      const SizedBox(height: 8),
      ...gerichte.map((g) {
        final isSel = selectedName == g['name'];
        return InkWell(
          onTap: () {
            setState(() { d['name'] = g['name']; d['adresse'] = g['adresse']; d['telefon'] = g['telefon']; d['oeffnungszeiten'] = g['oeffnungszeiten']; });
            _saveData(typ);
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: isSel ? color.shade50 : Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: isSel ? color.shade400 : Colors.grey.shade300, width: isSel ? 2 : 1)),
            child: Row(children: [
              Icon(isSel ? Icons.check_circle : Icons.account_balance, size: 20, color: isSel ? color.shade700 : Colors.grey.shade500),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g['name']!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isSel ? color.shade900 : Colors.black87)),
                Text(g['adresse']!, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                if (g['zustaendigkeit'] != null) Text(g['zustaendigkeit']!, style: TextStyle(fontSize: 10, color: color.shade400, fontStyle: FontStyle.italic)),
              ])),
            ]),
          ),
        );
      }),
      if (selected != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: color.shade200)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Kontakt', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color.shade800)),
            const SizedBox(height: 6),
            _infoRow(Icons.phone, 'Telefon', selected['telefon'] ?? ''),
            if ((selected['fax'] ?? '').isNotEmpty) _infoRow(Icons.print, 'Fax', selected['fax']!),
            _infoRow(Icons.email, 'E-Mail', selected['email'] ?? ''),
            _infoRow(Icons.access_time, 'Öffnungszeiten', selected['oeffnungszeiten'] ?? ''),
          ]),
        ),
      ],
      const SizedBox(height: 12),
      _fieldWithSave(typ, 'gericht', 'aktenzeichen', 'Aktenzeichen', Icons.tag),
      _fieldWithSave(typ, 'gericht', 'sachbearbeiter', 'Sachbearbeiter/in', Icons.person),
    ]));
  }

  // ============ TAB 2: VORFALL ============

  Widget _buildVorfallTab(String typ, String label, MaterialColor color) {
    final list = _vorfaelle[typ] ?? [];
    final antragTypen = typ == 'betreuungsgericht'
        ? ['Betreuung einrichten', 'Betreuerwechsel', 'Betreuung aufheben', 'Unterbringung', 'Vermögenssorge', 'Sonstiges']
        : typ == 'sozialgericht'
            ? ['Klage gegen Bescheid', 'Einstweiliger Rechtsschutz', 'Widerspruch', 'Berufung', 'Prozesskostenhilfe', 'Sonstiges']
            : ['Kündigungsschutzklage', 'Lohnklage', 'Zeugnis einklagen', 'Einstweilige Verfügung', 'Prozesskostenhilfe', 'Sonstiges'];
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Row(children: [
        Icon(Icons.report_problem, size: 20, color: color.shade700), const SizedBox(width: 8),
        Expanded(child: Text('Vorfälle (${list.length})', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color.shade700))),
        ElevatedButton.icon(
          onPressed: () => _showVorfallDialog(typ, label, color, antragTypen),
          icon: const Icon(Icons.add, size: 16), label: const Text('Neuer Vorfall', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
        ),
      ])),
      Expanded(child: list.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.folder_open, size: 48, color: Colors.grey.shade300), const SizedBox(height: 8), Text('Keine Vorfälle', style: TextStyle(color: Colors.grey.shade500))]))
          : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: list.length, itemBuilder: (_, i) {
              final v = list[i];
              final status = v['status']?.toString() ?? 'offen';
              return Card(child: ListTile(
                leading: Icon(_statusIcon(status), color: _statusColor(status), size: 28),
                title: Text(v['titel']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${v['datum'] ?? ''} • ${_statusLabel(status)}', style: TextStyle(fontSize: 11, color: _statusColor(status))),
                  if ((v['aktenzeichen']?.toString() ?? '').isNotEmpty) Text('Az.: ${v['aktenzeichen']}', style: TextStyle(fontSize: 10, color: color.shade600, fontWeight: FontWeight.w600)),
                ]),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400), onPressed: () async {
                    final id = int.tryParse(v['id']?.toString() ?? '');
                    if (id != null) { await widget.apiService.deleteGerichtVorfall(id); _loaded[typ] = false; setState(() {}); }
                  }),
                  Icon(Icons.chevron_right, color: Colors.grey.shade400),
                ]),
                onTap: () => _showVorfallDialog(typ, label, color, antragTypen, existing: v),
              ));
            })),
    ]);
  }

  void _showVorfallDialog(String typ, String label, MaterialColor color, List<String> antragTypen, {Map<String, dynamic>? existing}) {
    final isEdit = existing != null;
    final titelC = TextEditingController(text: existing?['titel']?.toString() ?? '');
    final aktenC = TextEditingController(text: existing?['aktenzeichen']?.toString() ?? '');
    final datumC = TextEditingController(text: existing?['datum']?.toString() ?? '');
    final sachC = TextEditingController(text: existing?['sachbearbeiter']?.toString() ?? '');
    final sachTelC = TextEditingController(text: existing?['sachbearbeiter_tel']?.toString() ?? '');
    final sachEmailC = TextEditingController(text: existing?['sachbearbeiter_email']?.toString() ?? '');
    final notizC = TextEditingController(text: existing?['notiz']?.toString() ?? '');
    String status = existing?['status']?.toString() ?? 'offen';

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(isEdit ? 'Vorfall bearbeiten' : 'Neuer Vorfall', style: TextStyle(color: color.shade700)),
      content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        DropdownButtonFormField<String>(
          value: antragTypen.contains(titelC.text) ? titelC.text : null,
          decoration: InputDecoration(labelText: 'Art *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          items: antragTypen.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 13)))).toList(),
          onChanged: (v) => setD(() => titelC.text = v ?? ''),
        ),
        const SizedBox(height: 8),
        TextField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', prefixIcon: const Icon(Icons.calendar_today, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          onTap: () async { final p = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de')); if (p != null) datumC.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}'; }),
        const SizedBox(height: 8),
        TextField(controller: aktenC, decoration: InputDecoration(labelText: 'Aktenzeichen', prefixIcon: const Icon(Icons.tag, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in [('offen', 'Offen', Colors.orange), ('in_bearbeitung', 'In Bearbeitung', Colors.blue), ('bewilligt', 'Bewilligt', Colors.green), ('abgelehnt', 'Abgelehnt', Colors.red), ('erledigt', 'Erledigt', Colors.grey)])
            ChoiceChip(label: Text(s.$2, style: TextStyle(fontSize: 11, color: status == s.$1 ? Colors.white : Colors.black87)), selected: status == s.$1, selectedColor: s.$3, onSelected: (_) => setD(() => status = s.$1)),
        ]),
        const SizedBox(height: 8),
        TextField(controller: sachC, decoration: InputDecoration(labelText: 'Sachbearbeiter/Richter', prefixIcon: const Icon(Icons.person, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: sachTelC, decoration: InputDecoration(labelText: 'Telefon', prefixIcon: const Icon(Icons.phone, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: sachEmailC, decoration: InputDecoration(labelText: 'E-Mail', prefixIcon: const Icon(Icons.email, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
        ]),
        const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 3, decoration: InputDecoration(labelText: 'Notizen', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          if (titelC.text.isEmpty) return;
          await widget.apiService.saveGerichtVorfall(widget.user.id, typ, {
            if (isEdit) 'id': existing['id'],
            'titel': titelC.text, 'aktenzeichen': aktenC.text, 'datum': datumC.text,
            'status': status, 'sachbearbeiter': sachC.text, 'sachbearbeiter_tel': sachTelC.text,
            'sachbearbeiter_email': sachEmailC.text, 'notiz': notizC.text,
          });
          if (ctx.mounted) Navigator.pop(ctx);
          _loaded[typ] = false; setState(() {});
        }, style: FilledButton.styleFrom(backgroundColor: color), child: Text(isEdit ? 'Speichern' : 'Erstellen')),
      ],
    )));
  }

  // ============ TAB 3: TERMINE ============

  Widget _buildTermineTab(String typ, MaterialColor color) {
    final list = _termine[typ] ?? [];
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Row(children: [
        Icon(Icons.calendar_month, size: 20, color: color.shade700), const SizedBox(width: 8),
        Expanded(child: Text('Termine (${list.length})', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color.shade700))),
        ElevatedButton.icon(
          onPressed: () => _showTerminDialog(typ, color),
          icon: const Icon(Icons.add, size: 16), label: const Text('Neuer Termin', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
        ),
      ])),
      Expanded(child: list.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.event_available, size: 48, color: Colors.grey.shade300), const SizedBox(height: 8), Text('Keine Termine', style: TextStyle(color: Colors.grey.shade500))]))
          : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: list.length, itemBuilder: (_, i) {
              final t = list[i];
              return Card(child: ListTile(
                leading: Icon(Icons.event, color: color.shade700),
                title: Text('${t['datum'] ?? ''}${(t['uhrzeit']?.toString() ?? '').isNotEmpty ? ' um ${t['uhrzeit']}' : ''}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if ((t['ort']?.toString() ?? '').isNotEmpty) Text(t['ort'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  if ((t['notiz']?.toString() ?? '').isNotEmpty) Text(t['notiz'].toString(), style: const TextStyle(fontSize: 11)),
                ]),
                trailing: IconButton(icon: Icon(Icons.delete, size: 18, color: Colors.red.shade400), onPressed: () async {
                  final id = int.tryParse(t['id']?.toString() ?? '');
                  if (id != null) { await widget.apiService.deleteGerichtTermin(id); _loaded[typ] = false; setState(() {}); }
                }),
              ));
            })),
    ]);
  }

  void _showTerminDialog(String typ, MaterialColor color) {
    final datumC = TextEditingController();
    final uhrzeitC = TextEditingController();
    final ortC = TextEditingController();
    final notizC = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Neuer Termin'),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          onTap: () async { final p = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de')); if (p != null) datumC.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}'; }),
        const SizedBox(height: 8),
        TextField(controller: uhrzeitC, decoration: InputDecoration(labelText: 'Uhrzeit', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 8),
        TextField(controller: ortC, decoration: InputDecoration(labelText: 'Ort / Saal', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 3, decoration: InputDecoration(labelText: 'Notizen', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          if (datumC.text.isEmpty) return;
          await widget.apiService.saveGerichtTermin(widget.user.id, typ, {'datum': datumC.text, 'uhrzeit': uhrzeitC.text, 'ort': ortC.text, 'notiz': notizC.text});
          if (ctx.mounted) Navigator.pop(ctx);
          _loaded[typ] = false; setState(() {});
        }, style: FilledButton.styleFrom(backgroundColor: color), child: const Text('Speichern')),
      ],
    ));
  }

  // ============ TAB 4: KORRESPONDENZ ============

  Widget _buildKorrespondenzTab(String typ, MaterialColor color) {
    final list = _korrespondenz[typ] ?? [];
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Expanded(child: Text('${list.length} Einträge', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
        FilledButton.icon(icon: const Icon(Icons.call_received, size: 14), label: const Text('Eingang', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.green.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _showKorrDialog(typ, 'eingang')),
        const SizedBox(width: 6),
        FilledButton.icon(icon: const Icon(Icons.call_made, size: 14), label: const Text('Ausgang', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _showKorrDialog(typ, 'ausgang')),
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
                    if (kid != null) { await widget.apiService.deleteGerichtKorrespondenz(kid); _loaded[typ] = false; setState(() {}); }
                  }, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28)),
                ]),
              );
            })),
    ]);
  }

  void _showKorrDialog(String typ, String richtung) {
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
          await widget.apiService.saveGerichtKorrespondenz(widget.user.id, typ, {'richtung': richtung, 'datum': datumC.text.trim(), 'betreff': betreffC.text.trim(), 'notiz': notizC.text.trim()});
          if (ctx.mounted) Navigator.pop(ctx);
          _loaded[typ] = false; setState(() {});
        }, child: const Text('Speichern')),
      ],
    ));
  }

  // ============ HELPERS ============

  Widget _infoRow(IconData icon, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 14, color: Colors.grey.shade600), const SizedBox(width: 8),
      SizedBox(width: 100, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600))),
      Expanded(child: SelectableText(value, style: const TextStyle(fontSize: 11))),
    ]));
  }

  Widget _fieldWithSave(String typ, String bereich, String key, String label, IconData icon) {
    final d = _d(typ, bereich);
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: TextField(
      controller: TextEditingController(text: d[key]?.toString() ?? ''),
      onChanged: (v) { d[key] = v; _saveData(typ); },
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
      style: const TextStyle(fontSize: 13),
    ));
  }

  IconData _statusIcon(String s) {
    switch (s) { case 'bewilligt': return Icons.check_circle; case 'abgelehnt': return Icons.cancel; case 'erledigt': return Icons.done_all; default: return Icons.hourglass_top; }
  }
  Color _statusColor(String s) {
    switch (s) { case 'bewilligt': return Colors.green; case 'abgelehnt': return Colors.red; case 'erledigt': return Colors.grey; case 'in_bearbeitung': return Colors.blue; default: return Colors.orange; }
  }
  String _statusLabel(String s) {
    switch (s) { case 'offen': return 'Offen'; case 'in_bearbeitung': return 'In Bearbeitung'; case 'bewilligt': return 'Bewilligt'; case 'abgelehnt': return 'Abgelehnt'; case 'erledigt': return 'Erledigt'; default: return s; }
  }
}
