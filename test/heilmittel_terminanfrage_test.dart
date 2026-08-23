import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/terminanfrage_vorlagen.dart';

/// Die Terminanfrage zu einer HEILMITTELVERORDNUNG.
///
/// 🔴 WORUM ES HIER GEHT
/// Der erste Anlauf reichte nur `arztTyp: 'gesundheit_hausarzt'` durch. Der
/// gemeinsame Dialog löste damit das Hausarzt-Fach auf, und in der Anfrage an
/// eine PHYSIOTHERAPIE-Praxis stand „zur hausärztlichen Erstvorstellung",
/// „Gesundheitsuntersuchung (Check-up) … § 25 Abs. 1 SGB V" und zur Auswahl
/// „Erkältung / Husten / Fieber" und „Blutbild / Laborkontrolle" — alles
/// Dinge, die eine Heilmittelpraxis weder darf noch tut.
///
/// Das kompiliert, `flutter analyze` schweigt, und aufgefallen wäre es erst
/// dem Menschen in der Praxis, der den Brief liest. Diese Tests sind die
/// Stelle, an der es stattdessen laut wird.
void main() {
  Map<String, dynamic> zeile({
    bool dringend = false,
    bool hausbesuch = false,
    bool rezeptDa = false,
    bool bericht = false,
  }) =>
      <String, dynamic>{
        'bereich': 'Physiotherapie',
        'datum': '2026-08-12',
        'hm1': 'Krankengymnastik',
        'hm1_anzahl': '6',
        'hm2': 'Manuelle Therapie',
        'hm2_anzahl': '6',
        'hm_ergaenzend': 'Wärmetherapie',
        'hm_erg_anzahl': '12',
        'behandlungseinheiten': '12',
        'frequenz': '2x pro Woche',
        'diagnosegruppe': 'WS2',
        'leitsymptomatik': 'Schmerzen der Wirbelsäule',
        'leitsymptomatik_abc': 'a',
        'diagnose1': 'Lumboischialgie',
        'diagnose1_icd10': 'M54.4',
        'dringend': dringend,
        'hausbesuch': hausbesuch,
        'therapiebericht': bericht,
        'rezept_in_praxis': rezeptDa,
        'lanr': '123456789',
        'bsnr': '987654321',
      };

  TerminanfrageDaten daten(Map<String, dynamic> r) => TerminanfrageDaten(
        // ⚠️ Der arztTyp bleibt der des Tabs, in dem die Verordnung hängt.
        // Genau deshalb muss `rezept` gewinnen — sonst schlägt das Hausarzt-
        // Fach durch.
        arztTyp: 'gesundheit_hausarzt',
        vorname: 'Ionuț-Claudiu',
        nachname: 'Duinea',
        geburtsdatum: '14.03.1985',
        rezept: HeilmittelVerordnung.ausZeile(r),
      );

  String brief(Map<String, dynamic> r) {
    final d = daten(r);
    final t = terminanfrageText(TerminanfrageVorlage.erstvorstellung, d);
    return '${t.betreff}\n${t.absaetze.join('\n')}';
  }

  group('Das Rezept verdrängt die Arzt-Vorlagen', () {
    test('kein einziger hausärztlicher Anlass im Brief', () {
      final text = brief(zeile());
      // Die Formulierungen stammen wörtlich aus kArztFaecher['gesundheit_hausarzt'].
      for (final verboten in const [
        'hausärztlichen Erstvorstellung',
        'Gesundheitsuntersuchung',
        'Check-up',
        '§ 25',
        'akuter Beschwerden',
      ]) {
        expect(text, isNot(contains(verboten)),
            reason: 'Hausarzt-Formulierung „$verboten" in einem Brief an eine '
                'Heilmittelpraxis');
      }
    });

    test('angekreuzte Arzt-Anlässe werden ignoriert, nicht eingebaut', () {
      // Selbst wenn von irgendwo Anlässe mitkommen: sie gehören zum Arztfach
      // und dürfen den Heilmittel-Brief nicht erreichen.
      final d = TerminanfrageDaten(
        arztTyp: 'gesundheit_hausarzt',
        vorname: 'A',
        nachname: 'B',
        anlaesse: const ['Blutbild / Laborkontrolle', 'Bluthochdruck'],
        rezept: HeilmittelVerordnung.ausZeile(zeile()),
      );
      final text =
          terminanfrageText(TerminanfrageVorlage.erstvorstellung, d)
              .absaetze
              .join('\n');
      expect(text, isNot(contains('Laborkontrolle')));
      expect(text, isNot(contains('Blutdruck')));
    });

    test('„Überweisung liegt vor" erscheint nicht — es ist Muster 13', () {
      final d = TerminanfrageDaten(
        arztTyp: 'gesundheit_hausarzt',
        vorname: 'A',
        nachname: 'B',
        ueberweisungLiegtVor: true,
        rezept: HeilmittelVerordnung.ausZeile(zeile()),
      );
      final text =
          terminanfrageText(TerminanfrageVorlage.erstvorstellung, d)
              .absaetze
              .join('\n');
      expect(text, isNot(contains('Überweisung')));
      expect(text, contains('Muster 13'));
    });
  });

  group('Was die Praxis zum Planen braucht', () {
    test('Heilmittel mit Mengen, Gesamtmenge und Frequenz', () {
      final text = brief(zeile());
      expect(text, contains('Krankengymnastik (6x)'));
      expect(text, contains('Manuelle Therapie (6x)'));
      expect(text, contains('Wärmetherapie (12x)'));
      // ⚠️ Ohne diese beiden plant die Praxis EINEN Termin statt einer Serie.
      expect(text, contains('12 Behandlungseinheiten'));
      expect(text, contains('2x pro Woche'));
    });

    test('Indikation und Diagnose samt ICD-10', () {
      final text = brief(zeile());
      expect(text, contains('WS2'));
      expect(text, contains('Schmerzen der Wirbelsäule'));
      expect(text, contains('Lumboischialgie'));
      expect(text, contains('ICD-10 M54.4'));
    });

    test('verordnende Praxis über BSNR und LANR zuordenbar', () {
      final text = brief(zeile());
      expect(text, contains('BSNR 987654321'));
      expect(text, contains('LANR 123456789'));
    });
  });

  group('Die beiden Merkmale, die den Brief umstellen', () {
    test('dringlich nennt ein DATUM, nicht eine Frist zum Ausrechnen', () {
      final text = brief(zeile(dringend: true));
      expect(text, contains('DRINGLICHER BEHANDLUNGSBEDARF'));
      // 12.08.2026 + 14 Tage
      expect(text, contains('spätestens am 26.08.2026'));
    });

    test('ohne Dringlichkeit steht keine Frist im Brief', () {
      expect(brief(zeile()), isNot(contains('spätestens am')));
    });

    test('unlesbares Ausstellungsdatum fällt auf die Frist zurück', () {
      // Lieber die allgemeine Formulierung als ein falsch gerechnetes Datum.
      final r = zeile(dringend: true)..['datum'] = '';
      final text = brief(r);
      expect(text, contains('innerhalb von 14 Tagen'));
      expect(text, isNot(contains('spätestens am')));
    });

    test('Hausbesuch ändert die BITTE, nicht nur einen Nebensatz', () {
      final ohne = brief(zeile());
      final mit = brief(zeile(hausbesuch: true));
      expect(ohne, contains('bitte ich um Behandlungstermine auf Grundlage'));
      expect(mit, contains('um Behandlungstermine als Hausbesuch'));
    });
  });

  group('Der Papierweg', () {
    test('Rezept noch nicht dort: wird mitgebracht', () {
      expect(brief(zeile()), contains('wird zum ersten Termin mitgebracht'));
    });

    test('Rezept liegt vor: kein „mitgebracht"', () {
      final text = brief(zeile(rezeptDa: true));
      expect(text, contains('liegt Ihnen bereits vor'));
      expect(text, isNot(contains('mitgebracht')));
    });

    test('Therapiebericht nur, wenn angefordert', () {
      expect(brief(zeile(bericht: true)), contains('Therapiebericht'));
      expect(brief(zeile()), isNot(contains('Therapiebericht')));
    });
  });

  group('Der Betreff nennt die Verordnung', () {
    test('Bereich, Ausstellungsdatum und Patient', () {
      final t = terminanfrageText(
          TerminanfrageVorlage.erstvorstellung, daten(zeile()));
      expect(t.betreff, contains('Physiotherapie'));
      expect(t.betreff, contains('Verordnung vom 12.08.2026'));
      expect(t.betreff, contains('Duinea'));
      // Nicht die Arzt-Fassung.
      expect(t.betreff, isNot(contains('Erstvorstellung')));
    });
  });

  group('Die Zeile wird gelesen, wie der Vordruck sie nennt', () {
    test('leere Heilmittel-Plätze erzeugen keine leeren Klammern', () {
      final r = zeile()
        ..['hm2'] = ''
        ..['hm2_anzahl'] = ''
        ..['hm_ergaenzend'] = '';
      final v = HeilmittelVerordnung.ausZeile(r);
      expect(v.heilmittel.length, 1);
      expect(v.heilmittelSatz, 'Krankengymnastik (6x)');
      expect(brief(r), isNot(contains('()')));
    });

    test('ältere Zeilen mit einfachem diagnose/icd10 werden gelesen', () {
      final r = zeile()
        ..remove('diagnose1')
        ..remove('diagnose1_icd10')
        ..['diagnose'] = 'Gonarthrose'
        ..['icd10'] = 'M17.0';
      expect(brief(r), contains('Gonarthrose (ICD-10 M17.0)'));
    });

    test('Merker werden auch als "true"/1 erkannt', () {
      // Der Server liefert Wahrheitswerte je nach Endpunkt unterschiedlich.
      for (final wert in <dynamic>[true, 'true', 1, '1']) {
        final r = zeile()..['dringend'] = wert;
        expect(HeilmittelVerordnung.ausZeile(r).dringend, isTrue,
            reason: 'dringend als $wert (${wert.runtimeType}) nicht erkannt');
      }
      for (final wert in <dynamic>[false, 'false', 0, '0', null]) {
        final r = zeile()..['dringend'] = wert;
        expect(HeilmittelVerordnung.ausZeile(r).dringend, isFalse);
      }
    });

    test('ohne Bereich bleibt es Physiotherapie, nicht leer', () {
      final r = zeile()..['bereich'] = '';
      expect(HeilmittelVerordnung.ausZeile(r).bereichOderStandard,
          'Physiotherapie');
      expect(brief(r), contains('Verordnung für Physiotherapie'));
    });
  });

  test('ohne Rezept bleibt das Arztfach unverändert', () {
    // Gegenprobe: die 21 Arztfächer dürfen von dieser Änderung nichts merken.
    final d = TerminanfrageDaten(
      arztTyp: 'gesundheit_hausarzt',
      vorname: 'A',
      nachname: 'B',
      anlaesse: const ['Bluthochdruck'],
    );
    final text = terminanfrageText(TerminanfrageVorlage.kontrolle, d)
        .absaetze
        .join('\n');
    expect(text, contains('Gesundheitsuntersuchung'));
    expect(text, contains('Blutdruck'));
    expect(text, isNot(contains('Muster 13')));
  });
}
