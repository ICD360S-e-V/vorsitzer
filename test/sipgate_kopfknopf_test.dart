import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/sipgate_service.dart';

/// Der Knopf in der Kopfleiste berichtet die **Anmeldung**, nicht das
/// Gespräch.
///
/// Bis zum 23.08.2026 stand dort `Gespräch läuft — <Nummer>`, sobald
/// `gespraech` gesetzt war. Gesetzt wird das aber schon bei
/// `CALL_INITIATION`, also mit `klingelt` (eingehend) oder `waehlt`
/// (abgehend) — in zwei von drei Fällen war die Aussage falsch. Bei einem
/// abgehenden Anruf standen dann zwei sich widersprechende Sätze gleichzeitig
/// auf dem Schirm, denn die schwebende Karte zeigt korrekt „Wählt …".
void main() {
  SipgateGespraech gespraech(SipgateGespraechStand stand, {bool ein = true}) =>
      SipgateGespraech(
        nummer: '+4973180159736',
        eingehend: ein,
        stand: stand,
        verbundenSeit: stand == SipgateGespraechStand.verbunden
            ? DateTime(2026, 8, 23, 12)
            : null,
      );

  group('der Text hängt NICHT am Gespräch', () {
    const ohne = SipgateZustand(
      stand: SipgateStand.registriert,
      sipId: '4023714e0',
    );

    test('angemeldet, ohne Gespräch', () {
      expect(sipgateKopfText(ohne), 'sipgate — angemeldet (4023714e0)');
    });

    test('ein eingehender Anruf, der noch klingelt, ändert nichts', () {
      // Genau hier stand die Falschaussage: es läutet erst, es ist niemand
      // dran, und der Knopf behauptete ein laufendes Gespräch.
      final z = SipgateZustand(
        stand: SipgateStand.registriert,
        sipId: '4023714e0',
        gespraech: gespraech(SipgateGespraechStand.klingelt),
      );
      expect(sipgateKopfText(z), sipgateKopfText(ohne));
      expect(sipgateKopfText(z), isNot(contains('Gespräch läuft')));
    });

    test('ein abgehender Anruf, der noch wählt, ändert nichts', () {
      // Der Fall, der wirklich beissen konnte: die Karte sagt „Wählt …",
      // der Knopf sagte „Gespräch läuft" — wer den Knopf liest, fängt an zu
      // reden, obwohl es beim anderen noch klingelt.
      final z = SipgateZustand(
        stand: SipgateStand.registriert,
        sipId: '4023714e0',
        gespraech: gespraech(SipgateGespraechStand.waehlt, ein: false),
      );
      expect(sipgateKopfText(z), sipgateKopfText(ohne));
    });

    test('auch ein wirklich verbundenes Gespräch ändert nichts', () {
      // Nicht weil es falsch wäre, sondern weil das Gespräch der Karte
      // gehört: sie liegt über demselben Bildschirm und sagt mehr.
      final z = SipgateZustand(
        stand: SipgateStand.registriert,
        sipId: '4023714e0',
        gespraech: gespraech(SipgateGespraechStand.verbunden),
      );
      expect(sipgateKopfText(z), sipgateKopfText(ohne));
    });

    test('und auch zwei Beine in Konferenz nicht', () {
      final z = SipgateZustand(
        stand: SipgateStand.registriert,
        sipId: '4023714e0',
        gespraech: gespraech(SipgateGespraechStand.verbunden),
        zweites: gespraech(SipgateGespraechStand.verbunden, ein: false),
        konferenz: true,
      );
      expect(sipgateKopfText(z), sipgateKopfText(ohne));
    });
  });

  group('die Anmeldezustände bleiben unterscheidbar', () {
    test('jeder Stand hat seinen eigenen Text', () {
      final texte = <String>{
        sipgateKopfText(const SipgateZustand(stand: SipgateStand.aus)),
        sipgateKopfText(const SipgateZustand(stand: SipgateStand.verbindet)),
        sipgateKopfText(
            const SipgateZustand(stand: SipgateStand.registriert, sipId: 'x')),
        sipgateKopfText(const SipgateZustand(stand: SipgateStand.fehler)),
        sipgateKopfText(
            const SipgateZustand(stand: SipgateStand.fremdesTelefon)),
      };
      expect(texte.length, 5, reason: 'sonst sind zwei Zustände ununterscheidbar');
    });

    test('bei fehler trägt die Meldung Grund und nächsten Anlauf', () {
      // Ohne sie stünde dort weiter „nicht angemeldet" — die Auskunft, die
      // nichts sagt und „versucht es gleich wieder" von „endgültig aus" nicht
      // trennt.
      final z = SipgateZustand(
        stand: SipgateStand.fehler,
        meldung: 'abgelehnt: 503\nneuer Versuch in 42 Sekunden (2. Anlauf).',
        naechsterVersuch: DateTime(2026, 8, 23, 12, 1),
      );
      expect(sipgateKopfText(z), contains('2. Anlauf'));
    });

    test('ohne Meldung fällt fehler auf den kurzen Satz zurück', () {
      expect(sipgateKopfText(const SipgateZustand(stand: SipgateStand.fehler)),
          'sipgate — nicht angemeldet');
    });

    test('ohne SIP-ID steht keine leere Klammer da', () {
      expect(sipgateKopfText(const SipgateZustand(stand: SipgateStand.registriert)),
          'sipgate — angemeldet');
    });
  });
}
