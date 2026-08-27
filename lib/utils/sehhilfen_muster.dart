/// Die drei Verordnungsvordrucke des Hilfsmittel-Reiters.
///
/// Sehhilfen SIND Hilfsmittel (§ 33 SGB V, Produktgruppe 25) — sie gehen aber
/// nicht auf Muster 16, sondern auf einen eigenen Vordruck, und sie werden beim
/// Augenoptiker eingelöst, nicht beim Sanitätshaus. Genau diese beiden Punkte
/// standen bis zum 27.08.2026 falsch im Erklärbanner des Reiters.
///
/// ⚠️ [kMusterSchluessel] ist eine Kopie der Whitelist `MUSTER_ERLAUBT` in den
/// sechs `*_hilfsmittel_manage.php` auf dem Server. Das PHP liegt in keinem
/// Repo — `test/sehhilfen_muster_test.dart` ist damit die EINZIGE Stelle, an
/// der ein Auseinanderlaufen überhaupt auffallen kann. Ein unbekannter Wert
/// wird vom Server mit HTTP 400 abgewiesen, nicht still zu `m16` verbogen.
library;

/// Schlüssel, genau wie sie über die Leitung gehen und in der Spalte
/// `muster` (VARCHAR(4), Default `m16`) landen.
const String kMuster16 = 'm16';
const String kMuster8 = 'm8';
const String kMuster8a = 'm8a';

/// Muss zeichengleich zu `MUSTER_ERLAUBT` auf dem Server bleiben.
const List<String> kMusterSchluessel = [kMuster16, kMuster8, kMuster8a];

/// Ein Vordruck mit allem, was das Formular davon braucht.
class MusterVordruck {
  /// Wert der Spalte `muster`.
  final String key;

  /// Kurzname für Chips und Auswahlknöpfe.
  final String kurz;

  /// Was der Vordruck verordnet.
  final String titel;

  /// Ein Satz Begründung — steht als Hinweis über dem Formular.
  final String hinweis;

  /// Wo das Rezept eingelöst wird. Muster 16 → Sanitätshaus, Sehhilfen →
  /// Augenoptiker. Steht im Hinweis und erklärt die Chronologie-Schritte.
  final String einloesestelle;

  /// Vorbelegung des Feldes „Verordnetes Hilfsmittel".
  final String vorschlag;

  /// Ob das Formular „Anzahl Paare / Wechselversorgung" zeigt. Das ist eine
  /// Einlagen-Frage (zwei Paar aus hygienischen Gründen) und bei Sehhilfen
  /// sinnlos.
  final bool zeigtAnzahlPaare;

  const MusterVordruck({
    required this.key,
    required this.kurz,
    required this.titel,
    required this.hinweis,
    required this.einloesestelle,
    required this.vorschlag,
    required this.zeigtAnzahlPaare,
  });
}

const List<MusterVordruck> kMusterVordrucke = [
  MusterVordruck(
    key: kMuster16,
    kurz: 'Muster 16',
    titel: 'Hilfsmittel allgemein',
    hinweis: 'Körpernahe Hilfen, die beim Mitglied bleiben — Einlagen (PG 08), '
        'Bandagen (PG 05), Hörgeräte (PG 13), Blindenhilfsmittel (PG 07). '
        'Zuzahlung 10 %, mindestens 5 €, höchstens 10 € pro Stück.',
    einloesestelle: 'Sanitätshaus',
    vorschlag: 'Orthopädische Einlagen',
    zeigtAnzahlPaare: true,
  ),
  MusterVordruck(
    key: kMuster8,
    kurz: 'Muster 8',
    titel: 'Sehhilfen (grüner Vordruck)',
    hinweis: 'Brillengläser, Kontaktlinsen und therapeutische Sehhilfen '
        '(§§ 13–15, § 17 HilfsM-RL). Die Kasse zahlt die Gläser bis zum '
        'Festbetrag — die Fassung nie.',
    einloesestelle: 'Augenoptiker',
    vorschlag: 'Brillengläser',
    zeigtAnzahlPaare: false,
  ),
  MusterVordruck(
    key: kMuster8a,
    kurz: 'Muster 8A',
    titel: 'Vergrößernde Sehhilfen (gelber Vordruck)',
    hinweis: 'Lupen, Lupengläser, Fernrohrlupenbrillen und elektronische '
        'Lesegeräte (§ 16 HilfsM-RL). Nur mit augenärztlich bestimmtem und '
        'dokumentiertem Vergrößerungsbedarf.',
    einloesestelle: 'Augenoptiker',
    vorschlag: 'Vergrößernde Sehhilfe',
    zeigtAnzahlPaare: false,
  ),
];

/// Der Vordruck zu einem Schlüssel; unbekannt oder leer → Muster 16.
///
/// Der Rückfall ist hier richtig und auf dem Server falsch: die Anzeige muss
/// auch einen Datensatz darstellen können, den eine neuere Fassung geschrieben
/// hat, während das Speichern einen unbekannten Wert abweisen muss.
MusterVordruck musterVordruck(String? key) => kMusterVordrucke.firstWhere(
      (m) => m.key == key,
      orElse: () => kMusterVordrucke.first,
    );

/// Eine wählbare Indikation: Kurztext plus die Fundstelle, die im Formular
/// dort steht, wo bei Muster 16 der ICD-10-Code steht.
class MusterIndikation {
  /// Landet in `diagnose_icd10` — bei Sehhilfen die Fundstelle statt eines
  /// ICD-Codes, weil der Anspruch dort aus der Richtlinie folgt und nicht aus
  /// einer Diagnoseziffer.
  final String ref;

  /// Landet in `diagnose_label`.
  final String label;

  /// Zwischenüberschrift, unter der der Eintrag steht. Leer = keine.
  ///
  /// ⚠️ Bei Muster 8 ist das keine Kosmetik: die Liste trägt ZWEI Anspruchs-
  /// wege, die nach ganz verschiedenen Regeln funktionieren (§ 12 nach Alter
  /// und Dioptrien, § 17 allein nach Diagnose). Flach untereinander sieht das
  /// aus wie eine einzige Liste gleichrangiger Fälle — und genau die
  /// Verwechslung kostet einen Anspruch, wenn jemand bei −2 dpt aufhört zu
  /// lesen, obwohl der therapeutische Teil darunter für ihn gilt.
  final String gruppe;

  const MusterIndikation(this.ref, this.label, [this.gruppe = '']);
}

/// Muster 16 — die orthopädischen Regelfälle des Reiters, unverändert.
const List<MusterIndikation> kIndikationenMuster16 = [
  MusterIndikation('M21.4', 'Senk-/Spreiz-/Knickfuß'),
  MusterIndikation('M20.1', 'Hallux valgus'),
  MusterIndikation('M72.2', 'Plantarfasziitis (Fersensporn)'),
  MusterIndikation('E10/E11', 'Diabetes — Diabetiker-Einlagen'),
  MusterIndikation('M41/M21.7', 'Skoliose / Beinlängendifferenz'),
];

/// Muster 8 — erst die drei Wege zum Anspruch auf sehschärfenverbessernde
/// Sehhilfen (§ 12 Abs. 1), dann die therapeutischen Fälle (§ 17).
///
/// ⚠️ Die Trennung ist der Kern des Vordrucks: § 12 hängt an Alter und
/// Dioptrien, § 17 an der Diagnose — **ohne** Altersgrenze und **ohne**
/// Dioptrienschwelle. Wer mit 40 und −2 dpt keine Brille bezahlt bekommt, hat
/// bei Amblyopie trotzdem Anspruch auf Okklusionspflaster.
///
/// ⚠️ Die Zahlen sind die der Richtlinie, nicht die des Gesetzes: § 33 Abs. 2
/// SGB V sagt „mehr als 6" bzw. „mehr als 4" Dioptrien, § 12 Abs. 1 Nr. 3
/// HilfsM-RL setzt das als ≥ 6,25 bzw. ≥ 4,25 um (Gläser gibt es in
/// 0,25er-Schritten). Auf dem Rezept steht die Richtlinien-Schwelle.
const List<MusterIndikation> kIndikationenMuster8 = [
  // ── Sehschärfe, § 12 Abs. 1 ──
  MusterIndikation('§ 12 Abs. 1 Nr. 1', 'Unter 18 Jahren — ohne weitere Voraussetzung', 'Sehschärfe verbessern — Anspruch nach § 12 Abs. 1'),
  MusterIndikation('§ 12 Abs. 1 Nr. 3', 'Fernkorrektur ≥ 6,25 dpt (Myopie/Hyperopie)'),
  MusterIndikation('§ 12 Abs. 1 Nr. 3', 'Fernkorrektur ≥ 4,25 dpt (Astigmatismus)'),
  MusterIndikation('§ 12 Abs. 1 Nr. 2', 'Visus ≤ 0,3 am besseren Auge (WHO-Stufe 1)'),
  MusterIndikation('§ 12 Abs. 1 Nr. 2', 'Gesichtsfeld ≤ 10° bei zentraler Fixation'),
  MusterIndikation('§ 15 Abs. 3', 'Kontaktlinsen — eine der 9 Indikationen'),
  // ── Therapeutisch, § 17 Abs. 1 ──
  MusterIndikation('§ 17 Nr. 1', 'Lichtschutzglas ≤ 75 % (Iriskolobom, Albinismus)', 'Therapeutisch nach § 17 — ohne Altersgrenze, ohne Dioptrienschwelle'),
  MusterIndikation('§ 17 Nr. 2', 'UV-Kantenfilter 400 nm (Aphakie, Pseudophakie)'),
  MusterIndikation('§ 17 Nr. 3', 'Bandpassfilter 450 nm (Blauzapfenmonochromasie)'),
  MusterIndikation('§ 17 Nr. 4', 'Kantenfilter > 500 nm (Achromatopsie, Retinopathia pigmentosa)'),
  MusterIndikation('§ 17 Nr. 6', 'Prismen ≥ 3 pdpt horizontal / ≥ 1 pdpt vertikal'),
  MusterIndikation('§ 17 Nr. 7', 'Okklusionsschalen bei bleibenden Doppelbildern'),
  MusterIndikation('§ 17 Nr. 8', 'Bifokalglas mit großem Nahteil (akkommodatives Schielen)'),
  MusterIndikation('§ 17 Nr. 9', 'Okklusionspflaster / -folien (Amblyopietherapie)'),
  MusterIndikation('§ 17 Nr. 10', 'Uhrglasverband bei unvollständigem Lidschluss'),
  MusterIndikation('§ 17 Nr. 11', 'Irislinsen bei Substanzverlust der Iris'),
  MusterIndikation('§ 17 Nr. 12', 'Verbandlinsen / -schalen (Erosion, Keratoplastik)'),
  MusterIndikation('§ 17 Nr. 13', 'Kontaktlinse als Medikamententräger'),
  MusterIndikation('§ 17 Nr. 15', 'Kontaktlinsen bei Keratokonus / nach Keratoplastik'),
  MusterIndikation('§ 17 Nr. 16', 'Kunststoff-Schutzgläser (Epilepsie, funktionell einäugig)'),
];

/// Muster 8A — § 16, nach Vergrößerungsbedarf gestaffelt.
const List<MusterIndikation> kIndikationenMuster8a = [
  MusterIndikation('§ 16 Abs. 3', 'Nähe ≥ 1,5-fach — Hellfeld-, Hand- oder Standlupe', 'Nach augenärztlich bestimmtem Vergrößerungsbedarf (§ 16)'),
  MusterIndikation('§ 16 Abs. 3', 'Nähe — Brillengläser mit Lupenwirkung'),
  MusterIndikation('§ 16 Abs. 3', 'Nähe — Fernrohrlupenbrille (begründeter Einzelfall)'),
  MusterIndikation('§ 16 Abs. 4', 'Nähe ≥ 6-fach — elektronisches Lesegerät'),
  MusterIndikation('§ 16 Abs. 5', 'Ferne — Handfernrohr / Monokular (fokussierbar)'),
];

List<MusterIndikation> musterIndikationen(String? key) => switch (key) {
      kMuster8 => kIndikationenMuster8,
      kMuster8a => kIndikationenMuster8a,
      _ => kIndikationenMuster16,
    };

/// Was im Detail unter „Wiederversorgung" steht.
///
/// ⚠️ Nur Muster 16 hat die 6-Monats-Frist, und nur dort legt der Server ein
/// Erinnerungs-Ticket an. Für Sehhilfen gibt es keine Frist, sondern eine
/// Bedingung — deshalb hier ein Satz statt eines Datums.
String wiederversorgungRegel(String? key) => switch (key) {
      kMuster8 => 'Neuversorgung erst bei einer Refraktionsänderung von '
          '≥ 0,5 dpt (§ 12 Abs. 4 HilfsM-RL). Als 0,5 dpt zählt auch, wenn ein '
          'Auge um 0,25 dpt zu- und das andere um 0,25 dpt abnimmt. Bis zum '
          '14. Geburtstag gilt die Schwelle nicht.',
      kMuster8a => 'Neuversorgung erst bei signifikant geändertem '
          'Vergrößerungsbedarf, neu bestimmt (§ 12 Abs. 5 HilfsM-RL).',
      _ => 'Wiederversorgung frühestens nach 6 Monaten.',
    };

/// Ob für diesen Vordruck ein Wiederversorgungs-Ticket entsteht. Spiegelt die
/// Bedingung `$muster !== 'm16'` im Server-Endpunkt.
bool musterHatWiederversorgungsTicket(String? key) =>
    musterVordruck(key).key == kMuster16;
