import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';
import 'file_viewer_dialog.dart';
import 'korrespondenz_message_dialog.dart';

/// GitHub ▸ Korrespondenz — the paper trail with GitHub, next to Konto Online.
///
/// Built on the same model as Finanzamt ▸ Korrespondenz: an entry has a
/// direction, a channel, a date and N documents; text is encrypted at rest and
/// the API speaks plaintext. Mail sent to github@icd360s.de is filed
/// automatically by a cron job (`quelle == 'mail'`), and entries can also be
/// written by hand — a support ticket, a phone call about billing.
///
/// The two GitHub-specific fields are [repo] and [grund] (GitHub's
/// X-GitHub-Reason). They exist because the volume here is nothing like the
/// Finanzamt's: dependabot alone produced 18 of the first 26 messages. Without
/// a filter the archive would be technically complete and practically unusable,
/// so both are plaintext columns the server can filter on.
class GithubKorrespondenzTab extends StatefulWidget {
  final ApiService apiService;

  const GithubKorrespondenzTab({super.key, required this.apiService});

  @override
  State<GithubKorrespondenzTab> createState() => _GithubKorrespondenzTabState();
}

// ─── Vocabulary ─────────────────────────────────────────────────────────────

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

/// X-GitHub-Reason values, as GitHub sends them. Anything not listed is shown
/// verbatim rather than hidden — GitHub adds new reasons without warning.
const Map<String, String> _grundLabel = {
  'ci_activity': 'CI / Actions',
  'subscribed': 'Abonniert',
  'security_alert': 'Sicherheit',
  'author': 'Autor',
  'comment': 'Kommentar',
  'mention': 'Erwähnung',
  'team_mention': 'Team-Erwähnung',
  'assign': 'Zugewiesen',
  'review_requested': 'Review angefragt',
  'state_change': 'Statuswechsel',
  'push': 'Push',
  'manual': 'Manuell',
  'your_activity': 'Eigene Aktivität',
};

const Map<String, IconData> _grundIcon = {
  'ci_activity': Icons.play_circle_outline,
  'subscribed': Icons.notifications_none,
  'security_alert': Icons.shield_outlined,
  'author': Icons.edit_outlined,
  'comment': Icons.chat_bubble_outline,
  'mention': Icons.alternate_email,
  'team_mention': Icons.groups_outlined,
  'assign': Icons.person_add_alt,
  'review_requested': Icons.rate_review_outlined,
  'state_change': Icons.swap_horiz,
  'push': Icons.upload_outlined,
};

const List<String> _korrExtensions = ['pdf', 'jpg', 'jpeg', 'png', 'tif', 'tiff'];

String _grundText(String grund) =>
    grund.isEmpty ? '' : (_grundLabel[grund] ?? grund.replaceAll('_', ' '));

/// Just the repository, without the org — the org is the same on every entry
/// and eats the width the name needs.
String _shortRepo(String repo) =>
    repo.contains('/') ? repo.split('/').last : repo;

class _GithubKorrespondenzTabState extends State<GithubKorrespondenzTab> {
  List<Map<String, dynamic>> _korrespondenz = [];
  List<Map<String, dynamic>> _repos = [];
  List<Map<String, dynamic>> _gruende = [];
  List<Map<String, dynamic>> _wege = [];
  bool _loading = true;

  String _filterRichtung = '';
  String _filterWeg = '';
  String _filterRepo = '';
  String _filterGrund = '';

  bool get _hasFilter =>
      _filterRichtung.isNotEmpty ||
      _filterWeg.isNotEmpty ||
      _filterRepo.isNotEmpty ||
      _filterGrund.isNotEmpty;

  /// Channels worth offering as a chip.
  ///
  /// Everything the importer files is 'email', so while that is the only value
  /// present a channel filter can only ever be a no-op or an empty list. The
  /// chips appear once something else has been recorded by hand.
  List<String> get _wegChipValues {
    final present = _wege
        .map((w) => w['weg']?.toString() ?? '')
        .where((w) => w.isNotEmpty)
        .toSet();
    if (present.length < 2) return const [];
    return _wegValues.where(present.contains).toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final result = await widget.apiService.getGithubKorrespondenz(
        richtung: _filterRichtung.isEmpty ? null : _filterRichtung,
        weg: _filterWeg.isEmpty ? null : _filterWeg,
        repo: _filterRepo.isEmpty ? null : _filterRepo,
        grund: _filterGrund.isEmpty ? null : _filterGrund,
      );
      if (mounted && result['success'] == true) {
        final data = result['data'] ?? result;
        _korrespondenz = List<Map<String, dynamic>>.from(data['korrespondenz'] ?? []);
        // The chip lists come from the whole table, not from the filtered page,
        // so choosing a filter can never make its own chip disappear.
        _repos = List<Map<String, dynamic>>.from(data['repos'] ?? []);
        _gruende = List<Map<String, dynamic>>.from(data['gruende'] ?? []);
        _wege = List<Map<String, dynamic>>.from(data['wege'] ?? []);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _setFilter({String? richtung, String? weg, String? repo, String? grund}) {
    setState(() {
      _filterRichtung = richtung ?? _filterRichtung;
      _filterWeg = weg ?? _filterWeg;
      _filterRepo = repo ?? _filterRepo;
      _filterGrund = grund ?? _filterGrund;
    });
    _load();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFilterBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _korrespondenz.isEmpty
                    ? _emptyState()
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: _korrespondenz.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _buildKorrCard(_korrespondenz[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _chip('Alle', !_hasFilter, () {
                        setState(() {
                          _filterRichtung = '';
                          _filterWeg = '';
                          _filterRepo = '';
                          _filterGrund = '';
                        });
                        _load();
                      }),
                      const SizedBox(width: 6),
                      _chip('↓ Eingang', _filterRichtung == 'eingang',
                          () => _setFilter(
                              richtung: _filterRichtung == 'eingang' ? '' : 'eingang')),
                      const SizedBox(width: 6),
                      _chip('↑ Ausgang', _filterRichtung == 'ausgang',
                          () => _setFilter(
                              richtung: _filterRichtung == 'ausgang' ? '' : 'ausgang')),
                      const SizedBox(width: 14),
                      for (final g in _gruende) ...[
                        _grundChip(g),
                        const SizedBox(width: 6),
                      ],
                      for (final w in _wegChipValues) ...[
                        _wegChip(w),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _buildRepoMenu(),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: 'Aktualisieren',
                onPressed: _load,
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Erfassen'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade800,
                  foregroundColor: Colors.white,
                ),
                onPressed: _erfassen,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Repositories go in a menu rather than in the chip row: "ICD360S-e-V/…"
  /// names are long enough that three of them push everything else off screen.
  Widget _buildRepoMenu() {
    final label = _filterRepo.isEmpty ? 'Alle Repos' : _shortRepo(_filterRepo);
    return PopupMenuButton<String>(
      tooltip: 'Nach Repository filtern',
      onSelected: (v) => _setFilter(repo: v),
      itemBuilder: (_) => [
        const PopupMenuItem(value: '', child: Text('Alle Repos')),
        for (final r in _repos)
          PopupMenuItem(
            value: r['repo']?.toString() ?? '',
            child: Text('${r['repo']}  (${r['count']})',
                style: const TextStyle(fontSize: 13)),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _filterRepo.isEmpty ? Colors.grey.shade100 : Colors.grey.shade800,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.folder_outlined,
              size: 14,
              color: _filterRepo.isEmpty ? Colors.grey.shade700 : Colors.white),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: _filterRepo.isEmpty ? Colors.grey.shade800 : Colors.white),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          Icon(Icons.arrow_drop_down,
              size: 18,
              color: _filterRepo.isEmpty ? Colors.grey.shade700 : Colors.white),
        ]),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _grundChip(Map<String, dynamic> g) {
    final grund = g['grund']?.toString() ?? '';
    final selected = _filterGrund == grund;
    return ChoiceChip(
      avatar: Icon(_grundIcon[grund] ?? Icons.label_outline, size: 14),
      label: Text('${_grundText(grund)} (${g['count']})',
          style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => _setFilter(grund: selected ? '' : grund),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _wegChip(String weg) {
    final selected = _filterWeg == weg;
    return ChoiceChip(
      avatar: Icon(_wegIcon[weg], size: 14),
      label: Text(_wegLabel[weg]!, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => _setFilter(weg: selected ? '' : weg),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.forum_outlined, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            _hasFilter
                ? 'Kein Eintrag für diesen Filter.'
                : 'Noch keine Korrespondenz erfasst.\n'
                    'E-Mails an github@icd360s.de werden automatisch übernommen.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildKorrCard(Map<String, dynamic> k) {
    final richtung = (k['richtung'] ?? 'eingang').toString();
    final weg = (k['weg'] ?? 'email').toString();
    final isEingang = richtung == 'eingang';
    final betreff = (k['betreff'] ?? '').toString();
    final absender = (k['absender'] ?? '').toString();
    final empfaenger = (k['empfaenger'] ?? '').toString();
    final notiz = (k['notiz'] ?? '').toString();
    final quelle = (k['quelle'] ?? 'manual').toString();
    final repo = (k['repo'] ?? '').toString();
    final grund = (k['grund'] ?? '').toString();
    final dateien = List<Map<String, dynamic>>.from(k['dateien'] ?? []);
    final accent = isEingang ? Colors.indigo : Colors.teal;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openEntry(k),
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
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(isEingang ? Icons.south_west : Icons.north_east,
                        size: 16, color: accent.shade600),
                    const SizedBox(width: 6),
                    Text(isEingang ? 'EINGANG' : 'AUSGANG',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: accent.shade700)),
                  ]),
                  if (repo.isNotEmpty)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.folder_outlined, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(_shortRepo(repo),
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade800)),
                    ]),
                  if (grund.isNotEmpty)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(_grundIcon[grund] ?? Icons.label_outline,
                          size: 13, color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Text(_grundText(grund),
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ]),
                  if (weg != 'email')
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(_wegIcon[weg], size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(_wegLabel[weg] ?? weg,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                    ]),
                  Text(_formatDateTime((k['datum'] ?? '').toString()),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  if (quelle == 'mail')
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.bolt, size: 10, color: Colors.blue.shade400),
                        const SizedBox(width: 2),
                        Text('automatisch',
                            style: TextStyle(fontSize: 10, color: Colors.blue.shade700)),
                      ]),
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
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (absender.isNotEmpty) absender,
                            if (empfaenger.isNotEmpty) '→ $empfaenger',
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
                    onPressed: () => _addFiles(k),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                    tooltip: 'Löschen',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _delete(k),
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
                Wrap(spacing: 8, runSpacing: 8, children: dateien.map(_fileChip).toList()),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _fileChip(Map<String, dynamic> f) {
    final name = (f['original_name'] ?? 'Datei').toString();
    final rolle = (f['rolle'] ?? 'attachment').toString();
    final size = f['file_size'];
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final (icon, color) =
        rolle == 'eml' ? (Icons.mail_outline, Colors.blueGrey) : _iconFor(ext);

    return InkWell(
      onTap: () => _viewFile(f),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
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

  // ── Actions ───────────────────────────────────────────────────────────────

  /// Tapping the entry opens its message, if it has one.
  void _openEntry(Map<String, dynamic> k) {
    final dateien = List<Map<String, dynamic>>.from(k['dateien'] ?? []);
    for (final f in dateien) {
      if ((f['rolle'] ?? '').toString() == 'eml') {
        _viewFile(f);
        return;
      }
    }
    if (dateien.length == 1) {
      _viewFile(dateien.first);
      return;
    }
    if (dateien.isEmpty) {
      _snack('Zu diesem Eintrag ist kein Dokument hinterlegt.');
    }
  }

  Future<void> _viewFile(Map<String, dynamic> file) async {
    final id = file['id'] is int ? file['id'] : int.parse(file['id'].toString());

    // An archived message goes to the mail reader. The file viewer knows PDFs
    // and images and renders nothing at all for message/rfc822.
    if ((file['rolle'] ?? '').toString() == 'eml') {
      await KorrespondenzMessageDialog.show(
        context,
        widget.apiService,
        id,
        loader: widget.apiService.getGithubKorrespondenzMessage,
      );
      return;
    }

    final response = await widget.apiService.downloadGithubKorrespondenzFile(id);
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

  Future<void> _delete(Map<String, dynamic> k) async {
    final betreff = (k['betreff'] ?? '').toString();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Korrespondenz löschen?'),
        content: Text('Der Eintrag${betreff.isEmpty ? '' : ' "$betreff"'} und alle '
            'zugehörigen Dokumente werden gelöscht.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final id = k['id'] is int ? k['id'] : int.parse(k['id'].toString());
    final result = await widget.apiService.deleteGithubKorrespondenz(id);
    if (!mounted) return;
    if (result['success'] == true) {
      _snack('Korrespondenz gelöscht');
      await _load();
    } else {
      _snack(result['message']?.toString() ?? 'Löschen fehlgeschlagen', isError: true);
    }
  }

  Future<void> _erfassen() async {
    final entry = await showDialog<_GhKorrDraft>(
      context: context,
      builder: (_) => _GithubKorrespondenzDialog(
        repos: _repos.map((r) => r['repo']?.toString() ?? '').where((r) => r.isNotEmpty).toList(),
        vorauswahlRepo: _filterRepo,
      ),
    );
    if (entry == null || !mounted) return;

    final created = await widget.apiService.createGithubKorrespondenz(
      richtung: entry.richtung,
      weg: entry.weg,
      datum: entry.datum,
      betreff: entry.betreff,
      absender: entry.absender,
      empfaenger: entry.empfaenger,
      notiz: entry.notiz,
      repo: entry.repo,
    );
    if (!mounted) return;
    if (created['success'] != true) {
      _snack(created['message']?.toString() ?? 'Anlegen fehlgeschlagen', isError: true);
      return;
    }
    final data = created['data'] ?? created;
    final korrId = data['id'] is int ? data['id'] : int.tryParse('${data['id']}') ?? 0;

    if (entry.files.isNotEmpty && korrId > 0) {
      await _uploadFiles(korrId, entry.files);
    }
    if (!mounted) return;
    _snack('Korrespondenz gespeichert');
    await _load();
  }

  Future<void> _addFiles(Map<String, dynamic> k) async {
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
    await _uploadFiles(id, valid);
    await _load();
  }

  /// Upload attachments one request at a time.
  ///
  /// Not a stylistic choice: nginx caps a single body at 200 MiB, PHP's
  /// max_file_uploads is 20, and ClamAV scans every write synchronously inside
  /// a 30 s budget. A batched POST fails at nginx with a bodyless 413 the app
  /// cannot even parse.
  Future<void> _uploadFiles(int korrId, List<PlatformFile> files) async {
    final items = files.where((f) => f.path != null).toList();
    if (items.isEmpty) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UploadProgressDialog(
        files: items,
        upload: (f) async {
          final r = await widget.apiService.attachGithubKorrespondenzFile(
            korrespondenzId: korrId,
            filePath: f.path!,
            fileName: f.name,
          );
          return r['success'] == true ? null : (r['message']?.toString() ?? 'Fehler');
        },
      ),
    );
  }

  // ── Small helpers ─────────────────────────────────────────────────────────

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
      duration: const Duration(seconds: 2),
    ));
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

  String _formatDateTime(String dateStr) {
    final dt = DateTime.tryParse(dateStr);
    if (dt == null) return dateStr;
    final d = '${dt.day.toString().padLeft(2, '0')}.'
        '${dt.month.toString().padLeft(2, '0')}.${dt.year}';
    if (dt.hour == 0 && dt.minute == 0) return d;
    return '$d ${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  static String _fmtBytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

// ─── Upload progress ────────────────────────────────────────────────────────

/// Runs the uploads one after another and shows how far along they are.
///
/// A ClamAV scan runs synchronously on every write, so even a small PDF takes
/// a noticeable moment; without this the app looks frozen and people pick the
/// files a second time.
class _UploadProgressDialog extends StatefulWidget {
  final List<PlatformFile> files;

  /// Returns null on success, or the error message to show for that file.
  final Future<String?> Function(PlatformFile) upload;

  const _UploadProgressDialog({required this.files, required this.upload});

  @override
  State<_UploadProgressDialog> createState() => _UploadProgressDialogState();
}

class _UploadProgressDialogState extends State<_UploadProgressDialog> {
  int _done = 0;
  final List<String> _failed = [];

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    for (final f in widget.files) {
      final err = await widget.upload(f);
      if (!mounted) return;
      setState(() {
        _done++;
        if (err != null) _failed.add('${f.name}: $err');
      });
    }
    if (mounted && _failed.isEmpty) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.files.length;
    final finished = _done >= total;

    return AlertDialog(
      title: Text(finished ? 'Upload abgeschlossen' : 'Dokumente werden hochgeladen',
          style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: total == 0 ? 0 : _done / total),
            const SizedBox(height: 10),
            Text('$_done von $total',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            if (_failed.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final e in _failed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(e,
                      style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
                ),
            ],
          ],
        ),
      ),
      actions: [
        if (finished)
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Schließen')),
      ],
    );
  }
}

// ─── Manual capture ─────────────────────────────────────────────────────────

class _GhKorrDraft {
  final String richtung;
  final String weg;
  final String datum;
  final String betreff;
  final String absender;
  final String empfaenger;
  final String notiz;
  final String repo;
  final List<PlatformFile> files;

  _GhKorrDraft({
    required this.richtung,
    required this.weg,
    required this.datum,
    required this.betreff,
    required this.absender,
    required this.empfaenger,
    required this.notiz,
    required this.repo,
    required this.files,
  });
}

/// Records an exchange the importer cannot see: a support ticket, a call about
/// billing, a letter. Defaults to 'online' rather than 'email', because anything
/// that arrived by mail is already in the list without anyone typing it.
class _GithubKorrespondenzDialog extends StatefulWidget {
  final List<String> repos;
  final String vorauswahlRepo;

  const _GithubKorrespondenzDialog({
    required this.repos,
    required this.vorauswahlRepo,
  });

  @override
  State<_GithubKorrespondenzDialog> createState() => _GithubKorrespondenzDialogState();
}

class _GithubKorrespondenzDialogState extends State<_GithubKorrespondenzDialog> {
  String _richtung = 'ausgang';
  String _weg = 'online';
  late String _repo = widget.vorauswahlRepo;
  DateTime _datum = DateTime.now();

  final _betreff = TextEditingController();
  final _absender = TextEditingController();
  final _empfaenger = TextEditingController();
  final _notiz = TextEditingController();

  final List<PlatformFile> _files = [];
  String? _error;

  bool get _isAnruf => _weg == 'anruf';

  @override
  void dispose() {
    _betreff.dispose();
    _absender.dispose();
    _empfaenger.dispose();
    _notiz.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _datum,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('de'),
    );
    if (picked != null) {
      setState(() => _datum = DateTime(
          picked.year, picked.month, picked.day, _datum.hour, _datum.minute));
    }
  }

  Future<void> _pickFiles() async {
    final picked = await FilePickerHelper.pickFiles(
      type: FileType.custom,
      allowedExtensions: _korrExtensions,
      allowMultiple: true,
      dialogTitle: 'Dokumente auswählen',
    );
    if (picked == null) return;
    final valid = picked.files.where((f) {
      final ext = f.name.contains('.') ? f.name.split('.').last.toLowerCase() : '';
      return f.path != null && _korrExtensions.contains(ext);
    }).toList();
    if (mounted) setState(() => _files.addAll(valid));
  }

  void _submit() {
    // Mirrors the server rule rather than waiting for its 400: a call leaves no
    // document, so the note is the only record of it there will ever be.
    if (_isAnruf && _notiz.text.trim().isEmpty) {
      setState(() => _error = 'Bei einem Anruf ist eine Notiz erforderlich.');
      return;
    }
    final d = _datum;
    Navigator.pop(
      context,
      _GhKorrDraft(
        richtung: _richtung,
        weg: _weg,
        datum: '${d.year}-${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')} '
            '${d.hour.toString().padLeft(2, '0')}:'
            '${d.minute.toString().padLeft(2, '0')}:00',
        betreff: _betreff.text.trim(),
        absender: _absender.text.trim(),
        empfaenger: _empfaenger.text.trim(),
        notiz: _notiz.text.trim(),
        repo: _repo,
        files: _files,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        Icon(Icons.forum_outlined, color: Colors.grey.shade800),
        const SizedBox(width: 10),
        const Text('Korrespondenz erfassen', style: TextStyle(fontSize: 17)),
      ]),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: SegmentedButton<String>(
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment(value: 'eingang', label: Text('Eingang'), icon: Icon(Icons.south_west, size: 16)),
                      ButtonSegment(value: 'ausgang', label: Text('Ausgang'), icon: Icon(Icons.north_east, size: 16)),
                    ],
                    selected: {_richtung},
                    onSelectionChanged: (s) => setState(() => _richtung = s.first),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _weg,
                    isDense: true,
                    decoration: const InputDecoration(labelText: 'Weg', border: OutlineInputBorder()),
                    items: [
                      for (final w in _wegValues)
                        DropdownMenuItem(
                          value: w,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(_wegIcon[w], size: 15),
                            const SizedBox(width: 6),
                            Text(_wegLabel[w]!, style: const TextStyle(fontSize: 13)),
                          ]),
                        ),
                    ],
                    onChanged: (v) => setState(() => _weg = v ?? 'online'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: _pickDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                          labelText: 'Datum', border: OutlineInputBorder(), isDense: true),
                      child: Text(
                        '${_datum.day.toString().padLeft(2, '0')}.'
                        '${_datum.month.toString().padLeft(2, '0')}.${_datum.year}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              // Free text as well as a pick: a new repository has no entry yet,
              // so it cannot appear in a list built from what is already filed.
              DropdownButtonFormField<String>(
                initialValue: widget.repos.contains(_repo) ? _repo : '',
                isDense: true,
                decoration: const InputDecoration(
                    labelText: 'Repository (optional)', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(value: '', child: Text('—', style: TextStyle(fontSize: 13))),
                  for (final r in widget.repos)
                    DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 13))),
                ],
                onChanged: (v) => setState(() => _repo = v ?? ''),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _betreff,
                decoration: const InputDecoration(
                    labelText: 'Betreff', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _absender,
                    decoration: const InputDecoration(
                        labelText: 'Von', border: OutlineInputBorder(), isDense: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _empfaenger,
                    decoration: const InputDecoration(
                        labelText: 'An', border: OutlineInputBorder(), isDense: true),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: _notiz,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: _isAnruf ? 'Notiz (erforderlich)' : 'Notiz',
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                OutlinedButton.icon(
                  onPressed: _pickFiles,
                  icon: const Icon(Icons.attach_file, size: 16),
                  label: const Text('Dokumente', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 10),
                if (_files.isNotEmpty)
                  Expanded(
                    child: Text('${_files.length} Datei(en) ausgewählt',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ),
              ]),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey.shade800, foregroundColor: Colors.white),
          onPressed: _submit,
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}
