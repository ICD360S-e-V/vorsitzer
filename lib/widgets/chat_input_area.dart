import 'dart:io';

import 'package:flutter/material.dart';

import '../utils/clipboard_import.dart';
import 'chat_pending_attachments.dart';
import 'eingabe_tasten.dart';
import 'wort_vorschlaege.dart';
import 'paste_image_detector.dart';
import '../utils/app_farben.dart';

/// Chat input area with attachment button and send button
/// 🆕 URGENT NOTIFICATIONS (2026-02-11): Added urgent checkbox for admins
class ChatInputArea extends StatelessWidget {
  final TextEditingController controller;
  final bool isSending;
  final bool isUploading;
  final VoidCallback onSend;
  final VoidCallback onPickFiles;
  final VoidCallback? onFocus;
  final ValueChanged<String>? onChanged;
  final String hintText;

  // 🆕 URGENT support (only visible for admins)
  final bool? isUrgent;
  final ValueChanged<bool>? onUrgentChanged;
  final bool showUrgentCheckbox;

  // Hides the paperclip on anonymous-visitor chats — operators must not
  // ship documents to a stateless visitor (GDPR + accidental leak risk).
  final bool disableAttachments;

  // Strg+V bzw. Bild aus der Tastatur. Ohne Handler bleibt beides aus.
  final VoidCallback? onPasteImage;
  final ValueChanged<KeyboardInsertedContent>? onKeyboardContent;

  // Vorgemerkte Anhänge, die mit der nächsten Nachricht rausgehen.
  final List<File> pendingFiles;
  final ValueChanged<File>? onRemovePending;

  const ChatInputArea({
    super.key,
    required this.controller,
    required this.isSending,
    required this.isUploading,
    required this.onSend,
    required this.onPickFiles,
    this.onFocus,
    this.onChanged,
    this.hintText = 'Nachricht eingeben...',
    this.isUrgent,
    this.onUrgentChanged,
    this.showUrgentCheckbox = false,
    this.disableAttachments = false,
    this.onPasteImage,
    this.onKeyboardContent,
    this.pendingFiles = const [],
    this.onRemovePending,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (onRemovePending != null)
            ChatPendingAttachments(
              files: pendingFiles,
              isUploading: isUploading,
              onRemove: onRemovePending!,
            ),
          // ⚠️ Die Vorschlagsleiste umschließt die ganze Zeile, nicht nur
          // das Textfeld. Sonst käme der Sendeknopf nicht an
          // [vorDemSenden] vorbei — und genau über ihn geht auf dem
          // Telefon fast jede Nachricht raus.
          WortVorschlaege(
            controller: controller,
            bauen: (vorDemSenden) => _buildRow(context, vorDemSenden),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, VoidCallback vorDemSenden) {
    void senden() {
      vorDemSenden();
      onSend();
    }

    // Büroklammer, URGENT-Chip und Sendeknopf sind rund 195 dp fest. Auf einem
    // Telefon blieben dem Textfeld damit knapp 180 dp. Der Chip trägt seine
    // Beschriftung deshalb nur, wo Platz ist — das Warndreieck bleibt immer.
    final schmal = MediaQuery.of(context).size.width < 500;

    return Row(
        children: [
          // Attachment button — hidden entirely for anonymous chats
          if (!disableAttachments)
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
            child: PasteImageDetector(
              enabled: onPasteImage != null,
              onPaste: onPasteImage ?? () {},
              child: EingabeTasten(
                onSend: senden,
                bauen: (abgesichert) => TextField(
              controller: controller,
              // BEIDE Wege gehen auf dieselbe abgesicherte Funktion: die
              // Eingabetaste einer echten Tastatur und der Senden-Knopf der
              // Bildschirmtastatur. [EingabeTasten] lässt einen doppelten
              // Aufruf fallen, also kann nichts zweimal rausgehen.
              onSubmitted: (_) => abgesichert(),
              onTap: onFocus,
              onChanged: onChanged,
              contentInsertionConfiguration: onKeyboardContent == null
                  ? null
                  : ContentInsertionConfiguration(
                      allowedMimeTypes: ClipboardImport.keyboardMimeTypes,
                      onContentInserted: onKeyboardContent!,
                    ),
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
                    color: (isUrgent ?? false) ? F.h(Colors.red, 50) : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: (isUrgent ?? false) ? Colors.red : F.h(Colors.grey, 300),
                      width: (isUrgent ?? false) ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.warning,
                        color: (isUrgent ?? false) ? Colors.red : F.h(Colors.grey, 500),
                        size: 18,
                      ),
                      if (!schmal) ...[
                        const SizedBox(width: 4),
                        Text(
                          'URGENT',
                          style: TextStyle(
                            color: (isUrgent ?? false) ? Colors.red : F.h(Colors.grey, 500),
                            fontWeight: (isUrgent ?? false) ? FontWeight.bold : FontWeight.normal,
                            fontSize: 11,
                          ),
                        ),
                      ],
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
              onPressed: isSending ? null : senden,
            ),
          ),
        ],
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
        color: F.h(Colors.grey, 200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Diese Konversation wurde geschlossen',
        style: TextStyle(color: F.h(Colors.grey, 500)),
      ),
    );
  }
}
