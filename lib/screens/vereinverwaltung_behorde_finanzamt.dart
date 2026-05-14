import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../widgets/file_viewer_dialog.dart';
import '../utils/file_picker_helper.dart';

class FinanzamtScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onBack;

  const FinanzamtScreen({
    super.key,
    required this.apiService,
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
  bool _docsLoading = false;
  bool _uploading = false;

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
    _docsLoading = true;
    try {
      final result = await widget.apiService.getFinanzamtDokumente();
      if (mounted && result['success'] == true) {
        _dokumente = List<Map<String, dynamic>>.from(result['dokumente'] ?? []);
      }
    } catch (_) {}
    _docsLoading = false;
  }

  Future<void> _saveVereinFinanzamt(Map<String, dynamic> data) async {
    try {
      final result = await widget.apiService.saveVereinFinanzamt(data);
      if (mounted) {
        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gespeichert'), backgroundColor: Colors.green),
          );
          _loadVereinFinanzamt().then((_) { if (mounted) setState(() {}); });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['message'] ?? 'Fehler'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    }
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
                      if (picked != null) {
                        datumController.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                      }
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

  Future<void> _uploadDokument() async {
    final result = await FilePickerHelper.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'doc', 'docx', 'tiff', 'bmp'],
      dialogTitle: 'Dokument auswählen',
    );

    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;

    final info = await _showUploadDialog(file.name);
    if (info == null) return;

    setState(() => _uploading = true);
    try {
      final uploadResult = await widget.apiService.uploadFinanzamtDokument(
        filePath: file.path!,
        fileName: file.name,
        kategorie: info['kategorie'] ?? 'sonstiges',
        beschreibung: info['beschreibung'] ?? '',
      );

      if (mounted) {
        if (uploadResult['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Dokument hochgeladen'), backgroundColor: Colors.green),
          );
          _loadDokumente().then((_) { if (mounted) setState(() {}); });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(uploadResult['message'] ?? 'Upload fehlgeschlagen'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<Map<String, String>?> _showUploadDialog(String fileName) async {
    final beschreibungController = TextEditingController();
    String selectedKategorie = 'gemeinnuetzigkeit';

    final kategorien = {
      'gemeinnuetzigkeit': 'Gemeinnützigkeit',
      'steuerbescheid': 'Steuerbescheid',
      'freistellungsbescheid': 'Freistellungsbescheid',
      'korrespondenz': 'Korrespondenz',
      'sonstiges': 'Sonstiges',
    };

    return showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.upload_file, color: Colors.teal.shade700),
              const SizedBox(width: 8),
              const Expanded(child: Text('Dokument hochladen')),
            ],
          ),
          content: SizedBox(
            width: 400,
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
                        child: Text(fileName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Kategorie', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: selectedKategorie,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                  items: kategorien.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDialogState(() => selectedKategorie = v);
                  },
                ),
                const SizedBox(height: 16),
                const Text('Beschreibung (optional)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.upload, size: 18),
              label: const Text('Hochladen'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade600,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, {
                'kategorie': selectedKategorie,
                'beschreibung': beschreibungController.text.trim(),
              }),
            ),
          ],
        ),
      ),
    );
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

    final result = await widget.apiService.deleteFinanzamtDokument(doc['id'] is int ? doc['id'] : int.parse(doc['id'].toString()));
    if (mounted) {
      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dokument gelöscht'), backgroundColor: Colors.green),
        );
        _loadDokumente().then((_) { if (mounted) setState(() {}); });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'] ?? 'Löschen fehlgeschlagen'), backgroundColor: Colors.red),
        );
      }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
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
          // Header
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
              const Text(
                'Finanzamt',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Content
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
                            Text(
                              'Keine Finanzamt-Daten vorhanden',
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
                            ),
                          ],
                        ),
                      )
                    : _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final d = _finanzamtData!;
    final vf = _vereinFinanzamt;

    final oeffnungszeiten = d['oeffnungszeiten'] as String?;
    final terminTelefon = d['termin_telefon'] as String?;

    final steuernummer = vf?['steuernummer'] as String?;
    final gemeinnStatus = (vf?['gemeinnuetzigkeit_status'] ?? 'nicht_beantragt') as String;
    final gemeinnDatum = vf?['gemeinnuetzigkeit_datum'] as String?;
    final sachbearbeiterName = vf?['sachbearbeiter_name'] as String?;
    final sachbearbeiterTelefon = vf?['sachbearbeiter_telefon'] as String?;
    final sachbearbeiterEmail = vf?['sachbearbeiter_email'] as String?;
    final sachbearbeiterZimmer = vf?['sachbearbeiter_zimmer'] as String?;
    final aktenzeichen = vf?['aktenzeichen'] as String?;

    final gemeinnLabels = {
      'anerkannt': 'Anerkannt',
      'beantragt': 'Beantragt',
      'abgelehnt': 'Abgelehnt',
      'nicht_beantragt': 'Nicht beantragt',
    };

    final isAnerkannt = gemeinnStatus == 'anerkannt';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: Finanzamt contact info (from finanzaemter DB - read only)
        Expanded(
          flex: 2,
          child: Column(
            children: [
              Expanded(
                child: Card(
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
                              child: Text(
                                d['name'] ?? '',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 28),
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
                        const Spacer(),
                        Row(
                          children: [
                            if (d['website'] != null)
                              Expanded(
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.open_in_new, size: 16),
                                  label: const Text('Website öffnen'),
                                  onPressed: () => _openUrl(d['website']),
                                ),
                              ),
                            const SizedBox(width: 8),
                            if (d['email'] != null)
                              Expanded(
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.email, size: 16),
                                  label: const Text('E-Mail senden'),
                                  onPressed: () => _openUrl('mailto:${d['email']}'),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // Middle: Verein data (editable - from vereinverwaltung_behorde_finanzamt DB)
        Expanded(
          flex: 1,
          child: Card(
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
                        child: const Icon(Icons.verified, color: Colors.teal, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'ICD360S e.V.',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  // Steuernummer (editable)
                  InkWell(
                    onTap: _editSteuernummer,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.teal.shade100),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.tag, color: Colors.teal.shade700, size: 28),
                              const SizedBox(width: 4),
                              Icon(Icons.edit, size: 14, color: Colors.teal.shade400),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text('Steuernummer', style: TextStyle(fontSize: 13, color: Colors.grey)),
                          const SizedBox(height: 4),
                          Text(
                            steuernummer != null && steuernummer.isNotEmpty ? steuernummer : '(klicken zum Eintragen)',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Gemeinnützigkeit (editable)
                  InkWell(
                    onTap: _editGemeinnuetzigkeit,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isAnerkannt ? Colors.green.shade50 : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isAnerkannt ? Colors.green.shade200 : Colors.orange.shade200,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isAnerkannt ? Icons.check_circle : Icons.pending,
                                color: isAnerkannt ? Colors.green.shade700 : Colors.orange.shade700,
                                size: 28,
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.edit, size: 14, color: isAnerkannt ? Colors.green.shade400 : Colors.orange.shade400),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text('Gemeinnützigkeit', style: TextStyle(fontSize: 13, color: Colors.grey)),
                          const SizedBox(height: 4),
                          Text(
                            gemeinnLabels[gemeinnStatus] ?? gemeinnStatus,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isAnerkannt ? Colors.green.shade700 : Colors.orange.shade700,
                            ),
                          ),
                          if (gemeinnDatum != null && gemeinnDatum.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'seit ${_formatDate(gemeinnDatum)}',
                              style: TextStyle(fontSize: 12, color: isAnerkannt ? Colors.green.shade500 : Colors.orange.shade500),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Sachbearbeiter (editable)
                  InkWell(
                    onTap: _editSachbearbeiter,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.blue.shade100),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.person, color: Colors.blue.shade700, size: 28),
                              const SizedBox(width: 4),
                              Icon(Icons.edit, size: 14, color: Colors.blue.shade400),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text('Sachbearbeiter/in', style: TextStyle(fontSize: 13, color: Colors.grey)),
                          const SizedBox(height: 4),
                          Text(
                            sachbearbeiterName != null && sachbearbeiterName.isNotEmpty
                                ? sachbearbeiterName
                                : '(klicken zum Eintragen)',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          ),
                          if (sachbearbeiterTelefon != null && sachbearbeiterTelefon.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text('Tel: $sachbearbeiterTelefon', style: TextStyle(fontSize: 12, color: Colors.blue.shade400)),
                          ],
                          if (sachbearbeiterEmail != null && sachbearbeiterEmail.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(sachbearbeiterEmail, style: TextStyle(fontSize: 12, color: Colors.blue.shade400)),
                          ],
                          if (sachbearbeiterZimmer != null && sachbearbeiterZimmer.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text('Zimmer: $sachbearbeiterZimmer', style: TextStyle(fontSize: 12, color: Colors.blue.shade400)),
                          ],
                          if (aktenzeichen != null && aktenzeichen.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text('Az: $aktenzeichen', style: TextStyle(fontSize: 12, color: Colors.blue.shade400, fontWeight: FontWeight.w500)),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Info text
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.grey.shade500),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Klicken Sie auf ein Feld, um es zu bearbeiten.',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        // Right: Dokumente
        Expanded(
          flex: 1,
          child: Card(
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
                          color: Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.folder_open, color: Colors.amber, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Dokumente',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_dokumente.length} Dokument${_dokumente.length == 1 ? '' : 'e'}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                  const Divider(height: 24),
                  // Upload button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: _uploading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.upload_file, size: 18),
                      label: Text(_uploading ? 'Wird hochgeladen...' : 'Dokument hochladen'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: _uploading ? null : _uploadDokument,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Document list
                  Expanded(
                    child: _docsLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _dokumente.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.folder_open, size: 40, color: Colors.grey.shade300),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Noch keine Dokumente\nhochgeladen',
                                      style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                itemCount: _dokumente.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (_, i) => _buildDocItem(_dokumente[i]),
                              ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDocItem(Map<String, dynamic> doc) {
    final name = doc['original_name'] ?? 'Unbekannt';
    final kategorie = doc['kategorie'] ?? 'sonstiges';
    final beschreibung = doc['beschreibung'] ?? '';
    final createdAt = doc['created_at'] ?? '';
    final extension = name.contains('.') ? name.split('.').last.toLowerCase() : '';

    IconData fileIcon;
    Color fileColor;
    switch (extension) {
      case 'pdf':
        fileIcon = Icons.picture_as_pdf;
        fileColor = Colors.red;
        break;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'tiff':
      case 'bmp':
        fileIcon = Icons.image;
        fileColor = Colors.blue;
        break;
      case 'doc':
      case 'docx':
        fileIcon = Icons.description;
        fileColor = Colors.indigo;
        break;
      default:
        fileIcon = Icons.insert_drive_file;
        fileColor = Colors.grey;
    }

    final kategorieLabels = {
      'gemeinnuetzigkeit': 'Gemeinnützigkeit',
      'steuerbescheid': 'Steuerbescheid',
      'freistellungsbescheid': 'Freistellung',
      'korrespondenz': 'Korrespondenz',
      'sonstiges': 'Sonstiges',
    };

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
                child: Text(
                  name,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  kategorieLabels[kategorie] ?? kategorie,
                  style: TextStyle(fontSize: 10, color: Colors.teal.shade700),
                ),
              ),
              const SizedBox(width: 6),
              if (createdAt.isNotEmpty)
                Text(
                  _formatDate(createdAt),
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
            ],
          ),
          if (beschreibung.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              beschreibung,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              InkWell(
                onTap: () => _viewDokument(doc),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.visibility, size: 18, color: Colors.teal.shade600),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => _deleteDokument(doc),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr);
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
    } catch (_) {
      return dateStr;
    }
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 10),
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
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
