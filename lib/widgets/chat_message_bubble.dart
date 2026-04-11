import 'dart:async';
import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import 'chat_attachment_item.dart';

/// A chat message bubble with privacy masking.
/// Non-own messages are hidden by default (★★★). Tap the lock icon
/// to reveal for 10 seconds, then auto-hides again.
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
  bool _isRevealed = false;
  Timer? _revealTimer;
  int _revealCountdown = 0;
  Timer? _countdownTicker;

  void _toggleReveal() {
    if (_isRevealed) {
      // Manual re-hide
      _revealTimer?.cancel();
      _countdownTicker?.cancel();
      setState(() {
        _isRevealed = false;
        _revealCountdown = 0;
      });
    } else {
      // Reveal for 10 seconds
      setState(() {
        _isRevealed = true;
        _revealCountdown = 10;
      });

      _countdownTicker?.cancel();
      _countdownTicker = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) { t.cancel(); return; }
        setState(() => _revealCountdown--);
        if (_revealCountdown <= 0) t.cancel();
      });

      _revealTimer?.cancel();
      _revealTimer = Timer(const Duration(seconds: 10), () {
        if (mounted) {
          setState(() {
            _isRevealed = false;
            _revealCountdown = 0;
          });
        }
      });
    }
  }

  String _maskText(String text) {
    return text.replaceAllMapped(RegExp(r'\S+'), (match) {
      return '★' * min(match.group(0)!.length, 12);
    });
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    _countdownTicker?.cancel();
    super.dispose();
  }

  // Responsive spacing helper
  double _getResponsiveSpacing(BuildContext context, double baseSize) {
    final width = MediaQuery.of(context).size.width;
    if (width < 360) return baseSize * 0.5;
    if (width < 400) return baseSize * 0.75;
    return baseSize;
  }

  @override
  Widget build(BuildContext context) {
    final attachments = List<Map<String, dynamic>>.from(
        widget.message['attachments'] ?? []);
    final status = widget.message['status'] ?? 'sent';
    final messageText = widget.message['message'] ?? '';
    final hasTextMessage = messageText.toString().isNotEmpty &&
        !messageText.toString().startsWith('[');

    // ALL messages are masked unless actively revealed
    final showMasked = !_isRevealed;

    return Align(
      alignment: widget.isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          bottom: _getResponsiveSpacing(context, 8),
          left: widget.isOwn ? _getResponsiveSpacing(context, 50) : 0,
          right: widget.isOwn ? 0 : _getResponsiveSpacing(context, 50),
        ),
        padding: EdgeInsets.all(_getResponsiveSpacing(context, 10)),
        decoration: BoxDecoration(
          color: showMasked
              ? (widget.isOwn ? const Color(0xFF12121f) : Colors.grey.shade200)
              : (widget.isOwn ? const Color(0xFF1a1a2e) : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: showMasked
              ? Border.all(
                  color: widget.isOwn
                      ? Colors.grey.shade700
                      : Colors.grey.shade300,
                  width: 0.5)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sender name (non-own) or lock row (own)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!widget.isOwn)
                    Text(
                      widget.message['sender_name'] ??
                          AppLocalizations.of(context)!.member,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  if (!widget.isOwn) const SizedBox(width: 6),
                  // Lock/unlock button for ALL messages
                  _buildLockButton(),
                ],
              ),
            ),
            // Message text
            if (hasTextMessage)
              showMasked
                  ? Text(
                      _maskText(messageText),
                      style: TextStyle(
                        color: widget.isOwn
                            ? Colors.white24
                            : Colors.grey.shade400,
                        letterSpacing: 1.2,
                        fontSize: 14,
                      ),
                    )
                  : _buildLinkifiedText(messageText, widget.isOwn),
            // Attachments
            if (attachments.isNotEmpty) ...[
              if (hasTextMessage) const SizedBox(height: 8),
              if (showMasked)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.attach_file,
                        size: 14,
                        color: widget.isOwn
                            ? Colors.white24
                            : Colors.grey.shade400),
                    const SizedBox(width: 4),
                    Text(
                      '${attachments.length} ${attachments.length == 1 ? 'Anhang' : 'Anhänge'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.isOwn
                            ? Colors.white24
                            : Colors.grey.shade400,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                )
              else
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
                      color:
                          widget.isOwn ? Colors.white70 : Colors.grey.shade500,
                    ),
                  ),
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
    );
  }

  Widget _buildLockButton() {
    final isOwn = widget.isOwn;

    if (_isRevealed) {
      // Unlocked state with countdown
      return InkWell(
        onTap: _toggleReveal,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isOwn ? Colors.green.shade900 : Colors.green.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isOwn ? Colors.green.shade700 : Colors.green.shade300,
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_open,
                  size: 12,
                  color: isOwn ? Colors.green.shade300 : Colors.green.shade700),
              const SizedBox(width: 3),
              Text(
                '${_revealCountdown}s',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: _revealCountdown <= 3
                      ? Colors.red.shade400
                      : isOwn
                          ? Colors.green.shade300
                          : Colors.green.shade700,
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      // Locked state
      return InkWell(
        onTap: _toggleReveal,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isOwn ? Colors.white12 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isOwn ? Colors.white24 : Colors.grey.shade300,
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline,
                  size: 12,
                  color: isOwn ? Colors.white60 : Colors.grey.shade600),
              const SizedBox(width: 3),
              Text(
                'Lesen',
                style: TextStyle(
                  fontSize: 10,
                  color: isOwn ? Colors.white60 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  static final _urlRegex = RegExp(
    r'https?://[^\s<>\"\)]+',
    caseSensitive: false,
  );

  Widget _buildLinkifiedText(String text, bool isOwn) {
    final matches = _urlRegex.allMatches(text).toList();
    if (matches.isEmpty) {
      return Text(text,
          style: TextStyle(color: isOwn ? Colors.white : Colors.black87));
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
        recognizer: TapGestureRecognizer()
          ..onTap = () => launchUrl(Uri.parse(url),
              mode: LaunchMode.externalApplication),
      ));
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return RichText(
      text: TextSpan(
        style: TextStyle(
            color: isOwn ? Colors.white : Colors.black87, fontSize: 14),
        children: spans,
      ),
    );
  }

  Widget _buildReadReceipt(String status) {
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
            Icon(Icons.done_all,
                size: 14, color: Colors.white.withValues(alpha: 0.7)),
          ],
        );
      case 'sent':
      default:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.done,
                size: 14, color: Colors.white.withValues(alpha: 0.7)),
          ],
        );
    }
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
