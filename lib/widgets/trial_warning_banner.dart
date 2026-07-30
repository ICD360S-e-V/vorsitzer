import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Banner für Konten mit Status 'neu': zeigt an, wann die 30-tägige Testphase
/// endet. Ohne abgeschlossene Verifizierung setzt der Cron `auto_suspend.php`
/// das Konto danach auf 'suspended' — bisher ohne jede Vorwarnung in der App.
///
/// Das Enddatum kommt aus `users.trial_ends_at` (Endpunkt account_status.php).
class TrialWarningBanner extends StatelessWidget {
  final int daysRemaining;

  /// Genaues Ende der Testphase. Null bei älteren Servern, die nur die
  /// Tagesanzahl liefern — dann entfällt die Datumszeile.
  final DateTime? trialEndsAt;

  const TrialWarningBanner({
    super.key,
    required this.daysRemaining,
    this.trialEndsAt,
  });

  @override
  Widget build(BuildContext context) {
    final isUrgent = daysRemaining <= 7;
    final endsAt = trialEndsAt;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isUrgent
              ? [Colors.red.shade700, Colors.orange.shade700]
              : [Colors.orange.shade600, Colors.amber.shade600],
        ),
      ),
      child: Row(
        children: [
          Icon(
            isUrgent ? Icons.warning : Icons.info_outline,
            color: Colors.white,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isUrgent
                      ? 'Testphase endet in $daysRemaining Tag(en)'
                      : 'Ihr Konto ist noch nicht verifiziert',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  endsAt != null
                      ? 'Ohne Verifizierung wird das Konto am '
                          '${DateFormat('dd.MM.yyyy').format(endsAt)} gesperrt.'
                      : 'Ohne Verifizierung wird das Konto nach Ablauf gesperrt.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$daysRemaining Tage',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
