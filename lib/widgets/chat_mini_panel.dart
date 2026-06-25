import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/chat_service.dart';
import '../services/global_chat_service.dart';
import '../services/logger_service.dart';

/// Lightweight Messenger-style chat panel — text + small action row only.
/// No WebRTC, no call buttons, no inline file attachment UI for now (link to
/// the full AdminChatDialog via the expand icon when richer actions needed).
///
/// Sized + dragged by the parent overlay; this widget just fills its slot.
class ChatMiniPanel extends StatefulWidget {
  final int conversationId;
  final String senderName;
  final String currentMitgliedernummer;
  final VoidCallback onMinimize;
  final VoidCallback onClose;
  final VoidCallback? onExpand;
  const ChatMiniPanel({
    super.key,
    required this.conversationId,
    required this.senderName,
    required this.currentMitgliedernummer,
    required this.onMinimize,
    required this.onClose,
    this.onExpand,
  });

  @override
  State<ChatMiniPanel> createState() => _ChatMiniPanelState();
}

class _ChatMiniPanelState extends State<ChatMiniPanel> {
  final _api = ApiService();
  final _chat = ChatService();
  final _log = LoggerService();
  final _inputC = TextEditingController();
  final _scrollC = ScrollController();
  StreamSubscription? _msgSub;
  List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  int? _lastMessageId;

  @override
  void initState() {
    super.initState();
    _chat.joinConversation(widget.conversationId);
    _load();
    _msgSub = _chat.messageStream.listen((m) {
      if (m.conversationId != widget.conversationId) return;
      if (!mounted) return;
      // Avoid duplicates from REST + WebSocket race
      if (_messages.any((x) => x.id == m.id)) return;
      setState(() {
        _messages.add(m);
        _lastMessageId = m.id;
      });
      _scrollToBottom();
      GlobalChatService().markRead(widget.conversationId);
    });
    // NOTE: polling fallback de 5s a fost eliminat — cauza rebuild-uri pe
    // panel care făceau backspace să nu mai funcționeze. WebSocket suficient.
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _inputC.dispose();
    _scrollC.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await _api.getChatMessages(widget.conversationId, widget.currentMitgliedernummer);
    if (!mounted) return;
    if (r['success'] == true) {
      final raw = (r['messages'] as List? ?? []);
      _messages = raw.map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      if (_messages.isNotEmpty) _lastMessageId = _messages.last.id;
    }
    setState(() => _loading = false);
    _scrollToBottom();
    GlobalChatService().markRead(widget.conversationId);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollC.hasClients) {
        _scrollC.jumpTo(_scrollC.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _inputC.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final r = await _api.sendChatMessage(widget.conversationId, widget.currentMitgliedernummer, text);
      if (r['success'] == true) {
        _inputC.clear();
        // Optimistic: append immediately so user sees the send before WS echo.
        // PHP poate returna message_id ca int sau ca String (BIGINT→string)
        // — folosim parser defensiv în loc de un cast direct care plesnea
        // cu "String is not subtype of int?".
        final rawId = r['message_id'];
        final id = rawId is int
            ? rawId
            : (rawId is String ? int.tryParse(rawId) : null)
              ?? DateTime.now().millisecondsSinceEpoch;
        final me = _chat.currentUserId ?? 0;
        if (!_messages.any((x) => x.id == id)) {
          _messages.add(ChatMessage(
            id: id,
            conversationId: widget.conversationId,
            senderId: me,
            senderName: 'Sie',
            senderRole: 'admin',
            isAdmin: true,
            message: text,
            createdAt: DateTime.now(),
          ));
          _lastMessageId = id;
        }
        _scrollToBottom();
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: ${r['message'] ?? 'Senden fehlgeschlagen'}'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      _log.error('mini-panel send failed: $e', tag: 'GLOBAL_CHAT');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
      );
    }
    if (mounted) setState(() => _sending = false);
  }

  Color _avatarColor(String name) {
    const palette = <Color>[
      Color(0xFF1976D2), Color(0xFF388E3C), Color(0xFFD32F2F),
      Color(0xFF7B1FA2), Color(0xFFF57C00), Color(0xFF00838F),
      Color(0xFFC2185B), Color(0xFF5D4037), Color(0xFF455A64),
    ];
    if (name.isEmpty) return Colors.grey;
    var hash = 0;
    for (final c in name.codeUnits) {
      hash = (hash * 31 + c) & 0x7fffffff;
    }
    return palette[hash % palette.length];
  }

  String _initial(String n) => n.trim().isEmpty ? '?' : n.trim()[0].toUpperCase();

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _header(),
          Expanded(child: _body()),
          _input(),
        ]),
      ),
    );
  }

  Widget _header() {
    final c = _avatarColor(widget.senderName);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(color: c, borderRadius: const BorderRadius.vertical(top: Radius.circular(10))),
      child: Row(children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(_initial(widget.senderName), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(
          widget.senderName,
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        )),
        if (widget.onExpand != null) _PlainIconButton(icon: Icons.open_in_full, size: 16, onTap: widget.onExpand!),
        _PlainIconButton(icon: Icons.remove, size: 18, onTap: widget.onMinimize),
        _PlainIconButton(icon: Icons.close, size: 18, onTap: widget.onClose),
      ]),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    if (_messages.isEmpty) {
      return Center(child: Text('Keine Nachrichten', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)));
    }
    return ListView.builder(
      controller: _scrollC,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      itemCount: _messages.length,
      itemBuilder: (_, i) {
        final m = _messages[i];
        final me = _chat.currentUserId;
        final isMe = me != null && m.senderId == me;
        return Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            constraints: const BoxConstraints(maxWidth: 240),
            decoration: BoxDecoration(
              color: isMe ? Colors.blue.shade100 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(m.displayMessage, style: const TextStyle(fontSize: 12)),
              Text(DateFormat('HH:mm').format(m.createdAt),
                  style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
            ]),
          ),
        );
      },
    );
  }

  /// Input este izolat într-un widget separat ca să NU se rebuilduie la
  /// fiecare mesaj primit (rebuild-ul părintelui pierdea focus + cauza
  /// glitch-uri la backspace).
  Widget _input() {
    return _InputArea(
      controller: _inputC,
      sending: _sending,
      onSend: _send,
    );
  }
}

/// Plain clickable icon — fără Material/InkWell hover-splash gri.
class _PlainIconButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;
  const _PlainIconButton({required this.icon, required this.size, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: Colors.white, size: size),
        ),
      ),
    );
  }
}

/// Izolat din ChatMiniPanel ca să nu fie afectat de rebuild-urile de la
/// mesaje noi (care altfel cauzau glitch la backspace).
class _InputArea extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  const _InputArea({required this.controller, required this.sending, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: TextField(
            controller: controller,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Nachricht…',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.grey.shade300)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.blue.shade400)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onSubmitted: (_) => onSend(),
          ),
        ),
        const SizedBox(width: 4),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: sending ? null : onSend,
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: sending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.send, color: Colors.blue.shade600, size: 22),
            ),
          ),
        ),
      ]),
    );
  }
}
