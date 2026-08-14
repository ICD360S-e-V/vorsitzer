import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' show TtfParser;

import 'package:icd360sev_vorsitzer/utils/flaggen.dart';
import 'package:icd360sev_vorsitzer/utils/visitenkarte_sprachen.dart';

/// Die Netze unter den 27 Sprachfassungen der Visitenkarte.
///
/// ⚠️ Kein Test hier kann beurteilen, **ob eine Übersetzung stimmt**. Sie
/// halten drei andere Dinge fest, an denen eine Fassung still kaputtgehen
/// kann:
///
/// 1. ein Zeichen, das die Druckschrift nicht kennt (sichtbar erst auf Papier),
/// 2. eine Fahne ohne Fassung oder eine Fassung ohne Fahne,
/// 3. eine Fassung, der ein Schlagwort fehlt.
///
/// Der vierte Fall — der Satz passt nicht mehr auf die Karte und der
/// PDF-Erzeuger wirft ihn stillschweigend weg — lässt sich hier nicht prüfen,
/// weil dafür der Bogen erzeugt und mit `pdftotext` gegengelesen werden muss.
/// Dafür gibt es die Messmappe; ihr Ergebnis steht als `schlagwortGrad` in der
/// Tabelle, und der Test unten hält wenigstens fest, dass niemand ihn
/// unbemerkt hochsetzt.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Zeichendeckung', () {
    late Set<int> regular;
    late Set<int> fett;

    setUpAll(() async {
      // ⚠️ Beide Schnitte, nicht nur einer. Sie decken nicht dasselbe ab, und
      // die Überschrift der Rückseite wird fett gesetzt.
      regular = TtfParser(await rootBundle.load('assets/fonts/DejaVuSans.ttf'))
          .charToGlyphIndexMap
          .keys
          .toSet();
      fett = TtfParser(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'))
          .charToGlyphIndexMap
          .keys
          .toSet();
    });

    test('DejaVu kennt jedes Zeichen jeder Sprachfassung', () {
      // Das Gegenstück zum GSM-7-Test der SMS-Vorlagen: ein fehlendes Zeichen
      // fällt sonst erst auf, wenn ein leeres Kästchen aus dem Drucker kommt —
      // auf 300 Karten gleichzeitig.
      final fehlend = <String, Set<String>>{};
      for (final e in kVisitenkarteSprachen.entries) {
        for (final text in e.value.alleTexte) {
          for (final rune in text.runes) {
            if (!regular.contains(rune) || !fett.contains(rune)) {
              (fehlend[e.key] ??= {}).add(
                  '${String.fromCharCode(rune)} (U+${rune.toRadixString(16).toUpperCase().padLeft(4, '0')})');
            }
          }
        }
      }
      expect(fehlend, isEmpty,
          reason: 'Zeichen ohne Glyphe in DejaVu Sans: $fehlend');
    });

    test('auch die festen Zeichen der Karte sind gedeckt', () {
      // Diese stehen nicht in der Sprachtabelle, sondern fest im Erzeuger.
      for (final z in '·§—°–'.runes) {
        expect(regular.contains(z) && fett.contains(z), isTrue,
            reason: 'U+${z.toRadixString(16)} fehlt in DejaVu');
      }
    });
  });

  group('Vollzähligkeit', () {
    test('zu jeder Fahne gibt es eine Fassung und umgekehrt', () {
      // ⚠️ Ohne Fahne gäbe es keinen Knopf, ohne Fassung führte ein Knopf
      // stillschweigend auf die deutsche Karte — der Nutzer sähe, dass er
      // gewählt hat, und bekäme trotzdem Deutsch.
      expect(kVisitenkarteSprachen.keys.toSet(), kFlaggenCodes);
    });

    test('jede Fassung trägt genau 22 Schlagwörter', () {
      // Sie stammen aus § 2 und § 3 der Satzung. Eines weniger wäre eine
      // Leistung, die auf der fremdsprachigen Karte fehlt.
      for (final e in kVisitenkarteSprachen.entries) {
        expect(e.value.schlagworte.length, 22, reason: e.key);
      }
    });

    test('kein Feld ist leer', () {
      for (final e in kVisitenkarteSprachen.entries) {
        for (final t in e.value.alleTexte) {
          expect(t.trim(), isNotEmpty, reason: '${e.key}: leeres Feld');
        }
      }
    });

    test('keine Fassung hat versehentlich deutsche Schlagwörter geerbt', () {
      // Ein kopierter Block, bei dem jemand das Übersetzen vergisst, sähe
      // sonst aus wie eine fertige Sprache.
      final de = kVisitenkarteSprachen['de']!;
      for (final e in kVisitenkarteSprachen.entries) {
        if (e.key == 'de') continue;
        expect(e.value.schlagworte, isNot(equals(de.schlagworte)),
            reason: '${e.key} trägt die deutschen Schlagwörter');
        expect(e.value.leitsatz, isNot(de.leitsatz), reason: e.key);
        expect(e.value.abgrenzung, isNot(de.abgrenzung), reason: e.key);
      }
    });
  });

  group('Schlagwortgrad', () {
    test('bleibt zwischen 5 und 7 pt', () {
      // Nach oben ist 7 der Wert, bei dem die deutsche Karte gesetzt ist; wer
      // höher geht, verliert am unteren Rand still die Fußzeile. Nach unten
      // wäre es nicht mehr lesbar — und lesbar sein ist bei diesem Verein
      // keine Feinheit.
      for (final e in kVisitenkarteSprachen.entries) {
        expect(e.value.schlagwortGrad, inInclusiveRange(5.0, 7.0),
            reason: e.key);
      }
    });

    test('die gemessenen Ausnahmen stehen fest', () {
      // ⚠️ Diese sieben Werte sind gemessen, nicht gewählt: je Sprache der
      // größte Grad, bei dem noch jedes Feld zehnmal auf dem Bogen steht.
      // Ändert jemand eine Übersetzung, muss die Messmappe erneut laufen —
      // dieser Test sagt dann, dass er es nicht getan hat.
      const gemessen = {
        'pl': 6.0,
        'ru': 6.4,
        'bg': 6.6,
        'pt': 6.6,
        'fr': 6.7,
        'uk': 6.8,
      };
      for (final e in gemessen.entries) {
        expect(kVisitenkarteSprachen[e.key]!.schlagwortGrad, e.value,
            reason: e.key);
      }
      for (final e in kVisitenkarteSprachen.entries) {
        if (gemessen.containsKey(e.key)) continue;
        expect(e.value.schlagwortGrad, 7.0,
            reason: '${e.key} weicht ab, ohne in der Messliste zu stehen');
      }
    });
  });

  group('amtsbezeichnung', () {
    test('setzt die Nummer dorthin, wo die Sprache sie haben will', () {
      final de = kVisitenkarteSprachen['de']!;
      final ro = kVisitenkarteSprachen['ro']!;
      expect(
          amtsbezeichnung(de,
              rolleKey: 'vorsitzer', anredeform: 'herr', vorsitzNr: 1),
          '1. Vorsitzender');
      // ⚠️ Rumänisch stellt die Nummer nach: „Președinte 1". Ohne Platzhalter
      // käme „1. Președinte" heraus, was niemand so schreibt.
      expect(
          amtsbezeichnung(ro,
              rolleKey: 'vorsitzer', anredeform: 'herr', vorsitzNr: 1),
          'Președinte 1');
    });

    test('ohne Nummer bleibt kein Punkt und kein Leerzeichen stehen', () {
      // Ein dritter Vorsitz bekommt vom Server `null` statt einer erfundenen
      // „3." — dann darf auf der Karte nicht „. Vorsitzender" stehen.
      for (final e in kVisitenkarteSprachen.entries) {
        final s = amtsbezeichnung(e.value,
            rolleKey: 'vorsitzer', anredeform: 'herr', vorsitzNr: null);
        expect(s.startsWith('.'), isFalse, reason: e.key);
        expect(s.trim(), s, reason: e.key);
        expect(s, isNot(contains('{n}')), reason: e.key);
        expect(s.trim(), isNotEmpty, reason: e.key);
      }
    });

    test('unterscheidet die Anredeformen', () {
      final de = kVisitenkarteSprachen['de']!;
      expect(
          amtsbezeichnung(de,
              rolleKey: 'vorsitzer', anredeform: 'frau', vorsitzNr: 2),
          '2. Vorsitzende');
      expect(
          amtsbezeichnung(de,
              rolleKey: 'vorsitzer', anredeform: 'neutral', vorsitzNr: 2),
          '2. Vorsitz');
      expect(
          amtsbezeichnung(de, rolleKey: 'schatzmeister', anredeform: 'frau'),
          'Schatzmeisterin');
    });

    test('eine unbekannte Rolle wird Mitglied, nicht die rohe Rolle', () {
      // „mitgliedergrunder" auf einer Visitenkarte wäre schlimmer als ein zu
      // allgemeines, aber richtiges Wort.
      final de = kVisitenkarteSprachen['de']!;
      expect(amtsbezeichnung(de, rolleKey: 'irgendwas', anredeform: 'herr'),
          'Mitglied');
      expect(amtsbezeichnung(de, rolleKey: '', anredeform: 'herr'), 'Mitglied');
    });
  });

  group('visitenkarteTexte', () {
    test('fällt auf Deutsch zurück statt leer zu bleiben', () {
      // Eine Karte ohne Rückseitentext wäre schlimmer als eine deutsche.
      expect(visitenkarteTexte('xx').ueberschrift, 'Was wir tun');
      expect(visitenkarteTexte(null).ueberschrift, 'Was wir tun');
      expect(visitenkarteTexte('').ueberschrift, 'Was wir tun');
    });

    test('nimmt es mit Groß- und Kleinschreibung nicht genau', () {
      expect(visitenkarteTexte('RO').ueberschrift, 'Ce facem');
      expect(visitenkarteTexte(' ro ').ueberschrift, 'Ce facem');
    });
  });
}
