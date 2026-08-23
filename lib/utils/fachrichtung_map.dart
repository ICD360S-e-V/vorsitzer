/// Vom Kurznamen der Überweisung auf die Schreibweise in `aerzte_datenbank`.
///
/// 🔴 WARUM ES DIESE DATEI GIBT
/// Der Server filtert mit EXAKTER GLEICHHEIT (`WHERE ... AND fachrichtung = ?`).
/// Das Auswahlfeld der Überweisung führt 24 Kurzformen („HNO", „Radiologie"),
/// die Datenbank die amtlichen Langformen („Hals-Nasen-Ohren-Heilkunde"). Ohne
/// Übersetzung findet die Suche in genau den Fällen nichts, in denen die Praxis
/// sehr wohl gespeichert ist — und eine leere Liste liest sich wie „gibt es
/// nicht", nicht wie „falsch geschrieben".
///
/// Nachgemessen am 23.08.2026 gegen die 23 Fachrichtungen der Datenbank:
/// 11 der 24 Kurznamen trafen exakt, 13 nicht. Von diesen 13 sind vier bloße
/// Schreibunterschiede (hier übersetzt) und neun tatsächlich leer — dort gibt
/// es schlicht keine Praxis.
///
/// ⚠️ Diese Tabelle ist eine BEHAUPTUNG ÜBER DIE DATEN, nicht über die Medizin.
/// Kommt eine Praxis mit anderer Schreibweise dazu, gehört sie hierher — oder,
/// besser, die Datenbank wird auf die amtliche Form gebracht.
library;

/// Kurzform → Schreibweise in der Datenbank.
///
/// Nur wo sie sich unterscheiden. Alles andere trifft ohnehin.
const Map<String, String> kFachrichtungAlias = {
  // Der Klassiker: drei Buchstaben gegen den vollen amtlichen Namen.
  'HNO': 'Hals-Nasen-Ohren-Heilkunde',
  // Der Schrägstrich der Auswahlliste gegen das „und" der Datenbank.
  'Psychiatrie / Psychotherapie': 'Psychiatrie und Psychotherapie',
  // ⚠️ In der Datenbank gibt es keine allgemeine „Chirurgie", sondern nur
  // Orthopädie mit Unfallchirurgie. Das ist keine Gleichsetzung der Fächer —
  // es ist die einzige Praxis, bei der eine chirurgische Überweisung in
  // dieser Datenbank überhaupt landen kann.
  'Chirurgie': 'Orthopädie und Unfallchirurgie',
};

/// Die Fachrichtung, mit der beim Server gesucht wird.
String fachrichtungFuerSuche(String kurz) {
  final k = kurz.trim();
  if (k.isEmpty) return '';
  return kFachrichtungAlias[k] ?? k;
}

/// Fachrichtungen, für die am 23.08.2026 KEINE einzige Praxis gespeichert war.
///
/// ⚠️ Wird nur benutzt, um dem Menschen zu sagen, WARUM die Liste leer ist.
/// Sie ist ein Stand, keine Wahrheit: sobald jemand eine Praxis anlegt, stimmt
/// der Eintrag nicht mehr. Deshalb entscheidet über die Anzeige immer das
/// tatsächliche Suchergebnis — diese Liste liefert nur den Zusatzsatz.
const Set<String> kFachrichtungOhneEintrag = {
  // ⚠️ „Radiologie" stand hier bis zum 23.08.2026 — zu Unrecht. Die beiden
  // Radiologien LAGEN in der Datenbank, nur unter `fachrichtung =
  // 'Allgemeinmedizin'`. Eine Abfrage auf die Fachrichtung meldete
  // wahrheitsgemäß „keine Radiologie" und war trotzdem falsch. Die beiden
  // Zeilen sind inzwischen richtig eingeordnet.
  'Kardiologie',
  'Pädiatrie',
  'Rheumatologie',
  'Nephrologie',
  'Hämatologie / Onkologie',
  'Innere Medizin',
  'Sportmedizin',
  'Labor',
};
