import 'dart:convert';

/// Preisüberwachung: Link deuten und aus einer gerenderten Seite lesen.
///
/// Reine Logik, absichtlich ohne Netz und ohne Flutter — damit das, worauf
/// alles andere aufbaut, im Test nachprüfbar ist.
///
/// ⚠️ Warum die Seite gerendert werden muss und ein einfacher Abruf nicht
/// reicht (gemessen am 05.09.2026):
///   - dm liefert für die Produktseite 11 kB reines JS-Gerüst. Weder Name noch
///     Preis stehen darin; der Browser holt sie danach nach.
///   - Rossmann antwortet auf jeden Abruf ohne Browser mit einer 3-kB-Seite
///     „Client Challenge".
///   - Müller allein käme ohne Browser aus.
/// Im echten Browser liefern alle drei dasselbe saubere schema.org/Product.

/// Ein aus der Seite gelesener Stand.
class PreisLesung {
  final String? name;
  final double? preis;
  final String waehrung;
  final String? gtin;
  final bool? verfuegbar;

  const PreisLesung({
    this.name,
    this.preis,
    this.waehrung = 'EUR',
    this.gtin,
    this.verfuegbar,
  });

  bool get brauchbar => preis != null;

  Map<String, dynamic> alsBericht() => {
        if (name != null && name!.isNotEmpty) 'name': name,
        if (preis != null) 'preis': preis,
        'waehrung': waehrung,
        if (gtin != null && gtin!.isNotEmpty) 'gtin': gtin,
        if (verfuegbar != null) 'verfuegbar': verfuegbar,
      };
}

/// Host eines Links, klein geschrieben. Leer, wenn es kein http(s)-Link ist.
String preisHostAus(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null || !u.hasScheme) return '';
  if (u.scheme != 'http' && u.scheme != 'https') return '';
  return u.host.toLowerCase();
}

/// Link auf seine Kennform bringen — zeichengleich mit
/// `preisUrlNormalisieren()` in api/preise/manage.php.
///
/// ⚠️ Query und Fragment fallen weg. Müller hängt an denselben Artikel ein
/// `?itemId=…`, und wer den Link einmal aus der Suche und einmal aus der
/// Merkliste kopiert, bekäme sonst zwei Zeilen für dasselbe Produkt — mit zwei
/// getrennten Preisverläufen, die beide unvollständig sind.
///
/// ⚠️ Weicht diese Funktion je von der auf dem Server ab, entstehen genau
/// solche Doppelungen, ohne dass irgendetwas fehlschlägt. `test/preis_link_test.dart`
/// hält beide Fassungen an denselben Fällen fest.
String preisUrlNormalisieren(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null || !u.hasScheme) return '';
  if (u.scheme != 'http' && u.scheme != 'https') return '';
  if (u.host.isEmpty) return '';
  final pfad = u.path.isEmpty ? '/' : u.path;
  return 'https://${u.host.toLowerCase()}$pfad';
}

/// Alle JSON-LD-Blöcke einer Seite.
List<dynamic> _jsonLdBloecke(String html) {
  final treffer = RegExp(
    r'<script[^>]*type\s*=\s*["' "'" r']application/ld\+json["' "'" r'][^>]*>(.*?)</script>',
    caseSensitive: false,
    dotAll: true,
  ).allMatches(html);

  final out = <dynamic>[];
  for (final m in treffer) {
    final roh = (m.group(1) ?? '').trim();
    if (roh.isEmpty) continue;
    try {
      out.add(jsonDecode(roh));
    } catch (_) {
      // Ein kaputter Block ist kein Grund, die übrigen wegzuwerfen — auf der
      // dm-Seite stehen mehrere, und nur einer trägt den Preis.
    }
  }
  return out;
}

/// Flacht @graph und Listen ein, damit die Suche unten nur Karten sieht.
void _sammle(dynamic knoten, List<Map<String, dynamic>> ziel) {
  if (knoten is List) {
    for (final k in knoten) {
      _sammle(k, ziel);
    }
  } else if (knoten is Map<String, dynamic>) {
    ziel.add(knoten);
    if (knoten['@graph'] != null) _sammle(knoten['@graph'], ziel);
  }
}

bool _istProdukt(Map<String, dynamic> k) {
  final t = k['@type'];
  if (t is String) return t.toLowerCase() == 'product';
  if (t is List) return t.any((x) => x.toString().toLowerCase() == 'product');
  return false;
}

/// Zahl aus `price` — der Wert kommt mal als Zahl, mal als Zeichenkette.
double? preisZahl(dynamic roh) {
  if (roh == null) return null;
  if (roh is num) {
    final w = roh.toDouble();
    return (w > 0 && w < 99999) ? w : null;
  }
  var s = roh.toString().replaceAll(RegExp(r'[^0-9,.\-]'), '');
  if (s.isEmpty) return null;
  // Deutsche Schreibweise: das Komma trennt die Nachkommastellen.
  if (s.contains(',')) s = s.replaceAll('.', '');
  s = s.replaceAll(',', '.');
  final w = double.tryParse(s);
  if (w == null || w <= 0 || w >= 99999) return null;
  return w;
}

/// Liest Name, Preis, GTIN und Verfügbarkeit aus einer GERENDERTEN Seite.
///
/// Gibt `null` zurück, wenn nichts Brauchbares darin steht — das ist ein
/// Fehlschlag und muss als solcher gemeldet werden, nie als „unverändert".
PreisLesung? preisAusDom(String html) {
  final karten = <Map<String, dynamic>>[];
  for (final b in _jsonLdBloecke(html)) {
    _sammle(b, karten);
  }

  for (final k in karten) {
    if (!_istProdukt(k)) continue;

    // ⚠️ `offers` ist mal Karte, mal Liste — Müller liefert eine Liste.
    final roh = k['offers'];
    final angebote = <Map<String, dynamic>>[];
    if (roh is Map<String, dynamic>) angebote.add(roh);
    if (roh is List) {
      angebote.addAll(roh.whereType<Map<String, dynamic>>());
    }

    for (final a in angebote) {
      final preis = preisZahl(a['price']);
      // ⚠️ Weitersuchen statt aufgeben: dm legt ZWEI Product-Karten auf die
      // Seite, und nur eine davon trägt einen Preis. Wer die erste nimmt und
      // sich zufriedengibt, meldet jeden Tag „nicht lesbar".
      if (preis == null) continue;

      final verf = a['availability']?.toString().toLowerCase();
      return PreisLesung(
        name: k['name']?.toString().trim(),
        preis: preis,
        waehrung: (a['priceCurrency']?.toString() ?? 'EUR').toUpperCase(),
        // ⚠️ Rossmann trägt die Nummer in `sku`, Müller und dm in `gtin`
        // bzw. `gtin13`. Alle drei meinen dieselbe EAN — sie ist die Klammer,
        // an der sich dasselbe Produkt in zwei Märkten wiederfindet.
        gtin: (k['gtin13'] ?? k['gtin'] ?? k['gtin8'] ?? k['sku'])?.toString().trim(),
        verfuegbar: verf == null
            ? null
            : (verf.contains('instock') || verf.contains('limitedavailability')),
      );
    }
  }
  return null;
}
