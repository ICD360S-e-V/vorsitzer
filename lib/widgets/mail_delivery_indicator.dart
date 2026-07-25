import 'package:flutter/material.dart';
import '../models/mail_models.dart';

/// Zustellstatus einer gesendeten Nachricht.
///
/// Der grüne Haken erscheint erst, wenn der **Zielserver** die Nachricht per
/// SMTP angenommen hat (2.x.x) — nicht schon beim Absenden. Der Tooltip zeigt
/// die Originalantwort des Zielservers, damit im Streitfall belegbar ist, wann
/// wer die Mail übernommen hat.
class MailDeliveryIndicator extends StatelessWidget {
  final MailDelivery delivery;

  /// Kompakt (Listenzeile) oder mit Beschriftung (Detailansicht).
  final bool showLabel;

  const MailDeliveryIndicator({
    super.key,
    required this.delivery,
    this.showLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    final v = _visualFor(context, delivery);
    if (v == null) return const SizedBox.shrink();

    final icon = Icon(v.icon, size: showLabel ? 18 : 16, color: v.color);
    if (!showLabel) {
      return Tooltip(message: v.tooltip, child: icon);
    }
    return Tooltip(
      message: v.tooltip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 6),
          Text(v.label,
              style: TextStyle(fontSize: 12.5, color: v.color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  static _DeliveryVisual? _visualFor(BuildContext context, MailDelivery d) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    switch (d.state) {
      case MailDeliveryState.sent:
        return _DeliveryVisual(
          icon: Icons.check_circle,
          color: const Color(0xFF2E9E4F),
          label: 'Zugestellt',
          tooltip: _sentTooltip(d),
        );
      case MailDeliveryState.queued:
        return _DeliveryVisual(
          icon: Icons.schedule,
          color: muted,
          label: 'In Warteschlange',
          tooltip: 'Unterwegs — der Zielserver hat noch nicht geantwortet.',
        );
      case MailDeliveryState.deferred:
        return _DeliveryVisual(
          icon: Icons.pending,
          color: const Color(0xFFE08A00),
          label: 'Erneuter Versuch',
          tooltip: 'Der Zielserver war nicht erreichbar. Postfix versucht es weiter.'
              '${d.smtpResponse.isNotEmpty ? '\n${d.smtpResponse}' : ''}',
        );
      case MailDeliveryState.bounced:
      case MailDeliveryState.expired:
        return _DeliveryVisual(
          icon: Icons.error,
          color: const Color(0xFFC62828),
          label: d.state == MailDeliveryState.bounced ? 'Abgelehnt' : 'Aufgegeben',
          tooltip: 'Die Nachricht kam nicht an.'
              '${d.smtpResponse.isNotEmpty ? '\n${d.smtpResponse}' : ''}',
        );
      case MailDeliveryState.unknown:
        return null;
    }
  }

  static String _sentTooltip(MailDelivery d) {
    final parts = <String>['Vom Zielserver angenommen'];
    if (d.deliveredAt != null && d.deliveredAt!.isNotEmpty) parts.add(d.deliveredAt!);
    if (d.relay.isNotEmpty) parts.add(d.relay);
    if (d.smtpResponse.isNotEmpty) parts.add(d.smtpResponse);
    return parts.join('\n');
  }
}

class _DeliveryVisual {
  final IconData icon;
  final Color color;
  final String label;
  final String tooltip;
  const _DeliveryVisual({
    required this.icon,
    required this.color,
    required this.label,
    required this.tooltip,
  });
}

/// Status der angeforderten Lesebestätigung — nur sichtbar, wenn beim Senden
/// eine angefordert wurde.
class MailReceiptIndicator extends StatelessWidget {
  final MailDelivery delivery;
  final bool showLabel;

  const MailReceiptIndicator({
    super.key,
    required this.delivery,
    this.showLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!delivery.receiptRequested) return const SizedBox.shrink();
    final read = delivery.wasRead;
    final color = read
        ? const Color(0xFF2E9E4F)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final tooltip = read
        ? 'Gelesen am ${delivery.receiptAt}'
        : 'Lesebestätigung angefordert — noch nicht bestätigt';
    final icon = Icon(read ? Icons.drafts : Icons.mark_email_unread_outlined,
        size: showLabel ? 18 : 15, color: color);
    if (!showLabel) return Tooltip(message: tooltip, child: icon);
    return Tooltip(
      message: tooltip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 6),
          Text(read ? 'Gelesen' : 'Lesebestätigung offen',
              style: TextStyle(fontSize: 12.5, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
