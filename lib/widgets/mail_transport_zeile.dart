import 'package:flutter/material.dart';

import '../utils/mail_transport.dart';

/// Zeigt, ob die LEITUNG zu war, auf der diese Nachricht ankam.
///
/// Steht direkt unter [MailEchtheitKarte] und beantwortet bewusst eine andere
/// Frage: die Karte darüber sagt, ob der Absender echt ist, diese Zeile sagt,
/// ob unterwegs jemand mitlesen konnte. Zusammengefasst zu einem „sicher"
/// wären beide falsch.
///
/// ⚠️ Dieselbe Regel wie bei der Karte darüber: ein grünes Häkchen an jeder
/// Mail wird nach drei Tagen zu Tapete. Gemessen sind auf diesem Postfach
/// 55 von 55 empfangenen Nachrichten verschlüsselt — der Normalfall bekommt
/// deshalb eine einzige unauffällige Zeile, und nur die Ausnahme wird laut.
///
/// „Nicht belegt" ist eine eigene Aussage und ausdrücklich NICHT dasselbe wie
/// „unverschlüsselt". Und selbst erzeugte Post (aus dem Haus, nie über das
/// Netz) bekommt gar keine Zeile: dort gibt es keine Leitung, über die etwas
/// zu sagen wäre.
class MailTransportZeile extends StatelessWidget {
  final MailTransportBefund befund;

  /// Gesendete Nachricht? Ändert nur die Formulierung.
  final bool gesendet;

  const MailTransportZeile({
    super.key,
    required this.befund,
    this.gesendet = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = mailTransportText(befund, gesendet: gesendet);

    if (befund.wert == MailTransportWert.intern) return const SizedBox.shrink();

    if (befund.istWarnung) {
      const farbe = Color(0xFFE08A00);
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: farbe.withValues(alpha: 0.10),
          border: Border.all(color: farbe.withValues(alpha: 0.45)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.lock_open, size: 18, color: farbe),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: farbe)),
            ),
          ],
        ),
      );
    }

    final unklar = befund.wert == MailTransportWert.unbekannt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(unklar ? Icons.help_outline : Icons.lock_outline,
              size: 15,
              color: unklar ? cs.onSurfaceVariant : const Color(0xFF2E7D32)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}
