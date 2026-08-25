import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/sekunden_takt.dart';

/// Bis zum 25.08.2026 hielt ein `Timer.periodic` im Dienst die Gesprächsdauer
/// in Gang, indem er jede Sekunde einen **kompletten neuen Zustand** in
/// `SipgateService.zustand` schob. Zwei Folgen, und die zweite war ein echter
/// Fehler:
///
///  1. Jeder Zuhörer wurde im Sekundentakt neu gebaut — auch die Kopfleiste
///     des Dashboards, die von der Dauer kein Wort zeigt.
///
///  2. `_setz()` führt `meldung` und `naechsterVersuch` bewusst NICHT fort,
///     und der Takt rief es ohne beide. Scheiterte die Anmeldung während eines
///     Gesprächs, waren Grund und geplanter Anlauf nach höchstens einer
///     Sekunde gelöscht — die Kopfleiste sprang von Bernstein („arbeitet
///     daran") auf Rot („hier hilft nur ein Mensch"), obwohl die Wiederholung
///     lief.
///
/// Das Risiko der Umstellung ist, dass die Uhr stehen bleibt und es niemandem
/// auffällt. Genau davor sind diese Tests.
///
/// ⚠️ Geprüft wird, dass der **Builder erneut aufgerufen** wird — nicht eine
/// ausgerechnete Uhrzeit. `pump(Duration)` dreht die Uhr der Timer weiter,
/// `DateTime.now()` aber nicht; ein Test auf „00:01" würde immer scheitern und
/// über den Takt gar nichts aussagen. Das erneute Bauen IST der Vertrag dieses
/// Widgets, die Zahl rechnet `dauerSekunden` selbst.
void main() {
  late int aufrufe;

  Widget bauen({required bool aktiv}) {
    return MaterialApp(
      home: Scaffold(
        body: SekundenTakt(
          aktiv: aktiv,
          bauen: (_) {
            aufrufe++;
            return Text('$aufrufe');
          },
        ),
      ),
    );
  }

  setUp(() => aufrufe = 0);

  testWidgets('der Inhalt wird jede Sekunde neu gebaut', (t) async {
    await t.pumpWidget(bauen(aktiv: true));
    expect(aufrufe, 1);

    await t.pump(const Duration(seconds: 1));
    expect(aufrufe, 2, reason: 'sonst steht die Uhr, und es fällt spät auf');

    await t.pump(const Duration(seconds: 1));
    expect(aufrufe, 3);

    // ⚠️ Ein einziges `pump(5s)` dreht die Uhr um fünf Sekunden, erzeugt aber
    // nur EINEN Frame — die fünf `setState` fallen darin zusammen. Das ist
    // kein Mangel, sondern die Obergrenze: der Takt kann nie mehr als einen
    // Aufbau je Frame verursachen, egal wie oft er feuert.
    await t.pump(const Duration(seconds: 5));
    expect(aufrufe, 4);

    // Fünf einzelne Sekunden sind dagegen fünf Aufbauten.
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(seconds: 1));
    }
    expect(aufrufe, 9);
  });

  testWidgets('ohne aktiv wird kein Takt gestellt', (t) async {
    // Beim Klingeln und beim Wählen steht dort ein fester Satz — ein Timer
    // dafür wäre Arbeit für nichts.
    await t.pumpWidget(bauen(aktiv: false));
    expect(aufrufe, 1);
    await t.pump(const Duration(seconds: 5));
    expect(aufrufe, 1);
  });

  testWidgets('der Takt springt an, wenn aus klingelt verbunden wird', (t) async {
    await t.pumpWidget(bauen(aktiv: false));
    await t.pump(const Duration(seconds: 3));
    expect(aufrufe, 1);

    // Dasselbe Widget, nur aktiv — der Übergang klingelt -> verbunden.
    await t.pumpWidget(bauen(aktiv: true));
    final nachWechsel = aufrufe;
    await t.pump(const Duration(seconds: 1));
    expect(aufrufe, nachWechsel + 1,
        reason: 'didUpdateWidget muss den Takt nachträglich stellen');
  });

  testWidgets('und hört wieder auf, wenn das Gespräch endet', (t) async {
    await t.pumpWidget(bauen(aktiv: true));
    await t.pump(const Duration(seconds: 1));
    final gelaufen = aufrufe;

    await t.pumpWidget(bauen(aktiv: false));
    await t.pump(const Duration(seconds: 5));
    expect(aufrufe, gelaufen + 1,
        reason: 'nur der eine Aufbau durch den Wechsel, danach Ruhe');
  });

  testWidgets('nach dem Entfernen läuft kein Timer weiter', (t) async {
    await t.pumpWidget(bauen(aktiv: true));
    await t.pump(const Duration(seconds: 1));
    // Ein nicht abbestellter Timer lässt den Test hier scheitern
    // („A Timer is still pending") — genau das soll er.
    await t.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await t.pump(const Duration(seconds: 3));
  });
}
