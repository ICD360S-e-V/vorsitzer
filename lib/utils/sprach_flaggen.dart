/// Sprachen als Flagge **und** Kürzel, für die Visitenkarte.
///
/// ⚠️ Warum nie die Flagge allein — zwei voneinander unabhängige Gründe, und
/// jeder für sich würde schon genügen:
///
/// **1. Auf Windows gibt es keine Flaggen.** Flaggen sind keine eigenen
/// Zeichen, sondern Paare aus Regional Indicator Symbols (`U+1F1E9 U+1F1EA`
/// für DE). Segoe UI Emoji bildet diese Paare bewusst nicht ab; Windows stellt
/// stattdessen die beiden Buchstaben dar. Aus 🇩🇪🇷🇴🇬🇧 wird dort „DE RO GB".
/// Das ist keine Schriftlücke, die sich mit einem Font beheben ließe — es ist
/// eine Produktentscheidung von Microsoft. Die Vorsitzer-App läuft auf Linux,
/// Android, macOS **und** Windows.
///
/// **2. Eine Flagge ist keine Sprache.** 🇬🇧 heißt „Vereinigtes Königreich",
/// nicht „Englisch"; wer Englisch in Nigeria oder Indien spricht, findet sich
/// darin nicht wieder. Für Arabisch gibt es überhaupt kein Land, das die
/// Sprache vertritt. Deshalb steht das Kürzel immer daneben und trägt die
/// Information; die Flagge ist Schmuck, der beim schnellen Erfassen hilft.
///
/// Folge: eine Sprache ohne sinnvolle Flagge (`ar`) bekommt schlicht keine —
/// statt einer geratenen. Angezeigt wird dann nur das Kürzel.
library;

import 'sprachen_options.dart';

/// Eine Sprache, wie sie auf der Karte erscheint.
class SprachAnzeige {
  /// ISO-639-1-Code, klein geschrieben.
  final String code;

  /// Flaggen-Emoji, oder `null`, wenn es keine vertretbare Flagge gibt.
  final String? flagge;

  /// Was auf der Karte unter der Flagge steht: der Code in Großbuchstaben.
  final String kuerzel;

  /// Deutscher Sprachname, für Tooltip und Vorlesehilfen.
  final String bezeichnung;

  const SprachAnzeige(this.code, this.flagge, this.kuerzel, this.bezeichnung);
}

/// Flagge je Sprachcode.
///
/// Bewusst nur für die 28 Codes aus [appSprachCodes] gepflegt: das sind die
/// Sprachen, in die der Verein überhaupt übersetzt. Alles andere landet ohne
/// Flagge in der Anzeige, statt eine Lücke zu hinterlassen.
///
/// Die Zuordnung ist an einer Stelle bewusst nicht die naheliegende:
///   • `en` → 🇬🇧, nicht 🇺🇸. Der Verein arbeitet in Deutschland mit
///     britischem Sprachraum als Bezug; „GB" ist außerdem das, was Windows
///     ohnehin anzeigt.
///   • `nb` (Bokmål) → 🇳🇴. Norwegen hat keine Flagge je Schriftnorm.
///   • `sr` → 🇷🇸. NLLB übersetzt Serbisch nur kyrillisch, das ändert an der
///     Flagge nichts.
///   • `ar` → **keine**. Arabisch wird in über zwanzig Ländern gesprochen;
///     die Flagge Saudi-Arabiens dafür zu nehmen wäre eine politische
///     Aussage, keine sprachliche.
const Map<String, String> _flaggen = {
  'bg': '🇧🇬', 'cs': '🇨🇿', 'da': '🇩🇰', 'de': '🇩🇪', 'el': '🇬🇷',
  'en': '🇬🇧', 'es': '🇪🇸', 'et': '🇪🇪', 'fi': '🇫🇮', 'fr': '🇫🇷',
  'hr': '🇭🇷', 'hu': '🇭🇺', 'it': '🇮🇹', 'lt': '🇱🇹', 'lv': '🇱🇻',
  'nb': '🇳🇴', 'nl': '🇳🇱', 'pl': '🇵🇱', 'pt': '🇵🇹', 'ro': '🇷🇴',
  'ru': '🇷🇺', 'sk': '🇸🇰', 'sl': '🇸🇮', 'sr': '🇷🇸', 'sv': '🇸🇪',
  'tr': '🇹🇷', 'uk': '🇺🇦',
};

/// Eine gespeicherte Sprachangabe in etwas Anzeigbares übersetzen.
///
/// Nimmt sowohl Codes (`'ro'`, wie `users.languages` sie speichert) als auch
/// deutsche Bezeichnungen (`'Rumänisch'`) entgegen — die Datenbank ist bei
/// Sprachfeldern historisch in beiden Formen gefüllt worden, siehe
/// `users.muttersprache`. Was sich nicht auflösen lässt, kommt trotzdem
/// zurück, nur ohne Flagge: ein neuer Code soll sichtbar sein und nicht
/// stillschweigend verschwinden.
SprachAnzeige sprachAnzeige(String eingabe) {
  final roh = eingabe.trim();
  if (roh.isEmpty) return const SprachAnzeige('', null, '?', '');

  var code = roh.toLowerCase();
  if (code.length > 3) {
    // Keine Codeform — als deutsche Bezeichnung auflösen.
    code = appSprachCodeFuerBezeichnung(roh) ?? code;
  }

  return SprachAnzeige(
    code,
    _flaggen[code],
    code.length <= 3 ? code.toUpperCase() : roh,
    appSprachBezeichnung(code),
  );
}

/// Die Liste aus `users.languages` in Anzeigeobjekte übersetzen.
///
/// Dubletten fallen raus (jemand kann „de" und „Deutsch" gespeichert haben),
/// die Reihenfolge bleibt sonst erhalten: sie ist die Reihenfolge, in der die
/// Person ihre Sprachen genannt hat, und die erste ist üblicherweise die
/// stärkste.
List<SprachAnzeige> sprachAnzeigen(Iterable<dynamic> gespeichert) {
  final gesehen = <String>{};
  final raus = <SprachAnzeige>[];
  for (final e in gespeichert) {
    final a = sprachAnzeige(e?.toString() ?? '');
    if (a.code.isEmpty || !gesehen.add(a.code)) continue;
    raus.add(a);
  }
  return raus;
}
