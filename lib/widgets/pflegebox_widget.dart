import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';
import 'file_viewer_dialog.dart';

/// DB-backed Pflegebox firma picker. Tapping the selected firma card opens
/// a dialog with 3 tabs: Details / Korrespondenz / Lieferungen.
class PflegeboxSection extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int? selectedFirmaId;
  final String selectedFirmaName;
  final ValueChanged<Map<String, dynamic>?> onFirmaChanged;

  const PflegeboxSection({
    super.key,
    required this.apiService,
    required this.userId,
    required this.selectedFirmaId,
    required this.selectedFirmaName,
    required this.onFirmaChanged,
  });

  @override
  State<PflegeboxSection> createState() => _PflegeboxSectionState();
}

class _PflegeboxSectionState extends State<PflegeboxSection> {
  List<Map<String, dynamic>> _firmen = [];
  bool _firmenLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadFirmen();
  }

  Future<void> _loadFirmen() async {
    try {
      final r = await widget.apiService.listPflegeboxFirmen();
      if (r['success'] == true && r['data'] is List) {
        if (mounted) {
          setState(() {
            _firmen = (r['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
            _firmenLoaded = true;
          });
        }
      }
    } catch (e) {
      debugPrint('[Pflegebox] firmen load error: $e');
    }
  }

  Map<String, dynamic>? _firmaById(int? id) {
    if (id == null) return null;
    for (final f in _firmen) {
      if ((f['id'] as int?) == id) return f;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final selected = _firmaById(widget.selectedFirmaId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.business, size: 18, color: Colors.green.shade700),
          const SizedBox(width: 6),
          Text('Anbieter / Firma', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.green.shade800)),
          const Spacer(),
          TextButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Neu', style: TextStyle(fontSize: 12)),
            onPressed: () => _showAddFirmaDialog(),
          ),
        ]),
        const SizedBox(height: 4),
        if (!_firmenLoaded)
          const LinearProgressIndicator(minHeight: 2)
        else
          Autocomplete<Map<String, dynamic>>(
            initialValue: TextEditingValue(
              text: selected != null
                  ? '${selected['firma_name']}${selected['brand'] != null && selected['brand'].toString().isNotEmpty ? ' – ${selected['brand']}' : ''}'
                  : widget.selectedFirmaName,
            ),
            displayStringForOption: (f) {
              final brand = f['brand']?.toString() ?? '';
              return brand.isNotEmpty ? '${f['firma_name']} – $brand' : '${f['firma_name']}';
            },
            optionsBuilder: (value) {
              if (value.text.isEmpty) return _firmen;
              final q = value.text.toLowerCase();
              return _firmen.where((f) =>
                (f['firma_name']?.toString().toLowerCase().contains(q) ?? false) ||
                (f['brand']?.toString().toLowerCase().contains(q) ?? false) ||
                (f['plz_ort']?.toString().toLowerCase().contains(q) ?? false));
            },
            fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                decoration: InputDecoration(
                  hintText: 'Firma suchen oder wählen...',
                  prefixIcon: const Icon(Icons.business, size: 18),
                  suffixIcon: selected != null
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            controller.clear();
                            widget.onFirmaChanged(null);
                          },
                        )
                      : const Icon(Icons.arrow_drop_down, size: 24),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                style: const TextStyle(fontSize: 13),
              );
            },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280, maxWidth: 520),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (ctx, i) {
                        final f = options.elementAt(i);
                        final brand = f['brand']?.toString() ?? '';
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: Colors.green.shade100,
                            child: Text(
                              (f['firma_name']?.toString() ?? '?').substring(0, 1),
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                            ),
                          ),
                          title: Text('${f['firma_name']}', style: const TextStyle(fontSize: 13)),
                          subtitle: Text(
                            [if (brand.isNotEmpty) brand, f['plz_ort'] ?? ''].where((s) => s.toString().isNotEmpty).join(' · '),
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                          onTap: () => onSelected(f),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
            onSelected: (f) {
              widget.onFirmaChanged(f);
            },
          ),
        if (selected != null) ...[
          const SizedBox(height: 10),
          InkWell(
            onTap: () => _showFirmaDetailDialog(selected),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green.shade50, Colors.green.shade100],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.shade300, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.green.shade600,
                      child: Text(
                        (selected['firma_name']?.toString() ?? '?').substring(0, 1),
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selected['firma_name']?.toString() ?? '',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green.shade900),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if ((selected['brand']?.toString() ?? '').isNotEmpty)
                            Text(
                              selected['brand'].toString(),
                              style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.w600),
                            ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Colors.green.shade700),
                  ]),
                  const SizedBox(height: 6),
                  if ((selected['plz_ort']?.toString() ?? '').isNotEmpty)
                    Row(children: [
                      Icon(Icons.location_on, size: 12, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${selected['strasse'] ?? ''}${selected['strasse'] != null && selected['plz_ort'] != null ? ', ' : ''}${selected['plz_ort'] ?? ''}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                        ),
                      ),
                    ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    _statBadge(Icons.info_outline, 'Details'),
                    const SizedBox(width: 6),
                    _statBadge(Icons.mail, 'Korrespondenz'),
                    const SizedBox(width: 6),
                    _statBadge(Icons.local_shipping, 'Lieferungen'),
                    const Spacer(),
                    Text('Antippen zum Öffnen', style: TextStyle(fontSize: 10, color: Colors.green.shade700, fontStyle: FontStyle.italic)),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _statBadge(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green.shade300)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: Colors.green.shade700),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.green.shade800, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  // ============ FIRMA DETAIL DIALOG (3 tabs) ============
  void _showFirmaDetailDialog(Map<String, dynamic> firma) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 640,
          height: 640,
          child: _FirmaDetailView(
            apiService: widget.apiService,
            userId: widget.userId,
            firma: firma,
            onFirmaUpdated: (updated) {
              _loadFirmen();
              widget.onFirmaChanged(updated);
            },
          ),
        ),
      ),
    );
  }

  // ============ ADD/EDIT FIRMA DIALOG ============
  void _showAddFirmaDialog({Map<String, dynamic>? existing}) {
    final nameC = TextEditingController(text: existing?['firma_name']?.toString() ?? '');
    final brandC = TextEditingController(text: existing?['brand']?.toString() ?? '');
    final strasseC = TextEditingController(text: existing?['strasse']?.toString() ?? '');
    final plzOrtC = TextEditingController(text: existing?['plz_ort']?.toString() ?? '');
    final telC = TextEditingController(text: existing?['telefon']?.toString() ?? '');
    final faxC = TextEditingController(text: existing?['fax']?.toString() ?? '');
    final emailC = TextEditingController(text: existing?['email']?.toString() ?? '');
    final webC = TextEditingController(text: existing?['website']?.toString() ?? '');
    final ikC = TextEditingController(text: existing?['ik_nummer']?.toString() ?? '');
    final hrC = TextEditingController(text: existing?['handelsregister']?.toString() ?? '');
    final notizC = TextEditingController(text: existing?['notizen']?.toString() ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Neue Pflegebox-Firma' : 'Firma bearbeiten'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _txt(nameC, 'Firmenname*', Icons.business),
                _txt(brandC, 'Brand / Produktname (z.B. sanus+, curabox)', Icons.label),
                _txt(strasseC, 'Straße', Icons.home),
                _txt(plzOrtC, 'PLZ Ort', Icons.location_city),
                _txt(telC, 'Telefon', Icons.phone),
                _txt(faxC, 'Fax', Icons.fax),
                _txt(emailC, 'E-Mail', Icons.email),
                _txt(webC, 'Website', Icons.language),
                _txt(ikC, 'IK-Nummer (Pflegekasse)', Icons.qr_code),
                _txt(hrC, 'Handelsregister', Icons.gavel),
                _txt(notizC, 'Notizen', Icons.note, maxLines: 2),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () async {
              if (nameC.text.trim().isEmpty) return;
              final payload = {
                if (existing != null) 'id': existing['id'],
                'firma_name': nameC.text.trim(),
                'brand': brandC.text.trim(),
                'strasse': strasseC.text.trim(),
                'plz_ort': plzOrtC.text.trim(),
                'telefon': telC.text.trim(),
                'fax': faxC.text.trim(),
                'email': emailC.text.trim(),
                'website': webC.text.trim(),
                'ik_nummer': ikC.text.trim(),
                'handelsregister': hrC.text.trim(),
                'notizen': notizC.text.trim(),
              };
              final res = existing == null
                  ? await widget.apiService.addPflegeboxFirma(payload)
                  : await widget.apiService.updatePflegeboxFirma(payload);
              if (!ctx.mounted) return;
              if (res['success'] == true) {
                Navigator.pop(ctx);
                await _loadFirmen();
                if (existing == null && res['firma'] is Map) {
                  widget.onFirmaChanged(Map<String, dynamic>.from(res['firma'] as Map));
                }
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(res['message']?.toString() ?? 'Fehler'), backgroundColor: Colors.red),
                );
              }
            },
            child: Text(existing == null ? 'Hinzufügen' : 'Speichern'),
          ),
        ],
      ),
    );
  }

  Widget _txt(TextEditingController c, String label, IconData icon, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 18),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        style: const TextStyle(fontSize: 13),
      ),
    );
  }
}

// ============================================================
// Firma detail dialog inner view (Details / Korrespondenz / Lieferungen)
// ============================================================
class _FirmaDetailView extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final Map<String, dynamic> firma;
  final ValueChanged<Map<String, dynamic>?> onFirmaUpdated;

  const _FirmaDetailView({
    required this.apiService,
    required this.userId,
    required this.firma,
    required this.onFirmaUpdated,
  });

  @override
  State<_FirmaDetailView> createState() => _FirmaDetailViewState();
}

class _FirmaDetailViewState extends State<_FirmaDetailView> {
  late Map<String, dynamic> _firma;

  @override
  void initState() {
    super.initState();
    _firma = Map<String, dynamic>.from(widget.firma);
  }

  @override
  Widget build(BuildContext context) {
    final brand = _firma['brand']?.toString() ?? '';
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.green.shade700, Colors.green.shade500]),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.white,
                child: Text(
                  (_firma['firma_name']?.toString() ?? '?').substring(0, 1),
                  style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _firma['firma_name']?.toString() ?? '',
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    if (brand.isNotEmpty) Text(brand, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ]),
          ),
          Container(
            color: Colors.green.shade700,
            child: const TabBar(
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: [
                Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Details'),
                Tab(icon: Icon(Icons.mail, size: 18), text: 'Korrespondenz'),
                Tab(icon: Icon(Icons.local_shipping, size: 18), text: 'Lieferungen'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(children: [
              _buildDetailsTab(),
              _KorrespondenzTab(apiService: widget.apiService, userId: widget.userId, firmaId: _firma['id'] as int),
              _LieferungenTab(apiService: widget.apiService, userId: widget.userId, firmaId: _firma['id'] as int),
            ]),
          ),
        ],
      ),
    );
  }

  // ============ DETAILS TAB ============
  Widget _buildDetailsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Firmendaten', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
            const Spacer(),
            OutlinedButton.icon(
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('Bearbeiten', style: TextStyle(fontSize: 12)),
              onPressed: () => _editFirma(),
            ),
          ]),
          const Divider(height: 20),
          _detail(Icons.business, 'Firma', _firma['firma_name']),
          _detail(Icons.label, 'Brand', _firma['brand']),
          _detail(Icons.home, 'Straße', _firma['strasse']),
          _detail(Icons.location_city, 'PLZ Ort', _firma['plz_ort']),
          _detail(Icons.phone, 'Telefon', _firma['telefon']),
          _detail(Icons.fax, 'Fax', _firma['fax']),
          _detail(Icons.email, 'E-Mail', _firma['email']),
          _detail(Icons.language, 'Website', _firma['website']),
          _detail(Icons.qr_code, 'IK-Nummer', _firma['ik_nummer']),
          _detail(Icons.gavel, 'Handelsregister', _firma['handelsregister']),
          _detail(Icons.badge, 'USt-ID', _firma['ust_id']),
          if ((_firma['notizen']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.yellow.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.yellow.shade200)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.note, size: 14, color: Colors.orange.shade700),
                const SizedBox(width: 6),
                Expanded(child: Text(_firma['notizen'].toString(), style: const TextStyle(fontSize: 12))),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detail(IconData icon, String label, dynamic value) {
    final s = value?.toString() ?? '';
    if (s.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        SizedBox(width: 110, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600))),
        Expanded(child: Text(s, style: const TextStyle(fontSize: 13))),
      ]),
    );
  }

  void _editFirma() {
    final nameC = TextEditingController(text: _firma['firma_name']?.toString() ?? '');
    final brandC = TextEditingController(text: _firma['brand']?.toString() ?? '');
    final strasseC = TextEditingController(text: _firma['strasse']?.toString() ?? '');
    final plzOrtC = TextEditingController(text: _firma['plz_ort']?.toString() ?? '');
    final telC = TextEditingController(text: _firma['telefon']?.toString() ?? '');
    final faxC = TextEditingController(text: _firma['fax']?.toString() ?? '');
    final emailC = TextEditingController(text: _firma['email']?.toString() ?? '');
    final webC = TextEditingController(text: _firma['website']?.toString() ?? '');
    final ikC = TextEditingController(text: _firma['ik_nummer']?.toString() ?? '');
    final hrC = TextEditingController(text: _firma['handelsregister']?.toString() ?? '');
    final notizC = TextEditingController(text: _firma['notizen']?.toString() ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Firma bearbeiten'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _field(nameC, 'Firmenname', Icons.business),
              _field(brandC, 'Brand', Icons.label),
              _field(strasseC, 'Straße', Icons.home),
              _field(plzOrtC, 'PLZ Ort', Icons.location_city),
              _field(telC, 'Telefon', Icons.phone),
              _field(faxC, 'Fax', Icons.fax),
              _field(emailC, 'E-Mail', Icons.email),
              _field(webC, 'Website', Icons.language),
              _field(ikC, 'IK-Nummer', Icons.qr_code),
              _field(hrC, 'Handelsregister', Icons.gavel),
              _field(notizC, 'Notizen', Icons.note, maxLines: 2),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () async {
              final payload = {
                'id': _firma['id'],
                'firma_name': nameC.text.trim(),
                'brand': brandC.text.trim(),
                'strasse': strasseC.text.trim(),
                'plz_ort': plzOrtC.text.trim(),
                'telefon': telC.text.trim(),
                'fax': faxC.text.trim(),
                'email': emailC.text.trim(),
                'website': webC.text.trim(),
                'ik_nummer': ikC.text.trim(),
                'handelsregister': hrC.text.trim(),
                'notizen': notizC.text.trim(),
              };
              final res = await widget.apiService.updatePflegeboxFirma(payload);
              if (!ctx.mounted) return;
              if (res['success'] == true) {
                Navigator.pop(ctx);
                setState(() => _firma = {..._firma, ...payload});
                widget.onFirmaUpdated(_firma);
              }
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label, IconData icon, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 18),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        style: const TextStyle(fontSize: 13),
      ),
    );
  }
}

// ============================================================
// KORRESPONDENZ TAB
// ============================================================
class _KorrespondenzTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int firmaId;
  const _KorrespondenzTab({required this.apiService, required this.userId, required this.firmaId});

  @override
  State<_KorrespondenzTab> createState() => _KorrespondenzTabState();
}

class _KorrespondenzTabState extends State<_KorrespondenzTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.apiService.listPflegeboxKorrespondenz(userId: widget.userId, firmaId: widget.firmaId);
    if (!mounted) return;
    if (r['success'] == true && r['data'] is List) {
      setState(() {
        _items = (r['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loaded = true;
      });
    }
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
            onPressed: () => _showUpload('eingang'),
          ),
          const SizedBox(width: 6),
          FilledButton.icon(
            icon: const Icon(Icons.call_made, size: 14),
            label: const Text('Ausgang', style: TextStyle(fontSize: 11)),
            style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
            onPressed: () => _showUpload('ausgang'),
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
                  final isEingang = k['richtung'] == 'eingang';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isEingang ? Colors.green.shade200 : Colors.blue.shade200),
                    ),
                    child: Row(children: [
                      Icon(isEingang ? Icons.call_received : Icons.call_made, size: 18, color: isEingang ? Colors.green.shade700 : Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(k['betreff']?.toString() ?? 'Ohne Betreff', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isEingang ? Colors.green.shade800 : Colors.blue.shade800)),
                        Text(k['datum']?.toString() ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                        if ((k['notiz']?.toString() ?? '').isNotEmpty)
                          Text(k['notiz'].toString(), style: TextStyle(fontSize: 10, color: Colors.grey.shade700, fontStyle: FontStyle.italic), maxLines: 2, overflow: TextOverflow.ellipsis),
                      ])),
                      if ((k['datei_name']?.toString() ?? '').isNotEmpty)
                        IconButton(
                          icon: Icon(Icons.visibility, size: 16, color: Colors.indigo.shade600),
                          tooltip: 'Anzeigen',
                          onPressed: () => _view(k['id'] as int, k['datei_name']?.toString() ?? ''),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        ),
                      IconButton(
                        icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400),
                        onPressed: () => _delete(k['id'] as int),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      ),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }

  Future<void> _delete(int id) async {
    final r = await widget.apiService.deletePflegeboxKorrespondenz(id);
    if (r['success'] == true) await _load();
  }

  Future<void> _view(int id, String name) async {
    try {
      final resp = await widget.apiService.downloadPflegeboxKorrespondenz(id);
      if (resp.statusCode == 200 && mounted) {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$name');
        await file.writeAsBytes(resp.bodyBytes);
        if (mounted) await FileViewerDialog.show(context, file.path, name);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    }
  }

  void _showUpload(String richtung) {
    final betreffC = TextEditingController();
    final notizC = TextEditingController();
    final datumC = TextEditingController(text: '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}');
    String? filePath;
    String? fileName;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setD) => AlertDialog(
          title: Text(richtung == 'eingang' ? 'Eingang erfassen' : 'Ausgang erfassen'),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: betreffC, decoration: const InputDecoration(labelText: 'Betreff', isDense: true, border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: datumC, decoration: const InputDecoration(labelText: 'Datum (YYYY-MM-DD)', isDense: true, border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: notizC, maxLines: 2, decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder())),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Text(fileName ?? 'Kein Dokument', style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
                OutlinedButton.icon(
                  icon: const Icon(Icons.attach_file, size: 14),
                  label: const Text('Datei', style: TextStyle(fontSize: 11)),
                  onPressed: () async {
                    final r = await FilePickerHelper.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
                    if (r != null && r.files.isNotEmpty && r.files.first.path != null) {
                      setD(() {
                        filePath = r.files.first.path;
                        fileName = r.files.first.name;
                      });
                    }
                  },
                ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            FilledButton(
              onPressed: () async {
                final res = await widget.apiService.uploadPflegeboxKorrespondenz(
                  userId: widget.userId,
                  firmaId: widget.firmaId,
                  richtung: richtung,
                  datum: datumC.text.trim(),
                  betreff: betreffC.text.trim(),
                  notiz: notizC.text.trim(),
                  filePath: filePath,
                  fileName: fileName,
                );
                if (!ctx.mounted) return;
                if (res['success'] == true) {
                  Navigator.pop(ctx);
                  await _load();
                }
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// LIEFERUNGEN TAB (monthly grid with tracking-id)
// ============================================================
class _LieferungenTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int firmaId;
  const _LieferungenTab({required this.apiService, required this.userId, required this.firmaId});

  @override
  State<_LieferungenTab> createState() => _LieferungenTabState();
}

class _LieferungenTabState extends State<_LieferungenTab> {
  List<Map<String, dynamic>> _lieferscheine = [];
  bool _loaded = false;
  int _selectedYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.apiService.listPflegeboxLieferscheine(widget.userId);
    if (!mounted) return;
    if (r['success'] == true && r['data'] is List) {
      setState(() {
        _lieferscheine = (r['data'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((l) => l['firma_id'] == widget.firmaId)
            .toList();
        _loaded = true;
      });
    }
  }

  Map<String, dynamic>? _lieferscheinFor(int monat, int jahr) {
    for (final l in _lieferscheine) {
      if ((l['monat'] as int?) == monat && (l['jahr'] as int?) == jahr) return l;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final monthNames = const ['Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'];
    final currentYear = DateTime.now().year;
    final years = [currentYear - 2, currentYear - 1, currentYear, currentYear + 1];
    final countForYear = _lieferscheine.where((l) => l['jahr'] == _selectedYear).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.local_shipping, size: 18, color: Colors.teal.shade700),
            const SizedBox(width: 6),
            Text('Monatliche Lieferungen $_selectedYear', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.teal.shade800)),
            const Spacer(),
            Text('$countForYear/12', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final y in years)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(y.toString(), style: TextStyle(fontSize: 12, color: _selectedYear == y ? Colors.white : Colors.black87)),
                      selected: _selectedYear == y,
                      selectedColor: Colors.teal.shade600,
                      onSelected: (_) => setState(() => _selectedYear = y),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.8,
            children: [
              for (int m = 1; m <= 12; m++) _buildMonthCell(m, _selectedYear, monthNames[m - 1]),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade100)),
            child: Row(children: [
              Icon(Icons.info_outline, size: 14, color: Colors.blue.shade700),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Klick auf leeren Monat = Lieferschein hochladen + Tracking-ID. Klick auf belegten Monat = Details.',
                  style: TextStyle(fontSize: 10, color: Colors.blue.shade800),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthCell(int monat, int jahr, String label) {
    final existing = _lieferscheinFor(monat, jahr);
    final hasFile = existing != null;
    final hasTracking = hasFile && (existing['tracking_id']?.toString() ?? '').isNotEmpty;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        if (hasFile) {
          _showLieferscheinDetail(existing);
        } else {
          _uploadDialog(monat, jahr);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: hasFile ? Colors.green.shade50 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: hasFile ? Colors.green.shade400 : Colors.grey.shade300, width: hasFile ? 1.5 : 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasFile ? Icons.check_circle : Icons.upload_file,
              size: 20,
              color: hasFile ? Colors.green.shade700 : Colors.grey.shade500,
            ),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: hasFile ? Colors.green.shade900 : Colors.grey.shade700)),
            if (hasTracking) ...[
              const SizedBox(height: 2),
              Icon(Icons.local_shipping, size: 11, color: Colors.orange.shade700),
            ],
          ],
        ),
      ),
    );
  }

  String _monthLabel(int m) => const ['', 'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'][m];

  Future<void> _uploadDialog(int monat, int jahr) async {
    final trackingC = TextEditingController();
    String anbieter = 'deutsche_post';
    final notizC = TextEditingController();
    String? filePath;
    String? fileName;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setD) => AlertDialog(
          title: Text('Lieferschein ${_monthLabel(monat)} $jahr'),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: filePath != null ? Colors.green.shade50 : Colors.grey.shade100, borderRadius: BorderRadius.circular(8), border: Border.all(color: filePath != null ? Colors.green.shade300 : Colors.grey.shade300)),
                    child: Row(children: [
                      Icon(filePath != null ? Icons.check_circle : Icons.upload_file, size: 18, color: filePath != null ? Colors.green.shade700 : Colors.grey.shade600),
                      const SizedBox(width: 8),
                      Expanded(child: Text(fileName ?? 'Dokument auswählen...', style: TextStyle(fontSize: 12, color: filePath != null ? Colors.green.shade900 : Colors.grey.shade700))),
                      TextButton(
                        onPressed: () async {
                          final r = await FilePickerHelper.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
                          if (r != null && r.files.isNotEmpty && r.files.first.path != null) {
                            setD(() {
                              filePath = r.files.first.path;
                              fileName = r.files.first.name;
                            });
                          }
                        },
                        child: const Text('Wählen', style: TextStyle(fontSize: 11)),
                      ),
                    ]),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: trackingC,
                decoration: InputDecoration(
                  labelText: 'Tracking-ID (Deutsche Post / DHL)',
                  hintText: 'z.B. RX123456789DE',
                  prefixIcon: const Icon(Icons.local_shipping, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: anbieter,
                decoration: InputDecoration(
                  labelText: 'Versanddienstleister',
                  prefixIcon: const Icon(Icons.business, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                items: const [
                  DropdownMenuItem(value: 'deutsche_post', child: Text('Deutsche Post')),
                  DropdownMenuItem(value: 'dhl', child: Text('DHL')),
                  DropdownMenuItem(value: 'hermes', child: Text('Hermes')),
                  DropdownMenuItem(value: 'dpd', child: Text('DPD')),
                  DropdownMenuItem(value: 'gls', child: Text('GLS')),
                  DropdownMenuItem(value: 'ups', child: Text('UPS')),
                  DropdownMenuItem(value: 'sonstige', child: Text('Sonstige')),
                ],
                onChanged: (v) => setD(() => anbieter = v ?? 'deutsche_post'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notizC,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Notiz',
                  prefixIcon: const Icon(Icons.note, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            FilledButton(
              onPressed: filePath == null
                  ? null
                  : () async {
                      final res = await widget.apiService.uploadPflegeboxLieferschein(
                        userId: widget.userId,
                        firmaId: widget.firmaId,
                        monat: monat,
                        jahr: jahr,
                        filePath: filePath!,
                        fileName: fileName!,
                        notiz: notizC.text.trim(),
                        trackingId: trackingC.text.trim(),
                        trackingAnbieter: anbieter,
                      );
                      if (!ctx.mounted) return;
                      if (res['success'] == true) {
                        Navigator.pop(ctx);
                        await _load();
                      } else {
                        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(res['message']?.toString() ?? 'Fehler'), backgroundColor: Colors.red));
                      }
                    },
              child: const Text('Hochladen'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLieferscheinDetail(Map<String, dynamic> l) async {
    final trackingC = TextEditingController(text: l['tracking_id']?.toString() ?? '');
    String anbieter = l['tracking_anbieter']?.toString() ?? 'deutsche_post';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setD) => AlertDialog(
          title: Text('${_monthLabel(l['monat'] as int)} ${l['jahr']}'),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green.shade200)),
                child: Row(children: [
                  Icon(Icons.description, size: 16, color: Colors.green.shade700),
                  const SizedBox(width: 6),
                  Expanded(child: Text(l['datei_name']?.toString() ?? '', style: const TextStyle(fontSize: 12))),
                  Text('${((l['file_size'] as int?) ?? 0) ~/ 1024} KB', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                ]),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: trackingC,
                decoration: InputDecoration(
                  labelText: 'Tracking-ID',
                  prefixIcon: const Icon(Icons.local_shipping, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: anbieter,
                decoration: InputDecoration(
                  labelText: 'Versanddienstleister',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                items: const [
                  DropdownMenuItem(value: 'deutsche_post', child: Text('Deutsche Post')),
                  DropdownMenuItem(value: 'dhl', child: Text('DHL')),
                  DropdownMenuItem(value: 'hermes', child: Text('Hermes')),
                  DropdownMenuItem(value: 'dpd', child: Text('DPD')),
                  DropdownMenuItem(value: 'gls', child: Text('GLS')),
                  DropdownMenuItem(value: 'ups', child: Text('UPS')),
                  DropdownMenuItem(value: 'sonstige', child: Text('Sonstige')),
                ],
                onChanged: (v) => setD(() => anbieter = v ?? 'deutsche_post'),
              ),
              if (trackingC.text.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.orange.shade200)),
                  child: Row(children: [
                    Icon(Icons.info_outline, size: 12, color: Colors.orange.shade700),
                    const SizedBox(width: 4),
                    Expanded(child: Text('Tracking-Link: ${_trackingUrl(anbieter, trackingC.text.trim())}', style: TextStyle(fontSize: 10, color: Colors.orange.shade900))),
                  ]),
                ),
              ],
            ]),
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.delete, color: Colors.red.shade400, size: 20),
              onPressed: () async {
                final r = await widget.apiService.deletePflegeboxLieferschein(l['id'] as int);
                if (!ctx.mounted) return;
                if (r['success'] == true) {
                  Navigator.pop(ctx);
                  await _load();
                }
              },
            ),
            TextButton.icon(
              icon: const Icon(Icons.download, size: 16),
              label: const Text('Download'),
              onPressed: () async {
                try {
                  final resp = await widget.apiService.downloadPflegeboxLieferschein(l['id'] as int);
                  if (resp.statusCode == 200) {
                    final savePath = await FilePickerHelper.saveFile(dialogTitle: 'Speichern', fileName: l['datei_name']?.toString() ?? 'lieferschein.pdf');
                    if (savePath != null) {
                      await File(savePath).writeAsBytes(resp.bodyBytes);
                      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Gespeichert'), backgroundColor: Colors.green));
                    }
                  }
                } catch (e) {
                  if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
                }
              },
            ),
            TextButton.icon(
              icon: const Icon(Icons.visibility, size: 16),
              label: const Text('Ansicht'),
              onPressed: () async {
                try {
                  final resp = await widget.apiService.downloadPflegeboxLieferschein(l['id'] as int);
                  if (resp.statusCode == 200 && ctx.mounted) {
                    final dir = await getTemporaryDirectory();
                    final file = File('${dir.path}/${l['datei_name'] ?? 'lieferschein.pdf'}');
                    await file.writeAsBytes(resp.bodyBytes);
                    if (ctx.mounted) await FileViewerDialog.show(ctx, file.path, l['datei_name']?.toString() ?? '');
                  }
                } catch (e) {
                  if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
                }
              },
            ),
            FilledButton(
              onPressed: () async {
                final res = await widget.apiService.updatePflegeboxLieferschein(
                  id: l['id'] as int,
                  trackingId: trackingC.text.trim(),
                  trackingAnbieter: anbieter,
                );
                if (!ctx.mounted) return;
                if (res['success'] == true) {
                  Navigator.pop(ctx);
                  await _load();
                }
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }

  String _trackingUrl(String anbieter, String id) {
    if (id.isEmpty) return '';
    switch (anbieter) {
      case 'dhl':
        return 'https://www.dhl.de/de/privatkunden/pakete-empfangen/verfolgen.html?piececode=$id';
      case 'hermes':
        return 'https://www.myhermes.de/empfangen/sendungsverfolgung/sendungsinformation/?barcode=$id';
      case 'dpd':
        return 'https://tracking.dpd.de/status/de_DE/parcel/$id';
      case 'gls':
        return 'https://www.gls-pakete.de/sendungsverfolgung?trackingNumber=$id';
      case 'ups':
        return 'https://www.ups.com/track?tracknum=$id';
      case 'deutsche_post':
      default:
        return 'https://www.deutschepost.de/sendung/simpleQueryResult.html?form.sendungsnummer=$id';
    }
  }
}
