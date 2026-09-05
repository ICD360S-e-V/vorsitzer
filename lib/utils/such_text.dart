/// Faltet einen Namen oder eine Mitgliedsnummer auf eine Form, mit der sich
/// vergleichen lässt: Kleinschreibung, keine diakritischen Zeichen.
///
/// ⚠️ WARUM DAS NÖTIG IST: die Mitglieder heißen Țănase, Grădinar, Müller und
/// Öztürk. Wer die Häkchen nicht auf der Tastatur hat — und das ist am Telefon
/// die Regel — findet sie mit einem einfachen `contains` nie. Ein Suchfeld,
/// das den gesuchten Namen nicht findet, ist schlimmer als keins: man scrollt
/// dann trotzdem, nur nachdem man erst getippt hat.
///
/// ⚠️ RUMÄNISCH HAT ZWEI SCHREIBWEISEN FÜR DENSELBEN BUCHSTABEN. Richtig ist
/// das Komma darunter (`ș` U+0219, `ț` U+021B), in älteren Datenbeständen
/// steht aber die Cedille (`ş` U+015F, `ţ` U+0163) — dieselbe Person, zwei
/// Bytefolgen. Beide müssen hier auf `s` und `t` fallen, sonst hängt das
/// Finden eines Mitglieds davon ab, mit welcher Tastatur sein Name irgendwann
/// eingetragen wurde.
const Map<String, String> _ersatz = {
  // Deutsch
  'ä': 'a', 'ö': 'o', 'ü': 'u', 'ß': 'ss',
  // Rumänisch — Komma darunter UND Cedille, siehe oben
  'ă': 'a', 'â': 'a', 'î': 'i', 'ș': 's', 'ş': 's', 'ț': 't', 'ţ': 't',
  // Türkisch — das punktlose ı ist ein eigener Buchstabe, kein verunglücktes i
  'ı': 'i', 'ğ': 'g', 'ç': 'c',
  // Polnisch
  'ą': 'a', 'ę': 'e', 'ł': 'l', 'ń': 'n', 'ó': 'o',
  'ś': 's', 'ź': 'z', 'ż': 'z', 'ć': 'c',
  // Was sonst noch in Namen vorkommt
  'à': 'a', 'á': 'a', 'å': 'a', 'ã': 'a',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'ï': 'i',
  'ò': 'o', 'ô': 'o', 'õ': 'o', 'ø': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u',
  'ñ': 'n', 'ý': 'y', 'ÿ': 'y', 'đ': 'd', 'ð': 'd', 'þ': 't',
  'č': 'c', 'š': 's', 'ž': 'z', 'ě': 'e', 'ř': 'r', 'ů': 'u',
};

/// Kleinschreibung, kombinierende Zeichen weg, dann die Tabelle oben.
///
/// ⚠️ Die kombinierenden Zeichen (U+0300–U+036F) müssen mit weg, weil dieselbe
/// Schreibweise auf zwei Wegen entstehen kann: `ö` ist entweder ein Zeichen
/// (U+00F6) oder ein `o` mit angehängtem Trema (U+006F U+0308). Auf dem
/// Bildschirm nicht zu unterscheiden, für `==` zwei verschiedene Texte. Dazu
/// kommt ein Sonderfall: `İ` wird von `toLowerCase()` zu `i` PLUS Punkt, also
/// genau so einem angehängten Zeichen.
String suchText(String roh) {
  final b = StringBuffer();
  for (final code in roh.toLowerCase().runes) {
    if (code >= 0x0300 && code <= 0x036F) continue;
    final z = String.fromCharCode(code);
    b.write(_ersatz[z] ?? z);
  }
  return b.toString();
}

/// Passt der Suchbegriff auf das Feld?
///
/// ⚠️ JEDES WORT MUSS VORKOMMEN, DIE REIHENFOLGE NICHT STIMMEN. Im Verzeichnis
/// steht „Ionut Doe"; getippt wird genauso oft „doe ionut", weil man den
/// Nachnamen zuerst im Kopf hat. Ein `contains` über den ganzen Begriff findet
/// das nicht und sieht dabei aus, als gäbe es das Mitglied nicht.
bool suchTreffer(String feld, String begriff) {
  final worte = suchText(begriff).split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (worte.isEmpty) return true;
  final heu = suchText(feld);
  return worte.every(heu.contains);
}
