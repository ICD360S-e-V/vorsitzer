import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/chat_service.dart';

/// Floating mini chat popup anchored to the bottom-right of the dashboard.
/// Opened by tapping a chat bubble — shows the conversation inline without
/// taking the user to the full admin chat dialog.
class ChatBubblePopup extends StatefulWidget {
  final int conversationId;
  final String memberName;
  final String currentMitgliedernummer;
  final String currentUserName;
  final VoidCallback onClose;
  final VoidCallback? onOpenFullChat;

  const ChatBubblePopup({
    super.key,
    required this.conversationId,
    required this.memberName,
    required this.currentMitgliedernummer,
    required this.currentUserName,
    required this.onClose,
    this.onOpenFullChat,
  });

  @override
  State<ChatBubblePopup> createState() => _ChatBubblePopupState();
}

class _ChatBubblePopupState extends State<ChatBubblePopup> {
  final _apiService = ApiService();
  final _chatService = ChatService();
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  StreamSubscription? _msgSub;
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _chatService.joinConversation(widget.conversationId);
    _loadMessages();
    _msgSub = _chatService.messageStream.listen(_onMessage);
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onMessage(ChatMessage m) {
    if (m.conversationId != widget.conversationId || !mounted) return;
    // Skip echoes of our own outbound messages (we add them locally on send).
    if (m.senderName == widget.currentUserName) return;
    setState(() {
      _messages.add({
        'id': m.id,
        'message': m.message,
        'sender_name': m.senderName,
        'is_own': false,
        'created_at': m.createdAt.toIso8601String(),
      });
    });
    _scrollToBottom();
  }

  Future<void> _loadMessages() async {
    try {
      final result = await _apiService.getChatMessages(
        widget.conversationId,
        widget.currentMitgliedernummer,
      );
      if (!mounted) return;
      if (result['success'] == true) {
        final data = result['data'] as Map<String, dynamic>? ?? result;
        final list = List<Map<String, dynamic>>.from(data['messages'] ?? result['messages'] ?? []);
        setState(() {
          _messages = list;
          _loading = false;
        });
        _scrollToBottom();
        // Auto-mark unread non-own messages as read — opening the bubble counts as "seen"
        _markUnreadAsRead();
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markUnreadAsRead() async {
    final unreadIds = _messages
        .where((m) =>
            m['is_own'] != true &&
            m['status'] != 'read' &&
            m['is_read'] != true &&
            m['deleted_at'] == null)
        .map((m) => m['id'])
        .whereType<int>()
        .where((id) => id > 0)
        .toList();
    if (unreadIds.isEmpty) return;
    try {
      await _apiService.markMessagesRead(
        conversationId: widget.conversationId,
        mitgliedernummer: widget.currentMitgliedernummer,
        status: 'read',
        messageIds: unreadIds,
      );
      if (!mounted) return;
      setState(() {
        for (final m in _messages) {
          if (unreadIds.contains(m['id'])) {
            m['status'] = 'read';
            m['is_read'] = true;
            m['read_at'] ??= DateTime.now().toIso8601String();
          }
        }
      });
    } catch (_) {
      // Silent — server is source of truth, will retry next open
    }
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);

    // Optimistic add — show immediately, sync with backend in background.
    final localId = -DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _messages.add({
        'id': localId,
        'message': text,
        'sender_name': widget.currentUserName,
        'is_own': true,
        'created_at': DateTime.now().toIso8601String(),
      });
    });
    _inputController.clear();
    _scrollToBottom();

    try {
      await _apiService.sendChatMessage(
        widget.conversationId,
        widget.currentMitgliedernummer,
        text,
      );
    } catch (_) {
      // Silent — message stays optimistically rendered; user can resend if needed.
    } finally {
      if (mounted) setState(() => _sending = false);
      _focusNode.requestFocus();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 360,
        height: 480,
        child: Column(
          children: [
            _buildHeader(),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildMessageList(),
            ),
            const Divider(height: 1),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.indigo.shade700,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.white24,
            child: Text(
              widget.memberName.isNotEmpty ? widget.memberName.trim()[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.memberName,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.onOpenFullChat != null)
            IconButton(
              icon: const Icon(Icons.open_in_full, color: Colors.white70, size: 18),
              tooltip: 'Vollbild öffnen',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: widget.onOpenFullChat,
            ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 20),
            tooltip: 'Schließen',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    if (_messages.isEmpty) {
      return Center(
        child: Text(
          'Noch keine Nachrichten',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      itemCount: _messages.length,
      itemBuilder: (_, i) {
        final m = _messages[i];
        final isOwn = m['is_own'] == true;
        return Align(
          alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            constraints: const BoxConstraints(maxWidth: 260),
            decoration: BoxDecoration(
              color: isOwn ? Colors.indigo.shade600 : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              (m['message'] ?? '').toString(),
              style: TextStyle(
                color: isOwn ? Colors.white : Colors.black87,
                fontSize: 13,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              focusNode: _focusNode,
              autofocus: true,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: 'Nachricht…',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: _sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.send, color: Colors.indigo.shade700),
            onPressed: _sending ? null : _send,
            tooltip: 'Senden',
          ),
        ],
      ),
    );
  }
}
