/// Namen aus `vorname`, `vorname2` und `nachname` zusammensetzen.
///
/// Klingt nach einer Zeile mit `join(' ')` — genau die steht an vier Stellen im
/// Client und ist an jeder von ihnen falsch:
///
/// ```dart
/// final fullVorname = [vorname, vorname2].where((s) => s.isNotEmpty).join(' ');
/// ```
///
/// Bei V27655 steht `vorname = 'Ionut-Claudiu'` und `vorname2 = 'Claudiu'`.
/// Stumpf aneinandergehängt ergibt das **„Ionut-Claudiu Claudiu Duinea"**, also
/// einen Namen, den es nicht gibt — der zweite Vorname wiederholt nur die
/// zweite Hälfte des ersten. Auf einer Visitenkarte fällt das sofort auf; auf
/// einer Vollmacht fällt es niemandem auf, bis eine Behörde nachfragt.
///
/// ⚠️ Die Regel ist zeichengleich zu `personName()` in
/// `api/cron/geburtstags_glueckwunsch.php`, `mailPersonName()` in
/// `api/mail/mail_config.php` und `vfPersonName()` in
/// `api/helpers/vorstand_funktion.php`: `vorname2` wird nur angehängt, wenn es
/// nicht schon in `vorname` vorkommt. Wer die Regel ändert, ändert sie an allen
/// vier Stellen.
///
/// Der Vergleich ist absichtlich **teilstring- und schreibweisenunabhängig**
/// (`stripos` in PHP, `toLowerCase().contains` hier). „Claudiu" steckt in
/// „Ionut-Claudiu"; ein Vergleich auf Gleichheit hätte den Dublettenfall genau
/// nicht erwischt.
library;

/// Der Vornamensteil: `vorname`, bei Bedarf ergänzt um `vorname2`.
///
/// Für Layouts, die Vor- und Nachname auf getrennte Zeilen setzen — auf einer
/// Visitenkarte steht der Nachname unter dem Vornamen, nicht dahinter.
String vornameVoll(String? vorname, String? vorname2) {
  final vor = (vorname ?? '').trim();
  final vor2 = (vorname2 ?? '').trim();

  if (vor.isEmpty) return vor2;
  if (vor2.isEmpty) return vor;
  if (vor.toLowerCase().contains(vor2.toLowerCase())) return vor;
  return '$vor $vor2';
}

/// Der vollständige Name.
///
/// [fallbackName] ist die abgeleitete Spalte `users.name`. Sie wird nur
/// benutzt, wenn aus den Einzelfeldern nichts zusammenkommt: bei den fünf
/// anonymisierten Konten sind `vorname`/`nachname` leer, `name` trägt dort
/// „Anonim #0103". Ohne den Rückfall stünde die Karte leer da.
String personName(
  String? vorname,
  String? vorname2,
  String? nachname, {
  String? fallbackName,
}) {
  final voll = [
    vornameVoll(vorname, vorname2),
    (nachname ?? '').trim(),
  ].where((t) => t.isNotEmpty).join(' ');

  return voll.isNotEmpty ? voll : (fallbackName ?? '').trim();
}

/// Nachname, mit demselben Rückfall wie [personName].
///
/// Fehlt der Nachname, aber `name` ist gefüllt, wird der letzte Bestandteil
/// von `name` genommen — besser eine begründete Vermutung als eine leere Zeile
/// dort, wo auf der Karte der Familienname steht.
String nachnameOder(String? nachname, {String? fallbackName}) {
  final n = (nachname ?? '').trim();
  if (n.isNotEmpty) return n;

  final f = (fallbackName ?? '').trim();
  if (f.isEmpty) return '';
  final teile = f.split(RegExp(r'\s+'));
  return teile.length > 1 ? teile.last : f;
}
