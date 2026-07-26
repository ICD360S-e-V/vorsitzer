import 'package:flutter/material.dart';

/// Marks a mail that has been copied into Finanzamt ▸ Korrespondenz.
///
/// Mail addressed to elster@icd360s.de is filed automatically by a cron job.
/// Without a visible marker there is no way to tell an archived mail from one
/// the importer has not seen yet — which leads to filing the same letter twice,
/// or worse, assuming a Bescheid was archived when it was not.
///
/// The original always stays in the mailbox; this only says a copy exists.
class MailKorrespondenzBadge extends StatelessWidget {
  /// The `korrespondenz` map the mail list attaches to a message:
  /// `{korrespondenz_id, datum, dateien}`. Null means "not archived".
  final Map<String, dynamic>? korrespondenz;

  /// Compact form for the list row; the long form is for the opened message.
  final bool compact;

  const MailKorrespondenzBadge({
    super.key,
    required this.korrespondenz,
    this.compact = true,
  });

  @override
  Widget build(BuildContext context) {
    final k = korrespondenz;
    if (k == null) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final dateien = (k['dateien'] as num?)?.toInt() ?? 0;

    if (compact) {
      return Tooltip(
        message: 'In Finanzamt-Korrespondenz übernommen',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.account_balance, size: 11, color: cs.onPrimaryContainer),
              const SizedBox(width: 3),
              Icon(Icons.check, size: 11, color: cs.onPrimaryContainer),
            ],
          ),
        ),
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
      child: Row(
        children: [
          Icon(Icons.account_balance, size: 18, color: cs.onPrimaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'In Finanzamt-Korrespondenz übernommen',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                Text(
                  [
                    if (_datum(k) != null) _datum(k)!,
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
      ),
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
