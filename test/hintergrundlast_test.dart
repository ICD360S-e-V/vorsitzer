import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/anruf_gateway_service.dart';
import 'package:icd360sev_vorsitzer/services/signatur_gateway_service.dart';
import 'package:icd360sev_vorsitzer/widgets/login_approval_dialog.dart';

/// Hält die Funklast der Dauerdienste fest.
///
/// Hintergrund: In der Nacht zum 09.08.2026 war das Telefon um 05:46 leer. Im
/// Serverprotokoll standen für dieses Gerät **5.176 Anfragen pro Stunde**,
/// durchgehend, bei stehendem Bildschirm — eine alle 0,7 Sekunden. Der Sprung
/// kam um 22:00 Uhr am Vortag, als die Fernwahl eingeschaltet wurde: der
/// Wachdienst stellte von 20 auf 5 Sekunden um, und die SMS-Abfrage wurde
/// stillschweigend mitgerissen. Jeder ihrer fünf Endpunkte stieg von 46 auf
/// 750 Anfragen je Stunde.
///
/// Keiner dieser Werte ist für sich falsch — falsch war, dass eine Konstante
/// eine zweite mitzog, ohne dass irgendwo stand, dass sie zusammenhängen.
/// Genau das prüfen die Tests hier.
void main() {
  group('Takt der Dauerdienste', () {
    test('der Anruf-Takt zieht die SMS-Abfrage nicht mehr mit sich', () {
      // Ein Wählauftrag gilt zwei Minuten und jemand wartet davor — fünf
      // Sekunden sind dafür richtig.
      expect(AnrufGatewayService.takt, const Duration(seconds: 5));

      // Eine Termin-Erinnerung hat einen Tag Vorlauf. Sie darf nie im Takt der
      // Fernwahl laufen: ein Durchlauf kostet FÜNF Anfragen (Termine,
      // Signatur-TAN, Medikamente, Wetter, chat/sms_outbox).
      expect(
        SignaturGatewayService.smsTakt,
        greaterThanOrEqualTo(AnrufGatewayService.takt * 4),
        reason: 'Ein SMS-Durchlauf kostet fünf Anfragen. Läuft er im '
            '5-Sekunden-Takt der Fernwahl mit, sind das rund 3.600 zusätzliche '
            'Funkweckrufe pro Stunde für eine Erinnerung mit einem Tag Vorlauf.',
      );
    });

    test('Anmelde-Anfragen werden nicht im Sekundentakt abgefragt', () {
      // Der WebSocket meldet eine Anfrage sofort über loginApprovalStream.
      // Diese Abfrage ist nur das Netz darunter — und lief bis zum 09.08.2026
      // alle fünf Sekunden, rund um die Uhr, als größter Einzelposten
      // überhaupt.
      expect(
        LoginApprovalOverlay.pollTakt,
        greaterThanOrEqualTo(const Duration(seconds: 30)),
        reason: 'Am anderen Ende wartet ein Mensch auf eine Entscheidung, '
            'kein Automat auf ein Zeitfenster.',
      );
    });
  });
}
