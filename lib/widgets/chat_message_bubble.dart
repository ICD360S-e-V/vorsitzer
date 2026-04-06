import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/clipboard_helper.dart';
import 'chat_attachment_item.dart';

/// A chat message bubble with optional attachments
class ChatMessageBubble extends StatefulWidget {
  final Map<String, dynamic> message;
  final bool isOwn;
  final Function(Map<String, dynamic>) onDownloadAttachment;

  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.isOwn,
    required this.onDownloadAttachment,
  });

  @override
  State<ChatMessageBubble> createState() => _ChatMessageBubbleState();
}

class _ChatMessageBubbleState extends State<ChatMessageBubble> {
  bool _showCopied = false;
  bool _isHidden = false;
  int _tapCount = 0;
  DateTime? _lastTapTime;

  void _copyMessage(String text) {
    ClipboardHelper.copy(context, text, 'Nachricht');
    setState(() => _showCopied = true);
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) setState(() => _showCopied = false);
    });
  }

  void _handleTap() {
    final now = DateTime.now();
    if (_lastTapTime != null && now.difference(_lastTapTime!).inMilliseconds < 400) {
      _tapCount++;
    } else {
      _tapCount = 1;
    }
    _lastTapTime = now;

    // Triple tap = hide/show message
    if (_tapCount >= 3) {
      setState(() => _isHidden = !_isHidden);
      _tapCount = 0;
    }
    // Double tap = copy (handled after short delay to not conflict with triple)
    else if (_tapCount == 2) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (_tapCount == 2) {
          final messageText = widget.message['message'] ?? '';
          if (messageText.toString().isNotEmpty && !messageText.toString().startsWith('[')) {
            _copyMessage(messageText);
          }
          _tapCount = 0;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final attachments = List<Map<String, dynamic>>.from(widget.message['attachments'] ?? []);
    final status = widget.message['status'] ?? 'sent';
    final messageText = widget.message['message'] ?? '';
    final hasTextMessage = messageText.toString().isNotEmpty &&
                           !messageText.toString().startsWith('[');

    // 🆕 URGENT message support
    final isUrgent = widget.message['is_urgent'] == true || widget.message['is_urgent'] == 1;

    // Generate stars based on message length
    final msgLen = messageText?.toString().length ?? 0;
    final hiddenText = _isHidden ? '★' * (msgLen.clamp(3, 20)) : messageText;

    return Align(
      alignment: widget.isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: hasTextMessage ? _handleTap : null,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              margin: EdgeInsets.only(
                bottom: 8,
                left: widget.isOwn ? 50 : 0,
                right: widget.isOwn ? 0 : 50,
              ),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                // 🆕 Red background for urgent messages
                color: isUrgent
                    ? (widget.isOwn ? Colors.red.shade900 : Colors.red.shade50)
                    : (widget.isOwn ? const Color(0xFF1a1a2e) : Colors.white),
                // 🆕 Red border for urgent messages
                border: isUrgent ? Border.all(color: Colors.red, width: 2) : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 🆕 URGENT badge (shows for all urgent messages)
                  if (isUrgent)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.warning, color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text(
                              'DRINGEND',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Sender name (only for non-own messages)
                  if (!widget.isOwn)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        widget.message['sender_name'] ?? 'Benutzer',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          color: isUrgent ? Colors.red.shade900 : Colors.blue.shade700,
                        ),
                      ),
                    ),
                  // Message text (hidden = stars, links clickable)
                  if (hasTextMessage)
                    _isHidden
                        ? Text(
                            hiddenText,
                            style: TextStyle(
                              color: widget.isOwn ? Colors.white38 : Colors.black38,
                              letterSpacing: 2,
                            ),
                          )
                        : _buildLinkifiedText(hiddenText.toString(), widget.isOwn),
                  // Translation indicator
                  if (widget.message['is_translated'] == true && !_isHidden)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.translate,
                            size: 10,
                            color: widget.isOwn ? Colors.white54 : Colors.grey.shade400,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'Übersetzt',
                            style: TextStyle(
                              fontSize: 9,
                              fontStyle: FontStyle.italic,
                              color: widget.isOwn ? Colors.white54 : Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Attachments
                  if (attachments.isNotEmpty) ...[
                    if (hasTextMessage) const SizedBox(height: 8),
                    ...attachments.map((att) => ChatAttachmentItem(
                      attachment: att,
                      isOwn: widget.isOwn,
                      onDownload: widget.onDownloadAttachment,
                    )),
                  ],
                  // Time and read receipt
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatTime(widget.message['created_at']),
                          style: TextStyle(
                            fontSize: 10,
                            color: widget.isOwn ? Colors.white70 : Colors.grey.shade500,
                          ),
                        ),
                        // Read receipt checkmarks (only for own messages)
                        if (widget.isOwn) ...[
                          const SizedBox(width: 4),
                          _buildReadReceipt(status),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // "Kopiert!" tooltip - appears briefly after double-click
            if (_showCopied)
              Positioned(
                top: -25,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.shade700,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Kopiert!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadReceipt(String status) {
    // WhatsApp style: ✓ = sent, ✓✓ = delivered, ✓✓ blue = read
    switch (status) {
      case 'read':
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.done_all, size: 14, color: Colors.lightBlueAccent),
          ],
        );
      case 'delivered':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.done_all, size: 14, color: Colors.white.withValues(alpha: 0.7)),
          ],
        );
      case 'sent':
      default:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.done, size: 14, color: Colors.white.withValues(alpha: 0.7)),
          ],
        );
    }
  }

  static final _urlRegex = RegExp(r'https?://[^\s<>\"\)]+', caseSensitive: false);

  Widget _buildLinkifiedText(String text, bool isOwn) {
    final matches = _urlRegex.allMatches(text).toList();
    if (matches.isEmpty) {
      return Text(text, style: TextStyle(color: isOwn ? Colors.white : Colors.black87));
    }
    final spans = <TextSpan>[];
    int lastEnd = 0;
    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      final url = match.group(0)!;
      spans.add(TextSpan(
        text: url,
        style: TextStyle(
          color: isOwn ? Colors.lightBlueAccent : Colors.blue.shade700,
          decoration: TextDecoration.underline,
        ),
        recognizer: TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      ));
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }
    return RichText(
      text: TextSpan(
        style: TextStyle(color: isOwn ? Colors.white : Colors.black87, fontSize: 14),
        children: spans,
      ),
    );
  }

  String _formatTime(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final messageDate = DateTime(date.year, date.month, date.day);

      if (messageDate == today) {
        return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      } else {
        return '${date.day}.${date.month}. ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      return '';
    }
  }
}
