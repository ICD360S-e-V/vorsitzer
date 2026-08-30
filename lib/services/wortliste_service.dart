import 'dart:convert' show jsonDecode;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../utils/diakritika.dart';
import '../utils/wort_vervollstaendigung.dart';

/// Lädt die rumänische Wortliste einmal pro Programmlauf und hält den Index.
///
/// ⚠️ DER AUFBAU LÄUFT IN HÄPPCHEN, NICHT AM STÜCK.
/// Es sind einige hunderttausend Wörter; in einer geschlossenen Schleife
/// stünde die Oberfläche eine halbe Sekunde. Dart hat nur einen Faden, also
/// wird nach je [_haeppchen] Zeilen abgegeben. `compute()` scheidet aus: der
/// fertige Index müsste zwischen den Isolaten kopiert werden, und das kostet
/// mehr als der Aufbau selbst.
///
/// ⚠️ Ein Fehlschlag ist kein Fehler, sondern nur „keine Vorschläge".
/// Das Schreibfeld darf niemals daran hängen, ob eine Datei da ist.
class WortlisteService {
  static const _pfad = 'assets/woerterbuch/ro.txt';
  static const _pfadKontext = 'assets/woerterbuch/ro_kontext.json';
  static const _haeppchen = 20000;

  static WortIndex _index = WortIndex.leer;
  static Diakritika _diakritika = Diakritika.leer;
  static Future<void>? _laeuft;

  static WortIndex get index => _index;
  static Diakritika get diakritika => _diakritika;
  static bool get bereit => _index.anzahl > 0;

  /// Mehrfach aufrufbar; der zweite Aufruf hängt sich an den ersten an.
  static Future<void> laden() {
    if (_index.anzahl > 0) return Future.value();
    return _laeuft ??= _laden();
  }

  static Future<void> _laden() async {
    try {
      final roh = await rootBundle.loadString(_pfad);
      final woerter = <String>[];
      var seitAbgabe = 0;
      for (final zeile in const LineSplitter().convert(roh)) {
        final w = zeile.trim();
        if (w.isNotEmpty) woerter.add(w);
        if (++seitAbgabe >= _haeppchen) {
          seitAbgabe = 0;
          await Future<void>.delayed(Duration.zero);
        }
      }
      _index = WortIndex.aufbauen(woerter);

      // Die Kontextregeln sind winzig (44 kB) und werden im selben Zug
      // gelesen. ⚠️ In EIGENEM try: fehlen sie, sollen die Vorschläge
      // trotzdem stehen — nur die Häkchen-Korrektur entfällt dann.
      try {
        final j = jsonDecode(await rootBundle.loadString(_pfadKontext));
        _diakritika = Diakritika.ausJson(j as Map<String, dynamic>);
      } catch (e) {
        debugPrint('📚 Kontextregeln nicht geladen: $e');
      }
      debugPrint('📚 Wortliste: ${_index.anzahl} Wörter, '
          '${_diakritika.kontext.length} Kontextwörter');
    } catch (e) {
      debugPrint('📚 Wortliste nicht geladen: $e');
      _index = WortIndex.leer;
    } finally {
      _laeuft = null;
    }
  }

  @visibleForTesting
  static void setzenFuerTest(WortIndex i, [Diakritika? d]) {
    _index = i;
    if (d != null) _diakritika = d;
  }
}

/// Eigene, winzige Fassung — `dart:convert` mitzuziehen lohnt hier nicht,
/// und `split('\n')` legt bei mehreren Megabyte eine zweite volle Kopie an.
class LineSplitter {
  const LineSplitter();
  Iterable<String> convert(String s) sync* {
    var start = 0;
    for (var i = 0; i < s.length; i++) {
      if (s.codeUnitAt(i) == 0x0A) {
        yield s.substring(start, i);
        start = i + 1;
      }
    }
    if (start < s.length) yield s.substring(start);
  }
}
