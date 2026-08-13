// Fixiert die EFA-Parser auf ECHTE, ungekürzte Serverantworten.
//
// Hintergrund: am 13.08.2026 stellte sich heraus, dass „Verbindung suchen"
// für jede Station und jede Adresse nichts lieferte — bahn.de antwortet seit
// dem hinter Akamai Bot Manager auf jede Anfrage `403 OPS_BLOCKED`, und der
// Tab kannte seit der „Simplificare" vom 11.07.2026 keinen anderen Weg mehr.
// Der Ersatz läuft über EFA (MENTZ).
//
// ⚠️ Genau wie bei speedtest_antwort_test.dart gilt: kein einziger der
// bestehenden Tests berührte je eine echte Serverantwort — deshalb hätte
// keiner den Ausfall bemerkt. Die Fixtures in test/fixtures/ sind daher
// wörtlich das, was der Server am 13./14.08.2026 geschickt hat.
//
// Aufgezeichnet mit:
//   curl 'https://www.efa-bw.de/nvbw/XML_STOPFINDER_REQUEST?outputFormat=JSON&type_sf=any&name_sf=…'
//   curl 'https://www.efa-bw.de/nvbw/XSLT_TRIP_REQUEST2?outputFormat=JSON&type_origin=stopID&…'

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/transit_service.dart';

dynamic _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync());

void main() {
  group('parseEfaLocations — echte XML_STOPFINDER_REQUEST-Antwort', () {
    test('Haltestellen-Suche liefert Ulm Hauptbahnhof mit EFA-Id', () {
      final locs = parseEfaLocations(_fixture('efa_stopfinder_ulm.json'));

      expect(locs, isNotEmpty);
      final ulm = locs.first;
      expect(ulm.name, 'Ulm, Hauptbahnhof');
      // Diese Id ist der ganze Zweck des Aufrufs: EFA plant NUR mit Ids,
      // mit einem Freitextnamen liefert es null Fahrten.
      expect(ulm.id, '9001008');
      expect(ulm.type, 'stop');
      // ref.coords ist "lon,lat" — vertauscht man es, landet Ulm im Meer.
      expect(ulm.lat, closeTo(48.399121, 0.0001));
      expect(ulm.lon, closeTo(9.984181, 0.0001));
    });

    test('Adress-Suche liefert Hausnummern als Typ address', () {
      final locs = parseEfaLocations(_fixture('efa_stopfinder_adresse.json'));

      expect(locs, isNotEmpty);
      final adresse = locs.firstWhere((l) => l.name.contains('Neue Straße 100'));
      expect(adresse.type, 'address');
      // Strukturierte Adress-Handles müssen unverändert durchgereicht werden —
      // sie sind der Schlüssel für den Fußweg zur nächsten Haltestelle.
      expect(adresse.id, startsWith('streetID:'));
    });

    test('Haltestellen stehen vor Adressen', () {
      final locs = parseEfaLocations(_fixture('efa_stopfinder_adresse.json'));
      final ersteAdresse = locs.indexWhere((l) => l.type == 'address');
      final letzteStation = locs.lastIndexWhere((l) => l.type == 'stop');
      if (ersteAdresse >= 0 && letzteStation >= 0) {
        expect(letzteStation, lessThan(ersteAdresse));
      }
    });

    test('Müll-Eingaben werfen nicht, sondern liefern leer', () {
      expect(parseEfaLocations(null), isEmpty);
      expect(parseEfaLocations('kein json'), isEmpty);
      expect(parseEfaLocations(<String, dynamic>{}), isEmpty);
      expect(parseEfaLocations({'stopFinder': <String, dynamic>{}}), isEmpty);
    });

    test('jeder Treffer merkt sich seine EFA-Instanz', () {
      // ⚠️ Der teuerste Fehler dieses Moduls wäre, eine numerische Id auf
      // einer ANDEREN Instanz weiterzuverwenden. Gemessen am 13.08.2026:
      // `9001008` ist auf efa-bw, VRR und VRN "Ulm, Hauptbahnhof" — auf VVO
      // dagegen "Marktleuthen". Die falsche Instanz meldet keinen Fehler,
      // sie plant eine saubere Fahrt in den falschen Ort. Ohne diesen
      // Stempel liesse sich das gar nicht auseinanderhalten.
      final locs = parseEfaLocations(
        _fixture('efa_stopfinder_ulm.json'),
        basis: 'https://www.efa-bw.de/nvbw',
      );
      expect(locs, isNotEmpty);
      expect(locs.every((l) => l.efaBasis == 'https://www.efa-bw.de/nvbw'), isTrue);
      // Ohne Angabe bleibt er null — und null heisst "nicht wiederverwenden",
      // was für alte gespeicherte Favoriten genau richtig ist.
      expect(parseEfaLocations(_fixture('efa_stopfinder_ulm.json'))
          .every((l) => l.efaBasis == null), isTrue);
    });
  });

  group('parseEfaJourneys — echte XSLT_TRIP_REQUEST2-Antwort', () {
    test('Adresse → Bahnhof: Fußweg, dann Bus, dann Straßenbahn', () {
      final journeys = parseEfaJourneys(_fixture('efa_trip_adresse_ulm.json'));

      expect(journeys, isNotEmpty);
      final j = journeys.first;
      expect(j.legs.length, greaterThanOrEqualTo(2));

      // Genau der Fall, den der Nutzer gemeldet hat: eine Adresse als
      // Startpunkt. EFA hängt den Fußweg zur Haltestelle selbst an.
      final fuss = j.legs.first;
      expect(fuss.isWalk, isTrue);
      expect(fuss.productType, 'walk');
      expect(fuss.line, 'Fußweg');
      expect(fuss.fromName, contains('Neue Straße 100'));

      final bus = j.legs.firstWhere((l) => l.productType == 'bus');
      expect(bus.line, '4');
      expect(bus.direction, 'Wiblingen');
      expect(bus.isWalk, isFalse);

      final tram = j.legs.firstWhere((l) => l.productType == 'tram');
      expect(tram.line, '2');

      // Zeiten müssen echte Zeitpunkte sein, keine Platzhalter.
      expect(j.depTime.year, 2026);
      expect(j.arrTime.isAfter(j.depTime), isTrue);
      expect(j.duration.inMinutes, greaterThan(0));
      expect(j.duration.inHours, lessThan(3));
      // Fußweg + Bus + Tram = ein Umstieg zwischen zwei Fahrzeugen.
      expect(j.transfers, 1);
    });

    test('Fernverkehr behält den Zuggattungs-Prefix — sonst frisst ihn '
        'der D-Ticket-Filter als Buslinie', () {
      final journeys = parseEfaJourneys(_fixture('efa_trip_ice_fern.json'));

      expect(journeys, isNotEmpty);
      final ice = journeys
          .expand((j) => j.legs)
          .firstWhere((l) => l.productType == 'train');

      // EFA liefert number="612" und trainType="ICE" getrennt. Nur die
      // nackte Nummer zu übernehmen wäre der teuerste Fehler hier: der
      // D-Ticket-Filter liest Linien-Prefixe, "612" käme als Nahverkehr
      // durch und der Nutzer stünde mit dem falschen Ticket im ICE.
      expect(ice.line, startsWith('ICE'));
      expect(ice.line, contains('612'));
      expect(ice.bikeAllowedHeuristic, isFalse);
    });

    test('Plattformen und Richtung werden übernommen', () {
      final journeys = parseEfaJourneys(_fixture('efa_trip_ice_fern.json'));
      final legs = journeys.expand((j) => j.legs).where((l) => !l.isWalk);
      expect(legs, isNotEmpty);
      expect(legs.any((l) => l.fromPlatform != null), isTrue,
          reason: 'mindestens ein Abschnitt muss ein Gleis nennen');
      expect(legs.every((l) => l.fromName.isNotEmpty), isTrue);
    });

    test('Leere Gleisangabe wird zu null, nicht zu ""', () {
      final journeys = parseEfaJourneys(_fixture('efa_trip_adresse_ulm.json'));
      final fuss = journeys.first.legs.first;
      // Ein Fußweg von einer Hausnummer hat kein Gleis. "" statt null würde
      // in der Karte als leeres Gleis-Etikett gerendert.
      expect(fuss.fromPlatform, isNull);
    });

    test('Müll-Eingaben werfen nicht, sondern liefern leer', () {
      expect(parseEfaJourneys(null), isEmpty);
      expect(parseEfaJourneys('kein json'), isEmpty);
      expect(parseEfaJourneys(<String, dynamic>{}), isEmpty);
      expect(parseEfaJourneys({'trips': null}), isEmpty);
    });
  });

  group('efaListe — dieselbe Feldform, drei Schreibweisen', () {
    // EFA-Instanzen liefern dasselbe Feld mal als Liste, mal als
    // {key: [...]}, mal als {key: {...}} bei genau einem Treffer. Wer nur
    // eine Form behandelt, bekommt bei der nächsten Instanz stumm null.
    test('bare Liste', () {
      expect(efaListe([1, 2, 3], 'trip'), [1, 2, 3]);
    });
    test('Map mit Liste', () {
      expect(efaListe({'trip': [1, 2]}, 'trip'), [1, 2]);
    });
    test('Map mit Einzelobjekt', () {
      expect(efaListe({'trip': {'a': 1}}, 'trip'), [{'a': 1}]);
    });
    test('fehlend oder falscher Typ', () {
      expect(efaListe(null, 'trip'), isEmpty);
      expect(efaListe({'anderes': 1}, 'trip'), isEmpty);
      expect(efaListe(42, 'trip'), isEmpty);
    });
  });
}
