import 'dart:convert';
import 'package:flutter/material.dart';
import 'phone_link.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';
import '../services/global_chat_service.dart';
import 'file_viewer_dialog.dart';
import 'cloud_file_picker.dart';
import '../utils/cloud_picker_helper.dart';
import 'feld_reihe.dart';
import 'vermieter_dokumente.dart' show dialogBreite;
import '../utils/app_farben.dart';
import '../utils/sicherer_dateiname.dart';
import '../utils/ra_antwort.dart' show raWert, raDatumDe;
import '../utils/sozialamt_korr_optionen.dart';

class BehordeSozialamtContent extends StatefulWidget {
  final ApiService? apiService;
  final int? userId;
  final Map<String, dynamic> Function(String type) getData;
  final bool Function(String type) isLoading;
  final bool Function(String type) isSaving;
  final void Function(String type) loadData;
  final void Function(String type, Map<String, dynamic> data) saveData;
  final Widget Function(String type, TextEditingController controller) dienststelleBuilder;

  const BehordeSozialamtContent({
    super.key,
    this.apiService,
    this.userId,
    required this.getData,
    required this.isLoading,
    required this.isSaving,
    required this.loadData,
    required this.saveData,
    required this.dienststelleBuilder,
  });

  static const type = 'sozialamt';

  @override
  State<BehordeSozialamtContent> createState() => _BehordeSozialamtContentState();
}

class _BehordeSozialamtContentState extends State<BehordeSozialamtContent> {
  Map<String, Map<String, dynamic>> _dbData = {};
  List<Map<String, dynamic>> _antraege = [];
  bool _loaded = false;
  Set<String> _checkedDocsGlobal = {};

  /// Ämter-Katalog vom Server (Tabelle `sozialamt_db`). Früher stand hier eine
  /// `static const`-Liste im Code — jedes neue Amt hätte ein Release gebraucht.
  List<Map<String, dynamic>> _aemter = [];
  String? _aemterFehler;

  @override
  void initState() {
    super.initState();
    _loadFromDB();
    _ladeAemter();
  }

  /// Holt den Katalog. Schlägt das fehl, bleibt die gespeicherte Auswahl
  /// trotzdem lesbar: die Karte zeigt, was am Mitglied hinterlegt ist, nicht
  /// was im Katalog steht.
  Future<void> _ladeAemter([String q = '']) async {
    if (widget.apiService == null) return;
    final r = await widget.apiService!.searchSozialamtDatenbank(q);
    if (!mounted) return;
    setState(() {
      if (r['success'] == true && r['results'] is List) {
        _aemter = (r['results'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _aemterFehler = null;
      } else {
        _aemterFehler = (r['message'] ?? 'Ämter-Katalog nicht erreichbar').toString();
      }
    });
  }

  Future<void> _loadFromDB() async {
    if (widget.apiService == null || widget.userId == null) {
      setState(() => _loaded = true);
      return;
    }
    final r = await widget.apiService!.getSozialamtData(widget.userId!);
    if (!mounted) return;
    if (r['success'] == true && r['data'] is Map) {
      final raw = r['data'] as Map;
      _dbData = {};
      for (final entry in raw.entries) {
        final map = Map<String, dynamic>.from(entry.value as Map);
        // Parse JSON strings back to lists/maps (stored as JSON in DB)
        for (final k in map.keys.toList()) {
          final v = map[k];
          if (v is String && v.startsWith('[')) {
            try { map[k] = jsonDecode(v); } catch (_) {}
          } else if (v is String && v.startsWith('{')) {
            try { map[k] = jsonDecode(v); } catch (_) {}
          }
        }
        _dbData[entry.key.toString()] = map;
      }
    }
    // Load from dedicated tables
    if (widget.apiService != null && widget.userId != null) {
      final aR = await widget.apiService!.listSozialamtAntraege(widget.userId!);
      if (aR['success'] == true && aR['data'] is List) _antraege = (aR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    // Load checked docs from DB (stored in sozialamt_data bereich='checked_docs')
    final cd = _dbData['checked_docs'];
    if (cd != null && cd['list'] is List) {
      _checkedDocsGlobal = Set<String>.from((cd['list'] as List).map((e) => e.toString()));
    } else if (cd != null && cd['list'] is String) {
      try { _checkedDocsGlobal = Set<String>.from(jsonDecode(cd['list'] as String)); } catch (_) {}
    }
    setState(() => _loaded = true);
  }

  Future<void> _save() async {
    if (widget.apiService == null || widget.userId == null) return;
    await widget.apiService!.saveSozialamtData(widget.userId!, _dbData);
  }

  String _fmtIsoDate(String iso) {
    if (iso.isEmpty || iso == 'null') return '';
    final p = iso.split(' ').first.split('-');
    return p.length == 3 ? '${p[2]}.${p[1]}.${p[0]}' : iso;
  }

  Map<String, dynamic> _b(String key) {
    _dbData[key] ??= {};
    return _dbData[key]!;
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());

    return DefaultTabController(
      length: 2,
      child: Column(children: [
        TabBar(
          labelColor: F.h(Colors.indigo, 700),
          unselectedLabelColor: F.h(Colors.grey, 600),
          indicatorColor: F.h(Colors.indigo, 700),
          isScrollable: true,
          tabs: [
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: (_b('behoerde')['name']?.toString() ?? '').isNotEmpty ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.account_balance, size: 16), const SizedBox(width: 4), const Text('Zuständige Behörde')])),
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: _antraege.isNotEmpty ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.description, size: 16), const SizedBox(width: 4), const Text('Anträge')])),
          ],
        ),
        Expanded(child: TabBarView(children: [
          _buildBehoerdeTab(),
          _buildAntraegeTab(),
        ])),
      ]),
    );
  }

  Widget _buildBehoerdeTab() {
    final d = _b('behoerde');
    final selected = d['name']?.toString() ?? '';
    // Erst das, was am Mitglied gespeichert ist, dann der Katalog als Nachschlag
    // für Felder, die es beim Speichern noch nicht gab (Fax, E-Mail, Quelle).
    final katalog = _aemter.where((a) => a['name'] == selected).firstOrNull;
    String feld(String k) {
      final v = d[k]?.toString() ?? '';
      if (v.isNotEmpty) return v;
      return katalog?[k]?.toString() ?? '';
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.account_balance, size: 20, color: F.h(Colors.indigo, 700)),
          const SizedBox(width: 8),
          Expanded(child: Text('Zuständiges Sozialamt', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: F.h(Colors.indigo, 700)))),
          OutlinedButton.icon(
            icon: const Icon(Icons.search, size: 16),
            label: Text(selected.isEmpty ? 'Auswählen' : 'Ändern', style: const TextStyle(fontSize: 12)),
            onPressed: () => _showBehoerdeSelectDialog(d),
          ),
        ]),
        if (_aemterFehler != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Icon(Icons.cloud_off, size: 14, color: F.h(Colors.orange, 800)),
              const SizedBox(width: 6),
              Expanded(child: Text('Ämter-Katalog: $_aemterFehler', style: TextStyle(fontSize: 11, color: F.h(Colors.orange, 800)))),
            ]),
          ),
        const SizedBox(height: 12),
        if (selected.isEmpty)
          Container(
            width: double.infinity, padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: F.h(Colors.grey, 50), borderRadius: BorderRadius.circular(10), border: Border.all(color: F.h(Colors.grey, 300))),
            child: Column(children: [
              Icon(Icons.search, size: 40, color: F.h(Colors.grey, 400)),
              const SizedBox(height: 8),
              Text('Kein Sozialamt ausgewählt', style: TextStyle(fontSize: 13, color: F.h(Colors.grey, 600))),
              const SizedBox(height: 4),
              Text('Tippen Sie auf "Auswählen" um das zuständige Amt zu suchen.', style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 500))),
            ]),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: F.h(Colors.indigo, 50), borderRadius: BorderRadius.circular(10), border: Border.all(color: F.h(Colors.indigo, 300))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(selected, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: F.h(Colors.indigo, 900))),
              const SizedBox(height: 6),
              _infoRow(Icons.location_on, [feld('adresse'), feld('plz_ort')].where((e) => e.isNotEmpty).join(', ')),
              _infoRow(Icons.phone, feld('telefon')),
              // Fax bekommt bewusst kein Telefon-Icon: `phoneAwareText` würde
              // daraus eine Wählfläche machen, und ein angerufenes Faxgerät
              // pfeift nur zurück.
              _infoRow(Icons.print, feld('fax')),
              _infoRow(Icons.mail_outline, feld('email')),
              _infoRow(Icons.language, feld('website')),
              _infoRow(Icons.access_time, feld('oeffnungszeiten')),
              _infoRow(Icons.info, feld('zustaendigkeit')),
              if (feld('fax').isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Für dieses Amt ist keine Faxnummer hinterlegt.',
                      style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: F.h(Colors.orange, 800))),
                ),
              if (katalog != null && (katalog['geprueft_am']?.toString() ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Katalogstand: ${_fmtIsoDate(katalog['geprueft_am'].toString())}',
                      style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
                ),
            ]),
          ),
      ]),
    );
  }

  Future<void> _showBehoerdeSelectDialog(Map<String, dynamic> d) async {
    if (widget.apiService == null) return;
    final gewaehlt = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _AmtAuswahlDialog(apiService: widget.apiService!),
    );
    if (gewaehlt == null || !mounted) return;
    setState(() {
      for (final k in ['name', 'adresse', 'plz_ort', 'telefon', 'fax', 'email', 'website', 'oeffnungszeiten', 'zustaendigkeit']) {
        d[k] = gewaehlt[k]?.toString() ?? '';
      }
      d['amt_id'] = gewaehlt['id']?.toString() ?? '';
    });
    _save();
    _ladeAemter();
  }

  Widget _infoRow(IconData icon, String text) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Icon(icon, size: 14, color: F.h(Colors.grey, 600)),
        const SizedBox(width: 6),
        Expanded(child: phoneAwareText(icon, text, style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700)))),
      ]),
    );
  }

  Widget _buildAntraegeTab() {
    final list = _antraege;
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Row(children: [
        Icon(Icons.description, size: 20, color: F.h(Colors.indigo, 700)), const SizedBox(width: 8),
        Expanded(child: Text('Anträge (${list.length})', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: F.h(Colors.indigo, 700)))),
        ElevatedButton.icon(onPressed: () => _showAntragDialog(), icon: const Icon(Icons.add, size: 16), label: const Text('Neuer Antrag', style: TextStyle(fontSize: 12)), style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white)),
      ])),
      Expanded(child: list.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.description, size: 48, color: F.h(Colors.grey, 300)), const SizedBox(height: 8), Text('Keine Anträge', style: TextStyle(color: F.h(Colors.grey, 500)))]))
          : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: list.length, itemBuilder: (_, i) {
              final a = list[i];
              final hatBew = a['hat_bewilligung'] == 1 || a['hat_bewilligung'] == '1';
              final bewOk = a['bew_bewilligt'] == 1 || a['bew_bewilligt'] == '1' || a['bew_bewilligt'] == true;
              final bewBis = _fmtIsoDate(a['bew_zeitraum_bis']?.toString() ?? '');
              final MaterialColor statusColor = hatBew ? (bewOk ? Colors.green : Colors.red) : Colors.grey;
              final statusText = hatBew ? (bewOk ? 'Bewilligt' : 'Abgelehnt') : (a['status']?.toString() ?? '');
              return Card(child: ListTile(
                leading: Icon(hatBew ? (bewOk ? Icons.check_circle : Icons.cancel) : Icons.description, color: hatBew ? (bewOk ? F.h(Colors.green, 600) : F.h(Colors.red, 600)) : F.h(Colors.indigo, 600)),
                title: Text(a['leistung']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${a['datum'] ?? ''}${(a['methode']?.toString() ?? '').isNotEmpty ? ' • ${a['methode']}' : ''}', style: const TextStyle(fontSize: 11)),
                  if ((a['aktenzeichen']?.toString() ?? '').isNotEmpty)
                    Text('Az. ${a['aktenzeichen']}', style: TextStyle(fontSize: 11, color: F.h(Colors.indigo, 400), fontWeight: FontWeight.w600)),
                  if ((a['ansprechpartner']?.toString() ?? '').isNotEmpty)
                    Text(a['ansprechpartner'].toString(), style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
                  const SizedBox(height: 3),
                  Row(children: [
                    Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: F.h(statusColor, 50), borderRadius: BorderRadius.circular(6), border: Border.all(color: F.h(statusColor, 200))), child: Text(statusText, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: F.h(statusColor, 700)))),
                    if (hatBew && bewOk && bewBis.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.event, size: 11, color: F.h(Colors.grey, 500)),
                      const SizedBox(width: 2),
                      Flexible(child: Text('gültig bis $bewBis', style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600)), overflow: TextOverflow.ellipsis)),
                    ],
                  ]),
                ]),
                isThreeLine: true,
                onTap: () {
                  final aid = int.tryParse(a['id']?.toString() ?? '');
                  if (aid != null) _showAntragDetailDialog(aid, a);
                },
                // Antippen öffnet weiterhin die Detailansicht; Bearbeiten und
                // Löschen sitzen im Menü. `_showAntragDialog(editIndex:)` gab
                // es längst — nur rief es niemand auf, ein Antrag war damit
                // nach dem Anlegen unveränderbar.
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  PopupMenuButton<String>(
                    tooltip: 'Antrag',
                    icon: Icon(Icons.more_vert, size: 20, color: F.h(Colors.grey, 600)),
                    onSelected: (wahl) {
                      if (wahl == 'bearbeiten') _showAntragDialog(editIndex: i);
                      if (wahl == 'loeschen') _antragLoeschen(a);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'bearbeiten', child: Row(children: [Icon(Icons.edit, size: 16), SizedBox(width: 8), Text('Bearbeiten')])),
                      PopupMenuItem(value: 'loeschen', child: Row(children: [Icon(Icons.delete_outline, size: 16, color: Colors.red), SizedBox(width: 8), Text('Löschen', style: TextStyle(color: Colors.red))])),
                    ],
                  ),
                  Icon(Icons.chevron_right, color: F.h(Colors.grey, 400)),
                ]),
              ));
            })),
    ]);
  }

  Future<void> _antragLoeschen(Map<String, dynamic> a) async {
    final id = int.tryParse(a['id']?.toString() ?? '');
    if (id == null || widget.apiService == null || widget.userId == null) return;
    final sicher = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Antrag löschen?'),
      content: Text('„${a['leistung'] ?? ''}" vom ${a['datum'] ?? ''} wird gelöscht. '
          'Dokumente, Verlauf und Korrespondenz dieses Antrags gehen mit.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen', style: TextStyle(color: Colors.red))),
      ],
    ));
    if (sicher != true) return;
    final r = await widget.apiService!.deleteSozialamtAntrag(widget.userId!, id);
    if (!mounted) return;
    if (r['success'] == true) {
      _loadFromDB();
    } else {
      // Grund anzeigen statt still nichts zu tun — sonst sieht ein
      // fehlgeschlagenes Löschen aus wie ein Antrag, der wieder auftaucht.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nicht gelöscht: ${r['message'] ?? 'unbekannter Fehler'}')));
    }
  }

  void _showAntragDialog({int? editIndex}) {
    final ex = editIndex != null ? _antraege[editIndex] : null;
    final datumC = TextEditingController(text: ex?['datum']?.toString() ?? '');
    final notizC = TextEditingController(text: ex?['notiz']?.toString() ?? '');
    final aktenzeichenC = TextEditingController(text: ex?['aktenzeichen']?.toString() ?? '');
    final ansprechpartnerC = TextEditingController(text: ex?['ansprechpartner']?.toString() ?? '');
    final telefonC = TextEditingController(text: ex?['telefon']?.toString() ?? '');
    final emailC = TextEditingController(text: ex?['email']?.toString() ?? '');
    String leistung = ex?['leistung']?.toString() ?? '';
    String methode = ex?['methode']?.toString() ?? '';
    String status = ex?['status']?.toString() ?? 'eingereicht';
    final leistungen = ['Grundsicherung im Alter', 'Grundsicherung bei Erwerbsminderung', 'Hilfe zum Lebensunterhalt', 'Eingliederungshilfe', 'Hilfe zur Pflege', 'Bildung und Teilhabe', 'Bestattungskosten', 'Blindengeld', 'Sonstige'];
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) => AlertDialog(
      title: Text(editIndex != null ? 'Antrag bearbeiten' : 'Neuer Antrag'),
      // Feste 460 dp sprengen ein 412-dp-Telefon — und der Vorsitzer arbeitet
      // auf einem Pixel. `dialogBreite` nimmt die Breite nur, wenn sie da ist.
      content: SizedBox(width: dialogBreite(ctx2, 460), child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(
          // Ohne `isExpanded` richtet sich ein Dropdown nach seinem
          // breitesten Eintrag, nicht nach dem Feld. Ein langer Name
          // sprengte damit die Zeile — gemessen 241 dp in
          // ordnungsmassnahmen_screen. Als Formularfeld soll es
          // ohnehin die volle Breite haben.
          isExpanded: true,initialValue: leistungen.contains(leistung) ? leistung : null, decoration: InputDecoration(labelText: 'Leistung *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), items: leistungen.map((l) => DropdownMenuItem(value: l, child: Text(l, style: const TextStyle(fontSize: 12)))).toList(), onChanged: (v) => setD(() => leistung = v ?? '')),
        const SizedBox(height: 8),
        TextField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onTap: () async { final p = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de')); if (p != null) setD(() => datumC.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}'); }),
        const SizedBox(height: 8),
        Wrap(spacing: 6, children: [('online', 'Online'), ('persoenlich', 'Persönlich'), ('postalisch', 'Postalisch'), ('email', 'E-Mail')].map((m) => ChoiceChip(label: Text(m.$2, style: TextStyle(fontSize: 11, color: methode == m.$1 ? Colors.white : F.textStark)), selected: methode == m.$1, selectedColor: Colors.indigo, onSelected: (_) => setD(() => methode = m.$1))).toList()),
        const SizedBox(height: 8),
        Wrap(spacing: 6, children: [('eingereicht', 'Eingereicht'), ('in_bearbeitung', 'In Bearbeitung'), ('bewilligt', 'Bewilligt'), ('abgelehnt', 'Abgelehnt'), ('widerspruch', 'Widerspruch')].map((s) => ChoiceChip(label: Text(s.$2, style: TextStyle(fontSize: 11, color: status == s.$1 ? Colors.white : F.textStark)), selected: status == s.$1, selectedColor: Colors.teal, onSelected: (_) => setD(() => status = s.$1))).toList()),
        const SizedBox(height: 8),
        TextField(controller: aktenzeichenC, decoration: InputDecoration(labelText: 'Aktenzeichen', isDense: true, prefixIcon: const Icon(Icons.tag, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 12),
        // Sachbearbeitung: wer den Fall führt und wie man die Person erreicht.
        // Ohne das steht bei jedem Rückruf wieder die Frage im Raum, mit wem
        // zuletzt gesprochen wurde.
        Row(children: [
          Icon(Icons.support_agent, size: 16, color: F.h(Colors.indigo, 400)),
          const SizedBox(width: 6),
          Text('Sachbearbeitung', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: F.h(Colors.indigo, 400))),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: F.h(Colors.indigo, 100))),
        ]),
        const SizedBox(height: 8),
        TextField(controller: ansprechpartnerC, decoration: InputDecoration(labelText: 'Ansprechpartner/in', isDense: true, prefixIcon: const Icon(Icons.person_outline, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 8),
        TextField(controller: telefonC, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: 'Telefon (Durchwahl)', isDense: true, prefixIcon: const Icon(Icons.phone, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 8),
        TextField(controller: emailC, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: 'E-Mail', isDense: true, prefixIcon: const Icon(Icons.mail_outline, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 12),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          if (leistung.isEmpty || datumC.text.isEmpty) return;
          if (widget.apiService != null && widget.userId != null) {
            await widget.apiService!.saveSozialamtAntrag(widget.userId!, {
              if (ex != null) 'id': ex['id'],
              'leistung': leistung, 'datum': datumC.text, 'methode': methode, 'status': status, 'notiz': notizC.text,
              'aktenzeichen': aktenzeichenC.text, 'ansprechpartner': ansprechpartnerC.text,
              'telefon': telefonC.text, 'email': emailC.text,
            });
          }
          if (ctx.mounted) Navigator.pop(ctx);
          _loadFromDB();
        }, child: Text(editIndex != null ? 'Speichern' : 'Hinzufügen')),
      ],
    )));
  }

  // ============ ANTRAG DETAIL MODAL ============
  void _showAntragDetailDialog(int antragId, Map<String, dynamic> antrag) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(width: 580, height: 560, child: _AntragDetailView(apiService: widget.apiService!, userId: widget.userId ?? 0, antragId: antragId, antrag: antrag, checkedDocs: _checkedDocsGlobal, onCheckedChanged: (docs) { _checkedDocsGlobal = docs; _dbData['checked_docs'] = {'list': docs.toList()}; _save(); })),
      ),
    );
  }


}

// ═══════════════════════════════════════════════════════
// ANTRAG DETAIL (Details / Verlauf / Korrespondenz)
// ═══════════════════════════════════════════════════════
class _AntragDetailView extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int antragId;
  final Map<String, dynamic> antrag;
  final Set<String> checkedDocs;
  final ValueChanged<Set<String>> onCheckedChanged;
  const _AntragDetailView({required this.apiService, required this.userId, required this.antragId, required this.antrag, required this.checkedDocs, required this.onCheckedChanged});
  @override
  State<_AntragDetailView> createState() => _AntragDetailViewState();
}

class _AntragDetailViewState extends State<_AntragDetailView> {
  List<Map<String, dynamic>> _verlauf = [];
  List<Map<String, dynamic>> _korr = [];
  List<Map<String, dynamic>> _docs = [];
  bool _loaded = false;

  /// Was das Sozialamt schickt und was NICHT zurückgeht.
  ///
  /// ⚠️ Steht bewusst NICHT in [_requiredDocs] und zählt nicht in den Balken
  /// „x / y": diese beiden Blätter muss niemand beibringen. Wären sie im
  /// Zähler, meldete der Schirm den Antrag als unvollständig, weil ein
  /// Anschreiben nicht eingescannt ist. Abgelegt gehören sie trotzdem — sie
  /// tragen Datum, Aktenzeichen und die Frist, auf die sich das Amt beruft.
  ///
  /// ⚠️ Die Merkblätter, die UNTERSCHRIEBEN ZURÜCKGEHEN — Auszug aus dem
  /// SGB I, Datenschutzhinweise nach Art. 13 DSGVO, Wichtige Hinweise zum
  /// Sozialhilfeantrag — stehen deshalb nicht hier, sondern in der
  /// Checkliste: sie sind Teil dessen, was abgegeben wird (Festlegung des
  /// Vorsitzenden, 04.09.2026).
  ///
  /// Für jede Leistung gleich.
  static const List<(String, String, IconData)> _amtsUnterlagen = [
    ('anschreiben_sozialamt', 'Anschreiben vom Sozialamt', Icons.mark_email_read_outlined),
    ('checkliste_sozialamt', 'Checkliste des Sozialamts', Icons.checklist_rtl),
  ];

  // ⚠️ DER SCHLÜSSEL IST DIE ABLAGE. Er landet als `doc_typ` in
  // `sozialamt_antrag_docs` und in der Liste `checked_docs` in
  // `sozialamt_data`. Ein umbenannter Schlüssel heisst: Haken weg, Datei
  // verwaist — ohne Fehler, ohne Meldung. Der Server prüft ihn nicht
  // (`$_POST['doc_typ'] ?? 'sonstiges'`), die Spalte ist varchar(50).
  // `test/sozialamt_dokumente_test.dart` hält die vorhandenen Schlüssel fest.
  //
  // Neue Zeilen stehen dort, wo ihr Geschwisterteil schon steht: die
  // Mietbescheinigung bei der Miete, die Übernahme der KV-Beiträge bei der
  // Krankenversicherung. Eine Zeile in einer Liste, in der ihr Thema gar nicht
  // vorkommt, ist kein Sicherheitsnetz, sondern ein Haken, den nie jemand
  // setzt — und der Balken erreicht die volle Zahl nie.
  static const Map<String, List<(String, String, IconData)>> _requiredDocs = {
    'Grundsicherung im Alter': [
      ('personalausweis', 'Personalausweis / Reisepass', Icons.badge),
      ('rentenbescheid', 'Rentenbescheid', Icons.description),
      ('kontoauszuege', 'Kontoauszüge (3 Monate, alle Konten)', Icons.account_balance),
      ('mietvertrag', 'Mietvertrag', Icons.home),
      ('mietbescheinigung', 'Mietbescheinigung (vom Vermieter auszufüllen)', Icons.apartment),
      ('nebenkostenabrechnung', 'Nebenkostenabrechnung', Icons.receipt),
      ('heizkostenabrechnung', 'Heizkostenabrechnung', Icons.thermostat),
      ('krankenversicherung', 'Krankenversicherungsnachweis', Icons.local_hospital),
      ('antrag_kv_beitraege', 'Antrag Übernahme der Krankenversicherungsbeiträge', Icons.health_and_safety_outlined),
      ('einkommensnachweis', 'Einkommensnachweise', Icons.euro),
      ('vermoegensnachweis', 'Vermögensnachweise (Sparbücher etc.)', Icons.savings),
      ('erklaerung_vermoegen', 'Erklärung über die Vermögensverhältnisse', Icons.account_balance_wallet_outlined),
      ('erklaerung_grundbesitz', 'Erklärung zu Haus- und Grundbesitz', Icons.terrain_outlined),
      ('erklaerung_ausland', 'Erklärung zu Lebens- und Arbeitszeiten im Ausland', Icons.public),
      ('sgb1_auszug', 'Auszug aus dem SGB I', Icons.gavel),
      ('datenschutz_art13', 'Datenschutzhinweise nach Art. 13 DSGVO', Icons.privacy_tip_outlined),
      ('hinweise_sozialhilfeantrag', 'Wichtige Hinweise zum Sozialhilfeantrag', Icons.info_outline),
      ('antrag_sgb12', 'Antrag Leistungen nach dem SGB XII', Icons.assignment_outlined),
    ],
    'Grundsicherung bei Erwerbsminderung': [
      ('personalausweis', 'Personalausweis / Reisepass', Icons.badge),
      ('em_bescheid', 'EM-Rentenbescheid / Gutachten Erwerbsminderung', Icons.medical_information),
      ('rentenbescheid', 'Rentenbescheid', Icons.description),
      ('kontoauszuege', 'Kontoauszüge (3 Monate, alle Konten)', Icons.account_balance),
      ('mietvertrag', 'Mietvertrag', Icons.home),
      ('mietbescheinigung', 'Mietbescheinigung (vom Vermieter auszufüllen)', Icons.apartment),
      ('nebenkostenabrechnung', 'Nebenkostenabrechnung', Icons.receipt),
      ('heizkostenabrechnung', 'Heizkostenabrechnung', Icons.thermostat),
      ('krankenversicherung', 'Krankenversicherungsnachweis', Icons.local_hospital),
      ('antrag_kv_beitraege', 'Antrag Übernahme der Krankenversicherungsbeiträge', Icons.health_and_safety_outlined),
      ('schwerbehindertenausweis', 'Schwerbehindertenausweis (falls vorhanden)', Icons.accessible),
      ('einkommensnachweis', 'Einkommensnachweise', Icons.euro),
      ('vermoegensnachweis', 'Vermögensnachweise', Icons.savings),
      ('erklaerung_vermoegen', 'Erklärung über die Vermögensverhältnisse', Icons.account_balance_wallet_outlined),
      ('erklaerung_grundbesitz', 'Erklärung zu Haus- und Grundbesitz', Icons.terrain_outlined),
      ('erklaerung_ausland', 'Erklärung zu Lebens- und Arbeitszeiten im Ausland', Icons.public),
      ('sgb1_auszug', 'Auszug aus dem SGB I', Icons.gavel),
      ('datenschutz_art13', 'Datenschutzhinweise nach Art. 13 DSGVO', Icons.privacy_tip_outlined),
      ('hinweise_sozialhilfeantrag', 'Wichtige Hinweise zum Sozialhilfeantrag', Icons.info_outline),
      ('antrag_sgb12', 'Antrag Leistungen nach dem SGB XII', Icons.assignment_outlined),
    ],
    'Hilfe zur Pflege': [
      ('personalausweis', 'Personalausweis / Reisepass', Icons.badge),
      ('pflegegrad_bescheid', 'Pflegegrad-Bescheid / MDK-Gutachten', Icons.medical_information),
      ('krankenversicherung', 'Kranken- und Pflegeversicherungsnachweis', Icons.local_hospital),
      ('antrag_kv_beitraege', 'Antrag Übernahme der Krankenversicherungsbeiträge', Icons.health_and_safety_outlined),
      ('kontoauszuege', 'Kontoauszüge (3 Monate)', Icons.account_balance),
      ('mietvertrag', 'Mietvertrag', Icons.home),
      ('mietbescheinigung', 'Mietbescheinigung (vom Vermieter auszufüllen)', Icons.apartment),
      ('einkommensnachweis', 'Einkommensnachweise', Icons.euro),
      ('vermoegensnachweis', 'Vermögensnachweise', Icons.savings),
      ('erklaerung_vermoegen', 'Erklärung über die Vermögensverhältnisse', Icons.account_balance_wallet_outlined),
      ('erklaerung_grundbesitz', 'Erklärung zu Haus- und Grundbesitz', Icons.terrain_outlined),
      ('erklaerung_ausland', 'Erklärung zu Lebens- und Arbeitszeiten im Ausland', Icons.public),
      // Unterhaltsheranziehung: hier fragt das Amt regelmässig nach den
      // Angehörigen. Bei der Grundsicherung steht der Bogen bewusst nicht —
      // dort schirmt § 43 Abs. 5 SGB XII Kinder und Eltern unterhalb der
      // Einkommensgrenze ab, und ein Haken, den nie jemand setzt, hält den
      // Balken für immer unter der vollen Zahl.
      ('fragebogen_angehoerige', 'Fragebogen zum Angehörigen', Icons.family_restroom),
      ('pflegekosten', 'Nachweise über Pflegekosten', Icons.receipt_long),
      ('sgb1_auszug', 'Auszug aus dem SGB I', Icons.gavel),
      ('datenschutz_art13', 'Datenschutzhinweise nach Art. 13 DSGVO', Icons.privacy_tip_outlined),
      ('hinweise_sozialhilfeantrag', 'Wichtige Hinweise zum Sozialhilfeantrag', Icons.info_outline),
      ('antrag_sgb12', 'Antrag Leistungen nach dem SGB XII', Icons.assignment_outlined),
    ],
    'Eingliederungshilfe': [
      ('personalausweis', 'Personalausweis / Reisepass', Icons.badge),
      ('aerztliches_gutachten', 'Ärztliches Gutachten / Diagnose', Icons.medical_information),
      ('schwerbehindertenausweis', 'Schwerbehindertenausweis', Icons.accessible),
      ('kontoauszuege', 'Kontoauszüge (3 Monate)', Icons.account_balance),
      ('einkommensnachweis', 'Einkommensnachweise', Icons.euro),
      ('vermoegensnachweis', 'Vermögensnachweise', Icons.savings),
      ('erklaerung_vermoegen', 'Erklärung über die Vermögensverhältnisse', Icons.account_balance_wallet_outlined),
      ('erklaerung_grundbesitz', 'Erklärung zu Haus- und Grundbesitz', Icons.terrain_outlined),
      ('erklaerung_ausland', 'Erklärung zu Lebens- und Arbeitszeiten im Ausland', Icons.public),
      ('fragebogen_angehoerige', 'Fragebogen zum Angehörigen', Icons.family_restroom),
      ('sgb1_auszug', 'Auszug aus dem SGB I', Icons.gavel),
      ('datenschutz_art13', 'Datenschutzhinweise nach Art. 13 DSGVO', Icons.privacy_tip_outlined),
      ('hinweise_sozialhilfeantrag', 'Wichtige Hinweise zum Sozialhilfeantrag', Icons.info_outline),
      // ⚠️ HIER steht weiterhin das allgemeine Formular, und nur hier: die
      // Eingliederungshilfe ist seit dem BTHG (2020) im SGB IX Teil 2, nicht
      // mehr im SGB XII. Ein „Antrag Leistungen nach dem SGB XII" wäre hier
      // ein Haken, den nie jemand setzen kann — und ganz ohne Antragszeile
      // fehlte der Liste ausgerechnet das Blatt, um das es geht.
      ('antrag_formular', 'Ausgefüllter Antrag (unterschrieben)', Icons.edit_document),
    ],
  };

  /// ⚠️ Gilt für FÜNF der neun Leistungen aus dem Antragsdialog — darunter
  /// „Hilfe zum Lebensunterhalt", der klassische Sozialhilfefall. Sie haben
  /// keine eigene Liste, also ist diese hier ihre einzige. Was zum
  /// Standardsatz eines Sozialhilfeantrags gehört, muss deshalb auch hier
  /// stehen, sonst sieht ausgerechnet der häufigste Fall nichts davon.
  static const _defaultDocs = [
    ('personalausweis', 'Personalausweis / Reisepass', Icons.badge),
    ('kontoauszuege', 'Kontoauszüge (3 Monate)', Icons.account_balance),
    ('mietvertrag', 'Mietvertrag', Icons.home),
    ('mietbescheinigung', 'Mietbescheinigung (vom Vermieter auszufüllen)', Icons.apartment),
    ('krankenversicherung', 'Krankenversicherungsnachweis', Icons.local_hospital),
    ('antrag_kv_beitraege', 'Antrag Übernahme der Krankenversicherungsbeiträge', Icons.health_and_safety_outlined),
    ('einkommensnachweis', 'Einkommensnachweise', Icons.euro),
    ('vermoegensnachweis', 'Vermögensnachweise', Icons.savings),
    ('erklaerung_vermoegen', 'Erklärung über die Vermögensverhältnisse', Icons.account_balance_wallet_outlined),
    ('erklaerung_grundbesitz', 'Erklärung zu Haus- und Grundbesitz', Icons.terrain_outlined),
    ('erklaerung_ausland', 'Erklärung zu Lebens- und Arbeitszeiten im Ausland', Icons.public),
    ('fragebogen_angehoerige', 'Fragebogen zum Angehörigen', Icons.family_restroom),
    ('sgb1_auszug', 'Auszug aus dem SGB I', Icons.gavel),
    ('datenschutz_art13', 'Datenschutzhinweise nach Art. 13 DSGVO', Icons.privacy_tip_outlined),
    ('hinweise_sozialhilfeantrag', 'Wichtige Hinweise zum Sozialhilfeantrag', Icons.info_outline),
    ('antrag_sgb12', 'Antrag Leistungen nach dem SGB XII', Icons.assignment_outlined),
    ('sonstiges', 'Sonstiges Dokument', Icons.attach_file),
  ];

  @override
  void initState() { super.initState(); _checkedDocs = Set<String>.from(widget.checkedDocs); _load(); }

  Future<void> _load() async {
    final vR = await widget.apiService.listAntragVerlauf(widget.antragId);
    final kR = await widget.apiService.listAntragKorrespondenz(widget.antragId);
    final dR = await widget.apiService.listAntragDocs(widget.antragId);
    if (!mounted) return;
    setState(() {
      if (vR['success'] == true && vR['data'] is List) _verlauf = (vR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (kR['success'] == true && kR['data'] is List) _korr = (kR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (dR['success'] == true && dR['data'] is List) _docs = (dR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.antrag;
    return DefaultTabController(length: 5, child: Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: F.h(Colors.indigo, 700), borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
        child: Row(children: [
          const Icon(Icons.description, color: Colors.white, size: 22), const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a['leistung']?.toString() ?? '', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            Text('${a['datum'] ?? ''} • ${a['status'] ?? ''}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ])),
          IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
        ]),
      ),
      TabBar(labelColor: F.h(Colors.indigo, 700), indicatorColor: F.h(Colors.indigo, 700), isScrollable: true, tabs: const [
        Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Details'),
        Tab(icon: Icon(Icons.folder, size: 18), text: 'Dokumente'),
        Tab(icon: Icon(Icons.timeline, size: 18), text: 'Verlauf'),
        Tab(icon: Icon(Icons.verified, size: 18), text: 'Bewilligung'),
        Tab(icon: Icon(Icons.mail, size: 18), text: 'Korrespondenz'),
      ]),
      Expanded(child: !_loaded ? const Center(child: CircularProgressIndicator()) : TabBarView(children: [
        _buildDetails(a),
        _buildDokumente(a),
        _buildVerlauf(),
        _AntragBewilligungTab(apiService: widget.apiService, userId: widget.userId, antragId: widget.antragId),
        _buildKorr(),
      ])),
    ]));
  }

  Widget _buildDetails(Map<String, dynamic> a) {
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _row(Icons.description, 'Leistung', a['leistung']),
      _row(Icons.calendar_today, 'Datum', a['datum']),
      _row(Icons.tag, 'Aktenzeichen', a['aktenzeichen']),
      _row(Icons.send, 'Methode', a['methode']),
      _row(Icons.flag, 'Status', a['status']),
      _row(Icons.support_agent, 'Ansprechpartner/in', a['ansprechpartner']),
      // Icons.phone, damit die Durchwahl per `phoneAwareText` wählbar wird —
      // genau dafür ist sie erfasst.
      _row(Icons.phone, 'Telefon', a['telefon']),
      _row(Icons.mail_outline, 'E-Mail', a['email']),
      if ((a['notiz']?.toString() ?? '').isNotEmpty) ...[
        const SizedBox(height: 8),
        Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: F.h(Colors.yellow, 50), borderRadius: BorderRadius.circular(8)),
          child: Text(a['notiz'].toString(), style: const TextStyle(fontSize: 12))),
      ],
    ]));
  }

  late Set<String> _checkedDocs;

  Widget _buildDokumente(Map<String, dynamic> a) {
    final leistung = a['leistung']?.toString() ?? '';
    final checklist = _requiredDocs[leistung] ?? _defaultDocs;
    final uploadedTypes = _docs.map((d) => d['doc_typ']?.toString() ?? '').toSet();
    // ⚠️ Gezählt wird NUR die Checkliste. Anschreiben und Checkliste des Amts
    // bringt niemand bei — sie im Zähler zu führen hiesse, den Antrag als
    // unvollständig zu melden, weil ein Anschreiben nicht eingescannt ist.
    final doneCount = checklist.where((c) => uploadedTypes.contains(c.$1) || _checkedDocs.contains(c.$1)).length;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.checklist, size: 20, color: F.h(Colors.indigo, 700)),
          const SizedBox(width: 8),
          Expanded(child: Text('Unterlagen-Checkliste', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: F.h(Colors.indigo, 700)))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: doneCount == checklist.length ? F.h(Colors.green, 100) : F.h(Colors.orange, 100), borderRadius: BorderRadius.circular(8)),
            child: Text('$doneCount / ${checklist.length}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: doneCount == checklist.length ? F.h(Colors.green, 800) : F.h(Colors.orange, 800))),
          ),
        ]),
        const SizedBox(height: 4),
        Text('Checkbox = als erledigt markieren (auch ohne Upload). Upload = Dokument hochladen.', style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
        if (doneCount == checklist.length)
          Container(
            width: double.infinity, margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: F.h(Colors.green, 50), borderRadius: BorderRadius.circular(8), border: Border.all(color: F.h(Colors.green, 300))),
            child: Row(children: [
              Icon(Icons.check_circle, size: 18, color: F.h(Colors.green, 700)),
              const SizedBox(width: 8),
              Text('Alle Unterlagen vollständig!', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: F.h(Colors.green, 800))),
            ]),
          ),
        const SizedBox(height: 12),
        _docAbschnitt('Beizubringen', Icons.upload_file, Colors.indigo,
            'Was das Mitglied dem Amt vorlegen muss.'),
        ...checklist.map((c) => _docZeile(c.$1, c.$2, c.$3, uploadedTypes)),
        const SizedBox(height: 16),
        _docAbschnitt('Vom Sozialamt erhalten', Icons.markunread_mailbox_outlined, Colors.teal,
            'Geht nicht zurück — zählt nicht in den Balken, gehört aber in die Akte.'),
        ..._amtsUnterlagen.map((c) => _docZeile(c.$1, c.$2, c.$3, uploadedTypes)),
      ]),
    );
  }

  /// Überschrift einer der beiden Gruppen im Reiter Dokumente.
  Widget _docAbschnitt(String titel, IconData icon, MaterialColor farbe, String erklaerung) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 15, color: F.h(farbe, 600)),
          const SizedBox(width: 6),
          Text(titel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: F.h(farbe, 700))),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: F.h(farbe, 100))),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(erklaerung, style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
        ),
      ]),
    );
  }

  /// Eine Zeile der Ablage. Identisch für beide Gruppen — Haken, „Aus Cloud",
  /// Hochladen und die schon abgelegten Dateien hängen am Schlüssel, nicht an
  /// der Gruppe.
  Widget _docZeile(String docTyp, String label, IconData icon, Set<String> uploadedTypes) {
        final hasUpload = uploadedTypes.contains(docTyp);
        final isChecked = hasUpload || _checkedDocs.contains(docTyp);
        final uploadedDocs = _docs.where((d) => d['doc_typ'] == docTyp).toList();
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: isChecked ? F.h(Colors.green, 50) : F.h(Colors.grey, 50),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isChecked ? F.h(Colors.green, 300) : F.h(Colors.grey, 300)),
          ),
          child: Column(children: [
            Row(children: [
              Checkbox(
                value: isChecked,
                activeColor: F.h(Colors.green, 700),
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _checkedDocs.add(docTyp);
                    } else {
                      _checkedDocs.remove(docTyp);
                    }
                  });
                  widget.onCheckedChanged(_checkedDocs);
                },
              ),
              Icon(icon, size: 18, color: isChecked ? F.h(Colors.green, 700) : F.h(Colors.grey, 500)),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isChecked ? F.h(Colors.green, 900) : F.textStark, decoration: isChecked ? TextDecoration.lineThrough : null))),
              IconButton(
                icon: Icon(Icons.cloud_download, size: 18, color: F.h(Colors.blue, 600)),
                tooltip: 'Aus Cloud',
                onPressed: () async {
                  final res = await CloudPickerHelper.uebernehmen(context, apiService: widget.apiService, memberId: widget.userId,
                      attach: (id) => widget.apiService.attachSozialamtAntragDocFromCloud(antragId: widget.antragId, cloudFileId: id, docTyp: docTyp),
                      // Dieselbe Liste wie am Geräte-Knopf daneben (_uploadDoc),
                      // sonst ließe sich über „Aus Cloud" ablegen, was „Dokument
                      // hochladen" verweigert.
                      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
                      // Einzeldatei wie am Geräte-Knopf: _uploadDoc nimmt nur
                      // files.first. Ohne die Grenze würde eine Mehrfachauswahl
                      // vollständig geholt und entschlüsselt, aber stillschweigend
                      // bis auf die erste Datei verworfen.
                      maxFiles: 1,
                      hochladen: (r) => _uploadDoc(docTyp, label, ausCloud: r));
                  if (res != null && mounted) { _load(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${res.ok} von ${res.total} aus Cloud übernommen${res.grund != null ? ' — ${res.grund}' : ''}'), backgroundColor: res.ok == res.total ? Colors.green : Colors.orange)); }
                },
              ),
              IconButton(
                icon: Icon(Icons.upload_file, size: 18, color: F.h(Colors.indigo, 600)),
                tooltip: 'Dokument hochladen',
                onPressed: () => _uploadDoc(docTyp, label),
              ),
            ]),
            if (uploadedDocs.isNotEmpty)
              ...uploadedDocs.map((d) => Padding(
                padding: const EdgeInsets.fromLTRB(48, 0, 16, 8),
                child: Row(children: [
                  Icon(Icons.attach_file, size: 12, color: F.h(Colors.green, 600)),
                  const SizedBox(width: 4),
                  Expanded(child: Text(d['datei_name']?.toString() ?? '', style: TextStyle(fontSize: 11, color: F.h(Colors.green, 800)))),
                  InkWell(onTap: () async {
                    try {
                      final resp = await widget.apiService.downloadAntragDoc(d['id'] as int);
                      if (resp.statusCode == 200 && mounted) {
                        final dir = await getTemporaryDirectory();
                        final file = sichereDatei(dir, d['datei_name']);
                        await file.writeAsBytes(resp.bodyBytes);
                        if (mounted) await FileViewerDialog.show(context, file.path, d['datei_name']?.toString() ?? '');
                      }
                    } catch (e) {
                      if (mounted) dateiFehlerMelden(context, e);
                    }
                  }, child: Icon(Icons.visibility, size: 14, color: F.h(Colors.indigo, 600))),
                  const SizedBox(width: 8),
                  InkWell(onTap: () async {
                    await widget.apiService.deleteAntragDoc(d['id'] as int);
                    _load();
                  }, child: Icon(Icons.delete_outline, size: 14, color: F.h(Colors.red, 400))),
                ]),
              )),
          ]),
        );
  }

  Future<void> _uploadDoc(String docTyp, String label, {FilePickerResult? ausCloud}) async {
    final result = ausCloud ?? await FilePickerHelper.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
    if (result == null || result.files.isEmpty || result.files.first.path == null) return;
    final file = result.files.first;
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wird hochgeladen...'), duration: Duration(seconds: 1)));
    await widget.apiService.uploadAntragDoc(antragId: widget.antragId, docTyp: docTyp, filePath: file.path!, fileName: file.name, notiz: label);
    _load();
  }

  Widget _buildVerlauf() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Expanded(child: Text('${_verlauf.length} Einträge', style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600)))),
        FilledButton.icon(icon: const Icon(Icons.add, size: 14), label: const Text('Neuer Eintrag', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.indigo, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: () { final datumC = TextEditingController(text: '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}'); final notizC = TextEditingController(); String status = '';
            showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (_, setD) => AlertDialog(title: const Text('Verlauf-Eintrag'),
              content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: datumC, decoration: const InputDecoration(labelText: 'Datum', isDense: true, border: OutlineInputBorder())), const SizedBox(height: 8),
                Wrap(spacing: 6, children: ['Eingereicht', 'In Bearbeitung', 'Nachforderung', 'Anhörung', 'Bewilligt', 'Abgelehnt', 'Widerspruch'].map((s) => ChoiceChip(label: Text(s, style: TextStyle(fontSize: 10, color: status == s ? Colors.white : F.textStark)), selected: status == s, selectedColor: Colors.indigo, onSelected: (_) => setD(() => status = s))).toList()), const SizedBox(height: 8),
                TextField(controller: notizC, maxLines: 3, decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder())),
              ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
                FilledButton(onPressed: () async { await widget.apiService.addAntragVerlauf(widget.antragId, {'datum': datumC.text, 'status': status, 'notiz': notizC.text}); if (ctx.mounted) Navigator.pop(ctx); _load(); }, child: const Text('Hinzufügen'))],
            ))); }),
      ])),
      Expanded(child: _verlauf.isEmpty ? Center(child: Text('Kein Verlauf', style: TextStyle(color: F.h(Colors.grey, 500))))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _verlauf.length, itemBuilder: (_, i) { final v = _verlauf[i];
          return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: F.flaeche, borderRadius: BorderRadius.circular(8), border: Border.all(color: F.h(Colors.indigo, 200))),
            child: Row(children: [
              Icon(Icons.circle, size: 10, color: F.h(Colors.indigo, 400)), const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Text(v['datum']?.toString() ?? '', style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))), if ((v['status']?.toString() ?? '').isNotEmpty) ...[const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: F.h(Colors.indigo, 100), borderRadius: BorderRadius.circular(6)), child: Text(v['status'].toString(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: F.h(Colors.indigo, 800))))]]),
                if ((v['notiz']?.toString() ?? '').isNotEmpty) Text(v['notiz'].toString(), style: const TextStyle(fontSize: 12)),
              ])),
              IconButton(icon: Icon(Icons.delete_outline, size: 16, color: F.h(Colors.red, 400)), onPressed: () async { await widget.apiService.deleteAntragVerlauf(v['id'] as int); _load(); }, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24)),
            ]));
        })),
    ]);
  }

  // ══════════════════════════════════════════════════════════
  // KORRESPONDENZ — Eingang/Ausgang mit Weg und Anhängen
  // ══════════════════════════════════════════════════════════

  /// Anhänge einer Zeile — der Server liefert sie mit der Liste, ein
  /// zweiter Aufruf je Eintrag entfällt damit.
  ///
  /// ⚠️ Fehlt das Feld (ältere Serverfassung), ist das eine LEERE Liste und
  /// kein Fehler: die Zeile bleibt lesbar, nur ohne Anhänge.
  List<Map<String, dynamic>> _korrDateien(Map<String, dynamic> k) {
    final roh = k['dateien'];
    if (roh is! List) return const [];
    return roh.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Widget _buildKorr() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Expanded(child: Text('${_korr.length} Einträge', style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600)))),
        FilledButton.icon(icon: const Icon(Icons.call_received, size: 14), label: const Text('Eingang', style: TextStyle(fontSize: 11)), style: FilledButton.styleFrom(backgroundColor: F.h(Colors.green, 600), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _addKorr('eingang')), const SizedBox(width: 6),
        FilledButton.icon(icon: const Icon(Icons.call_made, size: 14), label: const Text('Ausgang', style: TextStyle(fontSize: 11)), style: FilledButton.styleFrom(backgroundColor: F.h(Colors.blue, 600), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _addKorr('ausgang')),
      ])),
      Expanded(child: _korr.isEmpty ? Center(child: Text('Keine Korrespondenz', style: TextStyle(color: F.h(Colors.grey, 500))))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _korr.length, itemBuilder: (_, i) => _korrZeile(_korr[i]))),
    ]);
  }

  Widget _korrZeile(Map<String, dynamic> k) {
    // ⚠️ Nur 'ausgang' gilt als Ausgang. Ein leeres oder unbekanntes Feld
    // als Ausgang zu lesen würde die Beweisrichtung umdrehen — ein
    // eingegangener Bescheid stünde als eigenes Schreiben in der Akte.
    final isEin = raWert(k['richtung']) != 'ausgang';
    final id = (k['id'] as num?)?.toInt() ?? 0;
    final dateien = _korrDateien(k);
    final wegKey = raWert(k['weg']);
    final weg = kSozKorrWege[wegKey] ?? wegKey;
    final betreff = raWert(k['betreff']);
    final notiz = raWert(k['notiz']);
    final datum = raDatumDe(k['datum']);
    final farbe = isEin ? Colors.green : Colors.blue;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: F.flaeche, borderRadius: BorderRadius.circular(8), border: Border.all(color: F.h(farbe, 200))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(isEin ? Icons.call_received : Icons.call_made, size: 18, color: F.h(farbe, 700)), const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(betreff.isEmpty ? '(ohne Betreff)' : betreff,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: betreff.isEmpty ? F.h(Colors.grey, 500) : F.h(farbe, 800))),
            Wrap(spacing: 8, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (datum.isNotEmpty) Text(datum, style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
              if (weg.isNotEmpty) Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_wegIcon(wegKey), size: 11, color: F.h(Colors.grey, 600)), const SizedBox(width: 3),
                Text(weg, style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
              ]),
              if (dateien.isNotEmpty) Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.attach_file, size: 11, color: F.h(Colors.indigo, 500)), const SizedBox(width: 2),
                Text('${dateien.length}', style: TextStyle(fontSize: 10, color: F.h(Colors.indigo, 600))),
              ]),
            ]),
          ])),
          IconButton(icon: Icon(Icons.delete_outline, size: 16, color: F.h(Colors.red, 400)), onPressed: () => _korrLoeschen(k), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24)),
        ]),
        if (notiz.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 26, top: 4), child: Text(notiz, style: TextStyle(fontSize: 11, color: F.textStark))),
        for (final d in dateien) Padding(
          padding: const EdgeInsets.only(left: 22, top: 4),
          child: Row(children: [
            Icon(Icons.description_outlined, size: 13, color: F.h(Colors.indigo, 500)), const SizedBox(width: 5),
            Expanded(child: Text(raWert(d['datei_name']), style: TextStyle(fontSize: 11, color: F.h(Colors.indigo, 800)), overflow: TextOverflow.ellipsis)),
            Text(_dateiGroesse((d['file_size'] as num?)?.toInt() ?? 0), style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 500))), const SizedBox(width: 8),
            InkWell(onTap: () => _korrDateiAnsehen(d), child: Icon(Icons.visibility, size: 15, color: F.h(Colors.indigo, 600))), const SizedBox(width: 10),
            InkWell(onTap: () => _korrDateiLoeschen(d), child: Icon(Icons.delete_outline, size: 15, color: F.h(Colors.red, 400))),
          ]),
        ),
        if (id > 0) Padding(padding: const EdgeInsets.only(left: 22, top: 4), child: Row(children: [
          TextButton.icon(
            icon: const Icon(Icons.add, size: 14),
            label: const Text('Gerät', style: TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            onPressed: dateien.length >= kSozKorrMaxDateien ? null : () => _korrDateienNachtragen(id, dateien.length),
          ),
          const SizedBox(width: 6),
          CloudPickButton(
            memberId: widget.userId,
            apiService: widget.apiService,
            allowedExtensions: kSozKorrEndungen,
            // ⚠️ Der freie Rest, nicht die volle Zahl: sonst holt der Dialog
            // 20 Dateien, und der Server weist ab der Grenze jede einzelne ab —
            // nachdem sie schon entschlüsselt und übertragen wurden.
            maxFiles: kSozKorrMaxDateien - dateien.length,
            kompakt: true,
            enabled: dateien.length < kSozKorrMaxDateien,
            onPicked: (r) => _korrHochladen(id, r.files),
          ),
          const SizedBox(width: 8),
          if (dateien.length >= kSozKorrMaxDateien)
            Text('max. $kSozKorrMaxDateien', style: TextStyle(fontSize: 10, color: F.h(Colors.orange, 700))),
        ])),
      ]),
    );
  }

  static IconData _wegIcon(String weg) => switch (weg) {
        'email' || 'de_mail' => Icons.email_outlined,
        'fax' => Icons.print_outlined,
        'online' => Icons.language,
        'telefon' => Icons.call_outlined,
        'persoenlich' => Icons.person_outline,
        'einschreiben' => Icons.markunread_mailbox_outlined,
        'post' => Icons.mail_outline,
        _ => Icons.help_outline,
      };

  static String _dateiGroesse(int b) =>
      b >= 1048576 ? '${(b / 1048576).toStringAsFixed(1)} MB' : '${(b / 1024).ceil()} KB';

  Future<void> _korrLoeschen(Map<String, dynamic> k) async {
    final dateien = _korrDateien(k);
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Schriftstück löschen?'),
      content: Text(dateien.isEmpty
          ? 'Der Eintrag wird entfernt.'
          : 'Der Eintrag und seine ${dateien.length} Datei(en) werden entfernt. Das lässt sich nicht rückgängig machen.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
      ],
    ));
    if (ok != true) return;
    final r = await widget.apiService.deleteAntragKorrespondenz((k['id'] as num).toInt());
    if (!mounted) return;
    // Nicht blind neu laden: ein fehlgeschlagenes Löschen sähe sonst aus wie
    // ein Eintrag, der wieder auftaucht (dieselbe Falle wie bei _antragLoeschen).
    if (r['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nicht gelöscht: ${r['message'] ?? 'unbekannter Fehler'}'), backgroundColor: Colors.red));
      return;
    }
    _load();
  }

  Future<void> _korrDateiAnsehen(Map<String, dynamic> d) async {
    final name = raWert(d['datei_name']);
    try {
      final resp = await widget.apiService.downloadAntragKorrDoc((d['id'] as num).toInt());
      if (resp.statusCode != 200) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Datei nicht abrufbar (HTTP ${resp.statusCode})'), backgroundColor: Colors.red));
        return;
      }
      final dir = await getTemporaryDirectory();
      final file = sichereDatei(dir, name);
      await file.writeAsBytes(resp.bodyBytes);
      if (mounted) await FileViewerDialog.show(context, file.path, name);
    } catch (e) {
      if (mounted) dateiFehlerMelden(context, e);
    }
  }

  Future<void> _korrDateiLoeschen(Map<String, dynamic> d) async {
    final r = await widget.apiService.deleteAntragKorrDoc((d['id'] as num).toInt());
    if (!mounted) return;
    if (r['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nicht gelöscht: ${r['message'] ?? 'unbekannter Fehler'}'), backgroundColor: Colors.red));
      return;
    }
    _load();
  }

  Future<void> _korrDateienNachtragen(int korrId, int vorhanden) async {
    final r = await FilePickerHelper.pickFiles(
        type: FileType.custom, allowedExtensions: kSozKorrEndungen, allowMultiple: true);
    if (r == null || r.files.isEmpty) return;
    await _korrHochladen(korrId, r.files, vorhanden: vorhanden);
  }

  /// Lädt die Dateien einzeln hoch — der Endpunkt nimmt eine je Aufruf.
  ///
  /// ⚠️ Meldet, was NICHT durchkam, samt Grund. Ein stiller Teilerfolg wäre
  /// hier am teuersten: der Eintrag steht in der Akte, der Beleg fehlt, und
  /// nichts weist darauf hin.
  Future<void> _korrHochladen(int korrId, List<PlatformFile> dateien, {int vorhanden = 0}) async {
    var liste = dateien.where((f) => f.path != null).toList();
    final frei = kSozKorrMaxDateien - vorhanden;
    if (frei <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Höchstens $kSozKorrMaxDateien Dateien je Schriftstück'), backgroundColor: Colors.orange));
      }
      return;
    }
    var abgeschnitten = 0;
    if (liste.length > frei) { abgeschnitten = liste.length - frei; liste = liste.sublist(0, frei); }
    if (liste.isEmpty) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${liste.length} Datei(en) werden hochgeladen …'), duration: const Duration(seconds: 2)));
    }
    var ok = 0; String? grund;
    for (final f in liste) {
      final r = await widget.apiService.uploadAntragKorrDoc(korrId: korrId, filePath: f.path!, fileName: f.name);
      if (r['success'] == true) { ok++; } else { grund ??= raWert(r['message']); }
    }
    if (!mounted) return;
    final fehl = liste.length - ok;
    final text = StringBuffer('$ok von ${liste.length} Datei(en) angehängt');
    if (fehl > 0 && (grund ?? '').isNotEmpty) text.write(' — $grund');
    if (abgeschnitten > 0) text.write(' · $abgeschnitten übersprungen (max. $kSozKorrMaxDateien)');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text.toString()),
        backgroundColor: fehl == 0 && abgeschnitten == 0 ? Colors.green : Colors.orange));
    _load();
  }

  void _addKorr(String richtung) {
    final betreffC = TextEditingController();
    final notizC = TextEditingController();
    var datum = DateTime.now();
    var weg = kSozKorrWegVorgabe;
    final vorgemerkt = <PlatformFile>[];
    var speichert = false;

    showDialog(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx2, setDlg) => AlertDialog(
        title: Row(children: [
          Icon(richtung == 'eingang' ? Icons.call_received : Icons.call_made, size: 18,
              color: F.h(richtung == 'eingang' ? Colors.green : Colors.blue, 700)),
          const SizedBox(width: 8),
          Text(richtung == 'eingang' ? 'Eingang' : 'Ausgang', style: const TextStyle(fontSize: 16)),
        ]),
        content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: InkWell(
              onTap: () async {
                final d = await showDatePicker(
                  context: ctx2,
                  initialDate: datum,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2040),
                  locale: const Locale('de'),
                );
                if (d != null) setDlg(() => datum = d);
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Datum', isDense: true, prefixIcon: Icon(Icons.calendar_today, size: 16), border: OutlineInputBorder()),
                // Deutsch auf dem Schirm, ISO an den Server — MariaDB liest
                // „04.09.2026" als 0000-00-00, und das sähe aus wie „kein Datum".
                child: Text(raDatumDe(datum.toIso8601String()), style: const TextStyle(fontSize: 13)),
              ),
            )),
            const SizedBox(width: 8),
            Expanded(child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: weg,
              decoration: const InputDecoration(labelText: 'Weg', isDense: true, border: OutlineInputBorder()),
              items: kSozKorrWege.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12)))).toList(),
              onChanged: (v) => setDlg(() => weg = v ?? weg),
            )),
          ]),
          const SizedBox(height: 10),
          TextField(controller: betreffC, decoration: const InputDecoration(labelText: 'Betreff', isDense: true, border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: notizC, maxLines: 3, decoration: const InputDecoration(labelText: 'Notiz', alignLabelWithHint: true, isDense: true, border: OutlineInputBorder())),
          const Divider(height: 22),
          Row(children: [
            Icon(Icons.attach_file, size: 15, color: F.h(Colors.grey, 700)), const SizedBox(width: 5),
            Text('Anhänge', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: F.h(Colors.grey, 700))),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 15),
              label: const Text('Gerät', style: TextStyle(fontSize: 11.5)),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: Size.zero),
              onPressed: speichert ? null : () async {
                final r = await FilePickerHelper.pickFiles(
                    allowMultiple: true, type: FileType.custom, allowedExtensions: kSozKorrEndungen);
                if (r == null) return;
                setDlg(() => _vormerken(vorgemerkt, r.files));
              },
            ),
            CloudPickButton(
              memberId: widget.userId,
              apiService: widget.apiService,
              allowedExtensions: kSozKorrEndungen,
              // Beim Anlegen gibt es die Zeile noch nicht, also auch keine
              // korr_id — der Server kann hier nicht selbst kopieren. Die
              // Dateien kommen über das Gerät und gehen mit dem Speichern raus.
              maxFiles: kSozKorrMaxDateien - vorgemerkt.length,
              kompakt: true,
              enabled: !speichert && vorgemerkt.length < kSozKorrMaxDateien,
              onPicked: (r) => setDlg(() => _vormerken(vorgemerkt, r.files)),
            ),
          ]),
          if (vorgemerkt.isEmpty)
            Text('PDF, JPG, JPEG, PNG · max. $kSozKorrMaxDateien Dateien',
                style: TextStyle(fontSize: 10.5, color: F.h(Colors.grey, 500)))
          else
            for (final f in vorgemerkt)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                leading: Icon(Icons.description_outlined, size: 17, color: F.h(Colors.indigo, 500)),
                title: Text(f.name, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                subtitle: Text(_dateiGroesse(f.size), style: TextStyle(fontSize: 10.5, color: F.h(Colors.grey, 600))),
                trailing: IconButton(
                  icon: Icon(Icons.close, size: 16, color: F.h(Colors.red, 400)),
                  onPressed: speichert ? null : () => setDlg(() => vorgemerkt.remove(f)),
                ),
              ),
        ]))),
        actions: [
          TextButton(onPressed: speichert ? null : () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: speichert ? null : () async {
              setDlg(() => speichert = true);
              final res = await widget.apiService.addAntragKorrespondenz(widget.antragId, {
                'richtung': richtung,
                'weg': weg,
                'datum': datum.toIso8601String().substring(0, 10),
                'betreff': betreffC.text.trim(),
                'notiz': notizC.text.trim(),
              });
              if (res['success'] != true) {
                setDlg(() => speichert = false);
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      content: Text('Nicht gespeichert: ${res['message'] ?? 'unbekannter Fehler'}'), backgroundColor: Colors.red));
                }
                return;
              }
              final neueId = (res['id'] as num?)?.toInt() ?? 0;
              if (ctx.mounted) Navigator.pop(ctx);
              if (vorgemerkt.isEmpty) { _load(); return; }
              // ⚠️ Ohne id lässt sich nichts anhängen. Das dann stillschweigend
              // zu verschlucken hiesse: der Eintrag steht da, die Belege sind
              // weg, und niemand erfährt es.
              if (neueId <= 0) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Eintrag gespeichert, aber der Server hat keine Kennung geliefert — die ${vorgemerkt.length} Datei(en) sind NICHT angehängt.'),
                      backgroundColor: Colors.red));
                }
                _load();
                return;
              }
              await _korrHochladen(neueId, vorgemerkt);
            },
            child: speichert
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Speichern'),
          ),
        ],
      ),
    ));
  }

  /// Merkt neue Dateien vor, ohne Doppelte und ohne die Grenze zu reissen.
  void _vormerken(List<PlatformFile> ziel, List<PlatformFile> neu) {
    for (final f in neu) {
      if (ziel.length >= kSozKorrMaxDateien) break;
      if (f.path == null) continue;
      // Zweimal dieselbe Datei wäre zweimal derselbe Beleg in der Akte.
      if (ziel.any((v) => v.path == f.path)) continue;
      ziel.add(f);
    }
  }

  Widget _row(IconData icon, String label, dynamic value) {
    final s = value?.toString() ?? ''; if (s.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
      Icon(icon, size: 14, color: F.h(Colors.grey, 600)), const SizedBox(width: 8),
      SizedBox(width: 100, child: Text(label, style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600), fontWeight: FontWeight.w600))),
      // `phoneAwareText` ist ausserhalb von Telefon-Icons ein reines
      // `Text` — nur die Durchwahl der Sachbearbeitung wird wählbar.
      Expanded(child: phoneAwareText(icon, s, style: const TextStyle(fontSize: 13))),
    ]));
  }
}

// ═══════════════════════════════════════════════════════
// BEWILLIGUNG als Tab im Antrag (1:1) — Bescheid / Widerspruch / Unterlagen
// ═══════════════════════════════════════════════════════
class _AntragBewilligungTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int antragId;
  const _AntragBewilligungTab({required this.apiService, required this.userId, required this.antragId});
  @override
  State<_AntragBewilligungTab> createState() => _AntragBewilligungTabState();
}

class _AntragBewilligungTabState extends State<_AntragBewilligungTab> {
  Map<String, dynamic>? _b;
  List<Map<String, dynamic>> _docs = [];
  Map<String, dynamic>? _wbaTicket;   // Weiterbewilligung-Erinnerungsticket (aus wba_ticket)
  String? _wbaAction;                 // 'created'|'existing'|'updated' — nur direkt nach einem Speichern
  bool _loaded = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final r = await widget.apiService.listSozialamtBewilligungByAntrag(widget.antragId);
    Map<String, dynamic>? b;
    if (r['success'] == true && r['data'] is List && (r['data'] as List).isNotEmpty) {
      b = Map<String, dynamic>.from((r['data'] as List).first as Map);
    }
    List<Map<String, dynamic>> docs = [];
    if (b != null) {
      final bid = int.tryParse(b['id']?.toString() ?? '');
      if (bid != null) {
        final dR = await widget.apiService.listBewilligungDocs(bid);
        if (dR['success'] == true && dR['data'] is List) {
          docs = (dR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _b = b;
      _docs = docs;
      _wbaTicket = (b != null && b['wba_ticket'] is Map) ? Map<String, dynamic>.from(b['wba_ticket'] as Map) : null;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    if (_b == null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.assignment_turned_in_outlined, size: 48, color: F.h(Colors.grey, 300)),
          const SizedBox(height: 8),
          Text('Noch kein Bescheid erfasst', style: TextStyle(fontSize: 14, color: F.h(Colors.grey, 600))),
          const SizedBox(height: 4),
          Text('Bewilligungs- oder Ablehnungsbescheid zu diesem Antrag erfassen.', style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 500)), textAlign: TextAlign.center),
          const SizedBox(height: 14),
          ElevatedButton.icon(onPressed: () => _showForm(), icon: const Icon(Icons.add, size: 18), label: const Text('Bescheid erfassen'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white)),
        ]),
      ));
    }
    final b = _b!;
    final ok = b['bewilligt'] == true || b['bewilligt'] == 'true' || b['bewilligt'] == 1 || b['bewilligt'] == '1';
    final headColor = ok ? Colors.green : Colors.red;
    return DefaultTabController(length: 3, child: Column(children: [
      Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        color: F.h(headColor, 50),
        child: Row(children: [
          Icon(ok ? Icons.check_circle : Icons.cancel, size: 18, color: F.h(headColor, 700)),
          const SizedBox(width: 8),
          Expanded(child: Text('${ok ? 'Bewilligt' : 'Abgelehnt'}${(b['bescheid_datum']?.toString() ?? '').isNotEmpty ? ' • ${b['bescheid_datum']}' : ''}${(b['aktenzeichen']?.toString() ?? '').isNotEmpty ? ' • Az. ${b['aktenzeichen']}' : ''}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: F.h(headColor, 800)))),
          IconButton(icon: Icon(Icons.edit, size: 18, color: F.h(Colors.grey, 700)), tooltip: 'Bearbeiten', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: () => _showForm(existing: b)),
          IconButton(icon: Icon(Icons.delete_outline, size: 18, color: F.h(Colors.red, 400)), tooltip: 'Löschen', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: _delete),
        ]),
      ),
      TabBar(labelColor: F.h(Colors.green, 700), unselectedLabelColor: F.h(Colors.grey, 600), indicatorColor: F.h(Colors.green, 700), isScrollable: true, tabs: const [
        Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Bescheid'),
        Tab(icon: Icon(Icons.gavel, size: 18), text: 'Widerspruch'),
        Tab(icon: Icon(Icons.folder, size: 18), text: 'Unterlagen'),
      ]),
      Expanded(child: TabBarView(children: [
        _buildDetails(b),
        _buildWiderspruch(b),
        _buildUnterlagen(),
      ])),
    ]));
  }

  Future<void> _delete() async {
    final b = _b; if (b == null) return;
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Bescheid löschen?'),
      content: const Text('Diesen Bescheid inkl. Unterlagen wirklich löschen?'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')), FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('Löschen'))],
    ));
    if (confirm == true) {
      final bid = int.tryParse(b['id']?.toString() ?? '');
      if (bid != null) await widget.apiService.deleteSozialamtBewilligung(bid);
      _load();
    }
  }

  void _showForm({Map<String, dynamic>? existing}) {
    final isEdit = existing != null;
    String leistung = existing?['leistung']?.toString() ?? '';
    final aktenzeichenC = TextEditingController(text: existing?['aktenzeichen']?.toString() ?? '');
    final bescheidDatumC = TextEditingController(text: existing?['bescheid_datum']?.toString() ?? '');
    final erhaltenAmC = TextEditingController(text: existing?['erhalten_am']?.toString() ?? '');
    final zeitraumVonC = TextEditingController(text: existing?['zeitraum_von']?.toString() ?? '');
    final zeitraumBisC = TextEditingController(text: existing?['zeitraum_bis']?.toString() ?? '');
    final regelbedarfC = TextEditingController(text: existing?['regelbedarf']?.toString() ?? '');
    final mehrbedarfC = TextEditingController(text: existing?['mehrbedarf']?.toString() ?? '');
    final kaltmieteC = TextEditingController(text: existing?['kaltmiete']?.toString() ?? '');
    final nebenkostenC = TextEditingController(text: existing?['nebenkosten']?.toString() ?? '');
    final heizkostenC = TextEditingController(text: existing?['heizkosten']?.toString() ?? '');
    final einkommenC = TextEditingController(text: existing?['einkommen']?.toString() ?? '');
    final auszahlungC = TextEditingController(text: existing?['auszahlung']?.toString() ?? '');
    final notizC = TextEditingController(text: existing?['notiz']?.toString() ?? '');
    bool bewilligt = existing?['bewilligt'] == true || existing?['bewilligt'] == 'true' || existing?['bewilligt'] == 1 || existing?['bewilligt'] == '1' || (existing == null);
    bool widerspruch = existing?['widerspruch'] == true || existing?['widerspruch'] == 'true' || existing?['widerspruch'] == 1 || existing?['widerspruch'] == '1';
    final widerspruchDatumC = TextEditingController(text: existing?['widerspruch_datum']?.toString() ?? '');
    final leistungen = ['Grundsicherung im Alter', 'Grundsicherung bei Erwerbsminderung', 'Hilfe zum Lebensunterhalt', 'Eingliederungshilfe', 'Hilfe zur Pflege', 'Bildung und Teilhabe', 'Blindengeld', 'Sonstige'];

    Future<void> pickDate(BuildContext ctx, TextEditingController c) async {
      final p = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
      if (p != null) c.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}';
    }

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(isEdit ? 'Bescheid bearbeiten' : 'Bescheid erfassen'),
      content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        DropdownButtonFormField<String>(
          isExpanded: true,initialValue: leistungen.contains(leistung) ? leistung : null, decoration: InputDecoration(labelText: 'Leistungsart *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), items: leistungen.map((l) => DropdownMenuItem(value: l, child: Text(l, style: const TextStyle(fontSize: 12)))).toList(), onChanged: (v) => setD(() => leistung = v ?? '')),
        const SizedBox(height: 8),
        TextField(controller: aktenzeichenC, decoration: InputDecoration(labelText: 'Aktenzeichen', prefixIcon: const Icon(Icons.numbers, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 8),
        Row(children: [
          ChoiceChip(avatar: Icon(Icons.check_circle, size: 14, color: bewilligt ? Colors.white : Colors.green), label: Text('Bewilligt', style: TextStyle(fontSize: 11, color: bewilligt ? Colors.white : F.textStark)), selected: bewilligt, selectedColor: Colors.green, onSelected: (_) => setD(() => bewilligt = true)),
          const SizedBox(width: 8),
          ChoiceChip(avatar: Icon(Icons.cancel, size: 14, color: !bewilligt ? Colors.white : Colors.red), label: Text('Abgelehnt', style: TextStyle(fontSize: 11, color: !bewilligt ? Colors.white : F.textStark)), selected: !bewilligt, selectedColor: Colors.red, onSelected: (_) => setD(() => bewilligt = false)),
        ]),
        const SizedBox(height: 8),
        TextField(controller: bescheidDatumC, readOnly: true, decoration: InputDecoration(labelText: 'Bescheid-Datum *', prefixIcon: const Icon(Icons.calendar_today, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onTap: () async { await pickDate(ctx2, bescheidDatumC); setD(() {}); }),
        const SizedBox(height: 8),
        TextField(controller: erhaltenAmC, readOnly: true, decoration: InputDecoration(labelText: 'Erhalten per Post am', prefixIcon: const Icon(Icons.local_post_office, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), helperText: 'Wichtig für Widerspruchsfrist (1 Monat ab Zugang)'), onTap: () async { await pickDate(ctx2, erhaltenAmC); setD(() {}); }),
        const SizedBox(height: 8),
        Text('Bewilligungszeitraum', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: F.h(Colors.grey, 700))),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: TextField(controller: zeitraumVonC, readOnly: true, decoration: InputDecoration(labelText: 'Von', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onTap: () async { await pickDate(ctx2, zeitraumVonC); setD(() {}); })),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: zeitraumBisC, readOnly: true, decoration: InputDecoration(labelText: 'Bis', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onTap: () async { await pickDate(ctx2, zeitraumBisC); setD(() {}); })),
        ]),
        if (bewilligt) ...[
          const SizedBox(height: 12),
          Text('Berechnungsbogen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: F.h(Colors.grey, 700))),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: TextField(controller: regelbedarfC, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Regelbedarf €', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: mehrbedarfC, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Mehrbedarf €', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
          ]),
          const SizedBox(height: 8),
          Text('Kosten der Unterkunft (KdU)', style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
          const SizedBox(height: 4),
          FeldReihe(
            // Drei bis fünf Felder nebeneinander lassen auf 448 dp
            // je 83–139 dp übrig — kein Überlauf, aber nichts mehr,
            // worin sich ein Datum eintippen ließe.
            felder: [
              TextField(controller: kaltmieteC, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Kaltmiete €', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
              TextField(controller: nebenkostenC, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Nebenkosten €', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
              TextField(controller: heizkostenC, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Heizkosten €', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
            ],
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: einkommenC, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Anrechenb. Einkommen €', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: auszahlungC, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Auszahlung €/Monat', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), style: TextStyle(fontWeight: FontWeight.bold, color: F.h(Colors.green, 800)))),
          ]),
        ],
        const SizedBox(height: 8),
        Row(children: [
          Checkbox(value: widerspruch, onChanged: (v) => setD(() => widerspruch = v ?? false)),
          const Text('Widerspruch eingelegt', style: TextStyle(fontSize: 12)),
        ]),
        if (widerspruch)
          TextField(controller: widerspruchDatumC, readOnly: true, decoration: InputDecoration(labelText: 'Widerspruch am', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onTap: () async { await pickDate(ctx2, widerspruchDatumC); setD(() {}); }),
        const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notizen', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          if (leistung.isEmpty || bescheidDatumC.text.isEmpty) {
            ScaffoldMessenger.of(ctx2).showSnackBar(const SnackBar(content: Text('Bitte Leistungsart und Bescheid-Datum ausfüllen'), backgroundColor: Colors.red));
            return;
          }
          final res = await widget.apiService.saveSozialamtBewilligung(widget.userId, {
            if (isEdit) 'id': existing['id'],
            'antrag_id': widget.antragId,
            'leistung': leistung, 'aktenzeichen': aktenzeichenC.text.trim(), 'bewilligt': bewilligt, 'bescheid_datum': bescheidDatumC.text, 'erhalten_am': erhaltenAmC.text,
            'zeitraum_von': zeitraumVonC.text, 'zeitraum_bis': zeitraumBisC.text,
            'regelbedarf': double.tryParse(regelbedarfC.text), 'mehrbedarf': double.tryParse(mehrbedarfC.text),
            'kaltmiete': double.tryParse(kaltmieteC.text), 'nebenkosten': double.tryParse(nebenkostenC.text), 'heizkosten': double.tryParse(heizkostenC.text),
            'einkommen': double.tryParse(einkommenC.text), 'auszahlung': double.tryParse(auszahlungC.text),
            'widerspruch': widerspruch, 'widerspruch_datum': widerspruchDatumC.text, 'notiz': notizC.text,
          });
          if (res['success'] != true) {
            if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Fehler: ${res['message'] ?? 'Speichern fehlgeschlagen'}'), backgroundColor: Colors.red));
            return;
          }
          _wbaAction = res['wba_action']?.toString();
          final tid = res['wba_ticket'] is Map ? (res['wba_ticket'] as Map)['ticket_id'] : null;
          if (ctx.mounted) Navigator.pop(ctx);
          if (mounted && _wbaAction != null && _wbaAction != 'skipped' && tid != null) {
            final msg = switch (_wbaAction) {
              'created' => 'Gespeichert · Weiterbewilligung-Ticket #$tid neu erstellt',
              'updated' => 'Gespeichert · Bewilligungsende geändert — neues Ticket #$tid angelegt, altes geschlossen',
              'existing' => 'Gespeichert · Weiterbewilligung-Ticket #$tid bereits angelegt',
              _ => 'Gespeichert',
            };
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: F.h(Colors.indigo, 600), duration: const Duration(seconds: 4)));
          }
          _load();
        }, child: Text(isEdit ? 'Speichern' : 'Hinzufügen')),
      ],
    )));
  }

  // ============ BESCHEID DETAILS ============
  Widget _buildDetails(Map<String, dynamic> b) {
    final ok = b['bewilligt'] == true || b['bewilligt'] == 'true' || b['bewilligt'] == 1 || b['bewilligt'] == '1';
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dRow(Icons.description, 'Leistungsart', b['leistung']),
      _dRow(Icons.numbers, 'Aktenzeichen', b['aktenzeichen']),
      _dRow(ok ? Icons.check_circle : Icons.cancel, 'Status', ok ? 'Bewilligt' : 'Abgelehnt'),
      _dRow(Icons.calendar_today, 'Bescheid-Datum', b['bescheid_datum']),
      _dRow(Icons.local_post_office, 'Erhalten per Post', b['erhalten_am']),
      const SizedBox(height: 8),
      if ((b['zeitraum_von']?.toString() ?? '').isNotEmpty) ...[
        Text('Bewilligungszeitraum', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: F.h(Colors.grey, 700))),
        const SizedBox(height: 4),
        _dRow(Icons.date_range, 'Von – Bis', '${b['zeitraum_von']} – ${b['zeitraum_bis'] ?? ''}'),
      ],
      if (ok) ...[
        const SizedBox(height: 8),
        Text('Berechnungsbogen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: F.h(Colors.grey, 700))),
        const SizedBox(height: 4),
        _dRow(Icons.euro, 'Regelbedarf', _eur(b['regelbedarf'])),
        _dRow(Icons.euro, 'Mehrbedarf', _eur(b['mehrbedarf'])),
        const SizedBox(height: 4),
        Text('Kosten der Unterkunft (KdU)', style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
        _dRow(Icons.home, 'Kaltmiete', _eur(b['kaltmiete'])),
        _dRow(Icons.water_drop, 'Nebenkosten', _eur(b['nebenkosten'])),
        _dRow(Icons.thermostat, 'Heizkosten', _eur(b['heizkosten'])),
        const Divider(height: 16),
        _dRow(Icons.remove_circle_outline, 'Anrechenb. Einkommen', _eur(b['einkommen'])),
        Container(
          margin: const EdgeInsets.only(top: 4), padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: F.h(Colors.green, 50), borderRadius: BorderRadius.circular(8), border: Border.all(color: F.h(Colors.green, 300))),
          child: Row(children: [
            Icon(Icons.payments, size: 18, color: F.h(Colors.green, 800)), const SizedBox(width: 8),
            Text('Auszahlung: ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: F.h(Colors.green, 800))),
            Text('${_eur(b['auszahlung'])} /Monat', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: F.h(Colors.green, 900))),
          ]),
        ),
        if (_wbaTicket != null) ...[
          const SizedBox(height: 10),
          _buildWbaCard(),
        ],
      ],
      if (b['widerspruch'] == true || b['widerspruch'] == 'true' || b['widerspruch'] == 1 || b['widerspruch'] == '1') ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: F.h(Colors.orange, 50), borderRadius: BorderRadius.circular(8), border: Border.all(color: F.h(Colors.orange, 300))),
          child: Row(children: [
            Icon(Icons.warning, size: 18, color: F.h(Colors.orange, 800)), const SizedBox(width: 8),
            Expanded(child: Text('Widerspruch eingelegt${(b['widerspruch_datum']?.toString() ?? '').isNotEmpty ? ' am ${b['widerspruch_datum']}' : ''}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: F.h(Colors.orange, 800)))),
          ]),
        ),
      ],
      if ((b['notiz']?.toString() ?? '').isNotEmpty) ...[
        const SizedBox(height: 8),
        Container(
          width: double.infinity, padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: F.h(Colors.yellow, 50), borderRadius: BorderRadius.circular(8)),
          child: Text(b['notiz'].toString(), style: const TextStyle(fontSize: 12)),
        ),
      ],
    ]));
  }

  Widget _buildWbaCard() {
    final t = _wbaTicket!;
    final (Color chipColor, String chipText, Color cardColor, Color cardBorder, String headline) = switch (_wbaAction) {
      'updated'  => (F.h(Colors.orange, 100), 'Aktualisiert',     F.h(Colors.orange, 50), F.h(Colors.orange, 300), 'Weiterbewilligung-Ticket aktualisiert'),
      'existing' => (F.h(Colors.teal, 100),   'Bereits angelegt', F.h(Colors.teal, 50),   F.h(Colors.teal, 300),   'Weiterbewilligung-Ticket ist gesetzt'),
      'created'  => (F.h(Colors.green, 100),  'Neu erstellt',     F.h(Colors.indigo, 50), F.h(Colors.indigo, 300), 'Weiterbewilligung-Ticket erstellt'),
      _          => (F.h(Colors.blue, 100),   'Aktiv',            F.h(Colors.indigo, 50), F.h(Colors.indigo, 300), 'Weiterbewilligung-Erinnerung geplant'),
    };
    final textColor = switch (_wbaAction) { 'updated' => F.h(Colors.orange, 800), 'existing' => F.h(Colors.teal, 800), _ => F.h(Colors.indigo, 800) };
    final iconColor = switch (_wbaAction) { 'updated' => F.h(Colors.orange, 700), 'existing' => F.h(Colors.teal, 700), _ => F.h(Colors.indigo, 700) };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(8), border: Border.all(color: cardBorder, width: 1.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.event_available, color: iconColor, size: 22),
          const SizedBox(width: 8),
          Expanded(child: Text(headline, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textColor))),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: chipColor, borderRadius: BorderRadius.circular(10)), child: Text(chipText, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor))),
        ]),
        const SizedBox(height: 8),
        Text('Ticket #${t['ticket_id']}', style: const TextStyle(fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.w600)),
        if ((t['subject']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(t['subject'].toString(), style: const TextStyle(fontSize: 12)),
        ],
        const SizedBox(height: 6),
        Row(children: [
          Icon(Icons.calendar_today, size: 14, color: iconColor),
          const SizedBox(width: 4),
          Text('Geplant für: ', style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700))),
          Text(_fmtWbaDate(t['scheduled_date']?.toString()), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor)),
          const Spacer(),
          if ((t['bis']?.toString() ?? '').isNotEmpty) Text('Bewilligung bis ${t['bis']}', style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
        ]),
        const SizedBox(height: 4),
        Text('→ Erscheint in der Ticketverwaltung 2 Monate vor Bewilligungsende, damit der Weiterbewilligungsantrag rechtzeitig gestellt wird.', style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 700), fontStyle: FontStyle.italic)),
      ]),
    );
  }

  String _fmtWbaDate(String? s) {
    if (s == null || s.isEmpty) return '—';
    final datePart = s.split(' ').first;
    final p = datePart.split('-');
    return p.length == 3 ? '${p[2]}.${p[1]}.${p[0]}' : s;
  }

  String _eur(dynamic v) {
    final s = v?.toString() ?? '';
    if (s.isEmpty || s == 'null' || s == '0' || s == '0.00') return '';
    return '$s €';
  }

  Widget _dRow(IconData icon, String label, dynamic value) {
    final s = value?.toString() ?? ''; if (s.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
      Icon(icon, size: 14, color: F.h(Colors.grey, 600)), const SizedBox(width: 8),
      SizedBox(width: 130, child: Text(label, style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600), fontWeight: FontWeight.w600))),
      Expanded(child: Text(s, style: const TextStyle(fontSize: 13))),
    ]));
  }

  // ============ UNTERLAGEN ============
  Widget _buildUnterlagen() {
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Row(children: [
        Icon(Icons.folder, size: 20, color: F.h(Colors.green, 700)), const SizedBox(width: 8),
        Expanded(child: Text('Unterlagen (${_docs.length})', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: F.h(Colors.green, 700)))),
        OutlinedButton.icon(
          onPressed: _pickFromCloud,
          icon: const Icon(Icons.cloud_download, size: 16), label: const Text('Aus Cloud', style: TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(foregroundColor: F.h(Colors.blue, 700)),
        ),
        const SizedBox(width: 6),
        ElevatedButton.icon(
          onPressed: _uploadDoc,
          icon: const Icon(Icons.upload_file, size: 16), label: const Text('Hochladen', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
        ),
      ])),
      Expanded(child: _docs.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.cloud_upload, size: 48, color: F.h(Colors.grey, 300)), const SizedBox(height: 8),
              Text('Keine Unterlagen', style: TextStyle(color: F.h(Colors.grey, 500))),
              const SizedBox(height: 4),
              Text('Bewilligungsbescheid, Berechnungsbogen etc. hochladen', style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 400))),
            ]))
          : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: _docs.length, itemBuilder: (_, i) {
              final d = _docs[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: F.flaeche, borderRadius: BorderRadius.circular(8), border: Border.all(color: F.h(Colors.green, 200))),
                child: Row(children: [
                  Icon(Icons.attach_file, size: 18, color: F.h(Colors.green, 700)), const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(d['datei_name']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: F.h(Colors.green, 800))),
                    if ((d['created_at']?.toString() ?? '').isNotEmpty) Text(d['created_at'].toString(), style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
                  ])),
                  IconButton(icon: Icon(Icons.visibility, size: 18, color: F.h(Colors.indigo, 600)), tooltip: 'Anzeigen', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: () async {
                    try {
                      final resp = await widget.apiService.downloadBewilligungDoc(d['id'] as int);
                      if (resp.statusCode == 200 && mounted) {
                        final dir = await getTemporaryDirectory();
                        final file = sichereDatei(dir, d['datei_name']);
                        await file.writeAsBytes(resp.bodyBytes);
                        if (mounted) await FileViewerDialog.show(context, file.path, d['datei_name']?.toString() ?? '');
                      }
                    } catch (e) {
                      if (mounted) dateiFehlerMelden(context, e);
                    }
                  }),
                  IconButton(icon: Icon(Icons.download, size: 18, color: F.h(Colors.green, 700)), tooltip: 'Herunterladen', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: () async {
                    try {
                      // Herunterladen heisst behalten — vorher ging die Datei nur ins
                      // Temp-Verzeichnis und von dort an eine fremde App.
                      final resp = await widget.apiService.downloadBewilligungDoc(d['id'] as int);
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
                  IconButton(icon: Icon(Icons.delete_outline, size: 18, color: F.h(Colors.red, 400)), tooltip: 'Löschen', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: () async {
                    await widget.apiService.deleteBewilligungDoc(d['id'] as int);
                    _load();
                  }),
                ]),
              );
            })),
    ]);
  }

  Future<void> _uploadDoc({FilePickerResult? ausCloud}) async {
    final bid = int.tryParse(_b?['id']?.toString() ?? '');
    if (bid == null) return;
    final result = ausCloud ?? await FilePickerHelper.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'], allowMultiple: true);
    if (result == null || result.files.isEmpty) return;
    final files = result.files.where((f) => f.path != null).toList();
    if (files.isEmpty) return;
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${files.length} Datei(en) werden hochgeladen...'), duration: const Duration(seconds: 2)));
    for (final file in files) {
      await widget.apiService.uploadBewilligungDoc(bewilligungId: bid, filePath: file.path!, fileName: file.name);
    }
    _load();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${files.length} Datei(en) hochgeladen'), backgroundColor: Colors.green));
  }

  /// „Aus Cloud" — nimmt den zuständigen der beiden Speicher.
  ///
  /// Mitglied (1 GB): der Server hängt die Datei serverseitig an, sie berührt
  /// das Gerät nie. Eigene Akte des Vorsitzenden (50 GB, Ende-zu-Ende): das
  /// geht nicht, der Server kennt den Schlüssel nicht — dort wird lokal
  /// entschlüsselt und wie eine Geräte-Datei hochgeladen.
  Future<void> _pickFromCloud() async {
    final bid = int.tryParse(_b?['id']?.toString() ?? '');
    if (bid == null) return;
    // Der Vorsitzende in seiner EIGENEN Akte: seine Unterlagen liegen im
    // verschlüsselten 50-GB-Speicher. Den kann der Server nicht selbst
    // kopieren — er kennt den Schlüssel nicht. Also lokal entschlüsseln und
    // über den gewöhnlichen Upload-Weg ablegen.
    if (CloudPickerHelper.istVerschluesselt(widget.userId)) {
      final r = await CloudPickerHelper.pickFiles(context,
          apiService: widget.apiService,
          memberId: widget.userId,
          // Dieselbe Liste wie am Geräte-Knopf daneben (_uploadDoc).
          allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png']);
      if (r != null) await _uploadDoc(ausCloud: r);
      return;
    }
    final mnr = GlobalChatService().currentMitgliedernummer;
    if (mnr == null || mnr.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kein Admin angemeldet'), backgroundColor: Colors.red));
      return;
    }
    // Vor der asynchronen Lücke geholt, denn gefiltert wird erst nach dem
    // Schließen des Dialogs.
    final messenger = ScaffoldMessenger.of(context);
    // Volle Zeilen statt bloßer IDs, denn der Typfilter braucht den Dateinamen.
    final rows = await showCloudFilePickerFiles(context, apiService: widget.apiService, memberId: widget.userId, mitgliedernummer: mnr);
    if (rows == null || rows.isEmpty || !mounted) return;
    // Auch der Mitglieder-Cloud muss filtern: sonst ließe genau derselbe Knopf
    // über den 1-GB-Speicher einen Typ durch, den der Geräte-Knopf ablehnt.
    final picked = nurErlaubteEndungen(messenger, rows,
            dateiname: cloudZeilenDateiname,
            allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'])
        .map((r) => (r['id'] as num).toInt())
        .toList();
    if (picked.isEmpty || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${picked.length} Datei(en) werden übernommen...'), duration: const Duration(seconds: 2)));
    int ok = 0;
    for (final cfId in picked) {
      final r = await widget.apiService.attachBewilligungDocFromCloud(bewilligungId: bid, cloudFileId: cfId);
      if (r['success'] == true) ok++;
    }
    if (!mounted) return;
    _load();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$ok von ${picked.length} aus Cloud übernommen'), backgroundColor: ok == picked.length ? Colors.green : Colors.orange));
  }

  // ============ WIDERSPRUCH ============

  DateTime? _parseDate(dynamic v) {
    final s = v?.toString() ?? '';
    if (s.isEmpty || s == 'null') return null;
    return DateTime.tryParse(s);
  }

  // § 37 Abs. 2 SGB X: Bekanntgabe = 3 Tage nach Aufgabe zur Post
  // § 84 SGG: Widerspruchsfrist = 1 Monat nach Bekanntgabe
  // Ohne Rechtsbehelfsbelehrung: 1 Jahr (§ 66 SGG)
  DateTime _addMonth(DateTime d, int months) {
    var y = d.year; var m = d.month + months;
    while (m > 12) { y++; m -= 12; }
    var day = d.day;
    final maxDay = DateTime(y, m + 1, 0).day;
    if (day > maxDay) day = maxDay;
    var result = DateTime(y, m, day);
    // Falls Fristende auf Wochenende/Feiertag → nächster Werktag
    while (result.weekday == DateTime.saturday || result.weekday == DateTime.sunday) {
      result = result.add(const Duration(days: 1));
    }
    return result;
  }

  Widget _buildWiderspruch(Map<String, dynamic> b) {
    final bescheidDatum = _parseDate(b['bescheid_datum']);
    final erhaltenAm = _parseDate(b['erhalten_am']);
    final hasWiderspruch = b['widerspruch'] == true || b['widerspruch'] == 'true' || b['widerspruch'] == 1 || b['widerspruch'] == '1';
    final widerspruchDatum = _parseDate(b['widerspruch_datum']);

    if (bescheidDatum == null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.warning, size: 48, color: F.h(Colors.orange, 300)),
          const SizedBox(height: 8),
          Text('Kein Bescheid-Datum vorhanden', style: TextStyle(fontSize: 14, color: F.h(Colors.grey, 600))),
          const SizedBox(height: 4),
          Text('Bitte zuerst das Bescheid-Datum eintragen um die Fristen zu berechnen.', style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 500)), textAlign: TextAlign.center),
        ]),
      ));
    }

    // Bekanntgabe: erhalten_am oder bescheid_datum + 3 Tage (Bekanntgabefiktion)
    final bekanntgabe = erhaltenAm ?? bescheidDatum.add(const Duration(days: 3));
    final fristEnde = _addMonth(bekanntgabe, 1);
    final fristOhneRHB = _addMonth(bekanntgabe, 12); // ohne Rechtsbehelfsbelehrung
    final heute = DateTime.now();
    final heute0 = DateTime(heute.year, heute.month, heute.day);
    final restTage = fristEnde.difference(heute0).inDays;
    final fristAbgelaufen = heute0.isAfter(fristEnde);
    final fristJahrAbgelaufen = heute0.isAfter(fristOhneRHB);
    final letzteWoche = !fristAbgelaufen && restTage <= 7;

    String fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

    final statusColor = hasWiderspruch
        ? Colors.blue
        : fristAbgelaufen
            ? Colors.red
            : letzteWoche
                ? Colors.orange
                : Colors.green;

    final statusText = hasWiderspruch
        ? 'Widerspruch eingelegt${widerspruchDatum != null ? ' am ${fmt(widerspruchDatum)}' : ''}'
        : fristAbgelaufen
            ? 'Frist abgelaufen seit ${-restTage} Tagen'
            : '$restTage Tage verbleibend';

    final statusIcon = hasWiderspruch
        ? Icons.check_circle
        : fristAbgelaufen
            ? Icons.cancel
            : letzteWoche
                ? Icons.warning
                : Icons.timer;

    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Status-Banner
      Container(
        width: double.infinity, padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: F.h(statusColor, 50),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: F.h(statusColor, 300), width: 2),
        ),
        child: Row(children: [
          Icon(statusIcon, size: 28, color: F.h(statusColor, 700)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(statusText, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: F.h(statusColor, 800))),
            if (!hasWiderspruch && !fristAbgelaufen)
              Text('Fristende: ${fmt(fristEnde)}', style: TextStyle(fontSize: 12, color: F.h(statusColor, 700))),
          ])),
        ]),
      ),
      const SizedBox(height: 16),

      // Bescheid-Prüfung
      ..._buildBescheidPruefung(b, fristAbgelaufen),

      const SizedBox(height: 16),

      // Timeline
      Text('Fristenberechnung', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: F.h(Colors.grey, 800))),
      const SizedBox(height: 12),
      _timelineItem(Icons.description, 'Bescheid erstellt', fmt(bescheidDatum), Colors.indigo, true),
      if (erhaltenAm != null)
        _timelineItem(Icons.local_post_office, 'Per Post erhalten', fmt(erhaltenAm), Colors.teal, true)
      else
        _timelineItem(Icons.local_post_office, 'Bekanntgabe (Fiktion: +3 Tage)', fmt(bekanntgabe), F.h(Colors.teal, 300), true, subtitle: '§ 37 Abs. 2 SGB X: Gilt als am 3. Tag nach Aufgabe zur Post zugestellt'),
      _timelineItem(
        fristAbgelaufen ? Icons.cancel : Icons.gavel,
        'Widerspruchsfrist endet',
        fmt(fristEnde),
        fristAbgelaufen ? Colors.red : letzteWoche ? Colors.orange : Colors.green,
        true,
        subtitle: '§ 84 SGG: 1 Monat nach Bekanntgabe',
      ),
      if (!fristAbgelaufen && !hasWiderspruch)
        _timelineItem(Icons.timer, 'Heute', fmt(heute0), Colors.blue, false, subtitle: '$restTage Tage verbleibend'),
      if (hasWiderspruch && widerspruchDatum != null)
        _timelineItem(Icons.check_circle, 'Widerspruch eingelegt', fmt(widerspruchDatum), Colors.blue, false),

      const SizedBox(height: 16),

      // Rechtsgrundlage
      Container(
        width: double.infinity, padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: F.h(Colors.grey, 50), borderRadius: BorderRadius.circular(10), border: Border.all(color: F.h(Colors.grey, 300))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Rechtsgrundlage', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: F.h(Colors.grey, 700))),
          const SizedBox(height: 6),
          _lawRow('§ 84 SGG', 'Widerspruchsfrist: 1 Monat nach Bekanntgabe'),
          _lawRow('§ 37 Abs. 2 SGB X', 'Bekanntgabefiktion: 3 Tage nach Aufgabe zur Post'),
          _lawRow('§ 66 SGG', 'Ohne Rechtsbehelfsbelehrung: Frist verlängert auf 1 Jahr'),
          _lawRow('§ 84 Abs. 2 SGG', 'Fristende auf Wochenende/Feiertag: nächster Werktag'),
        ]),
      ),

      if (!fristJahrAbgelaufen && fristAbgelaufen) ...[
        const SizedBox(height: 12),
        Container(
          width: double.infinity, padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: F.h(Colors.amber, 50), borderRadius: BorderRadius.circular(10), border: Border.all(color: F.h(Colors.amber, 300))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.lightbulb, size: 20, color: F.h(Colors.amber, 700)), const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Hinweis: Fehlende Rechtsbehelfsbelehrung', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: F.h(Colors.amber, 800))),
              const SizedBox(height: 4),
              Text('Falls der Bescheid keine korrekte Rechtsbehelfsbelehrung enthält, gilt eine Frist von 1 Jahr statt 1 Monat (§ 66 SGG). Prüfen Sie den Bescheid!', style: TextStyle(fontSize: 11, color: F.h(Colors.amber, 900))),
              const SizedBox(height: 4),
              Text('Erweiterte Frist bis: ${fmt(fristOhneRHB)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: F.h(Colors.amber, 800))),
            ])),
          ]),
        ),
      ],

      const SizedBox(height: 16),

      // Aktion
      if (!hasWiderspruch && !fristAbgelaufen)
        SizedBox(width: double.infinity, child: ElevatedButton.icon(
          icon: const Icon(Icons.gavel),
          label: const Text('Widerspruch einlegen'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: () => _showForm(existing: b),
        ))
      else if (!hasWiderspruch && fristAbgelaufen && !fristJahrAbgelaufen)
        SizedBox(width: double.infinity, child: OutlinedButton.icon(
          icon: const Icon(Icons.gavel, color: Colors.orange),
          label: const Text('Trotzdem Widerspruch einlegen (§ 66 SGG prüfen)'),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.orange, padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: () => _showForm(existing: b),
        )),
    ]));
  }

  // Regelbedarf 2025/2026 nach Regelbedarfsstufen (§ 20 SGB II / § 28 SGB XII)
  static const _regelbedarfMin = 563.0; // Stufe 1 Alleinstehend 2025

  List<Widget> _buildBescheidPruefung(Map<String, dynamic> b, bool fristAbgelaufen) {
    final ok = b['bewilligt'] == true || b['bewilligt'] == 'true' || b['bewilligt'] == 1 || b['bewilligt'] == '1';

    final regelbedarf = double.tryParse(b['regelbedarf']?.toString() ?? '') ?? 0;
    final mehrbedarf = double.tryParse(b['mehrbedarf']?.toString() ?? '') ?? 0;
    final kaltmiete = double.tryParse(b['kaltmiete']?.toString() ?? '') ?? 0;
    final nebenkosten = double.tryParse(b['nebenkosten']?.toString() ?? '') ?? 0;
    final heizkosten = double.tryParse(b['heizkosten']?.toString() ?? '') ?? 0;
    final einkommen = double.tryParse(b['einkommen']?.toString() ?? '') ?? 0;
    final auszahlung = double.tryParse(b['auszahlung']?.toString() ?? '') ?? 0;
    final zeitraumVon = _parseDate(b['zeitraum_von']);
    final zeitraumBis = _parseDate(b['zeitraum_bis']);
    final kdu = kaltmiete + nebenkosten + heizkosten;
    final bedarf = regelbedarf + mehrbedarf + kdu;
    final sollAuszahlung = bedarf - einkommen;

    final checks = <({String title, String detail, IconData icon, MaterialColor color, bool problem})>[];

    if (!ok) {
      // Abgelehnt — immer prüfen
      checks.add((
        title: 'Antrag wurde abgelehnt',
        detail: 'Prüfen Sie den Ablehnungsgrund. Bei unzureichender Begründung ist ein Widerspruch oft erfolgreich.',
        icon: Icons.cancel, color: Colors.red, problem: true,
      ));
    } else {
      // Regelbedarf prüfen
      if (regelbedarf > 0 && regelbedarf < _regelbedarfMin) {
        checks.add((
          title: 'Regelbedarf zu niedrig',
          detail: 'Bewilligt: ${regelbedarf.toStringAsFixed(0)} € — Minimum 2025 (Stufe 1): ${_regelbedarfMin.toStringAsFixed(0)} € (§ 20 SGB II). Differenz: ${(_regelbedarfMin - regelbedarf).toStringAsFixed(2)} €/Monat.',
          icon: Icons.warning, color: Colors.red, problem: true,
        ));
      } else if (regelbedarf >= _regelbedarfMin) {
        checks.add((
          title: 'Regelbedarf korrekt',
          detail: '${regelbedarf.toStringAsFixed(0)} € (min. ${_regelbedarfMin.toStringAsFixed(0)} € Stufe 1)',
          icon: Icons.check_circle, color: Colors.green, problem: false,
        ));
      } else if (regelbedarf == 0 && ok) {
        checks.add((
          title: 'Regelbedarf nicht eingetragen',
          detail: 'Bitte Regelbedarf aus dem Berechnungsbogen übertragen um die Prüfung durchzuführen.',
          icon: Icons.help_outline, color: Colors.grey, problem: false,
        ));
      }

      // KdU prüfen
      if (kdu > 0) {
        if (kaltmiete == 0) {
          checks.add((
            title: 'Kaltmiete fehlt im Bescheid',
            detail: 'KdU bewilligt, aber Kaltmiete ist 0 €. Mietvertrag prüfen und ggf. Widerspruch einlegen.',
            icon: Icons.warning, color: Colors.orange, problem: true,
          ));
        } else if (heizkosten == 0) {
          checks.add((
            title: 'Heizkosten fehlen',
            detail: 'Kaltmiete ${kaltmiete.toStringAsFixed(0)} € bewilligt, aber keine Heizkosten. Ggf. separat beantragt?',
            icon: Icons.warning, color: Colors.orange, problem: true,
          ));
        } else {
          checks.add((
            title: 'KdU vollständig',
            detail: 'Kaltmiete ${kaltmiete.toStringAsFixed(0)} € + NK ${nebenkosten.toStringAsFixed(0)} € + Heizung ${heizkosten.toStringAsFixed(0)} € = ${kdu.toStringAsFixed(0)} €',
            icon: Icons.check_circle, color: Colors.green, problem: false,
          ));
        }
      } else if (ok && regelbedarf > 0) {
        checks.add((
          title: 'Keine KdU bewilligt',
          detail: 'Kosten der Unterkunft (Miete, Nebenkosten, Heizung) wurden nicht bewilligt. Falls Mietwohnung vorhanden, unbedingt prüfen!',
          icon: Icons.warning, color: Colors.red, problem: true,
        ));
      }

      // Auszahlung prüfen
      if (bedarf > 0 && auszahlung > 0) {
        final diff = (sollAuszahlung - auszahlung).abs();
        if (diff > 1.0 && auszahlung < sollAuszahlung) {
          checks.add((
            title: 'Auszahlung weicht ab',
            detail: 'Bedarf ${bedarf.toStringAsFixed(2)} € − Einkommen ${einkommen.toStringAsFixed(2)} € = ${sollAuszahlung.toStringAsFixed(2)} €, aber nur ${auszahlung.toStringAsFixed(2)} € bewilligt. Differenz: ${(sollAuszahlung - auszahlung).toStringAsFixed(2)} €/Monat.',
            icon: Icons.warning, color: Colors.red, problem: true,
          ));
        } else {
          checks.add((
            title: 'Auszahlung stimmt überein',
            detail: '${auszahlung.toStringAsFixed(2)} €/Monat (Bedarf ${bedarf.toStringAsFixed(0)} € − Einkommen ${einkommen.toStringAsFixed(0)} €)',
            icon: Icons.check_circle, color: Colors.green, problem: false,
          ));
        }
      }

      // Bewilligungszeitraum prüfen
      if (zeitraumVon != null && zeitraumBis != null) {
        final monate = (zeitraumBis.year - zeitraumVon.year) * 12 + zeitraumBis.month - zeitraumVon.month;
        if (monate < 12) {
          checks.add((
            title: 'Bewilligungszeitraum nur $monate Monate',
            detail: 'Standard ist 12 Monate (§ 44 SGB XII). Ein kürzerer Zeitraum muss begründet sein.',
            icon: Icons.warning, color: Colors.orange, problem: true,
          ));
        } else {
          checks.add((
            title: 'Bewilligungszeitraum $monate Monate',
            detail: 'Standardzeitraum (12 Monate) eingehalten.',
            icon: Icons.check_circle, color: Colors.green, problem: false,
          ));
        }
      }
    }

    final problems = checks.where((c) => c.problem).length;
    final hasData = checks.any((c) => c.color != Colors.grey);

    final ({String text, MaterialColor color, IconData icon}) empfehlung = !hasData
        ? (text: 'Daten unvollständig — bitte Berechnungsbogen eintragen', color: Colors.grey, icon: Icons.help_outline)
        : problems == 0
            ? (text: 'Bescheid korrekt — Widerspruch nicht empfohlen', color: Colors.green, icon: Icons.verified)
            : problems == 1
                ? (text: '1 Auffälligkeit — Widerspruch prüfen', color: Colors.orange, icon: Icons.warning)
                : (text: '$problems Auffälligkeiten — Widerspruch empfohlen', color: Colors.red, icon: Icons.gavel);

    return [
      Text('Bescheid-Prüfung', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: F.h(Colors.grey, 800))),
      const SizedBox(height: 8),
      // Empfehlung Banner
      Container(
        width: double.infinity, padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: F.h(empfehlung.color, 50),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: F.h(empfehlung.color, 300), width: 1.5),
        ),
        child: Row(children: [
          Icon(empfehlung.icon, size: 24, color: F.h(empfehlung.color, 700)),
          const SizedBox(width: 10),
          Expanded(child: Text(empfehlung.text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: F.h(empfehlung.color, 800)))),
        ]),
      ),
      const SizedBox(height: 8),
      ...checks.map((c) => Container(
        margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: F.flaeche, borderRadius: BorderRadius.circular(8), border: Border.all(color: F.h(c.color, 200))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(c.icon, size: 18, color: F.h(c.color, 600)), const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: F.h(c.color, 800))),
            const SizedBox(height: 2),
            Text(c.detail, style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700))),
          ])),
        ]),
      )),
    ];
  }

  Widget _timelineItem(IconData icon, String title, String date, Color color, bool hasLine, {String? subtitle}) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle, border: Border.all(color: color, width: 2)),
          child: Icon(icon, size: 16, color: color),
        ),
        if (hasLine) Container(width: 2, height: 28, color: F.h(Colors.grey, 300)),
      ]),
      const SizedBox(width: 12),
      Expanded(child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color))),
            Text(date, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: F.h(Colors.grey, 700))),
          ]),
          if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle, style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600), fontStyle: FontStyle.italic))),
        ]),
      )),
    ]);
  }

  Widget _lawRow(String paragraph, String text) {
    return Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: F.h(Colors.indigo, 50), borderRadius: BorderRadius.circular(4)),
        child: Text(paragraph, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: F.h(Colors.indigo, 700))),
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700)))),
    ]));
  }
}
// ═══════════════════════════════════════════════════════════════════════════
// ÄMTER-KATALOG (Tabelle sozialamt_db)
// Auswahl mit Suche + Pflege. Der Katalog lag früher als `static const` im
// Code; ein neues Amt kostete damit ein Release beider Apps.
// ═══════════════════════════════════════════════════════════════════════════

class _AmtAuswahlDialog extends StatefulWidget {
  final ApiService apiService;
  const _AmtAuswahlDialog({required this.apiService});
  @override
  State<_AmtAuswahlDialog> createState() => _AmtAuswahlDialogState();
}

class _AmtAuswahlDialogState extends State<_AmtAuswahlDialog> {
  final _suche = TextEditingController();
  List<Map<String, dynamic>> _treffer = [];
  bool _laedt = true;
  String? _fehler;

  @override
  void initState() { super.initState(); _laden(); }
  @override
  void dispose() { _suche.dispose(); super.dispose(); }

  Future<void> _laden() async {
    setState(() { _laedt = true; _fehler = null; });
    final r = await widget.apiService.searchSozialamtDatenbank(_suche.text.trim());
    if (!mounted) return;
    setState(() {
      _laedt = false;
      if (r['success'] == true && r['results'] is List) {
        _treffer = (r['results'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } else {
        _fehler = (r['message'] ?? 'Katalog nicht erreichbar').toString();
      }
    });
  }

  Future<void> _bearbeiten([Map<String, dynamic>? amt]) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _AmtBearbeitenDialog(apiService: widget.apiService, amt: amt),
    );
    if (ok == true) _laden();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Row(children: [
        Icon(Icons.search, color: F.h(Colors.indigo, 700)),
        const SizedBox(width: 8),
        const Expanded(child: Text('Sozialamt auswählen')),
        IconButton(
          tooltip: 'Neues Amt anlegen',
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => _bearbeiten(),
        ),
      ]),
      content: SizedBox(
        width: 520, height: 460,
        child: Column(children: [
          TextField(
            controller: _suche,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Name, PLZ, Ort oder Straße',
              prefixIcon: const Icon(Icons.search, size: 18),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _laden(),
          ),
          const SizedBox(height: 8),
          Expanded(child: _laedt
              ? const Center(child: CircularProgressIndicator())
              : _fehler != null
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.cloud_off, size: 40, color: F.h(Colors.orange, 300)),
                      const SizedBox(height: 8),
                      Text(_fehler!, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700))),
                      const SizedBox(height: 8),
                      OutlinedButton(onPressed: _laden, child: const Text('Nochmal')),
                    ]))
                  : _treffer.isEmpty
                      ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.account_balance_outlined, size: 40, color: F.h(Colors.grey, 300)),
                          const SizedBox(height: 8),
                          Text('Kein Amt gefunden', style: TextStyle(color: F.h(Colors.grey, 600))),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: () => _bearbeiten({'name': _suche.text.trim()}),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Dieses Amt anlegen'),
                          ),
                        ]))
                      : ListView.builder(
                          itemCount: _treffer.length,
                          itemBuilder: (_, i) => _zeile(_treffer[i]),
                        )),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
      ],
    );
  }

  Widget _zeile(Map<String, dynamic> a) {
    final fax = (a['fax']?.toString() ?? '').trim();
    final mail = (a['email']?.toString() ?? '').trim();
    return InkWell(
      onTap: () => Navigator.pop(context, a),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: F.flaeche, borderRadius: BorderRadius.circular(10), border: Border.all(color: F.h(Colors.grey, 300))),
        child: Row(children: [
          Icon(Icons.account_balance, size: 20, color: F.h(Colors.indigo, 600)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a['name']?.toString() ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: F.h(Colors.indigo, 900))),
            Text('${a['adresse'] ?? ''}, ${a['plz_ort'] ?? ''}', style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
            if ((a['zustaendigkeit']?.toString() ?? '').isNotEmpty)
              Text(a['zustaendigkeit'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: F.h(Colors.indigo, 400), fontStyle: FontStyle.italic)),
            const SizedBox(height: 4),
            // Fax und E-Mail als Marke: beim Auswählen soll man sofort sehen,
            // ob man dem Amt überhaupt etwas schicken kann.
            Wrap(spacing: 6, runSpacing: 4, children: [
              _marke(Icons.print, fax.isEmpty ? 'kein Fax' : fax, fax.isEmpty),
              _marke(Icons.mail_outline, mail.isEmpty ? 'keine E-Mail' : mail, mail.isEmpty),
            ]),
          ])),
          IconButton(
            tooltip: 'Bearbeiten',
            icon: Icon(Icons.edit, size: 18, color: F.h(Colors.grey, 600)),
            onPressed: () => _bearbeiten(a),
          ),
        ]),
      ),
    );
  }

  Widget _marke(IconData icon, String text, bool fehlt) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: fehlt ? F.h(Colors.orange, 50) : F.h(Colors.green, 50),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: fehlt ? F.h(Colors.orange, 200) : F.h(Colors.green, 200)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: fehlt ? F.h(Colors.orange, 800) : F.h(Colors.green, 800)),
          const SizedBox(width: 3),
          Text(text, style: TextStyle(fontSize: 10, color: fehlt ? F.h(Colors.orange, 800) : F.h(Colors.green, 800))),
        ]),
      );
}

class _AmtBearbeitenDialog extends StatefulWidget {
  final ApiService apiService;
  final Map<String, dynamic>? amt;
  const _AmtBearbeitenDialog({required this.apiService, this.amt});
  @override
  State<_AmtBearbeitenDialog> createState() => _AmtBearbeitenDialogState();
}

class _AmtBearbeitenDialogState extends State<_AmtBearbeitenDialog> {
  static const _kategorien = ['sozialamt', 'sozialraum', 'landratsamt', 'jobcenter', 'sonstige'];
  final _c = <String, TextEditingController>{};
  String _kategorie = 'sozialamt';
  bool _speichert = false;
  String? _fehler;

  int get _id => int.tryParse(widget.amt?['id']?.toString() ?? '') ?? 0;

  @override
  void initState() {
    super.initState();
    for (final f in ['name', 'adresse', 'plz_ort', 'bundesland', 'telefon', 'fax', 'email', 'website', 'oeffnungszeiten', 'zustaendigkeit', 'quelle']) {
      _c[f] = TextEditingController(text: widget.amt?[f]?.toString() ?? '');
    }
    final k = widget.amt?['kategorie']?.toString() ?? '';
    if (_kategorien.contains(k)) _kategorie = k;
  }

  @override
  void dispose() { for (final c in _c.values) { c.dispose(); } super.dispose(); }

  Future<void> _speichern() async {
    if (_c['name']!.text.trim().isEmpty) { setState(() => _fehler = 'Name ist Pflicht'); return; }
    setState(() { _speichert = true; _fehler = null; });
    final daten = <String, dynamic>{'kategorie': _kategorie};
    for (final e in _c.entries) { daten[e.key] = e.value.text.trim(); }
    final r = _id > 0
        ? await widget.apiService.updateSozialamtDatenbank(_id, daten)
        : await widget.apiService.addSozialamtDatenbank(daten);
    if (!mounted) return;
    if (r['success'] == true) {
      Navigator.pop(context, true);
    } else {
      // Der Grund muss auf den Schirm. Ein stilles Zurücksetzen sieht aus wie
      // „gespeichert" und die Nummer fehlt später beim Faxen.
      setState(() { _speichert = false; _fehler = (r['message'] ?? 'Speichern fehlgeschlagen').toString(); });
    }
  }

  Future<void> _stilllegen() async {
    final sicher = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Amt stilllegen?'),
      content: const Text('Das Amt verschwindet aus der Auswahl. Gelöscht wird nichts — '
          'bereits erfasste Anträge und Korrespondenz bleiben lesbar.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Stilllegen', style: TextStyle(color: Colors.red))),
      ],
    ));
    if (sicher != true) return;
    final r = await widget.apiService.deleteSozialamtDatenbank(_id);
    if (!mounted) return;
    if (r['success'] == true) {
      Navigator.pop(context, true);
    } else {
      setState(() => _fehler = (r['message'] ?? 'Nicht möglich').toString());
    }
  }

  Widget _feld(String schluessel, String label, {IconData? icon, int zeilen = 1, TextInputType? tastatur, String? hinweis}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: _c[schluessel],
          maxLines: zeilen,
          keyboardType: tastatur,
          decoration: InputDecoration(
            isDense: true,
            labelText: label,
            helperText: hinweis,
            helperMaxLines: 2,
            prefixIcon: icon == null ? null : Icon(icon, size: 18),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(_id > 0 ? 'Amt bearbeiten' : 'Neues Amt'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _feld('name', 'Name des Amts *', icon: Icons.account_balance),
            DropdownButtonFormField<String>(
              initialValue: _kategorie,
              decoration: InputDecoration(isDense: true, labelText: 'Art', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
              items: _kategorien.map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
              onChanged: (v) => setState(() => _kategorie = v ?? 'sozialamt'),
            ),
            const SizedBox(height: 10),
            _feld('adresse', 'Straße und Hausnummer', icon: Icons.location_on),
            _feld('plz_ort', 'PLZ und Ort', icon: Icons.markunread_mailbox),
            _feld('bundesland', 'Bundesland', icon: Icons.map_outlined),
            _feld('telefon', 'Telefon', icon: Icons.phone, tastatur: TextInputType.phone),
            _feld('fax', 'Fax', icon: Icons.print, tastatur: TextInputType.phone,
                hinweis: 'Nur eintragen, was das Amt selbst veröffentlicht — eine geratene Nummer landet bei Fremden.'),
            _feld('email', 'E-Mail', icon: Icons.mail_outline, tastatur: TextInputType.emailAddress),
            _feld('website', 'Website', icon: Icons.language, tastatur: TextInputType.url),
            _feld('oeffnungszeiten', 'Öffnungszeiten', icon: Icons.access_time, zeilen: 2),
            _feld('zustaendigkeit', 'Zuständigkeit', icon: Icons.info_outline, zeilen: 3),
            _feld('quelle', 'Quelle (Link)', icon: Icons.link,
                hinweis: 'Woher stammen die Angaben? Ohne Quelle kann später niemand prüfen, ob sie noch stimmen.'),
            if (_fehler != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_fehler!, style: const TextStyle(fontSize: 12, color: Colors.red)),
              ),
          ]),
        ),
      ),
      actions: [
        if (_id > 0)
          TextButton(onPressed: _speichert ? null : _stilllegen, child: const Text('Stilllegen', style: TextStyle(color: Colors.red))),
        TextButton(onPressed: _speichert ? null : () => Navigator.pop(context, false), child: const Text('Abbrechen')),
        ElevatedButton(
          onPressed: _speichert ? null : _speichern,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
          child: _speichert
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Speichern'),
        ),
      ],
    );
  }
}
