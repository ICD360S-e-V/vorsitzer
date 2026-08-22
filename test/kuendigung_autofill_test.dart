import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/kuendigung_autofill.dart';

void main() {
  // Ein Datensatz, wie ihn user_details.php (Stufe 1) liefert.
  final stamm = <String, dynamic>{
    'vorname': 'Beata',
    'vorname2': 'Maria',
    'nachname': 'Musterfrau',
    'geburtsdatum': '1980-04-27',
    'email': 'privat@gmx.de',
    'telefon_mobil': '+4915112345678',
    'telefon_fix': '+49731801597',
    'plz': '89073',
    'ort': 'Ulm',
    'strasse': 'Musterstraße',
    'hausnummer': '12a',
  };
  final vertrag = <String, dynamic>{
    'kundennummer': '1234567',
    'telefonnummer': '+4917699988877',
  };

  group('Geburtsdatum zerlegen', () {
    test('beide Schreibrichtungen', () {
      expect(geburtsdatumZerlegen('1980-04-27'), (tag: '27', monat: '04', jahr: '1980'));
      expect(geburtsdatumZerlegen('27.04.1980'), (tag: '27', monat: '04', jahr: '1980'));
      expect(geburtsdatumZerlegen('1980-04-27T00:00:00'), (tag: '27', monat: '04', jahr: '1980'));
    });

    test('Unbrauchbares gibt leer zurück statt Unsinn', () {
      // Lieber ein leeres Feld als der 19. des Monats 80.
      for (final e in ['', '1980', 'kein Datum', '27.04', 'x.y.z']) {
        final r = geburtsdatumZerlegen(e);
        expect(r.jahr, '', reason: e);
      }
    });
  });

  group('Autofill', () {
    test('Stammdaten landen in den richtigen Schlüsseln', () {
      final w = kuendigungAutofill(stammdaten: stamm, vertrag: vertrag);
      expect(w['vorname'], 'Beata Maria');
      expect(w['nachname'], 'Musterfrau');
      expect(w['geb_tag'], '27');
      expect(w['geb_monat'], '04');
      expect(w['geb_jahr'], '1980');
      expect(w['plz'], '89073');
      expect(w['ort'], 'Ulm');
      expect(w['land'], 'Deutschland');
    });

    test('Straße und Hausnummer bleiben getrennt', () {
      // o2 hat zwei Felder. Zusammengeklebt bliebe das Hausnummernfeld leer
      // und die Nummer stünde doppelt in der Straße.
      final w = kuendigungAutofill(stammdaten: stamm, vertrag: vertrag);
      expect(w['strasse'], 'Musterstraße');
      expect(w['hausnummer'], '12a');
    });

    test('gekündigt wird die Nummer DES VERTRAGS, nicht die private', () {
      final w = kuendigungAutofill(stammdaten: stamm, vertrag: vertrag);
      expect(w['rufnummer'], '+4917699988877');
      expect(w['telefon'], '+4915112345678');
    });

    test('ohne Vertragsnummer wird auf die Stammdaten zurückgefallen', () {
      final w = kuendigungAutofill(stammdaten: stamm, vertrag: {'kundennummer': '99'});
      expect(w['rufnummer'], '+4915112345678');
    });

    test('nur Festnetz hinterlegt', () {
      final s = Map<String, dynamic>.from(stamm)..remove('telefon_mobil');
      final w = kuendigungAutofill(stammdaten: s, vertrag: {});
      expect(w['telefon'], '+49731801597');
      expect(w['rufnummer'], '+49731801597');
    });

    test('die Eingangsbestätigung geht an den Verein, nicht an die Privatadresse', () {
      // Sie ist der Nachweis der Kündigung und muss archivierbar sein.
      final w = kuendigungAutofill(stammdaten: stamm, vertrag: vertrag);
      expect(w['email'], 'icd@icd360s.de');
      expect(w['email'], isNot('privat@gmx.de'));
    });

    test('leere Quellen ergeben leere Werte, keinen Absturz', () {
      final w = kuendigungAutofill();
      expect(w['vorname'], '');
      expect(w['kundennummer'], '');
      expect(w['land'], 'Deutschland');
      final w2 = kuendigungAutofill(stammdaten: {}, vertrag: {});
      expect(w2['nachname'], '');
    });

    test('Leerzeichen zählen nicht als Wert', () {
      final w = kuendigungAutofill(stammdaten: {'vorname': '   ', 'nachname': ' Meier '}, vertrag: {});
      expect(w['vorname'], '');
      expect(w['nachname'], 'Meier');
    });
  });

  group('Fehlende Pflichtangaben', () {
    test('vollständig → nichts zu melden', () {
      expect(kuendigungFehlendePflichtfelder(
          kuendigungAutofill(stammdaten: stamm, vertrag: vertrag)), isEmpty);
    });

    test('fehlende Kundennummer wird benannt', () {
      final w = kuendigungAutofill(stammdaten: stamm, vertrag: {'telefonnummer': '+49170'});
      expect(kuendigungFehlendePflichtfelder(w), ['Kundennummer']);
    });

    test('gar nichts hinterlegt → alle vier', () {
      expect(kuendigungFehlendePflichtfelder(kuendigungAutofill()),
          ['Vorname', 'Nachname', 'Kundennummer', 'Rufnummer']);
    });
  });
}
