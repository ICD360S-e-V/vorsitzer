import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../models/mail_models.dart';
import '../services/api_service.dart';
import '../utils/mail_html_text.dart';
import '../widgets/mail_delivery_indicator.dart';
import '../widgets/mail_folder_rail.dart';
import '../widgets/mail_quota_bar.dart';
import 'mail_compose_screen.dart';
import 'mail_signature_screen.dart';

/// Öffnet die Verfassen-Ansicht — vorbelegt für Antwort/Weiterleitung.
typedef MailComposeCallback = Future<void> Function({
  String? to,
  String? cc,
  String? subject,
  String? quotedBody,
  String? inReplyTo,
  List<MailOutgoingAttachment>? attachments,
});

/// In-App E-Mail Postfach (icd@icd360s.de) für den Vorsitzer.
/// Liest/sendet über icd360sev -> mail.icd360s.de (mTLS, mail_crypt).
class MailScreen extends StatefulWidget {
  final String mitgliedernummer;
  final String userName;
  final String email;

  const MailScreen({
    super.key,
    required this.mitgliedernummer,
    required this.userName,
    required this.email,
  });

  @override
  State<MailScreen> createState() => _MailScreenState();
}

class _MailScreenState extends State<MailScreen> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  static const int _pageSize = 50;

  String _box = 'INBOX';
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  /// Der Server hat den Token abgelehnt — dann hilft nur neu anmelden.
  bool _sessionExpired = false;
  List<Map<String, dynamic>> _messages = [];
  int _total = 0;
  Map<String, MailFolder> _folders = {};
  double _quotaUsedKb = 0;
  double _quotaLimitKb = 0;
  String _search = '';

  /// Nur im Zwei-Spalten-Layout: die im Lesebereich geöffnete Nachricht.
  int? _openUid;

  Timer? _searchDebounce;
  Timer? _deliveryPoll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _deliveryPoll?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ---------------- loading ----------------

  Future<void> _load({bool keepOpen = false}) async {
    setState(() {
      _loading = true;
      _error = null;
      if (!keepOpen) _openUid = null;
    });
    try {
      final res = await _api.getMailInbox(limit: _pageSize, box: _box, search: _search);
      if (res['success'] == true) {
        _messages = List<Map<String, dynamic>>.from(res['messages'] ?? []);
        _total = (res['total'] as num?)?.toInt() ?? _messages.length;
      } else {
        final msg = res['message']?.toString() ?? '';
        _error = _isAuthError(msg)
            ? 'Die Sitzung ist abgelaufen. Bitte ab- und wieder anmelden — '
                'danach ist das Postfach sofort wieder da.'
            : (msg.isNotEmpty ? msg : 'Der Ordner konnte nicht geladen werden.');
        _sessionExpired = _isAuthError(msg);
      }
    } catch (e) {
      _error = 'Keine Verbindung zum Server.';
    }
    _loadFolders();
    _loadQuota();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _messages.length >= _total) return;
    setState(() => _loadingMore = true);
    try {
      final res = await _api.getMailInbox(
        limit: _pageSize,
        offset: _messages.length,
        box: _box,
        search: _search,
      );
      if (res['success'] == true) {
        final more = List<Map<String, dynamic>>.from(res['messages'] ?? []);
        _messages.addAll(more);
        _total = (res['total'] as num?)?.toInt() ?? _total;
      }
    } catch (_) {/* keep what we already have */}
    if (mounted) setState(() => _loadingMore = false);
  }

  Future<void> _loadFolders() async {
    try {
      final res = await _api.getMailFolders();
      if (res['success'] != true || !mounted) return;
      final map = <String, MailFolder>{};
      for (final f in (res['folders'] as List? ?? [])) {
        if (f is Map) {
          final folder = MailFolder.fromJson(Map<String, dynamic>.from(f));
          map[folder.box] = folder;
        }
      }
      setState(() => _folders = map);
    } catch (_) {/* the rail falls back to Eingang/Ausgang only */}
  }

  Future<void> _loadQuota() async {
    try {
      final res = await _api.getMailQuota();
      final quota = (res['quota'] as List?) ?? [];
      for (final q in quota) {
        if (q is Map && q['type'] == 'STORAGE') {
          // doveadm reports both in kilobytes; an unlimited box sends '-'.
          final usedKb = double.tryParse('${q['value']}') ?? 0;
          final limitKb = double.tryParse('${q['limit']}') ?? 0;
          if (mounted) {
            setState(() {
              _quotaUsedKb = usedKb;
              _quotaLimitKb = limitKb;
            });
          }
        }
      }
    } catch (_) {/* quota is non-critical */}
  }

  void _selectBox(String box) {
    if (box == _box) return;
    setState(() {
      _box = box;
      _messages = [];
      _total = 0;
      _search = '';
      _searchCtrl.clear();
    });
    _load();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      setState(() => _search = value.trim());
      _load();
    });
  }

  /// Nach dem Senden braucht Postfix ein paar Sekunden, bis der Zielserver
  /// geantwortet hat — deshalb den Zustellstatus kurz nachfassen.
  void _pollDeliveryAfterSend() {
    _deliveryPoll?.cancel();
    var rounds = 0;
    _deliveryPoll = Timer.periodic(const Duration(seconds: 6), (t) async {
      rounds++;
      if (!mounted || rounds > 4) {
        t.cancel();
        return;
      }
      if (_box != 'Sent') return;
      final ids = _messages
          .map((m) => '${m['message_id'] ?? ''}')
          .where((s) => s.isNotEmpty)
          .toList();
      if (ids.isEmpty) return;
      try {
        final res = await _api.getMailDelivery(ids);
        if (res['success'] != true || !mounted) return;
        final delivery = Map<String, dynamic>.from(res['delivery'] ?? {});
        setState(() {
          for (final m in _messages) {
            final d = delivery['${m['message_id'] ?? ''}'];
            if (d is Map) m['delivery'] = Map<String, dynamic>.from(d);
          }
        });
      } catch (_) {/* try again next round */}
    });
  }

  // ---------------- actions ----------------

  /// Öffnet einen Entwurf zum Weiterschreiben statt in der Leseansicht.
  Future<void> _openDraft(Map<String, dynamic> msg) async {
    final uid = (msg['uid'] as num?)?.toInt() ?? 0;
    if (uid <= 0) return;
    setState(() => _loading = true);
    MailDraft? draft;
    try {
      final res = await _api.getMailMessage(uid, box: 'Drafts');
      if (res['success'] == true) {
        draft = MailDraft.fromMessageData(
            Map<String, dynamic>.from(res['message_data'] ?? {}));
      }
    } catch (_) {/* fall through to the error below */}
    if (!mounted) return;
    setState(() => _loading = false);
    if (draft == null || draft.draftId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Dieser Entwurf konnte nicht geöffnet werden.'),
      ));
      return;
    }
    final sent = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => MailComposeScreen(selfEmail: widget.email, draft: draft),
    ));
    if (!mounted) return;
    if (sent == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('E-Mail gesendet — der Zustellstatus steht im Ausgang.'),
      ));
      _pollDeliveryAfterSend();
    }
    _load();
  }

  Future<void> _openMessage(Map<String, dynamic> msg, {required bool wide}) async {
    final uid = (msg['uid'] as num?)?.toInt() ?? 0;
    if (uid <= 0) return;
    // A draft is for writing, not reading.
    if (_box == 'Drafts') {
      await _openDraft(msg);
      return;
    }
    if (wide) {
      setState(() => _openUid = uid);
      // Opening marks it read, so the rail counter has to catch up.
      if (msg['seen'] != true) {
        setState(() => msg['seen'] = true);
        _loadFolders();
      }
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _MailMessageRoute(
        uid: uid,
        box: _box,
        selfEmail: widget.email,
        onChanged: () => _load(),
        onCompose: _compose,
      ),
    ));
    _load();
  }

  Future<void> _compose({
    String? to,
    String? cc,
    String? subject,
    String? quotedBody,
    String? inReplyTo,
    List<MailOutgoingAttachment>? attachments,
  }) async {
    final sent = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => MailComposeScreen(
        selfEmail: widget.email,
        to: to,
        cc: cc,
        subject: subject,
        quotedBody: quotedBody,
        inReplyTo: inReplyTo,
        initialAttachments: attachments ?? const [],
      ),
    ));
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('E-Mail gesendet — der Zustellstatus steht im Ausgang.'),
      ));
      _load();
      _pollDeliveryAfterSend();
    }
  }

  Future<void> _openSignature() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MailSignatureScreen(mailboxAddress: widget.email),
    ));
  }

  Future<void> _toggleFlagged(Map<String, dynamic> msg) async {
    final uid = (msg['uid'] as num?)?.toInt() ?? 0;
    final next = msg['flagged'] != true;
    setState(() => msg['flagged'] = next);
    final res = await _api.flagMail(uid, flagged: next, box: _box);
    if (res['success'] != true && mounted) {
      setState(() => msg['flagged'] = !next);
    }
  }

  Future<void> _toggleSeen(Map<String, dynamic> msg) async {
    final uid = (msg['uid'] as num?)?.toInt() ?? 0;
    final next = msg['seen'] != true;
    setState(() => msg['seen'] = next);
    final res = await _api.flagMail(uid, seen: next, box: _box);
    if (res['success'] != true && mounted) {
      setState(() => msg['seen'] = !next);
    } else {
      _loadFolders();
    }
  }

  Future<void> _deleteMessage(Map<String, dynamic> msg) async {
    final uid = (msg['uid'] as num?)?.toInt() ?? 0;
    final permanent = _box == 'Trash';
    if (permanent) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Endgültig löschen?'),
          content: const Text(
              'Die Nachricht wird aus dem Papierkorb entfernt und ist danach weg.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Abbrechen')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Endgültig löschen')),
          ],
        ),
      );
      if (ok != true) return;
    }
    final res = await _api.deleteMail(uid, box: _box);
    if (!mounted) return;
    if (res['success'] == true) {
      setState(() {
        _messages.remove(msg);
        _total = _total > 0 ? _total - 1 : 0;
        if (_openUid == uid) _openUid = null;
      });
      _loadFolders();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(permanent ? 'Nachricht gelöscht' : 'In den Papierkorb verschoben'),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res['message']?.toString() ?? 'Löschen fehlgeschlagen.')));
    }
  }

  Future<void> _moveMessage(Map<String, dynamic> msg, String target) async {
    final uid = (msg['uid'] as num?)?.toInt() ?? 0;
    final res = await _api.moveMail(uid: uid, target: target, box: _box);
    if (!mounted) return;
    if (res['success'] == true) {
      setState(() {
        _messages.remove(msg);
        _total = _total > 0 ? _total - 1 : 0;
        if (_openUid == uid) _openUid = null;
      });
      _loadFolders();
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Verschoben nach ${MailBoxInfo.labelFor(target)}')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res['message']?.toString() ?? 'Verschieben fehlgeschlagen.')));
    }
  }

  // ---------------- layout ----------------

  int get _unread => _folders['INBOX']?.unseen ?? 0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final showRail = w >= 760;
      final showPane = w >= 1120;
      // The reading pane only makes sense while the rail is there too.
      final listWidth = showPane ? 400.0 : null;

      return Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(showRail ? MailBoxInfo.labelFor(_box) : 'E-Mail'),
              // Quota lives in the bar at the bottom, so the subtitle stays clean.
              Text(
                widget.email,
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Aktualisieren',
              onPressed: _loading ? null : () => _load(keepOpen: true),
            ),
            if (!showRail)
              IconButton(
                icon: const Icon(Icons.draw_outlined),
                tooltip: 'Signatur',
                onPressed: _openSignature,
              ),
          ],
        ),
        drawer: showRail
            ? null
            : Drawer(
                child: MailFolderRail(
                  isDrawer: true,
                  selectedBox: _box,
                  folders: _folders,
                  mailboxAddress: widget.email,
                  onSelect: _selectBox,
                  onCompose: () => _compose(),
                  onOpenSignature: _openSignature,
                ),
              ),
        floatingActionButton: showRail
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _compose(),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Neue E-Mail'),
              ),
        // Speicherplatz immer sichtbar am unteren Rand.
        bottomNavigationBar:
            MailQuotaBar(usedKb: _quotaUsedKb, limitKb: _quotaLimitKb),
        body: Row(
          children: [
            if (showRail)
              MailFolderRail(
                selectedBox: _box,
                folders: _folders,
                mailboxAddress: widget.email,
                onSelect: _selectBox,
                onCompose: () => _compose(),
                onOpenSignature: _openSignature,
              ),
            if (showRail) const VerticalDivider(width: 1),
            // With a reading pane the list keeps a fixed width; without one it
            // takes the rest of the row.
            if (showPane)
              SizedBox(width: listWidth, child: _listColumn(showPane: true))
            else
              Expanded(child: _listColumn(showPane: false)),
            if (showPane) ...[
              const VerticalDivider(width: 1),
              Expanded(
                child: _openUid == null
                    ? _emptyPane()
                    : MailMessageView(
                        key: ValueKey('$_box/$_openUid'),
                        uid: _openUid!,
                        box: _box,
                        selfEmail: widget.email,
                        onChanged: () => _load(keepOpen: true),
                        onCompose: _compose,
                        onDeleted: () {
                          final msg = _messages.firstWhere(
                            (m) => (m['uid'] as num?)?.toInt() == _openUid,
                            orElse: () => <String, dynamic>{},
                          );
                          setState(() {
                            if (msg.isNotEmpty) _messages.remove(msg);
                            _openUid = null;
                          });
                          _loadFolders();
                        },
                      ),
              ),
            ],
          ],
        ),
      );
    });
  }

  Widget _listColumn({required bool showPane}) {
    return Column(
      children: [
        _searchBar(),
        if (_box == 'INBOX' && _unread > 0)
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
            child: Text('$_unread ungelesen',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        Expanded(child: _buildList(showPane: showPane)),
      ],
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: TextField(
        controller: _searchCtrl,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'In ${MailBoxInfo.labelFor(_box)} suchen',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _search.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Suche zurücksetzen',
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _search = '');
                    _load();
                  },
                ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }

  Widget _emptyPane() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mark_email_read_outlined, size: 56, color: cs.outline),
          const SizedBox(height: 12),
          Text('Wählen Sie eine Nachricht aus.',
              style: TextStyle(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildList({required bool showPane}) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_sessionExpired ? Icons.lock_clock : Icons.error_outline,
                  size: 48,
                  color: _sessionExpired
                      ? Theme.of(context).colorScheme.primary
                      : Colors.redAccent),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              // Retrying cannot fix a rejected token, so do not offer it.
              if (_sessionExpired)
                Text(
                  'Abmelden und neu anmelden',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary),
                )
              else
                OutlinedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Erneut versuchen'),
                ),
            ],
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            const SizedBox(height: 100),
            Icon(MailBoxInfo.forBox(_box).icon,
                size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Center(
              child: Text(
                _search.isNotEmpty
                    ? 'Keine Treffer für „$_search“.'
                    : _emptyTextFor(_box),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(keepOpen: true),
      child: ListView.separated(
        itemCount: _messages.length + (_messages.length < _total ? 1 : 0),
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          if (i >= _messages.length) {
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: _loadingMore
                    ? const SizedBox(
                        width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : OutlinedButton(
                        onPressed: _loadMore,
                        child: Text('Weitere laden (${_total - _messages.length})'),
                      ),
              ),
            );
          }
          return _messageTile(_messages[i], showPane: showPane);
        },
      ),
    );
  }

  String _emptyTextFor(String box) {
    switch (box) {
      case 'Sent':
        return 'Noch nichts gesendet.';
      case 'Trash':
        return 'Der Papierkorb ist leer.';
      case 'Junk':
        return 'Kein Spam.';
      case 'Drafts':
        return 'Keine Entwürfe.';
      default:
        return 'Keine Nachrichten.';
    }
  }

  Widget _messageTile(Map<String, dynamic> m, {required bool showPane}) {
    final cs = Theme.of(context).colorScheme;
    final seen = m['seen'] == true;
    final uid = (m['uid'] as num?)?.toInt() ?? 0;
    final selected = showPane && uid == _openUid;
    // In Ausgang/Entwürfe the recipient is the useful name, not the sender.
    final outgoing = _box == 'Sent' || _box == 'Drafts';
    final who = _displayName('${(outgoing ? m['to'] : m['from']) ?? ''}');
    final subject = '${m['subject'] ?? '(kein Betreff)'}';
    final delivery = m['delivery'] is Map
        ? MailDelivery.fromJson(Map<String, dynamic>.from(m['delivery']))
        : null;

    return Material(
      color: selected ? cs.secondaryContainer.withValues(alpha: 0.55) : Colors.transparent,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: seen ? cs.surfaceContainerHighest : cs.primary,
          child: Text(
            who.isNotEmpty ? who[0].toUpperCase() : '?',
            style: TextStyle(
              color: seen ? cs.onSurfaceVariant : cs.onPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        title: Row(
          children: [
            if (outgoing)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text('An:',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ),
            Expanded(
              child: Text(
                who,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: seen ? FontWeight.normal : FontWeight.bold),
              ),
            ),
            Text(
              _shortDate('${m['date'] ?? ''}'),
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Row(
              children: [
                if (m['answered'] == true)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(Icons.reply, size: 14, color: cs.onSurfaceVariant),
                  ),
                Expanded(
                  child: Text(
                    subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: seen ? FontWeight.normal : FontWeight.w600),
                  ),
                ),
                if (m['has_attachment'] == true)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(Icons.attach_file, size: 15, color: cs.onSurfaceVariant),
                  ),
              ],
            ),
            if (delivery != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  MailDeliveryIndicator(delivery: delivery),
                  if (delivery.receiptRequested) ...[
                    const SizedBox(width: 8),
                    MailReceiptIndicator(delivery: delivery),
                  ],
                ],
              ),
            ],
          ],
        ),
        trailing: PopupMenuButton<String>(
          tooltip: 'Aktionen',
          icon: Icon(
            m['flagged'] == true ? Icons.star : Icons.more_vert,
            size: 20,
            color: m['flagged'] == true ? const Color(0xFFE0A800) : null,
          ),
          onSelected: (v) {
            switch (v) {
              case 'flag':
                _toggleFlagged(m);
                break;
              case 'seen':
                _toggleSeen(m);
                break;
              case 'spam':
                _moveMessage(m, 'Junk');
                break;
              case 'inbox':
                _moveMessage(m, 'INBOX');
                break;
              case 'delete':
                _deleteMessage(m);
                break;
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'flag',
              child: Text(m['flagged'] == true ? 'Markierung entfernen' : 'Markieren'),
            ),
            PopupMenuItem(
              value: 'seen',
              child: Text(seen ? 'Als ungelesen markieren' : 'Als gelesen markieren'),
            ),
            if (_box == 'INBOX')
              const PopupMenuItem(value: 'spam', child: Text('Als Spam markieren')),
            if (_box == 'Junk' || _box == 'Trash')
              const PopupMenuItem(value: 'inbox', child: Text('In den Eingang')),
            PopupMenuItem(
              value: 'delete',
              child: Text(_box == 'Trash' ? 'Endgültig löschen' : 'Löschen'),
            ),
          ],
        ),
        onTap: () => _openMessage(m, wide: showPane),
      ),
    );
  }
}

// ---------------- helpers ----------------

/// Erkennt die 401-Meldungen von `requireAuth()` serverseitig.
///
/// Wird gebraucht, weil ein abgelaufener Token sonst als „Ordner konnte nicht
/// geladen werden“ erscheint und man an der falschen Stelle sucht.
bool _isAuthError(String message) {
  final m = message.toLowerCase();
  return m.contains('invalid or expired token') ||
      m.contains('missing or invalid authorization') ||
      m.contains('konto deaktiviert');
}

String _extractEmail(String raw) {
  final m = RegExp(r'<([^>]+)>').firstMatch(raw);
  if (m != null) return m.group(1)!.trim();
  return raw.trim();
}

String _displayName(String raw) {
  final m = RegExp(r'^\s*"?([^"<]+?)"?\s*<').firstMatch(raw);
  if (m != null && m.group(1)!.trim().isNotEmpty) return m.group(1)!.trim();
  return _extractEmail(raw);
}

String _shortDate(String raw) {
  // API date is like "2026-07-24 13:25:22"; show date + HH:MM.
  if (raw.length >= 16 && raw.contains('-')) {
    return raw.substring(5, 16).replaceFirst(' ', '  ');
  }
  return raw.length > 16 ? raw.substring(0, 16) : raw;
}

String _fmtSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// Baut den Zitat-Block für Antwort/Weiterleitung.
String _quote(Map<String, dynamic> msg, String body) {
  final from = '${msg['from'] ?? ''}';
  final date = '${msg['date'] ?? ''}';
  final head = date.isNotEmpty ? 'Am $date schrieb $from:' : '$from schrieb:';
  final quoted = body.split('\n').map((l) => '> $l').join('\n');
  return '\n$head\n$quoted\n';
}

// ---------------- message detail ----------------

/// Vollständige Nachricht — als Lesebereich (breite Fenster) oder als eigene
/// Seite (schmale Fenster) verwendbar.
class MailMessageView extends StatefulWidget {
  final int uid;
  final String box;
  final String selfEmail;

  /// Wird gerufen, wenn sich Flags geändert haben (Liste neu laden).
  final VoidCallback onChanged;

  /// Wird gerufen, wenn die Nachricht verschoben/gelöscht wurde.
  final VoidCallback? onDeleted;

  final MailComposeCallback onCompose;

  const MailMessageView({
    super.key,
    required this.uid,
    required this.box,
    required this.selfEmail,
    required this.onChanged,
    required this.onCompose,
    this.onDeleted,
  });

  @override
  State<MailMessageView> createState() => _MailMessageViewState();
}

class _MailMessageViewState extends State<MailMessageView> {
  final _api = ApiService();

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _msg = {};
  bool _receiptSent = false;

  /// Anhänge werden für eine Weiterleitung geholt.
  bool _forwarding = false;
  final Set<int> _downloading = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MailMessageView old) {
    super.didUpdateWidget(old);
    if (old.uid != widget.uid || old.box != widget.box) {
      setState(() {
        _loading = true;
        _error = null;
        _msg = {};
        _receiptSent = false;
      });
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final res = await _api.getMailMessage(widget.uid, box: widget.box);
      if (res['success'] == true) {
        _msg = Map<String, dynamic>.from(res['message_data'] ?? {});
        // Reading it makes it read - fire and forget, the list refreshes anyway.
        if (widget.box != 'Sent') {
          _api.flagMail(widget.uid, seen: true, box: widget.box);
        }
      } else {
        _error = res['message']?.toString() ?? 'Die Nachricht konnte nicht geladen werden.';
      }
    } catch (e) {
      _error = 'Keine Verbindung zum Server.';
    }
    if (mounted) setState(() => _loading = false);
  }

  String get _bodyText {
    final text = '${_msg['text'] ?? ''}'.trim();
    if (text.isNotEmpty) return text;
    return mailHtmlToText('${_msg['html'] ?? ''}');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _reply({bool all = false}) async {
    final from = _extractEmail('${_msg['from'] ?? ''}');
    final subject = '${_msg['subject'] ?? ''}';
    var cc = '';
    if (all) {
      final self = widget.selfEmail.toLowerCase();
      final others = <String>[];
      for (final field in ['to', 'cc']) {
        for (final part in '${_msg[field] ?? ''}'.split(',')) {
          final addr = _extractEmail(part);
          if (addr.isEmpty) continue;
          final low = addr.toLowerCase();
          if (low == self || low == from.toLowerCase()) continue;
          if (!others.contains(addr)) others.add(addr);
        }
      }
      cc = others.join(', ');
    }
    await widget.onCompose(
      to: from,
      cc: cc,
      subject: subject.startsWith('Re:') ? subject : 'Re: $subject',
      quotedBody: _quote(_msg, _bodyText),
      inReplyTo: '${_msg['message_id'] ?? ''}',
    );
  }

  Future<void> _forward() async {
    final subject = '${_msg['subject'] ?? ''}';
    final attachments = (_msg['attachments'] as List?) ?? [];
    // A forward is expected to carry the files along, so fetch them first.
    final carried = attachments.isEmpty
        ? <MailOutgoingAttachment>[]
        : await _downloadAllAttachments(attachments);
    if (!mounted) return;
    await widget.onCompose(
      subject: subject.startsWith('Fwd:') ? subject : 'Fwd: $subject',
      quotedBody: _quote(_msg, _bodyText),
      attachments: carried,
    );
  }

  /// Lädt alle Anhänge für die Weiterleitung. Was nicht mehr in die 25-MB-Grenze
  /// passt, wird ausgelassen und benannt — lieber ohne eine Datei weiterleiten
  /// als am Ende beim Senden scheitern.
  Future<List<MailOutgoingAttachment>> _downloadAllAttachments(List raw) async {
    setState(() => _forwarding = true);
    final carried = <MailOutgoingAttachment>[];
    final skipped = <String>[];
    var used = 0;
    try {
      for (final entry in raw.whereType<Map>()) {
        final a = Map<String, dynamic>.from(entry);
        final index = (a['index'] as num?)?.toInt() ?? -1;
        final name = '${a['name'] ?? 'Anhang'}';
        if (index < 0) {
          skipped.add(name);
          continue;
        }
        try {
          final res = await _api.getMailAttachment(
              uid: widget.uid, index: index, box: widget.box);
          if (res['success'] != true) {
            skipped.add(name);
            continue;
          }
          final bytes = base64Decode('${res['data_base64'] ?? ''}');
          if (used + bytes.length > ApiService.mailMaxAttachmentBytes) {
            skipped.add(name);
            continue;
          }
          used += bytes.length;
          carried.add(MailOutgoingAttachment(
            filename: '${res['name'] ?? name}',
            bytes: Uint8List.fromList(bytes),
          ));
        } catch (_) {
          skipped.add(name);
        }
      }
    } finally {
      if (mounted) setState(() => _forwarding = false);
    }
    if (skipped.isNotEmpty) {
      _toast('Nicht übernommen: ${skipped.join(', ')}');
    }
    return carried;
  }

  Future<void> _delete() async {
    final permanent = widget.box == 'Trash';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(permanent ? 'Endgültig löschen?' : 'In den Papierkorb?'),
        content: Text(permanent
            ? 'Die Nachricht wird aus dem Papierkorb entfernt und ist danach weg.'
            : 'Die Nachricht wandert in den Papierkorb.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(permanent ? 'Endgültig löschen' : 'Löschen')),
        ],
      ),
    );
    if (ok != true) return;
    final res = await _api.deleteMail(widget.uid, box: widget.box);
    if (!mounted) return;
    if (res['success'] == true) {
      widget.onDeleted?.call();
      if (widget.onDeleted == null) Navigator.pop(context);
    } else {
      _toast(res['message']?.toString() ?? 'Löschen fehlgeschlagen.');
    }
  }

  Future<void> _markUnread() async {
    final res = await _api.flagMail(widget.uid, seen: false, box: widget.box);
    if (res['success'] == true) {
      widget.onChanged();
      _toast('Als ungelesen markiert');
    }
  }

  Future<void> _sendReceipt() async {
    final res = await _api.sendMailReadReceipt(widget.uid, box: widget.box);
    if (!mounted) return;
    if (res['success'] == true) {
      setState(() => _receiptSent = true);
      _toast('Lesebestätigung gesendet');
    } else {
      _toast(res['message']?.toString() ?? 'Lesebestätigung fehlgeschlagen.');
    }
  }

  Future<void> _openAttachment(Map<String, dynamic> a) async {
    final index = (a['index'] as num?)?.toInt() ?? -1;
    if (index < 0 || _downloading.contains(index)) return;
    setState(() => _downloading.add(index));
    try {
      final res = await _api.getMailAttachment(
          uid: widget.uid, index: index, box: widget.box);
      if (res['success'] != true) {
        _toast(res['message']?.toString() ?? 'Anhang konnte nicht geladen werden.');
        return;
      }
      final bytes = base64Decode('${res['data_base64'] ?? ''}');
      final name = '${res['name'] ?? a['name'] ?? 'anhang'}';
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${_safeName(name)}');
      await file.writeAsBytes(Uint8List.fromList(bytes));
      final opened = await OpenFilex.open(file.path);
      if (opened.type != ResultType.done) {
        _toast('Gespeichert unter ${file.path}');
      }
    } catch (e) {
      _toast('Anhang konnte nicht geöffnet werden.');
    } finally {
      if (mounted) setState(() => _downloading.remove(index));
    }
  }

  static String _safeName(String name) =>
      name.replaceAll(RegExp(r'[^A-Za-z0-9._\-]'), '_');

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 44, color: Colors.redAccent),
              const SizedBox(height: 10),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _load();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Erneut versuchen'),
              ),
            ],
          ),
        ),
      );
    }

    final cs = Theme.of(context).colorScheme;
    final subject = '${_msg['subject'] ?? '(kein Betreff)'}';
    final attachments = (_msg['attachments'] as List?) ?? [];
    final mdnRequestedBy = '${_msg['mdn_requested_by'] ?? ''}';
    final delivery = _msg['delivery'] is Map
        ? MailDelivery.fromJson(Map<String, dynamic>.from(_msg['delivery']))
        : null;

    return Column(
      children: [
        _actionBar(cs),
        if (_forwarding)
          const LinearProgressIndicator(minHeight: 2)
        else
          const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(subject,
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              _kv('Von', '${_msg['from'] ?? ''}'),
              _kv('An', '${_msg['to'] ?? ''}'),
              if ('${_msg['cc'] ?? ''}'.isNotEmpty) _kv('Cc', '${_msg['cc']}'),
              if ('${_msg['date'] ?? ''}'.isNotEmpty) _kv('Datum', '${_msg['date']}'),
              if (delivery != null) ...[
                const SizedBox(height: 10),
                _deliveryCard(cs, delivery),
              ],
              if (mdnRequestedBy.isNotEmpty && widget.box != 'Sent') ...[
                const SizedBox(height: 10),
                _receiptRequestCard(cs, mdnRequestedBy),
              ],
              if ('${_msg['mdn_original_id'] ?? ''}'.isNotEmpty) ...[
                const SizedBox(height: 10),
                _infoBanner(
                  cs,
                  Icons.drafts,
                  const Color(0xFF2E9E4F),
                  'Das ist eine Lesebestätigung. Der Status steht bei der '
                  'ursprünglichen Nachricht im Ausgang.',
                ),
              ],
              const Divider(height: 26),
              SelectableText(_bodyText,
                  style: const TextStyle(fontSize: 15, height: 1.45)),
              if (attachments.isNotEmpty) ...[
                const Divider(height: 26),
                Row(
                  children: [
                    const Icon(Icons.attach_file, size: 18),
                    const SizedBox(width: 6),
                    Text('${attachments.length} Anhang${attachments.length == 1 ? '' : 'e'}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                ...attachments.whereType<Map>().map((raw) {
                  final a = Map<String, dynamic>.from(raw);
                  final index = (a['index'] as num?)?.toInt() ?? -1;
                  final busy = _downloading.contains(index);
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.insert_drive_file_outlined),
                    title: Text('${a['name'] ?? 'Anhang'}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(_fmtSize((a['size'] as num?)?.toInt() ?? 0)),
                    trailing: const Icon(Icons.download, size: 20),
                    onTap: () => _openAttachment(a),
                  );
                }),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _actionBar(ColorScheme cs) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            IconButton(
                icon: const Icon(Icons.reply),
                tooltip: 'Antworten',
                onPressed: () => _reply()),
            IconButton(
                icon: const Icon(Icons.reply_all),
                tooltip: 'Allen antworten',
                onPressed: () => _reply(all: true)),
            IconButton(
                icon: const Icon(Icons.forward),
                tooltip: _forwarding ? 'Anhänge werden geladen …' : 'Weiterleiten',
                onPressed: _forwarding ? null : _forward),
            IconButton(
                icon: const Icon(Icons.mark_email_unread_outlined),
                tooltip: 'Als ungelesen markieren',
                onPressed: _markUnread),
            IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: widget.box == 'Trash' ? 'Endgültig löschen' : 'Löschen',
                onPressed: _delete),
          ],
        ),
      ),
    );
  }

  Widget _deliveryCard(ColorScheme cs, MailDelivery d) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MailDeliveryIndicator(delivery: d, showLabel: true),
          if (d.smtpResponse.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Antwort des Zielservers: ${d.smtpResponse}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ],
          if (d.deliveredAt != null && d.deliveredAt!.isNotEmpty)
            Text('Angenommen: ${d.deliveredAt}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          if (d.receiptRequested) ...[
            const SizedBox(height: 8),
            MailReceiptIndicator(delivery: d, showLabel: true),
          ],
        ],
      ),
    );
  }

  Widget _receiptRequestCard(ColorScheme cs, String requestedBy) {
    if (_receiptSent) {
      return _infoBanner(cs, Icons.check_circle, const Color(0xFF2E9E4F),
          'Lesebestätigung gesendet.');
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.mark_email_read_outlined, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Der Absender bittet um eine Lesebestätigung.',
              style: TextStyle(fontSize: 13),
            ),
          ),
          TextButton(onPressed: _sendReceipt, child: const Text('Bestätigen')),
        ],
      ),
    );
  }

  Widget _infoBanner(ColorScheme cs, IconData icon, Color color, String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 52,
                child: Text(k,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13))),
            Expanded(child: SelectableText(v, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );
}

/// Eigene Seite für die Nachricht auf schmalen Fenstern.
class _MailMessageRoute extends StatelessWidget {
  final int uid;
  final String box;
  final String selfEmail;
  final VoidCallback onChanged;
  final MailComposeCallback onCompose;

  const _MailMessageRoute({
    required this.uid,
    required this.box,
    required this.selfEmail,
    required this.onChanged,
    required this.onCompose,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(MailBoxInfo.labelFor(box))),
      body: MailMessageView(
        uid: uid,
        box: box,
        selfEmail: selfEmail,
        onChanged: onChanged,
        onCompose: onCompose,
      ),
    );
  }
}
