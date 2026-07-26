import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../services/secure_cloud_service.dart';
import 'webview_screen.dart';
import '../widgets/file_viewer_dialog.dart';
import '../utils/file_picker_helper.dart';

// ─── Korrespondenz vocabulary ───────────────────────────────────────────────

/// The channel an exchange went through. 'anruf' is the odd one out: it carries
/// no document at all, so there the note IS the record — the server rejects an
/// Anruf without one.
const List<String> _wegValues = ['email', 'anruf', 'online', 'fax', 'post', 'persoenlich'];

const Map<String, String> _wegLabel = {
  'email': 'E-Mail',
  'anruf': 'Anruf',
  'online': 'Online',
  'fax': 'Fax',
  'post': 'Post',
  'persoenlich': 'Persönlich',
};

const Map<String, IconData> _wegIcon = {
  'email': Icons.mail_outline,
  'anruf': Icons.phone_outlined,
  'online': Icons.language,
  'fax': Icons.print_outlined,
  'post': Icons.markunread_mailbox_outlined,
  'persoenlich': Icons.handshake_outlined,
};

const List<String> _korrExtensions = ['pdf', 'jpg', 'jpeg', 'png', 'tif', 'tiff'];

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

class _FinanzamtScreenState extends State<FinanzamtScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 6, vsync: this);

  // Finanzamt contact data (from finanzaemter table)
  Map<String, dynamic>? _finanzamtData;
  // Verein-specific Finanzamt data (from vereinverwaltung_behorde_finanzamt table)
  Map<String, dynamic>? _vereinFinanzamt;
  bool _isLoading = true;

  // Documents
  List<Map<String, dynamic>> _dokumente = [];
  _Slot? _uploadingSlot;

  // Korrespondenz
  List<Map<String, dynamic>> _korrespondenz = [];
  bool _korrLoading = false;
  String _korrFilterRichtung = '';
  String _korrFilterWeg = '';

  // ELSTER access (status only — the certificate itself is fetched on demand)
  Map<String, dynamic>? _elster;
  bool _elsterBusy = false;

  bool _weitereExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _loadFinanzamtData(),
      _loadVereinFinanzamt(),
      _loadDokumente(),
      _loadKorrespondenz(),
      _loadElster(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadKorrespondenz() async {
    _korrLoading = true;
    try {
      final result = await widget.apiService.getVereinKorrespondenz(
        richtung: _korrFilterRichtung.isEmpty ? null : _korrFilterRichtung,
        weg: _korrFilterWeg.isEmpty ? null : _korrFilterWeg,
      );
      if (mounted && result['success'] == true) {
        final data = result['data'] ?? result;
        _korrespondenz = List<Map<String, dynamic>>.from(data['korrespondenz'] ?? []);
      }
    } catch (_) {}
    _korrLoading = false;
  }

  Future<void> _loadElster() async {
    try {
      final result = await widget.apiService.getElsterZugang();
      if (mounted && result['success'] == true) {
        _elster = Map<String, dynamic>.from(result['data'] ?? result);
      }
    } catch (_) {}
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
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
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
          const SizedBox(height: 12),
          TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: Colors.teal.shade700,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: Colors.teal.shade600,
            tabs: [
              const Tab(icon: Icon(Icons.account_balance, size: 18), text: 'Zuständiges Finanzamt'),
              const Tab(icon: Icon(Icons.person, size: 18), text: 'Ansprechpartner'),
              const Tab(icon: Icon(Icons.tag, size: 18), text: 'Steuernummer'),
              const Tab(icon: Icon(Icons.verified, size: 18), text: 'Gemeinnützigkeit'),
              Tab(
                icon: const Icon(Icons.forum_outlined, size: 18),
                text: 'Korrespondenz'
                    '${_korrespondenz.isEmpty ? '' : ' (${_korrespondenz.length})'}',
              ),
              const Tab(icon: Icon(Icons.lock_outline, size: 18), text: 'ELSTER Online'),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _tabBehoerde(),
                      _tabAnsprechpartner(),
                      _tabSteuernummer(),
                      _tabGemeinnuetzigkeit(),
                      _tabKorrespondenz(),
                      _tabElster(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _pad(Widget child) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: child,
      );

  Widget _emptyState(IconData icon, String text) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
        ],
      ),
    );
  }

  // ── Tab 1: the Finanzamt itself ───────────────────────────────────────────

  Widget _tabBehoerde() {
    if (_finanzamtData == null) {
      return _emptyState(Icons.account_balance, 'Keine Finanzamt-Daten vorhanden');
    }
    return _pad(_buildBehoerdeCard());
  }

  // ── Tab 2: Ansprechpartner ────────────────────────────────────────────────

  Widget _tabAnsprechpartner() => _pad(_buildSachbearbeiterCard());

  // ── Tab 3: Steuernummer ───────────────────────────────────────────────────

  Widget _tabSteuernummer() => _pad(Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSteuernummerCard(),
          const SizedBox(height: 12),
          _buildWeitereDokumenteCard(),
        ],
      ));

  // ── Tab 4: Gemeinnützigkeit ───────────────────────────────────────────────

  Widget _tabGemeinnuetzigkeit() => _pad(_buildGemeinnuetzigkeitCard());

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

  // ── Verein data cards, one per tab ────────────────────────────────────────

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

  // ── Tab 5: Korrespondenz ──────────────────────────────────────────────────

  Widget _tabKorrespondenz() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip('Alle',
                          _korrFilterRichtung.isEmpty && _korrFilterWeg.isEmpty,
                          () => _setKorrFilter('', '')),
                      const SizedBox(width: 6),
                      _filterChip('↓ Eingang', _korrFilterRichtung == 'eingang',
                          () => _setKorrFilter('eingang', _korrFilterWeg)),
                      const SizedBox(width: 6),
                      _filterChip('↑ Ausgang', _korrFilterRichtung == 'ausgang',
                          () => _setKorrFilter('ausgang', _korrFilterWeg)),
                      const SizedBox(width: 14),
                      for (final w in _wegValues) ...[
                        _wegChip(w),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Erfassen'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade600,
                  foregroundColor: Colors.white,
                ),
                onPressed: _erfassenKorrespondenz,
              ),
            ],
          ),
        ),
        Expanded(
          child: _korrLoading
              ? const Center(child: CircularProgressIndicator())
              : _korrespondenz.isEmpty
                  ? _emptyState(
                      Icons.forum_outlined,
                      _korrFilterRichtung.isEmpty && _korrFilterWeg.isEmpty
                          ? 'Noch keine Korrespondenz erfasst.\n'
                            'E-Mails an elster@icd360s.de werden automatisch übernommen.'
                          : 'Kein Eintrag für diesen Filter.')
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: _korrespondenz.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _buildKorrCard(_korrespondenz[i]),
                    ),
        ),
      ],
    );
  }

  void _setKorrFilter(String richtung, String weg) {
    setState(() {
      _korrFilterRichtung = richtung;
      _korrFilterWeg = weg;
      _korrLoading = true;
    });
    _loadKorrespondenz().then((_) { if (mounted) setState(() {}); });
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _wegChip(String weg) {
    final selected = _korrFilterWeg == weg;
    return ChoiceChip(
      avatar: Icon(_wegIcon[weg], size: 14),
      label: Text(_wegLabel[weg]!, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => _setKorrFilter(_korrFilterRichtung, selected ? '' : weg),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildKorrCard(Map<String, dynamic> k) {
    final richtung = (k['richtung'] ?? 'eingang').toString();
    final weg = (k['weg'] ?? 'post').toString();
    final isEingang = richtung == 'eingang';
    final betreff = (k['betreff'] ?? '').toString();
    final absender = (k['absender'] ?? '').toString();
    final empfaenger = (k['empfaenger'] ?? '').toString();
    final partner = (k['gespraechspartner'] ?? '').toString();
    final notiz = (k['notiz'] ?? '').toString();
    final quelle = (k['quelle'] ?? 'manual').toString();
    final dateien = List<Map<String, dynamic>>.from(k['dateien'] ?? []);
    final accent = isEingang ? Colors.indigo : Colors.teal;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 4,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(isEingang ? Icons.south_west : Icons.north_east,
                        size: 16, color: accent.shade600),
                    const SizedBox(width: 6),
                    Text(isEingang ? 'EINGANG' : 'AUSGANG',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700,
                            letterSpacing: 0.6, color: accent.shade700)),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_wegIcon[weg], size: 14, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(_wegLabel[weg] ?? weg,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                  ],
                ),
                Text(_formatDateTime((k['datum'] ?? '').toString()),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                if (quelle == 'mail')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bolt, size: 10, color: Colors.blue.shade400),
                        const SizedBox(width: 2),
                        Text('automatisch',
                            style: TextStyle(fontSize: 10, color: Colors.blue.shade700)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (betreff.isNotEmpty)
                        Text(betreff,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (absender.isNotEmpty) absender,
                          if (empfaenger.isNotEmpty) '→ $empfaenger',
                          if (partner.isNotEmpty) '· $partner',
                        ].join(' '),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.attach_file, size: 18),
                  tooltip: 'Dokumente hinzufügen',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _addFilesToKorrespondenz(k),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                  tooltip: 'Löschen',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _deleteKorrespondenz(k),
                ),
              ],
            ),
            if (notiz.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Text(notiz, style: const TextStyle(fontSize: 12)),
              ),
            ],
            if (dateien.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: dateien.map(_buildKorrFileChip).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildKorrFileChip(Map<String, dynamic> f) {
    final name = (f['original_name'] ?? 'Datei').toString();
    final rolle = (f['rolle'] ?? 'attachment').toString();
    final size = f['file_size'];
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final (icon, color) =
        rolle == 'eml' ? (Icons.mail_outline, Colors.blueGrey) : _iconFor(ext);

    return InkWell(
      onTap: () => _viewKorrFile(f),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text(name,
                  style: const TextStyle(fontSize: 12),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (size != null) ...[
              const SizedBox(width: 6),
              Text(_fmtBytes(size is int ? size : int.tryParse('$size') ?? 0),
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _viewKorrFile(Map<String, dynamic> file) async {
    final id = file['id'] is int ? file['id'] : int.parse(file['id'].toString());
    final response = await widget.apiService.downloadVereinKorrespondenzFile(id);
    if (!mounted) return;
    if (response == null) {
      _snack('Datei konnte nicht geladen werden', isError: true);
      return;
    }
    await _openBytes(response.bodyBytes, file['original_name']?.toString() ?? 'datei');
  }

  Future<void> _openBytes(Uint8List bytes, String name) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/$name';
      await File(filePath).writeAsBytes(bytes);
      if (mounted) await FileViewerDialog.show(context, filePath, name);
    } catch (e) {
      if (mounted) _snack('Fehler: $e', isError: true);
    }
  }

  Future<void> _deleteKorrespondenz(Map<String, dynamic> k) async {
    final betreff = (k['betreff'] ?? '').toString();
    final confirmed = await _confirmDelete('Korrespondenz löschen?',
        'Der Eintrag${betreff.isEmpty ? '' : ' "$betreff"'} und alle zugehörigen '
        'Dokumente werden gelöscht.');
    if (!confirmed) return;

    final id = k['id'] is int ? k['id'] : int.parse(k['id'].toString());
    final result = await widget.apiService.deleteVereinKorrespondenz(id);
    if (!mounted) return;
    if (result['success'] == true) {
      _snack('Korrespondenz gelöscht');
      _loadKorrespondenz().then((_) { if (mounted) setState(() {}); });
    } else {
      _snack(result['message'] ?? 'Löschen fehlgeschlagen', isError: true);
    }
  }

  Future<void> _erfassenKorrespondenz() async {
    final entry = await showDialog<_KorrDraft>(
      context: context,
      builder: (_) => _KorrespondenzDialog(
        defaultPartner: (_vereinFinanzamt?['sachbearbeiter_name'] ?? '').toString(),
        finanzamtName: (_finanzamtData?['name'] ?? 'Finanzamt').toString(),
      ),
    );
    if (entry == null || !mounted) return;

    final created = await widget.apiService.createVereinKorrespondenz(
      richtung: entry.richtung,
      weg: entry.weg,
      datum: entry.datum,
      betreff: entry.betreff,
      absender: entry.absender,
      empfaenger: entry.empfaenger,
      gespraechspartner: entry.gespraechspartner,
      notiz: entry.notiz,
    );
    if (!mounted) return;
    if (created['success'] != true) {
      _snack(created['message'] ?? 'Anlegen fehlgeschlagen', isError: true);
      return;
    }
    final data = created['data'] ?? created;
    final korrId = data['id'] is int ? data['id'] : int.tryParse('${data['id']}') ?? 0;

    if (entry.files.isNotEmpty && korrId > 0) {
      await _uploadKorrFiles(korrId, entry.files);
    }
    if (!mounted) return;
    _snack('Korrespondenz gespeichert');
    await _loadKorrespondenz();
    if (mounted) setState(() {});
  }

  /// Upload attachments one request at a time.
  ///
  /// Not a stylistic choice: nginx caps a single body at 200 MiB, PHP's
  /// max_file_uploads is exactly 20, and ClamAV scans every write synchronously
  /// inside a 30 s execution budget. A batched POST would fail at nginx with a
  /// bodyless 413 that the app's error handling cannot even parse.
  Future<void> _uploadKorrFiles(int korrId, List<PlatformFile> files) async {
    final items = files.where((f) => f.path != null).toList();
    if (items.isEmpty) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _KorrUploadProgressDialog(
        files: items,
        upload: (f) async {
          final r = await widget.apiService.attachVereinKorrespondenzFile(
            korrespondenzId: korrId,
            filePath: f.path!,
            fileName: f.name,
          );
          return r['success'] == true ? null : (r['message']?.toString() ?? 'Fehler');
        },
      ),
    );
  }

  Future<void> _addFilesToKorrespondenz(Map<String, dynamic> k) async {
    final picked = await FilePickerHelper.pickFiles(
      type: FileType.custom,
      allowedExtensions: _korrExtensions,
      allowMultiple: true,
      dialogTitle: 'Dokumente auswählen',
    );
    if (picked == null || picked.files.isEmpty) return;

    // The macOS picker branch drops the extension filter, so re-check here.
    final valid = picked.files.where((f) {
      final ext = f.name.contains('.') ? f.name.split('.').last.toLowerCase() : '';
      return f.path != null && _korrExtensions.contains(ext);
    }).toList();

    if (!mounted) return;
    if (valid.isEmpty) {
      _snack('Nur PDF, JPG und PNG sind erlaubt.', isError: true);
      return;
    }
    if (valid.length < picked.files.length) {
      _snack('${picked.files.length - valid.length} Datei(en) übersprungen — '
             'nur PDF, JPG und PNG.', isError: true);
    }

    final id = k['id'] is int ? k['id'] : int.parse(k['id'].toString());
    await _uploadKorrFiles(id, valid);
    await _loadKorrespondenz();
    if (mounted) setState(() {});
  }

  // ── Tab 6: ELSTER Online ──────────────────────────────────────────────────

  Widget _tabElster() {
    final e = _elster;
    final configured = e != null && e['configured'] == true;
    final certName = (e?['zertifikat_name'] ?? '').toString();
    final certSize = e?['zertifikat_size'];
    final hasPw = e?['has_passwort'] == true;
    final gueltigBis = (e?['gueltig_bis'] ?? '').toString();

    return _pad(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lock_outline, size: 18, color: Colors.deepPurple.shade600),
                    const SizedBox(width: 8),
                    Text('ELSTER-ZUGANG',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700,
                            letterSpacing: 0.6, color: Colors.grey.shade700)),
                  ],
                ),
                const Divider(height: 16),

                // Certificate
                if (!configured)
                  _EmptyValue(
                    label: 'Kein Zertifikat hinterlegt',
                    actionLabel: 'Zertifikatsdatei (.pfx) wählen',
                    onTap: _pickElsterCertificate,
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.vpn_key, size: 20, color: Colors.deepPurple.shade400),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(certName.isEmpty ? 'Zertifikat' : certName,
                                  style: const TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.w600)),
                              Text(
                                [
                                  if (certSize != null)
                                    _fmtBytes(certSize is int
                                        ? certSize
                                        : int.tryParse('$certSize') ?? 0),
                                  hasPw ? 'Passwort gespeichert' : 'kein Passwort',
                                  if (gueltigBis.isNotEmpty)
                                    'gültig bis ${_formatDate(gueltigBis)}',
                                ].join('  ·  '),
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: _pickElsterCertificate,
                          child: const Text('Ersetzen'),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.password, size: 16),
                      label: Text(hasPw ? 'Passwort ändern' : 'Passwort setzen'),
                      onPressed: _setElsterPassword,
                    ),
                    const SizedBox(width: 8),
                    if (configured)
                      TextButton.icon(
                        icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400),
                        label: Text('Entfernen',
                            style: TextStyle(color: Colors.red.shade400)),
                        onPressed: _deleteElster,
                      ),
                  ],
                ),

                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.shield_outlined, size: 16, color: Colors.amber.shade800),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Zertifikat und Passwort werden verschlüsselt gespeichert und '
                          'sind nur für Vorsitzende lesbar. Wer beides besitzt, kann '
                          'Erklärungen im Namen des Vereins abgeben — eine Kopie lässt '
                          'sich nicht einzeln widerrufen.',
                          style: TextStyle(fontSize: 11, color: Colors.amber.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ANMELDEN',
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700,
                        letterSpacing: 0.6, color: Colors.grey.shade700)),
                const Divider(height: 16),
                Text(
                  Platform.isLinux
                      ? 'Öffnet die ELSTER-Anmeldung im externen Chromium und setzt '
                        'Zertifikat und Passwort ein.'
                      : 'Öffnet die ELSTER-Anmeldung im integrierten Browser und setzt '
                        'Zertifikat und Passwort ein.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton.icon(
                      icon: _elsterBusy
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.login, size: 18),
                      label: const Text('Bei ELSTER anmelden'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple.shade600,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: (!configured || _elsterBusy) ? null : _loginToElster,
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('Nur öffnen'),
                      onPressed: () => _openUrl(_elsterLoginUrl),
                    ),
                  ],
                ),
                if (!configured) ...[
                  const SizedBox(height: 8),
                  Text('Zuerst Zertifikat und Passwort hinterlegen.',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                ],
              ],
            ),
          ),
        ),
      ],
    ));
  }

  static const String _elsterLoginUrl =
      'https://www.elster.de/eportal/login/softpse?isErstlogin=true';

  Future<void> _pickElsterCertificate() async {
    final picked = await FilePickerHelper.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pfx', 'p12'],
      dialogTitle: 'ELSTER-Zertifikat (.pfx) wählen',
    );
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.first;
    if (f.path == null) return;

    // ELSTER issues PKCS#12, never PEM — catch the mix-up before upload.
    final ext = f.name.contains('.') ? f.name.split('.').last.toLowerCase() : '';
    if (ext != 'pfx' && ext != 'p12') {
      _snack('ELSTER liefert eine .pfx-Datei (PKCS#12), keine .pem.', isError: true);
      return;
    }

    final pw = await _askPassword('Passwort des Zertifikats');
    if (pw == null) return;

    setState(() => _elsterBusy = true);
    final r = await widget.apiService.saveElsterZugang(
      certificatePath: f.path!,
      certificateName: f.name,
      passwort: pw,
    );
    if (!mounted) return;
    setState(() => _elsterBusy = false);
    if (r['success'] == true) {
      _snack('Zertifikat gespeichert');
      await _loadElster();
      if (mounted) setState(() {});
    } else {
      _snack(r['message'] ?? 'Speichern fehlgeschlagen', isError: true);
    }
  }

  Future<void> _setElsterPassword() async {
    final pw = await _askPassword('Passwort des Zertifikats');
    if (pw == null) return;
    setState(() => _elsterBusy = true);
    final r = await widget.apiService.saveElsterZugang(passwort: pw);
    if (!mounted) return;
    setState(() => _elsterBusy = false);
    if (r['success'] == true) {
      _snack('Passwort gespeichert');
      await _loadElster();
      if (mounted) setState(() {});
    } else {
      _snack(r['message'] ?? 'Speichern fehlgeschlagen', isError: true);
    }
  }

  Future<String?> _askPassword(String label) async {
    final controller = TextEditingController();
    bool obscure = true;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(label),
          content: TextField(
            controller: controller,
            obscureText: obscure,
            autofocus: true,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                icon: Icon(obscure ? Icons.visibility : Icons.visibility_off, size: 18),
                onPressed: () => setD(() => obscure = !obscure),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteElster() async {
    final ok = await _confirmDelete('ELSTER-Zugang entfernen?',
        'Zertifikat und Passwort werden gelöscht.');
    if (!ok) return;
    final r = await widget.apiService.deleteElsterZugang();
    if (!mounted) return;
    if (r['success'] == true) {
      _snack('Entfernt');
      await _loadElster();
      if (mounted) setState(() {});
    } else {
      _snack(r['message'] ?? 'Löschen fehlgeschlagen', isError: true);
    }
  }

  /// Open the ELSTER certificate login with the keystore and password filled in.
  ///
  /// Routed through [WebViewScreen] rather than calling ExternalBrowserService
  /// directly — that is what every other portal in this app does (the doctor
  /// booking, Rundfunkbeitrag, the Arbeitsagentur SSO), and it is what makes
  /// this work on Windows, macOS and mobile too instead of Linux only.
  /// WebViewScreen picks the backend: Edge WebView2, WKWebView, native
  /// WebView, or the external Chromium over CDP on Linux.
  ///
  /// Auto-fill is possible at all because ELSTER's certificate login runs in
  /// page JavaScript rather than as a TLS client-certificate handshake.
  Future<void> _loginToElster() async {
    setState(() => _elsterBusy = true);
    File? tmp;
    try {
      final r = await widget.apiService.revealElsterZugang();
      if (!mounted) return;
      if (r['success'] != true) {
        _snack(r['message'] ?? 'Zugangsdaten konnten nicht geladen werden', isError: true);
        return;
      }
      final data = r['data'] ?? r;
      final b64 = (data['zertifikat_base64'] ?? '').toString();
      final pw = (data['passwort'] ?? '').toString();
      final certName = (data['zertifikat_name'] ?? 'elster.pfx').toString();
      if (b64.isEmpty) {
        _snack('Kein Zertifikat hinterlegt.', isError: true);
        return;
      }

      // Linux drives a real browser process, which needs a real file on disk.
      // The embedded webviews cannot be handed a path, so there the keystore
      // travels inside the injected JS instead and no file is written at all.
      if (Platform.isLinux) {
        final dir = await getTemporaryDirectory();
        tmp = File('${dir.path}/elster_${DateTime.now().millisecondsSinceEpoch}.pfx');
        await tmp.writeAsBytes(base64Decode(b64));
      }

      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => WebViewScreen(
          title: 'ELSTER-Anmeldung',
          url: _elsterLoginUrl,
          customJs: _elsterAutoFillJs(
            password: pw,
            // Only embed the keystore where JS has to build the File itself.
            certificateBase64: Platform.isLinux ? null : b64,
            certificateName: certName,
          ),
          fileInputSelector: Platform.isLinux ? 'input[type="file"]' : null,
          fileToUpload: tmp,
        ),
      ));
    } catch (e) {
      if (mounted) _snack('Fehler: $e', isError: true);
    } finally {
      // Never leave the keystore lying around in temp. On Linux the browser has
      // already read it by the time the screen is popped; if it has not, the
      // user can still pick the file by hand.
      if (tmp != null) {
        try { if (await tmp.exists()) await tmp.delete(); } catch (_) {}
      }
      if (mounted) setState(() => _elsterBusy = false);
    }
  }

  /// JS injected into the ELSTER login page: put the password in, and — where
  /// no real file can be handed over — build the keystore as a File in the page
  /// and place it in the file input via DataTransfer.
  ///
  /// JavaScript may not assign a path to `input.files`; that restriction is the
  /// browser's. It CAN assign a FileList built from bytes, which is the whole
  /// trick here. On Linux this is unnecessary — CDP's DOM.setFileInputFiles
  /// takes the path directly — so the certificate is not embedded there.
  ///
  /// Written defensively throughout: the page's markup is not ours, so every
  /// step is optional and a failure leaves the page usable by hand rather than
  /// throwing.
  String _elsterAutoFillJs({
    required String password,
    String? certificateBase64,
    String certificateName = 'elster.pfx',
  }) {
    final pw = jsonEncode(password);
    final certJs = certificateBase64 == null ? 'null' : jsonEncode(certificateBase64);
    final nameJs = jsonEncode(certificateName);
    return '''
(function () {
  try {
    var pw = $pw, certB64 = $certJs, certName = $nameJs;
    var didFile = false;

    var setNativeValue = function (el, value) {
      var setter = Object.getOwnPropertyDescriptor(
        window.HTMLInputElement.prototype, 'value').set;
      setter.call(el, value);
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
    };

    var putFile = function (input) {
      if (didFile || !certB64) return;
      try {
        var bin = atob(certB64);
        var bytes = new Uint8Array(bin.length);
        for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
        var file = new File([bytes], certName, { type: 'application/x-pkcs12' });
        var dt = new DataTransfer();
        dt.items.add(file);
        input.files = dt.files;
        input.dispatchEvent(new Event('input', { bubbles: true }));
        input.dispatchEvent(new Event('change', { bubbles: true }));
        didFile = true;
      } catch (e) { /* user picks it by hand */ }
    };

    var fill = function () {
      var f = document.querySelector('input[type="file"]');
      if (f) putFile(f);
      var p = document.querySelector('input[type="password"]');
      if (p && !p.value) setNativeValue(p, pw);
    };

    fill();
    // The certificate pane is rendered client-side, so the fields may appear
    // after we first run.
    var obs = new MutationObserver(fill);
    obs.observe(document.documentElement, { childList: true, subtree: true });
    setTimeout(function () { obs.disconnect(); }, 20000);
  } catch (e) { /* page still usable by hand */ }
})();
''';
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

  Future<bool> _confirmDelete(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// Like [_formatDate] but keeps the time when there is one — a phone call at
  /// 10:15 is a different record from "some time that day".
  String _formatDateTime(String dateStr) {
    final dt = DateTime.tryParse(dateStr);
    if (dt == null) return dateStr;
    final d = '${dt.day.toString().padLeft(2, '0')}.'
        '${dt.month.toString().padLeft(2, '0')}.${dt.year}';
    if (dt.hour == 0 && dt.minute == 0) return d;
    return '$d ${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
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

// ─── Korrespondenz capture ──────────────────────────────────────────────────

class _KorrDraft {
  final String richtung;
  final String weg;
  final String datum;
  final String betreff;
  final String absender;
  final String empfaenger;
  final String gespraechspartner;
  final String notiz;
  final List<PlatformFile> files;
  _KorrDraft({
    required this.richtung,
    required this.weg,
    required this.datum,
    required this.betreff,
    required this.absender,
    required this.empfaenger,
    required this.gespraechspartner,
    required this.notiz,
    required this.files,
  });
}

class _KorrespondenzDialog extends StatefulWidget {
  final String defaultPartner;
  final String finanzamtName;
  const _KorrespondenzDialog({required this.defaultPartner, required this.finanzamtName});

  @override
  State<_KorrespondenzDialog> createState() => _KorrespondenzDialogState();
}

class _KorrespondenzDialogState extends State<_KorrespondenzDialog> {
  String _richtung = 'eingang';
  String _weg = 'post';
  DateTime _datum = DateTime.now();

  final _betreff = TextEditingController();
  late final TextEditingController _partner =
      TextEditingController(text: widget.defaultPartner);
  final _notiz = TextEditingController();

  final List<PlatformFile> _files = [];
  String? _error;

  bool get _isAnruf => _weg == 'anruf';

  @override
  void dispose() {
    _betreff.dispose();
    _partner.dispose();
    _notiz.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final picked = await FilePickerHelper.pickFiles(
      type: FileType.custom,
      allowedExtensions: _korrExtensions,
      allowMultiple: true,
      dialogTitle: 'Dokumente auswählen',
    );
    if (picked == null) return;
    // The macOS picker branch silently drops the extension filter, so re-check.
    final valid = picked.files.where((f) {
      final ext = f.name.contains('.') ? f.name.split('.').last.toLowerCase() : '';
      return f.path != null && _korrExtensions.contains(ext);
    }).toList();
    if (!mounted) return;
    setState(() {
      _files.addAll(valid);
      _error = valid.length < picked.files.length
          ? 'Nur PDF, JPG und PNG — ${picked.files.length - valid.length} '
            'Datei(en) übersprungen.'
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Korrespondenz erfassen'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Richtung',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'eingang', label: Text('Eingang'),
                      icon: Icon(Icons.south_west, size: 16)),
                  ButtonSegment(value: 'ausgang', label: Text('Ausgang'),
                      icon: Icon(Icons.north_east, size: 16)),
                ],
                selected: {_richtung},
                onSelectionChanged: (s) => setState(() => _richtung = s.first),
              ),
              const SizedBox(height: 16),
              const Text('Weg', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _wegValues.map((v) => ChoiceChip(
                      avatar: Icon(_wegIcon[v], size: 14),
                      label: Text(_wegLabel[v]!, style: const TextStyle(fontSize: 12)),
                      selected: _weg == v,
                      onSelected: (_) => setState(() => _weg = v),
                    )).toList(),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(
                  '${_datum.day.toString().padLeft(2, '0')}.'
                  '${_datum.month.toString().padLeft(2, '0')}.${_datum.year}'
                  '${_isAnruf ? '  ${_datum.hour.toString().padLeft(2, '0')}:'
                               '${_datum.minute.toString().padLeft(2, '0')}' : ''}',
                ),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _datum,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                    locale: const Locale('de'),
                  );
                  if (d == null || !context.mounted) return;
                  // A phone call needs the time of day; a letter does not.
                  TimeOfDay? t;
                  if (_isAnruf) {
                    t = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(_datum),
                    );
                  }
                  if (!mounted) return;
                  setState(() => _datum = DateTime(d.year, d.month, d.day,
                      t?.hour ?? _datum.hour, t?.minute ?? _datum.minute));
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _partner,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(), isDense: true,
                  labelText: 'Gesprächspartner / Sachbearbeiter',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _betreff,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(), isDense: true, labelText: 'Betreff',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notiz,
                maxLines: 4,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  isDense: true,
                  labelText: _isAnruf ? 'Notiz (erforderlich)' : 'Notiz',
                  helperText: _isAnruf
                      ? 'Bei einem Anruf ist die Notiz der einzige Nachweis.'
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('Dokumente${_isAnruf ? ' (optional)' : ''}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.attach_file, size: 16),
                    label: const Text('Hinzufügen'),
                    onPressed: _pickFiles,
                  ),
                ],
              ),
              if (_files.isEmpty)
                Text('PDF, JPG oder PNG',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500))
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _files.map((f) => Chip(
                        label: Text(f.name, style: const TextStyle(fontSize: 11)),
                        onDeleted: () => setState(() => _files.remove(f)),
                        visualDensity: VisualDensity.compact,
                      )).toList(),
                ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade600, foregroundColor: Colors.white),
          onPressed: () {
            // Mirrors the server rule — a call with no note leaves no record.
            if (_isAnruf && _notiz.text.trim().isEmpty) {
              setState(() => _error = 'Bei einem Anruf ist eine Notiz erforderlich.');
              return;
            }
            final isEingang = _richtung == 'eingang';
            Navigator.pop(
              context,
              _KorrDraft(
                richtung: _richtung,
                weg: _weg,
                datum: '${_datum.year}-${_datum.month.toString().padLeft(2, '0')}-'
                       '${_datum.day.toString().padLeft(2, '0')} '
                       '${_datum.hour.toString().padLeft(2, '0')}:'
                       '${_datum.minute.toString().padLeft(2, '0')}:00',
                betreff: _betreff.text.trim(),
                absender: isEingang ? widget.finanzamtName : 'ICD360S e.V.',
                empfaenger: isEingang ? 'ICD360S e.V.' : widget.finanzamtName,
                gespraechspartner: _partner.text.trim(),
                notiz: _notiz.text.trim(),
                files: _files,
              ),
            );
          },
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}

/// Sequential upload with per-file status; cannot be dismissed until finished.
///
/// Modelled on the Secure Cloud batch dialog — the one place in this app that
/// gets the Android back-button case right — but parameterised by an upload
/// callback instead of being welded to one service.
class _KorrUploadProgressDialog extends StatefulWidget {
  final List<PlatformFile> files;
  final Future<String?> Function(PlatformFile) upload;
  const _KorrUploadProgressDialog({required this.files, required this.upload});

  @override
  State<_KorrUploadProgressDialog> createState() => _KorrUploadProgressDialogState();
}

class _KorrUploadProgressDialogState extends State<_KorrUploadProgressDialog> {
  final Map<int, String> _errors = {};
  final Set<int> _done = {};
  int _current = -1;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    for (var i = 0; i < widget.files.length; i++) {
      if (!mounted) return;
      setState(() => _current = i);
      final err = await widget.upload(widget.files[i]);
      if (!mounted) return;
      setState(() {
        _done.add(i);
        if (err != null) _errors[i] = err;
      });
    }
    if (mounted) setState(() { _finished = true; _current = -1; });
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.files.length;
    final failed = _errors.length;
    return PopScope(
      canPop: _finished,
      child: AlertDialog(
        title: Text(_finished
            ? 'Fertig (${_done.length - failed}/$total)'
            : 'Hochladen … (${_done.length}/$total)'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : _done.length / total,
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: total,
                  itemBuilder: (_, i) {
                    final Widget icon;
                    if (_errors.containsKey(i)) {
                      icon = const Icon(Icons.error, color: Colors.red, size: 20);
                    } else if (_done.contains(i)) {
                      icon = const Icon(Icons.check_circle, color: Colors.green, size: 20);
                    } else if (i == _current) {
                      icon = const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4));
                    } else {
                      icon = const Icon(Icons.schedule, color: Colors.grey, size: 20);
                    }
                    return ListTile(
                      dense: true,
                      leading: icon,
                      title: Text(widget.files[i].name,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13)),
                      subtitle: _errors[i] == null
                          ? null
                          : Text(_errors[i]!,
                              style: const TextStyle(color: Colors.red, fontSize: 11)),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _finished ? () => Navigator.of(context).pop() : null,
            child: Text(_finished && failed > 0
                ? 'Schließen ($failed fehlgeschlagen)' : 'Fertig'),
          ),
        ],
      ),
    );
  }
}
