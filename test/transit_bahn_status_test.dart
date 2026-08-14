// Zwei Fehler, die „Verbindung suchen" unbrauchbar gemacht haben, und die
// beide kein bestehender Test bemerkt hat.
//
// 1. bahn.de beantwortet die Verbindungssuche mit **201 Created** — mit
//    gültigem Rumpf. Die Prüfung hiess `statusCode != 200`, also wurde jede
//    erfolgreiche Suche weggeworfen. Übrig blieb „Keine Verbindungen
//    gefunden", und dieselbe 201 wurde später als „gesperrt" gewertet,
//    worauf der Dienst 30 Minuten auf den Ersatzweg auswich.
//
// 2. Auf „Ulm Rathaus" liefert bahn.de an erster Stelle „Ulm Rathaus,
//    Lichtenau (Baden)" — 200 km entfernt. Wer den ersten Vorschlag nimmt,
//    bekommt für vier Minuten Fahrt eine Auskunft über 207 Minuten. Genau
//    das sah dann aus wie „die Zeiten sind durcheinander".

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/transit_service.dart';

TransitLocation _ort(String name, double lat, double lon, {String typ = 'stop'}) =>
    TransitLocation(id: 'A=1@O=$name@', name: name, type: typ, lat: lat, lon: lon);

void main() {
  group('httpErfolg', () {
    test('201 ist ein Erfolg — das war der eigentliche Ausfall', () {
      expect(httpErfolg(201), isTrue);
    });

    test('der ganze 2xx-Bereich zählt', () {
      for (final s in [200, 201, 202, 204, 206, 299]) {
        expect(httpErfolg(s), isTrue, reason: '$s muss Erfolg sein');
      }
    });

    test('4xx und 5xx nicht', () {
      for (final s in [400, 403, 404, 429, 500, 503]) {
        expect(httpErfolg(s), isFalse, reason: '$s darf kein Erfolg sein');
      }
    });

    test('Umleitungen und Zwischenantworten sind kein Erfolg', () {
      // 301/302 hiesse: die Antwort steht woanders, wir haben sie nicht.
      for (final s in [100, 301, 302, 304]) {
        expect(httpErfolg(s), isFalse);
      }
    });
  });

  group('ordneVorschlaege', () {
    // Ulm Hbf als Bezugspunkt — das andere Ende der Fahrt.
    const ulmLat = 48.3996, ulmLon = 9.9824;

    test('die 200 km entfernte Namensvetterin verliert gegen die örtliche', () {
      final treffer = [
        _ort('Ulm Rathaus, Lichtenau (Baden)', 48.7272, 8.0134), // ~145 km weg
        _ort('Rathaus, Ulm', 48.3975, 9.9936),
      ];
      final sortiert = ordneVorschlaege('Ulm Rathaus', treffer,
          refLat: ulmLat, refLon: ulmLon);
      expect(sortiert.first.name, 'Rathaus, Ulm');
    });

    test('ohne Bezugspunkt bleibt die Reihenfolge der Quelle', () {
      // Kein Standort, kein Gegenstück — dann darf nicht geraten werden.
      final treffer = [
        _ort('Ulm Rathaus, Lichtenau (Baden)', 48.7272, 8.0134),
        _ort('Rathaus, Ulm', 48.3975, 9.9936),
      ];
      final sortiert = ordneVorschlaege('Ulm Rathaus', treffer);
      expect(sortiert.first.name, 'Ulm Rathaus, Lichtenau (Baden)');
    });

    test('Fernziele werden NICHT nach Hause gezogen', () {
      // Wer in Ulm sitzt und Berlin sucht, will Berlin. Nur gleich gute
      // Namenstreffer dürfen nach Nähe geordnet werden.
      final treffer = [
        _ort('Berlin Hbf', 52.5250, 13.3694),
        _ort('Ulm Hbf', 48.3996, 9.9824),
      ];
      final sortiert = ordneVorschlaege('Berlin Hbf', treffer,
          refLat: ulmLat, refLon: ulmLon);
      expect(sortiert.first.name, 'Berlin Hbf');
    });

    test('Haltestellen bleiben vor POIs, auch wenn der POI näher liegt', () {
      // Sonst gewinnt „Am Rathaus (Hotel)" gegen die Haltestelle — näher
      // dran, aber dorthin will niemand gefahren werden.
      final treffer = [
        _ort('Rathaus, Ulm', 48.3975, 9.9936),
        _ort('Ulm, Am Rathaus (Hotel)', 48.3976, 9.9937, typ: 'poi'),
      ];
      final sortiert = ordneVorschlaege('Ulm Rathaus',
          [treffer[1], treffer[0]], refLat: ulmLat, refLon: ulmLon);
      expect(sortiert.first.type, 'stop');
      expect(sortiert.first.name, 'Rathaus, Ulm');
    });

    test('Einträge ohne Koordinaten fallen ans Ende, nicht nach vorn', () {
      final treffer = [
        TransitLocation(id: 'x', name: 'Rathaus irgendwo', type: 'stop'),
        _ort('Rathaus, Ulm', 48.3975, 9.9936),
      ];
      final sortiert = ordneVorschlaege('Ulm Rathaus', treffer,
          refLat: ulmLat, refLon: ulmLon);
      expect(sortiert.first.name, 'Rathaus, Ulm');
    });

    test('keine Fahrt geht verloren und keine kommt dazu', () {
      final treffer = [
        _ort('A Rathaus', 48.0, 9.0),
        _ort('B Rathaus', 49.0, 10.0),
        _ort('C Rathaus', 50.0, 11.0),
      ];
      final sortiert = ordneVorschlaege('Rathaus', treffer,
          refLat: ulmLat, refLon: ulmLon);
      expect(sortiert.length, 3);
      expect(sortiert.map((l) => l.name).toSet(),
          {'A Rathaus', 'B Rathaus', 'C Rathaus'});
    });

    test('leere Liste und einzelner Treffer sind harmlos', () {
      expect(ordneVorschlaege('x', const [], refLat: ulmLat, refLon: ulmLon), isEmpty);
      final eins = [_ort('Rathaus, Ulm', 48.3975, 9.9936)];
      expect(ordneVorschlaege('Rathaus', eins, refLat: ulmLat, refLon: ulmLon).length, 1);
    });
  });
}
