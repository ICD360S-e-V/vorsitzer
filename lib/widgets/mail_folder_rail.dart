import 'package:flutter/material.dart';
import '../models/mail_models.dart';

/// Deutsche Beschriftung + Symbol für die IMAP-Ordner des Postfachs.
class MailBoxInfo {
  final String box;
  final String label;
  final IconData icon;
  final IconData activeIcon;

  const MailBoxInfo(this.box, this.label, this.icon, this.activeIcon);

  static const List<MailBoxInfo> all = [
    MailBoxInfo('INBOX', 'Eingang', Icons.inbox_outlined, Icons.inbox),
    MailBoxInfo('Sent', 'Ausgang', Icons.send_outlined, Icons.send),
    MailBoxInfo('Drafts', 'Entwürfe', Icons.edit_note_outlined, Icons.edit_note),
    MailBoxInfo('Junk', 'Spam', Icons.report_gmailerrorred_outlined, Icons.report),
    MailBoxInfo('Trash', 'Papierkorb', Icons.delete_outline, Icons.delete),
    MailBoxInfo('Archive', 'Archiv', Icons.archive_outlined, Icons.archive),
  ];

  static MailBoxInfo forBox(String box) => all.firstWhere(
        (b) => b.box == box,
        orElse: () => all.first,
      );

  static String labelFor(String box) => forBox(box).label;
}

/// Ordnerliste links neben dem Postfach.
///
/// Auf breiten Fenstern dauerhaft sichtbar, auf schmalen als Drawer.
class MailFolderRail extends StatelessWidget {
  final String selectedBox;
  final Map<String, MailFolder> folders;
  final String mailboxAddress;
  final ValueChanged<String> onSelect;
  final VoidCallback onCompose;
  final VoidCallback? onOpenSignature;

  /// Im Drawer wird nach der Auswahl geschlossen und ein Header angezeigt.
  final bool isDrawer;

  const MailFolderRail({
    super.key,
    required this.selectedBox,
    required this.folders,
    required this.mailboxAddress,
    required this.onSelect,
    required this.onCompose,
    this.onOpenSignature,
    this.isDrawer = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Only offer folders that exist server-side; Eingang/Ausgang always show so
    // the rail never looks broken while the counts are still loading.
    final visible = MailBoxInfo.all.where((b) {
      if (b.box == 'INBOX' || b.box == 'Sent') return true;
      return folders.containsKey(b.box);
    }).toList();

    return Container(
      width: isDrawer ? null : 232,
      color: isDrawer ? null : cs.surfaceContainerLow,
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, cs),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: FilledButton.icon(
                onPressed: () {
                  if (isDrawer) Navigator.of(context).pop();
                  onCompose();
                },
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Neue E-Mail'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(42),
                  alignment: Alignment.center,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final b in visible) _tile(context, cs, b),
                ],
              ),
            ),
            if (onOpenSignature != null) ...[
              const Divider(height: 1),
              ListTile(
                dense: true,
                leading: const Icon(Icons.draw_outlined, size: 20),
                title: const Text('Signatur', style: TextStyle(fontSize: 13.5)),
                onTap: () {
                  if (isDrawer) Navigator.of(context).pop();
                  onOpenSignature!();
                },
              ),
            ],
],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, ColorScheme cs) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, isDrawer ? 20 : 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.alternate_email, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              const Text('Postfach',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            mailboxAddress,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, ColorScheme cs, MailBoxInfo b) {
    final selected = b.box == selectedBox;
    final f = folders[b.box];
    // Unread matters in Eingang and Spam; elsewhere the total is the useful number.
    final showUnseen = (b.box == 'INBOX' || b.box == 'Junk') && (f?.unseen ?? 0) > 0;
    final trailingText = showUnseen ? '${f!.unseen}' : (f != null && f.total > 0 ? '${f.total}' : '');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected ? cs.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            if (isDrawer) Navigator.of(context).pop();
            onSelect(b.box);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(selected ? b.activeIcon : b.icon,
                    size: 20,
                    color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    b.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? cs.onSecondaryContainer : cs.onSurface,
                    ),
                  ),
                ),
                if (trailingText.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: showUnseen ? cs.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      trailingText,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: showUnseen ? FontWeight.w700 : FontWeight.w500,
                        color: showUnseen ? cs.onPrimary : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
