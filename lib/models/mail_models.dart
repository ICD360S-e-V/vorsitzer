import 'dart:typed_data';

/// Ein Anhang, der mit einer ausgehenden E-Mail hochgeladen wird.
class MailOutgoingAttachment {
  final String filename;
  final Uint8List bytes;

  const MailOutgoingAttachment({required this.filename, required this.bytes});

  int get size => bytes.length;
}

/// Ein IMAP-Ordner mit Zählern, wie ihn `mail/folders.php` liefert.
class MailFolder {
  /// IMAP-Name, z. B. 'INBOX' oder 'Sent'.
  final String box;
  final int total;
  final int unseen;

  const MailFolder({required this.box, this.total = 0, this.unseen = 0});

  factory MailFolder.fromJson(Map<String, dynamic> j) => MailFolder(
        box: '${j['box'] ?? 'INBOX'}',
        total: (j['total'] as num?)?.toInt() ?? 0,
        unseen: (j['unseen'] as num?)?.toInt() ?? 0,
      );
}

/// Zustellstatus einer gesendeten Nachricht, abgeleitet aus dem Postfix-Log.
enum MailDeliveryState {
  /// Noch in der Warteschlange — der Zielserver hat noch nicht geantwortet.
  queued,

  /// Der Zielserver hat die Nachricht angenommen (SMTP 2.x.x).
  sent,

  /// Temporär fehlgeschlagen, Postfix versucht es weiter.
  deferred,

  /// Endgültig abgelehnt.
  bounced,

  /// Zustellung aufgegeben (Queue-Lifetime abgelaufen).
  expired,

  /// Kein Log-Eintrag gefunden (z. B. von einem anderen Client gesendet).
  unknown,
}

class MailDelivery {
  final MailDeliveryState state;

  /// Die Antwort des Zielservers, z. B. '250 2.0.0 OK'.
  final String smtpResponse;
  final String relay;
  final String queueId;
  final String? deliveredAt;
  final List<String> recipients;

  /// Lesebestätigung wurde beim Senden angefordert.
  final bool receiptRequested;

  /// Zeitpunkt, an dem die Lesebestätigung zurückkam (null = noch offen).
  final String? receiptAt;

  const MailDelivery({
    this.state = MailDeliveryState.unknown,
    this.smtpResponse = '',
    this.relay = '',
    this.queueId = '',
    this.deliveredAt,
    this.recipients = const [],
    this.receiptRequested = false,
    this.receiptAt,
  });

  static MailDeliveryState _parseState(String raw) {
    switch (raw) {
      case 'sent':
        return MailDeliveryState.sent;
      case 'queued':
        return MailDeliveryState.queued;
      case 'deferred':
        return MailDeliveryState.deferred;
      case 'bounced':
        return MailDeliveryState.bounced;
      case 'expired':
        return MailDeliveryState.expired;
      default:
        return MailDeliveryState.unknown;
    }
  }

  factory MailDelivery.fromJson(Map<String, dynamic> j) => MailDelivery(
        state: _parseState('${j['status'] ?? 'unknown'}'),
        smtpResponse: '${j['smtp_response'] ?? ''}',
        relay: '${j['relay'] ?? ''}',
        queueId: '${j['queue_id'] ?? ''}',
        deliveredAt: j['delivered_at']?.toString(),
        recipients: ((j['recipients'] as List?) ?? const [])
            .map((e) => '$e')
            .toList(growable: false),
        receiptRequested: j['receipt_requested'] == true,
        receiptAt: j['receipt_at']?.toString(),
      );

  bool get isAccepted => state == MailDeliveryState.sent;
  bool get isFailed =>
      state == MailDeliveryState.bounced || state == MailDeliveryState.expired;
  bool get isPending =>
      state == MailDeliveryState.queued || state == MailDeliveryState.deferred;
  bool get wasRead => receiptAt != null && receiptAt!.isNotEmpty;
}
