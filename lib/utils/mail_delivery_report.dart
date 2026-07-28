/// Der Sendebericht einer gesendeten Nachricht — was das Postfix-Log über die
/// Zustellung sagt, als fertige Zeilen.
///
/// Bewusst hier und nicht im Bildschirm oder im Druck: Bildschirm und Ausdruck
/// müssen dasselbe sagen. Zwei Stellen, die denselben Zustand in eigenen Worten
/// beschreiben, laufen früher oder später auseinander — und dann steht auf dem
/// Papier etwas anderes als auf dem Schirm, ausgerechnet bei dem Blatt, das im
/// Streitfall etwas belegen soll.
library;

import '../models/mail_models.dart';

/// Die Zeilen des Sendeberichts, in der Reihenfolge, in der sie erscheinen.
///
/// Leere Felder fallen weg — eine Zeile „Zielserver:" ohne Wert sagt nichts und
/// sieht aus wie ein Fehler.
List<List<String>> deliveryReportRows(MailDelivery d) {
  final receipt = d.receiptRequested
      ? (d.wasRead
          ? 'Gelesen am ${d.receiptAt}'
          : 'Angefordert — noch nicht bestätigt')
      : '';
  return <List<String>>[
    ['Status', deliveryStatusText(d)],
    if ((d.deliveredAt ?? '').trim().isNotEmpty)
      ['Angenommen', d.deliveredAt!.trim()],
    if (d.recipients.isNotEmpty) ['Empfänger', d.recipients.join(', ')],
    if (d.relay.trim().isNotEmpty) ['Zielserver', d.relay.trim()],
    if (d.smtpResponse.trim().isNotEmpty) ['Antwort', d.smtpResponse.trim()],
    if (d.queueId.trim().isNotEmpty) ['Queue-ID', d.queueId.trim()],
    if (receipt.isNotEmpty) ['Lesebestätigung', receipt],
  ];
}

/// Dieselben Worte wie im `MailDeliveryIndicator`, nur ausgeschrieben.
///
/// `unknown` heißt am Symbol „kein Symbol"; hier muss es dastehen. Ein leeres
/// Feld läse sich sonst wie „zugestellt", und das ist genau die Aussage, die
/// ein Sendebericht nicht treffen darf, wenn er sie nicht belegen kann.
String deliveryStatusText(MailDelivery d) {
  switch (d.state) {
    case MailDeliveryState.sent:
      return 'Zugestellt — vom Zielserver angenommen';
    case MailDeliveryState.queued:
      return 'In Warteschlange — der Zielserver hat noch nicht geantwortet';
    case MailDeliveryState.deferred:
      return 'Erneuter Versuch — der Zielserver war nicht erreichbar';
    case MailDeliveryState.bounced:
      return 'Abgelehnt — die Nachricht kam nicht an';
    case MailDeliveryState.expired:
      return 'Aufgegeben — die Nachricht kam nicht an';
    case MailDeliveryState.unknown:
      return 'Kein Eintrag im Sendeprotokoll gefunden';
  }
}
