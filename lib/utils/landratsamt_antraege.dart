/// Katalog der Anträge und Vorgänge, die bei einem Landratsamt anfallen.
///
/// ⚠️ **Nicht aus dem Dienstleistungsverzeichnis EINES Landkreises abgeschrieben.**
/// Die Gliederung folgt den gesetzlichen Aufgaben der Kreisverwaltungsbehörde,
/// weil jeder Landkreis seinen Katalog anders zuschneidet und die Zuständigkeit
/// ausserdem je Bundesland auseinandergeht. Grundlage ist die Doppelnatur des
/// Landratsamts: Kreisbehörde für die Selbstverwaltungsaufgaben, untere
/// staatliche Verwaltungsbehörde für den staatlichen Teil — Art. 37 LKrO in
/// Bayern, § 15 LVG in Baden-Württemberg (dort sind die Landratsämter
/// ausdrücklich die unteren Verwaltungsbehörden).
///
/// ⚠️ **Warum das hier steht und nicht als Liste im Dialog:**
/// [titel] wird als Klartext in `landratsamt_vorfaelle.art` gespeichert
/// (verschlüsselt at rest). Ein umbenannter Titel macht **bestehende Vorfälle
/// unauffindbar** im Auswahldialog — der alte Wert steht dann in der Datenbank,
/// aber in keinem Katalogeintrag mehr. Deshalb: **Titel nie ändern, nur
/// hinzufügen.** `test/landratsamt_antraege_test.dart` hält die 19 Titel der
/// ersten Fassung fest und schlägt Alarm, wenn einer verschwindet.
///
/// [hinweis] trägt die Fälle, in denen das Landratsamt **nicht** oder nicht
/// überall zuständig ist. Das ist kein Beiwerk: wer einen Antrag bei der
/// falschen Behörde einreicht, verliert Wochen, und bei einer Frist verliert er
/// den Anspruch. Die drei Fälle, die diesen Verein am härtesten treffen, stehen
/// deshalb ausdrücklich drin — Schwerbehindertenausweis, Eingliederungshilfe
/// und Hilfe zur Pflege gehen in Bayern gerade **nicht** an das Landratsamt.
library;

/// Ein Antrag oder Vorgang beim Landratsamt.
class LandratsamtAntrag {
  /// Der gespeicherte Wert. Siehe Warnung oben: niemals ändern.
  final String titel;

  /// Fachbereich, nach dem der Auswahldialog gruppiert.
  final String gruppe;

  /// Rechtsgrundlage, soweit sie den Vorgang eindeutig benennt.
  final String? recht;

  /// Zuständigkeitswarnung — nur gesetzt, wo es eine gibt.
  final String? hinweis;

  /// `true`, wenn das Landratsamt für diesen Vorgang gar nicht zuständig ist
  /// oder es je nach Bundesland eine andere Behörde ist.
  ///
  /// ⚠️ Der Unterschied wird in der Oberfläche gezeigt, deshalb ist er ein
  /// eigenes Feld und kein „⚠️" im Text: ein Emoji wird auf manchen Geräten
  /// zum leeren Kästchen, und es stünde neben dem Symbol, das das Widget
  /// ohnehin setzt. Die Icon-Schrift ist dagegen mitgeliefert.
  final bool streng;

  const LandratsamtAntrag(this.titel, this.gruppe,
      {this.recht, this.hinweis, this.streng = false});
}

// ── Gruppen, in der Reihenfolge des Auswahldialogs ────────────────────────
// Vorn steht, was die Mitglieder dieses Vereins tatsächlich betrifft, nicht
// die alphabetische Ordnung eines Amtsverzeichnisses.
const kLraBetreuung = 'Betreuungsbehörde';
const kLraSchulden = 'Schuldner- und Insolvenzberatung';
const kLraSoziales = 'Sozialhilfe & soziale Leistungen';
const kLraTeilhabe = 'Behinderung & Teilhabe';
const kLraPflege = 'Pflege & Senioren';
const kLraJugend = 'Kinder, Jugend & Familie';
const kLraBildung = 'Bildung & Ausbildungsförderung';
const kLraAusland = 'Ausländer- & Staatsangehörigkeitsrecht';
const kLraGesundheit = 'Gesundheitsamt';
const kLraFuehrerschein = 'Führerscheinstelle';
const kLraKfz = 'Kfz-Zulassung';
const kLraVerkehr = 'Verkehr & Straßen';
const kLraBau = 'Bauaufsicht & Wohnen';
const kLraUmwelt = 'Umwelt, Natur & Wasser';
const kLraAbfall = 'Abfall & Entsorgung';
const kLraWaffen = 'Waffen, Jagd & Fischerei';
const kLraGewerbe = 'Gewerbe & Gaststätten';
const kLraDenkmal = 'Denkmalschutz';
const kLraOrdnung = 'Ordnung, Urkunden & Register';
const kLraVeterinaer = 'Veterinär- & Lebensmittelrecht';
const kLraSonstiges = 'Sonstiges';

/// Reihenfolge der Gruppen im Auswahldialog.
const kLandratsamtGruppen = <String>[
  kLraBetreuung, kLraSchulden, kLraSoziales, kLraTeilhabe, kLraPflege,
  kLraJugend, kLraBildung, kLraAusland, kLraGesundheit, kLraFuehrerschein,
  kLraKfz, kLraVerkehr, kLraBau, kLraUmwelt, kLraAbfall, kLraWaffen,
  kLraGewerbe, kLraDenkmal, kLraOrdnung, kLraVeterinaer, kLraSonstiges,
];

/// Der Katalog. Reihenfolge innerhalb einer Gruppe folgt dem Verfahrensablauf,
/// nicht dem Alphabet — bei der Insolvenzberatung etwa der Reihenfolge des
/// § 305 InsO, weil man die Schritte in dieser Folge geht.
const kLandratsamtAntraege = <LandratsamtAntrag>[
  // ══ Betreuungsbehörde ══════════════════════════════════════════════════
  // §§ 2-11 BtOG. Örtlich zuständig ist nach § 2 BtOG die Behörde am
  // gewöhnlichen Aufenthalt — bundeseinheitlich der Kreis bzw. die kreisfreie
  // Stadt, hier also ohne Länderunterschied.
  LandratsamtAntrag('Verfahrensbetreuung (Anordnung Betreuungsgericht)', kLraBetreuung, recht: '§ 12 BtOG'),
  LandratsamtAntrag('Betreuungsanregung', kLraBetreuung, recht: '§ 7 BtOG'),
  LandratsamtAntrag('Sozialbericht / Stellungnahme an Gericht', kLraBetreuung, recht: '§ 8 BtOG'),
  LandratsamtAntrag('Hausbesuch / Ermittlung', kLraBetreuung, recht: '§ 8 BtOG'),
  LandratsamtAntrag('Beratung Betroffene/r', kLraBetreuung, recht: '§ 5 BtOG'),
  LandratsamtAntrag('Beratung Angehörige', kLraBetreuung, recht: '§ 5 BtOG'),
  LandratsamtAntrag('Begleitung Anhörung Betreuungsgericht', kLraBetreuung),
  LandratsamtAntrag('Vorsorgevollmacht / Betreuungsverfügung — Beglaubigung (§ 7 BtOG)', kLraBetreuung,
      recht: '§ 7 BtOG',
      hinweis: 'Beglaubigt wird nur die Unterschrift, nicht der Inhalt. Für Grundstücks- und Handelsregistersachen reicht das nicht — dort braucht es den Notar.'),
  LandratsamtAntrag('Patientenverfügung — Beratung', kLraBetreuung, recht: '§ 1827 BGB'),
  LandratsamtAntrag('Vermittlung einer/eines beruflichen Betreuenden', kLraBetreuung, recht: '§ 11 BtOG'),
  LandratsamtAntrag('Registrierung beruflicher Betreuer (Stammbehörde)', kLraBetreuung,
      recht: '§ 24 BtOG',
      hinweis: 'Betrifft die Betreuungsperson selbst, nicht die betreute Person.'),

  // ══ Schuldner- und Insolvenzberatung ═══════════════════════════════════
  // Reihenfolge = Verfahrensgang des § 305 InsO. Die Anerkennung als
  // „geeignete Stelle" ist Landesrecht; nicht jedes Landratsamt hat eine
  // eigene, viele verweisen an Caritas, Diakonie oder AWO.
  LandratsamtAntrag('Schuldner-/Insolvenzberatung — Erstberatung', kLraSchulden),
  LandratsamtAntrag('Schuldnerberatung — Gläubigerübersicht / Forderungsaufstellung', kLraSchulden),
  LandratsamtAntrag('Schuldnerberatung — Schuldenbereinigungsplan erstellen', kLraSchulden, recht: '§ 305 Abs. 1 Nr. 4 InsO'),
  LandratsamtAntrag('Schuldnerberatung — Außergerichtlicher Einigungsversuch (§ 305 InsO)', kLraSchulden, recht: '§ 305 Abs. 1 Nr. 1 InsO'),
  LandratsamtAntrag('Insolvenzantrag — Bescheinigung § 305 Abs. 1 Nr. 1 InsO ausgestellt', kLraSchulden, recht: '§ 305 Abs. 1 Nr. 1 InsO'),
  LandratsamtAntrag('Insolvenzantrag — Antrag an Insolvenzgericht eingereicht', kLraSchulden, recht: '§ 305 InsO'),
  LandratsamtAntrag('P-Konto-Bescheinigung ausgestellt', kLraSchulden, recht: '§ 903 ZPO'),
  LandratsamtAntrag('Restschuldbefreiung — Antrag / Begleitung', kLraSchulden, recht: '§ 287 InsO'),

  // ══ Sozialhilfe & soziale Leistungen ═══════════════════════════════════
  // § 3 SGB XII: örtlicher Träger ist der Kreis. Was hier steht, bleibt auch
  // in Bayern beim Landratsamt — anders als Eingliederungshilfe und Hilfe zur
  // Pflege, siehe Gruppen „Behinderung & Teilhabe" und „Pflege & Senioren".
  LandratsamtAntrag('Grundsicherung im Alter / bei Erwerbsminderung (SGB XII Kap. 4)', kLraSoziales, recht: '§§ 41 ff. SGB XII'),
  LandratsamtAntrag('Hilfe zum Lebensunterhalt (SGB XII Kap. 3)', kLraSoziales, recht: '§§ 27 ff. SGB XII'),
  LandratsamtAntrag('Hilfe zur Weiterführung des Haushalts', kLraSoziales, recht: '§ 70 SGB XII'),
  LandratsamtAntrag('Altenhilfe', kLraSoziales, recht: '§ 71 SGB XII'),
  LandratsamtAntrag('Hilfe zur Überwindung besonderer sozialer Schwierigkeiten', kLraSoziales, recht: '§§ 67 ff. SGB XII'),
  LandratsamtAntrag('Bestattungskosten — Übernahme', kLraSoziales, recht: '§ 74 SGB XII'),
  LandratsamtAntrag('Sozialhilfe bei gewöhnlichem Aufenthalt im Ausland', kLraSoziales, recht: '§ 24 SGB XII'),
  LandratsamtAntrag('Kriegsopferfürsorge', kLraSoziales, recht: '§§ 25 ff. BVG'),
  LandratsamtAntrag('Bildung und Teilhabe (BuT) — Antrag', kLraSoziales,
      recht: '§ 34 SGB XII / § 28 SGB II',
      hinweis: 'Nur für Bezieher von SGB-XII-, Wohngeld- oder Kinderzuschlagsleistungen. Wer Bürgergeld bezieht, stellt den Antrag beim Jobcenter — eigener Reiter.'),
  LandratsamtAntrag('Asylbewerberleistungen — Antrag', kLraSoziales, recht: '§§ 3 ff. AsylbLG'),
  LandratsamtAntrag('Asylbewerberleistungen — Leistungen im Krankheitsfall', kLraSoziales, recht: '§§ 4, 6 AsylbLG'),
  LandratsamtAntrag('Wohngeld — Miet- oder Lastenzuschuss', kLraSoziales,
      recht: '§ 24 WoGG',
      hinweis: 'Für laufende Wohngeldsachen gibt es den eigenen Reiter „Wohngeldstelle". Hier nur eintragen, wenn der Vorgang tatsächlich über das Landratsamt läuft.'),
  LandratsamtAntrag('Wohnberechtigungsschein (WBS)', kLraSoziales,
      recht: '§ 5 WoBindG',
      hinweis: 'Eigener Reiter „WBS" — dort gehört der laufende Vorgang hin.'),

  // ══ Behinderung & Teilhabe ═════════════════════════════════════════════
  // ⚠️ Die wichtigste Zuständigkeitsfalle dieser Datei.
  LandratsamtAntrag('Schwerbehindertenausweis — Antrag / Verschlimmerungsantrag', kLraTeilhabe,
      recht: '§ 152 SGB IX, SchwbAwV',
      streng: true, hinweis: 'In Bayern NICHT das Landratsamt, sondern das ZBFS (Regionalstelle Schwaben). In Baden-Württemberg das Landratsamt, seit 01.01.2005 (VersVG BW). Eigener Reiter „Versorgungsamt".'),
  LandratsamtAntrag('Feststellung Grad der Behinderung (GdB) / Merkzeichen', kLraTeilhabe,
      recht: '§ 152 SGB IX',
      streng: true, hinweis: 'Bayern: ZBFS. Baden-Württemberg: Landratsamt.'),
  LandratsamtAntrag('Eingliederungshilfe — Antrag', kLraTeilhabe,
      recht: '§§ 90 ff. SGB IX',
      streng: true, hinweis: 'In Bayern ist der BEZIRK Träger der Eingliederungshilfe, nicht das Landratsamt. In Baden-Württemberg der Landkreis.'),
  LandratsamtAntrag('Parkausweis für schwerbehinderte Menschen', kLraTeilhabe,
      recht: '§ 46 StVO',
      hinweis: 'Meist die Wohnsitzgemeinde, nicht das Landratsamt. Voraussetzung ist das Merkzeichen aG oder Bl — das kommt in Bayern vom ZBFS.'),
  LandratsamtAntrag('Blindengeld / Blindenhilfe', kLraTeilhabe,
      recht: '§ 72 SGB XII / BayBlindG',
      streng: true, hinweis: 'Bayerisches Blindengeld beantragt man beim ZBFS. Die Blindenhilfe nach § 72 SGB XII läuft über den Sozialhilfeträger.'),
  LandratsamtAntrag('Werkstatt für behinderte Menschen — Aufnahme', kLraTeilhabe, recht: '§ 219 SGB IX'),
  LandratsamtAntrag('Ergänzende unabhängige Teilhabeberatung (EUTB) — Vermittlung', kLraTeilhabe, recht: '§ 32 SGB IX'),
  LandratsamtAntrag('Schulbegleitung / Integrationshelfer — Antrag', kLraTeilhabe,
      recht: '§ 112 SGB IX / § 35a SGB VIII',
      hinweis: 'Trägerschaft hängt an der Art der Behinderung: seelische Behinderung → Jugendamt (§ 35a SGB VIII), körperliche oder geistige → Eingliederungshilfeträger.'),

  // ══ Pflege & Senioren ══════════════════════════════════════════════════
  LandratsamtAntrag('Hilfe zur Pflege — Antrag', kLraPflege,
      recht: '§§ 61 ff. SGB XII',
      streng: true, hinweis: 'In Bayern seit 01.03.2018 vollständig beim BEZIRK, ambulant wie stationär (BayTHG I). In Baden-Württemberg beim Landkreis.'),
  LandratsamtAntrag('Pflegeberatung / Pflegestützpunkt', kLraPflege, recht: '§ 7a SGB XI'),
  LandratsamtAntrag('Heimaufsicht (FQA) — Beschwerde oder Prüfung', kLraPflege, recht: 'PfleWoqG (BY) / WTPG (BW)'),
  LandratsamtAntrag('Barrierefreier Wohnraum — Beratung', kLraPflege),
  LandratsamtAntrag('Betreutes Wohnen — Beratung / Vermittlung', kLraPflege),

  // ══ Kinder, Jugend & Familie ═══════════════════════════════════════════
  // § 69 SGB VIII: örtlicher Träger der Jugendhilfe ist der Kreis. Die App hat
  // dafür einen eigenen Reiter „Jugendamt" — hier stehen die Vorgänge, damit
  // sie auffindbar sind, mit Verweis dorthin.
  LandratsamtAntrag('Hilfe zur Erziehung — Antrag', kLraJugend,
      recht: '§§ 27 ff. SGB VIII',
      hinweis: 'Eigener Reiter „Jugendamt".'),
  LandratsamtAntrag('Eingliederungshilfe für seelisch behinderte Kinder (§ 35a SGB VIII)', kLraJugend, recht: '§ 35a SGB VIII'),
  LandratsamtAntrag('Hilfe für junge Volljährige', kLraJugend, recht: '§ 41 SGB VIII'),
  LandratsamtAntrag('Beistandschaft — Antrag', kLraJugend, recht: '§§ 1712 ff. BGB, § 55 SGB VIII'),
  LandratsamtAntrag('Vaterschaftsanerkennung — Beurkundung', kLraJugend, recht: '§ 59 SGB VIII'),
  LandratsamtAntrag('Unterhaltsverpflichtung — Beurkundung', kLraJugend, recht: '§ 59 SGB VIII'),
  LandratsamtAntrag('Sorgeerklärung / gemeinsame Sorge', kLraJugend, recht: '§ 1626a BGB'),
  LandratsamtAntrag('Auskunft aus dem Sorgeregister', kLraJugend, recht: '§ 58a SGB VIII'),
  LandratsamtAntrag('Unterhaltsvorschuss — Antrag', kLraJugend, recht: '§ 9 UhVorschG'),
  LandratsamtAntrag('Vormundschaft / Pflegschaft für Minderjährige', kLraJugend, recht: '§§ 55 ff. SGB VIII'),
  LandratsamtAntrag('Inobhutnahme', kLraJugend, recht: '§ 42 SGB VIII'),
  LandratsamtAntrag('Vollzeitpflege — Pflegegeld und Beihilfen', kLraJugend, recht: '§ 33 SGB VIII'),
  LandratsamtAntrag('Adoption — Antrag oder Beratung', kLraJugend, recht: 'AdVermiG'),
  LandratsamtAntrag('Kindertagespflege — Erlaubnis oder Vermittlung', kLraJugend, recht: '§ 43 SGB VIII'),
  LandratsamtAntrag('Kinderbetreuungsgebühren — Übernahme', kLraJugend, recht: '§ 90 SGB VIII'),
  LandratsamtAntrag('Mitwirkung des Jugendamts im Familiengerichtsverfahren', kLraJugend, recht: '§ 50 SGB VIII'),
  LandratsamtAntrag('Jugendhilfe im Strafverfahren (Jugendgerichtshilfe)', kLraJugend, recht: '§ 52 SGB VIII, § 38 JGG'),
  LandratsamtAntrag('Trennungs- und Scheidungsberatung / Umgangsberatung', kLraJugend, recht: '§ 17 SGB VIII'),
  LandratsamtAntrag('Frühe Hilfen / KoKi — Beratung', kLraJugend, recht: '§ 16 SGB VIII'),
  LandratsamtAntrag('Schwangerschaftsberatung', kLraJugend, recht: 'SchKG'),

  // ══ Bildung & Ausbildungsförderung ═════════════════════════════════════
  LandratsamtAntrag('Schüler-BAföG — Antrag', kLraBildung,
      recht: '§ 40 BAföG',
      hinweis: 'Jeder Kreis muss ein Amt für Ausbildungsförderung führen. Studierende beantragen dagegen beim Studierendenwerk.'),
  LandratsamtAntrag('Aufstiegs-BAföG (AFBG) — Antrag', kLraBildung, recht: 'AFBG'),
  LandratsamtAntrag('Schülerbeförderung — Erstattung der Schulwegkosten', kLraBildung),
  LandratsamtAntrag('Jugendsozialarbeit an Schulen (JaS) — Anfrage', kLraBildung, recht: '§ 13 SGB VIII'),

  // ══ Ausländer- & Staatsangehörigkeitsrecht ═════════════════════════════
  // § 71 AufenthG: Ausländerbehörde ist die nach Landesrecht bestimmte Stelle,
  // im Landkreis das Landratsamt. Die App hat den eigenen Reiter
  // „Ausländerbehörde" — dort gehört der laufende Vorgang hin.
  LandratsamtAntrag('Aufenthaltserlaubnis — Erteilung oder Verlängerung', kLraAusland,
      recht: '§ 7 AufenthG',
      hinweis: 'Eigener Reiter „Ausländerbehörde".'),
  LandratsamtAntrag('Niederlassungserlaubnis — Antrag', kLraAusland, recht: '§ 9 AufenthG'),
  LandratsamtAntrag('Erlaubnis zum Daueraufenthalt-EU', kLraAusland, recht: '§ 9a AufenthG'),
  LandratsamtAntrag('Blaue Karte EU — Antrag', kLraAusland, recht: '§ 18g AufenthG'),
  LandratsamtAntrag('Familiennachzug — Antrag', kLraAusland, recht: '§§ 27 ff. AufenthG'),
  LandratsamtAntrag('Duldung — Erteilung oder Verlängerung', kLraAusland, recht: '§ 60a AufenthG'),
  LandratsamtAntrag('Aufenthaltsgestattung — Bescheinigung', kLraAusland, recht: '§ 63 AsylG'),
  LandratsamtAntrag('Verpflichtungserklärung — Abgabe', kLraAusland, recht: '§ 68 AufenthG'),
  LandratsamtAntrag('Einbürgerung — Anspruchseinbürgerung', kLraAusland, recht: '§ 10 StAG'),
  LandratsamtAntrag('Einbürgerung — Ermessenseinbürgerung', kLraAusland, recht: '§§ 8, 9 StAG'),
  LandratsamtAntrag('Feststellung der deutschen Staatsangehörigkeit', kLraAusland, recht: '§ 30 StAG'),
  LandratsamtAntrag('Elektronischer Aufenthaltstitel (eAT) — Ausstellung', kLraAusland, recht: '§ 78 AufenthG'),
  LandratsamtAntrag('Rückkehrberatung', kLraAusland),

  // ══ Gesundheitsamt ═════════════════════════════════════════════════════
  // Untere Gesundheitsbehörde am Landratsamt: Art. 1 GDVG in Bayern,
  // ÖGDG in Baden-Württemberg.
  LandratsamtAntrag('Amtsärztliche Untersuchung / Gutachten', kLraGesundheit),
  LandratsamtAntrag('Belehrung nach § 43 IfSG (Lebensmittelbereich)', kLraGesundheit, recht: '§ 43 IfSG'),
  LandratsamtAntrag('Infektionsschutz — Meldung oder Anordnung', kLraGesundheit, recht: 'IfSG'),
  LandratsamtAntrag('Heilpraktikererlaubnis — Antrag', kLraGesundheit, recht: 'HeilprG'),
  LandratsamtAntrag('Sozialpsychiatrischer Dienst — Beratung', kLraGesundheit),
  LandratsamtAntrag('Unterbringung nach PsychKHG / UnterbrG', kLraGesundheit,
      recht: 'BayPsychKHG / PsychKHG BW',
      hinweis: 'Die Unterbringung selbst ordnet das Gericht an; die Kreisverwaltungsbehörde stellt den Antrag.'),
  LandratsamtAntrag('Impfberatung / Impfung im Gesundheitsamt', kLraGesundheit),
  LandratsamtAntrag('Trinkwasserüberwachung — Anzeige oder Auskunft', kLraGesundheit, recht: 'TrinkwV'),

  // ══ Führerscheinstelle ═════════════════════════════════════════════════
  // § 73 FeV. Bundeseinheitlich, kein Länderunterschied.
  LandratsamtAntrag('Fahrerlaubnis — Ersterteilung oder Erweiterung', kLraFuehrerschein, recht: '§ 21 FeV'),
  LandratsamtAntrag('Begleitetes Fahren ab 17 — Antrag', kLraFuehrerschein, recht: '§ 48a FeV'),
  LandratsamtAntrag('Führerschein — Umtausch in EU-Kartenführerschein', kLraFuehrerschein, recht: '§ 24a FeV'),
  LandratsamtAntrag('Führerschein — Umschreibung eines ausländischen Führerscheins', kLraFuehrerschein, recht: '§ 31 FeV'),
  LandratsamtAntrag('Führerschein — Ersatz nach Verlust oder Diebstahl', kLraFuehrerschein, recht: '§ 25 FeV'),
  LandratsamtAntrag('Führerschein — Neuerteilung nach Entzug', kLraFuehrerschein, recht: '§ 20 FeV'),
  LandratsamtAntrag('Internationaler Führerschein — Antrag', kLraFuehrerschein, recht: '§ 25b FeV'),
  LandratsamtAntrag('Fahrerlaubnis zur Fahrgastbeförderung (P-Schein)', kLraFuehrerschein, recht: '§ 48 FeV'),
  LandratsamtAntrag('Fahrerlaubnis Bus/Lkw — Verlängerung', kLraFuehrerschein, recht: '§ 24 FeV'),
  LandratsamtAntrag('Fahreignung — Anordnung MPU / Gutachten', kLraFuehrerschein, recht: '§§ 11 ff. FeV'),
  LandratsamtAntrag('Maßnahmen nach dem Fahreignungs-Bewertungssystem (Punkte)', kLraFuehrerschein, recht: '§ 4 StVG'),
  LandratsamtAntrag('Probezeitmaßnahmen — Anordnung', kLraFuehrerschein, recht: '§ 2a StVG'),
  LandratsamtAntrag('Fahrerqualifizierungsnachweis — Antrag', kLraFuehrerschein, recht: 'BKrFQG'),

  // ══ Kfz-Zulassung ══════════════════════════════════════════════════════
  // § 46 FZV. Für laufende Fahrzeugvorgänge gibt es den eigenen Reiter „KFZ".
  LandratsamtAntrag('Neuzulassung eines Fahrzeugs', kLraKfz, recht: '§ 6 FZV', hinweis: 'Eigener Reiter „KFZ".'),
  LandratsamtAntrag('Umschreibung / Wiederzulassung mit Halterwechsel', kLraKfz, recht: '§ 13 FZV'),
  LandratsamtAntrag('Außerbetriebsetzung (Abmeldung)', kLraKfz, recht: '§ 14 FZV'),
  LandratsamtAntrag('Wunschkennzeichen — Reservierung', kLraKfz),
  LandratsamtAntrag('Saison-, Wechsel- oder Kurzzeitkennzeichen', kLraKfz, recht: '§§ 9, 10, 16 FZV'),
  LandratsamtAntrag('Ersatzpapiere oder Ersatzkennzeichen bei Verlust/Diebstahl', kLraKfz),
  LandratsamtAntrag('Technische Änderung — Eintragung', kLraKfz, recht: '§ 19 StVZO'),
  LandratsamtAntrag('Import- oder Ausfuhrfahrzeug — Zulassung', kLraKfz, recht: '§ 19 FZV'),
  LandratsamtAntrag('Kfz-Steuerbefreiung bei Schwerbehinderung', kLraKfz,
      recht: '§ 3a KraftStG',
      hinweis: 'Festgesetzt wird die Kfz-Steuer vom Hauptzollamt; die Zulassungsstelle nimmt den Antrag entgegen. Voraussetzung sind Merkzeichen H, Bl oder aG.'),

  // ══ Verkehr & Straßen ══════════════════════════════════════════════════
  LandratsamtAntrag('Ausnahmegenehmigung Großraum- oder Schwertransport', kLraVerkehr, recht: '§ 29 StVO'),
  LandratsamtAntrag('Ausnahme vom Sonntagsfahrverbot', kLraVerkehr, recht: '§ 30 StVO'),
  LandratsamtAntrag('Erlaubnis für Veranstaltung auf öffentlicher Straße', kLraVerkehr, recht: '§ 29 Abs. 2 StVO'),
  LandratsamtAntrag('Verkehrsrechtliche Anordnung / Beschränkung', kLraVerkehr, recht: '§ 45 StVO'),
  LandratsamtAntrag('Gewerblicher Güterkraftverkehr — Erlaubnis', kLraVerkehr, recht: '§ 3 GüKG'),
  LandratsamtAntrag('Personenbeförderung — Genehmigung', kLraVerkehr, recht: 'PBefG'),
  LandratsamtAntrag('Parkausweis für Handwerker oder soziale Dienste', kLraVerkehr, recht: '§ 46 StVO'),
  LandratsamtAntrag('Gefahrgutbeförderung — Ausnahmegenehmigung', kLraVerkehr, recht: 'GGVSEB'),

  // ══ Bauaufsicht & Wohnen ═══════════════════════════════════════════════
  // Untere Bauaufsichtsbehörde: Art. 53 BayBO, § 46 LBO BW.
  LandratsamtAntrag('Baugenehmigung — Antrag', kLraBau, recht: 'Art. 68 BayBO / § 58 LBO BW', hinweis: 'Eigener Reiter „Bau & Wohnen".'),
  LandratsamtAntrag('Bauvorbescheid — Antrag', kLraBau, recht: 'Art. 71 BayBO'),
  LandratsamtAntrag('Verlängerung einer Baugenehmigung oder eines Vorbescheids', kLraBau),
  LandratsamtAntrag('Isolierte Befreiung vom Bebauungsplan', kLraBau, recht: '§ 31 BauGB'),
  LandratsamtAntrag('Isolierte Abweichung vom Bauordnungsrecht', kLraBau, recht: 'Art. 63 BayBO'),
  LandratsamtAntrag('Genehmigungsfreistellung — Anzeige', kLraBau, recht: 'Art. 58 BayBO'),
  LandratsamtAntrag('Beseitigung einer baulichen Anlage — Anzeige', kLraBau),
  LandratsamtAntrag('Abgeschlossenheitsbescheinigung', kLraBau, recht: '§ 7 WEG'),
  LandratsamtAntrag('Wohnraumförderung — Antrag', kLraBau),
  LandratsamtAntrag('Bodenrichtwert- oder Verkehrswertauskunft', kLraBau, recht: '§§ 192 ff. BauGB'),
  LandratsamtAntrag('Verkehrswertgutachten (Gutachterausschuss)', kLraBau, recht: '§ 193 BauGB'),
  LandratsamtAntrag('Bauaufsichtliche Beschwerde / Anordnung', kLraBau, recht: 'Art. 54 BayBO'),

  // ══ Umwelt, Natur & Wasser ═════════════════════════════════════════════
  // Untere Naturschutzbehörde (Art. 43 BayNatSchG), untere Wasserrechts- und
  // Immissionsschutzbehörde am Landratsamt.
  LandratsamtAntrag('Wasserrechtliche Erlaubnis — Gewässerbenutzung', kLraUmwelt, recht: '§ 8 WHG'),
  LandratsamtAntrag('Brunnenbau / Grundwasserentnahme — Anzeige oder Erlaubnis', kLraUmwelt, recht: '§ 46 WHG'),
  LandratsamtAntrag('Kleinkläranlage — Mitteilung des Prüfergebnisses', kLraUmwelt),
  LandratsamtAntrag('Niederschlagswasser — Einleitungserlaubnis', kLraUmwelt, recht: '§ 8 WHG'),
  LandratsamtAntrag('Heizöltank / wassergefährdende Stoffe — Anzeige', kLraUmwelt, recht: 'AwSV'),
  LandratsamtAntrag('Grundwasser-Wärmepumpe — Erlaubnis', kLraUmwelt, recht: '§ 8 WHG'),
  LandratsamtAntrag('Bauen im Überschwemmungsgebiet — Genehmigung', kLraUmwelt, recht: '§ 78 WHG'),
  LandratsamtAntrag('Immissionsschutz — Genehmigung einer Anlage', kLraUmwelt, recht: '§ 4 BImSchG'),
  LandratsamtAntrag('Lärm-, Geruchs- oder Rauchbeschwerde', kLraUmwelt, recht: '§ 24 BImSchG'),
  LandratsamtAntrag('Baumfällung / Eingriff in Natur und Landschaft', kLraUmwelt, recht: '§ 14 BNatSchG'),
  LandratsamtAntrag('Artenschutzrechtliche Ausnahme / Vermarktung', kLraUmwelt, recht: '§ 45 BNatSchG'),
  LandratsamtAntrag('Rodung oder Aufforstung — Erlaubnis', kLraUmwelt, recht: 'BayWaldG / LWaldG BW'),
  LandratsamtAntrag('Abgrabung (Kies, Sand, Lehm) — Genehmigung', kLraUmwelt, recht: 'BayAbgrG'),
  LandratsamtAntrag('Altlastenkataster — Auskunft', kLraUmwelt, recht: 'BBodSchG'),
  LandratsamtAntrag('Vertragsnaturschutz / Klimaschutz — Zuwendung', kLraUmwelt),

  // ══ Abfall & Entsorgung ════════════════════════════════════════════════
  LandratsamtAntrag('Mülltonne — Anmeldung, Änderung oder Abmeldung', kLraAbfall, recht: 'KrWG'),
  LandratsamtAntrag('Sperrmüll — Abholung', kLraAbfall),
  LandratsamtAntrag('Abfallerzeugernummer — Beantragung', kLraAbfall, recht: 'NachwV'),
  LandratsamtAntrag('Abfalltransport — Anzeige oder Erlaubnis', kLraAbfall, recht: '§§ 53, 54 KrWG'),
  LandratsamtAntrag('Illegale Abfallablagerung — Anzeige', kLraAbfall, recht: '§ 62 KrWG'),
  LandratsamtAntrag('Gebührenbescheid Abfall — Widerspruch', kLraAbfall),

  // ══ Waffen, Jagd & Fischerei ═══════════════════════════════════════════
  LandratsamtAntrag('Kleiner Waffenschein — Antrag', kLraWaffen, recht: '§ 10 Abs. 4 WaffG'),
  LandratsamtAntrag('Waffenbesitzkarte / Erwerb einer Schusswaffe', kLraWaffen, recht: '§ 10 WaffG'),
  LandratsamtAntrag('Europäischer Feuerwaffenpass', kLraWaffen, recht: '§ 32 WaffG'),
  LandratsamtAntrag('Sprengstoffrechtliche Erlaubnis', kLraWaffen, recht: 'SprengG'),
  LandratsamtAntrag('Jagdschein — Erteilung oder Verlängerung', kLraWaffen, recht: '§ 15 BJagdG'),
  LandratsamtAntrag('Fischereischein — Erteilung oder Verlängerung', kLraWaffen, recht: 'BayFiG / FischG BW'),
  LandratsamtAntrag('Fischerprüfung — Anmeldung', kLraWaffen),

  // ══ Gewerbe & Gaststätten ══════════════════════════════════════════════
  LandratsamtAntrag('Gaststättenerlaubnis — Antrag', kLraGewerbe, recht: '§ 2 GastG'),
  LandratsamtAntrag('Reisegewerbekarte — Antrag', kLraGewerbe, recht: '§ 55 GewO'),
  LandratsamtAntrag('Bewachungsgewerbe — Erlaubnis', kLraGewerbe, recht: '§ 34a GewO'),
  LandratsamtAntrag('Makler-, Bauträger- oder Verwaltererlaubnis', kLraGewerbe, recht: '§ 34c GewO'),
  LandratsamtAntrag('Spielhalle — Erlaubnis', kLraGewerbe, recht: '§ 33i GewO'),
  LandratsamtAntrag('Versteigerergewerbe — Erlaubnis', kLraGewerbe, recht: '§ 34b GewO'),
  LandratsamtAntrag('Gewerbezentralregisterauszug — Antrag', kLraGewerbe, recht: '§ 150 GewO'),
  LandratsamtAntrag('Ausnahme von den Ladenöffnungszeiten', kLraGewerbe, recht: 'LadSchlG / BayLadSchlG'),

  // ══ Denkmalschutz ══════════════════════════════════════════════════════
  LandratsamtAntrag('Denkmalrechtliche Erlaubnis — Antrag', kLraDenkmal, recht: 'Art. 6 BayDSchG / § 8 DSchG BW'),
  LandratsamtAntrag('Denkmalliste — Auskunft, Eintragung oder Streichung', kLraDenkmal),
  LandratsamtAntrag('Steuerbescheinigung für Denkmalaufwendungen', kLraDenkmal, recht: '§§ 7i, 10f EStG'),
  LandratsamtAntrag('Denkmalfördermittel — Zuschussantrag', kLraDenkmal),

  // ══ Ordnung, Urkunden & Register ═══════════════════════════════════════
  LandratsamtAntrag('Öffentlich-rechtliche Namensänderung', kLraOrdnung,
      recht: '§§ 3, 11 NamÄndG',
      hinweis: 'Nur bei wichtigem Grund. Namensänderungen aus Ehe oder Abstammung laufen dagegen über das Standesamt.'),
  LandratsamtAntrag('Apostille oder Vorbeglaubigung für das Ausland', kLraOrdnung, recht: 'Haager Übereinkommen 1961'),
  LandratsamtAntrag('Beglaubigung von Unterschrift oder Abschrift', kLraOrdnung, recht: 'Art. 34 BayVwVfG / § 33 VwVfG'),
  LandratsamtAntrag('Führungszeugnis — Antrag', kLraOrdnung,
      recht: '§ 30 BZRG',
      hinweis: 'Wird bei der Meldebehörde der Wohnsitzgemeinde beantragt, nicht beim Landratsamt.'),
  LandratsamtAntrag('Versammlung — Anzeige', kLraOrdnung, recht: 'BayVersG / VersammlG'),
  LandratsamtAntrag('Ausländerverein — Anmeldung', kLraOrdnung, recht: '§ 14 VereinsG'),
  LandratsamtAntrag('Widerspruch gegen einen Bescheid des Landratsamts', kLraOrdnung,
      recht: '§ 70 VwGO',
      hinweis: 'Frist ein Monat ab Bekanntgabe. In Bayern ist der Widerspruch in vielen Rechtsgebieten abgeschafft — dann geht es direkt zur Klage beim Verwaltungsgericht. Die Rechtsbehelfsbelehrung des Bescheids ist maßgeblich.'),
  LandratsamtAntrag('Akteneinsicht — Antrag', kLraOrdnung, recht: '§ 29 VwVfG, Art. 15 DSGVO'),
  LandratsamtAntrag('Kommunalaufsichtliche Beschwerde über eine Gemeinde', kLraOrdnung, recht: 'Art. 110 GO (BY) / § 118 GemO (BW)'),

  // ══ Veterinär- & Lebensmittelrecht ═════════════════════════════════════
  LandratsamtAntrag('Tierschutz — Anzeige tierschutzwidriger Haltung', kLraVeterinaer, recht: '§ 16a TierSchG'),
  LandratsamtAntrag('Tierschutzrechtliche Erlaubnis — Antrag', kLraVeterinaer, recht: '§ 11 TierSchG'),
  LandratsamtAntrag('Heimtierausweis / Reisen mit Haustieren', kLraVeterinaer),
  LandratsamtAntrag('Lebensmittelbetrieb — Anzeige oder Kontrolle', kLraVeterinaer, recht: 'LFGB'),
  LandratsamtAntrag('Verbraucherbeschwerde über ein Lebensmittel', kLraVeterinaer, recht: 'LFGB'),

  // ══ Sonstiges ══════════════════════════════════════════════════════════
  LandratsamtAntrag('Sonstiges', kLraSonstiges),
];

/// Alle Titel — das ist die Liste, gegen die der Dialog einen gespeicherten
/// Wert prüft.
List<String> landratsamtAntragTitel() =>
    kLandratsamtAntraege.map((a) => a.titel).toList(growable: false);

/// Einträge einer Gruppe, in Katalogreihenfolge.
List<LandratsamtAntrag> landratsamtAntraegeDerGruppe(String gruppe) =>
    kLandratsamtAntraege.where((a) => a.gruppe == gruppe).toList(growable: false);

/// Sucht über Titel, Gruppe und Rechtsgrundlage.
///
/// ⚠️ Die Rechtsgrundlage gehört bewusst in die Suche: wer einen Bescheid vor
/// sich hat, liest dort „§ 35a SGB VIII" und nicht die Überschrift, unter der
/// wir den Vorgang einsortiert haben.
List<LandratsamtAntrag> landratsamtAntraegeSuchen(String frage) {
  final q = frage.trim().toLowerCase();
  if (q.isEmpty) return kLandratsamtAntraege;
  return kLandratsamtAntraege.where((a) {
    return a.titel.toLowerCase().contains(q) ||
        a.gruppe.toLowerCase().contains(q) ||
        (a.recht?.toLowerCase().contains(q) ?? false);
  }).toList(growable: false);
}

/// Findet den Katalogeintrag zu einem gespeicherten Wert, oder `null`, wenn der
/// Wert aus einer älteren Fassung stammt und nicht mehr im Katalog steht.
LandratsamtAntrag? landratsamtAntragFinden(String? titel) {
  if (titel == null || titel.isEmpty) return null;
  for (final a in kLandratsamtAntraege) {
    if (a.titel == titel) return a;
  }
  return null;
}
