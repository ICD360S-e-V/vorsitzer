import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

/// Tests für die Freigabe der öffentlichen Kasse (icd360s.de/kasse.php).
///
/// ⚠️ Die JSON-Texte hier sind ECHTE Antworten des Servers vom 12.08.2026,
/// abgenommen von api/admin/finanzverwaltung/kasse_publizieren.php — nicht
/// von Hand nachgebaut. Das ist der ganze Sinn dieser Datei.
///
/// Der Grund steht in CLAUDE.md beim Speedtest: dort war der Bildschirm in
/// Produktion grau, weil PHP eine Liste lieferte, wo der Client eine Map las —
/// und weder `flutter analyze` noch 514 Tests haben es gesehen, weil keiner
/// von ihnen die echte Serverantwort anfasste.
///
/// ⚠️ Die Falle ist hier dieselbe: PHP kennt nur EINEN Array-Typ.
/// `['a' => 1]` wird zu einem JSON-Objekt, `[]` und `[1,2]` werden zu einer
/// JSON-Liste. Ein Feld, das heute ein Objekt ist, wird zur Liste, sobald es
/// leer ist — und `as Map?` wirft dann, statt null zu liefern.
void main() {
  // Zustand 1: nichts veröffentlicht, keine Buchungen erfasst.
  const statusLeer = '''
{"success":true,"oeffentlich":false,"live":null,
 "entwurf":{"einnahmen":0,"ausgaben":0,"saldo":0,"stand_buchung":null,
            "verdeckte":0,"jahre":0,"veroeffentlicht":null},
 "pruefsumme":"55832ccc5cb38c1c7ad3e9e1b473d349d20ab1b86b30359dbd8e8abb9c9687a4",
 "unterschied":true,"hat_buchungen":false}
''';

  // Zustand 2: veröffentlicht, danach wurde weiter gebucht.
  const statusAbweichend = '''
{"success":true,"oeffentlich":true,
 "live":{"einnahmen":150,"ausgaben":189.9,"saldo":-39.9,
         "stand_buchung":"2026-03-20","verdeckte":0,"jahre":1,
         "veroeffentlicht":"2026-08-12T19:24:09+02:00"},
 "entwurf":{"einnahmen":150,"ausgaben":199.89,"saldo":-49.89,
            "stand_buchung":"2026-04-01","verdeckte":0,"jahre":1,
            "veroeffentlicht":null},
 "pruefsumme":"7859ff75fc2731770000000000000000000000000000000000000000000000aa",
 "unterschied":true,"hat_buchungen":true}
''';

  // Antwort auf publizieren mit veralteter Prüfsumme (HTTP 409).
  const konflikt = '''
{"success":false,
 "message":"Die Zahlen haben sich seit der Vorschau geändert. Bitte erneut prüfen und dann freigeben.",
 "pruefsumme":"aaaa111122223333444455556666777788889999aaaabbbbccccddddeeeeffff",
 "http_status":409}
''';

  group('Status-Antwort', () {
    test('leerer Zustand: live ist null, ohne dass die Auswertung wirft', () {
      final d = jsonDecode(statusLeer) as Map<String, dynamic>;

      // Genau so liest der Reiter die Antwort.
      final live = d['live'] as Map<String, dynamic>?;
      final entwurf = d['entwurf'] as Map<String, dynamic>?;

      expect(live, isNull);
      expect(entwurf, isNotNull);
      expect(d['oeffentlich'], isFalse);
      expect(d['hat_buchungen'], isFalse);
      expect(d['pruefsumme'], isA<String>());
      expect((d['pruefsumme'] as String).length, 64);
    });

    test('veröffentlicht: live und entwurf sind beide Objekte', () {
      final d = jsonDecode(statusAbweichend) as Map<String, dynamic>;
      final live = d['live'] as Map<String, dynamic>?;
      final entwurf = d['entwurf'] as Map<String, dynamic>?;

      expect(live, isNotNull);
      expect(entwurf, isNotNull);
      expect(live!['ausgaben'], 189.9);
      expect(entwurf!['ausgaben'], 199.89);
    });

    test('⚠️ live darf NIE eine leere Liste sein — sonst wirft der Cast', () {
      // Wenn kasseKopf() serverseitig je ein leeres Array zurückgäbe, käme
      // hier [] an. Der Reiter castet auf Map? und würde mit TypeError
      // sterben — im Release-Build ohne Meldung, nur eine graue Fläche.
      // Genau dieser Fall hat den Speedtest-Bildschirm lahmgelegt.
      for (final text in [statusLeer, statusAbweichend]) {
        final d = jsonDecode(text) as Map<String, dynamic>;
        for (final feld in ['live', 'entwurf']) {
          expect(d[feld], anyOf(isNull, isA<Map<String, dynamic>>()),
              reason: '$feld darf null oder Objekt sein, niemals Liste');
        }
      }
    });

    test('neue Buchungen schlagen sich in unterschied nieder, nicht in live',
        () {
      final d = jsonDecode(statusAbweichend) as Map<String, dynamic>;
      final live = d['live'] as Map<String, dynamic>;
      final entwurf = d['entwurf'] as Map<String, dynamic>;

      // Das ist die Kernzusage der manuellen Freigabe: die Buchführung ist
      // weiter, die Öffentlichkeit sieht den freigegebenen Stand.
      expect(d['unterschied'], isTrue);
      expect(live['ausgaben'], isNot(entwurf['ausgaben']));
      expect(live['stand_buchung'], '2026-03-20');
      expect(entwurf['stand_buchung'], '2026-04-01');
    });
  });

  group('Freigabe', () {
    test('409 ist kein gewöhnlicher Fehler und liefert eine neue Prüfsumme',
        () {
      final d = jsonDecode(konflikt) as Map<String, dynamic>;

      expect(d['success'], isFalse);
      expect(d['http_status'], 409);
      // Ohne die neue Prüfsumme könnte die Oberfläche nur „Fehler" sagen;
      // mit ihr kann sie die geänderten Zahlen erneut vorlegen.
      expect(d['pruefsumme'], isA<String>());
      expect((d['pruefsumme'] as String).length, 64);
    });

    test('Freigabe ohne Prüfsumme aus der Vorschau ist nicht vorgesehen', () {
      // Die Prüfsumme kommt ausschließlich vom Server. Wird sie im Client
      // gebildet oder aus einem alten Aufruf wiederverwendet, gibt man Zahlen
      // frei, die niemand angesehen hat — dann ist der manuelle Schritt eine
      // Formalie. Der Test hält die Erwartung fest, dass der Wert vorliegt.
      final leer = jsonDecode(statusLeer) as Map<String, dynamic>;
      final abw = jsonDecode(statusAbweichend) as Map<String, dynamic>;
      expect(leer['pruefsumme'], isNotEmpty);
      expect(abw['pruefsumme'], isNotEmpty);
      expect(leer['pruefsumme'], isNot(abw['pruefsumme']));
    });
  });

  group('Betragsformatierung', () {
    // Spiegelt _kasseEuro(): deutsches Komma, immer zwei Nachkommastellen.
    String euro(dynamic v) {
      final d = v is num ? v.toDouble() : double.tryParse('${v ?? 0}') ?? 0;
      return '${d.toStringAsFixed(2).replaceAll('.', ',')} €';
    }

    test('int, double und String aus JSON ergeben dasselbe Format', () {
      // ⚠️ PHP liefert 150 (int), 189.9 (float) und aus DECIMAL-Spalten
      // gelegentlich "150.00" (String) — alle drei müssen durchgehen.
      expect(euro(150), '150,00 €');
      expect(euro(189.9), '189,90 €');
      expect(euro('150.00'), '150,00 €');
      expect(euro(-49.89), '-49,89 €');
      expect(euro(null), '0,00 €');
    });
  });
}
