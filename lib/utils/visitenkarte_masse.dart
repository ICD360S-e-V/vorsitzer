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
const double kGradRollstuhl = 9;
const double kFahneBreite = 12;
const double kFahneHoehe = 8;
const double kFahneAbstand = 3;

/// Abstand zwischen Rollstuhlzeichen und Fahnenreihe.
///
/// ⚠️ Knapp gerechnet: der Sprachblock ist das höchste Element der Kopfzeile
/// und bestimmt damit, wie viel Höhe für alles Übrige bleibt. Beim Einbau der
/// vierten Kontaktzeile (Fax) und des größeren QR-Feldes fehlten am Ende
/// wenige Punkte — sie kamen von hier.
///
/// Seit die Kürzel unter den Fahnen entfallen sind, ist der Block 7,5 pt
/// flacher; die Höhe kommt dem Satz darunter zugute, nicht dem Abstand hier.
const double kAbstandRollstuhlFahnen = 1.5;

/// Der Globus vor der Web-Adresse.
const double kIkoneWeb = 8;

/// Kantenlänge des QR-Feldes.
///
/// ⚠️ Gerechnet, nicht gewählt. Die vCard dieser Karte ergibt **69 × 69
/// Module**; bei Stufe L 61 Module, bei 24 mm also 0,39 mm je Modul.
///
/// Der Wert ist am 14.08.2026 von 20 auf 25 mm gewachsen, weil die Nutzlast von
/// MECARD auf vCard 3.0 gewechselt ist — nur vCard kennt ein Faxfeld
/// (`TEL;TYPE=WORK,FAX`), damit das Telefon beim Scannen weiß, welche der drei
/// Nummern ein Faxgerät ist.
///
/// 25 mm ist das obere Ende der Spanne, die Druck- und QR-Anbieter für
/// Visitenkarten nennen (20–25 mm); für Nutzlasten von 150–300 Zeichen gilt
/// „2 × 2 cm oder größer" als zuverlässig. Mehr geht auf 85 mm Breite nicht,
/// ohne die Kontaktzeilen zu erdrücken: es bleiben dann noch 42 mm für
/// „+49 731 80159736", das bei 8 pt rund 33 mm braucht.
///
/// ⚠️ Der frühere Richtwert von 0,40 mm je Modul ließ sich mit dem Faxfeld
/// nicht halten. Wer die vCard weiter auffüllt, macht den Code dichter — ein
/// Test hält die Schwelle, aber die einzige belastbare Probe bleibt ein
/// **echtes Telefon**.
const double kQrKante = 24 * mmInPt;

// ── Abstände ────────────────────────────────────────────────────────────────

// ⚠️ Diese Werte sind knapp gerechnet, nicht großzügig gewählt.
//
// Mit der vierten Kontaktzeile (Fax) kam der Satz auf rund 141 pt bei 127,6 pt
// verfügbarer Höhe — und der `Column` des PDF-Erzeugers wirft Überzähliges
// **stillschweigend** weg. Im Ausdruck fehlten schlagartig alle Kontaktzeilen,
// die Fußzeile und der QR, ohne Fehler und ohne Warnung. Aufgefallen ist es
// nur, weil der Erzeugungslauf seither mit `pdftotext` nachzählt, ob jedes
// Feld zehnmal auf dem Bogen steht.
//
// Wer hier etwas vergrößert oder eine fünfte Zeile hinzufügt, prüft das
// genauso nach. Die Zahlen sind das Ergebnis von Messen, nicht von Schätzen.
const double kAbstandNameLinie = 2;
const double kAbstandLinieSlogan = 3;
const double kAbstandNameAmt = 3;
const double kAbstandAmtKontakt = 3;
const double kAbstandKontaktZeilen = 2;
const double kAbstandQrSpalte = 6;
