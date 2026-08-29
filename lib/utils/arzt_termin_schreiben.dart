/// Ärzte ▸ Termin ▸ Terminverwaltung — die Kataloge der drei Schreiben.
///
/// Auslöser: viele Praxen verlangen eine Terminbestätigung. Dafür gab es in
/// der Anwendung bis zum 29.08.2026 nichts — und die vorhandenen Knöpfe
/// „Absage" und „Verschieben" erzeugten bloß einen Text zum Herauskopieren,
/// verschickt wurde nie etwas.
///
/// ⚠️ Diese drei Karten stehen ein zweites Mal auf dem Server, in
/// `api/helpers/arzt_termin_schreiben.php`. Der Server weist einen unbekannten
/// Schlüssel mit HTTP 400 ab, der Client zeigt die Beschriftung — laufen sie
/// auseinander, verschwindet ein Grund lautlos: der Haken lässt sich setzen,
/// die Vorschau schlägt fehl, und für den Nutzer passiert nichts.
///
/// Das PHP liegt in keinem Repo. `test/arzt_termin_schreiben_test.dart` hält
/// deshalb eine wörtliche Kopie der Server-Whitelist und vergleicht sie mit
/// diesen Karten — das ist die einzige Stelle, an der die Kopplung überhaupt
/// auffallen kann. Dasselbe Verfahren wie bei [kJcSchreibenArten] in
/// `jc_termin_gruende.dart`.
library;

/// Die drei Schreiben. Reihenfolge = Reihenfolge der Knöpfe.
///
/// ⚠️ „Absage" heißt hier wirklich Absage — anders als beim Jobcenter, wo das
/// Wort ein Wahlrecht behauptet, das es beim Meldetermin nicht gibt. Einen
/// Arzttermin darf man absagen.
const Map<String, String> kAtsArten = {
  'bestaetigen': 'Termin bestätigen',
  'verschieben': 'Termin verschieben',
  'absagen': 'Termin absagen',
};

/// Zusätze zur Terminbestätigung.
///
/// ⚠️ Das sind Hinweise, keine Gründe: eine Bestätigung braucht keine
/// Begründung. Deshalb darf hier auch nichts angekreuzt sein — siehe
/// [atsSchreibenPruefen].
const Map<String, String> kAtsZusaetzeBestaetigen = {
  'begleitung': 'Eine Begleitperson des Vereins kommt mit',
  'dolmetscher': 'Sprachmittlung durch die Begleitperson',
  'unterlagen': 'Die angeforderten Unterlagen werden mitgebracht',
  'ueberweisung': 'Die Überweisung wird mitgebracht',
  'versichertenkarte': 'Die Versichertenkarte wird mitgebracht',
  'barrierefrei': 'Es wird ein barrierefreier Zugang benötigt',
  'rollstuhl': 'Die Vorstellung erfolgt im Rollstuhl',
  'nuechtern': 'Rückfrage: muss zu diesem Termin nüchtern erschienen werden?',
};

/// Gründe für eine Terminverlegung.
const Map<String, String> kAtsGruendeVerschieben = {
  'behoerdentermin': 'Zeitgleicher Pflichttermin bei einer Behörde',
  'arbeitszeit': 'Der Termin liegt in der Arbeitszeit',
  'begleitung':
      'Begleitung und Sprachmittlung durch den Verein nur in einem anderen Zeitfenster möglich',
  'anderer_arzt': 'Zeitgleicher Termin bei einer anderen Praxis oder Klinik',
  'pflege': 'Betreuungs- oder Pflegezeit (Kind, Angehörige)',
  'gesundheit': 'Gesundheitliche Einschränkung zu dieser Tageszeit',
  'fahrt': 'Anfahrt mit dem ÖPNV zur genannten Uhrzeit nicht möglich',
  'ortsabwesenheit': 'Ortsabwesenheit an diesem Tag',
  'sonstiges': 'Sonstiger Grund',
};

/// Gründe für eine Terminabsage.
const Map<String, String> kAtsGruendeAbsagen = {
  'krankheit': 'Akute Erkrankung',
  'krankenhaus': 'Stationärer Krankenhausaufenthalt',
  'kind_krank':
      'Erkrankung des Kindes, Betreuung nicht anderweitig sicherzustellen',
  'pflege': 'Akute Pflege oder Betreuung einer oder eines Angehörigen',
  'behoerdentermin': 'Zeitgleicher Pflichttermin bei einer Behörde',
  'anderer_arzt': 'Die Behandlung wurde zwischenzeitlich anderweitig erbracht',
  'nicht_mehr_noetig':
      'Die Beschwerden bestehen nicht mehr, der Termin wird nicht mehr benötigt',
  'verkehr': 'Unvorhergesehener Ausfall öffentlicher Verkehrsmittel',
  'sonstiges': 'Sonstiger Grund',
};

/// Welcher Katalog gehört zu welchem Schreiben?
Map<String, String> atsKatalog(String art) => switch (art) {
      'bestaetigen' => kAtsZusaetzeBestaetigen,
      'verschieben' => kAtsGruendeVerschieben,
      'absagen' => kAtsGruendeAbsagen,
      _ => const {},
    };

/// Welchen Status setzt dieses Schreiben am Termin?
///
/// ⚠️ Der Status ist eine EIGENE Spalte, nicht der `typ`. Ein bestätigter
/// Notfalltermin bleibt ein Notfalltermin — würde man den `typ` überschreiben,
/// wäre hinterher nicht mehr zu erkennen, was für ein Termin das war. Die
/// ENUM-Werte `absage` und `verschoben` standen zwar seit jeher im `typ`,
/// wurden aber von keiner einzigen Zeile benutzt (nachgezählt am 29.08.2026:
/// 0 von 229).
String atsStatusFuer(String art) => switch (art) {
      'bestaetigen' => 'bestaetigt',
      'verschieben' => 'verschoben',
      'absagen' => 'abgesagt',
      _ => 'offen',
    };

/// Beschriftung eines Status, wie er am Termin angezeigt wird.
const Map<String, String> kAtsStatusLabel = {
  'offen': 'Offen',
  'bestaetigt': 'Bestätigt',
  'verschoben': 'Verlegung erbeten',
  'abgesagt': 'Abgesagt',
};

/// Prüft dasselbe wie der Server — damit der Nutzer die Absage sofort sieht
/// und nicht erst nach dem Rundweg über HTTP 400.
///
/// Gibt `null` zurück, wenn alles stimmt.
String? atsSchreibenPruefen({
  required String art,
  required List<String> gruende,
  required String freitext,
}) {
  if (!kAtsArten.containsKey(art)) return 'Unbekannte Art des Schreibens.';
  final katalog = atsKatalog(art);
  for (final g in gruende) {
    if (!katalog.containsKey(g)) return 'Unbekannter Grund: $g';
  }
  // ⚠️ Nur bei Verlegung und Absage. Eine Bestätigung bestätigt bloß; ein
  // Zwang zum Ankreuzen hätte dort dazu geführt, dass irgendein Zusatz
  // gewählt wird, nur damit der Knopf angeht.
  if (art != 'bestaetigen' && gruende.isEmpty && freitext.trim().isEmpty) {
    return 'Bitte einen Grund auswählen oder frei formulieren.';
  }
  return null;
}
