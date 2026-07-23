import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import '../services/api_service.dart';
import '../services/cloud_crypto_service.dart';
import '../services/secure_cloud_service.dart';
import '../utils/file_picker_helper.dart';
import '../widgets/file_viewer_dialog.dart';

// Scanner (OpenCV, offline, no Google). Android/iOS only — guarded at call site.
import 'package:edge_detection/edge_detection.dart';

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
  late final SecureCloudService _svc =
      SecureCloudService(ApiService(), widget.mitgliedernummer);

  _Stage _stage = _Stage.loading;
  String? _error;
  bool _busy = false;
  CloudListing? _listing;
  String _filter = 'Alle'; // active file-type filter
  int _sortCol = 2; // 0=Name, 1=Größe, 2=Datum
  bool _sortAsc = false; // default: newest first

  static const int _maxBatch = 50; // max files per upload batch

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _svc.lock(); // wipe the in-memory key when leaving the screen
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
    } else {
      setState(() => _stage = has ? _Stage.needsUnlock : _Stage.needsSetup);
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
    final result = await FilePickerHelper.pickFiles(
      allowMultiple: true,
      type: FileType.any,
      dialogTitle: 'Dateien in die Cloud hochladen (max. $_maxBatch)',
    );
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

  Future<void> _scanAndUpload() async {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      _snack('Scannen ist nur auf dem Tablet/Handy verfügbar.', isError: true);
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ok = await EdgeDetection.detectEdge(
        path,
        canUseGallery: false,
        androidScanTitle: 'Dokument scannen',
        androidCropTitle: 'Zuschneiden',
        androidCropBlackWhiteTitle: 'S/W',
        androidCropReset: 'Zurücksetzen',
      );
      if (ok != true) return; // cancelled
      final name = 'Scan_${DateTime.now().toIso8601String().substring(0, 19).replaceAll(':', '-')}.jpg';
      await _startUpload([
        _Upload(file: File(path), name: name, mime: 'image/jpeg', source: 'scan'),
      ]);
    } catch (e) {
      _snack('Scan fehlgeschlagen: $e', isError: true);
    }
  }

  Future<void> _startUpload(List<_Upload> items) async {
    if (items.isEmpty) return;
    // Modal progress dialog: encrypts + uploads each file, showing a per-file
    // spinner that turns into a green check on success (red on error).
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UploadProgressDialog(svc: _svc, items: items),
    );
    await _refresh(); // reflect the new files + updated quota
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
    final ext = f.name.contains('.') ? f.name.toLowerCase().split('.').last : '';
    final savedPath = await FilePickerHelper.saveFile(
      dialogTitle: 'Datei speichern',
      fileName: f.name,
      type: ext.isEmpty ? FileType.any : FileType.custom,
      allowedExtensions: ext.isEmpty ? null : [ext],
    );
    if (savedPath == null) return; // user cancelled
    try {
      await File(savedPath).writeAsBytes(bytes, flush: true);
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
            ],
            compact(Icons.download_outlined, 'Herunterladen', () => _download(f)),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'view') _preview(f);
                if (v == 'print') _print(f);
                if (v == 'save') _download(f);
                if (v == 'del') _delete(f);
              },
              itemBuilder: (_) => [
                if (f.readable) const PopupMenuItem(value: 'view', child: Text('Ansehen (im RAM)')),
                if (f.readable) const PopupMenuItem(value: 'print', child: Text('Drucken')),
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
                leading: const Icon(Icons.document_scanner),
                title: const Text('Dokument scannen'),
                subtitle: const Text('Kamera · automatische Randerkennung · offline'),
                onTap: () {
                  Navigator.pop(ctx);
                  _scanAndUpload();
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
  _UploadStatus status;
  String? error;
  _Upload({
    required this.file,
    required this.name,
    required this.mime,
    required this.source,
    this.status = _UploadStatus.pending,
    this.error,
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
