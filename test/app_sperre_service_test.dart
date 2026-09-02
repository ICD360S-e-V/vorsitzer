import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/app_sperre_service.dart';
import 'package:icd360sev_vorsitzer/utils/sperre_passwort.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    // ⚠️ Unter Linux faellt `SecureStore` auf eine verschluesselte Datei
    // zurueck, wenn der Schluesselbund nicht antwortet — und dafuer braucht es
    // `path_provider`. Ohne diese Vorspiegelung scheitern die Tests an einer
    // fehlenden Plattform-Umsetzung statt an der Logik, die geprueft werden
    // soll. Genau dieser Rueckfallweg ist im Betrieb der Regelfall (siehe
    // Kommentar in secure_store.dart), er gehoert also mitgeprueft.
    tempDir = Directory.systemTemp.createTempSync('sperre_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider_linux'),
      (call) async => tempDir.path,
    );
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('Zustand', () {
    test('ohne gesetztes Passwort wird nicht gesperrt', () async {
      final s = AppSperreService();
      await s.zuruecksetzen();
      await s.laden();
      expect(s.istEingerichtet, isFalse);
      expect(s.istGesperrt, isFalse,
          reason: 'sonst käme man ohne Passwort nie wieder hinein');
      expect(s.istGesperrt, isFalse);
    });

    test('mit gesetztem Passwort ist nach dem Laden gesperrt', () async {
      final s = AppSperreService();
      await s.zuruecksetzen();
      await s.passwortSetzen('Start-Passwort-1');
      expect(s.istGesperrt, isFalse, reason: 'direkt nach dem Setzen offen');

      // Neustart nachstellen: laden() liest den abgelegten Wert.
      await s.laden();
      expect(s.istEingerichtet, isTrue);
      expect(s.istGesperrt, isTrue,
          reason: 'die Vorgabe lautet: beim Öffnen fragen');
    });

    test('richtiges Passwort entsperrt, falsches nicht', () async {
      final s = AppSperreService();
      await s.zuruecksetzen();
      await s.passwortSetzen('Start-Passwort-1');
      await s.laden();
      expect(await s.entsperren('falsch'), isFalse);
      expect(s.istGesperrt, isTrue);
      expect(await s.entsperren('Start-Passwort-1'), isTrue);
      expect(s.istGesperrt, isFalse);
    });

    test('Abmelden räumt das Passwort weg', () async {
      final s = AppSperreService();
      await s.zuruecksetzen();
      await s.passwortSetzen('weg-damit-123');
      await s.zuruecksetzen();
      await s.laden();
      expect(s.istEingerichtet, isFalse);
      expect(s.istGesperrt, isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Kein Leerlauf mehr — Entscheidung des Users, 02.09.2026.
  //
  // Bis dahin sperrte die App nach 15 Minuten ohne Bedienung. Das hat mitten
  // in der Arbeit nach dem Passwort gefragt. Es bleiben drei Anlaesse:
  // Neustart, Schloss-Knopf, und die App ueber dem Geraete-Sperrbildschirm.
  //
  // ⚠️ Diese Proben pruefen den QUELLTEXT mit. Der Rueckfall waere sonst
  // lautlos: baut jemand `vermerkeBedienung`/`pruefen`/einen Sekundentakt
  // wieder ein, faellt keine Zusicherung ueber den Zustand um — die App wuerde
  // einfach wieder sperren, und gemeldet haette es niemand.
  // ══════════════════════════════════════════════════════════════════════════
  group('Kein Leerlauf', () {
    test('nach dem Entsperren bleibt offen, egal wie viel Zeit vergeht',
        () async {
      final s = AppSperreService();
      await s.zuruecksetzen();
      await s.passwortSetzen('kein-leerlauf-123');
      await s.laden();
      expect(s.istGesperrt, isTrue);
      expect(await s.entsperren('kein-leerlauf-123'), isTrue);
      expect(s.istGesperrt, isFalse);
      // Frueher haette hier ein Takt nach 15 Minuten zugeschlagen. Es gibt
      // keinen mehr — der Zustand kann sich ohne Zutun gar nicht mehr aendern.
      expect(s.istGesperrt, isFalse);
    });

    test('der Dienst kennt keine Leerlauf-Begriffe mehr', () {
      final quelle =
          File('lib/services/app_sperre_service.dart').readAsStringSync();
      // Der Kopfkommentar erklaert, warum es sie nicht mehr gibt — geprueft
      // wird deshalb der Code, nicht die Datei.
      final code = quelle
          .split('\n')
          .where((z) => !z.trimLeft().startsWith('//'))
          .join('\n');
      for (final wort in [
        'vermerkeBedienung',
        'Timer.periodic',
        'taktStarten',
        'warntGleich',
        'leerlauf',
      ]) {
        expect(code, isNot(contains(wort)),
            reason: 'die Leerlaufsperre ist zurueck: $wort');
      }
    });

    test('die Huelle lauscht nicht mehr auf Zeiger und Tasten', () {
      final quelle =
          File('lib/widgets/app_sperre_huelle.dart').readAsStringSync();
      final code = quelle
          .split('\n')
          .where((z) => !z.trimLeft().startsWith('///'))
          .join('\n');
      // Ein Lauscher ueber dem ganzen Baum kostet bei jeder Wischgeste Arbeit.
      expect(code, isNot(contains('onPointerMove')));
      expect(code, isNot(contains('HardwareKeyboard.instance.addHandler')));
    });

    test('sperren() wirkt nur bei gesetztem Passwort', () async {
      final s = AppSperreService();
      await s.zuruecksetzen();
      await s.laden();
      s.sperren();
      expect(s.istGesperrt, isFalse,
          reason: 'ohne Passwort gäbe es keinen Weg zurück');
    });

    test('sperren() ist der Schloss-Knopf und muss sofort greifen', () async {
      final s = AppSperreService();
      await s.zuruecksetzen();
      await s.passwortSetzen('schloss-knopf-123');
      expect(s.istGesperrt, isFalse);
      s.sperren();
      expect(s.istGesperrt, isTrue,
          reason: 'seit dem 02.09.2026 der einzige Weg neben dem Neustart');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Aussperr-Proben — die Fälle, in denen niemand mehr hineinkäme.
  //
  // Nachgemessen, worauf sie sich stützen:
  //  * Android löscht die Keystore-Schlüssel beim Deinstallieren. Holt
  //    Auto-Backup den Chiffretext zurück, ist er unlesbar.
  //  * Linux/Flatpak behält `~/.var/app/<id>/data/keyrings` — Deinstallieren
  //    allein hilft dort NICHT. Deshalb gibt es den Aktivierungscode-Weg.
  // ══════════════════════════════════════════════════════════════════════════
  group('Aussperren — darf nicht passieren', () {
    test('unlesbarer Eintrag gilt als KEIN Passwort, nicht als unknackbares',
        () async {
      // Der Android-Fall nach Deinstallieren + Auto-Backup: der Chiffretext
      // ist da, der Schlüssel weg. Würde das als „Passwort gesetzt" gelten,
      // wäre das Gerät für immer zu.
      final s = AppSperreService();
      await s.zuruecksetzen();
      FlutterSecureStorage.setMockInitialValues({
        'app_sperre_v1': 'unlesbarer rest aus einem backup',
      });
      await s.laden();
      expect(s.istEingerichtet, isFalse);
      expect(s.istGesperrt, isFalse, reason: 'sonst käme niemand mehr hinein');
    });

    test('halb geschriebener Eintrag sperrt ebenfalls nicht aus', () async {
      final s = AppSperreService();
      for (final rest in [
        '{"v":1,"salz":"AAAA"}',                 // Hash fehlt
        '{"v":1,"hash":"AAAA","runden":120000}', // Salz fehlt
        '{"v":1,"salz":"","hash":"","runden":120000}',
        '{',                                      // abgeschnitten
      ]) {
        await s.zuruecksetzen();
        FlutterSecureStorage.setMockInitialValues({'app_sperre_v1': rest});
        await s.laden();
        expect(s.istGesperrt, isFalse, reason: 'bei: $rest');
        expect(s.istEingerichtet, isFalse, reason: 'bei: $rest');
      }
    });

    test('die Wartestaffel sperrt nie dauerhaft aus', () async {
      // Fünf Minuten sind ärgerlich. Eine Stunde wäre ein Aussperren.
      for (final n in [5, 10, 50, 1000, 100000]) {
        expect(sperreWartezeit(n),
            lessThanOrEqualTo(const Duration(minutes: 5)),
            reason: '$n Fehlversuche');
      }
    });

    test('zuruecksetzen() öffnet immer — das ist der Weg des Codes', () async {
      // Nach erfolgreicher Freischaltung mit dem Aktivierungscode wird genau
      // das gerufen. Es muss unter allen Umständen aufgehen.
      final s = AppSperreService();
      await s.zuruecksetzen();
      await s.passwortSetzen('vergessenes-passwort');
      await s.laden();
      expect(s.istGesperrt, isTrue);
      await s.zuruecksetzen();
      expect(s.istGesperrt, isFalse);
      expect(s.istEingerichtet, isFalse,
          reason: 'danach fragt die App nach einem neuen Passwort');
      // Und ein Neustart darf das alte Passwort nicht wieder hervorholen.
      await s.laden();
      expect(s.istGesperrt, isFalse);
      expect(s.istEingerichtet, isFalse);
    });

    test('ohne Passwort führt kein Weg in den gesperrten Zustand', () async {
      final s = AppSperreService();
      await s.zuruecksetzen();
      await s.laden();
      s.sperren();
      for (var i = 0; i < 10; i++) {
        await s.entsperren('falsch');
      }
      expect(s.istGesperrt, isFalse);
    });
  });

  group('Wartestaffel', () {
    test('vier Fehlversuche sperren die Eingabe noch nicht', () async {
      final s = AppSperreService();
      await s.zuruecksetzen();
      await s.passwortSetzen('staffel-test-1');
      await s.laden();
      for (var i = 0; i < 4; i++) {
        expect(await s.entsperren('falsch$i'), isFalse);
      }
      expect(s.fehlversuche, 4);
      expect(s.wartezeitRest, Duration.zero);
      // Das richtige Passwort geht weiterhin sofort.
      expect(await s.entsperren('staffel-test-1'), isTrue);
      expect(s.fehlversuche, 0, reason: 'Erfolg setzt den Zähler zurück');
    });

    test('ab dem fünften Fehlversuch wird gewartet', () async {
      final s = AppSperreService();
      await s.zuruecksetzen();
      await s.passwortSetzen('staffel-test-2');
      await s.laden();
      for (var i = 0; i < 5; i++) {
        await s.entsperren('falsch$i');
      }
      expect(s.wartezeitRest, greaterThan(Duration.zero));
      // Während der Wartezeit wird selbst das RICHTIGE Passwort abgewiesen —
      // sonst liesse sich die Staffel durch Weiterprobieren aushebeln.
      expect(await s.entsperren('staffel-test-2'), isFalse);
      expect(s.istGesperrt, isTrue);
    });
  });

  group('Über dem Sperrbildschirm', () {
    test('gesperrtes Gerät + gesetztes Passwort → sperren', () async {
      final s = AppSperreService();
      await s.zuruecksetzen();
      await s.passwortSetzen('ueber-lock-passwort');
      expect(s.istGesperrt, isFalse);
      expect(s.sollUeberLockschirmSperren(true), isTrue);
      expect(s.sollUeberLockschirmSperren(false), isFalse,
          reason: 'Gerät nicht gesperrt → kein Grund zu sperren');
    });
    test('ohne gesetztes Passwort nicht', () async {
      final s = AppSperreService();
      await s.zuruecksetzen();
      expect(s.sollUeberLockschirmSperren(true), isFalse);
    });
    test('bereits gesperrt → nichts zu tun', () async {
      final s = AppSperreService();
      await s.zuruecksetzen();
      await s.passwortSetzen('ueber-lock-passwort');
      s.sperren();
      expect(s.istGesperrt, isTrue);
      expect(s.sollUeberLockschirmSperren(true), isFalse);
    });
  });
}
