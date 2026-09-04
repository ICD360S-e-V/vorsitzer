import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Die Faxnummer eines Vermieters hängt an DREI Stellen zusammen, und zwei
/// davon scheitern lautlos:
///
///   1. `VERMIETER_FELDER` in `api/admin/vermieter_manage.php` (liegt in
///      keinem Repo, deshalb hier nicht prüfbar),
///   2. die Feldliste, mit der ein Eintrag aus der öffentlichen Datenbank in
///      die Akte KOPIERT wird,
///   3. die Feldliste des Bearbeiten-Dialogs.
///
/// Fehlt `fax` in 2., kommt die Nummer beim „Aus Datenbank"-Griff nicht mit —
/// ohne Fehler, ohne leeres Feld: die Zeile fehlt einfach. Fehlt sie in 3.,
/// sendet der Dialog den Schlüssel nicht, und die Zeile bleibt für immer leer.
/// Beides sieht auf dem Schirm aus wie „diese Stelle hat kein Fax".
///
/// Geprüft wird der Quelltext, weil beide Listen `const`-Literale in einem
/// privaten Rückruf sind — ein Widget-Test käme an sie nicht heran, ohne
/// einen echten Server zu befragen.
void main() {
  final quelle = File('lib/widgets/behorde_vermieter.dart').readAsStringSync();

  test('Aus-Datenbank-Übernahme trägt die Faxnummer mit', () {
    final block = _abschnitt(quelle, 'void _ausDatenbank()');
    expect(block, contains("'fax'"),
        reason: 'Ohne fax in der Kopierliste bleibt die Nummer in der '
            'öffentlichen Datenbank liegen.');
  });

  test('Bearbeiten-Dialog kennt das Feld fax', () {
    final block = _abschnitt(quelle, 'void _bearbeiten(');
    expect(block, contains("'fax'"));
    expect(block, contains("c['fax']"),
        reason: 'Ohne Eingabefeld lässt sich eine Faxnummer nie eintragen '
            'oder korrigieren.');
  });

  test('die Faxnummer wird angezeigt, aber nicht als Wählfläche', () {
    expect(quelle, contains("_zeile(Icons.print, 'Fax'"),
        reason: 'Icons.print steht nicht in _phoneIcons — genau deshalb ist '
            'es hier richtig: ein Tipp darf kein Faxgerät anrufen.');
    expect(quelle.contains("_zeile(Icons.phone, 'Fax'"), isFalse);
  });
}

/// Der Rumpf einer Methode, von ihrer Signatur bis zur nächsten auf gleicher
/// Ebene. Ein Vergleich über die ganze Datei würde die beiden Listen
/// verwechseln — und der Test wäre schon grün, wenn nur eine stimmt.
String _abschnitt(String quelle, String signatur) {
  final start = quelle.indexOf(signatur);
  expect(start, isNot(-1), reason: '$signatur nicht gefunden — umbenannt?');
  final rest = quelle.substring(start + signatur.length);
  final ende = rest.indexOf('\n  /// ');
  return rest.substring(0, ende == -1 ? rest.length : ende);
}
