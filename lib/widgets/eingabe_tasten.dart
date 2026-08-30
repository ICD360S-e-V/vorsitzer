import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Macht die Eingabetaste zum Absenden — auf JEDER Plattform und über JEDEN
/// Weg, den es dafür gibt.
///
/// ⚠️ WARUM DAS NICHT `onSubmitted` ALLEIN KANN.
/// `onSubmitted` hängt an der Bauart des Feldes: bei einem einzeiligen Feld
/// löst die Eingabetaste es aus, bei einem mehrzeiligen NIE — dort fügt sie
/// eine Zeile ein. Ein Feld, das später einmal mehrzeilig wird, verlöre das
/// Senden per Tastatur lautlos.
///
/// ⚠️ UND WARUM NICHT DER TASTENHAKEN ALLEIN.
/// Der Senden-Knopf der Bildschirmtastatur auf dem Telefon erzeugt gar keinen
/// Tastendruck, sondern eine Eingabe-Aktion — die sieht nur `onSubmitted`.
/// Eine frühere Fassung schaltete den Tastenhaken deshalb auf Android ganz ab;
/// damit hing die Eingabetaste einer angeschlossenen Tastatur wieder allein am
/// Standardverhalten des Feldes.
///
/// ⚠️ DIESE TASTE SENDET, IMMER. Die Wortvervollständigung nimmt bewusst die
/// Leertaste — siehe [WortVorschlaege]. Wer der Eingabetaste hier eine zweite
/// Bedeutung gibt, sorgt dafür, dass irgendwann eine halbe Nachricht rausgeht.
///
/// Also BEIDE Wege, und dagegen eine Sperre: [senden] lässt einen zweiten
/// Aufruf innerhalb von [_sperre] fallen. Sonst ginge dieselbe Nachricht bei
/// einem Tastendruck zweimal raus.
class EingabeTasten extends StatefulWidget {
  final VoidCallback onSend;


  /// Bekommt die abgesicherte Sende-Funktion. Das Feld muss sie in
  /// `onSubmitted` einhängen — dann sind beide Wege gedeckt.
  final Widget Function(VoidCallback senden) bauen;

  const EingabeTasten({super.key, required this.onSend, required this.bauen});

  @override
  State<EingabeTasten> createState() => _EingabeTastenState();
}

class _EingabeTastenState extends State<EingabeTasten> {
  static const _sperre = Duration(milliseconds: 250);
  DateTime? _zuletzt;

  void _senden() {
    final jetzt = DateTime.now();
    final vorher = _zuletzt;
    if (vorher != null && jetzt.difference(vorher) < _sperre) return;
    _zuletzt = jetzt;
    widget.onSend();
  }

  KeyEventResult _taste(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final istEingabe = e.logicalKey == LogicalKeyboardKey.enter ||
        e.logicalKey == LogicalKeyboardKey.numpadEnter;
    // Umschalt+Eingabe bleibt frei — die übliche Geste für „neue Zeile".
    if (!istEingabe || HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    _senden();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      // Nimmt dem Feld nicht den Fokus weg — hängt sich nur in die
      // Tastenkette darüber ein.
      canRequestFocus: false,
      onKeyEvent: _taste,
      child: widget.bauen(_senden),
    );
  }
}
