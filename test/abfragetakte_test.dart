import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/ticket_notification_service.dart';
import 'package:icd360sev_vorsitzer/widgets/login_approval_dialog.dart';

/// Hält die Takte fest, die neben einem Push-Kanal laufen.
///
/// Dreimal dasselbe Muster gefunden: eine Abfrage im Sekundentakt, die neben
/// einem Kanal steht, der dieselbe Sache sofort meldet.
///
///   • Anmelde-Anfragen   5 s   neben `loginApprovalStream`   (bis 09.08.2026)
///   • Wählaufträge       5 s   neben der ntfy-Weckleitung    (bis 11.08.2026)
///   • Ticketmeldungen   60 s   neben `ticketNotificationStream`
///
/// Ein Netz unter einem Push-Kanal darf grob sein — es fängt den Ausfall des
/// Kanals ab, nicht die normale Zustellung. Am anderen Ende wartet in allen
/// drei Fällen ein Mensch auf eine Entscheidung, kein Automat auf ein
/// Zeitfenster.
void main() {
  group('Abfragen neben einem Push-Kanal', () {
    test('Anmelde-Anfragen fragen nicht im Sekundentakt', () {
      expect(LoginApprovalOverlay.pollTakt,
          greaterThanOrEqualTo(const Duration(seconds: 30)));
    });

    test('Ticketmeldungen fragen nicht im Minutentakt', () {
      // Ein Durchlauf kostet ZWEI Anfragen (Tickets und Ermäßigungen). Im
      // Minutentakt sind das 120 Funkweckrufe je Stunde, rund um die Uhr.
      expect(
        TicketNotificationService.pollTakt,
        greaterThanOrEqualTo(const Duration(minutes: 2)),
        reason: 'Der WebSocket meldet ein Ticket sofort; diese Abfrage ist nur '
            'das Netz darunter.',
      );
    });
  });
}
