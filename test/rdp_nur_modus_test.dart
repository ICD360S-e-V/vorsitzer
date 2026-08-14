import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/rdp_nur_modus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// „Nur Remote Desktop" — der Kiosk-Modus für das Telefon, das nichts anderes
/// tun soll als sich auf den Bürorechner zu schalten.
///
/// Zwei Dinge werden hier festgehalten, und beide würden im Betrieb erst
/// auffallen, wenn es zu spät ist:
///
///  1. **Der Schalter muss umkehrbar bleiben.** Wäre der Modus fest an das
///     Gerätemodell gebunden, hätte ein Pixel mit unerreichbarem RDP-Ziel keine
///     Oberfläche mehr, über die man es wieder geradebiegen könnte.
///  2. **Der Kiosk darf keine Dauerlast mitbringen.** Genau dafür ist er da:
///     ohne Dashboard laufen weder Chat-WebSocket noch Anmelde-Abfrage, Wetter,
///     ÖPNV oder Abzeichen. Siehe `hintergrundlast_test.dart` für den Vorfall,
///     der diese Buchführung nötig gemacht hat.
List<String> _codeLines(String source) => source
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('///'))
    .toList();

void main() {
  setUp(() {
    RdpNurModus.cacheLeeren();
  });

  group('Schalter', () {
    test('ohne gespeicherten Wert entscheidet die Erkennung — hier: aus', () async {
      SharedPreferences.setMockInitialValues({});
      // Die Testumgebung ist kein Android, die Pixel-Erkennung liefert also
      // false. Wichtig ist die Richtung: im Zweifel die vollständige App.
      expect(await RdpNurModus.istAn(), isFalse);
    });

    test('ein gespeicherter Wert schlägt die Erkennung', () async {
      SharedPreferences.setMockInitialValues({'rdp.nur_modus_an': true});
      expect(await RdpNurModus.istAn(), isTrue);
    });

    test('setzen() gilt dauerhaft und beendet die Automatik', () async {
      SharedPreferences.setMockInitialValues({
        'rdp.nur_modus_an': true,
        'rdp.nur_modus_automatisch': true,
      });
      expect(await RdpNurModus.istAn(), isTrue);
      expect(await RdpNurModus.istAutomatisch(), isTrue);

      await RdpNurModus.setzen(false);

      expect(await RdpNurModus.istAn(), isFalse);
      expect(await RdpNurModus.istAutomatisch(), isFalse,
          reason: 'Eine Entscheidung von Hand darf die Erkennung nie wieder '
              'überstimmen — sonst käme der Kiosk beim nächsten Start zurück.');
    });

    test('die Erkennung läuft genau einmal, danach steht der Wert', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await RdpNurModus.istAn(), isFalse);

      // Der erste Aufruf schreibt sein Ergebnis fest. Ab jetzt kann ein
      // Systemupdate, das die Modellkennung ändert, nichts mehr umwerfen.
      final sp = await SharedPreferences.getInstance();
      expect(sp.getBool('rdp.nur_modus_an'), isFalse);
    });

    test('auf einem Nicht-Android ist es nie ein Pixel', () async {
      expect(await RdpNurModus.istPixel(), isFalse);
    });
  });

  group('Der Kiosk bringt keine Dauerlast mit', () {
    late String quelle;

    setUpAll(() {
      quelle = _codeLines(File('lib/screens/rdp_only_screen.dart').readAsStringSync())
          .join('\n');
    });

    test('kein Chat-WebSocket, keine Abfragetakte des Dashboards', () {
      // Das sind die Posten aus dem Protokoll der Nacht zum 09.08.2026. Keiner
      // von ihnen hat in einem Gerät etwas zu suchen, das nur einen Knopf zeigt.
      for (final verboten in const [
        'ChatService',
        'startPolling',
        'HeartbeatService',
        'WeatherService',
        'TransitService',
        'YoutubeService',
        'MailBadgeService',
        'TicketNotificationService',
      ]) {
        expect(quelle, isNot(contains(verboten)),
            reason: '$verboten gehört ins Dashboard. Im Kiosk wäre es genau '
                'die Dauerlast, wegen der es den Kiosk gibt.');
      }
    });

    test('auf dem Pixel werden die Gateway-Rollen umgelegt, nicht übergangen', () {
      // ⚠️ Der Wachdienst ist ein Vordergrunddienst mit autoRunOnBoot: ihn
      // bloß nicht anzuwerfen ändert nichts, er kommt nach dem nächsten
      // Neustart von allein zurück. Am 14.08.2026 waren das 5.216 Anfragen an
      // anruf/queue.php an einem Tag. Der Kiosk muss die Schalter umlegen.
      expect(quelle, contains('RdpNurModus.istPixel'),
          reason: 'Stillgelegt wird ausschließlich auf dem Pixel.');
      expect(quelle, contains('AnrufGatewayService.setEnabled(false)'));
      expect(quelle, contains('TerminSmsGatewayService.setEnabled(false)'));
      expect(quelle, contains('SpeedtestService.setzeAuto(false)'));
      expect(quelle, contains('SignaturGatewayService.stoppen'),
          reason: 'Gürtel und Hosenträger: nach einem Force Stop läuft der '
              'Dienst, ohne dass ein Schalter davon weiß.');
    });

    test('auf jedem anderen Gerät bleiben die Rollen unberührt', () {
      // Das Tablet mit der SIM ist das SMS-Gateway des Vereins. Ein dort
      // versehentlich eingeschalteter Kiosk darf ihm nicht lautlos die
      // Termin-Erinnerungen abdrehen.
      expect(quelle, contains('TerminSmsGatewayService.initialize'),
          reason: 'Der einzige Workmanager-initialize() der App; ohne ihn '
              'verfallen die Aufträge eines Gateway-Geräts still.');
      expect(quelle, contains('AnrufGatewayService.starteVordergrundTakt'));
    });

    test('der Kiosk ist keine Einbahnstraße — die Aktualisierung bleibt', () {
      // Ohne diese eine Anfrage je App-Start bekäme das Gerät nie wieder eine
      // neue Fassung: es hat ja keine Oberfläche mehr, über die man sie holen
      // könnte.
      expect(quelle, contains('checkForUpdate'),
          reason: 'Sonst bleibt das Gerät für immer auf dem Stand des Tages, '
              'an dem der Schalter umgelegt wurde.');
    });

    test('die RDP-Verbindung selbst wird nicht nachgebaut', () {
      // Der Kiosk ist eine andere Oberfläche, kein zweiter Verbindungsweg.
      expect(quelle, contains('RdpService'));
      expect(quelle, contains('RdpSessionScreen'));
      expect(quelle, isNot(contains('rdpSession(')),
          reason: 'Die Sitzung läuft über RdpService, nicht am Dienst vorbei.');
      expect(quelle, isNot(contains('WebViewController')),
          reason: 'Die Anzeige gehört RdpSessionScreen — eine zweite Fassung '
              'würde beim nächsten Token-Problem auseinanderlaufen.');
    });
  });
}
