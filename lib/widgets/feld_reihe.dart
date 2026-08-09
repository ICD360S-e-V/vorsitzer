import 'package:flutter/material.dart';

import 'responsive_layout.dart';

/// Mehrere Eingabefelder nebeneinander — auf dem Telefon untereinander.
///
/// Drei bis fünf gleich breite Spalten sind auf einem Formular am Rechner
/// selbstverständlich. Auf 448 dp bleiben davon 139, 104 oder 83 dp pro
/// Feld übrig. Nichts davon läuft über — `Expanded` teilt brav auf —, aber
/// in ein 83-dp-Feld lässt sich kein Datum und kein Betrag mehr eintippen,
/// und die Beschriftung darüber ist nach zwei Silben abgeschnitten.
///
/// ⚠️ Genau darum findet kein Überlauf-Test diese Stellen: technisch ist
/// alles in Ordnung, benutzbar ist es nicht. Deshalb ein eigenes Widget
/// statt einer Reparatur an 32 Einzelstellen.
///
/// Die Felder werden **ohne** `Expanded` übergeben. Das Widget entscheidet:
/// nebeneinander bekommt jedes ein `Expanded`, untereinander keines — in
/// einer `Column` mit natürlicher Höhe wäre ein Flex-Kind ein Fehler.
class FeldReihe extends StatelessWidget {
  final List<Widget> felder;

  /// Abstand zwischen den Feldern — waagerecht wie senkrecht.
  final double abstand;

  const FeldReihe({super.key, required this.felder, this.abstand = 12});

  @override
  Widget build(BuildContext context) {
    if (felder.isEmpty) return const SizedBox.shrink();

    if (ResponsiveLayout.istTelefon(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < felder.length; i++) ...[
            if (i > 0) SizedBox(height: abstand),
            felder[i],
          ],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < felder.length; i++) ...[
          if (i > 0) SizedBox(width: abstand),
          Expanded(child: felder[i]),
        ],
      ],
    );
  }
}
