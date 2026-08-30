import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🔴 Kein Wortlaut und kein Name darf ins Protokoll.
///
/// WAS PASSIERT IST, am 30.08.2026 an echten Daten gemessen: sechs Stellen
/// schrieben Absendernamen und den vollen Text von Mitteilungen ins Protokoll
/// — `ntfy_service`, `notification_service` (dreimal), `dashboard_screen`,
/// `admin_chat_dialog`. `LoggerService` lädt die Protokollzeilen zum Server;
/// dort lagen **10.824** solcher Zeilen in `logs/vorsitzer/*.json`, 566 MB, vom
/// 22.07. an — darunter Gesundheitsangaben von Mitgliedern. Und der Pfad war
/// über HTTPS **ohne Anmeldung** abrufbar: ein einzelner GET lieferte 8,2 MB.
///
/// ⚠️ Die nginx-Sperre aus dem Juli griff nach ENDUNG (`.log`, `.sql`, `.bak`),
/// die Dateien heissen aber `.json`. Serverseitig ist das jetzt über den PFAD
/// gesperrt (`location ^~ /logs/`). Diese Datei deckt die andere Hälfte: dass
/// gar nichts erst hineingeschrieben wird.
///
/// ⚠️ OHNE AUSNAHMELISTE, und das ist Absicht. Auch der Titel einer
/// Wetterwarnung steht nicht mehr im Protokoll, obwohl er harmlos ist — eine
/// Regel mit Ausnahmen wird erweitert, eine ohne nicht.
void main() {
  /// Die Argumente aller `_log.…('…')`-Aufrufe.
  final logAufruf = RegExp(
    r"""_log\.(?:info|debug|warning|error)\(\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")""",
  );

  /// ⚠️ `\b(?!\w)` ist der Kern: `$messageId` und `${message.id}` sind KEINE
  /// Inhalte, `$message` ist einer. Ohne diese Grenze hätte der Wächter drei
  /// harmlose Stellen angemahnt — und ein Wächter, der Fehlalarm gibt, wird
  /// abgeschaltet.
  ///
  /// Erlaubt bleibt, was über den Inhalt nur die FORM verrät: `.length`, `.id`,
  /// `.isEmpty`. Genau das ist die richtige Art, so etwas zu protokollieren.
  final wortlaut = RegExp(
    r'\$\{?(title|body|message|senderName|nachricht|betreff|subject|content)'
    r'\b(?!\w)(?!\.(length|id|isEmpty|isNotEmpty))',
  );

  test('kein Log-Aufruf in lib/ trägt Wortlaut oder Namen', () {
    final dateien = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(dateien.length, greaterThan(50), reason: 'zu wenige Dateien — Test blind');

    final befunde = <String>[];
    var aufrufe = 0;
    for (final f in dateien) {
      final q = f.readAsStringSync();
      for (final m in logAufruf.allMatches(q)) {
        aufrufe++;
        final arg = m.group(1) ?? m.group(2) ?? '';
        final t = wortlaut.firstMatch(arg);
        if (t != null) {
          final zeile = '\n'.allMatches(q.substring(0, m.start)).length + 1;
          befunde.add('${f.path}:$zeile  ${t.group(0)}  «$arg»');
        }
      }
    }
    expect(aufrufe, greaterThan(200), reason: 'zu wenige Log-Aufrufe — Test blind');
    expect(befunde, isEmpty,
        reason: 'Wortlaut im Protokoll:\n${befunde.join('\n')}');
  });

  test('die Länge zu protokollieren bleibt erlaubt und wird genutzt', () {
    // ⚠️ Sonst liesse sich der Wächter erfüllen, indem man gar nichts mehr
    // protokolliert — und verlöre die Auskunft „kam die Benachrichtigung an?",
    // um derentwillen die Zeile existiert.
    final q = File('lib/services/notification_service.dart').readAsStringSync();
    expect(q, contains(r'${title.length}'));
    expect(q, contains(r'${body.length}'));
  });
}
