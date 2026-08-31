import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/voice_call_service.dart';

/// 🔴 Der Fehler, der die Fernwartung mit einem Mitglied auf WINDOWS
/// unbrauchbar machte, waehrend sie mit Telefonen lief.
///
/// Die C++-Bruecke von flutter_webrtc (Windows und Linux teilen sie) liest
/// `urls` in einen EINZELNEN String und ueberschreibt ihn je Durchlauf — von
/// N URIs ueberlebt nur die letzte. Android behaelt alle, weshalb es mit
/// Telefonen jahrelang gutging. Die letzte URI ist `turns:…:5349`, dessen
/// TLS-Handschlag libwebrtc nicht zustande bringt; mit
/// `iceTransportPolicy: relay` bleiben damit null Kandidaten.
void main() {
  const uris = [
    'stun:turn.icd360s.de:3478',
    'turn:turn.icd360s.de:3478?transport=udp',
    'turn:turn.icd360s.de:3478?transport=tcp',
    'turns:turn.icd360s.de:5349?transport=tcp',
  ];

  test('jede URI bekommt einen eigenen Eintrag', () {
    final e = iceServerEintraege(uris, 'u', 'p');
    expect(e.length, 4);
    for (final s in e) {
      expect(s['urls'], isA<String>(),
          reason: 'eine Liste ueberlebt den Schreibtisch nicht');
    }
  });

  /// Die Fernwartung baute die Liste selbst und gruppiert. Sie MUSS denselben
  /// Helfer benutzen wie der Anrufdienst, sonst laeuft die Reparatur wieder
  /// auseinander — und zwar unsichtbar, weil Android weiter funktioniert.
  test('der Betrachter benutzt den gemeinsamen Helfer', () {
    final quelle =
        File('lib/services/remote_control_service.dart').readAsStringSync();
    expect(quelle, contains('iceServerEintraege(uris, username, password)'));
    expect(quelle.contains("{'urls': turn,"), isFalse,
        reason: 'die gruppierte Form darf nicht zurueckkommen');
  });
}
