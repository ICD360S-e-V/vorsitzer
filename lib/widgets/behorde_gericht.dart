import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';
import 'file_viewer_dialog.dart';
import 'korrespondenz_attachments_widget.dart';

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
  @override
  void initState() { super.initState(); _loadArbeitgeberName(); }

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
    ('insolvenzgericht', 'Insolvenzgericht', Icons.account_balance_wallet, Colors.red),
    ('strafverfahren', 'Strafverfahren', Icons.shield, Colors.brown),
    ('beratungshilfe', 'Beratungshilfe', Icons.gavel, Colors.indigo),
  ];

  // Gerichte Datenbank — loaded from server
  final Map<String, List<Map<String, dynamic>>> _gerichtDB = {};

  Future<void> _loadAll(String typ) async {
    if (_loaded[typ] == true) return;
    final uid = widget.user.id;
    final results = await Future.wait([
      widget.apiService.getGerichtData(uid, typ),
      widget.apiService.listGerichtVorfaelle(uid, typ),
      widget.apiService.listGerichtTermineDB(uid, typ),
      widget.apiService.listGerichtKorrespondenzDB(uid, typ),
      widget.apiService.getGerichtDatenbank(typ),
    ]);
    if (!mounted) return;
    final dR = results[0];
    final vR = results[1];
    final tR = results[2];
    final kR = results[3];
    final dbR = results[4];
    setState(() {
      if (dR['success'] == true && dR['data'] is Map) {
        _gerichtData[typ] = {};
        (dR['data'] as Map).forEach((k, v) { if (v is Map) _gerichtData[typ]![k.toString()] = Map<String, dynamic>.from(v); });
      }
      if (vR['success'] == true && vR['data'] is List) _vorfaelle[typ] = (vR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (tR['success'] == true && tR['data'] is List) _termine[typ] = (tR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (kR['success'] == true && kR['data'] is List) _korrespondenz[typ] = (kR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (dbR['success'] == true && dbR['gerichte'] is List) _gerichtDB[typ] = List<Map<String, dynamic>>.from(dbR['gerichte']);
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
      length: _gerichtTypen.length,
      child: Column(children: [
        TabBar(
          labelColor: Colors.indigo.shade700,
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: Colors.indigo.shade700,
          isScrollable: true, tabAlignment: TabAlignment.start,
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
      length: 2,
      child: Column(children: [
        TabBar(
          labelColor: color.shade700, unselectedLabelColor: Colors.grey.shade600, indicatorColor: color.shade700,
          tabs: [
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: (_d(typ, 'gericht')['name']?.toString() ?? '').isNotEmpty ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.account_balance, size: 14), const SizedBox(width: 4), const Text('Zuständiges Gericht')])),
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: (_vorfaelle[typ]?.isNotEmpty == true) ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.report_problem, size: 14), const SizedBox(width: 4), const Text('Vorfall')])),
          ],
        ),
        Expanded(child: TabBarView(children: [
          _buildGerichtTab(typ, color),
          _buildVorfallTab(typ, label, color),
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

  void _showGerichtSelectDialog(String typ, Map<String, dynamic> d, List<Map<String, dynamic>> gerichte, MaterialColor color) {
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
            : typ == 'insolvenzgericht'
                ? ['Verbraucherinsolvenz (Privatinsolvenz)', 'Außergerichtlicher Einigungsversuch', 'Schuldenbereinigungsplan', 'Restschuldbefreiung', 'Prozesskostenhilfe', 'Sonstiges']
                : typ == 'strafverfahren'
                    ? ['Vorermittlungsverfahren', 'Ermittlungsverfahren', 'Einstellung (§170 Abs. 2 StPO)', 'Strafbefehl', 'Hauptverhandlung', 'Berufung/Revision', 'Verkehrsunfall', 'Körperverletzung', 'Diebstahl', 'Betrug', 'Ordnungswidrigkeit', 'Sonstiges']
                    : typ == 'beratungshilfe'
                        ? ['Beratungshilfeschein beantragen', 'Mietrecht', 'Arbeitsrecht', 'Familienrecht', 'Sozialrecht', 'Verbraucherrecht', 'Ausländerrecht', 'Strafrecht (Verteidigung)', 'Erbrecht', 'Schulden / Inkasso', 'Sonstiges']
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
          initialValue: antragTypen.contains(titelC.text) ? titelC.text : null,
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
          for (final s in [
            ('offen', 'Offen', Colors.orange),
            ('in_bearbeitung', 'In Bearbeitung', Colors.blue),
            if (typ == 'strafverfahren') ...[
              ('eingestellt', 'Eingestellt (§170 II)', Colors.teal),
              ('anklage', 'Anklage erhoben', Colors.deepOrange),
              ('freispruch', 'Freispruch', Colors.green),
              ('verurteilt', 'Verurteilt', Colors.red),
              ('strafbefehl', 'Strafbefehl', Colors.purple),
            ] else ...[
              ('bewilligt', 'Bewilligt', Colors.green),
              ('abgelehnt', 'Abgelehnt', Colors.red),
            ],
            ('erledigt', 'Erledigt', Colors.grey),
          ])
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

  // ============ HELPERS ============

  Widget _infoRow(IconData icon, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 14, color: Colors.grey.shade600), const SizedBox(width: 8),
      SizedBox(width: 100, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600))),
      Expanded(child: SelectableText(value, style: const TextStyle(fontSize: 11))),
    ]));
  }

  IconData _statusIcon(String s) {
    switch (s) { case 'bewilligt': case 'freispruch': return Icons.check_circle; case 'abgelehnt': case 'verurteilt': return Icons.cancel; case 'eingestellt': return Icons.block; case 'anklage': return Icons.gavel; case 'strafbefehl': return Icons.description; case 'erledigt': return Icons.done_all; default: return Icons.hourglass_top; }
  }
  Color _statusColor(String s) {
    switch (s) { case 'bewilligt': case 'freispruch': return Colors.green; case 'abgelehnt': case 'verurteilt': return Colors.red; case 'eingestellt': return Colors.teal; case 'anklage': return Colors.deepOrange; case 'strafbefehl': return Colors.purple; case 'erledigt': return Colors.grey; case 'in_bearbeitung': return Colors.blue; default: return Colors.orange; }
  }
  String _statusLabel(String s) {
    switch (s) { case 'offen': return 'Offen'; case 'in_bearbeitung': return 'In Bearbeitung'; case 'bewilligt': return 'Bewilligt'; case 'abgelehnt': return 'Abgelehnt'; case 'eingestellt': return 'Eingestellt'; case 'anklage': return 'Anklage'; case 'freispruch': return 'Freispruch'; case 'verurteilt': return 'Verurteilt'; case 'strafbefehl': return 'Strafbefehl'; case 'erledigt': return 'Erledigt'; default: return s; }
  }

  String _arbeitgeberName = '';

  Future<void> _loadArbeitgeberName() async {
    try {
      final res = await widget.apiService.getBerufserfahrung(widget.user.id);
      if (res['success'] == true && res['data'] is List) {
        final list = res['data'] as List;
        // Find aktuelle Arbeitgeber (aktuell=1)
        final aktuelle = list.where((a) => a['aktuell'] == 1 || a['aktuell'] == true || a['aktuell'] == '1').toList();
        if (aktuelle.isNotEmpty) {
          _arbeitgeberName = aktuelle.first['firma']?.toString() ?? '';
        } else if (list.isNotEmpty) {
          _arbeitgeberName = list.first['firma']?.toString() ?? '';
        }
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  String _getArbeitgeberName() => _arbeitgeberName;

  void _showVorfallDetailDialog(int vorfallId, Map<String, dynamic> vorfall, String typ, String label, MaterialColor color, List<String> antragTypen) {
    final size = MediaQuery.of(context).size;
    final dialogWidth = (size.width * 0.92).clamp(700.0, 1200.0);
    final dialogHeight = (size.height * 0.92).clamp(600.0, 1000.0);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(width: dialogWidth, height: dialogHeight, child: _GerichtVorfallDetailView(
          apiService: widget.apiService, userId: widget.user.id,
          vorfallId: vorfallId, vorfall: vorfall, gerichtTyp: typ, color: color, antragTypen: antragTypen,
          onEdit: () { Navigator.pop(ctx); _showVorfallDialog(typ, label, color, antragTypen, existing: vorfall); },
          onChanged: () { _loaded[typ] = false; setState(() {}); },
          userName: widget.user.vorname ?? '', userNachname: widget.user.nachname ?? widget.user.name,
          arbeitgeberName: _getArbeitgeberName(),
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
  final String userName;
  final String userNachname;
  final String arbeitgeberName;
  const _GerichtVorfallDetailView({required this.apiService, required this.userId, required this.vorfallId, required this.vorfall, required this.gerichtTyp, required this.color, required this.antragTypen, required this.onEdit, required this.onChanged, this.userName = '', this.userNachname = '', this.arbeitgeberName = ''});
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
    final isBetreuung = widget.gerichtTyp == 'betreuungsgericht';
    final isBeratungshilfe = widget.gerichtTyp == 'beratungshilfe';
    final tabCount = (isBetreuung || isBeratungshilfe) ? 8 : 7;
    return DefaultTabController(length: tabCount, child: Column(children: [
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
      TabBar(labelColor: widget.color.shade700, indicatorColor: widget.color.shade700, isScrollable: true, tabs: [
        const Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Details'),
        if (isBetreuung) const Tab(icon: Icon(Icons.assignment, size: 18), text: 'Antrag Generator'),
        if (isBeratungshilfe) const Tab(icon: Icon(Icons.picture_as_pdf, size: 18), text: 'PDF-Generator'),
        const Tab(icon: Icon(Icons.folder, size: 18), text: 'Dokumente'),
        const Tab(icon: Icon(Icons.timeline, size: 18), text: 'Verlauf'),
        const Tab(icon: Icon(Icons.calendar_month, size: 18), text: 'Termine'),
        const Tab(icon: Icon(Icons.mail, size: 18), text: 'Korrespondenz'),
        const Tab(icon: Icon(Icons.gavel, size: 18), text: 'Widerspruch'),
        const Tab(icon: Icon(Icons.balance, size: 18), text: 'Klage'),
      ]),
      Expanded(child: !_loaded ? const Center(child: CircularProgressIndicator()) : TabBarView(children: [
        _buildDetails(v),
        if (isBetreuung) _AnregungBetreuerTab(
          apiService: widget.apiService,
          vorfallId: widget.vorfallId,
          userId: widget.userId,
          color: widget.color,
        ),
        if (isBeratungshilfe) _BeratungshilfeGeneratorTab(
          apiService: widget.apiService,
          userId: widget.userId,
          vorfallId: widget.vorfallId,
          vorfall: v,
          userName: widget.userName,
          userNachname: widget.userNachname,
          color: widget.color,
        ),
        _buildDokumente(),
        _buildVerlaufUnified(v),
        _buildTermine(),
        _buildKorrespondenz(),
        _buildWiderspruch(v),
        _buildKlageTab(v),
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

  // ── DOKUMENTE (kategorisiert) ──
  Widget _buildDokumente() {
    final antragDocs   = _docs.where((d) => (d['kategorie']?.toString() ?? 'sonstiges') == 'antrag').toList();
    final sonstigeDocs = _docs.where((d) => (d['kategorie']?.toString() ?? 'sonstiges') == 'sonstiges').toList();
    return SingleChildScrollView(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _buildDokSection('Antrag', Icons.assignment, antragDocs, 'antrag',
        hint: 'Generierter Anregung-Antrag, Anlagen zum Antrag (Vollmachten, ärztliche Stellungnahme, Kopien)'),
      _buildDokSection('Sonstiges', Icons.folder, sonstigeDocs, 'sonstiges',
        hint: 'Alle anderen Dokumente ohne feste Kategorie'),
    ]));
  }

  Widget _buildDokSection(String title, IconData icon, List<Map<String, dynamic>> docs, String kategorie, {String? hint}) {
    return Container(margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: widget.color.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(color: widget.color.shade50, borderRadius: const BorderRadius.vertical(top: Radius.circular(10))),
          child: Row(children: [
            Icon(icon, size: 18, color: widget.color.shade700),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$title (${docs.length})', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: widget.color.shade800)),
              if (hint != null) Text(hint, style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
            ])),
            ElevatedButton.icon(
              onPressed: () => _uploadDoc(kategorie),
              icon: const Icon(Icons.upload_file, size: 14),
              label: const Text('Hochladen', style: TextStyle(fontSize: 11)),
              style: ElevatedButton.styleFrom(backgroundColor: widget.color, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
            ),
          ])),
        if (docs.isEmpty) Padding(padding: const EdgeInsets.all(16),
          child: Row(children: [
            Icon(Icons.inbox, size: 18, color: Colors.grey.shade400),
            const SizedBox(width: 8),
            Text('Keine Dokumente', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          ])),
        ...docs.map((d) => Padding(padding: const EdgeInsets.fromLTRB(12, 4, 8, 4), child: Row(children: [
          Icon(Icons.attach_file, size: 16, color: widget.color.shade700), const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d['datei_name']?.toString() ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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
        ]))),
        const SizedBox(height: 6),
      ]),
    );
  }

  Future<void> _uploadDoc(String kategorie) async {
    final result = await FilePickerHelper.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'], allowMultiple: true);
    if (result == null || result.files.isEmpty) return;
    final files = result.files.where((f) => f.path != null).toList();
    if (files.isEmpty) return;
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${files.length} Datei(en) werden hochgeladen...'), duration: const Duration(seconds: 2)));
    for (final file in files) {
      await widget.apiService.uploadGerichtVorfallDoc(vorfallId: widget.vorfallId, filePath: file.path!, fileName: file.name, kategorie: kategorie);
    }
    _load();
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
  String _methodeLabel(String m) {
    switch (m) {
      case 'email': return 'E-Mail';
      case 'post': return 'Post';
      case 'online': return 'Online';
      case 'persoenlich': return 'Persönlich';
      case 'fax': return 'Fax';
      case 'telefon': return 'Telefon';
      default: return m.isEmpty ? '' : m;
    }
  }

  IconData _methodeIcon(String m) {
    switch (m) {
      case 'email': return Icons.email;
      case 'post': return Icons.mail;
      case 'online': return Icons.language;
      case 'persoenlich': return Icons.person;
      case 'fax': return Icons.fax;
      case 'telefon': return Icons.phone;
      default: return Icons.help_outline;
    }
  }

  MaterialColor _methodeColor(String m) {
    switch (m) {
      case 'email': return Colors.cyan;
      case 'post': return Colors.brown;
      case 'online': return Colors.deepPurple;
      case 'persoenlich': return Colors.amber;
      case 'fax': return Colors.grey;
      case 'telefon': return Colors.teal;
      default: return Colors.blueGrey;
    }
  }

  Widget _methodeBadge(String methode) {
    if (methode.isEmpty) return const SizedBox.shrink();
    final c = _methodeColor(methode);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: c.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.shade300, width: 1)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(_methodeIcon(methode), size: 11, color: c.shade700),
        const SizedBox(width: 3),
        Text(_methodeLabel(methode), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c.shade800)),
      ]),
    );
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
            final methode = k['methode']?.toString() ?? '';
            return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: isEin ? Colors.green.shade200 : Colors.blue.shade200)),
              child: Row(children: [
                Icon(isEin ? Icons.call_received : Icons.call_made, size: 18, color: isEin ? Colors.green.shade700 : Colors.blue.shade700), const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Text(k['betreff']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isEin ? Colors.green.shade800 : Colors.blue.shade800))),
                    if (methode.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 4), child: _methodeBadge(methode)),
                  ]),
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(Icons.calendar_today, size: 11, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Text(k['datum']?.toString() ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  ]),
                  if ((k['notiz']?.toString() ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4),
                    child: Text(k['notiz'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade700))),
                  if (k['id'] != null) Padding(padding: const EdgeInsets.only(top: 4),
                    child: KorrAttachmentsWidget(apiService: widget.apiService, modul: 'gericht_vorfall', korrespondenzId: k['id'] as int)),
                ])),
                IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), onPressed: () async { await widget.apiService.deleteGerichtVorfallKorr(k['id'] as int); _load(); }, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28)),
              ]));
          })),
    ]);
  }

  void _addKorr(String richtung) {
    final betreffC = TextEditingController();
    final datumC = TextEditingController();
    final notizC = TextEditingController();
    String methode = richtung == 'eingang' ? 'post' : 'email';
    List<PlatformFile> files = [];
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) => AlertDialog(
      title: Row(children: [
        Icon(richtung == 'eingang' ? Icons.call_received : Icons.call_made, size: 18, color: richtung == 'eingang' ? Colors.green.shade700 : Colors.blue.shade700),
        const SizedBox(width: 8),
        Text(richtung == 'eingang' ? 'Eingang' : 'Ausgang', style: const TextStyle(fontSize: 14)),
      ]),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final m in [('email', 'E-Mail', Icons.email), ('post', 'Post', Icons.mail), ('online', 'Online', Icons.language), ('persoenlich', 'Persönlich', Icons.person), ('fax', 'Fax', Icons.fax), ('telefon', 'Telefon', Icons.phone)])
            ChoiceChip(label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(m.$3, size: 13, color: methode == m.$1 ? Colors.white : Colors.grey.shade700), const SizedBox(width: 4), Text(m.$2, style: TextStyle(fontSize: 10, color: methode == m.$1 ? Colors.white : Colors.grey.shade700))]),
              selected: methode == m.$1, selectedColor: Colors.indigo.shade600, onSelected: (_) => setDlg(() => methode = m.$1)),
        ]),
        const SizedBox(height: 12),
        TextFormField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', prefixIcon: const Icon(Icons.calendar_today, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async {
            final p = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de'));
            if (p != null) setDlg(() => datumC.text = '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}');
          }))),
        const SizedBox(height: 8),
        TextField(controller: betreffC, decoration: InputDecoration(labelText: 'Betreff *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
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
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          if (betreffC.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Betreff angeben'), backgroundColor: Colors.orange)); return; }
          final res = await widget.apiService.saveGerichtVorfallKorr(widget.vorfallId, widget.gerichtTyp, {'richtung': richtung, 'methode': methode, 'datum': datumC.text.trim(), 'betreff': betreffC.text.trim(), 'notiz': notizC.text.trim(), 'user_id': widget.userId});
          final korrId = res['id'];
          if (korrId != null && files.isNotEmpty) {
            for (final f in files) {
              if (f.path == null) continue;
              await widget.apiService.uploadKorrAttachment(modul: 'gericht_vorfall', korrespondenzId: korrId is int ? korrId : int.parse(korrId.toString()), filePath: f.path!, fileName: f.name);
            }
          }
          if (ctx.mounted) Navigator.pop(ctx); _load();
        }, child: const Text('Speichern')),
      ],
    )));
  }

  // ── WIDERSPRUCH ──

  DateTime? _parseDate(dynamic v) {
    final s = v?.toString().trim() ?? '';
    if (s.isEmpty || s == 'null') return null;
    // Try ISO 8601 first (YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS)
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;
    // Try German DD.MM.YYYY (and DD.MM.YYYY HH:MM)
    final m = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})(?:\s+(\d{1,2}):(\d{2}))?$').firstMatch(s);
    if (m != null) {
      try {
        return DateTime(
          int.parse(m.group(3)!),
          int.parse(m.group(2)!),
          int.parse(m.group(1)!),
          m.group(4) != null ? int.parse(m.group(4)!) : 0,
          m.group(5) != null ? int.parse(m.group(5)!) : 0,
        );
      } catch (_) { return null; }
    }
    return null;
  }

  DateTime _addDays(DateTime d, int days) {
    var result = d.add(Duration(days: days));
    while (result.weekday == DateTime.saturday || result.weekday == DateTime.sunday) {
      result = result.add(const Duration(days: 1));
    }
    return result;
  }

  DateTime _addMonth(DateTime d, int months) {
    var y = d.year; var m = d.month + months;
    while (m > 12) { y++; m -= 12; }
    var day = d.day;
    final maxDay = DateTime(y, m + 1, 0).day;
    if (day > maxDay) day = maxDay;
    var result = DateTime(y, m, day);
    while (result.weekday == DateTime.saturday || result.weekday == DateTime.sunday) {
      result = result.add(const Duration(days: 1));
    }
    return result;
  }

  // Fristen nach Gerichtstyp und Vorfallart
  ({int tage, String beschreibung, String paragraph}) _getFrist(String gerichtTyp, String titel) {
    final t = titel.toLowerCase();
    if (gerichtTyp == 'arbeitsgericht') {
      if (t.contains('mahnbescheid')) return (tage: 7, beschreibung: '1 Woche ab Zustellung des Mahnbescheids', paragraph: '§ 46a ArbGG i.V.m. § 692 ZPO');
      if (t.contains('kündigung')) return (tage: 21, beschreibung: '3 Wochen ab Zugang der Kündigung', paragraph: '§ 4 KSchG');
      return (tage: 14, beschreibung: '2 Wochen ab Zustellung', paragraph: '§ 59 ArbGG');
    }
    if (gerichtTyp == 'sozialgericht') {
      if (t.contains('einstweilig')) return (tage: 14, beschreibung: '2 Wochen (Eilverfahren)', paragraph: '§ 86b SGG');
      return (tage: 30, beschreibung: '1 Monat ab Bekanntgabe des Bescheids', paragraph: '§ 84 SGG');
    }
    if (gerichtTyp == 'betreuungsgericht') {
      if (t.contains('einstweilig') || t.contains('unterbringung')) return (tage: 14, beschreibung: '2 Wochen ab Bekanntgabe', paragraph: '§ 63 FamFG');
      return (tage: 30, beschreibung: '1 Monat ab schriftlicher Bekanntgabe', paragraph: '§ 63 Abs. 1 FamFG');
    }
    return (tage: 30, beschreibung: '1 Monat (Standard)', paragraph: '');
  }

  Widget _buildWiderspruch(Map<String, dynamic> v) {
    final bescheidDatum = _parseDate(v['datum']);
    final titel = v['titel']?.toString() ?? '';
    final status = v['status']?.toString() ?? '';

    if (bescheidDatum == null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.warning, size: 48, color: Colors.orange.shade300), const SizedBox(height: 8),
        Text('Kein Datum vorhanden', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
        Text('Bitte Datum im Vorfall eintragen.', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      ])));
    }

    final frist = _getFrist(widget.gerichtTyp, titel);
    final fristEnde = frist.tage <= 21 ? _addDays(bescheidDatum, frist.tage) : _addMonth(bescheidDatum, 1);
    final heute = DateTime.now();
    final heute0 = DateTime(heute.year, heute.month, heute.day);
    final restTage = fristEnde.difference(heute0).inDays;
    final abgelaufen = heute0.isAfter(fristEnde);
    final letzteWoche = !abgelaufen && restTage <= 7;

    // Check if Widerspruch was filed (from Verlauf entries)
    final widerspruchEntry = _verlauf.where((e) => (e['notiz']?.toString() ?? '').contains('Widerspruch eingelegt')).firstOrNull;
    final hatWiderspruch = widerspruchEntry != null || status == 'in_bearbeitung' || status == 'bewilligt' || status == 'abgelehnt' || status == 'erledigt';
    final widerspruchDatum = widerspruchEntry != null ? _parseDate(widerspruchEntry['datum']) : null;

    String fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

    final statusColor = hatWiderspruch
        ? (status == 'bewilligt' ? Colors.green : status == 'abgelehnt' ? Colors.red : status == 'erledigt' ? Colors.grey : Colors.blue)
        : abgelaufen ? Colors.red : letzteWoche ? Colors.orange : Colors.green;

    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Status Banner
      Container(
        width: double.infinity, padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: statusColor.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: statusColor.shade300, width: 2)),
        child: Row(children: [
          Icon(hatWiderspruch ? Icons.gavel : abgelaufen ? Icons.cancel : Icons.timer, size: 28, color: statusColor.shade700),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(hatWiderspruch
                ? 'Widerspruch eingelegt${widerspruchDatum != null ? ' am ${fmt(widerspruchDatum)}' : ''}'
                : abgelaufen ? 'Frist abgelaufen seit ${-restTage} Tagen' : '$restTage Tage verbleibend',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: statusColor.shade800)),
            if (hatWiderspruch) Text('Status: ${_sLabel(status)}', style: TextStyle(fontSize: 12, color: statusColor.shade700))
            else if (!abgelaufen) Text('Fristende: ${fmt(fristEnde)}', style: TextStyle(fontSize: 12, color: statusColor.shade700)),
          ])),
        ]),
      ),
      const SizedBox(height: 16),

      // Unified chronological timeline
      Text('Chronologie', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
      const SizedBox(height: 12),
      ...() {
        // Build unified list with dates for sorting
        final List<(DateTime, Widget)> items = [];
        // Bescheid
        items.add((bescheidDatum, _tlItem(Icons.description, 'Bescheid / Zustellung', fmt(bescheidDatum), Colors.indigo, true)));
        // Fristende
        items.add((fristEnde, _tlItem(abgelaufen && !hatWiderspruch ? Icons.cancel : Icons.timer, 'Fristende (${frist.tage} Tage)', fmt(fristEnde), abgelaufen && !hatWiderspruch ? Colors.red : Colors.grey, true, subtitle: '${frist.beschreibung} — ${frist.paragraph}')));
        // Widerspruch
        if (hatWiderspruch && widerspruchDatum != null) {
          items.add((widerspruchDatum, _tlItem(Icons.gavel, 'Widerspruch eingelegt', fmt(widerspruchDatum), Colors.blue, true, subtitle: widerspruchEntry?['notiz']?.toString())));
        }
        // Widerspruch Entscheidung (Status + Datum)
        final entscheidungDatum = _parseDate(v['widerspruch_entscheidung_datum']);
        final istAbgeschlossen2 = status == 'bewilligt' || status == 'abgelehnt' || status == 'erledigt' || status == 'teilweise_bewilligt';
        if (istAbgeschlossen2) {
          final stLabel2 = {'bewilligt': 'Bewilligt / Akzeptiert', 'teilweise_bewilligt': 'Teilweise bewilligt', 'abgelehnt': 'Abgelehnt', 'erledigt': 'Erledigt'}[status] ?? status;
          final stColor2 = {'bewilligt': Colors.green, 'teilweise_bewilligt': Colors.teal, 'abgelehnt': Colors.red, 'erledigt': Colors.grey}[status] ?? Colors.grey;
          final eDatum = entscheidungDatum ?? heute0;
          items.add((eDatum, _tlItem(Icons.verified, 'Widerspruch: $stLabel2', entscheidungDatum != null ? fmt(entscheidungDatum) : 'Datum ausstehend', stColor2, true)));
        }
        // Heute
        if (!abgelaufen && !hatWiderspruch) {
          items.add((heute0, _tlItem(Icons.today, 'Heute', fmt(heute0), Colors.blue, false, subtitle: '$restTage Tage verbleibend')));
        }
        // All Verlauf entries
        for (final e in _verlauf) {
          final notiz = e['notiz']?.toString() ?? '';
          if (notiz.contains('Widerspruch eingelegt')) continue;
          final eDatum = _parseDate(e['datum']) ?? heute0;
          items.add((eDatum, _tlItem(Icons.circle, '${_sLabel(e['status']?.toString() ?? '')}${notiz.isNotEmpty ? ': $notiz' : ''}', fmt(eDatum), widget.color, true)));
        }
        // Sort by date
        items.sort((a, b) => a.$1.compareTo(b.$1));
        return items.map((e) => e.$2);
      }(),
      // Status ändern
      const SizedBox(height: 16),
      () {
        final istAbgeschlossen = status == 'bewilligt' || status == 'abgelehnt' || status == 'erledigt' || status == 'teilweise_bewilligt';
        if (istAbgeschlossen) {
          final stLabel = {'bewilligt': 'Bewilligt / Akzeptiert', 'teilweise_bewilligt': 'Teilweise bewilligt', 'abgelehnt': 'Abgelehnt', 'erledigt': 'Erledigt'}[status] ?? status;
          final stColor = {'bewilligt': Colors.green, 'teilweise_bewilligt': Colors.teal, 'abgelehnt': Colors.red, 'erledigt': Colors.grey}[status] ?? Colors.grey;
          return Container(width: double.infinity, padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: stColor.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: stColor.shade300, width: 2)),
            child: Row(children: [
              Icon(Icons.lock, size: 20, color: stColor.shade700),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Widerspruch abgeschlossen', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: stColor.shade800)),
                Text('Status: $stLabel', style: TextStyle(fontSize: 12, color: stColor.shade700)),
                if (status == 'bewilligt') Text('→ Weiter zum Tab „Klage"', style: TextStyle(fontSize: 11, color: Colors.blue.shade700, fontStyle: FontStyle.italic)),
              ])),
            ]));
        }
        return Container(width: double.infinity, padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.purple.shade200)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Widerspruch-Status', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.purple.shade800)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final s in [('offen', 'Offen', Colors.orange), ('in_bearbeitung', 'In Bearbeitung', Colors.blue), ('bewilligt', 'Bewilligt / Akzeptiert', Colors.green), ('teilweise_bewilligt', 'Teilweise bewilligt', Colors.teal), ('abgelehnt', 'Abgelehnt', Colors.red), ('erledigt', 'Erledigt', Colors.grey)])
                ChoiceChip(
                  label: Text(s.$2, style: TextStyle(fontSize: 11, color: status == s.$1 ? Colors.white : s.$3.shade800)),
                  selected: status == s.$1,
                  selectedColor: s.$3.shade600,
                  onSelected: (_) async {
                    final isFinal = s.$1 == 'bewilligt' || s.$1 == 'abgelehnt' || s.$1 == 'erledigt' || s.$1 == 'teilweise_bewilligt';
                    String? datumStr;
                    if (isFinal && context.mounted) {
                      final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de'));
                      if (d != null) datumStr = '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
                      if (datumStr == null) return;
                    }
                    await widget.apiService.saveGerichtVorfall(widget.userId, widget.gerichtTyp, {...widget.vorfall, 'id': widget.vorfallId, 'status': s.$1, if (datumStr != null) 'widerspruch_entscheidung_datum': datumStr});
                    _load();
                    widget.onChanged();
                  },
                ),
            ]),
          ]),
        );
      }(),
      if (hatWiderspruch) ...[
        const SizedBox(height: 12),
        Container(
          width: double.infinity, padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blue.shade200)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(Icons.timer, size: 20, color: Colors.blue.shade700), const SizedBox(width: 8),
              Text('Erwartete Wartezeit', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue.shade800))]),
            const SizedBox(height: 6),
            Text(_getWartezeit(widget.gerichtTyp, titel), style: TextStyle(fontSize: 12, color: Colors.blue.shade900)),
          ]),
        ),
        if (widget.gerichtTyp == 'sozialgericht') ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity, padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade200)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.lightbulb, size: 16, color: Colors.amber.shade700), const SizedBox(width: 8),
              Expanded(child: Text('Nach 3 Monaten ohne Antwort: Untätigkeitsklage nach § 88 SGG möglich.', style: TextStyle(fontSize: 11, color: Colors.amber.shade900))),
            ]),
          ),
        ],
      ],
      const SizedBox(height: 16),

      // Rechtsgrundlage
      Container(
        width: double.infinity, padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Rechtsgrundlage', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
          const SizedBox(height: 6),
          if (widget.gerichtTyp == 'arbeitsgericht') ...[
            _lawRow('§ 46a ArbGG', 'Mahnbescheid: 1 Woche Widerspruchsfrist'),
            _lawRow('§ 4 KSchG', 'Kündigungsschutzklage: 3 Wochen ab Zugang'),
            _lawRow('§ 59 ArbGG', 'Allgemeine Rechtsmittelfrist: 2 Wochen'),
          ],
          if (widget.gerichtTyp == 'sozialgericht') ...[
            _lawRow('§ 84 SGG', 'Widerspruchsfrist: 1 Monat nach Bekanntgabe'),
            _lawRow('§ 87 SGG', 'Klagefrist: 1 Monat nach Widerspruchsbescheid'),
            _lawRow('§ 88 SGG', 'Untätigkeitsklage nach 3 Monaten'),
          ],
          if (widget.gerichtTyp == 'betreuungsgericht') ...[
            _lawRow('§ 63 FamFG', 'Beschwerde: 1 Monat ab Bekanntgabe'),
            _lawRow('§ 63 FamFG', 'Einstweilig/Unterbringung: 2 Wochen'),
          ],
        ]),
      ),

      if (!hatWiderspruch && !abgelaufen) ...[
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: ElevatedButton.icon(
          icon: const Icon(Icons.gavel),
          label: const Text('Widerspruch / Rechtsmittel einlegen'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: () => _showWiderspruchWizard(v, frist),
        )),
      ],
    ]));
  }

  String _getWartezeit(String gerichtTyp, String titel) {
    final t = titel.toLowerCase();
    if (gerichtTyp == 'arbeitsgericht') {
      if (t.contains('mahnbescheid')) return 'Nach Widerspruch: Verfahren wird an Arbeitsgericht abgegeben. Güteverhandlung i.d.R. innerhalb 2–6 Wochen.';
      if (t.contains('kündigung')) return 'Güteverhandlung i.d.R. innerhalb 2–4 Wochen nach Klageeinreichung. Kammertermin nach 2–4 Monaten.';
      return 'Güteverhandlung i.d.R. innerhalb 2–6 Wochen. Kammertermin nach 2–4 Monaten.';
    }
    if (gerichtTyp == 'sozialgericht') {
      if (t.contains('einstweilig')) return 'Eilverfahren: Entscheidung i.d.R. innerhalb 1–4 Wochen.';
      return 'Widerspruchsbescheid: i.d.R. innerhalb 3 Monaten. Nach 3 Monaten ohne Antwort → Untätigkeitsklage möglich (§ 88 SGG). Klageverfahren: durchschnittlich 15 Monate.';
    }
    if (gerichtTyp == 'betreuungsgericht') {
      if (t.contains('unterbringung') || t.contains('einstweilig')) return 'Eilentscheidung: i.d.R. innerhalb weniger Tage bis 2 Wochen.';
      return 'Beschwerdeverfahren: i.d.R. 1–3 Monate beim Landgericht.';
    }
    return 'Bearbeitungszeit variiert je nach Gericht und Verfahrensart.';
  }

  void _showWiderspruchWizard(Map<String, dynamic> v, ({int tage, String beschreibung, String paragraph}) frist) {
    int step = 0;
    String versandart = '';
    final widerspruchDatumC = TextEditingController(text: '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}');
    final titel = v['titel']?.toString() ?? '';

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(children: [
          Icon(Icons.gavel, color: widget.color.shade700, size: 22), const SizedBox(width: 8),
          Text(step == 0 ? 'Widerspruch eingelegt?' : step == 1 ? 'Versandart' : 'Wartezeit', style: TextStyle(fontSize: 16, color: widget.color.shade700)),
        ]),
        content: SizedBox(width: 460, child: step == 0
          // Step 1: Wurde Widerspruch eingelegt?
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Wurde der Widerspruch / das Rechtsmittel bereits eingelegt?', style: TextStyle(fontSize: 14, color: Colors.grey.shade800)),
              const SizedBox(height: 8),
              Text('Frist: ${frist.tage} Tage — ${frist.beschreibung}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 12),
              TextField(controller: widerspruchDatumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum des Widerspruchs', prefixIcon: const Icon(Icons.calendar_today, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                onTap: () async { final p = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de')); if (p != null) widerspruchDatumC.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}'; }),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: FilledButton.icon(
                icon: const Icon(Icons.check, size: 16), label: const Text('Ja, Widerspruch eingelegt'),
                style: FilledButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 12)),
                onPressed: () => setD(() => step = 1),
              )),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Nein, noch nicht'),
              )),
            ])
          : step == 1
          // Step 2: Wie wurde er versendet?
          ? Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Wie wurde der Widerspruch eingereicht?', style: TextStyle(fontSize: 14, color: Colors.grey.shade800)),
              const SizedBox(height: 12),
              ...[
                ('post', 'Per Post (Einschreiben empfohlen)', Icons.local_post_office, 'Zustellnachweis durch Einschreiben'),
                ('fax', 'Per Fax', Icons.fax, 'Sendebericht als Nachweis aufbewahren'),
                ('persoenlich', 'Persönlich bei Gericht abgegeben', Icons.person, 'Eingangsstempel auf Kopie verlangen'),
                ('elektronisch', 'Elektronisch (beA / EGVP)', Icons.computer, 'Über besonderes elektronisches Anwaltspostfach'),
              ].map((m) => InkWell(
                onTap: () => setD(() { versandart = m.$1; step = 2; }),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: double.infinity, margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: versandart == m.$1 ? widget.color.shade50 : Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: versandart == m.$1 ? widget.color.shade400 : Colors.grey.shade300)),
                  child: Row(children: [
                    Icon(m.$3, size: 20, color: widget.color.shade600), const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(m.$2, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade800)),
                      Text(m.$4, style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
                    ])),
                  ]),
                ),
              )),
            ])
          // Step 3: Wartezeit
          : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: double.infinity, padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.green.shade300)),
                child: Row(children: [
                  Icon(Icons.check_circle, size: 24, color: Colors.green.shade700), const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Widerspruch eingelegt am ${widerspruchDatumC.text}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                    Text('Versand: ${{'post': 'Per Post', 'fax': 'Per Fax', 'persoenlich': 'Persönlich', 'elektronisch': 'Elektronisch'}[versandart] ?? versandart}', style: TextStyle(fontSize: 11, color: Colors.green.shade700)),
                  ])),
                ]),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity, padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blue.shade200)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.timer, size: 20, color: Colors.blue.shade700), const SizedBox(width: 8),
                    Text('Erwartete Wartezeit', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                  ]),
                  const SizedBox(height: 6),
                  Text(_getWartezeit(widget.gerichtTyp, titel), style: TextStyle(fontSize: 12, color: Colors.blue.shade900)),
                ]),
              ),
              if (widget.gerichtTyp == 'sozialgericht') ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade200)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.lightbulb, size: 16, color: Colors.amber.shade700), const SizedBox(width: 8),
                    Expanded(child: Text('Tipp: Nach 3 Monaten ohne Antwort können Sie eine Untätigkeitsklage nach § 88 SGG erheben.', style: TextStyle(fontSize: 11, color: Colors.amber.shade900))),
                  ]),
                ),
              ],
            ]),
        ),
        actions: [
          if (step > 0) TextButton(onPressed: () => setD(() => step--), child: const Text('Zurück')),
          if (step < 2) TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          if (step == 2) FilledButton.icon(
            icon: const Icon(Icons.save, size: 16),
            label: const Text('Speichern & Schließen'),
            style: FilledButton.styleFrom(backgroundColor: widget.color),
            onPressed: () async {
              // Save verlauf entry
              await widget.apiService.addGerichtVorfallVerlauf(widget.vorfallId, {
                'datum': widerspruchDatumC.text,
                'status': 'in_bearbeitung',
                'notiz': 'Widerspruch eingelegt per ${{'post': 'Post', 'fax': 'Fax', 'persoenlich': 'persönlich beim Gericht', 'elektronisch': 'elektronisch (beA/EGVP)'}[versandart] ?? versandart}',
              });
              // Update vorfall status
              final updated = Map<String, dynamic>.from(widget.vorfall); updated['status'] = 'in_bearbeitung';
              await widget.apiService.saveGerichtVorfall(widget.userId, widget.gerichtTyp, updated);
              if (ctx.mounted) Navigator.pop(ctx);
              _load(); widget.onChanged();
            },
          ),
        ],
      );
    }));
  }

  // Unified Verlauf — collects from all tabs chronologically
  Widget _buildVerlaufUnified(Map<String, dynamic> v) {
    String fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    final List<(DateTime, IconData, String, String, MaterialColor)> items = [];

    // Verlauf entries (manuelle Notizen)
    for (final e in _verlauf) {
      final d = _parseDate(e['datum']);
      if (d != null) items.add((d, Icons.edit_note, e['notiz']?.toString() ?? _sLabel(e['status']?.toString() ?? ''), fmt(d), widget.color));
    }
    // Korrespondenz (Eingang / Ausgang) — mit Methode in Label
    for (final k in _korr) {
      final d = _parseDate(k['datum']);
      final isEin = k['richtung'] == 'eingang';
      final methode = k['methode']?.toString() ?? '';
      final methodeLabel = _methodeLabel(methode);
      final betreff = k['betreff']?.toString() ?? '';
      final dirLabel = isEin ? 'Eingang' : 'Ausgang';
      final label = methodeLabel.isNotEmpty
          ? '$dirLabel · $methodeLabel: $betreff'
          : '$dirLabel: $betreff';
      if (d != null) items.add((d, isEin ? Icons.call_received : Icons.call_made, label, fmt(d), isEin ? Colors.green : Colors.blue));
    }
    // Termine (geplante Termine)
    for (final t in _termine) {
      final d = _parseDate(t['datum']);
      if (d != null) items.add((d, Icons.event, 'Termin: ${t['ort'] ?? ''} ${t['uhrzeit'] ?? ''}'.trim(), fmt(d), Colors.purple));
    }
    // Dokumente (hochgeladen — created_at als Zeitpunkt)
    for (final d in _docs) {
      final ts = _parseDate(d['created_at']);
      if (ts != null) {
        final kategorie = (d['kategorie']?.toString() ?? 'sonstiges');
        final kategorieLabel = kategorie == 'antrag' ? 'Antrag' : 'Sonstiges';
        items.add((ts, Icons.upload_file, 'Dokument hochgeladen ($kategorieLabel): ${d['datei_name'] ?? ''}', fmt(ts), Colors.teal));
      }
    }
    // Bescheid / Zustellung (Vorfall-Datum als Eintrag)
    final bescheidD = _parseDate(v['datum']);
    if (bescheidD != null) items.add((bescheidD, Icons.description, 'Bescheid / Zustellung', fmt(bescheidD), Colors.indigo));

    // Neueste zuerst (descending)
    items.sort((a, b) => b.$1.compareTo(a.$1));

    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Icon(Icons.timeline, color: widget.color.shade700), const SizedBox(width: 8),
        Text('Verlauf — Chronologisch (${items.length})', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: widget.color.shade800)),
      ])),
      Expanded(child: items.isEmpty ? Center(child: Text('Kein Verlauf', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: items.length, itemBuilder: (_, i) {
            final e = items[i];
            return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 30, child: Column(children: [
                Container(width: 24, height: 24, decoration: BoxDecoration(color: e.$5.shade100, shape: BoxShape.circle, border: Border.all(color: e.$5.shade400, width: 2)),
                  child: Icon(e.$2, size: 12, color: e.$5.shade700)),
                if (i < items.length - 1) Expanded(child: Container(width: 2, color: Colors.grey.shade300)),
              ])),
              const SizedBox(width: 10),
              Expanded(child: Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: e.$5.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: e.$5.shade200)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Expanded(child: Text(e.$3, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: e.$5.shade800))),
                    Text(e.$4, style: TextStyle(fontSize: 10, color: e.$5.shade600))]),
                ]))),
            ]));
          })),
    ]);
  }

  // Klage Tab
  Widget _buildKlageTab(Map<String, dynamic> v) {
    final status = v['status']?.toString() ?? '';
    final klageRelevant = status == 'bewilligt' || status == 'in_bearbeitung';

    const klageStatusLabels = {
      'vorbereitung': 'In Vorbereitung',
      'eingereicht': 'Klage eingereicht',
      'guetetermin': 'Gütetermin angesetzt',
      'kammertermin': 'Kammertermin angesetzt',
      'verhandlung': 'Verhandlung läuft',
      'vergleich': 'Vergleich geschlossen',
      'urteil': 'Urteil gesprochen',
      'berufung': 'Berufung eingelegt',
      'abgeschlossen': 'Abgeschlossen',
    };
    const klageStatusColors = {
      'vorbereitung': Colors.orange, 'eingereicht': Colors.blue, 'guetetermin': Colors.purple,
      'kammertermin': Colors.indigo, 'verhandlung': Colors.teal, 'vergleich': Colors.green,
      'urteil': Colors.amber, 'berufung': Colors.red, 'abgeschlossen': Colors.grey,
    };

    final klageStatus = v['klage_status']?.toString() ?? '';
    final memberName = '${widget.userName} ${widget.userNachname}'.trim();
    final agName = widget.arbeitgeberName;
    final klaegerC = TextEditingController(text: v['klaeger']?.toString().isNotEmpty == true ? v['klaeger'].toString() : memberName);
    final beklagterC = TextEditingController(text: v['beklagter']?.toString().isNotEmpty == true ? v['beklagter'].toString() : agName);
    final aktenzeichenC = TextEditingController(text: v['klage_aktenzeichen']?.toString().isNotEmpty == true ? v['klage_aktenzeichen'].toString() : v['aktenzeichen']?.toString() ?? '');
    final richterC = TextEditingController(text: v['klage_richter']?.toString().isNotEmpty == true ? v['klage_richter'].toString() : v['sachbearbeiter']?.toString() ?? '');
    final gueteterminC = TextEditingController(text: v['guetetermin_datum']?.toString() ?? '');
    final kammerterminC = TextEditingController(text: v['kammertermin_datum']?.toString() ?? '');
    final notizC = TextEditingController(text: v['klage_notiz']?.toString() ?? '');

    // Parse klage_verlauf for timeline
    List<Map<String, dynamic>> klageVerlauf = [];
    try {
      final raw = v['klage_verlauf'];
      if (raw is List) { klageVerlauf = List<Map<String, dynamic>>.from(raw.map((e) => Map<String, dynamic>.from(e as Map))); }
      else if (raw is String && raw.isNotEmpty) { final decoded = jsonDecode(raw); if (decoded is List) klageVerlauf = List<Map<String, dynamic>>.from(decoded.map((e) => Map<String, dynamic>.from(e as Map))); }
    } catch (_) {}

    return StatefulBuilder(builder: (ctx, setK) {
      String currentStatus = v['klage_status']?.toString() ?? '';
      return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!klageRelevant && klageStatus.isEmpty) ...[
          Container(width: double.infinity, padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              Icon(Icons.balance, size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 8),
              Text('Keine Klage erforderlich', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
              const SizedBox(height: 4),
              Text('Eine Klage wird erst relevant wenn der Widerspruch bewilligt/akzeptiert wurde.', style: TextStyle(fontSize: 11, color: Colors.grey.shade400), textAlign: TextAlign.center),
            ])),
        ] else ...[
          Text('Klage', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
          const SizedBox(height: 12),

          // Parteien mit Switch
          Row(children: [
            Expanded(child: TextField(controller: klaegerC, decoration: InputDecoration(labelText: 'Kläger (wer klagt)', prefixIcon: const Icon(Icons.person, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: IconButton(
              icon: const Icon(Icons.swap_horiz, size: 24), tooltip: 'Kläger/Beklagter tauschen', color: Colors.indigo.shade600,
              onPressed: () => setK(() { final tmp = klaegerC.text; klaegerC.text = beklagterC.text; beklagterC.text = tmp; }),
            )),
            Expanded(child: TextField(controller: beklagterC, decoration: InputDecoration(labelText: 'Beklagter', prefixIcon: const Icon(Icons.business, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
          ]),
          const SizedBox(height: 10),
          TextField(controller: aktenzeichenC, decoration: InputDecoration(labelText: 'Aktenzeichen Gericht', prefixIcon: const Icon(Icons.bookmark, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 10),
          TextField(controller: richterC, decoration: InputDecoration(labelText: 'Richter/in', prefixIcon: const Icon(Icons.person_pin, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: gueteterminC, readOnly: true, decoration: InputDecoration(labelText: 'Gütetermin', prefixIcon: const Icon(Icons.handshake, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              onTap: () async { final d = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (d != null) gueteterminC.text = '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}'; })),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: kammerterminC, readOnly: true, decoration: InputDecoration(labelText: 'Kammertermin', prefixIcon: const Icon(Icons.event, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              onTap: () async { final d = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (d != null) kammerterminC.text = '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}'; })),
          ]),
          const SizedBox(height: 10),
          TextField(controller: notizC, maxLines: 3, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 16),

          // Klage Status
          Text('Klage-Status', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in klageStatusLabels.entries)
              ChoiceChip(label: Text(s.value, style: TextStyle(fontSize: 10, color: currentStatus == s.key ? Colors.white : (klageStatusColors[s.key] ?? Colors.grey).shade800)),
                selected: currentStatus == s.key, selectedColor: (klageStatusColors[s.key] ?? Colors.grey).shade600,
                onSelected: (_) async {
                  final d = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de'));
                  if (d == null) return;
                  final datumStr = '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}';
                  klageVerlauf.insert(0, {'status': s.key, 'datum': datumStr, 'zeit': '${DateTime.now().hour.toString().padLeft(2,'0')}:${DateTime.now().minute.toString().padLeft(2,'0')}'});
                  await widget.apiService.saveGerichtVorfall(widget.userId, widget.gerichtTyp, {
                    ...v, 'id': widget.vorfallId,
                    'klaeger': klaegerC.text.trim(), 'beklagter': beklagterC.text.trim(),
                    'klage_aktenzeichen': aktenzeichenC.text.trim(), 'klage_richter': richterC.text.trim(),
                    'guetetermin_datum': gueteterminC.text.trim(), 'kammertermin_datum': kammerterminC.text.trim(),
                    'klage_status': s.key, 'klage_notiz': notizC.text.trim(), 'klage_verlauf': klageVerlauf,
                  });
                  _load(); widget.onChanged(); setK(() {});
                }),
          ]),

          // Klage Chronologie
          if (klageVerlauf.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Chronologie', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            ...klageVerlauf.map((e) {
              final st = e['status']?.toString() ?? '';
              final stColor = klageStatusColors[st] ?? Colors.grey;
              return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: stColor.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: stColor.shade200)),
                child: Row(children: [
                  Icon(Icons.circle, size: 10, color: stColor.shade600),
                  const SizedBox(width: 8),
                  Expanded(child: Text(klageStatusLabels[st] ?? st, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: stColor.shade800))),
                  Text('${e['datum'] ?? ''} ${e['zeit'] ?? ''}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                ]));
            }),
          ],

          const SizedBox(height: 16),
          Align(alignment: Alignment.centerRight, child: ElevatedButton.icon(
            onPressed: () async {
              await widget.apiService.saveGerichtVorfall(widget.userId, widget.gerichtTyp, {
                ...v, 'id': widget.vorfallId,
                'klaeger': klaegerC.text.trim(), 'beklagter': beklagterC.text.trim(),
                'klage_aktenzeichen': aktenzeichenC.text.trim(), 'klage_richter': richterC.text.trim(),
                'guetetermin_datum': gueteterminC.text.trim(), 'kammertermin_datum': kammerterminC.text.trim(),
                'klage_status': currentStatus, 'klage_notiz': notizC.text.trim(), 'klage_verlauf': klageVerlauf,
              });
              _load(); widget.onChanged();
              if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: const Text('Gespeichert'), backgroundColor: Colors.green.shade600));
            },
            icon: const Icon(Icons.save, size: 16), label: const Text('Speichern'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade700, foregroundColor: Colors.white),
          )),
        ],
      ]));
    });
  }

  Widget _tlItem(IconData icon, String title, String date, Color color, bool hasLine, {String? subtitle}) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(children: [
        Container(width: 32, height: 32, decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle, border: Border.all(color: color, width: 2)),
          child: Icon(icon, size: 16, color: color)),
        if (hasLine) Container(width: 2, height: 28, color: Colors.grey.shade300),
      ]),
      const SizedBox(width: 12),
      Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color))), Text(date, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700))]),
        if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle, style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontStyle: FontStyle.italic))),
      ]))),
    ]);
  }

  Widget _lawRow(String paragraph, String text) {
    return Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(4)),
        child: Text(paragraph, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.indigo.shade700))),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: TextStyle(fontSize: 11, color: Colors.grey.shade700))),
    ]));
  }

  String _sLabel(String s) {
    switch (s) { case 'offen': return 'Offen'; case 'in_bearbeitung': return 'In Bearbeitung'; case 'bewilligt': return 'Bewilligt'; case 'abgelehnt': return 'Abgelehnt'; case 'erledigt': return 'Erledigt'; default: return s; }
  }
}

// ============================================================================
// Anregung Betreuer-Tab — Antrag Generator für Betreuungsgericht-Vorfall.
// Befüllt den offiziellen Bayern-Vordruck "Anregung zur Bestellung eines
// Betreuers" mit den Daten Vormund (Absender) + Mitglied (Betroffene Person)
// + Aufgabenbereiche-Auswahl, und liefert das fertige PDF zurück.
// ============================================================================

class _AnregungBetreuerTab extends StatefulWidget {
  final ApiService apiService;
  final int vorfallId;
  final int userId;
  final MaterialColor color;
  const _AnregungBetreuerTab({required this.apiService, required this.vorfallId, required this.userId, required this.color});
  @override
  State<_AnregungBetreuerTab> createState() => _AnregungBetreuerTabState();
}

class _AnregungBetreuerTabState extends State<_AnregungBetreuerTab> {
  bool _loading = true;
  bool _saving = false;
  bool _generating = false;
  Map<String, dynamic>? _target;
  Map<String, dynamic>? _vormund;
  Map<String, dynamic>? _defaults;

  String _verhaeltnisTyp = 'verwandt';

  // All boolean fields (mirror server BOOL_COLS list)
  static const _boolKeys = [
    'aufgaben_gesundheit','aufgaben_vermoegen','aufgaben_aufenthalt','aufgaben_wohnung',
    'aufgaben_haus_grund','aufgaben_vertretung','aufgaben_ambulant','aufgaben_heim',
    'aufgaben_geschlossene_unterbringung','aufgaben_freiheitsentziehend','aufgaben_rechte_bevollm',
    'aufgaben_post','aufgaben_sonstiges',
    'eilbeduerftigkeit','anlage_vollmachten','anlage_aerztl_stellung',
    'vollm_nicht_bekannt','vollm_vorsorge','vollm_bank','vollm_in_anhang','vollm_betreuung_notwendig',
    'vollm_umfasst_nicht','vollm_will_nicht','vollm_verstorben','vollm_nicht_zum_wohl','vollm_uneinig','vollm_sonstiges',
    'diag_demenz','diag_hirnorganisch','diag_alzheimer','diag_schlaganfall','diag_schizophrenie','diag_psychose',
    'diag_schaedelhirn','diag_sucht','diag_geistig','diag_mehrfach','diag_depression','aerztl_stellung_vorhanden',
    'zustand_willen_kund','zustand_willen_nicht','zustand_fortbewegen','zustand_nicht_fortbewegen',
    'zustand_hilfe_alles','zustand_tuer_nicht',
    'komm_schwerhoerig','komm_sehbehindert','komm_keine_deutsch',
    'aufenthalt_wohnung','aufenthalt_anderes',
    'zugericht_kann','zugericht_nicht',
    'haltung_nicht_bekannt','haltung_nicht_einverstanden','haltung_einverstanden','haltung_keine_kenntnis',
  ];
  // All text fields
  static const _textKeys = [
    'verwandtschaftsverhaeltnis','art_des_kontakts',
    'aufgaben_sonstiges_text','eilbeduerftigkeit_grund',
    'vollm_sonstiges_text','diag_sonstiges_text',
    'komm_dolmetscher_sprache','aufenthalt_anderes_text',
    'wunsch_betreuer','lehnt_betreuer','vertrauenspersonen',
  ];

  final Map<String, bool> _bools = {for (final k in _boolKeys) k: false};
  late final Map<String, TextEditingController> _texts = {for (final k in _textKeys) k: TextEditingController()};

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() {
    for (final c in _texts.values) { c.dispose(); }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await widget.apiService.loadAnregungBetreuerInput(vorfallId: widget.vorfallId, userId: widget.userId);
      if (r['success'] == true) {
        _target  = r['target']  is Map ? Map<String, dynamic>.from(r['target']  as Map) : null;
        _vormund = r['vormund'] is Map ? Map<String, dynamic>.from(r['vormund'] as Map) : null;
        _defaults= r['defaults']is Map ? Map<String, dynamic>.from(r['defaults']as Map) : null;
        final input = r['input'] is Map ? Map<String, dynamic>.from(r['input'] as Map) : null;
        if (input != null) {
          _verhaeltnisTyp = input['verhaeltnis_typ']?.toString() ?? 'verwandt';
          for (final k in _boolKeys) {
            _bools[k] = (input[k] ?? 0).toString() == '1';
          }
          for (final k in _textKeys) {
            _texts[k]!.text = input[k]?.toString() ?? '';
          }
        } else if (_defaults != null) {
          _verhaeltnisTyp = _defaults!['verhaeltnis_typ']?.toString() ?? 'verwandt';
          _texts['art_des_kontakts']!.text = _defaults!['art_des_kontakts_default']?.toString() ?? '';
        }
      }
    } catch (e) { debugPrint('[AnregungBetreuer] load: $e'); }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final input = <String, dynamic>{'verhaeltnis_typ': _verhaeltnisTyp};
    for (final k in _boolKeys) { input[k] = _bools[k]! ? 1 : 0; }
    for (final k in _textKeys) { input[k] = _texts[k]!.text.trim(); }
    final r = await widget.apiService.saveAnregungBetreuerInput(vorfallId: widget.vorfallId, userId: widget.userId, input: input);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r['message']?.toString() ?? (r['success'] == true ? 'Gespeichert' : 'Fehler')),
      backgroundColor: r['success'] == true ? Colors.green : Colors.red,
    ));
  }

  Future<void> _generateAndOpen() async {
    // Spinner ON from the very beginning — covers _save + PDF download.
    if (mounted) setState(() => _generating = true);

    Uint8List? pdfBytes;
    String? errorMsg;

    try {
      await _save();
      if (!mounted) return;

      final bytes = await widget.apiService.downloadAnregungBetreuerPdf(
        vorfallId: widget.vorfallId, userId: widget.userId,
      );
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) {
        errorMsg = 'PDF-Generierung fehlgeschlagen (Server lieferte keine Daten oder Zeitüberschreitung).';
      } else {
        pdfBytes = Uint8List.fromList(bytes);
        // Cache to disk too (so user can also access via filesystem)
        try {
          final dir = await getTemporaryDirectory();
          final ts = DateTime.now().millisecondsSinceEpoch;
          final f = File('${dir.path}/Anregung_Betreuung_$ts.pdf');
          await f.writeAsBytes(pdfBytes, flush: true);
          debugPrint('[Anregung] PDF cached at: ${f.path}');
        } catch (e) { debugPrint('[Anregung] cache write failed (non-fatal): $e'); }
      }
    } catch (e) {
      errorMsg = 'Fehler: $e';
    } finally {
      if (mounted) setState(() => _generating = false);
    }

    if (!mounted) return;
    if (errorMsg != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMsg), backgroundColor: Colors.red));
      return;
    }
    if (pdfBytes != null) {
      // Show in-app PDF viewer with pdfrx — works on all platforms without
      // depending on external apps (xdg-open / Okular / Adobe Reader).
      final ts = DateTime.now().millisecondsSinceEpoch;
      await FileViewerDialog.showFromBytes(
        context,
        pdfBytes,
        'Anregung_Betreuung_$ts.pdf',
      );
    }
  }

  Widget _section(String title) => Padding(padding: const EdgeInsets.only(top: 14, bottom: 6),
    child: Row(children: [
      Container(width: 4, height: 16, color: widget.color.shade400),
      const SizedBox(width: 8),
      Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: widget.color.shade800)),
    ]));

  Widget _info(String label, String? value) {
    final v = (value ?? '').trim();
    return Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [
      SizedBox(width: 140, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade700))),
      Expanded(child: Text(v.isEmpty ? '—' : v, style: TextStyle(fontSize: 12, color: v.isEmpty ? Colors.grey.shade400 : null))),
    ]));
  }

  Widget _cb(String key, String label) => CheckboxListTile(
    dense: true, contentPadding: EdgeInsets.zero,
    controlAffinity: ListTileControlAffinity.leading,
    title: Text(label, style: const TextStyle(fontSize: 12)),
    value: _bools[key]!,
    onChanged: (v) => setState(() => _bools[key] = v ?? false),
  );

  Widget _tf(String key, String label, {int maxLines = 1}) => Padding(padding: const EdgeInsets.symmetric(vertical: 4),
    child: TextField(controller: _texts[key], maxLines: maxLines, decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder())));

  /// TextField + 👤+ Button next to it: pick a Mitglied to auto-fill formatted entry.
  Widget _tfWithPicker(String key, String label, {String? helpHint}) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: TextField(
          controller: _texts[key], maxLines: 2,
          decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
        )),
        const SizedBox(width: 6),
        Tooltip(message: 'Mitglied auswählen und automatisch eintragen',
          child: ElevatedButton.icon(
            onPressed: () => _pickMitgliedFor(key),
            icon: const Icon(Icons.person_add, size: 16),
            label: const Text('Mitglied', style: TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.color.shade100,
              foregroundColor: widget.color.shade900,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            ),
          )),
      ]),
      if (helpHint != null) Padding(padding: const EdgeInsets.only(left: 4, top: 2),
        child: Text(helpHint, style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontStyle: FontStyle.italic))),
    ]));
  }

  Future<void> _pickMitgliedFor(String key) async {
    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _MitgliedPickerDialog(apiService: widget.apiService, excludeId: widget.userId),
    );
    if (picked == null || !mounted) return;
    final formatted = _formatMitgliedEntry(picked);
    final current = _texts[key]!.text.trim();
    setState(() {
      _texts[key]!.text = current.isEmpty ? formatted : '$current\n$formatted';
    });
  }

  String _formatMitgliedEntry(Map<String, dynamic> m) {
    final parts = <String>[];
    final fullName = '${m['vorname'] ?? ''} ${m['nachname'] ?? ''}'.trim();
    if (fullName.isNotEmpty) parts.add(fullName);
    final adr = [
      '${m['strasse'] ?? ''} ${m['hausnummer'] ?? ''}'.trim(),
      '${m['plz'] ?? ''} ${m['ort'] ?? ''}'.trim(),
    ].where((e) => e.isNotEmpty).join(', ');
    if (adr.isNotEmpty) parts.add(adr);
    final tel = (m['telefon_mobil']?.toString().isNotEmpty ?? false)
        ? m['telefon_mobil'].toString()
        : (m['telefon_fix']?.toString() ?? '');
    if (tel.isNotEmpty) parts.add('Tel: $tel');
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final hasVormund = _vormund != null;

    return SingleChildScrollView(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: widget.color.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: widget.color.shade200)),
        child: Row(children: [
          Icon(Icons.gavel, color: widget.color.shade700, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(
            'Anregung zur Bestellung eines Betreuers — Vordruck Bayerisches Staatsministerium der Justiz, einzureichen bei Amtsgericht Neu-Ulm (Betreuungsgericht).',
            style: TextStyle(fontSize: 11, color: widget.color.shade900))),
        ])),
      const SizedBox(height: 14),
      if (!hasVormund) Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade200)),
        child: Row(children: [
          Icon(Icons.warning_amber, color: Colors.orange.shade700),
          const SizedBox(width: 8),
          Expanded(child: Text(
            'Dieses Mitglied hat keinen Vormund verknüpft. Der Antragsteller (Absender) kann nicht automatisch befüllt werden. Bitte zuerst unter dem Vormund-Konto eine Verknüpfung anlegen.',
            style: TextStyle(fontSize: 12, color: Colors.orange.shade900))),
        ]),
      ),

      _section('Absender — Antragsteller (Vormund / Betreuer)'),
      if (hasVormund) ...[
        _info('Name, Vorname', '${_vormund!['nachname'] ?? ''}, ${_vormund!['vorname'] ?? ''}'),
        _info('Straße, Hausnr.', '${_vormund!['strasse'] ?? ''} ${_vormund!['hausnummer'] ?? ''}'),
        _info('PLZ, Ort', '${_vormund!['plz'] ?? ''} ${_vormund!['ort'] ?? ''}'),
        _info('Telefon mobil', _vormund!['telefon_mobil']?.toString()),
        _info('Telefon Festnetz', _vormund!['telefon_fix']?.toString()),
        _info('E-Mail', _vormund!['email']?.toString()),
      ],

      _section('Betroffene Person — Mitglied'),
      if (_target != null) ...[
        _info('Name, Vorname', '${_target!['nachname'] ?? ''}, ${_target!['vorname'] ?? ''}'),
        _info('Geburtsdatum', _target!['geburtsdatum']?.toString()),
        _info('Straße, Hausnr.', '${_target!['strasse'] ?? ''} ${_target!['hausnummer'] ?? ''}'),
        _info('PLZ, Wohnort', '${_target!['plz'] ?? ''} ${_target!['ort'] ?? ''}'),
        _info('Telefon mobil', _target!['telefon_mobil']?.toString()),
        _info('Telefon Festnetz', _target!['telefon_fix']?.toString()),
        _info('E-Mail', _target!['email']?.toString()),
      ],

      _section('Verhältnis zur betroffenen Person'),
      Wrap(spacing: 8, children: [
        ChoiceChip(label: const Text('verwandt'), selected: _verhaeltnisTyp == 'verwandt', onSelected: (_) => setState(() => _verhaeltnisTyp = 'verwandt')),
        ChoiceChip(label: const Text('bekannt / befreundet'), selected: _verhaeltnisTyp == 'befreundet', onSelected: (_) => setState(() => _verhaeltnisTyp = 'befreundet')),
        ChoiceChip(label: const Text('beruflich'), selected: _verhaeltnisTyp == 'beruflich', onSelected: (_) => setState(() => _verhaeltnisTyp = 'beruflich')),
      ]),
      if (_verhaeltnisTyp == 'verwandt') _tf('verwandtschaftsverhaeltnis', 'Verwandtschaftsverhältnis (Vater / Mutter / Sohn / Tochter / ...)'),
      if (_verhaeltnisTyp == 'beruflich') _tf('art_des_kontakts', 'Art des Kontakts (z.B. Behörde, Arzt, Sozialdienst, Berufsbetreuer)'),

      // ============ VOLLMACHTEN ============
      _section('Vollmachten'),
      _cb('vollm_nicht_bekannt', 'Ob Vollmachten bestehen, ist mir nicht bekannt'),
      _cb('vollm_vorsorge', 'Es besteht eine Vorsorgevollmacht'),
      _cb('vollm_bank', 'Es besteht eine Bankvollmacht'),
      _cb('vollm_in_anhang', 'Die bestehende/n Vollmacht/en füge ich in Kopie im Anhang bei'),
      _cb('vollm_betreuung_notwendig', 'Eine Betreuung ist notwendig, obwohl eine Vollmacht vorhanden ist, denn:'),
      if (_bools['vollm_betreuung_notwendig']!) ...[
        Padding(padding: const EdgeInsets.only(left: 24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _cb('vollm_umfasst_nicht', 'die Vollmacht umfasst nicht alle notwendigen Bereiche'),
          _cb('vollm_will_nicht', 'der/die Bevollmächtigte möchte die Vollmacht nicht mehr ausüben'),
          _cb('vollm_verstorben', 'der/die Bevollmächtigte ist verstorben oder gesundheitlich nicht in der Lage'),
          _cb('vollm_nicht_zum_wohl', 'der/die Bevollmächtigte übt die Vollmacht nicht zum Wohl der betroffenen Person aus'),
          _cb('vollm_uneinig', 'mehrere Bevollmächtigte sind sich über die Ausübung uneinig'),
          _cb('vollm_sonstiges', 'Sonstiges:'),
          if (_bools['vollm_sonstiges']!) _tf('vollm_sonstiges_text', 'Sonstiges (Freitext)'),
        ])),
      ],

      // ============ DIAGNOSE ============
      _section('Gesundheitszustand — Diagnose'),
      _cb('diag_demenz', 'Demenz'),
      _cb('diag_hirnorganisch', 'Hirnorganisches Psychosyndrom'),
      _cb('diag_alzheimer', 'Alzheimer Erkrankung'),
      _cb('diag_schlaganfall', 'Zustand nach Schlaganfall'),
      _cb('diag_schizophrenie', 'Schizophrenie'),
      _cb('diag_psychose', 'Psychose'),
      _cb('diag_schaedelhirn', 'Schädel-Hirn-Trauma'),
      _cb('diag_sucht', 'Suchtkrankheit'),
      _cb('diag_geistig', 'Geistige Behinderung'),
      _cb('diag_mehrfach', 'Mehrfachbehinderung'),
      _cb('diag_depression', 'Depression bzw. Angststörung'),
      _tf('diag_sonstiges_text', 'Sonstige Diagnose (Freitext)'),
      _cb('aerztl_stellung_vorhanden', 'Es liegt eine ärztliche Stellungnahme vor (als Anlage beigefügt)'),

      // ============ ZUSTAND ============
      _section('Zustand der betroffenen Person'),
      _cb('zustand_willen_kund', 'kann ihren Willen kundzutun'),
      _cb('zustand_willen_nicht', 'kann ihren Willen NICHT kundzutun'),
      _cb('zustand_fortbewegen', 'kann sich fortbewegen'),
      _cb('zustand_nicht_fortbewegen', 'kann sich NICHT fortbewegen'),
      _cb('zustand_hilfe_alles', 'ist in allen Bereichen des täglichen Lebens auf Hilfe angewiesen'),
      _cb('zustand_tuer_nicht', 'wird bei einem Kontaktversuch voraussichtlich die Tür nicht öffnen'),

      // ============ KOMMUNIKATION ============
      _section('Kommunikationsprobleme'),
      _cb('komm_schwerhoerig', 'Schwerhörigkeit'),
      _cb('komm_sehbehindert', 'Sehbehinderung'),
      _cb('komm_keine_deutsch', 'Unzureichende deutsche Sprachkenntnisse — Dolmetscher erforderlich'),
      if (_bools['komm_keine_deutsch']!) _tf('komm_dolmetscher_sprache', 'Sprache des Dolmetschers'),

      // ============ AUFENTHALTSORT ============
      _section('Derzeitiger Aufenthaltsort'),
      _cb('aufenthalt_wohnung', 'Die betroffene Person ist unter ihrer Wohnanschrift anzutreffen'),
      _cb('aufenthalt_anderes', 'Die betroffene Person ist derzeit anderweitig anzutreffen:'),
      if (_bools['aufenthalt_anderes']!) _tf('aufenthalt_anderes_text', 'Einrichtung, Adresse, Ansprechpartner, Station, Telefon (Freitext)', maxLines: 2),

      // ============ ZU GERICHT KOMMEN ============
      _section('Kann die Person zu Gericht / Sachverständigen kommen?'),
      _cb('zugericht_kann', 'kann kommen oder gebracht werden'),
      _cb('zugericht_nicht', 'kann NICHT kommen oder gebracht werden'),

      // ============ HALTUNG ============
      _section('Haltung der betroffenen Person zur Bestellung'),
      _cb('haltung_nicht_bekannt', 'Die Haltung ist mir nicht bekannt'),
      _cb('haltung_nicht_einverstanden', 'NICHT einverstanden'),
      _cb('haltung_einverstanden', 'einverstanden'),
      _cb('haltung_keine_kenntnis', 'Die betroffene Person hat von dieser Anregung keine Kenntnis'),

      // ============ WUNSCH / LEHNT / VERTRAUENSPERSONEN ============
      _section('Wunsch-Betreuer / Lehnt ab / Vertrauenspersonen'),
      _tfWithPicker('wunsch_betreuer', 'Wunsch-Betreuer (Name, Adresse, Telefon)',
        helpHint: 'Person, die der/die Betroffene als Betreuer wünscht (§ 1816 Abs. 2 BGB — Gericht muss respektieren)'),
      _tfWithPicker('lehnt_betreuer', 'Lehnt als Betreuer ab (Name, Adresse)',
        helpHint: 'Person, die der/die Betroffene NICHT als Betreuer haben möchte (z.B. Konflikt, Misstrauen)'),
      _tfWithPicker('vertrauenspersonen', 'Vertrauenspersonen (Name, Adresse, Telefon)',
        helpHint: 'Andere Personen aus dem Vertrauensumfeld, die als Betreuer in Betracht kommen'),

      // ============ AUFGABENBEREICHE ============
      _section('Aufgabenbereiche des Betreuers'),
      _cb('aufgaben_gesundheit', 'Gesundheitssorge'),
      _cb('aufgaben_vermoegen', 'Vermögenssorge'),
      _cb('aufgaben_aufenthalt', 'Aufenthaltsbestimmung'),
      _cb('aufgaben_wohnung', 'Wohnungsangelegenheiten'),
      _cb('aufgaben_haus_grund', 'Haus- und Grundstücksangelegenheiten'),
      _cb('aufgaben_vertretung', 'Vertretung gegenüber Behörden, Versicherungen, Renten-, Kranken- und Sozialleistungsträgern'),
      _cb('aufgaben_ambulant', 'Organisation der ambulanten Versorgung'),
      _cb('aufgaben_heim', 'Abschluss, Änderung und Kontrolle eines Heim- oder Pflegevertrages'),
      _cb('aufgaben_geschlossene_unterbringung', 'Entscheidung über die geschlossene Unterbringung'),
      _cb('aufgaben_freiheitsentziehend', 'Entscheidung über freiheitsentziehende Maßnahmen'),
      _cb('aufgaben_rechte_bevollm', 'Geltendmachung von Rechten gegenüber dem Bevollmächtigten'),
      _cb('aufgaben_post', 'Entgegennahme, Öffnen und Anhalten der Post'),
      _cb('aufgaben_sonstiges', 'Sonstiges'),
      if (_bools['aufgaben_sonstiges']!) _tf('aufgaben_sonstiges_text', 'Sonstige Aufgabenbereiche (Freitext)'),

      // ============ EILBEDÜRFTIGKEIT ============
      _section('Eilbedürftigkeit'),
      _cb('eilbeduerftigkeit', 'Es besteht besondere Eilbedürftigkeit'),
      if (_bools['eilbeduerftigkeit']!) _tf('eilbeduerftigkeit_grund', 'Begründung der Eilbedürftigkeit', maxLines: 2),

      // ============ ANLAGEN ============
      _section('Anlagen'),
      _cb('anlage_vollmachten', 'Vollmacht/en in Kopie'),
      _cb('anlage_aerztl_stellung', 'Ärztliche Stellungnahme in Kopie'),

      const SizedBox(height: 18),
      Row(children: [
        OutlinedButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save, size: 16),
          label: const Text('Speichern'),
        ),
        const SizedBox(width: 10),
        Expanded(child: ElevatedButton.icon(
          onPressed: (_generating || !hasVormund) ? null : _generateAndOpen,
          icon: _generating ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.picture_as_pdf, size: 16),
          label: const Text('PDF generieren & öffnen'),
          style: ElevatedButton.styleFrom(backgroundColor: widget.color.shade700, foregroundColor: Colors.white),
        )),
      ]),
      const SizedBox(height: 20),
    ]));
  }
}

// ============================================================================
// _MitgliedPickerDialog — search & pick a Mitglied to insert as
// Wunsch-/Lehnt-Betreuer or Vertrauensperson.
// ============================================================================

class _MitgliedPickerDialog extends StatefulWidget {
  final ApiService apiService;
  final int excludeId;
  const _MitgliedPickerDialog({required this.apiService, required this.excludeId});
  @override
  State<_MitgliedPickerDialog> createState() => _MitgliedPickerDialogState();
}

class _MitgliedPickerDialogState extends State<_MitgliedPickerDialog> {
  final _searchC = TextEditingController();
  List<Map<String, dynamic>> _candidates = [];
  bool _searching = false;

  @override
  void dispose() { _searchC.dispose(); super.dispose(); }

  Future<void> _search() async {
    final q = _searchC.text.trim();
    if (q.length < 2) return;
    setState(() { _searching = true; _candidates = []; });
    try {
      final r = await widget.apiService.searchMembersForLink(query: q, excludeVormundId: widget.excludeId);
      if (r['success'] == true) {
        _candidates = (r['candidates'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      }
    } catch (_) {}
    if (mounted) setState(() => _searching = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        Icon(Icons.person_search, color: Colors.indigo.shade700, size: 22),
        const SizedBox(width: 8),
        const Expanded(child: Text('Mitglied auswählen', style: TextStyle(fontSize: 16))),
      ]),
      content: SizedBox(width: 520, height: 460, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: TextField(controller: _searchC,
            decoration: InputDecoration(
              hintText: 'ID / Mitgliedernummer / Name...',
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onSubmitted: (_) => _search(),
          )),
          const SizedBox(width: 8),
          ElevatedButton(onPressed: _searching ? null : _search,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade700, foregroundColor: Colors.white),
            child: _searching ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Suchen'),
          ),
        ]),
        const SizedBox(height: 10),
        Expanded(child: _candidates.isEmpty
          ? Center(child: Text(_searching ? '' : 'Geben Sie Name oder Nummer ein und suchen.', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)))
          : ListView.separated(
              itemCount: _candidates.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
              itemBuilder: (lctx, i) {
                final c = _candidates[i];
                final adr = '${c['strasse'] ?? ''} ${c['hausnummer'] ?? ''}, ${c['plz'] ?? ''} ${c['ort'] ?? ''}'.trim();
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(backgroundColor: Colors.indigo.shade50, child: Icon(Icons.person, color: Colors.indigo.shade700, size: 18)),
                  title: Text('${c['vorname'] ?? ''} ${c['nachname'] ?? ''}'.trim(),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Nr. ${c['mitgliedernummer'] ?? '#${c['id']}'} · ${c['role'] ?? ''}', style: const TextStyle(fontSize: 10)),
                    if (adr.length > 2) Text(adr, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  ]),
                  trailing: const Icon(Icons.add_circle_outline, size: 20),
                  onTap: () => Navigator.pop(context, c),
                );
              },
            )),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen'))],
    );
  }
}

// ═══════════════════════════════════════════════════════
// BERATUNGSHILFE PDF-GENERATOR
// Bundeseinheitliches Antragsformular nebst Hinweisblatt
// (justizportal.justiz-bw.de). Pre-fills Stammdaten from the
// member's master row, lets the operator add Sachverhalt +
// Finanzangaben, then asks the server to render the AcroForm
// via /api/admin/beratungshilfe_pdf.php (pdftk fill_form).
// ═══════════════════════════════════════════════════════
class _BeratungshilfeGeneratorTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int vorfallId;
  final Map<String, dynamic> vorfall;
  final String userName;
  final String userNachname;
  final MaterialColor color;
  const _BeratungshilfeGeneratorTab({
    required this.apiService,
    required this.userId,
    required this.vorfallId,
    required this.vorfall,
    required this.userName,
    required this.userNachname,
    required this.color,
  });
  @override
  State<_BeratungshilfeGeneratorTab> createState() => _BeratungshilfeGeneratorTabState();
}

class _BeratungshilfeGeneratorTabState extends State<_BeratungshilfeGeneratorTab> {
  bool _loading = true;
  bool _generating = false;
  String? _lastError;
  String? _lastGeneratedPath;

  // Pre-filled from user master row
  Map<String, dynamic> _user = {};

  // Court catalogue + selection — every Amtsgericht has its own address
  // that the form's "Name des Amtsgerichts" + "Postleitzahl Ort" fields
  // get filled with. Loaded from gericht_datenbank where
  // gericht_typ = 'beratungshilfe'.
  List<Map<String, dynamic>> _gerichte = [];
  Map<String, dynamic>? _selectedGericht;

  // Keine Bearbeitungs-Felder hier. Tab is intentionally minimal: pick
  // the Amtsgericht, hit Generieren. Stammdaten kommen aus `users`,
  // Sachverhalt aus dem Vorfall (titel + notiz). Restliche Felder
  // (Einkommen, Wohnkosten, Vermögen, B-Erklärungen) bleiben im PDF
  // leer und werden später aus dedizierten Modulen befüllt.

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.apiService.getUserDetails(widget.userId);
      if (r['success'] == true && r['user'] is Map) {
        _user = Map<String, dynamic>.from(r['user'] as Map);
      }
    } catch (_) {}
    // Court catalogue — every Amtsgericht / Bundesland may ship its
    // own PDF template (BW v14, Bayern avr070, Berlin avr77 etc.)
    // referenced by gericht_datenbank.pdf_template.
    try {
      final g = await widget.apiService.getGerichtDatenbank('beratungshilfe');
      if (g['success'] == true && g['gerichte'] is List) {
        _gerichte = List<Map<String, dynamic>>.from(g['gerichte']);
        if (_gerichte.isNotEmpty) _selectedGericht = _gerichte.first;
      }
    } catch (_) {}
    // Pre-fill Sachverhalt from Vorfall titel + notiz
    final titel = widget.vorfall['titel']?.toString() ?? '';
    final notiz = widget.vorfall['notiz']?.toString() ?? '';
    _sachverhaltC.text = [titel, notiz].where((s) => s.isNotEmpty).join('\n\n');
    if (mounted) setState(() => _loading = false);
  }

  /// Extract "89073 Ulm" from an address line like
  /// "Zeughausgasse 14, 89073 Ulm (Justizzentrum Zeughaus, EG)".
  /// Used to fill the form's "Postleitzahl Ort" field from the chosen
  /// gericht_datenbank row.
  String _plzOrtFromAddress(String addr) {
    final m = RegExp(r'(\d{5}\s+[A-Za-zÄÖÜäöüß\-]+)').firstMatch(addr);
    return m?.group(1) ?? '';
  }

  String _antragsteller() {
    final v1 = (_user['vorname'] ?? widget.userName).toString();
    final v2 = (_user['vorname2'] ?? '').toString();
    final n  = (_user['nachname'] ?? widget.userNachname).toString();
    final gn = (_user['geburtsname'] ?? '').toString();
    final base = [v1, v2, n].where((s) => s.isNotEmpty).join(' ');
    return gn.isNotEmpty ? '$base (geb. $gn)' : base;
  }

  String _anschrift() {
    final s = (_user['strasse'] ?? '').toString();
    final h = (_user['hausnummer'] ?? '').toString();
    final p = (_user['plz'] ?? '').toString();
    final o = (_user['ort'] ?? '').toString();
    return '${[s, h].where((x) => x.isNotEmpty).join(' ')}, ${[p, o].where((x) => x.isNotEmpty).join(' ')}'
        .replaceAll(RegExp(r'^,\s*|\s*,$'), '');
  }

  String _telefon() {
    final m = (_user['telefon_mobil'] ?? '').toString();
    final f = (_user['telefon_fix'] ?? '').toString();
    return m.isNotEmpty ? m : f;
  }

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _lastError = null;
      _lastGeneratedPath = null;
    });
    if (_selectedGericht == null) {
      setState(() {
        _generating = false;
        _lastError = 'Kein Amtsgericht ausgewählt — bitte oben einen Eintrag wählen.';
      });
      return;
    }
    final g = _selectedGericht!;
    final titel = (widget.vorfall['titel'] ?? '').toString();
    final notiz = (widget.vorfall['notiz'] ?? '').toString();
    final sachverhalt = [titel, notiz].where((s) => s.isNotEmpty).join('\n\n');
    final payload = <String, dynamic>{
      'amtsgericht': (g['name'] ?? '').toString(),
      'amtsgericht_plz_ort': _plzOrtFromAddress((g['adresse'] ?? '').toString()),
      'pdf_template': (g['pdf_template'] ?? '').toString(),
      'antragsteller': _antragsteller(),
      'beruf': (_user['beruf'] ?? '').toString(),
      'geburtsdatum': (_user['geburtsdatum'] ?? '').toString(),
      'familienstand': (_user['familienstand'] ?? '').toString(),
      'anschrift': _anschrift(),
      'telefon': _telefon(),
      'sachverhalt': sachverhalt,
    };
    try {
      final bytes = await widget.apiService.generateBeratungshilfePdf(payload);
      if (!mounted) return;
      if (bytes == null) {
        setState(() {
          _generating = false;
          _lastError = 'Server lieferte kein PDF zurück. pdftk- oder Template-Fehler — Logs prüfen.';
        });
        return;
      }
      Directory? dir;
      try { dir = await getDownloadsDirectory(); } catch (_) {}
      dir ??= await getApplicationDocumentsDirectory().catchError((_) => Directory.systemTemp);
      final filename = 'Beratungshilfe_Antrag_${widget.userId}_${widget.vorfallId}.pdf';
      final path = '${dir.path}${Platform.pathSeparator}$filename';
      await File(path).writeAsBytes(bytes);
      if (!mounted) return;
      setState(() {
        _generating = false;
        _lastGeneratedPath = path;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('PDF gespeichert: $path'),
        backgroundColor: Colors.green,
        action: SnackBarAction(label: 'Öffnen', textColor: Colors.white, onPressed: () => OpenFilex.open(path)),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _lastError = 'Fehler: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final c = widget.color;
    return Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(Icons.picture_as_pdf, color: c.shade700),
        const SizedBox(width: 8),
        const Expanded(child: Text('Beratungshilfe-Antrag generieren',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
      ]),
      const SizedBox(height: 16),

      // Single court → no dropdown needed; multiple → pick one.
      if (_gerichte.isEmpty)
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.amber.shade300)),
          child: Row(children: [
            Icon(Icons.warning_amber, size: 18, color: Colors.amber.shade800),
            const SizedBox(width: 8),
            Expanded(child: Text('Kein Amtsgericht für Beratungshilfe in der Datenbank.',
              style: TextStyle(fontSize: 12, color: Colors.amber.shade900))),
          ]),
        )
      else if (_gerichte.length == 1)
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: c.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: c.shade300)),
          child: Row(children: [
            Icon(Icons.account_balance, size: 18, color: c.shade700),
            const SizedBox(width: 8),
            Expanded(child: Text((_selectedGericht?['name'] ?? '').toString(),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.shade800))),
          ]),
        )
      else
        DropdownButtonFormField<Map<String, dynamic>>(
          initialValue: _selectedGericht,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Amtsgericht',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: Icon(Icons.account_balance, size: 18, color: c.shade700),
          ),
          items: _gerichte.map((g) => DropdownMenuItem(
            value: g,
            child: Text((g['name'] ?? '').toString(),
              style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: (v) => setState(() => _selectedGericht = v),
        ),

      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: _generating ? null : _generate,
        icon: _generating
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.picture_as_pdf, size: 18),
        label: Text(_generating ? 'Wird erstellt…' : 'PDF generieren'),
        style: FilledButton.styleFrom(
          backgroundColor: c.shade700,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),

      if (_lastGeneratedPath != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.green.shade300)),
          child: Row(children: [
            Icon(Icons.check_circle, color: Colors.green.shade700, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(_lastGeneratedPath!, style: TextStyle(fontSize: 11, color: Colors.green.shade800), overflow: TextOverflow.ellipsis)),
            TextButton.icon(icon: const Icon(Icons.open_in_new, size: 14), label: const Text('Öffnen'),
              onPressed: () => OpenFilex.open(_lastGeneratedPath!)),
          ]),
        ),
      ],
      if (_lastError != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.red.shade300)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.error_outline, color: Colors.red.shade700, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(_lastError!, style: TextStyle(fontSize: 11, color: Colors.red.shade800))),
          ]),
        ),
      ],
    ]));
  }
}
