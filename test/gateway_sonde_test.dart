import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/heartbeat_service.dart';

/// Prüfungen am QUELLTEXT, nicht am Verhalten.
///
/// ⚠️ Warum so: die Regeln hier stehen in einer privaten Methode, die nur ein
/// laufender Vordergrunddienst mit angemeldetem Gerät und echter SIM auslöst.
/// Dasselbe Vorgehen wie in `sipgate_lebenszeichen_test.dart` und
/// `proguard_jna_test.dart` — es ist die einzige Stelle im Baum, an der ein
/// Bruch dieser Kopplungen überhaupt auffallen kann.
void main() {
  final gatewayQuelle =
      File('lib/services/termin_sms_gateway_service.dart').readAsStringSync();
  final apiQuelle = File('lib/services/api_service.dart').readAsStringSync();

  group('Warteschlangen-Sonde', () {
    test('fragt alle fünf Warteschlangen namentlich ab', () {
      // ⚠️ Diese Namen sind ein VERTRAG mit `api/gateway/anstehend.php`, und
      // das PHP liegt in keinem Repo. Wer dort einen Schlüssel umbenennt,
      // bekommt hier für die betroffene Warteschlange dauerhaft „nichts zu
      // tun" — lautlos, denn ein leerer Durchlauf sieht aus wie ein ruhiger.
      // Bei `signatur` hiesse das: eine TAN geht nie raus, während ein
      // Mitglied vor dem Unterschriftsfeld wartet.
      for (final name in const [
        'signatur',
        'termine',
        'medikamente',
        'wetter',
        'chat_outbox',
      ]) {
        expect(gatewayQuelle, contains("faellig('$name')"),
            reason: 'Warteschlange "$name" wird nicht mehr abgefragt');
      }
    });

    test('ein Fehlschlag der Sonde fragt ALLES, nicht nichts', () {
      // Der gefährlichste Fehler wäre, aus „Sonde nicht erreichbar" auf
      // „nichts zu tun" zu schliessen. Dann bliebe bei jedem Netzwackler die
      // ganze Warteschlange liegen.
      expect(gatewayQuelle,
          contains('anstehend == null || anstehend[name] == true'),
          reason: 'Die Sonde darf im Fehlerfall nicht sperren, sondern muss '
              'auf das alte Verhalten zurückfallen');
    });

    test('_restAbarbeiten fragt ohne Sonde weiterhin alles', () {
      // Ein künftiger Aufrufer, der `faellig` nicht kennt, muss das ALTE
      // Verhalten bekommen — nicht stillschweigend gar keines.
      expect(gatewayQuelle, contains('bool Function(String) faellig = _immerFaellig'));
      expect(gatewayQuelle, contains('static bool _immerFaellig(String _) => true;'));
    });

    test('die Sonde holt keine Zeilen, sondern nur Ja/Nein', () {
      // Sie darf nie zum zweiten Ort werden, an dem die Abfragen der fünf
      // Endpunkte nachgebaut sind — genau das liefe beim nächsten Umbau
      // auseinander.
      expect(apiQuelle, contains("_postGatewayWarteschlange('gateway/anstehend.php'"));
    });
  });

  group('Ortung', () {
    test('der grobe Transit-Verbraucher fordert NICHT die volle Genauigkeit', () {
      // ⚠️ `StandortStrom.anmelden` hat als Vorgabe `LocationAccuracy.high`,
      // und `_Anforderung.ausAbos` nimmt das MAXIMUM aller Verbraucher. Ein
      // Verbraucher, der `genauigkeit` weglässt, hält damit den Empfänger der
      // GANZEN App am Satelliten — auch wenn er selbst nur 100 m alle drei
      // Minuten braucht.
      //
      // Bis zum 03.09.2026 war genau das der Fall. Aufgefallen ist es erst,
      // als klar wurde, dass auf dem Gerät Play Services abgeschaltet sind:
      // dann wählt geolocator `LocationManagerClient`, und dessen
      // `determineProvider` geht auf den AOSP-FUSED_PROVIDER oder direkt auf
      // `GPS_PROVIDER` — es gibt keine Fused-Heuristik, die eine zu hohe
      // Anforderung abfedert.
      final quelle =
          File('lib/services/transit_service.dart').readAsStringSync();
      final block = RegExp(
        r"anmelden\(\s*name: 'Transit \(grob\)'.*?\);",
        dotAll: true,
      ).firstMatch(quelle);
      expect(block, isNotNull,
          reason: 'Die Anmeldung "Transit (grob)" wurde umbenannt oder entfernt');
      expect(block!.group(0), contains('genauigkeit:'),
          reason: 'Ohne ausdrückliche Genauigkeit erbt dieser Verbraucher '
              'LocationAccuracy.high und hebt den Strom der ganzen App an');
      // ⚠️ Auf das ARGUMENT prüfen, nicht auf den blossen Namen: der
      // Kommentar daneben erklärt die Falle und nennt `LocationAccuracy.high`
      // dabei wörtlich. Ein Test, der darauf anschlägt, meldet den Kommentar.
      expect(block.group(0),
          isNot(contains('genauigkeit: LocationAccuracy.high')),
          reason: 'Ein "grober" Verbraucher darf nicht die volle Genauigkeit '
              'fordern');
    });
  });

  group('Herzschlag', () {
    test('Takt bleibt unter dem Online-Fenster des Servers', () {
      // ⚠️ KOPPLUNG AN DEN SERVER: `api/chat/support_status.php` hält jemanden
      // für online, solange der letzte Herzschlag höchstens
      // ONLINE_FENSTER_SEKUNDEN = 180 zurückliegt. Das PHP liegt in keinem
      // Repo, deshalb steht die Zahl hier.
      //
      // Bis zum 03.09.2026 passte es nicht: 60 s hier gegen 30 s dort, also
      // galt der Vorsitz die halbe Zeit als offline, obwohl die App lief.
      // Live nachgemessen an dem Tag: seconds_since_active 32.
      //
      // Wer diesen Wert erhöht, erhöht ONLINE_FENSTER_SEKUNDEN mit — sonst
      // flackert die Anzeige wieder, und zwar ohne jede Fehlermeldung.
      const serverFensterSekunden = 180;
      expect(HeartbeatService.taktSekunden, lessThan(serverFensterSekunden),
          reason: 'Der Takt muss kleiner sein als das Online-Fenster des Servers');
      // Und mit Luft für einen ausgefallenen Schlag.
      expect(HeartbeatService.taktSekunden * 2, lessThanOrEqualTo(serverFensterSekunden + 60));
    });
  });
}
