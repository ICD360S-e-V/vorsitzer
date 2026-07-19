import 'package:flutter/material.dart';

/// A single attachment item in a chat message.
///
/// Tap on the body  → [onOpen]     (in-memory preview / OS open).
/// Tap on the icon  → [onDownload] (Save As… via file_picker portal,
///                                  works inside Flatpak sandbox).
class ChatAttachmentItem extends StatelessWidget {
  final Map<String, dynamic> attachment;
  final bool isOwn;
  final Function(Map<String, dynamic>) onDownload;
  final Function(Map<String, dynamic>)? onOpen;

  /// Save this attachment to the owning member's permanent 1 GB cloud.
  /// When null the cloud button is hidden (e.g. non-admin contexts).
  final Function(Map<String, dynamic>)? onSaveToCloud;

  /// Whether this attachment is already stored in the member's cloud
  /// (renders ☁✓ instead of the upload icon).
  final bool savedToCloud;

  const ChatAttachmentItem({
    super.key,
    required this.attachment,
    required this.isOwn,
    required this.onDownload,
    this.onOpen,
    this.onSaveToCloud,
    this.savedToCloud = false,
  });

  @override
  Widget build(BuildContext context) {
    final filename = attachment['filename'] ?? 'Datei';
    final extension = attachment['extension'] ?? '';
    final size = attachment['size'] ?? 0;

    final (icon, iconColor) = _getIconForExtension(extension);

    return InkWell(
      onTap: () => (onOpen ?? onDownload)(attachment),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isOwn ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    filename,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isOwn ? Colors.white : Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _formatFileSize(size),
                    style: TextStyle(
                      fontSize: 10,
                      color: isOwn ? Colors.white70 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            if (onSaveToCloud != null)
              InkWell(
                onTap: savedToCloud ? null : () => onSaveToCloud!(attachment),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    savedToCloud ? Icons.cloud_done : Icons.cloud_upload_outlined,
                    size: 18,
                    color: savedToCloud
                        ? Colors.green.shade400
                        : (isOwn ? Colors.white : Colors.indigo.shade600),
                  ),
                ),
              ),
            InkWell(
              onTap: () => onDownload(attachment),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.download,
                  size: 18,
                  color: isOwn ? Colors.white : Colors.indigo.shade600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  (IconData, Color) _getIconForExtension(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return (Icons.picture_as_pdf, Colors.red);
      case 'png':
      case 'jpg':
      case 'jpeg':
        return (Icons.image, Colors.blue);
      case 'txt':
        return (Icons.description, Colors.grey);
      default:
        return (Icons.insert_drive_file, Colors.grey);
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
