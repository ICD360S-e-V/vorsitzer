import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';
import 'file_viewer_dialog.dart';

/// Vorsitzer-only Kundenkarten / Treuekarten pro Mitglied ("Karten").
///
/// Backend (`mitglied_karten` + `mitglied_karten_doc`) speichert sensible
/// Spalten (Kartennummer, Barcode, PIN, Notiz) AES-256-CBC verschlüsselt;
/// Fotos auf Disk ebenfalls verschlüsselt. Der Shop-Katalog
/// (`shops_datenbank`) ist Klartext und dient als Auswahlliste.
///
/// Pilotphase: nur Vorsitzer (admin id 2) — Backend liefert 403 für andere.
class MitgliederKartenContent extends StatefulWidget {
  final ApiService apiService;
  final int userId;

  const MitgliederKartenContent({
    super.key,
    required this.apiService,
    required this.userId,
  });

  @override
  State<MitgliederKartenContent> createState() => _MitgliederKartenContentState();
}

/// Kategorie → (Label, Icon, Farbe). Von Shops und Karten geteilt.
const Map<String, (String, IconData, MaterialColor)> kartenKategorien = {
  'moebel':       ('Möbel',        Icons.chair,               Colors.brown),
  'elektronik':   ('Elektronik',   Icons.devices_other,       Colors.indigo),
  'lebensmittel': ('Lebensmittel', Icons.local_grocery_store, Colors.green),
  'drogerie':     ('Drogerie',     Icons.medical_services,    Colors.teal),
  'mode':         ('Mode',         Icons.checkroom,           Colors.pink),
  'sport':        ('Sport',        Icons.sports_soccer,       Colors.deepOrange),
  'bau':          ('Baumarkt',     Icons.handyman,            Colors.blueGrey),
  'sonstiges':    ('Sonstiges',    Icons.storefront,          Colors.grey),
};

/// Karten-Typ → Anzeigename.
const Map<String, String> kartenTypen = {
  'premium':        'Premium Card',
  'kundenkarte':    'Kundenkarte',
  'punktekarte':    'Punktekarte',
  'bonuskarte':     'Bonuskarte',
  'mitgliedskarte': 'Mitgliedskarte',
  'gutschein':      'Gutscheinkarte',
  'sonstiges':      'Sonstige',
};

(String, IconData, MaterialColor) katMeta(String? k) =>
    kartenKategorien[k] ?? kartenKategorien['sonstiges']!;

class _MitgliederKartenContentState extends State<MitgliederKartenContent> {
  List<Map<String, dynamic>> _karten = [];
  List<Map<String, dynamic>> _shops = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        widget.apiService.listMitgliedKarten(widget.userId),
        widget.apiService.listShops(),
      ]);
      if (!mounted) return;
      final kr = results[0];
      final sr = results[1];
      if (kr['success'] == true) {
        setState(() {
          _karten = List<Map<String, dynamic>>.from(kr['items'] ?? const []);
          _shops = sr['success'] == true
              ? List<Map<String, dynamic>>.from(sr['items'] ?? const [])
              : <Map<String, dynamic>>[];
          _loading = false;
        });
      } else {
        setState(() {
          _error = (kr['message'] ?? 'Laden fehlgeschlagen').toString();
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  List<Map<String, dynamic>> _kartenForShop(Map<String, dynamic> shop) {
    final id = shop['id'];
    final name = (shop['name'] ?? '').toString().trim().toLowerCase();
    return _karten.where((k) {
      if (k['shop_id'] != null && id != null && k['shop_id'] == id) return true;
      return (k['shop_name'] ?? '').toString().trim().toLowerCase() == name && name.isNotEmpty;
    }).toList();
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

    return DefaultTabController(
      length: 2,
      child: Column(children: [
        Container(
          color: Colors.grey.shade100,
          child: TabBar(
            labelColor: Colors.deepPurple.shade700,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: Colors.deepPurple.shade700,
            tabs: [
              const Tab(icon: Icon(Icons.storefront, size: 18), text: 'Zuständiger Shop'),
              Tab(icon: const Icon(Icons.loyalty, size: 18), text: 'Meine Karten (${_karten.length})'),
            ],
          ),
        ),
        // Banner DSGVO
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: Colors.amber.shade50,
          child: Row(children: [
            Icon(Icons.privacy_tip_outlined, size: 14, color: Colors.amber.shade800),
            const SizedBox(width: 6),
            Expanded(child: Text(
              'Pilotphase – nur Vorsitzender. Kundenkarten-Daten sind verschlüsselt gespeichert.',
              style: TextStyle(fontSize: 11, color: Colors.amber.shade900),
            )),
          ]),
        ),
        Expanded(child: TabBarView(children: [
          _buildShopsTab(),
          _buildKartenTab(),
        ])),
      ]),
    );
  }

  // ─── Tab 1: Zuständiger Shop ──────────────────────────────────
  Widget _buildShopsTab() {
    if (_shops.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.storefront_outlined, size: 56, color: Colors.grey.shade400),
        const SizedBox(height: 12),
        Text('Keine Shops im Katalog', style: TextStyle(color: Colors.grey.shade600)),
      ]));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: _shops.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) => _shopCard(_shops[i]),
    );
  }

  Widget _shopCard(Map<String, dynamic> shop) {
    final (katLabel, katIcon, katColor) = katMeta(shop['kategorie']?.toString());
    final name = (shop['name'] ?? '').toString();
    final ort = (shop['ort'] ?? '').toString().trim();
    final anzahl = _kartenForShop(shop).length;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: katColor.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openShopDetail(shop),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: katColor.shade50, borderRadius: BorderRadius.circular(6)),
              child: Icon(katIcon, color: katColor.shade700, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: katColor.shade50, borderRadius: BorderRadius.circular(4)),
                  child: Text(katLabel, style: TextStyle(fontSize: 10, color: katColor.shade700)),
                ),
                if (ort.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.place, size: 11, color: Colors.grey.shade600),
                  const SizedBox(width: 2),
                  Text(ort, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                ],
              ]),
            ])),
            if (anzahl > 0)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.deepPurple.shade50, borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.loyalty, size: 12, color: Colors.deepPurple.shade400),
                  const SizedBox(width: 3),
                  Text('$anzahl', style: TextStyle(fontSize: 11, color: Colors.deepPurple.shade700, fontWeight: FontWeight.bold)),
                ]),
              ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ]),
        ),
      ),
    );
  }

  Future<void> _openShopDetail(Map<String, dynamic> shop) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ShopDetailDialog(
        apiService: widget.apiService,
        userId: widget.userId,
        shop: shop,
        karten: _kartenForShop(shop),
        shops: _shops,
      ),
    );
    if (changed == true) _load();
  }

  // ─── Tab 2: Meine Karten ──────────────────────────────────────
  Widget _buildKartenTab() {
    return Column(children: [
      Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        color: Colors.grey.shade50,
        child: Row(children: [
          Icon(Icons.loyalty, color: Colors.deepPurple.shade700),
          const SizedBox(width: 8),
          Text('Karten', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade800)),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () => _openKarteEdit(null),
            icon: const Icon(Icons.add),
            label: const Text('Neue Karte'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple.shade600, foregroundColor: Colors.white),
          ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(child: _karten.isEmpty
        ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.loyalty_outlined, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text('Noch keine Karten erfasst', style: TextStyle(color: Colors.grey.shade600)),
          ]))
        : ListView.separated(
            padding: const EdgeInsets.all(8),
            itemCount: _karten.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (_, i) => _karteCard(_karten[i]),
          )),
    ]);
  }

  Widget _karteCard(Map<String, dynamic> k) {
    final (_, katIcon, katColor) = katMeta(k['shop_kategorie']?.toString());
    final shopName = (k['shop_name'] ?? '').toString().trim();
    final typ = kartenTypen[k['karten_typ']] ?? (k['karten_typ'] ?? '').toString();
    final nr = (k['kartennummer'] ?? '').toString().trim();
    final docCount = (k['doc_count'] is int) ? k['doc_count'] as int : 0;
    final gueltig = _fmtDate(k['gueltig_bis']?.toString());
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: katColor.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openKarteEdit(k),
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
                Expanded(child: Text(shopName.isEmpty ? (k['bezeichnung'] ?? 'Karte').toString() : shopName,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                if (typ.toString().isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.deepPurple.shade50, borderRadius: BorderRadius.circular(4)),
                    child: Text(typ, style: TextStyle(fontSize: 10, color: Colors.deepPurple.shade700, fontWeight: FontWeight.w600)),
                  ),
              ]),
              const SizedBox(height: 3),
              Row(children: [
                Icon(Icons.credit_card, size: 12, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(nr.isEmpty ? '—' : _maskNr(nr), style: TextStyle(fontSize: 12, color: Colors.grey.shade800)),
                const Spacer(),
                if (gueltig != '—') ...[
                  Icon(Icons.event_available, size: 11, color: Colors.grey.shade600),
                  const SizedBox(width: 3),
                  Text('bis $gueltig', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                  const SizedBox(width: 10),
                ],
                Icon(Icons.photo, size: 12, color: docCount > 0 ? Colors.deepPurple : Colors.grey.shade400),
                const SizedBox(width: 2),
                Text('$docCount', style: TextStyle(fontSize: 11, color: docCount > 0 ? Colors.deepPurple : Colors.grey.shade500)),
              ]),
            ])),
          ]),
        ),
      ),
    );
  }

  Future<void> _openKarteEdit(Map<String, dynamic>? existing, {Map<String, dynamic>? prefillShop}) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => KarteEditDialog(
        apiService: widget.apiService,
        userId: widget.userId,
        karte: existing,
        shops: _shops,
        prefillShop: prefillShop,
      ),
    );
    if (changed == true) _load();
  }

  String _fmtDate(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try { return DateFormat('dd.MM.yyyy').format(DateTime.parse(raw)); }
    catch (_) { return raw; }
  }

  String _maskNr(String nr) {
    final clean = nr.replaceAll(' ', '');
    if (clean.length <= 4) return nr;
    return '•••• ${clean.substring(clean.length - 4)}';
  }
}

// ═══════════════════════════════════════════════════════════════
// Shop-Detail: Info + Karten des Mitglieds bei diesem Shop
// ═══════════════════════════════════════════════════════════════

class _ShopDetailDialog extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final Map<String, dynamic> shop;
  final List<Map<String, dynamic>> karten;
  final List<Map<String, dynamic>> shops;
  const _ShopDetailDialog({
    required this.apiService,
    required this.userId,
    required this.shop,
    required this.karten,
    required this.shops,
  });
  @override
  State<_ShopDetailDialog> createState() => _ShopDetailDialogState();
}

class _ShopDetailDialogState extends State<_ShopDetailDialog> {
  bool _dirty = false;

  Future<void> _addKarte() async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => KarteEditDialog(
        apiService: widget.apiService,
        userId: widget.userId,
        karte: null,
        shops: widget.shops,
        prefillShop: widget.shop,
      ),
    );
    if (changed == true) { _dirty = true; if (mounted) Navigator.pop(context, true); }
  }

  Future<void> _openKarte(Map<String, dynamic> k) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => KarteEditDialog(
        apiService: widget.apiService,
        userId: widget.userId,
        karte: k,
        shops: widget.shops,
        prefillShop: widget.shop,
      ),
    );
    if (changed == true) { _dirty = true; if (mounted) Navigator.pop(context, true); }
  }

  @override
  Widget build(BuildContext context) {
    final shop = widget.shop;
    final (katLabel, katIcon, katColor) = katMeta(shop['kategorie']?.toString());
    final adresse = (shop['adresse'] ?? '').toString().trim();
    final website = (shop['website'] ?? '').toString().trim();
    final beschr = (shop['beschreibung'] ?? '').toString().trim();
    final vorteile = (shop['standard_vorteile'] ?? '').toString().trim();
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: SizedBox(
        width: 640,
        height: 620,
        child: Column(children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            decoration: BoxDecoration(color: katColor.shade50),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: katColor.shade100, borderRadius: BorderRadius.circular(8)),
                child: Icon(katIcon, color: katColor.shade700),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((shop['name'] ?? '').toString(), style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: katColor.shade900)),
                Text(katLabel, style: TextStyle(fontSize: 12, color: katColor.shade700)),
              ])),
              IconButton(onPressed: () => Navigator.pop(context, _dirty), icon: const Icon(Icons.close)),
            ]),
          ),
          Expanded(child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (beschr.isNotEmpty) ...[
                Text(beschr, style: TextStyle(fontSize: 13, color: Colors.grey.shade800)),
                const SizedBox(height: 12),
              ],
              if (adresse.isNotEmpty) _infoRow(Icons.place, 'Adresse', adresse),
              if (website.isNotEmpty) _infoRow(Icons.language, 'Website', website),
              if (vorteile.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.card_giftcard, size: 16, color: Colors.green.shade700),
                      const SizedBox(width: 6),
                      Text('Karten-Vorteile', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                    ]),
                    const SizedBox(height: 6),
                    Text(vorteile, style: TextStyle(fontSize: 12, color: Colors.green.shade900)),
                  ]),
                ),
              ],
              const SizedBox(height: 16),
              Row(children: [
                Icon(Icons.loyalty, size: 16, color: Colors.deepPurple.shade600),
                const SizedBox(width: 6),
                Text('Karten dieses Mitglieds (${widget.karten.length})',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade800)),
              ]),
              const SizedBox(height: 8),
              if (widget.karten.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('Noch keine Karte für diesen Shop.', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                )
              else
                ...widget.karten.map((k) {
                  final typ = kartenTypen[k['karten_typ']] ?? (k['karten_typ'] ?? '').toString();
                  final nr = (k['kartennummer'] ?? '').toString().trim();
                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade300)),
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.credit_card, color: Colors.deepPurple.shade400),
                      title: Text(typ.toString().isEmpty ? 'Karte' : typ.toString(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text(nr.isEmpty ? (k['bezeichnung'] ?? '').toString() : nr, style: const TextStyle(fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () => _openKarte(k),
                    ),
                  );
                }),
            ],
          )),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.grey.shade50, border: Border(top: BorderSide(color: Colors.grey.shade300))),
            child: Row(children: [
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _addKarte,
                icon: const Icon(Icons.add_card, size: 18),
                label: const Text('Neue Karte für diesen Shop'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple.shade600, foregroundColor: Colors.white),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        SizedBox(width: 70, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Karte anlegen / bearbeiten
// ═══════════════════════════════════════════════════════════════

class KarteEditDialog extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final Map<String, dynamic>? karte;
  final List<Map<String, dynamic>> shops;
  final Map<String, dynamic>? prefillShop;
  const KarteEditDialog({
    super.key,
    required this.apiService,
    required this.userId,
    required this.karte,
    required this.shops,
    this.prefillShop,
  });
  @override
  State<KarteEditDialog> createState() => _KarteEditDialogState();
}

class _KarteEditDialogState extends State<KarteEditDialog> with SingleTickerProviderStateMixin {
  late final TextEditingController _shopName;
  late final TextEditingController _bezeichnung;
  late final TextEditingController _kartennummer;
  late final TextEditingController _barcode;
  late final TextEditingController _pin;
  late final TextEditingController _vorteile;
  late final TextEditingController _notiz;
  late DateTime? _ausgestelltAm;
  late DateTime? _gueltigBis;
  late String _kartenTyp;
  int? _shopId;
  late final TabController _tabCtl;

  int? _id;
  String? _uuid;
  bool _saving = false;
  bool _dirty = false;
  bool _editMode = true;
  bool _obscurePin = true;
  int _docCount = 0;

  @override
  void initState() {
    super.initState();
    final k = widget.karte ?? const <String, dynamic>{};
    _id = k['id'] as int?;
    _uuid = k['uuid'] as String?;
    _shopId = k['shop_id'] as int?;
    _kartenTyp = (k['karten_typ'] ?? 'kundenkarte').toString();
    _shopName     = TextEditingController(text: (k['shop_name']    ?? '').toString());
    _bezeichnung  = TextEditingController(text: (k['bezeichnung']  ?? '').toString());
    _kartennummer = TextEditingController(text: (k['kartennummer'] ?? '').toString());
    _barcode      = TextEditingController(text: (k['barcode']      ?? '').toString());
    _pin          = TextEditingController(text: (k['pin']          ?? '').toString());
    _vorteile     = TextEditingController(text: (k['vorteile']     ?? '').toString());
    _notiz        = TextEditingController(text: (k['notiz']        ?? '').toString());
    _ausgestelltAm = _parseDate(k['ausgestellt_am']?.toString());
    _gueltigBis    = _parseDate(k['gueltig_bis']?.toString());
    _docCount = (k['doc_count'] is int) ? k['doc_count'] as int : 0;
    _editMode = widget.karte == null;

    // Vorbelegung aus Shop (Neuanlage aus Shop-Detail)
    if (widget.karte == null && widget.prefillShop != null) {
      final s = widget.prefillShop!;
      _shopId = s['id'] as int?;
      _shopName.text = (s['name'] ?? '').toString();
      final sv = (s['standard_vorteile'] ?? '').toString();
      if (_vorteile.text.trim().isEmpty && sv.isNotEmpty) _vorteile.text = sv;
    }

    for (final c in [_shopName, _bezeichnung, _kartennummer, _barcode, _pin, _vorteile, _notiz]) {
      c.addListener(() { if (_editMode && !_dirty) setState(() => _dirty = true); });
    }
    _tabCtl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _shopName.dispose(); _bezeichnung.dispose(); _kartennummer.dispose();
    _barcode.dispose(); _pin.dispose(); _vorteile.dispose(); _notiz.dispose();
    _tabCtl.dispose();
    super.dispose();
  }

  DateTime? _parseDate(String? s) {
    if (s == null || s.isEmpty) return null;
    try { return DateTime.parse(s); } catch (_) { return null; }
  }
  String? _fmtIso(DateTime? d) => d == null ? null : DateFormat('yyyy-MM-dd').format(d);

  void _onShopSelected(int? shopId) {
    setState(() {
      _shopId = shopId;
      _dirty = true;
      if (shopId != null) {
        final s = widget.shops.firstWhere((e) => e['id'] == shopId, orElse: () => const {});
        if (s.isNotEmpty) {
          _shopName.text = (s['name'] ?? '').toString();
          final sv = (s['standard_vorteile'] ?? '').toString();
          if (_vorteile.text.trim().isEmpty && sv.isNotEmpty) _vorteile.text = sv;
        }
      }
    });
  }

  Future<void> _save({bool closeAfter = true}) async {
    setState(() => _saving = true);
    final body = {
      if (_id != null) 'id': _id,
      if (_uuid != null) 'uuid': _uuid,
      'shop_id'        : _shopId,
      'shop_name'      : _shopName.text.trim(),
      'karten_typ'     : _kartenTyp,
      'bezeichnung'    : _bezeichnung.text.trim(),
      'kartennummer'   : _kartennummer.text.trim(),
      'barcode'        : _barcode.text.trim(),
      'pin'            : _pin.text.trim(),
      'vorteile'       : _vorteile.text.trim(),
      'ausgestellt_am' : _fmtIso(_ausgestelltAm) ?? '',
      'gueltig_bis'    : _fmtIso(_gueltigBis) ?? '',
      'notiz'          : _notiz.text.trim(),
    };
    final r = await widget.apiService.saveMitgliedKarte(widget.userId, body);
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
        setState(() { _editMode = false; });
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
      title: const Text('Karte löschen?'),
      content: const Text('Alle Fotos werden ebenfalls entfernt. Diese Aktion ist endgültig.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen', style: TextStyle(color: Colors.red))),
      ],
    ));
    if (ok != true) return;
    final r = await widget.apiService.deleteMitgliedKarte(_id!);
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
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              color: Colors.deepPurple.shade50,
              child: Row(children: [
                Icon(Icons.loyalty, color: Colors.deepPurple.shade700),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  isNew ? 'Neue Karte' : (_editMode ? 'Karte bearbeiten' : 'Karten-Details'),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade900),
                )),
                if (_id != null && !_editMode)
                  IconButton(onPressed: () => setState(() => _editMode = true), icon: const Icon(Icons.edit), color: Colors.deepPurple.shade700, tooltip: 'Bearbeiten'),
                if (_id != null && _editMode)
                  IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline, color: Colors.red), tooltip: 'Löschen'),
                IconButton(onPressed: () async { if (await _confirmClose() && mounted) Navigator.pop(context, _id != null); }, icon: const Icon(Icons.close)),
              ]),
            ),
            TabBar(
              controller: _tabCtl,
              labelColor: Colors.deepPurple.shade700,
              unselectedLabelColor: Colors.grey.shade600,
              indicatorColor: Colors.deepPurple.shade700,
              tabs: [
                const Tab(icon: Icon(Icons.edit_note, size: 18), text: 'Details'),
                Tab(icon: const Icon(Icons.photo_camera, size: 18), text: 'Foto ($_docCount)'),
              ],
            ),
            Expanded(child: TabBarView(controller: _tabCtl, children: [
              _buildDetails(),
              _buildDocs(),
            ])),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.grey.shade50, border: Border(top: BorderSide(color: Colors.grey.shade300))),
              child: Row(children: [
                const Spacer(),
                if (_editMode && !isNew)
                  TextButton(onPressed: _saving ? null : () => setState(() => _editMode = false), child: const Text('Abbrechen'))
                else
                  TextButton(onPressed: _saving ? null : () async { if (await _confirmClose() && mounted) Navigator.pop(context, _id != null); }, child: const Text('Schließen')),
                if (_editMode) ...[
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : () => _save(closeAfter: false),
                    icon: const Icon(Icons.photo_camera, size: 16),
                    label: const Text('Speichern + Foto'),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton.icon(
                    onPressed: _saving ? null : () => _save(closeAfter: true),
                    icon: _saving
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save, size: 16),
                    label: Text(_saving ? 'Speichert…' : 'Speichern'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple.shade600, foregroundColor: Colors.white),
                  ),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildDetails() {
    final ro = !_editMode;
    final fillColor = ro ? Colors.grey.shade50 : null;
    InputDecoration deco(String label, {IconData? icon, String? hint, bool alignTop = false, Widget? suffix}) => InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon) : null,
      suffixIcon: suffix,
      border: const OutlineInputBorder(),
      filled: ro, fillColor: fillColor,
      alignLabelWithHint: alignTop,
    );
    // Shop-Dropdown-Items: manuell + Katalog
    final shopItems = <DropdownMenuItem<int?>>[
      const DropdownMenuItem<int?>(value: null, child: Text('— manuell eingeben —')),
      ...widget.shops.map((s) => DropdownMenuItem<int?>(
        value: s['id'] as int?,
        child: Text((s['name'] ?? '').toString(), overflow: TextOverflow.ellipsis),
      )),
    ];
    // Falls die Karte einen shop_id hat, der nicht (mehr) im Katalog ist → auf manuell
    final validShopId = _shopId != null && widget.shops.any((s) => s['id'] == _shopId) ? _shopId : null;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DropdownButtonFormField<int?>(
          initialValue: validShopId,
          decoration: deco('Shop (aus Katalog)', icon: Icons.storefront),
          items: shopItems,
          onChanged: ro ? null : _onShopSelected,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _shopName,
          readOnly: ro,
          decoration: deco('Shop-Name', icon: Icons.store, hint: 'z. B. Möbel Inhofer'),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: DropdownButtonFormField<String>(
            initialValue: kartenTypen.containsKey(_kartenTyp) ? _kartenTyp : 'kundenkarte',
            decoration: deco('Karten-Typ', icon: Icons.style),
            items: kartenTypen.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
            onChanged: ro ? null : (v) { if (v != null) setState(() { _kartenTyp = v; _dirty = true; }); },
          )),
          const SizedBox(width: 10),
          Expanded(child: TextField(
            controller: _bezeichnung,
            readOnly: ro,
            decoration: deco('Bezeichnung', icon: Icons.label_outline, hint: 'optional'),
          )),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _kartennummer,
          readOnly: ro,
          decoration: deco('Kartennummer', icon: Icons.credit_card),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _barcode,
          readOnly: ro,
          decoration: deco('Barcode / EAN', icon: Icons.qr_code_2, hint: 'Nummer unter dem Strichcode'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pin,
          readOnly: ro,
          obscureText: _obscurePin,
          decoration: deco('PIN / Passwort', icon: Icons.lock_outline, suffix: IconButton(
            icon: Icon(_obscurePin ? Icons.visibility : Icons.visibility_off, size: 18),
            onPressed: () => setState(() => _obscurePin = !_obscurePin),
          )),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _DateField(
            label: 'Ausgestellt am',
            icon: Icons.event,
            value: _ausgestelltAm,
            enabled: !ro,
            onPick: (d) => setState(() { _ausgestelltAm = d; _dirty = true; }),
          )),
          const SizedBox(width: 10),
          Expanded(child: _DateField(
            label: 'Gültig bis',
            icon: Icons.event_available,
            value: _gueltigBis,
            enabled: !ro,
            onPick: (d) => setState(() { _gueltigBis = d; _dirty = true; }),
          )),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _vorteile,
          readOnly: ro,
          minLines: 3, maxLines: 8,
          decoration: deco('Vorteile', icon: Icons.card_giftcard, hint: 'Rabatte, Punkte, Aktionen …', alignTop: true),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notiz,
          readOnly: ro,
          minLines: 2, maxLines: 4,
          decoration: deco('Notiz', icon: Icons.sticky_note_2_outlined),
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
            const Text('Erst speichern – dann können Fotos angehängt werden', textAlign: TextAlign.center),
          ]),
        ),
      );
    }
    return _KartenDocsSection(
      apiService: widget.apiService,
      kartenId: _id!,
      userId: widget.userId,
      kartenUuid: _uuid!,
      onCountChanged: (n) { if (mounted) setState(() => _docCount = n); },
    );
  }
}

// ─── Inline date picker field ─────────────────────────────────

class _DateField extends StatelessWidget {
  final String label;
  final IconData icon;
  final DateTime? value;
  final ValueChanged<DateTime?> onPick;
  final bool enabled;
  const _DateField({required this.label, required this.icon, required this.value, required this.onPick, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: !enabled ? null : () async {
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
          filled: !enabled,
          fillColor: !enabled ? Colors.grey.shade50 : null,
          suffixIcon: (enabled && value != null)
              ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () => onPick(null))
              : null,
        ),
        child: Text(value == null ? '—' : DateFormat('dd.MM.yyyy').format(value!)),
      ),
    );
  }
}

// ─── Foto sub-tab ─────────────────────────────────────────────

class _KartenDocsSection extends StatefulWidget {
  final ApiService apiService;
  final int kartenId;
  final int userId;
  final String kartenUuid;
  final ValueChanged<int>? onCountChanged;
  const _KartenDocsSection({
    required this.apiService,
    required this.kartenId,
    required this.userId,
    required this.kartenUuid,
    this.onCountChanged,
  });
  @override
  State<_KartenDocsSection> createState() => _KartenDocsSectionState();
}

class _KartenDocsSectionState extends State<_KartenDocsSection> {
  List<Map<String, dynamic>> _items = [];
  bool _loaded = false;
  bool _uploading = false;
  int _doneCount = 0, _totalCount = 0;
  String _selectedType = 'foto_vorne';

  static const _typeMap = <String, (String, IconData, MaterialColor)>{
    'foto_vorne':  ('Vorderseite', Icons.crop_portrait, Colors.deepPurple),
    'foto_hinten': ('Rückseite',   Icons.flip_to_back,  Colors.indigo),
    'sonstiges':   ('Sonstiges',   Icons.attach_file,   Colors.grey),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.apiService.listMitgliedKartenDocs(kartenId: widget.kartenId);
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
        final r = await widget.apiService.uploadMitgliedKartenDoc(
          kartenId: widget.kartenId,
          userId: widget.userId,
          kartenUuid: widget.kartenUuid,
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
      title: const Text('Foto löschen?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen', style: TextStyle(color: Colors.red))),
      ],
    ));
    if (ok != true) return;
    final r = await widget.apiService.deleteMitgliedKartenDoc(id);
    if (r['success'] == true) _load();
  }

  Future<void> _open(Map<String, dynamic> d, {bool externalApp = false}) async {
    try {
      final resp = await widget.apiService.downloadMitgliedKartenDoc(d['id'] as int);
      if (resp.statusCode != 200 || !mounted) return;
      final dir = await getTemporaryDirectory();
      final raw = (d['filename']?.toString() ?? 'karte_${d['id']}');
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple.shade600, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), minimumSize: Size.zero),
          ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(child: _items.isEmpty
        ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.photo_camera_outlined, size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text('Noch kein Foto angehängt', style: TextStyle(color: Colors.grey.shade600)),
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
