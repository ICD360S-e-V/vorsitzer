import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/preis_link.dart';

/// Die Fixtures sind ECHT: am 05.09.2026 mit
/// `chromium --headless --dump-dom` von den drei Produktseiten gezogen und
/// auf die Felder gekürzt, die der Parser anfasst. Erfundene Fixtures würden
/// genau die Eigenheiten verschweigen, an denen dieser Parser scheitern kann.

String seite(String jsonLd) =>
    '<html><head><script type="application/ld+json">$jsonLd</script></head><body></body></html>';

// dm legt ZWEI Product-Karten auf die Seite. Die zweite trägt nur die
// Bewertung und gar kein `offers`.
const dmSeite = '''
<html><head>
<script type="application/ld+json">
{"@context":"https://schema.org","@type":"WebSite","name":"dm-drogerie markt"}
</script>
<script type="application/ld+json">
{"@context": "https://schema.org", "@type": "Product",
 "name": "Deo Roll-on Natural & Refresh, 50 ml",
 "sku": "1625195", "gtin": "4021457638765",
 "brand": {"@type": "Brand", "name": "lavera NATURKOSMETIK"},
 "offers": {"@type": "Offer", "priceCurrency": "EUR", "price": 5.95,
            "availability": "https://schema.org/InStock"}}
</script>
<script type="application/ld+json">
{"@context": "https://schema.org/", "@type": "Product",
 "aggregateRating": {"ratingValue": 4, "bestRating": 5}}
</script>
</head><body></body></html>''';

// Rossmann trägt die EAN in `sku`, nicht in `gtin`.
const rossmannLd = '''
{"@context":"https://schema.org","@type":"Product",
 "name":"Badekristalle Wald-BAD","sku":"4008233129761",
 "offers":{"@type":"Offer","price":"0.95","priceCurrency":"EUR",
           "availability":"https://schema.org/InStock"}}''';

// Müller liefert `offers` als LISTE.
const muellerLd = '''
{"@context":"https://schema.org","@type":"Product",
 "name":"The Sin: Bliss (Take 1 Version) ","gtin":"823375216964","sku":"3222787",
 "offers":[{"@type":"Offer","price":29.99,"priceCurrency":"EUR",
            "availability":"https://schema.org/InStock"}]}''';

void main() {
  group('Link deuten', () {
    test('Host wird klein geschrieben', () {
      expect(preisHostAus('https://WWW.DM.de/p/d/1/x'), 'www.dm.de');
      expect(preisHostAus('https://www.rossmann.de/de/x/p/4008233129761'), 'www.rossmann.de');
    });

    test('kein http(s) → leer, nicht geraten', () {
      expect(preisHostAus('kein link'), '');
      expect(preisHostAus('ftp://www.dm.de/x'), '');
      expect(preisHostAus('javascript:alert(1)'), '');
      expect(preisUrlNormalisieren('www.dm.de/p/d/1'), '');
    });

    // ⚠️ Diese Fälle stehen zeichengleich in api/preise/manage.php. Weichen
    // die beiden Fassungen ab, entstehen zwei Zeilen für dasselbe Produkt —
    // ohne dass irgendetwas fehlschlägt.
    test('Query und Fragment fallen weg', () {
      const roh = 'https://www.mueller.de/p/artikel-PPN3222787/?itemId=3222787#tab';
      expect(preisUrlNormalisieren(roh), 'https://www.mueller.de/p/artikel-PPN3222787/');
    });

    test('derselbe Artikel aus Suche und Merkliste ergibt EINE Kennform', () {
      expect(
        preisUrlNormalisieren('https://www.dm.de/p/d/1625195/lavera?utm_source=suche'),
        preisUrlNormalisieren('https://www.dm.de/p/d/1625195/lavera#bewertungen'),
      );
    });

    test('http wird zu https, Groß/Klein vereinheitlicht', () {
      expect(preisUrlNormalisieren('http://WWW.DM.de/p/d/1/x'), 'https://www.dm.de/p/d/1/x');
    });
  });

  group('Preis aus der gerenderten Seite', () {
    test('dm — überspringt die zweite Product-Karte ohne Preis', () {
      final l = preisAusDom(dmSeite)!;
      expect(l.preis, 5.95);
      expect(l.name, 'Deo Roll-on Natural & Refresh, 50 ml');
      expect(l.gtin, '4021457638765');
      expect(l.verfuegbar, isTrue);
      expect(l.waehrung, 'EUR');
    });

    test('Rossmann — EAN steht in sku', () {
      final l = preisAusDom(seite(rossmannLd))!;
      expect(l.preis, 0.95);
      expect(l.gtin, '4008233129761');
      expect(l.name, 'Badekristalle Wald-BAD');
    });

    test('Müller — offers ist eine Liste', () {
      final l = preisAusDom(seite(muellerLd))!;
      expect(l.preis, 29.99);
      expect(l.gtin, '823375216964');
    });

    // ⚠️ Der wichtigste Test der Datei. Ein Parser, der bei einer Seite ohne
    // Preis irgendetwas zurückgibt, macht aus einem Lesefehler ein
    // „unverändert" — der schlimmste Ausgang, den diese Funktion haben kann.
    test('nichts Lesbares → null, niemals ein erfundener Wert', () {
      expect(preisAusDom('<html><body>Client Challenge</body></html>'), isNull);
      expect(preisAusDom(''), isNull);
      expect(preisAusDom(seite('{kaputtes json')), isNull);
      expect(preisAusDom(seite('{"@type":"Product","name":"X"}')), isNull);
      expect(
        preisAusDom(seite('{"@type":"Product","name":"X","offers":{"price":null}}')),
        isNull,
      );
    });

    test('ein kaputter Block wirft die übrigen nicht weg', () {
      final html = '<html><head>'
          '<script type="application/ld+json">{kaputt</script>'
          '<script type="application/ld+json">$muellerLd</script>'
          '</head></html>';
      expect(preisAusDom(html)!.preis, 29.99);
    });

    test('@graph wird durchsucht', () {
      final html = seite('{"@context":"https://schema.org","@graph":[$muellerLd]}');
      expect(preisAusDom(html)!.preis, 29.99);
    });

    test('ausverkauft wird als solches gelesen, nicht als fehlend', () {
      final l = preisAusDom(seite(
          '{"@type":"Product","name":"X","offers":{"price":1.0,'
          '"availability":"https://schema.org/OutOfStock"}}'))!;
      expect(l.verfuegbar, isFalse);
    });
  });

  group('Preiszahl', () {
    test('deutsche und englische Schreibweise', () {
      expect(preisZahl(5.95), 5.95);
      expect(preisZahl('5.95'), 5.95);
      expect(preisZahl('5,95'), 5.95);
      expect(preisZahl('5,95 €'), 5.95);
      expect(preisZahl('1.234,50'), 1234.50);
    });

    // 0 ist kein Preis, sondern ein Lesefehler; ein verrutschtes Komma darf
    // nicht als echte Änderung durchgehen und ntfy auslösen.
    test('unbrauchbare Werte → null', () {
      expect(preisZahl(0), isNull);
      expect(preisZahl('0,00'), isNull);
      expect(preisZahl(-3), isNull);
      expect(preisZahl(''), isNull);
      expect(preisZahl(null), isNull);
      expect(preisZahl('kostenlos'), isNull);
      expect(preisZahl(999999), isNull);
    });
  });
}
