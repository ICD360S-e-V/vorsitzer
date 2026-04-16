import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';
import 'file_viewer_dialog.dart';

/// DB-backed Pflegebox firma picker + monthly Lieferschein grid.
/// Replaces the plain Firma TextField in Behörde Krankenkasse → Pflegegrad tab.
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
  List<Map<String, dynamic>> _lieferscheine = [];
  bool _lieferscheineLoaded = false;
  int _selectedYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _loadFirmen();
    _loadLieferscheine();
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

  Future<void> _loadLieferscheine() async {
    try {
      final r = await widget.apiService.listPflegeboxLieferscheine(widget.userId);
      if (r['success'] == true && r['data'] is List) {
        if (mounted) {
          setState(() {
            _lieferscheine = (r['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
            _lieferscheineLoaded = true;
          });
        }
      }
    } catch (e) {
      debugPrint('[Pflegebox] lieferscheine load error: $e');
    }
  }

  Map<String, dynamic>? _firmaById(int? id) {
    if (id == null) return null;
    for (final f in _firmen) {
      if ((f['id'] as int?) == id) return f;
    }
    return null;
  }

  Map<String, dynamic>? _lieferscheinFor(int firmaId, int monat, int jahr) {
    for (final l in _lieferscheine) {
      if ((l['firma_id'] as int?) == firmaId && (l['monat'] as int?) == monat && (l['jahr'] as int?) == jahr) {
        return l;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFirmaPicker(),
        const SizedBox(height: 16),
        if (widget.selectedFirmaId != null) _buildLieferscheineGrid(),
      ],
    );
  }

  // ============ FIRMA PICKER ============
  Widget _buildFirmaPicker() {
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
            initialValue: TextEditingValue(text: selected != null ? '${selected['firma_name']}${selected['brand'] != null && selected['brand'].toString().isNotEmpty ? ' – ${selected['brand']}' : ''}' : widget.selectedFirmaName),
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
                            child: Text((f['firma_name']?.toString() ?? '?').substring(0, 1), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                          ),
                          title: Text('${f['firma_name']}', style: const TextStyle(fontSize: 13)),
                          subtitle: Text([if (brand.isNotEmpty) brand, f['plz_ort'] ?? ''].where((s) => s.toString().isNotEmpty).join(' · '), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
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
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(selected['firma_name']?.toString() ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green.shade900))),
                  if ((selected['brand']?.toString() ?? '').isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Colors.green.shade700, borderRadius: BorderRadius.circular(10)),
                      child: Text(selected['brand'].toString(), style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  IconButton(
                    icon: Icon(Icons.edit, size: 16, color: Colors.grey.shade700),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () => _showAddFirmaDialog(existing: selected),
                  ),
                ]),
                if ((selected['strasse']?.toString() ?? '').isNotEmpty || (selected['plz_ort']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.location_on, size: 12, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Expanded(child: Text('${selected['strasse'] ?? ''}${selected['strasse'] != null && selected['plz_ort'] != null ? ', ' : ''}${selected['plz_ort'] ?? ''}', style: TextStyle(fontSize: 11, color: Colors.grey.shade700))),
                  ]),
                ],
                if ((selected['telefon']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(Icons.phone, size: 12, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(selected['telefon'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                  ]),
                ],
                if ((selected['website']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(Icons.language, size: 12, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(selected['website'].toString(), style: TextStyle(fontSize: 11, color: Colors.blue.shade700, decoration: TextDecoration.underline)),
                  ]),
                ],
                if ((selected['ik_nummer']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(Icons.qr_code, size: 12, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text('IK: ${selected['ik_nummer']}', style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontFamily: 'monospace')),
                  ]),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ============ LIEFERSCHEINE GRID ============
  Widget _buildLieferscheineGrid() {
    final firmaId = widget.selectedFirmaId!;
    final monthNames = const ['Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'];
    final currentYear = DateTime.now().year;
    final years = [currentYear - 2, currentYear - 1, currentYear, currentYear + 1];

    final countForYear = _lieferscheine.where((l) => l['firma_id'] == firmaId && l['jahr'] == _selectedYear).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.receipt_long, size: 18, color: Colors.teal.shade700),
          const SizedBox(width: 6),
          Text('Lieferscheine monatlich', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.teal.shade800)),
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
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          childAspectRatio: 1.4,
          children: [
            for (int m = 1; m <= 12; m++) _buildMonthCell(firmaId, m, _selectedYear, monthNames[m - 1]),
          ],
        ),
      ],
    );
  }

  Widget _buildMonthCell(int firmaId, int monat, int jahr, String label) {
    final existing = _lieferscheinFor(firmaId, monat, jahr);
    final hasFile = existing != null;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        if (hasFile) {
          _showLieferscheinActions(existing);
        } else {
          _uploadLieferschein(firmaId, monat, jahr);
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
              size: 18,
              color: hasFile ? Colors.green.shade700 : Colors.grey.shade500,
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: hasFile ? Colors.green.shade900 : Colors.grey.shade700)),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadLieferschein(int firmaId, int monat, int jahr) async {
    final result = await FilePickerHelper.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hochladen läuft...'), duration: Duration(seconds: 1)));

    try {
      final res = await widget.apiService.uploadPflegeboxLieferschein(
        userId: widget.userId,
        firmaId: firmaId,
        monat: monat,
        jahr: jahr,
        filePath: file.path!,
        fileName: file.name,
      );
      if (!mounted) return;
      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lieferschein für ${_monthLabel(monat)} $jahr gespeichert'), backgroundColor: Colors.green));
        await _loadLieferscheine();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: ${res['message'] ?? 'Upload fehlgeschlagen'}'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    }
  }

  String _monthLabel(int m) => const ['', 'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'][m];

  void _showLieferscheinActions(Map<String, dynamic> l) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${_monthLabel(l['monat'] as int)} ${l['jahr']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l['datei_name']?.toString() ?? '', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 4),
            Text('${((l['file_size'] as int?) ?? 0) ~/ 1024} KB', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.delete, size: 16, color: Colors.red),
            label: const Text('Löschen', style: TextStyle(color: Colors.red)),
            onPressed: () async {
              Navigator.pop(ctx);
              final r = await widget.apiService.deletePflegeboxLieferschein(l['id'] as int);
              if (!mounted) return;
              if (r['success'] == true) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gelöscht')));
                await _loadLieferscheine();
              }
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.download, size: 16),
            label: const Text('Download'),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final resp = await widget.apiService.downloadPflegeboxLieferschein(l['id'] as int);
                if (resp.statusCode == 200) {
                  final savePath = await FilePickerHelper.saveFile(dialogTitle: 'Speichern', fileName: l['datei_name']?.toString() ?? 'lieferschein.pdf');
                  if (savePath != null) {
                    await File(savePath).writeAsBytes(resp.bodyBytes);
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gespeichert'), backgroundColor: Colors.green));
                  }
                }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
              }
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.visibility, size: 16),
            label: const Text('Anzeigen'),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final resp = await widget.apiService.downloadPflegeboxLieferschein(l['id'] as int);
                if (resp.statusCode == 200) {
                  final dir = await getTemporaryDirectory();
                  final file = File('${dir.path}/${l['datei_name'] ?? 'lieferschein.pdf'}');
                  await file.writeAsBytes(resp.bodyBytes);
                  if (mounted) await FileViewerDialog.show(context, file.path, l['datei_name']?.toString() ?? '');
                }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
              }
            },
          ),
        ],
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
                _txt(nameC, 'Firmenname*', Icons.business, required: true),
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
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(res['message']?.toString() ?? 'Fehler'), backgroundColor: Colors.red));
              }
            },
            child: Text(existing == null ? 'Hinzufügen' : 'Speichern'),
          ),
        ],
      ),
    );
  }

  Widget _txt(TextEditingController c, String label, IconData icon, {bool required = false, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label + (required ? '' : ''),
          prefixIcon: Icon(icon, size: 18),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        style: const TextStyle(fontSize: 13),
      ),
    );
  }
}
