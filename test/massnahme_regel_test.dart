import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/massnahme_konstanten.dart';

/// ⚠️ Zeichengleich mit MN_STATUS / MN_ART in massnahme_manage.php UND mit
/// der ENUM-Spalte jobcenter_user_massnahme.status. Das PHP liegt in KEINEM
/// Repo (`_server_*/` ist gitignored), deshalb steht die Liste hier als
/// Literal — dieselbe Vorgehensweise wie `_serverWhitelist` bei den
/// Chat-Reaktionen. Weicht sie ab, weist der Server mit „Unbekannter Status"
/// ab, und für den Nutzer sieht das aus wie ein Fehler der App.
const _serverStatus = ['zugewiesen','angetreten','laufend','beendet','abgebrochen','abgelehnt'];
const _serverArten  = ['MAT','MAG','AVGS','Weiterbildung','sonstige'];


void _nummernPruefungen() {
  final tab = File('lib/widgets/jobcenter_massnahme_tab.dart').readAsStringSync();
  final modal = File('lib/widgets/massnahme_detail_modal.dart').readAsStringSync();

  group('Die drei Nummern des Bescheids', () {
    test('der Dialog hat für jede ein eigenes Feld', () {
      for (final label in [
        "labelText: 'Nummer der Maßnahme'",
        "labelText: 'Aktenzeichen des Jobcenters'",
        "labelText: 'Kundennummer'",
      ]) {
        expect(tab.contains(label), isTrue, reason: 'Feld fehlt: $label');
      }
    });

    test('alle drei werden auch gespeichert', () {
      for (final k in ["'massnahmenummer':", "'kundennummer':", "'aktenzeichen':"]) {
        expect(tab.contains(k), isTrue, reason: 'wird nicht gesendet: $k');
      }
    });

    // ⚠️ Der Katalogwert ist nur ein Vorschlag. Im Bescheid steht die Nummer
    // DIESES Durchgangs („/25"), und die darf nicht überschrieben werden.
    test('eine vorhandene Nummer wird vom Katalog nicht überschrieben', () {
      final i = tab.indexOf('if (_nummer.text.trim().isEmpty)');
      expect(i, greaterThan(0),
          reason: 'der Katalogvorschlag muss auf ein leeres Feld beschränkt sein');
    });

    // ⚠️ z.massnahmenummer und m.massnahmenummer hätten im SELECT denselben
    // Namen; PDO behält still die letzte. Deshalb liefert der Server
    // nummer_wirksam, und der Schirm nimmt die.
    test('angezeigt wird die wirksame Nummer, nicht blind die des Katalogs', () {
      expect(tab.contains("z['nummer_wirksam']"), isTrue);
      expect(modal.contains("z['nummer_wirksam']"), isTrue);
    });

    test('Aktenzeichen ist als das des Jobcenters beschriftet', () {
      expect(tab.contains("'Aktenzeichen (Jobcenter)'"), isTrue);
      expect(modal.contains("'Aktenzeichen (Jobcenter)'"), isTrue);
    });
  });
}

void main() {
  _nummernPruefungen();
  _ortVorschlagPruefungen();
  _vorbelegungPruefungen();
  _statusVeraltetPruefungen();
  group('Kopplung an den Server', () {
    test('Status-Liste ist zeichengleich', () {
      expect(kMassnahmeStatus, _serverStatus);
    });

    test('Art-Liste ist zeichengleich', () {
      expect(kMassnahmeArten, _serverArten);
    });

    test('jeder Status und jede Art hat eine Beschriftung', () {
      for (final s in kMassnahmeStatus) {
        expect(kMassnahmeStatusLabel[s], isNotNull, reason: 'ohne Beschriftung: $s');
      }
      for (final a in kMassnahmeArten) {
        expect(kMassnahmeArtLabel[a], isNotNull, reason: 'ohne Beschriftung: $a');
      }
    });

    // Läuft nur lokal, wo die Serverquelle daneben liegt. Auf dem Runner
    // fehlt sie — dann trägt der Literal-Test oben die Aussage allein.
    test('stimmt mit massnahme_manage.php überein (nur lokal)', () {
      final f = File('_server_massnahme/massnahme_manage.php');
      if (!f.existsSync()) return;
      final php = f.readAsStringSync();
      for (final s in kMassnahmeStatus) {
        expect(php.contains("'$s'"), isTrue, reason: 'Status fehlt im PHP: $s');
      }
      for (final a in kMassnahmeArten) {
        expect(php.contains("'$a'"), isTrue, reason: 'Art fehlt im PHP: $a');
      }
    });
  });

  group('Beschriftung', () {
    test('der Reiter nennt den Träger — MAT ist nicht MAG', () {
      expect(kMassnahmeTabTitel.contains('Träger'), isTrue);
    });

    test('der amtliche Wortlaut bleibt vollständig', () {
      expect(kMassnahmeVollTitel,
          'Zuweisung zu einer Maßnahme zur Aktivierung und beruflichen '
          'Eingliederung bei einem Träger');
      expect(kMassnahmeRechtsgrundlage, '§ 16 Abs. 1 SGB II i.V.m. § 45 SGB III');
      // ⚠️ Wortlaut aus dem echten Bescheid vom 04.09.2026: „Abs. 1" gehört an
      // § 16 SGB II, NICHT an § 45 SGB III. Ich hatte es zuerst vertauscht.
    });
  });

  group('Widerspruchsfrist § 84 Abs. 1 SGG', () {
    test('ein Monat ab Bekanntgabe', () {
      expect(massnahmeWiderspruchsfrist(DateTime(2026, 3, 15)), DateTime(2026, 4, 15));
    });

    // ⚠️ Der eigentliche Punkt: „Monat plus eins" gibt es nicht immer.
    test('31.01. → 28.02., nicht der 31.02.', () {
      expect(massnahmeWiderspruchsfrist(DateTime(2026, 1, 31)), DateTime(2026, 2, 28));
    });

    test('Schaltjahr: 31.01.2028 → 29.02.2028', () {
      expect(massnahmeWiderspruchsfrist(DateTime(2028, 1, 31)), DateTime(2028, 2, 29));
    });

    test('31.03. → 30.04.', () {
      expect(massnahmeWiderspruchsfrist(DateTime(2026, 3, 31)), DateTime(2026, 4, 30));
    });

    test('Jahreswechsel: 31.12. → 31.01. des Folgejahres', () {
      expect(massnahmeWiderspruchsfrist(DateTime(2026, 12, 31)), DateTime(2027, 1, 31));
    });

    test('ohne Bekanntgabedatum wird nichts geraten', () {
      expect(massnahmeWiderspruchsfrist(null), isNull);
      expect(massnahmeTageBisFrist(null), isNull);
    });

    test('Tage bis zur Frist, auch negativ', () {
      expect(massnahmeTageBisFrist(DateTime(2026, 9, 1), heute: DateTime(2026, 9, 20)), 11);
      expect(massnahmeTageBisFrist(DateTime(2026, 1, 1), heute: DateTime(2026, 9, 20)), lessThan(0));
    });
  });

  group('Zustand und Datum', () {
    test('offen sind genau zugewiesen/angetreten/laufend', () {
      expect(kMassnahmeStatus.where(massnahmeIstOffen).toList(),
          ['zugewiesen', 'angetreten', 'laufend']);
    });

    test('unbekannter Status gilt nicht als offen', () {
      expect(massnahmeIstOffen(null), isFalse);
      expect(massnahmeIstOffen('quatsch'), isFalse);
    });

    // Ein leeres Feld heisst „nicht erfasst". Deutsche Schreibweise wird NICHT
    // geraten — der Datumswähler schreibt immer ISO.
    test('nur ISO wird gelesen', () {
      expect(massnahmeDatum('2026-09-15'), DateTime(2026, 9, 15));
      expect(massnahmeDatum('2026-09-15 00:00:00'), DateTime(2026, 9, 15));
      expect(massnahmeDatum(''), isNull);
      expect(massnahmeDatum(null), isNull);
      expect(massnahmeDatum('15.09.2026'), isNull);
    });
  });
}

// ═════════════════════════════════════════════════════════════════════
// Der Bescheid trägt DREI verschiedene Nummern. Ein einziges Feld zwingt
// dazu, sie zu vermischen — beim ersten echten Bescheid ist genau das
// passiert: die Nummer der Maßnahme landete im Aktenzeichen.
// ═════════════════════════════════════════════════════════════════════

void _ortVorschlagPruefungen() {
  group('Durchführungsort wird vorgeschlagen', () {
    test('das Angebot selbst geht vor', () {
      expect(
        massnahmeOrtVorschlag({
          'durchfuehrungsort': 'Reuttier Straße 41, 89231 Neu-Ulm',
          'traeger_strasse': 'Frauentorstr. 29',
          'traeger_plz': '86152', 'traeger_ort': 'Augsburg',
        }),
        'Reuttier Straße 41, 89231 Neu-Ulm',
      );
    });

    test('sonst die Anschrift des Standorts', () {
      expect(
        massnahmeOrtVorschlag({
          'traeger_strasse': 'Reuttier Straße 41',
          'traeger_plz': '89231', 'traeger_ort': 'Neu-Ulm',
        }),
        'Reuttier Straße 41, 89231 Neu-Ulm',
      );
    });

    // ⚠️ „89231 Neu-Ulm" allein ist kein Ort, an den jemand hingeht. Lieber
    // nichts vorschlagen als etwas Halbes, das dann so stehen bleibt.
    test('ohne Straße wird nichts vorgeschlagen', () {
      expect(massnahmeOrtVorschlag({'traeger_plz': '89231', 'traeger_ort': 'Neu-Ulm'}), '');
      expect(massnahmeOrtVorschlag(const {}), '');
    });

    test('Straße ohne PLZ/Ort bleibt brauchbar', () {
      expect(massnahmeOrtVorschlag({'traeger_strasse': 'Reuttier Straße 41'}),
          'Reuttier Straße 41');
    });

    // ⚠️ Der Rechtsträger sitzt oft in einer anderen Stadt — im Bescheid sind
    // es zwei getrennte Zeilen. Wer ihn einsetzt, schickt jemanden 100 km weit.
    test('der juristische Sitz wird NIE verwendet', () {
      final v = massnahmeOrtVorschlag({
        'rechtstraeger': 'Kolping-Bildungswerk gGmbH in der Diözese Augsburg',
        'traeger_strasse': 'Reuttier Straße 41',
        'traeger_plz': '89231', 'traeger_ort': 'Neu-Ulm',
      });
      expect(v.contains('Augsburg'), isFalse);
      expect(v, 'Reuttier Straße 41, 89231 Neu-Ulm');
    });

    // ⚠️ Der Fall, der die Zusicherung erst prüfbar macht: OHNE Standort-
    // Anschrift. Solange traeger_strasse gesetzt ist, kann ein Rückfall auf
    // rechtstraeger gar nicht greifen — der Test oben allein wäre zahnlos.
    test('ohne Standort-Anschrift wird der Sitz NICHT ersatzweise genommen', () {
      expect(
        massnahmeOrtVorschlag({
          'rechtstraeger': 'Kolping-Bildungswerk gGmbH in der Diözese Augsburg',
          'traeger_ort': 'Neu-Ulm',
        }),
        '',
      );
    });
  });

  group('Verdrahtung im Dialog', () {
    final tab = File('lib/widgets/jobcenter_massnahme_tab.dart').readAsStringSync();

    test('der Ort wird beim Wählen eines Angebots vorgeschlagen', () {
      expect(tab.contains('massnahmeOrtVorschlag(a)'), isTrue);
    });

    // Ein bereits eingetragener Ort ist eine Angabe des Vorsitzenden und
    // darf nicht von einem Vorschlag überschrieben werden.
    test('ein vorhandener Ort wird nicht überschrieben', () {
      expect(tab.contains("if (_ort.text.trim().isEmpty)"), isTrue);
    });
  });
}

void _vorbelegungPruefungen() {
  final tab = File('lib/widgets/jobcenter_massnahme_tab.dart').readAsStringSync();

  group('Kundennummer aus dem Aktenzeichen', () {
    test('wird nach dem letzten Bindestrich gelesen', () {
      expect(massnahmeKundennummerAus('481.O-819D168082'), '819D168082');
    });

    // ⚠️ Lieber leer als geraten: eine falsche Kundennummer stünde später in
    // einem Widerspruch und fiele dort niemandem mehr auf.
    test('was nicht wie eine Kundennummer aussieht, wird nicht geraten', () {
      for (final s in ['481.O-irgendwas', 'ohne-Bindestrich', '', '123-456']) {
        expect(massnahmeKundennummerAus(s), '', reason: s);
      }
    });
  });

  group('Ende aus der Laufzeit', () {
    test('Beginn plus Wochen, letzter Tag inklusive', () {
      // 14.09. + 11 Wochen = 77 Tage; der letzte Tag zählt mit
      expect(massnahmeEndeVorschlag(DateTime(2026, 9, 14), 11), DateTime(2026, 11, 29));
    });

    test('ohne Beginn oder ohne Laufzeit wird nichts vorgeschlagen', () {
      expect(massnahmeEndeVorschlag(null, 11), isNull);
      expect(massnahmeEndeVorschlag(DateTime(2026, 9, 14), null), isNull);
      expect(massnahmeEndeVorschlag(DateTime(2026, 9, 14), 0), isNull);
    });

    test('nimmt die Wochenzahl auch als String (PDO liefert beides)', () {
      expect(massnahmeEndeVorschlag(DateTime(2026, 9, 14), '11'), DateTime(2026, 11, 29));
    });
  });

  group('Verdrahtung der Vorbelegung', () {
    test('alle vier Quellen werden benutzt', () {
      for (final q in [
        "widget.userAv['mein_zeichen']",           // Aktenzeichen
        "massnahmeKundennummerAus(az)",            // Kundennummer
        "a['stunden_woche']",                      // Stunden aus dem Angebot
        "massnahmeEndeVorschlag(",                 // Ende aus der Laufzeit
      ]) {
        expect(tab.contains(q), isTrue, reason: 'nicht vorbelegt: $q');
      }
    });

    // Jede Vorbelegung ist ein Vorschlag, kein Überschreiben.
    test('kein Feld wird überschrieben, wenn schon etwas drinsteht', () {
      for (final f in ['_ort', '_stunden', '_ende', '_nummer']) {
        expect(tab.contains('if ($f.text.trim().isEmpty)'), isTrue, reason: f);
      }
    });
  });
}

void _statusVeraltetPruefungen() {
  group('Status passt nicht mehr zu den Daten', () {
    test('offen und Ende vorbei -> Hinweis', () {
      expect(massnahmeStatusVeraltet('zugewiesen', DateTime(2026, 12, 3),
          heute: DateTime(2026, 12, 4)), isTrue);
    });

    test('am Endtag selbst noch kein Hinweis', () {
      expect(massnahmeStatusVeraltet('laufend', DateTime(2026, 12, 3),
          heute: DateTime(2026, 12, 3)), isFalse);
    });

    test('abgeschlossene Zustände lösen nie aus', () {
      for (final s in ['beendet', 'abgebrochen', 'abgelehnt']) {
        expect(massnahmeStatusVeraltet(s, DateTime(2020, 1, 1)), isFalse, reason: s);
      }
    });

    test('ohne Ende kein Hinweis', () {
      expect(massnahmeStatusVeraltet('zugewiesen', null), isFalse);
    });

    // ⚠️ Der Status wird NICHT automatisch gesetzt: „beendet" und
    // „abgebrochen" haben nach §§ 31 ff. SGB II verschiedene Folgen, und
    // welcher zutrifft, weiß nur der Vorstand.
    test('es wird nur hingewiesen, nicht fortgeschrieben', () {
      final tab = File('lib/widgets/jobcenter_massnahme_tab.dart').readAsStringSync();
      expect(tab.contains('massnahmeStatusVeraltet(status, ende)'), isTrue);
      expect(tab.contains("_status = 'beendet'"), isFalse,
          reason: 'der Status darf nicht automatisch gesetzt werden');
    });
  });
}
