import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/preis_leser_service.dart';

/// ⚠️ DIESE PRÜFUNGEN LESEN DEN QUELLTEXT, UND DAS IST ABSICHT.
/// Alles hier hängt an einem echten Chromium und einer echten Produktseite —
/// ein Einheitentest müsste beides nachbilden und prüfte am Ende dieselbe
/// Eigenschaft, die im Quelltext direkt dasteht. Derselbe Aufbau wie
/// `sipgate_lebenszeichen_test.dart` und `proguard_jna_test.dart`.
///
/// Jede Zusicherung ist gegengeprobt: nimmt man die Stelle im Quelltext
/// zurück, wird genau diese Prüfung rot.
void main() {
  // ⚠️ Kein `expect` hier: die Datei wird ausserhalb eines Tests gelesen, und
  // dort wirft der Matcher eine OutsideTestException statt zu scheitern.
  String quelle(String pfad) {
    final f = File(pfad);
    if (!f.existsSync()) throw StateError('Datei fehlt: $pfad');
    // Zeilenkommentare weg, bevor gesucht wird — sonst bestätigt die Prüfung
    // eine auskommentierte, also tote Zeile.
    return f
        .readAsStringSync()
        .split('\n')
        .map((z) => z.trimLeft().startsWith('//') ? '' : z)
        .join('\n');
  }

  final leser = quelle('lib/services/preis_leser_service.dart');

  group('Browser-Aufruf', () {
    // ⚠️ Hier wird eine FREMDE Seite gerendert. Der Sandkasten ist genau
    // dafür da; --no-sandbox nähme ihn weg, und zwar unbemerkt, weil die
    // Preise trotzdem ankämen.
    test('kein --no-sandbox', () {
      expect(leser.contains('--no-sandbox'), isFalse,
          reason: 'Fremde Seiten werden gerendert — der Sandkasten bleibt an.');
    });

    // ⚠️ Ohne das steht bei dm gar nichts auf der Seite: der Preis wird per
    // JavaScript nachgeholt.
    test('wartet auf nachgeladene Inhalte', () {
      expect(leser.contains('--virtual-time-budget='), isTrue);
      expect(leser.contains('--dump-dom'), isTrue);
    });

    // ⚠️ Ein wiederverwendetes Profil hat den Plattencache. Ab der zweiten
    // Runde käme der Preis von gestern zurück — als „unverändert", ohne dass
    // irgendetwas fehlschlägt.
    test('frisches Profil je Seite, und es wird wieder entfernt', () {
      expect(leser.contains('createTemp'), isTrue);
      expect(leser.contains('profil.delete'), isTrue);
      expect(leser.contains('--user-data-dir='), isTrue);
    });

    test('eine hängende Seite blockiert den Lauf nicht', () {
      expect(leser.contains('.timeout(_seiteTimeout)'), isTrue);
    });
  });

  group('Ein Fehlschlag darf nicht wie Erfolg aussehen', () {
    // Der wichtigste Punkt der ganzen Funktion: wer nichts meldet, ist von
    // „Preis unverändert" nicht zu unterscheiden.
    test('nicht lesbare Seite wird als Fehler gemeldet', () {
      expect(leser.contains("'fehler':"), isTrue,
          reason: 'Ein Fehlschlag muss berichtet werden, nicht verschwiegen.');
    });

    test('der Grund steht im Bericht, nicht nur „ging nicht"', () {
      expect(leser.contains('Kein Preis auf der Seite gefunden'), isTrue);
      expect(leser.contains('Bot-Abfrage'), isTrue);
    });

    test('auch eine geworfene Ausnahme wird berichtet', () {
      // Der catch-Zweig je Produkt darf nicht leer sein.
      expect(RegExp(r'\}\s*catch\s*\(e\)\s*\{\s*await api\.preiseAction')
          .hasMatch(leser), isTrue);
    });

    // ⚠️ Sonst verbraucht ein Start ohne Netz den Tag, und der Wächter meldet
    // abends zu Recht Schweigen — verursacht von uns.
    test('ein misslungener Lauf verbraucht den Tag nicht', () {
      expect(leser.contains('if (n >= 0) await prefs.setString'), isTrue);
    });
  });

  group('Nur wo ein Browser steht', () {
    test('ausserhalb von Linux gibt es keinen Pfad', () {
      // Auf dem Prüfstand (Linux) kann ein Chromium vorhanden sein — die
      // Aussage ist deshalb an die Plattformbedingung geknüpft.
      if (!Platform.isLinux) {
        expect(PreisLeserService.chromiumPfad(), isNull);
        expect(PreisLeserService.verfuegbar, isFalse);
      }
      expect(leser.contains('if (!Platform.isLinux) return null;'), isTrue);
    });

    // ⚠️ Ein einfacher Abruf als Rückfall käme bei zwei von drei Märkten mit
    // einer Seite ohne Preis zurück — das sähe wie ein defektes Produkt aus
    // statt wie ein fehlendes Werkzeug.
    test('kein stiller Rückfall auf einen einfachen Abruf', () {
      expect(leser.contains('http.get'), isFalse);
      expect(leser.contains('HttpClient()'), isFalse);
    });
  });
}
