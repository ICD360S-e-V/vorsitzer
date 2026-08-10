import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/krankmeldung_brief.dart';

/// Vollständiger Datensatz, wie ihn Stufe 1 + Jobcenter-Stammdaten + der
/// Krankmeldungs-Eintrag zusammen liefern.
KrankmeldungBriefDaten _daten({
  String art = 'folge',
  String auEnde = '2026-08-17',
  String feststellung = '2026-08-03',
  bool arbeitsunfall = false,
  String aktenzeichen = '12345/6789',
}) {
  return KrankmeldungBriefDaten(
    vorname: 'Max',
    nachname: 'Mustermann',
    geburtsdatum: '1982-03-14',
    strasse: 'Musterstr.',
    hausnummer: '1',
    plz: '12345',
    ort: 'Musterstadt',
    aktenzeichenLabel: 'Kundennummer',
    aktenzeichen: aktenzeichen,
    zweitAktenzeichenLabel: 'BG-Nummer',
    zweitAktenzeichen: '12345BG0001',
    art: art,
    feststellungsdatum: feststellung,
    auBeginn: '2026-08-03',
    auEnde: auEnde,
    arbeitsunfall: arbeitsunfall,
  );
}

void main() {
  group('Datumsformat', () {
    test('ISO wird deutsch', () {
      expect(krankmeldungDatum('2026-08-03'), '03.08.2026');
    });

    test('Zeitanteil wird abgeschnitten', () {
      expect(krankmeldungDatum('2026-08-03 14:30'), '03.08.2026');
    });

    test('bereits deutsches Datum bleibt unverändert', () {
      expect(krankmeldungDatum('03.08.2026'), '03.08.2026');
    });

    test('leer bleibt leer', () {
      expect(krankmeldungDatum(''), '');
      expect(krankmeldungDatum('   '), '');
    });
  });

  group('Betreff', () {
    test('enthält Art, Name, Geburtsdatum und beide Aktenzeichen', () {
      final b = krankmeldungBetreff(_daten());
      expect(b, contains('Folgebescheinigung'));
      expect(b, contains('Max Mustermann'));
      expect(b, contains('geb. 14.03.1982'));
      expect(b, contains('Kundennummer 12345/6789'));
      expect(b, contains('BG-Nummer 12345BG0001'));
    });

    test('Erstbescheinigung wird als solche benannt', () {
      expect(krankmeldungBetreff(_daten(art: 'erst')), contains('Erstbescheinigung'));
    });

    test('fehlendes Aktenzeichen erzeugt kein leeres Label', () {
      final b = krankmeldungBetreff(_daten(aktenzeichen: ''));
      expect(b, isNot(contains('Kundennummer')));
      expect(b, isNot(contains(', ,')));
    });
  });

  group('Schlusssatz je Empfänger', () {
    // Der eigentliche Grund für diese Datei: ein an das Jobcenter geschickter
    // eAU-Abrufsatz lässt dort auf einen Abruf warten, den es nicht geben kann.
    test('Jobcenter verspricht keinen eAU-Abruf', () {
      final t = krankmeldungText(_daten(), KrankmeldungEmpfaenger.jobcenter);
      expect(t, contains('gesondert vorgelegt'));
      expect(t, contains('nicht möglich'));
      expect(t, isNot(contains('§ 5b EntgFG')));
      expect(t, isNot(contains('§ 109a SGB IV')));
    });

    test('Arbeitgeber bekommt § 5b EntgFG', () {
      final t = krankmeldungText(_daten(), KrankmeldungEmpfaenger.arbeitgeber);
      expect(t, contains('§ 5b EntgFG'));
      expect(t, isNot(contains('§ 109a SGB IV')));
    });

    test('Agentur für Arbeit bekommt § 109a SGB IV', () {
      final t = krankmeldungText(_daten(), KrankmeldungEmpfaenger.agenturFuerArbeit);
      expect(t, contains('§ 109a SGB IV'));
      expect(t, isNot(contains('§ 5b EntgFG')));
    });

    test('Krankenkasse hat die eAU bereits', () {
      final t = krankmeldungText(_daten(), KrankmeldungEmpfaenger.krankenkasse);
      expect(t, contains('§ 295 Abs. 1 SGB V'));
      expect(t, contains('übermittelt'));
    });

    test('sonstige Stelle bekommt gar keine Aussage über den Abruf', () {
      final t = krankmeldungText(_daten(), KrankmeldungEmpfaenger.sonstige);
      expect(t, isNot(contains('eAU')));
      expect(t, isNot(contains('abrufen')));
      // Der Brief bleibt trotzdem vollständig.
      expect(t, contains('Sehr geehrte Damen und Herren,'));
      expect(t, contains('Mit freundlichen Grüßen'));
    });
  });

  group('Brieftext', () {
    test('nennt Mitglied, Vollmacht-Formel, Anschrift und Zeitraum', () {
      final t = krankmeldungText(_daten(), KrankmeldungEmpfaenger.jobcenter);
      expect(t, contains('namens und im Auftrag unseres Mitglieds Max Mustermann'));
      expect(t, contains('geboren am 14.03.1982'));
      expect(t, contains('wohnhaft Musterstr. 1, 12345 Musterstadt'));
      expect(t, contains('vom 03.08.2026 bis voraussichtlich 17.08.2026'));
      expect(t, contains('Es handelt sich um eine Folgebescheinigung, festgestellt am 03.08.2026.'));
    });

    test('ohne AU-Ende wird "seit dem" statt eines offenen Zeitraums geschrieben', () {
      final t = krankmeldungText(_daten(auEnde: ''), KrankmeldungEmpfaenger.jobcenter);
      expect(t, contains('seit dem 03.08.2026'));
      expect(t, isNot(contains('bis voraussichtlich')));
    });

    test('ohne Feststellungsdatum bleibt der Satz grammatikalisch heil', () {
      final t = krankmeldungText(_daten(feststellung: ''), KrankmeldungEmpfaenger.jobcenter);
      expect(t, contains('Es handelt sich um eine Folgebescheinigung.'));
      expect(t, isNot(contains('festgestellt am .')));
    });

    test('Arbeitsunfall wird genannt, weil er die Zuständigkeit ändert', () {
      final t = krankmeldungText(_daten(arbeitsunfall: true), KrankmeldungEmpfaenger.arbeitgeber);
      expect(t, contains('beruht auf einem Arbeitsunfall'));
    });

    test('ohne Arbeitsunfall steht der Satz nicht da', () {
      final t = krankmeldungText(_daten(), KrankmeldungEmpfaenger.arbeitgeber);
      expect(t, isNot(contains('Arbeitsunfall')));
    });

    // Datenschutz: die AU für den Arbeitgeber trägt amtlich keine Diagnose,
    // und gespeichert wird sie ohnehin nur als Metadatum.
    test('weder Diagnose noch ICD-Code können in den Brief geraten', () {
      for (final e in KrankmeldungEmpfaenger.values) {
        final t = krankmeldungText(_daten(), e).toLowerCase();
        expect(t, isNot(contains('diagnose')));
        expect(t, isNot(contains('icd')));
      }
    });

    // Ohne Anlage ist der Brief eine Anzeige, kein Nachweis — er darf keine
    // Anlage behaupten, die es nicht gibt.
    test('behauptet nie eine Anlage', () {
      for (final e in KrankmeldungEmpfaenger.values) {
        final t = krankmeldungText(_daten(), e);
        expect(t, isNot(contains('Anlage')));
        expect(t, isNot(contains('beigefügt')));
      }
    });
  });

  group('Namen zerlegen', () {
    test('getrennte Felder gewinnen', () {
      final n = krankmeldungNamenTeilen('Max', 'Mustermann', 'Egal Anders');
      expect(n.vorname, 'Max');
      expect(n.nachname, 'Mustermann');
    });

    test('nur Nachname gefüllt bleibt so', () {
      final n = krankmeldungNamenTeilen('', 'Mustermann', 'Max Mustermann');
      expect(n.vorname, '');
      expect(n.nachname, 'Mustermann');
    });

    test('voller Name wird am letzten Leerzeichen zerlegt', () {
      final n = krankmeldungNamenTeilen(null, null, 'Max Mustermann');
      expect(n.vorname, 'Max');
      expect(n.nachname, 'Mustermann');
    });

    test('mehrteiliger Name behält den letzten Teil als Nachnamen', () {
      final n = krankmeldungNamenTeilen(null, null, 'Ana Maria Popescu');
      expect(n.vorname, 'Ana Maria');
      expect(n.nachname, 'Popescu');
    });

    test('einzelnes Wort gilt als Nachname', () {
      final n = krankmeldungNamenTeilen(null, null, 'Mustermann');
      expect(n.vorname, '');
      expect(n.nachname, 'Mustermann');
    });

    test('leer bleibt leer', () {
      final n = krankmeldungNamenTeilen(null, null, '   ');
      expect(n.vorname, '');
      expect(n.nachname, '');
    });
  });

  test('jeder Empfängertyp hat ein Label', () {
    for (final e in KrankmeldungEmpfaenger.values) {
      expect(krankmeldungEmpfaengerLabel(e).trim(), isNotEmpty);
    }
  });
}
