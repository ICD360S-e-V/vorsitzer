/// Ordnet die Fachrichtung eines Reiters den Schreibweisen in den
/// Ärzte-Datenbanken zu.
///
/// 🔴 WARUM ES DIESE DATEI GIBT
/// Der Server filtert mit EXAKTER GLEICHHEIT (`WHERE ... AND fachrichtung = ?`).
/// Gesucht wird aber mit Bezeichnungen aus der Oberfläche, und die stimmen mit
/// dem Datenbankfeld fast nie zeichengleich überein. Ohne Übersetzung findet
/// die Suche in genau den Fällen nichts, in denen die Praxis sehr wohl
/// gespeichert ist — und eine leere Liste liest sich wie „gibt es nicht", nicht
/// wie „falsch geschrieben".
///
/// 🔴 EXAKTE GLEICHHEIT REICHT NICHT, AUCH NICHT MIT ÜBERSETZUNGSTABELLE.
/// Am 26.08.2026 gegen die 24 Schreibweisen der `aerzte_datenbank` nachgemessen:
/// ein und dasselbe Fach steht dort in mehreren Fassungen nebeneinander —
/// `Orthopädie`, `Orthopädie und Unfallchirurgie` und
/// `Orthopädie / Unfallchirurgie / Gefäßchirurgie / Neurochirurgie`, ebenso
/// `Psychiatrie` neben `Psychiatrie und Psychotherapie`. Eine Abfrage auf einen
/// einzelnen Wert kann davon immer nur einen Teil finden und verschweigt den
/// Rest, ohne dass etwas fehlschlägt. Deshalb wird hier nicht ein Wert
/// gesucht, sondern verglichen: beide Seiten werden in ihre Fachbegriffe
/// zerlegt, und es genügt EIN gemeinsamer Begriff.
///
/// ⚠️ Diese Datei ist eine BEHAUPTUNG ÜBER SCHREIBWEISEN, nicht über Medizin.
/// Sie setzt keine Fächer gleich; sie erkennt nur, dass „Orthopädie und
/// Unfallchirurgie" und „Orthopädie / Unfallchirurgie / …" dieselbe Praxis
/// meinen können.
library;

/// Bezeichnung aus der Oberfläche → Schreibweise in der Datenbank.
///
/// Nur da nötig, wo die Zerlegung in Fachbegriffe NICHT ausreicht, weil kein
/// einziger Begriff wörtlich übereinstimmt. „Psychiatrie / Psychotherapie"
/// stand hier bis zum 26.08.2026 und ist entfallen: gegen „Psychiatrie und
/// Psychotherapie" trifft schon der gemeinsame Begriff, und die alte Zeile
/// fand zusätzlich die Zeile `Psychiatrie` NICHT.
const Map<String, String> kFachrichtungAlias = {
  // Der Klassiker: drei Buchstaben gegen den vollen amtlichen Namen. Hier
  // hilft kein gemeinsamer Begriff — „HNO" kommt in der Langform nicht vor.
  'HNO': 'Hals-Nasen-Ohren-Heilkunde',
  // Der Augenarzt-Reiter nennt sein Fach 'Ophthalmologie', beide Kataloge
  // führen es als 'Augenheilkunde'. Dasselbe Fach, zwei Wörter, kein
  // gemeinsamer Begriff.
  'Ophthalmologie': 'Augenheilkunde',
  // ⚠️ In der Datenbank gibt es keine allgemeine „Chirurgie", sondern nur
  // Orthopädie mit Unfallchirurgie. Das ist keine Gleichsetzung der Fächer —
  // es ist die einzige Praxis, bei der eine chirurgische Überweisung in
  // dieser Datenbank überhaupt landen kann.
  'Chirurgie': 'Orthopädie und Unfallchirurgie',
};

/// Trennzeichen zwischen zwei Fachbegriffen in EINER Angabe.
///
/// ⚠️ Der Bindestrich steht bewusst NICHT dabei: „Hals-Nasen-Ohren-Heilkunde"
/// und „Magen-Darm-Erkrankungen" sind je ein Begriff, kein Aufzählung.
final RegExp _trenner = RegExp(r'\s*(?:/|,|;|\+|&|\bund\b|\boder\b)\s*');

/// Zerlegt eine Fachrichtungsangabe in ihre einzelnen Fachbegriffe.
///
/// `'Orthopädie und Unfallchirurgie'` → `{orthopädie, unfallchirurgie}`
/// `'Gastroenterologie / Magen-Darm-Erkrankungen'`
///   → `{gastroenterologie, magen-darm-erkrankungen}`
Set<String> fachrichtungBegriffe(String angabe) {
  final ausgeschrieben = kFachrichtungAlias[angabe.trim()] ?? angabe;
  return ausgeschrieben
      .toLowerCase()
      .split(_trenner)
      .map((t) => t.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((t) => t.isNotEmpty)
      .toSet();
}

/// Passt der Datenbankeintrag [ausDatenbank] zur gesuchten Fachrichtung
/// [gesucht]?
///
/// Es genügt EIN gemeinsamer Fachbegriff. Eine leere Suche passt auf alles —
/// ohne Fach gibt es nichts einzugrenzen.
bool fachrichtungPasst(String gesucht, String ausDatenbank) {
  if (gesucht.trim().isEmpty) return true;
  final a = fachrichtungBegriffe(gesucht);
  if (a.isEmpty) return true;
  final b = fachrichtungBegriffe(ausDatenbank);
  return b.any(a.contains);
}
