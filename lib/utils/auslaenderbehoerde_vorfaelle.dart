/// Vorfalltypen der Ausländerbehörde.
///
/// Die Liste ist aus den Dienstleistungsverzeichnissen echter Behörden
/// zusammengetragen, nicht aus dem Gedächtnis:
///   · Landratsamt Neu-Ulm, „Staatsangehörigkeit und Ausländerrecht"
///   · Stadt Ulm, „Ausländerbehörde — Unsere Dienstleistungen" (service-bw)
///   · Stadt Karlsruhe, Organisationseinheit Ausländerbehörde (38 Positionen,
///     derselbe service-bw-Katalog, den auch Ulm verwendet)
///   · Landeshauptstadt München (Chancenkarte, Dokumentenverlust)
///   · BayernPortal/LeiKa für die kanonischen Bezeichnungen
///
/// ⚠️ Die Schreibweise folgt der baden-württembergischen Form („… beantragen")
/// statt der bayerischen Semikolon-Form („Blaue Karte EU; Beantragung"). Die
/// App bedient beide Länder; als Dropdown-Eintrag liest sich die BW-Form
/// natürlicher und ist in beiden verständlich.
///
/// ⚠️ Einbürgerung steht bewusst NICHT in dieser Liste. Zuständig ist die
/// Staatsangehörigkeitsbehörde — organisatorisch meist dasselbe Haus (Ulm nennt
/// sich „Ausländer- und Einbürgerungsbehörde", Neu-Ulm führt den Fachbereich als
/// „Staatsangehörigkeits- und Ausländerrecht"), aber mit eigenem Ghișeu und in
/// Ulm sogar eigenen Öffnungszeiten. Diese Vorgänge gehören in den Reiter
/// „Landratsamt" (siehe [landratsamt_antraege.dart], Gruppe kLraAusland), sonst
/// steht später die falsche Behörde im Anschreiben.
library;

/// Wie lange im Voraus an den Ablauf erinnert werden soll.
///
/// ⚠️ Ein einziger Wert für alles wäre falsch. Eine Fiktionsbescheinigung gilt
/// oft nur drei Monate — bei 90 Tagen Vorwarnung stünde die Warnung schon am
/// Ausstellungstag. Ein Aufenthaltstitel braucht dagegen die langen 90 Tage,
/// weil die Verlängerung VOR Ablauf beantragt sein muss; wer das verpasst,
/// braucht ausgerechnet die kurzlebige Fiktionsbescheinigung.
class AbFrist {
  /// Tage vor Ablauf, ab denen gewarnt wird.
  final int vorwarnungTage;

  /// Was die Person in der Hand hält. Leer = der Vorgang erzeugt kein
  /// eigenes Dokument mit Ablaufdatum.
  final String dokument;

  /// Übliche Laufzeit — Anzeigetext, keine Rechnung.
  final String laufzeit;

  const AbFrist({
    required this.vorwarnungTage,
    required this.dokument,
    required this.laufzeit,
  });
}

/// Aufenthaltstitel als Karte: lange Vorlaufzeit, weil die Verlängerung vor
/// Ablauf beantragt sein muss.
const kAbFristTitel = AbFrist(
  vorwarnungTage: 90,
  dokument: 'Elektronischer Aufenthaltstitel (eAT-Karte)',
  laufzeit: 'befristet, zweckabhängig — meist 1 bis 4 Jahre',
);

/// ⚠️ Der Titel ist unbefristet, die KARTE nicht. Sie läuft in der Regel nach
/// zehn Jahren ab (bei Minderjährigen früher). Wer hier nicht erinnert, merkt
/// den fälligen Kartentausch nicht.
const kAbFristKarteUnbefristet = AbFrist(
  vorwarnungTage: 90,
  dokument: 'Elektronischer Aufenthaltstitel (eAT-Karte)',
  laufzeit: 'Titel unbefristet — die Karte selbst läuft ab (meist 10 Jahre)',
);

/// ⚠️ Die kürzeste und riskanteste Frist im ganzen Katalog. Das Gesetz nennt
/// für § 81 Abs. 5 AufenthG keine Dauer; die Behörde entscheidet nach Ermessen,
/// üblich sind drei, seltener sechs Monate.
const kAbFristFiktion = AbFrist(
  vorwarnungTage: 21,
  dokument: 'Fiktionsbescheinigung (§ 81 Abs. 5 AufenthG)',
  laufzeit: 'meist 3 Monate, teils bis 6 — die Behörde entscheidet',
);

const kAbFristDuldung = AbFrist(
  vorwarnungTage: 28,
  dokument: 'Duldungsbescheinigung (Papier)',
  laufzeit: 'häufig 6 Monate, oft auch nur 1 bis 3',
);

const kAbFristGestattung = AbFrist(
  vorwarnungTage: 28,
  dokument: 'Gestattungsbescheinigung (Papier)',
  laufzeit: 'kurz, wird laufend verlängert — meist 3 bis 6 Monate',
);

const kAbFristReiseausweis = AbFrist(
  vorwarnungTage: 90,
  dokument: 'Reiseausweis (Passersatz-Heft)',
  laufzeit: 'in der Regel an den Aufenthaltstitel gekoppelt',
);

const kAbFristAufenthaltskarte = AbFrist(
  vorwarnungTage: 90,
  dokument: 'Aufenthaltskarte bzw. Bescheinigung (FreizügG/EU)',
  laufzeit: 'Aufenthaltskarte 5 Jahre; Daueraufenthalt unbefristet',
);

/// ⚠️ Kein Dokumentablauf, sondern ein Haftungsdatum: die Haftung aus § 68
/// Abs. 2 AufenthG läuft fünf Jahre ab der Einreise und erlischt NICHT dadurch,
/// dass die eingeladene Person später einen eigenen Titel oder einen Schutz-
/// status bekommt. Deshalb steht hier „Haftung endet", nicht „gültig bis".
const kAbFristVerpflichtung = AbFrist(
  vorwarnungTage: 60,
  dokument: 'Verpflichtungserklärung (§ 68 AufenthG) — Haftungsdatum',
  laufzeit: 'Haftung 5 Jahre ab Einreise, unabhängig vom späteren Status',
);

const kAbFristIntegrationskurs = AbFrist(
  vorwarnungTage: 60,
  dokument: 'Berechtigungsschein Integrationskurs',
  laufzeit: 'Anmeldefrist 1 Jahr',
);

/// ══ § 24 AufenthG — vorübergehender Schutz (Ukraine) ══════════════════
///
/// 🔴 Diese Erlaubnis läuft NICHT ab wie die übrigen. Sie gilt kraft
/// Verordnung weiter — **ohne Antrag, ohne Vorsprache, ohne neue Karte**.
/// Die Berliner Ausländerbehörde schreibt es wörtlich: die Erlaubnisse sind
/// gültig, „auch wenn das Gültigkeitsdatum auf dem jeweiligen Dokument
/// abgelaufen ist".
///
/// ⚠️ Für die App heißt das: das Datum AUF DER KARTE ist bedeutungslos. Eine
/// Warnung „läuft ab, bitte verlängern lassen" wäre hier schlicht falsch und
/// schickte jemanden zu einem Termin, den es nicht braucht — bei einer Behörde,
/// die nach eigener Auskunft (Nürnberg) nicht einmal Bescheinigungen ausstellt.
///
/// Maßgeblich ist die **Ukraine-Aufenthalts-Fortgeltungsverordnung**
/// (UkraineAufenthFGV), zuletzt geändert durch BGBl. 2025 I Nr. 252 vom
/// 22.10.2025. NICHT die UkraineAufenthÜV — die regelt etwas anderes
/// (Befreiung vom Titelerfordernis beim Übergang) und wird oft verwechselt.
///
/// ⚠️ **Diese Verordnung wird JÄHRLICH neu erlassen und tritt sonst außer
/// Kraft** (§ 3 Abs. 2). Das Datum unten ist deshalb ein Verfallsdatum im
/// Code, keine Konstante der Rechtslage.
const kUkraineFortgeltungBis = '04.03.2027';

/// Stichtag: die Erlaubnis muss an diesem Tag gültig gewesen sein, um
/// weiterzugelten (§ 2 UkraineAufenthFGV).
///
/// ⚠️ Wer den Stichtag verpasst hat, fällt NICHT unter die Fortgeltung und
/// braucht sehr wohl die Ausländerbehörde. Deshalb steht er auf dem Schirm.
const kUkraineStichtag = '1. Februar 2026';

/// Was auf EU-Ebene schon beschlossen, in Deutschland aber noch nicht
/// umgesetzt ist.
///
/// ⚠️ Der Durchführungsbeschluss (EU) 2026/1912 vom 30.07.2026 verlängert den
/// vorübergehenden Schutz bis zum 04.03.2028. Deutschland hat das (Stand
/// 04.09.2026) **noch nicht** in eine dritte Änderungsverordnung gegossen.
/// Das EU-Datum darf deshalb NICHT als deutsches Ablaufdatum angezeigt
/// werden — es wäre eine Zusage, die hier noch niemand gemacht hat. Es steht
/// nur als Ausblick daneben.
const kUkraineEuBeschlossenBis = '04.03.2028';

/// Ob ein Typ unter die gesetzliche Fortgeltung fällt.
bool abFortgeltung(String typ) => abTypFinden(typ)?.fortgeltung ?? false;

/// Ein Vorgang bei der Ausländerbehörde.
class AbVorfallTyp {
  final String name;
  final String gruppe;

  /// Rechtsgrundlage, soweit eindeutig. Erscheint als Untertitel im Dialog.
  final String? recht;

  /// ⚠️-Hinweis, wenn die Behörde NICHT allein zuständig ist oder der Vorgang
  /// leicht mit einem anderen verwechselt wird.
  final String? hinweis;

  /// Ablauffrist, falls der Vorgang ein befristetes Dokument erzeugt.
  final AbFrist? frist;

  /// Gilt kraft Verordnung weiter — dann ist das Datum auf der Karte
  /// bedeutungslos und es darf NICHT zur Verlängerung aufgefordert werden.
  final bool fortgeltung;

  const AbVorfallTyp(
    this.name,
    this.gruppe, {
    this.recht,
    this.hinweis,
    this.frist,
    this.fortgeltung = false,
  });
}

const kAbGruppeTitel = 'Aufenthaltstitel';
const kAbGruppeFamilie = 'Familiennachzug';
const kAbGruppeHumanitaer = 'Humanitär';
const kAbGruppeDokumente = 'Dokumente';
const kAbGruppeArbeit = 'Erwerbstätigkeit';
const kAbGruppeSonstiges = 'Sonstiges';

/// Reihenfolge der Gruppen im Dropdown.
const kAbGruppen = <String>[
  kAbGruppeTitel,
  kAbGruppeFamilie,
  kAbGruppeHumanitaer,
  kAbGruppeDokumente,
  kAbGruppeArbeit,
  kAbGruppeSonstiges,
];

/// Der Vorgang mit der Sonderbehandlung — als Konstante, weil Bildschirm,
/// Test und Katalog denselben Namen treffen müssen.
const kUkraineTyp = 'Aufenthaltserlaubnis nach § 24 AufenthG (vorübergehender Schutz)';

/// Der Eintrag, der immer zuletzt steht.
///
/// ⚠️ Er ist keine Bequemlichkeit. Ausweisung, Abschiebungsandrohung, Anhörung,
/// Wiedereinreisesperre und Widerspruchsverfahren stehen in KEINEM
/// Dienstleistungsverzeichnis — sie sind keine beantragbaren Leistungen,
/// sondern Verfahren, die die Behörde von sich aus einleitet. Für einen Verein,
/// der Mitglieder begleitet, sind aber genau die häufig der Anlass des Termins.
const kAbSonstigesTyp = 'Sonstiges / Termin bei der Ausländerbehörde';

const kAbVorfallTypen = <AbVorfallTyp>[
  // ══ Aufenthaltstitel ═══════════════════════════════════════════════════
  AbVorfallTyp('Aufenthaltserlaubnis beantragen (Erstantrag)', kAbGruppeTitel,
      recht: '§ 7 AufenthG', frist: kAbFristTitel),
  AbVorfallTyp('Aufenthaltserlaubnis verlängern', kAbGruppeTitel,
      recht: '§ 8 AufenthG',
      hinweis: 'Vor Ablauf beantragen — sonst wird eine Fiktionsbescheinigung nötig.',
      frist: kAbFristTitel),
  AbVorfallTyp('Aufenthaltserlaubnis zum Zweck der Ausbildung oder des Studiums', kAbGruppeTitel,
      recht: '§§ 16a ff. AufenthG', frist: kAbFristTitel),
  AbVorfallTyp('Aufenthaltserlaubnis für eine Beschäftigung beantragen', kAbGruppeTitel,
      recht: '§ 18a AufenthG',
      hinweis: 'Regelmäßig nur mit Zustimmung der Bundesagentur für Arbeit.',
      frist: kAbFristTitel),
  AbVorfallTyp('Aufenthaltserlaubnis zur Ausübung einer selbständigen Tätigkeit', kAbGruppeTitel,
      recht: '§ 21 AufenthG', frist: kAbFristTitel),
  AbVorfallTyp('Aufenthaltserlaubnis zum Zweck der Forschung', kAbGruppeTitel,
      recht: '§ 18d AufenthG', frist: kAbFristTitel),
  AbVorfallTyp('Blaue Karte EU beantragen', kAbGruppeTitel,
      recht: '§ 18g AufenthG', frist: kAbFristTitel),
  AbVorfallTyp('Chancenkarte beantragen', kAbGruppeTitel,
      recht: '§ 20a AufenthG',
      hinweis: 'Neu mit dem Fachkräfteeinwanderungsgesetz.',
      frist: kAbFristTitel),
  AbVorfallTyp('Niederlassungserlaubnis beantragen', kAbGruppeTitel,
      recht: '§ 9 AufenthG', frist: kAbFristKarteUnbefristet),
  AbVorfallTyp('Erlaubnis zum Daueraufenthalt-EU beantragen', kAbGruppeTitel,
      recht: '§ 9a AufenthG', frist: kAbFristKarteUnbefristet),
  AbVorfallTyp('Aufenthaltskarte oder Daueraufenthaltsbescheinigung (Freizügigkeit)', kAbGruppeTitel,
      recht: '§ 5 FreizügG/EU',
      hinweis: 'Für Unionsbürger und ihre Angehörigen — kein Aufenthaltstitel im Sinne des AufenthG.',
      frist: kAbFristAufenthaltskarte),
  AbVorfallTyp('Beschleunigtes Fachkräfteverfahren', kAbGruppeTitel,
      recht: '§ 81a AufenthG',
      hinweis: 'Wird vom Arbeitgeber eingeleitet, nicht von der Fachkraft.'),

  // ══ Familiennachzug ════════════════════════════════════════════════════
  AbVorfallTyp('Familiennachzug zu Ausländern — Aufenthaltserlaubnis beantragen', kAbGruppeFamilie,
      recht: '§§ 29 ff. AufenthG', frist: kAbFristTitel),
  AbVorfallTyp('Familiennachzug zu Deutschen — Aufenthaltserlaubnis beantragen', kAbGruppeFamilie,
      recht: '§ 28 AufenthG', frist: kAbFristTitel),
  AbVorfallTyp('Nachzug weiterer Familienangehöriger', kAbGruppeFamilie,
      recht: '§ 36 AufenthG', frist: kAbFristTitel),
  AbVorfallTyp('Aufenthaltstitel für ein minderjähriges Kind erteilen oder verlängern', kAbGruppeFamilie,
      recht: '§ 33, § 34 AufenthG', frist: kAbFristTitel),

  // ══ Humanitär ══════════════════════════════════════════════════════════
  AbVorfallTyp(kUkraineTyp, kAbGruppeHumanitaer,
      recht: '§ 24 AufenthG, UkraineAufenthFGV',
      hinweis: 'Gilt kraft Verordnung bis zum $kUkraineFortgeltungBis weiter — '
          'ohne Antrag, ohne Termin und ohne neue Karte, auch wenn das Datum auf '
          'der Karte längst abgelaufen ist.',
      fortgeltung: true),
  AbVorfallTyp('Aufenthaltsgestattung verlängern', kAbGruppeHumanitaer,
      recht: '§ 63 AsylG',
      hinweis: 'Die Gestattung entsteht kraft Gesetzes; ausgehändigt wird sie von der '
          'Aufnahmeeinrichtung bzw. dem BAMF. Die Ausländerbehörde verlängert nur.',
      frist: kAbFristGestattung),
  AbVorfallTyp('Duldung — Erteilung oder Verlängerung', kAbGruppeHumanitaer,
      recht: '§ 60a AufenthG', frist: kAbFristDuldung),
  AbVorfallTyp('Ausbildungsduldung', kAbGruppeHumanitaer,
      recht: '§ 60c AufenthG',
      hinweis: 'An die Ausbildungsdauer gekoppelt; nach Abschluss 6 Monate zur Arbeitsuche.',
      frist: kAbFristDuldung),
  AbVorfallTyp('Beschäftigungsduldung', kAbGruppeHumanitaer,
      recht: '§ 60d AufenthG', frist: kAbFristDuldung),
  AbVorfallTyp('Aufenthaltstitel bei Asylantrag beantragen', kAbGruppeHumanitaer,
      recht: '§§ 22 ff. AufenthG',
      hinweis: 'Der Asylantrag selbst geht an das BAMF, nicht an die Ausländerbehörde.',
      frist: kAbFristTitel),
  AbVorfallTyp('Rückkehrberatung', kAbGruppeHumanitaer),

  // ══ Dokumente ══════════════════════════════════════════════════════════
  AbVorfallTyp('Elektronischen Aufenthaltstitel (eAT) beantragen', kAbGruppeDokumente,
      recht: '§ 78 AufenthG', frist: kAbFristTitel),
  AbVorfallTyp('Elektronischen Aufenthaltstitel (eAT) abholen', kAbGruppeDokumente,
      hinweis: 'Persönlich; eine Abholung durch Dritte braucht eine Vollmacht.'),
  AbVorfallTyp('eAT bei neuem oder geändertem Nationalpass bestellen (Passübertrag)', kAbGruppeDokumente,
      frist: kAbFristTitel),
  AbVorfallTyp('Elektronischen Aufenthaltstitel verloren oder gestohlen melden', kAbGruppeDokumente,
      hinweis: 'Verlustmeldung selbst kostenfrei; die Ersatzkarte ist gebührenpflichtig.'),
  AbVorfallTyp('Verlust eines ausländischen Reisepasses melden', kAbGruppeDokumente,
      hinweis: 'Für den Ersatz ist die Auslandsvertretung des Herkunftsstaats zuständig.'),
  AbVorfallTyp('Fiktionsbescheinigung', kAbGruppeDokumente,
      recht: '§ 81 Abs. 5 AufenthG',
      hinweis: 'Überbrückt die Zeit bis zur Entscheidung — kurze Laufzeit, früh nachfassen.',
      frist: kAbFristFiktion),
  AbVorfallTyp('Reiseausweis für Ausländer beantragen', kAbGruppeDokumente,
      recht: '§ 5 AufenthV', frist: kAbFristReiseausweis),
  AbVorfallTyp('Reiseausweis für Flüchtlinge oder für Staatenlose beantragen', kAbGruppeDokumente,
      frist: kAbFristReiseausweis),
  AbVorfallTyp('Notreiseausweis für Ausländer', kAbGruppeDokumente,
      hinweis: 'Nur für eine einzelne, unaufschiebbare Reise.'),

  // ══ Erwerbstätigkeit ═══════════════════════════════════════════════════
  AbVorfallTyp('Beschäftigungserlaubnis bei Duldung', kAbGruppeArbeit,
      recht: '§ 4a AufenthG',
      hinweis: 'Regelmäßig nur mit Zustimmung der Bundesagentur für Arbeit — daher die langen Bearbeitungszeiten.'),
  AbVorfallTyp('Beschäftigungserlaubnis bei Aufenthaltsgestattung', kAbGruppeArbeit,
      recht: '§ 61 AsylG',
      hinweis: 'Regelmäßig nur mit Zustimmung der Bundesagentur für Arbeit.'),
  AbVorfallTyp('Beschäftigungserlaubnis für ausländische Studierende', kAbGruppeArbeit,
      recht: '§ 16b AufenthG'),
  AbVorfallTyp('Erklärung zum Beschäftigungsverhältnis abgeben', kAbGruppeArbeit,
      hinweis: 'Wird vom Arbeitgeber ausgefüllt und der Behörde vorgelegt.'),

  // ══ Sonstiges ══════════════════════════════════════════════════════════
  AbVorfallTyp('Verpflichtungserklärung abgeben', kAbGruppeSonstiges,
      recht: '§ 68 AufenthG', frist: kAbFristVerpflichtung),
  AbVorfallTyp('Nebenbestimmungen oder Auflagen ändern', kAbGruppeSonstiges,
      recht: '§ 12 AufenthG'),
  AbVorfallTyp('Wohnsitzauflage aufheben', kAbGruppeSonstiges,
      recht: '§ 12a AufenthG'),
  AbVorfallTyp('Visumverlängerung', kAbGruppeSonstiges,
      recht: '§ 6 AufenthG',
      hinweis: 'Nur die Verlängerung im Inland. Das Visum selbst beantragt man vor der '
          'Einreise bei der deutschen Auslandsvertretung, nicht hier.'),
  AbVorfallTyp('Integrationskurs — Verpflichtung oder Berechtigungsschein', kAbGruppeSonstiges,
      recht: '§ 44, § 44a AufenthG',
      hinweis: 'Den Schein stellt die Ausländerbehörde aus; Kurszulassung und Abwicklung macht das BAMF.',
      frist: kAbFristIntegrationskurs),
  AbVorfallTyp(kAbSonstigesTyp, kAbGruppeSonstiges,
      hinweis: 'Auch für Verfahren, die die Behörde selbst einleitet: Anhörung, '
          'Ausweisung, Abschiebungsandrohung, Widerspruch.'),
];

/// Nachschlagen nach Name. Unbekannt -> null (eine ältere App kann einen Typ
/// geschickt haben, den diese Fassung nicht kennt — dann fehlt nur der
/// Untertitel, nicht der Vorfall).
AbVorfallTyp? abTypFinden(String name) {
  for (final t in kAbVorfallTypen) {
    if (t.name == name) return t;
  }
  return null;
}

/// Die Typen einer Gruppe, in Katalogreihenfolge.
List<AbVorfallTyp> abTypenDerGruppe(String gruppe) =>
    kAbVorfallTypen.where((t) => t.gruppe == gruppe).toList();

/// Vorwarnzeit eines Typs; ohne eigenes Dokument gilt die lange Titelfrist als
/// unschädlicher Vorgabewert.
int abVorwarnungTage(String typ) =>
    abTypFinden(typ)?.frist?.vorwarnungTage ?? kAbFristTitel.vorwarnungTage;

/// Ob der Ablauf schon in der Vorwarnzeit liegt. [heute] ist gesetzt, damit die
/// Regel prüfbar ist, ohne auf einen Kalendertag zu warten.
///
/// ⚠️ Ein bereits abgelaufenes Datum ist IMMER fällig — nicht „nicht mehr in
/// der Vorwarnzeit". Genau dann ist der Handlungsdruck am größten.
bool abLaeuftBaldAb(String typ, DateTime? ablauf, {DateTime? heute}) {
  // 🔴 Bei gesetzlicher Fortgeltung sagt das Kartendatum nichts. Eine Warnung
  // hier wäre eine Falschaussage — und die teuerste Sorte, weil sie jemanden
  // zu einem überflüssigen Behördengang schickt.
  if (abFortgeltung(typ)) return false;
  if (ablauf == null) return false;
  final jetzt = heute ?? DateTime.now();
  final grenze = DateTime(jetzt.year, jetzt.month, jetzt.day)
      .add(Duration(days: abVorwarnungTage(typ)));
  final tag = DateTime(ablauf.year, ablauf.month, ablauf.day);
  return !tag.isAfter(grenze);
}

/// Liest „TT.MM.JJJJ". Alles andere -> null.
///
/// ⚠️ Kein Erraten anderer Schreibweisen: die Datumsfelder schreiben immer
/// dieses Format, und ein leeres Feld heißt „nicht erfasst", nicht „unbefristet".
DateTime? abDatumLesen(String? s) {
  final t = (s ?? '').trim();
  final m = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})$').firstMatch(t);
  if (m == null) return null;
  final tag = int.parse(m.group(1)!);
  final monat = int.parse(m.group(2)!);
  final jahr = int.parse(m.group(3)!);
  if (monat < 1 || monat > 12 || tag < 1 || tag > 31) return null;
  final d = DateTime(jahr, monat, tag);
  if (d.day != tag || d.month != monat) return null;
  return d;
}
