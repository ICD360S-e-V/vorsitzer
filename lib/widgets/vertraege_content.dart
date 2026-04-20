import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';
import 'file_viewer_dialog.dart';

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
    ('strom_gas', 'Strom & Gas', Icons.bolt, Colors.orange),
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
            children: _kategorien.map((k) => _buildKategorieTab(k.$1, k.$2, k.$3, k.$4)).toList(),
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
                  onSelected: (_) => setD(() { selKat = k.$1; anbieterC.clear(); tarifC.clear(); kostenC.clear(); }),
                );
              }).toList()),
              const SizedBox(height: 12),
              if (vorschlaege.isNotEmpty)
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
                TextField(controller: tarifC, decoration: InputDecoration(labelText: 'Tarif / Paket', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(
                  controller: kostenC,
                  readOnly: kostenReadonly,
                  keyboardType: TextInputType.number,
                  style: TextStyle(fontSize: 14, color: kostenReadonly ? Colors.green.shade800 : null, fontWeight: kostenReadonly ? FontWeight.bold : null),
                  decoration: InputDecoration(
                    labelText: 'Kosten €/Monat',
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
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 580, height: 560,
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
      length: 5,
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
          labelColor: Colors.indigo.shade700,
          indicatorColor: Colors.indigo.shade700,
          tabs: const [
            Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Details'),
            Tab(icon: Icon(Icons.mail, size: 18), text: 'Korrespondenz'),
            Tab(icon: Icon(Icons.folder, size: 18), text: 'Dokumente'),
            Tab(icon: Icon(Icons.receipt, size: 18), text: 'Rechnung'),
            Tab(icon: Icon(Icons.cancel, size: 18), text: 'Kündigung'),
          ],
        ),
        Expanded(child: TabBarView(children: [
          _buildDetailsTab(v, aktiv),
          _KorrTab(apiService: widget.apiService, vertragId: int.tryParse(v['id']?.toString() ?? '') ?? 0),
          _DokTab(apiService: widget.apiService, vertragId: int.tryParse(v['id']?.toString() ?? '') ?? 0, kategorie: 'dokument', label: 'Dokumente'),
          _DokTab(apiService: widget.apiService, vertragId: int.tryParse(v['id']?.toString() ?? '') ?? 0, kategorie: 'rechnung', label: 'Rechnungen'),
          _DokTab(apiService: widget.apiService, vertragId: int.tryParse(v['id']?.toString() ?? '') ?? 0, kategorie: 'kuendigung', label: 'Kündigung'),
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
class _DokTab extends StatefulWidget {
  final ApiService apiService;
  final int vertragId;
  final String kategorie;
  final String label;
  const _DokTab({required this.apiService, required this.vertragId, required this.kategorie, required this.label});

  @override
  State<_DokTab> createState() => _DokTabState();
}

class _DokTabState extends State<_DokTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loaded = false;

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
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
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

  IconData _iconForKat() => switch (widget.kategorie) { 'rechnung' => Icons.receipt, 'kuendigung' => Icons.cancel, _ => Icons.description };

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
    String? filePath;
    String? fileName;
    bool uploading = false;
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
              onTap: () async {
                final r = await FilePickerHelper.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
                if (r != null && r.files.isNotEmpty && r.files.first.path != null) {
                  setD(() { filePath = r.files.first.path; fileName = r.files.first.name; });
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity, padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: filePath != null ? Colors.green.shade50 : Colors.grey.shade100, borderRadius: BorderRadius.circular(8), border: Border.all(color: filePath != null ? Colors.green.shade300 : Colors.grey.shade300)),
                child: Row(children: [
                  Icon(filePath != null ? Icons.check_circle : Icons.upload_file, size: 22, color: filePath != null ? Colors.green.shade700 : Colors.grey.shade500),
                  const SizedBox(width: 10),
                  Expanded(child: Text(fileName ?? 'Datei auswählen *', style: TextStyle(fontSize: 13, color: filePath != null ? Colors.green.shade900 : Colors.grey.shade600))),
                ]),
              ),
            ),
          ])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton.icon(
            icon: uploading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.upload_file, size: 16),
            label: Text(uploading ? 'Wird hochgeladen...' : 'Hochladen'),
            onPressed: (filePath == null || uploading) ? null : () async {
              setD(() => uploading = true);
              final res = await widget.apiService.uploadVertragDokument(
                vertragId: widget.vertragId,
                kategorie: widget.kategorie,
                filePath: filePath!,
                fileName: fileName!,
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
              if (!ctx.mounted) return;
              if (res['success'] == true) {
                Navigator.pop(ctx);
                _load();
              } else {
                setD(() => uploading = false);
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(res['message']?.toString() ?? 'Fehler'), backgroundColor: Colors.red));
              }
            },
          ),
        ],
      )),
    );
  }
}
