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
      Row(children: [
        Icon(Icons.account_balance, size: 20, color: color.shade700), const SizedBox(width: 8),
        Expanded(child: Text('Zuständiges Gericht', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color.shade700))),
        OutlinedButton.icon(
          icon: const Icon(Icons.search, size: 16),
          label: Text(selectedName.isEmpty ? 'Auswählen' : 'Ändern', style: const TextStyle(fontSize: 12)),
          onPressed: () => _showGerichtSelectDialog(typ, d, gerichte, color),
        ),
      ]),
      const SizedBox(height: 12),
      if (selectedName.isEmpty)
        Container(
          width: double.infinity, padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
          child: Column(children: [
            Icon(Icons.search, size: 40, color: Colors.grey.shade400), const SizedBox(height: 8),
            Text('Kein Gericht ausgewählt', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Text('Tippen Sie auf "Auswählen" um das zuständige Gericht zu suchen.', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          ]),
        )
      else ...[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: color.shade300)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(selectedName, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color.shade900)),
            if (selected != null) ...[
              const SizedBox(height: 6),
              _infoRow(Icons.location_on, 'Adresse', selected['adresse'] ?? ''),
              _infoRow(Icons.phone, 'Telefon', selected['telefon'] ?? ''),
              if ((selected['fax'] ?? '').isNotEmpty) _infoRow(Icons.print, 'Fax', selected['fax']!),
              _infoRow(Icons.email, 'E-Mail', selected['email'] ?? ''),
              _infoRow(Icons.access_time, 'Öffnungszeiten', selected['oeffnungszeiten'] ?? ''),
              _infoRow(Icons.info, 'Zuständigkeit', selected['zustaendigkeit'] ?? ''),
            ],
          ]),
        ),
      ],
    ]));
  }

  void _showGerichtSelectDialog(String typ, Map<String, dynamic> d, List<Map<String, String>> gerichte, MaterialColor color) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Row(children: [
        Icon(Icons.search, color: color.shade700), const SizedBox(width: 8),
        const Text('Gericht auswählen'),
      ]),
      content: SizedBox(
        width: 500, height: 400,
        child: ListView(children: gerichte.map((g) => InkWell(
          onTap: () {
            setState(() { d['name'] = g['name']; d['adresse'] = g['adresse']; d['telefon'] = g['telefon']; d['oeffnungszeiten'] = g['oeffnungszeiten']; });
            _saveData(typ);
            Navigator.pop(ctx);
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
            child: Row(children: [
              Icon(Icons.account_balance, size: 20, color: color.shade600), const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g['name']!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color.shade900)),
                Text('${g['adresse']}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                Text(g['zustaendigkeit'] ?? '', style: TextStyle(fontSize: 10, color: color.shade400, fontStyle: FontStyle.italic)),
              ])),
            ]),
          ),
        )).toList()),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen'))],
    ));
  }

  // ============ TAB 2: VORFALL ============

  Widget _buildVorfallTab(String typ, String label, MaterialColor color) {
    final list = _vorfaelle[typ] ?? [];
    final antragTypen = typ == 'betreuungsgericht'
        ? ['Betreuung einrichten', 'Betreuerwechsel', 'Betreuung aufheben', 'Unterbringung', 'Vermögenssorge', 'Sonstiges']
        : typ == 'sozialgericht'
            ? ['Klage gegen Bescheid', 'Einstweiliger Rechtsschutz', 'Widerspruch', 'Berufung', 'Prozesskostenhilfe', 'Sonstiges']
            : ['Kündigungsschutzklage', 'Lohnklage', 'Mahnbescheid (Lohnüberzahlung)', 'Zeugnis einklagen', 'Einstweilige Verfügung', 'Prozesskostenhilfe', 'Sonstiges'];
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
                onTap: () {
                  final vid = int.tryParse(v['id']?.toString() ?? '');
                  if (vid != null) _showVorfallDetailDialog(vid, v, typ, label, color, antragTypen);
                },
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

  void _showVorfallDetailDialog(int vorfallId, Map<String, dynamic> vorfall, String typ, String label, MaterialColor color, List<String> antragTypen) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(width: 620, height: 580, child: _GerichtVorfallDetailView(
          apiService: widget.apiService, userId: widget.user.id,
          vorfallId: vorfallId, vorfall: vorfall, gerichtTyp: typ, color: color, antragTypen: antragTypen,
          onEdit: () { Navigator.pop(ctx); _showVorfallDialog(typ, label, color, antragTypen, existing: vorfall); },
          onChanged: () { _loaded[typ] = false; setState(() {}); },
        )),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// VORFALL DETAIL (Details / Dokumente / Verlauf / Termine / Korrespondenz)
// ═══════════════════════════════════════════════════════
class _GerichtVorfallDetailView extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int vorfallId;
  final Map<String, dynamic> vorfall;
  final String gerichtTyp;
  final MaterialColor color;
  final List<String> antragTypen;
  final VoidCallback onEdit;
  final VoidCallback onChanged;
  const _GerichtVorfallDetailView({required this.apiService, required this.userId, required this.vorfallId, required this.vorfall, required this.gerichtTyp, required this.color, required this.antragTypen, required this.onEdit, required this.onChanged});
  @override
  State<_GerichtVorfallDetailView> createState() => _GerichtVorfallDetailViewState();
}

class _GerichtVorfallDetailViewState extends State<_GerichtVorfallDetailView> {
  List<Map<String, dynamic>> _verlauf = [];
  List<Map<String, dynamic>> _docs = [];
  List<Map<String, dynamic>> _termine = [];
  List<Map<String, dynamic>> _korr = [];
  bool _loaded = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final vR = await widget.apiService.listGerichtVorfallVerlauf(widget.vorfallId);
    final dR = await widget.apiService.listGerichtVorfallDocs(widget.vorfallId);
    final tR = await widget.apiService.listGerichtVorfallTermine(widget.vorfallId);
    final kR = await widget.apiService.listGerichtVorfallKorr(widget.vorfallId);
    if (!mounted) return;
    setState(() {
      if (vR['success'] == true && vR['data'] is List) _verlauf = (vR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (dR['success'] == true && dR['data'] is List) _docs = (dR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (tR['success'] == true && tR['data'] is List) _termine = (tR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (kR['success'] == true && kR['data'] is List) _korr = (kR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vorfall;
    final status = v['status']?.toString() ?? 'offen';
    return DefaultTabController(length: 5, child: Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: widget.color.shade700, borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
        child: Row(children: [
          Icon(Icons.gavel, color: Colors.white, size: 22), const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v['titel']?.toString() ?? '', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            Text('${v['datum'] ?? ''} • ${_sLabel(status)}${(v['aktenzeichen']?.toString() ?? '').isNotEmpty ? ' • Az. ${v['aktenzeichen']}' : ''}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ])),
          IconButton(icon: const Icon(Icons.edit, color: Colors.white, size: 20), tooltip: 'Bearbeiten', onPressed: widget.onEdit),
          IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
        ]),
      ),
      TabBar(labelColor: widget.color.shade700, indicatorColor: widget.color.shade700, isScrollable: true, tabs: const [
        Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Details'),
        Tab(icon: Icon(Icons.folder, size: 18), text: 'Dokumente'),
        Tab(icon: Icon(Icons.timeline, size: 18), text: 'Verlauf'),
        Tab(icon: Icon(Icons.calendar_month, size: 18), text: 'Termine'),
        Tab(icon: Icon(Icons.mail, size: 18), text: 'Korrespondenz'),
      ]),
      Expanded(child: !_loaded ? const Center(child: CircularProgressIndicator()) : TabBarView(children: [
        _buildDetails(v),
        _buildDokumente(),
        _buildVerlauf(),
        _buildTermine(),
        _buildKorrespondenz(),
      ])),
    ]));
  }

  Widget _buildDetails(Map<String, dynamic> v) {
    final status = v['status']?.toString() ?? 'offen';
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dRow(Icons.description, 'Art', v['titel']),
      _dRow(Icons.calendar_today, 'Datum', v['datum']),
      _dRow(Icons.tag, 'Aktenzeichen', v['aktenzeichen']),
      _dRow(Icons.flag, 'Status', _sLabel(status)),
      if ((v['sachbearbeiter']?.toString() ?? '').isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Sachbearbeiter/Richter', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        _dRow(Icons.person, 'Name', v['sachbearbeiter']),
        _dRow(Icons.phone, 'Telefon', v['sachbearbeiter_tel']),
        _dRow(Icons.email, 'E-Mail', v['sachbearbeiter_email']),
      ],
      if ((v['notiz']?.toString() ?? '').isNotEmpty) ...[
        const SizedBox(height: 8),
        Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.yellow.shade50, borderRadius: BorderRadius.circular(8)),
          child: Text(v['notiz'].toString(), style: const TextStyle(fontSize: 12))),
      ],
    ]));
  }

  Widget _dRow(IconData icon, String label, dynamic value) {
    final s = value?.toString() ?? ''; if (s.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
      Icon(icon, size: 14, color: Colors.grey.shade600), const SizedBox(width: 8),
      SizedBox(width: 120, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600))),
      Expanded(child: Text(s, style: const TextStyle(fontSize: 13))),
    ]));
  }

  // ── DOKUMENTE ──
  Widget _buildDokumente() {
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Row(children: [
        Icon(Icons.folder, size: 20, color: widget.color.shade700), const SizedBox(width: 8),
        Expanded(child: Text('Dokumente (${_docs.length})', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: widget.color.shade700))),
        ElevatedButton.icon(onPressed: _uploadDoc, icon: const Icon(Icons.upload_file, size: 16), label: const Text('Hochladen', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(backgroundColor: widget.color, foregroundColor: Colors.white)),
      ])),
      Expanded(child: _docs.isEmpty
        ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.cloud_upload, size: 48, color: Colors.grey.shade300), const SizedBox(height: 8), Text('Keine Dokumente', style: TextStyle(color: Colors.grey.shade500))]))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: _docs.length, itemBuilder: (_, i) {
            final d = _docs[i];
            return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: widget.color.shade200)),
              child: Row(children: [
                Icon(Icons.attach_file, size: 18, color: widget.color.shade700), const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d['datei_name']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: widget.color.shade800)),
                  if ((d['created_at']?.toString() ?? '').isNotEmpty) Text(d['created_at'].toString(), style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                ])),
                IconButton(icon: Icon(Icons.visibility, size: 18, color: Colors.indigo.shade600), tooltip: 'Anzeigen', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: () async {
                  try { final resp = await widget.apiService.downloadGerichtVorfallDoc(d['id'] as int); if (resp.statusCode == 200 && mounted) { final dir = await getTemporaryDirectory(); final file = File('${dir.path}/${d['datei_name']}'); await file.writeAsBytes(resp.bodyBytes); if (mounted) await FileViewerDialog.show(context, file.path, d['datei_name']?.toString() ?? ''); } } catch (_) {}
                }),
                IconButton(icon: Icon(Icons.download, size: 18, color: Colors.green.shade700), tooltip: 'Herunterladen', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: () async {
                  try { final resp = await widget.apiService.downloadGerichtVorfallDoc(d['id'] as int); if (resp.statusCode == 200 && mounted) { final dir = await getTemporaryDirectory(); final file = File('${dir.path}/${d['datei_name']}'); await file.writeAsBytes(resp.bodyBytes); await OpenFilex.open(file.path); } } catch (_) {}
                }),
                IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400), tooltip: 'Löschen', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: () async {
                  await widget.apiService.deleteGerichtVorfallDoc(d['id'] as int); _load();
                }),
              ]),
            );
          })),
    ]);
  }

  Future<void> _uploadDoc() async {
    final result = await FilePickerHelper.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'], allowMultiple: true);
    if (result == null || result.files.isEmpty) return;
    final files = result.files.where((f) => f.path != null).toList();
    if (files.isEmpty) return;
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${files.length} Datei(en) werden hochgeladen...'), duration: const Duration(seconds: 2)));
    for (final file in files) {
      await widget.apiService.uploadGerichtVorfallDoc(vorfallId: widget.vorfallId, filePath: file.path!, fileName: file.name);
    }
    _load();
  }

  // ── VERLAUF ──
  Widget _buildVerlauf() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Expanded(child: Text('${_verlauf.length} Einträge', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
        FilledButton.icon(icon: const Icon(Icons.add, size: 14), label: const Text('Neuer Eintrag', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: widget.color, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: _addVerlauf),
      ])),
      Expanded(child: _verlauf.isEmpty ? Center(child: Text('Kein Verlauf', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _verlauf.length, itemBuilder: (_, i) {
            final e = _verlauf[i];
            return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: widget.color.shade200)),
              child: Row(children: [
                Icon(Icons.circle, size: 10, color: widget.color.shade400), const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Text(e['datum']?.toString() ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                    if ((e['status']?.toString() ?? '').isNotEmpty) ...[const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: widget.color.shade100, borderRadius: BorderRadius.circular(6)), child: Text(_sLabel(e['status'].toString()), style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: widget.color.shade800)))]]),
                  if ((e['notiz']?.toString() ?? '').isNotEmpty) Text(e['notiz'].toString(), style: const TextStyle(fontSize: 12)),
                ])),
                IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), onPressed: () async { await widget.apiService.deleteGerichtVorfallVerlauf(e['id'] as int); _load(); widget.onChanged(); }, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24)),
              ]));
          })),
    ]);
  }

  void _addVerlauf() {
    final datumC = TextEditingController(text: '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}');
    final notizC = TextEditingController(); String status = '';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (_, setD) => AlertDialog(title: const Text('Verlauf-Eintrag'),
      content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: datumC, decoration: const InputDecoration(labelText: 'Datum', isDense: true, border: OutlineInputBorder())), const SizedBox(height: 8),
        Wrap(spacing: 6, children: ['offen', 'in_bearbeitung', 'bewilligt', 'abgelehnt', 'erledigt'].map((s) => ChoiceChip(label: Text(_sLabel(s), style: TextStyle(fontSize: 10, color: status == s ? Colors.white : Colors.black87)), selected: status == s, selectedColor: widget.color, onSelected: (_) => setD(() => status = s))).toList()), const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 3, decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder())),
      ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          await widget.apiService.addGerichtVorfallVerlauf(widget.vorfallId, {'datum': datumC.text, 'status': status, 'notiz': notizC.text});
          if (status.isNotEmpty) await widget.apiService.saveGerichtVorfall(widget.userId, widget.gerichtTyp, {'id': widget.vorfallId, 'status': status});
          if (ctx.mounted) Navigator.pop(ctx); _load(); widget.onChanged();
        }, child: const Text('Hinzufügen'))],
    )));
  }

  // ── TERMINE ──
  Widget _buildTermine() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Expanded(child: Text('${_termine.length} Termine', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
        FilledButton.icon(icon: const Icon(Icons.add, size: 14), label: const Text('Neuer Termin', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: widget.color, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: _addTermin),
      ])),
      Expanded(child: _termine.isEmpty ? Center(child: Text('Keine Termine', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _termine.length, itemBuilder: (_, i) {
            final t = _termine[i];
            return Card(child: ListTile(
              leading: Icon(Icons.event, color: widget.color.shade700),
              title: Text('${t['datum'] ?? ''}${(t['uhrzeit']?.toString() ?? '').isNotEmpty ? ' um ${t['uhrzeit']}' : ''}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if ((t['ort']?.toString() ?? '').isNotEmpty) Text(t['ort'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                if ((t['notiz']?.toString() ?? '').isNotEmpty) Text(t['notiz'].toString(), style: const TextStyle(fontSize: 11)),
              ]),
              trailing: IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), onPressed: () async { await widget.apiService.deleteGerichtVorfallTermin(t['id'] as int); _load(); }),
            ));
          })),
    ]);
  }

  void _addTermin() {
    final datumC = TextEditingController(); final uhrzeitC = TextEditingController(); final ortC = TextEditingController(); final notizC = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('Neuer Termin'),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          onTap: () async { final p = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de')); if (p != null) datumC.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}'; }),
        const SizedBox(height: 8),
        TextField(controller: uhrzeitC, decoration: InputDecoration(labelText: 'Uhrzeit', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 8),
        TextField(controller: ortC, decoration: InputDecoration(labelText: 'Ort / Saal', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 3, decoration: InputDecoration(labelText: 'Notizen', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          if (datumC.text.isEmpty) return;
          await widget.apiService.saveGerichtVorfallTermin(widget.vorfallId, widget.gerichtTyp, {'datum': datumC.text, 'uhrzeit': uhrzeitC.text, 'ort': ortC.text, 'notiz': notizC.text, 'user_id': widget.userId});
          if (ctx.mounted) Navigator.pop(ctx); _load();
        }, child: const Text('Speichern'))],
    ));
  }

  // ── KORRESPONDENZ ──
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
                ])),
                IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), onPressed: () async { await widget.apiService.deleteGerichtVorfallKorr(k['id'] as int); _load(); }, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28)),
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
          await widget.apiService.saveGerichtVorfallKorr(widget.vorfallId, widget.gerichtTyp, {'richtung': richtung, 'datum': datumC.text.trim(), 'betreff': betreffC.text.trim(), 'notiz': notizC.text.trim(), 'user_id': widget.userId});
          if (ctx.mounted) Navigator.pop(ctx); _load();
        }, child: const Text('Speichern'))],
    ));
  }

  String _sLabel(String s) {
    switch (s) { case 'offen': return 'Offen'; case 'in_bearbeitung': return 'In Bearbeitung'; case 'bewilligt': return 'Bewilligt'; case 'abgelehnt': return 'Abgelehnt'; case 'erledigt': return 'Erledigt'; default: return s; }
  }
}
