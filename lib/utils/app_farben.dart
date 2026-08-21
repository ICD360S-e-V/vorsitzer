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

  /// ⚠️ Wird ausschliesslich aus `MaterialApp.builder` und aus
  /// `AppTheme._bauen` gesetzt. Sonst nirgends — wer diesen Wert von Hand
  /// umlegt, färbt den nächsten Bildschirm falsch ein, ohne dass das Thema
  /// davon erfährt.
  static bool istDunkel = false;

  static bool get _dunkel => istDunkel;

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
}
