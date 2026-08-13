/// Die Farben der Visitenkarte — **einmal**, für Bildschirm und Druck.
///
/// ⚠️ Warum eine eigene Datei: die Karte gibt es zweimal, als Widget und als
/// PDF-Bogen. Stünden die Werte in beiden, wäre der Ausdruck irgendwann eine
/// andere Farbe als die Karte, die man vorher auf dem Schirm abgenommen hat —
/// und man sähe es erst auf Papier. Der PDF-Bauer rechnet diese `Color`-Werte
/// in `PdfColor` um; die Zahl steht nur hier.
///
/// ## ⚠️ Alle Werte sind gemessen, keiner ausgesucht
///
/// Das alte Kartenblau (#4a90d9 → #357abd) ist am 13.08.2026 abgelöst worden,
/// und nicht aus Geschmacksgründen: weiße Schrift darauf ergab **3,34 : 1**.
/// Die WCAG-Stufe AA verlangt 4,5 : 1; für Schrift unter 18 pt werden 7 : 1
/// empfohlen — und eine Visitenkarte besteht ausschließlich aus solcher
/// Schrift. Eine Karte, die der Vorstand eines Vereins von Menschen mit
/// Behinderung weiterreicht, darf nicht die einzige Fläche im Haus sein, die
/// durchfällt.
///
/// Im Druck kommt hinzu, dass Papier, Farbauftrag und Beleuchtung den Kontrast
/// weiter drücken. Bildschirmwerte sind dort nur ein Anhalt, also lieber
/// großzügiger als der Mindestwert.
///
/// ## Der Ton ist kein neuer
///
/// Es ist das Teal der Identitätsgruppe von icd360s.de (`[data-ton="teal"]`,
/// dort für Startseite, Kontakt und Impressum). Karte und Webauftritt zeigen
/// damit denselben Verein. Dass Teal für gemeinnützige Arbeit trägt, ist
/// nebenbei auch die verbreitete Einschätzung in der Markenberatung — kühle
/// Töne stehen für Verlässlichkeit; ausschlaggebend war aber die Messung und
/// die Herkunft aus dem eigenen Auftritt, nicht die Farbpsychologie.
///
/// ⚠️ Wer einen Wert ändert, rechnet nach. `test/visitenkarte_pdf_test.dart`
/// erzwingt das: dort steht die WCAG-Formel, und die Schwellen sind Zusicherung,
/// nicht Kommentar.
library;

import 'package:flutter/painting.dart' show Color;

/// Helles Ende des Verlaufs — der knappste Fall: weiße Schrift 7,17 : 1.
const Color kVkTonHell = Color(0xFF0F6070);

/// Dunkles Ende — weiße Schrift 10,74 : 1.
const Color kVkTonDunkel = Color(0xFF0A4450);

/// Aufgehellte Tealfläche, identisch mit `--ton-flaeche` des Webauftritts.
const Color kVkTonFlaeche = Color(0xFFE6F4F7);

/// Fließtext der Rückseite: 11,50 : 1 auf Weiß, 10,22 : 1 auf [kVkTonFlaeche].
const Color kVkTextDunkel = Color(0xFF243B53);

/// Nebentext: 7,53 : 1 auf Weiß, 6,68 : 1 auf der Tealfläche.
///
/// ⚠️ Nicht durch `Colors.grey.shade600/700` ersetzen. Die kamen auf 4,7 bzw.
/// 5,9 : 1 — auf dem Bildschirm unauffällig, für Schrift dieser Größe zu wenig.
const Color kVkTextLeise = Color(0xFF4A5568);
