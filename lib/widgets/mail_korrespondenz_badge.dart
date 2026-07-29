import 'package:flutter/material.dart';

/// Marks a mail that has been copied into one of the Korrespondenz archives.
///
/// Mail addressed to elster@icd360s.de lands in Finanzamt ▸ Korrespondenz and
/// mail to github@icd360s.de in GitHub ▸ Korrespondenz, each filed by its own
/// cron job. Without a visible marker there is no way to tell an archived mail
/// from one the importer has not seen yet — which leads to filing the same
/// letter twice, or worse, assuming a Bescheid was archived when it was not.
///
/// The original always stays in the mailbox; this only says a copy exists.
class MailKorrespondenzBadge extends StatelessWidget {
  /// What the status endpoint returned for this message: one entry per archive
  /// holding it, `{bereich, korrespondenz_id, datum, dateien}`.
  ///
  /// A list rather than a single entry because the archives are separate tables
  /// with separate importers, and nothing stops a message from matching two of
  /// them. Empty or null means "not archived".
  final List<Map<String, dynamic>>? eintraege;

  /// Compact form for the list row; the long form is for the opened message.
  final bool compact;

  const MailKorrespondenzBadge({
    super.key,
    required this.eintraege,
    this.compact = true,
  });

  /// bereich → how it is shown. An archive added server-side but not listed
  /// here still gets a badge, labelled by its own name — better a generic
  /// marker than silently pretending the mail was never filed.
  static const Map<String, (IconData, String)> _bereiche = {
    'finanzamt': (Icons.account_balance, 'Finanzamt'),
    'github': (Icons.code, 'GitHub'),
  };

  static (IconData, String) _lookUp(String bereich) =>
      _bereiche[bereich] ??
      (Icons.folder_outlined, bereich.isEmpty ? 'Korrespondenz' : bereich);

  @override
  Widget build(BuildContext context) {
    final list = eintraege;
    if (list == null || list.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;

    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < list.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            _compactChip(cs, list[i]),
          ],
        ],
      );
    }

    // Long form: a banner above the message body.
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < list.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _bannerRow(cs, list[i]),
          ],
        ],
      ),
    );
  }

  Widget _compactChip(ColorScheme cs, Map<String, dynamic> e) {
    final (icon, name) = _lookUp('${e['bereich'] ?? ''}');
    return Tooltip(
      message: 'In $name-Korrespondenz übernommen',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: cs.onPrimaryContainer),
            const SizedBox(width: 3),
            Icon(Icons.check, size: 11, color: cs.onPrimaryContainer),
          ],
        ),
      ),
    );
  }

  Widget _bannerRow(ColorScheme cs, Map<String, dynamic> e) {
    final (icon, name) = _lookUp('${e['bereich'] ?? ''}');
    final dateien = (e['dateien'] as num?)?.toInt() ?? 0;

    return Row(
      children: [
        Icon(icon, size: 18, color: cs.onPrimaryContainer),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'In $name-Korrespondenz übernommen',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onPrimaryContainer,
                ),
              ),
              Text(
                [
                  if (_datum(e) != null) _datum(e)!,
                  dateien == 1 ? '1 Dokument archiviert'
                               : '$dateien Dokumente archiviert',
                ].join('  ·  '),
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onPrimaryContainer.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String? _datum(Map<String, dynamic> k) {
    final raw = k['datum']?.toString();
    if (raw == null || raw.isEmpty) return null;
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return '${dt.day.toString().padLeft(2, '0')}.'
        '${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }
}
