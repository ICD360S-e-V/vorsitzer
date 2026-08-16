/// Wie ein Mitglied angeredet wird — abgeleitet aus `users.geschlecht`
/// (Verifizierung Stufe 1).
enum Anredeform {
  frau,
  herr,

  /// Kein oder ein anderes Geschlecht hinterlegt. Dann wird ohne „Frau"/„Herr"
  /// angeredet, statt zu raten oder ein „Sehr geehrte(r)" hinzuschreiben.
  neutral,
}

/// Liest die Anredeform aus dem Stufe-1-Feld.
///
/// Das Feld ist über die Jahre in fünf Schreibweisen gefüllt worden —
/// `weiblich`, `maennlich`, `W`, `M` und bei 18 von 50 Mitgliedern gar nicht.
/// Eine Prüfung auf `== 'W'` (so stand es in der Termin-Erinnerung) trifft
/// damit nur einen Bruchteil; alle anderen bekamen ein unpersönliches
/// „Sehr geehrte(r)". Deshalb hier einmal zentral und großzügig geparst.
Anredeform anredeform(String? geschlecht) {
  final g = (geschlecht ?? '').trim().toLowerCase();
  if (g.isEmpty) return Anredeform.neutral;

  if (_weiblich.contains(g)) return Anredeform.frau;
  if (_maennlich.contains(g)) return Anredeform.herr;
  // „divers", „d", Freitext: neutral anreden statt falsch anreden.
  return Anredeform.neutral;
}

const _weiblich = {'w', 'f', 'weiblich', 'frau', 'female', 'femenin', 'feminin'};
const _maennlich = {
  'm', 'maennlich', 'männlich', 'mann', 'herr', 'male', 'masculin',
};
const _divers = {'d', 'divers', 'diverse', 'other', 'x'};

/// Bringt denselben Wert auf den Code, den das Stufe-1-Auswahlfeld kennt:
/// `M`, `W`, `D` — oder Leerstring, wenn nichts hinterlegt ist.
///
/// ⚠️ Leerstring heißt „nicht hinterlegt", nicht „männlich". Das
/// Verifizierungspanel hat unbekannte Schreibweisen bis zum 16.08.2026 auf
/// `M` abgebildet; in der Datenbank stehen aber 7 Frauen als `weiblich` und
/// 18 Mitglieder gar nicht. Wer bei einer von ihnen Stufe 1 speicherte,
/// schrieb ihr stillschweigend „männlich" in den Datensatz — und aus dem
/// Datensatz kommt die Anrede in Briefen, SMS und Chat.
String geschlechtCode(String? geschlecht) {
  final g = (geschlecht ?? '').trim().toLowerCase();
  if (g.isEmpty) return '';
  if (_weiblich.contains(g)) return 'W';
  if (_maennlich.contains(g)) return 'M';
  if (_divers.contains(g)) return 'D';
  // Etwas anderes: nicht raten. Lieber leer lassen, dann fragt das Panel
  // sichtbar nach, statt eine Angabe zu erfinden.
  return '';
}
