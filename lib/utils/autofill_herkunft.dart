/// Herkunftsbindung für das Auto-Ausfüllen von Zugangsdaten im [WebViewScreen].
///
/// Die Regel lautet: **Zugangsdaten gehören zu genau einer Herkunft**, nämlich
/// der des URL, mit dem der Bildschirm geöffnet wurde. Alle vier Aufrufer
/// (Jasmina, Deutsche Post, servdiscount, Versicherungsportale in
/// `finanzen_kredit`) reichen URL und Zugangsdaten aus demselben Datensatz
/// herein — die richtige Herkunft muss also nirgends gepflegt werden, sie steht
/// schon da.
///
/// Warum das hier und nicht im Bildschirm steht: der eigentliche Schutz ist
/// eine Handvoll Zeichenkettenlogik, an der eine Unachtsamkeit nicht auffällt.
/// Als freie Funktionen lässt sie sich geradeheraus prüfen; als private
/// Methoden eines `State` nicht.
library;

import 'dart:convert';

/// Erwartete Herkunft im Format von `location.host`: Hostname klein
/// geschrieben, Port nur wenn er vom Standard abweicht.
///
/// `null` heißt „hier wird nichts eingetragen" — entweder ist der URL
/// unbrauchbar, oder er liegt nicht auf HTTPS.
///
/// ⚠️ Kein Rückfall auf `http`. `usesCleartextTraffic="false"` im Manifest
/// deckt nur Android ab; WebView2 unter Windows und WKWebView unter macOS laden
/// eine Klartextseite anstandslos, und dort stünde das Passwort dann im Netz.
String? autofillHerkunft(String? url) {
  if (url == null || url.trim().isEmpty) return null;
  final u = Uri.tryParse(url.trim());
  if (u == null || u.host.isEmpty) return null;
  if (u.scheme.toLowerCase() != 'https') return null;
  final host = u.host.toLowerCase();
  // `Uri.port` liefert bei fehlender Portangabe den Standardport, `hasPort`
  // unterscheidet die beiden Fälle. `location.host` lässt den Standardport weg,
  // ein ausdrückliches `:443` muss hier also genauso verschwinden.
  return u.hasPort && u.port != 443 ? '$host:${u.port}' : host;
}

/// Wert als JS-Stringliteral.
///
/// `jsonEncode` erzeugt bereits ein gültiges, doppelt gequotetes Literal und
/// behandelt Anführungszeichen, Backslashes und Steuerzeichen vollständig.
///
/// ⚠️ Der Vorgänger maskierte von Hand nur `\` und `'`. Ein Zeilenumbruch im
/// Passwort — in einem erzeugten Passwort keine Seltenheit — zerriss damit das
/// Literal; das Skript brach mit einem Syntaxfehler ab, und für den Benutzer
/// sah es aus, als sei das Auto-Ausfüllen kaputt.
///
/// U+2028/U+2029 sind in JSON erlaubt, gelten aber vor ES2019 als
/// Zeilenendezeichen. `minSdk = 24` reicht bis Android 7 zurück, wo eine nie
/// aktualisierte System-WebView stecken kann — deshalb ausdrücklich maskiert.
///
/// ⚠️ Die beiden Zeichen stehen als Escape-Sequenz da, nicht als Literal. Als
/// Literal wären es unsichtbare Zeichen mitten im Quelltext; ein Editor oder
/// ein Kopiervorgang macht daraus lautlos ein Leerzeichen — und dann ersetzte
/// diese Zeile jedes Leerzeichen im Passwort. Beim Schreiben dieser Zeile ist
/// genau das einmal passiert.
String jsLiteral(String s) => jsonEncode(s)
    .replaceAll('\u2028', '\\u2028')
    .replaceAll('\u2029', '\\u2029');

/// Rückgabewerte des eingespritzten Skripts.
class AutofillErgebnis {
  /// Seite ist nicht HTTPS.
  static const int keinTls = -1;

  /// Seite gehört nicht zur erwarteten Herkunft.
  static const int falscheHerkunft = -2;

  /// Kein Anmeldeformular auf der Seite (noch nicht geladen?) — erneut versuchen.
  static const int keinFormular = 0;
}

/// Baut das Skript, das die Zugangsdaten einträgt.
///
/// ⚠️ **Die Herkunftsprüfung steht im Skript, nicht auf Dart-Seite.** Das ist
/// der Kern der Sache und keine Stilfrage:
///
///  * `location` ist im HTML-Standard `[LegacyUnforgeable]` — die Eigenschaft
///    ist nicht überschreibbar, eine Seite kann über ihre eigene Adresse also
///    nicht lügen. Was das Skript dort liest, ist die Wahrheit.
///  * Die Prüfung ist damit **untrennbar** vom Eintragen: gleiches Skript,
///    gleicher Lauf, gleiches Dokument. Zwischen „geprüft" und „eingetragen"
///    passt keine Weiterleitung mehr.
///  * Auf Dart-Seite gäbe es diese Sicherheit nicht. `webview_windows` liefert
///    bei `navigationCompleted` **keinen** URL mit; der käme aus dem separaten
///    `url`-Stream, dessen Reihenfolge dazu nicht zugesichert ist. Wir würden
///    also womöglich die **vorige** Herkunft prüfen, während die neue Seite
///    schon steht — genau das Loch, das hier zugehen soll.
///
/// `runJavaScript` läuft nur im Hauptrahmen (Android `evaluateJavascript`,
/// WKWebView `forMainFrameOnly`), `document.querySelector` greift also nicht in
/// fremde iframes hinein. Die geprüfte `location` ist damit dieselbe, in der
/// auch eingetragen wird.
String autofillSkript({
  required String herkunft,
  required String benutzer,
  required String passwort,
}) {
  final jsHerkunft = jsLiteral(herkunft);
  final jsUser = jsLiteral(benutzer);
  final jsPass = jsLiteral(passwort);
  return '''
(function() {
  // `location` ist [LegacyUnforgeable] — die Seite kann diesen Wert nicht
  // fälschen. Erst prüfen, dann anfassen; beides im selben Lauf.
  if (location.protocol !== 'https:') return ${AutofillErgebnis.keinTls};
  if (String(location.host).toLowerCase() !== $jsHerkunft) return ${AutofillErgebnis.falscheHerkunft};

  function setNativeValue(el, val) {
    var setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
    setter.call(el, val);
    el.dispatchEvent(new Event('input', {bubbles: true}));
    el.dispatchEvent(new Event('change', {bubbles: true}));
    el.dispatchEvent(new KeyboardEvent('keydown', {bubbles: true}));
    el.dispatchEvent(new KeyboardEvent('keyup', {bubbles: true}));
  }

  // Das Passwortfeld ist das, was ein Anmeldeformular überhaupt erst zu einem
  // macht. Fehlt es, wird NICHTS eingetragen — sonst landet der Benutzername
  // auf einer beliebigen Seite im Suchfeld, und weil wir `input` auslösen,
  // schickt eine Suche-beim-Tippen ihn als Suchbegriff zum Server.
  var passField = document.querySelector('input[type="password"]');
  if (!passField) return ${AutofillErgebnis.keinFormular};

  var userField = document.querySelector('input[type="email"]')
    || document.querySelector('input[name*="user" i]')
    || document.querySelector('input[name*="email" i]')
    || document.querySelector('input[name*="login" i]')
    || document.querySelector('input[autocomplete="username"]')
    || document.querySelector('input[autocomplete="email"]')
    || document.querySelector('input[id*="email" i]')
    || document.querySelector('input[id*="user" i]')
    || document.querySelector('input[placeholder*="email" i]')
    || document.querySelector('input[placeholder*="E-Mail" i]')
    || document.querySelector('input[type="text"]');

  var filled = 0;
  if (userField) {
    userField.focus();
    setNativeValue(userField, $jsUser);
    userField.blur();
    filled++;
  }
  passField.focus();
  setNativeValue(passField, $jsPass);
  passField.blur();
  filled++;
  return filled;
})();
''';
}
