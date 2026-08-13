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

  group('normalize — zwei Anschlüsse in EINEM Feld', () {
    // ⚠️ Alle Rohwerte hier stehen wörtlich so in der Produktivdatenbank
    // (Stand 2026-08-13). Vorher verschmolz der Schrägstrich beide Nummern zu
    // einer Ziffernfolge, und ein Tipp auf das Feld wählte sie auch.
    test('der Schrägstrich zwischen zwei Nummern trennt', () {
      // Agentur für Arbeit Ulm: AN-Hotline und Ortsnetz in einem Feld.
      // Vorher: 080045555000731160900 — 21 Stellen, E.164 erlaubt 15.
      expect(n('0800 4555500 (AN) / 0731 160900'), '08004555500');
      expect(n('0800 1110111 / 0800 1110222'), '08001110111');
    });

    test('der Schrägstrich NACH der Vorwahl trennt nicht', () {
      // Die übliche deutsche Schreibweise — hier wäre eine Trennung falsch.
      expect(n('0731/266462'), '0731266462');
      expect(n('0711 / 123 456-78'), '071112345678');
      expect(n('08331 / 100-0'), '083311000');
    });

    test('mehrere Durchwahlen: die erste wird gewählt', () {
      // Amtsgericht Neu-Ulm — Betreuungsgericht.
      expect(n('0731 / 70793 -422, -424, -425'), '073170793422');
      expect(n('0731 / 189-2142, -2207, -2181'), '07311892142');
    });

    test('der Preishinweis bleibt ein Preishinweis', () {
      // ⚠️ Die Gegenprobe zur Reihenfolge: wird erst getrennt und dann
      // entklammert, zerlegt der Schrägstrich in „(20 Ct/Anruf)" das Feld
      // mitten im Hinweis. Auf der Serverseite ist die erste Fassung genau
      // hier gescheitert.
      expect(n('01806 999 555 10 (20 Ct/Anruf)'), '0180699955510');
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
