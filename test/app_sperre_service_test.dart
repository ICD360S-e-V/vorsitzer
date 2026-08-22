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
      s.pruefen();
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

  group('Leerlauf — an der Uhr, nicht heruntergezählt', () {
    test('frisch bedient bleibt fast die volle Zeit übrig', () async {
      final s = AppSperreService();
      await s.zuruecksetzen();
      await s.passwortSetzen('zeit-test-123');
      s.vermerkeBedienung(erzwingen: true);
      expect(s.verbleibend.inMinutes, greaterThanOrEqualTo(14));
      expect(s.verbleibend, lessThanOrEqualTo(AppSperreService.leerlauf));
      expect(s.warntGleich, isFalse);
    });

    test('die Warnschwelle liegt bei einer Minute', () {
      expect(AppSperreService.warnungAb, const Duration(minutes: 1));
      expect(AppSperreService.leerlauf, const Duration(minutes: 15));
    });

    test('Entprellung: schnelle Wiederholungen kosten nichts', () async {
      final s = AppSperreService();
      await s.zuruecksetzen();
      await s.passwortSetzen('entprell-123');
      s.vermerkeBedienung(erzwingen: true);
      final a = s.verbleibend;
      for (var i = 0; i < 500; i++) {
        s.vermerkeBedienung();
      }
      // Ohne Bremse hätte jede der 500 Wiederholungen die Zeit neu gesetzt;
      // mit Bremse bleibt sie stehen (bis auf den Lauf der Uhr).
      expect((a - s.verbleibend).inMilliseconds, lessThan(2000));
    });

    test('sperren() wirkt nur bei gesetztem Passwort', () async {
      final s = AppSperreService();
      await s.zuruecksetzen();
      await s.laden();
      s.sperren();
      expect(s.istGesperrt, isFalse,
          reason: 'ohne Passwort gäbe es keinen Weg zurück');
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
      s.pruefen();
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
}
