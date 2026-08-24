import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/landratsamt_antraege.dart';

/// Die 18 Titel der ersten Fassung des Vorfall-Katalogs.
///
/// ⚠️ Diese Liste steht hier absichtlich als Literal und wird NICHT aus dem
/// Katalog erzeugt — sonst würde sie sich selbst bestätigen. `art` wird als
/// Klartext in `landratsamt_vorfaelle` gespeichert; verschwindet einer dieser
/// Titel aus dem Katalog, findet der Auswahldialog bestehende Vorfälle nicht
/// mehr wieder und zeigt sie als „freien Text".
const _titelDerErstenFassung = <String>[
  'Verfahrensbetreuung (Anordnung Betreuungsgericht)',
  'Betreuungsanregung',
  'Sozialbericht / Stellungnahme an Gericht',
  'Hausbesuch / Ermittlung',
  'Beratung Betroffene/r',
  'Beratung Angehörige',
  'Begleitung Anhörung Betreuungsgericht',
  'Vorsorgevollmacht / Betreuungsverfügung — Beglaubigung (§ 7 BtOG)',
  'Schuldner-/Insolvenzberatung — Erstberatung',
  'Schuldnerberatung — Gläubigerübersicht / Forderungsaufstellung',
  'Schuldnerberatung — Schuldenbereinigungsplan erstellen',
  'Schuldnerberatung — Außergerichtlicher Einigungsversuch (§ 305 InsO)',
  'Insolvenzantrag — Bescheinigung § 305 Abs. 1 Nr. 1 InsO ausgestellt',
  'Insolvenzantrag — Antrag an Insolvenzgericht eingereicht',
  'P-Konto-Bescheinigung ausgestellt',
  'Grundsicherung im Alter / bei Erwerbsminderung (SGB XII Kap. 4)',
  'Hilfe zum Lebensunterhalt (SGB XII Kap. 3)',
  'Sonstiges',
];

void main() {
  group('Landratsamt-Antragskatalog', () {
    test('kein Titel der ersten Fassung ist verlorengegangen', () {
      final titel = landratsamtAntragTitel().toSet();
      for (final alt in _titelDerErstenFassung) {
        expect(titel, contains(alt),
            reason: 'Titel "$alt" fehlt — bestehende Vorfälle in der Datenbank '
                'wären damit nicht mehr auffindbar. Titel nie umbenennen, nur ergänzen.');
      }
    });

    test('keine doppelten Titel', () {
      final titel = landratsamtAntragTitel();
      expect(titel.toSet().length, titel.length,
          reason: 'Ein doppelter Titel erscheint zweimal im Dialog und macht '
              'nicht erkennbar, welcher Eintrag gemeint war.');
    });

    test('jede Gruppe im Katalog steht auch in kLandratsamtGruppen', () {
      // Sonst fiele der Eintrag im Suchdialog lautlos aus der Anzeige: der
      // Dialog läuft über kLandratsamtGruppen, nicht über den Katalog.
      final bekannt = kLandratsamtGruppen.toSet();
      for (final a in kLandratsamtAntraege) {
        expect(bekannt, contains(a.gruppe), reason: 'Gruppe "${a.gruppe}" von "${a.titel}"');
      }
    });

    test('jede Gruppe hat mindestens einen Eintrag', () {
      for (final g in kLandratsamtGruppen) {
        expect(landratsamtAntraegeDerGruppe(g), isNotEmpty, reason: 'Gruppe "$g" ist leer');
      }
    });

    test('kein Titel ist leer oder hat Rand-Leerzeichen', () {
      for (final a in kLandratsamtAntraege) {
        expect(a.titel.trim(), a.titel, reason: '"${a.titel}" hat Rand-Leerzeichen');
        expect(a.titel, isNotEmpty);
      }
    });

    test('"Sonstiges" bleibt erhalten', () {
      // Der Auffangwert. Ohne ihn müsste man einen unpassenden Vorgang
      // erfinden, um überhaupt speichern zu können.
      expect(landratsamtAntragFinden('Sonstiges'), isNotNull);
    });

    group('Zuständigkeitswarnungen', () {
      // Diese drei sind der Grund, warum es das Feld hinweis überhaupt gibt:
      // in Bayern ist für alle drei NICHT das Landratsamt zuständig.
      // Verschwindet der Hinweis, reicht jemand am falschen Ort ein.
      test('Schwerbehindertenausweis warnt vor dem ZBFS', () {
        final a = landratsamtAntragFinden(
            'Schwerbehindertenausweis — Antrag / Verschlimmerungsantrag');
        expect(a, isNotNull);
        expect(a!.hinweis, contains('ZBFS'));
        expect(a.hinweis, contains('Bayern'));
        expect(a.streng, isTrue);
      });

      test('Eingliederungshilfe warnt vor dem Bezirk', () {
        final a = landratsamtAntragFinden('Eingliederungshilfe — Antrag');
        expect(a, isNotNull);
        expect(a!.hinweis, contains('BEZIRK'));
        expect(a.streng, isTrue);
      });

      test('Hilfe zur Pflege warnt vor dem Bezirk', () {
        final a = landratsamtAntragFinden('Hilfe zur Pflege — Antrag');
        expect(a, isNotNull);
        expect(a!.hinweis, contains('BEZIRK'));
        expect(a.streng, isTrue);
      });

      test('streng setzt immer auch einen Hinweis', () {
        // Ein rotes Warndreieck ohne Text sagt nur „irgendwas stimmt nicht".
        for (final a in kLandratsamtAntraege.where((x) => x.streng)) {
          expect(a.hinweis, isNotNull, reason: '"${a.titel}" ist streng ohne Hinweis');
        }
      });

      test('kein Warn-Emoji mehr im Hinweistext', () {
        // Das Widget setzt das Symbol selbst; ein Emoji daneben wäre doppelt
        // und wird auf manchen Geräten zum leeren Kästchen.
        for (final a in kLandratsamtAntraege) {
          expect(a.hinweis ?? '', isNot(contains('\u26A0')), reason: a.titel);
        }
      });
    });

    group('Suche', () {
      test('leere Suche liefert den ganzen Katalog', () {
        expect(landratsamtAntraegeSuchen('').length, kLandratsamtAntraege.length);
        expect(landratsamtAntraegeSuchen('   ').length, kLandratsamtAntraege.length);
      });

      test('findet über den Titel, unabhängig von Groß-/Kleinschreibung', () {
        final t = landratsamtAntraegeSuchen('FÜHRERSCHEIN');
        expect(t, isNotEmpty);
        expect(t.every((a) =>
            a.titel.toLowerCase().contains('führerschein') ||
            a.gruppe.toLowerCase().contains('führerschein') ||
            (a.recht?.toLowerCase().contains('führerschein') ?? false)), isTrue);
      });

      test('findet über den Paragrafen', () {
        // Wer einen Bescheid vor sich hat, liest dort den Paragrafen und
        // nicht unsere Überschrift.
        final t = landratsamtAntraegeSuchen('35a');
        expect(t.map((a) => a.titel),
            contains('Eingliederungshilfe für seelisch behinderte Kinder (§ 35a SGB VIII)'));
      });

      test('findet über den Fachbereich', () {
        expect(landratsamtAntraegeSuchen(kLraWaffen), isNotEmpty);
      });

      test('liefert bei Unsinn eine leere Liste, nicht den ganzen Katalog', () {
        expect(landratsamtAntraegeSuchen('qwertzuiop'), isEmpty);
      });
    });

    test('landratsamtAntragFinden ist bei unbekanntem Wert null, nicht Fehler', () {
      // Ein Wert aus einer älteren Fassung darf die Detailansicht nicht
      // umbringen — er wird als freier Text angezeigt.
      expect(landratsamtAntragFinden('Irgendwas von 2019'), isNull);
      expect(landratsamtAntragFinden(null), isNull);
      expect(landratsamtAntragFinden(''), isNull);
    });
  });
}
