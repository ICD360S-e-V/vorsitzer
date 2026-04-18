import 'package:flutter/material.dart';
import '../services/api_service.dart';

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
        onTap: () => _showVertragDialog(existing: v),
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
}
