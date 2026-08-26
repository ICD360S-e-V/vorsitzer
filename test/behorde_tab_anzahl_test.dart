import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Haelt die drei Listen des Behoerden-Reiters auf gleicher Laenge.
///
/// ⚠️ Anlass ist ein echter Fehler: Commit 30587366e vom 03.07.2026 brachte
/// mit „Deutsche Bahn" den 26. Reiter, liess aber
/// `DefaultTabController(length: 25)` stehen. Damit war der letzte Reiter
/// nicht erreichbar - fast zwei Monate lang, ohne dass etwas rot wurde:
/// `flutter analyze` sieht solche Zahlen nicht, und die Tests fassten die
/// Datei nicht an.
void main() {
  final datei = File('lib/widgets/behorde_tab_content.dart');
  final quelle = datei.readAsStringSync();

  List<String> tabDefs() {
    final i = quelle.indexOf('_tabDefs');
    final seg = quelle.substring(i, quelle.indexOf('\n  ];', i));
    return RegExp(r"\{'type': '([a-z_]+)'")
        .allMatches(seg).map((m) => m.group(1)!).toList();
  }

  List<String> allTypes() {
    final m = RegExp(r'static const List<String> _allTypes = \[(.*?)\];', dotAll: true)
        .firstMatch(quelle)!;
    return RegExp(r"'([a-z_]+)'").allMatches(m.group(1)!).map((x) => x.group(1)!).toList();
  }

  /// Zaehlt die Kinder von TabBarView ueber Klammertiefe - eine reine
  /// Zeilenzaehlung wuerde an den mehrzeiligen Aufrufen scheitern.
  int tabBarViewKinder() {
    final i = quelle.indexOf('child: TabBarView(');
    var k = quelle.indexOf('children: [', i) + 'children: ['.length;
    final start0 = k;
    var tiefe = 0, anzahl = 0, letzterStart = k;
    while (k < quelle.length) {
      final c = quelle[k];
      if (c == '(' || c == '[' || c == '{') {
        tiefe++;
      } else if (c == ')' || c == '}') {
        tiefe--;
      } else if (c == ']') {
        if (tiefe == 0) break;
        tiefe--;
      } else if (c == ',' && tiefe == 0) {
        anzahl++;
        letzterStart = k + 1;
      }
      k++;
    }
    final rest = quelle.substring(letzterStart, k).trim();
    if (rest.isNotEmpty) anzahl++;
    expect(k, greaterThan(start0), reason: 'TabBarView nicht gefunden');
    return anzahl;
  }

  test('Reiter, Typen und Inhalte sind gleich viele', () {
    final defs = tabDefs();
    expect(defs.length, allTypes().length,
        reason: '_tabDefs und _allTypes unterschiedlich lang');
    expect(defs.length, tabBarViewKinder(),
        reason: 'Zu jedem Reiter muss genau ein TabBarView-Kind gehoeren');
  });

  test('die Laenge des TabControllers ist abgeleitet, nicht festgeschrieben', () {
    // Genau das war der Fehler vom 03.07.2026. Eine feste Zahl darf hier
    // nicht wieder auftauchen.
    expect(quelle.contains('length: _tabDefs.length'), isTrue,
        reason: 'DefaultTabController muss seine Laenge aus _tabDefs nehmen');
    expect(RegExp(r'DefaultTabController\(\s*(?://[^\n]*\n\s*)*length: \d+')
        .hasMatch(quelle), isFalse,
        reason: 'Feste Reiterzahl gefunden - sie laeuft der Liste davon');
  });

  test('Bussgeldstelle steht neben der Polizei', () {
    final defs = tabDefs();
    expect(defs.contains('bussgeldstelle'), isTrue);
    expect(defs.indexOf('bussgeldstelle'), defs.indexOf('polizei') + 1,
        reason: 'Die Bussgeldstelle wird neben der Polizei gesucht');
    expect(allTypes().contains('bussgeldstelle'), isTrue,
        reason: 'ohne Eintrag in _allTypes bleibt der Reiter aus der '
                'Tab-Verwaltung und der Vollstaendigkeitsrechnung heraus');
  });
}
