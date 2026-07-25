import 'dart:typed_data';

/// Ein Anhang, der mit einer ausgehenden E-Mail hochgeladen wird.
class MailOutgoingAttachment {
  final String filename;
  final Uint8List bytes;

  const MailOutgoingAttachment({required this.filename, required this.bytes});

  int get size => bytes.length;
}

/// Ein Anhang, der schon im gespeicherten Entwurf auf dem Server liegt.
///
/// Beim Autosave wird er nur über seinen [index] genannt — der Server übernimmt
/// ihn aus der vorherigen Fassung, damit er nie ein zweites Mal hochgeladen wird.
class MailStoredAttachment {
  final int index;
  final String name;
  final int size;
  final String type;

  const MailStoredAttachment({
    required this.index,
    required this.name,
    this.size = 0,
    this.type = '',
  });

  factory MailStoredAttachment.fromJson(Map<String, dynamic> j) => MailStoredAttachment(
        index: (j['index'] as num?)?.toInt() ?? -1,
        name: '${j['name'] ?? 'Anhang'}',
        size: (j['size'] as num?)?.toInt() ?? 0,
        type: '${j['type'] ?? ''}',
      );
}

/// Ein aus dem Ordner Entwürfe geladener Entwurf, bereit zum Weiterschreiben.
class MailDraft {
  final String draftId;
  final int uid;
  final String to;
  final String cc;
  final String bcc;
  final String subject;
  final String body;
  final String inReplyTo;
  final String references;
  final bool requestReceipt;
  final List<MailStoredAttachment> attachments;

  const MailDraft({
    required this.draftId,
    this.uid = 0,
    this.to = '',
    this.cc = '',
    this.bcc = '',
    this.subject = '',
    this.body = '',
    this.inReplyTo = '',
    this.references = '',
    this.requestReceipt = false,
    this.attachments = const [],
  });

  factory MailDraft.fromMessageData(Map<String, dynamic> d) => MailDraft(
        draftId: '${d['draft_id'] ?? ''}',
        uid: (d['uid'] as num?)?.toInt() ?? 0,
        to: '${d['to'] ?? ''}',
        cc: '${d['cc'] ?? ''}',
        bcc: '${d['bcc'] ?? ''}',
        subject: '${d['subject'] ?? ''}' == '(kein Betreff)' ? '' : '${d['subject'] ?? ''}',
        body: '${d['text'] ?? ''}',
        inReplyTo: '${d['in_reply_to'] ?? ''}',
        references: '${d['references'] ?? ''}',
        requestReceipt: d['request_receipt'] == true,
        attachments: ((d['attachments'] as List?) ?? const [])
            .whereType<Map>()
            .map((a) => MailStoredAttachment.fromJson(Map<String, dynamic>.from(a)))
            .toList(),
      );
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
