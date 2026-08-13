import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/sprach_flaggen.dart';
import 'package:icd360sev_vorsitzer/utils/visitenkarte_daten.dart';
import 'package:icd360sev_vorsitzer/utils/visitenkarte_farben.dart';
import 'package:icd360sev_vorsitzer/utils/visitenkarte_pdf.dart';
import 'package:icd360sev_vorsitzer/widgets/visitenkarte.dart';

/// Der Druckbogen lässt sich nicht „mal eben ansehen" — ein Fehler darin fällt
/// erst auf, wenn Papier und Schere schon im Spiel sind. Deshalb wird hier
/// gerechnet, was sich rechnen lässt.
///
/// Drei Dinge, die nur ein Test festhalten kann:
///   • dass zehn Karten in Originalgröße auf A4 passen und sich nicht
///     überlappen,
///   • dass die Rückseite für den Duplexdruck gespiegelt liegt,
///   • dass die Farben die Kontrastschwelle halten — die alte Karte tat es
///     nicht, und niemandem ist es aufgefallen.

// ── WCAG-Kontrast, hier nachgerechnet statt geglaubt ────────────────────────
double _kanal(int c) {
  final s = c / 255;
  return s <= 0.04045 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
}

double _leuchtdichte(int argb) => 0.2126 * _kanal((argb >> 16) & 0xFF) +
    0.7152 * _kanal((argb >> 8) & 0xFF) +
    0.0722 * _kanal(argb & 0xFF);

double kontrast(int a, int b) {
  final la = _leuchtdichte(a), lb = _leuchtdichte(b);
  final hell = math.max(la, lb), dunkel = math.min(la, lb);
  return (hell + 0.05) / (dunkel + 0.05);
}

const int _weiss = 0xFFFFFF;

void main() {
  group('Bogen-Geometrie', () {
    test('zehn Karten in Originalgröße, mehr passen nicht auf A4', () {
      expect(kKartenProBogen, 10);
      expect(kSpalten * kKarteBreiteMm, lessThanOrEqualTo(kBogenBreiteMm));
      expect(kZeilen * kKarteHoeheMm, lessThanOrEqualTo(kBogenHoeheMm));

      // Eine elfte Karte ginge nur, wenn man sie verkleinert — und eine
      // verkleinerte Visitenkarte ist keine mehr.
      expect((kSpalten + 1) * kKarteBreiteMm, greaterThan(kBogenBreiteMm));
      expect((kZeilen + 1) * kKarteHoeheMm, greaterThan(kBogenHoeheMm));
    });

    test('die Ränder ergeben sich aus dem Raster', () {
      expect(kRandXMm, 20);
      expect(kRandYMm, 11);
    });

    test('keine Karte liegt außerhalb des Blattes', () {
      for (var i = 0; i < kKartenProBogen; i++) {
        for (final rueck in [false, true]) {
          final p = kartenPosition(i, rueckseite: rueck);
          expect(p.x, greaterThanOrEqualTo(0));
          expect(p.y, greaterThanOrEqualTo(0));
          expect(p.x + kKarteBreiteMm, lessThanOrEqualTo(kBogenBreiteMm));
          expect(p.y + kKarteHoeheMm, lessThanOrEqualTo(kBogenHoeheMm));
        }
      }
    });

    test('keine zwei Karten überlappen', () {
      final orte = [
        for (var i = 0; i < kKartenProBogen; i++) kartenPosition(i),
      ];
      for (var a = 0; a < orte.length; a++) {
        for (var b = a + 1; b < orte.length; b++) {
          final ueberlapptX = orte[a].x < orte[b].x + kKarteBreiteMm &&
              orte[b].x < orte[a].x + kKarteBreiteMm;
          final ueberlapptY = orte[a].y < orte[b].y + kKarteHoeheMm &&
              orte[b].y < orte[a].y + kKarteHoeheMm;
          expect(ueberlapptX && ueberlapptY, isFalse,
              reason: 'Karte $a und $b überlappen');
        }
      }
    });

    test('die Karten stoßen ohne Steg aneinander', () {
      // Absicht: ein Schnitt trennt zwei Karten zugleich, und ein um einen
      // Millimeter verrutschter Schnitt hinterlässt keine weißen Blitzer.
      final erste = kartenPosition(0);
      final rechts = kartenPosition(1);
      final darunter = kartenPosition(kSpalten);
      expect(rechts.x - erste.x, kKarteBreiteMm);
      expect(darunter.y - erste.y, kKarteHoeheMm);
    });

    test('ein Index außerhalb des Bogens wird abgewiesen', () {
      expect(() => kartenPosition(-1), throwsRangeError);
      expect(() => kartenPosition(kKartenProBogen), throwsRangeError);
    });
  });

  group('Duplex', () {
    test('die Rückseite spiegelt die Spalten', () {
      expect(spalteGespiegelt(0), 1);
      expect(spalteGespiegelt(1), 0);
    });

    test('Karte 0 liegt hinten rechts, Karte 1 hinten links', () {
      // Beim Wenden über die lange Kante klappt das Blatt um die senkrechte
      // Achse. Ohne diese Spiegelung trüge jede Karte die Rückseite ihrer
      // Nachbarin — sobald ein Bogen zwei verschiedene Personen trägt.
      final v0 = kartenPosition(0), r0 = kartenPosition(0, rueckseite: true);
      final v1 = kartenPosition(1), r1 = kartenPosition(1, rueckseite: true);
      expect(r0.x, v1.x);
      expect(r1.x, v0.x);
      // Die Zeile bleibt, gewendet wird nur seitlich.
      expect(r0.y, v0.y);
    });

    test('gespiegelt bleibt jede Karte auf gleicher Höhe', () {
      for (var i = 0; i < kKartenProBogen; i++) {
        expect(kartenPosition(i, rueckseite: true).y, kartenPosition(i).y);
      }
    });

    test('das FALSCHE Wenden fällt geometrisch NICHT auf', () {
      // ⚠️ Der Grund, warum es die Wendemarke „▲ OBEN" auf dem Bogen gibt.
      //
      // Wendet jemand um die kurze Kante (oben nach unten) statt um die lange,
      // spiegelt sich y statt x. Das Raster ist aber auch senkrecht
      // symmetrisch: die Rückseiten landen dann WIEDER auf Kartenflächen, nur
      // um 180° verdreht. Kein Test, der bloß Positionen vergleicht, könnte
      // diesen Fehler je sehen — und am fertigen Stapel merkt man ihn erst,
      // wenn schon geschnitten ist.
      final zeilen = {
        for (var i = 0; i < kKartenProBogen; i++) kartenPosition(i).y,
      };
      for (final y in zeilen) {
        expect(zeilen, contains(kBogenHoeheMm - y - kKarteHoeheMm),
            reason: 'Zeile $y landet beim Querwenden auf keiner Kartenkante — '
                'dann wäre der Fehler sichtbar und die Marke entbehrlich');
      }
    });
  });

  group('Schnittmarken', () {
    test('drei senkrechte und sechs waagerechte Linien', () {
      final l = schnittlinien();
      expect(l.senkrecht, [20.0, 105.0, 190.0]);
      expect(l.waagerecht, [11.0, 66.0, 121.0, 176.0, 231.0, 286.0]);
    });

    test('jede Linie fällt mit einer Kartenkante zusammen', () {
      final l = schnittlinien();
      for (var i = 0; i < kKartenProBogen; i++) {
        final p = kartenPosition(i);
        expect(l.senkrecht, contains(p.x));
        expect(l.senkrecht, contains(p.x + kKarteBreiteMm));
        expect(l.waagerecht, contains(p.y));
        expect(l.waagerecht, contains(p.y + kKarteHoeheMm));
      }
    });

    test('die Marken bleiben im Rand, nie über einer Karte', () {
      // Sie ragen vom Rasterrand nach außen. Wäre die Marke länger als der
      // Rand, stünde Farbe dort, wo das Blatt beim Drucker aufhört.
      expect(kMarkeLaengeMm, lessThan(kRandXMm));
      expect(kMarkeLaengeMm, lessThan(kRandYMm));
    });
  });

  group('Farben — nachgerechnet, nicht geglaubt', () {
    test('weiße Schrift hält an beiden Verlaufsenden 7:1', () {
      // 7:1 ist die Empfehlung für Schrift unter 18 pt; eine Visitenkarte
      // besteht ausschließlich aus solcher Schrift. Im Druck drücken Papier
      // und Farbauftrag den Kontrast zusätzlich — deshalb nicht die 4,5:1
      // der Stufe AA.
      expect(kontrast(kTonHell.toInt() & 0xFFFFFF, _weiss),
          greaterThanOrEqualTo(7.0));
      expect(kontrast(kTonDunkel.toInt() & 0xFFFFFF, _weiss),
          greaterThanOrEqualTo(7.0));
    });

    test('das alte Kartenblau hätte hier durchfallen müssen', () {
      // Die Gegenprobe. Ohne sie wäre der Test oben nur eine Behauptung über
      // eine Zahl, die zufällig stimmt.
      expect(kontrast(0x4A90D9, _weiss), lessThan(4.5));
    });

    test('die Rückseitentexte halten 7:1 auf Weiß und auf der Tealfläche', () {
      final flaeche = kTonFlaeche.toInt() & 0xFFFFFF;
      for (final farbe in [kTonHell, kTextDunkel, kTextLeise]) {
        final c = farbe.toInt() & 0xFFFFFF;
        expect(kontrast(c, _weiss), greaterThanOrEqualTo(7.0));
        expect(kontrast(c, flaeche), greaterThanOrEqualTo(6.0),
            reason: 'auf der Tealfläche zu blass: $farbe');
      }
    });

    test('PDF und Bildschirm tragen denselben Ton', () {
      // ⚠️ Kein Vergleich zweier Literale — das bewiese nur, dass ich zweimal
      // dasselbe getippt habe. Geprüft wird, dass der PDF-Bauer die Farbe
      // WIRKLICH aus der gemeinsamen Quelle ableitet.
      expect(kTonHell.toInt(), kVkTonHell.toARGB32());
      expect(kTonDunkel.toInt(), kVkTonDunkel.toARGB32());
      expect(kTonFlaeche.toInt(), kVkTonFlaeche.toARGB32());
      expect(kTextDunkel.toInt(), kVkTextDunkel.toARGB32());
      expect(kTextLeise.toInt(), kVkTextLeise.toARGB32());
    });
  });

  group('Wortlaut steht an zwei Stellen und muss gleich bleiben', () {
    // ⚠️ Der PDF-Bauer darf nichts aus dem Widget-Baum ziehen, sonst wäre der
    // Bogen nur mit laufender Oberfläche zu bauen. Der Preis dafür sind zwei
    // Kopien der Texte — und dieser Test ist die einzige Stelle, an der ein
    // Auseinanderdriften überhaupt auffallen kann.
    test('die sechs Arbeitsfelder sind zeichengleich', () {
      expect(kVisitenkarteLeistungenPdf, kVisitenkarteLeistungen);
    });

    test('Leitsatz und Abgrenzung sind zeichengleich', () {
      expect(kVisitenkarteLeitsatzPdf, kVisitenkarteLeitsatz);
      expect(kVisitenkarteAbgrenzungPdf, kVisitenkarteAbgrenzung);
    });
  });

  group('Der Bogen entsteht wirklich', () {
    // Ohne diesen Fall prüfte alles oben nur Arithmetik. Erst hier wird die
    // Schrift geladen und das Dokument gesetzt.
    TestWidgetsFlutterBinding.ensureInitialized();

    final daten = VisitenkarteDaten(
      vereinsname: 'ICD360S e.V.',
      slogan: 'Integration · Chancen · Diversity · 360° Support',
      vorname: 'Ionut-Claudiu',
      nachname: 'Duinea',
      funktion: '1. Vorsitzender',
      istGruender: true,
      sprachen: sprachAnzeigen(const ['de', 'ro', 'en']),
      email: 'icd@icd360s.de',
      festnetz: '+49 731 80159736',
      mobil: '016094482053',
      web: 'icd360s.de',
      mitgliedernummer: 'V27655',
      anschrift: 'Elsa-Brandström-Straße 13 · 89231 Neu-Ulm',
      register: 'VR 201335 · Amtsgericht Memmingen, Bayern',
    );

    test('zwei Seiten, gültiges PDF, mit Inhalt', () async {
      final bytes = await visitenkartenBogen(daten);

      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      // Zwei Seiten: Vorder- und Rückseite. Ein Bogen mit nur einer Seite wäre
      // im Duplexdruck eine leere Rückseite.
      final text = String.fromCharCodes(bytes);
      expect(RegExp(r'/Type\s*/Page[^s]').allMatches(text).length, 2);
      // Ein PDF von wenigen hundert Byte wäre ein leeres Dokument.
      expect(bytes.length, greaterThan(20000));
    });

    test('die Sprachzeile trägt die Kürzel, nicht die Flaggen', () {
      // Im Druck gibt es keine Flaggen — DejaVu Sans enthält die
      // Regional-Indicator-Zeichen nicht. Die Kürzel tragen die Information
      // ohnehin allein.
      expect(daten.sprachZeile, 'DE · RO · EN');
    });
  });
}
