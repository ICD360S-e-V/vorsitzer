import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/screens/blitz_fenster_app.dart';

/// Hält fest, was das Blitz-Fenster unter Linux überhaupt sichtbar macht.
///
/// Vorgeschichte in zwei Stufen, beide gemessen:
///   * 6.183.0 — Fenster 380×243, ALLE 92.340 Pixel `#000000`. Seit Flutter
///     3.47 (#541) ist Impeller unter Linux die Voreinstellung; das zweite
///     Fenster von desktop_multi_window zeichnet damit nur seine unterste
///     Ebene.
///   * 6.183.5 — der erste Anlauf (#557) schaltete Impeller über
///     `FLUTTER_ENGINE_SWITCHES` ab. Im Debug-Bau half das, im ausgelieferten
///     Programm NICHT: der Einbetter liest die Umgebung nur ausserhalb von
///     Release (`#ifndef FLUTTER_RELEASE`). Nachgezählt in den beiden
///     Engine-Bibliotheken: debug 1×, release 0×.
///
/// ⚠️ Alles hier wird am Quelltext geprüft, und das ist kein Notbehelf: der
/// Runner ist C++, `flutter analyze` fasst ihn nicht an, `flutter test` baut
/// ihn nicht, und `pr-checks.yml` baut kein Linux-Paket. Ohne diese Prüfungen
/// gibt es weder Fehler noch Meldung — nur ein leeres Rechteck mitten auf dem
/// Bildschirm des Vorsitzenden.
void main() {
  String lies(String pfad) {
    final datei = File(pfad);
    expect(datei.existsSync(), isTrue, reason: '$pfad fehlt');
    return datei.readAsStringSync();
  }

  /// Nur der Code, ohne `//`-Zeilen.
  ///
  /// ⚠️ Nötig, weil der Runner die verworfene Umgebungs-Lösung ausdrücklich
  /// ERKLÄRT — diese Begründung ist das Wertvollste an der Datei und darf
  /// nicht daran scheitern, dass ein Test nach der Zeichenfolge sucht.
  String nurCode(String quelle) => quelle
      .split('\n')
      .where((z) => !z.trimLeft().startsWith('//'))
      .join('\n');

  group('Blitz-Fenster bleibt sichtbar', () {
    test('Impeller wird über die FlDartProject-Fabrik abgeschaltet', () {
      final quelle = lies('linux/runner/main.cc');

      // Die Fabrik selbst wird überlagert — nur so erwischt es auch das
      // Projekt, das desktop_multi_window INTERN für das Blitz-Fenster anlegt.
      expect(quelle, contains('fl_dart_project_new'),
          reason: 'ohne Überlagerung erreicht der Schalter nur das Hauptfenster');
      expect(quelle, contains('dlsym(RTLD_NEXT'),
          reason: 'die echte Fabrik muss dahinter noch gerufen werden');
      expect(quelle, contains('fl_dart_project_set_enable_impeller'));
      expect(quelle, contains('FALSE'));
    });

    test('NICHT wieder über die Umgebung — das ist im Release wirkungslos', () {
      final quelle = nurCode(lies('linux/runner/main.cc'));
      expect(quelle.contains('FLUTTER_ENGINE_SWITCHES'), isFalse,
          reason: 'der Einbetter liest die Umgebung nur ausserhalb von '
              'Release; im ausgelieferten Programm passiert damit nichts');
    });

    test('das Programm exportiert seine Symbole', () {
      final quelle = lies('linux/runner/CMakeLists.txt');
      // Ohne ENABLE_EXPORTS steht `fl_dart_project_new` nicht in der
      // dynamischen Symboltabelle des Programms, das Plugin bindet direkt an
      // die Engine, und die Überlagerung greift ins Leere.
      expect(quelle, contains('ENABLE_EXPORTS ON'));
    });

    test('das Blitz-Fenster ist nicht durchsichtig', () {
      final quelle = lies('lib/screens/blitz_fenster_app.dart');
      // Unter Linux hat das Fenster keinen RGBA-Visual; der Hintergrund einer
      // FlView ist laut fl_view.h „defaults to black". Durchsichtig heisst
      // dort also schwarz.
      expect(quelle.contains('backgroundColor: Colors.transparent'), isFalse,
          reason: 'durchsichtig heisst unter Linux schwarz');
      expect(quelle, contains('backgroundColor: F.flaeche'));
    });
  });

  test('die Kartenhöhe bleibt zwischen den Grenzen des Fensters', () {
    expect(kBlitzMinHoehe, lessThan(kBlitzMaxHoehe));
    expect(kBlitzStartHoehe, greaterThanOrEqualTo(kBlitzMinHoehe));
    expect(kBlitzStartHoehe, lessThanOrEqualTo(kBlitzMaxHoehe));
    expect(kBlitzFensterGroesse, const Size(kBlitzBreite, kBlitzStartHoehe));
  });
}
