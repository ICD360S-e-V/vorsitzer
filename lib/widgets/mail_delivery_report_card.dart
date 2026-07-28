import 'package:flutter/material.dart';

import '../models/mail_models.dart';
import '../utils/mail_delivery_report.dart';
import 'mail_delivery_indicator.dart';

/// Der Sendebericht einer gesendeten Nachricht, wie er über dem Text steht.
///
/// Zeigt dieselben Zeilen wie der Ausdruck — beide holen sie aus
/// [deliveryReportRows]. Vorher stand hier nur der Status und die Antwort des
/// Zielservers; Empfänger, Zielserver und Queue-ID hingen ausschließlich im
/// Tooltip des Symbols, waren also auf einem Touchgerät praktisch nicht
/// erreichbar und im Ausdruck gar nicht.
///
/// Die Werte sind auswählbar: eine Queue-ID oder eine SMTP-Antwort schreibt
/// man nicht ab, die kopiert man in die Beschwerde.
class MailDeliveryReportCard extends StatelessWidget {
  final MailDelivery delivery;

  const MailDeliveryReportCard({super.key, required this.delivery});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = deliveryReportRows(delivery);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sendebericht',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface)),
          const SizedBox(height: 6),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 104,
                    child: Text(r[0],
                        style:
                            TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  ),
                  // Das farbige Symbol bleibt beim Status — auf einen Blick
                  // grün oder rot zu sehen ist der Grund, warum die Karte
                  // überhaupt oben steht.
                  //
                  // Der Platz dafür steht in JEDER Zeile, auch in den leeren:
                  // sonst rückt allein der Status nach rechts und die Werte
                  // stehen nicht mehr untereinander. Bei `unknown` gibt der
                  // Indikator nichts aus, die Spalte bleibt trotzdem.
                  SizedBox(
                    width: 22,
                    child: r[0] == 'Status'
                        ? MailDeliveryIndicator(delivery: delivery)
                        : null,
                  ),
                  Expanded(
                    child: SelectableText(r[1],
                        style: const TextStyle(fontSize: 12.5)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
