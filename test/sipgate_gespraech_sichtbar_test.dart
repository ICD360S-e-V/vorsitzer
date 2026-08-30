import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/sipgate_service.dart';

/// Drei Dinge, die während eines Gesprächs unsichtbar waren.
void main() {
  String quelle(String p) => File(p).readAsStringSync();

  group('die Gegenseite hält uns — und das ist etwas anderes als „wir halten"',
      () {
    const g = SipgateGespraech(
      nummer: '+4973180159736',
      eingehend: true,
      stand: SipgateGespraechStand.verbunden,
    );

    test('die beiden Felder sind getrennt', () {
      // Zusammengelegt stünde bei „Bitte bleiben Sie in der Leitung" auf dem
      // Schirm, WIR hätten jemanden geparkt.
      final wir = g.kopie(gehalten: true);
      expect(wir.gehalten, isTrue);
      expect(wir.vonGegenseiteGehalten, isFalse);

      final die = g.kopie(vonGegenseiteGehalten: true);
      expect(die.vonGegenseiteGehalten, isTrue);
      expect(die.gehalten, isFalse);
    });

    test('kopie() verliert das Feld nicht', () {
      final vorher = g.kopie(vonGegenseiteGehalten: true);
      expect(vorher.kopie(stumm: true).vonGegenseiteGehalten, isTrue);
    });

    test('voreingestellt ist es aus', () {
      expect(g.vonGegenseiteGehalten, isFalse);
    });

    // Der Rumpf stand mit `break;` leer im switch — die plötzliche Stille war
    // von einer Störung nicht zu unterscheiden.
    test('HOLD/UNHOLD wird ausgewertet, und nur von der Gegenseite', () {
      final q = quelle('lib/services/sipgate_service.dart');
      expect(q, contains('Originator.remote'),
          reason: 'ohne die Prüfung käme unser eigenes *3 doppelt an');
      expect(q, contains('vonGegenseiteGehalten: gehalten'));
    });

    test('die schwebende Karte sagt es auch', () {
      expect(quelle('lib/widgets/sipgate_anruf_overlay.dart'),
          contains('In der Warteschleife'));
    });
  });

  group('das laufende Gespräch steht auch ausserhalb der App', () {
    // Die schwebende Karte hängt im Navigator-Overlay: wer den Bildschirm
    // sperrt, hatte weder Dauer noch Auflegen-Knopf mehr vor sich.
    test('eigener Kanal, nicht der des Klingelns', () {
      final q = quelle('lib/services/notification_service.dart');
      expect(q, contains("channelIdGespraech = 'sipgate_gespraech'"));
      // Derselbe Kanal wie beim Klingeln hiesse: es klingelt ein zweites Mal,
      // mitten im Satz. Ein Android-Kanal lässt sich nachträglich nicht mehr
      // leiser stellen.
      expect(q, contains('Importance.low'));
    });

    test('die Meldung wird auch wieder weggenommen', () {
      final q = quelle('lib/services/sipgate_service.dart');
      expect(q, contains('cancelOngoingCall'));
      expect('_laufendesGespraechMelden()'.allMatches(q).length,
          greaterThanOrEqualTo(4),
          reason: 'verbunden, beendet, gehalten und Gegenseite-hält');
    });

    test('der Auflegen-Knopf ist verdrahtet', () {
      // Ein Knopf in einer Benachrichtigung, den niemand entgegennimmt, sieht
      // aus wie ein Fehler des Telefons.
      expect(quelle('lib/services/notification_service.dart'),
          contains('aktionAuflegen'));
      expect(quelle('lib/services/sipgate_service.dart'),
          contains('NotificationService.aktionAuflegen'));
    });
  });

  group('Notruf: die Absage nennt jetzt den Weg, der funktioniert', () {
    test('die Sperre selbst bleibt', () {
      for (final n in const ['110', '112', '911', '999']) {
        expect(SipgateService.istNotruf(n), isTrue);
      }
      expect(SipgateService.istNotruf('116117'), isFalse,
          reason: 'ärztlicher Bereitschaftsdienst ist kein Notruf');
      expect(SipgateService.istNotruf('115'), isFalse);
    });

    test('der Bildschirm fängt sie ab, BEVOR gewählt wird', () {
      final q = quelle('lib/screens/sipgate_screen.dart');
      expect(q, contains('SipgateService.istNotruf(roh)'));
      expect(q.indexOf('SipgateService.istNotruf(roh)'),
          lessThan(q.indexOf('_dienst.anrufen(roh)')));
    });

    test('gewählt wird nichts von selbst', () {
      // `PhoneCallService` öffnet für Notrufnummern ausschliesslich die
      // Telefon-App (`emergency_dialer`); auslösen muss ein Mensch. Ein
      // versehentlicher 112-Anruf bindet eine Leitstelle, die jemand anderes
      // gerade braucht.
      final q = quelle('lib/screens/sipgate_screen.dart');
      expect(q, contains('PhoneCallService.call(context, nummer)'));
      expect(q, contains('Telefon-App öffnen'));
      expect(quelle('lib/services/phone_call_service.dart'),
          contains("case 'emergency_dialer':"));
    });
  });
}
