import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../models/mail_models.dart';
import '../services/api_service.dart';
import '../services/mail_html_sanitizer.dart';
import '../services/secure_cloud_service.dart';
import '../utils/mail_html_text.dart';
import '../widgets/cloud_unlock_dialog.dart';
import '../widgets/file_viewer_dialog.dart';
import '../widgets/mail_delivery_indicator.dart';
import '../widgets/mail_korrespondenz_badge.dart';
import '../widgets/mail_folder_rail.dart';
import '../widgets/mail_html_view.dart';
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
  String? references,
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

  /// UIDs im Auswahlmodus. Leer heisst: kein Auswahlmodus. Die Auswahl gilt nur
  /// fuer den aktuellen Ordner und wird beim Wechseln verworfen.
  final Set<int> _selected = {};

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
    _loadKorrespondenzStatus();
    if (mounted) setState(() => _loading = false);
  }

  /// Mark the mails that already sit in Finanzamt ▸ Korrespondenz.
  ///
  /// Without this there is no way to tell an archived mail from one the import
  /// cron has not picked up — you either file it twice or assume it was filed
  /// when it was not. Best-effort: a failure just leaves the badges off.
  Future<void> _loadKorrespondenzStatus() async {
    final ids = _messages
        .map((m) => '${m['message_id'] ?? ''}')
        .where((s) => s.isNotEmpty)
        .toList();
    if (ids.isEmpty) return;
    try {
      final res = await _api.getKorrespondenzStatus(ids);
      if (res['success'] != true || !mounted) return;
      final data = res['data'] ?? res;
      final status = Map<String, dynamic>.from(data['status'] ?? {});
      if (status.isEmpty) return;
      setState(() {
        for (final m in _messages) {
          final s = status['${m['message_id'] ?? ''}'];
          if (s is Map) m['korrespondenz'] = Map<String, dynamic>.from(s);
        }
      });
    } catch (_) {/* badges are cosmetic — never break the list over them */}
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
    _loadKorrespondenzStatus();
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
      _selected.clear();
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
        mitgliedernummer: widget.mitgliedernummer,
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
    String? references,
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
        references: references,
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

  /// Rückfrage vor dem endgültigen Löschen. Nur im Papierkorb nötig — überall
  /// sonst landet die Nachricht dort und ist zurückholbar.
  Future<bool> _confirmPermanentDelete() async {
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
    return ok == true;
  }

  Future<void> _deleteMessage(Map<String, dynamic> msg) async {
    final uid = (msg['uid'] as num?)?.toInt() ?? 0;
    final permanent = _box == 'Trash';
    if (permanent && !await _confirmPermanentDelete()) return;
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

  // ---------------- Mehrfachauswahl ----------------

  bool get _selecting => _selected.isNotEmpty;

  List<Map<String, dynamic>> get _selectedMessages => _messages
      .where((m) => _selected.contains((m['uid'] as num?)?.toInt() ?? -1))
      .toList();

  void _toggleSelected(int uid) {
    setState(() {
      if (!_selected.remove(uid)) _selected.add(uid);
    });
  }

  void _clearSelection() => setState(_selected.clear);

  void _selectAllLoaded() {
    setState(() {
      for (final m in _messages) {
        final uid = (m['uid'] as num?)?.toInt() ?? 0;
        if (uid > 0) _selected.add(uid);
      }
    });
  }

  /// Der Ordner hat mehr Nachrichten, als geladen sind. Erst nachladen, dann
  /// auswaehlen — sonst hiesse „alle" in Wahrheit „alle sichtbaren", und man
  /// loescht 50 statt der 312, die man gemeint hat.
  Future<void> _selectAllInFolder() async {
    while (mounted && _messages.length < _total && !_loadingMore) {
      final before = _messages.length;
      await _loadMore();
      if (!mounted || _messages.length == before) break; // kein Fortschritt
    }
    if (mounted) _selectAllLoaded();
  }

  /// Meldet, was wirklich passiert ist. `ok`/`failed` kommen pro UID vom Server;
  /// ein stilles „fertig" bei drei fehlgeschlagenen Nachrichten waere genau der
  /// Fehler, den Sammelaktionen ueblicherweise machen.
  void _reportBulk(Map<String, dynamic> res, String verb, {VoidCallback? undo}) {
    final ok = (res['ok'] as List?)?.length ?? 0;
    final failed = (res['failed'] as List?)?.length ?? 0;
    final text = failed == 0
        ? '$ok $verb'
        : '$ok $verb, $failed fehlgeschlagen';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      action: (undo != null && ok > 0)
          ? SnackBarAction(label: 'Rückgängig', onPressed: undo)
          : null,
    ));
  }

  Future<void> _bulkFlag() async {
    final picked = _selectedMessages;
    if (picked.isEmpty) return;
    // Ist irgendetwas ungelesen, liest die Aktion alles — sonst umgekehrt.
    final markSeen = picked.any((m) => m['seen'] != true);
    final uids = picked
        .map((m) => (m['uid'] as num?)?.toInt() ?? 0)
        .where((u) => u > 0)
        .toList();
    final res = await _api.flagMail(0, uids: uids, seen: markSeen, box: _box);
    if (!mounted) return;
    setState(() {
      for (final m in picked) {
        m['seen'] = markSeen;
      }
      _selected.clear();
    });
    _loadFolders();
    _reportBulk(res, markSeen ? 'als gelesen markiert' : 'als ungelesen markiert');
  }

  Future<void> _bulkMove(String target, String verb) async {
    final picked = _selectedMessages;
    if (picked.isEmpty) return;
    final origin = _box;
    final uids = picked
        .map((m) => (m['uid'] as num?)?.toInt() ?? 0)
        .where((u) => u > 0)
        .toList();
    // Vor dem Verschieben merken: danach haben die Nachrichten im Zielordner
    // andere UIDs, und nur die Message-ID findet sie fuer das Rueckgaengig.
    final mids = picked
        .map((m) => '${m['message_id'] ?? ''}')
        .where((s) => s.isNotEmpty)
        .toList();
    setState(() {
      _messages.removeWhere((m) => picked.contains(m));
      _total = (_total - picked.length).clamp(0, 1 << 30);
      if (_openUid != null && uids.contains(_openUid)) _openUid = null;
      _selected.clear();
    });
    final res = await _api.moveMail(target: target, box: origin, uids: uids);
    if (!mounted) return;
    if (res['success'] != true) {
      // Auch bei einem Teilerfolg neu laden: die fehlgeschlagenen Nachrichten
      // liegen noch im Ordner, sind aber oben schon aus der Liste geflogen.
      _load(keepOpen: true);
    }
    _loadFolders();
    _reportBulk(res, verb,
        undo: mids.isEmpty
            ? null
            : () => _undoBulk(mids, from: target, to: origin));
  }

  Future<void> _bulkDelete() async {
    final picked = _selectedMessages;
    if (picked.isEmpty) return;
    final origin = _box;
    final permanent = origin == 'Trash';
    if (permanent && !await _confirmPermanentDeleteMany(picked.length)) return;
    final uids = picked
        .map((m) => (m['uid'] as num?)?.toInt() ?? 0)
        .where((u) => u > 0)
        .toList();
    final mids = picked
        .map((m) => '${m['message_id'] ?? ''}')
        .where((s) => s.isNotEmpty)
        .toList();
    setState(() {
      _messages.removeWhere((m) => picked.contains(m));
      _total = (_total - picked.length).clamp(0, 1 << 30);
      if (_openUid != null && uids.contains(_openUid)) _openUid = null;
      _selected.clear();
    });
    final res = await _api.deleteMail(0, uids: uids, box: origin);
    if (!mounted) return;
    if (res['success'] != true) {
      _load(keepOpen: true);
    }
    _loadFolders();
    _reportBulk(res, permanent ? 'endgültig gelöscht' : 'in den Papierkorb verschoben',
        // Endgueltig geloescht gibt es nichts zurueckzuholen.
        undo: (permanent || mids.isEmpty)
            ? null
            : () => _undoBulk(mids, from: 'Trash', to: origin));
  }

  Future<void> _undoBulk(List<String> messageIds,
      {required String from, required String to}) async {
    final res = await _api.moveMail(target: to, box: from, messageIds: messageIds);
    if (!mounted) return;
    _load(keepOpen: true);
    _loadFolders();
    if (res['success'] != true) {
      _reportBulk(res, 'zurückgeholt');
    }
  }

  Future<bool> _confirmPermanentDeleteMany(int count) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$count Nachrichten endgültig löschen?'),
        content: const Text(
            'Sie werden aus dem Papierkorb entfernt und sind danach weg.'),
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
    return ok == true;
  }

  // ---------------- Wischgesten ----------------

  /// Entfernt die Zeile sofort und stellt sie wieder her, wenn der Server
  /// ablehnt. Sofortiges Verschwinden ist der Punkt der Geste — auf die Antwort
  /// zu warten würde sich anfühlen, als hätte der Wisch nicht gezählt.
  ///
  /// [undoFrom] ist der Ordner, in dem die Nachricht danach liegt, [undoTo] der,
  /// aus dem sie kam. Fehlt eines davon, gibt es kein Rückgängig — beim
  /// endgültigen Löschen gibt es nichts mehr zurückzuholen.
  Future<void> _removeWithRollback(
    Map<String, dynamic> m, {
    required Future<Map<String, dynamic>> Function() call,
    required String doneText,
    String? undoFrom,
    String? undoTo,
  }) async {
    final uid = (m['uid'] as num?)?.toInt() ?? 0;
    final index = _messages.indexOf(m);
    final reopen = _openUid == uid;
    setState(() {
      _messages.remove(m);
      _total = _total > 0 ? _total - 1 : 0;
      if (reopen) _openUid = null;
    });
    final res = await call();
    if (!mounted) return;
    if (res['success'] != true) {
      setState(() {
        _messages.insert(index < 0 ? 0 : index.clamp(0, _messages.length), m);
        _total += 1;
        if (reopen) _openUid = uid;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res['message']?.toString() ?? 'Aktion fehlgeschlagen.')));
      return;
    }
    _loadFolders();
    final mid = '${m['message_id'] ?? ''}';
    final canUndo = undoFrom != null && undoTo != null && mid.isNotEmpty;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(doneText),
      action: canUndo
          ? SnackBarAction(
              label: 'Rückgängig',
              onPressed: () => _undoMove(mid, from: undoFrom, to: undoTo))
          : null,
    ));
  }

  /// Holt eine verschobene Nachricht zurück. Im Zielordner hat sie eine andere
  /// UID, deshalb wird sie über ihre Message-ID benannt.
  Future<void> _undoMove(String messageId,
      {required String from, required String to}) async {
    final res = await _api.moveMail(target: to, box: from, messageId: messageId);
    if (!mounted) return;
    if (res['success'] == true) {
      _load(keepOpen: true);
      _loadFolders();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res['message']?.toString() ?? 'Rückgängig fehlgeschlagen.')));
    }
  }

  Future<void> _swipeMove(
      Map<String, dynamic> m, String target, String doneText) {
    final origin = _box;
    return _removeWithRollback(m,
        call: () => _api.moveMail(
            uid: (m['uid'] as num?)?.toInt() ?? 0, target: target, box: origin),
        doneText: doneText,
        undoFrom: target,
        undoTo: origin);
  }

  Future<void> _swipeDelete(Map<String, dynamic> m) {
    final origin = _box;
    final permanent = origin == 'Trash';
    return _removeWithRollback(m,
        call: () =>
            _api.deleteMail((m['uid'] as num?)?.toInt() ?? 0, box: origin),
        doneText:
            permanent ? 'Endgültig gelöscht' : 'In den Papierkorb verschoben',
        undoFrom: permanent ? null : 'Trash',
        undoTo: permanent ? null : origin);
  }

  /// Nach rechts wischen: die aufbauende Geste. Was das heißt, hängt vom Ordner
  /// ab — im Eingang gelesen/ungelesen, im Spam „kein Spam", im Papierkorb
  /// wiederherstellen. In Gesendet und Entwürfe gibt es nichts Sinnvolles, dort
  /// bleibt die Richtung aus.
  _SwipeAction? _swipeRightAction(Map<String, dynamic> m) {
    switch (_box) {
      case 'INBOX':
      case 'Archive':
        final seen = m['seen'] == true;
        return _SwipeAction(
          icon: seen ? Icons.mark_email_unread_outlined : Icons.drafts_outlined,
          label: seen ? 'Ungelesen' : 'Gelesen',
          color: const Color(0xFF4a90d9),
          removesRow: false,
          run: () => _toggleSeen(m),
        );
      case 'Junk':
        return _SwipeAction(
          icon: Icons.inbox_outlined,
          label: 'Kein Spam',
          color: const Color(0xFF2E7D32),
          removesRow: true,
          run: () => _swipeMove(m, 'INBOX', 'Als „kein Spam" in den Eingang'),
        );
      case 'Trash':
        return _SwipeAction(
          icon: Icons.restore_from_trash_outlined,
          label: 'Wiederherstellen',
          color: const Color(0xFF2E7D32),
          removesRow: true,
          run: () => _swipeMove(m, 'INBOX', 'Wiederhergestellt'),
        );
      default:
        return null;
    }
  }

  /// Nach links wischen: raus aus diesem Ordner. Im Papierkorb heißt das
  /// endgültig, deshalb dort die Rückfrage.
  _SwipeAction _swipeLeftAction(Map<String, dynamic> m) {
    final permanent = _box == 'Trash';
    return _SwipeAction(
      icon: permanent ? Icons.delete_forever_outlined : Icons.delete_outline,
      label: permanent ? 'Endgültig löschen' : 'Papierkorb',
      color: permanent ? const Color(0xFFB3261E) : const Color(0xFFD32F2F),
      removesRow: true,
      confirm: permanent ? _confirmPermanentDelete : null,
      run: () => _swipeDelete(m),
    );
  }

  Widget _swipeBackground(_SwipeAction a, {required bool fromLeft}) {
    const text = TextStyle(color: Colors.white, fontWeight: FontWeight.w600);
    final parts = <Widget>[
      Icon(a.icon, color: Colors.white),
      const SizedBox(width: 8),
      Text(a.label, style: text),
    ];
    return Container(
      color: a.color,
      alignment: fromLeft ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: fromLeft ? parts : parts.reversed.toList(),
      ),
    );
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
        appBar: _selecting ? _selectionAppBar() : _normalAppBar(showRail: showRail),
        drawer: (showRail || _selecting)
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
        floatingActionButton: (showRail || _selecting)
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
                        mitgliedernummer: widget.mitgliedernummer,
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

  PreferredSizeWidget _normalAppBar({required bool showRail}) {
    return AppBar(
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
    );
  }

  /// Die Leiste im Auswahlmodus. Sie ersetzt die normale, damit auf einen Blick
  /// klar ist, dass die naechste Aktion mehrere Nachrichten trifft.
  PreferredSizeWidget _selectionAppBar() {
    final cs = Theme.of(context).colorScheme;
    final anyUnread = _selectedMessages.any((m) => m['seen'] != true);
    return AppBar(
      backgroundColor: cs.secondaryContainer,
      foregroundColor: cs.onSecondaryContainer,
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Auswahl beenden',
        onPressed: _clearSelection,
      ),
      title: Text('${_selected.length} ausgewählt'),
      actions: [
        IconButton(
          icon: const Icon(Icons.select_all),
          tooltip: 'Alle geladenen auswählen',
          onPressed: _selectAllLoaded,
        ),
        IconButton(
          icon: Icon(anyUnread ? Icons.drafts_outlined : Icons.mark_email_unread_outlined),
          tooltip: anyUnread ? 'Als gelesen markieren' : 'Als ungelesen markieren',
          onPressed: _bulkFlag,
        ),
        if (_box == 'INBOX')
          IconButton(
            icon: const Icon(Icons.report_outlined),
            tooltip: 'Als Spam markieren',
            onPressed: () => _bulkMove('Junk', 'als Spam markiert'),
          ),
        if (_box == 'Junk' || _box == 'Trash')
          IconButton(
            icon: const Icon(Icons.inbox_outlined),
            tooltip: 'In den Eingang',
            onPressed: () => _bulkMove('INBOX', 'in den Eingang verschoben'),
          ),
        IconButton(
          icon: Icon(_box == 'Trash' ? Icons.delete_forever_outlined : Icons.delete_outline),
          tooltip: _box == 'Trash' ? 'Endgültig löschen' : 'In den Papierkorb',
          onPressed: _bulkDelete,
        ),
      ],
    );
  }

  Widget _listColumn({required bool showPane}) {
    final cs = Theme.of(context).colorScheme;
    // Alles Geladene ist markiert, im Ordner liegt aber mehr. Ohne diesen
    // Hinweis heisst „alle auswaehlen" stillschweigend „alle sichtbaren".
    final moreInFolder = _selecting &&
        _selected.length >= _messages.length &&
        _total > _messages.length;
    return Column(
      children: [
        _searchBar(),
        if (moreInFolder)
          Container(
            width: double.infinity,
            color: cs.secondaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Alle ${_messages.length} geladenen ausgewählt.',
                    style: TextStyle(fontSize: 12, color: cs.onSecondaryContainer),
                  ),
                ),
                TextButton(
                  onPressed: _selectAllInFolder,
                  child: Text('Alle $_total im Ordner'),
                ),
              ],
            ),
          ),
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
    final picked = _selected.contains(uid);
    // In Ausgang/Entwürfe the recipient is the useful name, not the sender.
    final outgoing = _box == 'Sent' || _box == 'Drafts';
    final who = _displayName('${(outgoing ? m['to'] : m['from']) ?? ''}');
    final subject = '${m['subject'] ?? '(kein Betreff)'}';
    final delivery = m['delivery'] is Map
        ? MailDelivery.fromJson(Map<String, dynamic>.from(m['delivery']))
        : null;

    final tile = Material(
      // Ausgewaehlt und geoeffnet muessen sich unterscheiden — sonst weiss man
      // im Lesebereich nicht, ob eine Zeile markiert oder nur offen ist.
      color: picked
          ? cs.primaryContainer.withValues(alpha: 0.75)
          : selected
              ? cs.secondaryContainer.withValues(alpha: 0.55)
              : Colors.transparent,
      child: ListTile(
        leading: picked
            ? CircleAvatar(
                backgroundColor: cs.primary,
                child: Icon(Icons.check, color: cs.onPrimary),
              )
            : CircleAvatar(
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
            if (delivery != null || m['korrespondenz'] != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  if (delivery != null) ...[
                    MailDeliveryIndicator(delivery: delivery),
                    if (delivery.receiptRequested) ...[
                      const SizedBox(width: 8),
                      MailReceiptIndicator(delivery: delivery),
                    ],
                    if (m['korrespondenz'] != null) const SizedBox(width: 8),
                  ],
                  if (m['korrespondenz'] != null)
                    MailKorrespondenzBadge(
                      korrespondenz:
                          Map<String, dynamic>.from(m['korrespondenz'] as Map),
                    ),
                ],
              ),
            ],
          ],
        ),
        trailing: _selecting
            ? null
            : PopupMenuButton<String>(
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
        onTap: () => _selecting
            ? _toggleSelected(uid)
            : _openMessage(m, wide: showPane),
        // Langes Druecken startet die Auswahl — die uebliche Geste dafuer.
        onLongPress: uid > 0 ? () => _toggleSelected(uid) : null,
      ),
    );

    // Im Auswahlmodus kein Wischen: die Geste wuerde eine einzelne Nachricht
    // treffen, waehrend die Leiste oben mehrere meint.
    if (_selecting) return tile;

    final right = _swipeRightAction(m);
    final left = _swipeLeftAction(m);
    return Dismissible(
      key: ValueKey('$_box:$uid'),
      direction: right == null
          ? DismissDirection.endToStart
          : DismissDirection.horizontal,
      background: right == null
          ? const SizedBox.shrink()
          : _swipeBackground(right, fromLeft: true),
      secondaryBackground: _swipeBackground(left, fromLeft: false),
      // Ein Viertel Zeile reicht nicht: beim Scrollen darf nichts aus Versehen
      // im Papierkorb landen.
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.45,
        DismissDirection.endToStart: 0.45,
      },
      confirmDismiss: (dir) async {
        final a = dir == DismissDirection.startToEnd ? right : left;
        if (a == null) return false;
        if (a.confirm != null && !await a.confirm!()) return false;
        // Gelesen/ungelesen entfernt die Zeile nicht — sie federt zurück, und
        // die Aktion läuft hier statt in onDismissed.
        if (!a.removesRow) {
          await a.run();
          return false;
        }
        return true;
      },
      onDismissed: (dir) {
        final a = dir == DismissDirection.startToEnd ? right : left;
        a?.run();
      },
      child: tile,
    );
  }
}

/// Eine Wischgeste auf einer Nachrichtenzeile.
class _SwipeAction {
  final IconData icon;
  final String label;
  final Color color;

  /// true = die Zeile verschwindet, false = sie federt zurück.
  final bool removesRow;

  /// Rückfrage vor dem Wegwischen; null heißt: ohne Nachfrage.
  final Future<bool> Function()? confirm;
  final Future<void> Function() run;

  const _SwipeAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.removesRow,
    required this.run,
    this.confirm,
  });
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

  /// Für die Cloud-Sitzung — der verschlüsselte Speicher hängt am Postfach.
  final String mitgliedernummer;

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
    required this.mitgliedernummer,
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

  /// Formatierte Ansicht ist AUS, solange sie nicht angefordert wird.
  ///
  /// BSI IT-Grundschutz APP.5.3.A1 ist ein Basis-MUSS: E-Mail-Clients MÜSSEN so
  /// konfiguriert sein, dass HTML nicht automatisch interpretiert wird. Der
  /// Textpfad ist also die Voreinstellung, nicht ein Notbehelf.
  bool _showFormatted = false;
  MailSanitizedHtml? _sanitized;
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
    _loadKorrespondenzStatus();
    // Nicht abwarten: die Nachricht soll sofort dastehen, das Archivieren
    // laeuft daneben und meldet sich, wenn es fertig ist.
    unawaited(_archiveAttachments());
  }

  /// Ask separately whether this mail is already archived. The viewer fetches
  /// its own message by uid, so it never sees the flag the list attached — and
  /// threading it through every call site would break the moment the viewer is
  /// opened from somewhere new.
  Future<void> _loadKorrespondenzStatus() async {
    final id = '${_msg['message_id'] ?? ''}';
    if (id.isEmpty) return;
    try {
      final res = await _api.getKorrespondenzStatus([id]);
      if (res['success'] != true || !mounted) return;
      final data = res['data'] ?? res;
      final s = Map<String, dynamic>.from(data['status'] ?? {})[id];
      if (s is Map) {
        setState(() => _msg['korrespondenz'] = Map<String, dynamic>.from(s));
      }
    } catch (_) {/* the banner is cosmetic */}
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

  // ---------------- Anhänge in die verschlüsselte Cloud ----------------

  /// Die Sitzung des verschlüsselten Speichers. Sie wird beim App-Start
  /// entsperrt und beim Beenden gesperrt — hier wird nur benutzt, was offen ist.
  late final SecureCloudService _cloud =
      SecureCloudService(_api, widget.mitgliedernummer);

  bool _archiving = false;

  /// Nur diese vier Formate, wie besprochen.
  static const _cloudExt = {'pdf', 'jpg', 'jpeg', 'txt'};
  static const _cloudMime = {
    'application/pdf',
    'application/x-pdf',
    'image/jpeg',
    'image/jpg',
    'text/plain',
  };

  /// Ordner, aus denen automatisch archiviert wird.
  ///
  /// Bewusst NICHT Spam: dessen Anhänge automatisch in den Dauerspeicher zu
  /// legen hieße, Schadsoftware aufzubewahren. Und nicht Gesendet/Entwürfe —
  /// was man selbst verschickt hat, hatte man schon.
  static const _archiveBoxes = {'INBOX', 'Archive'};

  /// Ein echter Anhang in einem der gewünschten Formate.
  ///
  /// `inline` schließt Signatur-Logos und Newsletter-Bilder aus, die technisch
  /// auch Anhänge sind — sonst wäre die Cloud nach einer Woche voll mit fremden
  /// Grafiken statt mit Unterlagen.
  bool _cloudWorthy(Map a) {
    if (a['inline'] == true) return false;
    final type = '${a['type'] ?? ''}'.toLowerCase().split(';').first.trim();
    if (_cloudMime.contains(type)) return true;
    // Manche Absender schicken alles als application/octet-stream; dann zählt
    // die Endung.
    final name = '${a['name'] ?? ''}'.toLowerCase();
    final dot = name.lastIndexOf('.');
    return dot > 0 && _cloudExt.contains(name.substring(dot + 1));
  }

  List<Map<String, dynamic>> get _cloudAttachments =>
      ((_msg['attachments'] as List?) ?? const [])
          .whereType<Map>()
          .where(_cloudWorthy)
          .map((a) => Map<String, dynamic>.from(a))
          .toList();

  /// Legt die Anhänge verschlüsselt in der Cloud ab, sobald die Mail geöffnet
  /// wird.
  ///
  /// Der Server kann das nicht selbst: der Cloud-Schlüssel entsteht aus der
  /// Passphrase und liegt nur hier im Speicher. Deshalb passiert es beim Lesen
  /// und nur, wenn die Sitzung offen ist — ist sie es nicht, bleibt alles, wie
  /// es war, und es wird nichts erzwungen.
  ///
  /// Die Klartextbytes gehen direkt aus der Antwort in die Verschlüsselung;
  /// nichts davon berührt die Platte.
  Future<void> _archiveAttachments() async {
    if (_archiving || !mounted) return;
    if (_msg['archived'] == true) return;
    if (!_archiveBoxes.contains(widget.box)) return;
    if (!_cloud.isUnlocked) return;
    final wanted = _cloudAttachments;
    if (wanted.isEmpty) return;

    setState(() => _archiving = true);
    var done = 0;
    String? failure;
    for (final a in wanted) {
      final index = (a['index'] as num?)?.toInt() ?? -1;
      if (index < 0) continue;
      try {
        final res = await _api.getMailAttachment(
            uid: widget.uid, index: index, box: widget.box);
        if (res['success'] != true) {
          failure = res['message']?.toString() ?? 'Anhang nicht lesbar';
          continue;
        }
        final bytes =
            Uint8List.fromList(base64Decode('${res['data_base64'] ?? ''}'));
        final err = await _cloud.uploadBytes(
          plain: bytes,
          displayName: '${res['name'] ?? a['name'] ?? 'anhang'}',
          mime: '${res['type'] ?? a['type'] ?? ''}',
        );
        if (err != null) {
          failure = err;
          // Volle Cloud oder abgelaufene Sitzung trifft auch alle weiteren —
          // dann lieber abbrechen als denselben Fehler fünfmal zeigen.
          break;
        }
        done++;
      } catch (e) {
        failure = 'Sichern fehlgeschlagen';
        break;
      }
    }

    // Die Markierung nur setzen, wenn wirklich alles drin ist. Sonst gälte die
    // Mail als erledigt und der Rest würde nie nachgeholt.
    final complete = done == wanted.length;
    if (complete) {
      await _api.flagMail(widget.uid, keyword: r'$CloudArchived', box: widget.box);
    }
    if (!mounted) return;
    setState(() {
      _archiving = false;
      if (complete) _msg['archived'] = true;
    });
    if (complete) {
      _toast(done == 1
          ? 'Anhang in der verschlüsselten Cloud gesichert'
          : '$done Anhänge in der verschlüsselten Cloud gesichert');
      widget.onChanged();
    } else if (failure != null) {
      _toast('Cloud: $failure');
    }
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
      // Carry the parent's chain so a reply-to-a-reply keeps its history.
      references: '${_msg['references'] ?? ''}',
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
      if (!mounted) return;

      // PDFs und Bilder zeigt die App selbst — direkt aus dem Speicher, ohne
      // die Datei je auf die Platte zu schreiben und ohne sie einem fremden
      // Programm zu übergeben. Ein Anhang aus einer E-Mail ist der klassische
      // Weg für Schadsoftware, und hier gehen Arzt-, Jobcenter- und
      // Behördenunterlagen durch.
      final shown = await FileViewerDialog.showFromBytes(
          context, Uint8List.fromList(bytes), _viewerName(name, '${res['type'] ?? ''}'));
      if (shown) return;

      // Nur für Formate ohne eingebauten Betrachter — etwa Word oder Excel.
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

  static const _viewableExt = {
    'pdf', 'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'tiff'
  };

  /// Der Betrachter entscheidet anhand der Dateiendung. Anhänge aus fremden
  /// Programmen kommen aber oft ohne oder mit falscher Endung — ein als
  /// `dokument` benanntes PDF wäre sonst nicht darstellbar, obwohl der
  /// Content-Type es klar sagt. Deshalb notfalls die Endung daraus ableiten.
  static String _viewerName(String name, String contentType) {
    final ext = name.toLowerCase().split('.').last;
    if (_viewableExt.contains(ext)) return name;
    const byType = {
      'application/pdf': 'pdf',
      'application/x-pdf': 'pdf',
      'image/jpeg': 'jpg',
      'image/jpg': 'jpg',
      'image/png': 'png',
      'image/gif': 'gif',
      'image/webp': 'webp',
      'image/bmp': 'bmp',
      'image/x-ms-bmp': 'bmp',
      'image/tiff': 'tiff',
    };
    final want = byType[contentType.toLowerCase().split(';').first.trim()];
    if (want == null) return name;
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    return '${base.isEmpty ? 'anhang' : base}.$want';
  }

  bool get _hasHtml => '${_msg['html'] ?? ''}'.trim().isNotEmpty;

  void _toggleFormatted() {
    if (!_showFormatted) {
      // Erst beim Anfordern sanitisieren, und das Ergebnis behalten.
      _sanitized ??= sanitizeMailHtml('${_msg['html'] ?? ''}');
    }
    setState(() => _showFormatted = !_showFormatted);
  }

  /// Löst `cid:` gegen die Teile DIESER Nachricht auf. Kein Netzzugriff nach
  /// außen — der Teil kommt aus derselben Mail über das eigene Backend.
  Future<Uint8List?> _loadInlineImage(String contentId) async {
    final parts = (_msg['attachments'] as List?) ?? const [];
    for (final raw in parts.whereType<Map>()) {
      final a = Map<String, dynamic>.from(raw);
      if ('${a['content_id'] ?? ''}' != contentId) continue;
      final index = (a['index'] as num?)?.toInt() ?? -1;
      if (index < 0) return null;
      try {
        final res = await _api.getMailAttachment(
            uid: widget.uid, index: index, box: widget.box);
        if (res['success'] != true) return null;
        return Uint8List.fromList(base64Decode('${res['data_base64'] ?? ''}'));
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Widget _viewToggle(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(_showFormatted ? Icons.article : Icons.text_fields,
              size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _showFormatted
                  ? 'Formatierte Ansicht'
                  : 'Textansicht — Formatierung und Bilder des Absenders sind aus',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
          TextButton(
            onPressed: _toggleFormatted,
            child: Text(_showFormatted ? 'Nur Text' : 'Formatiert anzeigen'),
          ),
        ],
      ),
    );
  }

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
    // Wird die formatierte Ansicht gezeigt, stehen eingebettete Bilder schon im
    // Text — dann gehören sie nicht zusätzlich in die Anhangsliste.
    final hideInline = _showFormatted && _hasHtml;
    final fileAttachments = attachments
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((a) => !(hideInline &&
            a['inline'] == true &&
            '${a['content_id'] ?? ''}'.isNotEmpty))
        .toList();
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
              // Above the subject on purpose: whether this letter is already
              // in the Verein's records is the first thing worth knowing.
              if (_msg['korrespondenz'] is Map)
                MailKorrespondenzBadge(
                  korrespondenz: Map<String, dynamic>.from(_msg['korrespondenz'] as Map),
                  compact: false,
                ),
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
              if (_hasHtml) _viewToggle(cs),
              if (_showFormatted && _hasHtml)
                MailHtmlView(
                  sanitized: _sanitized!,
                  loadInlineImage: _loadInlineImage,
                )
              else
                SelectableText(_bodyText,
                    style: const TextStyle(fontSize: 15, height: 1.45)),
              if (fileAttachments.isNotEmpty) ...[
                const Divider(height: 26),
                Row(
                  children: [
                    const Icon(Icons.attach_file, size: 18),
                    const SizedBox(width: 6),
                    Text(
                        '${fileAttachments.length} Anhang'
                        '${fileAttachments.length == 1 ? '' : 'e'}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (_msg['archived'] == true)
                      Row(
                        children: [
                          const Icon(Icons.cloud_done,
                              size: 16, color: Color(0xFF2E7D32)),
                          const SizedBox(width: 4),
                          Text('In der Cloud gesichert',
                              style: TextStyle(
                                  fontSize: 12, color: cs.onSurfaceVariant)),
                        ],
                      )
                    else if (_archiving)
                      Row(
                        children: [
                          const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 6),
                          Text('Wird gesichert…',
                              style: TextStyle(
                                  fontSize: 12, color: cs.onSurfaceVariant)),
                        ],
                      )
                    // Gesperrte Cloud stillschweigend zu übergehen wäre der
                    // schlimmere Fehler: man glaubt, die Anhänge lägen sicher,
                    // und sie tun es nicht.
                    else if (_archiveBoxes.contains(widget.box) &&
                        _cloudAttachments.isNotEmpty &&
                        !_cloud.isUnlocked)
                      TextButton.icon(
                        icon: const Icon(Icons.lock_outline, size: 16),
                        label: const Text('Cloud gesperrt'),
                        style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact),
                        onPressed: () async {
                          final ok = await CloudUnlockDialog.ensureUnlocked(
                              context, _api, widget.mitgliedernummer);
                          if (ok) await _archiveAttachments();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                ...fileAttachments.map((raw) {
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
                    // Grüne Wolke = liegt verschlüsselt in der Cloud. Nur bei
                    // den Anhängen, die dorthin gehören — bei einem inline
                    // eingebetteten Logo wäre sie eine Lüge.
                    trailing: (_msg['archived'] == true && _cloudWorthy(a))
                        ? const Icon(Icons.cloud_done,
                            size: 20, color: Color(0xFF2E7D32))
                        : _archiving && _cloudWorthy(a)
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.download, size: 20),
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
  final String mitgliedernummer;
  final VoidCallback onChanged;
  final MailComposeCallback onCompose;

  const _MailMessageRoute({
    required this.uid,
    required this.box,
    required this.selfEmail,
    required this.mitgliedernummer,
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
        mitgliedernummer: mitgliedernummer,
        onChanged: onChanged,
        onCompose: onCompose,
      ),
    );
  }
}
