import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Die Erkennung auf dem Server — und die Zusagen, die dabei gelten.
///
/// ⚠️ QUELLTEXT-PRÜFUNG, wie `sipgate_lebenszeichen_test.dart`: der Weg führt
/// über einen WebSocket, einen Plattformkanal und einen laufenden Anruf. Um
/// ihn beobachtend zu prüfen, müsste man alle drei nachbilden und am Ende
/// dieselben Eigenschaften prüfen, die hier direkt dastehen.
void main() {
  late String dienst;
  late String strom;
  late String nativ;

  setUpAll(() {
    dienst = File('lib/services/untertitel_service.dart').readAsStringSync();
    strom = File('lib/services/untertitel_strom.dart').readAsStringSync();
    nativ = File(
            'android/app/src/main/kotlin/de/icd360sev/vorsitzer/Untertitel.kt')
        .readAsStringSync();
  });

  test('der Server wird ZUERST versucht, das Gerät ist der Rückfall', () {
    // Am Telefonband gemessen: Gerät 17,6 % Wortfehler, Server 0,0 %.
    final i = dienst.indexOf('Future<String?> starten(String spurId');
    expect(i, isNot(-1));
    final rumpf = dienst.substring(i, i + 1600);
    expect(rumpf, contains('_stromStarten(spurId)'));
    // Und der Rückfall kommt DANACH, nicht stattdessen.
    expect(rumpf.indexOf('_stromStarten'),
        lessThan(rumpf.indexOf("_kanal.invokeMapMethod")));
  });

  test('ein Abriss schaltet auf das Gerät um, statt still zu werden', () {
    // ⚠️ Sonst stünde der Text mitten im Gespräch und ohne Erklärung.
    //
    // ⚠️ Auf den AUFRUF geprüft, nicht auf den Namen: die Definition der
    // Methode enthält ihn auch, und meine erste Fassung bestand deshalb noch,
    // als ich den Aufruf zur Gegenprobe entfernt hatte.
    expect(dienst, contains('unawaited(_aufGeraetUmschalten());'));
    final i = dienst.indexOf('Future<void> _aufGeraetUmschalten()');
    expect(i, isNot(-1));
    final r = dienst.substring(i, i + 400);
    expect(r, contains('await beenden()'));
    expect(r, contains('starten(spur)'));
  });

  test('im Strommodus erkennt das Gerät NICHT mit', () {
    // Sonst zahlte das Tablet Speicher und Rechenzeit für ein Ergebnis, das
    // niemand benutzt.
    final i = nativ.indexOf('fun starten(');
    final r = nativ.substring(i, i + 1400);
    expect(r, contains('if (!strom) {'));
    expect(r, contains('Recognizer(m, ZIEL_RATE.toFloat())'));
    // Und das Modell wird im Strommodus nicht verlangt.
    expect(r, contains('if (!strom && !modellDa(ctx))'));
  });

  test('der Ton geht als Little-Endian-PCM hinaus', () {
    // ⚠️ Andersherum hätten beide Seiten Rauschen statt Sprache — und nichts
    // würde fehlschlagen, es käme nur nie ein Wort heraus.
    final i = nativ.indexOf('if (strommodus) {');
    expect(i, isNot(-1));
    // ⚠️ Weit genug: die Begründung darüber ist lang, und ein zu kleines
    // Fenster lässt den Test scheitern, obwohl der Code stimmt.
    final r = nativ.substring(i, i + 1200);
    expect(r, contains('(v and 0xFF).toByte()'));
    expect(r, contains('((v shr 8) and 0xFF).toByte()'));
    expect(r, contains('melde("ton"'));
  });

  test('die Anmeldung läuft über einen Einmal-Schlüssel, nicht über Kopfzeilen', () {
    expect(strom, contains('asrToken()'));
    // Der Schlüssel geht als ERSTE Nachricht, vor jedem Ton.
    final i = strom.indexOf('WebSocket.connect(url)');
    expect(i, isNot(-1));
    final r = strom.substring(i, i + 300);
    expect(r, contains("jsonEncode({'token': token})"));
  });

  test('beim Beenden wird das Ende ANGESAGT, bevor geschlossen wird', () {
    // Sonst geht der letzte, noch nicht abgeschlossene Satz verloren — und das
    // ist meistens der, den man gerade lesen wollte.
    // ⚠️ NICHT über die ganze Methode geprüft: sie hat oben einen früheren
    // Ausstieg für den Fall, dass die Strecke gar nicht offen ist, und DORT
    // wird richtigerweise nur geschlossen. Meine erste Fassung dieses Tests
    // sah jenen `close()` und meldete einen Fehler, den es nicht gab.
    final i = strom.indexOf('// ⚠️ Erst das Ende ansagen');
    expect(i, isNot(-1), reason: 'Begründung fehlt — Abschnitt nicht gefunden');
    // ⚠️ Bis zum Dateiende begrenzen: der Abschnitt liegt am Schluss, und ein
    // festes Fenster lief über das Ende hinaus.
    final r = strom.substring(i, (i + 500).clamp(i, strom.length));
    // ⚠️ ERST auf Vorhandensein prüfen. `indexOf` gibt bei Fehlen -1 zurück,
    // und -1 ist kleiner als jede Position — der Vergleich allein bestand
    // also auch dann, wenn die Ansage ganz fehlte. Genau so ist meine erste
    // Fassung dieses Tests durch die Gegenprobe gerutscht.
    expect(r, contains(r'{"eof":1}'));
    expect(r, contains('close()'));
    expect(r.indexOf(r'{"eof":1}'), lessThan(r.indexOf('close()')));
  });

  test('nichts wird gespeichert — auch auf diesem Weg nicht', () {
    for (final verboten in const [
      'SharedPreferences',
      'writeAsString',
      'writeAsBytes',
      'File(',
      'ApiService().sipgateAction',
    ]) {
      expect(strom, isNot(contains(verboten)), reason: 'legt ab: $verboten');
    }
  });

  test('kein Log-Aufruf trägt gesprochenen Text', () {
    // Dieselbe Regel wie überall — siehe kein_inhalt_im_protokoll_test.
    final aufrufe = RegExp(
      r"""_log\.(?:info|debug|warning|error)\(\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")""",
    ).allMatches(strom).map((m) => m.group(1) ?? m.group(2) ?? '').toList();
    expect(aufrufe, isNotEmpty);
    for (final a in aufrufe) {
      for (final w in const [r'$text', r'${text', r'$pcm', r'$teil']) {
        expect(a, isNot(contains(w)), reason: 'Wortlaut im Protokoll: $w');
      }
    }
  });

  test('der Ton wird zu 100-ms-Stücken gesammelt, nicht einzeln geschickt', () {
    // 🔴 GEMESSEN, und die naheliegende Wahl war die schlechteste. WebRTC
    // liefert 10-ms-Rahmen; einzeln weitergereicht hing der Text im Median
    // 556 ms hinter dem Ton, weil der Server 100 Übergaben je Sekunde machen
    // muss. Bei 100 ms sind es 85 ms — und zehnmal weniger Pakete auf einer
    // Leitung, auf der wir Einbrüche unter 2 Mbit/s gemessen haben.
    //
    // ⚠️ Grösser ist auch nicht besser: 250 ms ergaben wieder 292 ms Verzug.
    expect(nativ, contains('STROM_STUECK_MS = 100'));
    expect(nativ, contains('if (stromPuffer.size < STROM_PROBEN) continue'));
    // Und der Puffer wird beim Start geleert, sonst begänne das nächste
    // Gespräch mit einem Rest des vorigen.
    final i = nativ.indexOf('warteschlange.clear()');
    expect(nativ.substring(i, i + 300), contains('stromPuffer.clear()'));
  });

  test('die Aufbaufrist ist kurz', () {
    // ⚠️ Unsere eigenen Speedtest-Messungen zeigen auf dieser Leitung Spitzen
    // bis 7.402 ms und Tage unter 2 Mbit/s. Wer zwanzig Sekunden auf den
    // Server wartet, hat so lange gar keine Mitschrift.
    expect(strom, contains('Duration(seconds: 6)'));
  });
}
