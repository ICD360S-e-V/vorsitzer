import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/phone_call_service.dart';

/// Die Rufnummern in den Behörden-/Arzt-/Mitglieder-Datensätzen sind von Hand
/// erfasst und entsprechend uneinheitlich. Diese Tests pinnen fest, was
/// [PhoneCallService.normalize] daraus macht — ein Fehler hier wählt im
/// Ernstfall die falsche Nummer.
void main() {
  String? n(String s) => PhoneCallService.normalize(s);

  group('normalize — gängige Schreibweisen', () {
    test('Trenner (Leerzeichen, Slash, Bindestrich) fallen weg', () {
      expect(n('0711 / 123 456-78'), '071112345678');
      expect(n('030-12345678'), '03012345678');
      expect(n('0711.123.456'), '0711123456');
    });

    test('Ländervorwahl bleibt mit +', () {
      expect(n('+49 711 123456'), '+49711123456');
      expect(n('0049 711 123456'), '0049711123456');
    });

    test('(0) als Verkehrsausscheidungsziffer fällt weg', () {
      expect(n('+49 (0)711 123456'), '+49711123456');
      expect(n('+49 (0) 711 123456'), '+49711123456');
    });

    test('Klammern um die Vorwahl bleiben erhalten', () {
      expect(n('(0711) 123456'), '0711123456');
      expect(n('(030) 12 34 56'), '030123456');
    });

    test('Beschriftungen und Preishinweise fallen weg', () {
      expect(n('Tel. 0711 123456'), '0711123456');
      expect(n('Tel: 0711 123456'), '0711123456');
      expect(n('01806 999 555 10 (20 Ct/Anruf)'), '0180699955510');
      expect(n('0800 1110111 (kostenfrei)'), '08001110111');
    });

    test('Notrufnummern bleiben wählbar', () {
      expect(n('110'), '110');
      expect(n('112'), '112');
      expect(n('116117'), '116117');
    });

    test('Durchwahl mit Bindestrich bleibt Teil der Nummer', () {
      expect(n('0711 123456-789'), '0711123456789');
    });
  });

  group('normalize — Fließtext', () {
    test('gewinnt der Abschnitt mit den meisten Ziffern', () {
      expect(n('Mo-Fr 8-16 Uhr, Tel 0711 123456'), '0711123456');
      expect(n('Zimmer 204, Durchwahl 0711 9876543'), '07119876543');
    });

    test('bei mehreren Nummern die erste vollständige', () {
      // Gleich viele Ziffern → der erste Treffer gewinnt.
      expect(n('0711 123456 oder 0711 654321'), '0711123456');
    });
  });

  group('normalize — nichts Wählbares', () {
    test('leere und rein textliche Felder', () {
      expect(n(''), isNull);
      expect(n('   '), isNull);
      expect(n('-'), isNull);
      expect(n('auf Anfrage'), isNull);
      expect(n('k. A.'), isNull);
    });

    test('zu kurze Ziffernfolgen', () {
      expect(n('Zimmer 12'), isNull);
      expect(n('8-16 Uhr'), isNull);
    });
  });

  group('isDialable', () {
    test('folgt normalize', () {
      expect(PhoneCallService.isDialable('0711 123456'), isTrue);
      expect(PhoneCallService.isDialable('112'), isTrue);
      expect(PhoneCallService.isDialable('-'), isFalse);
      expect(PhoneCallService.isDialable(''), isFalse);
      expect(PhoneCallService.isDialable(null), isFalse);
    });
  });
}
