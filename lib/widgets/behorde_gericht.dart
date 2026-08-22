import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'phone_link.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../utils/clipboard_helper.dart';
import '../utils/file_picker_helper.dart';
import 'file_viewer_dialog.dart';
import 'vollmacht_link_aktionen.dart';
import 'korrespondenz_attachments_widget.dart';
import '../utils/cloud_picker_helper.dart';
import '../utils/ra_antwort.dart';
import '../services/signatur_service.dart';
import '../utils/app_farben.dart';
import '../utils/sicherer_dateiname.dart';

/// Kategorien der Dokumente an einem Gerichts-Vorfall (Reiter „Dokumente").
///
/// ⚠️ Zeichengleich mit `GV_KATEGORIEN` in `api/admin/gericht_vorfall_detail.php`.
/// Das PHP liegt nur auf dem Server, nicht im Repository — `test/
/// gericht_vorfall_kategorien_test.dart` ist deshalb die einzige Stelle, an der
/// ein Auseinanderlaufen überhaupt auffallen kann. Und es fällt sonst NICHT
/// auf: einen Wert, den der Server nicht kennt, setzt er still auf
/// `sonstiges` zurück. Der Nutzer lädt einen Beschluss hoch, bekommt kein
/// Fehlerzeichen — und findet ihn danach im falschen Abschnitt.
///
/// `beschluss` zeigt der Client nur beim Insolvenzgericht an; serverseitig ist
/// die Kategorie für alle Gerichtstypen erlaubt, denn sie hängt am Dokument,
/// nicht am Gerichtstyp.
const kGerichtVorfallDokKategorien = <String, String>{
  'antrag':    'Antrag',
  'beschluss': 'Beschluss',
  'sonstiges': 'Sonstiges',
};

class BehordeGerichtContent extends StatefulWidget {
  final User user;
  final ApiService apiService;
  /// Mitgliedsnummer des angemeldeten Vorstands. Die digitale Unterschrift
  /// wird IN SEINEM NAMEN angefordert, nicht im Namen des Mitglieds.
  final String adminMitgliedernummer;
  final Map<String, dynamic> Function(String type) getData;
  final bool Function(String type) isLoading;
  final bool Function(String type) isSaving;
  final void Function(String type) loadData;
  final void Function(String type, Map<String, dynamic> data) saveData;

  const BehordeGerichtContent({
    super.key,
    required this.user,
    required this.apiService,
    this.adminMitgliedernummer = '',
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
          labelColor: F.h(Colors.indigo, 700),
          unselectedLabelColor: F.h(Colors.grey, 600),
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
          labelColor: F.h(color, 700), unselectedLabelColor: F.h(Colors.grey, 600), indicatorColor: color.shade700,
          tabs: [
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: (_d(typ, 'gericht')['name']?.toString() ?? '').isNotEmpty ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.account_balance, size: 14), const SizedBox(width: 4), const Flexible(child: Text('Zuständiges Gericht', overflow: TextOverflow.ellipsis))])),
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: (_vorfaelle[typ]?.isNotEmpty == true) ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.report_problem, size: 14), const SizedBox(width: 4), const Flexible(child: Text('Vorfall', overflow: TextOverflow.ellipsis))])),
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
        Icon(Icons.account_balance, size: 20, color: F.h(color, 700)), const SizedBox(width: 8),
        Expanded(child: Text('Zuständiges Gericht', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: F.h(color, 700)))),
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
          decoration: BoxDecoration(color: F.h(Colors.grey, 50), borderRadius: BorderRadius.circular(10), border: Border.all(color: F.h(Colors.grey, 300))),
          child: Column(children: [
            Icon(Icons.search, size: 40, color: F.h(Colors.grey, 400)), const SizedBox(height: 8),
            Text('Kein Gericht ausgewählt', style: TextStyle(fontSize: 13, color: F.h(Colors.grey, 600))),
            const SizedBox(height: 4),
            Text('Tippen Sie auf "Auswählen" um das zuständige Gericht zu suchen.', style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 500))),
          ]),
        )
      else ...[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: F.h(color, 50), borderRadius: BorderRadius.circular(10), border: Border.all(color: F.h(color, 300))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(selectedName, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: F.h(color, 900))),
            if (selected != null) ...[
              const SizedBox(height: 6),
              _infoRow(Icons.location_on, 'Adresse', selected['adresse'] ?? '', copyable: true),
              _infoRow(Icons.phone, 'Telefon', selected['telefon'] ?? '', copyable: true),
              if ((selected['fax'] ?? '').isNotEmpty)
                _infoRow(Icons.print, 'Fax', selected['fax']!, copyable: true),
              _infoRow(Icons.email, 'E-Mail', selected['email'] ?? '', copyable: true, copyLabel: 'E-Mail'),
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
        Icon(Icons.search, color: F.h(color, 700)), const SizedBox(width: 8),
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
            decoration: BoxDecoration(color: F.flaeche, borderRadius: BorderRadius.circular(10), border: Border.all(color: F.h(Colors.grey, 300))),
            child: Row(children: [
              Icon(Icons.account_balance, size: 20, color: F.h(color, 600)), const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g['name']!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: F.h(color, 900))),
                Text('${g['adresse']}', style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
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
        Icon(Icons.report_problem, size: 20, color: F.h(color, 700)), const SizedBox(width: 8),
        Expanded(child: Text('Vorfälle (${list.length})', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: F.h(color, 700)))),
        ElevatedButton.icon(
          onPressed: () => _showVorfallDialog(typ, label, color, antragTypen),
          icon: const Icon(Icons.add, size: 16), label: const Text('Neuer Vorfall', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
        ),
      ])),
      Expanded(child: list.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.folder_open, size: 48, color: F.h(Colors.grey, 300)), const SizedBox(height: 8), Text('Keine Vorfälle', style: TextStyle(color: F.h(Colors.grey, 500)))]))
          : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: list.length, itemBuilder: (_, i) {
              final v = list[i];
              final status = v['status']?.toString() ?? 'offen';
              return Card(child: ListTile(
                leading: Icon(_statusIcon(status), color: _statusColor(status), size: 28),
                title: Text(v['titel']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${v['datum'] ?? ''} • ${_statusLabel(status)}', style: TextStyle(fontSize: 11, color: _statusColor(status))),
                  if ((v['aktenzeichen']?.toString() ?? '').isNotEmpty) Text('Az.: ${v['aktenzeichen']}', style: TextStyle(fontSize: 10, color: F.h(color, 600), fontWeight: FontWeight.w600)),
                ]),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400), onPressed: () async {
                    final id = int.tryParse(v['id']?.toString() ?? '');
                    if (id != null) { await widget.apiService.deleteGerichtVorfall(id); _loaded[typ] = false; setState(() {}); }
                  }),
                  Icon(Icons.chevron_right, color: F.h(Colors.grey, 400)),
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
      title: Text(isEdit ? 'Vorfall bearbeiten' : 'Neuer Vorfall', style: TextStyle(color: F.h(color, 700))),
      content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        DropdownButtonFormField<String>(
          // Ohne `isExpanded` richtet sich ein Dropdown nach seinem
          // breitesten Eintrag, nicht nach dem Feld. Ein langer Name
          // sprengte damit die Zeile — gemessen 241 dp in
          // ordnungsmassnahmen_screen. Als Formularfeld soll es
          // ohnehin die volle Breite haben.
          isExpanded: true,
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
            ChoiceChip(label: Text(s.$2, style: TextStyle(fontSize: 11, color: status == s.$1 ? Colors.white : F.textStark)), selected: status == s.$1, selectedColor: s.$3, onSelected: (_) => setD(() => status = s.$1)),
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

  Widget _infoRow(IconData icon, String label, String value, {bool copyable = false, String? copyLabel}) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Icon(icon, size: 14, color: F.h(Colors.grey, 600)), const SizedBox(width: 8),
      SizedBox(width: 100, child: Text(label, style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600), fontWeight: FontWeight.w600))),
      Expanded(child: SelectableText(value, style: const TextStyle(fontSize: 11))),
      // SelectableText bleibt selektierbar; das Wählen bekommt einen eigenen Button.
      if (isPhoneIcon(icon)) PhoneCallButton(number: value, label: label, size: 14),
      if (copyable) InkWell(
        onTap: () => ClipboardHelper.copy(context, value, copyLabel ?? label),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(Icons.copy, size: 14, color: F.h(Colors.blue, 600)),
        ),
      ),
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
          adminMitgliedernummer: widget.adminMitgliedernummer,
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
  /// Mitgliedsnummer des angemeldeten Vorstands. Der Signatur-Endpunkt
  /// verlangt sie als Identitätsnachweis des Anfordernden — ohne sie bleibt
  /// der Unterschriftsstand ungeladen, statt geraten zu werden.
  final String adminMitgliedernummer;
  const _GerichtVorfallDetailView({required this.apiService, required this.userId, required this.vorfallId, required this.vorfall, required this.gerichtTyp, required this.color, required this.antragTypen, required this.onEdit, required this.onChanged, this.userName = '', this.userNachname = '', this.arbeitgeberName = '', this.adminMitgliedernummer = ''});
  @override
  State<_GerichtVorfallDetailView> createState() => _GerichtVorfallDetailViewState();
}

class _GerichtVorfallDetailViewState extends State<_GerichtVorfallDetailView> {
  List<Map<String, dynamic>> _verlauf = [];
  List<Map<String, dynamic>> _docs = [];
  List<Map<String, dynamic>> _termine = [];
  List<Map<String, dynamic>> _korr = [];
  bool _loaded = false;
  // Read-only listing of docs sitting in sibling Behörden modules
  // (Jobcenter Bescheid scans, Vermieter Mietvertrag anhänge, etc.).
  // Populated from /api/admin/related_docs.php — NO files are copied.
  List<Map<String, dynamic>> _relatedSections = [];
  // Pflicht-Checkliste of Belege the Antrag auf Beratungshilfe asks
  // for (justizportal.justiz-bw.de + service.justiz.de). Each entry
  // {key,label,found,hint}.
  List<Map<String, dynamic>> _relatedChecklist = [];
  // Per-section Behörde filter — key = section key (e.g. 'korrespondenz'),
  // value = selected behoerde or null for all. Multiple Behörden often
  // surface Widerspruch-Belege (Jobcenter, Arbeitsagentur, Sozialamt,
  // Versorgungsamt, …) and the operator wants to pick one to focus on.
  final Map<String, String?> _relatedSectionFilter = {};
  // All "cases" the member has across Behörden — surfaced by the server
  // so the operator can choose which ones belong to this Beratungshilfe-
  // Vorfall. Each entry: {behoerde, case_type, case_id, label,
  // files_count, widerspruch}.
  List<Map<String, dynamic>> _availableCases = [];
  // Currently linked cases on this vorfall (subset of _availableCases).
  // Each entry only carries {behoerde, case_type, case_id}.
  List<Map<String, dynamic>> _linkedCases = [];
  // Bank statements from Finanzen → only loaded for Beratungshilfe, where
  // § 2 BerHG requires proof of financial hardship via the last 3 months
  // of Kontoauszüge (some Gerichte accept up to 6). The Dokumente tab
  // shows a coverage indicator so the Vorstand sees at a glance whether
  // the required window is met before submitting the Antrag.
  List<Map<String, dynamic>> _kontoauszuege = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final vR = await widget.apiService.listGerichtVorfallVerlauf(widget.vorfallId);
    final dR = await widget.apiService.listGerichtVorfallDocs(widget.vorfallId);
    final tR = await widget.apiService.listGerichtVorfallTermine(widget.vorfallId);
    final kR = await widget.apiService.listGerichtVorfallKorr(widget.vorfallId);
    final rR = await widget.apiService.listRelatedDocs(widget.userId, vorfallId: widget.vorfallId);
    final kaR = widget.gerichtTyp == 'beratungshilfe'
        ? await widget.apiService.listFinanzenKontoauszuege(widget.userId)
        : null;
    if (!mounted) return;
    setState(() {
      if (vR['success'] == true && vR['data'] is List) _verlauf = (vR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (dR['success'] == true && dR['data'] is List) _docs = (dR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (tR['success'] == true && tR['data'] is List) _termine = (tR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (kR['success'] == true && kR['data'] is List) {
        _korr = (kR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        // Chronologische Reihenfolge, neueste oben — die Endpunkte geben die
        // Einträge je nach Tabelle in inkonsistenter Reihenfolge zurück
        // (manchmal nach id DESC, manchmal nach id ASC), also sortieren
        // wir hier zentral nach dem Datum. Fällt auf created_at zurück,
        // wenn datum fehlt; Einträge ohne beides landen am Ende.
        _korr.sort((a, b) {
          final aDt = _parseDatum(a['datum']?.toString()) ?? _parseDatum(a['created_at']?.toString());
          final bDt = _parseDatum(b['datum']?.toString()) ?? _parseDatum(b['created_at']?.toString());
          if (aDt == null && bDt == null) return 0;
          if (aDt == null) return 1;
          if (bDt == null) return -1;
          return bDt.compareTo(aDt);
        });
      }
      if (rR != null && rR['sections'] is List) {
        _relatedSections = (rR['sections'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      if (rR != null && rR['checklist'] is List) {
        _relatedChecklist = (rR['checklist'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      if (rR != null && rR['cases'] is List) {
        _availableCases = (rR['cases'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } else {
        _availableCases = [];
      }
      if (rR != null && rR['linked_cases'] is List) {
        _linkedCases = (rR['linked_cases'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } else {
        _linkedCases = [];
      }
      if (kaR != null && kaR['success'] == true && kaR['data'] is List) {
        _kontoauszuege = (kaR['data'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } else {
        _kontoauszuege = [];
      }
      _loaded = true;
    });
  }

  bool _caseIsLinked(Map<String, dynamic> c) {
    final beh = (c['behoerde'] ?? '').toString();
    final ct  = (c['case_type'] ?? '').toString();
    final cid = c['case_id'] is int ? c['case_id'] as int : int.tryParse('${c['case_id']}') ?? 0;
    for (final l in _linkedCases) {
      if ((l['behoerde'] ?? '') == beh
          && (l['case_type'] ?? '') == ct
          && (l['case_id'] is int ? l['case_id'] : int.tryParse('${l['case_id']}')) == cid) {
        return true;
      }
    }
    return false;
  }

  Future<void> _openCasePicker() async {
    if (_availableCases.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Keine Fälle verfügbar — keine Widerspruch-Belege im System.'),
        ));
      }
      return;
    }
    // Build a local mutable set keyed by "beh|ct|cid".
    String key(Map c) => '${c['behoerde']}|${c['case_type']}|${c['case_id']}';
    final selected = <String>{for (final c in _availableCases) if (_caseIsLinked(c)) key(c)};

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        // Group cases per Behörde.
        final groups = <String, List<Map<String, dynamic>>>{};
        for (final c in _availableCases) {
          (groups[(c['behoerde'] ?? '').toString()] ??= []).add(c);
        }
        final keys = groups.keys.toList()..sort();
        return AlertDialog(
          title: const Text('Fälle für Beratungshilfe wählen'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    selected.isEmpty
                        ? 'Keine Auswahl → in der Korrespondenz-Sektion erscheinen ALLE Fälle.'
                        : '${selected.length} Fall/Fälle gewählt → nur diese erscheinen in der Korrespondenz-Sektion.',
                    style: TextStyle(fontSize: 12, color: F.hd(Colors.black54, F.textSchwach)),
                  ),
                ),
                Row(children: [
                  TextButton.icon(
                    icon: const Icon(Icons.select_all, size: 16),
                    label: const Text('Alle wählen', style: TextStyle(fontSize: 12)),
                    onPressed: () => setD(() => selected
                      ..clear()
                      ..addAll(_availableCases.map(key))),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.deselect, size: 16),
                    label: const Text('Auswahl löschen', style: TextStyle(fontSize: 12)),
                    onPressed: () => setD(() => selected.clear()),
                  ),
                ]),
                const Divider(),
                for (final b in keys) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 4),
                    child: Text(_behoerdeLabel(b),
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: F.h(Colors.indigo, 700))),
                  ),
                  for (final c in groups[b]!)
                    CheckboxListTile(
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      value: selected.contains(key(c)),
                      onChanged: (v) => setD(() {
                        if (v == true) {
                          selected.add(key(c));
                        } else {
                          selected.remove(key(c));
                        }
                      }),
                      title: Text((c['label'] ?? '').toString(), style: const TextStyle(fontSize: 12)),
                      subtitle: Text(
                        '${c['files_count']} Datei(en)'
                            '${(c['widerspruch'] == true) ? ' · ⚖ Widerspruchsverfahren' : ''}',
                        style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600)),
                      ),
                    ),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
            ElevatedButton(
              onPressed: () async {
                final picked = _availableCases.where((c) => selected.contains(key(c))).map((c) => {
                  'behoerde':  c['behoerde'],
                  'case_type': c['case_type'],
                  'case_id':   c['case_id'],
                }).toList();
                final ok = await widget.apiService.setVorfallLinkedCases(
                  vorfallId: widget.vorfallId,
                  userId: widget.userId,
                  cases: picked,
                );
                if (!ctx.mounted) return;
                Navigator.pop(ctx, ok);
              },
              child: const Text('Speichern'),
            ),
          ],
        );
      }),
    );
    if (saved == true) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vorfall;
    final status = v['status']?.toString() ?? 'offen';
    final isBetreuung = widget.gerichtTyp == 'betreuungsgericht';
    final isBeratungshilfe = widget.gerichtTyp == 'beratungshilfe';
    // Nur hier gibt es eine Insolvenzverwaltung: bestellt wird sie vom
    // Insolvenzgericht im Eröffnungsbeschluss. Bei den übrigen fünf
    // Gerichtstypen bliebe der Tab immer leer.
    final isInsolvenz = widget.gerichtTyp == 'insolvenzgericht';
    // Basis 8: Details · Dokumente · Verlauf · Termine · Korrespondenz ·
    // Widerspruch · Klage · Vollmacht. Betreuung und Beratungshilfe bringen je
    // einen eigenen Generator-Tab mit, das Insolvenzgericht die Verwaltung.
    final tabCount = 8
        + ((isBetreuung || isBeratungshilfe) ? 1 : 0)
        + (isInsolvenz ? 1 : 0);
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
      TabBar(labelColor: F.h(widget.color, 700), indicatorColor: widget.color.shade700, isScrollable: true, tabs: [
        const Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Details'),
        if (isBetreuung) const Tab(icon: Icon(Icons.assignment, size: 18), text: 'Antrag Generator'),
        if (isBeratungshilfe) const Tab(icon: Icon(Icons.picture_as_pdf, size: 18), text: 'PDF-Generator'),
        const Tab(icon: Icon(Icons.folder, size: 18), text: 'Dokumente'),
        const Tab(icon: Icon(Icons.timeline, size: 18), text: 'Verlauf'),
        const Tab(icon: Icon(Icons.calendar_month, size: 18), text: 'Termine'),
        const Tab(icon: Icon(Icons.mail, size: 18), text: 'Korrespondenz'),
        const Tab(icon: Icon(Icons.gavel, size: 18), text: 'Widerspruch'),
        const Tab(icon: Icon(Icons.balance, size: 18), text: 'Klage'),
        const Tab(icon: Icon(Icons.assignment_ind, size: 18), text: 'Vollmacht'),
        if (isInsolvenz)
          const Tab(icon: Icon(Icons.account_balance_wallet, size: 18), text: 'Insolvenzverwalter'),
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
          onAntragUploaded: _load, // refresh _docs so new PDF shows up
        ),
        _buildDokumente(),
        _buildVerlaufUnified(v),
        _buildTermine(),
        _buildKorrespondenz(),
        _buildWiderspruch(v),
        _buildKlageTab(v),
        _GerichtVollmachtTab(
          apiService: widget.apiService,
          userId: widget.userId,
          vorfallId: widget.vorfallId,
          gerichtTyp: widget.gerichtTyp,
          color: widget.color,
          // ⚠️ Ohne die Nummer des Vorstands fällt in diesem Reiter alles aus,
          // was an der Unterschrift hängt — und zwar lautlos: „Zur Unterschrift
          // stellen" rendert gar nicht, `_signaturenLaden()` kehrt sofort um,
          // also bleibt auch „Unterschriebene Fassung" für immer unsichtbar,
          // und der Signierlink kann nie gehen, weil seine Voraussetzung hier
          // nicht anlegbar ist. Der Reiter direkt darunter bekam sie längst.
          adminMitgliedernummer: widget.adminMitgliedernummer,
        ),
        if (isInsolvenz) _InsolvenzverwalterTab(
          apiService: widget.apiService,
          userId: widget.userId,
          vorfallId: widget.vorfallId,
          color: widget.color,
          adminMitgliedernummer: widget.adminMitgliedernummer,
        ),
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
        Text('Sachbearbeiter/Richter', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: F.h(Colors.grey, 700))),
        const SizedBox(height: 4),
        _dRow(Icons.person, 'Name', v['sachbearbeiter']),
        _dRow(Icons.phone, 'Telefon', v['sachbearbeiter_tel']),
        _dRow(Icons.email, 'E-Mail', v['sachbearbeiter_email']),
      ],
      if ((v['notiz']?.toString() ?? '').isNotEmpty) ...[
        const SizedBox(height: 8),
        Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: F.h(Colors.yellow, 50), borderRadius: BorderRadius.circular(8)),
          child: Text(v['notiz'].toString(), style: const TextStyle(fontSize: 12))),
      ],
    ]));
  }

  Widget _dRow(IconData icon, String label, dynamic value) {
    final s = value?.toString() ?? ''; if (s.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
      Icon(icon, size: 14, color: F.h(Colors.grey, 600)), const SizedBox(width: 8),
      SizedBox(width: 120, child: Text(label, style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600), fontWeight: FontWeight.w600))),
      Expanded(child: phoneAwareText(icon, s, label: label, style: const TextStyle(fontSize: 13))),
    ]));
  }

  // ── DOKUMENTE (kategorisiert) ──
  Widget _buildDokumente() {
    final isBeratungshilfe = widget.gerichtTyp == 'beratungshilfe';
    // Eigener Abschnitt für gerichtliche Beschlüsse — nur beim
    // Insolvenzgericht. Bei den übrigen Gerichtstypen bliebe er meist leer,
    // und ein leerer Abschnitt kostet nur Platz.
    final isInsolvenz = widget.gerichtTyp == 'insolvenzgericht';
    final antragDocs   = _docs.where((d) => (d['kategorie']?.toString() ?? 'sonstiges') == 'antrag').toList();
    final beschlussDocs = _docs.where((d) => (d['kategorie']?.toString() ?? 'sonstiges') == 'beschluss').toList();
    // ⚠️ „Sonstiges" ist der Auffang, NICHT die Kategorie `sonstiges`.
    // Vorher stand hier `== 'sonstiges'`: ein Dokument mit einer Kategorie,
    // die gerade keinen eigenen Abschnitt hat, war damit auf dem Schirm
    // nirgends zu sehen — es lag in der Datenbank und galt als verloren.
    // Genau das träfe einen Beschluss, wenn der Vorfall später auf einen
    // anderen Gerichtstyp umgestellt wird.
    final sonstigeDocs = _docs.where((d) {
      final k = d['kategorie']?.toString() ?? 'sonstiges';
      if (k == 'antrag') return false;
      if (k == 'beschluss' && isInsolvenz) return false;
      return true;
    }).toList();
    return SingleChildScrollView(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Pflicht-Belege-Checkliste — only for Beratungshilfe, where
      // justizportal explicitly lists what's required.
      if (isBeratungshilfe && _relatedChecklist.isNotEmpty)
        _buildChecklistCard(),
      if (isInsolvenz) ...[
        _buildBeschlussHinweis(beschlussDocs),
        _buildDokSection('Beschluss', Icons.gavel, beschlussDocs, 'beschluss',
          hint: 'Beschluss über die Erteilung der Restschuldbefreiung (§ 300 InsO), '
                'Eröffnungsbeschluss (§ 27 InsO), Aufhebung des Verfahrens (§ 200 InsO), '
                'Stundung der Verfahrenskosten (§ 4a InsO)'),
      ],
      _buildDokSection('Antrag', Icons.assignment, antragDocs, 'antrag',
        hint: 'Generierter Anregung-Antrag, Anlagen zum Antrag (Vollmachten, ärztliche Stellungnahme, Kopien)'),
      // Read-only sections sourced from sibling Behörden modules — no
      // file copy, the doc stays in its original place; click opens it
      // through the per-module download endpoint.
      ..._relatedSections.map(_buildRelatedSection),
      _buildDokSection('Sonstiges', Icons.folder, sonstigeDocs, 'sonstiges',
        hint: 'Alle anderen Dokumente ohne feste Kategorie'),
      // Kontoauszüge (Beratungshilfe § 2 BerHG) — Nachweis der letzten
      // 3 Monate vor Antragstellung.
      if (isBeratungshilfe) _buildKontoauszuegeSection(),
    ]));
  }

  /// Warum der Beschluss über die Restschuldbefreiung einen eigenen Platz hat
  /// und nicht im Stapel „Sonstiges" liegen darf.
  ///
  /// ⚠️ Die öffentliche Bekanntmachung ist KEIN dauerhafter Nachweis: nach
  /// § 3 InsoBekV wird die Veröffentlichung auf insolvenzbekanntmachungen.de
  /// spätestens sechs Monate nach Rechtskraft gelöscht. Danach ist die eigene
  /// Kopie die einzige Urkunde, die das Mitglied noch hat — und gebraucht wird
  /// sie oft erst Jahre später, wenn ein Gläubiger wieder anschreibt.
  Widget _buildBeschlussHinweis(List<Map<String, dynamic>> beschluesse) {
    final leer = beschluesse.isEmpty;
    final farbe = leer ? Colors.amber : Colors.blue;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: F.h(farbe, 50),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: F.h(farbe, 200)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(leer ? Icons.warning_amber_rounded : Icons.gavel, size: 18, color: F.h(farbe, 800)),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(leer ? 'Noch kein Beschluss hinterlegt' : 'Beschlüsse des Insolvenzgerichts',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: F.h(farbe, 900))),
          const SizedBox(height: 4),
          Text(
            'Über die Restschuldbefreiung entscheidet das Gericht durch Beschluss (§ 300 InsO). '
            'Dieser Beschluss ist der Nachweis, dass die Schulden erloschen sind — er wirkt nach '
            '§ 301 Abs. 1 InsO gegen ALLE Insolvenzgläubiger, auch gegen die, die ihre Forderung '
            'nie angemeldet haben.',
            style: TextStyle(fontSize: 11, color: F.h(farbe, 900))),
          const SizedBox(height: 4),
          Text(
            '⚠️ Die öffentliche Bekanntmachung wird nach § 3 InsoBekV spätestens sechs Monate '
            'nach Rechtskraft gelöscht. Danach ist diese Kopie der einzige Nachweis. '
            'Ausgenommen bleiben nur die Forderungen aus § 302 InsO.',
            style: TextStyle(fontSize: 10, color: F.h(farbe, 900), fontStyle: FontStyle.italic)),
        ])),
      ]),
    );
  }

  Widget _buildKontoauszuegeSection() {
    final vorfallDatum = _parseDatum(widget.vorfall['datum']?.toString());
    // Berechne Referenzzeitraum: 3 Monate vor Antrag bis Antragsdatum.
    // Falls das Vorfall-Datum leer ist, nehmen wir "heute" — sonst würde
    // der Card fälschlicherweise anzeigen "keine Auszüge vorhanden".
    final refBis = vorfallDatum ?? DateTime.now();
    final refVon = DateTime(refBis.year, refBis.month - 3, refBis.day);

    // Merge overlapping ranges to check if [refVon..refBis] is fully covered.
    final ranges = <MapEntry<DateTime, DateTime>>[];
    for (final k in _kontoauszuege) {
      final v = _parseDatum(k['von_datum']?.toString());
      final b = _parseDatum(k['bis_datum']?.toString());
      if (v == null || b == null) continue;
      ranges.add(MapEntry(v, b));
    }
    ranges.sort((a, b) => a.key.compareTo(b.key));
    final merged = <MapEntry<DateTime, DateTime>>[];
    for (final r in ranges) {
      if (merged.isEmpty || r.key.isAfter(merged.last.value.add(const Duration(days: 1)))) {
        merged.add(MapEntry(r.key, r.value));
      } else if (r.value.isAfter(merged.last.value)) {
        merged[merged.length - 1] = MapEntry(merged.last.key, r.value);
      }
    }
    final fullyCovered = merged.any((r) =>
      !r.key.isAfter(refVon) && !r.value.isBefore(refBis));

    final overlappingIds = <int>{};
    for (final k in _kontoauszuege) {
      final v = _parseDatum(k['von_datum']?.toString());
      final b = _parseDatum(k['bis_datum']?.toString());
      final id = int.tryParse(k['id']?.toString() ?? '');
      if (v == null || b == null || id == null) continue;
      if (!b.isBefore(refVon) && !v.isAfter(refBis)) overlappingIds.add(id);
    }

    Color statusColor;
    IconData statusIcon;
    String statusText;
    if (_kontoauszuege.isEmpty) {
      statusColor = Colors.red.shade600;
      statusIcon = Icons.error_outline;
      statusText = 'Keine Kontoauszüge vorhanden — Nachweis fehlt';
    } else if (fullyCovered) {
      statusColor = Colors.green.shade700;
      statusIcon = Icons.check_circle;
      statusText = 'Die 3 Monate vor Antrag sind lückenlos abgedeckt';
    } else if (overlappingIds.isNotEmpty) {
      statusColor = Colors.orange.shade700;
      statusIcon = Icons.warning_amber;
      statusText = 'Teilweise abgedeckt — bitte Lücken vor der Einreichung schließen';
    } else {
      statusColor = Colors.red.shade600;
      statusIcon = Icons.error_outline;
      statusText = 'Vorhandene Auszüge liegen außerhalb des Referenzzeitraums';
    }

    String fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: statusColor.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.account_balance, size: 18, color: statusColor),
          const SizedBox(width: 6),
          Expanded(child: Text('Kontoauszüge (Beratungshilfe § 2 BerHG)',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: statusColor))),
          Text('${_kontoauszuege.length}', style: TextStyle(fontSize: 12, color: statusColor)),
        ]),
        const SizedBox(height: 6),
        Text('Nachweis-Zeitraum: ${fmt(refVon)} – ${fmt(refBis)} '
             '(${vorfallDatum == null ? "kein Antrag-Datum, heute als Referenz" : "3 Monate vor Antrag"})',
             style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700))),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
          child: Row(children: [
            Icon(statusIcon, size: 16, color: statusColor),
            const SizedBox(width: 6),
            Expanded(child: Text(statusText, style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w600))),
          ]),
        ),
        if (_kontoauszuege.isEmpty) ...[
          const SizedBox(height: 8),
          Text('Legen Sie Kontoauszüge unter Finanzen → Zuständige Bank → Kontoauszüge an.',
            style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600), fontStyle: FontStyle.italic)),
        ] else ...[
          const SizedBox(height: 10),
          ..._kontoauszuege.map((k) {
            final v = _parseDatum(k['von_datum']?.toString());
            final b = _parseDatum(k['bis_datum']?.toString());
            final id = int.tryParse(k['id']?.toString() ?? '');
            final inWindow = id != null && overlappingIds.contains(id);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: F.flaeche,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: inWindow ? F.h(Colors.green, 300) : F.h(Colors.grey, 300)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(inWindow ? Icons.check_circle : Icons.remove_circle_outline,
                    size: 16, color: inWindow ? F.h(Colors.green, 700) : F.h(Colors.grey, 500)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(
                    '${v != null ? fmt(v) : '?'} – ${b != null ? fmt(b) : '?'}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  )),
                  if (v != null && b != null)
                    Text('${b.difference(v).inDays + 1} Tage',
                      style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
                ]),
                if ((k['notiz']?.toString() ?? '').isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 3, left: 22),
                    child: Text(k['notiz'].toString(), style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700)))),
                if (id != null) Padding(
                  padding: const EdgeInsets.only(top: 6, left: 22),
                  child: KorrAttachmentsWidget(
                    apiService: widget.apiService,
                    modul: 'finanzen_kontoauszug',
                    korrespondenzId: id,
                   memberId: widget.userId,),
                ),
              ]),
            );
          }),
        ],
      ]),
    );
  }

  Widget _buildChecklistCard() {
    final missing = _relatedChecklist.where((c) => c['found'] != true).toList();
    final foundCount = _relatedChecklist.length - missing.length;
    final headerColor = missing.isEmpty ? Colors.green : Colors.amber;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: (missing.isEmpty ? Colors.green : Colors.amber).shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: F.h(headerColor, 300)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(missing.isEmpty ? Icons.check_circle : Icons.checklist,
            size: 18, color: F.h(headerColor, 800)),
          const SizedBox(width: 6),
          Expanded(child: Text(
            'Pflicht-Belege für Beratungshilfe ($foundCount von ${_relatedChecklist.length})',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: F.h(headerColor, 900)),
          )),
        ]),
        const SizedBox(height: 6),
        ..._relatedChecklist.map((c) {
          final found = c['found'] == true;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(found ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 14, color: found ? F.h(Colors.green, 700) : F.h(Colors.grey, 500)),
              const SizedBox(width: 6),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  (c['label'] ?? '').toString(),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: found ? FontWeight.w600 : FontWeight.normal,
                    color: found ? F.h(Colors.green, 900) : F.h(Colors.grey, 800),
                    decoration: null,
                  ),
                ),
                if (!found && (c['hint'] != null) && (c['hint'] as String).isNotEmpty)
                  Text(c['hint'].toString(),
                    style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600), fontStyle: FontStyle.italic)),
              ])),
            ]),
          );
        }),
      ]),
    );
  }

  Widget _buildRelatedSection(Map<String, dynamic> section) {
    final allItems = (section['items'] as List?) ?? const [];
    if (allItems.isEmpty) return const SizedBox.shrink();
    final title = (section['title'] ?? '').toString();
    final key   = (section['key'] ?? '').toString();
    final widerspruchCount = (section['widerspruch_count'] is int)
        ? section['widerspruch_count'] as int
        : 0;
    // Unique Behörden in this section. If >1, show filter chips so the
    // operator can narrow down to a single Behörde (jobcenter / sozialamt
    // / versorgungsamt / arbeitsagentur / finanzamt / krankenkasse / rfb).
    final behoerden = <String>{};
    for (final raw in allItems) {
      final b = (raw is Map ? raw['behoerde'] : null)?.toString() ?? '';
      if (b.isNotEmpty) behoerden.add(b);
    }
    final selected = _relatedSectionFilter[key];
    final items = selected == null
        ? allItems
        : allItems.where((r) =>
            (r is Map ? r['behoerde'] : null)?.toString() == selected).toList();
    final icon  = key == 'einkommen'
        ? Icons.account_balance_wallet
        : key == 'wohnen' ? Icons.home
        : key == 'korrespondenz' ? Icons.gavel
        : Icons.folder_special;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: F.flaeche,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: F.h(Colors.indigo, 200)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            color: F.h(Colors.indigo, 50),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
          ),
          child: Row(children: [
            Icon(icon, size: 18, color: F.h(Colors.indigo, 700)),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                selected != null
                    ? '$title (${items.length} von ${allItems.length})'
                    : '$title (${allItems.length})',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: F.h(Colors.indigo, 900)),
              ),
              if (widerspruchCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: F.h(Colors.deepOrange, 100),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.deepOrange.shade400),
                    ),
                    child: Text(
                      '⚖ $widerspruchCount im aktiven Widerspruchsverfahren',
                      style: TextStyle(fontSize: 10, color: F.h(Colors.deepOrange, 900), fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              Text('Aus anderer Akte — read-only Link, kein Datei-Kopie',
                style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600), fontStyle: FontStyle.italic)),
            ])),
            // Case-Picker — nur für die Korrespondenz-Sektion. Zeigt
            // einen Dialog mit allen Fällen (Sanktionen, Anträge,
            // Bewilligungen, Korr-Einträge) gruppiert nach Behörde, mit
            // Multi-Select. Auswahl wird auf gericht_vorfaelle.linked_cases
            // gespeichert und filtert anschließend die Korrespondenz.
            if (key == 'korrespondenz' && _availableCases.isNotEmpty)
              Tooltip(
                message: _linkedCases.isEmpty
                    ? 'Alle ${_availableCases.length} Fälle aktiv — klicken um auszuwählen'
                    : '${_linkedCases.length} von ${_availableCases.length} Fällen gewählt',
                child: TextButton.icon(
                  onPressed: _openCasePicker,
                  icon: const Icon(Icons.checklist, size: 16),
                  label: Text(
                    _linkedCases.isEmpty
                        ? 'Fälle (alle)'
                        : 'Fälle (${_linkedCases.length}/${_availableCases.length})',
                    style: const TextStyle(fontSize: 11),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: _linkedCases.isEmpty ? F.h(Colors.indigo, 700) : F.h(Colors.deepOrange, 800),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
          ]),
        ),
        if (behoerden.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 8, 2),
            child: Wrap(
              spacing: 6, runSpacing: 4,
              children: [
                _behoerdeChip(key, null, 'Alle (${allItems.length})', selected == null),
                ...behoerden.map((b) {
                  final n = allItems.where((r) =>
                      (r is Map ? r['behoerde'] : null)?.toString() == b).length;
                  return _behoerdeChip(key, b, '${_behoerdeLabel(b)} ($n)', selected == b);
                }),
              ],
            ),
          ),
        ...items.map<Widget>((raw) {
          final it = Map<String, dynamic>.from(raw as Map);
          final source = (it['source'] ?? '').toString();
          final fname = source == 'vermieter_mietvertrag'
              ? 'Mietvertrag #${it['mietvertrag_id']} — ${it['dokument_typ'] ?? "Dokument"}'
              : (it['filename'] ?? '?').toString();
          final kb = it['kb'] is int ? it['kb'] as int : 0;
          final behoerde = (it['behoerde'] ?? '').toString();
          final kategorie = (it['kategorie'] ?? '').toString();
          final richtung = (it['richtung'] ?? '').toString();
          // Active Widerspruchsverfahren: server marks via
          // widerspruch_eingelegt=true OR kategorie starts with
          // 'widerspruch_'. Treat as the strongest signal for the
          // Beratungshilfe operator.
          final widerspruchEingelegt = it['widerspruch_eingelegt'] == true;
          final isWiderspruch = widerspruchEingelegt
              || kategorie == 'widerspruch'
              || kategorie == 'widerspruch_bescheid'
              || kategorie == 'widerspruch_korrespondenz';
          final subline = [
            if (behoerde.isNotEmpty) behoerde,
            if (kategorie == 'widerspruch_bescheid') 'Widerspruchsverfahren · Sanktion-Bescheid',
            if (kategorie == 'widerspruch_korrespondenz') 'Widerspruchsverfahren · Korr.',
            if (kategorie == 'widerspruch') 'Widerspruch',
            if (kategorie == 'sanktion_bescheid') 'Sanktion-Bescheid',
            if (kategorie == 'sanktion_korrespondenz') 'Sanktion-Korr.',
            if (richtung.isNotEmpty) (richtung == 'ausgang' ? '→ raus' : '← rein'),
            if (it['sanktion_id'] != null) 'Sanktion #${it['sanktion_id']}',
            if (it['antrag_id'] != null) 'Antrag ${it['antrag_id']}',
            if (kb > 0) '$kb KB',
            if (it['uploaded_at'] != null) it['uploaded_at'].toString(),
          ].join(' · ');
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
            child: Row(children: [
              Icon(
                isWiderspruch ? Icons.gavel : Icons.link,
                size: 16,
                color: isWiderspruch ? F.h(Colors.deepOrange, 700) : F.h(Colors.indigo, 600),
              ),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  fname,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isWiderspruch ? F.h(Colors.deepOrange, 900) : null,
                  ),
                ),
                if (subline.isNotEmpty)
                  Text(subline, style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
              ])),
              IconButton(
                icon: Icon(Icons.visibility, size: 18, color: F.h(Colors.indigo, 600)),
                tooltip: 'Anzeigen',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () => _openRelatedDoc(source, it),
              ),
              IconButton(
                icon: Icon(Icons.download, size: 18, color: F.h(Colors.green, 700)),
                tooltip: 'Herunterladen',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () => _openRelatedDoc(source, it, openInApp: true),
              ),
            ]),
          );
        }),
        const SizedBox(height: 6),
      ]),
    );
  }

  Widget _behoerdeChip(String sectionKey, String? value, String label, bool isSelected) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: isSelected,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onSelected: (_) {
        setState(() {
          _relatedSectionFilter[sectionKey] = value;
        });
      },
      selectedColor: Colors.indigo.shade200,
      backgroundColor: F.h(Colors.grey, 100),
      labelStyle: TextStyle(
        color: isSelected ? F.h(Colors.indigo, 900) : F.h(Colors.grey, 700),
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }

  String _behoerdeLabel(String key) {
    switch (key) {
      case 'jobcenter':       return 'Jobcenter';
      case 'arbeitsagentur':  return 'Arbeitsagentur';
      case 'sozialamt':       return 'Sozialamt';
      case 'versorgungsamt':  return 'Versorgungsamt';
      case 'finanzamt':       return 'Finanzamt';
      case 'krankenkasse':    return 'Krankenkasse';
      case 'rundfunkbeitrag': return 'Rundfunkbeitrag';
      case 'rentenversicherung': return 'Rentenversicherung';
      case 'bundesagentur':   return 'Bundesagentur';
      default: return key.isEmpty ? '?' : '${key[0].toUpperCase()}${key.substring(1)}';
    }
  }

  // Pick the best human filename for a downloaded related doc. The
  // server-side endpoints decrypt the original name and put it in
  // Content-Disposition — so the network header is the source of truth.
  // Fall back to the per-item filename only if it isn't empty and
  // doesn't look like a base64 blob (encrypted leftover).
  String _bestFilename(http.Response resp, Map<String, dynamic> it, String fallback) {
    final cd = (resp.headers['content-disposition'] ?? '').toString();
    final m = RegExp(r'filename\*?=(?:UTF-8\x27\x27)?"?([^";]+)"?').firstMatch(cd);
    String name = (m?.group(1) ?? '').trim();
    if (name.isEmpty) {
      final raw = (it['filename'] ?? '').toString().trim();
      // base64-Müll erkennen: kein Punkt, nur base64-Zeichen, lang.
      final looksB64 = raw.length > 32 && !raw.contains('.') &&
          RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(raw);
      name = (raw.isEmpty || looksB64) ? fallback : raw;
    }
    // .enc-Suffix entfernen (Jobcenter-Sanktion legt das encrypted-Blob
    // mit .enc auf der Platte; der entschlüsselte Inhalt ist z. B. PDF).
    if (name.toLowerCase().endsWith('.enc')) {
      name = name.substring(0, name.length - 4);
    }
    // Filesystem-unsichere Zeichen ersetzen.
    name = name.replaceAll(RegExp(r'[<>:"|?*\\/]'), '_');
    // Wenn keine Extension erkennbar ist, eine aus mime_type ableiten.
    if (!name.contains('.')) {
      final mt = (it['mime_type'] ?? '').toString().toLowerCase();
      final ext = mt.contains('pdf') ? '.pdf'
          : mt.contains('jpeg') || mt.contains('jpg') ? '.jpg'
          : mt.contains('png') ? '.png'
          : '';
      name = '$name$ext';
    }
    return name;
  }

  Future<void> _openRelatedDoc(String source, Map<String, dynamic> it, {bool openInApp = false}) async {
    try {
      final id = it['id'] is int ? it['id'] as int : int.tryParse('${it['id']}') ?? 0;
      if (id <= 0) return;

      late final http.Response resp;
      String fallback;

      switch (source) {
        case 'behoerde_antrag':
          resp = await widget.apiService.downloadAntragDokument(id);
          fallback = 'dokument_$id.pdf';
          break;
        case 'vermieter_mietvertrag':
          resp = await widget.apiService.downloadVermieterDokument(
            dokumentId: id, userId: widget.userId);
          fallback = 'mietvertrag_${it['mietvertrag_id']}_${it['dokument_typ'] ?? "anhang"}.pdf';
          break;
        case 'jobcenter_sanktion_file':
          resp = await widget.apiService.downloadJobcenterSanktionFile(id);
          fallback = 'sanktion_${it['sanktion_id'] ?? id}_bescheid.pdf';
          break;
        case 'jobcenter_sanktion_korr':
          resp = await widget.apiService.downloadJobcenterSanktionKorrAnhang(id);
          fallback = 'sanktion_korr_$id.pdf';
          break;
        case 'arbeitsagentur_korrespondenz':
          resp = await widget.apiService.downloadAAKorrespondenzDoc(id);
          fallback = 'arbeitsagentur_korr_$id.pdf';
          break;
        case 'sozialamt_bewilligung_doc':
        case 'sozialamt_bewilligung':
          resp = await widget.apiService.downloadBewilligungDoc(id);
          fallback = 'sozialamt_bewilligung_$id.pdf';
          break;
        case 'sozialamt_antrag_doc':
        case 'sozialamt_antrag':
          resp = await widget.apiService.downloadAntragDoc(id);
          fallback = 'sozialamt_antrag_$id.pdf';
          break;
        case 'versorgungsamt_antrag_doc':
          resp = await widget.apiService.downloadVaAntragDoc(id);
          fallback = 'versorgungsamt_antrag_$id.pdf';
          break;
        case 'versorgungsamt_korr_doc':
          resp = await widget.apiService.downloadVersorgungsamtKorrDoc(id);
          fallback = 'versorgungsamt_korr_$id.pdf';
          break;
        case 'finanzamt_korrespondenz':
          resp = await widget.apiService.downloadFinanzamtKorrespondenz(id);
          fallback = 'finanzamt_$id.pdf';
          break;
        case 'krankenkasse_korrespondenz':
          resp = await widget.apiService.downloadKKKorrespondenzDoc(id);
          fallback = 'krankenkasse_$id.pdf';
          break;
        case 'rfb_antrag_doc':
          resp = await widget.apiService.downloadRfbAntragDoc(id);
          fallback = 'rundfunkbeitrag_$id.pdf';
          break;
        default:
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Source nicht unterstützt: $source'),
            ));
          }
          return;
      }

      if (resp.statusCode != 200 || !mounted) return;
      final fname = _bestFilename(resp, it, fallback);
      final dir = await getTemporaryDirectory();
      final f = sichereDatei(dir, fname);
      await f.writeAsBytes(resp.bodyBytes);
      if (openInApp) {
        await OpenFilex.open(f.path);
      } else if (mounted) {
        await FileViewerDialog.show(context, f.path, fname);
      }
    } catch (e) {
      if (mounted) dateiFehlerMelden(context, e);
    }
  }

  Widget _buildDokSection(String title, IconData icon, List<Map<String, dynamic>> docs, String kategorie, {String? hint}) {
    // ⚠️ Der Hinweis darf auf dem Telefon NICHT neben den beiden Knöpfen
    // stehen. „Aus Cloud" und „Hochladen" belegen zusammen rund 230 dp; auf
    // 360 dp bleiben dem Text keine 100 dp, und er bricht mitten im Wort
    // („Restschuldbefrei / ung") über ein Dutzend Zeilen. Auf dem Golden
    // gesehen, nicht aus dem Code geschlossen — der Analyzer meldet so etwas
    // nie. Unterhalb der Schwelle wandert er deshalb unter die Knopfzeile,
    // wo ihm die volle Breite gehört.
    const engeSchwelle = 480.0;
    Widget? hinweisZeile(bool eng) => hint == null
        ? null
        : Text(hint, style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600), fontStyle: FontStyle.italic));
    // ⚠️ Der erste Parameter heißt bewusst `_` und nicht `context`: sonst
    // verdeckt er `State.context`, und die vier `mounted`-Prüfungen weiter
    // unten gelten plötzlich für einen anderen BuildContext — der Analyzer
    // meldet das als `use_build_context_synchronously`.
    return LayoutBuilder(builder: (_, c) {
      final eng = c.maxWidth < engeSchwelle;
      return Container(margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(color: F.flaeche, borderRadius: BorderRadius.circular(10), border: Border.all(color: F.h(widget.color, 200))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(color: F.h(widget.color, 50), borderRadius: const BorderRadius.vertical(top: Radius.circular(10))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 18, color: F.h(widget.color, 700)),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$title (${docs.length})', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: F.h(widget.color, 800))),
              if (!eng && hint != null) hinweisZeile(false)!,
            ])),
            OutlinedButton.icon(
              onPressed: () async {
                final res = await CloudPickerHelper.uebernehmen(context, apiService: widget.apiService, memberId: widget.userId,
                    allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
                    attach: (id) => widget.apiService.attachGerichtVorfallDocFromCloud(vorfallId: widget.vorfallId, cloudFileId: id, kategorie: kategorie),
                hochladen: (r) => _uploadDoc(kategorie, ausCloud: r));
                if (res != null && mounted) { _load(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${res.ok} von ${res.total} aus Cloud übernommen'), backgroundColor: res.ok == res.total ? Colors.green : Colors.orange)); }
              },
              icon: const Icon(Icons.cloud_download, size: 14),
              label: const Text('Aus Cloud', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(foregroundColor: F.h(Colors.blue, 700), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
            ),
            const SizedBox(width: 6),
            ElevatedButton.icon(
              onPressed: () => _uploadDoc(kategorie),
              icon: const Icon(Icons.upload_file, size: 14),
              label: const Text('Hochladen', style: TextStyle(fontSize: 11)),
              style: ElevatedButton.styleFrom(backgroundColor: widget.color, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
            ),
          ]),
          if (eng && hint != null) ...[
            const SizedBox(height: 6),
            hinweisZeile(true)!,
          ],
        ])),
        if (docs.isEmpty) Padding(padding: const EdgeInsets.all(16),
          child: Row(children: [
            Icon(Icons.inbox, size: 18, color: F.h(Colors.grey, 400)),
            const SizedBox(width: 8),
            Text('Keine Dokumente', style: TextStyle(color: F.h(Colors.grey, 500), fontSize: 12)),
          ])),
        ...docs.map((d) => Padding(padding: const EdgeInsets.fromLTRB(12, 4, 8, 4), child: Row(children: [
          Icon(Icons.attach_file, size: 16, color: F.h(widget.color, 700)), const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d['datei_name']?.toString() ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            if ((d['created_at']?.toString() ?? '').isNotEmpty) Text(d['created_at'].toString(), style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
          ])),
          IconButton(icon: Icon(Icons.visibility, size: 18, color: F.h(Colors.indigo, 600)), tooltip: 'Anzeigen', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: () async {
            try { final resp = await widget.apiService.downloadGerichtVorfallDoc(d['id'] as int); if (resp.statusCode == 200 && mounted) { final dir = await getTemporaryDirectory(); final file = sichereDatei(dir, d['datei_name']); await file.writeAsBytes(resp.bodyBytes); if (mounted) await FileViewerDialog.show(context, file.path, d['datei_name']?.toString() ?? ''); } } catch (e) { if (mounted) dateiFehlerMelden(context, e); }
          }),
          IconButton(icon: Icon(Icons.download, size: 18, color: F.h(Colors.green, 700)), tooltip: 'Herunterladen', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: () async {
            try {
              // Herunterladen heisst behalten — vorher ging die Datei nur ins
              // Temp-Verzeichnis und von dort an eine fremde App.
              final resp = await widget.apiService.downloadGerichtVorfallDoc(d['id'] as int);
              if (resp.statusCode != 200) return;
              final saved = await FilePickerHelper.saveBytes(
                bytes: resp.bodyBytes,
                fileName: d['datei_name']?.toString() ?? 'dokument',
                dialogTitle: 'Dokument speichern',
              );
              if (saved == null || !mounted) return; // abgebrochen
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Gespeichert: $saved'), backgroundColor: Colors.green),
              );
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Download fehlgeschlagen: $e'), backgroundColor: Colors.red),
                );
              }
            }
          }),
          IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400), tooltip: 'Löschen', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: () async {
            await widget.apiService.deleteGerichtVorfallDoc(d['id'] as int); _load();
          }),
        ]))),
        const SizedBox(height: 6),
      ]),
      );
    });
  }

  Future<void> _uploadDoc(String kategorie, {FilePickerResult? ausCloud}) async {
    final result = ausCloud ?? await FilePickerHelper.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'], allowMultiple: true);
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
        Expanded(child: Text('${_termine.length} Termine', style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600)))),
        FilledButton.icon(icon: const Icon(Icons.add, size: 14), label: const Text('Neuer Termin', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: widget.color, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: _addTermin),
      ])),
      Expanded(child: _termine.isEmpty ? Center(child: Text('Keine Termine', style: TextStyle(color: F.h(Colors.grey, 500))))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _termine.length, itemBuilder: (_, i) {
            final t = _termine[i];
            return Card(child: ListTile(
              leading: Icon(Icons.event, color: F.h(widget.color, 700)),
              title: Text('${t['datum'] ?? ''}${(t['uhrzeit']?.toString() ?? '').isNotEmpty ? ' um ${t['uhrzeit']}' : ''}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if ((t['ort']?.toString() ?? '').isNotEmpty) Text(t['ort'].toString(), style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
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
      decoration: BoxDecoration(color: F.h(c, 50), borderRadius: BorderRadius.circular(10), border: Border.all(color: F.h(c, 300), width: 1)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(_methodeIcon(methode), size: 11, color: F.h(c, 700)),
        const SizedBox(width: 3),
        Text(_methodeLabel(methode), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: F.h(c, 800))),
      ]),
    );
  }

  /// Accepts both German (dd.mm.yyyy) and ISO (yyyy-mm-dd[ HH:mm:ss])
  /// formats. Returns null when the input is empty or unparseable so the
  /// sort can push those entries to the bottom.
  DateTime? _parseDatum(String? s) {
    if (s == null) return null;
    final t = s.trim();
    if (t.isEmpty) return null;
    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(t);
    if (iso != null) {
      try {
        return DateTime(
          int.parse(iso.group(1)!), int.parse(iso.group(2)!), int.parse(iso.group(3)!),
        );
      } catch (_) {}
    }
    final de = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})').firstMatch(t);
    if (de != null) {
      try {
        return DateTime(
          int.parse(de.group(3)!), int.parse(de.group(2)!), int.parse(de.group(1)!),
        );
      } catch (_) {}
    }
    return null;
  }

  Widget _buildKorrespondenz() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Expanded(child: Text('${_korr.length} Einträge', style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600)))),
        FilledButton.icon(icon: const Icon(Icons.call_received, size: 14), label: const Text('Eingang', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.green.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _addKorr('eingang')),
        const SizedBox(width: 6),
        FilledButton.icon(icon: const Icon(Icons.call_made, size: 14), label: const Text('Ausgang', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _addKorr('ausgang')),
      ])),
      Expanded(child: _korr.isEmpty ? Center(child: Text('Keine Korrespondenz', style: TextStyle(color: F.h(Colors.grey, 500))))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _korr.length, itemBuilder: (_, i) {
            final k = _korr[i]; final isEin = k['richtung'] == 'eingang';
            final methode = k['methode']?.toString() ?? '';
            return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: F.flaeche, borderRadius: BorderRadius.circular(8), border: Border.all(color: isEin ? F.h(Colors.green, 200) : F.h(Colors.blue, 200))),
              child: Row(children: [
                Icon(isEin ? Icons.call_received : Icons.call_made, size: 18, color: isEin ? F.h(Colors.green, 700) : F.h(Colors.blue, 700)), const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Text(k['betreff']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isEin ? F.h(Colors.green, 800) : F.h(Colors.blue, 800)))),
                    if (methode.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 4), child: _methodeBadge(methode)),
                  ]),
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(Icons.calendar_today, size: 11, color: F.h(Colors.grey, 500)),
                    const SizedBox(width: 4),
                    Text(k['datum']?.toString() ?? '', style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
                  ]),
                  if ((k['notiz']?.toString() ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4),
                    child: Text(k['notiz'].toString(), style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700)))),
                  if (k['id'] != null) Padding(padding: const EdgeInsets.only(top: 4),
                    child: KorrAttachmentsWidget(apiService: widget.apiService, modul: 'gericht_vorfall', korrespondenzId: k['id'] as int, memberId: widget.userId)),
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
        Icon(richtung == 'eingang' ? Icons.call_received : Icons.call_made, size: 18, color: richtung == 'eingang' ? F.h(Colors.green, 700) : F.h(Colors.blue, 700)),
        const SizedBox(width: 8),
        Text(richtung == 'eingang' ? 'Eingang' : 'Ausgang', style: const TextStyle(fontSize: 14)),
      ]),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final m in [('email', 'E-Mail', Icons.email), ('post', 'Post', Icons.mail), ('online', 'Online', Icons.language), ('persoenlich', 'Persönlich', Icons.person), ('fax', 'Fax', Icons.fax), ('telefon', 'Telefon', Icons.phone)])
            ChoiceChip(label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(m.$3, size: 13, color: methode == m.$1 ? Colors.white : F.h(Colors.grey, 700)), const SizedBox(width: 4), Text(m.$2, style: TextStyle(fontSize: 10, color: methode == m.$1 ? Colors.white : F.h(Colors.grey, 700)))]),
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
        OutlinedButton.icon(icon: Icon(Icons.attach_file, size: 16, color: F.h(Colors.teal, 600)),
          label: Text(files.isEmpty ? 'Dokumente anhängen' : '${files.length} Datei(en)', style: TextStyle(fontSize: 12, color: F.h(Colors.teal, 700))),
          style: OutlinedButton.styleFrom(side: BorderSide(color: F.h(Colors.teal, 300))),
          onPressed: () async {
            final r = await FilePickerHelper.pickFiles(allowMultiple: true, type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
            if (r != null) setDlg(() { files.addAll(r.files); if (files.length > 20) files = files.sublist(0, 20); });
          }),
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
        Text('Kein Datum vorhanden', style: TextStyle(fontSize: 14, color: F.h(Colors.grey, 600))),
        Text('Bitte Datum im Vorfall eintragen.', style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 500))),
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
        decoration: BoxDecoration(color: F.h(statusColor, 50), borderRadius: BorderRadius.circular(12), border: Border.all(color: F.h(statusColor, 300), width: 2)),
        child: Row(children: [
          Icon(hatWiderspruch ? Icons.gavel : abgelaufen ? Icons.cancel : Icons.timer, size: 28, color: F.h(statusColor, 700)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(hatWiderspruch
                ? 'Widerspruch eingelegt${widerspruchDatum != null ? ' am ${fmt(widerspruchDatum)}' : ''}'
                : abgelaufen ? 'Frist abgelaufen seit ${-restTage} Tagen' : '$restTage Tage verbleibend',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: F.h(statusColor, 800))),
            if (hatWiderspruch) Text('Status: ${_sLabel(status)}', style: TextStyle(fontSize: 12, color: F.h(statusColor, 700)))
            else if (!abgelaufen) Text('Fristende: ${fmt(fristEnde)}', style: TextStyle(fontSize: 12, color: F.h(statusColor, 700))),
          ])),
        ]),
      ),
      const SizedBox(height: 16),

      // Unified chronological timeline
      Text('Chronologie', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: F.h(Colors.grey, 800))),
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
            decoration: BoxDecoration(color: F.h(stColor, 50), borderRadius: BorderRadius.circular(10), border: Border.all(color: F.h(stColor, 300), width: 2)),
            child: Row(children: [
              Icon(Icons.lock, size: 20, color: F.h(stColor, 700)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Widerspruch abgeschlossen', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: F.h(stColor, 800))),
                Text('Status: $stLabel', style: TextStyle(fontSize: 12, color: F.h(stColor, 700))),
                if (status == 'bewilligt') Text('→ Weiter zum Tab „Klage"', style: TextStyle(fontSize: 11, color: F.h(Colors.blue, 700), fontStyle: FontStyle.italic)),
              ])),
            ]));
        }
        return Container(width: double.infinity, padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: F.h(Colors.purple, 50), borderRadius: BorderRadius.circular(10), border: Border.all(color: F.h(Colors.purple, 200))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Widerspruch-Status', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: F.h(Colors.purple, 800))),
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
          decoration: BoxDecoration(color: F.h(Colors.blue, 50), borderRadius: BorderRadius.circular(10), border: Border.all(color: F.h(Colors.blue, 200))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(Icons.timer, size: 20, color: F.h(Colors.blue, 700)), const SizedBox(width: 8),
              Text('Erwartete Wartezeit', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: F.h(Colors.blue, 800)))]),
            const SizedBox(height: 6),
            Text(_getWartezeit(widget.gerichtTyp, titel), style: TextStyle(fontSize: 12, color: F.h(Colors.blue, 900))),
          ]),
        ),
        if (widget.gerichtTyp == 'sozialgericht') ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity, padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: F.h(Colors.amber, 50), borderRadius: BorderRadius.circular(8), border: Border.all(color: F.h(Colors.amber, 200))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.lightbulb, size: 16, color: F.h(Colors.amber, 700)), const SizedBox(width: 8),
              Expanded(child: Text('Nach 3 Monaten ohne Antwort: Untätigkeitsklage nach § 88 SGG möglich.', style: TextStyle(fontSize: 11, color: F.h(Colors.amber, 900)))),
            ]),
          ),
        ],
      ],
      const SizedBox(height: 16),

      // Rechtsgrundlage
      Container(
        width: double.infinity, padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: F.h(Colors.grey, 50), borderRadius: BorderRadius.circular(10), border: Border.all(color: F.h(Colors.grey, 300))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Rechtsgrundlage', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: F.h(Colors.grey, 700))),
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
          Icon(Icons.gavel, color: F.h(widget.color, 700), size: 22), const SizedBox(width: 8),
          Text(step == 0 ? 'Widerspruch eingelegt?' : step == 1 ? 'Versandart' : 'Wartezeit', style: TextStyle(fontSize: 16, color: F.h(widget.color, 700))),
        ]),
        content: SizedBox(width: 460, child: step == 0
          // Step 1: Wurde Widerspruch eingelegt?
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Wurde der Widerspruch / das Rechtsmittel bereits eingelegt?', style: TextStyle(fontSize: 14, color: F.h(Colors.grey, 800))),
              const SizedBox(height: 8),
              Text('Frist: ${frist.tage} Tage — ${frist.beschreibung}', style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600))),
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
              Text('Wie wurde der Widerspruch eingereicht?', style: TextStyle(fontSize: 14, color: F.h(Colors.grey, 800))),
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
                  decoration: BoxDecoration(color: versandart == m.$1 ? F.h(widget.color, 50) : F.flaeche, borderRadius: BorderRadius.circular(10), border: Border.all(color: versandart == m.$1 ? widget.color.shade400 : F.h(Colors.grey, 300))),
                  child: Row(children: [
                    Icon(m.$3, size: 20, color: F.h(widget.color, 600)), const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(m.$2, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: F.h(Colors.grey, 800))),
                      Text(m.$4, style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600), fontStyle: FontStyle.italic)),
                    ])),
                  ]),
                ),
              )),
            ])
          // Step 3: Wartezeit
          : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: double.infinity, padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: F.h(Colors.green, 50), borderRadius: BorderRadius.circular(10), border: Border.all(color: F.h(Colors.green, 300))),
                child: Row(children: [
                  Icon(Icons.check_circle, size: 24, color: F.h(Colors.green, 700)), const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Widerspruch eingelegt am ${widerspruchDatumC.text}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: F.h(Colors.green, 800))),
                    Text('Versand: ${{'post': 'Per Post', 'fax': 'Per Fax', 'persoenlich': 'Persönlich', 'elektronisch': 'Elektronisch'}[versandart] ?? versandart}', style: TextStyle(fontSize: 11, color: F.h(Colors.green, 700))),
                  ])),
                ]),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity, padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: F.h(Colors.blue, 50), borderRadius: BorderRadius.circular(10), border: Border.all(color: F.h(Colors.blue, 200))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.timer, size: 20, color: F.h(Colors.blue, 700)), const SizedBox(width: 8),
                    Text('Erwartete Wartezeit', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: F.h(Colors.blue, 800))),
                  ]),
                  const SizedBox(height: 6),
                  Text(_getWartezeit(widget.gerichtTyp, titel), style: TextStyle(fontSize: 12, color: F.h(Colors.blue, 900))),
                ]),
              ),
              if (widget.gerichtTyp == 'sozialgericht') ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: F.h(Colors.amber, 50), borderRadius: BorderRadius.circular(8), border: Border.all(color: F.h(Colors.amber, 200))),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.lightbulb, size: 16, color: F.h(Colors.amber, 700)), const SizedBox(width: 8),
                    Expanded(child: Text('Tipp: Nach 3 Monaten ohne Antwort können Sie eine Untätigkeitsklage nach § 88 SGG erheben.', style: TextStyle(fontSize: 11, color: F.h(Colors.amber, 900)))),
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
        // ⚠️ Der Verlauf ist die Chronik der Akte. Stünde hier für einen
        // Beschluss „Sonstiges", würde die Zeile, auf die es ankommt, im
        // Protokoll unsichtbar.
        final kategorieLabel = kGerichtVorfallDokKategorien[kategorie] ?? 'Sonstiges';
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
        Icon(Icons.timeline, color: F.h(widget.color, 700)), const SizedBox(width: 8),
        Text('Verlauf — Chronologisch (${items.length})', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: F.h(widget.color, 800))),
      ])),
      Expanded(child: items.isEmpty ? Center(child: Text('Kein Verlauf', style: TextStyle(color: F.h(Colors.grey, 500))))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: items.length, itemBuilder: (_, i) {
            final e = items[i];
            return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 30, child: Column(children: [
                Container(width: 24, height: 24, decoration: BoxDecoration(color: e.$5.shade100, shape: BoxShape.circle, border: Border.all(color: e.$5.shade400, width: 2)),
                  child: Icon(e.$2, size: 12, color: e.$5.shade700)),
                if (i < items.length - 1) Expanded(child: Container(width: 2, color: F.h(Colors.grey, 300))),
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
            decoration: BoxDecoration(color: F.h(Colors.grey, 50), borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              Icon(Icons.balance, size: 48, color: F.h(Colors.grey, 300)),
              const SizedBox(height: 8),
              Text('Keine Klage erforderlich', style: TextStyle(fontSize: 14, color: F.h(Colors.grey, 500))),
              const SizedBox(height: 4),
              Text('Eine Klage wird erst relevant wenn der Widerspruch bewilligt/akzeptiert wurde.', style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 400)), textAlign: TextAlign.center),
            ])),
        ] else ...[
          Text('Klage', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: F.h(Colors.indigo, 800))),
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
          Text('Klage-Status', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: F.h(Colors.indigo, 700))),
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
            Text('Chronologie', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: F.h(Colors.grey, 700))),
            const SizedBox(height: 8),
            ...klageVerlauf.map((e) {
              final st = e['status']?.toString() ?? '';
              final stColor = klageStatusColors[st] ?? Colors.grey;
              return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: F.h(stColor, 50), borderRadius: BorderRadius.circular(8), border: Border.all(color: F.h(stColor, 200))),
                child: Row(children: [
                  Icon(Icons.circle, size: 10, color: F.h(stColor, 600)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(klageStatusLabels[st] ?? st, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: F.h(stColor, 800)))),
                  Text('${e['datum'] ?? ''} ${e['zeit'] ?? ''}', style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
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
        if (hasLine) Container(width: 2, height: 28, color: F.h(Colors.grey, 300)),
      ]),
      const SizedBox(width: 12),
      Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color))), Text(date, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: F.h(Colors.grey, 700)))]),
        if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle, style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600), fontStyle: FontStyle.italic))),
      ]))),
    ]);
  }

  Widget _lawRow(String paragraph, String text) {
    return Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: F.h(Colors.indigo, 50), borderRadius: BorderRadius.circular(4)),
        child: Text(paragraph, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: F.h(Colors.indigo, 700)))),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700)))),
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
          final f = sichereDatei(dir, 'Anregung_Betreuung_$ts.pdf');
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
      Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: F.h(widget.color, 800))),
    ]));

  Widget _info(String label, String? value) {
    final v = (value ?? '').trim();
    return Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [
      SizedBox(width: 140, child: Text(label, style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700)))),
      Expanded(child: Text(v.isEmpty ? '—' : v, style: TextStyle(fontSize: 12, color: v.isEmpty ? F.h(Colors.grey, 400) : null))),
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
              backgroundColor: F.h(widget.color, 100),
              foregroundColor: F.h(widget.color, 900),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            ),
          )),
      ]),
      if (helpHint != null) Padding(padding: const EdgeInsets.only(left: 4, top: 2),
        child: Text(helpHint, style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600), fontStyle: FontStyle.italic))),
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
        decoration: BoxDecoration(color: F.h(widget.color, 50), borderRadius: BorderRadius.circular(8), border: Border.all(color: F.h(widget.color, 200))),
        child: Row(children: [
          Icon(Icons.gavel, color: F.h(widget.color, 700), size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(
            'Anregung zur Bestellung eines Betreuers — Vordruck Bayerisches Staatsministerium der Justiz, einzureichen bei Amtsgericht Neu-Ulm (Betreuungsgericht).',
            style: TextStyle(fontSize: 11, color: F.h(widget.color, 900)))),
        ])),
      const SizedBox(height: 14),
      if (!hasVormund) Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: F.h(Colors.orange, 50), borderRadius: BorderRadius.circular(8), border: Border.all(color: F.h(Colors.orange, 200))),
        child: Row(children: [
          Icon(Icons.warning_amber, color: F.h(Colors.orange, 700)),
          const SizedBox(width: 8),
          Expanded(child: Text(
            'Dieses Mitglied hat keinen Vormund verknüpft. Der Antragsteller (Absender) kann nicht automatisch befüllt werden. Bitte zuerst unter dem Vormund-Konto eine Verknüpfung anlegen.',
            style: TextStyle(fontSize: 12, color: F.h(Colors.orange, 900)))),
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
        Icon(Icons.person_search, color: F.h(Colors.indigo, 700), size: 22),
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
          ? Center(child: Text(_searching ? '' : 'Geben Sie Name oder Nummer ein und suchen.', style: TextStyle(color: F.h(Colors.grey, 500), fontSize: 12)))
          : ListView.separated(
              itemCount: _candidates.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: F.h(Colors.grey, 200)),
              itemBuilder: (lctx, i) {
                final c = _candidates[i];
                final adr = '${c['strasse'] ?? ''} ${c['hausnummer'] ?? ''}, ${c['plz'] ?? ''} ${c['ort'] ?? ''}'.trim();
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(backgroundColor: F.h(Colors.indigo, 50), child: Icon(Icons.person, color: F.h(Colors.indigo, 700), size: 18)),
                  title: Text('${c['vorname'] ?? ''} ${c['nachname'] ?? ''}'.trim(),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Nr. ${c['mitgliedernummer'] ?? '#${c['id']}'} · ${c['role'] ?? ''}', style: const TextStyle(fontSize: 10)),
                    if (adr.length > 2) Text(adr, style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
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
// via /api/admin/beratungshilfe_pdf.php (pdfcpu form fill).
// ═══════════════════════════════════════════════════════
class _BeratungshilfeGeneratorTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int vorfallId;
  final Map<String, dynamic> vorfall;
  final String userName;
  final String userNachname;
  final MaterialColor color;
  // Fired after a freshly generated PDF was uploaded to the Vorfall's
  // 'antrag' bucket — parent reloads its docs list so the new file
  // shows up in the Dokumente tab right away.
  final VoidCallback? onAntragUploaded;
  const _BeratungshilfeGeneratorTab({
    required this.apiService,
    required this.userId,
    required this.vorfallId,
    required this.vorfall,
    required this.userName,
    required this.userNachname,
    required this.color,
    this.onAntragUploaded,
  });
  @override
  State<_BeratungshilfeGeneratorTab> createState() => _BeratungshilfeGeneratorTabState();
}

class _BeratungshilfeGeneratorTabState extends State<_BeratungshilfeGeneratorTab> {
  bool _loading = true;
  bool _generating = false;
  String? _lastError;
  String? _lastGeneratedPath;
  String? _lastFileName;
  Uint8List? _lastBytes;

  /// Die Kopie oben liegt dort, wo die App schreiben darf (und von wo sie in
  /// die Vorfall-Akte hochgeladen wird). Damit der Nutzer den Antrag behalten
  /// kann, führt kein Weg an der Systemauswahl vorbei.
  Future<void> _saveGeneratedPdf() async {
    final bytes = _lastBytes;
    final name = _lastFileName;
    if (bytes == null || name == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = await FilePickerHelper.saveBytes(
        bytes: bytes,
        fileName: name,
        dialogTitle: 'PDF speichern',
      );
      if (saved == null) return; // abgebrochen
      messenger.showSnackBar(SnackBar(content: Text('Gespeichert: $saved'), backgroundColor: Colors.green));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: $e'), backgroundColor: Colors.red));
    }
  }

  // Pre-filled from user master row
  Map<String, dynamic> _user = {};

  // Court catalogue + selection — every Amtsgericht has its own address
  // that the form's "Name des Amtsgerichts" + "Postleitzahl Ort" fields
  // get filled with. Loaded from gericht_datenbank where
  // gericht_typ = 'beratungshilfe'.
  List<Map<String, dynamic>> _gerichte = [];
  Map<String, dynamic>? _selectedGericht;

  // Auto-detected from /api/admin/beratungshilfe_sources.php — drives
  // the Motiv dropdown and the Beruf = arbeitslos override.
  bool _isArbeitslos = false;
  String? _arbeitslosQuelle;
  List<Map<String, dynamic>> _motiveOptions = [];

  // Motiv: 'free' = operator types the Sachverhalt manually; any other
  // value = id of a motive_options row (jobcenter_sanktion_<id> etc.).
  String _selectedMotivId = 'free';
  final _sachverhaltC = TextEditingController();

  // Section B of the Antrag: 4 declarations the applicant signs.
  // B1 (Rechtsschutzversicherung): operator toggles based on what
  //     the member has on file. Default = false (most members don't).
  // B2/B3/B4 are virtually always true for our flow — kept as
  //     constants but exposed should the operator ever need to flip.
  bool _hasRechtsschutz = false;
  static const bool _bKeineMoeglichkeit = true;
  static const bool _bNichtBewilligt    = true;
  static const bool _bKeinGerichtlich   = true;

  // Section C input: operator types the Auszahlbetrag 1:1 from the
  // Bürgergeld-Bescheid the member shows. C1 (Brutto) = C2 (Netto)
  // for Bürgergeld since no Steuern/Sozialversicherung are withheld.
  final _auszahlbetragC = TextEditingController();

  // Section D inputs: pre-filled from the most recent aktiver Mietvertrag
  // (vermieter_mietvertraege via beratungshilfe_sources.php > wohnung).
  // Operator can still override before generating.
  final _wohnflaecheC = TextEditingController();
  final _warmmieteC   = TextEditingController();
  // D3 — "Von den gesamten Wohnkosten zahle ich: ___ EUR". Defaults to
  // the same value as Warmmiete (D2), because the applicant is the
  // sole tenant on the Mietvertrag and pays the rent in full (even
  // when Jobcenter reimburses KdU later). Operator can override.
  final _wohnkostenAnteilC = TextEditingController();
  String? _wohnungAdresse; // caption-only hint, not in PDF payload
  int _kinderAnzahl = 0;   // Bedarfsgemeinschaft size driver for D5/D6

  // Section F — Bankkonten (aus Finanzen-Modul). When the member has
  // a bank row, F1-Konten2 + F1-InhaberA + F3-Bank1 are auto-filled.
  bool _hatBankkonten = false;
  String? _bankName;
  String? _bankIban;
  String? _bankKontoart;

  // Tab now exposes: Amtsgericht selector + auto-arbeitslos banner +
  // Motiv dropdown (auto-detected aus Jobcenter Sanktion / Widerspruch,
  // oder freier Text) + Auszahlbetrag aus Bescheid.
  // Sachverhalt-Text wird mit dem ausgewählten Motiv vorbefüllt.

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _sachverhaltC.dispose();
    _auszahlbetragC.dispose();
    _wohnflaecheC.dispose();
    _warmmieteC.dispose();
    _wohnkostenAnteilC.dispose();
    super.dispose();
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
    // Auto-detection: arbeitslos status + Motiv-Vorschläge from other
    // Behörden-Akten (Jobcenter, Arbeitsagentur, Sanktionen).
    try {
      final s = await widget.apiService.getBeratungshilfeSources(widget.userId);
      if (s != null) {
        _isArbeitslos = s['is_arbeitslos'] == true;
        _arbeitslosQuelle = s['arbeitslos_quelle']?.toString();
        _motiveOptions = ((s['motive_options'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        if (_motiveOptions.isNotEmpty) {
          _selectedMotivId = _motiveOptions.first['id'].toString();
          _sachverhaltC.text = _motiveOptions.first['text']?.toString() ?? '';
        }
        // Auszahlbetrag pre-fill from Jobcenter bescheid_betrag.
        final betrag = s['auszahlbetrag']?.toString();
        if (betrag != null && betrag.isNotEmpty) {
          _auszahlbetragC.text = betrag;
        }
        // Section D pre-fill from the most recent aktiver Mietvertrag.
        final wohnung = s['wohnung'];
        if (wohnung is Map) {
          final w = Map<String, dynamic>.from(wohnung);
          final qm = w['wohnflaeche_qm']?.toString();
          final warm = w['warmmiete']?.toString();
          final adr = w['adresse']?.toString();
          if (qm != null && qm.isNotEmpty) _wohnflaecheC.text = qm;
          if (warm != null && warm.isNotEmpty) {
            _warmmieteC.text = warm;
            // D3 = D2 by default (applicant pays the full rent).
            _wohnkostenAnteilC.text = warm;
          }
          if (adr != null && adr.isNotEmpty) _wohnungAdresse = adr;
          final ka = w['kinder_anzahl'];
          if (ka is int) {
            _kinderAnzahl = ka;
          } else if (ka != null) {
            _kinderAnzahl = int.tryParse(ka.toString()) ?? 0;
          }
        }
        // Section F — bank block from Finanzen-Modul.
        final bank = s['bank'];
        if (bank is Map) {
          final b = Map<String, dynamic>.from(bank);
          _hatBankkonten = b['hat_bankkonten'] == true;
          _bankName     = b['name']?.toString();
          _bankIban     = b['iban']?.toString();
          _bankKontoart = b['kontoart']?.toString();
        }
      }
    } catch (_) {}
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

  /// Extract just the city ("Ulm") from a court-address line. The PDF
  /// already prints "An das Amtsgericht" before the field, so we don't
  /// want to write "Amtsgericht Ulm" there — the result would read
  /// "An das Amtsgericht Amtsgericht Ulm".
  String _ortFromAddress(String addr) {
    final m = RegExp(r'\d{5}\s+([A-Za-zÄÖÜäöüß\-]+)').firstMatch(addr);
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
    final addr = (g['adresse'] ?? '').toString();
    // City-only for "An das Amtsgericht ___" — full name would
    // duplicate the printed prefix.
    final ort = _ortFromAddress(addr);
    final sachverhalt = _sachverhaltC.text.trim();
    final payload = <String, dynamic>{
      'ort': ort,                                       // → "Name des Amtsgerichts"
      'amtsgericht': (g['name'] ?? '').toString(),      // fallback / audit
      'amtsgericht_plz_ort': _plzOrtFromAddress(addr),
      'pdf_template': (g['pdf_template'] ?? '').toString(),
      'antragsteller': _antragsteller(),
      // Beruf: arbeitslos override is set server-side from this flag
      // (auto-detected via Jobcenter / Arbeitsagentur sources).
      'beruf': _isArbeitslos ? 'arbeitslos' : (_user['beruf'] ?? '').toString(),
      'beruf_arbeitslos': _isArbeitslos,
      'geburtsdatum': (_user['geburtsdatum'] ?? '').toString(),
      'familienstand': (_user['familienstand'] ?? '').toString(),
      'anschrift': _anschrift(),
      // telefon intentionally not sent — operator-side decision.
      'sachverhalt': sachverhalt,
      // Section B declarations: B1 driven by the operator toggle,
      // B2/B3/B4 are constants for our flow (no other free help, never
      // applied for Beratungshilfe in this matter, no court case yet).
      'keine_rechtsschutz': !_hasRechtsschutz,
      'keine_moeglichkeit': _bKeineMoeglichkeit,
      'nicht_bewilligt':    _bNichtBewilligt,
      'kein_gerichtlich':   _bKeinGerichtlich,
      // Section C — Bescheid 1:1: Auszahlbetrag → both C1 (Brutto) and
      // C2 (Netto). Bürgergeld hat keine Abzüge.
      'brutto': _auszahlbetragC.text.trim(),
      'netto':  _auszahlbetragC.text.trim(),
      // Section D — Wohnung. Pre-fill from active Mietvertrag,
      // operator can override. wohnkosten = Warmmiete (= Kalt + NK
      // + Heizung) total monthly rent including everything;
      // wohnkosten_anteil (D3) = the part the applicant pays out of
      // pocket (0 € for full-Bürgergeld recipients).
      'wohnung_groesse':    _wohnflaecheC.text.trim(),
      'wohnkosten':         _warmmieteC.text.trim(),
      'wohnkosten_anteil':  _wohnkostenAnteilC.text.trim(),
      // D4/D5/D6: if the member has Kinder/Familienangehörige linked
      // via vormund_user_id, mark "gemeinsam bewohnt" + write the
      // count into D6 ("weitere Personen"). Otherwise allein.
      'allein_bewohner': _kinderAnzahl == 0,
      'mit_bewohner':    _kinderAnzahl > 0 ? '$_kinderAnzahl' : '',
      // Section F — Bankkonten. Server flips F1-Konten2 +
      // F1-InhaberA automatically when hat_bankkonten=true; F3-Bank1
      // is bank_name.
      'hat_bankkonten': _hatBankkonten,
      'bank_name':      _bankName ?? '',
    };
    try {
      final bytes = await widget.apiService.generateBeratungshilfePdf(payload);
      if (!mounted) return;
      if (bytes == null) {
        setState(() {
          _generating = false;
          _lastError = 'Server lieferte kein PDF zurück. pdfcpu- oder Template-Fehler — Logs prüfen.';
        });
        return;
      }
      Directory? dir;
      try { dir = await getDownloadsDirectory(); } catch (_) {}
      dir ??= await getApplicationDocumentsDirectory().catchError((_) => Directory.systemTemp);
      final ts = DateTime.now().toIso8601String().substring(0, 19).replaceAll(':', '-');
      final filename = 'Beratungshilfe_Antrag_${widget.userId}_${widget.vorfallId}_$ts.pdf';
      final path = '${dir.path}${Platform.pathSeparator}$filename';
      await File(path).writeAsBytes(bytes);

      // Auto-upload to the Vorfall's Dokumente tab (kategorie='antrag')
      // so the operator finds the generated Antrag listed there next
      // time they open the tab — no manual re-upload needed.
      String uploadHint = '';
      try {
        final r = await widget.apiService.uploadGerichtVorfallDoc(
          vorfallId: widget.vorfallId,
          filePath: path,
          fileName: filename,
          kategorie: 'antrag',
        );
        if (r['success'] == true) {
          uploadHint = ' · zur Vorfall-Akte unter „Antrag" hinzugefügt';
          widget.onAntragUploaded?.call();
        } else {
          uploadHint = ' · Upload-Fehler: ${r['message'] ?? "unbekannt"}';
        }
      } catch (e) {
        uploadHint = ' · Upload-Fehler: $e';
      }

      if (!mounted) return;
      setState(() {
        _generating = false;
        _lastGeneratedPath = path;
        _lastFileName = filename;
        _lastBytes = Uint8List.fromList(bytes);
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('PDF erstellt$uploadHint'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 5),
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
    return SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(Icons.picture_as_pdf, color: F.h(c, 700)),
        const SizedBox(width: 8),
        const Expanded(child: Text('Beratungshilfe-Antrag generieren',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
      ]),
      const SizedBox(height: 16),

      // Single court → no dropdown needed; multiple → pick one.
      if (_gerichte.isEmpty)
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: F.h(Colors.amber, 50), borderRadius: BorderRadius.circular(6), border: Border.all(color: F.h(Colors.amber, 300))),
          child: Row(children: [
            Icon(Icons.warning_amber, size: 18, color: F.h(Colors.amber, 800)),
            const SizedBox(width: 8),
            Expanded(child: Text('Kein Amtsgericht für Beratungshilfe in der Datenbank.',
              style: TextStyle(fontSize: 12, color: F.h(Colors.amber, 900)))),
          ]),
        )
      else if (_gerichte.length == 1)
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: F.h(c, 50), borderRadius: BorderRadius.circular(6), border: Border.all(color: F.h(c, 300))),
          child: Row(children: [
            Icon(Icons.account_balance, size: 18, color: F.h(c, 700)),
            const SizedBox(width: 8),
            Expanded(child: Text((_selectedGericht?['name'] ?? '').toString(),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: F.h(c, 800)))),
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
            prefixIcon: Icon(Icons.account_balance, size: 18, color: F.h(c, 700)),
          ),
          items: _gerichte.map((g) => DropdownMenuItem(
            value: g,
            child: Text((g['name'] ?? '').toString(),
              style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: (v) => setState(() => _selectedGericht = v),
        ),

      // Auto-detected arbeitslos indicator
      if (_isArbeitslos) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: F.h(Colors.green, 50),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: F.h(Colors.green, 300)),
          ),
          child: Row(children: [
            Icon(Icons.check_circle, color: F.h(Colors.green, 700), size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(
              'Beruf wird automatisch auf "arbeitslos" gesetzt — Quelle: '
              '${_arbeitslosQuelle == "jobcenter" ? "Jobcenter (Hartz IV bewilligt)" : "Arbeitsagentur (ALG bewilligt)"}.',
              style: TextStyle(fontSize: 11, color: F.h(Colors.green, 900)),
            )),
          ]),
        ),
      ],

      // Abschnitt A — Sachverhalt (Motiv-Vorschlag + Freitext)
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: F.h(Colors.teal, 50),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: F.h(Colors.teal, 300)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.subject, size: 16, color: F.h(Colors.teal, 800)),
            const SizedBox(width: 6),
            Text('Abschnitt A — Sachverhalt',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: F.h(Colors.teal, 900))),
          ]),
          const SizedBox(height: 6),
          if (_motiveOptions.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: _selectedMotivId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Vorschlag aus Akten oder freier Text',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: Icon(Icons.assignment, size: 18, color: F.h(Colors.teal, 700)),
              ),
              items: [
                ..._motiveOptions.map((m) => DropdownMenuItem<String>(
                  value: m['id'].toString(),
                  child: Text((m['label'] ?? '').toString(),
                    style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                )),
                const DropdownMenuItem<String>(
                  value: 'free',
                  child: Text('— Anders / freier Text —', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                ),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _selectedMotivId = v;
                  if (v == 'free') {
                    _sachverhaltC.text = '';
                  } else {
                    final m = _motiveOptions.firstWhere((o) => o['id'].toString() == v, orElse: () => const {});
                    _sachverhaltC.text = (m['text'] ?? '').toString();
                  }
                });
              },
            )
          else
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: F.h(Colors.grey, 100), borderRadius: BorderRadius.circular(6)),
              child: Row(children: [
                Icon(Icons.info_outline, size: 14, color: F.h(Colors.grey, 600)),
                const SizedBox(width: 6),
                Expanded(child: Text(
                  'Keine automatischen Motiv-Vorschläge — bitte Sachverhalt unten frei eingeben.',
                  style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700)),
                )),
              ]),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _sachverhaltC,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Sachverhalt (geht in Abschnitt A des Antrags)',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ]),
      ),

      // Abschnitt B: Erklärungen — only B1 is operator-driven, the
      // other three are constants in our flow.
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        decoration: BoxDecoration(
          color: F.h(Colors.grey, 50),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: F.h(Colors.grey, 300)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.fact_check, size: 16, color: F.h(c, 700)),
            const SizedBox(width: 6),
            Text('Abschnitt B — Erklärungen',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: F.h(c, 800))),
          ]),
          const SizedBox(height: 4),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            title: Text(
              _hasRechtsschutz
                  ? 'Rechtsschutzversicherung vorhanden (B1 NICHT angekreuzt)'
                  : 'Keine Rechtsschutzversicherung (B1 angekreuzt)',
              style: const TextStyle(fontSize: 11.5),
            ),
            value: _hasRechtsschutz,
            onChanged: (v) => setState(() => _hasRechtsschutz = v),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: Text(
              'B2/B3/B4 werden immer angekreuzt: keine andere kostenlose Beratung, '
              'noch nicht bewilligt/versagt, kein gerichtliches Verfahren.',
              style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600), height: 1.3),
            ),
          ),
        ]),
      ),

      // Abschnitt C — Einkommen aus Jobcenter-Bescheid (1:1)
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: F.h(Colors.amber, 50),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: F.h(Colors.amber, 300)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.euro, size: 16, color: F.h(Colors.amber, 800)),
            const SizedBox(width: 6),
            Text('Abschnitt C — Einkünfte (aus Bescheid)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: F.h(Colors.amber, 900))),
          ]),
          const SizedBox(height: 6),
          Text(
            'Auszahlbetrag aus dem Bürgergeld-/ALG-Bescheid 1:1 eintragen. '
            'Wird sowohl in C1 (Brutto) als auch C2 (Netto) übernommen — '
            'Bürgergeld hat keine Abzüge.',
            style: TextStyle(fontSize: 10.5, color: F.h(Colors.amber, 900), height: 1.4),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _auszahlbetragC,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Auszahlbetrag (€/Monat)',
              isDense: true,
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.account_balance_wallet, size: 18),
              suffixText: '€',
              hintText: 'z. B. 1722.68',
            ),
          ),
          if (_auszahlbetragC.text.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              Icon(Icons.auto_fix_high, size: 12, color: F.h(Colors.green, 700)),
              const SizedBox(width: 4),
              Text(
                'Automatisch übernommen aus aktivem Jobcenter-Bewilligungsbescheid '
                '(bescheid_betrag). Bei Bedarf überschreiben.',
                style: TextStyle(fontSize: 10, color: F.h(Colors.green, 800), fontStyle: FontStyle.italic),
              ),
            ]),
          ],
        ]),
      ),

      // Abschnitt D — Wohnung (aus aktivem Mietvertrag)
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: F.h(Colors.blue, 50),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: F.h(Colors.blue, 300)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.home, size: 16, color: F.h(Colors.blue, 800)),
            const SizedBox(width: 6),
            Text('Abschnitt D — Wohnung (aus Mietvertrag)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: F.h(Colors.blue, 900))),
          ]),
          if (_wohnungAdresse != null) ...[
            const SizedBox(height: 4),
            Text('Mietobjekt: $_wohnungAdresse',
              style: TextStyle(fontSize: 10.5, color: F.h(Colors.blue, 800), fontStyle: FontStyle.italic)),
          ],
          if (_kinderAnzahl > 0) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: F.h(Colors.indigo, 100),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.family_restroom, size: 14, color: F.h(Colors.indigo, 700)),
                const SizedBox(width: 4),
                Text(
                  '$_kinderAnzahl ${_kinderAnzahl == 1 ? "Kind/Angehörige/r" : "Kinder/Angehörige"} im Haushalt — '
                  'D5 (gemeinsam bewohnt) wird automatisch angekreuzt, D6 = $_kinderAnzahl',
                  style: TextStyle(fontSize: 10.5, color: F.h(Colors.indigo, 900), fontWeight: FontWeight.w600),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(
              controller: _wohnflaecheC,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Wohnfläche',
                suffixText: 'm²',
                isDense: true,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.square_foot, size: 18),
              ),
            )),
            const SizedBox(width: 8),
            Expanded(child: TextField(
              controller: _warmmieteC,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Warmmiete (Kalt + NK + Heizung)',
                suffixText: '€',
                isDense: true,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.euro, size: 18),
              ),
            )),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _wohnkostenAnteilC,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Davon zahle ich (D3)',
              hintText: 'Standard: gleicher Betrag wie Warmmiete',
              suffixText: '€',
              isDense: true,
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.payments, size: 18),
            ),
          ),
          if (_wohnflaecheC.text.isNotEmpty || _warmmieteC.text.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              Icon(Icons.auto_fix_high, size: 12, color: F.h(Colors.green, 700)),
              const SizedBox(width: 4),
              Expanded(child: Text(
                'Automatisch übernommen aus aktivem Mietvertrag '
                '(vermieter_mietvertraege). Bei Bedarf überschreiben.',
                style: TextStyle(fontSize: 10, color: F.h(Colors.green, 800), fontStyle: FontStyle.italic),
              )),
            ]),
          ],
        ]),
      ),

      // Abschnitt F — Bankkonto (aus Finanzen-Modul)
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: F.h(Colors.purple, 50),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: F.h(Colors.purple, 300)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.account_balance, size: 16, color: F.h(Colors.purple, 800)),
            const SizedBox(width: 6),
            Text('Abschnitt F — Bankkonto (aus Finanzen)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: F.h(Colors.purple, 900))),
          ]),
          const SizedBox(height: 6),
          if (_hatBankkonten) ...[
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.check_circle, size: 14, color: F.h(Colors.green, 700)),
              const SizedBox(width: 6),
              Expanded(child: Text(
                'F1 = JA (Konto vorhanden) angekreuzt · F1-Inhaber = A (Antragsteller) angekreuzt · '
                'F3-Bank1 = ${_bankName ?? "(kein Name)"}'
                '${_bankKontoart != null && _bankKontoart!.isNotEmpty ? " · Kontoart: $_bankKontoart" : ""}'
                '${_bankIban != null && _bankIban!.length >= 4 ? " · IBAN endet auf ${_bankIban!.substring(_bankIban!.length - 4)}" : ""}',
                style: TextStyle(fontSize: 11, color: F.h(Colors.purple, 900)),
              )),
            ]),
          ] else ...[
            Row(children: [
              Icon(Icons.info_outline, size: 14, color: F.h(Colors.grey, 600)),
              const SizedBox(width: 6),
              Expanded(child: Text(
                'Kein Bankkonto im Finanzen-Modul hinterlegt — F1 wird auf NEIN gesetzt.',
                style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700)),
              )),
            ]),
          ],
        ]),
      ),

      // Abschnitt G — Zahlungsverpflichtungen (immer NEIN)
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: F.h(Colors.grey, 100),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: F.h(Colors.grey, 300)),
        ),
        child: Row(children: [
          Icon(Icons.gavel, size: 16, color: F.h(Colors.grey, 700)),
          const SizedBox(width: 6),
          Expanded(child: Text(
            'Abschnitt G — beide Fragen werden auf NEIN gesetzt: G1 '
            '(Zahlungsverpflichtungen / Kreditraten) und G9 (sonstige '
            'besondere Belastungen wie Krankheits- / Pflegekosten).',
            style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 800)),
          )),
        ]),
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
          decoration: BoxDecoration(color: F.h(Colors.green, 50), borderRadius: BorderRadius.circular(6), border: Border.all(color: F.h(Colors.green, 300))),
          child: Row(children: [
            Icon(Icons.check_circle, color: F.h(Colors.green, 700), size: 18),
            const SizedBox(width: 8),
            // Auf Mobil ist der Ablageort app-privat — dort nur der Name.
            Expanded(child: Text(
              FilePickerHelper.savesToRealPath ? _lastGeneratedPath! : (_lastFileName ?? ''),
              style: TextStyle(fontSize: 11, color: F.h(Colors.green, 800)),
              overflow: TextOverflow.ellipsis,
            )),
            TextButton.icon(icon: const Icon(Icons.open_in_new, size: 14), label: const Text('Öffnen'),
              onPressed: () => OpenFilex.open(_lastGeneratedPath!)),
            TextButton.icon(icon: const Icon(Icons.download, size: 14), label: const Text('Speichern'),
              onPressed: _saveGeneratedPdf),
          ]),
        ),
      ],
      if (_lastError != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: F.h(Colors.red, 50), borderRadius: BorderRadius.circular(6), border: Border.all(color: F.h(Colors.red, 300))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.error_outline, color: F.h(Colors.red, 700), size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(_lastError!, style: TextStyle(fontSize: 11, color: F.h(Colors.red, 800)))),
          ]),
        ),
      ],
    ]));
  }
}

// ============================================================================
// VOLLMACHT-Tab im Gerichts-Vorfall — direkt neben "Klage".
//
// Anders als bei den Behörden (§ 13 Abs. 1 SGB X: jeder darf Bevollmächtigter
// sein) hat vor Gericht jede Verfahrensordnung eine ABSCHLIESSENDE Liste, wer
// vertreten darf — und ein Verein steht auf keiner davon, außer unter engen
// Bedingungen vor dem Sozialgericht (§ 73 Abs. 2 S. 2 Nr. 8 SGG) und im
// Verbraucherinsolvenzverfahren (§ 305 Abs. 4 InsO). Deshalb kommt die
// Rechtslage vom Server (vollmacht_gericht_lib.php) und wird hier nur
// angezeigt: eine zweite Kopie der Matrix im Client würde irgendwann von der
// im PDF abweichen, und dann verspricht der Bildschirm etwas anderes als das
// unterschriebene Dokument.
//
// Datenquellen: Verifizierung Stufe 1 (Mitgliedsdaten) + der Vorfall selbst
// (Gericht, Aktenzeichen, Parteien, Termine).
// ============================================================================

/// PHP kennt nur einen Array-Typ: `json_encode` macht aus einer assoziativen
/// Struktur ein JSON-Objekt, aus einer lückenlos nummerierten eine JSON-Liste
/// und aus einer leeren ebenfalls eine Liste. `as Map` auf einer Liste liefert
/// nicht null, sondern wirft — im Release-Build sieht man davon nur eine graue
/// Fläche (so geschehen im Speedtest-Bildschirm am 05.08.2026). Deshalb lesen
/// die Vollmacht-Felder grundsätzlich beide Formen.
///
/// Konkret betroffen: `recht.umfang_organisation` ist heute ein Objekt, wäre
/// aber eine Liste, sobald ein Gerichtstyp einmal keine Umfangspunkte hat.
Map<String, dynamic> vollmachtFeldAlsMap(dynamic v) {
  if (v is Map) return Map<String, dynamic>.from(v);
  if (v is List) {
    final m = <String, dynamic>{};
    for (var i = 0; i < v.length; i++) {
      m['$i'] = v[i];
    }
    return m;
  }
  return {};
}

// ⚠️ `kVollmachtVersandWege` stand hier bis 21.08.2026 ein ZWEITES Mal, mit
// demselben Inhalt wie in `vollmacht_link_aktionen.dart`. Zwei Tabellen wären
// zwei Stände: derselbe Weg, hier ausgeschrieben und dort roh. Die Tabelle
// gehört zum Versandprotokoll, und das wird an mehreren Stellen gezeichnet —
// deshalb liegt sie beim Protokoll-Widget und wird von dort importiert.

/// Gegenstück für Felder, die als Liste gedacht sind (`recht.grenzen`), vom
/// Server aber als Objekt kommen könnten.
List<String> vollmachtFeldAlsListe(dynamic v) {
  if (v is List) return v.map((e) => e.toString()).toList();
  if (v is Map) return v.values.map((e) => e.toString()).toList();
  return const [];
}

class _GerichtVollmachtTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int vorfallId;
  final String gerichtTyp;
  final MaterialColor color;

  /// 'gericht' (Regelfall) oder 'insolvenzverwalter'. Dieselbe Maske, aber
  /// eine andere Rechtslage — und die kommt vollständig vom Server, damit der
  /// Bildschirm nichts anderes verspricht als das unterschriebene Dokument.
  /// Beim Verwalter ist `umfang_vertretung` leer, also verschwindet der
  /// Vertretungsblock hier von selbst; es braucht dafür keine zweite Regel.
  final String adressat;

  /// Bindet die Urkunde an EIN Aktenzeichen. Ohne sie zeigte der Tab einer
  /// Akte auch die Vollmachten der anderen Akten desselben Verfahrens.
  final int? insolvenzAkteId;

  /// Für den Signatur-Endpunkt: er verlangt die Mitgliedsnummer des
  /// Anfordernden. Fehlt sie, wird der Unterschriftsstand nicht geladen und
  /// die Schaltfläche bleibt aus — lieber keine Angabe als eine erfundene.
  final String adminMitgliedernummer;

  /// Erscheint im Titel des Signaturvorgangs, damit im Postfach der
  /// Unterzeichner erkennbar ist, worum es geht.
  final String akteBezeichnung;

  const _GerichtVollmachtTab({
    required this.apiService,
    required this.userId,
    required this.vorfallId,
    required this.gerichtTyp,
    required this.color,
    this.adressat = 'gericht',
    this.insolvenzAkteId,
    this.adminMitgliedernummer = '',
    this.akteBezeichnung = '',
  });
  @override
  State<_GerichtVollmachtTab> createState() => _GerichtVollmachtTabState();
}

class _GerichtVollmachtTabState extends State<_GerichtVollmachtTab> with SingleTickerProviderStateMixin {
  late TabController _sub;
  bool _loading = true;
  bool _generating = false;

  Map<String, dynamic> _user = {};
  Map<String, dynamic> _vorsitzer = {};
  Map<String, dynamic> _verein = {};
  Map<String, dynamic> _verfahren = {};
  Map<String, dynamic> _gericht = {};
  /// Nur bei adressat == 'insolvenzverwalter' gefüllt.
  Map<String, dynamic> _verwalter = {};
  /// Die Akte, an der dieses Blatt hängt — mit BEIDEN Aktenzeichen.
  Map<String, dynamic> _akte = {};
  Map<String, dynamic> _recht = {};
  List<Map<String, dynamic>> _vollmachten = [];
  /// Unterschriftsvorgänge je Vollmacht-Id. Leer, solange niemand etwas zur
  /// Unterschrift gestellt hat — oder wenn die Mitgliedsnummer des
  /// Anfordernden fehlt.
  Map<int, List<Signaturvorgang>> _signaturen = {};
  int? _stelltZu;
  /// Vollmacht-Id, deren Fax gerade unterwegs ist. Eigenes Feld statt eines
  /// gemeinsamen „busy": ein laufendes Fax darf den Knopf „Zur Unterschrift
  /// stellen" nicht sperren, und ein zweiter Druck auf „Per Fax" würde
  /// dasselbe Dokument ein zweites Mal faxen.
  int? _faxtGerade;

  final Map<String, bool> _org = {};
  final Map<String, bool> _vtr = {};
  bool _vertretungBestaetigt = false;
  bool _beistand = true;
  bool _untervollmacht = false;
  final _nachweisC = TextEditingController();
  DateTime _validFrom = DateTime.now();
  DateTime? _validUntil;

  @override
  void initState() {
    super.initState();
    _sub = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _sub.dispose();
    _nachweisC.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final d = await widget.apiService.getVollmachtData(
      widget.userId, 'gericht',
      gerichtTyp: widget.gerichtTyp, vorfallId: widget.vorfallId,
      adressat: widget.adressat, insolvenzAkteId: widget.insolvenzAkteId,
    );
    final l = await widget.apiService.listVollmachten(
      widget.userId, 'gericht', vorfallId: widget.vorfallId,
      insolvenzAkteId: widget.insolvenzAkteId,
      // Ohne diesen Filter stünden im Verwalter-Tab auch die an das Gericht
      // gerichteten Urkunden desselben Verfahrens — und eingereicht würde
      // dann die falsche.
      adressat: widget.adressat,
    );
    if (!mounted) return;
    setState(() {
      if (d['success'] == true) {
        _user      = vollmachtFeldAlsMap(d['user']);
        _vorsitzer = vollmachtFeldAlsMap(d['vorsitzer']);
        _verein    = vollmachtFeldAlsMap(d['verein']);
        _verfahren = vollmachtFeldAlsMap(d['verfahren']);
        _gericht   = vollmachtFeldAlsMap(d['gericht']);
        _verwalter = vollmachtFeldAlsMap(d['verwalter']);
        _akte      = vollmachtFeldAlsMap(d['akte']);
        _recht     = vollmachtFeldAlsMap(d['recht']);
        final org = vollmachtFeldAlsMap(_recht['umfang_organisation']);
        final vtr = vollmachtFeldAlsMap(_recht['umfang_vertretung']);
        for (final k in org.keys) {
          // "anwalt" bleibt aus: einen Rechtsanwalt im Namen des Mitglieds zu
          // beauftragen kostet Geld und ist ein eigenes Rechtsgeschäft — das
          // soll niemand versehentlich mitankreuzen.
          _org.putIfAbsent(k, () => k != 'anwalt');
        }
        for (final k in vtr.keys) {
          _vtr.putIfAbsent(k, () => false);
        }
      }
      if (l['success'] == true && l['vollmachten'] is List) {
        _vollmachten = (l['vollmachten'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      _loading = false;
    });
    _signaturenLaden();
  }

  /// ⚠️ Nur laden, wenn wir wissen, wer fragt: der Endpunkt verlangt die
  /// Mitgliedsnummer des Anfordernden als Identitätsnachweis. Fehlt sie,
  /// bleibt der Unterschriftsstand eben leer — lieber keine Angabe als eine
  /// erfundene. Dieselbe Regel wie im Rechtsanwalts-Modul.
  Future<void> _signaturenLaden() async {
    if (widget.adminMitgliedernummer.isEmpty) return;
    final alle = await SignaturService().liste(
      callerMitgliedernummer: widget.adminMitgliedernummer,
      userId: widget.userId,
    );
    if (!mounted) return;
    final je = <int, List<Signaturvorgang>>{};
    for (final v in alle) {
      if (v.quelleTabelle != 'member_vollmachten' || v.quelleId == null) continue;
      je.putIfAbsent(v.quelleId!, () => []).add(v);
    }
    setState(() => _signaturen = je);
  }

  /// Stellt die Vollmacht beiden Seiten zur Unterschrift.
  ///
  /// ⚠️ Erst danach darf sie hinausgehen: ohne Unterschrift darf die
  /// Insolvenzverwaltung nach § 43a Abs. 2 BRAO und § 203 Abs. 1 Nr. 3 StGB
  /// gar nichts sagen. Ein Entwurf im Anhang kostet sie eine Rückfrage und
  /// uns eine Woche.
  Future<void> _zurUnterschrift(int id, String filename) async {
    final vorsitzerId = _vorsitzer['id'] is int
        ? _vorsitzer['id'] as int
        : int.tryParse('${_vorsitzer['id']}') ?? 0;
    if (vorsitzerId <= 0 || widget.adminMitgliedernummer.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ohne angemeldeten Vorstand kann nichts gestellt werden'),
        backgroundColor: Colors.red));
      return;
    }
    setState(() => _stelltZu = id);
    try {
      final resp = await widget.apiService.downloadVollmachtPdf(id);
      if (!mounted) return;
      if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('PDF nicht abrufbar (HTTP ${resp.statusCode})'),
          backgroundColor: Colors.red));
        return;
      }
      final titel = 'Vollmacht und Schweigepflichtentbindung'
          '${widget.akteBezeichnung.isEmpty ? '' : ' — ${widget.akteBezeichnung}'}';
      final r = await SignaturService().anfordernAusBytes(
        callerMitgliedernummer: widget.adminMitgliedernummer,
        userId: widget.userId,
        dokumentTyp: widget.adressat == 'insolvenzverwalter'
            ? 'insolvenz_vollmacht' : 'gericht_vollmacht',
        dokumentTitel: titel,
        pdfBytes: resp.bodyBytes,
        dateiname: filename,
        quelleTabelle: 'member_vollmachten',
        quelleId: id,
        unterzeichner: [
          Unterzeichner(userId: widget.userId, rolle: 'vollmachtgeber'),
          Unterzeichner(userId: vorsitzerId, rolle: 'bevollmaechtigter'),
        ],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.ok
            ? 'Zur Unterschrift gestellt — beide Unterzeichner sind benachrichtigt'
            : (r.fehler ?? 'Fehler')),
        backgroundColor: r.ok ? Colors.green : Colors.red));
      if (r.ok) _signaturenLaden();
    } finally {
      if (mounted) setState(() => _stelltZu = null);
    }
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  /// Was noch fehlt, bevor das Dokument überhaupt Sinn ergibt.
  List<String> _fehlend() {
    final f = <String>[];
    if ((_user['vorname'] ?? '').toString().isEmpty || (_user['nachname'] ?? '').toString().isEmpty) {
      f.add('Name (Verifizierung Stufe 1)');
    }
    if ((_user['geburtsdatum'] ?? '').toString().isEmpty) f.add('Geburtsdatum (Stufe 1)');
    if ((_user['strasse'] ?? '').toString().isEmpty || (_user['plz'] ?? '').toString().isEmpty) {
      f.add('Anschrift (Stufe 1)');
    }
    if ((_vorsitzer['vorname'] ?? '').toString().isEmpty) f.add('Vorsitzender');
    if ((_verein['vereinsname'] ?? '').toString().isEmpty) f.add('Vereinsdaten');
    if (widget.adressat == 'insolvenzverwalter') {
      // Ohne Verwalter hat das Blatt keinen Adressaten — der Server lehnt es
      // dann auch ab. Hier steht es vorher da, statt erst nach dem Klick.
      final vw = '${_verwalter['name'] ?? ''}${_verwalter['kanzlei'] ?? ''}'.trim();
      if (vw.isEmpty) f.add('Zuständige Insolvenzverwaltung (Unterreiter daneben)');
    } else if ((_gericht['name'] ?? '').toString().isEmpty) {
      f.add('Zuständiges Gericht (Tab „Gericht")');
    }
    return f;
  }

  Future<void> _generate() async {
    setState(() => _generating = true);
    final res = await widget.apiService.createVollmacht({
      'user_id': widget.userId,
      'behoerde': 'gericht',
      'gericht_typ': widget.gerichtTyp,
      'vorfall_id': widget.vorfallId,
      'adressat': widget.adressat,
      if (widget.insolvenzAkteId != null) 'insolvenz_akte_id': widget.insolvenzAkteId,
      'valid_from': _validFrom.toIso8601String().substring(0, 10),
      'valid_until': _validUntil?.toIso8601String().substring(0, 10),
      'options': {
        'organisation': _org,
        'vertretung': _vtr,
        'vertretung_bestaetigt': _vertretungBestaetigt,
        'vertretung_nachweis': _nachweisC.text.trim(),
        'beistand_beantragt': _beistand,
        'untervollmacht': _untervollmacht,
      },
    });
    if (!mounted) return;
    setState(() => _generating = false);
    final ok = res['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Vollmacht erstellt (ID ${res['id']})' : (res['message'] ?? 'Fehler').toString()),
      backgroundColor: ok ? Colors.green : Colors.red,
    ));
    if (ok) {
      _sub.animateTo(1);
      _load();
    }
  }

  /// Wer schon unterschrieben hat. Solange nichts gestellt wurde, bleibt die
  /// Zeile weg statt „0 von 2" zu behaupten.
  Widget _unterschriftsstand(int id) {
    final vorgaenge = _signaturen[id] ?? const <Signaturvorgang>[];
    if (vorgaenge.isEmpty) return const SizedBox.shrink();
    // ⚠️ Die Zahlen der GRUPPE, nicht die der zurückgegebenen Zeilen. `liste`
    // steht unter einem Mitglied und liefert von einer Vollmacht nur dessen
    // eine Zeile — die zweite gehört dem Vorstand. Gezählt kam deshalb
    // „0 von 1" heraus, obwohl zwei Unterschriften angefordert waren, und
    // sobald das Mitglied unterschrieben hatte, stand da „Von beiden
    // unterschrieben". Der Server liefert gruppe_gesamt/gruppe_signiert
    // genau dafür mit.
    final fertig = vorgaenge.first.gruppeSigniert;
    final gesamt = vorgaenge.first.gruppeGesamt;
    final alle = vorgaenge.first.gruppeVollstaendig;
    return Padding(padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Icon(alle ? Icons.verified : Icons.hourglass_bottom, size: 14,
          color: alle ? F.h(Colors.green, 700) : F.h(Colors.orange, 700)),
        const SizedBox(width: 4),
        Text(alle
            ? 'Von beiden unterschrieben'
            : 'Unterschrieben: $fertig von $gesamt',
          style: TextStyle(fontSize: 11,
            color: alle ? F.h(Colors.green, 800) : F.h(Colors.orange, 800))),
      ]));
  }

  /// Versand an die Kanzlei. Holt zuerst Vorlage und Bereitschaft, damit der
  /// Dialog sagen kann, WARUM nicht gesendet werden kann — statt einen grauen
  /// Knopf zu zeigen.
  Future<void> _mailDialog(int vollmachtId) async {
    final v = await widget.apiService.insolvenzVollmachtMailVorlage(vollmachtId);
    if (!mounted) return;
    if (v['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text((v['message'] ?? 'Vorlage nicht abrufbar').toString()),
        backgroundColor: Colors.red));
      return;
    }
    final vorlage = vollmachtFeldAlsMap(
        vollmachtFeldAlsMap(v['vorlagen'])['einreichen']);
    final bereit = v['bereit'] == true;
    final unterschrieben = (v['unterschrieben'] as num?)?.toInt() ?? 0;
    final noetig = (v['noetig'] as num?)?.toInt() ?? 0;

    final empf = TextEditingController(text: (v['empfaenger'] ?? '').toString());
    final betr = TextEditingController(text: (vorlage['betreff'] ?? '').toString());
    final text = TextEditingController(text: (vorlage['text'] ?? '').toString());
    var laeuft = false;

    if (!mounted) return;
    await showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) =>
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(children: [
          Icon(Icons.forward_to_inbox, color: F.h(widget.color, 700)), const SizedBox(width: 8),
          const Expanded(child: Text('Vollmacht senden', style: TextStyle(fontSize: 16))),
        ]),
        content: SizedBox(width: 560, child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            if (!bereit)
              Container(
                width: double.infinity, padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: F.h(Colors.orange, 50),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: F.h(Colors.orange, 300))),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.hourglass_bottom, size: 18, color: F.h(Colors.orange, 800)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    noetig == 0
                        ? 'Noch nicht zur Unterschrift gestellt. Ohne unterschriebene '
                          'Vollmacht darf die Insolvenzverwaltung keine Auskunft geben '
                          '(§ 43a Abs. 2 BRAO, § 203 Abs. 1 Nr. 3 StGB) — ein Entwurf im '
                          'Anhang kostet nur eine Rückfrage.'
                        : 'Erst $unterschrieben von $noetig Unterschriften. Gesendet wird '
                          'ausschließlich die von beiden unterschriebene Fassung.',
                    style: TextStyle(fontSize: 11, color: F.h(Colors.orange, 900)))),
                ])),
            TextField(controller: empf, style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(labelText: 'An', isDense: true,
                border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: betr, style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(labelText: 'Betreff', isDense: true,
                border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: text, maxLines: 12, style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(labelText: 'Text', isDense: true,
                border: OutlineInputBorder())),
            const SizedBox(height: 6),
            Text('Absender: ${v['absender'] ?? ''} · Anlage: ${v['anhang'] ?? ''}\n'
                 'Die Signatur des angemeldeten Vorstands wird automatisch angehängt.',
              style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
          ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: widget.color),
            icon: laeuft
                ? const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send, size: 16),
            label: const Text('Senden'),
            onPressed: (!bereit || laeuft) ? null : () async {
              setLocal(() => laeuft = true);
              final r = await widget.apiService.insolvenzVollmachtMailSenden(
                vollmachtId: vollmachtId,
                empfaenger: empf.text.trim(),
                betreff: betr.text.trim(),
                text: text.text,
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (!mounted) return;
              final ok = r['success'] == true;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(ok
                    ? 'Gesendet an ${r['empfaenger'] ?? ''}'
                    : (r['message'] ?? 'Nicht gesendet').toString()),
                backgroundColor: ok ? Colors.green : Colors.red,
                duration: const Duration(seconds: 6)));
              if (ok) _load();
            }),
        ],
      )));
    empf.dispose(); betr.dispose(); text.dispose();
  }

  /// Dieselbe unterschriebene Fassung per Fax.
  ///
  /// ⚠️ Kein Entwurfsdialog wie bei der Mail: ein Fax hat keinen Fließtext.
  /// Was der Mensch vor dem Auslösen sehen muss, ist die Nummer und die
  /// Tatsache, dass es sich nicht zurückholen lässt.
  ///
  /// ⚠️ Die Nummer wird beim Öffnen frisch geholt, nicht aus der Liste
  /// genommen: sie hängt an der Kanzlei in der Rechtsanwaltsdatenbank, und
  /// die kann sich zwischen zwei Aufrufen geändert haben. Dieselbe Antwort
  /// sagt auch, ob überhaupt eine unterschriebene Fassung vorliegt — damit
  /// der Dialog den Grund nennen kann, statt einen grauen Knopf zu zeigen.
  Future<void> _faxDialog(int vollmachtId) async {
    final v = await widget.apiService.insolvenzVollmachtMailVorlage(vollmachtId);
    if (!mounted) return;
    if (v['success'] != true) {
      _melden((v['message'] ?? 'Faxdaten nicht abrufbar').toString(), Colors.red);
      return;
    }

    final nummer = (v['fax'] ?? '').toString().trim();
    // ⚠️ NICHT `kanzlei`. Die Faxnummer hängt an der Kanzlei als Stelle; im
    // Datensatz gibt es genau ein Faxfeld. Der Server liefert dafür einen
    // eigenen Namen, damit der Bildschirm keine Abteilung behauptet.
    final stelle = (v['fax_name'] ?? '').toString().trim().isEmpty
        ? 'diese Kanzlei'
        : (v['fax_name'] ?? '').toString().trim();
    final bereit = v['bereit'] == true;
    final unterschrieben = (v['unterschrieben'] as num?)?.toInt() ?? 0;
    final noetig = (v['noetig'] as num?)?.toInt() ?? 0;

    if (nummer.isEmpty) {
      _melden('Für $stelle ist keine Faxnummer hinterlegt.', Colors.orange);
      return;
    }
    if (!bereit) {
      _melden(
        noetig == 0
            ? 'Noch nicht zur Unterschrift gestellt — gefaxt wird nur die von beiden '
              'unterschriebene Fassung.'
            : 'Erst $unterschrieben von $noetig Unterschriften — gefaxt wird nur die '
              'von beiden unterschriebene Fassung.',
        Colors.orange);
      return;
    }

    final los = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Row(children: [
        Icon(Icons.fax, color: F.h(widget.color, 700)), const SizedBox(width: 8),
        const Expanded(child: Text('Per Fax senden?', style: TextStyle(fontSize: 16))),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('An: $stelle', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          Text(nummer, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
          const SizedBox(height: 10),
          Text('Anlage: ${v['anhang'] ?? 'die unterschriebene Vollmacht'}',
            style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700))),
          const SizedBox(height: 10),
          Text('⚠️ Ein Fax lässt sich nicht zurückholen.',
            style: TextStyle(fontSize: 12, color: F.h(Colors.red, 800))),
          const SizedBox(height: 6),
          Text('„Übergeben" ist noch nicht „zugestellt": das Dokument geht an sipgate, '
               'die Zustellung wird danach nachverfolgt.',
            style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
        ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: widget.color),
          icon: const Icon(Icons.fax, size: 16),
          label: const Text('Senden'),
          onPressed: () => Navigator.pop(ctx, true)),
      ],
    ));
    if (los != true || !mounted) return;

    setState(() => _faxtGerade = vollmachtId);
    final r = await widget.apiService.insolvenzVollmachtFaxSenden(vollmachtId: vollmachtId);
    if (!mounted) return;
    setState(() => _faxtGerade = null);

    final ok = r['success'] == true;
    _melden(
      ok
          // Die Sitzungsnummer gehört in die Meldung: sie ist das, womit sich
          // im Fax-Bildschirm nachsehen lässt, was daraus geworden ist.
          ? 'Fax übergeben an ${r['empfaenger'] ?? nummer} — Sitzung ${r['session_id'] ?? ''}'
          : (r['message'] ?? 'Fax nicht gesendet').toString(),
      ok ? Colors.green : Colors.red);
    if (ok) _load();
  }

  /// [typ] `pdf` = die deutsche Urkunde, `translation` = das Leseexemplar in
  /// der Sprache des Mitglieds.
  ///
  /// ⚠️ Der Vorstand muss das Leseexemplar ÖFFNEN können, nicht nur
  /// verschicken. Bisher ging es in den Chat und als SMS-Link hinaus, ohne
  /// dass hier jemand es je zu sehen bekam — wer etwas verschickt, das er
  /// nicht ansehen kann, kann auf eine Rückfrage dazu nicht antworten.
  Future<void> _openPdf(int id, String filename, {String typ = 'pdf'}) async {
    try {
      final r = await widget.apiService.downloadVollmachtPdf(id, type: typ);
      if (!mounted) return;
      if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
        FileViewerDialog.showFromBytes(context, r.bodyBytes, filename);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler (${r.statusCode})'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
      }
    }
  }

  /// Das PDF auf die Platte, statt es nur anzusehen.
  Future<void> _speichern(int id, String filename, {String typ = 'pdf'}) async {
    try {
      final r = await widget.apiService.downloadVollmachtPdf(id, type: typ);
      if (!mounted) return;
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) {
        _melden('Fehler (${r.statusCode})', Colors.red);
        return;
      }
      final ziel = await FilePickerHelper.saveBytes(
          bytes: r.bodyBytes, fileName: filename, dialogTitle: 'Vollmacht speichern');
      if (ziel == null || !mounted) return;
      _melden('Gespeichert: $ziel', Colors.green);
    } catch (e) {
      if (mounted) _melden('Fehler: $e', Colors.red);
    }
  }

  /// Die UNTERSCHRIEBENE, gesiegelte Fassung — die mit beiden Unterschriften.
  ///
  /// ⚠️ Genau die fehlte hier. Der Bildschirm sagte „Unterschrieben: 2 von 2"
  /// und bot keinen Weg, das Ergebnis zu öffnen. Im Rechtsanwalts-Modul hat
  /// derselbe blinde Fleck dazu geführt, dass eine bereits unterschriebene
  /// Vollmacht widerrufen wurde, weil es aussah, als sei nichts passiert.
  ///
  /// Der Siegel-Cron schreibt den Pfad auf ALLE Zeilen der Gruppe, sobald der
  /// letzte unterschrieben hat: es ist ein Dokument mit beiden Unterschriften,
  /// nicht zwei.
  /// Ob für diese Vollmacht überhaupt eine Unterschrift ANGEFORDERT ist.
  ///
  /// ⚠️ Genau die Bedingung, die `vollmacht_link_senden` serverseitig prüft:
  /// der Signierlink führt zu einem OFFENEN Vorgang und legt keinen an. Ohne
  /// ihn antwortet der Server mit `grund: nicht_gestellt`.
  ///
  /// ⚠️ Ist die Nummer des Vorstands nicht bekannt, wurde die Liste gar nicht
  /// geladen. Dann ist „nein" keine Aussage über den Vorgang, sondern über
  /// unser Wissen — der Hinweis sagt deshalb etwas anderes.
  bool _signaturGestellt(int id) =>
      (_signaturen[id] ?? const <Signaturvorgang>[]).any((x) => x.istOffen);

  Signaturvorgang? _signiertVerfuegbar(int id) {
    final vorgaenge = _signaturen[id] ?? const <Signaturvorgang>[];
    if (vorgaenge.isEmpty) return null;
    // ⚠️ Ebenfalls über die GRUPPE. `every()` über die gelieferten Zeilen war
    // wahr, sobald das MITGLIED unterschrieben hatte — die Zeile des
    // Vorstands ist hier gar nicht dabei. Der Knopf „Unterschriebene
    // Fassung" wäre also erschienen, bevor der Vorstand unterschrieben hat,
    // und hätte ein Dokument angeboten, das es noch nicht gibt.
    if (!vorgaenge.first.gruppeVollstaendig) return null;
    return vorgaenge.firstWhere((x) => x.istSigniert, orElse: () => vorgaenge.first);
  }

  Future<void> _signiertOeffnen(int id, {bool speichern = false}) async {
    final vorgang = _signiertVerfuegbar(id);
    if (vorgang == null) return;
    final bytes = await SignaturService().herunterladen(
      callerMitgliedernummer: widget.adminMitgliedernummer,
      signaturId: vorgang.id,
      welche: 'signiert',
    );
    if (!mounted) return;
    if (bytes == null) {
      // Der Cron läuft alle paar Minuten. „Noch nicht da" ist kein Fehler,
      // aber es muss dastehen — sonst sucht jemand an der falschen Stelle.
      _melden('Die unterschriebene Fassung ist noch nicht gesiegelt — '
              'das geschieht wenige Minuten nach der letzten Unterschrift',
          Colors.orange);
      return;
    }
    final name = 'vollmacht_unterschrieben_$id.pdf';
    if (speichern) {
      final ziel = await FilePickerHelper.saveBytes(
          bytes: Uint8List.fromList(bytes), fileName: name,
          dialogTitle: 'Unterschriebene Vollmacht speichern');
      if (ziel == null || !mounted) return;
      _melden('Gespeichert: $ziel', Colors.green);
      return;
    }
    await FileViewerDialog.showFromBytes(context, Uint8List.fromList(bytes), name);
  }

  /// Das Leseexemplar in das Postfach DES MITGLIEDS, dem die Vollmacht gehört.
  ///
  /// ⚠️ Adressiert wird über `mitglied_nummer` aus der Vollmacht-Zeile, nicht
  /// über das gerade geöffnete Profil. Beides ist fast immer dasselbe — aber
  /// „fast immer" ist bei einer Vollmacht zu wenig: ein Dokument im falschen
  /// Postfach ist eine Datenpanne, kein Schönheitsfehler.
  Future<void> _inDenChat(Map<String, dynamic> v) async {
    final id = v['id'] is int ? v['id'] as int : int.parse('${v['id']}');
    final nummer = '${v['mitglied_nummer'] ?? ''}'.trim();
    if (nummer.isEmpty || widget.adminMitgliedernummer.isEmpty) {
      _melden('Empfänger nicht ermittelbar', Colors.red);
      return;
    }
    // ⚠️ Ins Postfach des Mitglieds gehört die Fassung, die es LESEN kann.
    // Unterschrieben und der Kanzlei vorgelegt wird weiter allein die
    // deutsche; das Leseexemplar sagt das auf jeder Seite.
    //
    // Es entsteht bei der Erzeugung, wenn die Sprache des Mitglieds eine der
    // sechs übersetzten ist. Fehlt es — etwa bei einer Vollmacht aus der Zeit
    // davor oder bei „de" —, geht die deutsche, und der Hinweis sagt das
    // offen, statt es zu verschweigen.
    final sprache = '${v['translation_language'] ?? ''}'.trim();
    final istUebersetzt = sprache.isNotEmpty;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('In den Chat senden?'),
        content: Text(
          istUebersetzt
              ? 'Das Leseexemplar (${sprache.toUpperCase()}) geht an $nummer.\n\n'
                'Unterschrieben und der Kanzlei vorgelegt wird weiter allein '
                'die deutsche Fassung — das steht auch auf jeder Seite des '
                'Leseexemplars.'
              : 'Die deutsche Fassung geht an $nummer.\n\n'
                'Ein Leseexemplar in der Sprache des Mitglieds gibt es für '
                'diese Vollmacht nicht. Der Verein erläutert den Inhalt '
                'mündlich — so steht es auch im Dokument.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: widget.color.shade700, foregroundColor: Colors.white),
            child: const Text('Senden'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    File? temp;
    try {
      // ⚠️ Bei vorhandenem Leseexemplar wird GENAU DAS geholt, nicht die
      // deutsche Fassung. Ohne den Typ ginge stillschweigend das deutsche
      // Blatt hinaus, während der Dialog eine Übersetzung angekündigt hat.
      final r = await widget.apiService
          .downloadVollmachtPdf(id, type: istUebersetzt ? 'translation' : 'pdf');
      if (!mounted) return;
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) {
        _melden('Fehler (${r.statusCode})', Colors.red);
        return;
      }
      final gespraech =
          await widget.apiService.adminStartChat(widget.adminMitgliedernummer, nummer);
      final cid = int.tryParse('${gespraech['conversation_id'] ?? ''}') ??
          int.tryParse('${(gespraech['data'] as Map?)?['conversation_id'] ?? ''}') ?? 0;
      if (cid <= 0) {
        if (mounted) _melden('Kein Gespräch mit $nummer gefunden', Colors.red);
        return;
      }
      // ⚠️ Der Chat-Upload will eine Datei auf der Platte. Das PDF liegt hier
      // im Speicher, muss also kurz abgelegt werden — im temporären
      // Verzeichnis der App und mit `finally` wieder weg. Es wandert ohnehin
      // gleich in die Chat-Ablage, ist also keine neue Offenlegung.
      temp = File('${Directory.systemTemp.path}/'
          'vollmacht_$id${istUebersetzt ? '_$sprache' : ''}.pdf');
      await temp.writeAsBytes(r.bodyBytes, flush: true);
      final res = await widget.apiService.uploadChatAttachments(
        conversationId: cid,
        mitgliedernummer: widget.adminMitgliedernummer,
        files: [temp],
        message: istUebersetzt
            ? 'Vollmacht (Leseexemplar) — ${widget.akteBezeichnung}'
            : 'Vollmacht — ${widget.akteBezeichnung}',
      );
      if (!mounted) return;
      final erfolg = res['success'] == true;
      // ⚠️ Erst jetzt protokollieren, nachdem der Server den Empfang bestätigt
      // hat. Vorher einzutragen hieße, eine Sendung zu behaupten, die
      // vielleicht nie ankam — und genau darauf verlässt sich später jemand,
      // der sieht „ist beim Mitglied".
      if (erfolg) {
        await widget.apiService.insolvenzVollmachtVersandEintragen(
          vollmachtId: id, empfaenger: nummer, weg: 'chat',
          fassung: istUebersetzt ? 'uebersetzung' : 'original',
          sprache: istUebersetzt ? sprache : 'de',
        );
      }
      if (!mounted) return;
      _melden(erfolg ? 'An $nummer gesendet' : 'Konnte nicht gesendet werden',
          erfolg ? Colors.green : Colors.red);
    } catch (e) {
      if (mounted) _melden('Fehler: $e', Colors.red);
    } finally {
      if (temp != null && await temp.exists()) {
        await temp.delete();
      }
    }
  }

  /// Jede Sendung, nicht nur die letzte.
  Future<void> _versandprotokoll(int id) async {
    final res = await widget.apiService.insolvenzVollmachtVersandListe(id);
    if (!mounted) return;
    final zeilen = (res['items'] is List)
        ? List<Map<String, dynamic>>.from(
            (res['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)))
        : <Map<String, dynamic>>[];
    // ⚠️ Die Linkzeilen stehen ABGESETZT von den Sendungen an die Gegenseite.
    // Eine Fax- oder Mailzeile beantwortet „wann ging was an wen"; eine
    // Linkzeile beantwortet zusätzlich, was das Mitglied damit GETAN hat —
    // geöffnet, heruntergeladen, bestätigt, unterschrieben. In eine Tabelle
    // gepresst, deren Zeitspalte „gesendet" heißt, läse sich das eine als das
    // andere.
    final links = (res['links'] is List)
        ? List<Map<String, dynamic>>.from(
            (res['links'] as List).map((e) => Map<String, dynamic>.from(e as Map)))
        : <Map<String, dynamic>>[];
    final linkBlock = vollmachtLinkBlock(links);
    final breite = MediaQuery.of(context).size.width;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Versandprotokoll'),
        content: SizedBox(
          width: breite < 560 ? breite * 0.86 : 480,
          child: (zeilen.isEmpty && linkBlock == null)
              ? const Text('Noch nicht verschickt.', style: TextStyle(fontSize: 13))
              : SingleChildScrollView(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (zeilen.isNotEmpty) ListView.separated(
                  shrinkWrap: true,
                  itemCount: zeilen.length,
                  separatorBuilder: (_, __) => const Divider(height: 12),
                  itemBuilder: (_, i) {
                    final z = zeilen[i];
                    final fassung = '${z['fassung'] ?? ''}' == 'uebersetzung'
                        ? 'Leseexemplar' : 'deutsche Fassung';
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${z['gesendet_am'] ?? ''} · $fassung',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      Text('${kVollmachtVersandWege['${z['weg'] ?? ''}'] ?? '${z['weg'] ?? ''}'}'
                           ' an ${z['empfaenger'] ?? ''}',
                          style: const TextStyle(fontSize: 12)),
                      if ('${z['gesendet_von_name'] ?? ''}'.trim().isNotEmpty)
                        Text('durch ${z['gesendet_von_name']}',
                            style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
                      if ('${z['notiz'] ?? ''}'.trim().isNotEmpty)
                        Text('${z['notiz']}',
                            style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
                    ]);
                  },
                ),
                    if (linkBlock != null) linkBlock,
                  ])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen')),
        ],
      ),
    );
  }

  Future<void> _statusAendern(Map<String, dynamic> v) async {
    final id = v['id'] is int ? v['id'] as int : int.parse('${v['id']}');
    final ergebnis = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => _VollmachtStatusDialog(vollmacht: v, color: widget.color),
    );
    if (ergebnis == null || !mounted) return;
    final res = await widget.apiService.insolvenzVollmachtStatus(
      vollmachtId: id,
      status: ergebnis['status'] ?? '',
      submittedAt: ergebnis['submitted_at'] ?? '',
      submittedMethod: ergebnis['submitted_method'] ?? '',
      submittedNotes: ergebnis['submitted_notes'] ?? '',
    );
    if (!mounted) return;
    final gut = res['success'] == true;
    _melden(gut ? 'Gespeichert' : '${res['message'] ?? 'Fehler'}',
        gut ? Colors.green : Colors.red);
    if (gut) _load();
  }

  /// ⚠️ Nur Entwürfe. Was einmal unterschrieben oder eingereicht war, wird
  /// widerrufen, nicht entfernt — der Server hält das durch, der Dialog sagt
  /// es vorher.
  Future<void> _loeschen(Map<String, dynamic> v) async {
    final id = v['id'] is int ? v['id'] as int : int.parse('${v['id']}');
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Entwurf entfernen?'),
      content: const Text(
          'Das PDF und alle Protokollzeilen dieser Vollmacht gehen mit.\n\n'
          'Nur Entwürfe lassen sich entfernen. Eine erteilte Vollmacht wird '
          'widerrufen — sie muss in der Akte bleiben.',
          style: TextStyle(fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          child: const Text('Entfernen'),
        ),
      ],
    ));
    if (ok != true || !mounted) return;
    final res = await widget.apiService.insolvenzVollmachtLoeschen(id);
    if (!mounted) return;
    final gut = res['success'] == true;
    _melden(gut ? 'Entwurf entfernt' : '${res['message'] ?? 'Fehler'}',
        gut ? Colors.green : Colors.red);
    if (gut) _load();
  }

  void _melden(String text, Color farbe) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text), backgroundColor: farbe));

  Future<void> _revoke(int id) async {
    final grundC = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Vollmacht widerrufen'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
          widget.adressat == 'insolvenzverwalter'
            ? 'Der Widerruf muss der Insolvenzverwaltung angezeigt werden. Bis dahin darf sie '
              'auf die Vollmacht vertrauen (§ 173 BGB) — § 87 ZPO gilt hier nicht, weil die '
              'Urkunde nicht an das Gericht gerichtet ist.'
            : 'Der Widerruf muss dem Gericht angezeigt werden — gegenüber der Gegenseite wird er '
              'nach § 87 Abs. 1 ZPO erst mit dieser Anzeige wirksam.',
          style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 12),
        TextField(controller: grundC, maxLines: 2,
          decoration: const InputDecoration(labelText: 'Grund (optional)', border: OutlineInputBorder())),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true), child: const Text('Widerrufen')),
      ],
    ));
    if (ok != true) return;
    final res = await widget.apiService.revokeVollmacht(id, reason: grundC.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(res['success'] == true ? 'Vollmacht widerrufen' : (res['message'] ?? 'Fehler').toString()),
      backgroundColor: res['success'] == true ? Colors.orange : Colors.red));
    if (res['success'] == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      TabBar(
        controller: _sub,
        labelColor: F.h(widget.color, 700),
        indicatorColor: widget.color.shade700,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        tabs: [
          const Tab(icon: Icon(Icons.add_circle_outline, size: 16), text: 'Erstellen'),
          Tab(icon: const Icon(Icons.history, size: 16), text: 'Historie (${_vollmachten.length})'),
        ],
      ),
      Expanded(child: TabBarView(controller: _sub, children: [
        _buildErstellen(),
        _buildHistorie(),
      ])),
    ]);
  }

  // ── Erstellen ─────────────────────────────────────────────────────────
  Widget _buildErstellen() {
    final fehlend = _fehlend();
    final moeglich = (_recht['vertretung_moeglich'] ?? 'nein').toString();
    final org = vollmachtFeldAlsMap(_recht['umfang_organisation']);
    final vtr = vollmachtFeldAlsMap(_recht['umfang_vertretung']);

    return SingleChildScrollView(padding: const EdgeInsets.all(16), child:
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Vollmacht — ${_recht['label'] ?? ''}',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: F.h(widget.color, 800))),
        const SizedBox(height: 2),
        Text(widget.adressat == 'insolvenzverwalter'
            ? 'Vorzulegen bei der Insolvenzverwaltung — NICHT zu den Gerichtsakten'
            : 'Einzureichen zu den Gerichtsakten gem. ${_recht['vollmacht_norm'] ?? ''}',
          style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 500))),
        const SizedBox(height: 12),
        // ⚠️ AN WEN das Blatt geht, ist die wichtigste Angabe darauf — und
        // stand vorher nirgends auf dem Schirm. Wer den Reiter in einem
        // Aktenzeichen öffnete, las „Einzureichen zu den Gerichtsakten" und
        // „Gericht" in der Datenbox und hielt das Dokument für eine
        // Prozessvollmacht. Das PDF war die ganze Zeit richtig adressiert;
        // der Bildschirm verschwieg es nur.
        if (widget.adressat == 'insolvenzverwalter') ...[
          _buildAdressatBlock(),
          const SizedBox(height: 10),
        ],

        // Wer / wogegen / wo — aus Stufe 1 und aus dem Vorfall.
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: F.h(widget.color, 50), borderRadius: BorderRadius.circular(8),
            border: Border.all(color: F.h(widget.color, 200))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _kv('Mitglied', '${_user['vorname'] ?? ''} ${_user['nachname'] ?? ''}'
                ' — geb. ${_user['geburtsdatum'] ?? '?'}'
                '${(_user['geburtsort'] ?? '').toString().isNotEmpty ? ' in ${_user['geburtsort']}' : ''}'),
            _kv('Anschrift', '${_user['strasse'] ?? ''} ${_user['hausnummer'] ?? ''}, '
                '${_user['plz'] ?? ''} ${_user['ort'] ?? ''}'),
            const Divider(height: 12),
            _kv(widget.adressat == 'insolvenzverwalter'
                    ? 'Insolvenzgericht'   // nur zur Bezeichnung des Verfahrens
                    : 'Gericht',
                (_gericht['name'] ?? '').toString().isEmpty ? '— nicht gewählt —' : _gericht['name'].toString()),
            _kv('Verfahren', (_verfahren['titel'] ?? '').toString()),
            _kv(widget.adressat == 'insolvenzverwalter' ? 'Az. des Gerichts' : 'Aktenzeichen',
                _aktenzeichen().isEmpty ? '— wird nachgereicht —' : _aktenzeichen()),
            // Die Kanzlei führt die Sache unter IHRER Nummer — danach wird
            // gefragt, wenn man dort anruft.
            if (widget.adressat == 'insolvenzverwalter')
              _kv('Az. der Kanzlei', (_akte['az_verwalter'] ?? '').toString().isEmpty
                  ? '— nicht bekannt —' : _akte['az_verwalter'].toString()),
            if ((_verfahren['klaeger'] ?? '').toString().isNotEmpty)
              _kv('Kläger', _verfahren['klaeger'].toString()),
            if ((_verfahren['beklagter'] ?? '').toString().isNotEmpty)
              _kv('Beklagter', _verfahren['beklagter'].toString()),
            const Divider(height: 12),
            _kv('Bevollmächtigter', '${_verein['vereinsname'] ?? ''} — vertreten durch '
                '${_vorsitzer['vorname'] ?? ''} ${_vorsitzer['nachname'] ?? ''}'),
          ]),
        ),

        if (fehlend.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: F.h(Colors.red, 50), border: Border.all(color: F.h(Colors.red, 300)),
            borderRadius: BorderRadius.circular(6)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.warning, color: F.h(Colors.red, 700), size: 18), const SizedBox(width: 6),
            Expanded(child: Text('Fehlt noch: ${fehlend.join(", ")}',
              style: TextStyle(fontSize: 12, color: F.h(Colors.red, 900)))),
          ]),
        )),

        const SizedBox(height: 16),
        _buildRechtsBox(moeglich),

        const SizedBox(height: 14),
        _sectionTitle(Icons.checklist, 'A — Organisatorische Aufgaben'),
        Text('Keine Rechtsdienstleistung i.S.d. § 2 Abs. 1 RDG — diese Punkte sind immer zulässig.',
          style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
        for (final e in org.entries)
          CheckboxListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(e.value.toString(), style: const TextStyle(fontSize: 12)),
            value: _org[e.key] ?? false,
            onChanged: (v) => setState(() => _org[e.key] = v ?? false),
          ),

        if (moeglich != 'nein') ...[
          const SizedBox(height: 14),
          _sectionTitle(Icons.gavel, 'B — Verfahrenshandlungen'),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: _vertretungBestaetigt,
            onChanged: (v) => setState(() => _vertretungBestaetigt = v),
            title: Text('Vertretungsbefugnis nach ${_recht['vertretung_norm'] ?? ''} geltend machen',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            subtitle: const Text(
              'Nur einschalten, wenn die unten genannte Voraussetzung tatsächlich vorliegt. '
              'Über die Zulassung entscheidet das Gericht.',
              style: TextStyle(fontSize: 11)),
          ),
          if (_vertretungBestaetigt) ...[
            Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: TextField(
              controller: _nachweisC, maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Begründung der Vertretungsbefugnis (wird mitgedruckt)',
                hintText: 'z. B. Satzung § 2 — Interessenvertretung behinderter Menschen',
                isDense: true, border: OutlineInputBorder(), alignLabelWithHint: true),
            )),
            for (final e in vtr.entries)
              CheckboxListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(e.value.toString(), style: const TextStyle(fontSize: 12)),
                value: _vtr[e.key] ?? false,
                onChanged: (v) => setState(() => _vtr[e.key] = v ?? false),
              ),
          ],
        ],

        const SizedBox(height: 8),
        SwitchListTile(
          dense: true, contentPadding: EdgeInsets.zero,
          value: _beistand,
          onChanged: (v) => setState(() => _beistand = v),
          title: Text('Zulassung als Beistand beantragen (${_recht['beistand_norm'] ?? ''})',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          subtitle: const Text(
            'Das Mitglied erscheint selbst; der Verein unterstützt in der Verhandlung. '
            'Die Zulassung liegt im Ermessen des Gerichts.',
            style: TextStyle(fontSize: 11)),
        ),
        SwitchListTile(
          dense: true, contentPadding: EdgeInsets.zero,
          value: _untervollmacht,
          onChanged: (v) => setState(() => _untervollmacht = v),
          title: const Text('Untervollmacht für Vereinsmitarbeitende zulässig',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ),

        const SizedBox(height: 8),
        _sectionTitle(Icons.event, 'Gültigkeit'),
        Row(children: [
          Expanded(child: ListTile(
            dense: true,
            title: const Text('Gültig ab', style: TextStyle(fontSize: 12)),
            subtitle: Text(_fmt(_validFrom), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            trailing: const Icon(Icons.calendar_today, size: 16),
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: _validFrom,
                firstDate: DateTime(2020), lastDate: DateTime(2099));
              if (d != null) setState(() => _validFrom = d);
            },
          )),
          Expanded(child: ListTile(
            dense: true,
            title: const Text('Gültig bis', style: TextStyle(fontSize: 12)),
            subtitle: Text(_validUntil != null ? _fmt(_validUntil!) : 'auf Widerruf',
              style: const TextStyle(fontSize: 13)),
            trailing: _validUntil != null
                ? IconButton(icon: const Icon(Icons.clear, size: 16),
                    onPressed: () => setState(() => _validUntil = null))
                : const Icon(Icons.calendar_today, size: 16),
            onTap: () async {
              final d = await showDatePicker(context: context,
                initialDate: _validUntil ?? _validFrom.add(const Duration(days: 365)),
                firstDate: _validFrom, lastDate: DateTime(2099));
              if (d != null) setState(() => _validUntil = d);
            },
          )),
        ]),

        const SizedBox(height: 8),
        _buildGrenzen(),

        const SizedBox(height: 16),
        Center(child: ElevatedButton.icon(
          icon: _generating
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.picture_as_pdf),
          label: Text(_generating ? 'Generiere…' : 'Vollmacht generieren'),
          style: ElevatedButton.styleFrom(backgroundColor: widget.color.shade700,
            foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
          onPressed: (_generating || fehlend.isNotEmpty) ? null : _generate,
        )),
        const SizedBox(height: 8),
        Center(child: Text(
          'Das Original ist zu den Gerichtsakten einzureichen — Kopie, Fax oder Scan genügen als '
          'Nachweis der Bevollmächtigung nicht.',
          style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600)), textAlign: TextAlign.center)),
      ]),
    );
  }

  /// Wer dieses Blatt bekommt — beim Verwalter die Kanzlei, nicht das Gericht.
  ///
  /// ⚠️ Der Hinweistext ist bewusst zurueckhaltend formuliert. Eine
  /// ALLGEMEINE Auskunftspflicht des Insolvenzverwalters gegenueber dem
  /// Schuldner gibt es nicht: § 97 InsO laeuft nur in die andere Richtung, und
  /// die Berichtspflicht des § 58 Abs. 1 Satz 2 InsO richtet sich allein an das
  /// Insolvenzgericht. Dieses Blatt VERPFLICHTET die Verwaltung also nicht — es
  /// raeumt das Hindernis aus, an dem eine Auskunft sonst scheitert
  /// (Verschwiegenheit und Datenschutz), und ueberlaesst ihr den Rest.
  Widget _buildAdressatBlock() {
    final k = vollmachtFeldAlsMap(_verwalter['kanzlei']);
    final firma = (k['firmenname'] ?? '').toString();
    final person = (k['anwalt_name'] ?? '').toString();
    final rolle = kInsolvenzRollen[(_verwalter['rolle'] ?? '').toString()] ?? '';
    final leer = firma.isEmpty && person.isEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: leer ? F.h(Colors.red, 50) : F.h(Colors.indigo, 50),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: leer ? F.h(Colors.red, 300) : F.h(Colors.indigo, 200))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(leer ? Icons.warning : Icons.forward_to_inbox, size: 18,
            color: leer ? F.h(Colors.red, 700) : F.h(Colors.indigo, 700)),
          const SizedBox(width: 6),
          Expanded(child: Text('Dieses Blatt geht an die Insolvenzverwaltung',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
              color: leer ? F.h(Colors.red, 900) : F.h(Colors.indigo, 900)))),
        ]),
        const SizedBox(height: 6),
        if (leer)
          Text('Noch keine Insolvenzverwaltung ausgewählt — im Unterreiter daneben '
               'aus der Rechtsanwaltsdatenbank wählen. Ohne Adressat lehnt der Server ab.',
            style: TextStyle(fontSize: 11, color: F.h(Colors.red, 900)))
        else ...[
          if (firma.isNotEmpty)
            Text(firma, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
              color: F.h(Colors.indigo, 900))),
          if (person.isNotEmpty)
            Text(person, style: TextStyle(fontSize: 11, color: F.h(Colors.indigo, 800))),
          if (rolle.isNotEmpty)
            Text(rolle, style: TextStyle(fontSize: 11, color: F.h(Colors.indigo, 700))),
          const SizedBox(height: 6),
          Text('Vom Gericht bestellt — nicht Vertreter des Mitglieds, sondern eigenes '
               'Organ des Verfahrens. Erklärungen ihm gegenüber sind gewöhnliche '
               'Stellvertretung (§§ 164 ff. BGB); der abschließende Katalog des § 79 ZPO '
               'regelt die Vertretung vor Gericht und greift hier nicht.',
            style: TextStyle(fontSize: 11, color: F.h(Colors.indigo, 900))),
          const SizedBox(height: 4),
          Text('Für die Gerichtsakte ist die Vollmacht im Vorfall selbst zu verwenden.',
            style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic,
              color: F.h(Colors.indigo, 700))),
        ],
      ]),
    );
  }

  String _aktenzeichen() {
    // Steht das Blatt in einer Akte, gilt DEREN gerichtliches Aktenzeichen —
    // ein Verfahren kann mehrere tragen, vorgelegt wird unter dem einen.
    final a = (_akte['az_gericht'] ?? '').toString().trim();
    if (a.isNotEmpty) return a;
    final k = (_verfahren['klage_aktenzeichen'] ?? '').toString().trim();
    if (k.isNotEmpty) return k;
    return (_verfahren['aktenzeichen'] ?? '').toString().trim();
  }

  Widget _buildRechtsBox(String moeglich) {
    final (Color bg, Color fg, IconData ic, String titel) = switch (moeglich) {
      'ja' => (Colors.green.shade50, Colors.green.shade900, Icons.check_circle, 'Vertretung möglich'),
      'bedingt' => (Colors.amber.shade50, Colors.amber.shade900, Icons.help_outline,
                    'Vertretung nur unter Bedingung möglich'),
      _ => (Colors.blueGrey.shade50, Colors.blueGrey.shade900, Icons.block,
            'Keine Prozessvertretung möglich'),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8),
        border: Border.all(color: fg.withValues(alpha: 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(ic, size: 18, color: fg), const SizedBox(width: 6),
          Expanded(child: Text(titel, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: fg))),
        ]),
        const SizedBox(height: 6),
        Text('${_recht['verfahrensordnung'] ?? ''} · ${_recht['vertretung_norm'] ?? ''}',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
        const SizedBox(height: 4),
        Text((_recht['vertretung_text'] ?? '').toString(), style: TextStyle(fontSize: 11, color: fg)),
        if ((_recht['bedingung'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Voraussetzung: ${_recht['bedingung']}',
            style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: fg)),
        ],
      ]),
    );
  }

  Widget _buildGrenzen() {
    final g = vollmachtFeldAlsListe(_recht['grenzen']);
    if (g.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: F.h(Colors.grey, 100), borderRadius: BorderRadius.circular(8),
        border: Border.all(color: F.h(Colors.grey, 300))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.do_not_disturb_on_outlined, size: 16, color: F.h(Colors.grey, 700)),
          const SizedBox(width: 6),
          Text('Steht so im PDF: ausdrücklich NICHT umfasst',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: F.h(Colors.grey, 800))),
        ]),
        const SizedBox(height: 6),
        for (final s in g) Padding(padding: const EdgeInsets.only(bottom: 4),
          child: Text('•  $s', style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700)))),
      ]),
    );
  }

  // ── Historie ──────────────────────────────────────────────────────────
  Widget _buildHistorie() {
    if (_vollmachten.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
        mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.assignment_ind_outlined, size: 48, color: F.h(Colors.grey, 300)),
          const SizedBox(height: 8),
          Text('Für dieses Verfahren wurde noch keine Vollmacht erstellt.',
            style: TextStyle(color: F.h(Colors.grey, 500), fontSize: 13), textAlign: TextAlign.center),
        ])));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _vollmachten.length,
      itemBuilder: (_, i) {
        final v = _vollmachten[i];
        final status = (v['status'] ?? '').toString();
        final color = switch (status) {
          'aktiv' || 'active' => Colors.green,
          'draft' => Colors.blue,
          'revoked' => Colors.red,
          'expired' => Colors.grey,
          _ => Colors.blueGrey,
        };
        final filename = (v['pdf_filename'] ?? 'vollmacht_${v['id']}.pdf').toString();
        // Leer, solange es kein Leseexemplar gibt — die Sprache des Mitglieds
        // ist dann nicht übersetzt oder die Vollmacht stammt aus der Zeit vor
        // der Umstellung.
        final uebersetzungSprache = '${v['translation_language'] ?? ''}'.trim();
        return Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(
          leading: Icon(Icons.picture_as_pdf, color: color),
          title: Text('Vollmacht #${v['id']} — ${status.toUpperCase()}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Erstellt: ${v['generated_at'] ?? ''}', style: const TextStyle(fontSize: 11)),
            Text('Gültig: ${v['valid_from'] ?? ''} → ${v['valid_until'] ?? 'auf Widerruf'}',
              style: const TextStyle(fontSize: 11)),
            if (status == 'revoked')
              Text('Widerrufen: ${v['revoked_at'] ?? ''}',
                style: TextStyle(fontSize: 11, color: F.h(Colors.red, 700))),
            const SizedBox(height: 4),
            _unterschriftsstand(v['id'] is int ? v['id'] as int : int.parse('${v['id']}')),
            Wrap(spacing: 6, runSpacing: 4, children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.picture_as_pdf, size: 14),
                label: const Text('PDF öffnen', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  minimumSize: const Size(0, 28), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                onPressed: () => _openPdf(v['id'] is int ? v['id'] as int : int.parse('${v['id']}'), filename),
              ),
              if (status != 'revoked' && widget.adminMitgliedernummer.isNotEmpty)
                OutlinedButton.icon(
                  icon: _stelltZu == (v['id'] is int ? v['id'] : int.parse('${v['id']}'))
                      ? const SizedBox(width: 12, height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.draw, size: 14),
                  label: const Text('Zur Unterschrift stellen', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: F.h(widget.color, 700),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    minimumSize: const Size(0, 28), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  onPressed: _stelltZu != null ? null : () => _zurUnterschrift(
                      v['id'] is int ? v['id'] as int : int.parse('${v['id']}'), filename),
                ),
              // Nur bei der an die Verwaltung gerichteten Fassung: die
              // Gerichtsfassung wird eingereicht, nicht gemailt.
              if (widget.adressat == 'insolvenzverwalter' && status != 'revoked')
                OutlinedButton.icon(
                  icon: const Icon(Icons.forward_to_inbox, size: 14),
                  label: const Text('Per E-Mail senden', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: F.h(Colors.indigo, 700),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    minimumSize: const Size(0, 28), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  onPressed: () => _mailDialog(
                      v['id'] is int ? v['id'] as int : int.parse('${v['id']}')),
                ),
              // Derselbe Adressat, anderer Weg. Kanzleien nehmen Vollmachten
              // oft nur per Fax an — und der Sendebericht ist dort der
              // Nachweis, den eine E-Mail nicht liefert.
              if (widget.adressat == 'insolvenzverwalter' && status != 'revoked')
                OutlinedButton.icon(
                  icon: _faxtGerade == (v['id'] is int ? v['id'] : int.parse('${v['id']}'))
                      ? const SizedBox(width: 12, height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.fax, size: 14),
                  label: const Text('Per Fax senden', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: F.h(Colors.deepPurple, 700),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    minimumSize: const Size(0, 28), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  onPressed: _faxtGerade != null ? null : () => _faxDialog(
                      v['id'] is int ? v['id'] as int : int.parse('${v['id']}')),
                ),
              // Für Mitglieder OHNE App: die Vollmacht geht als SMS-Link auf
              // ihr Handy. Erst zum Lesen in ihrer Sprache, dann — von Hand,
              // nach ihrer Bestätigung — zum Unterschreiben.
              //
              // ⚠️ Steht neben dem Chat-Knopf, nicht statt seiner: der Chat
              // erreicht nur, wer die App hat. Am 18.08.2026 hatten von 44
              // aktiven Mitgliedern zwölf eine Mobilnummer, aber keine App.
              if (status != 'revoked')
                VollmachtLinkKnoepfe(
                  farbe: widget.color,
                  widerrufen: status == 'revoked',
                  signierbar: _signaturGestellt(
                      v['id'] is int ? v['id'] as int : int.parse('${v['id']}')),
                  signierHinweis: widget.adminMitgliedernummer.isEmpty
                      ? 'Unterschriftsstand nicht abrufbar — Mitgliedsnummer des '
                        'Vorstands fehlt.'
                      : 'Erst „Zur Unterschrift stellen" — der Link führt zu einem '
                        'offenen Vorgang, er legt keinen an.',
                  onGesendet: _load,
                  onSenden: (zweck) => widget.apiService.insolvenzVollmachtLinkSenden(
                    vollmachtId: v['id'] is int ? v['id'] as int : int.parse('${v['id']}'),
                    zweck: zweck),
                ),
              // Die unterschriebene Fassung — erst sichtbar, wenn wirklich
              // alle unterschrieben haben. Vorher gäbe es nichts zu öffnen,
              // und ein Knopf, der nichts tut, ist schlimmer als keiner.
              if (_signiertVerfuegbar(
                      v['id'] is int ? v['id'] as int : int.parse('${v['id']}')) != null)
                OutlinedButton.icon(
                  icon: const Icon(Icons.verified, size: 14),
                  label: const Text('Unterschriebene Fassung', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: F.h(Colors.green, 700),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    minimumSize: const Size(0, 28), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  onPressed: () => _signiertOeffnen(
                      v['id'] is int ? v['id'] as int : int.parse('${v['id']}')),
                ),
              OutlinedButton.icon(
                icon: const Icon(Icons.download, size: 14),
                label: const Text('Speichern', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  minimumSize: const Size(0, 28), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                onPressed: () => _speichern(
                    v['id'] is int ? v['id'] as int : int.parse('${v['id']}'), filename),
              ),
              // Das Leseexemplar in der Sprache des Mitglieds — dasselbe
              // Dokument, das in den Chat und als SMS-Link hinausgeht.
              //
              // ⚠️ Nur wenn es eines GIBT: `translation_language` ist leer,
              // solange die Sprache des Mitglieds nicht übersetzt ist oder die
              // Vollmacht aus der Zeit davor stammt. Ein Knopf, der dann ins
              // Leere führt, wäre schlimmer als keiner.
              //
              // ⚠️ Die Sprache steht IM Knopf. „Leseexemplar" allein sagt
              // nicht, was das Mitglied bekommt — und genau das ist die Frage,
              // die man sich vor dem Verschicken stellt.
              if (uebersetzungSprache.isNotEmpty) ...[
                OutlinedButton.icon(
                  icon: const Icon(Icons.translate, size: 14),
                  label: Text('Leseexemplar (${uebersetzungSprache.toUpperCase()})',
                      style: const TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: F.h(Colors.teal, 700),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    minimumSize: const Size(0, 28), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  onPressed: () => _openPdf(
                      v['id'] is int ? v['id'] as int : int.parse('${v['id']}'),
                      filename.replaceFirst(RegExp(r'\.pdf$'), '_$uebersetzungSprache.pdf'),
                      typ: 'translation'),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.download, size: 14),
                  label: const Text('Leseexemplar speichern', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: F.h(Colors.teal, 700),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    minimumSize: const Size(0, 28), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  onPressed: () => _speichern(
                      v['id'] is int ? v['id'] as int : int.parse('${v['id']}'),
                      filename.replaceFirst(RegExp(r'\.pdf$'), '_$uebersetzungSprache.pdf'),
                      typ: 'translation'),
                ),
              ],
              if (widget.adminMitgliedernummer.isNotEmpty
                  && '${v['mitglied_nummer'] ?? ''}'.trim().isNotEmpty)
                OutlinedButton.icon(
                  icon: const Icon(Icons.alternate_email, size: 14),
                  label: const Text('In den Chat', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    minimumSize: const Size(0, 28), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  onPressed: () => _inDenChat(v),
                ),
              OutlinedButton.icon(
                icon: const Icon(Icons.outgoing_mail, size: 14),
                label: const Text('Versandprotokoll', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  minimumSize: const Size(0, 28), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                onPressed: () => _versandprotokoll(
                    v['id'] is int ? v['id'] as int : int.parse('${v['id']}')),
              ),
              if (status != 'revoked')
                OutlinedButton.icon(
                  icon: const Icon(Icons.flag_outlined, size: 14),
                  label: const Text('Status', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    minimumSize: const Size(0, 28), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  onPressed: () => _statusAendern(v),
                ),
              // Nur beim Entwurf. Der Server lehnt alles andere ab; hier
              // erscheint der Knopf gar nicht erst, damit niemand eine
              // Ablehnung als Fehler liest.
              if (status == 'draft')
                OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 14),
                  label: const Text('Entwurf entfernen', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: F.h(Colors.red, 700),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    minimumSize: const Size(0, 28), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  onPressed: () => _loeschen(v),
                ),
            ]),
          ]),
          trailing: status != 'revoked'
              ? IconButton(icon: const Icon(Icons.cancel, size: 20, color: Colors.red),
                  tooltip: 'Widerrufen',
                  onPressed: () => _revoke(v['id'] is int ? v['id'] as int : int.parse('${v['id']}')))
              : null,
        ));
      },
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 110, child: Text(k, style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 500)))),
      Expanded(child: Text(v, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
    ]));

  Widget _sectionTitle(IconData icon, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Icon(icon, size: 16, color: F.h(widget.color, 700)), const SizedBox(width: 6),
      Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: F.h(widget.color, 700))),
    ]));
}

// ============================================================================
// INSOLVENZVERWALTER — Tab im Vorfall, direkt neben „Vollmacht".
//
// NUR beim Insolvenzgericht. Einen Insolvenzverwalter bestellt das
// Insolvenzgericht im Eroeffnungsbeschluss; vor dem Arbeits-, Sozial- oder
// Betreuungsgericht gibt es ihn nicht, und ein Tab, der bei fuenf von sechs
// Gerichtstypen leer bleibt, ist kein Angebot, sondern Rauschen. Der Server
// weist jeden anderen Gerichtstyp ohnehin ab — hier steht nur die schnellere
// Antwort.
//
// Der Aufbau wiederholt bewusst die Ebene darueber (Zuständiges Gericht |
// Vorfall):
//   Unterreiter 1  „Zuständige Insolvenzverwaltung"  — wer es ist
//   Unterreiter 2  „Aktenzeichen"                    — worunter die Sache läuft
// und ein Aktenzeichen öffnet wieder ein Modal, diesmal mit Details ·
// Korrespondenz · Unterlagen · Vollmacht.
//
// ⚠️ WARUM AKTENZEICHEN EINE LISTE IST UND KEIN FELD: ein Insolvenzverfahren
// trägt regelmäßig ZWEI Nummern — die des Gerichts (`123 IN 456/24`) und die
// interne der Verwalterkanzlei, die in deren Schreiben unter der Anschrift
// steht. Wer beim Verwalter anruft, wird nach der zweiten gefragt.
// ============================================================================

/// Rollen im Verfahren. Die Person bleibt meist dieselbe, die Rolle nicht:
/// vorläufige/r Insolvenzverwalter/in → Insolvenzverwalter/in → Treuhänder/in
/// in der Wohlverhaltensphase. Sachwalter/in ist etwas anderes — sie überwacht
/// bei Eigenverwaltung nur und verwaltet die Masse nicht selbst.
///
/// ⚠️ Die Schlüssel müssen mit `INSOLVENZ_ROLLEN` in `insolvenz_manage.php`
/// übereinstimmen; ein unbekannter Wert fällt dort still auf 'verwalter'
/// zurück. `test/insolvenz_verwalter_test.dart` hält beide Listen zusammen.
const kInsolvenzRollen = <String, String>{
  'vorlaeufig':      'Vorläufige/r Insolvenzverwalter/in',
  'verwalter':       'Insolvenzverwalter/in',
  'treuhaender':     'Treuhänder/in (Wohlverhaltensphase)',
  'vorl_sachwalter': 'Vorläufige/r Sachwalter/in',
  'sachwalter':      'Sachwalter/in (Eigenverwaltung)',
};

/// Abschnitte des Verfahrens in der Reihenfolge, in der sie eintreten.
const kInsolvenzPhasen = <String, String>{
  'eroeffnungsverfahren': 'Eröffnungsverfahren',
  'eroeffnet':            'Verfahren eröffnet',
  'pruefungstermin':      'Prüfungstermin',
  'verwertung':           'Verwertung der Masse',
  'schlusstermin':        'Schlusstermin / Schlussverteilung',
  'wohlverhalten':        'Wohlverhaltensphase',
  'restschuldbefreiung':  'Restschuldbefreiung erteilt',
  'aufgehoben':           'Verfahren aufgehoben',
};

const kInsolvenzAkteStatus = <String, String>{
  'laufend':      'laufend',
  'ruhend':       'ruhend',
  'abgeschlossen':'abgeschlossen',
};

/// Ein Abschnitt in der Unterlagen-Liste der Insolvenzakte.
///
/// [quelle] ist der Schlüssel, unter dem `insolvenz_manage.php?type=quellen`
/// meldet, ob dieselbe Angabe schon in einem anderen Modul dieses Hauses
/// liegt. `null` heißt „dafür gibt es keinen anderen Ort" — dann wird auch
/// kein Hinweis angezeigt, statt einer Zeile „nirgends gefunden", die nur
/// aussagt, dass wir gar nicht gesucht haben.
class InsolvenzUnterlage {
  final String schluessel;
  final String titel;

  /// Was genau gemeint ist. Steht klein unter dem Titel — „Rente" allein
  /// sagt nicht, ob der Bescheid oder die Anpassungsmitteilung gebraucht wird.
  final String? hinweis;

  /// Schlüssel in der `quellen`-Antwort, oder null.
  final String? quelle;

  const InsolvenzUnterlage(
    this.schluessel,
    this.titel, {
    this.hinweis,
    this.quelle,
  });
}

/// Die Unterlagen, die eine Insolvenzverwaltung nach § 97 InsO regelmäßig
/// anfordert — in der Reihenfolge, in der sie auf den üblichen Anforderungs-
/// schreiben stehen: erst wer man ist, dann wovon man lebt, dann was man hat,
/// dann was gegen einen läuft.
///
/// ⚠️ Die Schlüssel müssen mit `INSOLVENZ_KATEGORIEN` in
/// `insolvenz_manage.php` übereinstimmen. Ein dort unbekannter Schlüssel
/// fällt beim Hochladen STILL auf `sonstiges` zurück — die Datei landet
/// dann im falschen Abschnitt, ohne Fehlermeldung.
/// `test/insolvenz_verwalter_test.dart` hält beide Listen zusammen; das PHP
/// liegt in keinem Repository, der Test ist also die einzige Stelle, an der
/// ein Auseinanderlaufen überhaupt auffallen kann.
const kInsolvenzUnterlagen = <InsolvenzUnterlage>[
  InsolvenzUnterlage('ausweis', 'Ausweis',
      hinweis: 'Personalausweis oder Reisepass, Vorder- und Rückseite'),

  // ── Wovon das Mitglied lebt ──
  // Vier getrennte Abschnitte statt eines Sammelpostens „Einkommen": die
  // Verwaltung fragt jede Quelle einzeln ab, und wer alles in einen Stapel
  // legt, muss bei jeder Nachfrage neu suchen.
  InsolvenzUnterlage('einkommen_gehalt', 'Einkommensnachweis Gehalt — letzte 3 Monate',
      hinweis: 'Lohn- bzw. Gehaltsabrechnungen der letzten drei Monate',
      quelle: 'einkommen_gehalt'),
  InsolvenzUnterlage('alg1', 'ALG I',
      hinweis: 'Bewilligungsbescheid der Agentur für Arbeit',
      quelle: 'alg1'),
  InsolvenzUnterlage('buergergeld', 'Bürgergeld / Grundsicherung',
      hinweis: 'Bewilligungsbescheid des Jobcenters (SGB II)',
      quelle: 'buergergeld'),
  InsolvenzUnterlage('rente', 'Rente',
      hinweis: 'Rentenbescheid oder aktuelle Anpassungsmitteilung',
      quelle: 'rente'),
  InsolvenzUnterlage('grundsicherung_sozialamt', 'Grundsicherung Sozialamt',
      hinweis: 'Bescheid des Sozialamts (SGB XII)',
      quelle: 'grundsicherung_sozialamt'),
  InsolvenzUnterlage('steuerbescheid', 'Letzter Steuerbescheid',
      hinweis: 'Wegen der Steuererklärung — der zuletzt ergangene Bescheid',
      quelle: 'steuerbescheid'),

  // ── Wohnen ──
  InsolvenzUnterlage('mietvertrag', 'Mietvertrag',
      hinweis: 'Vollständig, mit allen Anlagen und Nachträgen',
      quelle: 'mietvertrag'),
  InsolvenzUnterlage('kaution', 'Zahlung Kaution Mietvertrag',
      hinweis: 'Nachweis über die geleistete Kaution — sie gehört zur Masse',
      quelle: 'kaution'),

  // ── Was an Werten da ist ──
  InsolvenzUnterlage('versicherungen', 'Versicherungen, auch Lebensversicherung',
      hinweis: 'Policen und Rückkaufswerte',
      quelle: 'versicherungen'),
  InsolvenzUnterlage('bausparvertrag', 'Bausparverträge',
      hinweis: 'Vertrag und aktueller Kontostand',
      quelle: 'bausparvertrag'),
  InsolvenzUnterlage('kfz', 'Kfz-Brief und Fahrzeugschein',
      hinweis: 'Zulassungsbescheinigung Teil I und Teil II',
      quelle: 'kfz'),
  InsolvenzUnterlage('grundbuch', 'Grundbuchauszüge',
      hinweis: 'Für jedes Grundstück ein aktueller Auszug'),
  InsolvenzUnterlage('kontoauszuege', 'Kontoauszüge — letzte 6 Monate bis heute',
      hinweis: 'Alle Konten, lückenlos und ungeschwärzt',
      quelle: 'kontoauszuege'),

  // ── Was gegen das Mitglied läuft ──
  InsolvenzUnterlage('zwangsvollstreckung',
      'Zwangsvollstreckungsmaßnahmen — letzte 3 Monate',
      hinweis: 'Aufstellung der gegen Sie gerichteten Maßnahmen'),

  // ── Was das Verfahren selbst braucht ──
  // Das Mitglied lädt die unterschriebene Einwilligung im Live-Chat hoch;
  // sie landet in seinem verschlüsselten 1-GB-Speicher und wird hier über
  // „Aus Cloud" übernommen. Deshalb steht am Knopf kein zweiter Weg — der
  // vorhandene führt schon dorthin.
  InsolvenzUnterlage('insoup', 'Nutzung InsoUp-App — Einwilligung',
      hinweis: 'Vom Mitglied unterschrieben — über „Aus Cloud" aus seinem '
          'verschlüsselten Speicher übernehmen'),
  InsolvenzUnterlage('merkblatt', 'Merkblatt für Insolvenzschuldner',
      hinweis: 'Aushändigung bestätigt'),

  InsolvenzUnterlage('sonstiges', 'Sonstiges'),
];

/// Titel der Abschnitte, die es früher gab und die der Server weiter annimmt.
///
/// ⚠️ Ohne diese Tabelle wäre ein Altdokument UNSICHTBAR: die Anzeige geht
/// über [kInsolvenzUnterlagen], und was dort keinen Abschnitt hat, wird von
/// keiner Zeile eingesammelt. Heute liegt nichts darunter — aber „heute
/// nichts" ist kein Grund, es beim nächsten Mal zu verlieren.
const kInsolvenzDokKategorienAlt = <String, String>{
  'beschluss':           'Beschlüsse des Gerichts',
  'forderungsanmeldung': 'Forderungsanmeldungen',
  'einkommen':           'Einkommensnachweise (alte Ablage)',
  'vermoegen':           'Vermögensauskunft',
  'abtretung':           'Abtretungserklärung',
  'schriftverkehr':      'Schriftverkehr',
};

/// Registerzeichen aus einem gerichtlichen Aktenzeichen (`123 IN 456/24`):
/// IN = Regelinsolvenz, IK = Verbraucherinsolvenz, IE = internationale
/// Zuständigkeit. Gibt `null` zurück, wenn die Form nichts hergibt.
///
/// ⚠️ Zeichengleich mit `insolvenzRegisterzeichen()` in `insolvenz_manage.php`
/// — hier nur, damit der Dialog es sofort anzeigt; maßgeblich ist der Server.
/// Der Ausdruck verlangt die ganze Form `<Nr>/<Jahr>` und Großschreibung:
/// ohne beides trifft er an „Termin in 2 Wochen" und an „Zahlung in 12/25
/// fällig" und behauptet eine Regelinsolvenz, wo nur ein deutsches Wort stand.
String? insolvenzRegisterzeichen(String az) {
  final m = RegExp(r'\b(IN|IK|IE)\s*\d+\s*/\s*\d{2,4}\b').firstMatch(az);
  return m?.group(1);
}

/// Was das Registerzeichen über die Verfahrensart sagt.
String? insolvenzVerfahrensart(String? registerzeichen) => switch (registerzeichen) {
  'IK' => 'Verbraucherinsolvenzverfahren',
  'IN' => 'Regelinsolvenzverfahren',
  'IE' => 'Verfahren mit internationalem Bezug',
  _    => null,
};

class _InsolvenzverwalterTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int vorfallId;
  final MaterialColor color;
  /// Mitgliedsnummer des angemeldeten Vorstands — der Signatur-Endpunkt
  /// verlangt sie als Identitätsnachweis des Anfordernden.
  final String adminMitgliedernummer;
  const _InsolvenzverwalterTab({
    required this.apiService,
    required this.userId,
    required this.vorfallId,
    required this.color,
    this.adminMitgliedernummer = '',
  });

  @override
  State<_InsolvenzverwalterTab> createState() => _InsolvenzverwalterTabState();
}

class _InsolvenzverwalterTabState extends State<_InsolvenzverwalterTab>
    with SingleTickerProviderStateMixin {
  late TabController _sub;
  bool _loading = true;
  bool _saving = false;
  Map<String, dynamic> _verwalter = {};
  List<Map<String, dynamic>> _akten = [];

  /// Das Nachschlagewerk der Kanzleien — dieselbe Quelle wie bei den
  /// Vertrags-Rechtsanwälten. Eine Insolvenzverwalterin IST eine
  /// Rechtsanwältin; sie hier ein zweites Mal abzutippen hieße, dieselbe
  /// Kanzlei in jedem Verfahren neu zu pflegen.
  List<Map<String, dynamic>> _kanzleien = [];
  int? _raId;
  String _rolle = 'verwalter';

  /// Was zum VERFAHREN gehört, nicht zur Kanzlei: wer dort die Akte führt,
  /// unter welcher Durchwahl, und die eigene Notiz. Diese drei liegen
  /// verschlüsselt, die Kanzleidaten dagegen im Klartext im Nachschlagewerk.
  final _sachbearbeiter = TextEditingController();
  final _durchwahl = TextEditingController();
  final _notiz = TextEditingController();
  final _bestellt = TextEditingController();
  final _ende = TextEditingController();

  @override
  void initState() {
    super.initState();
    _sub = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _sub.dispose();
    _sachbearbeiter.dispose();
    _durchwahl.dispose();
    _notiz.dispose();
    _bestellt.dispose();
    _ende.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final v = await widget.apiService.getInsolvenzVerwalter(widget.vorfallId);
    final a = await widget.apiService.listInsolvenzAkten(widget.vorfallId);
    final k = await widget.apiService.listRechtsanwaltDatenbank();
    if (!mounted) return;
    setState(() {
      // ⚠️ 'data' ist ein Objekt ODER null — PHP liefert null, solange niemand
      // eine Verwaltung ausgewählt hat. `as Map` würfe auf einer Liste.
      final d = v['data'];
      _verwalter = d is Map ? Map<String, dynamic>.from(d) : {};
      _raId = _verwalter['rechtsanwalt_id'] as int?;
      final r = (_verwalter['rolle'] ?? 'verwalter').toString();
      _rolle = kInsolvenzRollen.containsKey(r) ? r : 'verwalter';
      _sachbearbeiter.text = (_verwalter['sachbearbeiter'] ?? '').toString();
      _durchwahl.text = (_verwalter['sachbearbeiter_tel'] ?? '').toString();
      _notiz.text = (_verwalter['notiz'] ?? '').toString();
      _bestellt.text = (_verwalter['bestellt_am'] ?? '').toString();
      _ende.text = (_verwalter['ende_am'] ?? '').toString();
      _akten = (a['data'] is List)
          ? (a['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : [];
      // raListe statt eigener Auswertung: die Antwort trägt die Liste mal in
      // der Wurzel, mal unter `data`, und ein leeres PHP-Array wird zur Liste
      // statt zum Objekt. Der Helfer aus utils/ra_antwort.dart kennt beides —
      // eine zweite Fassung davon wäre genau die Stelle, an der es später
      // auseinanderläuft.
      _kanzleien = raListe(k);
      _loading = false;
    });
  }

  Future<void> _speichern() async {
    setState(() => _saving = true);
    final r = await widget.apiService.saveInsolvenzVerwalter(widget.vorfallId, {
      'rechtsanwalt_id': _raId,
      'rolle': _rolle,
      'sachbearbeiter': _sachbearbeiter.text.trim(),
      'sachbearbeiter_tel': _durchwahl.text.trim(),
      'notiz': _notiz.text.trim(),
      'bestellt_am': _bestellt.text.trim(),
      'ende_am': _ende.text.trim(),
    });
    if (!mounted) return;
    setState(() => _saving = false);
    final ok = r['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Insolvenzverwaltung gespeichert' : (r['message'] ?? 'Fehler').toString()),
      backgroundColor: ok ? Colors.green : Colors.red));
    if (ok) _load();
  }

  /// Die ausgewählte Kanzlei — erst aus dem Nachschlagewerk, sonst aus dem
  /// Block, den der Server mitgeliefert hat. Der Rückfall zählt: eine Kanzlei
  /// kann inzwischen stillgelegt worden sein und fehlt dann in der Liste,
  /// steht aber weiterhin in diesem Verfahren.
  Map<String, dynamic>? get _kanzlei {
    if (_raId == null) return null;
    for (final k in _kanzleien) {
      if (k['id'] == _raId) return k;
    }
    final vom = _verwalter['kanzlei'];
    return vom is Map ? Map<String, dynamic>.from(vom) : null;
  }

  bool get _verwalterErfasst => _kanzlei != null;

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      TabBar(
        controller: _sub,
        labelColor: F.h(widget.color, 700),
        unselectedLabelColor: F.h(Colors.grey, 600),
        indicatorColor: widget.color.shade700,
        tabs: [
          Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, size: 8, color: _verwalterErfasst ? Colors.green : Colors.red),
            const SizedBox(width: 4), const Icon(Icons.person_search, size: 14), const SizedBox(width: 4),
            const Flexible(child: Text('Zuständige Insolvenzverwaltung', overflow: TextOverflow.ellipsis)),
          ])),
          Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, size: 8, color: _akten.isNotEmpty ? Colors.green : Colors.red),
            const SizedBox(width: 4), const Icon(Icons.tag, size: 14), const SizedBox(width: 4),
            Flexible(child: Text('Aktenzeichen (${_akten.length})', overflow: TextOverflow.ellipsis)),
          ])),
        ],
      ),
      Expanded(child: TabBarView(controller: _sub, children: [
        _buildVerwalter(),
        _buildAkten(),
      ])),
    ]);
  }

  // ── Unterreiter 1: die bestellte Kanzlei, per Lupe aus dem Nachschlagewerk ──
  Widget _buildVerwalter() {
    final k = _kanzlei;
    return SingleChildScrollView(padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.gavel, size: 20, color: F.h(widget.color, 700)), const SizedBox(width: 8),
          Expanded(child: Text('Zuständige Insolvenzverwaltung',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: F.h(widget.color, 700)))),
          OutlinedButton.icon(
            icon: const Icon(Icons.search, size: 16),
            label: Text(k == null ? 'Auswählen' : 'Ändern', style: const TextStyle(fontSize: 12)),
            onPressed: _kanzleiWaehlen,
          ),
        ]),
        const SizedBox(height: 12),
        if (k == null)
          Container(
            width: double.infinity, padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: F.h(Colors.grey, 50),
              borderRadius: BorderRadius.circular(10), border: Border.all(color: F.h(Colors.grey, 300))),
            child: Column(children: [
              Icon(Icons.search, size: 40, color: F.h(Colors.grey, 400)), const SizedBox(height: 8),
              Text('Keine Insolvenzverwaltung ausgewählt',
                style: TextStyle(fontSize: 13, color: F.h(Colors.grey, 600))),
              const SizedBox(height: 4),
              Text('Tippen Sie auf „Auswählen" — gesucht wird in der Rechtsanwaltsdatenbank.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 500))),
            ]),
          )
        else
          _kanzleiKarte(k),
        const SizedBox(height: 16),
        Text('Angaben zu diesem Verfahren',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: F.h(Colors.grey, 700))),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _rolle,
          decoration: const InputDecoration(labelText: 'Stellung im Verfahren',
            border: OutlineInputBorder(), isDense: true),
          style: TextStyle(fontSize: 13, color: F.textStark),
          items: kInsolvenzRollen.entries
              .map((e) => DropdownMenuItem(value: e.key,
                    child: Text(e.value, style: const TextStyle(fontSize: 13))))
              .toList(),
          onChanged: (v) => setState(() => _rolle = v ?? 'verwalter'),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: _bestellt, style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(labelText: 'Bestellt am', hintText: 'JJJJ-MM-TT',
              isDense: true, border: OutlineInputBorder()))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _ende, style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(labelText: 'Ende der Bestellung', hintText: 'JJJJ-MM-TT',
              isDense: true, border: OutlineInputBorder()))),
        ]),
        const SizedBox(height: 10),
        // Wer in der Kanzlei die Akte führt, gehört zum Verfahren, nicht zum
        // Kanzleischild — am Telefon erreicht man fast nie die bestellte Person.
        TextField(controller: _sachbearbeiter, style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(labelText: 'Sachbearbeitung in der Kanzlei',
            isDense: true, border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: _durchwahl, style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(labelText: 'Durchwahl der Sachbearbeitung',
            isDense: true, border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: _notiz, maxLines: 3, style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(labelText: 'Notiz', isDense: true,
            border: OutlineInputBorder())),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: widget.color),
          icon: _saving
              ? const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save, size: 16),
          label: const Text('Speichern'),
          onPressed: _saving ? null : _speichern,
        )),
      ]));
  }

  /// Die Karte zur ausgewählten Kanzlei — wie beim zuständigen Gericht.
  Widget _kanzleiKarte(Map<String, dynamic> k) {
    String f(String s) => (k[s] ?? '').toString();
    final anschrift = [f('strasse'), f('plz_ort')].where((e) => e.isNotEmpty).join(', ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: F.h(widget.color, 50), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: F.h(widget.color, 300))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(f('firmenname'),
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: F.h(widget.color, 900))),
        if (f('anwalt_name').isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 2),
            child: Text(f('anwalt_name'),
              style: TextStyle(fontSize: 12, color: F.h(widget.color, 700)))),
        const SizedBox(height: 6),
        if (anschrift.isNotEmpty) _kRow(Icons.location_on, 'Anschrift', anschrift),
        if (f('telefon').isNotEmpty) _kRow(Icons.phone, 'Telefon', f('telefon')),
        if (f('fax').isNotEmpty) _kRow(Icons.print, 'Fax', f('fax')),
        if (f('email').isNotEmpty) _kRow(Icons.email, 'E-Mail', f('email')),
        if (f('website').isNotEmpty) _kRow(Icons.language, 'Internet', f('website')),
        // beA und Kammer sind kein Beiwerk: über das besondere elektronische
        // Anwaltspostfach läuft der Schriftverkehr, und die Kammer ist die
        // Aufsicht nach § 73 BRAO — der Ort für eine Beschwerde.
        if (f('bea_safe_id').isNotEmpty) _kRow(Icons.mark_email_read, 'beA SAFE-ID', f('bea_safe_id')),
        if (f('rechtsanwaltskammer').isNotEmpty)
          _kRow(Icons.account_balance, 'Kammer', f('rechtsanwaltskammer')),
        if (f('fachgebiete').isNotEmpty) _kRow(Icons.workspace_premium, 'Fachgebiete', f('fachgebiete')),
      ]));
  }

  Widget _kRow(IconData icon, String label, String wert) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 14, color: F.h(Colors.grey, 600)), const SizedBox(width: 8),
      SizedBox(width: 96, child: Text(label,
        style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600), fontWeight: FontWeight.w600))),
      Expanded(child: phoneAwareText(icon, wert, label: label, style: const TextStyle(fontSize: 12))),
    ]));

  /// Suchdialog über das Nachschlagewerk — dasselbe Muster wie beim
  /// zuständigen Gericht, aber mit Filterfeld: die Kanzleiliste wächst.
  void _kanzleiWaehlen() {
    final suche = TextEditingController();
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      final q = suche.text.trim().toLowerCase();
      final treffer = q.isEmpty ? _kanzleien : _kanzleien.where((k) =>
          ['firmenname', 'anwalt_name', 'plz_ort', 'fachgebiete']
              .any((f) => (k[f] ?? '').toString().toLowerCase().contains(q))).toList();
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(children: [
          Icon(Icons.search, color: F.h(widget.color, 700)), const SizedBox(width: 8),
          const Expanded(child: Text('Insolvenzverwaltung auswählen', style: TextStyle(fontSize: 16))),
        ]),
        content: SizedBox(width: 520, height: 440, child: Column(children: [
          TextField(
            controller: suche,
            autofocus: true,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'Kanzlei, Name, Ort oder Fachgebiet …',
              prefixIcon: Icon(Icons.search, size: 18), isDense: true,
              border: OutlineInputBorder()),
            onChanged: (_) => setLocal(() {}),
          ),
          const SizedBox(height: 10),
          if (_kanzleien.isEmpty)
            Expanded(child: Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(
              'Die Rechtsanwaltsdatenbank ist leer. Kanzleien werden in der '
              'Vertragsverwaltung gepflegt — dort angelegt, stehen sie hier zur Auswahl.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600))))))
          else if (treffer.isEmpty)
            Expanded(child: Center(child: Text('Kein Treffer',
              style: TextStyle(fontSize: 13, color: F.h(Colors.grey, 500)))))
          else
            Expanded(child: ListView.builder(
              itemCount: treffer.length,
              itemBuilder: (_, i) {
                final k = treffer[i];
                final gewaehlt = k['id'] == _raId;
                return InkWell(
                  onTap: () {
                    setState(() => _raId = k['id'] as int?);
                    Navigator.pop(ctx);
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: gewaehlt ? F.h(widget.color, 50) : F.flaeche,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: gewaehlt ? widget.color.shade400 : F.h(Colors.grey, 300))),
                    child: Row(children: [
                      Icon(Icons.gavel, size: 20, color: F.h(widget.color, 600)),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text((k['firmenname'] ?? '').toString(),
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
                            color: F.h(widget.color, 900))),
                        if ((k['anwalt_name'] ?? '').toString().isNotEmpty)
                          Text((k['anwalt_name']).toString(),
                            style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700))),
                        if ((k['plz_ort'] ?? '').toString().isNotEmpty)
                          Text((k['plz_ort']).toString(),
                            style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
                        if ((k['fachgebiete'] ?? '').toString().isNotEmpty)
                          Text((k['fachgebiete']).toString(),
                            style: TextStyle(fontSize: 10, color: widget.color.shade400,
                              fontStyle: FontStyle.italic)),
                      ])),
                      if (gewaehlt) Icon(Icons.check_circle, size: 18, color: F.h(widget.color, 600)),
                    ]),
                  ),
                );
              })),
        ])),
        actions: [
          if (_raId != null) TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () { setState(() => _raId = null); Navigator.pop(ctx); },
            child: const Text('Auswahl entfernen')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        ],
      );
    }));
  }

  // ── Unterreiter 2: die Aktenzeichen ──
  Widget _buildAkten() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Expanded(child: Text('${_akten.length} Aktenzeichen',
          style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600)))),
        FilledButton.icon(
          icon: const Icon(Icons.add, size: 14),
          label: const Text('Neues Aktenzeichen', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: widget.color,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _akteDialog(),
        ),
      ])),
      Expanded(child: _akten.isEmpty
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.tag, size: 36, color: F.h(Colors.grey, 300)),
            const SizedBox(height: 8),
            Text('Noch kein Aktenzeichen erfasst', style: TextStyle(color: F.h(Colors.grey, 500), fontSize: 13)),
            const SizedBox(height: 4),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: Text(
              'Das Gericht führt die Sache unter „123 IN 456/24", die Kanzlei unter ihrem '
              'eigenen Zeichen. Beide gehören hierher.',
              textAlign: TextAlign.center,
              style: TextStyle(color: F.h(Colors.grey, 400), fontSize: 11))),
          ]))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _akten.length,
            itemBuilder: (_, i) {
              final a = _akten[i];
              final azG = (a['az_gericht'] ?? '').toString();
              final azV = (a['az_verwalter'] ?? '').toString();
              final art = insolvenzVerfahrensart((a['registerzeichen'] ?? '').toString());
              final status = (a['status'] ?? 'laufend').toString();
              return Card(child: ListTile(
                leading: CircleAvatar(radius: 16, backgroundColor: F.h(widget.color, 50),
                  child: Text((a['registerzeichen'] ?? '?').toString(),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: F.h(widget.color, 700)))),
                title: Text(azG.isNotEmpty ? azG : (a['bezeichnung'] ?? 'Ohne Aktenzeichen').toString(),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (azV.isNotEmpty) Text('Kanzlei: $azV', style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700))),
                  Text([
                    if (art != null) art,
                    if (kInsolvenzPhasen[(a['phase'] ?? '').toString()] != null)
                      kInsolvenzPhasen[(a['phase'] ?? '').toString()]!,
                    status,
                  ].join(' · '), style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
                ]),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if ((a['korr_anzahl'] ?? 0) != 0)
                    _zaehler(Icons.mail_outline, a['korr_anzahl']),
                  if ((a['doc_anzahl'] ?? 0) != 0)
                    _zaehler(Icons.attach_file, a['doc_anzahl']),
                  const Icon(Icons.chevron_right, size: 18),
                ]),
                onTap: () => _akteOeffnen(a),
              ));
            })),
    ]);
  }

  Widget _zaehler(IconData icon, dynamic n) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: F.h(Colors.grey, 600)),
      const SizedBox(width: 2),
      Text('$n', style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
    ]));

  void _akteOeffnen(Map<String, dynamic> akte) {
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;
    showDialog(context: context, builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding: const EdgeInsets.all(12),
      child: SizedBox(
        // Auf dem Telefon ist der Bildschirm die Obergrenze, nicht 900 dp —
        // sonst quetscht sich der Inhalt lautlos zusammen.
        width: w < 900 ? w : 900,
        height: h < 700 ? h * 0.92 : 700,
        child: _InsolvenzAkteDetailView(
          apiService: widget.apiService,
          userId: widget.userId,
          vorfallId: widget.vorfallId,
          akte: akte,
          color: widget.color,
          adminMitgliedernummer: widget.adminMitgliedernummer,
          onEdit: () { Navigator.pop(ctx); _akteDialog(bestehend: akte); },
          onChanged: _load,
        ),
      ),
    ));
  }

  void _akteDialog({Map<String, dynamic>? bestehend}) {
    final istNeu = bestehend == null;
    final bez = TextEditingController(text: (bestehend?['bezeichnung'] ?? '').toString());
    final azG = TextEditingController(text: (bestehend?['az_gericht'] ?? '').toString());
    final azV = TextEditingController(text: (bestehend?['az_verwalter'] ?? '').toString());
    final erff = TextEditingController(text: (bestehend?['eroeffnet_am'] ?? '').toString());
    final ende = TextEditingController(text: (bestehend?['ende_am'] ?? '').toString());
    final notiz = TextEditingController(text: (bestehend?['notiz'] ?? '').toString());
    String? phase = kInsolvenzPhasen.containsKey((bestehend?['phase'] ?? '').toString())
        ? bestehend!['phase'].toString() : null;
    String status = kInsolvenzAkteStatus.containsKey((bestehend?['status'] ?? '').toString())
        ? bestehend!['status'].toString() : 'laufend';

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      final reg = insolvenzRegisterzeichen(azG.text);
      final art = insolvenzVerfahrensart(reg);
      return AlertDialog(
        title: Text(istNeu ? 'Neues Aktenzeichen' : 'Aktenzeichen bearbeiten',
          style: TextStyle(color: F.h(widget.color, 700), fontSize: 16)),
        content: SizedBox(width: 460, child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: bez, style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(labelText: 'Bezeichnung', isDense: true,
                hintText: 'z. B. Verbraucherinsolvenzverfahren', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: azG, style: const TextStyle(fontSize: 13),
              onChanged: (_) => setLocal(() {}),
              decoration: const InputDecoration(labelText: 'Aktenzeichen des Gerichts',
                hintText: '123 IN 456/24', isDense: true, border: OutlineInputBorder())),
            // Sofortige Rückmeldung, was aus dem Aktenzeichen folgt. Erkennt
            // der Ausdruck nichts, bleibt es dabei — geraten wird nicht.
            if (art != null) Padding(padding: const EdgeInsets.only(top: 4),
              child: Align(alignment: Alignment.centerLeft, child: Text('→ $art',
                style: TextStyle(fontSize: 11, color: F.h(Colors.green, 700))))),
            const SizedBox(height: 10),
            TextField(controller: azV, style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(labelText: 'Aktenzeichen der Kanzlei',
                hintText: 'steht in deren Schreiben unter der Anschrift',
                isDense: true, border: OutlineInputBorder())),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: phase,
              decoration: const InputDecoration(labelText: 'Verfahrensabschnitt',
                isDense: true, border: OutlineInputBorder()),
              style: TextStyle(fontSize: 13, color: F.textStark),
              items: kInsolvenzPhasen.entries
                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13))))
                  .toList(),
              onChanged: (v) => setLocal(() => phase = v),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: status,
              decoration: const InputDecoration(labelText: 'Status', isDense: true, border: OutlineInputBorder()),
              style: TextStyle(fontSize: 13, color: F.textStark),
              items: kInsolvenzAkteStatus.entries
                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13))))
                  .toList(),
              onChanged: (v) => setLocal(() => status = v ?? 'laufend'),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: erff, style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(labelText: 'Eröffnet am', hintText: 'JJJJ-MM-TT',
                  isDense: true, border: OutlineInputBorder()))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: ende, style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(labelText: 'Beendet am', hintText: 'JJJJ-MM-TT',
                  isDense: true, border: OutlineInputBorder()))),
            ]),
            const SizedBox(height: 10),
            TextField(controller: notiz, maxLines: 3, style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder())),
          ]))),
        actions: [
          if (!istNeu) TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              final r = await widget.apiService.deleteInsolvenzAkte(bestehend['id'] as int);
              if (!ctx.mounted) return;
              if (r['success'] == true) {
                Navigator.pop(ctx);
                _load();
              } else {
                // ⚠️ Der Server lehnt das Löschen ab, solange eine Vollmacht
                // dieses Aktenzeichen nennt. Die Begründung gehört auf den
                // Schirm — ein stiller Fehlschlag sähe aus wie ein Defekt.
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                  content: Text((r['message'] ?? 'Löschen nicht möglich').toString()),
                  backgroundColor: Colors.red, duration: const Duration(seconds: 6)));
              }
            },
            child: const Text('Löschen')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: widget.color),
            onPressed: () async {
              final daten = <String, dynamic>{
                if (!istNeu) 'id': bestehend['id'],
                if (istNeu) 'vorfall_id': widget.vorfallId,
                'bezeichnung': bez.text.trim(),
                'az_gericht': azG.text.trim(),
                'az_verwalter': azV.text.trim(),
                'phase': phase ?? '',
                'status': status,
                'eroeffnet_am': erff.text.trim(),
                'ende_am': ende.text.trim(),
                'notiz': notiz.text.trim(),
              };
              final r = await widget.apiService.saveInsolvenzAkte(daten);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (r['success'] != true && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text((r['message'] ?? 'Speichern fehlgeschlagen').toString()),
                  backgroundColor: Colors.red));
              }
              _load();
            },
            child: const Text('Speichern')),
        ],
      );
    }));
  }
}

// ============================================================================
// EIN AKTENZEICHEN — Details · Korrespondenz · Unterlagen · Vollmacht.
//
// Dieselbe Aufteilung wie beim Vorfall eine Ebene höher, nur enger gefasst:
// hier hängt alles am Aktenzeichen, unter dem die Verwalterkanzlei die Sache
// führt. Was an dieser Akte liegt, gehört in den Umschlag, der an sie geht.
// ============================================================================
class _InsolvenzAkteDetailView extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int vorfallId;
  final Map<String, dynamic> akte;
  final MaterialColor color;
  final String adminMitgliedernummer;
  final VoidCallback onEdit;
  final VoidCallback onChanged;
  const _InsolvenzAkteDetailView({
    required this.apiService,
    required this.userId,
    required this.vorfallId,
    required this.akte,
    required this.color,
    required this.onEdit,
    required this.onChanged,
    this.adminMitgliedernummer = '',
  });

  @override
  State<_InsolvenzAkteDetailView> createState() => _InsolvenzAkteDetailViewState();
}

class _InsolvenzAkteDetailViewState extends State<_InsolvenzAkteDetailView> {
  bool _loaded = false;
  bool _standLaeuft = false;
  List<Map<String, dynamic>> _korr = [];
  List<Map<String, dynamic>> _docs = [];

  /// Was `type=quellen` über die anderen Module gemeldet hat:
  /// kategorie → {wo, anzahl, zustand}.
  Map<String, Map<String, dynamic>> _quellen = {};

  int get _akteId => widget.akte['id'] as int;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final k = await widget.apiService.listInsolvenzAkteKorr(_akteId);
    final d = await widget.apiService.listInsolvenzAkteDocs(_akteId);
    final q = await widget.apiService.listInsolvenzUnterlagenQuellen(widget.userId);
    if (!mounted) return;
    setState(() {
      _korr = (k['data'] is List)
          ? (k['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList() : [];
      _docs = (d['data'] is List)
          ? (d['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList() : [];
      // ⚠️ PHP kennt nur einen Array-Typ: eine leere Liste kommt als `[]`
      // heraus, nicht als `{}`. Ein `as Map` würde darauf nicht null
      // liefern, sondern WERFEN — und im Release-Build bliebe nur eine graue
      // Fläche ohne Meldung. Der Server codiert deshalb mit (object), und
      // hier wird trotzdem geprüft: die Codierung ist eine Nebenwirkung der
      // Schlüssel, kein Vertrag.
      final roh = q['quellen'];
      _quellen = roh is Map
          ? roh.map((s, v) => MapEntry(s.toString(),
              v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{}))
          : <String, Map<String, dynamic>>{};
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.akte;
    final azG = (a['az_gericht'] ?? '').toString();
    final azV = (a['az_verwalter'] ?? '').toString();
    return DefaultTabController(length: 4, child: Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: widget.color.shade700,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
        child: Row(children: [
          const Icon(Icons.tag, color: Colors.white, size: 22), const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(azG.isNotEmpty ? azG : (a['bezeichnung'] ?? 'Aktenzeichen').toString(),
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            Text([
              if (azV.isNotEmpty) 'Kanzlei: $azV',
              if (kInsolvenzPhasen[(a['phase'] ?? '').toString()] != null)
                kInsolvenzPhasen[(a['phase'] ?? '').toString()]!,
              (a['status'] ?? 'laufend').toString(),
            ].join(' • '), style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ])),
          IconButton(icon: const Icon(Icons.edit, color: Colors.white, size: 20),
            tooltip: 'Bearbeiten', onPressed: widget.onEdit),
          IconButton(icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context)),
        ]),
      ),
      TabBar(labelColor: F.h(widget.color, 700), indicatorColor: widget.color.shade700,
        isScrollable: true, tabs: const [
          Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Details'),
          Tab(icon: Icon(Icons.mail, size: 18), text: 'Korrespondenz'),
          Tab(icon: Icon(Icons.folder, size: 18), text: 'Unterlagen'),
          Tab(icon: Icon(Icons.assignment_ind, size: 18), text: 'Vollmacht'),
        ]),
      Expanded(child: !_loaded
        ? const Center(child: CircularProgressIndicator())
        : TabBarView(children: [
            _buildDetails(),
            _buildKorrespondenz(),
            _buildUnterlagen(),
            _GerichtVollmachtTab(
              apiService: widget.apiService,
              userId: widget.userId,
              vorfallId: widget.vorfallId,
              gerichtTyp: 'insolvenzgericht',
              color: widget.color,
              // Diese Fassung geht an die Verwaltung, nicht an das Gericht:
              // Erklärungen ihr gegenüber sind §§ 164 ff. BGB und brauchen
              // keine Vertretungsbefugnis. Die vollständige Begründung steht
              // in vollmacht_gericht_lib.php und wird von dort angezeigt.
              adressat: 'insolvenzverwalter',
              insolvenzAkteId: _akteId,
              adminMitgliedernummer: widget.adminMitgliedernummer,
              akteBezeichnung: [
                (widget.akte['az_verwalter'] ?? '').toString().trim(),
                (widget.akte['az_gericht'] ?? '').toString().trim(),
              ].where((e) => e.isNotEmpty).join(' · '),
            ),
          ])),
    ]));
  }

  // ── Details ──
  Widget _buildDetails() {
    final a = widget.akte;
    final reg = (a['registerzeichen'] ?? '').toString();
    final art = insolvenzVerfahrensart(reg);
    return SingleChildScrollView(padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _zeile(Icons.description, 'Bezeichnung', a['bezeichnung']),
        _zeile(Icons.gavel, 'Az. des Gerichts', a['az_gericht']),
        _zeile(Icons.business_center, 'Az. der Kanzlei', a['az_verwalter']),
        if (art != null) _zeile(Icons.category, 'Verfahrensart', '$art (Registerzeichen $reg)'),
        _zeile(Icons.timeline, 'Abschnitt', kInsolvenzPhasen[(a['phase'] ?? '').toString()]),
        _zeile(Icons.flag, 'Status', kInsolvenzAkteStatus[(a['status'] ?? '').toString()]),
        _zeile(Icons.event_available, 'Eröffnet am', a['eroeffnet_am']),
        _zeile(Icons.event_busy, 'Beendet am', a['ende_am']),
        if ((a['notiz']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(width: double.infinity, padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: F.h(Colors.yellow, 50), borderRadius: BorderRadius.circular(8)),
            child: Text(a['notiz'].toString(), style: const TextStyle(fontSize: 12))),
        ],
        if (art == null && (a['az_gericht']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: F.h(Colors.orange, 50), borderRadius: BorderRadius.circular(8),
              border: Border.all(color: F.h(Colors.orange, 200))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.help_outline, size: 16, color: F.h(Colors.orange, 800)),
              const SizedBox(width: 8),
              Expanded(child: Text(
                'Aus diesem Aktenzeichen lässt sich die Verfahrensart nicht ablesen. '
                'Erwartet wird die Form „123 IN 456/24" — IN für die Regelinsolvenz, '
                'IK für die Verbraucherinsolvenz.',
                style: TextStyle(fontSize: 11, color: F.h(Colors.orange, 900)))),
            ])),
        ],
      ]));
  }

  Widget _zeile(IconData icon, String label, dynamic wert) {
    final s = wert?.toString() ?? '';
    if (s.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
      Icon(icon, size: 14, color: F.h(Colors.grey, 600)), const SizedBox(width: 8),
      SizedBox(width: 130, child: Text(label,
        style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600), fontWeight: FontWeight.w600))),
      Expanded(child: Text(s, style: const TextStyle(fontSize: 13))),
    ]));
  }

  // ── Korrespondenz ──
  Widget _buildKorrespondenz() {
    final offen = _korr.where((k) => k['erledigt'] != true).length;
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Expanded(child: Text(
          '${_korr.length} Einträge${offen > 0 ? ' · $offen offen' : ''}',
          style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600)))),
        // Der Zustellstand kommt aus dem Postfix-Protokoll und ändert sich
        // Minuten nach dem Versand — deshalb von Hand nachfragbar.
        if (_korr.any((k) => (k['mail_message_id'] ?? '').toString().isNotEmpty))
          IconButton(
            icon: _standLaeuft
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh, size: 18),
            tooltip: 'Zustellstand nachfragen',
            onPressed: _standLaeuft ? null : _zustellstand,
          ),
        FilledButton.icon(icon: const Icon(Icons.add, size: 14),
          label: const Text('Neuer Eintrag', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: widget.color,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _korrDialog()),
      ])),
      Expanded(child: _korr.isEmpty
        ? Center(child: Text('Keine Korrespondenz', style: TextStyle(color: F.h(Colors.grey, 500))))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _korr.length,
            itemBuilder: (_, i) {
              final k = _korr[i];
              final eingang = (k['richtung'] ?? 'eingang') == 'eingang';
              final erledigt = k['erledigt'] == true;
              return Card(child: InkWell(
                // ⚠️ Die ganze Zeile öffnet den Inhalt. Vorher war sie eine
                // Notiz ÜBER eine Mail: Betreff, Weg, Partner — und wer sie
                // antippte, bekam nichts. Ausgerechnet der wichtigste
                // Schriftwechsel der Akte war der einzige ohne Inhalt.
                onTap: () => _korrOeffnen(k),
                child: Padding(padding: const EdgeInsets.all(10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(eingang ? Icons.call_received : Icons.call_made, size: 16,
                      color: eingang ? F.h(Colors.blue, 700) : F.h(Colors.green, 700)),
                    const SizedBox(width: 6),
                    Expanded(child: Text((k['betreff'] ?? '').toString(),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                        color: erledigt ? F.h(Colors.grey, 600) : null,
                        decoration: erledigt ? TextDecoration.lineThrough : null))),
                    Text((k['datum'] ?? '').toString(),
                      style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
                    // Erledigt-Haken direkt in der Zeile: der häufigste
                    // Handgriff soll keinen Dialog kosten.
                    IconButton(
                      icon: Icon(erledigt ? Icons.check_circle : Icons.circle_outlined,
                        size: 17, color: erledigt ? F.h(Colors.green, 600) : F.h(Colors.grey, 400)),
                      tooltip: erledigt ? 'Als offen markieren' : 'Als erledigt markieren',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () => _korrErledigt(k, !erledigt)),
                    IconButton(icon: Icon(Icons.edit_outlined, size: 16, color: F.h(widget.color, 600)),
                      tooltip: 'Bearbeiten', padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () => _korrDialog(bestehend: k)),
                    IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400),
                      tooltip: 'Löschen', padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () => _korrLoeschen(k)),
                  ]),
                  Wrap(spacing: 10, children: [
                    if ((k['methode']?.toString() ?? '').isNotEmpty)
                      Text(k['methode'].toString(),
                        style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
                    // Mit WEM gesprochen wurde — „ich habe Montag angerufen"
                    // hilft niemandem, ein Name schon.
                    if ((k['gespraechspartner']?.toString() ?? '').isNotEmpty)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.person, size: 12, color: F.h(Colors.grey, 600)),
                        const SizedBox(width: 3),
                        Text(k['gespraechspartner'].toString(),
                          style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700))),
                      ]),
                  ]),
                  if ((k['notiz']?.toString() ?? '').isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 4),
                      child: Text(k['notiz'].toString(), style: const TextStyle(fontSize: 12))),
                  _zustellzeile(k),
                  const SizedBox(height: 6),
                  KorrAttachmentsWidget(apiService: widget.apiService, modul: 'insolvenz_akte',
                    korrespondenzId: k['id'] as int, memberId: widget.userId),
                ]))));
            })),
    ]);
  }

  /// Was der Server der Kanzlei geantwortet hat.
  ///
  /// ⚠️ Nicht zu verwechseln mit „abgeschickt": dass unser eigener Server die
  /// Nachricht angenommen hat, sagt nichts darüber, ob die Gegenseite sie
  /// genommen hat. Genau dieser Unterschied ist der Grund für die Zeile —
  /// sonst hält man eine abgewiesene Mail für zugestellt.
  void _melden(String text, Color farbe) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text), backgroundColor: farbe));

  /// Zeigt, WAS geschickt wurde — Text und Anlage.
  ///
  /// ⚠️ Die Anlage wird nicht mitgeliefert, sondern beschrieben: das
  /// unterschriebene PDF liegt beim Signaturvorgang und wird von dort geholt.
  /// Eine zweite Kopie wäre ein zweiter Ort, an dem dasselbe Dokument altert.
  Future<void> _korrOeffnen(Map<String, dynamic> k) async {
    final id = k['id'] is int ? k['id'] as int : int.tryParse('${k['id']}') ?? 0;
    if (id <= 0) return;
    final res = await widget.apiService.insolvenzKorrNachricht(id);
    if (!mounted) return;
    if (res['success'] != true) {
      _melden('${res['message'] ?? 'Konnte nicht geladen werden'}', Colors.red);
      return;
    }
    final text = '${res['nachricht'] ?? ''}'.trim();
    final anhang = res['anhang'] is Map ? Map<String, dynamic>.from(res['anhang'] as Map) : null;
    final breite = MediaQuery.of(context).size.width;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${res['betreff'] ?? ''}', style: const TextStyle(fontSize: 14)),
        content: SizedBox(
          width: breite < 620 ? breite * 0.88 : 540,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
              children: [
                Text('${res['datum'] ?? ''} · ${res['empfaenger'] ?? ''}',
                    style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700))),
                const Divider(height: 16),
                if (text.isEmpty)
                  Text('Für diese Zeile wurde kein Text gespeichert.',
                      style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic,
                          color: F.h(Colors.grey, 600)))
                else
                  SelectableText(text, style: const TextStyle(fontSize: 12.5, height: 1.35)),
                if (anhang != null) ...[
                  const Divider(height: 20),
                  Text('Anlage', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                      color: F.h(Colors.grey, 700))),
                  const SizedBox(height: 4),
                  // ⚠️ Der Knopf sagt die Wahrheit über die Verfügbarkeit: der
                  // Siegel-Cron läuft alle paar Minuten. Ohne `bereit` führte
                  // er ins Leere und der Fehler sähe nach einem Defekt aus.
                  if (anhang['bereit'] == true)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.picture_as_pdf, size: 15),
                      label: Text('${anhang['titel'] ?? 'Anlage'}',
                          style: const TextStyle(fontSize: 11.5)),
                      onPressed: () => _anhangOeffnen(anhang),
                    )
                  else
                    Text('${anhang['titel'] ?? 'Anlage'} — wird noch gesiegelt',
                        style: TextStyle(fontSize: 11.5, color: F.h(Colors.orange, 800))),
                ],
              ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen')),
        ],
      ),
    );
  }

  Future<void> _anhangOeffnen(Map<String, dynamic> anhang) async {
    final sigId = anhang['signatur_id'] is int
        ? anhang['signatur_id'] as int
        : int.tryParse('${anhang['signatur_id']}') ?? 0;
    if (sigId <= 0 || widget.adminMitgliedernummer.isEmpty) return;
    final bytes = await SignaturService().herunterladen(
      callerMitgliedernummer: widget.adminMitgliedernummer,
      signaturId: sigId,
      welche: 'signiert',
    );
    if (!mounted) return;
    if (bytes == null) {
      _melden('Die unterschriebene Fassung ist noch nicht abrufbar', Colors.orange);
      return;
    }
    await FileViewerDialog.showFromBytes(
        context, Uint8List.fromList(bytes), 'vollmacht_unterschrieben_$sigId.pdf');
  }

  Widget _zustellzeile(Map<String, dynamic> k) {
    if ((k['mail_message_id'] ?? '').toString().isEmpty) return const SizedBox.shrink();
    final stand = (k['mail_status'] ?? '').toString();
    final (IconData ikone, Color farbe, String wort) = switch (stand) {
      'sent'     => (Icons.mark_email_read, Colors.green.shade700, 'zugestellt'),
      'deferred' => (Icons.schedule, Colors.orange.shade700, 'verzögert — wird erneut versucht'),
      'bounced'  => (Icons.error_outline, Colors.red.shade700, 'abgewiesen'),
      ''         => (Icons.hourglass_empty, Colors.grey.shade600, 'noch keine Rückmeldung'),
      _          => (Icons.info_outline, Colors.grey.shade700, stand),
    };
    final antwort = (k['mail_antwort'] ?? '').toString();
    final wann = (k['mail_zugestellt_am'] ?? '').toString();
    return Padding(padding: const EdgeInsets.only(top: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(ikone, size: 13, color: farbe), const SizedBox(width: 4),
        // Die Antwort des fremden Servers im Wortlaut: bei einer Abweisung
        // steht dort der Grund, und den will man nicht raten müssen.
        Expanded(child: Text(
          'E-Mail: $wort${wann.isEmpty ? '' : ' ($wann)'}'
          '${antwort.isEmpty ? '' : '\n$antwort'}',
          style: TextStyle(fontSize: 10, color: farbe))),
      ]));
  }

  Future<void> _zustellstand() async {
    setState(() => _standLaeuft = true);
    await widget.apiService.insolvenzKorrMailStatus(_akteId);
    if (!mounted) return;
    setState(() => _standLaeuft = false);
    // Der Endpunkt schreibt den Stand in die Tabelle; gelesen wird er beim
    // Neuladen der Liste — so gibt es nur eine Quelle für die Anzeige.
    _load();
  }

  Future<void> _korrErledigt(Map<String, dynamic> k, bool erledigt) async {
    await widget.apiService.saveInsolvenzAkteKorr(_akteId, {
      'id': k['id'],
      'richtung': k['richtung'] ?? 'eingang',
      'methode': (k['methode'] ?? '').toString(),
      'gespraechspartner': (k['gespraechspartner'] ?? '').toString(),
      'datum': (k['datum'] ?? '').toString(),
      'betreff': (k['betreff'] ?? '').toString(),
      'notiz': (k['notiz'] ?? '').toString(),
      'erledigt': erledigt,
    });
    _load(); widget.onChanged();
  }

  Future<void> _korrLoeschen(Map<String, dynamic> k) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Eintrag löschen?', style: TextStyle(fontSize: 16)),
      content: const Text(
        'Die angehängten Dateien werden mitgelöscht — sie hängen an diesem Eintrag. '
        'Für einen Tippfehler genügt „Bearbeiten".',
        style: TextStyle(fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        TextButton(style: TextButton.styleFrom(foregroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
      ]));
    if (ok != true) return;
    await widget.apiService.deleteInsolvenzAkteKorr(k['id'] as int);
    _load(); widget.onChanged();
  }

  void _korrDialog({Map<String, dynamic>? bestehend}) {
    final istNeu = bestehend == null;
    String richtung = (bestehend?['richtung'] ?? 'eingang').toString();
    final methode = TextEditingController(text: (bestehend?['methode'] ?? '').toString());
    final partner = TextEditingController(text: (bestehend?['gespraechspartner'] ?? '').toString());
    final datum = TextEditingController(text: (bestehend?['datum'] ?? '').toString().isNotEmpty
        ? bestehend!['datum'].toString()
        : DateTime.now().toIso8601String().substring(0, 10));
    final betreff = TextEditingController(text: (bestehend?['betreff'] ?? '').toString());
    final notiz = TextEditingController(text: (bestehend?['notiz'] ?? '').toString());
    bool erledigt = bestehend?['erledigt'] == true;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) => AlertDialog(
      title: Text(istNeu ? 'Korrespondenz erfassen' : 'Korrespondenz bearbeiten',
        style: TextStyle(color: F.h(widget.color, 700), fontSize: 16)),
      content: SizedBox(width: 420, child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'eingang', label: Text('Eingang'), icon: Icon(Icons.call_received, size: 14)),
              ButtonSegment(value: 'ausgang', label: Text('Ausgang'), icon: Icon(Icons.call_made, size: 14)),
            ],
            selected: {richtung},
            onSelectionChanged: (s) => setLocal(() => richtung = s.first),
          ),
          const SizedBox(height: 10),
          TextField(controller: betreff, style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(labelText: 'Betreff', isDense: true, border: OutlineInputBorder())),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: datum, style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(labelText: 'Datum', hintText: 'JJJJ-MM-TT',
                isDense: true, border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: methode, style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(labelText: 'Weg', hintText: 'Brief, E-Mail, Telefon',
                isDense: true, border: OutlineInputBorder()))),
          ]),
          const SizedBox(height: 10),
          TextField(controller: partner, style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(labelText: 'Gesprächspartner',
              hintText: 'wer in der Kanzlei — nicht „die Kanzlei"',
              isDense: true, border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: notiz, maxLines: 3, style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder())),
          CheckboxListTile(
            dense: true, contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Erledigt', style: TextStyle(fontSize: 13)),
            value: erledigt,
            onChanged: (v) => setLocal(() => erledigt = v ?? false),
          ),
        ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: widget.color),
          onPressed: () async {
            await widget.apiService.saveInsolvenzAkteKorr(_akteId, {
              if (!istNeu) 'id': bestehend['id'],
              'richtung': richtung,
              'methode': methode.text.trim(),
              'gespraechspartner': partner.text.trim(),
              'datum': datum.text.trim(),
              'betreff': betreff.text.trim(),
              'notiz': notiz.text.trim(),
              'erledigt': erledigt,
            });
            if (!ctx.mounted) return;
            Navigator.pop(ctx);
            _load(); widget.onChanged();
          },
          child: const Text('Speichern')),
      ],
    )));
  }

  // ── Unterlagen ──
  Widget _buildUnterlagen() {
    return SingleChildScrollView(padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: F.h(Colors.blue, 50), borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade100)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline, size: 16, color: F.h(Colors.blue, 700)),
            const SizedBox(width: 8),
            Expanded(child: Text(
              'Die Insolvenzverwaltung fordert Unterlagen nach § 97 InsO an. ⚠️ Geschützt sind '
              'nur die Auskünfte des Schuldners, nicht die übergebenen Unterlagen selbst — '
              'diese dürfen als Beweismittel verwendet werden.',
              style: TextStyle(fontSize: 11, color: F.h(Colors.blue, 900)))),
          ])),
        ...kInsolvenzUnterlagen.map(_dokAbschnitt),
        // Abschnitte aus der früheren Aufteilung — nur, solange dort noch
        // etwas liegt. Sonst stünden sieben leere Kästen unter der Liste,
        // die niemand mehr befüllen soll.
        ...kInsolvenzDokKategorienAlt.entries
            .where((e) => _docs.any((d) => (d['kategorie'] ?? '').toString() == e.key))
            .map((e) => _dokAbschnitt(
                  InsolvenzUnterlage(e.key, e.value,
                      hinweis: 'Aus der früheren Aufteilung — bitte in einen '
                          'der Abschnitte oben umlegen'),
                )),
      ]));
  }

  /// Bandzeile: liegt dieselbe Angabe schon in einem anderen Modul?
  ///
  /// Drei Zustände, drei verschiedene Aussagen — und der dritte ist der
  /// Grund, warum das hier nicht bloß ein grünes Häkchen ist:
  ///   vorhanden → „dort liegen N Einträge", also nicht neu anfordern
  ///   leer      → „dort ist nichts", also beim Mitglied nachfragen
  ///   unbekannt → „wir konnten nicht nachsehen" — ausdrücklich NICHT „leer"
  Widget? _quellenBand(String? quelle) {
    if (quelle == null) return null;
    final q = _quellen[quelle];
    if (q == null) return null;

    final zustand = (q['zustand'] ?? 'unbekannt').toString();
    final wo = (q['wo'] ?? '').toString();
    final anzahl = int.tryParse('${q['anzahl']}') ?? 0;

    final (MaterialColor farbe, IconData sinnbild, String text) = switch (zustand) {
      'vorhanden' => (
          Colors.green,
          Icons.check_circle_outline,
          'Bereits hinterlegt: $anzahl ${anzahl == 1 ? 'Eintrag' : 'Einträge'} '
              'unter $wo',
        ),
      'leer' => (
          Colors.grey,
          Icons.remove_circle_outline,
          'Unter $wo ist nichts hinterlegt',
        ),
      _ => (
          Colors.orange,
          Icons.help_outline,
          'Konnte nicht nachsehen ($wo) — das heißt nicht, dass dort nichts liegt',
        ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(sinnbild, size: 13, color: F.h(farbe, 700)),
        const SizedBox(width: 6),
        Expanded(child: Text(text,
          style: TextStyle(fontSize: 10.5, color: F.h(farbe, 800)))),
      ]),
    );
  }

  Widget _dokAbschnitt(InsolvenzUnterlage u) {
    final kategorie = u.schluessel;
    final titel = u.titel;
    final docs = _docs.where((d) => (d['kategorie'] ?? 'sonstiges').toString() == kategorie).toList();
    return Container(margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: F.flaeche, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: F.h(widget.color, 200))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(color: F.h(widget.color, 50),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10))),
          child: Row(children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$titel (${docs.length})',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                    color: F.h(widget.color, 800))),
                if (u.hinweis != null)
                  Padding(padding: const EdgeInsets.only(top: 2),
                    child: Text(u.hinweis!,
                      style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600)))),
              ])),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final res = await CloudPickerHelper.uebernehmen(context,
                  apiService: widget.apiService, memberId: widget.userId,
                  allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
                  attach: (id) => widget.apiService.attachInsolvenzAkteDocFromCloud(
                    akteId: _akteId, cloudFileId: id, kategorie: kategorie),
                  hochladen: (r) => _upload(kategorie, ausCloud: r));
                if (res != null && mounted) {
                  _load();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('${res.ok} von ${res.total} aus Cloud übernommen'),
                    backgroundColor: res.ok == res.total ? Colors.green : Colors.orange));
                }
              },
              icon: const Icon(Icons.cloud_download, size: 13),
              label: const Text('Aus Cloud', style: TextStyle(fontSize: 10)),
              style: OutlinedButton.styleFrom(foregroundColor: F.h(Colors.blue, 700),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero),
            ),
            const SizedBox(width: 6),
            ElevatedButton.icon(
              onPressed: () => _upload(kategorie),
              icon: const Icon(Icons.upload_file, size: 13),
              label: const Text('Hochladen', style: TextStyle(fontSize: 10)),
              style: ElevatedButton.styleFrom(backgroundColor: widget.color, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero),
            ),
          ])),
        // Der Verweis steht ÜBER der Dateiliste, nicht darunter: er ist die
        // Antwort auf „muss ich das überhaupt anfordern?", und die wird
        // gestellt, bevor jemand die Liste liest.
        ?_quellenBand(u.quelle),
        if (docs.isEmpty) Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
          child: Text('Keine Unterlagen', style: TextStyle(color: F.h(Colors.grey, 500), fontSize: 11))),
        ...docs.map((d) => Padding(padding: const EdgeInsets.fromLTRB(12, 2, 6, 2), child: Row(children: [
          Icon(Icons.attach_file, size: 15, color: F.h(widget.color, 700)), const SizedBox(width: 8),
          Expanded(child: Text((d['datei_name'] ?? '').toString(), style: const TextStyle(fontSize: 12))),
          IconButton(icon: Icon(Icons.visibility, size: 17, color: F.h(Colors.indigo, 600)),
            tooltip: 'Anzeigen', padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            onPressed: () async {
              try {
                final resp = await widget.apiService.downloadInsolvenzAkteDoc(d['id'] as int);
                if (resp.statusCode == 200 && mounted) {
                  final dir = await getTemporaryDirectory();
                  final file = sichereDatei(dir, d['datei_name']);
                  await file.writeAsBytes(resp.bodyBytes);
                  if (mounted) await FileViewerDialog.show(context, file.path, (d['datei_name'] ?? '').toString());
                }
              } catch (e) {
                if (mounted) dateiFehlerMelden(context, e);
              }
            }),
          IconButton(icon: Icon(Icons.download, size: 17, color: F.h(Colors.green, 700)),
            tooltip: 'Herunterladen', padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            onPressed: () async {
              try {
                final resp = await widget.apiService.downloadInsolvenzAkteDoc(d['id'] as int);
                if (resp.statusCode != 200) return;
                final saved = await FilePickerHelper.saveBytes(bytes: resp.bodyBytes,
                  fileName: (d['datei_name'] ?? 'dokument').toString(),
                  dialogTitle: 'Unterlage speichern');
                if (saved == null || !mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Gespeichert: $saved'), backgroundColor: Colors.green));
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Download fehlgeschlagen: $e'), backgroundColor: Colors.red));
                }
              }
            }),
          IconButton(icon: Icon(Icons.delete_outline, size: 17, color: Colors.red.shade400),
            tooltip: 'Löschen', padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            onPressed: () async {
              await widget.apiService.deleteInsolvenzAkteDoc(d['id'] as int);
              _load(); widget.onChanged();
            }),
        ]))),
        const SizedBox(height: 6),
      ]));
  }

  Future<void> _upload(String kategorie, {FilePickerResult? ausCloud}) async {
    final result = ausCloud ?? await FilePickerHelper.pickFiles(
      type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'], allowMultiple: true);
    if (result == null || result.files.isEmpty) return;
    final files = result.files.where((f) => f.path != null).toList();
    if (files.isEmpty) return;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${files.length} Datei(en) werden hochgeladen...'),
        duration: const Duration(seconds: 2)));
    }
    for (final file in files) {
      await widget.apiService.uploadInsolvenzAkteDoc(
        akteId: _akteId, filePath: file.path!, fileName: file.name, kategorie: kategorie);
    }
    _load();
    widget.onChanged();
  }
}

/// Status, Übermittlung und Notizen einer Vollmacht.
///
/// ⚠️ `revoked` steht bewusst NICHT zur Wahl: der Widerruf hat einen eigenen
/// Weg, der Grund und Zeitpunkt festhält. Über diesen Dialog gesetzt, stünde
/// eine widerrufene Vollmacht ohne Grund in der Akte. Der Server weist es
/// zusätzlich ab — die Liste hier ist die Höflichkeit, die Prüfung dort die
/// Sicherung.
class _VollmachtStatusDialog extends StatefulWidget {
  final Map<String, dynamic> vollmacht;
  final MaterialColor color;
  const _VollmachtStatusDialog({required this.vollmacht, required this.color});
  @override
  State<_VollmachtStatusDialog> createState() => _VollmachtStatusDialogState();
}

class _VollmachtStatusDialogState extends State<_VollmachtStatusDialog> {
  static const _status = <String, String>{
    'draft': 'Entwurf',
    'wartet_unterschriften': 'Wartet auf Unterschriften',
    'unterzeichnet': 'Unterzeichnet',
    'eingereicht': 'Eingereicht / übermittelt',
    'aktiv': 'Aktiv',
    'expired': 'Abgelaufen',
  };
  static const _wege = <String, String>{
    '': '— kein Weg vermerkt —',
    'post': 'Post',
    'fax': 'Fax',
    'online': 'Online / E-Mail',
    'persoenlich': 'Persönlich übergeben',
  };

  late String _gewaehlt;
  late String _weg;
  final _datum = TextEditingController();
  final _notiz = TextEditingController();

  @override
  void initState() {
    super.initState();
    final s = '${widget.vollmacht['status'] ?? 'draft'}';
    // Ein unbekannter oder widerrufener Ausgangswert darf die Auswahl nicht
    // leer lassen — DropdownButton wirft dann.
    _gewaehlt = _status.containsKey(s) ? s : 'draft';
    final w = '${widget.vollmacht['submitted_method'] ?? ''}';
    _weg = _wege.containsKey(w) ? w : '';
    _datum.text = '${widget.vollmacht['submitted_at'] ?? ''}'.split(' ').first;
    _notiz.text = '${widget.vollmacht['submitted_notes'] ?? ''}';
  }

  @override
  void dispose() {
    _datum.dispose();
    _notiz.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final breite = MediaQuery.of(context).size.width;
    return AlertDialog(
      title: const Text('Status der Vollmacht'),
      content: SizedBox(
        width: breite < 560 ? breite * 0.86 : 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: _gewaehlt,
              decoration: const InputDecoration(labelText: 'Status', isDense: true),
              items: _status.entries
                  .map((e) => DropdownMenuItem(value: e.key,
                      child: Text(e.value, style: const TextStyle(fontSize: 13))))
                  .toList(),
              onChanged: (x) => setState(() => _gewaehlt = x ?? _gewaehlt),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _weg,
              decoration: const InputDecoration(labelText: 'Übermittelt per', isDense: true),
              items: _wege.entries
                  .map((e) => DropdownMenuItem(value: e.key,
                      child: Text(e.value, style: const TextStyle(fontSize: 13))))
                  .toList(),
              onChanged: (x) => setState(() => _weg = x ?? _weg),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _datum,
              decoration: const InputDecoration(
                  labelText: 'Übermittelt am', hintText: 'JJJJ-MM-TT', isDense: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notiz,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notizen', isDense: true),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: widget.color.shade700, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(context, {
            'status': _gewaehlt,
            'submitted_at': _datum.text.trim(),
            'submitted_method': _weg,
            'submitted_notes': _notiz.text.trim(),
          }),
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}
