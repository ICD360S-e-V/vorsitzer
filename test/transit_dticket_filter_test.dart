import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/transit_service.dart';

/// Test suite pentru filter Deutschlandticket. Verifică toate cazurile
/// edge care au cauzat bug-ul original ("ICE100" fără spațiu → nu era
/// filtrat, ICE apărea în rezultate D-Ticket).
///
/// Rulează în CI la fiecare push → dacă cineva schimbă filter-ul greșit
/// (ex. adaugă IC pe whitelist), testele pică imediat.
void main() {
  final service = TransitService();

  DateTime dt(int h, [int m = 0]) => DateTime(2026, 7, 10, h, m);

  Journey oneLegJourney(String line, String productType) => Journey(
        legs: [
          JourneyLeg(
            line: line,
            direction: 'Test',
            fromName: 'A',
            toName: 'B',
            depTime: dt(10),
            arrTime: dt(11),
            productType: productType,
          ),
        ],
        depTime: dt(10),
        arrTime: dt(11),
      );

  group('D-Ticket filter — Fernverkehr respins', () {
    final rejectCases = [
      ('ICE 100', 'train'),
      ('ICE100', 'train'),      // bug original — fără spațiu
      ('ICE', 'train'),
      ('IC 2013', 'train'),
      ('IC2013', 'train'),
      ('IC', 'train'),
      ('IC 68', 'train'),        // fostul Erfurt-Gera, nu mai e valabil 2026
      ('EC 27', 'train'),
      ('EC27', 'train'),
      ('ECE 100', 'train'),
      ('ECE100', 'train'),
      ('IR 2100', 'train'),
      ('TGV 9575', 'train'),
      ('RJ 68', 'train'),
      ('NJ 421', 'train'),
      ('FLX 1804', 'train'),     // FlixTrain
      ('EN 447', 'train'),
      ('CNL 40447', 'train'),
      ('THALYS 9445', 'train'),
    ];

    for (final (line, pt) in rejectCases) {
      test('respinge $line ($pt)', () {
        final j = oneLegJourney(line, pt);
        expect(
          service.isJourneyDTicketCompatible(j),
          isFalse,
          reason: '"$line" ar trebui respins de D-Ticket filter',
        );
      });
    }
  });

  group('D-Ticket filter — Nahverkehr acceptat', () {
    final acceptCases = [
      ('RE 1', 'regional'),
      ('RE12345', 'regional'),
      ('RE-1', 'regional'),
      ('RB 13', 'regional'),
      ('IRE 3', 'regional'),
      ('IRE3', 'regional'),
      ('MEX 16', 'regional'),
      ('MEX16', 'regional'),
      ('S1', 'suburban'),
      ('S 1', 'suburban'),
      ('S25', 'suburban'),
      ('U6', 'subway'),
      ('U 6', 'subway'),
      ('U55', 'subway'),
      ('Tram 1', 'tram'),
      ('Bus 234', 'bus'),
      ('Fähre', 'ferry'),
      // Brand-names regionale — toate D-Ticket eligible
      ('metronom ME 1', 'regional'),
      ('erixx ERX 82', 'regional'),
      ('meridian M 2', 'regional'),
      ('agilis 84013', 'regional'),
      ('eurobahn ERB 63', 'regional'),
      ('ODEG RE 2', 'regional'),
      ('VIAS RB 22', 'regional'),
      ('cantus', 'regional'),
    ];

    for (final (line, pt) in acceptCases) {
      test('accepta $line ($pt)', () {
        final j = oneLegJourney(line, pt);
        expect(
          service.isJourneyDTicketCompatible(j),
          isTrue,
          reason: '"$line" ar trebui acceptat de D-Ticket filter',
        );
      });
    }
  });

  group('D-Ticket filter — IC-Linien exceptii 2026 (Nahverkehrsfreigabe)', () {
    // Din bahn.de/service/nahverkehrsfreigabe:
    // IC 2222-2226, 2320, 2323-2327 Dortmund↔Iserlohn↔Dillenburg
    // IC 2075 Sylt↔Niebüll (nur Mo-Fr)
    final icExceptions = [
      'IC 2222', 'IC2222',
      'IC 2223', 'IC2223',
      'IC 2224', 'IC2224',
      'IC 2225', 'IC2225',
      'IC 2226', 'IC2226',
      'IC 2320', 'IC2320',
      'IC 2323', 'IC2323',
      'IC 2324', 'IC2324',
      'IC 2325', 'IC2325',
      'IC 2326', 'IC2326',
      'IC 2327', 'IC2327',
      'IC 2075', 'IC2075',
    ];

    for (final line in icExceptions) {
      test('accepta $line (D-Ticket exception)', () {
        final j = oneLegJourney(line, 'train');
        expect(
          service.isJourneyDTicketCompatible(j),
          isTrue,
          reason: '"$line" e integrat in Nahverkehrsfreigabe 2026',
        );
      });
    }
  });

  group('D-Ticket filter — Journey cu Umstieg', () {
    test('journey RE + S = OK', () {
      final j = Journey(
        legs: [
          JourneyLeg(
            line: 'RE 4', direction: 'Frankfurt', fromName: 'A', toName: 'B',
            depTime: dt(9), arrTime: dt(10), productType: 'regional',
          ),
          JourneyLeg(
            line: 'S8', direction: 'Wiesbaden', fromName: 'B', toName: 'C',
            depTime: dt(10, 5), arrTime: dt(10, 30), productType: 'suburban',
          ),
        ],
        depTime: dt(9),
        arrTime: dt(10, 30),
      );
      expect(service.isJourneyDTicketCompatible(j), isTrue);
    });

    test('journey RE + ICE = respins (chiar dacă doar 1 leg e FV)', () {
      final j = Journey(
        legs: [
          JourneyLeg(
            line: 'RE 1', direction: 'Mannheim', fromName: 'A', toName: 'B',
            depTime: dt(9), arrTime: dt(10), productType: 'regional',
          ),
          JourneyLeg(
            line: 'ICE 273', direction: 'Basel', fromName: 'B', toName: 'C',
            depTime: dt(10, 15), arrTime: dt(12), productType: 'train',
          ),
        ],
        depTime: dt(9),
        arrTime: dt(12),
      );
      expect(service.isJourneyDTicketCompatible(j), isFalse);
    });

    test('journey cu Fußweg + Nahverkehr = OK (walks ignorate)', () {
      final j = Journey(
        legs: [
          JourneyLeg(
            line: 'Fußweg', direction: '', fromName: 'A', toName: 'B',
            depTime: dt(9), arrTime: dt(9, 5),
            productType: 'walk', isWalk: true,
          ),
          JourneyLeg(
            line: 'RB 26', direction: 'Frankfurt', fromName: 'B', toName: 'C',
            depTime: dt(9, 10), arrTime: dt(10), productType: 'regional',
          ),
        ],
        depTime: dt(9),
        arrTime: dt(10),
      );
      expect(service.isJourneyDTicketCompatible(j), isTrue);
    });
  });

  group('D-Ticket filter — cazuri de tip productType', () {
    test('productType=train + line=RB1 → acceptat (regional prin prefix)', () {
      // Uneori HAFAS raportează RB ca 'train' din bit-mask class=8. Prefix
      // ar trebui să suprascrie și să accepte ca Nahverkehr.
      final j = oneLegJourney('RB 1', 'train');
      expect(service.isJourneyDTicketCompatible(j), isTrue);
    });

    test('productType=regional + line=ICE (misclassify) → respins prin prefix', () {
      // Belt-and-suspenders: dacă HAFAS greșește productType-ul dar line-ul
      // spune clar ICE, prefix-check trebuie să respingă.
      final j = oneLegJourney('ICE 100', 'regional');
      expect(service.isJourneyDTicketCompatible(j), isFalse);
    });
  });
}
