import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/mail_suche.dart';
import 'package:icd360sev_vorsitzer/utils/mail_vorlage.dart';

void main() {
  group('Suchfelder lesen', () {
    test('reiner Freitext bleibt Freitext', () {
      final s = mailSucheLesen('Widerspruch Bescheid');
      expect(s.text, 'Widerspruch Bescheid');
      expect(s.hatFelder, isFalse);
      expect(s.istLeer, isFalse);
    });

    test('leere Eingabe ist leer', () {
      expect(mailSucheLesen('').istLeer, isTrue);
      expect(mailSucheLesen('   ').istLeer, isTrue);
    });

    test('von, an, betreff', () {
      final s = mailSucheLesen('von:jobcenter an:datenschutz betreff:Frist');
      expect(s.von, 'jobcenter');
      expect(s.an, 'datenschutz');
      expect(s.betreff, 'Frist');
      expect(s.text, '');
    });

    test('englische Schlüsselwörter gehen auch', () {
      final s = mailSucheLesen('from:amt to:icd subject:Bescheid');
      expect(s.von, 'amt');
      expect(s.an, 'icd');
      expect(s.betreff, 'Bescheid');
    });

    test('Anführungszeichen halten den Ausdruck zusammen', () {
      final s = mailSucheLesen('betreff:"Ihr Widerspruch" rest');
      expect(s.betreff, 'Ihr Widerspruch');
      expect(s.text, 'rest');
    });

    test('hat:anhang', () {
      expect(mailSucheLesen('hat:anhang').hatAnhang, isTrue);
      expect(mailSucheLesen('has:attachment').hatAnhang, isTrue);
    });

    test('ist:ungelesen / gelesen / markiert', () {
      expect(mailSucheLesen('ist:ungelesen').ungelesen, isTrue);
      expect(mailSucheLesen('ist:gelesen').ungelesen, isFalse);
      expect(mailSucheLesen('ist:markiert').markiert, isTrue);
    });

    test('ordner:alle', () {
      expect(mailSucheLesen('ordner:alle Miete').alleOrdner, isTrue);
      expect(mailSucheLesen('Miete').alleOrdner, isFalse);
    });

    test('Freitext und Felder zusammen', () {
      final s = mailSucheLesen('von:amt Widerspruch hat:anhang Bescheid');
      expect(s.von, 'amt');
      expect(s.hatAnhang, isTrue);
      expect(s.text, 'Widerspruch Bescheid');
    });

    test('unverstandener Wert BLEIBT Freitext', () {
      // Sonst sucht der Nutzer nach etwas, das er nie eingegeben hat.
      final s = mailSucheLesen('hat:zeit Termin');
      expect(s.hatAnhang, isNull);
      expect(s.text, 'hat:zeit Termin');
    });

    test('ein unbekanntes Schlüsselwort wird nicht angefasst', () {
      final s = mailSucheLesen('http://example.org/x Rechnung');
      expect(s.text, 'http://example.org/x Rechnung');
      expect(s.hatFelder, isFalse);
    });
  });

  group('Datum', () {
    test('deutsches Datum wird ISO', () {
      expect(mailDatumNormalisieren('01.02.2026'), '2026-02-01');
      expect(mailDatumNormalisieren('1.2.2026'), '2026-02-01');
    });

    test('ISO bleibt ISO, aber zweistellig', () {
      expect(mailDatumNormalisieren('2026-2-1'), '2026-02-01');
      expect(mailDatumNormalisieren('2026-02-01'), '2026-02-01');
    });

    test('zweistellige Jahre werden NICHT geraten', () {
      expect(mailDatumNormalisieren('01.02.26'), '');
      expect(mailDatumNormalisieren('Unsinn'), '');
    });

    test('unbrauchbares Datum verfällt zu Freitext', () {
      final s = mailSucheLesen('seit:irgendwann Miete');
      expect(s.seit, '');
      expect(s.text, 'seit:irgendwann Miete');
    });

    test('seit und bis', () {
      final s = mailSucheLesen('seit:01.01.2026 bis:2026-06-30');
      expect(s.seit, '2026-01-01');
      expect(s.bis, '2026-06-30');
    });
  });

  group('Übertragung', () {
    test('leere Felder fallen weg, damit ein alter Server versteht', () {
      final f = mailSucheLesen('Miete').alsFelder();
      expect(f, {'search': 'Miete'});
    });

    test('alle Felder kommen mit', () {
      final f = mailSucheLesen(
              'von:a an:b betreff:c hat:anhang ist:ungelesen '
              'seit:01.01.2026 bis:02.01.2026 ordner:alle rest')
          .alsFelder();
      expect(f['search'], 'rest');
      expect(f['von'], 'a');
      expect(f['an'], 'b');
      expect(f['betreff'], 'c');
      expect(f['hat_anhang'], 1);
      expect(f['ungelesen'], 1);
      expect(f['seit'], '2026-01-01');
      expect(f['bis'], '2026-01-02');
      expect(f['alle_ordner'], 1);
    });

    test('Chips nennen jedes erkannte Feld', () {
      final chips = mailSucheChips(mailSucheLesen('von:amt hat:anhang ordner:alle'));
      expect(chips, contains('Von: amt'));
      expect(chips, contains('mit Anhang'));
      expect(chips, contains('alle Ordner'));
    });

    test('jedes Hilfemuster lässt sich auch wirklich lesen', () {
      for (final h in kMailSucheHilfe) {
        expect(mailSucheLesen(h.muster).hatFelder, isTrue,
            reason: 'Hilfe zeigt „${h.muster}", das der Parser nicht versteht');
      }
    });
  });

  group('Vorlagen füllen', () {
    const daten = MailVorlageDaten(
      anrede: 'Sehr geehrte Frau Menning',
      vorname: 'Anica',
      nachname: 'Menning',
      mitgliedsnummer: 'M51060',
      absender: 'Ionut Duinea',
    );

    test('setzt die Werte ein', () {
      expect(
          mailVorlageFuellen('{anrede},\n\n{name} ({mitgliedsnummer})', daten),
          'Sehr geehrte Frau Menning,\n\nAnica Menning (M51060)');
    });

    test('Datum wird deutsch formatiert', () {
      final t = mailVorlageFuellen('{datum}',
          const MailVorlageDaten(heute: null).copyHeute(DateTime(2026, 8, 3)));
      expect(t, '03.08.2026');
    });

    test('leerer Wert LÄSST den Platzhalter stehen', () {
      // „Sehr geehrte ," ist genau der Fehler, der schon einmal an sieben
      // echte Menschen hinausgegangen ist.
      expect(mailVorlageFuellen('{anrede},', const MailVorlageDaten()),
          '{anrede},');
    });

    test('unbekannter Platzhalter bleibt stehen', () {
      expect(mailVorlageFuellen('{quatsch}', daten), '{quatsch}');
    });

    test('offene Platzhalter werden gemeldet', () {
      final gefuellt = mailVorlageFuellen('{anrede} {quatsch} {datum}', daten);
      expect(mailVorlageOffenePlatzhalter(gefuellt), ['datum', 'quatsch']);
    });

    test('nichts offen, wenn alles gesetzt ist', () {
      final gefuellt = mailVorlageFuellen('{anrede} {name}', daten);
      expect(mailVorlageOffenePlatzhalter(gefuellt), isEmpty);
    });

    test('jeder angebotene Platzhalter wird auch ersetzt', () {
      final voll = MailVorlageDaten(
        anrede: 'A', vorname: 'B', nachname: 'C',
        mitgliedsnummer: 'D', absender: 'E', heute: DateTime(2026, 1, 1),
      );
      for (final p in kMailPlatzhalter) {
        final t = mailVorlageFuellen('{${p.schluessel}}', voll);
        expect(t, isNot('{${p.schluessel}}'),
            reason: '${p.schluessel} wird angeboten, aber nie ersetzt');
      }
    });
  });
}

extension on MailVorlageDaten {
  MailVorlageDaten copyHeute(DateTime d) => MailVorlageDaten(
        anrede: anrede,
        vorname: vorname,
        nachname: nachname,
        mitgliedsnummer: mitgliedsnummer,
        absender: absender,
        heute: d,
      );
}
