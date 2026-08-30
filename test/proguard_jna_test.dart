import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Die R8-Regeln, ohne die die Live-Mitschrift im Release-Bau nicht startet.
///
/// 🔴 WARUM ES DIESEN TEST GIBT. Im ausgelieferten APK 6.174.0 hatte
/// `com.sun.jna.Pointer` genau EIN Feld, und es hiess `j`. `libjnidispatch.so`
/// sucht es per JNI unter dem Namen `peer`; findet es das nicht, scheitert der
/// statische Initialisierer von `com.sun.jna.Native`. Weil
/// `LibVosk.<clinit>` ihn über `Native.register(LibVosk.class, "vosk")`
/// auslöst, stand am Ende `org.vosk.LibVosk` in Rot auf dem Schirm — an einer
/// Klasse, an der nichts kaputt war.
///
/// ⚠️ KEIN ANDERER TEST KANN DAS FINDEN. `flutter analyze` fasst Kotlin nicht
/// an, die Testsuite baut kein Release, und im DEBUG-Bau läuft R8 gar nicht —
/// dort funktioniert die Mitschrift also. Der Fehler entsteht ausschliesslich
/// beim Verkleinern, also erst in dem Paket, das die Mitglieder bekommen.
/// Siehe [[ci-green-is-not-tested]].
void main() {
  late String regeln;

  setUpAll(() {
    final f = File('android/app/proguard-rules.pro');
    expect(f.existsSync(), isTrue, reason: 'proguard-rules.pro fehlt');
    regeln = f.readAsStringSync();
  });

  test('JNA bleibt vollständig erhalten — mit ZWEI Sternen', () {
    // ⚠️ Die offizielle JNA-Regel benutzt einen Stern. Der deckt nur das
    // oberste Paket, nicht `com.sun.jna.ptr` und `com.sun.jna.internal`.
    expect(regeln, contains('-keep class com.sun.jna.** { *; }'));
    expect(regeln, contains('-keepclassmembers class com.sun.jna.** { *; }'));
  });

  test('org.vosk bleibt erhalten', () {
    expect(regeln, contains('-keep class org.vosk.** { *; }'));
  });

  test('die Begründung steht dabei', () {
    // Eine Regel ohne Grund wird beim nächsten Aufräumen entfernt — genau so
    // käme der Fehler zurück.
    expect(regeln, contains('libjnidispatch'));
    expect(regeln, contains('peer'));
  });

  test('R8 ist im Release überhaupt an', () {
    // Wäre es aus, wäre dieser Test bedeutungslos und man wüsste es nicht.
    final g = File('android/app/build.gradle.kts').readAsStringSync();
    expect(g, contains('isMinifyEnabled = true'));
  });
}
