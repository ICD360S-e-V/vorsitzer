import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'cloud_file_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';
import 'file_viewer_dialog.dart';

/// Familienkasse: 4 Tabs
///  1. Zuständige Familienkasse — Auswahl aus geteilter Datenbank
///     (familienkassen_datenbank: BA-Regional / öffentl. Dienst / Ausland).
///  2. Stammdaten — Kindergeld-Nummer, Sachbearbeiter, Kinderzuschlag, Notizen.
///  3. Anträge — Liste mit "+" Button; pro Antrag ein Detail-Modal mit
///     Details / Unterlagen / Korrespondenz / Termine / Bewilligung
///     (eigene DB-Tabellen, verschlüsselt). Jeder Antrag hat eine Art
///     (Kindergeld, Kinderzuschlag, …).
///  4. Rechner — Kinder-Anspruchsprüfung + Kindergeld/Freibetrag. Die Beträge
///     (Kindergeld/Monat, Kinderzuschlag-Max, Kinderfreibetrag) werden LIVE aus
///     `kindergeld_saetze` vom Server geladen (getKindergeldSaetze), damit die
///     jährliche gesetzliche Anpassung ohne App-Update sofort greift.
class BehordeFamilienkasseContent extends StatefulWidget {
  final ApiService apiService;
  final int userId;

  const BehordeFamilienkasseContent({
    super.key,
    required this.apiService,
    required this.userId,
  });

  static const type = 'familienkasse';

  @override
  State<BehordeFamilienkasseContent> createState() => _BehordeFamilienkasseContentState();
}

/// Antragsarten der Familienkasse (recherchiert, DA-KG Vordruckverzeichnis / BKGG / EStG).
const List<String> _fkArten = [
  'Kindergeld (KG1)',
  'Anlage Kind (weiteres Kind)',
  'Kinderzuschlag (KiZ)',
  'Kindergeld volljähriges Kind (Schule/Ausbildung/Studium)',
  'Kindergeld bei Behinderung',
  'Kindergeld Vollwaisen (KG1a)',
  'Auslands-/EU-Kindergeld (Anlage Ausland/EU)',
  'Abzweigung / Auszahlung an das Kind',
  'Weiterleitungserklärung',
  'Veränderungsmitteilung',
  'Sonstiges',
];

IconData _fkArtIcon(String? art) {
  switch (art) {
    case 'Kindergeld (KG1)': return Icons.child_care;
    case 'Anlage Kind (weiteres Kind)': return Icons.child_friendly;
    case 'Kinderzuschlag (KiZ)': return Icons.euro;
    case 'Kindergeld volljähriges Kind (Schule/Ausbildung/Studium)': return Icons.school;
    case 'Kindergeld bei Behinderung': return Icons.accessible;
    case 'Kindergeld Vollwaisen (KG1a)': return Icons.family_restroom;
    case 'Auslands-/EU-Kindergeld (Anlage Ausland/EU)': return Icons.public;
    case 'Abzweigung / Auszahlung an das Kind': return Icons.account_balance_wallet;
    case 'Weiterleitungserklärung': return Icons.forward_to_inbox;
    case 'Veränderungsmitteilung': return Icons.edit_note;
    default: return Icons.description;
  }
}

/// Einreichungswege für Anträge (online / persönlich / fax / email / post).
const Map<String, (String, IconData)> _fkMethoden = {
  'online': ('Online (BA-Portal)', Icons.language),
  'persoenlich': ('Persönlich', Icons.person),
  'fax': ('Fax', Icons.fax),
  'email': ('Per E-Mail', Icons.email),
  'post': ('Per Post', Icons.local_post_office),
};

String _fkMethodeLabel(String? m) => _fkMethoden[m ?? '']?.$1 ?? (m ?? '');

const Map<String, (String, MaterialColor)> _fkStatus = {
  'geplant': ('Geplant', Colors.blueGrey),
  'eingereicht': ('Eingereicht', Colors.orange),
  'in_bearbeitung': ('In Bearbeitung', Colors.blue),
  'unterlagen_fehlen': ('Unterlagen nachgefordert', Colors.amber),
  'bewilligt': ('Bewilligt', Colors.green),
  'abgelehnt': ('Abgelehnt', Colors.red),
  'widerspruch': ('Widerspruch', Colors.purple),
};

String _fkStatusLabel(String? s) => _fkStatus[s ?? '']?.$1 ?? ((s ?? '').replaceAll('_', ' '));
MaterialColor _fkStatusColor(String? s) => _fkStatus[s ?? '']?.$2 ?? Colors.grey;

class _BehordeFamilienkasseContentState extends State<BehordeFamilienkasseContent> {
  // Per-user Stammdaten, bereich → feld → wert
  Map<String, Map<String, dynamic>> _dbData = {};
  bool _dbLoaded = false;

  List<Map<String, dynamic>> _antraege = [];
  bool _antraegeLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Map<String, dynamic> _db(String bereich) {
    _dbData[bereich] ??= {};
    return _dbData[bereich]!;
  }

  Future<void> _loadData() async {
    try {
      final r = await widget.apiService.getFamilienkasseData(widget.userId);
      if (!mounted) return;
      if (r['success'] == true && r['data'] is Map) {
        _dbData = {};
        (r['data'] as Map).forEach((k, v) { if (v is Map) _dbData[k.toString()] = Map<String, dynamic>.from(v); });
      }
    } catch (e) {
      debugPrint('[Familienkasse] Load error: $e');
    }
    if (!mounted) return;
    setState(() => _dbLoaded = true);
  }

  Future<void> _saveKasse() async {
    await widget.apiService.saveFamilienkasseData(widget.userId, {'kasse': _dbData['kasse'] ?? {}});
  }

  @override
  Widget build(BuildContext context) {
    if (!_dbLoaded) return const Center(child: CircularProgressIndicator());
    final kasse = _dbData['kasse'] ?? {};
    final hatKasse = (kasse['name']?.toString() ?? '').isNotEmpty;
    final stamm = _dbData['stammdaten'] ?? {};
    final hatStamm = (stamm['kindergeld_nr']?.toString() ?? '').isNotEmpty;
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            labelColor: Colors.orange.shade800,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: Colors.orange.shade700,
            tabs: [
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, size: 8, color: hatKasse ? Colors.green : Colors.red),
                const SizedBox(width: 4), const Icon(Icons.account_balance, size: 16),
                const SizedBox(width: 4), const Flexible(child: Text('Zuständige Familienkasse', overflow: TextOverflow.ellipsis)),
              ])),
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, size: 8, color: hatStamm ? Colors.green : Colors.red),
                const SizedBox(width: 4), const Icon(Icons.badge, size: 16),
                const SizedBox(width: 4), const Text('Stammdaten'),
              ])),
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, size: 8, color: _antraege.isNotEmpty ? Colors.green : Colors.red),
                const SizedBox(width: 4), const Icon(Icons.description, size: 16),
                const SizedBox(width: 4), const Text('Anträge'),
              ])),
              const Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.calculate, size: 16),
                SizedBox(width: 4), Text('Rechner'),
              ])),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildKasseTab(kasse),
                _buildStammdatenTab(stamm),
                _buildAntragTab(),
                _FkRechnerTab(apiService: widget.apiService, userId: widget.userId, db: _db('rechner'), onPersist: _saveRechner),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveRechner(Map<String, dynamic> rechner) async {
    _dbData['rechner'] = rechner;
    await widget.apiService.saveFamilienkasseData(widget.userId, {'rechner': rechner});
  }

  // ============ TAB 1: ZUSTÄNDIGE FAMILIENKASSE ============

  Widget _buildKasseTab(Map<String, dynamic> kasse) {
    final hatKasse = (kasse['name']?.toString() ?? '').isNotEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.account_balance, size: 20, color: Colors.orange.shade800),
          const SizedBox(width: 8),
          Text('Zuständige Familienkasse', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
          const Spacer(),
          TextButton.icon(
            onPressed: _pickFamilienkasse,
            icon: const Icon(Icons.search, size: 18),
            label: Text(hatKasse ? 'Ändern' : 'Auswählen', style: const TextStyle(fontSize: 12)),
          ),
        ]),
        const SizedBox(height: 8),
        if (!hatKasse)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
            child: Column(children: [
              Icon(Icons.account_balance, size: 40, color: Colors.grey.shade400),
              const SizedBox(height: 8),
              Text('Keine Familienkasse ausgewählt', style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _pickFamilienkasse,
                icon: const Icon(Icons.search, size: 16),
                label: const Text('Aus Datenbank wählen'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white),
              ),
            ]),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange.shade200)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(kasse['name']?.toString() ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
              if ((kasse['strasse']?.toString() ?? '').isNotEmpty) ...[const SizedBox(height: 4), _amtRow(Icons.location_on, '${kasse['strasse']}, ${kasse['plz_ort'] ?? ''}')],
              if ((kasse['postanschrift']?.toString() ?? '').isNotEmpty) _amtRow(Icons.markunread_mailbox, 'Post: ${kasse['postanschrift']}'),
              if ((kasse['telefon']?.toString() ?? '').isNotEmpty) _amtRow(Icons.phone, kasse['telefon'].toString()),
              if ((kasse['email']?.toString() ?? '').isNotEmpty) _amtRow(Icons.email, kasse['email'].toString()),
              if ((kasse['website']?.toString() ?? '').isNotEmpty) _amtRow(Icons.language, kasse['website'].toString()),
              if ((kasse['oeffnungszeiten']?.toString() ?? '').isNotEmpty) _amtRow(Icons.schedule, kasse['oeffnungszeiten'].toString()),
              if ((kasse['zustaendig_fuer']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Zuständig für:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange.shade800)),
                const SizedBox(height: 2),
                Text(kasse['zustaendig_fuer'].toString(), style: TextStyle(fontSize: 11, color: Colors.orange.shade700)),
              ],
            ]),
          ),
        const SizedBox(height: 12),
        Row(children: [
          Icon(Icons.info_outline, size: 14, color: Colors.grey.shade500),
          const SizedBox(width: 6),
          Expanded(child: Text('Kindergeld-Nummer & Sachbearbeiter im Tab „Stammdaten"; Aktenzeichen, Korrespondenz & Unterlagen pro Antrag im Tab „Anträge".', style: TextStyle(fontSize: 11, color: Colors.grey.shade500))),
        ]),
      ]),
    );
  }

  Widget _amtRow(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 14, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        ]),
      );

  Future<void> _pickFamilienkasse() async {
    final searchC = TextEditingController();
    List<Map<String, dynamic>> results = [];
    bool loading = true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) {
        Future<void> doSearch() async {
          setD(() => loading = true);
          final r = await widget.apiService.searchFamilienkassen(search: searchC.text.trim());
          final list = (r['familienkassen'] as List?) ?? (r['data'] as List?) ?? [];
          if (!ctx2.mounted) return;
          setD(() {
            results = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
            loading = false;
          });
        }

        if (loading && results.isEmpty) {
          Future.microtask(doSearch);
        }

        return AlertDialog(
          title: const Text('Familienkasse auswählen', style: TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 480,
            height: 460,
            child: Column(children: [
              TextField(
                controller: searchC,
                autofocus: true,
                onSubmitted: (_) => doSearch(),
                decoration: InputDecoration(
                  hintText: 'Suche (Name, Bundesland, PLZ)...',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: doSearch),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : results.isEmpty
                        ? const Center(child: Text('Keine Familienkassen gefunden'))
                        : ListView.builder(
                            itemCount: results.length,
                            itemBuilder: (_, i) {
                              final a = results[i];
                              return Card(
                                child: ListTile(
                                  leading: Icon(Icons.account_balance, color: Colors.orange.shade700),
                                  title: Text(a['name']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                  subtitle: Text('${a['plz_ort'] ?? ''}${(a['zustaendig_fuer']?.toString() ?? '').isNotEmpty ? '\n${a['zustaendig_fuer']}' : ''}', style: const TextStyle(fontSize: 11), maxLines: 3, overflow: TextOverflow.ellipsis),
                                  isThreeLine: true,
                                  onTap: () {
                                    final kasse = _db('kasse');
                                    kasse['db_id'] = a['id']?.toString() ?? '';
                                    kasse['name'] = a['name']?.toString() ?? '';
                                    kasse['kurzname'] = a['kurzname']?.toString() ?? '';
                                    kasse['strasse'] = a['strasse']?.toString() ?? '';
                                    kasse['plz_ort'] = a['plz_ort']?.toString() ?? '';
                                    kasse['postanschrift'] = a['postanschrift']?.toString() ?? '';
                                    kasse['telefon'] = a['telefon']?.toString() ?? '';
                                    kasse['email'] = a['email']?.toString() ?? '';
                                    kasse['website'] = a['website']?.toString() ?? '';
                                    kasse['oeffnungszeiten'] = a['oeffnungszeiten']?.toString() ?? '';
                                    kasse['zustaendig_fuer'] = a['zustaendig_fuer']?.toString() ?? '';
                                    _saveKasse();
                                    setState(() {});
                                    Navigator.pop(ctx);
                                  },
                                ),
                              );
                            },
                          ),
              ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen'))],
        );
      }),
    );
  }

  // ============ TAB 2: STAMMDATEN ============

  Widget _buildStammdatenTab(Map<String, dynamic> stamm) {
    return _FkStammdatenTab(
      initial: stamm,
      onSave: (data) async {
        _dbData['stammdaten'] = data;
        final r = await widget.apiService.saveFamilienkasseData(widget.userId, {'stammdaten': data});
        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(r['success'] == true ? 'Stammdaten gespeichert' : 'Fehler beim Speichern'),
            backgroundColor: r['success'] == true ? Colors.green.shade700 : Colors.red,
          ));
        }
      },
    );
  }

  // ============ TAB 3: ANTRÄGE ============

  Future<void> _loadAntraege() async {
    final r = await widget.apiService.listFamilienkasseAntraege(widget.userId);
    if (!mounted) return;
    setState(() {
      if (r['success'] == true && r['data'] is List) {
        _antraege = (r['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      _antraegeLoaded = true;
    });
  }

  Widget _buildAntragTab() {
    if (!_antraegeLoaded) { _loadAntraege(); return const Center(child: CircularProgressIndicator()); }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          Icon(Icons.description, size: 20, color: Colors.orange.shade800),
          const SizedBox(width: 8),
          Text('Anträge (${_antraege.length})', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _showNewAntragDialog,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Neuer Antrag'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white),
          ),
        ]),
      ),
      Expanded(
        child: _antraege.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.description_outlined, size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 8),
                Text('Keine Anträge vorhanden', style: TextStyle(color: Colors.grey.shade500)),
              ]))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _antraege.length,
                itemBuilder: (_, i) {
                  final a = _antraege[i];
                  final status = a['status']?.toString() ?? '';
                  final statusColor = _fkStatusColor(status);
                  final art = a['art']?.toString() ?? '';
                  final az = a['aktenzeichen']?.toString() ?? '';
                  return Card(
                    child: ListTile(
                      leading: Icon(_fkArtIcon(art), color: statusColor, size: 28),
                      title: Text(art.isEmpty ? '(ohne Art)' : art, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2, bottom: 4),
                          child: Text('${a['datum'] ?? ''} — ${_fkMethodeLabel(a['methode']?.toString())}${az.isNotEmpty ? '  •  Az: $az' : ''}', style: const TextStyle(fontSize: 11)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: statusColor.shade100, borderRadius: BorderRadius.circular(8)),
                          child: Text(_fkStatusLabel(status).toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor.shade800)),
                        ),
                      ]),
                      onTap: () {
                        final aid = int.tryParse(a['id']?.toString() ?? '');
                        if (aid != null) _showAntragDetailDialog(aid, a);
                      },
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                          onPressed: () async {
                            final aid = int.tryParse(a['id']?.toString() ?? '');
                            if (aid == null) return;
                            final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
                              title: const Text('Antrag löschen?'),
                              content: const Text('Der Antrag und alle Unterlagen/Korrespondenz werden gelöscht.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
                                FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(c, true), child: const Text('Löschen')),
                              ],
                            ));
                            if (ok == true) { await widget.apiService.deleteFamilienkasseAntrag(aid); _loadAntraege(); }
                          },
                        ),
                        Icon(Icons.chevron_right, color: Colors.grey.shade400),
                      ]),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  void _showNewAntragDialog() {
    final datumC = TextEditingController();
    final aktenzeichenC = TextEditingController();
    String? art;
    String methode = '';
    String status = 'eingereicht';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Text('Neuer Antrag', style: TextStyle(fontSize: 16)),
      content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Art des Antrags *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: art,
          isExpanded: true,
          decoration: InputDecoration(hintText: 'Art wählen', prefixIcon: const Icon(Icons.category, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          items: _fkArten.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) => setD(() => art = v),
        ),
        const SizedBox(height: 12),
        Text('Datum der Antragstellung *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        TextField(
          controller: datumC,
          readOnly: true,
          decoration: InputDecoration(
            hintText: 'Datum wählen',
            prefixIcon: const Icon(Icons.calendar_today, size: 18),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onTap: () async {
            final p = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
            if (p != null) setD(() => datumC.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}');
          },
        ),
        const SizedBox(height: 12),
        TextField(controller: aktenzeichenC, decoration: InputDecoration(labelText: 'Kindergeld-Nr. / Aktenzeichen', prefixIcon: const Icon(Icons.folder, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 12),
        Text('Einreichungsweg *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: _fkMethoden.entries.map((m) {
          final sel = methode == m.key;
          return ChoiceChip(
            label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(m.value.$2, size: 14, color: sel ? Colors.white : Colors.grey.shade700), const SizedBox(width: 4), Text(m.value.$1, style: TextStyle(fontSize: 11, color: sel ? Colors.white : Colors.black87))]),
            selected: sel, selectedColor: Colors.orange.shade700,
            onSelected: (_) => setD(() => methode = m.key),
          );
        }).toList()),
        const SizedBox(height: 12),
        Text('Status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: status,
          isExpanded: true,
          decoration: InputDecoration(isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
          items: _fkStatus.entries.map((s) => DropdownMenuItem(value: s.key, child: Text(s.value.$1, style: const TextStyle(fontSize: 13)))).toList(),
          onChanged: (v) => setD(() => status = v ?? 'eingereicht'),
        ),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700),
          onPressed: () async {
            if (art == null || datumC.text.isEmpty || methode.isEmpty) return;
            await widget.apiService.saveFamilienkasseAntrag(widget.userId, {
              'art': art,
              'datum': datumC.text,
              'aktenzeichen': aktenzeichenC.text.trim(),
              'methode': methode,
              'status': status,
            });
            if (ctx.mounted) Navigator.pop(ctx);
            _loadAntraege();
          },
          child: const Text('Antrag stellen'),
        ),
      ],
    )));
  }

  void _showAntragDetailDialog(int antragId, Map<String, dynamic> antrag) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.85,
          height: MediaQuery.of(context).size.height * 0.82,
          child: _FkAntragDetailView(
            apiService: widget.apiService,
            userId: widget.userId,
            antragId: antragId,
            antrag: antrag,
            onChanged: _loadAntraege,
          ),
        ),
      ),
    );
  }
}

// ============ TAB 2 STATE: STAMMDATEN ============

class _FkStammdatenTab extends StatefulWidget {
  final Map<String, dynamic> initial;
  final Future<void> Function(Map<String, dynamic>) onSave;
  const _FkStammdatenTab({required this.initial, required this.onSave});
  @override
  State<_FkStammdatenTab> createState() => _FkStammdatenTabState();
}

class _FkStammdatenTabState extends State<_FkStammdatenTab> {
  late TextEditingController _kindergeldNrC, _sachbearbeiterC, _kinderzuschlagC, _notizenC;
  late bool _hatKinderzuschlag;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    _kindergeldNrC = TextEditingController(text: s['kindergeld_nr']?.toString() ?? '');
    _sachbearbeiterC = TextEditingController(text: s['sachbearbeiter']?.toString() ?? '');
    _kinderzuschlagC = TextEditingController(text: s['kinderzuschlag']?.toString() ?? '');
    _notizenC = TextEditingController(text: s['notizen']?.toString() ?? '');
    _hatKinderzuschlag = (s['hat_kinderzuschlag']?.toString() ?? '') == 'true' || s['hat_kinderzuschlag'] == true;
  }

  @override
  void dispose() {
    _kindergeldNrC.dispose();
    _sachbearbeiterC.dispose();
    _kinderzuschlagC.dispose();
    _notizenC.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.onSave({
      'kindergeld_nr': _kindergeldNrC.text.trim(),
      'sachbearbeiter': _sachbearbeiterC.text.trim(),
      'hat_kinderzuschlag': _hatKinderzuschlag,
      'kinderzuschlag': _kinderzuschlagC.text.trim(),
      'notizen': _notizenC.text.trim(),
    });
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.badge, size: 20, color: Colors.orange.shade800),
        const SizedBox(width: 8),
        Text('Stammdaten', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
      ]),
      const SizedBox(height: 12),
      Text('Kindergeld-Nummer', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
      const SizedBox(height: 4),
      TextField(
        controller: _kindergeldNrC,
        decoration: InputDecoration(
          hintText: 'z.B. FK 123 456 789 0',
          prefixIcon: const Icon(Icons.confirmation_number, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          isDense: true,
        ),
      ),
      const SizedBox(height: 16),
      Text('Sachbearbeiter/in', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
      const SizedBox(height: 4),
      TextField(
        controller: _sachbearbeiterC,
        decoration: InputDecoration(
          hintText: 'Name des Sachbearbeiters',
          prefixIcon: const Icon(Icons.person, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          isDense: true,
        ),
      ),
      const SizedBox(height: 16),
      Row(children: [
        Text('Kinderzuschlag (KiZ) bezogen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(width: 8),
        Switch(
          value: _hatKinderzuschlag,
          activeTrackColor: Colors.green.shade300,
          activeThumbColor: Colors.green,
          onChanged: (val) => setState(() => _hatKinderzuschlag = val),
        ),
        Text(_hatKinderzuschlag ? 'Ja' : 'Nein', style: TextStyle(color: _hatKinderzuschlag ? Colors.green : Colors.grey)),
      ]),
      if (_hatKinderzuschlag) ...[
        const SizedBox(height: 8),
        TextField(
          controller: _kinderzuschlagC,
          decoration: InputDecoration(
            hintText: 'Betrag / Details',
            prefixIcon: const Icon(Icons.euro, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            isDense: true,
          ),
        ),
      ],
      const SizedBox(height: 16),
      Text('Notizen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
      const SizedBox(height: 4),
      TextField(
        controller: _notizenC,
        maxLines: 3,
        decoration: InputDecoration(
          hintText: 'Weitere Informationen...',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          isDense: true,
        ),
      ),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save, size: 18),
          label: const Text('Speichern'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white),
        ),
      ),
    ]));
  }
}

// ============ ANTRAG DETAIL: Details / Unterlagen / Korrespondenz / Termine / Bewilligung ============

class _FkAntragDetailView extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int antragId;
  final Map<String, dynamic> antrag;
  final VoidCallback onChanged;
  const _FkAntragDetailView({required this.apiService, required this.userId, required this.antragId, required this.antrag, required this.onChanged});

  @override
  State<_FkAntragDetailView> createState() => _FkAntragDetailViewState();
}

class _FkAntragDetailViewState extends State<_FkAntragDetailView> {
  List<Map<String, dynamic>> _docs = [];
  List<Map<String, dynamic>> _korr = [];
  List<Map<String, dynamic>> _termine = [];
  Map<String, dynamic>? _bewilligung;
  bool _loaded = false;
  late Map<String, dynamic> _antrag;

  @override
  void initState() {
    super.initState();
    _antrag = Map<String, dynamic>.from(widget.antrag);
    _load();
  }

  Future<void> _load() async {
    final dR = await widget.apiService.listFkAntragDocs(widget.antragId);
    final kR = await widget.apiService.listFkAntragKorr(widget.antragId);
    final tR = await widget.apiService.listFkAntragTermine(widget.antragId);
    final bR = await widget.apiService.getFkBewilligung(widget.antragId);
    if (!mounted) return;
    setState(() {
      if (dR['success'] == true && dR['data'] is List) _docs = (dR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (kR['success'] == true && kR['data'] is List) _korr = (kR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (tR['success'] == true && tR['data'] is List) _termine = (tR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _bewilligung = (bR['success'] == true && bR['data'] is Map) ? Map<String, dynamic>.from(bR['data'] as Map) : null;
      _loaded = true;
    });
  }

  Future<void> _persistAntrag() async {
    await widget.apiService.saveFamilienkasseAntrag(widget.userId, {
      'id': widget.antragId,
      'art': _antrag['art'],
      'datum': _antrag['datum'],
      'methode': _antrag['methode'],
      'status': _antrag['status'],
      'aktenzeichen': _antrag['aktenzeichen'],
      'notiz': _antrag['notiz'],
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final status = _antrag['status']?.toString() ?? 'eingereicht';
    final isOk = status == 'bewilligt';
    final art = _antrag['art']?.toString() ?? '';
    final hatBew = _bewilligung != null;
    return DefaultTabController(length: 5, child: Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: isOk ? Colors.green.shade700 : Colors.orange.shade800, borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
        child: Row(children: [
          Icon(_fkArtIcon(art), color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(art.isEmpty ? 'Antrag' : art, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            Text('${_antrag['datum'] ?? ''} • ${_fkMethodeLabel(_antrag['methode']?.toString())} • ${_fkStatusLabel(status).toUpperCase()}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ])),
          IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
        ]),
      ),
      TabBar(labelColor: Colors.orange.shade800, unselectedLabelColor: Colors.grey.shade600, indicatorColor: Colors.orange.shade700, isScrollable: true, tabs: [
        const Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Details'),
        Tab(icon: const Icon(Icons.folder, size: 18), text: 'Unterlagen (${_docs.length})'),
        Tab(icon: const Icon(Icons.mail, size: 18), text: 'Korrespondenz (${_korr.length})'),
        Tab(icon: const Icon(Icons.event, size: 18), text: 'Termine (${_termine.length})'),
        Tab(icon: Icon(hatBew ? Icons.verified : Icons.verified_outlined, size: 18), text: 'Bewilligung'),
      ]),
      Expanded(child: !_loaded ? const Center(child: CircularProgressIndicator()) : TabBarView(children: [
        _buildDetails(),
        _buildDokumente(),
        _buildKorrespondenz(),
        _buildTermine(),
        _buildBewilligung(),
      ])),
    ]));
  }

  // ---- Details ----
  Widget _buildDetails() {
    final a = _antrag;
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Antrag', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
      const SizedBox(height: 8),
      Text('Art', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
      const SizedBox(height: 4),
      DropdownButtonFormField<String>(
        initialValue: _fkArten.contains(a['art']) ? a['art'].toString() : null,
        isExpanded: true,
        decoration: InputDecoration(isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
        items: _fkArten.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))).toList(),
        onChanged: (v) async {
          if (v == null) return;
          setState(() => _antrag['art'] = v);
          await _persistAntrag();
        },
      ),
      const SizedBox(height: 12),
      _dRow(Icons.calendar_today, 'Antragsdatum', a['datum']?.toString()),
      _dRow(Icons.send, 'Einreichungsweg', _fkMethodeLabel(a['methode']?.toString())),
      if ((a['aktenzeichen']?.toString() ?? '').isNotEmpty) _dRow(Icons.folder, 'Kindergeld-Nr./Az.', a['aktenzeichen'].toString()),
      const SizedBox(height: 12),
      Text('Status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
      const SizedBox(height: 4),
      DropdownButtonFormField<String>(
        initialValue: _fkStatus.containsKey(a['status']) ? a['status'].toString() : 'eingereicht',
        isExpanded: true,
        decoration: InputDecoration(isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
        items: _fkStatus.entries.map((s) => DropdownMenuItem(value: s.key, child: Text(s.value.$1, style: const TextStyle(fontSize: 13)))).toList(),
        onChanged: (v) async {
          if (v == null) return;
          setState(() => _antrag['status'] = v);
          await _persistAntrag();
        },
      ),
      const SizedBox(height: 16),
      Text('Notiz', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
      const SizedBox(height: 4),
      _NotizEditor(
        initial: a['notiz']?.toString() ?? '',
        onSave: (txt) async {
          setState(() => _antrag['notiz'] = txt);
          await _persistAntrag();
        },
      ),
    ]));
  }

  Widget _dRow(IconData icon, String label, String? value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          SizedBox(width: 130, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
          Expanded(child: Text((value ?? '').isEmpty ? '—' : value!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        ]),
      );

  // ---- Unterlagen ----
  Widget _buildDokumente() {
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Row(children: [
        Icon(Icons.lock, size: 16, color: Colors.green.shade700),
        const SizedBox(width: 6),
        Expanded(child: Text('${_docs.length} Unterlagen · verschlüsselt', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
        OutlinedButton.icon(
          onPressed: () async {
            final res = await pickAndAttachFromCloud(context, apiService: widget.apiService, memberId: widget.userId,
                attach: (id) => widget.apiService.attachFkAntragDocFromCloud(antragId: widget.antragId, cloudFileId: id));
            if (res != null && mounted) { _load(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${res.ok} von ${res.total} aus Cloud übernommen'), backgroundColor: res.ok == res.total ? Colors.green : Colors.orange)); }
          },
          icon: const Icon(Icons.cloud_download, size: 16), label: const Text('Aus Cloud', style: TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.blue.shade700)),
        const SizedBox(width: 6),
        ElevatedButton.icon(onPressed: _uploadDoc, icon: const Icon(Icons.upload_file, size: 16), label: const Text('Hochladen', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white)),
      ])),
      Expanded(child: _docs.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.cloud_upload, size: 48, color: Colors.grey.shade300), const SizedBox(height: 8), Text('Keine Unterlagen', style: TextStyle(color: Colors.grey.shade500))]))
          : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: _docs.length, itemBuilder: (_, i) {
              final d = _docs[i];
              return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green.shade200)),
                child: Row(children: [
                  Icon(Icons.attach_file, size: 18, color: Colors.green.shade700),
                  const SizedBox(width: 8),
                  Expanded(child: Text(d['datei_name']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade800))),
                  IconButton(icon: Icon(Icons.visibility, size: 18, color: Colors.orange.shade700), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: () => _viewDoc(d, external: false)),
                  IconButton(icon: Icon(Icons.download, size: 18, color: Colors.green.shade700), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: () => _viewDoc(d, external: true)),
                  IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: () async { await widget.apiService.deleteFkAntragDoc(d['id'] as int); _load(); }),
                ]));
            })),
    ]);
  }

  Future<void> _viewDoc(Map<String, dynamic> d, {required bool external}) async {
    try {
      final resp = await widget.apiService.downloadFkAntragDoc(d['id'] as int);
      if (resp.statusCode != 200 || !mounted) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${d['datei_name']}');
      await file.writeAsBytes(resp.bodyBytes);
      if (external) {
        await OpenFilex.open(file.path);
      } else if (mounted) {
        await FileViewerDialog.show(context, file.path, d['datei_name']?.toString() ?? '');
      }
    } catch (_) {}
  }

  Future<void> _uploadDoc() async {
    final result = await FilePickerHelper.pickFiles(type: FileType.any, allowMultiple: true);
    if (result == null || result.files.isEmpty) return;
    for (final file in result.files.where((f) => f.path != null)) {
      await widget.apiService.uploadFkAntragDoc(antragId: widget.antragId, filePath: file.path!, fileName: file.name);
    }
    _load();
  }

  // ---- Korrespondenz ----
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
      Expanded(child: _korr.isEmpty
          ? Center(child: Text('Keine Korrespondenz', style: TextStyle(color: Colors.grey.shade500)))
          : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _korr.length, itemBuilder: (_, i) {
              final k = _korr[i];
              final isEin = k['richtung'] == 'eingang';
              final kColor = isEin ? Colors.green : Colors.blue;
              return Card(margin: const EdgeInsets.only(bottom: 6), child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _showKorrDetail(k),
                child: Padding(padding: const EdgeInsets.all(10), child: Row(children: [
                  Icon(isEin ? Icons.call_received : Icons.call_made, size: 18, color: kColor.shade700),
                  const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text((k['betreff']?.toString() ?? '').isEmpty ? '(kein Betreff)' : k['betreff'].toString(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kColor.shade800)),
                    Row(children: [
                      Text(k['datum']?.toString() ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                      if ((k['methode']?.toString() ?? '').isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(_fkMethodeLabel(k['methode']?.toString()), style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                      ],
                    ]),
                  ])),
                  Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
                  IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () async { await widget.apiService.deleteFkAntragKorr(k['id'] as int); _load(); }),
                ])),
              ));
            })),
    ]);
  }

  void _showKorrDetail(Map<String, dynamic> k) {
    final isEin = k['richtung'] == 'eingang';
    final color = isEin ? Colors.green : Colors.blue;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Row(children: [
        Icon(isEin ? Icons.call_received : Icons.call_made, size: 20, color: color.shade700),
        const SizedBox(width: 8),
        Expanded(child: Text((k['betreff']?.toString() ?? '').isEmpty ? '(kein Betreff)' : k['betreff'].toString(), style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color.shade800))),
      ]),
      content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: color.shade100, borderRadius: BorderRadius.circular(8)),
            child: Text(isEin ? 'Eingang' : 'Ausgang', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color.shade800))),
          if ((k['methode']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(8)),
              child: Text(_fkMethodeLabel(k['methode']?.toString()), style: TextStyle(fontSize: 11, color: Colors.purple.shade700))),
          ],
          const Spacer(),
          Text(k['datum']?.toString() ?? '', style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
        ]),
        if ((k['notiz']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Inhalt', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
            child: SelectableText(k['notiz'].toString(), style: const TextStyle(fontSize: 13, height: 1.4))),
        ],
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen'))],
    ));
  }

  void _addKorr(String richtung) {
    final betreffC = TextEditingController();
    final now = DateTime.now();
    final datumC = TextEditingController(text: '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}');
    final notizC = TextEditingController();
    String methode = '';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) => AlertDialog(
      title: Text(richtung == 'eingang' ? 'Eingang' : 'Ausgang', style: const TextStyle(fontSize: 16)),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', isDense: true, border: const OutlineInputBorder(), suffixIcon: IconButton(icon: const Icon(Icons.calendar_today, size: 18), onPressed: () async {
          final p = await showDatePicker(context: ctx2, initialDate: DateTime.tryParse(datumC.text) ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
          if (p != null) setD(() => datumC.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}');
        }))),
        const SizedBox(height: 8),
        Text('Kontaktart', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 6, children: _fkMethoden.entries.map((m) => ChoiceChip(
          label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(m.value.$2, size: 14, color: methode == m.key ? Colors.white : Colors.grey.shade700), const SizedBox(width: 4), Text(m.value.$1, style: TextStyle(fontSize: 11, color: methode == m.key ? Colors.white : Colors.black87))]),
          selected: methode == m.key, selectedColor: Colors.orange.shade700, onSelected: (_) => setD(() => methode = m.key),
        )).toList()),
        const SizedBox(height: 8),
        TextField(controller: betreffC, decoration: const InputDecoration(labelText: 'Betreff', isDense: true, border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 3, decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder())),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          await widget.apiService.saveFkAntragKorr(widget.antragId, {'richtung': richtung, 'methode': methode, 'datum': datumC.text.trim(), 'betreff': betreffC.text.trim(), 'notiz': notizC.text.trim()});
          if (ctx.mounted) Navigator.pop(ctx);
          _load();
        }, child: const Text('Speichern')),
      ],
    )));
  }

  // ---- Termine (Sync Terminverwaltung) ----
  Widget _buildTermine() {
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 4), child: Row(children: [
        Icon(Icons.event, size: 18, color: Colors.orange.shade800),
        const SizedBox(width: 6),
        Expanded(child: Text('Termine', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange.shade800))),
        ElevatedButton.icon(onPressed: _addTermin, icon: const Icon(Icons.add, size: 14), label: const Text('Neuer Termin', style: TextStyle(fontSize: 11)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10))),
      ])),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.blue.shade200)),
        child: Row(children: [
          Icon(Icons.info_outline, size: 14, color: Colors.blue.shade700),
          const SizedBox(width: 6),
          Expanded(child: Text('Termine werden automatisch in die zentrale Terminverwaltung übernommen.', style: TextStyle(fontSize: 10, color: Colors.blue.shade900))),
        ]),
      )),
      Expanded(child: _termine.isEmpty
          ? Center(child: Text('Keine Termine', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)))
          : ListView.builder(padding: const EdgeInsets.fromLTRB(12, 8, 12, 12), itemCount: _termine.length, itemBuilder: (_, i) {
              final t = _termine[i];
              final hasGlobal = (t['termin_id']?.toString() ?? '').isNotEmpty && t['termin_id'] != null;
              return Card(margin: const EdgeInsets.only(bottom: 6), child: ListTile(
                dense: true,
                leading: Icon(Icons.event, color: Colors.orange.shade800, size: 22),
                title: Text('${t['datum'] ?? ''}${(t['uhrzeit']?.toString() ?? '').isNotEmpty ? '  ·  ${t['uhrzeit']}' : ''}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if ((t['ort']?.toString() ?? '').isNotEmpty) Text('Ort: ${t['ort']}', style: const TextStyle(fontSize: 11)),
                  if ((t['notiz']?.toString() ?? '').isNotEmpty) Text(t['notiz'].toString(), style: const TextStyle(fontSize: 11)),
                  if (hasGlobal) Padding(padding: const EdgeInsets.only(top: 2), child: Row(children: [
                    Icon(Icons.check_circle, size: 10, color: Colors.green.shade600),
                    const SizedBox(width: 3),
                    Text('In Terminverwaltung übernommen', style: TextStyle(fontSize: 9, color: Colors.green.shade700, fontWeight: FontWeight.w600)),
                  ])),
                ]),
                trailing: IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400), onPressed: () async {
                  final id = int.tryParse(t['id']?.toString() ?? '');
                  if (id != null) { await widget.apiService.deleteFkAntragTermin(id); await _load(); }
                }),
              ));
            })),
    ]);
  }

  Future<void> _addTermin() async {
    final datumC = TextEditingController();
    final uhrzeitC = TextEditingController();
    final ortC = TextEditingController();
    final notizC = TextEditingController();
    bool submitting = false;
    if (!mounted) return;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Neuer Termin'),
        content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: TextField(controller: datumC, readOnly: true,
              decoration: InputDecoration(labelText: 'Datum *', prefixIcon: const Icon(Icons.calendar_today, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              onTap: () async {
                final p = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
                if (p != null) setD(() => datumC.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}');
              })),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: uhrzeitC, readOnly: true,
              decoration: InputDecoration(labelText: 'Uhrzeit *', prefixIcon: const Icon(Icons.access_time, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              onTap: () async {
                final t = await showTimePicker(context: ctx2, initialTime: const TimeOfDay(hour: 9, minute: 0));
                if (t != null) setD(() => uhrzeitC.text = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
              })),
          ]),
          const SizedBox(height: 8),
          TextField(controller: ortC, decoration: InputDecoration(labelText: 'Ort', prefixIcon: const Icon(Icons.place, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 8),
          TextField(controller: notizC, maxLines: 3, decoration: InputDecoration(labelText: 'Notiz / Anlass', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.blue.shade200)),
            child: Row(children: [
              Icon(Icons.info_outline, size: 14, color: Colors.blue.shade700),
              const SizedBox(width: 6),
              Expanded(child: Text('Termin wird automatisch in der Terminverwaltung erstellt (Institution & Az. aus diesem Antrag).', style: TextStyle(fontSize: 10, color: Colors.blue.shade900))),
            ])),
        ]))),
        actions: [
          TextButton(onPressed: submitting ? null : () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: submitting ? null : () async {
            if (datumC.text.trim().isEmpty || uhrzeitC.text.trim().isEmpty) return;
            setD(() => submitting = true);
            await widget.apiService.saveFkAntragTermin(widget.antragId, widget.userId, {
              'datum': datumC.text.trim(), 'uhrzeit': uhrzeitC.text.trim(), 'ort': ortC.text.trim(), 'notiz': notizC.text.trim(),
            });
            if (ctx.mounted) Navigator.pop(ctx, true);
          }, child: submitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Speichern')),
        ],
      );
    }));
    if (ok == true) await _load();
  }

  // ---- Bewilligung (1:1 pro Antrag) ----
  Widget _buildBewilligung() {
    return _FkBewilligungForm(
      apiService: widget.apiService,
      userId: widget.userId,
      antragId: widget.antragId,
      initial: _bewilligung,
      onSaved: _load,
    );
  }
}

/// Kleiner Inline-Editor für die Notiz mit Speichern-Button (nur sichtbar, wenn geändert).
class _NotizEditor extends StatefulWidget {
  final String initial;
  final Future<void> Function(String) onSave;
  const _NotizEditor({required this.initial, required this.onSave});
  @override
  State<_NotizEditor> createState() => _NotizEditorState();
}

class _NotizEditorState extends State<_NotizEditor> {
  late TextEditingController _c;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      TextField(
        controller: _c,
        maxLines: 4,
        onChanged: (v) => setState(() => _dirty = v != widget.initial),
        decoration: InputDecoration(hintText: 'z.B. fehlende Unterlagen, Fristen...', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
      ),
      if (_dirty) Padding(
        padding: const EdgeInsets.only(top: 6),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700),
          icon: const Icon(Icons.save, size: 16),
          label: const Text('Notiz speichern', style: TextStyle(fontSize: 12)),
          onPressed: () async { await widget.onSave(_c.text.trim()); if (mounted) setState(() => _dirty = false); },
        ),
      ),
    ]);
  }
}

/// Bewilligungsformular (1:1 pro Antrag). Erfasst Bescheid, Zeitraum, Beträge,
/// Widerspruch. Auto-Weiterbewilligung-Erinnerung serverseitig (2 Mon. vor Ablauf,
/// v.a. für befristete Bewilligungen wie Kinderzuschlag/KiZ).
class _FkBewilligungForm extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int antragId;
  final Map<String, dynamic>? initial;
  final VoidCallback onSaved;
  const _FkBewilligungForm({required this.apiService, required this.userId, required this.antragId, required this.initial, required this.onSaved});

  @override
  State<_FkBewilligungForm> createState() => _FkBewilligungFormState();
}

class _FkBewilligungFormState extends State<_FkBewilligungForm> {
  late bool _bewilligt;
  late bool _widerspruch;
  late TextEditingController _bescheidC, _vonC, _bisC, _wsDatumC, _monatlichC, _einmalC, _aktenC, _notizC;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final b = widget.initial ?? {};
    _bewilligt = (b['bewilligt']?.toString() ?? '1') != '0';
    _widerspruch = (b['widerspruch']?.toString() ?? '0') == '1';
    _bescheidC = TextEditingController(text: b['bescheid_datum']?.toString() ?? '');
    _vonC = TextEditingController(text: b['zeitraum_von']?.toString() ?? '');
    _bisC = TextEditingController(text: b['zeitraum_bis']?.toString() ?? '');
    _wsDatumC = TextEditingController(text: b['widerspruch_datum']?.toString() ?? '');
    _monatlichC = TextEditingController(text: _fmtNum(b['betrag_monatlich']));
    _einmalC = TextEditingController(text: _fmtNum(b['einmalbetrag']));
    _aktenC = TextEditingController(text: b['aktenzeichen']?.toString() ?? '');
    _notizC = TextEditingController(text: b['notiz']?.toString() ?? '');
  }

  String _fmtNum(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
  }

  @override
  void dispose() {
    for (final c in [_bescheidC, _vonC, _bisC, _wsDatumC, _monatlichC, _einmalC, _aktenC, _notizC]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _pickDate(TextEditingController c) async {
    final p = await showDatePicker(context: context, initialDate: DateTime.tryParse(c.text) ?? DateTime.now(), firstDate: DateTime(2015), lastDate: DateTime(2045), locale: const Locale('de'));
    if (p != null) setState(() => c.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}');
  }

  Widget _dateField(String label, TextEditingController c, IconData icon) => TextField(
        controller: c, readOnly: true,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          suffixIcon: c.text.isEmpty ? null : IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () => setState(() => c.clear()))),
        onTap: () => _pickDate(c),
      );

  Future<void> _save() async {
    setState(() => _saving = true);
    final r = await widget.apiService.saveFkBewilligung(widget.userId, {
      if (widget.initial?['id'] != null) 'id': widget.initial!['id'],
      'antrag_id': widget.antragId,
      'bewilligt': _bewilligt,
      'bescheid_datum': _bescheidC.text.trim(),
      'zeitraum_von': _vonC.text.trim(),
      'zeitraum_bis': _bisC.text.trim(),
      'betrag_monatlich': _monatlichC.text.trim().replaceAll(',', '.'),
      'einmalbetrag': _einmalC.text.trim().replaceAll(',', '.'),
      'aktenzeichen': _aktenC.text.trim(),
      'widerspruch': _widerspruch,
      'widerspruch_datum': _wsDatumC.text.trim(),
      'notiz': _notizC.text.trim(),
    });
    if (!mounted) return;
    setState(() => _saving = false);
    final wba = r['wba_action']?.toString();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r['success'] == true
          ? 'Bewilligung gespeichert${(wba == 'created' || wba == 'updated') ? ' · Weiterbewilligung-Erinnerung angelegt' : ''}'
          : 'Fehler beim Speichern'),
      backgroundColor: r['success'] == true ? Colors.green.shade700 : Colors.red,
    ));
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final wba = widget.initial?['wba_ticket'];
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.verified, size: 18, color: Colors.orange.shade800),
        const SizedBox(width: 6),
        Text('Bewilligung / Bescheid', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
        const Spacer(),
        if (widget.initial?['id'] != null)
          IconButton(icon: Icon(Icons.delete_outline, size: 20, color: Colors.red.shade400), tooltip: 'Bewilligung löschen', onPressed: () async {
            final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
              title: const Text('Bewilligung löschen?'),
              content: const Text('Der Bescheid-Datensatz wird gelöscht. Eine offene Weiterbewilligung-Erinnerung wird geschlossen.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
                FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(c, true), child: const Text('Löschen')),
              ],
            ));
            if (ok == true) { await widget.apiService.deleteFkBewilligung(widget.initial!['id'] as int); widget.onSaved(); }
          }),
      ]),
      const SizedBox(height: 10),
      // Bewilligt / Abgelehnt
      Row(children: [
        Expanded(child: ChoiceChip(
          label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.check_circle, size: 15, color: _bewilligt ? Colors.white : Colors.green.shade600), const SizedBox(width: 4), Text('Bewilligt', style: TextStyle(fontSize: 12, color: _bewilligt ? Colors.white : Colors.black87))]),
          selected: _bewilligt, selectedColor: Colors.green.shade600, onSelected: (_) => setState(() => _bewilligt = true))),
        const SizedBox(width: 8),
        Expanded(child: ChoiceChip(
          label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.cancel, size: 15, color: !_bewilligt ? Colors.white : Colors.red.shade600), const SizedBox(width: 4), Text('Abgelehnt', style: TextStyle(fontSize: 12, color: !_bewilligt ? Colors.white : Colors.black87))]),
          selected: !_bewilligt, selectedColor: Colors.red.shade600, onSelected: (_) => setState(() => _bewilligt = false))),
      ]),
      const SizedBox(height: 12),
      _dateField('Bescheid-Datum', _bescheidC, Icons.event_note),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _dateField('Zeitraum von', _vonC, Icons.play_arrow)),
        const SizedBox(width: 8),
        Expanded(child: _dateField('Zeitraum bis', _bisC, Icons.flag)),
      ]),
      const SizedBox(height: 4),
      Padding(padding: const EdgeInsets.only(left: 4), child: Text('„Zeitraum bis" steuert die automatische Weiterbewilligung-Erinnerung (2 Monate vorher).', style: TextStyle(fontSize: 10, color: Colors.grey.shade500))),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: TextField(controller: _monatlichC, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Betrag mtl. (€)', prefixIcon: const Icon(Icons.euro, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
        const SizedBox(width: 8),
        Expanded(child: TextField(controller: _einmalC, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Einmalbetrag (€)', prefixIcon: const Icon(Icons.payments, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
      ]),
      const SizedBox(height: 10),
      TextField(controller: _aktenC, decoration: InputDecoration(labelText: 'Kindergeld-Nr. / Bescheid-Nr.', prefixIcon: const Icon(Icons.folder, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      const SizedBox(height: 12),
      Container(
        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
        child: Column(children: [
          SwitchListTile(
            dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            title: const Text('Widerspruch eingelegt', style: TextStyle(fontSize: 13)),
            value: _widerspruch, activeThumbColor: Colors.purple, onChanged: (v) => setState(() => _widerspruch = v)),
          if (_widerspruch) Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 10), child: _dateField('Widerspruch-Datum', _wsDatumC, Icons.gavel)),
        ]),
      ),
      const SizedBox(height: 12),
      TextField(controller: _notizC, maxLines: 3, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      if (wba is Map) ...[
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade300)),
          child: Row(children: [
            Icon(Icons.notifications_active, size: 18, color: Colors.amber.shade800),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Weiterbewilligung-Erinnerung aktiv', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
              Text('Ticket #${wba['ticket_id']} · fällig ${(wba['scheduled_date']?.toString() ?? '').split(' ').first} · Bewilligung bis ${wba['bis'] ?? ''}', style: TextStyle(fontSize: 11, color: Colors.amber.shade900)),
            ])),
          ])),
      ],
      const SizedBox(height: 16),
      SizedBox(width: double.infinity, child: FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700),
        icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 18),
        label: Text(widget.initial?['id'] != null ? 'Bewilligung aktualisieren' : 'Bewilligung speichern'),
        onPressed: _saving ? null : _save,
      )),
    ]));
  }
}

// ============ TAB 4: RECHNER (Kinder-Anspruch + Kindergeld/Freibetrag, server-driven) ============

/// Kindergeld-/Freibetrag-Rechner mit Kinder-Anspruchsprüfung.
/// Die Beträge (Kindergeld/Monat, Kinderzuschlag-Max, Kinderfreibetrag) werden
/// LIVE aus `kindergeld_saetze` (getKindergeldSaetze) geladen — die gesetzliche
/// Anpassung (i.d.R. jährlich) greift so ohne App-Update. Offline-Fallback unten.
class _FkRechnerTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final Map<String, dynamic> db; // bereich 'rechner'
  final Future<void> Function(Map<String, dynamic>) onPersist;
  const _FkRechnerTab({required this.apiService, required this.userId, required this.db, required this.onPersist});

  @override
  State<_FkRechnerTab> createState() => _FkRechnerTabState();
}

class _FkRechnerTabState extends State<_FkRechnerTab> {
  // Offline-Fallback (kindergeld_saetze auf dem Server ist die Quelle der Wahrheit)
  static const int _fbKindergeld = 259;       // 2026 €/Monat
  static const int _fbKiZMax = 297;           // 2026 €/Monat
  static const int _fbKinderfreibetrag = 9756; // 2026 €/Jahr (inkl. BEA, beide Eltern)
  static const Map<int, int> _grundfreibetrag = {2023: 10908, 2024: 11604, 2025: 12084, 2026: 12336};

  static const Map<String, String> _statusLabels = {
    'kind': 'Minderjähriges Kind',
    'schule': 'Schüler/in',
    'ausbildung': 'In Ausbildung',
    'studium': 'Im Studium',
    'fsj': 'FSJ / BFD (Freiwilligendienst)',
    'arbeitssuchend': 'Arbeitssuchend',
    'behinderung': 'Behinderung (nicht erwerbsfähig)',
    'berufstaetig': 'Berufstätig / Keine Ausbildung',
  };

  late List<Map<String, dynamic>> _kinderListe;
  Map<String, dynamic>? _saetzeAktuell;
  List<Map<String, dynamic>> _saetzeAlle = [];
  bool _saetzeLoaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _kinderListe = _parseKinder();
    _loadSaetze();
  }

  List<Map<String, dynamic>> _parseKinder() {
    final raw = widget.db['kinder_liste'];
    try {
      if (raw is String && raw.trim().isNotEmpty) {
        final d = jsonDecode(raw);
        if (d is List) return d.map((k) => Map<String, dynamic>.from(k as Map)).toList();
      } else if (raw is List) {
        return raw.map((k) => Map<String, dynamic>.from(k as Map)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> _loadSaetze() async {
    try {
      final r = await widget.apiService.getKindergeldSaetze();
      if (!mounted) return;
      if (r['success'] == true) {
        if (r['aktuell'] is Map) _saetzeAktuell = Map<String, dynamic>.from(r['aktuell'] as Map);
        if (r['alle'] is List) _saetzeAlle = (r['alle'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      debugPrint('[Familienkasse-Rechner] Sätze load error: $e');
    }
    if (mounted) setState(() => _saetzeLoaded = true);
  }

  Future<void> _saveKinder() async {
    setState(() => _saving = true);
    await widget.onPersist({
      'kinder_liste': jsonEncode(_kinderListe),
      'anzahl_kinder': _kinderListe.length.toString(),
    });
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kinder gespeichert'), backgroundColor: Colors.green));
  }

  int? _numToInt(dynamic v) => v == null ? null : double.tryParse(v.toString())?.round();

  static String _formatCurrency(int amount) {
    final str = amount.toString();
    final parts = <String>[];
    for (var i = str.length; i > 0; i -= 3) {
      parts.insert(0, str.substring(i - 3 < 0 ? 0 : i - 3, i));
    }
    return '${parts.join(".")} €';
  }

  int _getGrundfreibetrag(int year) => _grundfreibetrag[year] ?? _grundfreibetrag.values.last;

  DateTime? _parseDateDE(String dateStr) {
    if (dateStr.isEmpty) return null;
    final parts = dateStr.split('.');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    return DateTime(year, month, day);
  }

  int? _berechneAlter(String geburtsdatum, DateTime now) {
    final geb = _parseDateDE(geburtsdatum);
    if (geb == null) return null;
    int alter = now.year - geb.year;
    if (now.month < geb.month || (now.month == geb.month && now.day < geb.day)) alter--;
    return alter;
  }

  bool _isKindergeldBerechtigt(Map<String, dynamic> kind, DateTime now) {
    final alter = _berechneAlter(kind['geburtsdatum'] ?? '', now);
    if (alter == null) return true;
    final status = kind['status'] ?? 'kind';
    if (alter < 18) return true;
    if (alter < 25) {
      return status == 'schule' || status == 'ausbildung' || status == 'studium' ||
          status == 'fsj' || status == 'arbeitssuchend' || status == 'behinderung';
    }
    if (status == 'behinderung') return true;
    return false;
  }

  String _getKindergeldStatusInfo(Map<String, dynamic> kind, DateTime now) {
    final alter = _berechneAlter(kind['geburtsdatum'] ?? '', now);
    if (alter == null) return 'Geburtsdatum eingeben für automatische Prüfung';
    final status = kind['status'] ?? 'kind';
    if (alter < 18) return 'Unter 18 — Kindergeld-Anspruch besteht automatisch';
    if (alter >= 18 && alter < 25) {
      switch (status) {
        case 'schule': return 'Schüler/in — Kindergeld-Anspruch bis 25. Lebensjahr';
        case 'ausbildung': return 'In Ausbildung — Kindergeld-Anspruch bis 25. Lebensjahr';
        case 'studium': return 'Im Studium — Kindergeld-Anspruch bis 25. Lebensjahr';
        case 'fsj': return 'FSJ/BFD — Kindergeld-Anspruch bis 25. Lebensjahr';
        case 'arbeitssuchend': return 'Arbeitssuchend — Kindergeld max. 4 Monate';
        case 'behinderung': return 'Behinderung — Kindergeld-Anspruch unbefristet';
        case 'berufstaetig': return 'Berufstätig — kein Kindergeld-Anspruch (nicht in Ausbildung)';
        default: return 'Status wählen für Kindergeld-Prüfung';
      }
    }
    if (status == 'behinderung') {
      return 'Über 25 mit Behinderung — Kindergeld-Anspruch unbefristet (wenn Behinderung vor 25. Lj.)';
    }
    return 'Über 25 — kein Kindergeld-Anspruch mehr (nur bei Behinderung vor dem 25. Lebensjahr)';
  }

  bool _hatMerkzeichen(Map<String, dynamic> kind, String code) => List<String>.from(kind['merkzeichen'] ?? []).contains(code);

  Widget _merkzeichenChip(String code, String label, Map<String, dynamic> kind) {
    final merkzeichen = List<String>.from(kind['merkzeichen'] ?? []);
    final selected = merkzeichen.contains(code);
    return FilterChip(
      label: Text('$code ($label)', style: TextStyle(fontSize: 10, color: selected ? Colors.white : Colors.purple.shade700)),
      selected: selected,
      selectedColor: Colors.purple.shade600,
      checkmarkColor: Colors.white,
      backgroundColor: Colors.purple.shade50,
      side: BorderSide(color: selected ? Colors.purple.shade600 : Colors.purple.shade200),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      onSelected: (val) {
        setState(() {
          if (val) { merkzeichen.add(code); } else { merkzeichen.remove(code); }
          kind['merkzeichen'] = merkzeichen;
        });
      },
    );
  }

  Widget _fkInfoRow(String label, String value, MaterialColor color, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: color.shade700))),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.bold : FontWeight.w500, color: color.shade800)),
        ]),
      );

  Widget _fkRuleRow(IconData icon, String text, MaterialColor color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 14, color: color.shade400),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: TextStyle(fontSize: 11, color: Colors.grey.shade700))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    if (!_saetzeLoaded) return const Center(child: CircularProgressIndicator());
    final now = DateTime.now();
    final currentYear = now.year;
    final kindergeldMonat = _numToInt(_saetzeAktuell?['betrag_pro_kind']) ?? _fbKindergeld;
    final kiZMax = _numToInt(_saetzeAktuell?['kinderzuschlag_max']) ?? _fbKiZMax;
    final kinderfreibetrag = _numToInt(_saetzeAktuell?['kinderfreibetrag']) ?? _fbKinderfreibetrag;
    final quelle = _saetzeAktuell?['quelle']?.toString() ?? 'Bundeskindergeldgesetz (BKGG)';
    final satzJahr = _numToInt(_saetzeAktuell?['jahr']) ?? currentYear;
    final serverLive = _saetzeAktuell != null;
    final kindergeldJahr = kindergeldMonat * 12;

    int berechtigteKinder = 0;
    for (final kind in _kinderListe) {
      if (_isKindergeldBerechtigt(kind, now)) berechtigteKinder++;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Datenquelle-Hinweis ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: serverLive ? Colors.green.shade50 : Colors.amber.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: serverLive ? Colors.green.shade200 : Colors.amber.shade300),
          ),
          child: Row(children: [
            Icon(serverLive ? Icons.cloud_done : Icons.cloud_off, size: 18, color: serverLive ? Colors.green.shade700 : Colors.amber.shade800),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(serverLive ? 'Beträge $satzJahr live vom Server' : 'Offline — zuletzt bekannte Beträge', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: serverLive ? Colors.green.shade800 : Colors.amber.shade900)),
              Text('Quelle: $quelle', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
            ])),
          ]),
        ),
        const SizedBox(height: 12),

        // ── KINDER LISTE ──
        Row(children: [
          Icon(Icons.child_care, size: 20, color: Colors.orange.shade700),
          const SizedBox(width: 6),
          Text('Kinder', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
          const Spacer(),
          if (_kinderListe.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(12)),
              child: Text('${_kinderListe.length} ${_kinderListe.length == 1 ? 'Kind' : 'Kinder'}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
            ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => setState(() => _kinderListe.add({'name': '', 'geburtsdatum': '', 'status': 'kind', 'behinderung': false})),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Kind hinzufügen'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade600, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), textStyle: const TextStyle(fontSize: 12)),
          ),
        ]),
        const SizedBox(height: 8),

        ..._kinderListe.asMap().entries.map((entry) {
          final idx = entry.key;
          final kind = entry.value;
          final alter = _berechneAlter(kind['geburtsdatum'] ?? '', now);
          final eligible = _isKindergeldBerechtigt(kind, now);
          final status = kind['status'] ?? 'kind';
          final eligInfo = _getKindergeldStatusInfo(kind, now);

          return Container(
            key: ValueKey('kind_$idx'),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: eligible ? Colors.green.shade50 : Colors.red.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: eligible ? Colors.green.shade300 : Colors.red.shade300),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 26, height: 26,
                  decoration: BoxDecoration(color: eligible ? Colors.green.shade600 : Colors.red.shade400, shape: BoxShape.circle),
                  child: Center(child: Text('${idx + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text((kind['name'] ?? '').toString().isNotEmpty ? kind['name'] : 'Kind ${idx + 1}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade800))),
                if (alter != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(10)),
                    child: Text('$alter ${alter == 1 ? 'Jahr' : 'Jahre'}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                  ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: eligible ? Colors.green.shade100 : Colors.red.shade100, borderRadius: BorderRadius.circular(10)),
                  child: Text(eligible ? 'Berechtigt' : 'Kein Anspruch', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: eligible ? Colors.green.shade800 : Colors.red.shade700)),
                ),
                const SizedBox(width: 4),
                InkWell(onTap: () => setState(() => _kinderListe.removeAt(idx)), child: Icon(Icons.close, size: 18, color: Colors.red.shade400)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: TextEditingController(text: kind['name'] ?? ''),
                    decoration: InputDecoration(labelText: 'Name', prefixIcon: const Icon(Icons.person_outline, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (v) => kind['name'] = v,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: () async {
                      final initial = _parseDateDE(kind['geburtsdatum'] ?? '');
                      final picked = await showDatePicker(context: context, initialDate: initial ?? DateTime(2010, 1, 1), firstDate: DateTime(1970), lastDate: now, locale: const Locale('de'));
                      if (picked != null) {
                        setState(() {
                          kind['geburtsdatum'] = '${picked.day.toString().padLeft(2, '0')}.${picked.month.toString().padLeft(2, '0')}.${picked.year}';
                          final age = _berechneAlter(kind['geburtsdatum'], now);
                          if (age != null && age < 18) kind['status'] = 'kind';
                        });
                      }
                    },
                    child: AbsorbPointer(
                      child: TextField(
                        controller: TextEditingController(text: kind['geburtsdatum'] ?? ''),
                        decoration: InputDecoration(labelText: 'Geburtsdatum', prefixIcon: const Icon(Icons.cake, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ]),
              if (alter != null && alter >= 18) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(8)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _statusLabels.containsKey(status) ? status : 'berufstaetig',
                      isExpanded: true,
                      style: const TextStyle(fontSize: 13, color: Colors.black87),
                      items: _statusLabels.entries.where((e) => e.key != 'kind').map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12)))).toList(),
                      onChanged: (v) => setState(() => kind['status'] = v),
                    ),
                  ),
                ),
              ],
              if (status == 'behinderung') ...[
                const SizedBox(height: 10),
                _buildBehinderungBox(kind),
              ],
              if (eligInfo.isNotEmpty && status != 'behinderung') ...[
                const SizedBox(height: 6),
                Text(eligInfo, style: TextStyle(fontSize: 11, color: eligible ? Colors.green.shade700 : Colors.red.shade600, fontStyle: FontStyle.italic)),
              ],
            ]),
          );
        }),

        if (_kinderListe.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
            child: Column(children: [
              Icon(Icons.child_care, size: 40, color: Colors.grey.shade400),
              const SizedBox(height: 8),
              Text('Keine Kinder eingetragen', style: TextStyle(color: Colors.grey.shade500)),
              Text('Klicken Sie auf "Kind hinzufügen"', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
            ]),
          ),
        const SizedBox(height: 16),

        // ── KINDERGELD INFO CARD ──
        if (_kinderListe.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.orange.shade50, Colors.orange.shade100], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade300),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.child_care, color: Colors.orange.shade700, size: 22),
                const SizedBox(width: 8),
                Text('Kindergeld $satzJahr', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.orange.shade700, borderRadius: BorderRadius.circular(12)),
                  child: Text('$berechtigteKinder / ${_kinderListe.length} berechtigt', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ]),
              const SizedBox(height: 12),
              _fkInfoRow('Pro Kind / Monat', '$kindergeldMonat €', Colors.orange),
              _fkInfoRow('Pro Kind / Jahr', _formatCurrency(kindergeldJahr), Colors.orange),
              if (berechtigteKinder > 0) ...[
                const Divider(height: 16),
                _fkInfoRow('Gesamt für $berechtigteKinder berechtigte${berechtigteKinder == 1 ? 's Kind' : ' Kinder'} / Monat', _formatCurrency(kindergeldMonat * berechtigteKinder), Colors.orange, bold: true),
                _fkInfoRow('Gesamt für $berechtigteKinder berechtigte${berechtigteKinder == 1 ? 's Kind' : ' Kinder'} / Jahr', _formatCurrency(kindergeldJahr * berechtigteKinder), Colors.orange, bold: true),
              ],
              if (berechtigteKinder < _kinderListe.length) ...[
                const SizedBox(height: 6),
                Text('${_kinderListe.length - berechtigteKinder} ${_kinderListe.length - berechtigteKinder == 1 ? 'Kind' : 'Kinder'} ohne Anspruch (über 25 oder nicht in Ausbildung)', style: TextStyle(fontSize: 11, color: Colors.red.shade400, fontStyle: FontStyle.italic)),
              ],
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade200)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Kindergeld-Anspruch:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                  const SizedBox(height: 4),
                  _fkRuleRow(Icons.check_circle, 'Unter 18 Jahre: immer', Colors.green),
                  _fkRuleRow(Icons.check_circle, '18–25 Jahre: in Ausbildung, Studium, FSJ/BFD', Colors.green),
                  _fkRuleRow(Icons.check_circle, '18–25 Jahre: arbeitssuchend (max. 4 Monate)', Colors.green),
                  _fkRuleRow(Icons.check_circle, 'Über 25: nur bei Behinderung (vor dem 25. Lj. eingetreten)', Colors.green),
                  _fkRuleRow(Icons.cancel, 'Über 25 ohne Behinderung: kein Anspruch', Colors.red),
                ]),
              ),
              if (_saetzeAlle.isNotEmpty) ...[
                const SizedBox(height: 8),
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    title: Text('Kindergeld-Verlauf anzeigen', style: TextStyle(fontSize: 12, color: Colors.orange.shade700, fontWeight: FontWeight.w500)),
                    children: _buildVerlauf(satzJahr),
                  ),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 16),

          // ── KINDERZUSCHLAG CARD ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.teal.shade200)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.euro, color: Colors.teal.shade700, size: 20),
                const SizedBox(width: 8),
                Text('Kinderzuschlag (KiZ) $satzJahr', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
              ]),
              const SizedBox(height: 8),
              _fkInfoRow('Höchstbetrag pro Kind / Monat', '$kiZMax €', Colors.teal, bold: true),
              const SizedBox(height: 4),
              Text('Für Familien mit geringem Einkommen zusätzlich zum Kindergeld. Antrag über die Familienkasse (kiz-digital.de). Höhe abhängig von Einkommen/Wohnkosten.', style: TextStyle(fontSize: 11, color: Colors.teal.shade700)),
            ]),
          ),
          const SizedBox(height: 16),

          // ── KINDERFREIBETRAG CARD (server total, inkl. BEA) ──
          if (berechtigteKinder > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.indigo.shade50, Colors.indigo.shade100], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.indigo.shade300),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.account_balance, color: Colors.indigo.shade700, size: 22),
                  const SizedBox(width: 8),
                  Text('Kinderfreibetrag $satzJahr', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
                ]),
                const SizedBox(height: 4),
                Text('Steuerlicher Freibetrag inkl. BEA (Betreuung, Erziehung, Ausbildung), beide Eltern.', style: TextStyle(fontSize: 11, color: Colors.indigo.shade600)),
                const SizedBox(height: 10),
                _fkInfoRow('Pro Kind (beide Eltern)', _formatCurrency(kinderfreibetrag), Colors.indigo),
                _fkInfoRow('Pro Elternteil', _formatCurrency(kinderfreibetrag ~/ 2), Colors.indigo),
                if (berechtigteKinder > 1)
                  _fkInfoRow('Gesamt $berechtigteKinder Kinder', _formatCurrency(kinderfreibetrag * berechtigteKinder), Colors.indigo, bold: true),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                      const SizedBox(width: 6),
                      Text('Kindergeld oder Freibetrag?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                    ]),
                    const SizedBox(height: 4),
                    Text('Das Finanzamt prüft automatisch (Günstigerprüfung), ob Kindergeld oder Kinderfreibetrag vorteilhafter ist.', style: TextStyle(fontSize: 11, color: Colors.blue.shade700)),
                    const SizedBox(height: 4),
                    Text('Kindergeld: ${_formatCurrency(kindergeldJahr * berechtigteKinder)}/Jahr vs. Freibetrag-Ersparnis: max ~${_formatCurrency((kinderfreibetrag * berechtigteKinder * 0.42).round())}/Jahr (42%)', style: TextStyle(fontSize: 11, color: Colors.blue.shade600, fontStyle: FontStyle.italic)),
                  ]),
                ),
              ]),
            ),
          const SizedBox(height: 16),
        ],

        // ── SPEICHERN ──
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _saving ? null : _saveKinder,
            icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 18),
            label: const Text('Kinder speichern'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white),
          ),
        ),
      ]),
    );
  }

  List<Widget> _buildVerlauf(int satzJahr) {
    final rows = _saetzeAlle.where((e) => _numToInt(e['betrag_pro_kind']) != null).toList()
      ..sort((a, b) => (_numToInt(b['jahr']) ?? 0).compareTo(_numToInt(a['jahr']) ?? 0));
    final maxBetrag = rows.fold<int>(1, (m, e) => (_numToInt(e['betrag_pro_kind']) ?? 0) > m ? (_numToInt(e['betrag_pro_kind']) ?? 0) : m);
    return rows.map((e) {
      final jahr = _numToInt(e['jahr']) ?? 0;
      final betrag = _numToInt(e['betrag_pro_kind']) ?? 0;
      final isCurrent = jahr == satzJahr;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          SizedBox(width: 50, child: Text('$jahr', style: TextStyle(fontSize: 12, fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal, color: isCurrent ? Colors.orange.shade800 : Colors.grey.shade600))),
          Expanded(
            child: Container(
              height: 18,
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: (betrag / (maxBetrag * 1.15)).clamp(0.02, 1.0).toDouble(),
                child: Container(decoration: BoxDecoration(color: isCurrent ? Colors.orange.shade400 : Colors.orange.shade200, borderRadius: BorderRadius.circular(4))),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('$betrag €', style: TextStyle(fontSize: 12, fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal, color: isCurrent ? Colors.orange.shade800 : Colors.grey.shade600)),
        ]),
      );
    }).toList();
  }

  Widget _buildBehinderungBox(Map<String, dynamic> kind) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.purple.shade300)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.accessible, size: 18, color: Colors.purple.shade700),
          const SizedBox(width: 6),
          Text('Behinderung — Details', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.purple.shade800)),
        ]),
        const SizedBox(height: 8),
        Text('Grad der Behinderung (GdB)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(8)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: (kind['gdb'] ?? '').toString().isEmpty ? '' : kind['gdb'].toString(),
              isExpanded: true,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
              items: const [
                DropdownMenuItem(value: '', child: Text('Nicht angegeben', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: '20', child: Text('GdB 20', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: '30', child: Text('GdB 30', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: '40', child: Text('GdB 40', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: '50', child: Text('GdB 50 (Schwerbehinderung)', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: '60', child: Text('GdB 60', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: '70', child: Text('GdB 70', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: '80', child: Text('GdB 80', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: '90', child: Text('GdB 90', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: '100', child: Text('GdB 100', style: TextStyle(fontSize: 12))),
              ],
              onChanged: (v) => setState(() => kind['gdb'] = v),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('Merkzeichen im Schwerbehindertenausweis', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 4, children: [
          _merkzeichenChip('H', 'Hilflos', kind),
          _merkzeichenChip('Bl', 'Blind', kind),
          _merkzeichenChip('B', 'Begleitperson', kind),
          _merkzeichenChip('aG', 'Auss. gehbehindert', kind),
          _merkzeichenChip('G', 'Gehbehindert', kind),
          _merkzeichenChip('Gl', 'Gehörlos', kind),
          _merkzeichenChip('TBl', 'Taubblind', kind),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Checkbox(value: kind['beh_vor_25'] == true, onChanged: (v) => setState(() => kind['beh_vor_25'] = v), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact),
          Expanded(child: Text('Behinderung vor Vollendung des 25. Lebensjahres eingetreten', style: TextStyle(fontSize: 11, color: Colors.grey.shade700))),
        ]),
        Row(children: [
          Checkbox(value: kind['nicht_selbst_unterhalten'] == true, onChanged: (v) => setState(() => kind['nicht_selbst_unterhalten'] = v), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact),
          Expanded(child: Text('Kind kann sich nicht selbst unterhalten (Einkommen unter Grundfreibetrag ${_formatCurrency(_getGrundfreibetrag(DateTime.now().year))})', style: TextStyle(fontSize: 11, color: Colors.grey.shade700))),
        ]),
        const SizedBox(height: 8),
        if ((kind['gdb'] ?? '').toString().isNotEmpty) ...[
          () {
            final gdb = int.tryParse(kind['gdb'].toString()) ?? 0;
            if (gdb < 50) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.amber.shade300)),
                child: Row(children: [
                  Icon(Icons.warning_amber, size: 16, color: Colors.amber.shade700),
                  const SizedBox(width: 6),
                  Expanded(child: Text('GdB unter 50 — Kindergeld-Anspruch bei Behinderung erfordert i.d.R. mindestens GdB 50 (Schwerbehinderung)', style: TextStyle(fontSize: 11, color: Colors.amber.shade800))),
                ]),
              );
            }
            return const SizedBox.shrink();
          }(),
        ],
        if (_hatMerkzeichen(kind, 'H'))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.green.shade300)),
              child: Row(children: [
                Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
                const SizedBox(width: 6),
                Expanded(child: Text('Merkzeichen H (hilflos) vorhanden — Kindergeld-Anspruch wird von der Familienkasse grundsätzlich anerkannt', style: TextStyle(fontSize: 11, color: Colors.green.shade800))),
              ]),
            ),
          ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.blue.shade200)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Kindergeld bei Behinderung — Voraussetzungen:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
            const SizedBox(height: 4),
            _fkRuleRow(Icons.check_circle, 'Behinderung vor dem 25. Lebensjahr eingetreten', Colors.green),
            _fkRuleRow(Icons.check_circle, 'Kind kann sich nicht selbst unterhalten', Colors.green),
            _fkRuleRow(Icons.check_circle, 'GdB mindestens 50 (Schwerbehinderung)', Colors.green),
            _fkRuleRow(Icons.check_circle, 'Merkzeichen H = automatisch anerkannt', Colors.green),
            _fkRuleRow(Icons.check_circle, 'Einkommen unter ${_formatCurrency(_getGrundfreibetrag(DateTime.now().year))}/Jahr', Colors.green),
            _fkRuleRow(Icons.check_circle, 'Anspruch unbefristet (lebenslang)', Colors.green),
            const SizedBox(height: 4),
            Text('Nachweise: Schwerbehindertenausweis, ärztliches Gutachten, Pflegegrad-Bescheid', style: TextStyle(fontSize: 10, color: Colors.blue.shade600, fontStyle: FontStyle.italic)),
          ]),
        ),
      ]),
    );
  }
}
