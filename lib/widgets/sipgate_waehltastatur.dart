import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/app_farben.dart';

/// Die Wähltastatur — ein 3×4-Feld wie auf jedem Telefon.
///
/// ⚠️ Vorher lagen die Zwölf in einem `Wrap`. Das ist kein Schönheitsfehler:
/// ein Wrap bricht nach verfügbarer Breite um, also je nach Fenster nach vier,
/// fünf oder sechs Tasten. Damit steht die 5 mal in der Mitte, mal am Rand —
/// und genau das macht Wählen anstrengend, weil die Hand jedes Mal neu suchen
/// muss, statt einem Muster zu folgen, das sie seit dreissig Jahren kennt.
/// Drei Spalten sind deshalb fest verdrahtet, nicht ausgerechnet.
///
/// Die Buchstaben unter den Ziffern sind kein Zierrat: Ämter und Praxen
/// nennen ihre Nummern manchmal als Wort, und ohne die Zeile muss man raten.
class SipgateWaehltastatur extends StatelessWidget {
  const SipgateWaehltastatur({
    super.key,
    required this.schmal,
    required this.beiTaste,
  });

  /// Telefonbreite — dort sitzen die Tasten enger, aber im selben Muster.
  final bool schmal;

  /// Was mit dem gedrückten Zeichen geschieht, entscheidet der Bildschirm:
  /// im Gespräch ein Tastenton, sonst eine Ziffer im Wählfeld.
  final void Function(String zeichen) beiTaste;

  @override
  Widget build(BuildContext context) {
    // Kein `Wrap`, kein GridView: feste Reihen. Was hier steht, steht auf dem
    // Bildschirm an derselben Stelle — auf dem Telefon wie auf dem Tablet.
    const reihen = [
      [['1', ''], ['2', 'ABC'], ['3', 'DEF']],
      [['4', 'GHI'], ['5', 'JKL'], ['6', 'MNO']],
      [['7', 'PQRS'], ['8', 'TUV'], ['9', 'WXYZ']],
      [['*', ''], ['0', '+'], ['#', '']],
    ];

    return LayoutBuilder(builder: (context, c) {
      final abstand = schmal ? 10.0 : 14.0;
      // ⚠️ Nach oben begrenzt: auf einem breiten Tablet würde die Tastatur sonst
      // über 900 dp auseinandergezogen und man müsste die Hand versetzen, um
      // von der 1 zur 3 zu kommen. Ein Telefonfeld ist eine schmale Spalte.
      final breite = c.maxWidth < 320 ? c.maxWidth : 320.0;
      final seite = ((breite - 2 * abstand) / 3).clamp(52.0, 86.0);

      return Center(
        child: SizedBox(
          width: seite * 3 + abstand * 2,
          child: Column(
            children: [
              for (final reihe in reihen) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final t in reihe)
                      _taste(
                        t[0],
                        t[1],
                        seite,
                        // Die 0 trägt das „+" wie auf jedem Telefon: langes
                        // Drücken. Ein eigener dreizehnter Knopf hat die Reihen
                        // gebrochen und damit das ganze Muster.
                        langdruck: t[0] == '0' ? '+' : null,
                      ),
                  ],
                ),
                if (reihe != reihen.last) SizedBox(height: abstand),
              ],
            ],
          ),
        ),
      );
    });
  }

  Widget _taste(String zeichen, String unten, double seite, {String? langdruck}) {
    void tippen(String was) {
      HapticFeedback.selectionClick();
      beiTaste(was);
    }

    return SizedBox(
      width: seite,
      height: seite,
      child: Material(
        color: F.h(Colors.grey, 100),
        shape: CircleBorder(side: BorderSide(color: F.h(Colors.grey, 300))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => tippen(zeichen),
          onLongPress: langdruck == null
              ? null
              : () {
                  HapticFeedback.mediumImpact();
                  tippen(langdruck);
                },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                zeichen,
                style: TextStyle(
                  fontSize: seite * 0.42,
                  height: 1.0,
                  color: F.h(Colors.grey, 900),
                ),
              ),
              if (unten.isNotEmpty)
                Text(
                  unten,
                  style: TextStyle(
                    // ⚠️ Ein einzelnes Zeichen braucht mehr Punkte als drei.
                    // „ABC" liest sich bei 0,17 gut, das „+" unter der Null war
                    // im gerenderten Bild ein Fleck — und es ist der einzige
                    // Hinweis darauf, dass langes Drücken dort etwas tut.
                    fontSize: seite * (unten.length == 1 ? 0.26 : 0.17),
                    height: unten.length == 1 ? 1.0 : 1.6,
                    letterSpacing: unten.length == 1 ? 0 : 1.2,
                    color: F.h(Colors.grey, 700),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
