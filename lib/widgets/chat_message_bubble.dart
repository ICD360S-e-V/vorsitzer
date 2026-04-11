import 'dart:async';
import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import 'chat_attachment_item.dart';

/// A chat message bubble with auto-masking privacy feature.
/// Non-own messages auto-mask with stars after 10 seconds of being visible.
/// Swipe right to temporarily reveal a masked message.
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

class _ChatMessageBubbleState extends State<ChatMessageBubble>
    with SingleTickerProviderStateMixin {
  bool _isMasked = false;
  bool _isRevealed = false;
  Timer? _autoMaskTimer;
  Timer? _revealTimer;
  late AnimationController _countdownController;
  int _countdownSeconds = 10;
  Timer? _countdownTickTimer;

  // Swipe detection
  double _dragStartX = 0;

  @override
  void initState() {
    super.initState();
    _countdownController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );

    // Only auto-mask non-own messages (member messages)
    if (!widget.isOwn) {
      _startAutoMaskCountdown();
    }
  }

  void _startAutoMaskCountdown() {
    _countdownSeconds = 10;
    _countdownController.forward(from: 0);

    _countdownTickTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _countdownSeconds--;
      });
      if (_countdownSeconds <= 0) {
        timer.cancel();
      }
    });

    _autoMaskTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) {
        setState(() {
          _isMasked = true;
          _isRevealed = false;
        });
      }
    });
  }

  void _onSwipeRight() {
    if (!_isMasked) return; // Not masked yet, nothing to toggle

    if (!_isRevealed) {
      // Reveal temporarily
      setState(() => _isRevealed = true);
      _revealTimer?.cancel();
      _revealTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _isRevealed = false);
      });
    } else {
      // Manual re-mask
      _revealTimer?.cancel();
      setState(() => _isRevealed = false);
    }
  }

  String _maskText(String text) {
    // Replace each word with stars of the same length
    return text.replaceAllMapped(RegExp(r'\S+'), (match) {
      return '★' * min(match.group(0)!.length, 12);
    });
  }

  @override
  void dispose() {
    _autoMaskTimer?.cancel();
    _revealTimer?.cancel();
    _countdownTickTimer?.cancel();
    _countdownController.dispose();
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

    final showMasked = !widget.isOwn && _isMasked && !_isRevealed;
    final showCountdown = !widget.isOwn && !_isMasked && _countdownSeconds > 0;

    final bubble = Container(
      margin: EdgeInsets.only(
        bottom: _getResponsiveSpacing(context, 8),
        left: widget.isOwn ? _getResponsiveSpacing(context, 50) : 0,
        right: widget.isOwn ? 0 : _getResponsiveSpacing(context, 50),
      ),
      padding: EdgeInsets.all(_getResponsiveSpacing(context, 10)),
      decoration: BoxDecoration(
        color: widget.isOwn
            ? const Color(0xFF1a1a2e)
            : showMasked
                ? Colors.grey.shade300
                : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: showMasked
            ? Border.all(color: Colors.grey.shade400, width: 0.5)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sender name (only for non-own messages)
          if (!widget.isOwn)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.message['sender_name'] ??
                        AppLocalizations.of(context)!.member,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      color: Colors.blue.shade700,
                    ),
                  ),
                  // Countdown badge
                  if (showCountdown) ...[
                    const SizedBox(width: 6),
                    _buildCountdownBadge(),
                  ],
                  // Lock icon when masked
                  if (showMasked) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.lock_outline,
                        size: 12, color: Colors.grey.shade600),
                    const SizedBox(width: 2),
                    Text(
                      '← swipe',
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.grey.shade500,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          // Message text (masked or clear)
          if (hasTextMessage)
            showMasked
                ? Text(
                    _maskText(messageText),
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      letterSpacing: 1.5,
                      fontSize: 14,
                    ),
                  )
                : _buildLinkifiedText(messageText, widget.isOwn),
          // Attachments (also masked when text is masked)
          if (attachments.isNotEmpty) ...[
            if (hasTextMessage) const SizedBox(height: 8),
            if (showMasked)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.attach_file,
                      size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text(
                    '${attachments.length} ${attachments.length == 1 ? 'Anhang' : 'Anhänge'} (ausgeblendet)',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
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
                    color: widget.isOwn
                        ? Colors.white70
                        : Colors.grey.shade500,
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
    );

    // Wrap non-own messages with swipe gesture detector
    if (!widget.isOwn) {
      return Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          onHorizontalDragStart: (details) {
            _dragStartX = details.localPosition.dx;
          },
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            // Swipe right detection (positive velocity = right direction)
            if (velocity > 200) {
              _onSwipeRight();
            }
          },
          child: bubble,
        ),
      );
    }

    return Align(
      alignment: Alignment.centerRight,
      child: bubble,
    );
  }

  Widget _buildCountdownBadge() {
    return AnimatedBuilder(
      animation: _countdownController,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: _countdownSeconds <= 3
                ? Colors.red.shade100
                : Colors.orange.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.timer_outlined,
                size: 10,
                color: _countdownSeconds <= 3
                    ? Colors.red.shade700
                    : Colors.orange.shade700,
              ),
              const SizedBox(width: 2),
              Text(
                '${_countdownSeconds}s',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: _countdownSeconds <= 3
                      ? Colors.red.shade700
                      : Colors.orange.shade700,
                ),
              ),
            ],
          ),
        );
      },
    );
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
