import 'package:flutter/material.dart';
import '../utils/file_picker_helper.dart';

/// Chat input area with attachment button and send button
/// 🆕 URGENT NOTIFICATIONS (2026-02-11): Added urgent checkbox for admins
class ChatInputArea extends StatelessWidget {
  final TextEditingController controller;
  final bool isSending;
  final bool isUploading;
  final VoidCallback onSend;
  final VoidCallback onPickFiles;
  final VoidCallback? onFocus;
  final String hintText;

  // 🆕 URGENT support (only visible for admins)
  final bool? isUrgent;
  final ValueChanged<bool>? onUrgentChanged;
  final bool showUrgentCheckbox;

  const ChatInputArea({
    super.key,
    required this.controller,
    required this.isSending,
    required this.isUploading,
    required this.onSend,
    required this.onPickFiles,
    this.onFocus,
    this.hintText = 'Nachricht eingeben...',
    this.isUrgent,
    this.onUrgentChanged,
    this.showUrgentCheckbox = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          // Attachment button
          IconButton(
            icon: isUploading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.attach_file, color: Color(0xFF1a1a2e)),
            onPressed: isUploading ? null : onPickFiles,
            tooltip: 'Dateien anhängen (max. 10, 100MB)',
          ),
          Expanded(
            child: TextField(
              controller: controller,
              onSubmitted: (_) => onSend(),
              onTap: onFocus,
              decoration: InputDecoration(
                hintText: hintText,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),

          // 🆕 URGENT checkbox (only for admins)
          if (showUrgentCheckbox && onUrgentChanged != null) ...[
            const SizedBox(width: 4),
            Tooltip(
              message: 'Als dringende Nachricht markieren (Full-Screen Alert)',
              child: InkWell(
                onTap: () => onUrgentChanged!(!(isUrgent ?? false)),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: (isUrgent ?? false) ? Colors.red.shade50 : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: (isUrgent ?? false) ? Colors.red : Colors.grey.shade300,
                      width: (isUrgent ?? false) ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.warning,
                        color: (isUrgent ?? false) ? Colors.red : Colors.grey,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'URGENT',
                        style: TextStyle(
                          color: (isUrgent ?? false) ? Colors.red : Colors.grey,
                          fontWeight: (isUrgent ?? false) ? FontWeight.bold : FontWeight.normal,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: const Color(0xFF1a1a2e),
            child: IconButton(
              icon: isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.send, color: Colors.white, size: 20),
              onPressed: isSending ? null : onSend,
            ),
          ),
        ],
      ),
    );
  }
}

/// Closed conversation indicator
class ClosedConversationIndicator extends StatelessWidget {
  const ClosedConversationIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'Diese Konversation wurde geschlossen',
        style: TextStyle(color: Colors.grey),
      ),
    );
  }
}
