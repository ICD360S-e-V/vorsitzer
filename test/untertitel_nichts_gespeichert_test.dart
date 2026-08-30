import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Der Text der Mitschrift verlässt das Gerät nicht — und wird nirgends abgelegt.
///
/// 🔴 WARUM DAS EINE PRÜFUNG BRAUCHT UND KEIN VERSPRECHEN IST.
/// `LoggerService` lädt die Protokollzeilen zum Server hoch (`_uploadQueue`,
/// `POST` mit dem Feld `logs`). Heute steht in keiner Zeile der Mitschrift ein
/// gesprochenes Wort — geprüft wurden alle vier Log-Aufrufe im Dienst und alle
/// drei in `Untertitel.kt`, sie tragen Ausnahmen und Zähler. Es genügt aber ein
/// `_log.info('Untertitel: $text')`, und private Gespräche lägen auf dem
/// Server, ohne dass irgendetwas fehlschlägt.
///
/// Dem User wurde zugesagt: es wird nichts aufgezeichnet und nichts
/// gespeichert. Diese Datei ist die Stelle, an der ein Bruch dieser Zusage
/// auffällt.
void main() {
  late String dienst;
  late String nativ;

  setUpAll(() {
    dienst = File('lib/services/untertitel_service.dart').readAsStringSync();
    nativ = File(
            'android/app/src/main/kotlin/de/icd360sev/vorsitzer/Untertitel.kt')
        .readAsStringSync();
  });

  test('der Dienst legt nichts ab — keine Datei, kein Speicher, kein Server', () {
    for (final verboten in const [
      'SharedPreferences',
      'writeAsString',
      'writeAsBytes',
      'SecureStore',
      'ApiService',
      'sipgateAction',
      'getApplicationDocumentsDirectory',
      'getApplicationSupportDirectory',
    ]) {
      expect(dienst, isNot(contains(verboten)), reason: 'legt ab: $verboten');
    }
  });

  test('kein Log-Aufruf trägt gesprochene Wörter', () {
    // ⚠️ Geprüft werden die ARGUMENTE der Log-Aufrufe, nicht die ganze Datei:
    // die Bezeichner kommen im übrigen Code natürlich vor.
    final aufrufe = RegExp(r"_log\.\w+\(([^;]*?)\)\s*;", dotAll: true)
        .allMatches(dienst)
        .map((m) => m.group(1) ?? '')
        .toList();
    expect(aufrufe, isNotEmpty, reason: 'keine Log-Aufrufe gefunden — Test blind');

    for (final a in aufrufe) {
      for (final wort in const [
        r'$text',
        r'${text',
        r'$_vorlaeufig',
        r'$_saetze',
        r'${_saetze',
        r"e['text']",
        r"e['partial']",
      ]) {
        expect(a, isNot(contains(wort)),
            reason: 'Mitschrift im Protokoll: $wort in »$a«');
      }
    }
  });

  test('auch die native Seite protokolliert keine Wörter', () {
    final aufrufe = RegExp(r'Log\.\w+\(([^\n]*)\)')
        .allMatches(nativ)
        .map((m) => m.group(1) ?? '')
        .toList();
    expect(aufrufe, isNotEmpty, reason: 'keine Log-Aufrufe gefunden — Test blind');

    for (final a in aufrufe) {
      for (final wort in const [r'$w', r'$roh', r'optString', r'$text']) {
        expect(a, isNot(contains(wort)),
            reason: 'Mitschrift im Android-Protokoll: $wort in »$a«');
      }
    }
  });

  test('die native Seite schreibt keine Datei ausser dem Modellordner', () {
    for (final verboten in const [
      'openFileOutput',
      'FileOutputStream',
      'FileWriter',
      'getSharedPreferences',
      'MediaRecorder',
      'AudioRecord',
    ]) {
      expect(nativ, isNot(contains(verboten)), reason: 'schreibt: $verboten');
    }
  });

  test('beenden räumt Text und Sätze weg', () {
    final i = dienst.indexOf('Future<void> beenden()');
    expect(i, isNot(-1));
    final rumpf = dienst.substring(i, i + 700);
    expect(rumpf, contains('_saetze.clear()'));
    expect(rumpf, contains("_vorlaeufig = ''"));
    expect(rumpf, contains("text.value = ''"));
  });
}
