import 'package:flutter_test/flutter_test.dart';

/// Der Kiosk legt beim Aufbau vier Dauerdienste still: Fernwahl, SMS-Gateway,
/// Speedtest, Wachdienst.
///
/// ⚠️ Bis 24.08.2026 standen alle vier in EINEM `try`. Wirft der erste — und
/// `AnrufGatewayService.setEnabled(false)` greift über einen MethodChannel nach
/// einem Vordergrunddienst, kann also sehr wohl werfen —, laufen die drei
/// danach gar nicht mehr. Die einzige Spur war ein `debugPrint`, den in einem
/// Release-Build niemand sieht.
///
/// Was das kostet, ist nicht theoretisch: das Pixel stand im Kiosk und fragte
/// trotzdem 48-mal je Stunde `chat/sms_inbox.php` ab. Es hat keine
/// Vereins-SIM — es liest also den PRIVATEN Posteingang eines Telefons und
/// schreibt dessen Nachrichten in die Akten von Mitgliedern (am 13.08. fünf
/// Zeilen).
///
/// Hier steht die Ablaufregel selbst, ohne Flutter-Widgets: der Kiosk-Bildschirm
/// braucht Plugins, die im Test nicht existieren, und ein Test, der dafür alles
/// wegmockt, prüft am Ende nur die Mocks.
void main() {
  /// Nachbau von `_rollenStillegen`: jeder Schalter in seinem eigenen Versuch,
  /// Fehlschläge werden gesammelt statt geworfen.
  Future<List<String>> stillegenAlle(
    List<(String, Future<bool> Function(), Future<void> Function())> rollen,
  ) async {
    final gescheitert = <String>[];
    for (final (name, istAn, aus) in rollen) {
      try {
        if (await istAn()) await aus();
      } catch (_) {
        gescheitert.add(name);
      }
    }
    return gescheitert;
  }

  test('ein werfender Schalter reisst die anderen nicht mit', () async {
    final abgeschaltet = <String>[];
    final gescheitert = await stillegenAlle([
      ('Fernwahl', () async => true, () async => throw StateError('Kanal tot')),
      ('SMS-Gateway', () async => true, () async => abgeschaltet.add('sms')),
      ('Speedtest', () async => true, () async => abgeschaltet.add('speed')),
      ('Wachdienst', () async => true, () async => abgeschaltet.add('wach')),
    ]);

    // Das ist der ganze Punkt: die drei nach dem Fehlschlag laufen trotzdem.
    expect(abgeschaltet, ['sms', 'speed', 'wach']);
    expect(gescheitert, ['Fernwahl']);
  });

  test('ein Schalter, der ohnehin aus ist, wird nicht angefasst', () async {
    var beruehrt = 0;
    final gescheitert = await stillegenAlle([
      ('SMS-Gateway', () async => false, () async => beruehrt++),
    ]);
    expect(beruehrt, 0);
    expect(gescheitert, isEmpty);
  });

  test('auch die Abfrage „ist es an?" darf werfen, ohne den Rest zu stoppen',
      () async {
    final abgeschaltet = <String>[];
    final gescheitert = await stillegenAlle([
      ('Fernwahl', () async => throw StateError('kein Plugin'), () async {}),
      ('SMS-Gateway', () async => true, () async => abgeschaltet.add('sms')),
    ]);
    expect(abgeschaltet, ['sms']);
    expect(gescheitert, ['Fernwahl']);
  });

  test('klappt alles, bleibt die Liste leer — dann steht auch keine Warnung da',
      () async {
    final gescheitert = await stillegenAlle([
      ('Fernwahl', () async => true, () async {}),
      ('SMS-Gateway', () async => true, () async {}),
    ]);
    expect(gescheitert, isEmpty);
  });
}
