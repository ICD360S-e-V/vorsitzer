/// Namen aus `vorname`, `vorname2` und `nachname` zusammensetzen.
///
/// Klingt nach einer Zeile mit `join(' ')` — genau die steht an vier Stellen im
/// Client und ist an jeder von ihnen falsch:
///
/// ```dart
/// final fullVorname = [vorname, vorname2].where((s) => s.isNotEmpty).join(' ');
/// ```
///
/// Bei V10001 steht `vorname = 'Ilies-Cristian'` und `vorname2 = 'Cristian'`.
/// Stumpf aneinandergehängt ergibt das **„Ilies-Cristian Cristian Doe"**, also
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
/// (`stripos` in PHP, `toLowerCase().contains` hier). „Cristian" steckt in
/// „Ilies-Cristian"; ein Vergleich auf Gleichheit hätte den Dublettenfall genau
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

/// Die Vereinsadresse einer Person, abgeleitet aus Rolle und Namen.
///
/// ## Zwei Regeln, nach Rolle
///
/// * **Vorstand und benannte Ämter** → die Anfangsbuchstaben aller Namensteile.
///   Ilies-Cristian Doe wird zu `icd@`, Michaela-Christine Weber zu `mcw@` —
///   genau die Adressen, die beide seit jeher benutzen. Die Regel ist also
///   nicht erfunden, sondern die bereits gelebte Praxis, aufgeschrieben.
/// * **Alle übrigen** → die Mitgliedsnummer, `M10001@`.
///
/// ## ⚠️ Warum nicht einfach `users.email`
///
/// Weil dort bei mehreren Vorstandsmitgliedern eine **private** Adresse steht
/// (`erika.musterfrau@example.com`, `max.mustermann@example.com`). Auf einer Karte, die
/// der Verein ausgibt und die weitergereicht wird, hat die nichts verloren —
/// und sie bliebe erreichbar, lange nachdem die Person nicht mehr im Vorstand
/// ist. Die abgeleitete Adresse gehört dem Verein.
///
/// ## ⚠️ Es muss kein Postfach angelegt werden
///
/// Für `icd360s.de` gibt es einen Auffang-Alias (`@icd360s.de -> icd@`). Am
/// 14.08.2026 mit je einem eigenen SMTP-Versuch geprüft — `V10001@`, `V10002@`,
/// `am@`, `adcr@`, `msrd@`, `dmp@`, `icd@` und `mcw@` antworten alle mit
/// `250 2.1.5 Ok`.
///
/// ⚠️ Die erste Messung war falsch: mehrere `RCPT` in einer Sitzung, getrennt
/// durch `RSET` — das setzt die Transaktion zurück, danach fehlt das `MAIL
/// FROM` und jedes weitere `RCPT` läuft ins Leere. Nur der erste Wert galt.
/// Wer das nachprüft, baut je Adresse eine eigene Sitzung.
///
/// ⚠️ **Gleiche Initialen kollidieren.** Bei den heutigen sechs Ämtern gibt es
/// keine Dublette (icd, mcw, am, adcr, msrd, dmp), ein Test hält das fest.
/// Kommt jemand mit denselben Anfangsbuchstaben dazu, teilen sich zwei Personen
/// eine Adresse — was beim Auffang-Alias niemandem auffällt, weil ohnehin alles
/// im selben Postfach landet. Dann muss die Regel von Hand aufgelöst werden.
const Set<String> kAemterRollen = {
  'vorsitzer',
  'schatzmeister',
  'kassierer',
  'mitgliedergrunder',
};

String vereinsAdresse({
  required String rolle,
  required String mitgliedernummer,
  required String vorname,
  String? vorname2,
  required String nachname,
  required String domain,
}) {
  if (!kAemterRollen.contains(rolle.trim().toLowerCase())) {
    return '$mitgliedernummer@$domain';
  }
  final ini = initialen(vorname, vorname2, nachname);
  // Ohne verwertbaren Namen bleibt die Nummer — besser als ein leeres `@`.
  return ini.isEmpty ? '$mitgliedernummer@$domain' : '$ini@$domain';
}

/// Die Anfangsbuchstaben aller Namensteile, klein geschrieben.
///
/// ⚠️ Getrennt wird an Leerzeichen **und Bindestrichen**: „Ilies-Cristian" sind
/// zwei Namen, nicht einer. Ohne den Bindestrich käme `id@` statt `icd@` heraus
/// — und `icd@icd360s.de` ist die Adresse, die es seit jeher gibt.
///
/// `vorname2` fließt nur ein, wenn er nicht schon im Vornamen steckt (dieselbe
/// Regel wie in [vornameVoll]); sonst hätte V10001 ein `c` doppelt.
String initialen(String? vorname, String? vorname2, String? nachname) {
  final teile = [
    vornameVoll(vorname, vorname2),
    (nachname ?? '').trim(),
  ].where((t) => t.isNotEmpty).join(' ');

  return teile
      .split(RegExp(r'[\s\-]+'))
      .where((t) => t.isNotEmpty)
      .map((t) => t[0].toLowerCase())
      .join();
}
