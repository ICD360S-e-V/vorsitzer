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

  const weiblich = {'w', 'f', 'weiblich', 'frau', 'female', 'femenin', 'feminin'};
  const maennlich = {
    'm', 'maennlich', 'männlich', 'mann', 'herr', 'male', 'masculin',
  };

  if (weiblich.contains(g)) return Anredeform.frau;
  if (maennlich.contains(g)) return Anredeform.herr;
  // „divers", „d", Freitext: neutral anreden statt falsch anreden.
  return Anredeform.neutral;
}
