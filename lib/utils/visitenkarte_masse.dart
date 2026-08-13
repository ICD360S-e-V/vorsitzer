/// Die Maße der Visitenkarte — **einmal**, für Bildschirm und Druck.
///
/// ## ⚠️ Warum das eine eigene Datei ist
///
/// Die Karte gibt es zweimal: als Widget und als PDF-Bogen. Beide hatten ihre
/// eigenen Zahlen, und beim Nachmessen am 13.08.2026 kam heraus, wie weit sie
/// auseinandergelaufen waren:
///
/// | Element | Druck | Bildschirm soll | war | Abweichung |
/// |---|---|---|---|---|
/// | Vereinsname | 13 pt | 25,9 px | 21 px | −19 % |
/// | Slogan | 7 pt | 13,9 px | 10,5 px | −25 % |
/// | Sprachkürzel | 7 pt | 13,9 px | 8,5 px | **−39 %** |
/// | Tealbalken | 6 mm | 33,9 px | 22 px | **−35 %** |
///
/// Das war keine Vorschau mehr, sondern eine zweite Gestaltung. Wer die Karte
/// auf dem Schirm abnimmt und dann druckt, bekommt etwas anderes als das, was
/// er abgenommen hat — und merkt es erst auf Papier.
///
/// ## Die Einheit ist der **PDF-Punkt**
///
/// Nicht Millimeter, obwohl das naheliegender klänge: Schriftgrößen sind in
/// Punkt gebräuchlich, und der PDF-Erzeuger rechnet ohnehin in Punkt. Die
/// Karte ist 85 × 55 mm = **241,0 × 155,9 pt**.
///
/// * Der Druck nimmt diese Werte **unverändert**.
/// * Der Bildschirm rechnet um: `px = pt × (Kartenbreite / 241)`. Bei 480 px
///   Kartenbreite ist der Faktor 1,992.
///
/// Damit stimmen die Verhältnisse in beiden Welten auf die Stelle genau, und
/// eine Änderung wirkt an beiden Stellen zugleich.
library;

import 'package:pdf/pdf.dart' show PdfPageFormat;

/// Ein Millimeter in PDF-Punkten (72 / 25,4).
const double mmInPt = PdfPageFormat.mm;

/// 85 × 55 mm, das übliche Kartenformat in Deutschland.
const double kKarteBreitePt = 85 * mmInPt;   // 240,94
const double kKarteHoehePt = 55 * mmInPt;    // 155,91

/// Der Umrechnungsfaktor für den Bildschirm.
///
/// [kartenBreite] ist die Breite, mit der das Widget die Karte zeichnet.
double bildschirmSkala(double kartenBreite) => kartenBreite / kKarteBreitePt;

// ── Flächen und Ränder ──────────────────────────────────────────────────────

/// Der Tealbalken an der Stange. 6 mm von 85 mm sind rund 7 % Farbfläche —
/// die Begründung steht in visitenkarte_farben.dart.
const double kBalkenBreite = 6 * mmInPt;

/// Sicherheitsabstand ringsum. Druckereien nennen 3 mm als Minimum und 5 mm
/// als das Bessere; bei einem Bogen, den jemand mit der Schere schneidet, ist
/// das Bessere die richtige Wahl.
const double kPolster = 5 * mmInPt;

// ── Schriftgrade ────────────────────────────────────────────────────────────
//
// ⚠️ **Nichts unter 7 pt.** Das ist der übereinstimmende Rat der Druckereien;
// darunter wird es auf Papier unleserlich — und zwar für genau die Menschen,
// für die dieser Verein da ist. Die übliche Staffelung dazu: Name 9–12 pt,
// Funktion und Kontaktdaten 7–8 pt.

const double kGradVereinsname = 13;
const double kGradSlogan = 7;
const double kGradName = 11;
const double kGradAmt = 8;
const double kGradKontakt = 8;
const double kGradFussNummer = 7;
const double kGradFussWeb = 8;
const double kGradSprachKuerzel = 7;

/// Zeilenhöhe als Vielfaches des Schriftgrads.
///
/// ⚠️ Muss auf dem Bildschirm **ausdrücklich** gesetzt werden. Flutter nimmt
/// sonst die Metrik der jeweiligen Systemschrift, und die ist großzügiger als
/// die des PDF-Erzeugers: mit sonst gleichen Größen kam die Karte auf 339
/// statt 310,6 px, also 9 % zu hoch. Ein fester Wert macht die Höhe außerdem
/// unabhängig davon, welche Schrift auf dem jeweiligen Gerät eingestellt ist.
const double kZeilenHoehe = 1.1;

// ── Einzelteile ─────────────────────────────────────────────────────────────

/// Der Strich unter dem Vereinsnamen.
const double kLinieBreite = 24;
const double kLinieHoehe = 1.4;

/// Das Sinnbild in einer Kontaktzeile und die Spalte, in der es sitzt.
const double kIkoneKontakt = 8.5;
const double kSpalteIkone = 13;

/// Rollstuhlzeichen, Fahne und deren Abstände im Sprachblock.
const double kGradRollstuhl = 11;
const double kFahneBreite = 12;
const double kFahneHoehe = 8;
const double kFahneAbstand = 3;

/// Der Globus vor der Web-Adresse.
const double kIkoneWeb = 8;

/// Kantenlänge des QR-Feldes.
///
/// ⚠️ Gerechnet, nicht gewählt: der MECARD dieser Karte ergibt 49 × 49 Module,
/// bei 20 mm sind das 0,41 mm je Modul. Unter etwa 0,4 mm verläuft die Tinte
/// eines Tintendruckers auf Normalpapier so weit, dass benachbarte Module
/// zusammenlaufen — der Code wäre dann nicht schlecht lesbar, sondern tot.
/// Ein Test in visitenkarte_pdf_test.dart hält die Schwelle.
const double kQrKante = 20 * mmInPt;

// ── Abstände ────────────────────────────────────────────────────────────────

const double kAbstandNameLinie = 2.5;
const double kAbstandLinieSlogan = 4;
const double kAbstandNameAmt = 4;
const double kAbstandAmtKontakt = 6;
const double kAbstandKontaktZeilen = 4;
const double kAbstandQrSpalte = 6;
