import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/ntfy_service.dart';

/// Seit der Wachdienst einen eigenen ntfy-Strom hält, hängen ZWEI Abonnenten
/// am selben Thema: die Oberfläche und der Dienst, jeder in seinem Isolate.
/// ntfy stellt jede Nachricht beiden zu — also erschien seit dem 10.08.2026
/// jede Chatmeldung doppelt auf dem Bildschirm. Im Serverprotokoll steht
/// derselbe Wortlaut zur selben Sekunde mehrfach.
///
/// Der Dienst braucht den Strom nur für die stummen Marken. Alles, was ein
/// Mensch lesen soll, bleibt Sache der Oberfläche.
void main() {
  const meldung =
      '{"event":"message","title":"Neue Nachricht","message":"hallo"}';
  const smsMarke = '{"event":"message","tags":["sms_gateway"],"message":"x"}';
  const anrufMarke = '{"event":"message","tags":["anruf_gateway"],"message":"x"}';

  tearDown(() {
    NtfyService.onGatewayWake = null;
    NtfyService.onAnrufWake = null;
    NtfyService().stop();
  });

  test('der Maschinen-Strom weckt weiterhin, zeigt aber nichts an', () {
    final dienst = NtfyService();
    var sms = 0, anruf = 0;
    NtfyService.onGatewayWake = () => sms++;
    NtfyService.onAnrufWake = () => anruf++;

    dienst.start('V27655', jwtToken: 'egal', nurMaschine: true);
    dienst.angezeigteMeldungen = 0;

    dienst.handleLineFuerTest(smsMarke);
    dienst.handleLineFuerTest(anrufMarke);
    dienst.handleLineFuerTest(meldung);

    expect(sms, 1, reason: 'Die SMS-Warteschlange muss weiter geweckt werden.');
    expect(anruf, 1, reason: 'Der Wählauftrag muss weiter geweckt werden.');
    expect(dienst.angezeigteMeldungen, 0,
        reason: 'Der Dienst darf nichts anzeigen — sonst steht jede Meldung '
            'zweimal da, einmal von ihm und einmal von der Oberfläche.');
  });

  test('die Oberfläche zeigt Meldungen weiterhin an', () {
    final ui = NtfyService();
    ui.start('V27655', jwtToken: 'egal');
    ui.angezeigteMeldungen = 0;

    ui.handleLineFuerTest(meldung);

    expect(ui.angezeigteMeldungen, 1,
        reason: 'Ohne nurMaschine bleibt es beim bisherigen Verhalten — sonst '
            'käme gar keine Meldung mehr an.');
  });
}
