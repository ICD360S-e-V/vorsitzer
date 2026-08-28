import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/mail_virenscan.dart';

void main() {
  group('Befund aus der Serverantwort', () {
    test('die drei bekannten Zustände', () {
      expect(MailScanBefund.ausJson({'status': 'sauber'}).wert,
          MailScanWert.sauber);
      expect(MailScanBefund.ausJson({'status': 'befallen'}).wert,
          MailScanWert.befallen);
      expect(MailScanBefund.ausJson({'status': 'fehler'}).wert,
          MailScanWert.fehler);
    });

    // ⚠️ Der wichtigste Test der Datei. Führt eine spätere Server-Fassung
    // einen weiteren Zustand ein, darf eine ältere App ihn NIE als Freigabe
    // lesen. Alles Unbekannte ist 'fehler', nie 'sauber'.
    test('ein unbekannter Zustand ist niemals sauber', () {
      for (final roh in ['', 'unbekannt', 'quarantaene', 'ok', 'clean', 'x']) {
        expect(MailScanBefund.ausJson({'status': roh}).wert,
            isNot(MailScanWert.sauber),
            reason: '"$roh" darf keine Freigabe sein');
        expect(MailScanBefund.ausJson({'status': roh}).wert, MailScanWert.fehler);
      }
      expect(MailScanBefund.ausJson({}).wert, MailScanWert.fehler);
    });

    test('Datum und Signaturstand kommen mit', () {
      final b = MailScanBefund.ausJson({
        'status': 'sauber',
        'geprueft_am': '2026-08-28 11:43:25',
        'signaturen': '28106',
      });
      expect(b.geprueftAm, DateTime(2026, 8, 28, 11, 43, 25));
      expect(b.signaturen, '28106');
      expect(mailScanDatumKurz(b.geprueftAm), '28.08.');
    });

    test('leere Felder werden zu null, nicht zu Leerstrings', () {
      final b = MailScanBefund.ausJson(
          {'status': 'sauber', 'signatur': '  ', 'signaturen': ''});
      expect(b.signatur, isNull);
      expect(b.signaturen, isNull);
      expect(b.geprueftAm, isNull);
    });

    test('nur ein Treffer sperrt', () {
      expect(MailScanBefund.ausJson({'status': 'befallen'}).gesperrt, isTrue);
      expect(MailScanBefund.ausJson({'status': 'sauber'}).gesperrt, isFalse);
      expect(MailScanBefund.ausJson({'status': 'fehler'}).gesperrt, isFalse);
      expect(MailScanBefund.unbekannt.gesperrt, isFalse);
    });
  });

  group('Gesamtbefund einer Nachricht', () {
    MailScanBefund b(MailScanWert w) => MailScanBefund(wert: w);

    // ⚠️ Ein sauberer Anhang entschärft keinen befallenen. Deshalb gewinnt
    // das SCHLIMMSTE Ergebnis, nicht die Mehrheit und nicht das erste.
    test('ein Treffer schlägt beliebig viele saubere', () {
      expect(
        mailScanGesamt([
          b(MailScanWert.sauber),
          b(MailScanWert.sauber),
          b(MailScanWert.befallen),
          b(MailScanWert.sauber),
        ]),
        MailScanWert.befallen,
      );
    });

    test('ein Treffer schlägt auch einen Fehler', () {
      expect(mailScanGesamt([b(MailScanWert.fehler), b(MailScanWert.befallen)]),
          MailScanWert.befallen);
    });

    test('ein Fehler schlägt sauber — „nicht prüfbar" ist nicht „sauber"', () {
      expect(mailScanGesamt([b(MailScanWert.sauber), b(MailScanWert.fehler)]),
          MailScanWert.fehler);
    });

    test('nur saubere ergeben sauber', () {
      expect(mailScanGesamt([b(MailScanWert.sauber), b(MailScanWert.sauber)]),
          MailScanWert.sauber);
    });

    test('gar nichts ergibt unbekannt, nicht sauber', () {
      expect(mailScanGesamt([]), MailScanWert.unbekannt);
      expect(mailScanGesamt([b(MailScanWert.unbekannt)]),
          MailScanWert.unbekannt);
    });

    test('läuft noch überstimmt sauber, aber nicht Fehler oder Treffer', () {
      expect(mailScanGesamt([b(MailScanWert.sauber), b(MailScanWert.laeuft)]),
          MailScanWert.laeuft);
      expect(mailScanGesamt([b(MailScanWert.fehler), b(MailScanWert.laeuft)]),
          MailScanWert.fehler);
    });
  });

  group('Sammelstand der Liste', () {
    test('die Werte des Servers', () {
      expect(mailScanWertAusText('sauber'), MailScanWert.sauber);
      expect(mailScanWertAusText('befallen'), MailScanWert.befallen);
      expect(mailScanWertAusText('fehler'), MailScanWert.fehler);
    });

    // `leer` heißt: geprüft, aber gar kein Anhang. Da ist nichts zu sagen —
    // ein grünes Zeichen an einer Mail ohne Anhang wäre sinnlos.
    test('leer und Unbekanntes bekommen kein Zeichen', () {
      expect(mailScanWertAusText('leer'), MailScanWert.unbekannt);
      expect(mailScanWertAusText(null), MailScanWert.unbekannt);
      expect(mailScanWertAusText('quatsch'), MailScanWert.unbekannt);
    });
  });

  group('Erklärungstext', () {
    // Der ganze Punkt der Plakette: sie behauptet nie „sicher", sondern sagt,
    // WANN geprüft wurde — und dass die Signaturen seither weitergezogen sind.
    test('sauber nennt Datum und die Einschränkung', () {
      final t = mailScanErklaerung(MailScanBefund(
        wert: MailScanWert.sauber,
        geprueftAm: DateTime(2026, 8, 28, 11, 43),
        signaturen: '28106',
      ));
      expect(t, contains('28.08.2026'));
      expect(t, contains('28106'));
      expect(t, contains('ändern'));
      expect(t.toLowerCase(), isNot(contains('ist sicher')));
    });

    test('Fehler sagt ausdrücklich, dass das nicht sauber heißt', () {
      final t = mailScanErklaerung(
          const MailScanBefund(wert: MailScanWert.fehler, signatur: 'clamd weg'));
      expect(t, contains('NICHT'));
      expect(t, contains('clamd weg'));
    });

    test('Treffer nennt die Signatur und die Sperre', () {
      final t = mailScanErklaerung(const MailScanBefund(
          wert: MailScanWert.befallen, signatur: 'Eicar-Test-Signature'));
      expect(t, contains('Eicar-Test-Signature'));
      expect(t, contains('gesperrt'));
    });
  });
}
