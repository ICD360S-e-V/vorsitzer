import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/weather_service.dart';

/// Der Ortungsstrom lief bis 09.08.2026 weiter, während der Bildschirm aus
/// war — beim ÖPNV mit `LocationAccuracy.high` alle 15 Sekunden, also mit
/// dauernd eingeschaltetem Satellitenempfänger, für eine Abfahrtstafel, die
/// in der Hosentasche niemand ansieht.
///
/// Beim Abschalten lauert ein zweiter Fehler, der leichter zu machen als zu
/// bemerken ist: beim Aufwachen alles wieder einzuschalten — auch bei jemandem,
/// der die Ortung absichtlich aus hatte. Ein Schalter, der sich von selbst
/// umlegt, ist schlimmer als keiner, und auffallen würde es nur dem, der
/// nachmisst.
void main() {
  group('Ortung pausieren', () {
    test('eine ausgeschaltete Ortung bleibt nach dem Aufwachen aus', () {
      final wetter = WeatherService();
      expect(wetter.folgtGps, isFalse,
          reason: 'Vorbedingung: ohne start(followGps: true) ist die Ortung aus');

      wetter.ortungPausieren();
      wetter.ortungFortsetzen();

      expect(wetter.folgtGps, isFalse,
          reason: 'Das Aufwachen darf die Ortung nicht von selbst einschalten.');
    });

    test('mehrfaches Pausieren vergisst den Ausgangszustand nicht', () {
      final wetter = WeatherService();

      wetter.ortungPausieren();
      wetter.ortungPausieren();
      wetter.ortungFortsetzen();

      expect(wetter.folgtGps, isFalse);
    });
  });
}
