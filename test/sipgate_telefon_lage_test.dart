import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/sipgate_service.dart';

/// Der Bildschirm auf dem Rechner hatte über das Tablet nichts zu sagen. Von
/// dort gehen die Wählaufträge aus, und seit „nur das Gerät mit eigenem
/// VoIP-Telefon meldet sich an" scheitert ein Auftrag mit `wahlweg: sipgate`
/// ehrlich, wenn das Tablet nicht angemeldet ist — nur erfuhr man das erst
/// NACH dem Klick.
///
/// Gefragt wird deshalb bei sipgate selbst (`GET /v2/{userId}/devices`), nicht
/// beim Tablet. Ein Lebenszeichen des Geräts bewiese nur „die App läuft und
/// fragt", nicht „sie ist angemeldet" — und die beiden gehen genau in dem Fall
/// auseinander, für den die Wiederholung nach RFC 5626 gebaut wurde.
void main() {
  group('was sipgate sagt, wird zur Aussage', () {
    test('angemeldet mit unserer Kennung heisst bereit', () {
      expect(
        sipgateTelefonLage(
            online: true, dnd: false, userAgent: 'ICD360S-Vorsitzer'),
        SipgateTelefonLage.bereit,
      );
    });

    test('nicht angemeldet heisst abgemeldet', () {
      expect(
        sipgateTelefonLage(online: false, dnd: false, userAgent: null),
        SipgateTelefonLage.abgemeldet,
      );
    });

    test('nichts bekannt ist NICHT dasselbe wie abgemeldet', () {
      // Der Unterschied entscheidet, ob der Bildschirm einen Fehler behauptet
      // oder zugibt, dass er nichts weiss.
      expect(
        sipgateTelefonLage(online: null, dnd: null, userAgent: null),
        SipgateTelefonLage.unbekannt,
      );
      expect(SipgateTelefonLage.unbekannt,
          isNot(SipgateTelefonLage.abgemeldet));
    });

    test('eine fremde Kennung heisst fremdesGeraet', () {
      expect(
        sipgateTelefonLage(
            online: true, dnd: false, userAgent: 'Zoiper/2.9'),
        SipgateTelefonLage.fremdesGeraet,
      );
    });

    test('nicht stören wird gemeldet — es klingelt sonst lautlos gar nicht', () {
      expect(
        sipgateTelefonLage(
            online: true, dnd: true, userAgent: 'ICD360S-Vorsitzer'),
        SipgateTelefonLage.nichtStoeren,
      );
    });
  });

  group('die Reihenfolge ist die Aussage', () {
    test('abgemeldet schlägt alles — auch dnd', () {
      // Sonst nennte der Bildschirm „nicht stören" als Grund, während der
      // wirkliche Grund ist, dass gar keine Anmeldung steht.
      expect(
        sipgateTelefonLage(online: false, dnd: true, userAgent: 'Zoiper/2.9'),
        SipgateTelefonLage.abgemeldet,
      );
    });

    test('fremdes Gerät schlägt dnd', () {
      // Ein dnd auf einer fremden Anmeldung zu melden hiesse, den zweiten
      // Grund zu nennen und den ersten zu verschweigen: unsere App hält die
      // Leitung gar nicht.
      expect(
        sipgateTelefonLage(online: true, dnd: true, userAgent: 'Zoiper/2.9'),
        SipgateTelefonLage.fremdesGeraet,
      );
    });

    test('unbekannt schlägt alles', () {
      expect(
        sipgateTelefonLage(online: null, dnd: true, userAgent: 'Zoiper/2.9'),
        SipgateTelefonLage.unbekannt,
      );
    });
  });

  group('Randfälle der Kennung', () {
    test('angemeldet ohne genannte Kennung ist kein fremdes Gerät', () {
      // Leer heisst: sipgate nennt keine. Daraus ein fremdes Softphone zu
      // behaupten wäre eine Warnung ohne Anlass.
      for (final ua in [null, '', '   ']) {
        expect(
          sipgateTelefonLage(online: true, dnd: false, userAgent: ua),
          SipgateTelefonLage.bereit,
          reason: 'userAgent=${ua == null ? 'null' : '"$ua"'}',
        );
      }
    });

    test('Leerzeichen um die eigene Kennung stören nicht', () {
      expect(
        sipgateTelefonLage(
            online: true, dnd: false, userAgent: '  ICD360S-Vorsitzer  '),
        SipgateTelefonLage.bereit,
      );
    });

    test('die Kennung kommt vom Server, nicht aus dem Client', () {
      // Der Server schickt `eigener_user_agent` mit. Weicht die Konstante hier
      // je ab, hielte der Bildschirm die eigene Anmeldung für ein fremdes
      // Softphone — dafür ist der Parameter da.
      expect(
        sipgateTelefonLage(
            online: true,
            dnd: false,
            userAgent: 'ICD360S-Neu',
            eigenerUserAgent: 'ICD360S-Neu'),
        SipgateTelefonLage.bereit,
      );
    });
  });
}
