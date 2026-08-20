import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/mail_cache_service.dart';
import 'package:icd360sev_vorsitzer/utils/mail_echtheit.dart';

void main() {
  group('Was in den Zwischenspeicher darf', () {
    test('die gewöhnlichen Kopffelder bleiben', () {
      final k = mailKopfFuerBestand({
        'uid': 42,
        'from': 'Jobcenter <post@jobcenter-ulm.de>',
        'subject': 'Ihr Widerspruch',
        'date': '2026-08-20 09:00:00',
        'seen': false,
        'has_attachment': true,
      });
      expect(k['uid'], 42);
      expect(k['subject'], 'Ihr Widerspruch');
      expect(k['has_attachment'], isTrue);
    });

    test('delivery wird NICHT abgelegt', () {
      // Sonst zeigte die Liste beim nächsten Start einen Zustellstatus, den
      // seit Stunden niemand mehr geprüft hat.
      final k = mailKopfFuerBestand({
        'uid': 1,
        'delivery': {'status': 'sent'},
      });
      expect(k.containsKey('delivery'), isFalse);
    });

    test('korrespondenz wird NICHT abgelegt', () {
      // Das wäre die schlimmere Lüge: „liegt in der Korrespondenz" ist eine
      // Aussage über die Akte, nicht über die Anzeige.
      final k = mailKopfFuerBestand({
        'uid': 1,
        'korrespondenz': [
          {'bereich': 'finanzamt'}
        ],
      });
      expect(k.containsKey('korrespondenz'), isFalse);
    });

    test('box wird NICHT abgelegt — der Bestand ist je Ordner abgelegt', () {
      expect(mailKopfFuerBestand({'uid': 1, 'box': 'Trash'}).containsKey('box'),
          isFalse);
    });

    test('was fehlt, wird nicht erfunden', () {
      final k = mailKopfFuerBestand({'uid': 7});
      expect(k.keys.toList(), ['uid']);
    });

    test('die Positivliste enthält nichts Flüchtiges', () {
      for (final verboten in ['delivery', 'korrespondenz', 'box', 'html', 'text']) {
        expect(kMailBestandFelder, isNot(contains(verboten)),
            reason: '$verboten gehört nicht in eine Listenzeile');
      }
    });
  });

  group('Altersangabe', () {
    test('gerade eben', () {
      expect(mailStandText(DateTime.now()), 'gerade eben');
    });

    test('Minuten, Stunden, Tage — jeweils mit richtiger Mehrzahl', () {
      final j = DateTime.now();
      expect(mailStandText(j.subtract(const Duration(minutes: 20))),
          'vor 20 Minuten');
      expect(mailStandText(j.subtract(const Duration(hours: 1, minutes: 1))),
          'vor 1 Stunde');
      expect(mailStandText(j.subtract(const Duration(hours: 5))), 'vor 5 Stunden');
      expect(mailStandText(j.subtract(const Duration(days: 1, hours: 1))),
          'vor 1 Tag');
      expect(mailStandText(j.subtract(const Duration(days: 3))), 'vor 3 Tagen');
    });
  });

  // Die Zeichenketten unten stammen WÖRTLICH vom Produktionsserver
  // (20.08.2026, doveadm fetch hdr über INBOX). Sie sind der einzige Test hier,
  // der die echte Antwort berührt — genau die Lücke, durch die beim Speedtest
  // ein grauer Bildschirm in die Auslieferung gerutscht ist.
  group('echte Authentication-Results vom Server', () {
    test('opendkim allein: dkim=pass, aber nichts ist bestätigt', () {
      final e = mailEchtheitLesen(
          'mail.icd360s.de; dkim=pass (2048-bit key, unprotected) '
          'header.d=arbeitsagentur.de header.i=@arbeitsagentur.de '
          'header.a=rsa-sha256 header.s=wa202006 header.b=kSTz6fpg');
      expect(e.dkim, MailPruefwert.bestanden);
      expect(e.dkimDomain, 'arbeitsagentur.de');
      // ⚠️ Ohne DMARC gilt nichts als bestätigt — und genau so sahen ALLE
      // Nachrichten aus, bevor rspamd seine Zeile dazuschrieb.
      expect(e.dmarc, MailPruefwert.unbekannt);
      expect(e.istBestaetigt, isFalse);
      expect(e.istGescheitert, isFalse);
    });

    test('zwei Signaturen in einer Zeile (DHL über einen Versender)', () {
      final e = mailEchtheitLesen(
          'mail.icd360s.de; dkim=pass (2048-bit key, unprotected) '
          'header.d=dhl.de header.i=noreply@dhl.de header.a=rsa-sha256 '
          'header.s=epi header.b=faAlRBzP; dkim=pass (2048-bit key, unprotected) '
          'header.d=srv2.de header.i=@srv2.de header.a=rsa-sha256 '
          'header.s=mailkey1 header.b=wPjOQ3ya');
      expect(e.dkim, MailPruefwert.bestanden);
      // Die ERSTE Domain gewinnt — das ist die des eigentlichen Absenders,
      // nicht die des Dienstleisters, der die Mail verschickt hat.
      expect(e.dkimDomain, 'dhl.de');
    });

    test('opendkim und rspamd zusammengefügt ergeben einen vollen Befund', () {
      // So sieht es aus, seit rspamd seine eigene Zeile schreibt: zwei
      // Kopfzeilen mit UNSERER Kennung, vom Server zu einer verbunden.
      final e = mailEchtheitLesen(
          'mail.icd360s.de; dkim=pass header.d=arbeitsagentur.de '
          'mail.icd360s.de; dkim=pass header.d=arbeitsagentur.de; '
          'spf=pass smtp.mailfrom=arbeitsagentur.de; '
          'dmarc=pass header.from=arbeitsagentur.de');
      expect(e.dkim, MailPruefwert.bestanden);
      expect(e.spf, MailPruefwert.bestanden);
      expect(e.dmarc, MailPruefwert.bestanden);
      expect(e.istBestaetigt, isTrue);
    });
  });
}
