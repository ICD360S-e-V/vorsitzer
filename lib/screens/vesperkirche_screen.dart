import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../widgets/file_viewer_dialog.dart';
import '../utils/file_picker_helper.dart';

/// Vereinverwaltung → Partner & Dienstleister → Ulmer Vesperkirche
/// (Pauluskirche Ulm, Frauenstraße 110). Three-tab layout mirroring the
/// Microsoft-for-Nonprofits screen but with a static Details card
/// (no credentials to manage). Aufgaben + Korrespondenz reuse the shared
/// `platform_*` backend with a fixed key.
class VesperkircheScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onBack;

  const VesperkircheScreen({
    super.key,
    required this.apiService,
    required this.onBack,
  });

  @override
  State<VesperkircheScreen> createState() => _VesperkircheScreenState();
}

class _VesperkircheScreenState extends State<VesperkircheScreen>
    with SingleTickerProviderStateMixin {
  static const String _platformId = 'vesperkirche';

  // Static partner data — Ulmer Vesperkirche (Paulusgemeinde Ulm).
  // Source: pauluskirche-ulm.de/vesperkirche.html, Wikipedia, public Kontakt page.
  static const String _name = 'Ulmer Vesperkirche';
  static const String _traeger = 'Evangelische Kirchengemeinde Pauluskirche Ulm';
  static const String _strasse = 'Frauenstraße 110';
  static const String _plz = '89073';
  static const String _ort = 'Ulm';
  static const String _telefon = '0731 24318';
  static const String _fax = '0731 22705';
  static const String _email = 'Pfarramt.Ulm.Pauluskirche@elkw.de';
  static const String _website = 'https://www.pauluskirche-ulm.de/vesperkirche.html';
  static const String _beschreibung =
      'Soziales Projekt der Paulusgemeinde Ulm: Bedürftige erhalten in der '
      'Pauluskirche zu einem symbolischen Preis ein warmes Mittagessen in '
      'würdevoller Atmosphäre — täglich ca. 500 Mahlzeiten, getragen von rund '
      '200 Ehrenamtlichen. Jährlich aktiv ca. 4 Wochen ab Mitte Januar.';

  late TabController _tabController;

  // Aufgaben
  bool _aufgabenLoading = true;
  List<Map<String, dynamic>> _aufgaben = [];

  // Korrespondenz state (Eingang / Ausgang)
  String _korrTab = 'eingang';
  List<Map<String, dynamic>> _korrEingang = [];
  List<Map<String, dynamic>> _korrAusgang = [];
  final Set<int> _korrExpanded = <int>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAufgaben();
    _loadKorrespondenz();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════════════
  // Aufgaben
  // ════════════════════════════════════════════════════════════════

  Future<void> _loadAufgaben() async {
    try {
      final result = await widget.apiService.getPlatformAufgaben(_platformId);
      if (result['success'] == true && result['aufgaben'] != null) {
        _aufgaben = List<Map<String, dynamic>>.from(result['aufgaben']);
      }
    } catch (_) {
      // surface in card empty-state instead of crashing the screen
    }
    if (mounted) setState(() => _aufgabenLoading = false);
  }

  Future<void> _showCreateAufgabeDialog() async {
    final messenger = ScaffoldMessenger.of(context);
    final titelController = TextEditingController();
    final beschreibungController = TextEditingController();
    DateTime selectedDate = DateTime.now().add(const Duration(days: 7));
    TimeOfDay selectedTime = const TimeOfDay(hour: 10, minute: 0);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Icon(Icons.add_task, color: Colors.deepPurple.shade700),
            const SizedBox(width: 8),
            const Text('Neue Aufgabe'),
          ]),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titelController,
                  decoration: const InputDecoration(
                    labelText: 'Titel *',
                    hintText: 'z.B. Spenden-Sammel-Aktion vorbereiten',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: beschreibungController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Beschreibung (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: selectedDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                          locale: const Locale('de'),
                        );
                        if (picked != null) {
                          setDialogState(() => selectedDate = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Fällig am',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_today, size: 18),
                        ),
                        child: Text(DateFormat('dd.MM.yyyy').format(selectedDate)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: ctx,
                          initialTime: selectedTime,
                        );
                        if (picked != null) {
                          setDialogState(() => selectedTime = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Uhrzeit',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.access_time, size: 18),
                        ),
                        child: Text(
                          '${selectedTime.hour.toString().padLeft(2, '0')}:'
                          '${selectedTime.minute.toString().padLeft(2, '0')}',
                        ),
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                if (titelController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Bitte Titel eingeben'), backgroundColor: Colors.orange),
                  );
                  return;
                }
                Navigator.pop(ctx, true);
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Erstellen'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      final faelligAm = DateTime(
        selectedDate.year, selectedDate.month, selectedDate.day,
        selectedTime.hour, selectedTime.minute,
      );
      final faelligStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(faelligAm);

      final res = await widget.apiService.createPlatformAufgabe(
        platform: _platformId,
        titel: titelController.text.trim(),
        faelligAm: faelligStr,
        beschreibung: beschreibungController.text.trim().isEmpty
            ? null
            : beschreibungController.text.trim(),
      );

      if (mounted) {
        if (res['success'] == true) {
          await _loadAufgaben();
          messenger.showSnackBar(
            const SnackBar(content: Text('Aufgabe erstellt'), backgroundColor: Colors.green),
          );
        } else {
          messenger.showSnackBar(
            SnackBar(content: Text('Fehler: ${res['message']}'), backgroundColor: Colors.red),
          );
        }
      }
    }
    titelController.dispose();
    beschreibungController.dispose();
  }

  Future<void> _toggleAufgabe(Map<String, dynamic> aufgabe) async {
    final newErledigt = !(aufgabe['erledigt'] as bool);
    final res = await widget.apiService.updatePlatformAufgabe({
      'id': aufgabe['id'],
      'erledigt': newErledigt ? 1 : 0,
    });
    if (res['success'] == true && mounted) await _loadAufgaben();
  }

  Future<void> _deleteAufgabe(int id) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aufgabe löschen?'),
        content: const Text('Diese Aufgabe wird unwiderruflich gelöscht.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final res = await widget.apiService.deletePlatformAufgabe(id);
      if (res['success'] == true && mounted) {
        await _loadAufgaben();
        messenger.showSnackBar(
          const SnackBar(content: Text('Aufgabe gelöscht'), backgroundColor: Colors.green),
        );
      }
    }
  }

  bool _isOverdue(String? dateStr) {
    if (dateStr == null) return false;
    try {
      return DateTime.parse(dateStr).isBefore(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  String _formatFaelligAm(String? dateStr) {
    if (dateStr == null) return '-';
    try {
      return DateFormat('dd.MM.yyyy, HH:mm').format(DateTime.parse(dateStr));
    } catch (_) {
      return dateStr;
    }
  }

  // ════════════════════════════════════════════════════════════════
  // Korrespondenz (Eingang / Ausgang + multi-file upload)
  // ════════════════════════════════════════════════════════════════

  Future<void> _loadKorrespondenz() async {
    try {
      final results = await Future.wait([
        widget.apiService.getPlatformKorrespondenz(platform: _platformId, direction: 'eingang'),
        widget.apiService.getPlatformKorrespondenz(platform: _platformId, direction: 'ausgang'),
      ]);
      if (results[0]['success'] == true && results[0]['korrespondenz'] != null) {
        _korrEingang = List<Map<String, dynamic>>.from(results[0]['korrespondenz']);
      }
      if (results[1]['success'] == true && results[1]['korrespondenz'] != null) {
        _korrAusgang = List<Map<String, dynamic>>.from(results[1]['korrespondenz']);
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  List<Map<String, dynamic>> get _currentKorrList =>
      _korrTab == 'eingang' ? _korrEingang : _korrAusgang;

  Future<void> _showCreateKorrespondenzDialog() async {
    final betreffCtrl = TextEditingController();
    final inhaltCtrl = TextEditingController();
    final absenderCtrl = TextEditingController();
    final empfaengerCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now();
    List<File> pickedFiles = [];
    bool saving = false;

    final isEingang = _korrTab == 'eingang';

    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setDState) => AlertDialog(
          title: Text(isEingang ? 'Neue Eingang-Mail' : 'Neue Ausgang-Mail'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: dctx,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 1)),
                      );
                      if (picked != null) {
                        setDState(() {
                          selectedDate = DateTime(picked.year, picked.month, picked.day,
                              selectedDate.hour, selectedDate.minute);
                        });
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Datum',
                        prefixIcon: Icon(Icons.calendar_today),
                        border: OutlineInputBorder(),
                      ),
                      child: Text(DateFormat('dd.MM.yyyy').format(selectedDate)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: betreffCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Betreff *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.subject),
                    ),
                    maxLength: 500,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: isEingang ? absenderCtrl : empfaengerCtrl,
                    decoration: InputDecoration(
                      labelText: isEingang ? 'Absender' : 'Empfänger',
                      hintText: isEingang
                          ? 'z.B. Pfarramt.Ulm.Pauluskirche@elkw.de'
                          : 'z.B. Pfarramt.Ulm.Pauluskirche@elkw.de',
                      border: const OutlineInputBorder(),
                      prefixIcon: Icon(isEingang ? Icons.mail : Icons.send),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: inhaltCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Inhalt',
                      hintText: 'Volltext der Nachricht (optional)',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    maxLines: 8,
                    minLines: 4,
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.attach_file),
                      label: Text('Dateien hinzufügen (${pickedFiles.length})'),
                      onPressed: saving
                          ? null
                          : () async {
                              final files = await _pickFiles();
                              if (files.isNotEmpty) {
                                setDState(() => pickedFiles.addAll(files));
                              }
                            },
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'mehrere gleichzeitig · max 25 MB pro Datei',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ]),
                  if (pickedFiles.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: pickedFiles.asMap().entries.map((e) {
                        final i = e.key;
                        final f = e.value;
                        final name = f.uri.pathSegments.isNotEmpty
                            ? f.uri.pathSegments.last
                            : 'datei';
                        return Chip(
                          label: Text(name, style: const TextStyle(fontSize: 12)),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: saving ? null : () => setDState(() => pickedFiles.removeAt(i)),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dctx, false),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton.icon(
              icon: saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text(saving ? 'Speichern...' : 'Speichern'),
              onPressed: saving
                  ? null
                  : () async {
                      if (betreffCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(dctx).showSnackBar(
                          const SnackBar(content: Text('Betreff ist erforderlich')),
                        );
                        return;
                      }
                      setDState(() => saving = true);
                      final result = await widget.apiService.createPlatformKorrespondenz(
                        platform: _platformId,
                        direction: _korrTab,
                        betreff: betreffCtrl.text.trim(),
                        datum: selectedDate,
                        inhalt: inhaltCtrl.text.trim().isEmpty ? null : inhaltCtrl.text.trim(),
                        absender: isEingang ? absenderCtrl.text.trim() : null,
                        empfaenger: !isEingang ? empfaengerCtrl.text.trim() : null,
                        files: pickedFiles,
                      );
                      if (!dctx.mounted) return;
                      if (result['success'] == true) {
                        Navigator.pop(dctx, true);
                      } else {
                        setDState(() => saving = false);
                        ScaffoldMessenger.of(dctx).showSnackBar(
                          SnackBar(
                            content: Text('Fehler: ${result['message'] ?? 'Unbekannter Fehler'}'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
            ),
          ],
        ),
      ),
    );

    betreffCtrl.dispose();
    inhaltCtrl.dispose();
    absenderCtrl.dispose();
    empfaengerCtrl.dispose();

    if (created == true) {
      await _loadKorrespondenz();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Korrespondenz gespeichert'), backgroundColor: Colors.green),
        );
      }
    }
  }

  Future<void> _deleteKorrespondenz(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Löschen?'),
        content: const Text('Diese Korrespondenz und alle Anhänge werden dauerhaft entfernt.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Abbrechen')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final result = await widget.apiService.deletePlatformKorrespondenz(id);
    if (!mounted) return;
    if (result['success'] == true) {
      await _loadKorrespondenz();
      messenger.showSnackBar(
        const SnackBar(content: Text('Gelöscht'), backgroundColor: Colors.green),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text('Fehler: ${result['message']}'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _openKorrespondenzAttachment(Map<String, dynamic> file) async {
    final fileId = file['id'] as int;
    final fileName = (file['datei_name'] as String?) ?? 'attachment';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
          const SizedBox(width: 12),
          Text('Lade $fileName ...'),
        ]),
        duration: const Duration(seconds: 30),
      ),
    );

    final Uint8List? bytes = await widget.apiService.downloadPlatformKorrespondenzFile(fileId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Datei konnte nicht geladen werden'), backgroundColor: Colors.red),
      );
      return;
    }
    await FileViewerDialog.showFromBytes(context, bytes, fileName);
  }

  Future<List<File>> _pickFiles() async {
    try {
      final res = await FilePickerHelper.pickFiles(
        allowMultiple: true,
        withData: false,
      );
      if (res == null) return [];
      return res.files
          .where((f) => f.path != null)
          .map((f) => File(f.path!))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ════════════════════════════════════════════════════════════════
  // Build
  // ════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: widget.onBack,
              tooltip: 'Zurück zu Partner & Dienstleister',
            ),
            const SizedBox(width: 8),
            Icon(Icons.church, size: 32, color: Colors.deepPurple.shade700),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Ulmer Vesperkirche',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          TabBar(
            controller: _tabController,
            labelColor: Colors.deepPurple.shade700,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: Colors.deepPurple.shade700,
            tabs: [
              const Tab(icon: Icon(Icons.info_outline), text: 'Details'),
              Tab(
                icon: const Icon(Icons.task_alt),
                text: 'Aufgaben${_aufgaben.isNotEmpty ? " (${_aufgaben.where((a) => !(a['erledigt'] as bool)).length})" : ""}',
              ),
              Tab(
                icon: const Icon(Icons.email),
                text: 'Korrespondenz (${_korrEingang.length + _korrAusgang.length})',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildDetailsTab(),
                _buildAufgabenTab(),
                _buildKorrespondenzTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.church, color: Colors.deepPurple.shade700, size: 22),
                    const SizedBox(width: 8),
                    const Text(_name,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 4),
                  Text(_traeger,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontStyle: FontStyle.italic)),
                  const SizedBox(height: 16),
                  Text(
                    _beschreibung,
                    style: const TextStyle(fontSize: 14, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Kontakt', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _kontaktRow(Icons.location_on, 'Adresse', '$_strasse · $_plz $_ort'),
                  _kontaktRow(Icons.phone, 'Telefon', _telefon,
                      onTap: () => _launch('tel:${_telefon.replaceAll(' ', '')}')),
                  _kontaktRow(Icons.fax, 'Fax', _fax),
                  _kontaktRow(Icons.email, 'E-Mail', _email,
                      onTap: () => _launch('mailto:$_email')),
                  _kontaktRow(Icons.language, 'Website', _website,
                      onTap: () => _launch(_website)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kontaktRow(IconData icon, String label, String value, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: value));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$value" kopiert'), duration: const Duration(seconds: 1)),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          SizedBox(
            width: 110,
            child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: onTap != null ? Colors.blue.shade700 : null,
                decoration: onTap != null ? TextDecoration.underline : null,
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildAufgabenTab() {
    if (_aufgabenLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            const Expanded(
              child: Text('Aufgaben & Fristen',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neue Aufgabe'),
              onPressed: _showCreateAufgabeDialog,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ]),
        ),
        Expanded(
          child: _aufgaben.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.checklist, size: 48, color: Colors.grey.shade300),
                      const SizedBox(height: 8),
                      Text('Keine Aufgaben vorhanden',
                          style: TextStyle(color: Colors.grey.shade500)),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: _aufgaben.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final a = _aufgaben[i];
                    final erledigt = a['erledigt'] as bool;
                    final overdue = !erledigt && _isOverdue(a['faellig_am']);
                    return Container(
                      decoration: BoxDecoration(
                        color: erledigt
                            ? Colors.green.shade50
                            : overdue
                                ? Colors.red.shade50
                                : Colors.deepPurple.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: erledigt
                              ? Colors.green.shade200
                              : overdue
                                  ? Colors.red.shade300
                                  : Colors.deepPurple.shade200,
                        ),
                      ),
                      child: ListTile(
                        leading: IconButton(
                          icon: Icon(
                            erledigt ? Icons.check_circle : Icons.radio_button_unchecked,
                            color: erledigt ? Colors.green.shade700 : Colors.deepPurple.shade600,
                            size: 28,
                          ),
                          onPressed: () => _toggleAufgabe(a),
                        ),
                        title: Text(
                          a['titel'],
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            decoration: erledigt ? TextDecoration.lineThrough : null,
                            color: erledigt ? Colors.grey : null,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if ((a['beschreibung'] ?? '').toString().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(a['beschreibung'].toString(),
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                              ),
                            const SizedBox(height: 4),
                            Row(children: [
                              Icon(Icons.schedule, size: 14,
                                  color: overdue ? Colors.red.shade700 : Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Text(_formatFaelligAm(a['faellig_am'] as String?),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: overdue ? FontWeight.bold : null,
                                    color: overdue ? Colors.red.shade700 : Colors.grey.shade600,
                                  )),
                              if (overdue) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text('Überfällig',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red.shade800,
                                      )),
                                ),
                              ],
                            ]),
                          ],
                        ),
                        trailing: IconButton(
                          icon: Icon(Icons.delete_outline, size: 20, color: Colors.red.shade400),
                          onPressed: () => _deleteAufgabe(a['id'] as int),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildKorrespondenzTab() {
    final list = _currentKorrList;
    final isEingang = _korrTab == 'eingang';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            Expanded(
              child: Row(children: [
                Expanded(
                  child: ChoiceChip(
                    label: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.inbox, size: 18),
                        const SizedBox(width: 6),
                        Text('Eingang (${_korrEingang.length})'),
                      ],
                    ),
                    selected: _korrTab == 'eingang',
                    onSelected: (_) => setState(() => _korrTab = 'eingang'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.send, size: 18),
                        const SizedBox(width: 6),
                        Text('Ausgang (${_korrAusgang.length})'),
                      ],
                    ),
                    selected: _korrTab == 'ausgang',
                    onSelected: (_) => setState(() => _korrTab = 'ausgang'),
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: Text('Neue ${isEingang ? "Eingang" : "Ausgang"}'),
              onPressed: _showCreateKorrespondenzDialog,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ]),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.email_outlined, size: 48, color: Colors.grey.shade300),
                      const SizedBox(height: 8),
                      Text('Keine ${isEingang ? "Eingang" : "Ausgang"}-Mails',
                          style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) => _buildKorrespondenzItem(list[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildKorrespondenzItem(Map<String, dynamic> entry) {
    final id = entry['id'] as int;
    final betreff = (entry['betreff'] as String?) ?? '(ohne Betreff)';
    final inhalt = (entry['inhalt'] as String?) ?? '';
    final datumStr = (entry['datum'] as String?) ?? '';
    DateTime? datum;
    try { datum = DateTime.parse(datumStr); } catch (_) {}
    final dateLabel = datum != null ? DateFormat('dd.MM.yyyy HH:mm').format(datum) : datumStr;
    final partner = _korrTab == 'eingang'
        ? ((entry['absender'] as String?) ?? '')
        : ((entry['empfaenger'] as String?) ?? '');
    final files = List<Map<String, dynamic>>.from(entry['files'] ?? const []);
    final expanded = _korrExpanded.contains(id);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            dense: true,
            leading: Icon(
              _korrTab == 'eingang' ? Icons.inbox : Icons.send,
              color: Colors.deepPurple.shade700,
            ),
            title: Text(
              betreff,
              style: const TextStyle(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dateLabel, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                if (partner.isNotEmpty)
                  Text(
                    '${_korrTab == "eingang" ? "Von" : "An"}: $partner',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                  ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (files.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('${files.length}'),
                      avatar: const Icon(Icons.attach_file, size: 14),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                IconButton(
                  icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                  onPressed: () => setState(() {
                    if (expanded) {
                      _korrExpanded.remove(id);
                    } else {
                      _korrExpanded.add(id);
                    }
                  }),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: Colors.red.shade400,
                  onPressed: () => _deleteKorrespondenz(id),
                ),
              ],
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (inhalt.isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: SelectableText(inhalt, style: const TextStyle(fontSize: 13)),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (files.isNotEmpty) ...[
                    Text('Anhänge:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        )),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: files.map((f) {
                        final name = (f['datei_name'] as String?) ?? 'datei';
                        final size = (f['datei_groesse'] as int?) ?? 0;
                        final sizeKb = size > 0 ? '${(size / 1024).toStringAsFixed(0)} KB' : '';
                        return ActionChip(
                          avatar: const Icon(Icons.insert_drive_file, size: 16),
                          label: Text(
                            '$name${sizeKb.isNotEmpty ? " · $sizeKb" : ""}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          onPressed: () => _openKorrespondenzAttachment(f),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
