// Warum es diesen Filter gibt — gemessen am 14.08.2026 um 23:07,
// Saarbrücken → Ulm mit Deutschlandticket. Ganz oben stand:
//
//   02:23  Fußweg, dann Tram 1 für DREI Minuten
//          danach 36 Minuten Wartezeit
//   03:06  Nachtbus N2 …            Ankunft 10:51, 6× umsteigen
//
// und weiter unten in derselben Liste dieselbe Fahrt ohne den Vorspann:
//
//   02:54  Fußweg zum selben Halt
//   03:06  derselbe Nachtbus N2 …   Ankunft 10:51, 5× umsteigen
//
// Beide erreichen denselben Bus. Die erste holt einen 31 Minuten früher aus
// dem Bett — für drei Minuten Straßenbahn und eine Dreiviertelstunde Warten.
// Sie stand oben, weil sie „am frühesten abfährt". Von aussen liest sich das
// wie eine erfundene Auskunft.

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/transit_service.dart';
import 'package:icd360sev_vorsitzer/utils/opnv_dominanz.dart';

DateTime _t(int h, int m) => DateTime(2026, 8, 15, h, m);

Journey _f({required DateTime ab, required DateTime an, required int umstiege}) {
  // umstiege+1 Fahrzeug-Etappen ⇒ transfers == umstiege
  final legs = [
    for (int i = 0; i <= umstiege; i++)
      JourneyLeg(
        line: 'L$i', direction: '', fromName: 'A', toName: 'B',
        depTime: ab, arrTime: an, productType: 'bus',
        productTypeVerlaesslich: true,
      ),
  ];
  return Journey(legs: legs, depTime: ab, arrTime: an);
}

void main() {
  group('entferneDominierte', () {
    test('der sinnlose Vorspann fliegt raus — der echte Fall', () {
      final mitVorspann = _f(ab: _t(2, 23), an: _t(10, 51), umstiege: 6);
      final ohneVorspann = _f(ab: _t(2, 54), an: _t(10, 51), umstiege: 5);

      final uebrig = entferneDominierte([mitVorspann, ohneVorspann]);

      expect(uebrig, [ohneVorspann]);
      expect(uebrig.first.depTime, _t(2, 54),
          reason: 'später losfahren, gleich früh ankommen, seltener umsteigen');
    });

    test('gleich gute Fahrt mit früherer Ankunft gewinnt', () {
      final spaeter = _f(ab: _t(8, 0), an: _t(12, 0), umstiege: 2);
      final frueher = _f(ab: _t(8, 0), an: _t(11, 0), umstiege: 2);
      expect(entferneDominierte([spaeter, frueher]), [frueher]);
    });

    test('weniger Umstiege bei sonst gleichen Zeiten gewinnt', () {
      final viele = _f(ab: _t(8, 0), an: _t(12, 0), umstiege: 4);
      final wenige = _f(ab: _t(8, 0), an: _t(12, 0), umstiege: 1);
      expect(entferneDominierte([viele, wenige]), [wenige]);
    });

    test('⚠️ ungleiche Vorteile werden NICHT gegeneinander abgewogen', () {
      // Später da, dafür seltener umsteigen — das darf der Fahrgast
      // entscheiden. Für jemanden im Rollstuhl kann ein Umstieg weniger
      // eine Stunde später wert sein.
      final schnellVieleUmstiege = _f(ab: _t(8, 0), an: _t(11, 0), umstiege: 5);
      final langsamDirekt = _f(ab: _t(8, 0), an: _t(12, 0), umstiege: 0);
      final uebrig = entferneDominierte([schnellVieleUmstiege, langsamDirekt]);
      expect(uebrig.length, 2);
    });

    test('eine frühere Abfahrt allein wird nicht bestraft', () {
      // Wer früher fährt UND früher ankommt, ist eine echte Alternative.
      final frueh = _f(ab: _t(6, 0), an: _t(10, 0), umstiege: 2);
      final spaet = _f(ab: _t(9, 0), an: _t(13, 0), umstiege: 2);
      expect(entferneDominierte([frueh, spaet]).length, 2);
    });

    test('gleiche Zeiten heissen nicht gleiche Fahrt — beide bleiben', () {
      // ⚠️ Hier wird verglichen, nicht dedupliziert. Zwei Fahrten mit
      // denselben Zeiten können über verschiedene Linien laufen, und welche
      // davon fährt, ist bei Verspätung oder Ausfall ein Unterschied. Sie
      // dürfen sich auch nicht gegenseitig hinauswerfen — sonst wäre die
      // Liste am Ende leer.
      final a = _f(ab: _t(8, 0), an: _t(12, 0), umstiege: 2);
      final b = _f(ab: _t(8, 0), an: _t(12, 0), umstiege: 2);
      final uebrig = entferneDominierte([a, b]);
      expect(uebrig.length, 2);
    });

    test('nie leer, egal was hereinkommt', () {
      for (final liste in <List<Journey>>[
        [],
        [_f(ab: _t(8, 0), an: _t(9, 0), umstiege: 0)],
        [
          _f(ab: _t(2, 23), an: _t(10, 51), umstiege: 6),
          _f(ab: _t(2, 54), an: _t(10, 51), umstiege: 5),
          _f(ab: _t(2, 54), an: _t(11, 43), umstiege: 4),
          _f(ab: _t(2, 23), an: _t(11, 43), umstiege: 5),
        ],
      ]) {
        final uebrig = entferneDominierte(liste);
        if (liste.isNotEmpty) expect(uebrig, isNotEmpty);
        expect(uebrig.length, lessThanOrEqualTo(liste.length));
      }
    });

    test('die echte Vierer-Liste schrumpft auf die zwei sinnvollen', () {
      // Genau das, was der Dienst geliefert hat.
      final a = _f(ab: _t(2, 23), an: _t(10, 51), umstiege: 6);
      final b = _f(ab: _t(2, 23), an: _t(11, 43), umstiege: 5);
      final c = _f(ab: _t(2, 54), an: _t(10, 51), umstiege: 5);
      final d = _f(ab: _t(2, 54), an: _t(11, 43), umstiege: 4);
      final uebrig = entferneDominierte([a, b, c, d]);
      expect(uebrig, [c, d]);
      expect(uebrig.every((j) => j.depTime == _t(2, 54)), isTrue);
    });

    test('Reihenfolge der Überlebenden bleibt wie geliefert', () {
      final c = _f(ab: _t(2, 54), an: _t(10, 51), umstiege: 5);
      final d = _f(ab: _t(2, 54), an: _t(11, 43), umstiege: 4);
      expect(entferneDominierte([c, d]), [c, d]);
    });
  });
}
