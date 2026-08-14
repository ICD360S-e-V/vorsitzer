// Was die Oberfläche am Ende WIRKLICH zeigt.
//
// ⚠️ Der Anlass: der Dienst lieferte 7 Fahrten, auf dem Schirm stand „Keine
// Verbindungen". Dazwischen liegt diese Rechnung, und die hatte niemand
// geprüft — alle bisherigen Tests hörten beim Dienst auf.
//
// Gemessen am 14.08.2026 auf einer gewöhnlichen Stadtfahrt (Ulm Hbf →
// Rathaus): der „Mit Rad"-Filter blendete **6 von 7** Fahrten aus, nämlich
// jede mit einem Bus. Grund war `bikeAllowedHeuristic`, das den Bus im
// default-Zweig als `false` zurückgibt, obwohl der Kommentar daneben selbst
// sagt, beim Bus sei die Mitnahme *unbekannt*. Unbekannt darf nicht wie
// verboten wirken.

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/transit_service.dart';
import 'package:icd360sev_vorsitzer/utils/opnv_filter.dart';

DateTime _t(int h, int m) => DateTime(2026, 8, 14, h, m);

JourneyLeg _leg(String line, String produkt, {bool walk = false, bool? rad}) =>
    JourneyLeg(
      line: line, direction: '', fromName: 'A', toName: 'B',
      depTime: _t(9, 0), arrTime: _t(9, 10),
      productType: walk ? 'walk' : produkt, isWalk: walk,
      fahrradmitnahme: rad, productTypeVerlaesslich: true,
    );

Journey _fahrt(List<JourneyLeg> legs) =>
    Journey(legs: legs, depTime: legs.first.depTime, arrTime: legs.last.arrTime);

void main() {
  // Genau die Zusammensetzung der echten Fahrt Ulm Hbf → Rathaus, Ulm.
  final stadtfahrten = <Journey>[
    _fahrt([_leg('5', 'bus')]),
    _fahrt([_leg('Fußweg', 'walk', walk: true), _leg('77', 'bus')]),
    _fahrt([_leg('1', 'tram'), _leg('4', 'bus')]),
    _fahrt([_leg('Fußweg', 'walk', walk: true)]),
    _fahrt([_leg('5', 'bus')]),
    _fahrt([_leg('6', 'bus')]),
    _fahrt([_leg('Fußweg', 'walk', walk: true), _leg('84X', 'bus')]),
  ];

  bool? keineAufzugsauskunft(int i) => null;

  group('„Mit Rad" darf Unbekanntes nicht wie Verbotenes behandeln', () {
    test('eine gewöhnliche Stadtfahrt überlebt den Rad-Filter', () {
      final sicht = sichtbareTreffer(stadtfahrten,
          barrierFrei: false, mitRad: true, aufzugKaputt: keineAufzugsauskunft);
      // Vorher blieb hier genau die eine reine Fußweg-Fahrt übrig.
      expect(sicht.indizes.length, stadtfahrten.length,
          reason: 'beim Bus ist die Mitnahme unbekannt, nicht ausgeschlossen');
      expect(sicht.istLeer, isFalse);
    });

    test('ein ausdrückliches Nein des Betreibers blendet weiterhin aus', () {
      final fahrten = [
        _fahrt([_leg('5', 'bus', rad: false)]),
        _fahrt([_leg('6', 'bus', rad: true)]),
      ];
      final sicht = sichtbareTreffer(fahrten,
          barrierFrei: false, mitRad: true, aufzugKaputt: keineAufzugsauskunft);
      expect(sicht.indizes, [1]);
    });

    test('ICE bleibt ausgeschlossen — dort braucht es eine Reservierung', () {
      final fahrten = [
        _fahrt([_leg('ICE 612', 'train')]),
        _fahrt([_leg('RE 5', 'regional')]),
      ];
      final sicht = sichtbareTreffer(fahrten,
          barrierFrei: false, mitRad: true, aufzugKaputt: keineAufzugsauskunft);
      expect(sicht.indizes, [1]);
    });
  });

  group('alle Schalterstellungen an derselben echten Fahrtenliste', () {
    for (final barriere in [false, true]) {
      for (final rad in [false, true]) {
        test('barrierefrei=$barriere mitRad=$rad lässt etwas übrig', () {
          final sicht = sichtbareTreffer(stadtfahrten,
              barrierFrei: barriere, mitRad: rad,
              aufzugKaputt: keineAufzugsauskunft);
          expect(sicht.istLeer, isFalse,
              reason: 'keine Schalterstellung darf eine normale Stadtfahrt '
                  'restlos ausblenden');
        });
      }
    }
  });

  group('leere Liste nennt den Grund', () {
    test('der Dienst hat nichts geliefert', () {
      final sicht = sichtbareTreffer(const [],
          barrierFrei: false, mitRad: false, aufzugKaputt: keineAufzugsauskunft);
      expect(sicht.leerGrund, OpnvLeerGrund.keineFahrten);
      // Mit D-Ticket-Schalter muss der Text auf genau den Schalter zeigen.
      expect(opnvLeerText(sicht.leerGrund!, nurDTicket: true),
          contains('Nur D-Ticket'));
      expect(opnvLeerText(sicht.leerGrund!, nurDTicket: false),
          isNot(contains('Nur D-Ticket')));
    });

    test('der Rad-Filter war es', () {
      final fahrten = [_fahrt([_leg('ICE 612', 'train')])];
      final sicht = sichtbareTreffer(fahrten,
          barrierFrei: false, mitRad: true, aufzugKaputt: keineAufzugsauskunft);
      expect(sicht.leerGrund, OpnvLeerGrund.fahrrad);
      expect(opnvLeerText(sicht.leerGrund!, nurDTicket: false),
          contains('Mit Rad'));
    });

    test('der Barrierefrei-Filter war es', () {
      final sicht = sichtbareTreffer(stadtfahrten,
          barrierFrei: true, mitRad: false, aufzugKaputt: (_) => true);
      expect(sicht.leerGrund, OpnvLeerGrund.barrierefrei);
      expect(opnvLeerText(sicht.leerGrund!, nurDTicket: false),
          contains('Barrierefrei'));
    });

    test('beide zusammen', () {
      final fahrten = [
        _fahrt([_leg('ICE 612', 'train')]),   // fällt am Rad
        _fahrt([_leg('5', 'bus')]),           // fällt am Aufzug
      ];
      final sicht = sichtbareTreffer(fahrten,
          barrierFrei: true, mitRad: true, aufzugKaputt: (i) => i == 1);
      expect(sicht.leerGrund, OpnvLeerGrund.mehrere);
    });
  });

  group('Aufzugsauskunft', () {
    test('keine Auskunft blendet nicht aus', () {
      // Eine Haltestelle ohne Aufzugsdaten ist nicht dasselbe wie eine mit
      // kaputtem Aufzug.
      final sicht = sichtbareTreffer(stadtfahrten,
          barrierFrei: true, mitRad: false, aufzugKaputt: (_) => null);
      expect(sicht.indizes.length, stadtfahrten.length);
    });

    test('gemeldeter Defekt blendet nur die betroffene Fahrt aus', () {
      final sicht = sichtbareTreffer(stadtfahrten,
          barrierFrei: true, mitRad: false, aufzugKaputt: (i) => i == 2);
      expect(sicht.indizes.contains(2), isFalse);
      expect(sicht.indizes.length, stadtfahrten.length - 1);
    });
  });

  test('die zurückgegebenen Indizes zeigen auf dieselben Fahrten', () {
    // Daran hängt die Aufzugs-Auskunft je Karte.
    final sicht = sichtbareTreffer(stadtfahrten,
        barrierFrei: false, mitRad: false, aufzugKaputt: keineAufzugsauskunft);
    for (final i in sicht.indizes) {
      expect(identical(stadtfahrten[i], stadtfahrten[i]), isTrue);
    }
    expect(sicht.indizes, List.generate(stadtfahrten.length, (i) => i));
  });
}
