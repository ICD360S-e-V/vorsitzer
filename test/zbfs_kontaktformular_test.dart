import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/zbfs_kontaktformular.dart';

void main() {
  group('zbfsDatumDe', () {
    test('wandelt das ISO-Datum der API in die Schreibweise des Formulars', () {
      expect(zbfsDatumDe('1980-01-05'), '05.01.1980');
      expect(zbfsDatumDe('1980-1-5'), '05.01.1980');
      expect(zbfsDatumDe('2026-08-22T10:00:00'), '22.08.2026');
    });

    test('lässt ein deutsches Datum stehen und füllt einstellige Teile auf', () {
      expect(zbfsDatumDe('5.1.1980'), '05.01.1980');
      expect(zbfsDatumDe('05.01.1980'), '05.01.1980');
    });

    test('erfindet nichts, wenn die Eingabe unverständlich ist', () {
      expect(zbfsDatumDe(''), '');
      expect(zbfsDatumDe(null), '');
      expect(zbfsDatumDe('unbekannt'), 'unbekannt');
    });
  });

  group('zbfsAnredeOption', () {
    test('kennt alle fünf Schreibweisen aus users.geschlecht', () {
      expect(zbfsAnredeOption('M'), '1|Herr');
      expect(zbfsAnredeOption('maennlich'), '1|Herr');
      expect(zbfsAnredeOption('W'), '2|Frau');
      expect(zbfsAnredeOption('weiblich'), '2|Frau');
    });

    test('rät nicht, wenn nichts hinterlegt ist', () {
      // 16 von 52 Mitgliedern haben kein Geschlecht im Datensatz. Eine geratene
      // Anrede stünde anschließend in der Behördenakte.
      expect(zbfsAnredeOption(''), '9|keine Angabe');
      expect(zbfsAnredeOption(null), '9|keine Angabe');
      expect(zbfsAnredeOption('divers'), '9|keine Angabe');
    });
  });

  group('zbfsAktenzeichen', () {
    test('schreibt vier Ziffern, Bindestrich, vier Ziffern', () {
      // Der Bindestrich gehört zur Schreibweise des ZBFS. Er war zeitweise
      // entfernt, weil er nach einer Zutat unserer Eingabemaske aussah.
      expect(zbfsAktenzeichen('4641-1720'), '4641-1720');
      expect(zbfsAktenzeichen('46411720'), '4641-1720');
      expect(zbfsAktenzeichen('4641 1720'), '4641-1720');
      expect(zbfsAktenzeichen(' 4641 - 1720 '), '4641-1720');
    });

    test('baut nichts um, was nicht acht Ziffern hat', () {
      expect(zbfsAktenzeichen('123456'), '123456');
      expect(zbfsAktenzeichen('AZ 4711'), 'AZ 4711');
      expect(zbfsAktenzeichen(''), '');
      expect(zbfsAktenzeichen(null), '');
    });
  });

  group('zbfsAdresseZerlegen', () {
    test('zerlegt die mehrzeilige Vereinsanschrift', () {
      final a = zbfsAdresseZerlegen(
          'ICD360S e.V.\nc/o Ionut-Claudiu Duinea\nElsa-Brandström-Straße 13\n89231 Neu-Ulm');
      expect(a.strasse, 'Elsa-Brandström-Straße 13');
      expect(a.plz, '89231');
      expect(a.ort, 'Neu-Ulm');
    });

    test('kommt mit Leerzeilen und Wagenrücklauf zurecht', () {
      final a = zbfsAdresseZerlegen('Musterweg 1\r\n\r\n12345 Musterstadt\r\n');
      expect(a.strasse, 'Musterweg 1');
      expect(a.plz, '12345');
      expect(a.ort, 'Musterstadt');
    });

    test('gibt leer zurück, statt eine Anschrift zu raten', () {
      // Lieber ein leeres Feld, das jemand ausfüllt, als eine falsche
      // Absenderanschrift auf einem Behördenformular.
      final a = zbfsAdresseZerlegen('Irgendwas ohne Postleitzahl');
      expect(a.strasse, '');
      expect(a.plz, '');
      expect(a.ort, '');
    });
  });

  group('zbfsThemenzuordnung', () {
    test('führt Wertmarke und Ausweis über das Feststellungsverfahren', () {
      for (final art in ['wertmarke', 'ausweis_verlaengerung', 'erstantrag', 'merkzeichen']) {
        final z = zbfsThemenzuordnung(art);
        expect(z.themenbereich, '2|Menschen mit Behinderung', reason: art);
        expect(z.unterpunkt, startsWith('1|Schwerbehindertenfeststellungsverfahren'), reason: art);
      }
    });

    test('Landesblindengeld und Soziale Entschädigung laufen woanders', () {
      expect(zbfsThemenzuordnung('landesblindengeld').unterpunkt, '2|Bayerisches Blindengeld');
      expect(zbfsThemenzuordnung('soziale_entschaedigung').themenbereich, '4|Soziale Entschädigung');
    });
  });

  group('zbfsMitteilung', () {
    test('Wertmarke nennt die Rechtsgrundlage und die bekannte Gültigkeit', () {
      final t = zbfsMitteilung(
          antragsart: 'wertmarke', antragDatum: '2026-08-20', wertmarkeBis: '09/2026');
      expect(t, contains('§ 228 Absatz 5 SGB IX'));
      expect(t, contains('gilt bis einschließlich 09/2026'));
      expect(t, contains('Antrag vom 20.08.2026'));
    });

    test('Wertmarke wird ausgegeben, nicht verlängert', () {
      // Das ZBFS schreibt selbst „Nach Ablauf der Gültigkeitsdauer können Sie
      // eine neue Wertmarke erwerben"; § 228 Abs. 5 SGB IX spricht von der
      // „Ausgabe der Wertmarken … auf Antrag". „Verlängerung" gibt es dort nicht.
      final t = zbfsMitteilung(antragsart: 'wertmarke');
      expect(t, contains('Ausgabe eines Beiblatts mit einer neuen Wertmarke'));
      expect(t, isNot(contains('Verlängerung')));
    });

    test('lässt die Gültigkeit weg, wenn wir sie nicht kennen', () {
      final t = zbfsMitteilung(antragsart: 'wertmarke');
      expect(t, isNot(contains('gilt bis')));
      expect(t, contains('hiermit'));
    });

    test('unterschrieben wird mit dem Namen des Mitglieds', () {
      final t = zbfsMitteilung(antragsart: 'wertmarke', unterzeichner: 'Maria Musterfrau');
      expect(t, contains('Mit freundlichen Grüßen\nMaria Musterfrau'));
    });

    test('ohne Namen bleibt keine leere Zeile unter dem Gruß', () {
      final t = zbfsMitteilung(antragsart: 'wertmarke');
      expect(t, endsWith('Mit freundlichen Grüßen'));
    });

    test('der Schlussvermerk nennt den Verein und die Ehrenamtlichkeit', () {
      final t = zbfsMitteilung(
          antragsart: 'wertmarke', unterzeichner: 'Maria Musterfrau', vereinName: 'ICD360S e.V.');
      expect(t, contains('automatisch erstellt durch den ICD360S e.V.'));
      expect(t, contains('gemeinnützigen Verein'));
      expect(t, contains('ehrenamtlich und unentgeltlich'));
      // Der Vermerk steht unter der Unterschrift, nicht dazwischen.
      expect(t.indexOf('Maria Musterfrau'), lessThan(t.indexOf('automatisch erstellt')));
    });

    test('ohne Vereinsnamen entfällt der Vermerk ganz', () {
      // „…erstellt durch den , einen gemeinnützigen Verein" wäre schlechter
      // als gar kein Vermerk.
      final t = zbfsMitteilung(antragsart: 'wertmarke', unterzeichner: 'Maria Musterfrau');
      expect(t, isNot(contains('automatisch erstellt')));
    });

    test('jede Antragsart bekommt einen eigenen Satz', () {
      final saetze = <String>{};
      for (final art in [
        'erstantrag', 'neufeststellung', 'ausweis_verlaengerung', 'ausweis_neu',
        'wertmarke', 'parkausweis', 'merkzeichen', 'soziale_entschaedigung',
        'landesblindengeld', 'sonstiges',
      ]) {
        final t = zbfsMitteilung(antragsart: art);
        expect(t, startsWith('Sehr geehrte Damen und Herren,'));
        saetze.add(t);
      }
      expect(saetze.length, 10, reason: 'kein Satz darf doppelt vorkommen');
    });
  });

  group('zbfsAutofillJs', () {
    ZbfsFormularDaten daten({String nachname = 'Mustermann', String plz = '89231'}) =>
        ZbfsFormularDaten(
          vorname: 'Maria',
          nachname: nachname,
          geschlecht: 'W',
          strasseHausnummer: 'Musterstr. 1',
          plz: plz,
          ort: 'Neu-Ulm',
          geburtsdatum: '1980-01-05',
          aktenzeichen: '4641-1720',
          vereinName: 'ICD360S e.V.',
          vereinTelefon: '+49 731 80159736',
          vereinStrasseHausnummer: 'Elsa-Brandström-Straße 13',
          vereinPlz: '89231',
          vereinOrt: 'Neu-Ulm',
          antragsart: 'wertmarke',
          mitteilung: 'Sehr geehrte Damen und Herren,',
        );

    /// Zieht das eingebettete Wertepaket wieder aus dem Skript heraus.
    Map<String, dynamic> werte(String js) {
      final m = RegExp(r'var W = (\{.*?\});').firstMatch(js);
      expect(m, isNotNull, reason: 'Wertepaket nicht gefunden');
      return jsonDecode(m!.group(1)!) as Map<String, dynamic>;
    }

    test('trägt die Stufe-1-Daten unter den richtigen Schlüsseln ein', () {
      final w = werte(zbfsAutofillJs(daten()));
      expect(w['person.vorname'], 'Maria');
      expect(w['person.nachname'], 'Mustermann');
      expect(w['person.anrede'], '2|Frau');
      expect(w['person.strasse_hausnummer'], 'Musterstr. 1');
      expect(w['person.plz'], '89231');
      expect(w['person.ort'], 'Neu-Ulm');
      expect(w['person.geburtsdatum'], '05.01.1980');
      expect(w['person.aktenzeichen'], '4641-1720');
    });

    test('die Telefonnummer ist die des Vereins, nicht die des Mitglieds', () {
      final w = werte(zbfsAutofillJs(daten()));
      expect(w['person.telefon'], '+49 731 80159736');
      expect(w['absender.telefon'], '+49 731 80159736');
    });

    test('der Absender-Zweig trägt den Verein als bevollmächtigte Vertretung', () {
      final w = werte(zbfsAutofillJs(daten()));
      expect(w['absender.funktion'], '1|bevollmächtigte Vertretung');
      expect(w['absender.firma'], 'ICD360S e.V.');
      expect(w['absender.ort'], 'Neu-Ulm');
      // Der unterschreibende Mensch wird nicht geraten.
      expect(w.containsKey('absender.anrede'), isFalse);
      expect(w.containsKey('absender.vorname'), isFalse);
    });

    test('Land wird nur bei deutscher Postleitzahl ergänzt', () {
      expect(werte(zbfsAutofillJs(daten()))['person.land'], 'Deutschland');
      // Ohne fünfstellige PLZ bleibt das Feld leer, statt „Deutschland" zu
      // behaupten.
      expect(werte(zbfsAutofillJs(daten(plz: '')))['person.land'], isNull);
    });

    test('leere Werte landen gar nicht erst im Skript', () {
      final js = zbfsAutofillJs(const ZbfsFormularDaten(vorname: 'Max'));
      final w = werte(js);
      expect(w['person.vorname'], 'Max');
      expect(w.containsKey('person.nachname'), isFalse);
      expect(w.containsKey('person.aktenzeichen'), isFalse);
      expect(w.containsKey('absender.firma'), isFalse);
    });

    test('ein Apostroph im Namen zerlegt das Skript nicht', () {
      // Der Grund für JSON statt Handmaskierung: „O'Brien" beendete in der
      // alten Bauweise die JS-Zeichenkette.
      final js = zbfsAutofillJs(daten(nachname: "O'Brien"));
      expect(werte(js)['person.nachname'], "O'Brien");
      expect(js, isNot(contains(r"O\'Brien")));
    });

    test('das Skript schickt nichts ab und klickt nicht weiter', () {
      final js = zbfsAutofillJs(daten());
      expect(js, isNot(contains('submit.forward')));
      expect(js, isNot(contains('.submit()')));
      expect(js, isNot(contains('form.submit')));
      // Ein change-Ereignis darf nur die aufeinander aufbauenden Auswahlfelder
      // auslösen — dort ist es der einzige Weg, das nächste Feld einzublenden.
      expect(js, contains("KASKADE = { 'themenbereich': 1, 'behinderung': 1 }"));
    });

    test('das Auswahlfeld „Ich wende mich an das ZBFS" bleibt unbelegt', () {
      // Ob der Verein in eigener Sache oder als Bevollmächtigter schreibt, ist
      // eine rechtliche Aussage.
      expect(werte(zbfsAutofillJs(daten())).keys.any((k) => k.contains('zbfsk')), isFalse);
    });
  });
}
