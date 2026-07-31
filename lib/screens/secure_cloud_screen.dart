import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import '../services/cloud_crypto_service.dart';
import '../services/live_document_detector.dart';
import '../services/scan_geometry.dart';
import '../services/secure_cloud_service.dart';
import 'document_crop_screen.dart';
import '../utils/file_picker_helper.dart';
import '../widgets/file_viewer_dialog.dart';
import '../widgets/scan_overlay.dart';

/// Admin "Sichere Cloud" — 50 GB, client-side zero-knowledge storage.
/// The recovery passphrase is requested on every open; the key lives only in
/// memory for the lifetime of this screen (wiped in dispose).
class SecureCloudScreen extends StatefulWidget {
  final String mitgliedernummer;
  final String userName;

  const SecureCloudScreen({
    super.key,
    required this.mitgliedernummer,
    required this.userName,
  });

  @override
  State<SecureCloudScreen> createState() => _SecureCloudScreenState();
}

enum _Stage { loading, error, needsSetup, needsUnlock, ready }

class _SecureCloudScreenState extends State<SecureCloudScreen> {
  final ApiService _api = ApiService();
  late final SecureCloudService _svc =
      SecureCloudService(_api, widget.mitgliedernummer);

  _Stage _stage = _Stage.loading;
  String? _error;
  bool _busy = false;
  CloudListing? _listing;
  String _filter = 'Alle'; // active file-type filter
  int _sortCol = 2; // 0=Name, 1=Größe, 2=Datum
  bool _sortAsc = false; // default: newest first

  static const int _maxBatch = 50; // max files per upload batch

  /// Hard cap for a transfer into a member cloud — nginx `client_max_body_size`
  /// and PHP `post_max_size` are both 200 MB on the server.
  static const int _maxTransferBytes = 200 * 1024 * 1024;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    // Absichtlich KEIN lock() mehr: die Cloud-Sitzung gilt jetzt für die ganze
    // App, nicht für diesen Bildschirm. Sonst wäre sie wieder zu, sobald man
    // das Cloud-Fenster verlässt, und Mail-Anhänge könnten nicht mehr
    // automatisch archiviert werden. Gesperrt wird beim Beenden der App
    // (dashboard_screen) oder von Hand.
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _stage = _Stage.loading;
      _error = null;
    });
    final has = await _svc.hasCloud();
    if (!mounted) return;
    if (has == null) {
      setState(() {
        _stage = _Stage.error;
        _error = 'Keine Verbindung zum Server.';
      });
      return;
    }
    if (!has) {
      setState(() => _stage = _Stage.needsSetup);
      return;
    }
    // Existing cloud. Before prompting, try to silently resume a session that
    // the file-picker Activity may have killed our process for — so returning
    // from picking a file doesn't re-ask the passphrase. (Camera capture is now
    // in-process and never kills us; see _capturePhotoAndUpload.)
    final resumed = await _svc.tryResume();
    if (!mounted) return;
    if (resumed) {
      setState(() => _stage = _Stage.ready);
      await _refresh();
    } else {
      setState(() => _stage = _Stage.needsUnlock);
    }
  }

  Future<void> _refresh() async {
    final listing = await _svc.list();
    if (!mounted) return;
    setState(() => _listing = listing);
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _doSetup(String passphrase) async {
    setState(() => _busy = true);
    final err = await _svc.setup(passphrase);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      _snack(err, isError: true);
      return;
    }
    setState(() => _stage = _Stage.ready);
    await _refresh();
  }

  Future<void> _doUnlock(String passphrase) async {
    setState(() => _busy = true);
    final err = await _svc.unlock(passphrase);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      _snack(err, isError: true);
      return;
    }
    setState(() => _stage = _Stage.ready);
    await _refresh();
  }

  Future<void> _pickAndUpload() async {
    // The file picker opens a separate Activity too — arm the resume token so
    // returning after a process kill auto-unlocks instead of re-prompting.
    await _svc.armResume();
    final result = await FilePickerHelper.pickFiles(
      allowMultiple: true,
      type: FileType.any,
      dialogTitle: 'Dateien in die Cloud hochladen (max. $_maxBatch)',
    );
    await _svc.clearResume(); // survived the round-trip
    if (result == null || result.files.isEmpty) return;
    var picked = result.files.where((f) => f.path != null).toList();
    if (picked.length > _maxBatch) {
      _snack('Max. $_maxBatch Dateien auf einmal — die ersten $_maxBatch werden hochgeladen.',
          isError: true);
      picked = picked.sublist(0, _maxBatch);
    }
    if (picked.isEmpty) return;
    final items = picked
        .map((f) => _Upload(
            file: File(f.path!), name: f.name, mime: _guessMime(f.name), source: 'device'))
        .toList();
    await _startUpload(items);
  }

  /// Take a photo with an IN-APP camera (the `camera` plugin renders the preview
  /// inside our own Activity). Because we never launch an external app, Android
  /// can't kill our process mid-capture — the DEK stays in RAM and the photo is
  /// never lost. The captured jpg comes back as an [XFile] we upload directly.
  Future<void> _capturePhotoAndUpload() async {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      _snack('Kamera ist nur auf dem Handy/Tablet verfügbar.', isError: true);
      return;
    }
    final _ScanShot? shot = await Navigator.of(context).push<_ScanShot>(
      MaterialPageRoute(builder: (_) => const _CameraCaptureScreen()),
    );
    if (shot == null || !mounted) return; // cancelled
    final raw = await File(shot.file.path).readAsBytes();
    if (!mounted) return;
    // Review step. When the live overlay was locked on the document as the
    // shutter fired it hands over a [ScanHint]; if the still detection agrees,
    // the crop happens automatically and this screen is never shown.
    final Uint8List? out = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => DocumentCropScreen(jpg: raw, hint: shot.hint),
      ),
    );
    if (out == null || !mounted) return;
    final tmp = File(
        '${(await getTemporaryDirectory()).path}/scan_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await tmp.writeAsBytes(out, flush: true);
    final name =
        'Scan_${DateTime.now().toIso8601String().substring(0, 19).replaceAll(':', '-')}.jpg';
    await _startUpload([
      _Upload(file: tmp, name: name, mime: 'image/jpeg', source: 'scan'),
    ]);
  }

  /// Returns true only if every item uploaded successfully.
  Future<bool> _startUpload(List<_Upload> items) async {
    if (items.isEmpty) return false;
    // Modal progress dialog: encrypts + uploads each file, showing a per-file
    // spinner that turns into a green check on success (red on error).
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UploadProgressDialog(svc: _svc, items: items),
    );
    await _refresh(); // reflect the new files + updated quota
    return items.every((i) => i.status == _UploadStatus.done);
  }

  Future<void> _download(CloudFile f) async {
    // Decrypt in RAM (no plaintext temp file), then let the user pick where to
    // save it via the native "save as" dialog.
    setState(() => _busy = true);
    final bytes = await _svc.downloadToMemory(f);
    if (!mounted) return;
    setState(() => _busy = false);
    if (bytes == null) {
      _snack('Download/Entschlüsselung fehlgeschlagen.', isError: true);
      return;
    }
    try {
      final savedPath = await FilePickerHelper.saveBytes(
        bytes: bytes,
        fileName: f.name,
        dialogTitle: 'Datei speichern',
      );
      if (savedPath == null) return; // user cancelled
      _snack('Gespeichert: $savedPath');
    } catch (e) {
      _snack('Speichern fehlgeschlagen: $e', isError: true);
    }
  }

  /// Preview a file with the dedicated in-app viewer for its type — decrypted
  /// entirely IN RAM, never written to disk. Each extension routes to its own
  /// viewer: PDF -> pdfrx, images -> image viewer (zoom/rotate), txt -> text.
  Future<void> _preview(CloudFile f) async {
    setState(() => _busy = true);
    final bytes = await _svc.downloadToMemory(f);
    if (!mounted) return;
    setState(() => _busy = false);
    if (bytes == null) {
      _snack('Laden/Entschlüsseln fehlgeschlagen.', isError: true);
      return;
    }
    final ext = f.name.contains('.') ? f.name.toLowerCase().split('.').last : '';
    if (ext == 'txt') {
      await _showTextViewer(f.name, bytes);
      return;
    }
    // PDF + images (jpg/jpeg/png/gif/webp/bmp/tiff) via the shared in-app viewer.
    final shown = await FileViewerDialog.showFromBytes(context, bytes, f.name);
    if (!shown && mounted) {
      _snack('Keine In-App-Vorschau für „.$ext" — über das Menü herunterladen.',
          isError: true);
    }
  }

  /// Dedicated in-app text viewer (from RAM). Handles .txt.
  Future<void> _showTextViewer(String name, Uint8List bytes) async {
    String text;
    try {
      text = utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      text = String.fromCharCodes(bytes);
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700, maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                title: Text(name, overflow: TextOverflow.ellipsis),
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    text,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Print a file directly from the app — decrypted IN RAM (no disk). PDFs print
  /// as-is; images/txt are wrapped in a one-off PDF. Opens the native print sheet.
  Future<void> _print(CloudFile f) async {
    setState(() => _busy = true);
    final bytes = await _svc.downloadToMemory(f);
    if (!mounted) return;
    setState(() => _busy = false);
    if (bytes == null) {
      _snack('Laden/Entschlüsseln fehlgeschlagen.', isError: true);
      return;
    }
    final ext = f.name.contains('.') ? f.name.toLowerCase().split('.').last : '';
    try {
      if (ext == 'pdf') {
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: f.name);
      } else if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'tiff'].contains(ext)) {
        final doc = pw.Document();
        final img = pw.MemoryImage(bytes);
        doc.addPage(pw.Page(build: (ctx) => pw.Center(child: pw.Image(img))));
        await Printing.layoutPdf(onLayout: (_) async => doc.save(), name: f.name);
      } else if (ext == 'txt') {
        final text = utf8.decode(bytes, allowMalformed: true);
        final doc = pw.Document();
        doc.addPage(pw.MultiPage(
            build: (ctx) => [pw.Text(text, style: const pw.TextStyle(fontSize: 11))]));
        await Printing.layoutPdf(onLayout: (_) async => doc.save(), name: f.name);
      } else {
        _snack('Drucken für „.$ext" nicht möglich.', isError: true);
      }
    } catch (e) {
      _snack('Drucken fehlgeschlagen: $e', isError: true);
    }
  }

  Future<void> _delete(CloudFile f) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Datei löschen?'),
        content: Text('„${f.name}" wird endgültig gelöscht.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _busy = true);
    final err = await _svc.delete(f.id);
    await _refresh();
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) _snack(err, isError: true);
  }

  /// Move a file out of this vault into a member's cloud — the ☁ behind the
  /// Live-Chat header. The member cloud needs no passphrase (it is encrypted
  /// with the server key), so the bytes must pass through this device: unlock →
  /// decrypt in RAM → post the plaintext. See [SecureCloudService.sendToMember].
  Future<void> _sendToMember(CloudFile f) async {
    if (!f.readable) {
      _snack('Nicht lesbare Datei kann nicht übertragen werden.', isError: true);
      return;
    }
    if (f.plainSize > _maxTransferBytes) {
      _snack('Zu groß für eine Übertragung (max. ${_fmtBytes(_maxTransferBytes)}).',
          isError: true);
      return;
    }

    setState(() => _busy = true);
    final res = await _api.getUsers();
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['success'] != true) {
      _snack('Mitgliederliste konnte nicht geladen werden.', isError: true);
      return;
    }
    // Everyone who is neither staff nor an anonymous chat account — a denylist,
    // so a newly added member role shows up here instead of silently missing.
    const notMembers = {'vorsitzer', 'schatzmeister', 'kassierer', 'anonymous'};
    final members = [
      for (final u in List<Map<String, dynamic>>.from(res['users'] ?? []))
        if (!notMembers.contains((u['role'] ?? '').toString().toLowerCase())) u
    ];
    if (members.isEmpty) {
      _snack('Keine Mitglieder gefunden.', isError: true);
      return;
    }

    final target = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _MemberPicker(members: members, fileName: f.name),
    );
    if (target == null || !mounted) return;
    final memberId = (target['id'] as num?)?.toInt();
    if (memberId == null) return;
    final label = _memberLabel(target);

    // Preflight the member's 1 GB quota — the vault holds 50 GB, so a file that
    // fits here can easily not fit there. Cheaper to refuse before uploading.
    setState(() => _busy = true);
    final quota = await _api.listMemberCloud(
        mitgliedernummer: widget.mitgliedernummer, memberId: memberId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (quota['success'] == true) {
      final used = (quota['quota_used'] as num?)?.toInt() ?? 0;
      final total = (quota['quota_total'] as num?)?.toInt() ?? 0;
      if (total > 0 && used + f.plainSize > total) {
        _snack(
            'Cloud von $label ist zu voll — ${_fmtBytes(total - used)} frei, '
            '${_fmtBytes(f.plainSize)} nötig.',
            isError: true);
        return;
      }
    }

    var deleteOriginal = true; // "verschieben" is the default intent
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: const Text('An Mitglied übertragen?'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('„${f.name}" (${_fmtBytes(f.plainSize)})'),
                const SizedBox(height: 4),
                Text('→ Cloud von $label',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                const Text(
                  'In der Mitglieder-Cloud liegt die Datei serverseitig '
                  'verschlüsselt — nicht mehr Ende-zu-Ende wie hier im Tresor. '
                  'Dafür ist sie dort im Live-Chat und in den Behörden-Bereichen '
                  'verwendbar.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                CheckboxListTile(
                  value: deleteOriginal,
                  onChanged: (v) => setInner(() => deleteOriginal = v ?? false),
                  title: const Text('Original hier löschen (verschieben)',
                      style: TextStyle(fontSize: 13)),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Abbrechen')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Übertragen')),
          ],
        ),
      ),
    );
    if (go != true || !mounted) return;

    setState(() => _busy = true);
    final r = await _svc.sendToMember(file: f, memberId: memberId);
    if (r.error != null) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(r.error!, isError: true);
      return;
    }
    // Only now is the copy safe on the server; deleting earlier could lose it.
    final delErr = deleteOriginal ? await _svc.delete(f.id) : null;
    await _refresh();
    if (!mounted) return;
    setState(() => _busy = false);
    if (delErr != null) {
      _snack('Übertragen — Original konnte nicht gelöscht werden: $delErr',
          isError: true);
    } else {
      _snack('„${f.name}" → $label  '
          '(${_fmtBytes(r.quotaUsed)} / ${_fmtBytes(r.quotaTotal)})');
    }
  }

  static String _memberLabel(Map<String, dynamic> m) {
    final name = (m['name'] ?? '').toString().trim();
    final nr = (m['mitgliedernummer'] ?? '').toString().trim();
    if (name.isNotEmpty && nr.isNotEmpty) return '$name ($nr)';
    if (name.isNotEmpty) return name;
    return nr.isNotEmpty ? nr : 'Mitglied';
  }

  Future<void> _changePassphrase() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Passwort ändern'),
        content: _PassphraseField(controller: ctrl, hint: 'Neues Passwort (min. 20 Zeichen)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ändern')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final err = await _svc.changePassphrase(ctrl.text);
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(err ?? 'Passwort geändert.', isError: err != null);
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sichere Cloud'),
        actions: [
          if (_stage == _Stage.ready) ...[
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Aktualisieren',
              onPressed: _busy ? null : _refresh,
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'pass') _changePassphrase();
                if (v == 'lock') {
                  _svc.lock();
                  setState(() => _stage = _Stage.needsUnlock);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'pass', child: Text('Passwort ändern')),
                PopupMenuItem(value: 'lock', child: Text('Sperren')),
              ],
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          _buildBody(),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x66000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
      floatingActionButton: _stage == _Stage.ready
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _showUploadSheet,
              icon: const Icon(Icons.upload),
              label: const Text('Hochladen'),
            )
          : null,
    );
  }

  Widget _buildBody() {
    switch (_stage) {
      case _Stage.loading:
        return const Center(child: CircularProgressIndicator());
      case _Stage.error:
        return _CenteredMessage(
          icon: Icons.cloud_off,
          title: _error ?? 'Fehler',
          action: FilledButton(onPressed: _bootstrap, child: const Text('Erneut versuchen')),
        );
      case _Stage.needsSetup:
        return _SetupView(busy: _busy, onSubmit: _doSetup);
      case _Stage.needsUnlock:
        return _UnlockView(busy: _busy, onSubmit: _doUnlock);
      case _Stage.ready:
        return _buildReady();
    }
  }

  Widget _buildReady() {
    final listing = _listing;
    if (listing == null) {
      return const Column(children: [
        _QuotaBar(used: 0, total: 0, count: 0),
        Expanded(child: Center(child: CircularProgressIndicator())),
      ]);
    }

    // Count files per type category (for the filter chips + counts).
    final counts = <String, int>{};
    for (final f in listing.files) {
      final c = _category(f.name);
      counts[c] = (counts[c] ?? 0) + 1;
    }
    final categories = counts.keys.toList()..sort();
    final filtered = _filter == 'Alle'
        ? listing.files
        : listing.files.where((f) => _category(f.name) == _filter).toList();

    return Column(
      children: [
        _QuotaBar(
          used: listing.quotaUsed,
          total: listing.quotaTotal,
          count: listing.files.length,
        ),
        if (listing.files.isNotEmpty)
          _TypeFilterBar(
            categories: categories,
            counts: counts,
            total: listing.files.length,
            selected: _filter,
            onSelect: (c) => setState(() => _filter = c),
          ),
        Expanded(
          child: listing.files.isEmpty
              ? const _CenteredMessage(
                  icon: Icons.lock,
                  title: 'Noch keine Dateien.\nAlles hier wird Ende-zu-Ende verschlüsselt.',
                )
              : filtered.isEmpty
                  ? const _CenteredMessage(
                      icon: Icons.filter_alt_off,
                      title: 'Keine Dateien dieses Typs.',
                    )
                  : _buildTable(filtered),
        ),
      ],
    );
  }

  /// Friendly type category for a filename, used by the filter chips.
  String _category(String name) {
    final ext = name.contains('.') ? name.toLowerCase().split('.').last : '';
    if (ext == 'pdf') return 'PDF';
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'tiff', 'heic'].contains(ext)) return 'Bilder';
    if (['txt', 'md', 'log'].contains(ext)) return 'Text';
    if (['doc', 'docx', 'odt', 'rtf'].contains(ext)) return 'Dokumente';
    if (['xls', 'xlsx', 'csv'].contains(ext)) return 'Tabellen';
    return 'Andere';
  }

  void _setSort(int col, bool asc) => setState(() {
        _sortCol = col;
        _sortAsc = asc;
      });

  int _cmp(CloudFile a, CloudFile b) {
    int r;
    switch (_sortCol) {
      case 0:
        r = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        break;
      case 1:
        r = a.plainSize.compareTo(b.plainSize);
        break;
      default:
        r = a.createdAt.compareTo(b.createdAt);
    }
    return _sortAsc ? r : -r;
  }

  Widget _buildTable(List<CloudFile> files) {
    final sorted = [...files]..sort(_cmp);
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              sortColumnIndex: _sortCol,
              sortAscending: _sortAsc,
              columnSpacing: 16,
              headingRowHeight: 42,
              dataRowMinHeight: 44,
              dataRowMaxHeight: 60,
              columns: [
                DataColumn(label: const Text('Name'), onSort: _setSort),
                DataColumn(label: const Text('Größe'), numeric: true, onSort: _setSort),
                DataColumn(label: const Text('Datum'), onSort: _setSort),
                const DataColumn(label: Text('')),
              ],
              rows: [for (final f in sorted) _dataRow(f)],
            ),
          ),
        ],
      ),
    );
  }

  DataRow _dataRow(CloudFile f) {
    IconButton compact(IconData icon, String tip, VoidCallback onTap) => IconButton(
          icon: Icon(icon, size: 20),
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: onTap,
        );
    return DataRow(
      cells: [
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_iconFor(f), size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Flexible(child: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
          onTap: f.readable ? () => _preview(f) : null,
        ),
        DataCell(Text(_fmtBytes(f.plainSize))),
        DataCell(Text(_fmtDate(f.createdAt))),
        DataCell(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (f.readable) ...[
              compact(Icons.visibility_outlined, 'Ansehen (im RAM)', () => _preview(f)),
              compact(Icons.print_outlined, 'Drucken', () => _print(f)),
              compact(Icons.drive_file_move_outlined, 'An Mitglied senden',
                  () => _sendToMember(f)),
            ],
            compact(Icons.download_outlined, 'Herunterladen', () => _download(f)),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'view') _preview(f);
                if (v == 'print') _print(f);
                if (v == 'send') _sendToMember(f);
                if (v == 'save') _download(f);
                if (v == 'del') _delete(f);
              },
              itemBuilder: (_) => [
                if (f.readable) const PopupMenuItem(value: 'view', child: Text('Ansehen (im RAM)')),
                if (f.readable) const PopupMenuItem(value: 'print', child: Text('Drucken')),
                if (f.readable)
                  const PopupMenuItem(value: 'send', child: Text('An Mitglied senden')),
                const PopupMenuItem(value: 'save', child: Text('Herunterladen / Speichern')),
                const PopupMenuItem(value: 'del', child: Text('Löschen')),
              ],
            ),
          ],
        )),
      ],
    );
  }

  void _showUploadSheet() {
    final canScan = Platform.isAndroid || Platform.isIOS;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('Datei vom Gerät'),
              subtitle: const Text('Android / Linux'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUpload();
              },
            ),
            if (canScan)
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Foto aufnehmen'),
                subtitle: const Text('Kamera in der App · direkt verschlüsselt'),
                onTap: () {
                  Navigator.pop(ctx);
                  _capturePhotoAndUpload();
                },
              ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red.shade700 : null,
    ));
  }

  IconData _iconFor(CloudFile f) {
    if (f.source == 'scan') return Icons.document_scanner;
    final n = f.name.toLowerCase();
    if (n.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (RegExp(r'\.(jpg|jpeg|png|gif|webp|heic)$').hasMatch(n)) return Icons.image;
    if (RegExp(r'\.(mp4|mov|avi|mkv)$').hasMatch(n)) return Icons.videocam;
    if (RegExp(r'\.(mp3|wav|m4a|aac)$').hasMatch(n)) return Icons.audiotrack;
    return Icons.insert_drive_file;
  }

  String? _guessMime(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.pdf')) return 'application/pdf';
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    if (n.endsWith('.txt')) return 'text/plain';
    return null;
  }

  static String _fmtBytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

// ── Member picker (transfer target) ────────────────────────────────────────

/// Choose whose member cloud a vault file is transferred into. Pops the picked
/// user map (from `admin/users.php`), or null when cancelled.
class _MemberPicker extends StatefulWidget {
  final List<Map<String, dynamic>> members;
  final String fileName;

  const _MemberPicker({required this.members, required this.fileName});

  @override
  State<_MemberPicker> createState() => _MemberPickerState();
}

class _MemberPickerState extends State<_MemberPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final list = q.isEmpty
        ? widget.members
        : widget.members.where((m) {
            final hay = '${m['name'] ?? ''} ${m['vorname'] ?? ''} '
                    '${m['nachname'] ?? ''} ${m['mitgliedernummer'] ?? ''}'
                .toLowerCase();
            return hay.contains(q);
          }).toList();

    return AlertDialog(
      title: const Text('In welche Mitglieder-Cloud?'),
      content: SizedBox(
        width: 420,
        height: 460,
        child: Column(
          children: [
            Text('„${widget.fileName}"',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 8),
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Name oder Mitgliedsnummer',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('Keine Treffer'))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final m = list[i];
                        final nr = (m['mitgliedernummer'] ?? '').toString();
                        return ListTile(
                          dense: true,
                          leading: const CircleAvatar(child: Icon(Icons.person, size: 20)),
                          title: Text((m['name'] ?? 'Unbekannt').toString(),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(nr),
                          onTap: () => Navigator.pop(context, m),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen')),
      ],
    );
  }
}

// ── Quota bar ──────────────────────────────────────────────────────────────

class _QuotaBar extends StatelessWidget {
  final int used;
  final int total;
  final int count;
  const _QuotaBar({required this.used, required this.total, required this.count});

  @override
  Widget build(BuildContext context) {
    final frac = total > 0 ? (used / total).clamp(0.0, 1.0) : 0.0;
    final near = frac > 0.9;
    final grey = TextStyle(fontSize: 12, color: Colors.grey.shade600);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${_SecureCloudScreenState._fmtBytes(used)} von '
                  '${_SecureCloudScreenState._fmtBytes(total)}'),
              const Icon(Icons.lock, size: 14),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 8,
              color: near ? Colors.red : null,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$count ${count == 1 ? 'Datei' : 'Dateien'} im Cloud', style: grey),
              Text('${(frac * 100).toStringAsFixed(frac >= 0.1 ? 0 : 1)} % belegt', style: grey),
            ],
          ),
        ],
      ),
    );
  }
}

/// Horizontal chips to filter the list by file-type category, each with a count.
class _TypeFilterBar extends StatelessWidget {
  final List<String> categories;
  final Map<String, int> counts;
  final int total;
  final String selected;
  final ValueChanged<String> onSelect;
  const _TypeFilterBar({
    required this.categories,
    required this.counts,
    required this.total,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _chip('Alle', total),
          for (final c in categories) _chip(c, counts[c] ?? 0),
        ],
      ),
    );
  }

  Widget _chip(String label, int n) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text('$label ($n)'),
        selected: selected == label,
        onSelected: (_) => onSelect(label),
      ),
    );
  }
}

// ── Setup / Unlock views ─────────────────────────────────────────────────────

class _SetupView extends StatefulWidget {
  final bool busy;
  final ValueChanged<String> onSubmit;
  const _SetupView({required this.busy, required this.onSubmit});

  @override
  State<_SetupView> createState() => _SetupViewState();
}

class _SetupViewState extends State<_SetupView> {
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  PassphraseCheck _check = CloudPassphrasePolicy.check('');

  @override
  void dispose() {
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final match = _pass.text == _confirm.text;
    final canSubmit = _check.ok && match && !widget.busy;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.enhanced_encryption, size: 48),
          const SizedBox(height: 12),
          Text('Cloud einrichten', style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text(
            'Wähle ein Wiederherstellungs-Passwort (min. 20 Zeichen). Damit werden '
            'alle Dateien verschlüsselt. Es wird bei jedem Öffnen abgefragt und auf '
            'neuen Geräten benötigt.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '⚠︎ Zero-Knowledge: Es gibt keine Hintertür. Wenn du das Passwort '
              'vergisst, sind die Dateien unwiederbringlich verloren. Tipp: 4–5 '
              'gut merkbare Wörter kombinieren.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 16),
          _PassphraseField(
            controller: _pass,
            hint: 'Wiederherstellungs-Passwort',
            onChanged: (v) => setState(() => _check = CloudPassphrasePolicy.check(v)),
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: _check.meter,
            minHeight: 6,
            color: _check.ok ? Colors.green : Colors.orange,
          ),
          if (_pass.text.isNotEmpty && _check.issues.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_check.issues.join(' · '),
                  style: TextStyle(color: Colors.orange.shade800, fontSize: 12)),
            ),
          const SizedBox(height: 12),
          _PassphraseField(
            controller: _confirm,
            hint: 'Passwort wiederholen',
            onChanged: (_) => setState(() {}),
          ),
          if (_confirm.text.isNotEmpty && !match)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Passwörter stimmen nicht überein', style: TextStyle(color: Colors.red, fontSize: 12)),
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: canSubmit ? () => widget.onSubmit(_pass.text) : null,
            icon: const Icon(Icons.lock),
            label: const Text('Cloud einrichten'),
          ),
        ],
      ),
    );
  }
}

class _UnlockView extends StatefulWidget {
  final bool busy;
  final ValueChanged<String> onSubmit;
  const _UnlockView({required this.busy, required this.onSubmit});

  @override
  State<_UnlockView> createState() => _UnlockViewState();
}

class _UnlockViewState extends State<_UnlockView> {
  final _pass = TextEditingController();

  @override
  void dispose() {
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          const Icon(Icons.lock, size: 48),
          const SizedBox(height: 12),
          Text('Cloud entsperren', style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text('Gib dein Wiederherstellungs-Passwort ein.', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          _PassphraseField(
            controller: _pass,
            hint: 'Passwort',
            onSubmitted: widget.busy ? null : widget.onSubmit,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: widget.busy ? null : () => widget.onSubmit(_pass.text),
            icon: const Icon(Icons.lock_open),
            label: const Text('Entsperren'),
          ),
        ],
      ),
    );
  }
}

/// Obscured passphrase field with a show/hide toggle.
class _PassphraseField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  const _PassphraseField({
    required this.controller,
    required this.hint,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  State<_PassphraseField> createState() => _PassphraseFieldState();
}

class _PassphraseFieldState extends State<_PassphraseField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _obscure,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        hintText: widget.hint,
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.password),
        suffixIcon: IconButton(
          icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}

// ── Small shared widgets ─────────────────────────────────────────────────────

class _CenteredMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? action;
  const _CenteredMessage({required this.icon, required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

// ── Upload progress ──────────────────────────────────────────────────────────

enum _UploadStatus { pending, uploading, done, error }

class _Upload {
  final File file;
  final String name;
  final String? mime;
  final String source; // 'device' | 'scan'
  _UploadStatus status = _UploadStatus.pending;
  String? error;
  _Upload({
    required this.file,
    required this.name,
    required this.mime,
    required this.source,
  });
}

/// Encrypts + uploads a batch sequentially, showing per-file status: a spinner
/// while uploading that turns into a green check on success (red on error), plus
/// an overall progress bar and X/N count. Can't be dismissed until it finishes.
class _UploadProgressDialog extends StatefulWidget {
  final SecureCloudService svc;
  final List<_Upload> items;
  const _UploadProgressDialog({required this.svc, required this.items});

  @override
  State<_UploadProgressDialog> createState() => _UploadProgressDialogState();
}

class _UploadProgressDialogState extends State<_UploadProgressDialog> {
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    for (final it in widget.items) {
      if (!mounted) return;
      setState(() => it.status = _UploadStatus.uploading);
      final err = await widget.svc.uploadFile(
        plain: it.file,
        displayName: it.name,
        mime: it.mime,
        source: it.source,
      );
      if (!mounted) return;
      setState(() {
        it.status = err == null ? _UploadStatus.done : _UploadStatus.error;
        it.error = err;
      });
    }
    if (mounted) setState(() => _finished = true);
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.items.length;
    final done = widget.items.where((i) => i.status == _UploadStatus.done).length;
    final failed = widget.items.where((i) => i.status == _UploadStatus.error).length;
    return PopScope(
      canPop: _finished, // block dismissal (incl. Android back) until done
      child: AlertDialog(
        title: Text(_finished ? 'Fertig ($done/$total)' : 'Hochladen … ($done/$total)'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : (done + failed) / total,
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: total,
                  itemBuilder: (_, i) {
                    final it = widget.items[i];
                    return ListTile(
                      dense: true,
                      leading: _statusIcon(it.status),
                      title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: it.status == _UploadStatus.error
                          ? Text(it.error ?? 'Fehler',
                              style: const TextStyle(color: Colors.red, fontSize: 11))
                          : null,
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
            child: Text(_finished && failed > 0 ? 'Schließen ($failed fehlgeschlagen)' : 'Fertig'),
          ),
        ],
      ),
    );
  }

  Widget _statusIcon(_UploadStatus s) {
    switch (s) {
      case _UploadStatus.pending:
        return const Icon(Icons.schedule, color: Colors.grey, size: 22);
      case _UploadStatus.uploading:
        return const SizedBox(
            width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4));
      case _UploadStatus.done:
        return const Icon(Icons.check_circle, color: Colors.green, size: 22);
      case _UploadStatus.error:
        return const Icon(Icons.error, color: Colors.red, size: 22);
    }
  }
}
// ── In-app live document scanner ─────────────────────────────────────────────

/// What [_CameraCaptureScreen] pops: the captured still, plus — when the live
/// overlay was locked onto the document as the shutter fired — its belief about
/// where the corners are, so the crop screen can skip the manual step.
class _ScanShot {
  final XFile file;
  final ScanHint? hint;
  const _ScanShot(this.file, this.hint);
}

/// Full-screen camera that renders the preview INSIDE our own Activity (the
/// `camera` plugin), so taking a photo never launches an external app. That is
/// the whole point: Android can't kill our process mid-capture, so the unlocked
/// DEK stays in RAM and the photo is never lost.
///
/// On top of that it runs live document detection on the preview frames: the
/// detected corners are drawn as you aim, and once they hold still the shutter
/// fires by itself after a visible 5 · 4 · 3 · 2 · 1 · 0 countdown. Detection is
/// pure OpenCV in a background isolate — no ML Kit, no Play Services, which
/// also keeps the F-Droid and Huawei builds honest.
///
/// Pops a [_ScanShot], or null if the user backs out. Handles init,
/// permission/hardware errors, and pausing/resuming with the app lifecycle.
class _CameraCaptureScreen extends StatefulWidget {
  const _CameraCaptureScreen();

  @override
  State<_CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<_CameraCaptureScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // ── tuning ─────────────────────────────────────────────────────────────────
  /// One countdown step. Five of them, so arming to shutter is exactly 5 s.
  static const Duration _kTick = Duration(seconds: 1);
  static const int _kSteps = 5;

  /// Quad turns teal and arming becomes possible at [_kLockOn]; it only counts
  /// as lost below [_kLockOff]. The gap is what stops single-frame chatter.
  static const double _kLockOn = 0.62;
  static const double _kLockOff = 0.50;
  static const int _kBadFrames = 2;

  /// Good, still frames required before the countdown arms (~350 ms).
  static const int _kSettleFrames = 5;

  /// Max deviation of any corner from the window mean, in isotropic upright
  /// units (1.0 == frame height). Measuring against the mean rather than the
  /// previous frame is what catches a slow steady slide.
  static const double _kSettleDrift = 0.010;

  /// Movement since arming that cancels the countdown outright.
  static const double _kBreakDrift = 0.035;

  static const int _kMissBreak = 3;
  static const Duration _kRearmDelay = Duration(milliseconds: 400);

  // ── camera ─────────────────────────────────────────────────────────────────
  CameraController? _controller;
  String? _error;
  bool _taking = false;
  bool _disposed = false;
  bool _streamStopped = false;
  int _generation = 0;

  // ── live detection ─────────────────────────────────────────────────────────
  LiveDocumentDetector? _detector;
  StreamSubscription<DetectionResult>? _sub;
  bool _liveEnabled = false;
  bool _auto = true;
  bool _loggedFrame = false;

  final ValueNotifier<ScanFrame> _frame = ValueNotifier(ScanFrame.empty);
  late final AnimationController _countdown = AnimationController(
    vsync: this,
    duration: _kTick * _kSteps,
  );

  ScanPhase _phase = ScanPhase.searching;
  bool _flash = false;

  // Tracking state. `raw` values feed the arming decision, `smoothed` values
  // feed the drawing — mixing them would arm the countdown off a filtered
  // signal that lags real motion by design.
  List<double>? _smoothed; // upright-normalized, TL TR BR BL
  List<double>? _prevRawIso;
  final List<List<double>> _window = [];
  final List<double> _windowConf = [];
  List<double>? _armIso;
  double _jitterEwma = 0;
  double _gEwma = 0;
  double _confidence = 0;
  double _ua = 1.0;
  int _missStreak = 0;
  int _badStreak = 0;
  int _lastShown = _kSteps;
  DateTime _lastCancel = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Pinning the display rotation keeps `deviceOrientation` at portraitUp, so
    // the buffer→preview rotation is a constant, and makes takePicture() write
    // a deterministic EXIF orientation. Cheaper and less invasive than
    // lockCaptureOrientation, which permanently flips plugin-global state.
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    _countdown
      ..addListener(_onCountdownTick)
      ..addStatusListener(_onCountdownStatus);
    _bootDetector();
    _setupCamera();
  }

  Future<void> _bootDetector() async {
    try {
      final d = await LiveDocumentDetector.start();
      if (!mounted || _disposed) {
        await d.dispose();
        return;
      }
      _detector = d;
      _sub = d.results.listen(_onResult);
    } catch (_) {
      // No live detection — the manual shutter still works.
      if (mounted) setState(() {});
    }
  }

  Future<void> _setupCamera() async {
    final gen = ++_generation;
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        if (mounted) setState(() => _error = 'Keine Kamera gefunden.');
        return;
      }
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      // Prefer a legible resolution for documents; fall back if unsupported.
      CameraController ctrl;
      try {
        ctrl = await _make(back, ResolutionPreset.veryHigh);
      } on CameraException {
        ctrl = await _make(back, ResolutionPreset.high);
      }
      if (!mounted || gen != _generation) {
        await ctrl.dispose();
        return;
      }
      setState(() {
        _controller = ctrl;
        _error = null;
        _liveEnabled = supportsLiveDetection(back);
      });
      if (_liveEnabled) unawaited(_startStream(gen));
    } on CameraException catch (e) {
      if (mounted) {
        setState(() => _error = 'Kamera nicht verfügbar: ${e.description ?? e.code}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Kamera-Fehler: $e');
    }
  }

  Future<CameraController> _make(CameraDescription cam, ResolutionPreset p) async {
    final ctrl = CameraController(
      cam,
      p,
      enableAudio: false,
      // yuv420, NOT jpeg. On Android `jpeg` is a silent no-op for image streams
      // (the CameraX delegate maps it to no analysis format at all), and on iOS
      // it falls back to bgra8888 where plane 0 is interleaved BGRA rather than
      // luma. yuv420 gives us planes[0] == Y on both platforms.
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await ctrl.initialize();
    return ctrl;
  }

  Future<void> _startStream(int gen) async {
    final ctrl = _controller;
    if (ctrl == null || gen != _generation || _disposed) return;
    try {
      _streamStopped = false;
      await ctrl.startImageStream(_onFrame);
    } catch (_) {
      _liveEnabled = false; // manual shutter only
      if (mounted) setState(() {});
    }
  }

  void _onFrame(CameraImage image) {
    if (_streamStopped || _disposed || _taking || !mounted) return;
    final d = _detector;
    if (d == null || d.dead) return;
    if (!_loggedFrame) {
      _loggedFrame = true;
      // One-shot bring-up diagnostic. If the preview's aspect ratio does not
      // match the frame's, preview and analysis resolved to different fields of
      // view and the overlay will be off by exactly that delta — this turns a
      // baffling misalignment into a ten-second diagnosis.
      debugPrint('[scan] frame=${image.width}x${image.height} '
          'fmt=${image.format.group} planes=${image.planes.length} '
          'stride=${image.planes.first.bytesPerRow} '
          'preview=${_controller?.value.previewSize} '
          'sensor=${_controller?.description.sensorOrientation} '
          'rotCW=${previewRotationCW(_controller!)}');
    }
    // Copies synchronously: on iOS the plane bytes may be recycled the instant
    // this callback returns.
    d.submit(image);
  }

  // ── detection results ──────────────────────────────────────────────────────

  static List<double> _iso(List<double> q, double ua) =>
      [for (var i = 0; i < 8; i += 2) ...[q[i] * ua, q[i + 1]]];

  void _onResult(DetectionResult r) {
    if (!mounted || _disposed || _taking) return;
    final ctrl = _controller;
    if (ctrl == null) return;

    if (r.quadN == null) {
      _missStreak++;
      if (_missStreak >= _kMissBreak) _cancelCountdown();
      if (_missStreak > 6) {
        _resetTracking();
        _frame.value = ScanFrame.empty;
        return;
      }
      // Hold the last quad and fade it: a single dropped detection should not
      // make the outline blink.
      _frame.value = ScanFrame(
        quadN: _smoothed,
        uprightAspect: _ua,
        confidence: _confidence,
        opacity: (1.0 - _missStreak / 4.0).clamp(0.0, 1.0),
      );
      return;
    }

    _missStreak = 0;
    final rotCW = previewRotationCW(ctrl);
    final ua = ScanGeometry.uprightAspect(r.frameWidth, r.frameHeight, rotCW);
    _ua = ua;

    final q = r.quadN!;
    final upright = <double>[];
    for (var i = 0; i < 8; i += 2) {
      // Live detection is gated to the back lens, so the buffer is never
      // mirrored — the front-camera mirror differs between Android's two
      // preview delegates and cannot be resolved from Dart.
      final (u, v) = ScanGeometry.toUpright(q[i], q[i + 1], rotCW, false);
      upright
        ..add(u)
        ..add(v);
    }
    // Rotation moves which physical corner is top-left, so re-order after it.
    final ordered = ScanGeometry.orderQuad(upright);
    final rawIso = _iso(ordered, ua);

    // Jitter → stability. Raw, never smoothed.
    final prev = _prevRawIso;
    if (prev != null) {
      final d = ScanGeometry.meanCornerDistance(rawIso, prev);
      _jitterEwma = 0.30 * d + 0.70 * _jitterEwma;
    }
    _prevRawIso = rawIso;
    _gEwma = _gEwma == 0 ? r.score : 0.25 * r.score + 0.75 * _gEwma;
    final stability = 1.0 - (_jitterEwma / 0.012).clamp(0.0, 1.0);
    _confidence = (0.65 * _gEwma + 0.35 * stability).clamp(0.0, 1.0);

    _updateSmoothed(ordered, rawIso, ua);

    _window.add(rawIso);
    _windowConf.add(_confidence);
    if (_window.length > _kSettleFrames) {
      _window.removeAt(0);
      _windowConf.removeAt(0);
    }

    _frame.value = ScanFrame(
      quadN: _smoothed,
      uprightAspect: ua,
      confidence: _confidence,
      opacity: 1.0,
    );

    _advance(rawIso);
  }

  void _updateSmoothed(List<double> ordered, List<double> rawIso, double ua) {
    final s = _smoothed;
    if (s == null ||
        ScanGeometry.maxCornerDistance(_iso(s, ua), rawIso) >
            ScanGeometry.snapDistance) {
      _smoothed = List<double>.of(ordered); // different document — snap
      return;
    }
    final next = List<double>.of(s);
    for (var i = 0; i < 8; i += 2) {
      final dx = (ordered[i] - s[i]) * ua;
      final dy = ordered[i + 1] - s[i + 1];
      final a = ScanGeometry.alphaFor(math.sqrt(dx * dx + dy * dy));
      next[i] = s[i] + (ordered[i] - s[i]) * a;
      next[i + 1] = s[i + 1] + (ordered[i + 1] - s[i + 1]) * a;
    }
    _smoothed = next;
  }

  /// Drive the state machine from the freshly accepted raw quad.
  void _advance(List<double> rawIso) {
    final dead = _detector?.dead ?? true;
    if (!_auto || dead || !_liveEnabled) {
      if (_phase != ScanPhase.searching) _setPhase(ScanPhase.searching);
      return;
    }

    if (_phase == ScanPhase.counting) {
      final arm = _armIso;
      if (_confidence < _kLockOff) {
        _badStreak++;
        if (_badStreak >= _kBadFrames) _cancelCountdown();
        return;
      }
      _badStreak = 0;
      // A deliberate reposition must cancel instantly rather than let a
      // countdown run out over a document that is no longer where it was.
      if (arm != null &&
          ScanGeometry.maxCornerDistance(rawIso, arm) > _kBreakDrift) {
        _cancelCountdown();
      }
      return;
    }

    if (_confidence < _kLockOff) {
      _badStreak++;
      if (_badStreak >= _kBadFrames && _phase != ScanPhase.searching) {
        _setPhase(ScanPhase.searching);
      }
      return;
    }
    _badStreak = 0;
    if (_confidence >= _kLockOn && _phase == ScanPhase.searching) {
      _setPhase(ScanPhase.holding);
    }

    if (_phase != ScanPhase.holding) return;
    if (_window.length < _kSettleFrames) return;
    if (_windowConf.any((c) => c < _kLockOn)) return;
    if (DateTime.now().difference(_lastCancel) < _kRearmDelay) return;
    if (_maxDriftFromMean() > _kSettleDrift) return;

    _armIso = rawIso;
    _lastShown = _kSteps;
    _setPhase(ScanPhase.counting);
    _countdown.forward(from: 0);
  }

  /// Largest deviation of any corner from its mean across the settle window.
  double _maxDriftFromMean() {
    if (_window.isEmpty) return double.infinity;
    final mean = List<double>.filled(8, 0);
    for (final q in _window) {
      for (var i = 0; i < 8; i++) {
        mean[i] += q[i];
      }
    }
    for (var i = 0; i < 8; i++) {
      mean[i] /= _window.length;
    }
    var worst = 0.0;
    for (final q in _window) {
      worst = math.max(worst, ScanGeometry.maxCornerDistance(q, mean));
    }
    return worst;
  }

  void _resetTracking() {
    _smoothed = null;
    _prevRawIso = null;
    _window.clear();
    _windowConf.clear();
    _armIso = null;
    _jitterEwma = 0;
    _gEwma = 0;
    _confidence = 0;
    _badStreak = 0;
  }

  void _setPhase(ScanPhase p) {
    if (_phase == p) return;
    setState(() => _phase = p);
  }

  void _cancelCountdown() {
    _armIso = null;
    _badStreak = 0;
    if (_countdown.isAnimating || _countdown.value != 0) {
      _countdown.stop();
      _countdown.value = 0;
    }
    _lastCancel = DateTime.now();
    _window.clear();
    _windowConf.clear();
    if (_phase == ScanPhase.counting) _setPhase(ScanPhase.searching);
  }

  void _onCountdownTick() {
    if (_phase != ScanPhase.counting) return;
    final shown = (_kSteps - (_countdown.value * _kSteps).floor()).clamp(0, _kSteps);
    if (shown != _lastShown) {
      _lastShown = shown;
      HapticFeedback.selectionClick();
    }
  }

  void _onCountdownStatus(AnimationStatus s) {
    if (s == AnimationStatus.completed && _phase == ScanPhase.counting) {
      HapticFeedback.mediumImpact();
      _fire(auto: true);
    }
  }

  // ── capture ────────────────────────────────────────────────────────────────

  ScanHint? _buildHint() {
    final q = _smoothed;
    if (q == null || q.length != 8) return null;
    return ScanHint(List<double>.of(q), _ua, _confidence);
  }

  Future<void> _fire({required bool auto}) async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _taking) return;
    _cancelCountdown();
    setState(() {
      _taking = true;
      _phase = ScanPhase.capturing;
      _flash = true;
    });
    // Freeze the overlay: the quad on screen IS the quad about to be captured.
    _detector?.pause();
    // A manual tap never carries a hint, so it always shows the editor — the
    // user asked to frame it themselves.
    final hint = auto ? _buildHint() : null;
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted && !_disposed) setState(() => _flash = false);
    });
    try {
      final XFile file = await ctrl.takePicture();
      if (!mounted) return;
      Navigator.of(context).pop(_ScanShot(file, hint));
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _taking = false;
        _phase = ScanPhase.searching;
        _flash = false;
      });
      _resetTracking();
      _detector?.resume();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Aufnahme fehlgeschlagen: ${e.description ?? e.code}'),
        backgroundColor: Colors.red.shade700,
      ));
    }
  }

  // ── lifecycle ──────────────────────────────────────────────────────────────

  /// `CameraController.dispose()` does NOT stop the image stream, and the
  /// CameraX analyze callback ends in two null-asserted lookups — a frame in
  /// flight during teardown throws an uncatchable null-check error.
  Future<void> _teardown(CameraController? c) async {
    if (c == null) return;
    _streamStopped = true;
    if (c.value.isStreamingImages) {
      try {
        await c.stopImageStream();
      } catch (_) {
        // already gone
      }
    }
    await c.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _controller;
    if (state == AppLifecycleState.inactive) {
      _generation++; // invalidate any _setupCamera still awaiting
      _cancelCountdown();
      _resetTracking();
      _frame.value = ScanFrame.empty;
      _detector?.pause(); // keep the isolate — no respawn cost on resume
      _controller = null;
      unawaited(_teardown(ctrl));
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && ctrl == null) {
      _detector?.resume();
      _setupCamera();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _countdown
      ..removeListener(_onCountdownTick)
      ..removeStatusListener(_onCountdownStatus)
      ..dispose();
    _sub?.cancel();
    _frame.dispose();
    unawaited(_teardown(_controller));
    _controller = null;
    unawaited(_detector?.dispose() ?? Future<void>.value());
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ready = _controller?.value.isInitialized ?? false;
    final dead = _detector?.dead ?? false;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Foto aufnehmen'),
        actions: [
          if (_liveEnabled && !dead)
            IconButton(
              tooltip: 'Automatisch auslösen',
              icon: Icon(_auto
                  ? Icons.motion_photos_auto
                  : Icons.motion_photos_off_outlined),
              onPressed: () {
                setState(() => _auto = !_auto);
                if (!_auto) _cancelCountdown();
              },
            ),
        ],
      ),
      body: _buildBody(ready),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: ready && _error == null
          ? FloatingActionButton.large(
              onPressed: _taking ? null : () => _fire(auto: false),
              child: _taking
                  ? const SizedBox(
                      width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3))
                  : const Icon(Icons.camera_alt, size: 34),
            )
          : null,
    );
  }

  Widget _buildBody(bool ready) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
        ),
      );
    }
    if (!ready) return const Center(child: CircularProgressIndicator());

    final hint = _liveEnabled
        ? scanHintText(
            phase: _phase,
            autoEnabled: _auto,
            detectorDead: _detector?.dead ?? false,
            frame: _frame.value,
          )
        : null;

    return Stack(
      children: [
        Center(
          child: CameraPreview(
            _controller!,
            // CameraPreview puts this child in a Stack(fit: expand) INSIDE the
            // AspectRatio and OUTSIDE the RotatedBox, so the overlay's
            // constraints are exactly the preview box: no AppBar, SafeArea or
            // letterbox offset ever needs subtracting, and it is not rotated.
            child: _liveEnabled
                ? IgnorePointer(
                    child: LayoutBuilder(
                      builder: (_, c) => ScanOverlay(
                        box: Size(c.maxWidth, c.maxHeight),
                        frame: _frame,
                        countdown: _countdown,
                        phase: _phase,
                        lockThreshold: _kLockOn,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
        if (hint != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 120,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0x99000000),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(hint,
                      style: const TextStyle(color: Colors.white70, fontSize: 14)),
                ),
              ),
            ),
          ),
        if (_flash)
          const Positioned.fill(
            child: IgnorePointer(child: ColoredBox(color: Colors.white70)),
          ),
      ],
    );
  }
}
