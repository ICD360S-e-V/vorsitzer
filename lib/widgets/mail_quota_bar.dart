import 'package:flutter/material.dart';

/// Speicherplatz-Anzeige am unteren Rand des Postfachs.
///
/// Die Farbe wechselt mit dem Füllstand, damit der freie Platz auf einen Blick
/// erkennbar ist: unter 25 % blau, unter 50 % grün, unter 75 % gelb, darüber rot.
class MailQuotaBar extends StatelessWidget {
  /// Belegter Speicher in Kilobyte (wie von doveadm geliefert).
  final double usedKb;

  /// Erlaubter Speicher in Kilobyte; 0 oder kleiner = kein Limit.
  final double limitKb;

  const MailQuotaBar({super.key, required this.usedKb, required this.limitKb});

  bool get _hasLimit => limitKb > 0;

  /// Füllstand 0..1.
  double get fraction => _hasLimit ? (usedKb / limitKb).clamp(0.0, 1.0) : 0.0;

  int get percent => (fraction * 100).round();

  static const Color _blue = Color(0xFF1E76D4);
  static const Color _green = Color(0xFF2E9E4F);
  static const Color _yellow = Color(0xFFE0A800);
  static const Color _red = Color(0xFFD32F2F);
  static const Color _deepRed = Color(0xFFA31515);

  /// Farbe nach Füllstand.
  static Color colorForFraction(double f) {
    final p = f * 100;
    if (p < 25) return _blue;
    if (p < 50) return _green;
    if (p < 75) return _yellow;
    if (p < 90) return _red;
    return _deepRed;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _hasLimit ? colorForFraction(fraction) : cs.onSurfaceVariant;
    final label = _hasLimit
        ? '${formatKb(usedKb)} von ${formatKb(limitKb)}'
        : '${formatKb(usedKb)} belegt · kein Limit';

    return Material(
      color: cs.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.storage_outlined, size: 16, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (_hasLimit)
                    Text(
                      '$percent %',
                      style: TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700, color: color),
                    ),
                ],
              ),
              if (_hasLimit) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 6,
                    color: color,
                    backgroundColor: cs.outlineVariant.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Formatiert Kilobyte adaptiv — 120 KB, 4.2 MB, 1.5 GB.
  static String formatKb(double kb) {
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
    final mb = kb / 1024;
    if (mb < 1024) {
      return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
    }
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(gb < 10 ? 1 : 0)} GB';
  }
}
