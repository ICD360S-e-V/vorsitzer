import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ⚠️ Die WebRTC-Fassung im App-Modul MUSS die von `flutter_webrtc` sein.
///
/// Das App-Modul bindet die AAR `compileOnly` ein, um `org.webrtc.AudioTrack`
/// für die Live-Untertitel übersetzen zu können — geladen wird zur Laufzeit
/// aber die, die `flutter_webrtc` mitbringt. Laufen die beiden auseinander,
/// merkt das niemand beim Bauen: es fällt erst auf dem Gerät auf, als
/// `NoSuchMethodError` mitten im Gespräch.
///
/// Dieser Test liest beide Zahlen aus den Build-Dateien und vergleicht sie.
void main() {
  test('App-Modul und flutter_webrtc übersetzen gegen dieselbe WebRTC-AAR', () {
    final app = File('android/app/build.gradle.kts').readAsStringSync();
    final meine = RegExp(r'io\.github\.webrtc-sdk:android:([0-9.]+)')
        .firstMatch(app)
        ?.group(1);
    expect(meine, isNotNull, reason: 'compileOnly-Zeile fehlt im App-Modul');

    // Den Pfad zum Paket aus der Sperrdatei holen, damit der Test eine
    // Aktualisierung von flutter_webrtc mitbekommt statt an einer festen
    // Versionsnummer vorbeizulaufen.
    final lock = File('pubspec.lock').readAsStringSync();
    final v = RegExp(r'flutter_webrtc:[\s\S]{0,400}?version: "([0-9.+]+)"')
        .firstMatch(lock)
        ?.group(1);
    expect(v, isNotNull, reason: 'flutter_webrtc steht nicht in pubspec.lock');

    final heim = Platform.environment['PUB_CACHE'] ??
        '${Platform.environment['HOME']}/.pub-cache';
    final gradle = File('$heim/hosted/pub.dev/flutter_webrtc-$v/android/build.gradle');
    if (!gradle.existsSync()) {
      // Kein Grund, den Lauf rot zu machen — auf einem CI-Rechner ohne
      // warmen Paketspeicher gibt es die Datei nicht. Aber sagen muss man es.
      markTestSkipped('flutter_webrtc-$v nicht im Paketspeicher: ${gradle.path}');
      return;
    }
    final seine = RegExp(r'io\.github\.webrtc-sdk:android:([0-9.]+)')
        .firstMatch(gradle.readAsStringSync())
        ?.group(1);
    expect(meine, seine,
        reason: 'App-Modul übersetzt gegen $meine, flutter_webrtc lädt $seine');
  });
}
