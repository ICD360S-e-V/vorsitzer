import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Prüfungen am QUELLTEXT.
///
/// ⚠️ Warum so: hier geht es um Zusicherungen, die nur ein laufender
/// Vordergrunddienst auf einem echten Gerät verletzen würde — mit dem einzigen
/// sichtbaren Symptom „der Akku ist morgens leer". Dieselbe Bauart wie
/// `sipgate_lebenszeichen_test.dart` und `proguard_jna_test.dart`.
void main() {
  final dienst =
      File('lib/services/signatur_gateway_service.dart').readAsStringSync();
  final plugin = File(
    'packages/icd_wachlicht/android/src/main/kotlin/de/icd360sev/'
    'icd_wachlicht/IcdWachlichtPlugin.kt',
  ).readAsStringSync();

  /// Quelltext ohne Kommentare.
  ///
  /// ⚠️ Ohne das prüft ein Test die eigene Prosa. Genau das ist hier zweimal
  /// passiert: der Kommentar, der `acquire()` als Fehler ERKLÄRT, enthält die
  /// Zeichenfolge — und ein Test, der stumpf danach sucht, meldet die
  /// Erklärung statt des Fehlers. Wer eine Regel am Quelltext prüft, muss
  /// vorher die Stellen entfernen, an denen über die Regel geredet wird.
  String ohneKommentare(String q) => q
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .split('\n')
      .map((z) {
        final i = z.indexOf('//');
        return i < 0 ? z : z.substring(0, i);
      })
      .join('\n');

  final pluginCode = ohneKommentare(plugin);
  final dienstCode = ohneKommentare(dienst);

  final ntfy = File('lib/services/ntfy_service.dart').readAsStringSync();
  final ntfyCode = ohneKommentare(ntfy);

  group('Stillstandswache am ntfy-Strom', () {
    test('das Lebenszeichen setzt die Wache zurück — VOR jedem Filter', () {
      // 🔴 DER FEHLER, DEN DAS BEHEBT
      // Läuft die NAT-Zuordnung des Betreibers ab, ist die Verbindung tot,
      // ohne dass irgendetwas davon erfährt: kein FIN, kein RST, kein Fehler.
      // `onDone` feuert nicht, `onError` feuert nicht — `_verbunden` blieb
      // deshalb für immer auf `true`. Die App hielt sich für erreichbar,
      // während niemand mehr zuhörte.
      //
      // ⚠️ Die Reihenfolge IST die Zusicherung. Stünde `_wacheStellen()`
      // hinter dem Filter auf `event == 'message'`, schlüge die Wache in genau
      // den ruhigen Stunden an, in denen alles in Ordnung ist — dann kommen
      // nämlich ausschliesslich `keepalive`-Zeilen.
      final rumpf = RegExp(
        r'void _handleLine\(String line\) \{(.*?)\n  \}',
        dotAll: true,
      ).firstMatch(ntfyCode);
      expect(rumpf, isNotNull, reason: '_handleLine wurde umbenannt');
      final wache = rumpf!.group(1)!.indexOf('_wacheStellen()');
      final leer = rumpf.group(1)!.indexOf('line.trim().isEmpty');
      final filter = rumpf.group(1)!.indexOf("event != 'message'");
      expect(wache, greaterThan(-1),
          reason: 'Der Strom hat keine Stillstandswache mehr');
      expect(wache, lessThan(leer),
          reason: 'Auch eine leere Zeile ist ein Lebenszeichen');
      expect(wache, lessThan(filter),
          reason: 'Ein keepalive ist das EINZIGE, was in ruhigen Stunden '
              'ankommt — es muss die Wache zurücksetzen');
    });

    test('die Frist lässt mehrere Lebenszeichen ausfallen', () {
      // ⚠️ Kopplung an den Server: ntfy schickt alle 45 s ein keepalive
      // (`keepalive-interval`, Vorgabe, bei uns nicht überschrieben). Die
      // Frist muss ein Vielfaches davon sein, sonst beendet ein verzögertes
      // Paket eine gesunde Verbindung. Das PHP bzw. die Serverconfig liegt in
      // keinem Repo — deshalb steht die Zahl hier.
      const serverKeepaliveSekunden = 45;
      final m = RegExp(r'_stillstandsfrist = Duration\(seconds: (\d+)\)')
          .firstMatch(ntfyCode);
      expect(m, isNotNull, reason: '_stillstandsfrist wurde umbenannt');
      final frist = int.parse(m!.group(1)!);
      expect(frist, greaterThanOrEqualTo(serverKeepaliveSekunden * 3),
          reason: 'Zu kurz: ein verzögertes Lebenszeichen würde eine gesunde '
              'Verbindung abreissen');
    });

    test('beim Anschlagen wird der Zustand zurückgesetzt, nicht nur neu verbunden', () {
      // Ohne `_scheduleReconnect()` (das als Erstes `_verbunden = false`
      // setzt) blieben Abfragetakt UND Wachlicht im Sparmodus stehen,
      // während in Wahrheit niemand mehr zuhört.
      final block = RegExp(
        r'void _wacheStellen\(\) \{.*?\n  \}',
        dotAll: true,
      ).firstMatch(ntfyCode);
      expect(block, isNotNull);
      expect(block!.group(0), contains('_scheduleReconnect()'));
    });
  });

  group('Wachlicht', () {
    test('der Dauerlock des Plugins ist an ALLEN Stellen aus', () {
      // ⚠️ Es sind zwei: `init()` und `taktAnpassen()`. Nur eine umzustellen
      // wirkt gar nicht — beim nächsten Dienststart gewönne die andere.
      expect(dienstCode, isNot(contains('allowWakeLock: true')),
          reason: 'allowWakeLock: true nimmt einen PARTIAL_WAKE_LOCK ohne '
              'Zeitgrenze für die Lebensdauer des Dienstes');
      expect('allowWakeLock: false'.allMatches(dienstCode).length, 2,
          reason: 'Erwartet an genau zwei Stellen (init + taktAnpassen)');
    });

    test('das Wachlicht hängt am Zustand der Weckleitung, nicht an einem Schalter', () {
      // Steht der ntfy-Strom, weckt sein Lebenszeichen (alle 45 s) das Gerät
      // ohnehin und der Lock ist überflüssig. Reisst er, ist die Abfrage die
      // einzige Absicherung — und die braucht einen wachen Prozessor.
      expect(dienst, contains('NtfyService().istVerbunden'),
          reason: 'Ohne diesen Umschalter fällt das Wachlicht nicht von '
              'allein zurück, wenn der Strom reisst');
      final block = RegExp(
        r'Future<void> _wachlichtNachfuehren\(\) async \{.*?\n  \}',
        dotAll: true,
      ).firstMatch(dienst);
      expect(block, isNotNull,
          reason: '_wachlichtNachfuehren wurde umbenannt oder entfernt');
      expect(block!.group(0), contains('IcdWachlicht.freigeben()'));
      expect(block.group(0), contains('IcdWachlicht.nehmen('));
    });

    test('es wird bei jedem Takt nachgeführt, vor der Anmeldung', () {
      // ⚠️ Nach der Anmeldeprüfung wäre falsch: ein Gerät, das sich gerade
      // nicht anmelden kann, stiege vorher aus — und stünde ausgerechnet
      // dann ohne Wachlicht da, wenn nichts mehr funktioniert.
      final ort = dienst.indexOf('await _wachlichtNachfuehren();');
      final anmeldung = dienst.indexOf('if (!await _anmelden()) {');
      expect(ort, greaterThan(-1),
          reason: 'Der Takt führt das Wachlicht nicht mehr nach');
      expect(ort, lessThan(anmeldung),
          reason: 'Das Wachlicht muss VOR der Anmeldeprüfung nachgeführt '
              'werden, sonst fehlt es genau im Störungsfall');
    });

    test('der alte Dauerlock wird beim Update einmal aktiv abgeworfen', () {
      // 🔴 Ohne diesen Schritt greift die ganze Änderung erst beim nächsten
      // Geräte-Neustart. `allowWakeLock` wird nur in
      // `startForegroundService()` ausgewertet; `updateService` läuft über
      // `API_UPDATE` und fasst den Lock nicht an. Und weil
      // `autoRunOnMyPackageReplaced: true` den Dienst nach dem Update mit den
      // ALTEN Einstellungen wieder hochfährt, wird der Dauerlock dabei erneut
      // genommen.
      expect(dienstCode, contains('_wachlichtUmstellen()'),
          reason: 'Ohne einmaligen Neustart bleibt der alte Dauerlock '
              'gehalten — und der PR sähe wirkungslos aus');
      final block = RegExp(
        r'Future<void> _wachlichtUmstellen\(\) async \{.*?\n  \}',
        dotAll: true,
      ).firstMatch(dienstCode);
      expect(block, isNotNull);
      expect(block!.group(0), contains('await stoppen()'));
      expect(block.group(0), contains('await starten()'));
      // ⚠️ Nur wenn der Dienst läuft — ihn hier zu STARTEN wäre etwas anderes.
      expect(block.group(0), contains('if (await laeuft())'),
          reason: 'Die Umstellung darf keinen Dienst starten, der auf diesem '
              'Gerät gar nicht hingehört');
    });

    test('beim Beenden des Dienstes wird freigegeben', () {
      final block = RegExp(
        r'Future<void> onDestroy\(.*?\n  \}',
        dotAll: true,
      ).firstMatch(dienst);
      expect(block, isNotNull);
      expect(block!.group(0), contains('IcdWachlicht.freigeben()'),
          reason: 'Ein beendeter Dienst darf das Gerät nicht bis zum Ablauf '
              'der Zeitgrenze wach halten');
    });

    test('KEIN acquire ohne Zeitgrenze — das ist der ganze Punkt', () {
      // ⚠️ Genau dieser Aufruf steht in flutter_foreground_task
      // (ForegroundService.kt:428) und ist der Grund für dieses Paket. Ein
      // Absturz zwischen Nehmen und Freigeben liesse das Gerät sonst bis zum
      // Neustart wach — Googles „stuck wake lock".
      expect(pluginCode, isNot(contains(RegExp(r'\bacquire\(\s*\)'))),
          reason: 'acquire() ohne Argument hält den Lock unbegrenzt');
      expect(pluginCode, contains('l.acquire(grenze)'));
      expect(pluginCode, contains('MAX_GRENZE_MS'),
          reason: 'Ohne Obergrenze könnte ein Aufrufer die Zeitgrenze '
              'beliebig hoch setzen und den Dauerlock wieder herstellen');
    });

    test('das Plugin gibt beim Abbau der Engine frei', () {
      final block = RegExp(
        r'override fun onDetachedFromEngine\(.*?\n    \}',
        dotAll: true,
      ).firstMatch(plugin);
      expect(block, isNotNull);
      expect(block!.group(0), contains('freigeben()'),
          reason: 'Stirbt die Engine mit gehaltenem Lock, gibt ihn niemand '
              'mehr frei');
    });
  });
}
