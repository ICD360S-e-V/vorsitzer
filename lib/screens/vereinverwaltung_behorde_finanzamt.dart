import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../services/secure_cloud_service.dart';
import '../widgets/file_viewer_dialog.dart';
import '../utils/file_picker_helper.dart';

// ─── Nachweis slots ─────────────────────────────────────────────────────────
//
// Documents are no longer a free-floating list: each one lives under the field
// it proves. `kategorie` (a free-text column, unchanged on the server) decides
// which slot a document lands in, so existing rows keep working — a stored
// 'freistellungsbescheid' still shows up under Gemeinnützigkeit.

enum _Slot { steuernummer, gemeinnuetzigkeit, weitere }

/// kategorie → slot. Anything unknown falls through to [_Slot.weitere].
_Slot _slotFor(String kategorie) {
  switch (kategorie) {
    case 'steuernummer':
    case 'steuerbescheid':
      return _Slot.steuernummer;
    case 'gemeinnuetzigkeit':
    case 'freistellungsbescheid':
      return _Slot.gemeinnuetzigkeit;
    default:
      return _Slot.weitere;
  }
}

const Map<String, String> _katLabels = {
  'steuernummer': 'Steuernummer-Mitteilung',
  'steuerbescheid': 'Steuerbescheid',
  'gemeinnuetzigkeit': 'Anerkennung § 52 AO',
  'freistellungsbescheid': 'Freistellungsbescheid',
  'korrespondenz': 'Korrespondenz',
  'sonstiges': 'Sonstiges',
};

/// The categories offered when uploading into a given slot — the slot decides,
/// so a Nachweis can no longer be mis-filed by picking the wrong entry.
List<String> _katOptionsFor(_Slot slot) {
  switch (slot) {
    case _Slot.steuernummer:
      return const ['steuernummer', 'steuerbescheid'];
    case _Slot.gemeinnuetzigkeit:
      return const ['freistellungsbescheid', 'gemeinnuetzigkeit'];
    case _Slot.weitere:
      return const ['korrespondenz', 'sonstiges'];
  }
}

/// Only a Freistellungsbescheid actually expires — offer the date field there.
bool _katHasValidity(String kategorie) => kategorie == 'freistellungsbescheid';

const List<String> _allowedExtensions = [
  'pdf', 'png', 'jpg', 'jpeg', 'doc', 'docx', 'tiff', 'bmp',
];

class FinanzamtScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onBack;

  /// Current admin — identifies whose personal Secure Cloud to unlock when
  /// importing a Nachweis from it.
  final String mitgliedernummer;

  const FinanzamtScreen({
    super.key,
    required this.apiService,
    required this.mitgliedernummer,
    required this.onBack,
  });

  @override
  State<FinanzamtScreen> createState() => _FinanzamtScreenState();
}

class _FinanzamtScreenState extends State<FinanzamtScreen> {
  // Finanzamt contact data (from finanzaemter table)
  Map<String, dynamic>? _finanzamtData;
  // Verein-specific Finanzamt data (from vereinverwaltung_behorde_finanzamt table)
  Map<String, dynamic>? _vereinFinanzamt;
  bool _isLoading = true;

  // Documents
  List<Map<String, dynamic>> _dokumente = [];
  _Slot? _uploadingSlot;

  // Narrow layout: the read-only Behörde panel collapses out of the way.
  bool _behoerdeExpanded = false;
  bool _weitereExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _loadFinanzamtData(),
      _loadVereinFinanzamt(),
      _loadDokumente(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadFinanzamtData() async {
    try {
      final result = await widget.apiService.getFinanzaemterStammdaten();
      if (mounted && result['success'] == true) {
        final list = result['data'] as List?;
        if (list != null && list.isNotEmpty) {
          final fa = list.firstWhere(
            (e) => (e['name'] ?? '').toString().contains('Neu-Ulm'),
            orElse: () => list.first,
          );
          _finanzamtData = Map<String, dynamic>.from(fa as Map);
        }
      }
    } catch (_) {}
  }

  Future<void> _loadVereinFinanzamt() async {
    try {
      final result = await widget.apiService.getVereinFinanzamt();
      if (mounted && result['success'] == true && result['data'] != null) {
        _vereinFinanzamt = Map<String, dynamic>.from(result['data'] as Map);
      }
    } catch (_) {}
  }

  Future<void> _loadDokumente() async {
    try {
      final result = await widget.apiService.getFinanzamtDokumente();
      if (mounted && result['success'] == true) {
        _dokumente = List<Map<String, dynamic>>.from(result['dokumente'] ?? []);
      }
    } catch (_) {}
  }

  List<Map<String, dynamic>> _docsIn(_Slot slot) => _dokumente
      .where((d) => _slotFor((d['kategorie'] ?? 'sonstiges').toString()) == slot)
      .toList();

  Future<void> _saveVereinFinanzamt(Map<String, dynamic> data) async {
    try {
      final result = await widget.apiService.saveVereinFinanzamt(data);
      if (mounted) {
        if (result['success'] == true) {
          _snack('Gespeichert');
          _loadVereinFinanzamt().then((_) { if (mounted) setState(() {}); });
        } else {
          _snack(result['message'] ?? 'Fehler', isError: true);
        }
      }
    } catch (e) {
      if (mounted) _snack('Fehler: $e', isError: true);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
    ));
  }

  // ==================== EDIT DIALOGS ====================

  Future<void> _editSteuernummer() async {
    final controller = TextEditingController(text: _vereinFinanzamt?['steuernummer'] ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Steuernummer bearbeiten'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'z.B. 151/342/12345',
            labelText: 'Steuernummer',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (result != null) {
      final data = Map<String, dynamic>.from(_vereinFinanzamt ?? {});
      data['steuernummer'] = result;
      data['finanzamt_id'] = _finanzamtData?['id'];
      await _saveVereinFinanzamt(data);
    }
  }

  Future<void> _editGemeinnuetzigkeit() async {
    String status = _vereinFinanzamt?['gemeinnuetzigkeit_status'] ?? 'nicht_beantragt';
    final datumController = TextEditingController(text: _vereinFinanzamt?['gemeinnuetzigkeit_datum'] ?? '');

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Gemeinnützigkeit bearbeiten'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Status', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                items: const [
                  DropdownMenuItem(value: 'anerkannt', child: Text('Anerkannt')),
                  DropdownMenuItem(value: 'beantragt', child: Text('Beantragt')),
                  DropdownMenuItem(value: 'abgelehnt', child: Text('Abgelehnt')),
                  DropdownMenuItem(value: 'nicht_beantragt', child: Text('Nicht beantragt')),
                ],
                onChanged: (v) { if (v != null) setDialogState(() => status = v); },
              ),
              const SizedBox(height: 16),
              const Text('Datum (seit wann)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(
                controller: datumController,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: 'YYYY-MM-DD',
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.calendar_today, size: 18),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                        locale: const Locale('de'),
                      );
                      if (picked != null) datumController.text = _isoDate(picked);
                    },
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, {
                'status': status,
                'datum': datumController.text.trim(),
              }),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      final data = Map<String, dynamic>.from(_vereinFinanzamt ?? {});
      data['gemeinnuetzigkeit_status'] = result['status'];
      data['gemeinnuetzigkeit_datum'] = result['datum']!.isNotEmpty ? result['datum'] : null;
      data['finanzamt_id'] = _finanzamtData?['id'];
      await _saveVereinFinanzamt(data);
    }
  }

  Future<void> _editSachbearbeiter() async {
    final nameController = TextEditingController(text: _vereinFinanzamt?['sachbearbeiter_name'] ?? '');
    final telefonController = TextEditingController(text: _vereinFinanzamt?['sachbearbeiter_telefon'] ?? '');
    final emailController = TextEditingController(text: _vereinFinanzamt?['sachbearbeiter_email'] ?? '');
    final zimmerController = TextEditingController(text: _vereinFinanzamt?['sachbearbeiter_zimmer'] ?? '');
    final aktenzeichenController = TextEditingController(text: _vereinFinanzamt?['aktenzeichen'] ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sachbearbeiter bearbeiten'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Name', isDense: true),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: telefonController,
                  decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Telefon / Durchwahl', isDense: true),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'E-Mail', isDense: true),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: zimmerController,
                  decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Zimmer / Raum', isDense: true),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: aktenzeichenController,
                  decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Aktenzeichen', isDense: true),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (result == true) {
      final data = Map<String, dynamic>.from(_vereinFinanzamt ?? {});
      data['sachbearbeiter_name'] = nameController.text.trim();
      data['sachbearbeiter_telefon'] = telefonController.text.trim();
      data['sachbearbeiter_email'] = emailController.text.trim();
      data['sachbearbeiter_zimmer'] = zimmerController.text.trim();
      data['aktenzeichen'] = aktenzeichenController.text.trim();
      data['finanzamt_id'] = _finanzamtData?['id'];
      await _saveVereinFinanzamt(data);
    }
  }

  // ==================== DOCUMENT METHODS ====================

  /// Pick a file from the device and upload it into [slot].
  Future<void> _uploadFromDevice(_Slot slot) async {
    final picked = await FilePickerHelper.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedExtensions,
      dialogTitle: 'Dokument auswählen',
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    if (file.path == null) return;

    final info = await _showUploadDialog(slot, file.name);
    if (info == null) return;

    setState(() => _uploadingSlot = slot);
    try {
      final result = await widget.apiService.uploadFinanzamtDokument(
        filePath: file.path!,
        fileName: file.name,
        kategorie: info.kategorie,
        beschreibung: info.beschreibung,
        gueltigBis: info.gueltigBis,
        herkunft: 'device',
      );
      _afterUpload(result);
    } catch (e) {
      if (mounted) _snack('Fehler: $e', isError: true);
    } finally {
      if (mounted) setState(() => _uploadingSlot = null);
    }
  }

  /// Import a Nachweis out of the admin's zero-knowledge Secure Cloud.
  ///
  /// The blob is decrypted in RAM and forwarded straight to the Verein archive.
  /// The resulting copy is NOT encrypted — that is the whole point (an official
  /// document has to stay readable for every Vorsitzender and any successor),
  /// and the picker says so before the user commits.
  Future<void> _importFromCloud(_Slot slot) async {
    final pick = await showDialog<_CloudPick>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CloudPickerDialog(
        apiService: widget.apiService,
        mitgliedernummer: widget.mitgliedernummer,
      ),
    );
    if (pick == null || !mounted) return;

    final info = await _showUploadDialog(slot, pick.name);
    if (info == null) return;

    setState(() => _uploadingSlot = slot);
    try {
      final result = await widget.apiService.uploadFinanzamtDokumentBytes(
        bytes: pick.bytes,
        fileName: pick.name,
        kategorie: info.kategorie,
        beschreibung: info.beschreibung,
        gueltigBis: info.gueltigBis,
        herkunft: 'cloud',
      );
      _afterUpload(result);
    } catch (e) {
      if (mounted) _snack('Fehler: $e', isError: true);
    } finally {
      if (mounted) setState(() => _uploadingSlot = null);
    }
  }

  void _afterUpload(Map<String, dynamic> result) {
    if (!mounted) return;
    if (result['success'] == true) {
      _snack('Dokument hochgeladen');
      _loadDokumente().then((_) { if (mounted) setState(() {}); });
    } else {
      _snack(result['message'] ?? 'Upload fehlgeschlagen', isError: true);
    }
  }

  Future<_UploadInfo?> _showUploadDialog(_Slot slot, String fileName) async {
    final options = _katOptionsFor(slot);
    final beschreibungController = TextEditingController();
    final gueltigController = TextEditingController();
    String selected = options.first;

    return showDialog<_UploadInfo>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.upload_file, color: Colors.teal.shade700),
              const SizedBox(width: 8),
              Expanded(child: Text(_slotUploadTitle(slot))),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.insert_drive_file, size: 18, color: Colors.teal.shade600),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(fileName,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Art des Nachweises',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: selected,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      isDense: true,
                    ),
                    items: options
                        .map((k) => DropdownMenuItem(value: k, child: Text(_katLabels[k] ?? k)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => selected = v);
                    },
                  ),
                  if (_katHasValidity(selected)) ...[
                    const SizedBox(height: 16),
                    const Text('Gültig bis',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: gueltigController,
                      readOnly: true,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        hintText: 'YYYY-MM-DD (optional)',
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.calendar_today, size: 18),
                          onPressed: () async {
                            final now = DateTime.now();
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: DateTime(now.year + 3, now.month, now.day),
                              firstDate: DateTime(now.year - 10),
                              lastDate: DateTime(now.year + 20),
                              locale: const Locale('de'),
                            );
                            if (picked != null) {
                              setDialogState(() => gueltigController.text = _isoDate(picked));
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ein Freistellungsbescheid gilt in der Regel 3 Jahre.',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text('Beschreibung (optional)',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: beschreibungController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'z.B. Freistellungsbescheid vom 15.01.2026',
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            ElevatedButton.icon(
              icon: const Icon(Icons.upload, size: 18),
              label: const Text('Hochladen'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade600,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(
                ctx,
                _UploadInfo(
                  kategorie: selected,
                  beschreibung: beschreibungController.text.trim(),
                  gueltigBis: _katHasValidity(selected) && gueltigController.text.isNotEmpty
                      ? gueltigController.text
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _slotUploadTitle(_Slot slot) {
    switch (slot) {
      case _Slot.steuernummer:
        return 'Nachweis: Steuernummer';
      case _Slot.gemeinnuetzigkeit:
        return 'Nachweis: Gemeinnützigkeit';
      case _Slot.weitere:
        return 'Dokument hochladen';
    }
  }

  Future<void> _deleteDokument(Map<String, dynamic> doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dokument löschen?'),
        content: Text('Möchten Sie "${doc['original_name']}" wirklich löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await widget.apiService
        .deleteFinanzamtDokument(doc['id'] is int ? doc['id'] : int.parse(doc['id'].toString()));
    if (!mounted) return;
    if (result['success'] == true) {
      _snack('Dokument gelöscht');
      _loadDokumente().then((_) { if (mounted) setState(() {}); });
    } else {
      _snack(result['message'] ?? 'Löschen fehlgeschlagen', isError: true);
    }
  }

  Future<void> _viewDokument(Map<String, dynamic> doc) async {
    final docId = doc['id'] is int ? doc['id'] : int.parse(doc['id'].toString());
    final response = await widget.apiService.downloadFinanzamtDokument(docId);
    if (response == null || !mounted) return;

    try {
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/${doc['original_name']}';
      await File(filePath).writeAsBytes(response.bodyBytes);
      if (mounted) {
        await FileViewerDialog.show(context, filePath, doc['original_name']);
      }
    } catch (e) {
      if (mounted) _snack('Fehler: $e', isError: true);
    }
  }

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
                tooltip: 'Zurück',
              ),
              const SizedBox(width: 8),
              Icon(Icons.receipt_long, size: 32, color: Colors.teal.shade700),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Finanzamt',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Aktualisieren',
                onPressed: _isLoading ? null : _loadAll,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _finanzamtData == null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.receipt_long, size: 48, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text('Keine Finanzamt-Daten vorhanden',
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
                          ],
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) => constraints.maxWidth >= 900
                            ? _buildWideLayout()
                            : _buildNarrowLayout(),
                      ),
          ),
        ],
      ),
    );
  }

  /// Two columns: read-only Behörde (flex 2) beside the editable Verein data
  /// with its inline Nachweise (flex 3).
  Widget _buildWideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: _buildBehoerdeCard()),
        const SizedBox(width: 16),
        Expanded(flex: 3, child: _buildVereinPanel()),
      ],
    );
  }

  /// Stacked, with the Behörde block collapsed by default — on a narrow screen
  /// the editable data matters more than the (unchanging) contact details.
  Widget _buildNarrowLayout() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.account_balance, color: Colors.teal, size: 20),
                  ),
                  title: Text(_finanzamtData?['name'] ?? 'Finanzamt',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  trailing: Icon(_behoerdeExpanded ? Icons.expand_less : Icons.expand_more),
                  onTap: () => setState(() => _behoerdeExpanded = !_behoerdeExpanded),
                ),
                if (_behoerdeExpanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: _buildBehoerdeDetails(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildVereinPanel(scrollable: false),
        ],
      ),
    );
  }

  // ── Left panel: the Behörde itself (read-only) ─────────────────────────────

  Widget _buildBehoerdeCard() {
    final d = _finanzamtData!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.account_balance, color: Colors.teal, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(d['name'] ?? '',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const Divider(height: 28),
            Expanded(child: SingleChildScrollView(child: _buildBehoerdeDetails())),
          ],
        ),
      ),
    );
  }

  Widget _buildBehoerdeDetails() {
    final d = _finanzamtData!;
    final oeffnungszeiten = d['oeffnungszeiten'] as String?;
    final terminTelefon = d['termin_telefon'] as String?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoRow(Icons.location_on, 'Adresse', d['adresse'] ?? '-'),
        const SizedBox(height: 12),
        _buildInfoRow(Icons.phone, 'Telefon', d['telefon'] ?? '-'),
        const SizedBox(height: 12),
        _buildInfoRow(Icons.fax, 'Fax', d['fax'] ?? '-'),
        const SizedBox(height: 12),
        _buildInfoRow(Icons.email, 'E-Mail', d['email'] ?? '-'),
        if (oeffnungszeiten != null) ...[
          const SizedBox(height: 12),
          _buildInfoRow(Icons.access_time, 'Öffnungszeiten', oeffnungszeiten),
        ],
        if (terminTelefon != null) ...[
          const SizedBox(height: 12),
          _buildInfoRow(Icons.support_agent, 'Termin-Telefon', terminTelefon),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            if (d['website'] != null)
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Website'),
                  onPressed: () => _openUrl(d['website']),
                ),
              ),
            if (d['website'] != null && d['email'] != null) const SizedBox(width: 8),
            if (d['email'] != null)
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.email, size: 16),
                  label: const Text('E-Mail'),
                  onPressed: () => _openUrl('mailto:${d['email']}'),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ── Right panel: Verein data, each field carrying its own Nachweise ────────

  Widget _buildVereinPanel({bool scrollable = true}) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSteuernummerCard(),
        const SizedBox(height: 12),
        _buildGemeinnuetzigkeitCard(),
        const SizedBox(height: 12),
        _buildSachbearbeiterCard(),
        const SizedBox(height: 12),
        _buildWeitereDokumenteCard(),
      ],
    );
    if (!scrollable) return content;
    return SingleChildScrollView(child: content);
  }

  Widget _buildSteuernummerCard() {
    final steuernummer = (_vereinFinanzamt?['steuernummer'] ?? '').toString();
    final docs = _docsIn(_Slot.steuernummer);

    return _FieldCard(
      icon: Icons.tag,
      accent: Colors.teal,
      title: 'Steuernummer',
      onEdit: _editSteuernummer,
      body: steuernummer.isEmpty
          ? _EmptyValue(
              label: 'Noch nicht eingetragen',
              actionLabel: 'Steuernummer eintragen',
              onTap: _editSteuernummer,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(steuernummer,
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal.shade700)),
                const SizedBox(height: 2),
                Text(
                  [
                    _finanzamtData?['name'],
                    if ((_vereinFinanzamt?['aktenzeichen'] ?? '').toString().isNotEmpty)
                      'Az. ${_vereinFinanzamt!['aktenzeichen']}',
                  ].whereType<String>().join('  ·  '),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
      // A value with no document behind it is the case worth flagging.
      nachweis: steuernummer.isEmpty ? null : _buildNachweisSection(_Slot.steuernummer, docs),
    );
  }

  Widget _buildGemeinnuetzigkeitCard() {
    final status = (_vereinFinanzamt?['gemeinnuetzigkeit_status'] ?? 'nicht_beantragt').toString();
    final datum = (_vereinFinanzamt?['gemeinnuetzigkeit_datum'] ?? '').toString();
    final docs = _docsIn(_Slot.gemeinnuetzigkeit);
    final isAnerkannt = status == 'anerkannt';

    const labels = {
      'anerkannt': 'Anerkannt',
      'beantragt': 'Beantragt',
      'abgelehnt': 'Abgelehnt',
      'nicht_beantragt': 'Nicht beantragt',
    };
    final accent = isAnerkannt ? Colors.green : Colors.orange;

    // Validity comes from the newest Freistellungsbescheid that carries a
    // `gueltig_bis` — absent until the column exists server-side, in which case
    // the bar simply doesn't render.
    final validity = _newestValidity(docs);

    return _FieldCard(
      icon: isAnerkannt ? Icons.check_circle : Icons.pending,
      accent: accent,
      title: 'Gemeinnützigkeit',
      onEdit: _editGemeinnuetzigkeit,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: accent.shade600, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(labels[status] ?? status,
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold, color: accent.shade700)),
              if (datum.isNotEmpty) ...[
                const SizedBox(width: 10),
                Text('seit ${_formatDate(datum)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ],
          ),
          if (validity != null) ...[
            const SizedBox(height: 12),
            _ValidityBar(validity: validity),
          ],
        ],
      ),
      nachweis: _buildNachweisSection(_Slot.gemeinnuetzigkeit, docs),
    );
  }

  Widget _buildSachbearbeiterCard() {
    final name = (_vereinFinanzamt?['sachbearbeiter_name'] ?? '').toString();
    final telefon = (_vereinFinanzamt?['sachbearbeiter_telefon'] ?? '').toString();
    final email = (_vereinFinanzamt?['sachbearbeiter_email'] ?? '').toString();
    final zimmer = (_vereinFinanzamt?['sachbearbeiter_zimmer'] ?? '').toString();
    final aktenzeichen = (_vereinFinanzamt?['aktenzeichen'] ?? '').toString();

    return _FieldCard(
      icon: Icons.person,
      accent: Colors.blue,
      title: 'Sachbearbeiter/in',
      onEdit: _editSachbearbeiter,
      body: name.isEmpty
          ? _EmptyValue(
              label: 'Noch nicht eingetragen',
              actionLabel: 'Sachbearbeiter eintragen',
              onTap: _editSachbearbeiter,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    if (telefon.isNotEmpty) _miniInfo(Icons.phone, telefon),
                    if (email.isNotEmpty) _miniInfo(Icons.email, email),
                    if (zimmer.isNotEmpty) _miniInfo(Icons.meeting_room, 'Zimmer $zimmer'),
                    if (aktenzeichen.isNotEmpty) _miniInfo(Icons.folder, 'Az. $aktenzeichen'),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _miniInfo(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.grey.shade500),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
      ],
    );
  }

  Widget _buildWeitereDokumenteCard() {
    final docs = _docsIn(_Slot.weitere);
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.folder_open, color: Colors.amber, size: 20),
            ),
            title: Text('Weitere Dokumente (${docs.length})',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Hochladen'),
                  onPressed: _uploadingSlot != null ? null : () => _uploadFromDevice(_Slot.weitere),
                ),
                Icon(_weitereExpanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
            onTap: () => setState(() => _weitereExpanded = !_weitereExpanded),
          ),
          if (_weitereExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: docs.isEmpty
                  ? Text('Keine weiteren Dokumente.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500))
                  : Column(
                      children: [
                        for (final d in docs) ...[
                          _buildDocTile(d),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
            ),
        ],
      ),
    );
  }

  // ── Nachweis section shared by the field cards ─────────────────────────────

  Widget _buildNachweisSection(_Slot slot, List<Map<String, dynamic>> docs) {
    final busy = _uploadingSlot == slot;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('NACHWEIS',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: Colors.grey.shade600)),
            const Spacer(),
            if (docs.isEmpty)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber, size: 14, color: Colors.orange.shade600),
                  const SizedBox(width: 4),
                  Text('kein Beleg',
                      style: TextStyle(fontSize: 11, color: Colors.orange.shade700)),
                ],
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, size: 14, color: Colors.green.shade600),
                  const SizedBox(width: 4),
                  Text('${docs.length} ${docs.length == 1 ? 'Datei' : 'Dateien'}',
                      style: TextStyle(fontSize: 11, color: Colors.green.shade700)),
                ],
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (docs.isEmpty)
          _DropZone(
            busy: busy,
            onPickDevice: () => _uploadFromDevice(slot),
            onPickCloud: () => _importFromCloud(slot),
          )
        else ...[
          for (final d in docs) ...[
            _buildDocTile(d),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              TextButton.icon(
                icon: busy
                    ? const SizedBox(
                        width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add, size: 16),
                label: const Text('Nachweis hinzufügen'),
                onPressed: busy ? null : () => _uploadFromDevice(slot),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                icon: const Icon(Icons.cloud_outlined, size: 16),
                label: const Text('Aus sicherer Cloud'),
                onPressed: busy ? null : () => _importFromCloud(slot),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildDocTile(Map<String, dynamic> doc) {
    final name = (doc['original_name'] ?? 'Unbekannt').toString();
    final kategorie = (doc['kategorie'] ?? 'sonstiges').toString();
    final beschreibung = (doc['beschreibung'] ?? '').toString();
    final createdAt = (doc['created_at'] ?? '').toString();
    final gueltigBis = (doc['gueltig_bis'] ?? '').toString();
    final herkunft = (doc['herkunft'] ?? '').toString();
    final size = doc['file_size'];

    final extension = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final (fileIcon, fileColor) = _iconFor(extension);

    final subtitleParts = <String>[
      if (createdAt.isNotEmpty) _formatDate(createdAt),
      if (size != null) _fmtBytes(size is int ? size : int.tryParse(size.toString()) ?? 0),
      if (gueltigBis.isNotEmpty) 'gültig bis ${_formatDate(gueltigBis)}',
    ];

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(fileIcon, size: 20, color: fileColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(name,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              InkWell(
                onTap: () => _viewDokument(doc),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.visibility, size: 18, color: Colors.teal.shade600),
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: () => _deleteDokument(doc),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(_katLabels[kategorie] ?? kategorie,
                    style: TextStyle(fontSize: 10, color: Colors.teal.shade700)),
              ),
              if (herkunft == 'cloud')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_done, size: 10, color: Colors.indigo.shade400),
                      const SizedBox(width: 3),
                      Text('aus Cloud',
                          style: TextStyle(fontSize: 10, color: Colors.indigo.shade700)),
                    ],
                  ),
                ),
              if (subtitleParts.isNotEmpty)
                Text(subtitleParts.join('  ·  '),
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            ],
          ),
          if (beschreibung.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(beschreibung,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }

  (IconData, Color) _iconFor(String extension) {
    switch (extension) {
      case 'pdf':
        return (Icons.picture_as_pdf, Colors.red);
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'tiff':
      case 'bmp':
        return (Icons.image, Colors.blue);
      case 'doc':
      case 'docx':
        return (Icons.description, Colors.indigo);
      default:
        return (Icons.insert_drive_file, Colors.grey);
    }
  }

  /// Newest `gueltig_bis` among [docs], paired with that document's upload date
  /// so the bar knows how much of the validity window has burnt down.
  _Validity? _newestValidity(List<Map<String, dynamic>> docs) {
    DateTime? best;
    DateTime? from;
    for (final d in docs) {
      final raw = (d['gueltig_bis'] ?? '').toString();
      if (raw.isEmpty) continue;
      final parsed = DateTime.tryParse(raw);
      if (parsed == null) continue;
      if (best == null || parsed.isAfter(best)) {
        best = parsed;
        from = DateTime.tryParse((d['created_at'] ?? '').toString());
      }
    }
    if (best == null) return null;
    return _Validity(until: best, from: from);
  }

  String _formatDate(String dateStr) {
    final dt = DateTime.tryParse(dateStr);
    if (dt == null) return dateStr;
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }

  static String _isoDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _fmtBytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 10),
        SizedBox(
          width: 110,
          child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}

// ─── Small value types ──────────────────────────────────────────────────────

class _UploadInfo {
  final String kategorie;
  final String beschreibung;
  final String? gueltigBis;
  _UploadInfo({required this.kategorie, required this.beschreibung, this.gueltigBis});
}

class _Validity {
  final DateTime until;
  final DateTime? from;
  _Validity({required this.until, this.from});

  int get daysLeft => until.difference(DateTime.now()).inDays;
  bool get expired => daysLeft < 0;
  bool get expiringSoon => !expired && daysLeft < 90;

  /// How much of the window has elapsed (0..1). Falls back to a 3-year window
  /// when the issue date is unknown — a Freistellungsbescheid's usual term.
  double get progress {
    final start = from ?? until.subtract(const Duration(days: 365 * 3));
    final total = until.difference(start).inSeconds;
    if (total <= 0) return 1;
    final done = DateTime.now().difference(start).inSeconds;
    return (done / total).clamp(0.0, 1.0);
  }
}

/// One decrypted pick out of the Secure Cloud, held in memory only.
class _CloudPick {
  final Uint8List bytes;
  final String name;
  _CloudPick({required this.bytes, required this.name});
}

// ─── Presentational widgets ─────────────────────────────────────────────────

/// A Stammdaten field: header + value, optionally followed by the Nachweise
/// that prove it.
class _FieldCard extends StatelessWidget {
  final IconData icon;
  final MaterialColor accent;
  final String title;
  final VoidCallback onEdit;
  final Widget body;
  final Widget? nachweis;

  const _FieldCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.onEdit,
    required this.body,
    this.nachweis,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: accent.shade600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.edit, size: 14),
                  label: const Text('Bearbeiten', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: onEdit,
                ),
              ],
            ),
            const Divider(height: 16),
            body,
            if (nachweis != null) ...[
              const SizedBox(height: 16),
              nachweis!,
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyValue extends StatelessWidget {
  final String label;
  final String actionLabel;
  final VoidCallback onTap;
  const _EmptyValue({required this.label, required this.actionLabel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      alignment: Alignment.center,
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onTap, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

/// Dashed-looking drop zone shown when a field has no Nachweis at all.
class _DropZone extends StatelessWidget {
  final bool busy;
  final VoidCallback onPickDevice;
  final VoidCallback onPickCloud;
  const _DropZone({required this.busy, required this.onPickDevice, required this.onPickCloud});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: busy
          ? const Center(
              child: SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
          : Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.upload_file, size: 16),
                  label: const Text('Datei wählen'),
                  onPressed: onPickDevice,
                ),
                TextButton.icon(
                  icon: const Icon(Icons.cloud_outlined, size: 16),
                  label: const Text('Aus sicherer Cloud'),
                  onPressed: onPickCloud,
                ),
              ],
            ),
    );
  }
}

class _ValidityBar extends StatelessWidget {
  final _Validity validity;
  const _ValidityBar({required this.validity});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    if (validity.expired) {
      color = Colors.red.shade600;
      label = 'Freistellungsbescheid ABGELAUFEN seit '
          '${_fmt(validity.until)} — neuer Bescheid erforderlich';
    } else if (validity.expiringSoon) {
      color = Colors.orange.shade700;
      label = 'Freistellungsbescheid läuft ab am ${_fmt(validity.until)} '
          '(noch ${validity.daysLeft} Tage)';
    } else {
      color = Colors.green.shade600;
      final months = (validity.daysLeft / 30).floor();
      label = 'Freistellungsbescheid gültig bis ${_fmt(validity.until)} '
          '(noch $months Monate)';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: validity.progress,
            minHeight: 6,
            backgroundColor: color.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            if (validity.expired || validity.expiringSoon) ...[
              Icon(Icons.warning_amber, size: 13, color: color),
              const SizedBox(width: 4),
            ],
            Expanded(child: Text(label, style: TextStyle(fontSize: 11, color: color))),
          ],
        ),
      ],
    );
  }

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}

// ─── Secure Cloud picker ────────────────────────────────────────────────────

/// Unlocks the admin's zero-knowledge cloud, lists it, and hands back ONE file
/// decrypted in memory. The DEK is dropped again as soon as the dialog closes.
class _CloudPickerDialog extends StatefulWidget {
  final ApiService apiService;
  final String mitgliedernummer;
  const _CloudPickerDialog({required this.apiService, required this.mitgliedernummer});

  @override
  State<_CloudPickerDialog> createState() => _CloudPickerDialogState();
}

class _CloudPickerDialogState extends State<_CloudPickerDialog> {
  late final SecureCloudService _svc =
      SecureCloudService(widget.apiService, widget.mitgliedernummer);

  final _passController = TextEditingController();
  bool _busy = true;
  String? _error;
  bool? _hasCloud;
  List<CloudFile>? _files;
  int? _selectedId;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    // Never leave the key resident once the picker is gone.
    _svc.lock();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final has = await _svc.hasCloud();
    if (!mounted) return;
    setState(() {
      _hasCloud = has;
      _busy = false;
      if (has == null) _error = 'Netzwerkfehler — Cloud nicht erreichbar.';
    });
  }

  Future<void> _unlock() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await _svc.unlock(_passController.text);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }
    _passController.clear();
    final listing = await _svc.list();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _files = listing?.files ?? const [];
      if (listing == null) _error = 'Liste konnte nicht geladen werden.';
    });
  }

  Future<void> _take() async {
    final id = _selectedId;
    CloudFile? file;
    for (final f in _files ?? const <CloudFile>[]) {
      if (f.id == id) {
        file = f;
        break;
      }
    }
    if (file == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final bytes = await _svc.downloadToMemory(file);
    if (!mounted) return;
    if (bytes == null) {
      setState(() {
        _busy = false;
        _error = 'Datei konnte nicht entschlüsselt werden.';
      });
      return;
    }
    Navigator.pop(context, _CloudPick(bytes: bytes, name: file.name));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.cloud_outlined, color: Colors.indigo.shade600),
          const SizedBox(width: 8),
          const Expanded(child: Text('Aus sicherer Cloud übernehmen')),
        ],
      ),
      content: SizedBox(width: 460, child: _buildBody()),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        if (_files != null)
          ElevatedButton.icon(
            icon: const Icon(Icons.download_done, size: 18),
            label: const Text('Übernehmen'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade600,
              foregroundColor: Colors.white,
            ),
            onPressed: (_busy || _selectedId == null) ? null : _take,
          ),
      ],
    );
  }

  Widget _buildBody() {
    if (_busy && _files == null && _hasCloud == null) {
      return const SizedBox(height: 90, child: Center(child: CircularProgressIndicator()));
    }
    if (_hasCloud == false) {
      return _message(
        Icons.cloud_off,
        'Die sichere Cloud ist noch nicht eingerichtet.\n'
        'Richten Sie sie zuerst über das Wolken-Symbol in der Kopfzeile ein.',
      );
    }
    if (_files == null) return _buildUnlock();
    return _buildList();
  }

  Widget _buildUnlock() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.lock_outline, size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Text('Cloud gesperrt',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passController,
          obscureText: _obscure,
          autofocus: true,
          enabled: !_busy,
          onSubmitted: (_) => _busy ? null : _unlock(),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: 'Passphrase',
            isDense: true,
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off, size: 18),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.lock_open, size: 18),
            label: const Text('Entsperren'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo.shade600,
              foregroundColor: Colors.white,
            ),
            onPressed: _busy ? null : _unlock,
          ),
        ),
      ],
    );
  }

  Widget _buildList() {
    final files = _files!;
    if (files.isEmpty) {
      return _message(Icons.folder_off, 'Die sichere Cloud enthält noch keine Dateien.');
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: RadioGroup<int>(
              groupValue: _selectedId,
              onChanged: (v) {
                if (_busy) return;
                setState(() => _selectedId = v);
              },
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: files.length,
                itemBuilder: (_, i) {
                  final f = files[i];
                  return RadioListTile<int>(
                    value: f.id,
                    dense: true,
                    // Unreadable entries mean meta_enc failed to decrypt —
                    // nothing useful to import.
                    enabled: f.readable && !_busy,
                    title: Text(f.name,
                        style: const TextStyle(fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${f.source == 'scan' ? 'Scan' : 'Datei'}  ·  '
                      '${_FinanzamtScreenState._fmtBytes(f.plainSize)}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
        ],
        const Divider(height: 20),
        // The one thing the user must understand before committing.
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber, size: 16, color: Colors.orange.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Die Kopie wird ENTSCHLÜSSELT im Vereins-Archiv abgelegt — '
                  'lesbar für alle Vorsitzenden. Das Original bleibt verschlüsselt '
                  'in Ihrer Cloud.',
                  style: TextStyle(fontSize: 11, color: Colors.orange.shade900),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _message(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: Colors.grey.shade300),
          const SizedBox(height: 10),
          Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}
