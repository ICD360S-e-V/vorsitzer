import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/voice_call_service.dart';

/// Die Form der ICE-Server-Liste, festgenagelt.
///
/// Am 11.08.2026 kam ein Anruf zwischen dem Vorsitzer (Android) und einem
/// Mitglied (Windows) zustande, klingelte, zeigte auf beiden Seiten „verbunden"
/// mit laufender Gesprächsdauer — und übertrug **null Byte**. Ursache war nicht
/// das Netz und nicht der TURN-Server, sondern diese Liste:
///
/// ```dart
/// {'urls': [turnUdp, turnTcp, turnsTls], 'username': …, 'credential': …}
/// ```
///
/// Die Desktop-Brücke von flutter_webrtc (Windows und Linux teilen sich
/// `common/cpp/src/flutter_webrtc_base.cc`) liest `urls` in `IceServer.uri` —
/// ein **einzelner String** — und überschreibt ihn in jedem Schleifendurchlauf.
/// Von N URIs überlebt nur die **letzte**. Auf Windows blieb damit einzig
/// `turns:…:5349` übrig, ausgerechnet der Transport, dessen TLS-Handshake
/// libwebrtc nicht abschließen kann (fest einkompilierter Zertifikatsspeicher
/// `ssl_roots.h`, der die Let's-Encrypt-Hierarchie „Root YE" nicht kennt).
/// Ergebnis: kein einziger Relay-Kandidat, und bei
/// `iceTransportPolicy: 'relay'` heißt das gar kein Kandidat.
///
/// Android hat einen eigenen Java-Pfad (`IceServer.builder(urlsList)`) und
/// behält alle URIs — deshalb war der Fehler auf dem Telefon unsichtbar und
/// fiel monatelang niemandem auf.
///
/// Die gruppierte Form sieht im Review völlig vernünftig aus und entspricht
/// sogar dem W3C-Vorbild. Genau deshalb steht sie hier unter Test: sie wird
/// sonst beim nächsten Aufräumen zurückgebaut.
void main() {
  const uris = <String>[
    'stun:turn.icd360s.de:3478',
    'turn:turn.icd360s.de:3478?transport=udp',
    'turn:turn.icd360s.de:3478?transport=tcp',
    'turns:turn.icd360s.de:5349?transport=tcp',
  ];

  group('iceServerEintraege', () {
    test('jede URI bekommt einen eigenen Eintrag', () {
      final servers = iceServerEintraege(uris, 'benutzer', 'geheim');
      expect(servers, hasLength(uris.length));
      expect(
        servers.map((s) => s['urls']).toList(),
        uris,
        reason: 'Reihenfolge und Vollständigkeit müssen erhalten bleiben',
      );
    });

    test('urls ist NIE eine Liste — sonst überlebt auf Desktop nur die letzte URI', () {
      for (final s in iceServerEintraege(uris, 'benutzer', 'geheim')) {
        expect(
          s['urls'],
          isA<String>(),
          reason: 'flutter_webrtc common/cpp überschreibt IceServer.uri je '
              'Listenelement — eine Liste reduziert den Client still auf einen '
              'einzigen Transport',
        );
      }
    });

    test('alle drei TURN-Transporte überleben, nicht nur turns:', () {
      final urls = iceServerEintraege(uris, 'benutzer', 'geheim')
          .map((s) => s['urls'] as String)
          .toList();
      expect(urls, contains('turn:turn.icd360s.de:3478?transport=udp'));
      expect(urls, contains('turn:turn.icd360s.de:3478?transport=tcp'));
      expect(urls, contains('turns:turn.icd360s.de:5349?transport=tcp'));
    });

    test('nur TURN trägt Zugangsdaten, STUN nicht', () {
      final servers = iceServerEintraege(uris, 'benutzer', 'geheim');
      for (final s in servers) {
        final url = s['urls'] as String;
        if (url.startsWith('stun:')) {
          expect(s.containsKey('username'), isFalse);
          expect(s.containsKey('credential'), isFalse);
        } else {
          expect(s['username'], 'benutzer');
          expect(s['credential'], 'geheim');
        }
      }
    });

    test('unbekannte Schemata werden verworfen, nicht durchgereicht', () {
      final servers = iceServerEintraege(
        ['http://turn.icd360s.de', 'stun:turn.icd360s.de:3478'],
        'b',
        'g',
      );
      expect(servers, hasLength(1));
      expect(servers.single['urls'], 'stun:turn.icd360s.de:3478');
    });

    test('gedeckelt auf die native Feldgröße — der C++-Code prüft die Grenze nicht', () {
      final viele = List.generate(20, (i) => 'turn:relay$i.icd360s.de:3478');
      final servers = iceServerEintraege(viele, 'b', 'g');
      expect(servers, hasLength(VoiceCallService.maxIceServer));
      expect(VoiceCallService.maxIceServer, 8,
          reason: 'kMaxIceServerSize in third_party/libwebrtc/include/rtc_types.h');
    });

    test('leere Eingabe ergibt leere Liste (Aufrufer wirft TURN_UNAVAILABLE)', () {
      expect(iceServerEintraege(const [], 'b', 'g'), isEmpty);
    });
  });
}
