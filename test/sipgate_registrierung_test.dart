import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/sipgate_service.dart';

/// `sip_ua` wiederholt eine abgelehnte Anmeldung NICHT von sich aus —
/// nachgesehen in `sip_ua-1.1.0` und gegen `main` von
/// `flutter-webrtc/dart-sip-ua` gegengeprüft: `registrator.dart` →
/// `_registrationFailure()` meldet den Fehlschlag und hört auf, ohne Timer.
/// Die einzige selbsttätige Neuanmeldung hängt am Wiederaufbau des WebSockets
/// (`ua.dart` → `onTransportConnect`).
///
/// Damit blieb eine Lücke: ein REGISTER, das abgelehnt wird, **während der
/// Socket steht**, führte in einen Zustand, aus dem nichts mehr herausführte.
/// Auf einem Tablet, das dauerhaft auf dem Tisch liegt, heisst das: es
/// klingelt nichts mehr.
///
/// Die beiden Regeln dieser Wiederholung stehen deshalb als reine Funktionen
/// im Dienst — dieselbe Bauform wie `iceServerEintraege`, aus demselben Grund:
/// sie sind ohne Netz, ohne Gerät und ohne Singleton prüfbar.
void main() {
  group('Wartezeit — RFC 5626 § 4.5', () {
    // W = min(max-time, base-time × 2^consecutive-failures), und die
    // tatsächliche Wartezeit ist „a uniform random time between 50 and 100% of
    // the upper-bound wait time".

    test('der erste Anlauf liegt zwischen 30 und 60 Sekunden', () {
      // Die RFC nennt genau diese Spanne im Fliesstext:
      // „the first retry happens somewhere between 30 and 60 seconds".
      expect(sipgateWartezeit(1, 0.0).inSeconds, 30);
      expect(sipgateWartezeit(1, 1.0).inSeconds, 60);
    });

    test('die Obergrenze verdoppelt sich mit jedem Fehlversuch', () {
      expect(sipgateWartezeit(1, 1.0).inSeconds, 60);
      expect(sipgateWartezeit(2, 1.0).inSeconds, 120);
      expect(sipgateWartezeit(3, 1.0).inSeconds, 240);
    });

    test('der Deckel greift ab dem vierten Anlauf', () {
      // 30 × 2^4 = 480 > 300.
      expect(sipgateWartezeit(4, 1.0), sipgateWartedeckel);
      expect(sipgateWartezeit(9, 1.0), sipgateWartedeckel);
      expect(sipgateWartezeit(99, 1.0), sipgateWartedeckel);
    });

    test('auch der kürzeste Abstand am Deckel bleibt über der Erneuerung/2', () {
      // Der Grund für die 300 s statt der 1800 s aus der RFC: am Deckel liegen
      // zwischen zwei REGISTER 150–300 s, die gesunde Erneuerung läuft alle
      // 295 s. Die Wiederholung erzeugt also nie mehr Verkehr als eine
      // funktionierende Anmeldung.
      expect(sipgateWartezeit(9, 0.0).inSeconds, 150);
      expect(sipgateWartezeit(9, 0.0).inSeconds * 2, greaterThanOrEqualTo(295));
    });

    test('die Streuung bleibt immer zwischen 50 und 100 Prozent', () {
      for (var n = 1; n <= 12; n++) {
        for (final z in [0.0, 0.25, 0.5, 0.75, 1.0]) {
          final w = sipgateWartezeit(n, z).inSeconds;
          final obergrenze = sipgateWartezeit(n, 1.0).inSeconds;
          expect(w, greaterThanOrEqualTo((obergrenze / 2).floor()));
          expect(w, lessThanOrEqualTo(obergrenze));
        }
      }
    });

    test('kein Überlauf, auch wenn ein Gerät wochenlang vergeblich klopft', () {
      // 1 << n mit n = 40 wäre in Dart auf dem Web stillschweigend falsch.
      expect(sipgateWartezeit(40, 1.0), sipgateWartedeckel);
      expect(sipgateWartezeit(1000, 1.0), sipgateWartedeckel);
      expect(sipgateWartezeit(1000, 1.0).isNegative, isFalse);
    });

    test('unsinnige Eingaben ergeben trotzdem eine brauchbare Wartezeit', () {
      // Ein Zähler bei 0 darf nicht in eine Wartezeit von 0 münden — das wäre
      // eine Endlosschleife voller REGISTER.
      expect(sipgateWartezeit(0, 0.0).inSeconds, 30);
      expect(sipgateWartezeit(-5, 0.0).inSeconds, 30);
      expect(sipgateWartezeit(1, -1.0).inSeconds, 30);
      expect(sipgateWartezeit(1, 5.0).inSeconds, 60);
      expect(sipgateWartezeit(1, double.nan).inSeconds, 30);
    });
  });

  group('Einordnung des Fehlschlags', () {
    test('Zeitüberschreitung und Transportfehler werden wiederholt', () {
      // Genau die beiden Fälle, die `registrator.dart` selbst erzeugt:
      // 408 bei EventOnRequestTimeout, 500 bei EventOnTransportError.
      for (final code in [408, 500, 502, 503, 504, 480, 486]) {
        expect(
          sipgateAnmeldeFolge(code, datenSchonErneuert: false),
          SipgateAnmeldeFolge.wiederholen,
          reason: 'Code $code ist vorübergehend',
        );
      }
    });

    test('ein unbekannter Code wird wiederholt, nicht aufgegeben', () {
      // Die Einteilung ist absichtlich schmal. Wer hier eine lange Liste
      // „endgültiger" Codes pflegt, schaltet die Wiederholung irgendwann für
      // einen Fall ab, der sich von selbst erholt hätte.
      expect(sipgateAnmeldeFolge(null, datenSchonErneuert: false),
          SipgateAnmeldeFolge.wiederholen);
      expect(sipgateAnmeldeFolge(699, datenSchonErneuert: false),
          SipgateAnmeldeFolge.wiederholen);
    });

    test('abgelehnte Zugangsdaten holen die Daten erst neu', () {
      for (final code in [401, 403, 404, 407]) {
        expect(
          sipgateAnmeldeFolge(code, datenSchonErneuert: false),
          SipgateAnmeldeFolge.datenErneuern,
          reason: 'Code $code kann ein veralteter HA1 sein',
        );
      }
    });

    test('und geben erst auf, wenn auch frische Daten abgelehnt werden', () {
      for (final code in [401, 403, 404, 407]) {
        expect(
          sipgateAnmeldeFolge(code, datenSchonErneuert: true),
          SipgateAnmeldeFolge.aufgeben,
        );
      }
    });

    test('ein vorübergehender Fehler wird auch nach dem Neuholen wiederholt', () {
      // Sonst würde ein einziger 403 dazu führen, dass später jede
      // Zeitüberschreitung das Telefon endgültig stilllegt.
      expect(sipgateAnmeldeFolge(408, datenSchonErneuert: true),
          SipgateAnmeldeFolge.wiederholen);
      expect(sipgateAnmeldeFolge(503, datenSchonErneuert: true),
          SipgateAnmeldeFolge.wiederholen);
    });
  });

  group('Abmeldung nach einem Fehlschlag', () {
    // Scheitert die Erneuerung einer stehenden Anmeldung, kommt in `sip_ua`
    // erst REGISTRATION_FAILED und unmittelbar danach UNREGISTERED
    // (`_registrationFailure()` ruft beides). Das zweite Ereignis darf das
    // erste nicht auslöschen.

    test('waehrend ein Anlauf geplant ist, gilt sie nicht', () {
      expect(
        sipgateAbmeldungUebernehmen(
          anlaufGeplant: true,
          aktuell: SipgateStand.fehler,
        ),
        isFalse,
        reason: 'sonst stuende in der Kopfleiste „aus" statt „versucht es wieder"',
      );
    });

    test('auch aus dem registrierten Zustand heraus nicht', () {
      // Der Weg, auf dem es wirklich passiert: registriert → Erneuerung
      // scheitert → failed (plant Anlauf) → unregistered.
      expect(
        sipgateAbmeldungUebernehmen(
          anlaufGeplant: true,
          aktuell: SipgateStand.registriert,
        ),
        isFalse,
      );
    });

    test('ohne geplanten Anlauf gilt sie', () {
      // Der normale Fall: der Nutzer hat abgemeldet.
      expect(
        sipgateAbmeldungUebernehmen(
          anlaufGeplant: false,
          aktuell: SipgateStand.registriert,
        ),
        isTrue,
      );
      expect(
        sipgateAbmeldungUebernehmen(
          anlaufGeplant: false,
          aktuell: SipgateStand.fehler,
        ),
        isTrue,
      );
    });

    test('wer schon aus ist, wird nicht noch einmal ausgeschaltet', () {
      // Sonst ersetzte jedes wiederholte UNREGISTERED die stehende Meldung.
      expect(
        sipgateAbmeldungUebernehmen(
          anlaufGeplant: false,
          aktuell: SipgateStand.aus,
        ),
        isFalse,
      );
    });
  });

  group('Zustand', () {
    test('naechsterVersuch unterscheidet „arbeitet daran" von „aus"', () {
      const arbeitet = SipgateZustand(
        stand: SipgateStand.fehler,
        naechsterVersuch: null,
      );
      expect(arbeitet.naechsterVersuch, isNull);

      final geplant = SipgateZustand(
        stand: SipgateStand.fehler,
        naechsterVersuch: DateTime(2026, 8, 23, 10, 0),
      );
      expect(geplant.naechsterVersuch, isNotNull);
      // Beide sind `fehler` — die Kopfleiste darf sie trotzdem nicht gleich
      // malen, sonst ist die Wiederholung wieder unsichtbar.
      expect(geplant.stand, arbeitet.stand);
    });
  });
}
