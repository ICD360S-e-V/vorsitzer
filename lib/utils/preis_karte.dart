// Rechnen auf einer Produktkarte: was ist der günstigste Markt, und um
// wie viel.
//
// Reine Logik ohne Flutter, damit die eine Aussage, wegen der es diese
// Funktion überhaupt gibt — „hier sind es X Cent weniger" — im Test
// nachprüfbar ist.

class PreisSpanne {
  final double guenstigster;
  final double teuerster;
  final int mitPreis;

  const PreisSpanne({
    required this.guenstigster,
    required this.teuerster,
    required this.mitPreis,
  });

  double get differenz => teuerster - guenstigster;

  /// Aufschlag des teuersten gegenüber dem günstigsten, in Prozent.
  double get prozent => guenstigster <= 0 ? 0 : differenz / guenstigster * 100;

  /// ⚠️ Ein Vergleich braucht ZWEI Preise. Mit einem einzigen gibt es keinen
  /// „Gewinner" — ein Häkchen an der einzigen Zeile behauptet einen Vergleich,
  /// den niemand angestellt hat.
  bool get vergleichbar => mitPreis >= 2 && differenz > 0.0001;
}

/// Die Spanne über die Links einer Karte. `null`, wenn nichts zu vergleichen ist.
///
/// ⚠️ Zeilen ohne Preis zählen nicht mit — weder als 0 noch als „teuer".
/// Ein Markt, dessen Seite heute nicht gelesen werden konnte, darf den
/// Vergleich nicht gewinnen und nicht verlieren.
PreisSpanne? preisSpanne(List<Map<String, dynamic>> links) {
  final werte = <double>[];
  for (final l in links) {
    final p = l['letzter_preis'];
    if (p is num && p > 0) werte.add(p.toDouble());
  }
  if (werte.isEmpty) return null;
  werte.sort();
  return PreisSpanne(
    guenstigster: werte.first,
    teuerster: werte.last,
    mitPreis: werte.length,
  );
}

/// Ist DIESER Link der günstigste der Karte?
///
/// ⚠️ Nur wenn es überhaupt etwas zu vergleichen gibt. Sonst trüge die
/// einzige Zeile einer neuen Karte sofort ein „am günstigsten", und das
/// stimmt nur zufällig.
bool istGuenstigster(Map<String, dynamic> link, List<Map<String, dynamic>> alle) {
  final s = preisSpanne(alle);
  if (s == null || !s.vergleichbar) return false;
  final p = link['letzter_preis'];
  if (p is! num) return false;
  return (p.toDouble() - s.guenstigster).abs() < 0.005;
}

/// Wie alt ist die älteste Lesung, die in den Vergleich eingeht?
///
/// ⚠️ Zwei Preise aus verschiedenen Tagen nebeneinanderzustellen und daraus
/// „dm ist teurer" zu machen, ist eine Aussage über vorgestern. Der Bildschirm
/// schreibt die Spanne deshalb hin, statt sie zu verschweigen.
Duration? aeltesteLesung(List<Map<String, dynamic>> links, {DateTime? jetzt}) {
  final n = jetzt ?? DateTime.now();
  DateTime? aeltest;
  for (final l in links) {
    if (l['letzter_preis'] == null) continue;
    final roh = l['zuletzt_geprueft'] as String?;
    if (roh == null) continue;
    final d = DateTime.tryParse(roh);
    if (d == null) continue;
    if (aeltest == null || d.isBefore(aeltest)) aeltest = d;
  }
  return aeltest == null ? null : n.difference(aeltest);
}

String euro(num? w) =>
    w == null ? '—' : '${w.toStringAsFixed(2).replaceAll('.', ',')} €';

/// Prozentangabe für den Unterschied.
///
/// ⚠️ Unter zehn Prozent mit einer Nachkommastelle. Ohne sie werden aus
/// 0,67 % gerundete „1 %" — das übertreibt den Unterschied um die Hälfte,
/// und zwar ausgerechnet bei den kleinen Abständen, die den Alltag ausmachen.
String prozentText(double p) {
  final s = p < 10 ? p.toStringAsFixed(1) : p.toStringAsFixed(0);
  return '${s.replaceAll('.', ',')} %';
}
