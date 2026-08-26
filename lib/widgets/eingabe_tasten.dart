import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Fängt die Eingabetaste auf dem Rechner ab und schickt damit die Nachricht.
///
/// ⚠️ Warum nicht einfach `onSubmitted`? Weil das an der Bauart des Feldes
/// hängt: bei einem einzeiligen Feld löst die Eingabetaste es aus, bei einem
/// mehrzeiligen NIE — dort fügt sie eine Zeile ein. Ein Feld, das später
/// einmal mehrzeilig wird, verlöre das Senden per Tastatur lautlos. Hier
/// steht es ausdrücklich da und hängt an nichts.
class EingabeTasten extends StatelessWidget {
  final VoidCallback onSend;
  final Widget child;

  const EingabeTasten({super.key, required this.onSend, required this.child});

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid || Platform.isIOS) return child;
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (_, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        final istEingabe = e.logicalKey == LogicalKeyboardKey.enter ||
            e.logicalKey == LogicalKeyboardKey.numpadEnter;
        // Umschalt+Eingabe bleibt frei — wer später ein mehrzeiliges Feld
        // baut, hat damit bereits die übliche Geste für „neue Zeile".
        if (!istEingabe || HardwareKeyboard.instance.isShiftPressed) {
          return KeyEventResult.ignored;
        }
        onSend();
        return KeyEventResult.handled;
      },
      child: child,
    );
  }
}
