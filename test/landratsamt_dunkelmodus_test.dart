import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Fängt genau den Fehler, der ausgeliefert wurde: eine neue Oberfläche mit
/// `Colors.white` als Fläche.
///
/// ⚠️ Warum eine Quelltextprüfung und kein Widget-Test: die Tokens aus `F` sind
/// keine `InheritedWidget`s, sondern statische Getter. Ein Widget-Test, der die
/// gezeichneten Farben misst, bräuchte für jeden Zustand eine eigene Aufnahme —
/// und würde trotzdem nur die Stellen prüfen, die er zufällig zeichnet. Die
/// rohe Farbe steht dagegen sichtbar im Quelltext.
///
/// Der ursprüngliche Defekt: die Trefferkarten im Auswahldialog standen auf
/// `Colors.white`, die Schrift kam aus dem dunklen TextTheme — weiss auf weiss,
/// die Auswahl war im Dunkelmodus unbenutzbar. `flutter analyze` und 4064 Tests
/// waren dabei grün.
void main() {
  group('Landratsamt-Antragswahl im Dunkelmodus', () {
    final datei = File('lib/widgets/landratsamt_art_auswahl.dart');

    test('Quelldatei existiert', () {
      expect(datei.existsSync(), isTrue,
          reason: 'Pfad geändert? Dann diesen Test mitziehen, sonst prüft er nichts.');
    });

    test('keine rohen Flächen- oder Graufarben', () {
      final zeilen = datei.readAsLinesSync();
      final roh = <String>[];
      // `Colors.white` in `Colors.white.withValues(...)` als Schleier über
      // einem Bild ist etwas anderes als eine Fläche — hier kommt beides
      // nicht vor, deshalb die strenge Fassung.
      final muster = RegExp(r'Colors\.\w+\.shade\d+|Colors\.white\b|Colors\.black\b');
      for (var i = 0; i < zeilen.length; i++) {
        final z = zeilen[i];
        if (z.trimLeft().startsWith('//') || z.trimLeft().startsWith('///')) continue;
        // Innerhalb von F.h(...) ist `Colors.grey` das Argument und richtig so.
        final ohneToken = z.replaceAll(RegExp(r'F\.h\([^)]*\)'), '');
        for (final t in muster.allMatches(ohneToken)) {
          roh.add('Zeile ${i + 1}: ${t.group(0)}  →  ${z.trim()}');
        }
      }
      expect(roh, isEmpty,
          reason: 'Rohe Farben gefunden. Fläche → F.flaeche, Grautöne und blasse '
              'Tönungen → F.h(<Farbe>, <Stufe>). Links steht immer die '
              'ursprüngliche Farbe, damit das helle Bild unverändert bleibt.\n'
              '${roh.join('\n')}');
    });

    test('die Farbtokens werden überhaupt eingebunden', () {
      // Ohne den Import kann die Datei die Tokens nicht benutzen — dann wäre
      // der Test oben nur deshalb grün, weil gar keine Farbe gesetzt wird.
      final quelle = datei.readAsStringSync();
      expect(quelle, contains("import '../utils/app_farben.dart';"));
      expect(quelle, contains('F.flaeche'),
          reason: 'Die Kartenfläche muss über F.flaeche laufen — das war die '
              'Ursache des weiss-auf-weiss-Defekts.');
    });
  });
}
