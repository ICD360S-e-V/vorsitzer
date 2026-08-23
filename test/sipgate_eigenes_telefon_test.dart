import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/sipgate_service.dart';

/// Es gibt genau ein VoIP-Telefon, und es gehört dem Tablet. Der Server
/// verweigert aber nie: `sipgateGeraetWaehlen()` fällt zuletzt auf
/// „irgendeines, das aktiv ist" zurück — unter dem Kommentar „Nichts frei —
/// teilen statt verweigern". Jedes andere Android-Gerät bekam damit die SIP-ID
/// des Tablets mit `geteilt = true`.
///
/// sipgate lässt bei zwei Anmeldungen auf einer SIP-ID beide klingeln
/// (Parallelruf), und wer zuerst abnimmt, gewinnt. Ein Anruf eines Klienten
/// hätte in einer Hosentasche landen können statt am Tablet, an dem das
/// Bluetooth-Headset hängt — ohne dass jemand etwas eingeschaltet hätte, denn
/// `autoAktiv()` ist auf Android voreingestellt AN.
void main() {
  group('nur mit eigenem Telefon anmelden', () {
    test('ein eigenes Telefon darf sich anmelden', () {
      expect(sipgateDarfAnmelden(geteilt: false), isTrue);
    });

    test('ein geteiltes NICHT — auch nicht „nur zum Zuhören"', () {
      // Es gibt kein harmloses Mitklingeln: der Parallelruf entscheidet nach
      // Reihenfolge des Abnehmens, nicht nach Absicht.
      expect(sipgateDarfAnmelden(geteilt: true), isFalse);
    });
  });

  group('der Zustand sagt es, ohne zu erschrecken', () {
    test('fremdesTelefon ist ein eigener Stand, kein Fehler', () {
      // Wäre es `fehler`, würde die Kopfleiste rot und jemand suchte einen
      // Defekt, den es nicht gibt. Wäre es `aus`, sähe es aus, als hätte
      // jemand die Telefonie abgeschaltet.
      expect(SipgateStand.fremdesTelefon, isNot(SipgateStand.fehler));
      expect(SipgateStand.fremdesTelefon, isNot(SipgateStand.aus));
      expect(SipgateStand.values, contains(SipgateStand.fremdesTelefon));
    });

    test('in diesem Stand ist nichts angemeldet und nichts geplant', () {
      const z = SipgateZustand(stand: SipgateStand.fremdesTelefon, geteilt: true);
      expect(z.stand == SipgateStand.registriert, isFalse);
      expect(z.gespraech, isNull);
      // Kein Wiederholversuch: das ist eine Feststellung, kein Fehlschlag.
      // Ändern kann es nur ein Mensch im Bildschirm.
      expect(z.naechsterVersuch, isNull);
    });
  });
}
