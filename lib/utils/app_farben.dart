import 'package:flutter/material.dart';

/// Semantische Farbtokens für Hell- und Dunkelmodus.
///
/// ⚠️ **Warum statisch und nicht über `Theme.of(context)`?**
/// Die Anwendung hat 427.000 Zeilen und rund 11.000 fest verdrahtete Farben,
/// verteilt über 219 Dateien. Ein grosser Teil davon steht in `static`-Methoden,
/// in Hilfsfunktionen ohne `BuildContext` oder in `const`-Konstruktoren. Ein
/// Token, das einen Kontext verlangt, wäre an tausenden Stellen schlicht nicht
/// aufrufbar gewesen — die Umstellung hätte bedeutet, den Kontext durch die
/// halbe Anwendung durchzureichen.
///
/// Deshalb ein globaler Schalter: es gibt genau **eine** [MaterialApp], also
/// genau eine Helligkeit. [istDunkel] wird in `MaterialApp.builder` gesetzt
/// (siehe `main.dart`), bevor irgendein Nachfahre baut. Wechselt der Modus,
/// baut die ganze Anwendung ohnehin neu auf — der Wert steht dann bereits.
///
/// ⚠️ **Chromatische Farben stehen NICHT hier drin.** Rot, Grün, Orange und die
/// Behörden-Hausfarben tragen Bedeutung und werden bewusst nicht umgeschaltet.
/// Umgestellt werden ausschliesslich *neutrale* Farben — Weiss, Schwarz und die
/// Grautöne — denn nur die kippen zwischen den Modi.
class F {
  F._();

  /// ⚠️ Wird ausschliesslich aus `MaterialApp.builder` gesetzt — über
  /// [uebernehmen]. Sonst nirgends.
  static bool istDunkel = false;

  static bool get _dunkel => istDunkel;

  /// Übernimmt die neue Helligkeit und baut den Baum darunter neu auf.
  ///
  /// ⚠️ **Der Neuaufbau ist keine Vorsichtsmassnahme, er ist notwendig.**
  /// Diese Tokens sind keine [InheritedWidget]s — wer `F.flaeche` liest,
  /// „hängt" an nichts und wird von Flutter beim Themenwechsel deshalb auch
  /// nicht neu gebaut. Gemessen in einem Versuch: nach dem Umschalten stand
  /// `istDunkel` korrekt auf `true`, die Fläche war aber unverändert weiss,
  /// weil das Widget schlicht nie wieder gebaut wurde. Auf dem Gerät hiesse
  /// das: man drückt den Knopf, die Material-Farben kippen, und die halbe
  /// Oberfläche bleibt hell stehen, bis man irgendwo hin und zurück
  /// navigiert.
  ///
  /// ⚠️ Bewusst `markNeedsBuild` statt eines wechselnden [Key]s: ein neuer
  /// Schlüssel würde den Teilbaum wegwerfen und neu erzeugen — mitsamt
  /// Navigator-Stapel, Bildlaufständen und halb ausgefüllten Formularen. Hier
  /// bleibt jeder [State] erhalten, es wird nur neu gezeichnet.
  ///
  /// Gibt zurück, ob sich etwas geändert hat — der Aufrufer darf nicht in
  /// jedem Aufbau neu bauen lassen, das wäre eine Schleife.
  static bool uebernehmen(BuildContext kontext, bool dunkel) {
    if (dunkel == istDunkel) return false;
    istDunkel = dunkel;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      void alle(Element el) {
        el.markNeedsBuild();
        el.visitChildren(alle);
      }

      if (kontext is Element && kontext.mounted) alle(kontext);
    });
    return true;
  }

  // ──────────────────────────────────────────────────────────────────
  // Flächen
  // ──────────────────────────────────────────────────────────────────

  /// Hintergrund des [Scaffold] — die tiefste Ebene.
  static Color get hintergrund =>
      _dunkel ? const Color(0xFF131419) : const Color(0xFFF5F5F5);

  /// Karten, Dialoge, Panels — was auf dem Hintergrund liegt.
  /// Ersetzt `Colors.white` in Füll-Rollen.
  static Color get flaeche =>
      _dunkel ? const Color(0xFF1E1F26) : Colors.white;

  /// Leicht abgesetzte Füllung: Eingabefelder, Listenstreifen, Chips.
  /// Ersetzt `Colors.grey.shade50` / `.shade100` / `0xFFF5F5F5`.
  static Color get flaecheGedaempft =>
      _dunkel ? const Color(0xFF262832) : const Color(0xFFF3F4F6);

  /// Stärker abgesetzt: Kopfzeilen von Tabellen, ausgewählte Zeilen.
  /// Ersetzt `Colors.grey.shade200` / `.shade300` in Füll-Rollen.
  static Color get flaecheBetont =>
      _dunkel ? const Color(0xFF313340) : const Color(0xFFE7E9EE);

  // ──────────────────────────────────────────────────────────────────
  // Schrift und Symbole
  // ──────────────────────────────────────────────────────────────────

  /// Fliesstext und Überschriften. Ersetzt `Colors.black87`, `Colors.black`,
  /// `Colors.grey.shade900` / `.shade800` in Schrift-Rollen.
  static Color get textStark =>
      _dunkel ? const Color(0xFFECEDF2) : const Color(0xDD000000);

  /// Beschriftungen, Untertitel. Ersetzt `Colors.black54`,
  /// `Colors.grey.shade700` / `.shade600`.
  static Color get textSchwach =>
      _dunkel ? const Color(0xFFAFB2BF) : const Color(0xFF5A5F6B);

  /// Platzhalter, deaktivierte Zustände. Ersetzt `Colors.black38`,
  /// `Colors.grey.shade500` / `.shade400`, `Colors.grey`.
  static Color get textLeise =>
      _dunkel ? const Color(0xFF80838F) : const Color(0xFF8A8F99);

  // ──────────────────────────────────────────────────────────────────
  // Ränder
  // ──────────────────────────────────────────────────────────────────

  /// Sichtbarer Rand, Trennlinie. Ersetzt `Colors.grey.shade300` in
  /// Rand-Rollen.
  static Color get rand =>
      _dunkel ? const Color(0xFF3A3D4A) : const Color(0xFFD6D9E0);

  /// Zurückhaltender Rand. Ersetzt `Colors.grey.shade200`.
  static Color get randLeise =>
      _dunkel ? const Color(0xFF2C2E39) : const Color(0xFFE7E9EE);

  /// Schattenfarbe. Im Dunkeln trägt ein schwarzer Schatten nichts bei —
  /// er wird tiefer und weicher, statt zu verschwinden.
  static Color get schatten =>
      _dunkel ? const Color(0x8C000000) : const Color(0x1A000000);

  // ──────────────────────────────────────────────────────────────────
  // Modusabhängiges Paar
  // ──────────────────────────────────────────────────────────────────

  /// Im Hellmodus [hell], im Dunkelmodus [dunkel].
  ///
  /// ⚠️ Das ist die Form, in der die Umstellung geschrieben ist — und zwar
  /// aus einem gemessenen Grund. Der erste Anlauf hat die Grautöne auf
  /// wenige sinngebende Tokens zusammengefasst; damit wurde aus
  /// `Colors.grey.shade600` (#757575) im Hellmodus `#5A5F6B`, aus
  /// `Colors.grey.shade100` ein anderes Grau, und so fort. Der Dunkelmodus
  /// stimmte — aber das gewohnte helle Bild hatte sich mitverändert, ohne
  /// dass das jemand verlangt hätte.
  ///
  /// Steht links die **ursprüngliche** Farbe, kann das im Hellmodus gar nicht
  /// mehr passieren: dort wird buchstäblich der alte Wert zurückgegeben. Der
  /// Nachweis ist dann kein Argument, sondern ein Bildvergleich gegen
  /// `origin/main`, der null abweichende Bildpunkte zeigt.
  static Color hd(Color hell, Color dunkel) => _dunkel ? dunkel : hell;

  // ──────────────────────────────────────────────────────────────────
  // Getönte Flächen
  // ──────────────────────────────────────────────────────────────────

  /// Eine Stufe einer Material-Farbe, die den Modus mitmacht.
  ///
  /// ⚠️ Das hier war der grosse blinde Fleck der ersten Fassung. Die Regel
  /// „chromatische Farben bleiben" stimmt für *gesättigte* Farben — ein rotes
  /// Abzeichen, ein grüner Haken lesen sich hell wie dunkel. Sie stimmt aber
  /// **nicht** für die blassen Stufen: `Colors.red.shade50` ist praktisch ein
  /// getöntes Weiss und wird im Dunkelmodus zu einem leuchtenden Fleck.
  /// Gemessen auf einer Testaufnahme: der Hinweiskasten in den Einstellungen
  /// stand mit `(255, 224, 228)` mitten in einer dunklen Fläche, die
  /// ausgewählte Zeile mit `(236, 239, 241)`. Beides fiel erst auf, als das
  /// Bild wirklich angesehen wurde — kein Test hätte das gemeldet.
  ///
  /// Die Zuordnung ist bewusst grob und nur für die Stufen belegt, die auch
  /// wirklich kippen müssen:
  ///
  ///   50 / 100  Fläche  → dunkle Fläche mit einem Hauch derselben Farbe
  ///   200 / 300 Rand    → die dunklen Stufen derselben Farbe
  ///   600 … 900 Schrift → die hellen Stufen, sonst steht dunkle Schrift
  ///                       auf dunklem Grund
  ///
  /// Gesättigte Flächen (`shade600`/`shade700` als Hintergrund, etwa eine
  /// petrolfarbene Kopfzeile mit weisser Schrift) werden **nicht** angefasst:
  /// die tragen in beiden Modi.
  static Color h(MaterialColor farbe, int stufe) {
    if (!_dunkel) return farbe[stufe] ?? farbe;
    switch (stufe) {
      // Blasse Tönungen → dunkle Fläche, die die Farbe nur andeutet.
      case 50:
        return Color.alphaBlend(
            (farbe[200] ?? farbe).withValues(alpha: 0.13), flaeche);
      case 100:
        return Color.alphaBlend(
            (farbe[200] ?? farbe).withValues(alpha: 0.20), flaeche);
      // Ränder.
      case 200:
        return farbe[800] ?? farbe;
      case 300:
        return farbe[700] ?? farbe;
      // Schrift und Sinnbilder.
      case 400:
      case 500:
        return farbe[400] ?? farbe;
      case 600:
      case 700:
        return farbe[300] ?? farbe;
      case 800:
      case 900:
        return farbe[200] ?? farbe;
      default:
        return farbe[stufe] ?? farbe;
    }
  }
}
