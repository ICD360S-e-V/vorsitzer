import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';
import 'file_viewer_dialog.dart';

/// Vorsitzer-only digital inventory per member ("Einkaufen").
///
/// Backend stores every text column AES-256-CBC encrypted (NU JSON blob)
/// in `mitglied_einkauf` + `mitglied_einkauf_doc`. Files on disk are also
/// AES-256-CBC encrypted.
///
/// Pilot phase: only the Vorsitzer (admin id 2) can read/write — backend
/// returns 403 for any other admin. UI surfaces that gracefully.
class EinkaufenTabContent extends StatefulWidget {
  final ApiService apiService;
  final int userId;

  const EinkaufenTabContent({
    super.key,
    required this.apiService,
    required this.userId,
  });

  @override
  State<EinkaufenTabContent> createState() => _EinkaufenTabContentState();
}

class _EinkaufenTabContentState extends State<EinkaufenTabContent> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  String _filterKategorie = 'alle';

  static const _kategorien = <String, (String, IconData, MaterialColor)>{
    'elektronik':   ('Elektronik',     Icons.devices_other,    Colors.indigo),
    'moebel':       ('Möbel',          Icons.chair,            Colors.brown),
    'haushalt':     ('Haushaltsgeräte', Icons.kitchen,          Colors.teal),
    'kleidung':     ('Kleidung',       Icons.checkroom,        Colors.pink),
    'schmuck':      ('Schmuck',        Icons.diamond,          Colors.amber),
    'werkzeug':     ('Werkzeug',       Icons.handyman,         Colors.deepOrange),
    'fahrzeug':     ('Fahrzeug',       Icons.directions_car,   Colors.blueGrey),
    'lebensmittel': ('Lebensmittel',   Icons.local_grocery_store, Colors.green),
    'sonstiges':    ('Sonstiges',      Icons.shopping_bag,     Colors.grey),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await widget.apiService.listMitgliedEinkauf(widget.userId);
      if (!mounted) return;
      if (r['success'] == true) {
        setState(() {
          _items = List<Map<String, dynamic>>.from(r['items'] ?? const []);
          _loading = false;
        });
      } else {
        setState(() {
          _error = (r['message'] ?? 'Laden fehlgeschlagen').toString();
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filterKategorie == 'alle') return _items;
    return _items.where((e) => (e['kategorie'] ?? '') == _filterKategorie).toList();
  }

  String _fmtDate(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try { return DateFormat('dd.MM.yyyy').format(DateTime.parse(raw)); }
    catch (_) { return raw; }
  }

  String _fmtBetrag(String? raw, String waehrung) {
    if (raw == null || raw.isEmpty) return '—';
    return '$raw $waehrung';
  }

  (String, IconData, MaterialColor) _katMeta(String? k) {
    return _kategorien[k] ?? _kategorien['sonstiges']!;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.lock_outline, color: Colors.red.shade400, size: 40),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.red.shade700)),
            const SizedBox(height: 16),
            TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Erneut versuchen')),
          ]),
        ),
      );
    }

    final list = _filtered;
    return Column(children: [
      // Header
      Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        color: Colors.grey.shade50,
        child: Row(children: [
          Icon(Icons.shopping_bag, color: Colors.indigo.shade700),
          const SizedBox(width: 8),
          Text('Einkaufen', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: Colors.indigo.shade100, borderRadius: BorderRadius.circular(10)),
            child: Text('${_items.length}', style: TextStyle(fontSize: 12, color: Colors.indigo.shade800, fontWeight: FontWeight.bold)),
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () => _openEdit(null),
            icon: const Icon(Icons.add),
            label: const Text('Neuer Einkauf'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade600, foregroundColor: Colors.white),
          ),
        ]),
      ),
      // Banner DSGVO
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        color: Colors.amber.shade50,
        child: Row(children: [
          Icon(Icons.privacy_tip_outlined, size: 14, color: Colors.amber.shade800),
          const SizedBox(width: 6),
          Expanded(child: Text(
            'Pilotphase – nur Vorsitzender. Spätere Mitglied-Sichtbarkeit erfordert schriftliche Einwilligung (DSGVO Art. 6 (1) (a)).',
            style: TextStyle(fontSize: 11, color: Colors.amber.shade900),
          )),
        ]),
      ),
      // Filter chips
      SizedBox(height: 44, child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          _chip('Alle', 'alle', null),
          ..._kategorien.entries.map((e) => _chip(e.value.$1, e.key, e.value.$2)),
        ],
      )),
      const Divider(height: 1),
      Expanded(child: list.isEmpty
        ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.shopping_bag_outlined, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(_filterKategorie == 'alle' ? 'Noch keine Einkäufe erfasst' : 'Keine Einträge in dieser Kategorie',
                style: TextStyle(color: Colors.grey.shade600)),
          ]))
        : ListView.separated(
            padding: const EdgeInsets.all(8),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (_, i) => _card(list[i]),
          )),
    ]);
  }

  Widget _chip(String label, String value, IconData? icon) {
    final selected = _filterKategorie == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        avatar: icon != null ? Icon(icon, size: 14) : null,
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) => setState(() => _filterKategorie = value),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _card(Map<String, dynamic> e) {
    final (katLabel, katIcon, katColor) = _katMeta(e['kategorie']);
    final docCount = (e['doc_count'] is int) ? e['doc_count'] as int : 0;
    final haendler = (e['haendler']?.toString() ?? '').trim();
    final betrag = _fmtBetrag(e['gesamtbetrag']?.toString(), e['waehrung']?.toString() ?? 'EUR');
    final beschr = (e['beschreibung']?.toString() ?? '').trim();
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: katColor.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openEdit(e),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: katColor.shade50, borderRadius: BorderRadius.circular(6)),
              child: Icon(katIcon, color: katColor.shade700, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(haendler.isEmpty ? katLabel : haendler,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(betrag, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: katColor.shade700)),
              ]),
              const SizedBox(height: 2),
              Row(children: [
                Icon(Icons.calendar_today, size: 11, color: Colors.grey.shade600),
                const SizedBox(width: 3),
                Text(_fmtDate(e['datum']?.toString()), style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: katColor.shade50, borderRadius: BorderRadius.circular(4)),
                  child: Text(katLabel, style: TextStyle(fontSize: 10, color: katColor.shade700)),
                ),
                const Spacer(),
                Icon(Icons.attach_file, size: 11, color: docCount > 0 ? Colors.indigo : Colors.grey.shade400),
                const SizedBox(width: 2),
                Text('$docCount', style: TextStyle(fontSize: 11, color: docCount > 0 ? Colors.indigo : Colors.grey.shade500)),
              ]),
              if (beschr.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(beschr, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade800)),
              ],
            ])),
          ]),
        ),
      ),
    );
  }

  Future<void> _openEdit(Map<String, dynamic>? existing) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EinkaufEditDialog(
        apiService: widget.apiService,
        userId: widget.userId,
        einkauf: existing,
        kategorien: _kategorien,
      ),
    );
    if (changed == true) _load();
  }
}

// ─── Edit/Create modal ─────────────────────────────────────────

class _EinkaufEditDialog extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final Map<String, dynamic>? einkauf;
  final Map<String, (String, IconData, MaterialColor)> kategorien;
  const _EinkaufEditDialog({
    required this.apiService,
    required this.userId,
    required this.einkauf,
    required this.kategorien,
  });
  @override
  State<_EinkaufEditDialog> createState() => _EinkaufEditDialogState();
}

class _EinkaufEditDialogState extends State<_EinkaufEditDialog> with SingleTickerProviderStateMixin {
  late final TextEditingController _haendler;
  late final TextEditingController _betrag;
  late final TextEditingController _waehrung;
  late final TextEditingController _beschreibung;
  late final TextEditingController _seriennummer;
  late final TextEditingController _notiz;
  late DateTime? _datum;
  late DateTime? _garantieBis;
  late String _kategorie;
  late final TabController _tabCtl;

  int? _id;
  String? _uuid;
  bool _saving = false;
  bool _dirty = false;
  int _docCount = 0;

  @override
  void initState() {
    super.initState();
    final e = widget.einkauf ?? const <String, dynamic>{};
    _id = e['id'] as int?;
    _uuid = e['uuid'] as String?;
    _haendler     = TextEditingController(text: (e['haendler']     ?? '').toString());
    _betrag       = TextEditingController(text: (e['gesamtbetrag'] ?? '').toString());
    _waehrung     = TextEditingController(text: (e['waehrung']     ?? 'EUR').toString());
    _beschreibung = TextEditingController(text: (e['beschreibung'] ?? '').toString());
    _seriennummer = TextEditingController(text: (e['seriennummer'] ?? '').toString());
    _notiz        = TextEditingController(text: (e['notiz']        ?? '').toString());
    _kategorie    = (e['kategorie']    ?? 'sonstiges').toString();
    _datum       = _parseDate(e['datum']?.toString());
    _garantieBis = _parseDate(e['garantie_bis']?.toString());
    _docCount    = (e['doc_count'] is int) ? e['doc_count'] as int : 0;
    for (final c in [_haendler, _betrag, _waehrung, _beschreibung, _seriennummer, _notiz]) {
      c.addListener(() { if (!_dirty) setState(() => _dirty = true); });
    }
    _tabCtl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _haendler.dispose(); _betrag.dispose(); _waehrung.dispose();
    _beschreibung.dispose(); _seriennummer.dispose(); _notiz.dispose();
    _tabCtl.dispose();
    super.dispose();
  }

  DateTime? _parseDate(String? s) {
    if (s == null || s.isEmpty) return null;
    try { return DateTime.parse(s); } catch (_) { return null; }
  }
  String? _fmtIso(DateTime? d) => d == null ? null : DateFormat('yyyy-MM-dd').format(d);

  Future<void> _save({bool closeAfter = true}) async {
    setState(() => _saving = true);
    final body = {
      if (_id != null) 'id': _id,
      if (_uuid != null) 'uuid': _uuid,
      'datum'        : _fmtIso(_datum),
      'kategorie'    : _kategorie,
      'haendler'     : _haendler.text.trim(),
      'gesamtbetrag' : _betrag.text.trim(),
      'waehrung'     : _waehrung.text.trim().isEmpty ? 'EUR' : _waehrung.text.trim().toUpperCase(),
      'beschreibung' : _beschreibung.text.trim(),
      'seriennummer' : _seriennummer.text.trim(),
      'garantie_bis' : _fmtIso(_garantieBis) ?? '',
      'notiz'        : _notiz.text.trim(),
    };
    final r = await widget.apiService.saveMitgliedEinkauf(widget.userId, body);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['success'] == true) {
      _id ??= r['id'] as int?;
      _uuid ??= r['uuid'] as String?;
      _dirty = false;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gespeichert'), backgroundColor: Colors.green, duration: Duration(seconds: 2)));
      if (closeAfter) {
        Navigator.pop(context, true);
      } else {
        setState(() {});
        // Switch to Belege tab so user can immediately attach files
        _tabCtl.animateTo(1);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r['message']?.toString() ?? 'Fehler beim Speichern'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _delete() async {
    if (_id == null) { Navigator.pop(context, false); return; }
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Einkauf löschen?'),
      content: const Text('Alle Dateien werden ebenfalls entfernt. Diese Aktion ist endgültig.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen', style: TextStyle(color: Colors.red))),
      ],
    ));
    if (ok != true) return;
    final r = await widget.apiService.deleteMitgliedEinkauf(_id!);
    if (!mounted) return;
    if (r['success'] == true) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r['message']?.toString() ?? 'Löschen fehlgeschlagen'), backgroundColor: Colors.red));
    }
  }

  Future<bool> _confirmClose() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Ungespeicherte Änderungen'),
      content: const Text('Schließen ohne Speichern?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Verwerfen', style: TextStyle(color: Colors.red))),
      ],
    ));
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final isNew = _id == null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmClose() && mounted) Navigator.pop(context, _id != null);
      },
      child: Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: SizedBox(
          width: 700,
          height: 640,
          child: Column(children: [
              // Title bar
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                color: Colors.indigo.shade50,
                child: Row(children: [
                  Icon(Icons.shopping_bag, color: Colors.indigo.shade700),
                  const SizedBox(width: 8),
                  Expanded(child: Text(isNew ? 'Neuer Einkauf' : 'Einkauf bearbeiten',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo.shade900))),
                  if (_id != null)
                    IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline, color: Colors.red), tooltip: 'Löschen'),
                  IconButton(onPressed: () async { if (await _confirmClose() && mounted) Navigator.pop(context, _id != null); }, icon: const Icon(Icons.close)),
                ]),
              ),
              TabBar(
                controller: _tabCtl,
                labelColor: Colors.indigo.shade700,
                unselectedLabelColor: Colors.grey.shade600,
                indicatorColor: Colors.indigo.shade700,
                tabs: [
                  const Tab(icon: Icon(Icons.edit_note, size: 18), text: 'Details'),
                  Tab(icon: const Icon(Icons.attach_file, size: 18), text: 'Belege (${_docCount})'),
                ],
              ),
              Expanded(child: TabBarView(controller: _tabCtl, children: [
                _buildDetails(),
                _buildDocs(),
              ])),
              // Footer
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.grey.shade50, border: Border(top: BorderSide(color: Colors.grey.shade300))),
                child: Row(children: [
                  if (!isNew && _uuid != null)
                    Expanded(child: Text('UUID: ${_uuid!}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis))
                  else
                    const Spacer(),
                  TextButton(onPressed: _saving ? null : () async { if (await _confirmClose() && mounted) Navigator.pop(context, _id != null); }, child: const Text('Schließen')),
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : () => _save(closeAfter: false),
                    icon: const Icon(Icons.attach_file, size: 16),
                    label: const Text('Speichern + Belege'),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton.icon(
                    onPressed: _saving ? null : () => _save(closeAfter: true),
                    icon: _saving
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save, size: 16),
                    label: Text(_saving ? 'Speichert…' : 'Speichern'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade600, foregroundColor: Colors.white),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      );
  }

  Widget _buildDetails() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Datum + Kategorie
        Row(children: [
          Expanded(child: _DateField(
            label: 'Datum',
            icon: Icons.calendar_today,
            value: _datum,
            onPick: (d) => setState(() { _datum = d; _dirty = true; }),
          )),
          const SizedBox(width: 10),
          Expanded(child: DropdownButtonFormField<String>(
            initialValue: _kategorie,
            decoration: const InputDecoration(labelText: 'Kategorie', border: OutlineInputBorder(), prefixIcon: Icon(Icons.category)),
            items: widget.kategorien.entries.map((e) => DropdownMenuItem(
              value: e.key,
              child: Row(children: [Icon(e.value.$2, size: 16, color: e.value.$3.shade600), const SizedBox(width: 6), Text(e.value.$1)]),
            )).toList(),
            onChanged: (v) { if (v != null) setState(() { _kategorie = v; _dirty = true; }); },
          )),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _haendler,
          decoration: const InputDecoration(labelText: 'Händler / Geschäft', border: OutlineInputBorder(), prefixIcon: Icon(Icons.storefront)),
        ),
        const SizedBox(height: 12),
        // Betrag + Währung
        Row(children: [
          Expanded(flex: 3, child: TextField(
            controller: _betrag,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Gesamtbetrag', border: OutlineInputBorder(), prefixIcon: Icon(Icons.euro)),
          )),
          const SizedBox(width: 10),
          Expanded(flex: 1, child: TextField(
            controller: _waehrung,
            decoration: const InputDecoration(labelText: 'Währung', border: OutlineInputBorder()),
            textCapitalization: TextCapitalization.characters,
          )),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _beschreibung,
          minLines: 3, maxLines: 8,
          decoration: const InputDecoration(
            labelText: 'Beschreibung / Produkte',
            hintText: '1× Samsung TV 55"\n1× Sony Soundbar HT-S400',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _seriennummer,
          decoration: const InputDecoration(
            labelText: 'Seriennummer(n)',
            hintText: 'z. B. SN1234567890 — wichtig im Diebstahlfall',
            border: OutlineInputBorder(), prefixIcon: Icon(Icons.qr_code_2),
          ),
        ),
        const SizedBox(height: 12),
        _DateField(
          label: 'Garantie bis',
          icon: Icons.shield_outlined,
          value: _garantieBis,
          onPick: (d) => setState(() { _garantieBis = d; _dirty = true; }),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notiz,
          minLines: 2, maxLines: 4,
          decoration: const InputDecoration(labelText: 'Notiz', border: OutlineInputBorder(), prefixIcon: Icon(Icons.sticky_note_2_outlined)),
        ),
      ]),
    );
  }

  Widget _buildDocs() {
    if (_id == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.save_outlined, size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text('Erst speichern – dann können Belege angehängt werden', textAlign: TextAlign.center),
          ]),
        ),
      );
    }
    return _EinkaufDocsSection(
      apiService: widget.apiService,
      einkaufId: _id!,
      userId: widget.userId,
      einkaufUuid: _uuid!,
      onCountChanged: (n) {
        if (mounted) setState(() => _docCount = n);
      },
    );
  }
}

// ─── Inline date picker field ─────────────────────────────────

class _DateField extends StatelessWidget {
  final String label;
  final IconData icon;
  final DateTime? value;
  final ValueChanged<DateTime?> onPick;
  const _DateField({required this.label, required this.icon, required this.value, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(1990),
          lastDate: DateTime(2099),
        );
        if (picked != null) onPick(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          prefixIcon: Icon(icon),
          suffixIcon: value != null
              ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () => onPick(null))
              : null,
        ),
        child: Text(value == null ? '—' : DateFormat('dd.MM.yyyy').format(value!)),
      ),
    );
  }
}

// ─── Docs sub-tab ─────────────────────────────────────────────

class _EinkaufDocsSection extends StatefulWidget {
  final ApiService apiService;
  final int einkaufId;
  final int userId;
  final String einkaufUuid;
  final ValueChanged<int>? onCountChanged;
  const _EinkaufDocsSection({
    required this.apiService,
    required this.einkaufId,
    required this.userId,
    required this.einkaufUuid,
    this.onCountChanged,
  });
  @override
  State<_EinkaufDocsSection> createState() => _EinkaufDocsSectionState();
}

class _EinkaufDocsSectionState extends State<_EinkaufDocsSection> {
  List<Map<String, dynamic>> _items = [];
  bool _loaded = false;
  bool _uploading = false;
  int _doneCount = 0, _totalCount = 0;
  String _selectedType = 'rechnung';

  static const _typeMap = <String, (String, IconData, MaterialColor)>{
    'rechnung':  ('Rechnung',  Icons.receipt_long, Colors.indigo),
    'foto':      ('Foto',      Icons.photo,        Colors.teal),
    'garantie':  ('Garantie',  Icons.shield,       Colors.green),
    'sonstiges': ('Sonstiges', Icons.attach_file,  Colors.grey),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.apiService.listMitgliedEinkaufDocs(einkaufId: widget.einkaufId);
    if (!mounted) return;
    if (r['success'] == true) {
      setState(() {
        _items = List<Map<String, dynamic>>.from(r['items'] ?? const []);
        _loaded = true;
      });
      widget.onCountChanged?.call(_items.length);
    } else {
      setState(() => _loaded = true);
    }
  }

  Future<void> _upload() async {
    final pick = await FilePickerHelper.pickFiles(allowMultiple: true);
    if (pick == null || pick.files.isEmpty) return;
    final files = pick.files.where((f) => f.path != null).toList();
    if (files.isEmpty) return;
    if (files.length > 20) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Max 20 Dateien gleichzeitig')));
      return;
    }
    setState(() { _uploading = true; _doneCount = 0; _totalCount = files.length; });
    final errors = <String>[];
    for (final f in files) {
      try {
        final r = await widget.apiService.uploadMitgliedEinkaufDoc(
          einkaufId: widget.einkaufId,
          userId: widget.userId,
          einkaufUuid: widget.einkaufUuid,
          docType: _selectedType,
          filePath: f.path!,
          fileName: f.name,
        );
        if (r['success'] != true) errors.add('${f.name}: ${r['message'] ?? 'Fehler'}');
      } catch (e) {
        errors.add('${f.name}: $e');
      }
      if (mounted) setState(() => _doneCount++);
    }
    if (!mounted) return;
    setState(() => _uploading = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
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
    final r = await widget.apiService.deleteMitgliedEinkaufDoc(id);
    if (r['success'] == true) _load();
  }

  Future<void> _open(Map<String, dynamic> d, {bool externalApp = false}) async {
    try {
      final resp = await widget.apiService.downloadMitgliedEinkaufDoc(d['id'] as int);
      if (resp.statusCode != 200 || !mounted) return;
      final dir = await getTemporaryDirectory();
      final raw = (d['filename']?.toString() ?? 'einkauf_${d['id']}');
      final safeName = raw.replaceAll(RegExp(r'[<>:"|?*\\/]'), '_');
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

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Row(children: [
          DropdownButton<String>(
            value: _selectedType,
            isDense: true,
            items: _typeMap.entries.map((e) => DropdownMenuItem(
              value: e.key,
              child: Row(children: [Icon(e.value.$2, size: 14, color: e.value.$3.shade600), const SizedBox(width: 4), Text(e.value.$1, style: const TextStyle(fontSize: 12))]),
            )).toList(),
            onChanged: (v) { if (v != null) setState(() => _selectedType = v); },
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _uploading ? null : _upload,
            icon: _uploading
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.upload_file, size: 14),
            label: Text(_uploading
                ? (_totalCount > 0 ? '$_doneCount / $_totalCount …' : 'Lädt…')
                : 'Hochladen (bis 20)', style: const TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade600, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), minimumSize: Size.zero),
          ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(child: _items.isEmpty
        ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.attach_file, size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text('Noch keine Belege angehängt', style: TextStyle(color: Colors.grey.shade600)),
          ]))
        : ListView.separated(
            padding: const EdgeInsets.all(8),
            itemCount: _items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final d = _items[i];
              final t = _typeMap[d['doc_type']] ?? _typeMap['sonstiges']!;
              return ListTile(
                dense: true,
                leading: Icon(t.$2, color: t.$3.shade600),
                title: Text(d['filename']?.toString() ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${t.$1} · ${_fmtSize(d['size_bytes'] as int? ?? 0)} · ${d['uploaded_at']?.toString().substring(0, 10) ?? ''}', style: const TextStyle(fontSize: 11)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: const Icon(Icons.visibility, size: 18), tooltip: 'Anzeigen', onPressed: () => _open(d)),
                  IconButton(icon: const Icon(Icons.open_in_new, size: 18), tooltip: 'Mit App öffnen', onPressed: () => _open(d, externalApp: true)),
                  IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red), tooltip: 'Löschen', onPressed: () => _delete(d['id'] as int)),
                ]),
              );
            },
          )),
    ]);
  }
}
