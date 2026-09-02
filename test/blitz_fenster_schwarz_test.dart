import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/screens/blitz_fenster_app.dart';

/// Hält die beiden Dinge fest, ohne die das Blitz-Fenster unter Linux ein
/// schwarzes Rechteck ist (gemessen am 02.09.2026 an Fassung 6.183.0: alle
/// 92.340 Pixel `#000000`).
///
/// ⚠️ Beides ist am Quelltext geprüft und nicht am Verhalten — und das ist
/// hier kein Notbehelf, sondern die einzige Stelle, an der es überhaupt
/// auffallen kann:
///   * Der Impeller-Schalter steht in C++ und wirkt erst in einem gebauten
///     Linux-Paket. `flutter analyze` fasst den Runner nicht an, `flutter
///     test` baut ihn nicht, und `pr-checks.yml` baut kein Linux-Paket.
///   * Die Fensterfarbe lässt sich in einem Widget-Test zwar setzen, aber ihre
///     Wirkung — was eine `FlView` malt, wo Flutter nichts malt — gibt es in
///     der Testumgebung nicht.
/// Ohne diese Prüfungen gibt es weder Fehler noch Meldung: nur ein schwarzes
/// Rechteck mitten auf dem Bildschirm des Vorsitzenden.
void main() {
  String lies(String pfad) {
    final datei = File(pfad);
    expect(datei.existsSync(), isTrue, reason: '$pfad fehlt');
    return datei.readAsStringSync();
  }

  group('Blitz-Fenster bleibt sichtbar', () {
    test('der Linux-Runner schaltet Impeller ab', () {
      final quelle = lies('linux/runner/main.cc');

      // Über die Umgebung, weil das zweite Fenster sein FlDartProject
      // innerhalb von desktop_multi_window bekommt — `fl_dart_project_*`
      // erreichte nur das Hauptfenster.
      expect(quelle, contains('FLUTTER_ENGINE_SWITCHES'),
          reason: 'ohne den Schalter zeichnet das Blitz-Fenster nur seine '
              'unterste Ebene');
      expect(quelle, contains('enable-impeller=false'));

      // Der Aufruf muss auch wirklich stattfinden, nicht nur dastehen.
      final rumpf = quelle.substring(quelle.indexOf('int main('));
      expect(rumpf, contains('impeller_abschalten();'),
          reason: 'die Funktion steht da, wird aber in main() nicht gerufen');
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
    // Belegt nebenbei, dass die Deckel zueinander passen — ein Fenster, das
    // höher wäre als die Karte, zeigte unten wieder den Hintergrund.
    expect(kBlitzMinHoehe, lessThan(kBlitzMaxHoehe));
    expect(kBlitzStartHoehe, greaterThanOrEqualTo(kBlitzMinHoehe));
    expect(kBlitzStartHoehe, lessThanOrEqualTo(kBlitzMaxHoehe));
    expect(kBlitzFensterGroesse, const Size(kBlitzBreite, kBlitzStartHoehe));
  });
}
