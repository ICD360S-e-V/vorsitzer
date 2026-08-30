import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🔴 Der schwarze Bildschirm nach dem Einbau des Mikrofons.
///
/// `onTrack` feuert je SPUR. Das Mitglied haengt den Bildschirm an
/// `_screenStream` und das Mikrofon an `_mikroStream` — zwei verschiedene
/// Streams. Wer im Betrachter blind `event.streams[0]` nimmt, ueberschreibt
/// den Bildschirm mit der Tonspur, sobald sie als zweite eintrifft.
///
/// Dass daraus Schwarz wird, steht in flutter_webrtc selbst
/// (`FlutterRTCVideoRenderer.setStream`):
///
///     List<VideoTrack> videoTracks = mediaStream.videoTracks;
///     videoTrack = videoTracks.isEmpty() ? null : videoTracks.get(0);
///     setVideoTrack(videoTrack);
///
/// Ein Stream ohne Videospur ergibt `null` — es wird nichts gezeichnet.
///
/// ⚠️ Geprueft wird der QUELLTEXT, weil der Fehler nur in einem echten
/// `onTrack`-Rueckruf mit zwei Spuren auftritt: dafuer braeuchte es zwei
/// verbundene WebRTC-Gegenstellen. Dieselbe Vorgehensweise wie in
/// `sipgate_lebenszeichen_test.dart`.
void main() {
  final quelle = File('lib/services/remote_control_service.dart').readAsStringSync();

  test('onTrack nimmt NUR die Videospur fuer die Anzeige', () {
    final block = RegExp(r'_pc!\.onTrack = \(event\) \{(.*?)\n    \};', dotAll: true)
        .firstMatch(quelle)
        ?.group(1);
    expect(block, isNotNull, reason: 'onTrack-Block nicht gefunden');
    expect(block, contains("event.track.kind != 'video'"),
        reason: 'ohne diese Pruefung ueberschreibt die Tonspur das Bild');
  });

  test('die Tonspur setzt den angezeigten Stream nicht', () {
    final block = RegExp(r'_pc!\.onTrack = \(event\) \{(.*?)\n    \};', dotAll: true)
        .firstMatch(quelle)!
        .group(1)!;
    // Die Zuweisung darf erst NACH dem frühen Ausstieg kommen.
    final ausstieg = block.indexOf('return;');
    final zuweisung = block.indexOf('_remoteStream = event.streams[0]');
    expect(ausstieg, greaterThan(-1));
    expect(zuweisung, greaterThan(ausstieg),
        reason: 'sonst greift die Pruefung zu spaet');
  });
}
