import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:icd360sev_vorsitzer/services/standort_strom.dart';

/// Ersatz-Plattform: schreibt mit, mit welchen Einstellungen ein Strom
/// angefordert wurde, und lässt uns Positionen von Hand einspeisen.
class _FakeGeolocator extends GeolocatorPlatform with MockPlatformInterfaceMixin {
  final List<LocationSettings?> angefordert = [];
  final List<StreamController<Position>> regler = [];
  int abbestellt = 0;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    angefordert.add(locationSettings);
    final c = StreamController<Position>.broadcast(
      onCancel: () => abbestellt++,
    );
    regler.add(c);
    return c.stream;
  }

  void sende(Position p) {
    if (regler.isEmpty) return;
    regler.last.add(p);
  }
}

Position _pos(double lat, double lon) => Position(
      latitude: lat,
      longitude: lon,
      timestamp: DateTime(2026, 8, 13),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

/// Ein Grad Breite ≈ 111 km, also sind 0.001° ≈ 111 m.
Position _posMeterNoerdlich(double meter) => _pos(48.4 + meter / 111000.0, 10.0);

void main() {
  late _FakeGeolocator fake;

  setUp(() async {
    fake = _FakeGeolocator();
    GeolocatorPlatform.instance = fake;
    await StandortStrom.instance.alleAbmeldenFuerTest();
  });

  tearDown(() async {
    await StandortStrom.instance.alleAbmeldenFuerTest();
  });

  test('ein feinerer Verbraucher baut den Strom neu auf', () async {
    final grob = StandortStrom.instance.anmelden(
      name: 'grob',
      abstandMeter: 100,
      intervall: const Duration(seconds: 15),
      onPosition: (_) {},
    );
    await pumpEventQueue();
    expect(StandortStrom.instance.aktiveAnforderung, contains('100 m'));
    expect(StandortStrom.instance.aktiveAnforderung, contains('15000 ms'));

    final fein = StandortStrom.instance.anmelden(
      name: 'karte',
      abstandMeter: 10,
      intervall: const Duration(seconds: 2),
      onPosition: (_) {},
    );
    await pumpEventQueue();

    // ⚠️ Der Kern des Ganzen: geolocator gibt bei einem zweiten Aufruf den
    // alten Strom zurück und verwirft die neuen Einstellungen. Es muss also
    // wirklich abbestellt und neu angefordert worden sein.
    expect(fake.abbestellt, 1);
    expect(fake.angefordert.length, 2);
    expect(StandortStrom.instance.aktiveAnforderung, contains('10 m'));
    expect(StandortStrom.instance.aktiveAnforderung, contains('2000 ms'));

    fein.abmelden();
    await pumpEventQueue();
    expect(StandortStrom.instance.aktiveAnforderung, contains('100 m'));

    grob.abmelden();
    await pumpEventQueue();
    expect(StandortStrom.instance.aktiveAnforderung, 'aus');
  });

  test('jeder Verbraucher behält seine eigene Schwelle', () async {
    final grobe = <Position>[];
    final feine = <Position>[];

    StandortStrom.instance.anmelden(
      name: 'grob',
      abstandMeter: 100,
      intervall: Duration.zero,
      onPosition: grobe.add,
    );
    StandortStrom.instance.anmelden(
      name: 'karte',
      abstandMeter: 10,
      intervall: Duration.zero,
      onPosition: feine.add,
    );
    await pumpEventQueue();

    fake.sende(_posMeterNoerdlich(0)); // erster Fix — beide bekommen ihn
    await pumpEventQueue();
    fake.sende(_posMeterNoerdlich(20)); // nur für den feinen weit genug
    await pumpEventQueue();
    fake.sende(_posMeterNoerdlich(40));
    await pumpEventQueue();
    fake.sende(_posMeterNoerdlich(150)); // jetzt auch für den groben
    await pumpEventQueue();

    expect(feine.length, 4);
    // Der Wetterdienst wird nicht dadurch gesprächiger, dass eine Karte offen
    // ist — sonst hätte der Umbau ihn vervierfacht.
    expect(grobe.length, 2);
  });

  test('ein neuer Verbraucher bekommt sofort die letzte bekannte Position',
      () async {
    StandortStrom.instance.anmelden(
      name: 'erst',
      abstandMeter: 0,
      intervall: Duration.zero,
      onPosition: (_) {},
    );
    await pumpEventQueue();
    fake.sende(_pos(48.4, 10.0));
    await pumpEventQueue();

    final spaet = <Position>[];
    StandortStrom.instance.anmelden(
      name: 'karte',
      abstandMeter: 10,
      intervall: const Duration(seconds: 2),
      onPosition: spaet.add,
    );
    await pumpEventQueue();

    // Ohne das startet eine frisch geöffnete Karte ohne Standort und wartet
    // auf den nächsten Fix.
    expect(spaet.length, 1);
    expect(spaet.first.latitude, 48.4);
  });

  test('Vordergrunddienst gilt, sobald ihn einer anfordert', () async {
    StandortStrom.instance.anmelden(
      name: 'grob',
      abstandMeter: 100,
      intervall: const Duration(seconds: 15),
      onPosition: (_) {},
    );
    final alarm = StandortStrom.instance.anmelden(
      name: 'alarm',
      abstandMeter: 5,
      intervall: const Duration(seconds: 2),
      vordergrunddienst: true,
      onPosition: (_) {},
    );
    await pumpEventQueue();
    expect(StandortStrom.instance.aktiveAnforderung, contains('Vordergrund'));

    alarm.abmelden();
    await pumpEventQueue();
    expect(StandortStrom.instance.aktiveAnforderung, isNot(contains('Vordergrund')));
  });
}
