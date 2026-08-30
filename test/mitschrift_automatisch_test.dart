import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Die Mitschrift startet von selbst — und die Bedingungen dafür.
///
/// ⚠️ QUELLTEXT-PRÜFUNG, wie `sipgate_lebenszeichen_test.dart` und aus
/// demselben Grund: die Regel steht in einem `switch`-Zweig eines privaten
/// Rückrufs, den nur ein laufender SIP-Stack mit einer eingetroffenen Tonspur
/// auslöst. Um sie beobachtend zu prüfen, müsste man den halben Stack
/// nachbilden und am Ende dieselbe Eigenschaft prüfen, die hier dasteht.
void main() {
  late String quelle;

  setUpAll(() {
    final f = File('lib/services/sipgate_service.dart');
    expect(f.existsSync(), isTrue);
    quelle = f.readAsStringSync();
  });

  String rumpf(String ab, String bis) {
    final i = quelle.indexOf(ab);
    expect(i, isNot(-1), reason: 'nicht gefunden: $ab');
    final j = quelle.indexOf(bis, i);
    return quelle.substring(i, j == -1 ? quelle.length : j);
  }

  test('angestossen wird es bei der TONSPUR, nicht beim Verbinden', () {
    // ⚠️ Bei `CONFIRMED` gibt es die Spur noch nicht; die native Seite meldete
    // dann nur „Tonspur der Gegenstelle nicht gefunden".
    // ⚠️ Der Anstoss heisst `_mitschriftAufNeueSpur` — sie startet die
    // Automatik, wenn nichts läuft, und hängt eine laufende Mitschrift sonst
    // auf die neue Spur um. Beides gehört an DIESES Ereignis.
    final stream = rumpf('case CallStateEnum.STREAM:', 'case CallStateEnum.MUTED');
    expect(stream, contains('_mitschriftAufNeueSpur()'));

    final confirmed = rumpf('case CallStateEnum.CONFIRMED:', 'case CallStateEnum.FAILED');
    expect(confirmed, isNot(contains('_mitschrift')));
  });

  test('ohne vorhandenes Modell wird NICHT von selbst geholt', () {
    // Sonst zöge ein angenommener Anruf 46 MB über die Mobilfunkleitung, ohne
    // dass jemand das wollte.
    final m = rumpf('Future<void> _mitschriftVonSelbst()', '\n  /// Beginnt die Güte');
    expect(m, contains('UntertitelModell().vorhanden()'));
    // Und die Prüfung muss VOR dem Starten kommen.
    expect(m.indexOf('vorhanden()'), lessThan(m.indexOf('u.starten(')));
  });

  test('in der Konferenz nicht', () {
    final m = rumpf('Future<void> _mitschriftVonSelbst()', '\n  /// Beginnt die Güte');
    expect(m, contains('konferenz'));
  });

  test('ein Fehlschlag geht ins Protokoll, nicht auf den Bildschirm', () {
    // Von selbst gestartet heisst: es hat niemand danach gefragt. Eine
    // Fehlermeldung über den Bildschirm zu legen, während man gerade abhebt,
    // wäre schlimmer als keine Mitschrift.
    final m = rumpf('Future<void> _mitschriftVonSelbst()', '\n  /// Beginnt die Güte');
    expect(m, contains('_log.warning'));
    for (final verboten in const ['_letzteAbsage', 'showDialog', '_melde(']) {
      expect(m, isNot(contains(verboten)), reason: 'meldet nach aussen: $verboten');
    }
  });

  test('die Tonspur wird ERFRAGT, nicht erinnert', () {
    // 🔴 Gemeldet: „Tonspur der Gegenstelle nicht gefunden", obwohl das
    // Gespräch lief. Im hochgeladenen Protokoll desselben Tages stehen ZWEI
    // `Tonspur der Gegenstelle steht` binnen 37 Sekunden im selben Anruf
    // (21:08:07 und 21:08:44) — eine Neuverhandlung, bei der die Gegenstelle
    // eine NEUE Spur mit neuer Kennung bekommt. Die gemerkte zeigt danach ins
    // Leere; nativ wird auch in den Transceivern gesucht und trotzdem nichts
    // gefunden, weil die alte Kennung nirgends mehr vorkommt.
    expect(quelle, contains('Future<String?> gegenstelleSpurAktuell()'));
    expect(quelle, contains('await pc.getReceivers()'));

    final m = rumpf('Future<void> _mitschriftVonSelbst()', '\n  /// Beginnt die Güte');
    expect(m, contains('await gegenstelleSpurAktuell()'));
    expect(m, isNot(contains('final id = gegenstelleSpurId;')),
        reason: 'nimmt wieder die gemerkte Kennung');
  });

  test('eine laufende Mitschrift wird auf die neue Spur gesetzt', () {
    // ⚠️ Ohne das hinge sie nach der Neuverhandlung an einer Spur, die niemand
    // mehr füttert — sie würde einfach still, ohne Fehler und ohne Hinweis.
    final stream = rumpf('case CallStateEnum.STREAM:', 'case CallStateEnum.MUTED');
    expect(stream, contains('_mitschriftAufNeueSpur()'));

    final m = rumpf('Future<void> _mitschriftAufNeueSpur()',
        '\n  Future<void> _mitschriftVonSelbst()');
    // Erst lösen, dann binden: der Sink hängt nativ an der ALTEN Spur.
    expect(m.indexOf('u.beenden()'), lessThan(m.indexOf('u.starten(')));
  });

  test('auch der Knopf im Bildschirm fragt die lebende Spur ab', () {
    final b = File('lib/screens/sipgate_screen.dart').readAsStringSync();
    expect(b, contains('gegenstelleSpurAktuell()'));
    expect(b, isNot(contains("u.starten(_dienst.gegenstelleSpurId ?? '')")));
  });

  test('am Gesprächsende hört sie wieder auf', () {
    // ⚠️ Sonst liefe die Erkennung nach dem Auflegen weiter — und mit ihr der
    // Text, der ausdrücklich mit dem Gespräch verschwinden soll.
    final ende = rumpf('case CallStateEnum.FAILED:', 'case CallStateEnum.HOLD');
    expect(ende, contains('UntertitelService().beenden()'));
  });
}
