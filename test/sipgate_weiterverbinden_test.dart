import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Weiterverbinden läuft über die sipgate-Anlage, NICHT über SIP-REFER.
///
/// ⚠️ Der SIP-Weg wäre naheliegend — `sip_ua` hat `Call.refer()`. Er hat aber
/// zwei Eigenschaften, die hier nicht tragen, beide nachgelesen in
/// `sip_ua-1.1.0/lib/src/sip_ua_helper.dart`:
///
///  * `refer.on(EventReferFailed(), (data) {});` — der Zweig ist **leer**. Eine
///    von der Gegenstelle abgelehnte Übergabe meldet nichts; der Vorsitzer
///    hielte sie für geglückt und legte auf.
///  * Er kann nur BLIND übergeben. Die Übergabe mit Ansage („ich verbinde
///    Sie") kennt er gar nicht.
///
/// Über `POST /calls/{id}/transfer` kommt ein HTTP-Status zurück, den man
/// hinschreiben kann, und `attended: true` ist genau die Ansage.
/// Nur der Code, ohne Kommentare — sonst prüft der Test die eigene
/// Begründung mit. Genau das ist beim ersten Lauf passiert: die Zeile
/// „`sip_ua` kann zwar `Call.refer()`" im Doc-Kommentar liess die Prüfung
/// „REFER wird nirgends benutzt" scheitern. Dieselbe Hilfe wie in
/// `rdp_nur_modus_test.dart`.
List<String> _nurCode(String quelltext) => quelltext
    .split('\n')
    .where((l) =>
        !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('///'))
    .toList();

void main() {
  String quelle(String p) => File(p).readAsStringSync();
  String code(String p) => _nurCode(quelle(p)).join('\n');

  test('der Bildschirm nimmt den Weg über die Anlage', () {
    final q = quelle('lib/screens/sipgate_screen.dart');
    expect(q, contains("'action': 'weiterverbinden'"));
    expect(q, contains("'action': 'laufende_gespraeche'"));
    // Die Kennung der Anlage (`pbx-…`) ist eine andere als die von `sip_ua`;
    // nur mit ihr lässt sich übergeben. Sie muss also geholt werden.
    expect(q.indexOf("'action': 'laufende_gespraeche'"),
        lessThan(q.indexOf("'action': 'weiterverbinden'")),
        reason: 'ohne call_id von der Anlage kann nicht übergeben werden');
  });

  test('SIP-REFER wird nirgends benutzt', () {
    // Nicht aus Prinzip, sondern wegen des leeren Fehlerzweigs oben.
    for (final p in const [
      'lib/services/sipgate_service.dart',
      'lib/screens/sipgate_screen.dart',
    ]) {
      expect(code(p), isNot(contains('.refer(')), reason: p);
    }
  });

  test('mit Ansage ist die Voreinstellung', () {
    // Bei der blinden Übergabe ist der Anrufer verloren, wenn drüben niemand
    // abnimmt. Wer das will, soll es wählen müssen.
    final q = quelle('lib/screens/sipgate_screen.dart');
    expect(q, contains('var mitAnsage = true;'));
  });

  test('ein Fehlschlag wird gezeigt, nicht verschluckt', () {
    final q = quelle('lib/screens/sipgate_screen.dart');
    expect(q, contains("_melde('\${a['message']"));
  });
}
