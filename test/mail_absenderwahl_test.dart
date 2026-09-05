import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/mail_absenderwahl.dart';
import 'package:icd360sev_vorsitzer/utils/mail_vorlage.dart';

// Die Reihenfolge, in der der Server sie liefert: eigenes Postfach zuerst.
// Nachgeprüft am 20.08.2026 gegen mailserver.virtual_aliases.
const _erlaubt = [
  'icd@icd360s.de',
  'datenschutz@icd360s.de',
  'kuendigung@icd360s.de',
  'satzung@icd360s.de',
  'widerruf@icd360s.de',
  'widerrufsrecht@icd360s.de',
];

void main() {
  group('Absender aus dem Empfang', () {
    test('Anfrage an datenschutz@ wird unter datenschutz@ beantwortet', () {
      expect(
          mailAbsenderAusEmpfang('datenschutz@icd360s.de, ', _erlaubt),
          'datenschutz@icd360s.de');
    });

    test('mit Anzeigename davor', () {
      expect(
          mailAbsenderAusEmpfang(
              '"ICD360S Widerruf" <widerruf@icd360s.de>', _erlaubt),
          'widerruf@icd360s.de');
    });

    test('Großschreibung stört nicht', () {
      expect(mailAbsenderAusEmpfang('Kuendigung@ICD360S.DE', _erlaubt),
          'kuendigung@icd360s.de');
    });

    test('an icd@ UND widerruf@: das allgemeine Postfach gewinnt', () {
      // Die Reihenfolge der ERLAUBTEN Liste entscheidet, nicht die der
      // Nachricht — sonst hinge die Absenderadresse davon ab, wie der
      // Absender seine Empfänger sortiert hat.
      expect(
          mailAbsenderAusEmpfang(
              'widerruf@icd360s.de, icd@icd360s.de', _erlaubt),
          'icd@icd360s.de');
    });

    test('fremde Adresse ergibt nichts', () {
      expect(mailAbsenderAusEmpfang('post@jobcenter-ulm.de', _erlaubt), isNull);
    });

    test('leer und null ergeben nichts', () {
      expect(mailAbsenderAusEmpfang('', _erlaubt), isNull);
      expect(mailAbsenderAusEmpfang(null, _erlaubt), isNull);
      expect(mailAbsenderAusEmpfang('   ,  , ', _erlaubt), isNull);
    });

    test('ein ANGEHÄNGTER Name ist kein Treffer', () {
      // `contains` hätte hier „widerruf@icd360s.de" gefunden und die Antwort
      // unter einer Adresse verschickt, die in der Nachricht nie stand.
      expect(
          mailAbsenderAusEmpfang('nichtwiderruf@icd360s.de', _erlaubt), isNull);
      expect(
          mailAbsenderAusEmpfang('widerruf@icd360s.de.example', _erlaubt),
          isNull);
    });

    test('leere Erlaubnisliste ergibt nichts', () {
      expect(mailAbsenderAusEmpfang('icd@icd360s.de', const []), isNull);
    });
  });

  group('Platzhalter sind alle füllbar', () {
    // ⚠️ Der eigentliche Punkt: die erste Fassung bot {anrede},
    // {mitgliedsnummer} und {name} an — und der Verfassen-Bildschirm übergab
    // NUR das Datum. Alle drei blieben also in jedem Brief stehen. Der alte
    // Test prüfte die Funktion mit von Hand gefüllten Daten und war deshalb
    // grün, ohne etwas über die App auszusagen.
    //
    // Diese Liste bildet ab, was `_vorlagenDaten()` im Verfassen-Bildschirm
    // wirklich beschaffen kann.
    const ausDerApp = {'name', 'vorname', 'nachname', 'empfaenger', 'datum',
                       'absender'};

    test('jeder ANGEBOTENE Platzhalter kann von der App gefüllt werden', () {
      for (final p in kMailPlatzhalter) {
        expect(ausDerApp, contains(p.schluessel),
            reason: '{${p.schluessel}} wird angeboten, aber nie beschafft');
      }
    });

    test('{anrede} wird NICHT angeboten', () {
      // Aus Adresse und Name lässt sich das Geschlecht nicht ableiten.
      expect(kMailPlatzhalter.map((p) => p.schluessel), isNot(contains('anrede')));
    });

    test('mit den Werten der App bleibt nichts offen', () {
      const daten = MailVorlageDaten(
        vorname: 'Adela',
        nachname: 'Musterfrau',
        empfaenger: 'adela@example.org',
        absender: 'Ionut Doe',
      );
      final text = kMailPlatzhalter.map((p) => '{${p.schluessel}}').join(' ');
      final gefuellt = mailVorlageFuellen(
          text,
          const MailVorlageDaten(
            vorname: 'Adela',
            nachname: 'Musterfrau',
            empfaenger: 'adela@example.org',
            absender: 'Ionut Doe',
          ).mitDatum(DateTime(2026, 8, 20)));
      expect(mailVorlageOffenePlatzhalter(gefuellt), isEmpty);
      expect(daten.name, 'Adela Musterfrau');
    });

    test('ohne Treffer im Adressbuch bleiben die Namen STEHEN', () {
      // Kein Netz oder kein Kontakt: „Sehr geehrte ," darf nie entstehen.
      final gefuellt = mailVorlageFuellen('Guten Tag {nachname},',
          const MailVorlageDaten(empfaenger: 'x@y.de').mitDatum(DateTime(2026, 1, 1)));
      expect(gefuellt, 'Guten Tag {nachname},');
    });
  });
}

extension on MailVorlageDaten {
  MailVorlageDaten mitDatum(DateTime d) => MailVorlageDaten(
        anrede: anrede,
        vorname: vorname,
        nachname: nachname,
        mitgliedsnummer: mitgliedsnummer,
        empfaenger: empfaenger,
        absender: absender,
        heute: d,
      );
}
