/// Flaggen als **mitgelieferte Bilddateien**, eine je Sprache.
///
/// ## Warum Bilder und nicht Emoji
///
/// Zwei Wände, gegen die ein Emoji hier läuft:
///
/// 1. **Im PDF gibt es keine.** Die eingebauten PDF-Schriften kennen die
///    Regional-Indicator-Zeichen nicht, die mitgelieferte DejaVu auch nicht,
///    und farbige Emoji-Schriften (CBDT/sbix/COLR) bildet der PDF-Erzeuger
///    grundsätzlich nicht ab. Eine Flagge käme als leeres Kästchen heraus.
/// 2. **Auf Windows gibt es auch keine.** Segoe UI Emoji bildet die
///    Regional-Indicator-Paare bewusst nicht ab; dort stehen stattdessen die
///    zwei Buchstaben des Ländercodes. Das ist eine Produktentscheidung von
///    Microsoft, keine Schriftlücke, die sich mit einem Font beheben ließe.
///
/// Als Bilddateien sind sie auf allen vier Zielplattformen und im Druck
/// dieselben — der Windows-Fall ist damit ebenfalls erledigt.
///
/// ## ⚠️ Warum NICHT selbst gezeichnet
///
/// Eine erste Fassung baute die Fahnen aus Rechtecken. Das trägt für Streifen
/// und Nordkreuze, scheitert aber an allem mit Wappen, Halbmond oder Emblem —
/// und, schlimmer, es scheiterte still: **der handgezeichnete Union Jack ohne
/// Schrägbalken war ein rot-weißes Kreuz auf Blau, also die Flagge Islands.**
/// Aufgefallen ist das erst am gerenderten Bogen. Eine Flagge ohne ihr Merkmal
/// ist die Flagge eines anderen Landes; Slowakei ohne Wappen ist Russland,
/// Slowenien ebenso. Mit echten Bildern gibt es diese Fehlerklasse nicht.
///
/// ## Herkunft und Lizenz
///
/// Bezogen von Wikimedia Commons über `Special:FilePath`, in 180 px Breite aus
/// den amtlichen SVG-Vorlagen gerastert. Nationalflaggen sind gemeinfrei —
/// sie sind keine schutzfähigen Werke, und die Commons-Dateien sind
/// entsprechend als *public domain* ausgewiesen.
///
/// ⚠️ **Nicht** aus `/usr/share/iso-flag-png` genommen, obwohl es lokal liegt:
/// das Paket stammt von Linux Mint und steht unter **GPL-2.0+**. Eine
/// Copyleft-Lizenz an Programmbeiträgen dieser App wäre eine Entscheidung,
/// die niemand getroffen hat — und für Flaggen völlig unnötig, weil es sie
/// gemeinfrei gibt.
///
/// ⚠️ Der Bezug lief **einmalig beim Bauen**, die Dateien liegen im Bundle.
/// Zur Laufzeit wird nichts nachgeladen: die Karte muss auch ohne Netz
/// druckbar sein, und ein Abruf bei jedem Öffnen wäre nebenbei eine Meldung an
/// einen Dritten, wer hier gerade Visitenkarten druckt.
///
/// ## ⚠️ Die Seitenverhältnisse sind verschieden
///
/// Dänemark ist 37 : 28, die Schweiz wäre quadratisch, das Vereinigte
/// Königreich amtlich 2 : 1 (hier in der 3 : 5-Variante). Die Dateien behalten
/// ihr eigenes Verhältnis; gezeichnet wird in einen festen Rahmen mit
/// `contain`, nie verzerrt.
library;

/// Sprachcodes, für die eine Fahne mitgeliefert wird.
///
/// ⚠️ `ar` fehlt, und zwar mit Absicht: Arabisch wird in über zwanzig Ländern
/// gesprochen. Die Flagge Saudi-Arabiens dafür zu nehmen wäre eine politische
/// Aussage, keine sprachliche. Dort steht das Kürzel allein — es trägt die
/// Information ohnehin.
const Set<String> kFlaggenCodes = {
  'bg', 'cs', 'da', 'de', 'el', 'en', 'es', 'et', 'fi', 'fr',
  'hr', 'hu', 'it', 'lt', 'lv', 'nb', 'nl', 'pl', 'pt', 'ro',
  'ru', 'sk', 'sl', 'sr', 'sv', 'tr', 'uk',
};

/// Der Bundle-Pfad zur Fahne einer Sprache, oder `null`.
///
/// ⚠️ Sprache ist nicht Land. Die Zuordnung ist eine **Konvention für die
/// Anzeige**, keine Aussage darüber, wo jemand herkommt — genau deshalb steht
/// das Kürzel immer daneben. Englisch zeigt das Vereinigte Königreich, weil
/// der Verein im europäischen Sprachraum arbeitet; wer Englisch in Nigeria
/// gelernt hat, findet sich in dieser Fahne nicht wieder, wohl aber im „EN".
String? flaggenPfad(String sprachcode) {
  final c = sprachcode.trim().toLowerCase();
  return kFlaggenCodes.contains(c) ? 'assets/flaggen/$c.png' : null;
}
