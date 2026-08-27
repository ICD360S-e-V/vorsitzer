import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/models/mail_models.dart';
import 'package:icd360sev_vorsitzer/utils/mail_delivery_report.dart';

/// Festgenagelt auf die **echte, ungekürzte** Antwort von `api/mail/delivery.php`,
/// aufgezeichnet am 2026-08-10 bei einer scharfen Probe des Krankmeldungs-Wegs.
///
/// Der Grund für diese Datei: kein anderer Test fasst eine echte Serverantwort an.
/// Der Server nennt das Feld `status`, das Dart-Modell heißt `state` — wer beim
/// Lesen `state` erwartet, bekommt still `unknown`, und `unknown` sieht im
/// Zweifel aus wie „noch unterwegs" statt wie „wir wissen es nicht". Genau das
/// ist bei der Probe passiert, allerdings im Prüfskript und nicht im Client.
const _echteAntwort = '''
{
  "status": "sent",
  "queue_id": "551D7A05E85E",
  "smtp_response": "250 2.0.0 <icd@icd360s.de> 6QYxMilCemqPlSwAqwUPWA Saved",
  "relay": "mail.icd360s.de[private/dovecot-lmtp]",
  "recipients": ["icd@icd360s.de"],
  "per_recipient": [
    {
      "at": "2026-08-10 23:27:05",
      "dsn": "2.0.0",
      "relay": "mail.icd360s.de[private/dovecot-lmtp]",
      "response": "250 2.0.0 <icd@icd360s.de> 6QYxMilCemqPlSwAqwUPWA Saved",
      "service": "lmtp",
      "status": "sent",
      "to": "icd@icd360s.de"
    }
  ],
  "delivered_at": "2026-08-10 23:27:05",
  "sent_at": "2026-08-10 23:27:05",
  "receipt_requested": false,
  "receipt_at": null
}
''';

/// Die Antwort unmittelbar nach dem Senden — das Postfix-Log hat den Eintrag
/// noch nicht. Fast alles ist `null`; ein Leser, der das für „zugestellt" hält,
/// behauptet etwas, das er nicht belegen kann.
const _antwortNochInWarteschlange = '''
{
  "status": "queued",
  "queue_id": null,
  "smtp_response": null,
  "relay": null,
  "recipients": ["icd@icd360s.de"],
  "per_recipient": [],
  "delivered_at": null,
  "sent_at": "2026-08-10 23:27:05",
  "receipt_requested": false,
  "receipt_at": null
}
''';

MailDelivery _lesen(String roh) =>
    MailDelivery.fromJson(Map<String, dynamic>.from(jsonDecode(roh) as Map));

void main() {
  group('echte Antwort nach erfolgreicher Zustellung', () {
    final d = _lesen(_echteAntwort);

    test('Zustand kommt aus "status", nicht aus "state"', () {
      expect(d.state, MailDeliveryState.sent);
      expect(d.isAccepted, isTrue);
      expect(d.isPending, isFalse);
      expect(d.isFailed, isFalse);
    });

    test('Zielserver und dessen SMTP-Antwort überleben das Einlesen', () {
      // Das sind die beiden Angaben, die im Streitfall etwas belegen.
      expect(d.relay, 'mail.icd360s.de[private/dovecot-lmtp]');
      expect(d.smtpResponse, startsWith('250 2.0.0'));
      expect(d.queueId, '551D7A05E85E');
      expect(d.deliveredAt, '2026-08-10 23:27:05');
      expect(d.recipients, ['icd@icd360s.de']);
    });

    test('Sendebericht nennt Zustand, Zielserver und Antwort', () {
      final zeilen = deliveryReportRows(d);
      final map = {for (final z in zeilen) z[0]: z[1]};
      expect(map['Status'], 'Zugestellt — vom Zielserver angenommen');
      expect(map['Zielserver'], 'mail.icd360s.de[private/dovecot-lmtp]');
      expect(map['Antwort'], startsWith('250 2.0.0'));
      expect(map['Queue-ID'], '551D7A05E85E');
      // Ohne angeforderte Lesebestätigung darf keine Zeile dazu erscheinen.
      expect(map.containsKey('Lesebestätigung'), isFalse);
    });

    test('unbekannte Zusatzfelder stören nicht', () {
      // per_recipient/sent_at liest das Modell nicht — es darf daran auch
      // nicht scheitern, wenn der Server weitere Felder ergänzt.
      final erweitert = Map<String, dynamic>.from(jsonDecode(_echteAntwort) as Map)
        ..['irgendwas_neues'] = {'a': 1};
      expect(MailDelivery.fromJson(erweitert).state, MailDeliveryState.sent);
    });
  });

  group('Antwort direkt nach dem Senden', () {
    final d = _lesen(_antwortNochInWarteschlange);

    test('bleibt "in Warteschlange" und nicht "zugestellt"', () {
      expect(d.state, MailDeliveryState.queued);
      expect(d.isAccepted, isFalse);
      expect(d.isPending, isTrue);
      expect(deliveryStatusText(d),
          'In Warteschlange — der Zielserver hat noch nicht geantwortet');
    });

    test('leere Felder erscheinen gar nicht, statt leer dazustehen', () {
      final map = {for (final z in deliveryReportRows(d)) z[0]: z[1]};
      expect(map.containsKey('Zielserver'), isFalse);
      expect(map.containsKey('Antwort'), isFalse);
      expect(map.containsKey('Angenommen'), isFalse);
      // Der Zustand selbst muss trotzdem dastehen.
      expect(map['Status'], isNotNull);
    });
  });

  test('fehlender Eintrag im Log heißt "unbekannt", nicht "zugestellt"', () {
    final d = MailDelivery.fromJson(const {});
    expect(d.state, MailDeliveryState.unknown);
    expect(d.isAccepted, isFalse);
    expect(deliveryStatusText(d), 'Kein Eintrag im Sendeprotokoll gefunden');
  });

  test('abgelehnt wird nie als schwebend gelesen', () {
    for (final s in ['bounced', 'expired']) {
      final d = MailDelivery.fromJson({'status': s});
      expect(d.isFailed, isTrue, reason: s);
      expect(d.isPending, isFalse, reason: s);
      expect(d.isAccepted, isFalse, reason: s);
    }
  });
}
