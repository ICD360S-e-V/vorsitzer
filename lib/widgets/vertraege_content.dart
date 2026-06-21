import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';
import 'file_viewer_dialog.dart';
import 'korrespondenz_attachments_widget.dart';

class VertraegeContent extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  const VertraegeContent({super.key, required this.apiService, required this.userId});

  @override
  State<VertraegeContent> createState() => _VertraegeContentState();
}

class _VertraegeContentState extends State<VertraegeContent> {
  List<Map<String, dynamic>> _vertraege = [];
  bool _loaded = false;

  static const _kategorien = [
    ('multimedia', 'Multimedia & Streaming', Icons.tv, Colors.purple),
    ('handy', 'Handyvertrag', Icons.phone_android, Colors.blue),
    ('internet', 'Internet & DSL', Icons.wifi, Colors.teal),
    ('versicherung', 'Versicherung', Icons.shield, Colors.green),
    ('strom', 'Strom', Icons.bolt, Colors.orange),
    ('gas', 'Gas', Icons.local_fire_department, Colors.deepOrange),
    ('verein', 'Verein', Icons.groups, Colors.indigo),
    ('fax', 'Fax', Icons.fax, Colors.cyan),
    ('sonstige', 'Sonstige', Icons.receipt_long, Colors.grey),
  ];

  static const _streamingAnbieter = [
    'Netflix', 'Disney+', 'Amazon Prime Video', 'Apple TV+', 'Spotify', 'DAZN',
    'WOW', 'Paramount+', 'RTL+', 'Joyn Plus+', 'Crunchyroll',
    'YouTube Premium', 'Tidal', 'Deezer', 'Apple Music', 'Audible',
  ];

  /// Tarife + Preise Deutschland 2026 (Stand April 2026)
  static const Map<String, List<(String, double)>> _streamingTarife = {
    'Netflix': [
      ('Standard mit Werbung', 4.99),
      ('Standard', 13.99),
      ('Premium (4K)', 19.99),
    ],
    'Disney+': [
      ('Standard mit Werbung', 5.99),
      ('Standard', 9.99),
      ('Premium (4K)', 13.99),
    ],
    'Amazon Prime Video': [
      ('Prime (mit Werbung)', 8.99),
      ('Prime werbefrei', 11.98),
    ],
    'Apple TV+': [
      ('Monatsabo', 9.99),
    ],
    'Spotify': [
      ('Individual', 12.99),
      ('Duo', 17.99),
      ('Family', 19.99),
      ('Student', 5.99),
    ],
    'DAZN': [
      ('Unlimited (Jahresabo)', 24.99),
      ('Unlimited (Monatsabo)', 44.99),
      ('Super Sports', 19.99),
      ('World', 9.99),
    ],
    'WOW': [
      ('Serien', 7.99),
      ('Filme & Serien', 9.98),
      ('Live-Sport', 24.99),
    ],
    'Paramount+': [
      ('Essential', 4.99),
      ('Standard', 7.99),
    ],
    'RTL+': [
      ('Max', 7.99),
      ('Premium', 11.99),
    ],
    'Crunchyroll': [
      ('Fan', 6.99),
      ('Mega Fan', 9.99),
    ],
    'YouTube Premium': [
      ('Individual', 13.99),
      ('Family', 23.99),
      ('Student', 7.99),
    ],
    'Apple Music': [
      ('Individual', 10.99),
      ('Family', 16.99),
      ('Student', 5.99),
    ],
    'Deezer': [
      ('Premium', 11.99),
      ('Family', 19.99),
    ],
    'Tidal': [
      ('Individual', 11.99),
      ('Family', 17.99),
      ('HiFi Plus', 17.99),
    ],
    'Audible': [
      ('Abo (1 Hörbuch/Monat)', 9.95),
    ],
    'Joyn Plus+': [
      ('Monatsabo', 6.99),
    ],
  };

  static const _handyAnbieter = [
    'Telekom', 'Vodafone', 'O2 / Telefónica', '1&1', 'congstar', 'ALDI TALK',
    'LIDL Connect', 'Blau', 'Drillisch', 'Lebara', 'Lycamobile', 'simplytel',
    'PremiumSIM', 'winSIM', 'fraenk', 'freenet',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.apiService.listVertraege(widget.userId);
    if (!mounted) return;
    if (r['success'] == true && r['data'] is List) {
      setState(() {
        _vertraege = (r['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loaded = true;
      });
    } else {
      setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());

    return DefaultTabController(
      length: _kategorien.length,
      child: Column(children: [
        TabBar(
          isScrollable: true,
          labelColor: Colors.indigo.shade700,
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: Colors.indigo.shade700,
          tabs: _kategorien.map((k) => Tab(
            icon: Icon(k.$3, size: 16, color: k.$4),
            text: k.$2,
          )).toList(),
        ),
        Expanded(
          child: TabBarView(
            children: _kategorien.map((k) => k.$1 == 'verein' ? _VereinTab(apiService: widget.apiService, userId: widget.userId, vertraege: _vertraege.where((v) => v['kategorie'] == 'verein').toList(), onChanged: _load) : _buildKategorieTab(k.$1, k.$2, k.$3, k.$4)).toList(),
          ),
        ),
      ]),
    );
  }

  Widget _buildKategorieTab(String kategorie, String label, IconData icon, Color color) {
    final filtered = _vertraege.where((v) => v['kategorie'] == kategorie).toList();
    final aktive = filtered.where((v) => v['is_active'] == 1 || v['is_active'] == true || v['is_active'] == '1').toList();
    final inaktive = filtered.where((v) => !(v['is_active'] == 1 || v['is_active'] == true || v['is_active'] == '1')).toList();
    final totalKosten = aktive.fold<double>(0, (s, v) => s + (double.tryParse(v['monatliche_kosten']?.toString() ?? '') ?? 0));

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color))),
          if (totalKosten > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Text('${totalKosten.toStringAsFixed(2)} €/Mt.', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
            ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => _showVertragDialog(kategorie: kategorie),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Neu', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
          ),
        ]),
      ),
      Expanded(
        child: filtered.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 8),
                Text('Keine $label Verträge', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
              ]))
            : ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  ...aktive.map((v) => _buildVertragCard(v, color, aktiv: true)),
                  if (inaktive.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 6),
                      child: Text('Beendet / Gekündigt', style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                    ),
                    ...inaktive.map((v) => _buildVertragCard(v, Colors.grey, aktiv: false)),
                  ],
                ],
              ),
      ),
    ]);
  }

  Widget _buildVertragCard(Map<String, dynamic> v, Color color, {required bool aktiv}) {
    final kosten = double.tryParse(v['monatliche_kosten']?.toString() ?? '') ?? 0;
    return Card(
      color: aktiv ? null : Colors.grey.shade50,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: aktiv ? color.withValues(alpha: 0.15) : Colors.grey.shade200,
          child: Icon(Icons.receipt, size: 20, color: aktiv ? color : Colors.grey),
        ),
        title: Text(v['anbieter']?.toString() ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: aktiv ? null : Colors.grey)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if ((v['tarif']?.toString() ?? '').isNotEmpty)
            Text(v['tarif'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          Row(children: [
            if (kosten > 0) Text('${kosten.toStringAsFixed(2)} €/Mt.', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: aktiv ? Colors.green.shade700 : Colors.grey)),
            if ((v['vertragsbeginn']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(width: 8),
              Text('seit ${v['vertragsbeginn']}', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            ],
          ]),
          if ((v['telefonnummer']?.toString() ?? '').isNotEmpty)
            Text('Tel: ${v['telefonnummer']}', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
          if ((v['gekuendigt_am']?.toString() ?? '').isNotEmpty)
            Text('Gekündigt: ${v['gekuendigt_am']}', style: TextStyle(fontSize: 10, color: Colors.red.shade400)),
        ]),
        isThreeLine: true,
        onTap: () => _showVertragDetailModal(v),
        trailing: IconButton(
          icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
          onPressed: () async {
            final id = int.tryParse(v['id']?.toString() ?? '');
            if (id != null) {
              await widget.apiService.deleteVertrag(id);
              _load();
            }
          },
        ),
      ),
    );
  }

  void _showVertragDialog({String? kategorie, Map<String, dynamic>? existing}) {
    final kat = existing?['kategorie']?.toString() ?? kategorie ?? 'multimedia';
    final anbieterC = TextEditingController(text: existing?['anbieter']?.toString() ?? '');
    final tarifC = TextEditingController(text: existing?['tarif']?.toString() ?? '');
    final kostenC = TextEditingController(text: existing?['monatliche_kosten']?.toString() ?? '');
    final beginnC = TextEditingController(text: existing?['vertragsbeginn']?.toString() ?? '');
    final laufzeitC = TextEditingController(text: existing?['mindestlaufzeit']?.toString() ?? '');
    final fristC = TextEditingController(text: existing?['kuendigungsfrist']?.toString() ?? '');
    final gekuendigtC = TextEditingController(text: existing?['gekuendigt_am']?.toString() ?? '');
    final endeC = TextEditingController(text: existing?['vertragsende']?.toString() ?? '');
    final telC = TextEditingController(text: existing?['telefonnummer']?.toString() ?? '');
    final volumenC = TextEditingController(text: existing?['datenvolumen']?.toString() ?? '');
    final emailC = TextEditingController(text: existing?['login_email']?.toString() ?? '');
    final notizenC = TextEditingController(text: existing?['notizen']?.toString() ?? '');
    bool shared = existing?['shared_account'] == 1 || existing?['shared_account'] == true || existing?['shared_account'] == '1';
    bool aktiv = existing == null || existing['is_active'] == 1 || existing['is_active'] == true || existing['is_active'] == '1';
    String selKat = kat;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) {
        final isVerein = selKat == 'verein';
        final vorschlaege = selKat == 'handy' ? _handyAnbieter : (selKat == 'multimedia' ? _streamingAnbieter : <String>[]);
        final tarife = _streamingTarife[anbieterC.text.trim()];
        final hasTarife = tarife != null && tarife.isNotEmpty;
        final kostenReadonly = hasTarife && tarifC.text.isNotEmpty;

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text(existing != null ? 'Vertrag bearbeiten' : 'Neuer Vertrag'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Wrap(spacing: 6, runSpacing: 6, children: _kategorien.map((k) {
                final sel = selKat == k.$1;
                return ChoiceChip(
                  avatar: Icon(k.$3, size: 14, color: sel ? Colors.white : k.$4),
                  label: Text(k.$2, style: TextStyle(fontSize: 10, color: sel ? Colors.white : Colors.black87)),
                  selected: sel,
                  selectedColor: k.$4,
                  onSelected: (_) => setD(() { selKat = k.$1; anbieterC.clear(); tarifC.clear(); kostenC.clear(); if (k.$1 == 'verein') { laufzeitC.text = '12 Monate'; fristC.text = '3 Monate zum Jahresende'; } }),
                );
              }).toList()),
              const SizedBox(height: 12),
              if (isVerein)
                TextField(controller: anbieterC, decoration: InputDecoration(labelText: 'Verein *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  suffixIcon: IconButton(icon: Icon(Icons.search, size: 20, color: Colors.indigo.shade600), tooltip: 'Aus Datenbank',
                    onPressed: () async {
                      final vereine = await widget.apiService.getVereinDatenbank();
                      if (!ctx2.mounted || vereine.isEmpty) return;
                      final sel = await showDialog<Map<String, dynamic>>(context: ctx2, builder: (sCtx) {
                        String search = '';
                        List<Map<String, dynamic>> results = vereine;
                        return StatefulBuilder(builder: (sCtx, setS) => AlertDialog(
                          title: Row(children: [Icon(Icons.groups, size: 18, color: Colors.indigo.shade700), const SizedBox(width: 8), const Text('Verein auswählen', style: TextStyle(fontSize: 14))]),
                          content: SizedBox(width: 450, height: 400, child: Column(children: [
                            TextField(autofocus: true, decoration: InputDecoration(hintText: 'Suchen...', prefixIcon: const Icon(Icons.search, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                              onChanged: (v) => setS(() { search = v.toLowerCase(); results = vereine.where((s) => (s['name']?.toString() ?? '').toLowerCase().contains(search) || (s['plz_ort']?.toString() ?? '').toLowerCase().contains(search)).toList(); })),
                            const SizedBox(height: 8),
                            Expanded(child: results.isEmpty ? Center(child: Text('Keine Ergebnisse', style: TextStyle(color: Colors.grey.shade500)))
                              : ListView.builder(itemCount: results.length, itemBuilder: (_, i) {
                                  final v = results[i];
                                  return ListTile(dense: true, leading: Icon(Icons.groups, size: 18, color: Colors.indigo.shade400),
                                    title: Text(v['name']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                    subtitle: Text([v['typ'], v['plz_ort']].where((x) => x != null && x.toString().isNotEmpty).join(' · '), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                    onTap: () => Navigator.pop(sCtx, v));
                                })),
                          ])),
                          actions: [TextButton(onPressed: () => Navigator.pop(sCtx), child: const Text('Abbrechen'))],
                        ));
                      });
                      if (sel != null) setD(() { anbieterC.text = sel['name']?.toString() ?? ''; if ((sel['telefon']?.toString() ?? '').isNotEmpty && telC.text.isEmpty) telC.text = sel['telefon'].toString(); if ((sel['email']?.toString() ?? '').isNotEmpty && emailC.text.isEmpty) emailC.text = sel['email'].toString(); });
                    })))
              else if (vorschlaege.isNotEmpty)
                Autocomplete<String>(
                  initialValue: anbieterC.value,
                  optionsBuilder: (v) => v.text.isEmpty ? vorschlaege : vorschlaege.where((a) => a.toLowerCase().contains(v.text.toLowerCase())),
                  fieldViewBuilder: (_, c, fn, __) {
                    if (c.text.isEmpty && anbieterC.text.isNotEmpty) c.text = anbieterC.text;
                    return TextField(controller: c, focusNode: fn, decoration: InputDecoration(labelText: 'Anbieter *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onChanged: (v) { anbieterC.text = v; setD(() { tarifC.clear(); kostenC.clear(); }); });
                  },
                  onSelected: (v) => setD(() { anbieterC.text = v; tarifC.clear(); kostenC.clear(); }),
                )
              else
                TextField(controller: anbieterC, decoration: InputDecoration(labelText: 'Anbieter *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
              const SizedBox(height: 8),
              // Tarif: dropdown if known provider, free-text otherwise
              if (hasTarife)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(8)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: tarife.any((t) => t.$1 == tarifC.text) ? tarifC.text : null,
                      hint: const Text('Tarif wählen', style: TextStyle(fontSize: 13)),
                      isExpanded: true,
                      items: tarife.map((t) => DropdownMenuItem(value: t.$1, child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(t.$1, style: const TextStyle(fontSize: 13)),
                          Text('${t.$2.toStringAsFixed(2)} €', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
                        ],
                      ))).toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        final preis = tarife.firstWhere((t) => t.$1 == v).$2;
                        setD(() { tarifC.text = v; kostenC.text = preis.toStringAsFixed(2); });
                      },
                    ),
                  ),
                )
              else
                TextField(controller: tarifC, decoration: InputDecoration(labelText: isVerein ? 'Art der Mitgliedschaft' : 'Tarif / Paket', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(
                  controller: kostenC,
                  readOnly: kostenReadonly,
                  keyboardType: TextInputType.number,
                  style: TextStyle(fontSize: 14, color: kostenReadonly ? Colors.green.shade800 : null, fontWeight: kostenReadonly ? FontWeight.bold : null),
                  decoration: InputDecoration(
                    labelText: isVerein ? 'Mitgliedsbeitrag €/Jahr' : 'Kosten €/Monat',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    filled: kostenReadonly,
                    fillColor: kostenReadonly ? Colors.green.shade50 : null,
                    suffixIcon: kostenReadonly ? Icon(Icons.lock, size: 16, color: Colors.green.shade700) : null,
                  ),
                )),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: beginnC, readOnly: true, decoration: InputDecoration(labelText: 'Vertragsbeginn', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onTap: () async {
                  final p = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2010), lastDate: DateTime(2040), locale: const Locale('de'));
                  if (p != null) setD(() => beginnC.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}');
                })),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(controller: laufzeitC, decoration: InputDecoration(labelText: 'Mindestlaufzeit', hintText: 'z.B. 24 Monate', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: fristC, decoration: InputDecoration(labelText: 'Kündigungsfrist', hintText: 'z.B. 1 Monat', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
              ]),
              if (selKat == 'handy') ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(controller: telC, decoration: InputDecoration(labelText: 'Telefonnummer', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: volumenC, decoration: InputDecoration(labelText: 'Datenvolumen', hintText: 'z.B. 20 GB', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
                ]),
              ],
              if (selKat == 'multimedia') ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(controller: emailC, decoration: InputDecoration(labelText: 'Login-E-Mail', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
                  const SizedBox(width: 8),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Checkbox(value: shared, onChanged: (v) => setD(() => shared = v ?? false)),
                    const Text('Geteiltes Konto', style: TextStyle(fontSize: 12)),
                  ]),
                ]),
              ],
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(controller: gekuendigtC, readOnly: true, decoration: InputDecoration(labelText: 'Gekündigt am', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onTap: () async {
                  final p = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2010), lastDate: DateTime(2040), locale: const Locale('de'));
                  if (p != null) setD(() => gekuendigtC.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}');
                })),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: endeC, readOnly: true, decoration: InputDecoration(labelText: 'Vertragsende', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onTap: () async {
                  final p = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2010), lastDate: DateTime(2040), locale: const Locale('de'));
                  if (p != null) setD(() => endeC.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}');
                })),
              ]),
              const SizedBox(height: 8),
              TextField(controller: notizenC, maxLines: 2, decoration: InputDecoration(labelText: 'Notizen', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
              const SizedBox(height: 8),
              Row(children: [
                Switch(value: aktiv, onChanged: (v) => setD(() => aktiv = v)),
                Text(aktiv ? 'Aktiv' : 'Beendet', style: TextStyle(fontSize: 12, color: aktiv ? Colors.green : Colors.grey)),
              ]),
            ])),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            FilledButton(
              onPressed: () async {
                if (anbieterC.text.trim().isEmpty) return;
                await widget.apiService.saveVertrag(widget.userId, {
                  if (existing != null) 'id': existing['id'],
                  'kategorie': selKat,
                  'anbieter': anbieterC.text.trim(),
                  'tarif': tarifC.text.trim(),
                  'monatliche_kosten': double.tryParse(kostenC.text.trim()),
                  'vertragsbeginn': beginnC.text.trim(),
                  'mindestlaufzeit': laufzeitC.text.trim(),
                  'kuendigungsfrist': fristC.text.trim(),
                  'gekuendigt_am': gekuendigtC.text.trim(),
                  'vertragsende': endeC.text.trim(),
                  'telefonnummer': telC.text.trim(),
                  'datenvolumen': volumenC.text.trim(),
                  'login_email': emailC.text.trim(),
                  'shared_account': shared,
                  'notizen': notizenC.text.trim(),
                  'is_active': aktiv,
                });
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              },
              child: Text(existing != null ? 'Speichern' : 'Hinzufügen'),
            ),
          ],
        );
      }),
    );
  }

  // ═══════════════════════════════════════════════════════
  // DETAIL MODAL (Details readonly + Korrespondenz)
  // ═══════════════════════════════════════════════════════
  void _showVertragDetailModal(Map<String, dynamic> v) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: SizedBox(
          width: double.infinity, height: MediaQuery.of(context).size.height * 0.85,
          child: _VertragDetailView(
            apiService: widget.apiService,
            vertrag: v,
            onEdit: () {
              Navigator.pop(ctx);
              _showVertragDialog(existing: v);
            },
            onChanged: () => _load(),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// Inner detail view with 2 tabs
// ═══════════════════════════════════════════════════════
class _VertragDetailView extends StatefulWidget {
  final ApiService apiService;
  final Map<String, dynamic> vertrag;
  final VoidCallback onEdit;
  final VoidCallback onChanged;
  const _VertragDetailView({required this.apiService, required this.vertrag, required this.onEdit, required this.onChanged});

  @override
  State<_VertragDetailView> createState() => _VertragDetailViewState();
}

class _VertragDetailViewState extends State<_VertragDetailView> {
  @override
  Widget build(BuildContext context) {
    final v = widget.vertrag;
    final kosten = double.tryParse(v['monatliche_kosten']?.toString() ?? '') ?? 0;
    final aktiv = v['is_active'] == 1 || v['is_active'] == true || v['is_active'] == '1';
    return DefaultTabController(
      length: 6,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: aktiv ? Colors.indigo.shade700 : Colors.grey.shade600,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          ),
          child: Row(children: [
            Icon(Icons.receipt, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v['anbieter']?.toString() ?? '', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              if ((v['tarif']?.toString() ?? '').isNotEmpty)
                Text(v['tarif'].toString(), style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ])),
            if (kosten > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)),
                child: Text('${kosten.toStringAsFixed(2)} €/Mt.', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              ),
            const SizedBox(width: 8),
            IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
          ]),
        ),
        TabBar(
          isScrollable: true,
          labelColor: Colors.indigo.shade700,
          indicatorColor: Colors.indigo.shade700,
          tabs: const [
            Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Details'),
            Tab(icon: Icon(Icons.mail, size: 18), text: 'Korrespondenz'),
            Tab(icon: Icon(Icons.folder, size: 18), text: 'Dokumente'),
            Tab(icon: Icon(Icons.receipt, size: 18), text: 'Rechnung'),
            Tab(icon: Icon(Icons.cancel, size: 18), text: 'Kündigung'),
            Tab(icon: Icon(Icons.gavel, size: 18), text: 'Inkasso'),
          ],
        ),
        Expanded(child: TabBarView(children: [
          _buildDetailsTab(v, aktiv),
          _KorrTab(apiService: widget.apiService, vertragId: int.tryParse(v['id']?.toString() ?? '') ?? 0),
          _DokSubTabs(apiService: widget.apiService, vertragId: int.tryParse(v['id']?.toString() ?? '') ?? 0),
          _DokTab(apiService: widget.apiService, vertragId: int.tryParse(v['id']?.toString() ?? '') ?? 0, kategorie: 'rechnung', label: 'Rechnungen'),
          _DokTab(apiService: widget.apiService, vertragId: int.tryParse(v['id']?.toString() ?? '') ?? 0, kategorie: 'kuendigung', label: 'Kündigung'),
          _InkassoTab(apiService: widget.apiService, vertragId: int.tryParse(v['id']?.toString() ?? '') ?? 0),
        ])),
      ]),
    );
  }

  Widget _buildDetailsTab(Map<String, dynamic> v, bool aktiv) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Vertragsdaten', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
          const Spacer(),
          OutlinedButton.icon(
            icon: const Icon(Icons.edit, size: 16),
            label: const Text('Bearbeiten', style: TextStyle(fontSize: 12)),
            onPressed: widget.onEdit,
          ),
        ]),
        const Divider(height: 20),
        _row(Icons.business, 'Anbieter', v['anbieter']),
        _row(Icons.label, 'Tarif', v['tarif']),
        _row(Icons.euro, 'Kosten/Monat', v['monatliche_kosten'] != null ? '${double.tryParse(v['monatliche_kosten'].toString())?.toStringAsFixed(2)} €' : null),
        _row(Icons.calendar_today, 'Vertragsbeginn', v['vertragsbeginn']),
        _row(Icons.timer, 'Mindestlaufzeit', v['mindestlaufzeit']),
        _row(Icons.exit_to_app, 'Kündigungsfrist', v['kuendigungsfrist']),
        _row(Icons.event_busy, 'Gekündigt am', v['gekuendigt_am']),
        _row(Icons.event, 'Vertragsende', v['vertragsende']),
        if ((v['telefonnummer']?.toString() ?? '').isNotEmpty)
          _row(Icons.phone, 'Telefonnummer', v['telefonnummer']),
        if ((v['datenvolumen']?.toString() ?? '').isNotEmpty)
          _row(Icons.data_usage, 'Datenvolumen', v['datenvolumen']),
        if ((v['login_email']?.toString() ?? '').isNotEmpty)
          _row(Icons.email, 'Login-E-Mail', v['login_email']),
        if (v['shared_account'] == 1 || v['shared_account'] == true)
          _row(Icons.people, 'Geteiltes Konto', 'Ja'),
        if ((v['notizen']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.yellow.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.yellow.shade200)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.note, size: 14, color: Colors.orange.shade700),
              const SizedBox(width: 6),
              Expanded(child: Text(v['notizen'].toString(), style: const TextStyle(fontSize: 12))),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: aktiv ? Colors.green.shade50 : Colors.red.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: aktiv ? Colors.green.shade200 : Colors.red.shade200),
          ),
          child: Row(children: [
            Icon(aktiv ? Icons.check_circle : Icons.cancel, size: 16, color: aktiv ? Colors.green.shade700 : Colors.red.shade700),
            const SizedBox(width: 6),
            Text(aktiv ? 'Vertrag aktiv' : 'Vertrag beendet', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: aktiv ? Colors.green.shade800 : Colors.red.shade800)),
          ]),
        ),
      ]),
    );
  }

  Widget _row(IconData icon, String label, dynamic value) {
    final s = value?.toString() ?? '';
    if (s.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        SizedBox(width: 120, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600))),
        Expanded(child: Text(s, style: const TextStyle(fontSize: 13))),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════
// KORRESPONDENZ TAB
// ═══════════════════════════════════════════════════════
class _KorrTab extends StatefulWidget {
  final ApiService apiService;
  final int vertragId;
  const _KorrTab({required this.apiService, required this.vertragId});

  @override
  State<_KorrTab> createState() => _KorrTabState();
}

class _KorrTabState extends State<_KorrTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.apiService.listVertraegeKorrespondenz(widget.vertragId);
    if (!mounted) return;
    setState(() {
      _items = (r['success'] == true && r['data'] is List) ? (r['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList() : [];
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(child: Text('${_items.length} Einträge', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
          FilledButton.icon(
            icon: const Icon(Icons.call_received, size: 14),
            label: const Text('Eingang', style: TextStyle(fontSize: 11)),
            style: FilledButton.styleFrom(backgroundColor: Colors.green.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
            onPressed: () => _showKorrDialog('eingang'),
          ),
          const SizedBox(width: 6),
          FilledButton.icon(
            icon: const Icon(Icons.call_made, size: 14),
            label: const Text('Ausgang', style: TextStyle(fontSize: 11)),
            style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
            onPressed: () => _showKorrDialog('ausgang'),
          ),
        ]),
      ),
      Expanded(
        child: _items.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.mail_outline, size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 6),
                Text('Keine Korrespondenz', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ]))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _items.length,
                itemBuilder: (_, i) {
                  final k = _items[i];
                  final isEin = k['richtung'] == 'eingang';
                  return InkWell(
                    onTap: () => _showKorrDetail(k),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white, borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isEin ? Colors.green.shade200 : Colors.blue.shade200),
                      ),
                      child: Row(children: [
                        Icon(isEin ? Icons.call_received : Icons.call_made, size: 18, color: isEin ? Colors.green.shade700 : Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(k['betreff']?.toString() ?? 'Ohne Betreff', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isEin ? Colors.green.shade800 : Colors.blue.shade800)),
                          Text(k['datum']?.toString() ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                          if ((k['notiz']?.toString() ?? '').isNotEmpty)
                            Text(k['notiz'].toString(), style: TextStyle(fontSize: 10, color: Colors.grey.shade700, fontStyle: FontStyle.italic), maxLines: 2, overflow: TextOverflow.ellipsis),
                        ])),
                        Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
                      ]),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  void _showKorrDetail(Map<String, dynamic> k) {
    final isEin = k['richtung'] == 'eingang';
    final color = isEin ? Colors.green : Colors.blue;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(children: [
          Icon(isEin ? Icons.call_received : Icons.call_made, color: color.shade700),
          const SizedBox(width: 8),
          Expanded(child: Text(
            k['betreff']?.toString() ?? 'Ohne Betreff',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color.shade800),
          )),
        ]),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: color.shade200)),
              child: Row(children: [
                Icon(isEin ? Icons.inbox : Icons.send, size: 14, color: color.shade700),
                const SizedBox(width: 6),
                Text(isEin ? 'Eingang (empfangen)' : 'Ausgang (gesendet)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color.shade800)),
                const Spacer(),
                Icon(Icons.calendar_today, size: 12, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(k['datum']?.toString() ?? '', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              ]),
            ),
            const SizedBox(height: 16),
            Text('Betreff', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Text(k['betreff']?.toString() ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Text('Inhalt / Notiz', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              constraints: const BoxConstraints(minHeight: 120),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: SelectableText(
                (k['notiz']?.toString() ?? '').isEmpty ? '(kein Inhalt)' : k['notiz'].toString(),
                style: TextStyle(fontSize: 13, height: 1.5, color: (k['notiz']?.toString() ?? '').isEmpty ? Colors.grey.shade400 : Colors.black87),
              ),
            ),
          ])),
        ),
        actions: [
          TextButton.icon(
            icon: Icon(Icons.delete, size: 16, color: Colors.red.shade400),
            label: Text('Löschen', style: TextStyle(color: Colors.red.shade400)),
            onPressed: () async {
              await widget.apiService.deleteVertraegeKorrespondenz(k['id'] as int);
              if (ctx.mounted) Navigator.pop(ctx);
              _load();
            },
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen')),
        ],
      ),
    );
  }

  void _showKorrDialog(String richtung) {
    final betreffC = TextEditingController();
    final notizC = TextEditingController();
    final datumC = TextEditingController(text: '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(richtung == 'eingang' ? 'E-Mail Eingang' : 'E-Mail Ausgang'),
        content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: datumC, decoration: const InputDecoration(labelText: 'Datum', isDense: true, border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: betreffC, decoration: const InputDecoration(labelText: 'Betreff', isDense: true, border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: notizC, maxLines: 3, decoration: const InputDecoration(labelText: 'Notiz / Inhalt', isDense: true, border: OutlineInputBorder())),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(onPressed: () async {
            await widget.apiService.saveVertraegeKorrespondenz({
              'vertrag_id': widget.vertragId,
              'richtung': richtung,
              'datum': datumC.text.trim(),
              'betreff': betreffC.text.trim(),
              'notiz': notizC.text.trim(),
            });
            if (ctx.mounted) Navigator.pop(ctx);
            _load();
          }, child: const Text('Speichern')),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// DOKUMENTE / RECHNUNG / KÜNDIGUNG TAB (unified)
// ═══════════════════════════════════════════════════════
// ==================== DOKUMENTE SUB-TABS ====================
class _DokSubTabs extends StatefulWidget {
  final ApiService apiService;
  final int vertragId;
  const _DokSubTabs({required this.apiService, required this.vertragId});
  @override
  State<_DokSubTabs> createState() => _DokSubTabsState();
}
class _DokSubTabsState extends State<_DokSubTabs> with TickerProviderStateMixin {
  late TabController _tabC;
  static const _tabs = [
    ('vertrag', 'Vertrag'),
    ('agb', 'AGB'),
    ('leistungsbeschreibung', 'Leistungsbeschreibung'),
    ('preise', 'Preise'),
    ('datenschutz', 'Datenschutz'),
    ('widerrufsbelehrung', 'Widerrufsbelehrung'),
    ('elektrogesetz', 'Elektrogesetz'),
  ];
  final Map<String, bool> _hasDocs = {};

  @override
  void initState() { super.initState(); _tabC = TabController(length: _tabs.length, vsync: this); _loadCounts(); }
  @override
  void dispose() { _tabC.dispose(); super.dispose(); }

  Future<void> _loadCounts() async {
    for (final t in _tabs) {
      try {
        final res = await widget.apiService.listVertragDokumente(widget.vertragId, kategorie: t.$1);
        if (res['success'] == true && res['data'] is List && (res['data'] as List).isNotEmpty) {
          if (mounted) setState(() => _hasDocs[t.$1] = true);
        }
      } catch (_) {}
    }
  }

  Widget _tabLabel(String kategorie, String label) {
    final has = _hasDocs[kategorie] == true;
    return Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label),
      if (has) ...[const SizedBox(width: 4), Icon(Icons.check_circle, size: 14, color: Colors.green.shade600)],
    ]));
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TabBar(controller: _tabC, isScrollable: true, tabAlignment: TabAlignment.start, labelColor: Colors.indigo.shade700, unselectedLabelColor: Colors.grey, indicatorColor: Colors.indigo.shade600,
        labelStyle: const TextStyle(fontSize: 11), tabs: _tabs.map((t) => _tabLabel(t.$1, t.$2)).toList()),
      Expanded(child: TabBarView(controller: _tabC, children: _tabs.map((t) =>
        _DokTab(apiService: widget.apiService, vertragId: widget.vertragId, kategorie: t.$1, label: t.$2, onChanged: () { _loadCounts(); }),
      ).toList())),
    ]);
  }
}

class _DokTab extends StatefulWidget {
  final ApiService apiService;
  final int vertragId;
  final String kategorie;
  final String label;
  final VoidCallback? onChanged;
  const _DokTab({required this.apiService, required this.vertragId, required this.kategorie, required this.label, this.onChanged});

  @override
  State<_DokTab> createState() => _DokTabState();
}

class _DokTabState extends State<_DokTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loaded = false;

  static const _kuendigungSchritte = [
    ('eingereicht', 'Kündigung eingereicht', Icons.send, Colors.red, 'Kündigung an den Anbieter abgeschickt.'),
    ('warte_14', '14 Tage warten', Icons.hourglass_top, Colors.orange, 'Anbieter muss bei Online-Kündigung sofort bestätigen, sonst max. 14 Tage warten.'),
    ('bestaetigung', 'Bestätigung erhalten', Icons.check_circle, Colors.green, 'Kündigungsbestätigung mit Vertragsende-Datum erhalten.'),
    ('mahnung', 'Mahnung / Erinnerung', Icons.warning, Colors.deepOrange, 'Keine Bestätigung? Per Einschreiben mit Rückschein erneut kündigen + Frist setzen (7 Tage).'),
    ('beschwerde', 'Beschwerde', Icons.gavel, Colors.purple, 'Keine Reaktion? Beschwerde bei Bundesnetzagentur oder Verbraucherzentrale einreichen.'),
    ('vertragsende', 'Vertrag beendet', Icons.event_available, Colors.teal, 'Vertrag ist offiziell beendet. SIM-Karte zurückgeben falls verlangt.'),
    ('rufnummer', 'Rufnummernmitnahme (optional)', Icons.phone_forwarded, Colors.blue, 'Optional: Rufnummer zum neuen Anbieter mitnehmen (kostenlos per TKG, bis 1 Monat nach Vertragsende). Nur wenn gewünscht.'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.apiService.listVertragDokumente(widget.vertragId, kategorie: widget.kategorie);
    if (!mounted) return;
    setState(() {
      _items = (r['success'] == true && r['data'] is List) ? (r['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList() : [];
      _loaded = true;
    });
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    if (widget.kategorie == 'kuendigung') return _buildKuendigungTimeline();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(child: Text('${_items.length} ${widget.label}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
          FilledButton.icon(
            icon: const Icon(Icons.upload_file, size: 14),
            label: Text('${widget.label} hochladen', style: const TextStyle(fontSize: 11)),
            style: FilledButton.styleFrom(backgroundColor: Colors.indigo.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
            onPressed: () => _uploadDialog(),
          ),
        ]),
      ),
      Expanded(
        child: _items.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.folder_open, size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 6),
                Text('Keine ${widget.label}', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ]))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _items.length,
                itemBuilder: (_, i) {
                  final d = _items[i];
                  return Card(
                    child: ListTile(
                      leading: Icon(_iconForKat(), color: Colors.indigo.shade600),
                      title: Text(d['titel']?.toString().isNotEmpty == true ? d['titel'].toString() : d['datei_name']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (widget.kategorie == 'rechnung') ...[
                          if ((d['rechnungsnummer']?.toString() ?? '').isNotEmpty)
                            Text('Nr: ${d['rechnungsnummer']}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontFamily: 'monospace')),
                          if ((d['abrechnungszeitraum']?.toString() ?? '').isNotEmpty)
                            Text('Zeitraum: ${d['abrechnungszeitraum']}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          if (d['betrag'] != null)
                            Text('${double.tryParse(d['betrag'].toString())?.toStringAsFixed(2)} €', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
                        ],
                        if (widget.kategorie == 'kuendigung') ...[
                          if ((d['kuendigung_datum']?.toString() ?? '').isNotEmpty)
                            Text('Gekündigt am: ${d['kuendigung_datum']}', style: TextStyle(fontSize: 11, color: Colors.red.shade600)),
                          if ((d['kuendigung_grund']?.toString() ?? '').isNotEmpty)
                            Row(children: [
                              Icon(_wegIcon(d['kuendigung_grund'].toString()), size: 12, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Text('per ${_wegLabel(d['kuendigung_grund'].toString())}', style: TextStyle(fontSize: 10, color: Colors.grey.shade700)),
                            ]),
                          Row(children: [
                            Icon(d['kuendigung_bestaetigt'] == 1 ? Icons.check_circle : Icons.hourglass_top, size: 12, color: d['kuendigung_bestaetigt'] == 1 ? Colors.green : Colors.orange),
                            const SizedBox(width: 4),
                            Text(d['kuendigung_bestaetigt'] == 1 ? 'Bestätigt${d['kuendigung_bestaetigungs_datum'] != null ? ' am ${d['kuendigung_bestaetigungs_datum']}' : ''}' : 'Ausstehend', style: TextStyle(fontSize: 10, color: d['kuendigung_bestaetigt'] == 1 ? Colors.green.shade700 : Colors.orange.shade700)),
                          ]),
                          if (d['rufnummernmitnahme'] == 1)
                            Row(children: [
                              Icon(Icons.phone_forwarded, size: 12, color: Colors.blue.shade600),
                              const SizedBox(width: 4),
                              Text('Rufnummernmitnahme beantragt', style: TextStyle(fontSize: 10, color: Colors.blue.shade700)),
                            ]),
                        ],
                        if ((d['notiz']?.toString() ?? '').isNotEmpty)
                          Text(d['notiz'].toString(), style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontStyle: FontStyle.italic), maxLines: 2, overflow: TextOverflow.ellipsis),
                      ]),
                      isThreeLine: true,
                      onTap: () => _viewDoc(d),
                      trailing: IconButton(
                        icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                        onPressed: () async {
                          await widget.apiService.deleteVertragDokument(d['id'] as int);
                          _load();
                        },
                      ),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  Widget _buildKuendigungTimeline() {
    Map<String, Map<String, dynamic>> erledigte = {};
    for (final item in _items) {
      final schritt = item['rechnungsnummer']?.toString() ?? '';
      if (schritt.isNotEmpty) erledigte[schritt] = item;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.timeline, size: 20, color: Colors.red.shade700),
          const SizedBox(width: 8),
          Text('Kündigungs-Chronologie', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
        ]),
        const SizedBox(height: 16),
        for (int i = 0; i < _kuendigungSchritte.length; i++) ...[
          Builder(builder: (_) {
            final s = _kuendigungSchritte[i];
            final key = s.$1;
            final done = erledigte.containsKey(key);
            final entry = erledigte[key];
            final isLast = i == _kuendigungSchritte.length - 1;
            final color = done ? s.$4 : Colors.grey;
            return IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 32, child: Column(children: [
                  Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done ? color.shade100 : Colors.grey.shade200,
                      border: Border.all(color: done ? color.shade700 : Colors.grey.shade400, width: 2),
                    ),
                    child: Icon(done ? Icons.check : s.$3, size: 14, color: done ? color.shade700 : Colors.grey.shade500),
                  ),
                  if (!isLast) Expanded(child: Container(width: 2, color: done ? color.shade300 : Colors.grey.shade300)),
                ])),
                const SizedBox(width: 12),
                Expanded(child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: done ? color.shade50 : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: done ? color.shade300 : Colors.grey.shade300),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(s.$3, size: 16, color: done ? color.shade700 : Colors.grey.shade500),
                      const SizedBox(width: 6),
                      Expanded(child: Text(s.$2, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: done ? color.shade900 : Colors.grey.shade600))),
                      if (done && entry != null)
                        Text(entry['kuendigung_datum']?.toString() ?? entry['erstellt_am']?.toString().substring(0, 10) ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade600))
                      else if (!done)
                        InkWell(
                          onTap: () => _addKuendigungSchritt(key, s.$2),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: s.$4.shade100, borderRadius: BorderRadius.circular(6)),
                            child: Text('Erledigt', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: s.$4.shade800)),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 4),
                    Text(s.$5, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
                    if (done && entry != null) ...[
                      if ((entry['notiz']?.toString() ?? '').isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity, padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                          child: Text(entry['notiz'].toString(), style: const TextStyle(fontSize: 12)),
                        ),
                      ],
                      if ((entry['datei_name']?.toString() ?? '').isNotEmpty) ...[
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () => _viewDoc(entry),
                          child: Row(children: [
                            Icon(Icons.attach_file, size: 12, color: Colors.indigo.shade600),
                            const SizedBox(width: 4),
                            Text(entry['datei_name'].toString(), style: TextStyle(fontSize: 10, color: Colors.indigo.shade700, decoration: TextDecoration.underline)),
                          ]),
                        ),
                      ],
                    ],
                  ]),
                )),
              ]),
            );
          }),
        ],
      ]),
    );
  }

  Future<void> _addKuendigungSchritt(String schrittKey, String schrittLabel) async {
    final datumC = TextEditingController(text: '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}');
    final notizC = TextEditingController();
    String? filePath;
    String? fileName;
    bool uploading = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) => AlertDialog(
        title: Text(schrittLabel),
        content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', prefixIcon: const Icon(Icons.calendar_today, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onTap: () async {
            final p = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
            if (p != null) setD(() => datumC.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}');
          }),
          const SizedBox(height: 8),
          TextField(controller: notizC, maxLines: 3, decoration: InputDecoration(labelText: 'Notiz / Details', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 8),
          InkWell(
            onTap: () async {
              final r = await FilePickerHelper.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
              if (r != null && r.files.isNotEmpty && r.files.first.path != null) {
                setD(() { filePath = r.files.first.path; fileName = r.files.first.name; });
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: double.infinity, padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: filePath != null ? Colors.green.shade50 : Colors.grey.shade100, borderRadius: BorderRadius.circular(8), border: Border.all(color: filePath != null ? Colors.green.shade300 : Colors.grey.shade300)),
              child: Row(children: [
                Icon(filePath != null ? Icons.check_circle : Icons.attach_file, size: 18, color: filePath != null ? Colors.green.shade700 : Colors.grey.shade500),
                const SizedBox(width: 8),
                Expanded(child: Text(fileName ?? 'Dokument anhängen (optional)', style: TextStyle(fontSize: 12, color: filePath != null ? Colors.green.shade900 : Colors.grey.shade600))),
              ]),
            ),
          ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton.icon(
            icon: uploading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check, size: 16),
            label: Text(uploading ? 'Speichern...' : 'Erledigt markieren'),
            onPressed: uploading ? null : () async {
              setD(() => uploading = true);
              if (filePath != null) {
                await widget.apiService.uploadVertragDokument(
                  vertragId: widget.vertragId, kategorie: 'kuendigung',
                  filePath: filePath!, fileName: fileName!,
                  rechnungsnummer: schrittKey,
                  kuendigungDatum: datumC.text.trim(),
                  notiz: notizC.text.trim(),
                );
              } else {
                await widget.apiService.uploadVertragDokument(
                  vertragId: widget.vertragId, kategorie: 'kuendigung',
                  filePath: '', fileName: '',
                  rechnungsnummer: schrittKey,
                  kuendigungDatum: datumC.text.trim(),
                  notiz: notizC.text.trim(),
                );
              }
              if (ctx.mounted) Navigator.pop(ctx);
              _load();
            },
          ),
        ],
      )),
    );
  }

  IconData _iconForKat() => switch (widget.kategorie) { 'rechnung' => Icons.receipt, 'kuendigung' => Icons.cancel, _ => Icons.description };

  static IconData _wegIcon(String weg) => switch (weg) { 'online' => Icons.language, 'email' => Icons.email, 'postalisch' => Icons.local_post_office, 'persoenlich' => Icons.person, 'fax' => Icons.fax, _ => Icons.send };
  static String _wegLabel(String weg) => switch (weg) { 'online' => 'Online / Kündigungsbutton', 'email' => 'E-Mail', 'postalisch' => 'Post (Brief)', 'persoenlich' => 'Persönlich (Shop)', 'fax' => 'Fax', _ => weg };

  Future<void> _viewDoc(Map<String, dynamic> d) async {
    try {
      final resp = await widget.apiService.downloadVertragDokument(d['id'] as int);
      if (resp.statusCode == 200 && mounted) {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/${d['datei_name'] ?? 'dokument.pdf'}');
        await file.writeAsBytes(resp.bodyBytes);
        if (mounted) await FileViewerDialog.show(context, file.path, d['datei_name']?.toString() ?? '');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _uploadDialog() async {
    final titelC = TextEditingController();
    final notizC = TextEditingController();
    // Multi-file: same metadata (Rechnungsnr, Zeitraum, Betrag, etc.)
    // applied to every selected file. One POST per file — server stores
    // each as its own dokument row.
    final selectedFiles = <PlatformFile>[];
    bool uploading = false;
    int uploadProgressDone = 0;
    int uploadProgressTotal = 0;
    // Rechnung fields
    final rechnungNrC = TextEditingController();
    final zeitraumC = TextEditingController();
    final betragC = TextEditingController();
    // Kündigung fields
    final kundDatumC = TextEditingController();
    final bestDatumC = TextEditingController();
    bool bestaetigt = false;
    bool rufnummer = false;
    final grundC = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('${widget.label} hochladen'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: titelC, decoration: InputDecoration(labelText: 'Titel / Bezeichnung', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
            const SizedBox(height: 8),
            if (widget.kategorie == 'rechnung') ...[
              TextField(controller: rechnungNrC, decoration: InputDecoration(labelText: 'Rechnungsnummer', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
              const SizedBox(height: 8),
              TextField(controller: zeitraumC, decoration: InputDecoration(labelText: 'Abrechnungszeitraum (z.B. 01.03.–31.03.2026)', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
              const SizedBox(height: 8),
              TextField(controller: betragC, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Betrag €', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
              const SizedBox(height: 8),
            ],
            if (widget.kategorie == 'kuendigung') ...[
              TextField(controller: kundDatumC, readOnly: true, decoration: InputDecoration(labelText: 'Kündigungsdatum *', prefixIcon: const Icon(Icons.calendar_today, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onTap: () async {
                final p = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
                if (p != null) setD(() => kundDatumC.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}');
              }),
              const SizedBox(height: 8),
              Text('Kündigung erfolgt per:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final m in [('online', 'Online / Kündigungsbutton', Icons.language), ('email', 'Per E-Mail', Icons.email), ('postalisch', 'Postalisch (Brief)', Icons.local_post_office), ('persoenlich', 'Persönlich (im Shop)', Icons.person), ('fax', 'Per Fax', Icons.fax)])
                  ChoiceChip(
                    avatar: Icon(m.$3, size: 14, color: grundC.text == m.$1 ? Colors.white : Colors.grey.shade700),
                    label: Text(m.$2, style: TextStyle(fontSize: 10, color: grundC.text == m.$1 ? Colors.white : Colors.black87)),
                    selected: grundC.text == m.$1,
                    selectedColor: Colors.red.shade600,
                    onSelected: (_) => setD(() => grundC.text = m.$1),
                  ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Checkbox(value: bestaetigt, onChanged: (v) => setD(() => bestaetigt = v ?? false)),
                const Text('Kündigung bestätigt', style: TextStyle(fontSize: 12)),
              ]),
              if (bestaetigt) ...[
                TextField(controller: bestDatumC, readOnly: true, decoration: InputDecoration(labelText: 'Bestätigungsdatum', prefixIcon: const Icon(Icons.check_circle, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onTap: () async {
                  final p = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
                  if (p != null) setD(() => bestDatumC.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}');
                }),
                const SizedBox(height: 8),
              ],
              Row(children: [
                Checkbox(value: rufnummer, onChanged: (v) => setD(() => rufnummer = v ?? false)),
                const Text('Rufnummernmitnahme beantragt', style: TextStyle(fontSize: 12)),
              ]),
              TextField(controller: grundC, maxLines: 2, decoration: InputDecoration(labelText: 'Kündigungsgrund', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
              const SizedBox(height: 8),
            ],
            TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
            const SizedBox(height: 8),
            InkWell(
              onTap: uploading ? null : () async {
                final r = await FilePickerHelper.pickFiles(
                  allowMultiple: true,
                  type: FileType.custom,
                  allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
                );
                if (r != null && r.files.isNotEmpty) {
                  setD(() {
                    for (final f in r.files) {
                      if (f.path == null) continue;
                      if (selectedFiles.any((s) => s.path == f.path)) continue;
                      selectedFiles.add(f);
                    }
                  });
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity, padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: selectedFiles.isNotEmpty ? Colors.green.shade50 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: selectedFiles.isNotEmpty ? Colors.green.shade300 : Colors.grey.shade300),
                ),
                child: Row(children: [
                  Icon(selectedFiles.isNotEmpty ? Icons.check_circle : Icons.upload_file,
                    size: 22, color: selectedFiles.isNotEmpty ? Colors.green.shade700 : Colors.grey.shade500),
                  const SizedBox(width: 10),
                  Expanded(child: Text(
                    selectedFiles.isEmpty
                        ? 'Datei(en) auswählen * — Mehrfachauswahl möglich'
                        : '${selectedFiles.length} Datei(en) ausgewählt — klicken zum Hinzufügen',
                    style: TextStyle(fontSize: 13, color: selectedFiles.isNotEmpty ? Colors.green.shade900 : Colors.grey.shade600),
                  )),
                ]),
              ),
            ),
            if (selectedFiles.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...selectedFiles.asMap().entries.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Icon(Icons.insert_drive_file, size: 16, color: Colors.indigo.shade400),
                  const SizedBox(width: 6),
                  Expanded(child: Text(e.value.name, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
                  Text(
                    '${(e.value.size / 1024).toStringAsFixed(0)} KB',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 16, color: Colors.red.shade400),
                    onPressed: uploading ? null : () => setD(() => selectedFiles.removeAt(e.key)),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                ]),
              )),
            ],
          ])),
        ),
        actions: [
          TextButton(onPressed: uploading ? null : () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton.icon(
            icon: uploading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.upload_file, size: 16),
            label: Text(uploading
                ? (uploadProgressTotal > 0 ? '$uploadProgressDone / $uploadProgressTotal …' : 'Wird hochgeladen...')
                : (selectedFiles.length > 1 ? 'Alle ${selectedFiles.length} hochladen' : 'Hochladen')),
            onPressed: (selectedFiles.isEmpty || uploading) ? null : () async {
              setD(() {
                uploading = true;
                uploadProgressTotal = selectedFiles.length;
                uploadProgressDone = 0;
              });
              final errors = <String>[];
              for (final f in selectedFiles) {
                final res = await widget.apiService.uploadVertragDokument(
                  vertragId: widget.vertragId,
                  kategorie: widget.kategorie,
                  filePath: f.path!,
                  fileName: f.name,
                  titel: titelC.text.trim(),
                  rechnungsnummer: rechnungNrC.text.trim(),
                  abrechnungszeitraum: zeitraumC.text.trim(),
                  betrag: double.tryParse(betragC.text.trim()),
                  kuendigungDatum: kundDatumC.text.isNotEmpty ? kundDatumC.text.trim() : null,
                  kuendigungBestaetigt: bestaetigt,
                  kuendigungBestaetigungsDatum: bestDatumC.text.isNotEmpty ? bestDatumC.text.trim() : null,
                  rufnummernmitnahme: rufnummer,
                  kuendigungGrund: grundC.text.trim(),
                  notiz: notizC.text.trim(),
                );
                if (res['success'] != true) {
                  errors.add('${f.name}: ${res['message']?.toString() ?? 'unbekannter Fehler'}');
                }
                if (ctx.mounted) setD(() => uploadProgressDone++);
              }
              if (!ctx.mounted) return;
              if (errors.isEmpty) {
                Navigator.pop(ctx);
                _load();
              } else {
                setD(() => uploading = false);
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                  content: Text('${errors.length} Datei(en) fehlgeschlagen:\n${errors.join("\n")}'),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 6),
                ));
              }
            },
          ),
        ],
      )),
    );
  }
}

// ═══════════════════════════════════════════════════════
// VEREIN TAB (sub-tabs: Zuständiger Verein + Vertrag)
// ═══════════════════════════════════════════════════════
class _VereinTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final List<Map<String, dynamic>> vertraege;
  final Future<void> Function() onChanged;
  const _VereinTab({required this.apiService, required this.userId, required this.vertraege, required this.onChanged});
  @override
  State<_VereinTab> createState() => _VereinTabState();
}

class _VereinTabState extends State<_VereinTab> {
  Map<String, dynamic>? _selectedVerein;
  List<Map<String, dynamic>> _localVertraege = [];

  @override
  void initState() { super.initState(); _localVertraege = List.from(widget.vertraege); _loadSelectedVerein(); }

  @override
  void didUpdateWidget(covariant _VereinTab old) { super.didUpdateWidget(old); _localVertraege = List.from(widget.vertraege); }

  Future<void> _loadSelectedVerein() async {
    try {
      final r = await widget.apiService.getVereinData(widget.userId);
      if (r['success'] == true && r['data'] != null && r['data'] is Map && (r['data']['name'] ?? '').toString().isNotEmpty) {
        _selectedVerein = Map<String, dynamic>.from(r['data']);
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _saveSelectedVerein(Map<String, dynamic>? v) async {
    final data = <String, dynamic>{};
    if (v != null) { for (final e in v.entries) {
      data[e.key.toString()] = e.value?.toString() ?? '';
    } }
    else { data['name'] = ''; data['typ'] = ''; data['strasse'] = ''; data['plz_ort'] = ''; data['telefon'] = ''; data['email'] = ''; data['oeffnungszeiten'] = ''; }
    await widget.apiService.saveVereinData(widget.userId, data);
  }

  Future<void> _reload() async {
    await widget.onChanged();
    try {
      final r = await widget.apiService.listVertraege(widget.userId);
      if (r['success'] == true && r['data'] is List && mounted) {
        _localVertraege = (r['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).where((v) => v['kategorie'] == 'verein').toList();
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _searchVerein() async {
    final vereine = await widget.apiService.getVereinDatenbank();
    if (!mounted || vereine.isEmpty) return;
    final sel = await showDialog<Map<String, dynamic>>(context: context, builder: (sCtx) {
      String search = '';
      List<Map<String, dynamic>> results = vereine;
      return StatefulBuilder(builder: (sCtx, setS) => AlertDialog(
        title: Row(children: [Icon(Icons.groups, size: 18, color: Colors.indigo.shade700), const SizedBox(width: 8), const Text('Verein suchen', style: TextStyle(fontSize: 14))]),
        content: SizedBox(width: 450, height: 400, child: Column(children: [
          TextField(autofocus: true, decoration: InputDecoration(hintText: 'Name oder Ort...', prefixIcon: const Icon(Icons.search, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            onChanged: (v) => setS(() { search = v.toLowerCase(); results = vereine.where((s) => (s['name']?.toString() ?? '').toLowerCase().contains(search) || (s['plz_ort']?.toString() ?? '').toLowerCase().contains(search)).toList(); })),
          const SizedBox(height: 8),
          Expanded(child: results.isEmpty ? Center(child: Text('Keine Ergebnisse', style: TextStyle(color: Colors.grey.shade500)))
            : ListView.builder(itemCount: results.length, itemBuilder: (_, i) {
                final v = results[i];
                return ListTile(dense: true, leading: Icon(Icons.groups, size: 18, color: Colors.indigo.shade400),
                  title: Text(v['name']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text([v['typ'], v['plz_ort']].where((x) => x != null && x.toString().isNotEmpty).join(' · '), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  onTap: () => Navigator.pop(sCtx, v));
              })),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(sCtx), child: const Text('Abbrechen'))],
      ));
    });
    if (sel != null) { setState(() => _selectedVerein = sel); _saveSelectedVerein(sel); }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(length: 2, child: Column(children: [
      TabBar(labelColor: Colors.indigo.shade700, unselectedLabelColor: Colors.grey.shade500, indicatorColor: Colors.indigo.shade700,
        tabs: const [Tab(icon: Icon(Icons.groups, size: 14), text: 'Zuständiger Verein'), Tab(icon: Icon(Icons.description, size: 14), text: 'Vertrag')]),
      Expanded(child: TabBarView(children: [_buildVereinInfo(), _buildVertragList()])),
    ]));
  }

  Widget _buildVereinInfo() {
    final hasV = _selectedVerein != null;
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.groups, size: 20, color: Colors.indigo.shade700), const SizedBox(width: 8),
        Text('Zuständiger Verein', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
        const Spacer(),
        FilledButton.icon(icon: const Icon(Icons.search, size: 16), label: Text(hasV ? 'Ändern' : 'Suchen', style: const TextStyle(fontSize: 12)),
          style: FilledButton.styleFrom(backgroundColor: Colors.indigo.shade600, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero),
          onPressed: _searchVerein),
      ]),
      const SizedBox(height: 16),
      if (!hasV)
        Container(width: double.infinity, padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
          child: Column(children: [Icon(Icons.search, size: 48, color: Colors.grey.shade300), const SizedBox(height: 8), Text('Kein Verein ausgewählt', style: TextStyle(fontSize: 13, color: Colors.grey.shade500))]))
      else
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.indigo.shade200)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [CircleAvatar(radius: 22, backgroundColor: Colors.indigo.shade100, child: Icon(Icons.groups, size: 24, color: Colors.indigo.shade700)), const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_selectedVerein!['name']?.toString() ?? '', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
                if ((_selectedVerein!['typ']?.toString() ?? '').isNotEmpty) Text(_selectedVerein!['typ'].toString(), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ])),
              IconButton(icon: Icon(Icons.close, size: 18, color: Colors.red.shade400), onPressed: () { setState(() => _selectedVerein = null); _saveSelectedVerein(null); }),
            ]),
            const Divider(height: 20),
            if ((_selectedVerein!['strasse']?.toString() ?? '').isNotEmpty || (_selectedVerein!['plz_ort']?.toString() ?? '').isNotEmpty)
              _ir(Icons.location_on, [_selectedVerein!['strasse'], _selectedVerein!['plz_ort']].where((v) => v != null && v.toString().isNotEmpty).join(', '), Colors.indigo),
            if ((_selectedVerein!['telefon']?.toString() ?? '').isNotEmpty) _ir(Icons.phone, _selectedVerein!['telefon'].toString(), Colors.blue),
            if ((_selectedVerein!['email']?.toString() ?? '').isNotEmpty) _ir(Icons.email, _selectedVerein!['email'].toString(), Colors.teal),
            if ((_selectedVerein!['oeffnungszeiten']?.toString() ?? '').isNotEmpty) _ir(Icons.schedule, _selectedVerein!['oeffnungszeiten'].toString(), Colors.orange),
          ])),
    ]));
  }

  Widget _ir(IconData icon, String text, MaterialColor c) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [
    Icon(icon, size: 16, color: c.shade600), const SizedBox(width: 10), Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: Colors.grey.shade800)))]));

  Widget _buildVertragList() {
    final list = _localVertraege;
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Icon(Icons.description, size: 18, color: Colors.indigo.shade700), const SizedBox(width: 8),
        Text('${list.length} Vertrag/Verträge', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const Spacer(),
        FilledButton.icon(icon: const Icon(Icons.add, size: 16), label: const Text('Neuer Vertrag', style: TextStyle(fontSize: 12)),
          style: FilledButton.styleFrom(backgroundColor: Colors.indigo.shade600, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero),
          onPressed: () async {
            final anbieter = _selectedVerein?['name']?.toString() ?? '';
            final tel = _selectedVerein?['telefon']?.toString() ?? '';
            await _addVereinVertrag(anbieter, tel);
          }),
      ])),
      Expanded(child: list.isEmpty ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.description_outlined, size: 48, color: Colors.grey.shade300), const SizedBox(height: 8), Text('Keine Verträge', style: TextStyle(fontSize: 12, color: Colors.grey.shade500))]))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: list.length, itemBuilder: (_, i) {
            final v = list[i];
            bool aktiv = v['is_active'] == 1 || v['is_active'] == true || v['is_active'] == '1';
            final ende = v['vertragsende']?.toString() ?? '';
            if (aktiv && ende.isNotEmpty) { try { final p = ende.split('.'); final d = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0])); if (d.isBefore(DateTime.now())) aktiv = false; } catch (_) {} }
            final gekuendigt = (v['gekuendigt_am']?.toString() ?? '').isNotEmpty;
            return Container(margin: const EdgeInsets.only(bottom: 8), child: InkWell(borderRadius: BorderRadius.circular(8),
              onTap: () => _showVertragDetail(v),
              child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.indigo.shade200)),
                child: Row(children: [
                  Icon(Icons.groups, size: 18, color: Colors.indigo.shade700), const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(v['anbieter']?.toString() ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade800))),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: aktiv ? Colors.green.shade100 : gekuendigt ? Colors.red.shade100 : Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
                        child: Text(aktiv ? 'Aktiv' : gekuendigt ? 'Gekündigt' : 'Abgelaufen', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: aktiv ? Colors.green.shade800 : gekuendigt ? Colors.red.shade800 : Colors.grey.shade700))),
                    ]),
                    if ((v['tarif']?.toString() ?? '').isNotEmpty) Text(v['tarif'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    if ((v['monatliche_kosten']?.toString() ?? '').isNotEmpty) Text('${v['monatliche_kosten']} €/Jahr', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  ])),
                  Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
                ]))));
          })),
    ]);
  }

  Future<void> _addVereinVertrag(String anbieter, String tel) async {
    final anbieterC = TextEditingController(text: anbieter);
    final tarifC = TextEditingController();
    final kostenC = TextEditingController();
    final beginnC = TextEditingController();
    final laufzeitC = TextEditingController(text: '12 Monate');
    final fristC = TextEditingController(text: '3 Monate zum Jahresende');
    final telC = TextEditingController(text: tel);
    final notizenC = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Row(children: [Icon(Icons.groups, size: 18, color: Colors.indigo.shade700), const SizedBox(width: 8), const Text('Neuer Vereinsvertrag', style: TextStyle(fontSize: 14))]),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: anbieterC, decoration: InputDecoration(labelText: 'Verein *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 8),
        TextField(controller: tarifC, decoration: InputDecoration(labelText: 'Art der Mitgliedschaft', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 8),
        TextField(controller: kostenC, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Mitgliedsbeitrag €/Jahr', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 8),
        TextFormField(controller: beginnC, readOnly: true, decoration: InputDecoration(labelText: 'Vertragsbeginn', prefixIcon: const Icon(Icons.calendar_today, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async { final p = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de')); if (p != null) beginnC.text = '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}'; }))),
        const SizedBox(height: 8),
        Row(children: [Expanded(child: TextField(controller: laufzeitC, decoration: InputDecoration(labelText: 'Laufzeit', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
          const SizedBox(width: 8), Expanded(child: TextField(controller: fristC, decoration: InputDecoration(labelText: 'Kündigungsfrist', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))))]),
        const SizedBox(height: 8),
        TextField(controller: telC, decoration: InputDecoration(labelText: 'Telefon', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 8),
        TextField(controller: notizenC, maxLines: 2, decoration: InputDecoration(labelText: 'Notizen', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Speichern')),
      ],
    ));
    if (ok != true) return;
    await widget.apiService.saveVertrag(widget.userId, {
      'kategorie': 'verein', 'anbieter': anbieterC.text.trim(), 'tarif': tarifC.text.trim(),
      'monatliche_kosten': kostenC.text.trim(), 'vertragsbeginn': beginnC.text.trim(),
      'mindestlaufzeit': laufzeitC.text.trim(), 'kuendigungsfrist': fristC.text.trim(),
      'telefonnummer': telC.text.trim(), 'notizen': notizenC.text.trim(),
    });
    await _reload();
  }

  void _showVertragDetail(Map<String, dynamic> v) {
    final vid = int.tryParse(v['id']?.toString() ?? '') ?? 0;
    showDialog(context: context, builder: (ctx) => Dialog(child: SizedBox(width: 580, height: 500, child: StatefulBuilder(builder: (ctx, setDlg) => DefaultTabController(length: 3, child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 8, 0), child: Row(children: [
        Icon(Icons.groups, size: 18, color: Colors.indigo.shade700), const SizedBox(width: 8),
        Expanded(child: Text(v['anbieter']?.toString() ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo.shade800), overflow: TextOverflow.ellipsis)),
        IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.pop(ctx)),
      ])),
      TabBar(labelColor: Colors.indigo.shade700, unselectedLabelColor: Colors.grey.shade500, indicatorColor: Colors.indigo.shade700, tabs: const [
        Tab(icon: Icon(Icons.info_outline, size: 16), text: 'Details'),
        Tab(icon: Icon(Icons.email, size: 16), text: 'Korrespondenz'),
        Tab(icon: Icon(Icons.cancel_outlined, size: 16), text: 'Kündigung'),
      ]),
      Expanded(child: TabBarView(children: [
        SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _dr(Icons.groups, 'Verein', v['anbieter']),
          _dr(Icons.card_membership, 'Art', v['tarif']),
          _dr(Icons.euro, 'Beitrag/Jahr', v['monatliche_kosten'] != null ? '${v['monatliche_kosten']} €' : null),
          _dr(Icons.calendar_today, 'Beginn', v['vertragsbeginn']),
          _dr(Icons.timelapse, 'Laufzeit', v['mindestlaufzeit']),
          _dr(Icons.timer, 'Kündigungsfrist', v['kuendigungsfrist']),
          _dr(Icons.phone, 'Telefon', v['telefonnummer']),
          _dr(Icons.cancel, 'Gekündigt am', v['gekuendigt_am']),
          _dr(Icons.event_busy, 'Vertragsende', v['vertragsende']),
          if ((v['notizen']?.toString() ?? '').isNotEmpty) ...[const SizedBox(height: 10),
            Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
              child: Text(v['notizen'].toString(), style: const TextStyle(fontSize: 12)))],
        ])),
        _VereinKorrTab(apiService: widget.apiService, vertragId: vid),
        // ──── Kündigung Tab ────
        SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.cancel_outlined, size: 20, color: Colors.red.shade700), const SizedBox(width: 8),
            Text('Kündigung', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.red.shade700))]),
          const SizedBox(height: 12),
          if ((v['gekuendigt_am']?.toString() ?? '').isNotEmpty) ...[
            Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.shade200)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Icon(Icons.check_circle, size: 16, color: Colors.red.shade700), const SizedBox(width: 8), Text('Gekündigt', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red.shade800))]),
                const SizedBox(height: 8),
                _dr(Icons.calendar_today, 'Gekündigt am', v['gekuendigt_am']),
                _dr(Icons.event_busy, 'Vertragsende', v['vertragsende']),
                if ((v['kuendigung_methode']?.toString() ?? '').isNotEmpty) _dr(Icons.send, 'Methode', {'online': 'Online', 'email': 'E-Mail', 'post': 'Post', 'persoenlich': 'Persönlich'}[v['kuendigung_methode']] ?? v['kuendigung_methode'].toString()),
                if ((v['kuendigung_notiz']?.toString() ?? '').isNotEmpty) ...[const SizedBox(height: 6), Text(v['kuendigung_notiz'].toString(), style: TextStyle(fontSize: 12, color: Colors.grey.shade700))],
              ])),
          ] else ...[
            Container(width: double.infinity, padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
              child: Column(children: [Icon(Icons.info_outline, size: 32, color: Colors.grey.shade400), const SizedBox(height: 8),
                Text('Vertrag ist aktiv — noch nicht gekündigt', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                if ((v['kuendigungsfrist']?.toString() ?? '').isNotEmpty) Text('Kündigungsfrist: ${v['kuendigungsfrist']}', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ])),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(icon: Icon((v['gekuendigt_am']?.toString() ?? '').isNotEmpty ? Icons.edit : Icons.cancel, size: 16),
            label: Text((v['gekuendigt_am']?.toString() ?? '').isNotEmpty ? 'Kündigung bearbeiten' : 'Jetzt kündigen', style: const TextStyle(fontSize: 12)),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
            onPressed: () {
              final gekDatumC = TextEditingController(text: v['gekuendigt_am']?.toString() ?? '');
              final endeC = TextEditingController(text: v['vertragsende']?.toString() ?? '');
              final notizKC = TextEditingController(text: v['kuendigung_notiz']?.toString() ?? '');
              String methode = v['kuendigung_methode']?.toString() ?? '';
              showDialog(context: ctx, builder: (kCtx) => StatefulBuilder(builder: (kCtx, setK) => AlertDialog(
                title: Row(children: [Icon(Icons.cancel, size: 18, color: Colors.red.shade700), const SizedBox(width: 8), const Text('Kündigung', style: TextStyle(fontSize: 14))]),
                content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('Wie wurde gekündigt?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 4, children: [for (final m in [('online', 'Online', Icons.language), ('email', 'E-Mail', Icons.email), ('post', 'Post', Icons.mail), ('persoenlich', 'Persönlich', Icons.person)])
                    ChoiceChip(label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(m.$3, size: 13, color: methode == m.$1 ? Colors.white : Colors.grey.shade700), const SizedBox(width: 4), Text(m.$2, style: TextStyle(fontSize: 10, color: methode == m.$1 ? Colors.white : Colors.grey.shade700))]),
                      selected: methode == m.$1, selectedColor: Colors.red.shade600, onSelected: (_) => setK(() => methode = m.$1))]),
                  const SizedBox(height: 12),
                  TextFormField(controller: gekDatumC, readOnly: true, decoration: InputDecoration(labelText: 'Gekündigt am', prefixIcon: const Icon(Icons.calendar_today, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async { final p = await showDatePicker(context: kCtx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de')); if (p != null) setK(() => gekDatumC.text = '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}'); }))),
                  const SizedBox(height: 8),
                  TextFormField(controller: endeC, readOnly: true, decoration: InputDecoration(labelText: 'Vertragsende', prefixIcon: const Icon(Icons.event_busy, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async { final p = await showDatePicker(context: kCtx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de')); if (p != null) setK(() => endeC.text = '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}'); }))),
                  const SizedBox(height: 8),
                  TextField(controller: notizKC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
                ])),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(kCtx), child: const Text('Abbrechen')),
                  FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600), onPressed: () async {
                    v['gekuendigt_am'] = gekDatumC.text.trim(); v['vertragsende'] = endeC.text.trim(); v['kuendigung_methode'] = methode; v['kuendigung_notiz'] = notizKC.text.trim(); v['is_active'] = 0;
                    await widget.apiService.saveVertrag(widget.userId, v);
                    await _reload(); if (kCtx.mounted) Navigator.pop(kCtx); setDlg(() {});
                  }, child: const Text('Speichern')),
                ],
              )));
            }),
        ])),
      ])),
    ]))))));
  }

  Widget _dr(IconData icon, String label, dynamic value) {
    final val = value?.toString() ?? ''; if (val.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [
      Icon(icon, size: 14, color: Colors.indigo.shade600), const SizedBox(width: 8),
      Text('$label: ', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      Expanded(child: Text(val, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)))]));
  }
}

class _VereinKorrTab extends StatefulWidget {
  final ApiService apiService;
  final int vertragId;
  const _VereinKorrTab({required this.apiService, required this.vertragId});
  @override
  State<_VereinKorrTab> createState() => _VereinKorrTabState();
}

class _VereinKorrTabState extends State<_VereinKorrTab> {
  List<Map<String, dynamic>> _korr = [];
  bool _loaded = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final r = await widget.apiService.listVertraegeKorrespondenz(widget.vertragId);
      if (r['success'] == true && r['data'] is List) _korr = (r['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [const Spacer(),
        FilledButton.icon(icon: const Icon(Icons.call_received, size: 14), label: const Text('Eingang', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.green.shade600, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _addKorr('eingang')),
        const SizedBox(width: 6),
        FilledButton.icon(icon: const Icon(Icons.call_made, size: 14), label: const Text('Ausgang', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade600, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _addKorr('ausgang')),
      ])),
      Expanded(child: _korr.isEmpty ? Center(child: Text('Keine Korrespondenz', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _korr.length, itemBuilder: (_, i) {
            final k = _korr[i]; final isEin = k['richtung'] == 'eingang'; final c = isEin ? Colors.green : Colors.blue;
            const mL = {'email': 'E-Mail', 'post': 'Post', 'online': 'Online', 'persoenlich': 'Persönlich'};
            return InkWell(borderRadius: BorderRadius.circular(8), onTap: () => _showKorrDetail(k),
              child: Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: c.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: c.shade200)),
                child: Row(children: [
                  Icon(isEin ? Icons.call_received : Icons.call_made, size: 18, color: c.shade700), const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(k['betreff']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c.shade800)),
                    if ((k['datum']?.toString() ?? '').isNotEmpty) Text(k['datum'].toString(), style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  ])),
                  if ((k['methode']?.toString() ?? '').isNotEmpty) Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: c.shade100, borderRadius: BorderRadius.circular(4)),
                    child: Text(mL[k['methode']] ?? k['methode'].toString(), style: TextStyle(fontSize: 9, color: c.shade700))),
                  Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
                ])));
          })),
    ]);
  }

  void _showKorrDetail(Map<String, dynamic> k) {
    final isEin = k['richtung'] == 'eingang';
    final c = isEin ? Colors.green : Colors.blue;
    const mL = {'email': 'E-Mail', 'post': 'Post', 'online': 'Online', 'persoenlich': 'Persönlich'};
    final kId = k['id'] is int ? k['id'] as int : int.parse(k['id'].toString());
    showDialog(context: context, builder: (ctx) => AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      title: Row(children: [
        Icon(isEin ? Icons.call_received : Icons.call_made, size: 18, color: c.shade700), const SizedBox(width: 8),
        Expanded(child: Text(k['betreff']?.toString() ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: c.shade800), overflow: TextOverflow.ellipsis)),
        IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), tooltip: 'Löschen', onPressed: () async {
          await widget.apiService.deleteVertraegeKorrespondenz(kId); _load(); if (ctx.mounted) Navigator.pop(ctx); }),
        IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.pop(ctx)),
      ]),
      content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(isEin ? Icons.call_received : Icons.call_made, size: 14, color: c.shade600), const SizedBox(width: 6),
              Text(isEin ? 'Eingang' : 'Ausgang', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.shade700))]),
            const SizedBox(height: 6),
            if ((k['methode']?.toString() ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(children: [
              Icon(Icons.send, size: 12, color: Colors.grey.shade500), const SizedBox(width: 6),
              Text('Methode: ', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              Text(mL[k['methode']] ?? k['methode'].toString(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))])),
            if ((k['datum']?.toString() ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(children: [
              Icon(Icons.calendar_today, size: 12, color: Colors.grey.shade500), const SizedBox(width: 6),
              Text('Datum: ', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              Text(k['datum'].toString(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))])),
            Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(children: [
              Icon(Icons.subject, size: 12, color: Colors.grey.shade500), const SizedBox(width: 6),
              Text('Betreff: ', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              Expanded(child: Text(k['betreff']?.toString() ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)))])),
          ])),
        if ((k['notiz']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Inhalt / Notiz', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
              const SizedBox(height: 6),
              Text(k['notiz'].toString(), style: const TextStyle(fontSize: 13)),
            ])),
        ],
        const SizedBox(height: 12),
        Text('Dokumente', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
        const SizedBox(height: 4),
        KorrAttachmentsWidget(apiService: widget.apiService, modul: 'verein_vertrag', korrespondenzId: kId),
      ]))),
    ));
  }

  void _addKorr(String richtung) {
    final datumC = TextEditingController(); final betreffC = TextEditingController(); final notizC = TextEditingController();
    String methode = richtung == 'eingang' ? 'post' : 'email';
    List<PlatformFile> files = [];
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) => AlertDialog(
      title: Row(children: [Icon(richtung == 'eingang' ? Icons.call_received : Icons.call_made, size: 18, color: richtung == 'eingang' ? Colors.green.shade700 : Colors.blue.shade700), const SizedBox(width: 8), Text(richtung == 'eingang' ? 'Eingang' : 'Ausgang', style: const TextStyle(fontSize: 14))]),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Wrap(spacing: 6, runSpacing: 4, children: [for (final m in [('email', 'E-Mail', Icons.email), ('post', 'Post', Icons.mail), ('online', 'Online', Icons.language), ('persoenlich', 'Persönlich', Icons.person)])
          ChoiceChip(label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(m.$3, size: 13, color: methode == m.$1 ? Colors.white : Colors.grey.shade700), const SizedBox(width: 4), Text(m.$2, style: TextStyle(fontSize: 10, color: methode == m.$1 ? Colors.white : Colors.grey.shade700))]),
            selected: methode == m.$1, selectedColor: Colors.indigo.shade600, onSelected: (_) => setDlg(() => methode = m.$1))]),
        const SizedBox(height: 12),
        TextFormField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', prefixIcon: const Icon(Icons.calendar_today, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async { final p = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de')); if (p != null) setDlg(() => datumC.text = '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}'); }))),
        const SizedBox(height: 8),
        TextField(controller: betreffC, decoration: InputDecoration(labelText: 'Betreff *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 12),
        OutlinedButton.icon(icon: Icon(Icons.attach_file, size: 16, color: Colors.teal.shade600),
          label: Text(files.isEmpty ? 'Dokumente anhängen' : '${files.length} Datei(en)', style: TextStyle(fontSize: 12, color: Colors.teal.shade700)),
          style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.teal.shade300)),
          onPressed: () async { final r = await FilePickerHelper.pickFiles(allowMultiple: true, type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']); if (r != null) setDlg(() { files.addAll(r.files); if (files.length > 20) files = files.sublist(0, 20); }); }),
        if (files.isNotEmpty) ...files.asMap().entries.map((e) => Padding(padding: const EdgeInsets.only(top: 3), child: Row(children: [
          Icon(Icons.description, size: 13, color: Colors.grey.shade500), const SizedBox(width: 6),
          Expanded(child: Text(e.value.name, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
          IconButton(icon: Icon(Icons.close, size: 14, color: Colors.red.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24), onPressed: () => setDlg(() => files.removeAt(e.key))),
        ]))),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          if (betreffC.text.trim().isEmpty) return;
          final res = await widget.apiService.saveVertraegeKorrespondenz({'vertrag_id': widget.vertragId, 'richtung': richtung, 'methode': methode, 'datum': datumC.text.trim(), 'betreff': betreffC.text.trim(), 'notiz': notizC.text.trim()});
          final korrId = res['id'];
          if (korrId != null && files.isNotEmpty) { for (final f in files) { if (f.path == null) continue; await widget.apiService.uploadKorrAttachment(modul: 'verein_vertrag', korrespondenzId: korrId is int ? korrId : int.parse(korrId.toString()), filePath: f.path!, fileName: f.name); } }
          if (ctx.mounted) Navigator.pop(ctx); _load();
        }, child: const Text('Speichern')),
      ],
    )));
  }
}

// ═════════════════════════════════════════════════════════════════════
// INKASSO TAB — 3 sub-tabs: Zuständige Inkasso | Stammdaten | Aktenzeichen
// All free-form data stored server-side AES-256-GCM encrypted.
// ═════════════════════════════════════════════════════════════════════

class _InkassoTab extends StatefulWidget {
  final ApiService apiService;
  final int vertragId;
  const _InkassoTab({required this.apiService, required this.vertragId});

  @override
  State<_InkassoTab> createState() => _InkassoTabState();
}

class _InkassoTabState extends State<_InkassoTab> {
  Map<String, dynamic>? _inkassoRow;
  bool _loaded = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final res = await widget.apiService.getVertragInkasso(widget.vertragId);
    if (!mounted) return;
    // Server returns the JSON flat: {success, exists, data: {…}, message}.
    // The previous code unwrapped res['data'] first, then checked
    // data['exists'] — which always missed because 'exists' lives on the
    // root. Result: _inkassoRow stayed null, the sub-tabs initialised
    // empty controllers, and the operator saw "nothing was saved" even
    // though the server had persisted the row.
    setState(() {
      _inkassoRow = (res['exists'] == true) ? (res['data'] as Map<String, dynamic>?) : null;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());

    return DefaultTabController(
      length: 3,
      child: Column(children: [
        Container(
          color: Colors.purple.shade50,
          child: TabBar(
            isScrollable: true,
            labelColor: Colors.purple.shade700,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: Colors.purple.shade700,
            tabs: const [
              Tab(icon: Icon(Icons.business_center, size: 16), text: 'Zuständige Inkasso'),
              Tab(icon: Icon(Icons.fact_check, size: 16), text: 'Stammdaten'),
              Tab(icon: Icon(Icons.folder_open, size: 16), text: 'Aktenzeichen'),
            ],
          ),
        ),
        Expanded(child: TabBarView(children: [
          _ZustaendigeInkassoSubTab(
            apiService: widget.apiService,
            vertragId: widget.vertragId,
            current: _inkassoRow,
            onSaved: _load,
          ),
          _StammdatenSubTab(
            apiService: widget.apiService,
            vertragId: widget.vertragId,
            current: _inkassoRow,
            onSaved: _load,
          ),
          _AktenzeichenSubTab(
            apiService: widget.apiService,
            vertragId: widget.vertragId,
          ),
        ])),
      ]),
    );
  }
}

// ─── Sub-tab 1: Zuständige Inkasso (dropdown from inkasso_datenbank) ───

class _ZustaendigeInkassoSubTab extends StatefulWidget {
  final ApiService apiService;
  final int vertragId;
  final Map<String, dynamic>? current;
  final VoidCallback onSaved;
  const _ZustaendigeInkassoSubTab({required this.apiService, required this.vertragId, required this.current, required this.onSaved});

  @override
  State<_ZustaendigeInkassoSubTab> createState() => _ZustaendigeInkassoSubTabState();
}

class _ZustaendigeInkassoSubTabState extends State<_ZustaendigeInkassoSubTab> {
  List<Map<String, dynamic>> _datenbank = [];
  int? _selectedId;
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.current?['inkasso_id'] as int?;
    _loadDatenbank();
  }

  Future<void> _loadDatenbank() async {
    final res = await widget.apiService.listInkassoDatenbank();
    if (!mounted) return;
    final data = res['data'] as Map<String, dynamic>? ?? res;
    setState(() {
      _datenbank = List<Map<String, dynamic>>.from(data['items'] as List? ?? []);
      _loaded = true;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final cur = widget.current ?? <String, dynamic>{};
    final res = await widget.apiService.saveVertragInkasso(widget.vertragId, {
      'inkasso_id': _selectedId,
      'status': cur['status'] ?? 'offen',
      'eroeffnet_am': cur['eroeffnet_am'],
      'abgeschlossen_am': cur['abgeschlossen_am'],
      'ansprechpartner': cur['ansprechpartner'],
      'telefon_durchwahl': cur['telefon_durchwahl'],
      'email_ansprechpartner': cur['email_ansprechpartner'],
      'ref_intern': cur['ref_intern'],
      'gesamtforderung': cur['gesamtforderung'],
      'notizen': cur['notizen'],
    });
    if (!mounted) return;
    setState(() => _saving = false);
    final ok = res['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Inkasso gespeichert' : (res['message'] ?? 'Fehler')),
      backgroundColor: ok ? Colors.green : Colors.red,
    ));
    if (ok) widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final selected = _datenbank.firstWhere((e) => (e['id'] as int?) == _selectedId, orElse: () => <String, dynamic>{});
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Zuständige Inkasso-Firma', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple.shade700)),
        const SizedBox(height: 8),
        DropdownButtonFormField<int?>(
          initialValue: _selectedId,
          isExpanded: true,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            hintText: 'Inkasso-Firma auswählen…',
            prefixIcon: const Icon(Icons.business_center),
          ),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('— keine —')),
            ..._datenbank.map((e) => DropdownMenuItem<int?>(
                  value: e['id'] as int?,
                  child: Text(e['firmenname']?.toString() ?? '', overflow: TextOverflow.ellipsis),
                )),
          ],
          onChanged: (v) => setState(() => _selectedId = v),
        ),
        if (selected.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if ((selected['firmenname'] ?? '').toString().isNotEmpty)
                Text(selected['firmenname'].toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 6),
              if ((selected['strasse'] ?? '').toString().isNotEmpty)
                _infoRow(Icons.location_on, '${selected['strasse']}, ${selected['plz_ort'] ?? ''}'),
              if ((selected['telefon'] ?? '').toString().isNotEmpty)
                _infoRow(Icons.phone, selected['telefon'].toString()),
              if ((selected['fax'] ?? '').toString().isNotEmpty)
                _infoRow(Icons.fax, selected['fax'].toString()),
              if ((selected['email'] ?? '').toString().isNotEmpty)
                _infoRow(Icons.email, selected['email'].toString()),
              if ((selected['website'] ?? '').toString().isNotEmpty)
                _infoRow(Icons.language, selected['website'].toString()),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 16),
            label: const Text('Speichern (verschlüsselt)'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple.shade600, foregroundColor: Colors.white),
          ),
        ),
      ]),
    );
  }

  Widget _infoRow(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Icon(icon, size: 14, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        ]),
      );
}

// ─── Sub-tab 2: Stammdaten (case-specific data, encrypted) ───────────

class _StammdatenSubTab extends StatefulWidget {
  final ApiService apiService;
  final int vertragId;
  final Map<String, dynamic>? current;
  final VoidCallback onSaved;
  const _StammdatenSubTab({required this.apiService, required this.vertragId, required this.current, required this.onSaved});

  @override
  State<_StammdatenSubTab> createState() => _StammdatenSubTabState();
}

class _StammdatenSubTabState extends State<_StammdatenSubTab> {
  late final TextEditingController _ansprechC;
  late final TextEditingController _telC;
  late final TextEditingController _emailC;
  late final TextEditingController _refC;
  late final TextEditingController _forderungC;
  late final TextEditingController _notizenC;
  String _status = 'offen';
  DateTime? _eroeffnet;
  DateTime? _abgeschlossen;
  bool _saving = false;

  static const _statusOptions = [
    ('offen', 'Offen', Colors.orange),
    ('in_bearbeitung', 'In Bearbeitung', Colors.blue),
    ('vergleich', 'Vergleich', Colors.teal),
    ('ratenzahlung', 'Ratenzahlung', Colors.indigo),
    ('widerspruch', 'Widerspruch', Colors.purple),
    ('gerichtlich', 'Gerichtlich', Colors.red),
    ('abgeschlossen', 'Abgeschlossen', Colors.green),
    ('zurueckgewiesen', 'Zurückgewiesen', Colors.grey),
  ];

  @override
  void initState() {
    super.initState();
    final c = widget.current ?? <String, dynamic>{};
    _ansprechC = TextEditingController(text: c['ansprechpartner']?.toString() ?? '');
    _telC = TextEditingController(text: c['telefon_durchwahl']?.toString() ?? '');
    _emailC = TextEditingController(text: c['email_ansprechpartner']?.toString() ?? '');
    _refC = TextEditingController(text: c['ref_intern']?.toString() ?? '');
    _forderungC = TextEditingController(text: c['gesamtforderung']?.toString() ?? '');
    _notizenC = TextEditingController(text: c['notizen']?.toString() ?? '');
    _status = c['status']?.toString() ?? 'offen';
    _eroeffnet = DateTime.tryParse(c['eroeffnet_am']?.toString() ?? '');
    _abgeschlossen = DateTime.tryParse(c['abgeschlossen_am']?.toString() ?? '');
  }

  @override
  void dispose() {
    _ansprechC.dispose(); _telC.dispose(); _emailC.dispose();
    _refC.dispose(); _forderungC.dispose(); _notizenC.dispose();
    super.dispose();
  }

  Future<void> _pickDate(BuildContext ctx, DateTime? initial, ValueChanged<DateTime?> onPicked) async {
    final d = await showDatePicker(
      context: ctx,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2010),
      lastDate: DateTime(2050),
    );
    if (d != null) onPicked(d);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final res = await widget.apiService.saveVertragInkasso(widget.vertragId, {
      'inkasso_id': widget.current?['inkasso_id'],
      'status': _status,
      'eroeffnet_am': _eroeffnet?.toIso8601String().substring(0, 10),
      'abgeschlossen_am': _abgeschlossen?.toIso8601String().substring(0, 10),
      'ansprechpartner': _ansprechC.text.trim(),
      'telefon_durchwahl': _telC.text.trim(),
      'email_ansprechpartner': _emailC.text.trim(),
      'ref_intern': _refC.text.trim(),
      'gesamtforderung': _forderungC.text.trim(),
      'notizen': _notizenC.text.trim(),
    });
    if (!mounted) return;
    setState(() => _saving = false);
    final ok = res['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Stammdaten gespeichert (verschlüsselt)' : (res['message'] ?? 'Fehler')),
      backgroundColor: ok ? Colors.green : Colors.red,
    ));
    if (ok) widget.onSaved();
  }

  String _formatDate(DateTime? d) => d == null ? '—' : '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Status row
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status', prefixIcon: Icon(Icons.flag), border: OutlineInputBorder(), isDense: true),
              items: _statusOptions.map((s) => DropdownMenuItem(value: s.$1, child: Row(children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: s.$3, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(s.$2),
              ]))).toList(),
              onChanged: (v) => setState(() => _status = v ?? 'offen'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _forderungC,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Gesamtforderung (€)', prefixIcon: Icon(Icons.euro), border: OutlineInputBorder(), isDense: true),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: InkWell(
            onTap: () => _pickDate(context, _eroeffnet, (d) => setState(() => _eroeffnet = d)),
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Eröffnet am', prefixIcon: Icon(Icons.date_range), border: OutlineInputBorder(), isDense: true),
              child: Text(_formatDate(_eroeffnet)),
            ),
          )),
          const SizedBox(width: 12),
          Expanded(child: InkWell(
            onTap: () => _pickDate(context, _abgeschlossen, (d) => setState(() => _abgeschlossen = d)),
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Abgeschlossen am', prefixIcon: Icon(Icons.event_available), border: OutlineInputBorder(), isDense: true),
              child: Text(_formatDate(_abgeschlossen)),
            ),
          )),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _ansprechC,
          decoration: const InputDecoration(labelText: 'Ansprechpartner', prefixIcon: Icon(Icons.person), border: OutlineInputBorder(), isDense: true),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(
            controller: _telC,
            decoration: const InputDecoration(labelText: 'Telefon / Durchwahl', prefixIcon: Icon(Icons.phone), border: OutlineInputBorder(), isDense: true),
          )),
          const SizedBox(width: 12),
          Expanded(child: TextField(
            controller: _emailC,
            decoration: const InputDecoration(labelText: 'E-Mail Ansprechpartner', prefixIcon: Icon(Icons.email), border: OutlineInputBorder(), isDense: true),
          )),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _refC,
          decoration: const InputDecoration(labelText: 'Interne Referenz', prefixIcon: Icon(Icons.tag), border: OutlineInputBorder(), isDense: true),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notizenC,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Notizen', prefixIcon: Icon(Icons.note), border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 16),
            label: const Text('Speichern (verschlüsselt)'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple.shade600, foregroundColor: Colors.white),
          ),
        ),
      ]),
    );
  }
}

// ─── Sub-tab 3: Aktenzeichen (1:N, click → detail dialog) ───────────

class _AktenzeichenSubTab extends StatefulWidget {
  final ApiService apiService;
  final int vertragId;
  const _AktenzeichenSubTab({required this.apiService, required this.vertragId});

  @override
  State<_AktenzeichenSubTab> createState() => _AktenzeichenSubTabState();
}

class _AktenzeichenSubTabState extends State<_AktenzeichenSubTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loaded = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final res = await widget.apiService.listVertragInkassoAktenzeichen(widget.vertragId);
    if (!mounted) return;
    final data = res['data'] as Map<String, dynamic>? ?? res;
    setState(() {
      _items = List<Map<String, dynamic>>.from(data['items'] as List? ?? []);
      _loaded = true;
    });
  }

  Future<void> _addOrEdit({Map<String, dynamic>? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => _AktenzeichenEditDialog(
        apiService: widget.apiService,
        vertragId: widget.vertragId,
        existing: existing,
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aktenzeichen löschen?'),
        content: const Text('Auch alle dazugehörigen Korrespondenzen werden entfernt.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    await widget.apiService.deleteVertragInkassoAktenzeichen(id);
    _load();
  }

  void _openDetail(Map<String, dynamic> akz) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: SizedBox(
          width: 720,
          height: 600,
          child: _AktenzeichenDetailDialog(
            apiService: widget.apiService,
            vertragId: widget.vertragId,
            aktenzeichen: akz,
            onChanged: _load,
          ),
        ),
      ),
    );
  }

  Color _statusColor(String? s) {
    switch (s) {
      case 'offen': return Colors.orange;
      case 'in_bearbeitung': return Colors.blue;
      case 'vergleich': return Colors.teal;
      case 'ratenzahlung': return Colors.indigo;
      case 'widerspruch': return Colors.purple;
      case 'gerichtlich': return Colors.red;
      case 'abgeschlossen': return Colors.green;
      case 'zurueckgewiesen': return Colors.grey;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          Icon(Icons.folder_open, size: 18, color: Colors.purple.shade700),
          const SizedBox(width: 8),
          Text('${_items.length} Aktenzeichen', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple.shade700)),
          const Spacer(),
          ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Neu'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple.shade600, foregroundColor: Colors.white),
            onPressed: () => _addOrEdit(),
          ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: _items.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.folder_open, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 8),
                Text('Noch keine Aktenzeichen', style: TextStyle(color: Colors.grey.shade600)),
              ]))
            : ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _items.length,
                itemBuilder: (ctx, i) {
                  final a = _items[i];
                  final status = a['status']?.toString();
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: _statusColor(status).withValues(alpha: 0.15), child: Icon(Icons.folder, color: _statusColor(status))),
                      title: Text(a['aktenzeichen']?.toString() ?? '(ohne Aktenzeichen)', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if ((a['bezeichnung'] ?? '').toString().isNotEmpty) Text(a['bezeichnung'].toString()),
                        Wrap(spacing: 8, children: [
                          if (status != null) Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: _statusColor(status).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                            child: Text(status, style: TextStyle(fontSize: 10, color: _statusColor(status))),
                          ),
                          if ((a['forderung_brutto'] ?? '').toString().isNotEmpty)
                            Text('${a['forderung_brutto']} €', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ]),
                      ]),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _addOrEdit(existing: a), tooltip: 'Bearbeiten'),
                        IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red), onPressed: () => _delete(a['id'] as int), tooltip: 'Löschen'),
                      ]),
                      onTap: () => _openDetail(a),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}

// ─── Edit dialog for adding/editing an Aktenzeichen ──────────────────

class _AktenzeichenEditDialog extends StatefulWidget {
  final ApiService apiService;
  final int vertragId;
  final Map<String, dynamic>? existing;
  const _AktenzeichenEditDialog({required this.apiService, required this.vertragId, this.existing});

  @override
  State<_AktenzeichenEditDialog> createState() => _AktenzeichenEditDialogState();
}

class _AktenzeichenEditDialogState extends State<_AktenzeichenEditDialog> {
  late final TextEditingController _aktenC;
  late final TextEditingController _bezC;
  late final TextEditingController _forderungC;
  late final TextEditingController _gezahltC;
  late final TextEditingController _notizenC;
  String _status = 'offen';
  DateTime? _eroeffnet;
  DateTime? _geschlossen;
  DateTime? _frist;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing ?? <String, dynamic>{};
    _aktenC = TextEditingController(text: e['aktenzeichen']?.toString() ?? '');
    _bezC = TextEditingController(text: e['bezeichnung']?.toString() ?? '');
    _forderungC = TextEditingController(text: e['forderung_brutto']?.toString() ?? '');
    _gezahltC = TextEditingController(text: e['gezahlt']?.toString() ?? '');
    _notizenC = TextEditingController(text: e['notizen']?.toString() ?? '');
    _status = e['status']?.toString() ?? 'offen';
    _eroeffnet = DateTime.tryParse(e['eroeffnet_am']?.toString() ?? '');
    _geschlossen = DateTime.tryParse(e['geschlossen_am']?.toString() ?? '');
    _frist = DateTime.tryParse(e['naechste_frist']?.toString() ?? '');
  }

  @override
  void dispose() {
    _aktenC.dispose(); _bezC.dispose(); _forderungC.dispose();
    _gezahltC.dispose(); _notizenC.dispose();
    super.dispose();
  }

  Future<void> _pickDate(DateTime? initial, ValueChanged<DateTime?> onPicked) async {
    final d = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2010),
      lastDate: DateTime(2050),
    );
    if (d != null) onPicked(d);
  }

  String _fmt(DateTime? d) => d == null ? '—' : '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  Future<void> _save() async {
    if (_aktenC.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aktenzeichen darf nicht leer sein')));
      return;
    }
    setState(() => _saving = true);
    final body = {
      if (widget.existing != null) 'id': widget.existing!['id'],
      'aktenzeichen': _aktenC.text.trim(),
      'bezeichnung': _bezC.text.trim(),
      'status': _status,
      'eroeffnet_am': _eroeffnet?.toIso8601String().substring(0, 10),
      'geschlossen_am': _geschlossen?.toIso8601String().substring(0, 10),
      'naechste_frist': _frist?.toIso8601String().substring(0, 10),
      'forderung_brutto': _forderungC.text.trim(),
      'gezahlt': _gezahltC.text.trim(),
      'notizen': _notizenC.text.trim(),
    };
    final res = await widget.apiService.saveVertragInkassoAktenzeichen(widget.vertragId, body);
    if (!mounted) return;
    setState(() => _saving = false);
    final ok = res['success'] == true;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Fehler'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Neues Aktenzeichen' : 'Aktenzeichen bearbeiten'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: _aktenC, decoration: const InputDecoration(labelText: 'Aktenzeichen *', prefixIcon: Icon(Icons.tag), border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _bezC, decoration: const InputDecoration(labelText: 'Bezeichnung', prefixIcon: Icon(Icons.label), border: OutlineInputBorder())),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status', prefixIcon: Icon(Icons.flag), border: OutlineInputBorder()),
              items: _AktenzeichenEditDialogState._statusOptions.map((s) => DropdownMenuItem(value: s.$1, child: Text(s.$2))).toList(),
              onChanged: (v) => setState(() => _status = v ?? 'offen'),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: _forderungC, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Forderung (€)', prefixIcon: Icon(Icons.euro), border: OutlineInputBorder()))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _gezahltC, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Gezahlt (€)', prefixIcon: Icon(Icons.payments), border: OutlineInputBorder()))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: InkWell(onTap: () => _pickDate(_eroeffnet, (d) => setState(() => _eroeffnet = d)),
                child: InputDecorator(decoration: const InputDecoration(labelText: 'Eröffnet', prefixIcon: Icon(Icons.date_range), border: OutlineInputBorder()), child: Text(_fmt(_eroeffnet))))),
              const SizedBox(width: 8),
              Expanded(child: InkWell(onTap: () => _pickDate(_frist, (d) => setState(() => _frist = d)),
                child: InputDecorator(decoration: const InputDecoration(labelText: 'Nächste Frist', prefixIcon: Icon(Icons.alarm), border: OutlineInputBorder()), child: Text(_fmt(_frist))))),
            ]),
            const SizedBox(height: 12),
            TextField(controller: _notizenC, maxLines: 3, decoration: const InputDecoration(labelText: 'Notizen', border: OutlineInputBorder())),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Abbrechen')),
        ElevatedButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 16),
          label: const Text('Speichern'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.purple.shade600, foregroundColor: Colors.white),
        ),
      ],
    );
  }

  static const _statusOptions = [
    ('offen', 'Offen'),
    ('in_bearbeitung', 'In Bearbeitung'),
    ('vergleich', 'Vergleich'),
    ('ratenzahlung', 'Ratenzahlung'),
    ('widerspruch', 'Widerspruch'),
    ('gerichtlich', 'Gerichtlich'),
    ('abgeschlossen', 'Abgeschlossen'),
    ('zurueckgewiesen', 'Zurückgewiesen'),
  ];
}

// ─── Aktenzeichen detail dialog (Details + Korrespondenz tabs) ───────

class _AktenzeichenDetailDialog extends StatelessWidget {
  final ApiService apiService;
  final int vertragId;
  final Map<String, dynamic> aktenzeichen;
  final VoidCallback onChanged;
  const _AktenzeichenDetailDialog({required this.apiService, required this.vertragId, required this.aktenzeichen, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: Colors.purple.shade700, borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
          child: Row(children: [
            const Icon(Icons.folder, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(
              aktenzeichen['aktenzeichen']?.toString() ?? '',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            )),
            IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
          ]),
        ),
        TabBar(
          labelColor: Colors.purple.shade700,
          indicatorColor: Colors.purple.shade700,
          tabs: const [
            Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Details'),
            Tab(icon: Icon(Icons.mail, size: 18), text: 'Korrespondenz'),
            Tab(icon: Icon(Icons.fact_check, size: 18), text: 'Akteneinsicht'),
          ],
        ),
        Expanded(child: TabBarView(children: [
          _AktenzeichenDetailsView(aktenzeichen: aktenzeichen),
          _AktenzeichenKorrTab(apiService: apiService, aktenzeichenId: aktenzeichen['id'] as int),
          _AktenzeichenAkteneinsichtTab(apiService: apiService, aktenzeichenId: aktenzeichen['id'] as int),
        ])),
      ]),
    );
  }
}

// ─── Akteneinsicht tab — multi-file uploader for documents requested ───
//     via Akteneinsicht. Up to 20 files at once, shown as a list with
//     individual delete/preview/download buttons. Each file is AES-CBC
//     encrypted server-side.
class _AktenzeichenAkteneinsichtTab extends StatefulWidget {
  final ApiService apiService;
  final int aktenzeichenId;
  const _AktenzeichenAkteneinsichtTab({required this.apiService, required this.aktenzeichenId});
  @override
  State<_AktenzeichenAkteneinsichtTab> createState() => _AktenzeichenAkteneinsichtTabState();
}

class _AktenzeichenAkteneinsichtTabState extends State<_AktenzeichenAkteneinsichtTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loaded = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final res = await widget.apiService.listInkassoAkteneinsichtDocs(widget.aktenzeichenId);
    if (!mounted) return;
    setState(() {
      _items = List<Map<String, dynamic>>.from(res['items'] as List? ?? []);
      _loaded = true;
    });
  }

  Future<void> _upload() async {
    final r = await FilePickerHelper.pickFiles(
      allowMultiple: true, type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx', 'odt', 'txt'],
    );
    if (r == null || r.files.isEmpty) return;
    var files = r.files.where((f) => f.path != null).toList();
    if (files.length > 20) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Max. 20 Dateien gleichzeitig — ${files.length - 20} ausgelassen'), backgroundColor: Colors.orange));
      files = files.sublist(0, 20);
    }
    int done = 0;
    final errors = <String>[];
    final scaffold = ScaffoldMessenger.of(context);
    for (final f in files) {
      final res = await widget.apiService.uploadInkassoDoc(
        type: 'akteneinsicht', parentId: widget.aktenzeichenId,
        filePath: f.path!, fileName: f.name,
      );
      if (res['success'] == true) { done++; } else { errors.add('${f.name}: ${res['message'] ?? '?'}'); }
    }
    if (!mounted) return;
    scaffold.showSnackBar(SnackBar(
      content: Text(errors.isEmpty
        ? '$done Datei(en) hochgeladen'
        : '$done OK, ${errors.length} fehlgeschlagen:\n${errors.join("\n")}'),
      backgroundColor: errors.isEmpty ? Colors.green : Colors.orange,
      duration: const Duration(seconds: 4),
    ));
    _load();
  }

  Future<void> _delete(int id) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Dokument löschen?'),
      content: const Text('Die Datei wird unwiderruflich entfernt.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen', style: TextStyle(color: Colors.red))),
      ],
    ));
    if (ok != true) return;
    await widget.apiService.deleteInkassoAkteneinsichtDoc(id);
    _load();
  }

  Future<void> _open(Map<String, dynamic> d, {bool externalApp = false}) async {
    try {
      final resp = await widget.apiService.downloadInkassoDoc(type: 'akteneinsicht', id: d['id'] as int);
      if (resp.statusCode != 200 || !mounted) return;
      final dir = await getTemporaryDirectory();
      final safeName = (d['datei_name']?.toString() ?? 'akteneinsicht_${d['id']}.pdf').replaceAll(RegExp(r'[<>:"|?*\\/]'), '_');
      final f = File('${dir.path}/$safeName');
      await f.writeAsBytes(resp.bodyBytes);
      if (externalApp) {
        await OpenFilex.open(f.path);
      } else if (mounted) {
        await FileViewerDialog.show(context, f.path, safeName);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(children: [
          Icon(Icons.fact_check, size: 18, color: Colors.purple.shade700),
          const SizedBox(width: 8),
          Text('${_items.length} Dokument(e)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple.shade700)),
          const Spacer(),
          ElevatedButton.icon(
            icon: const Icon(Icons.upload_file, size: 16),
            label: const Text('Hochladen (bis 20)'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple.shade600, foregroundColor: Colors.white),
            onPressed: _upload,
          ),
        ]),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        color: Colors.amber.shade50,
        child: Row(children: [
          Icon(Icons.info_outline, size: 14, color: Colors.amber.shade800),
          const SizedBox(width: 6),
          Expanded(child: Text(
            'Hier werden die Dokumente abgelegt, die bei der Inkasso-Firma '
            'per Akteneinsicht angefordert wurden (Forderungsunterlagen, '
            'Mahnungen, Verträge, Vollmachten, etc.).',
            style: TextStyle(fontSize: 11, color: Colors.amber.shade900))),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: _items.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.fact_check_outlined, size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 10),
              Text('Noch keine Akteneinsicht-Dokumente', style: TextStyle(color: Colors.grey.shade500)),
            ]))
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _items.length,
              itemBuilder: (ctx, i) {
                final d = _items[i];
                final kb = ((d['file_size'] as num?) ?? 0).toInt() ~/ 1024;
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.description, color: Colors.purple.shade400),
                    title: Text(d['datei_name']?.toString() ?? '?', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                    subtitle: Text('$kb KB · ${d['mime_type'] ?? ''} · ${d['erstellt_am'] ?? ''}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: const Icon(Icons.visibility, size: 18), tooltip: 'Anzeigen', onPressed: () => _open(d)),
                      IconButton(icon: Icon(Icons.download, size: 18, color: Colors.green.shade700), tooltip: 'Herunterladen', onPressed: () => _open(d, externalApp: true)),
                      IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red), onPressed: () => _delete(d['id'] as int)),
                    ]),
                  ),
                );
              },
            ),
      ),
    ]);
  }
}

class _AktenzeichenDetailsView extends StatelessWidget {
  final Map<String, dynamic> aktenzeichen;
  const _AktenzeichenDetailsView({required this.aktenzeichen});

  Widget _row(IconData icon, String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        SizedBox(width: 140, child: Text(label, style: TextStyle(color: Colors.grey.shade700, fontSize: 13))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = aktenzeichen;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _row(Icons.tag, 'Aktenzeichen', a['aktenzeichen']?.toString()),
        _row(Icons.label, 'Bezeichnung', a['bezeichnung']?.toString()),
        _row(Icons.flag, 'Status', a['status']?.toString()),
        _row(Icons.euro, 'Forderung', a['forderung_brutto']?.toString() != null && (a['forderung_brutto'] ?? '').toString().isNotEmpty ? '${a['forderung_brutto']} €' : null),
        _row(Icons.payments, 'Gezahlt', (a['gezahlt'] ?? '').toString().isNotEmpty ? '${a['gezahlt']} €' : null),
        _row(Icons.date_range, 'Eröffnet', a['eroeffnet_am']?.toString()),
        _row(Icons.event_available, 'Geschlossen', a['geschlossen_am']?.toString()),
        _row(Icons.alarm, 'Nächste Frist', a['naechste_frist']?.toString()),
        if ((a['notizen'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Notizen', style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
            child: Text(a['notizen'].toString()),
          ),
        ],
      ]),
    );
  }
}

class _AktenzeichenKorrTab extends StatefulWidget {
  final ApiService apiService;
  final int aktenzeichenId;
  const _AktenzeichenKorrTab({required this.apiService, required this.aktenzeichenId});

  @override
  State<_AktenzeichenKorrTab> createState() => _AktenzeichenKorrTabState();
}

class _AktenzeichenKorrTabState extends State<_AktenzeichenKorrTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loaded = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final res = await widget.apiService.listVertragInkassoKorrespondenz(widget.aktenzeichenId);
    if (!mounted) return;
    final data = res['data'] as Map<String, dynamic>? ?? res;
    setState(() {
      _items = List<Map<String, dynamic>>.from(data['items'] as List? ?? []);
      _loaded = true;
    });
  }

  Future<void> _addOrEdit({Map<String, dynamic>? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => _KorrEditDialog(apiService: widget.apiService, aktenzeichenId: widget.aktenzeichenId, existing: existing),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Korrespondenz löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    await widget.apiService.deleteVertragInkassoKorrespondenz(id);
    _load();
  }

  IconData _mediumIcon(String? m) {
    switch (m) {
      case 'email': return Icons.email;
      case 'brief': return Icons.markunread_mailbox;
      case 'fax': return Icons.fax;
      case 'telefon': return Icons.phone;
      case 'online': return Icons.language;
      case 'sms': return Icons.sms;
      default: return Icons.notes;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(children: [
          Icon(Icons.mail_outline, size: 18, color: Colors.purple.shade700),
          const SizedBox(width: 8),
          Text('${_items.length} Einträge', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple.shade700)),
          const Spacer(),
          ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Neu'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple.shade600, foregroundColor: Colors.white),
            onPressed: () => _addOrEdit(),
          ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: _items.isEmpty
            ? Center(child: Text('Keine Korrespondenz', style: TextStyle(color: Colors.grey.shade600)))
            : ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _items.length,
                itemBuilder: (ctx, i) {
                  final k = _items[i];
                  final eingehend = k['richtung'] == 'eingehend';
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: (eingehend ? Colors.blue : Colors.green).shade50,
                        child: Icon(_mediumIcon(k['medium']?.toString()), color: eingehend ? Colors.blue : Colors.green, size: 18),
                      ),
                      title: Text(k['betreff']?.toString() ?? '(ohne Betreff)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text(k['datum']?.toString() ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(color: (eingehend ? Colors.blue : Colors.green).shade50, borderRadius: BorderRadius.circular(4)),
                            child: Text(eingehend ? 'eingehend' : 'ausgehend', style: TextStyle(fontSize: 10, color: eingehend ? Colors.blue : Colors.green)),
                          ),
                        ]),
                        if ((k['text'] ?? '').toString().isNotEmpty)
                          Padding(padding: const EdgeInsets.only(top: 4), child: Text(k['text'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
                      ]),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: const Icon(Icons.edit_outlined, size: 16), onPressed: () => _addOrEdit(existing: k)),
                        IconButton(icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red), onPressed: () => _delete(k['id'] as int)),
                      ]),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}

class _KorrEditDialog extends StatefulWidget {
  final ApiService apiService;
  final int aktenzeichenId;
  final Map<String, dynamic>? existing;
  const _KorrEditDialog({required this.apiService, required this.aktenzeichenId, this.existing});

  @override
  State<_KorrEditDialog> createState() => _KorrEditDialogState();
}

class _KorrEditDialogState extends State<_KorrEditDialog> {
  late final TextEditingController _betreffC;
  late final TextEditingController _textC;
  late final TextEditingController _anhangC;
  late final TextEditingController _notizenC;
  DateTime _datum = DateTime.now();
  String _richtung = 'eingehend';
  String _medium = 'email';
  bool _erledigt = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing ?? <String, dynamic>{};
    _betreffC = TextEditingController(text: e['betreff']?.toString() ?? '');
    _textC = TextEditingController(text: e['text']?.toString() ?? '');
    _anhangC = TextEditingController(text: e['anhang_pfad']?.toString() ?? '');
    _notizenC = TextEditingController(text: e['notizen']?.toString() ?? '');
    final parsedDate = DateTime.tryParse(e['datum']?.toString() ?? '');
    if (parsedDate != null) _datum = parsedDate;
    _richtung = e['richtung']?.toString() ?? 'eingehend';
    _medium = e['medium']?.toString() ?? 'email';
    _erledigt = e['erledigt'] == 1 || e['erledigt'] == true;
  }

  @override
  void dispose() {
    _betreffC.dispose(); _textC.dispose(); _anhangC.dispose(); _notizenC.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final body = {
      if (widget.existing != null) 'id': widget.existing!['id'],
      'datum': _datum.toIso8601String().substring(0, 10),
      'richtung': _richtung,
      'medium': _medium,
      'erledigt': _erledigt ? 1 : 0,
      'betreff': _betreffC.text.trim(),
      'text': _textC.text.trim(),
      'anhang_pfad': _anhangC.text.trim(),
      'notizen': _notizenC.text.trim(),
    };
    final res = await widget.apiService.saveVertragInkassoKorrespondenz(widget.aktenzeichenId, body);
    if (!mounted) return;
    setState(() => _saving = false);
    final ok = res['success'] == true;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Fehler'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Neue Korrespondenz' : 'Korrespondenz bearbeiten'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: InkWell(
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: _datum, firstDate: DateTime(2010), lastDate: DateTime(2050));
                if (d != null) setState(() => _datum = d);
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Datum', prefixIcon: Icon(Icons.date_range), border: OutlineInputBorder()),
                child: Text('${_datum.day.toString().padLeft(2, '0')}.${_datum.month.toString().padLeft(2, '0')}.${_datum.year}'),
              ),
            )),
            const SizedBox(width: 8),
            Expanded(child: DropdownButtonFormField<String>(
              initialValue: _richtung,
              decoration: const InputDecoration(labelText: 'Richtung', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'eingehend', child: Text('Eingehend')),
                DropdownMenuItem(value: 'ausgehend', child: Text('Ausgehend')),
              ],
              onChanged: (v) => setState(() => _richtung = v ?? 'eingehend'),
            )),
            const SizedBox(width: 8),
            Expanded(child: DropdownButtonFormField<String>(
              initialValue: _medium,
              decoration: const InputDecoration(labelText: 'Medium', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'email', child: Text('E-Mail')),
                DropdownMenuItem(value: 'brief', child: Text('Brief')),
                DropdownMenuItem(value: 'fax', child: Text('Fax')),
                DropdownMenuItem(value: 'telefon', child: Text('Telefon')),
                DropdownMenuItem(value: 'online', child: Text('Online')),
                DropdownMenuItem(value: 'sms', child: Text('SMS')),
                DropdownMenuItem(value: 'sonstiges', child: Text('Sonstiges')),
              ],
              onChanged: (v) => setState(() => _medium = v ?? 'email'),
            )),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _betreffC, decoration: const InputDecoration(labelText: 'Betreff', prefixIcon: Icon(Icons.subject), border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _textC, maxLines: 5, decoration: const InputDecoration(labelText: 'Text / Inhalt', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _anhangC, decoration: const InputDecoration(labelText: 'Anhang-Hinweis (Pfad / URL — Dateien siehe unten)', prefixIcon: Icon(Icons.link, size: 18), border: OutlineInputBorder())),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _erledigt,
            onChanged: (v) => setState(() => _erledigt = v ?? false),
            title: const Text('Erledigt'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 4),
          TextField(controller: _notizenC, maxLines: 2, decoration: const InputDecoration(labelText: 'Notizen', border: OutlineInputBorder())),
          // Inline file attachments for this Korr entry. Available only
          // after the entry has been saved at least once (so we have an
          // id to attach files to). On a new entry we ask the user to
          // save first, then reopen to add files.
          if (widget.existing != null) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            _InkassoDocsSection(
              apiService: widget.apiService,
              type: 'korr',
              parentId: widget.existing!['id'] as int,
              colorScheme: Colors.purple,
              hintText: 'Anhänge zu diesem Korrespondenz-Eintrag (E-Mail-PDF, Brief-Scan, Quittung, …)',
            ),
          ] else ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.amber.shade200)),
              child: Row(children: [
                Icon(Icons.info_outline, size: 16, color: Colors.amber.shade800), const SizedBox(width: 6),
                const Expanded(child: Text('Anhänge können nach dem ersten Speichern hinzugefügt werden.', style: TextStyle(fontSize: 11))),
              ]),
            ),
          ],
        ])),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Abbrechen')),
        ElevatedButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 16),
          label: const Text('Speichern'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.purple.shade600, foregroundColor: Colors.white),
        ),
      ],
    );
  }
}

// ─── Reusable Inkasso docs section: works for both 'akteneinsicht'
// (parent = aktenzeichen_id) and 'korr' (parent = korr_id). Same
// list + multi-file upload (up to 20) + view/download/delete.
class _InkassoDocsSection extends StatefulWidget {
  final ApiService apiService;
  final String type; // 'akteneinsicht' | 'korr'
  final int parentId;
  final MaterialColor colorScheme;
  final String hintText;
  const _InkassoDocsSection({
    required this.apiService,
    required this.type,
    required this.parentId,
    this.colorScheme = Colors.purple,
    this.hintText = '',
  });
  @override
  State<_InkassoDocsSection> createState() => _InkassoDocsSectionState();
}

class _InkassoDocsSectionState extends State<_InkassoDocsSection> {
  List<Map<String, dynamic>> _items = [];
  bool _loaded = false;
  bool _uploading = false;
  int _doneCount = 0;
  int _totalCount = 0;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final res = widget.type == 'akteneinsicht'
      ? await widget.apiService.listInkassoAkteneinsichtDocs(widget.parentId)
      : await widget.apiService.listInkassoKorrDocs(widget.parentId);
    if (!mounted) return;
    setState(() {
      _items = List<Map<String, dynamic>>.from(res['items'] as List? ?? []);
      _loaded = true;
    });
  }

  Future<void> _upload() async {
    final r = await FilePickerHelper.pickFiles(
      allowMultiple: true, type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx', 'odt', 'txt'],
    );
    if (r == null || r.files.isEmpty) return;
    var files = r.files.where((f) => f.path != null).toList();
    final scaffold = ScaffoldMessenger.of(context);
    if (files.length > 20) {
      scaffold.showSnackBar(SnackBar(content: Text('Max. 20 Dateien — ${files.length - 20} ausgelassen'), backgroundColor: Colors.orange));
      files = files.sublist(0, 20);
    }
    setState(() { _uploading = true; _doneCount = 0; _totalCount = files.length; });
    final errors = <String>[];
    for (final f in files) {
      final res = await widget.apiService.uploadInkassoDoc(
        type: widget.type, parentId: widget.parentId,
        filePath: f.path!, fileName: f.name,
      );
      if (res['success'] == true) { _doneCount++; } else { errors.add('${f.name}: ${res['message'] ?? '?'}'); }
      if (mounted) setState(() {});
    }
    if (!mounted) return;
    setState(() => _uploading = false);
    scaffold.showSnackBar(SnackBar(
      content: Text(errors.isEmpty
        ? '$_doneCount/$_totalCount Datei(en) hochgeladen'
        : '$_doneCount OK, ${errors.length} fehlgeschlagen:\n${errors.join("\n")}'),
      backgroundColor: errors.isEmpty ? Colors.green : Colors.orange,
      duration: const Duration(seconds: 4),
    ));
    _load();
  }

  Future<void> _delete(int id) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Datei löschen?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen', style: TextStyle(color: Colors.red))),
      ],
    ));
    if (ok != true) return;
    final res = widget.type == 'akteneinsicht'
      ? await widget.apiService.deleteInkassoAkteneinsichtDoc(id)
      : await widget.apiService.deleteInkassoKorrDoc(id);
    if (res['success'] == true) _load();
  }

  Future<void> _open(Map<String, dynamic> d, {bool externalApp = false}) async {
    try {
      final resp = await widget.apiService.downloadInkassoDoc(type: widget.type, id: d['id'] as int);
      if (resp.statusCode != 200 || !mounted) return;
      final dir = await getTemporaryDirectory();
      final safeName = (d['datei_name']?.toString() ?? '${widget.type}_${d['id']}.pdf')
          .replaceAll(RegExp(r'[<>:"|?*\\/]'), '_');
      final f = File('${dir.path}/$safeName');
      await f.writeAsBytes(resp.bodyBytes);
      if (externalApp) {
        await OpenFilex.open(f.path);
      } else if (mounted) {
        await FileViewerDialog.show(context, f.path, safeName);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Padding(padding: EdgeInsets.all(8), child: Center(child: CircularProgressIndicator()));
    final cs = widget.colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Icon(Icons.folder_zip, size: 16, color: cs.shade700), const SizedBox(width: 6),
        Expanded(child: Text('${_items.length} Datei(en)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cs.shade800))),
        ElevatedButton.icon(
          onPressed: _uploading ? null : _upload,
          icon: _uploading
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.upload_file, size: 14),
          label: Text(
            _uploading
              ? (_totalCount > 0 ? '$_doneCount / $_totalCount …' : 'Lädt…')
              : 'Hochladen (bis 20)',
            style: const TextStyle(fontSize: 11),
          ),
          style: ElevatedButton.styleFrom(backgroundColor: cs.shade600, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), minimumSize: Size.zero),
        ),
      ]),
      if (widget.hintText.isNotEmpty) Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(widget.hintText, style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
      ),
      const SizedBox(height: 6),
      if (_items.isEmpty)
        Padding(padding: const EdgeInsets.all(8), child: Text('Keine Dateien', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)))
      else
        ..._items.map((d) {
          final kb = ((d['file_size'] as num?) ?? 0).toInt() ~/ 1024;
          return Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [
            Icon(Icons.description, size: 16, color: cs.shade400), const SizedBox(width: 6),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d['datei_name']?.toString() ?? '?', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
              Text('$kb KB · ${d['erstellt_am'] ?? ''}', style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
            ])),
            IconButton(icon: const Icon(Icons.visibility, size: 16), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28), tooltip: 'Anzeigen', onPressed: () => _open(d)),
            IconButton(icon: Icon(Icons.download, size: 16, color: Colors.green.shade700), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28), tooltip: 'Herunterladen', onPressed: () => _open(d, externalApp: true)),
            IconButton(icon: const Icon(Icons.close, size: 16, color: Colors.red), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28), onPressed: () => _delete(d['id'] as int)),
          ]));
        }),
    ]);
  }
}
