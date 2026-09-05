import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/models/mail_models.dart';
import 'package:icd360sev_vorsitzer/utils/mail_delivery_report.dart';
import 'package:icd360sev_vorsitzer/utils/mail_transport.dart';

/// Echte Formen vom Server, gemessen am 24.08.2026 gegen das laufende Postfach
/// und das Postfix-Log — nicht ausgedacht.
///
/// ⚠️ Zwei Fälle darin sind genau die, an denen die erste Fassung gescheitert
/// ist, beide erst durch den Lauf gegen echte Daten aufgefallen:
///   * `UTF8SMTPS` — die Arbeitsagentur sendet mit SMTPUTF8; eine Prüfung auf
///     „beginnt mit ESMTPS" stufte deren Post als „unbekannt" ein.
///   * `Untrusted` — dieselbe Arztpraxis, die auch bei DMARC durchfällt: TLS
///     stand, das Zertifikat war aber nicht überprüfbar. Das als schlichtes
///     „verschlüsselt" zu zeigen verschweigt genau den Teil, der zählt.

const String _perEmpfaengerGut = r'''
[{"to":"max.mustermann@example.com","status":"sent","dsn":"2.0.0","relay":"gmail-smtp-in.l.google.com[142.250.153.26]:25","response":"250 2.0.0 OK","at":"2026-08-23 09:12:03","service":"smtp","tls_status":"verschluesselt","tls":{"stufe":"Trusted","version":"TLSv1.3","cipher":"TLS_AES_256_GCM_SHA384","ziel":"gmail-smtp-in.l.google.com[142.250.153.26]:25"}}]
''';

const String _perEmpfaengerUngeprueft = r'''
[{"to":"praxis@internisten-ulm.de","status":"sent","dsn":"2.0.0","relay":"mail.internisten-ulm.de[85.13.145.9]:25","response":"250 OK","at":"2026-08-23 08:41:02","service":"smtp","tls_status":"verschluesselt","tls":{"stufe":"Untrusted","version":"TLSv1.3","cipher":"TLS_AES_256_GCM_SHA384","ziel":"mail.internisten-ulm.de[85.13.145.9]:25"}}]
''';

/// Zwei Empfänger, einer davon im Klartext.
const String _perEmpfaengerGemischt = r'''
[{"to":"gut@example.org","status":"sent","service":"smtp","tls_status":"verschluesselt","tls":{"stufe":"Trusted","version":"TLSv1.3","cipher":"X","ziel":"a"}},
 {"to":"offen@example.net","status":"sent","service":"smtp","tls_status":"klartext","tls":null}]
''';

void main() {
  group('Eingang', () {
    test('ESMTPS und UTF8SMTPS gelten beide als verschlüsselt', () {
      for (final p in const ['ESMTPS', 'UTF8SMTPS']) {
        final b = mailTransportLesen({'status': 'verschluesselt', 'protokoll': p});
        expect(b.wert, MailTransportWert.verschluesselt, reason: p);
        expect(b.istSauber, isTrue, reason: p);
        expect(mailTransportText(b, gesendet: false), contains('Verschlüsselt empfangen'));
      }
    });

    test('Klartext ist eine Warnung, „nicht belegt" ausdrücklich nicht', () {
      final offen = mailTransportLesen({'status': 'klartext', 'protokoll': 'ESMTP'});
      expect(offen.istWarnung, isTrue);
      expect(mailTransportText(offen, gesendet: false), contains('offen lesbar'));

      final unklar = mailTransportLesen({'status': 'unbekannt', 'protokoll': 'QMQP'});
      expect(unklar.istWarnung, isFalse);
      expect(unklar.istSauber, isFalse);
      expect(mailTransportText(unklar, gesendet: false), 'Verschlüsselung nicht belegt');
    });

    test('eigene Post kennt keine Leitung', () {
      final b = mailTransportLesen({'status': 'intern', 'protokoll': ''});
      expect(b.wert, MailTransportWert.intern);
      expect(b.istWarnung, isFalse);
    });

    // ⚠️ PHP reicht die mailapi-Antwort unverändert durch, und ein leerer
    // Block kommt dort als LISTE an. Ein `as Map` darauf wirft, statt null zu
    // liefern — dieselbe Falle, die den Speedtest-Schirm grau werden liess.
    test('eine Liste statt einer Map wirft nicht', () {
      expect(() => mailTransportLesen(const []), returnsNormally);
      expect(mailTransportLesen(const []).wert, MailTransportWert.unbekannt);
      expect(mailTransportLesen(null).wert, MailTransportWert.unbekannt);
    });
  });

  group('Ausgang', () {
    test('geprüftes Zertifikat wird als solches benannt', () {
      final b = mailTransportAusEmpfaengern(jsonDecode(_perEmpfaengerGut));
      expect(b.wert, MailTransportWert.verschluesselt);
      expect(b.zertifikat, MailZertifikatWert.geprueft);
      expect(b.istWarnung, isFalse);
      final t = mailTransportText(b, gesendet: true);
      expect(t, contains('Verschlüsselt zugestellt'));
      expect(t, contains('TLSv1.3'));
      expect(t, contains('Zertifikat geprüft'));
    });

    test('verschlüsselt mit unüberprüfbarem Zertifikat ist eine Warnung', () {
      final b = mailTransportAusEmpfaengern(jsonDecode(_perEmpfaengerUngeprueft));
      expect(b.wert, MailTransportWert.verschluesselt);
      expect(b.zertifikat, MailZertifikatWert.ungeprueft);
      // Das ist der Punkt: „verschlüsselt" allein wäre hier beschönigend.
      expect(b.istWarnung, isTrue);
      expect(b.istSauber, isFalse);
      expect(mailTransportText(b, gesendet: true), contains('nicht überprüfbar'));
    });

    test('der schlechteste Empfänger gewinnt', () {
      final b = mailTransportAusEmpfaengern(jsonDecode(_perEmpfaengerGemischt));
      expect(b.wert, MailTransportWert.klartext);
      expect(mailTransportText(b, gesendet: true), contains('Unverschlüsselt zugestellt'));
    });

    test('ohne Empfängerdaten bleibt es unbekannt, nicht sauber', () {
      expect(mailTransportAusEmpfaengern(const []).wert, MailTransportWert.unbekannt);
      expect(mailTransportAusEmpfaengern(null).wert, MailTransportWert.unbekannt);
      expect(mailTransportAusEmpfaengern(const {}).wert, MailTransportWert.unbekannt);
    });
  });

  group('Sendebericht', () {
    test('die Zeile steht immer da — auch ohne Beleg', () {
      // ⚠️ Eine fehlende Zeile läse sich wie „war schon in Ordnung". Genau
      // deshalb ist sie nicht an eine Bedingung geknüpft.
      final ohne = MailDelivery.fromJson(const {'status': 'sent'});
      final zeilen = deliveryReportRows(ohne).map((r) => r[0]).toList();
      expect(zeilen, contains('Verschlüsselung'));
      expect(
        deliveryReportRows(ohne).firstWhere((r) => r[0] == 'Verschlüsselung')[1],
        'Verschlüsselung nicht belegt',
      );
    });

    test('MailDelivery liest per_recipient mit', () {
      final d = MailDelivery.fromJson({
        'status': 'sent',
        'relay': 'gmail-smtp-in.l.google.com[142.250.153.26]:25',
        'per_recipient': jsonDecode(_perEmpfaengerGut),
      });
      expect(d.transport.wert, MailTransportWert.verschluesselt);
      expect(
        deliveryReportRows(d).firstWhere((r) => r[0] == 'Verschlüsselung')[1],
        contains('TLSv1.3'),
      );
    });
  });
}
