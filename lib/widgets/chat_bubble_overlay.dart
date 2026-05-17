import 'package:flutter/material.dart';

/// One pending conversation rendered as a floating bubble on the dashboard.
class ChatBubbleEntry {
  final int conversationId;
  final String senderName;
  final int unreadCount;
  final String? lastMessagePreview;

  const ChatBubbleEntry({
    required this.conversationId,
    required this.senderName,
    required this.unreadCount,
    this.lastMessagePreview,
  });
}

/// Floating column of Messenger-style chat heads on the right edge of the
/// dashboard. Each bubble shows the first letter of the sender's name + an
/// unread count badge. Tap → opens chat for that conversation directly.
class ChatBubbleOverlay extends StatelessWidget {
  final List<ChatBubbleEntry> entries;
  final ValueChanged<int> onBubbleTap;
  final ValueChanged<int>? onBubbleClose;
  final VoidCallback? onDismiss;

  const ChatBubbleOverlay({
    super.key,
    required this.entries,
    required this.onBubbleTap,
    this.onBubbleClose,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return Positioned(
      right: 16,
      top: 100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final e in entries.take(8))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ChatBubble(
                entry: e,
                onTap: () => onBubbleTap(e.conversationId),
                onClose: onBubbleClose != null ? () => onBubbleClose!(e.conversationId) : null,
              ),
            ),
          if (entries.length > 8)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.grey.shade700,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '+${entries.length - 8}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          if (entries.isNotEmpty && onDismiss != null)
            Material(
              color: Colors.transparent,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onDismiss,
                child: Tooltip(
                  message: 'Alle ausblenden',
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.close, size: 18, color: Colors.grey.shade700),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatBubbleEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  const _ChatBubble({required this.entry, required this.onTap, this.onClose});

  @override
  Widget build(BuildContext context) {
    final initial = entry.senderName.isNotEmpty
        ? entry.senderName.trim()[0].toUpperCase()
        : '?';
    final tooltip = entry.lastMessagePreview != null && entry.lastMessagePreview!.isNotEmpty
        ? '${entry.senderName}\n${entry.lastMessagePreview}'
        : entry.senderName;
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: 0,
            bottom: 0,
            child: Tooltip(
              message: tooltip,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onTap,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _colorForName(entry.senderName),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Text(
                          initial,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (entry.unreadCount > 0)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                            decoration: BoxDecoration(
                              color: Colors.red.shade600,
                              shape: BoxShape.rectangle,
                              borderRadius: BorderRadius.circular(11),
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              entry.unreadCount > 99 ? '99+' : '${entry.unreadCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (onClose != null)
            Positioned(
              left: 0,
              top: 0,
              child: Tooltip(
                message: 'Bubble ausblenden',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onClose,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade800,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.close, size: 12, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Deterministic color per sender — same name → same bubble color.
  Color _colorForName(String name) {
    if (name.isEmpty) return Colors.grey;
    const palette = <Color>[
      Color(0xFF1976D2), Color(0xFF388E3C), Color(0xFFD32F2F),
      Color(0xFF7B1FA2), Color(0xFFF57C00), Color(0xFF00838F),
      Color(0xFFC2185B), Color(0xFF5D4037), Color(0xFF455A64),
    ];
    var hash = 0;
    for (final c in name.codeUnits) {
      hash = (hash * 31 + c) & 0x7fffffff;
    }
    return palette[hash % palette.length];
  }
}
