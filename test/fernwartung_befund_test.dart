import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/remote_control_service.dart';

/// Die Zahlen, an denen der Vorsitz „ruckelt" und „verbraucht zu viel"
/// festmachen kann — und die Fallen beim Ausrechnen.
void main() {
  BildBefund b({
    int empfangen = 0,
    int dekodiert = 0,
    int bytes = 0,
    int breite = 0,
    int hoehe = 0,
    String? codec,
    int kbit = 0,
    double fps = 0,
    double? rttMs,
  }) =>
      BildBefund(
        empfangen: empfangen,
        dekodiert: dekodiert,
        bytes: bytes,
        breite: breite,
        hoehe: hoehe,
        codec: codec,
        kbit: kbit,
        fps: fps,
        rttMs: rttMs,
      );

  test('die erste Zeile zeigt Bildrate, Verbrauch und Umlaufzeit', () {
    final z = b(fps: 12.4, kbit: 960, rttMs: 62).kurz;
    expect(z, contains('12 fps'));
    // 960 kbit/s sind 120 kB/s — der Wert, an dem man den Mobilfunkvertrag misst.
    expect(z, contains('120 kB/s'));
    expect(z, contains('62 ms'));
  });

  /// ⚠️ Unter 10 fps entscheidet die erste Nachkommastelle, ob es „noch geht"
  /// oder „steht": 2 fps und 2,4 fps sehen gleich aus, 2 und 9 nicht.
  test('unter 10 fps mit einer Nachkommastelle', () {
    expect(b(fps: 2.4).kurz, contains('2.4 fps'));
    expect(b(fps: 24.6).kurz, contains('25 fps'));
  });

  test('ohne Messung steht ein Strich, keine erfundene Null', () {
    expect(b().kurz, contains('– fps'));
    expect(b().kurz.contains('kB/s'), isFalse,
        reason: 'eine 0 waere eine Aussage, die noch niemand gemessen hat');
  });

  /// Die Gegenseite haengt an einem Mobilfunkvertrag. Eine halbe Stunde bei
  /// 120 kB/s sind rund 200 MB — das gehoert sichtbar gemacht.
  test('die zweite Zeile nennt das Gesamtvolumen', () {
    expect(b(bytes: 4 * 1024 * 1024).zweiteZeile, contains('4.0 MB'));
    expect(b(bytes: 210 * 1024 * 1024).zweiteZeile, contains('210 MB'));
  });

  test('die zweite Zeile nennt Format und Bildzaehler', () {
    final z = b(breite: 1080, hoehe: 2400, codec: 'VP8', dekodiert: 300, empfangen: 302)
        .zweiteZeile;
    expect(z, contains('1080×2400'));
    expect(z, contains('VP8'));
    expect(z, contains('300/302'));
  });

  /// Die Deutungen muessen sich gegenseitig ausschliessen, sonst zeigt die
  /// Zeile zwei Ursachen gleichzeitig an.
  test('stumm und nichtDekodiert schliessen einander aus', () {
    expect(b().stumm, isTrue);
    expect(b().nichtDekodiert, isFalse);

    final ohneDekodierung = b(empfangen: 90, bytes: 50000);
    expect(ohneDekodierung.stumm, isFalse);
    expect(ohneDekodierung.nichtDekodiert, isTrue);

    final gut = b(empfangen: 90, dekodiert: 90, bytes: 50000);
    expect(gut.stumm, isFalse);
    expect(gut.nichtDekodiert, isFalse);
  });
}
