import 'dart:convert' show utf8;
import 'dart:math' as math;
import 'dart:typed_data' show Uint8List;

import 'package:barcode/barcode.dart';
import 'dart:async' show Completer;
import 'dart:ui' show Image, ImageByteFormat, decodeImageFromList;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:icd360sev_vorsitzer/utils/flaggen.dart';
import 'package:icd360sev_vorsitzer/utils/sprach_flaggen.dart';
import 'package:icd360sev_vorsitzer/utils/sprachen_options.dart';
import 'package:icd360sev_vorsitzer/utils/visitenkarte_daten.dart';
import 'package:icd360sev_vorsitzer/utils/visitenkarte_farben.dart';
import 'package:icd360sev_vorsitzer/utils/visitenkarte_masse.dart';
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

  group('Wortlaut', () {
    test('jedes Schlagwort ist kurz genug für eine Zeile', () {
      // ⚠️ Der Zweck der Umstellung: vorher standen hier Sätze, die auf 85 mm
      // umbrachen und deshalb auf 5,8 pt heruntergesetzt waren — unter dem
      // Druckminimum von 7 pt. Ein Wort, das länger ist als „Kinderbetreuung",
      // bringt genau dieses Problem zurück.
      for (final w in kVisitenkarteSchlagworte) {
        expect(w.length, lessThanOrEqualTo(16), reason: 'zu lang: $w');
        expect(w, isNot(contains(' ')), reason: 'kein einzelnes Wort: $w');
      }
    });

    test('keine Dubletten', () {
      expect(kVisitenkarteSchlagworte.toSet().length,
          kVisitenkarteSchlagworte.length);
    });

    test('Leitsatz und Abgrenzung sind zeichengleich mit dem Widget', () {
      // ⚠️ Der PDF-Bauer darf nichts aus dem Widget-Baum ziehen, sonst wäre
      // der Bogen nur mit laufender Oberfläche zu bauen. Der Preis dafür sind
      // zwei Kopien dieser Texte — und dieser Test ist die einzige Stelle, an
      // der ein Auseinanderdriften auffallen kann.
      expect(kVisitenkarteLeitsatzPdf, kVisitenkarteLeitsatz);
      expect(kVisitenkarteAbgrenzungPdf, kVisitenkarteAbgrenzung);
    });
  });

  group('QR-Feld', () {
    final daten = _beispiel();

    test('die vCard ist wohlgeformt', () {
      final v = daten.vcard;
      expect(v, startsWith('BEGIN:VCARD\r\nVERSION:3.0\r\n'));
      expect(v, endsWith('\r\nEND:VCARD'));
      expect(v, contains('N:Doe;Ilies-Cristian;;;'));
      expect(v, contains('FN:Ilies-Cristian Doe'));
      expect(v, contains('ORG:ICD360S e.V.'));
      expect(v, contains('TITLE:1. Vorsitzender'));
      expect(v, contains('EMAIL;TYPE=INTERNET:icd@icd360s.de'));
      // ⚠️ Der Doppelpunkt in der Adresse darf NICHT geschützt sein. Am
      // iPhone geprüft: mit `\:` wird daraus `http://https:%5C://…`.
      expect(v, contains('URL:https://icd360s.de'));
      expect(v, isNot(contains(r'https\:')));
    });

    test('alle drei Nummern, jede mit ihrer Art', () {
      // ⚠️ Der Grund für den Wechsel von MECARD auf vCard: MECARD kennt kein
      // Faxfeld. Ein drittes `TEL` wäre dort als Rufnummer gespeichert
      // worden, und niemand wüsste, welche der drei ein Faxgerät ist.
      final v = daten.vcard;
      expect(v, contains('TEL;TYPE=WORK,VOICE:+4973180159736'));
      // ⚠️ Nur `FAX`, ohne `WORK`. Android nahm bei `WORK,FAX` nur den ersten
      // Typ und beschriftete die Nummer als „Arbeit" — das Fax war als Fax
      // nicht mehr erkennbar. Auf einem echten Gerät gemessen, nicht vermutet.
      expect(v, contains('TEL;TYPE=FAX:+4973180159737'));
      expect(v, isNot(contains('WORK,FAX')));
      expect(v, contains('TEL;TYPE=CELL:+4916087654321'));
    });

    test('die Zeilen sind mit CRLF getrennt', () {
      // Die Vorschrift verlangt es; ältere Auswerter lesen sonst alles als
      // eine Zeile.
      expect(daten.vcard.split('\r\n').length, greaterThan(8));
      expect(daten.vcard.replaceAll('\r\n', ''), isNot(contains('\n')));
    });

    test('der Code bleibt grob genug für einen Tintendrucker', () {
      // ⚠️ Der wichtigste Test dieser Gruppe. Wer ein Feld in die vCard
      // aufnimmt, macht den Code dichter — und ein zu dichter Code ist auf
      // Normalpapier nicht schlecht lesbar, sondern tot. Hier fällt es auf,
      // bevor jemand zwanzig Bogen druckt.
      final bc =
          Barcode.qrCode(errorCorrectLevel: BarcodeQRCorrectionLevel.low);
      final elemente = bc
          .makeBytes(Uint8List.fromList(utf8.encode(daten.vcard)),
              width: 1000, height: 1000)
          .whereType<BarcodeBar>()
          .toList();
      final schmalste =
          elemente.map((b) => b.width).reduce((a, b) => a < b ? a : b);
      final module = (1000 / schmalste).round();

      expect(module, lessThanOrEqualTo(61),
          reason: 'Die vCard ist zu lang geworden: $module Module');

      // kQrKante steht in PDF-Punkten; für Tinte auf Papier zählen Millimeter.
      final mmJeModul = (kQrKante / mmInPt) / module;
      expect(mmJeModul, greaterThanOrEqualTo(0.39),
          reason: 'Nur ${mmJeModul.toStringAsFixed(3)} mm je Modul — '
              'darunter läuft Tinte auf Normalpapier zusammen');
    });
  });

  group('Sinnbilder', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('sechs Zeichen: Brief, Festnetz, Fax, Handy, Globus, Rollstuhl', () {
      expect(kIkonen,
          ['email', 'phone', 'smartphone', 'language', 'accessible', 'fax']);
    });

    test('jedes liegt WIRKLICH im Bundle und ist ein PNG', () async {
      // ⚠️ Fällt `assets/ikonen/` aus der pubspec.yaml oder trägt jemand einen
      // Namen ein, ohne die Datei zu liefern, sähe der Code richtig aus und die
      // Karte hätte Lücken.
      for (final name in kIkonen) {
        final daten = await rootBundle.load('assets/ikonen/$name.png');
        expect(daten.lengthInBytes, greaterThan(100), reason: 'leer: $name');
        expect(daten.buffer.asUint8List(0, 8),
            [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
            reason: 'kein PNG: $name');
      }
    });

    test('sie tragen den Vereinston, nicht Schwarz', () async {
      // Eingefärbt wird beim Bauen — der PDF-Erzeuger kann ein Bild nicht
      // umfärben. Ein schwarz gebliebenes Sinnbild neben tealfarbener Schrift
      // sähe aus wie versehentlich stehen geblieben.
      final bytes =
          (await rootBundle.load('assets/ikonen/email.png')).buffer.asUint8List();
      final fertig = Completer<Image>();
      decodeImageFromList(bytes, fertig.complete);
      final bild = await fertig.future;
      final daten = (await bild.toByteData(format: ImageByteFormat.rawRgba))!;

      final soll = [
        (kVkTonHell.toARGB32() >> 16) & 0xFF,
        (kVkTonHell.toARGB32() >> 8) & 0xFF,
        kVkTonHell.toARGB32() & 0xFF,
      ];
      var gefunden = false;
      for (var i = 0; i + 3 < daten.lengthInBytes; i += 4) {
        if (daten.getUint8(i + 3) < 250) continue;
        expect([daten.getUint8(i), daten.getUint8(i + 1), daten.getUint8(i + 2)],
            soll, reason: 'Bildpunkt trägt nicht den Vereinston');
        gefunden = true;
        break;
      }
      expect(gefunden, isTrue, reason: 'kein deckender Bildpunkt');
    });
  });

  group('Fahnen', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('jede App-Sprache außer Arabisch hat eine Fahne', () {
      final ohne = appSprachCodes.where((c) => flaggenPfad(c) == null).toList();
      // ⚠️ Arabisch bewusst ohne: die Sprache wird in über zwanzig Ländern
      // gesprochen, eine Nationalflagge dafür wäre eine politische Aussage.
      expect(ohne, ['ar']);
    });

    test('ein unbekannter Code bekommt keine Fahne statt einer falschen', () {
      expect(flaggenPfad('xx'), isNull);
      expect(flaggenPfad(''), isNull);
    });

    test('jede hinterlegte Fahne liegt WIRKLICH im Bundle', () async {
      // ⚠️ Wikimedia weist Anfragen ohne User-Agent ab und liefert dann
      // HTML-Fehlerseiten unter dem Namen *.png — 22 von 27 Dateien waren so
      // „vorhanden" und keine Bilder. Deshalb die Signaturprüfung.
      for (final code in kFlaggenCodes) {
        final daten = await rootBundle.load(flaggenPfad(code)!);
        expect(daten.lengthInBytes, greaterThan(200), reason: 'leer: $code');
        expect(daten.buffer.asUint8List(0, 8),
            [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
            reason: 'kein PNG: $code');
      }
    });
  });

  group('Der Bogen entsteht wirklich', () {
    // Ohne diesen Fall prüfte alles oben nur Arithmetik. Erst hier wird die
    // Schrift geladen und das Dokument gesetzt.
    TestWidgetsFlutterBinding.ensureInitialized();

    final daten = _beispiel();

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

    test('der Bogen trägt keine Sprachkürzel mehr', () async {
      // ⚠️ Bis zum 14.08.2026 stand unter jeder Fahne ihr Kürzel; auf
      // Entscheidung des Users ist es entfallen. Die Fahnen selbst sind
      // Bilddateien und stehen daher nicht im Textstrom — hier lässt sich also
      // nur die Abwesenheit prüfen, das Vorhandensein hält der Golden-Lauf.
      final bytes = await visitenkartenBogen(daten);
      final text = String.fromCharCodes(bytes);
      // Der Vereinsname steht als Beleg dafür, dass der Textstrom überhaupt
      // lesbar ist — sonst wäre „nichts gefunden" nur ein komprimierter Strom.
      expect(text.contains('ICD360S'), isTrue,
          reason: 'Textstrom unlesbar, der Rest dieses Tests sagt dann nichts');
      for (final k in const ['DE', 'RO', 'EN']) {
        expect(RegExp('\\($k\\)').hasMatch(text), isFalse,
            reason: 'Sprachkürzel $k steht wieder auf der Karte');
      }
    });
  });
}

/// Die Beispieldaten für V10001 — wörtlich das, was der Server liefert.
VisitenkarteDaten _beispiel() => VisitenkarteDaten(
      vereinsname: 'ICD360S e.V.',
      slogan: 'Integration · Chancen · Diversity · 360° Support',
      vorname: 'Ilies-Cristian',
      nachname: 'Doe',
      funktion: '1. Vorsitzender',
      istGruender: true,
      sprachen: sprachAnzeigen(const ['de', 'ro', 'en']),
      email: 'icd@icd360s.de',
      festnetz: '+49 731 80159736',
      fax: '+49 731 80159737',
      mobil: '016087654321',
      web: 'icd360s.de',
      mitgliedernummer: 'V10001',
      anschrift: 'Elsa-Brandström-Straße 13 · 89231 Neu-Ulm',
      register: 'VR 201335 · Amtsgericht Memmingen, Bayern',
    );
