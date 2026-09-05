import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/mail_echtheit.dart';

void main() {
  group('Authentication-Results lesen', () {
    test('liest alle drei Prüfungen', () {
      final e = mailEchtheitLesen(
          'mail.icd360s.de; dkim=pass header.d=jobcenter.de; '
          'spf=pass smtp.mailfrom=jobcenter.de; dmarc=pass header.from=jobcenter.de');
      expect(e.dkim, MailPruefwert.bestanden);
      expect(e.spf, MailPruefwert.bestanden);
      expect(e.dmarc, MailPruefwert.bestanden);
      expect(e.dkimDomain, 'jobcenter.de');
      expect(e.istBestaetigt, isTrue);
      expect(e.istGescheitert, isFalse);
    });

    test('fail wird als gescheitert erkannt', () {
      final e = mailEchtheitLesen('x; dkim=fail; spf=pass; dmarc=fail');
      expect(e.istGescheitert, isTrue);
      expect(e.istBestaetigt, isFalse);
    });

    test('softfail und neutral sind weich, nicht gescheitert', () {
      final e = mailEchtheitLesen('x; spf=softfail; dkim=neutral; dmarc=pass');
      expect(e.spf, MailPruefwert.weich);
      expect(e.dkim, MailPruefwert.weich);
      expect(e.istGescheitert, isFalse);
      expect(e.istBestaetigt, isTrue);
    });

    test('none zählt nicht als Fehler — viele kleine Absender haben kein DKIM',
        () {
      final e = mailEchtheitLesen('x; dkim=none; spf=pass; dmarc=pass');
      expect(e.dkim, MailPruefwert.keine);
      expect(e.istGescheitert, isFalse);
      expect(e.istBestaetigt, isTrue);
    });

    test('ohne DMARC gilt nichts als bestätigt', () {
      final e = mailEchtheitLesen('x; spf=pass');
      expect(e.istBestaetigt, isFalse);
      expect(e.hatBefund, isTrue);
    });

    test('leer oder null gibt einen leeren Befund', () {
      expect(mailEchtheitLesen(null).hatBefund, isFalse);
      expect(mailEchtheitLesen('').hatBefund, isFalse);
      expect(mailEchtheitLesen('   ').hatBefund, isFalse);
    });

    test('die ERSTE Angabe gewinnt — ein nachgereichtes pass darf ein fail '
        'nicht überschreiben', () {
      final e = mailEchtheitLesen('a; dmarc=fail; b; dmarc=pass');
      expect(e.dmarc, MailPruefwert.gescheitert);
    });

    test('unbekanntes Wort bleibt unbekannt', () {
      expect(mailEchtheitLesen('x; dkim=quatsch').dkim, MailPruefwert.unbekannt);
    });
  });

  group('Absender zerlegen', () {
    test('Name und Adresse', () {
      final t = mailAbsenderTeile('Adela Musterfrau <adela@icd360s.de>');
      expect(t.name, 'Adela Musterfrau');
      expect(t.adresse, 'adela@icd360s.de');
    });

    test('Anführungszeichen fallen weg', () {
      expect(mailAbsenderTeile('"Amt, Ulm" <a@b.de>').name, 'Amt, Ulm');
    });

    test('nackte Adresse hat keinen Namen', () {
      final t = mailAbsenderTeile('a@b.de');
      expect(t.name, '');
      expect(t.adresse, 'a@b.de');
    });
  });

  group('Absenderverdacht', () {
    test('saubere Adresse ist unverdächtig', () {
      expect(mailAbsenderVerdacht('Jobcenter Ulm <post@jobcenter-ulm.de>'),
          MailVerdacht.keiner);
    });

    test('ohne Anzeigename gibt es nichts zu vergleichen', () {
      expect(mailAbsenderVerdacht('post@jobcenter-ulm.de'), MailVerdacht.keiner);
    });

    test('fremde Adresse im Anzeigenamen', () {
      expect(
          mailAbsenderVerdacht('"post@amtsgericht-ulm.de" <abc123@gmail.com>'),
          MailVerdacht.andereAdresseImNamen);
    });

    test('dieselbe Adresse im Namen ist kein Verdacht', () {
      expect(mailAbsenderVerdacht('a@b.de <a@b.de>'), MailVerdacht.keiner);
    });

    test('fremde Domain im Anzeigenamen', () {
      expect(mailAbsenderVerdacht('"Sparkasse Ulm sparkasse.de" <x@mailer.ru>'),
          MailVerdacht.andereDomainImNamen);
    });

    test('eigene Domain im Namen ist in Ordnung', () {
      expect(mailAbsenderVerdacht('"Service icd360s.de" <icd@icd360s.de>'),
          MailVerdacht.keiner);
    });

    test('Unterdomain zählt als dieselbe Herkunft', () {
      expect(mailAbsenderVerdacht('"beispiel.de" <x@mail.beispiel.de>'),
          MailVerdacht.keiner);
    });

    test('angehängter Domainname ist KEINE Unterdomain', () {
      // boesesparkasse.de darf nicht als Unterdomain von sparkasse.de gelten —
      // sonst fällt der Verdacht genau bei der Schreibweise weg, für die er
      // gedacht ist.
      expect(mailAbsenderVerdacht('"sparkasse.de" <x@boesesparkasse.de>'),
          MailVerdacht.andereDomainImNamen);
    });

    test('gemischte Schrift im Namen', () {
      // Das erste „а" ist kyrillisch U+0430.
      expect(mailAbsenderVerdacht('"Spаrkasse" <x@example.com>'),
          MailVerdacht.gemischteSchrift);
    });

    test('durchgehend kyrillischer Name ist einfach ein Name', () {
      expect(mailAbsenderVerdacht('"Ольга Мельник" <olena@example.com>'),
          MailVerdacht.keiner);
    });

    test('jeder Verdacht hat einen Text, keiner hat keinen', () {
      for (final v in MailVerdacht.values) {
        final t = mailVerdachtText(v);
        expect(t.isEmpty, v == MailVerdacht.keiner,
            reason: 'Text fehlt oder ist zu viel für $v');
      }
    });
  });
}
