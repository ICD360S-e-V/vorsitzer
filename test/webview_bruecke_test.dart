import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/webview_bruecke.dart';

/// Die JavaScript-Brücken der WebView — `FlutterFilePicker` öffnet den
/// Dateiauswähler des Geräts, `RdpBridge` steuert die Sitzung — waren für jede
/// Seite offen, die in der WebView lief. Und dort laufen fremde Seiten:
/// YouTube-Kanäle, Arzt- und Versicherungsportale aus der Datenbank, das
/// ODR-Portal der EU.
void main() {
  const portal = 'https://www.elster.de/eportal/login/softpse';

  group('Erlaubt', () {
    test('dieselbe Herkunft', () {
      expect(brueckeErlaubt(portal, portal), isTrue);
      expect(brueckeErlaubt(portal, 'https://www.elster.de/anderer/pfad'), isTrue,
          reason: 'ein anderer Pfad derselben Seite ist dieselbe Seite');
    });

    test('noch keine Seitenmeldung — der Startwert gilt', () {
      // Sonst schlüge die erste Anfrage fehl, bevor `onPageStarted` gelaufen
      // ist, und der Dateiauswähler ginge beim ersten Versuch nie auf.
      expect(brueckeErlaubt(portal, null), isTrue);
      expect(brueckeErlaubt(portal, ''), isTrue);
      expect(brueckeErlaubt(portal, '   '), isTrue);
    });
  });

  group('Abgewiesen', () {
    test('die Seite ist woanders hingewandert', () {
      expect(brueckeErlaubt(portal, 'https://boesewicht.de/'), isFalse);
      expect(brueckeErlaubt(portal, 'https://elster.de.boesewicht.de/'), isFalse,
          reason: 'ein angehängter Name ist eine andere Seite');
      expect(brueckeErlaubt(portal, 'https://www.elster.de.evil/'), isFalse);
    });

    test('ein Unterdomain zählt nicht als dieselbe Seite', () {
      expect(brueckeErlaubt(portal, 'https://cdn.elster.de/'), isFalse);
    });

    test('Klartext wird nie erlaubt', () {
      expect(brueckeErlaubt('http://portal.de/', 'http://portal.de/'), isFalse);
      expect(brueckeErlaubt(portal, 'http://www.elster.de/'), isFalse);
    });

    test('unbrauchbare Startadresse sperrt zu, nicht auf', () {
      for (final url in [null, '', '   ', 'kein url', 'javascript:alert(1)']) {
        expect(brueckeErlaubt(url, portal), isFalse, reason: 'bei: $url');
        expect(brueckeErlaubt(url, url), isFalse, reason: 'bei: $url');
      }
    });
  });

  group('Die Meldung', () {
    test('nennt die erwartete Seite, statt stumm zu bleiben', () {
      // Ein Dateiauswähler, der sich nicht öffnet, sieht sonst wie ein kaputter
      // Knopf aus — und ein echter Angriff genauso.
      expect(brueckeAbgelehntText(portal), contains('www.elster.de'));
      expect(brueckeAbgelehntText(portal), contains('abgelehnt'));
      expect(brueckeAbgelehntText(null), isNotEmpty);
    });
  });

  group('Die Grenze, ausdrücklich festgehalten', () {
    test('ein fremdes iframe INNERHALB der erlaubten Seite kommt durch', () {
      // ⚠️ Kein Fehler in diesem Test, sondern die bewusste Entscheidung des
      // Users vom 22.08.2026: die Brücke bleibt auf allen Bildschirmen
      // angemeldet, geprüft wird die Herkunft.
      //
      // Android reicht solche Kanäle an JEDEN Rahmen weiter und sagt nicht,
      // wer gerufen hat — für ein Werbe-iframe auf einer erlaubten Seite ist
      // der Hauptrahmen genau der erwartete. Das hier ist also die Zusage, die
      // wir NICHT geben.
      //
      // Wer das schliessen will, meldet die Brücke nur auf den Bildschirmen
      // an, die sie brauchen (zwei von fünfzig).
      const seiteMitFremdemRahmen = 'https://www.youtube.com/@kanal';
      expect(brueckeErlaubt(seiteMitFremdemRahmen, seiteMitFremdemRahmen), isTrue,
          reason: 'der Hauptrahmen stimmt — das iframe darunter sieht man nicht');
    });
  });
}
