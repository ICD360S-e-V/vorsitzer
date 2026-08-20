import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/mail_sendeschutz.dart';

List<MailSendeWarnung> _arten({
  String to = 'a@b.de',
  String cc = '',
  String bcc = '',
  String koerper = '',
  int anhaenge = 0,
}) =>
    mailSendeBefunde(
            to: to, cc: cc, bcc: bcc, koerper: koerper, anhangAnzahl: anhaenge)
        .map((b) => b.art)
        .toList();

void main() {
  group('vergessener Anhang', () {
    test('„anbei" ohne Datei warnt', () {
      expect(_arten(koerper: 'Guten Tag,\n\nanbei der Bescheid.\n'),
          contains(MailSendeWarnung.anhangVergessen));
    });

    test('mit Datei warnt nicht', () {
      expect(_arten(koerper: 'anbei der Bescheid.', anhaenge: 1),
          isNot(contains(MailSendeWarnung.anhangVergessen)));
    });

    test('ohne Ankündigung warnt nicht', () {
      expect(_arten(koerper: 'Guten Tag, bitte um Rückruf.'),
          isNot(contains(MailSendeWarnung.anhangVergessen)));
    });

    test('erkennt die üblichen Formulierungen', () {
      for (final s in [
        'anbei',
        'beigefügt finden Sie',
        'beiliegend die Kopie',
        'Im Anhang der Bescheid',
        'als Anhang',
        'in der Anlage',
        'please find attached',
        'enclosed',
      ]) {
        expect(mailKuendigtAnhangAn(s), isTrue, reason: s);
      }
    });

    test('trifft nicht mitten im Wort', () {
      expect(mailKuendigtAnhangAn('Der Anlagenbau in Ulm'), isFalse);
      expect(mailKuendigtAnhangAn('Anbeißen ist erlaubt'), isFalse);
    });

    test('„anbei" AUS DEM ZITAT löst nichts aus', () {
      const koerper = 'Guten Tag, danke für die Nachricht.\n'
          '\n'
          'Am 12.08.2026 schrieb post@amt.de:\n'
          '> anbei der Bescheid\n';
      expect(mailKuendigtAnhangAn(koerper), isFalse);
    });

    test('„anbei" aus der Signatur löst nichts aus', () {
      expect(mailKuendigtAnhangAn('Text\n-- \nanbei nichts\n'), isFalse);
    });

    test('eigener Text endet an der ersten Zitatzeile', () {
      expect(mailEigenerText('eins\nzwei\n> drei\nvier'), 'eins\nzwei');
    });
  });

  group('offene Empfängerliste', () {
    test('vier Empfänger sind ein Verteiler, keine Liste', () {
      expect(_arten(to: 'a@x.de, b@x.de', cc: 'c@x.de, d@x.de'),
          isNot(contains(MailSendeWarnung.offeneEmpfaengerliste)));
    });

    test('fünf sichtbare Empfänger warnen', () {
      expect(_arten(to: 'a@x.de, b@x.de, c@x.de', cc: 'd@x.de, e@x.de'),
          contains(MailSendeWarnung.offeneEmpfaengerliste));
    });

    test('Bcc zählt nicht mit — das ist ja gerade die Lösung', () {
      expect(_arten(to: 'a@x.de', bcc: 'b@x.de, c@x.de, d@x.de, e@x.de, f@x.de'),
          isNot(contains(MailSendeWarnung.offeneEmpfaengerliste)));
    });

    test('dieselbe Adresse doppelt zählt einmal', () {
      expect(
          _arten(to: 'a@x.de, A@X.de, a@x.de', cc: 'b@x.de, c@x.de, d@x.de'),
          isNot(contains(MailSendeWarnung.offeneEmpfaengerliste)));
    });
  });

  group('nach Bcc verschieben', () {
    test('einer bleibt sichtbar, der Rest wandert', () {
      final r = mailNachBcc(
          to: 'a@x.de, b@x.de', cc: 'c@x.de, d@x.de, e@x.de', bcc: '');
      expect(r.to, 'a@x.de');
      expect(r.cc, '');
      expect(r.bcc, 'b@x.de, c@x.de, d@x.de, e@x.de');
    });

    test('vorhandenes Bcc bleibt erhalten und steht vorn', () {
      final r = mailNachBcc(to: 'a@x.de, b@x.de', cc: '', bcc: 'z@x.de');
      expect(r.bcc, 'z@x.de, b@x.de');
    });

    test('ein einzelner Empfänger wird nicht angefasst', () {
      final r = mailNachBcc(to: 'a@x.de', cc: '', bcc: 'z@x.de');
      expect(r.to, 'a@x.de');
      expect(r.bcc, 'z@x.de');
    });

    test('keine Dubletten im Bcc', () {
      final r = mailNachBcc(to: 'a@x.de, b@x.de', cc: 'B@X.de', bcc: 'b@x.de');
      expect(r.bcc, 'b@x.de');
    });

    test('nach dem Verschieben warnt nichts mehr', () {
      const to = 'a@x.de, b@x.de, c@x.de';
      const cc = 'd@x.de, e@x.de';
      expect(_arten(to: to, cc: cc),
          contains(MailSendeWarnung.offeneEmpfaengerliste));
      final r = mailNachBcc(to: to, cc: cc, bcc: '');
      expect(_arten(to: r.to, cc: r.cc, bcc: r.bcc),
          isNot(contains(MailSendeWarnung.offeneEmpfaengerliste)));
    });
  });

  test('die Verzögerung ist lang genug, um sie zu bemerken', () {
    expect(kMailSendeVerzoegerung.inSeconds, greaterThanOrEqualTo(10));
    expect(kMailSendeVerzoegerung.inSeconds, lessThanOrEqualTo(30));
  });
}
