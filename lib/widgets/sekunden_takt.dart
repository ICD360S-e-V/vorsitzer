import 'dart:async';

import 'package:flutter/widgets.dart';

/// Baut seinen Inhalt jede Sekunde neu — und **nur** ihn.
///
/// ⚠️ WOFÜR DAS DA IST, UND WAS ES ERSETZT
/// Die Gesprächsdauer rechnet [SipgateGespraech.dauerSekunden] selbst aus
/// `verbundenSeit`; damit sie weiterläuft, muss lediglich jemand neu bauen.
/// Bis zum 25.08.2026 tat das der Dienst: ein `Timer.periodic` schob jede
/// Sekunde einen **kompletten neuen Zustand** in `SipgateService.zustand`.
///
/// Das hatte zwei Folgen, und die zweite war ein echter Fehler:
///
///  1. Jeder, der am Zustand hing, wurde im Sekundentakt neu gebaut — auch die
///     Kopfleiste des Dashboards, die von der Dauer kein Wort zeigt.
///
///  2. `_setz()` führt `meldung` und `naechsterVersuch` bewusst **nicht** fort
///     (ein durchgereichter Zeitpunkt würde ewig „nächster Versuch"
///     behaupten). Der Takt rief `_setz()` ohne beide — also wurden sie jede
///     Sekunde gelöscht. Scheiterte die Anmeldung **während eines Gesprächs**,
///     stand nach höchstens einer Sekunde ein rotes Symbol da, das „hier tut
///     niemand mehr etwas" heißt, obwohl die Wiederholung lief. Genau die
///     Unterscheidung, für die Bernstein und Rot eingeführt wurden.
///
/// Hier tickt deshalb der Ort, der die Zahl zeigt, und sonst niemand. Das ist
/// auch die Form, die Flutter dafür vorsieht: der Builder umschließt nur das
/// Widget, das sich ändert, nicht den Bildschirm darum herum.
///
/// ⚠️ [bauen] muss die Zahl **im Builder** ausrechnen. Wer außerhalb einen
/// String baut und ihn hereinreicht, bekommt jede Sekunde denselben.
class SekundenTakt extends StatefulWidget {
  const SekundenTakt({super.key, required this.aktiv, required this.bauen});

  /// Läuft überhaupt etwas? Bei `false` wird kein Timer angelegt — ein
  /// klingelnder Anruf zeigt „Eingehender Anruf", da ändert sich nichts.
  final bool aktiv;

  final WidgetBuilder bauen;

  @override
  State<SekundenTakt> createState() => _SekundenTaktState();
}

class _SekundenTaktState extends State<SekundenTakt> {
  Timer? _takt;

  @override
  void initState() {
    super.initState();
    _stellen();
  }

  @override
  void didUpdateWidget(SekundenTakt alt) {
    super.didUpdateWidget(alt);
    // Der Zustand kann von „klingelt" nach „verbunden" wechseln, während das
    // Widget stehen bleibt — dann muss der Takt anspringen.
    if (alt.aktiv != widget.aktiv) _stellen();
  }

  void _stellen() {
    _takt?.cancel();
    _takt = null;
    if (!widget.aktiv) return;
    _takt = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    // Ohne das liefe der Takt weiter, nachdem die Karte weg ist — und er
    // hielte über den Verschluss den ganzen Baum am Leben.
    _takt?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.bauen(context);
}
