/// Baut die Ausfüllwerte für ein Online-Kündigungsformular.
///
/// Die Daten kommen aus zwei Quellen, weil kein Formular mit einer allein
/// auskommt: die **Stammdaten des Mitglieds** aus Verifizierung Stufe 1
/// (Name, Geburtsdatum, Anschrift) und der **Vertrag selbst**
/// (Kundennummer, Rufnummer). Das Formular von o2 verlangt beides.
///
/// Die Schlüssel sind genau die, die `_buildGo2DocJs` in
/// `lib/screens/webview_screen.dart` liest — dieselbe Maschinerie, mit der
/// die Praxisportale bei Ärzte → Termin befüllt werden.
///
/// ⚠️ Reine Funktion, kein Widget und kein Netz: nur so lässt sich prüfen,
/// dass aus einem Datensatz die richtigen Werte fallen. Das Laden der
/// Stammdaten macht der Aufrufer.
library;

/// Postfach des Vereins für die Eingangsbestätigung.
///
/// ⚠️ Bewusst **nicht** die private Adresse des Mitglieds. Die Bestätigung
/// einer Kündigung ist der Nachweis, dass sie zugegangen ist — sie muss dort
/// landen, wo der Verein sie archiviert und wiederfindet, und das ist das
/// Postfach, das die Korrespondenz einliest. Dieselbe Entscheidung wie beim
/// Praxis-Portal in `gesundheit_tab_content.dart`.
const String kKuendigungBestaetigungMail = 'icd@icd360s.de';

/// Nimmt den ersten nicht-leeren Wert aus [quellen] für [schluessel].
String _feld(List<Map<String, dynamic>?> quellen, String schluessel) {
  for (final q in quellen) {
    final v = q?[schluessel];
    if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
  }
  return '';
}

/// Zerlegt ein Geburtsdatum in Tag, Monat, Jahr.
///
/// ⚠️ Erkennt beide Richtungen: `1980-04-27` (so liefert es die Datenbank)
/// und `27.04.1980` (so tippt es ein Mensch). Ohne die Fallunterscheidung
/// stünde im Formular der 19. des Monats 80.
({String tag, String monat, String jahr}) geburtsdatumZerlegen(String roh) {
  final teile = roh.trim().split(RegExp(r'[-./T ]'));
  if (teile.length < 3) return (tag: '', monat: '', jahr: '');
  String tag, monat, jahr;
  if (teile[0].length == 4) {
    jahr = teile[0];
    monat = teile[1];
    tag = teile[2].length > 2 ? teile[2].substring(0, 2) : teile[2];
  } else {
    tag = teile[0];
    monat = teile[1];
    jahr = teile[2];
  }
  if (jahr.length != 4 || int.tryParse(jahr) == null) return (tag: '', monat: '', jahr: '');
  if (int.tryParse(tag) == null || int.tryParse(monat) == null) return (tag: '', monat: '', jahr: '');
  return (tag: tag, monat: monat, jahr: jahr);
}

/// Baut die Werte für das Kündigungsformular.
///
/// [stammdaten] ist die Antwort von `user_details.php` (Stufe 1),
/// [vertrag] die Zeile aus `mitglied_vertraege`.
Map<String, String> kuendigungAutofill({
  Map<String, dynamic>? stammdaten,
  Map<String, dynamic>? vertrag,
}) {
  final q = [stammdaten];

  final vorname = _feld(q, 'vorname');
  final vorname2 = _feld(q, 'vorname2');
  final geb = geburtsdatumZerlegen(_feld(q, 'geburtsdatum'));

  // ⚠️ Straße und Hausnummer bleiben GETRENNT. Das Praxis-Portal hat ein
  // einziges Feld und bekommt sie zusammengesetzt; o2 hat `address.street`
  // und `address.houseNumber` als eigene Felder. Zusammengeklebt stünde die
  // Hausnummer zweimal in der Straße und das eigene Feld bliebe leer.
  final strasse = _feld(q, 'strasse');
  final hausnummer = _feld(q, 'hausnummer');

  // ⚠️ Die Rufnummer des VERTRAGS, nicht die private Mobilnummer des
  // Mitglieds. Gekündigt wird die Nummer, die im Vertrag steht — die beiden
  // sind oft verschieden, und eine falsche Rufnummer kündigt entweder nichts
  // oder den falschen Anschluss. Nur wenn der Vertrag keine trägt, wird auf
  // die Stammdaten zurückgefallen.
  final vertragsNummer = _feld([vertrag], 'telefonnummer');
  final telMobil = _feld(q, 'telefon_mobil');
  final telFix = _feld(q, 'telefon_fix');

  return {
    'vorname': [vorname, vorname2].where((s) => s.isNotEmpty).join(' '),
    'nachname': _feld(q, 'nachname'),
    'geb_tag': geb.tag,
    'geb_monat': geb.monat,
    'geb_jahr': geb.jahr,
    'email': kKuendigungBestaetigungMail,
    'telefon': telMobil.isNotEmpty ? telMobil : telFix,
    'plz': _feld(q, 'plz'),
    'ort': _feld(q, 'ort'),
    'strasse': strasse,
    'hausnummer': hausnummer,
    'land': 'Deutschland',
    // ⚠️ Auf einem Kündigungsformular wird KEIN Häkchen gesetzt. Beim
    // Praxisportal ist das Häkchen die Datenschutzerklärung, ohne die kein
    // Termin zustande kommt; hier steht an derselben Stelle die
    // Werbeeinwilligung — gemessen bei 1&1 und WEtell.
    'einwilligung_ankreuzen': 'nein',
    'kundennummer': _feld([vertrag], 'kundennummer'),
    'rufnummer': vertragsNummer.isNotEmpty
        ? vertragsNummer
        : (telMobil.isNotEmpty ? telMobil : telFix),
  };
}

/// Welche Pflichtangaben des Formulars fehlen — für den Hinweis, bevor die
/// Seite aufgeht.
///
/// ⚠️ Es geht nicht darum, das Öffnen zu verhindern: fehlende Werte trägt man
/// von Hand nach. Es geht darum, dass man es **vorher** weiß und nicht erst
/// vor dem abgeschickten Formular steht.
List<String> kuendigungFehlendePflichtfelder(Map<String, String> werte) {
  const pflicht = {
    'vorname': 'Vorname',
    'nachname': 'Nachname',
    'kundennummer': 'Kundennummer',
    'rufnummer': 'Rufnummer',
  };
  return pflicht.entries
      .where((e) => (werte[e.key] ?? '').isEmpty)
      .map((e) => e.value)
      .toList();
}
