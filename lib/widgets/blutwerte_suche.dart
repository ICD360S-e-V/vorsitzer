import 'package:flutter/material.dart';
import '../utils/app_farben.dart';

/// Suchfeld und Filter für die Blutwerte-Eingabe.
///
/// ⚠️ Erst mit 170 Feldern ist das kein Komfort mehr, sondern die Bedingung
/// dafür, dass die Maske überhaupt benutzbar bleibt. Bei 36 Einträgen scrollt
/// man; bei 170 sucht man.
///
/// Liegt hier und nicht in den sechs Ärzte-Dialogen, aus demselben Grund wie
/// die Parameterliste selbst: eine Regel, die man sechsmal pflegen muss,
/// driftet.

/// Vergleichsform: klein, ohne Umlautpunkte, ohne Zierzeichen.
///
/// ⚠️ Umlaute werden hier ZU DEM GRUNDBUCHSTABEN, nicht zu „ae". Wer schnell
/// tippt, schreibt „folsaure" — nicht „folsaeure". Genau das war der erste
/// Fehlversuch: die Suche wandelte beide Seiten nach „ae" um, und die
/// häufigste Schreibweise fand nichts.
String blutSuchform(String s) {
  var t = s.toLowerCase();
  const ersatz = {
    'ä': 'a', 'ö': 'o', 'ü': 'u', 'ß': 'ss',
    'é': 'e', 'è': 'e', 'á': 'a', 'à': 'a', 'í': 'i', 'ó': 'o', 'ú': 'u',
  };
  ersatz.forEach((a, b) => t = t.replaceAll(a, b));
  return t.replaceAll(RegExp(r'[^a-z0-9]'), '');
}

/// Dieselbe Form, aber mit der amtlichen Umschreibung („ä" → „ae").
///
/// ⚠️ Beide Formen stehen im durchsuchten Text, weil beide Schreibweisen
/// vorkommen: auf dem Befund steht „Folsäure", getippt wird „folsaure", und
/// wer die Umschreibung gelernt hat, tippt „folsaeure".
String blutSuchformAe(String s) {
  var t = s.toLowerCase();
  const ersatz = {'ä': 'ae', 'ö': 'oe', 'ü': 'ue', 'ß': 'ss'};
  ersatz.forEach((a, b) => t = t.replaceAll(a, b));
  return t.replaceAll(RegExp(r'[^a-z0-9]'), '');
}

/// Die Parameter, die zu [suche] passen — bei leerer Suche alle.
///
/// ⚠️ Jedes Wort der Eingabe muss vorkommen, nicht die ganze Zeichenkette:
/// „vitamin d" soll „Vitamin D3 (25-OH)" finden, obwohl dort etwas dazwischen
/// steht. Ohne das müsste man raten, wie der Parameter genau heißt — also
/// genau das, was das Suchfeld ersparen soll.
List<Map<String, dynamic>> blutParameterFiltern(
    List<Map<String, dynamic>> alle, String suche) {
  final worte = suche
      .split(RegExp(r'\s+'))
      .map(blutSuchform)
      .where((w) => w.isNotEmpty)
      .toList();
  if (worte.isEmpty) return alle;
  return alle.where((p) {
    final roh =
        '${p['such'] ?? ''} ${p['label'] ?? ''} ${p['key'] ?? ''} ${p['unit'] ?? ''}';
    final heu = '${blutSuchform(roh)} ${blutSuchformAe(roh)}';
    return worte.every(heu.contains);
  }).toList();
}

/// Das Suchfeld über der Parameterliste.
class BlutwerteSuchfeld extends StatelessWidget {
  const BlutwerteSuchfeld({
    super.key,
    required this.controller,
    required this.suche,
    required this.onSuche,
    required this.treffer,
    required this.gesamt,
    required this.ausgefuellt,
  });

  /// ⚠️ Der Controller lebt im Dialog, nicht hier. Würde er bei jedem Aufbau
  /// neu erzeugt, spränge der Cursor bei jedem Tastendruck ans Ende — beim
  /// Korrigieren eines Tippfehlers mitten im Wort merkt man das sofort.
  final TextEditingController controller;
  final String suche;
  final ValueChanged<String> onSuche;

  /// Wie viele Parameter die Suche gerade übrig lässt.
  final int treffer;
  final int gesamt;

  /// Wie viele davon schon einen Wert tragen — die Zahl, die man beim
  /// Abtippen eines Befunds wirklich sehen will.
  final int ausgefuellt;

  @override
  Widget build(BuildContext context) {
    final gefiltert = suche.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('blutwerte-suche'),
            controller: controller,
            onChanged: onSuche,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18, color: F.h(Colors.grey, 600)),
              prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              hintText: 'Analyse suchen — z. B. TSH, Ferritin, Vitamin D',
              hintStyle: TextStyle(fontSize: 12, color: F.h(Colors.grey, 500)),
              suffixIcon: gefiltert
                  ? IconButton(
                      icon: Icon(Icons.close, size: 16, color: F.h(Colors.grey, 600)),
                      tooltip: 'Suche zurücksetzen',
                      onPressed: () {
                        controller.clear();
                        onSuche('');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 2),
            child: Text(
              gefiltert
                  ? (treffer == 0
                      ? 'Kein Feld passt zu „$suche" — die Bezeichnung des Labors kann abweichen.'
                      : '$treffer von $gesamt Feldern · $ausgefuellt ausgefüllt')
                  : '$gesamt Felder · $ausgefuellt ausgefüllt',
              style: TextStyle(
                  fontSize: 10,
                  color: gefiltert && treffer == 0
                      ? F.h(Colors.orange, 800)
                      : F.textSchwach),
            ),
          ),
        ],
      ),
    );
  }
}
